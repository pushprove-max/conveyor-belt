#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 300
# Engine cases: the review loop, landing and follow-ups.
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"
# The engine folder, as lib.sh sets it: named here too, so the release closure (tools/closure.sh) follows this file's paths.
SRC=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)

# Bugs: a GO card that never reaches main or lands with no record line; cached tokens counted as fresh; a huge issue
# body cut from the brief; the brief carrying another area's rulings or none.
t_land() {
  setup "$(issue 7 2026-01-01 bug area:billing P2 | jq -c '[. + {body: ("x" * 300000 + "END")}]')"
  echo "$GO" > "$STUB/review.1"; provenbug # a bug card
  loop run >/dev/null || fail "run exited non-zero"
  # Bug: a session in any other mode cannot write under .claude/, so a tooling card left no change.
  grep -q -- "--permission-mode bypassPermissions" "$STUB/sessions" || fail "the build session was not started in bypass mode"
  [ "$(st 'select(.step == "landed") | .sha')" = "$(git -C "$R" rev-parse HEAD)" ] || fail "landed sha is not main's head"
  [ "$(git -C "$T/$CASE/origin" rev-parse refs/heads/main)" = "$(git -C "$R" rev-parse HEAD)" ] && [ -z "$(st 'select(.step == "push")')" ] \
    || fail "run did not push the landing to origin"
  git -C "$R" log -1 --format=%B | grep -q 'fix(billing): title 7 (#7)' || fail "commit subject: $(git -C "$R" log -1 --format=%s)"
  grep -qx two "$R/a.txt" && [ -z "$(git -C "$R" status --porcelain)" ] || fail "main lacks the change or is left dirty"
  [ "$(st 'select(.step == "build") | .tokens.claude')" = 35 ] && [ "$(st 'select(.step == "review") | .tokens.codex')" = 47 ] || fail "fresh tokens wrong"
  # Bugs: the dashboard's row has no issue title, or no token split to price a step with.
  [ "$(st 'select(.step == "picked") | .title')" = "title 7" ] || fail "the picked line lacks the issue title"
  [ "$(st 'select(.usage) | .usage | map(tostring) | join(" ")' | tr '\n' ,)" = "10 20 0 999 5,40 60 7,0 0 0 0 0," ] || fail "token split: $(st '.usage | tojson')"
  [ "$(wc -l < "$STUB/reviews")" = 1 ] && [ -z "$(ls "$T/$CASE/cards")" ] || fail "more than one review, or the worktree is left"
  [ "$(wc -c < "$STUB/brief")" -gt 300000 ] && grep -q 'END$' "$STUB/brief" || fail "issue body cut from the brief"
  grep -q '"r-1"' "$STUB/brief" && ! grep -q '"r-2"' "$STUB/brief" || fail "brief rulings are not the billing ones"
}

# Bugs: a merge after NO-GO; a card given up before its review cap instead of going round fix and review until
# GO; a finding outside the issue dropped from the record.
t_nogo() {
  setup "[$(issue 7 2026-01-01 area:billing)]"; echo "$NOGO" > "$STUB/review.1"; moved 2 "$NOGO" > "$STUB/review.2"; echo "$GO" > "$STUB/review.3"
  { printf 'a%.0s' {1..1500}; echo; cat "$STUB/review.1"; } > "$STUB/review.0"; mv "$STUB/review.0" "$STUB/review.1"
  loop run >/dev/null || fail "run exited non-zero"
  # A NO-GO keeps its findings whole in its line's tail (the Board's output of that step): a long line before them in
  # the review does not cut them off, as the reason's length cap would.
  [ "$(st 'select(.step == "review" and .result == "NO-GO") | .tail | split("\n") | [(.[0] | length), (any(. == "[P1] a.txt:1 wrong word"))] | tojson' | head -1)" = '[1500,true]' ] \
    || fail "a NO-GO review's line does not keep its findings whole: $(st 'select(.step == "review") | .tail' | head -c 300)"
  # Its counts are taken from the whole review (card.sh), so the P1 finding past the reason's cut is counted: the
  # line of 1500 a's, which has no mark, is one P1 and that finding the other (the reason alone gives 1).
  [ "$(st 'select(.step == "review") | .counts.P1' | head -n 1)" = 2 ] || fail "the P1 finding past the reason's cut is not counted: $(st 'select(.step == "review") | .counts | tojson' | head -n 1)"
  [ "$(wc -l < "$STUB/reviews")" = 3 ] && [ "$(wc -l < "$STUB/sessions")" = 3 ] || fail "not a fix session and a new review after each NO-GO"
  # #307: each review's line keeps the line its finding cites as that review read it, so the Board shows it after the
  # worktree is gone (the case's last check): the first review read a.txt's first line, "one".
  [ "$(st 'select(.step == "review") | .excerpts // [] | map([.at, .side, .lines]) | tojson' | head -n 1)" = '[["a.txt:1","new",["one"]]]' ] \
    || fail "a review's line does not keep the line its finding cites: $(st 'select(.step == "review") | .excerpts | tojson')"
  # Bug: a build or fix session loaded the account's connectors (their instructions and tools), which no card uses.
  [ "$(grep -c -- ' --strict-mcp-config ' "$STUB/sessions")" = 3 ] || fail "a build or fix session started without --strict-mcp-config: $(cat "$STUB/sessions")"
  [ "$(st 'select(.step == "review") | .result' | tr '\n' ' ')" = "NO-GO NO-GO GO " ] || fail "review results: $(st 'select(.step == "review") | .result' | tr '\n' ' ')"
  st 'select(.step == "review") | .reason' | grep -q 'NEW CARD: b.txt is stale' || fail "out-of-scope finding not recorded"
  [ "$(st 'select(.step == "landed") | .sha')" = "$(git -C "$R" rev-parse HEAD)" ] && [ -z "$(ls "$T/$CASE/cards")" ] || fail "not landed after the GO, or the worktree is left"
  [ ! -e "$STUB/filed" ] && [ "$(st 'select(.step == "landed") | has("leftover") or has("followups")')" = false ] || fail "a card that landed on a GO filed follow-ups or is recorded as leftover"
}

# Bugs: an UNPROVEN line holds a GO, is counted as a finding, or is dropped from the review's record; the reviewer is
# not asked for a proof or the three angles.
t_unproven() {
  setup "[$(issue 8 2026-01-01)]"
  printf '%s\n' 'UNPROVEN: b.txt may be read before it is written' 'USER-VISIBLE: no' 'VERDICT: GO' > "$STUB/r.review"
  # The verdict, the counts and the finding lines the loop reads of the review; the lines its record keeps (UNRECORDED,
  # as the review's reason); the review prompt as names() puts it together.
  fx_in 'verdict "$STUB/r.review"; counts "$STUB/r.review"; echo "[$(leftovers "$STUB/r.review")]"; grep -Ev "$UNRECORDED" "$STUB/r.review"; echo ---
    printf "%s\n" "$REVIEW" > "$STUB/asked"'
  [ "$RC" = 0 ] && [ "$(sed -n 1,3p "$T/$CASE/run.out" | tr '\n' ' ')" = 'GO {"P0":0,"P1":0,"P2":0,"P3":0} [] ' ] \
    || fail "a review whose only other line is UNPROVEN is not a GO with no finding counted: $(cat "$T/$CASE/run.out")"
  [ "$(sed -n '4,/^---$/p' "$T/$CASE/run.out" | head -n 1)" = 'UNPROVEN: b.txt may be read before it is written' ] || fail "the UNPROVEN line is not in the review's record"
  grep -q 'Proof: <proof>' "$STUB/asked" && grep -q 'A problem you cannot prove that way is one line `UNPROVEN: what`' "$STUB/asked" \
    && grep -q 'look for the same mistake elsewhere in the staged change' "$STUB/asked" && grep -q '^- bypass and trust:' "$STUB/asked" \
    && grep -q '^- behaviour:' "$STUB/asked" && grep -q '^- tests and words:' "$STUB/asked" && grep -q 'is a P1 finding' "$STUB/asked" \
    && grep -q 'a smaller change that fully solves the issue is a finding' "$STUB/asked" || fail "the reviewer is not asked for proofs, the same mistake elsewhere, the angles or the checks"
}

# Bugs: an UNPROVEN line is counted as a finding, or filed as a follow-up after a last NO-GO; a proven finding beside a
# GO lets the card land; the fix session is not given the proven finding, or not told to fix the same mistake elsewhere
# in the change.
t_proven() {
  # A proven finding beside a GO is a NO-GO, with one P1 counted; the follow-ups of a last NO-GO are the proven
  # finding alone.
  setup "[$(issue 7 2026-01-02)]"
  F='[P1] a.txt:1 wrong word. Proof: a.txt line 2 reads "two"'
  printf '%s\n' "$F" 'UNPROVEN: b.txt may be stale' 'USER-VISIBLE: no' 'VERDICT: GO' > "$STUB/r.review"
  fx_in 'verdict "$STUB/r.review"; counts "$STUB/r.review" | jq .P1; followups c1-7 "$(jq -c ".[0]" "$STUB/issues.json")" "$STUB/r.review"'
  [ "$RC" = 0 ] && [ "$(tr '\n' ' ' < "$T/$CASE/run.out")" = 'NO-GO 1 [100101] ' ] \
    || fail "a proven finding beside a GO did not make it a NO-GO, or the UNPROVEN line was counted or filed: $(cat "$T/$CASE/run.out")"
  [ "$(jq -r .title "$STUB/filed")" = "$F" ] || fail "follow-ups filed after the last NO-GO are not the proven finding alone: $(cat "$STUB/filed")"
  # The fix session is given the proven finding, with its id, under the same-mistake instruction. A loop run
  # (that review, then a GO): the fix brief is put together inline in card() (card.sh) and given to session(), which
  # no engine function returns alone.
  cp "$STUB/r.review" "$STUB/review.1"; echo "$GO" > "$STUB/review.2"; rm -f "$STUB/filed"
  loop run --only 7 >/dev/null || fail "run of #7 exited non-zero"
  [ "$(wc -l < "$STUB/sessions")" = 2 ] || fail "not one build and one fix session: $(cat "$STUB/sessions")"
  grep -qx '# Reviewer findings: fix these findings, and every other place in this change that makes the same mistake; nothing else' "$STUB/brief" \
    && grep -qxF "E1 $F" "$STUB/brief" \
    || fail "the fix session's brief lacks the same-mistake instruction or the proven finding: $(grep -n -e '^# Reviewer findings' -e 'wrong word' "$STUB/brief")"
}

# Bugs: a leftover finding is not filed, or filed with the wrong mark, depth, labels or milestone; a NEW CARD line is
# filed as one; a depth-1 follow-up (under the cap, MAX_DEPTH, 2) has its findings declined instead of filed at
# depth 2, so a true finding of a follow-up's card is lost.
t_leftover() {
  setup "[$(issue 7 2026-01-01 area:billing P3 | jq -c '.milestone = {title: "M1"}')]"
  echo "$NOGO3" > "$STUB/r.review"
  # The last NO-GO's findings of #7, and then those of the card of its first follow-up (#100101, its review the same),
  # each filed as the card files them; the depth the card reads of each issue first (fudepth()), to file or decline.
  fx_in 'i=$(jq -c ".[0]" "$STUB/issues.json"); fudepth "$i"; followups c1-7 "$i" "$STUB/r.review"
    i=$(jq -c "select(.number == 100101)" "$STUB/filed"); fudepth "$i"; echo "$MAX_DEPTH"; followups c2-100101 "$i" "$STUB/r.review"'
  [ "$RC" = 0 ] && [ "$(tr '\n' ' ' < "$T/$CASE/run.out")" = '0 [100101,100102,100103] 1 2 [100104,100105,100106] ' ] \
    || fail "the follow-ups of #7, or those of its depth-1 follow-up under the cap of 2, were not filed: $(cat "$T/$CASE/run.out")"
  [ "$(jq -rs '.[:3][] | [.title, (.labels | map(.name) | join(" ")), .milestone.title] | join(" | ")' "$STUB/filed")" = '[P0] a.txt:1 wrong word | conveyor-followup bug P0 area:billing | M1
b.txt:22 no mark here | conveyor-followup bug P1 area:billing | M1
[P2] c.txt:3 a nit | conveyor-followup bug P2 area:billing | M1' ] || fail "follow-ups filed: $(cat "$STUB/filed")"
  [ "$(jq -rs --arg c c1-7 '.[:3] | map(select((.body | contains("#7")) and (.body | contains($c)) and (.body | test("(^|\n)Follow-up depth: 1(\n|$)")))) | length' "$STUB/filed")" = 3 ] \
    && jq -rs '.[1].body' "$STUB/filed" | grep -q 'b.txt:22' || fail "a follow-up's body lacks the parent, the card, the file:line or the depth line: $(cat "$STUB/filed")"
  [ "$(jq -rs --arg c c2-100101 '.[3:] | map(select((.body | contains("Follow-up to #100101 (Conveyor card \($c))")) and (.body | test("(^|\n)Follow-up depth: 2$")))) | length' "$STUB/filed")" = 3 ] \
    || fail "a depth-1 follow-up's follow-ups do not name their parent, or do not carry depth 2: $(tail -n 3 "$STUB/filed")"
  [ ! -e "$ST/declined.jsonl" ] || fail "a follow-up's card declined a finding: $(cat "$ST/declined.jsonl")"
}
# Bugs: with one card in flight and nothing else to pick, the run stops picking, and the follow-ups that
# card files wait for another run; a follow-up is picked before its parent has landed (here #8's card ends while
# #7's second follow-up is still being filed, so the loop picks again with #100101 open and #7 not landed).
t_chain() {
  setup "$(jq -cs . <(issue 7 2026-01-01 P1) <(issue 8 2026-01-02 P2))"; : > "$STUB/list-filed"
  # The filing of the second follow-up goes on until #8's card has ended and the loop has taken a whole turn after it
  # (two of its waits begun, lib.sh), the turn in which it would pick #100101.
  # #7's review is the same P2 and P3 each time: back after its one fix round, it is the last review (card.sh), filed
  # as a third NO-GO is, in two reviews. The follow-ups need only be picked: their builds change nothing, so each ends
  # after its build (blocked: no change to review), with no review, tests or landing.
  tune '.tunables.poll = 1'; watchturns
  cat > "$STUB/create-cmd" <<'EOF'
[ "$n" != 100102 ] || { while [ -d "$STUB" ]; do jq -e 'select(.issue == 8 and .step == "blocked")' "$ST/cards.jsonl" >/dev/null 2>&1 && break; sleep 0.1; done
  k=$(wc -l < "$TURNS"); while [ -d "$STUB" ] && [ "$(wc -l < "$TURNS")" -lt $((k + 2)) ]; do sleep 0.1; done; }
EOF
  cat > "$STUB/claude" <<'EOF'
#!/usr/bin/env bash
case $(cat) in *'# Issue #8:'*) while [ -d "$STUB" ]; do [ -e "$STUB/filed" ] && break; sleep 0.1; done; exit 1 ;; *'# Issue #7:'*) . "$STUB/build" ;; esac
echo '{"type":"result","is_error":false,"usage":{"input_tokens":10,"cache_creation_input_tokens":20,"cache_read_input_tokens":999,"output_tokens":5}}'
EOF
  printf '[P2] a.txt:1 a nit\n[P3] c.txt:3 a style nit\nUSER-VISIBLE: no\nVERDICT: NO-GO\n' > "$STUB/codex-answer" # every review's answer
  loop run >/dev/null || fail "run exited non-zero"
  steps=$(st 'select(.step | IN("picked", "landed", "blocked")) | "\(.issue) \(.step)"')
  at() { grep -nx "$1" <<<"$steps" | cut -d: -f1; }
  [ "$(st 'select(.step == "landed") | [.issue, .followups] | tojson' | tr '\n' ' ')" = '[7,[100101,100102]] ' ] \
    && [ "$(st 'select(.step == "picked" and .issue > 100000) | .issue' | sort | tr '\n' ' ')" = '100101 100102 ' ] \
    || fail "the follow-ups were not picked in the run that filed them: $(tr '\n' ',' <<<"$steps")"
  [ "$(at '8 blocked')" -lt "$(at '7 landed')" ] || fail "the test made no pick while #7's follow-ups were being filed: $(tr '\n' ',' <<<"$steps")"
  [ "$(at '7 landed')" -lt "$(at '100101 picked')" ] || fail "follow-up #100101 was picked before its parent landed: $(tr '\n' ',' <<<"$steps")"
}

# Bugs: a filing fails and the card lands anyway, or the follow-ups already filed stay open to be built
# against a main that never got the change; a card blocked after a review does not post that review's findings.
# Bug: a blocked card's session output, error output and last review were deleted with its worktree.
t_filefail() {
  setup "[$(issue 7 2026-01-01)]"; for i in 1 2; do moved $i "$NOGO3" > "$STUB/review.$i"; done; echo "$NOGO3" > "$STUB/review.3"; head=$(git -C "$R" rev-parse HEAD)
  echo '[ "$n" != 100102 ] || { echo "could not add label" >&2; exit 1; }' > "$STUB/create-cmd"
  loop run >/dev/null || fail "run exited non-zero"
  st 'select(.step == "blocked") | .reason' | grep -q 'follow-up not filed.*b.txt:22.*could not add label' || fail "failed filing did not block with its reason: $(st 'select(.step == "blocked") | .reason')"
  [ "$(git -C "$R" rev-parse HEAD)" = "$head" ] && [ -z "$(st 'select(.step == "landed")')" ] && [ -z "$(ls "$T/$CASE/cards")" ] || fail "landed after a failed filing, or the worktree is left"
  [ "$(cat "$STUB/closed")" = 100101 ] || fail "the follow-up already filed was not withdrawn: $(cat "$STUB/closed" 2>&1)"
  grep -q '^7 --body .*blocked' "$STUB/comments" && grep -q 'no mark here' "$STUB/comments" || fail "the review's findings were not posted on the issue: $(cat "$STUB/comments" 2>&1)"
  # The kept folder is under the state folder, and the blocked line names it relative to that folder.
  k=$(st 'select(.step == "blocked") | "\(.kept) \(.card)"'); [ "${k% *}" = "kept/${k#* }" ] && [ -d "$ST/${k% *}" ] || fail "blocked line names no kept folder under the state folder: $k"
  k=$ST/${k% *}
  # rerun: what its tests passed, for a retried card to keep (issue 460).
  [ "$(ls "$k" | sed 's/.*\.//' | sort | tr '\n' ' ')" = "base err out patch rerun review rounds test testlog withdrawn " ] && grep -q 'wrong word' "$k"/*.review || fail "evidence not kept: $(ls "$k")"
  # Bugs: the blocked card's change went with its worktree; the withdrawn follow-up closed as completed, its finding kept nowhere.
  grep -qx '+two' "$k"/*.patch && [ "$(cat "$k"/*.base)" = "$head" ] || fail "the blocked card's change was not kept as a patch with the commit it was built on: $(ls "$k")"
  [ "$(cat "$k"/*.withdrawn)" = '#100101 [P0] a.txt:1 wrong word' ] && grep -q -- '--reason not planned --comment .*#7 ' "$STUB/close-comments" \
    || fail "the withdrawn follow-up was not closed as not planned naming #7, or its finding was not kept: $(cat "$STUB/close-comments" "$k"/*.withdrawn 2>&1)"
}

# A home path, put together here so this file holds none itself (the privacy check runs over it).
HX=/hom"e"/x
# A private key header, put together the same way: a hit of several words, which no one word of it makes.
KX="-----BEGIN PRIVATE"" KEY-----"
# Bug: with the pack's privacy.mode public, a last finding that quotes a home path (here also as an escaped string)
# could not be filed, as the privacy check refused its text, so the whole card was blocked; one that quotes a private
# key header still was, as each of its words passes the check alone.
t_privmask() {
  setup "[$(issue 7 2026-01-01)]"; tune '.privacy.mode = "public"'
  printf '%s\n' "[P2] b.txt:3 reads $HX/notes, and ${HX//\//\\/} and $KX too" 'USER-VISIBLE: no' 'VERDICT: NO-GO' > "$STUB/r.review"
  fx_in 'followups c1-7 "$(jq -c ".[0]" "$STUB/issues.json")" "$STUB/r.review"'
  [ "$RC" = 0 ] && [ "$(cat "$T/$CASE/run.out")" = '[100101]' ] || fail "the follow-up was not filed: $(cat "$T/$CASE/run.out")"
  [ "$(jq -r .title "$STUB/filed")" = '[P2] b.txt:3 reads <home path> and <home path> and <token> too' ] && jq -r .body "$STUB/filed" | grep -q 'Conveyor masked the parts' \
    && ! grep -qF -e "${HX#/}" -e "${KX#-----}" "$STUB/filed" || fail "the follow-up's text is not masked, or does not say so: $(cat "$STUB/filed")"
}

# Bug: a last finding that is a privacy hit in the card's own change (a line the card added holds a home path) was
# filed as a follow-up, which would land the hit on main, instead of going to a fix round.
# privown() is what sends the card to that fix round (card.sh); a hit the change does not add (here one on another
# path) is no hit of the card's own, and goes to a follow-up as before.
t_privfix() {
  setup "[$(issue 7 2026-01-01)]"
  fx_wt "printf 'two\ncd %s/bench\n' '$HX' >> a.txt" b.txt b
  printf '%s\n' "[P0] a.txt:3 flags $HX/bench" 'USER-VISIBLE: no' 'VERDICT: NO-GO' > "$FXWT.review"
  fx_in 'privown "$FXWT"; echo ---; printf "%s\n" "[P0] b.txt:3 flags $HX/other" "VERDICT: NO-GO" > "$FXWT.review"; privown "$FXWT"'
  [ "$RC" = 0 ] && [ "$(cat "$T/$CASE/run.out")" = "[P0] a.txt:3 flags $HX/bench
---" ] || fail "the privacy finding on the card's own line is not found as one, or one on a line the card did not add is: $(cat "$T/$CASE/run.out")"
}
# Bug: card() does not join privown() to the fix round: a last-review privacy hit on a line the card added is filed as
# a follow-up (landing the hit on main), or its fix round is not given, or the hit lands. A loop run: the choice of one
# more fix round is made inline in card() after its last review, which no engine function exposes alone. The build stub
# knows its fix session by the file its first session writes; it drops the line only when the fix brief names the hit.
t_privfixrun() {
  setup "[$(issue 7 2026-01-01)]"; export HX
  echo 'if [ -e "$STUB/built" ]; then echo fix >> a.txt; ! grep -qF "$HX/bench" "$STUB/brief" || { grep -vF "$HX/bench" a.txt > a.new; mv a.new a.txt; }
    else : > "$STUB/built"; printf "two\ncd %s/bench\n" "$HX" >> a.txt; fi' > "$STUB/build"
  for i in 1 2; do moved $i "$NOGO" > "$STUB/review.$i"; done; echo "$GO" > "$STUB/review.4"
  printf '%s\n' "[P0] a.txt:3 flags $HX/bench" 'USER-VISIBLE: no' 'VERDICT: NO-GO' > "$STUB/review.3"
  loop run >/dev/null || fail "run exited non-zero"
  [ "$(st 'select(.step == "review") | .result' | tr '\n' ' ')" = "NO-GO NO-GO NO-GO GO " ] && [ ! -e "$STUB/filed" ] \
    || fail "the privacy finding on the card's own line did not go to a fix round: $(st 'select(.step == "review") | .result' | tr '\n' ' ') $(cat "$STUB/filed" 2>&1)"
  [ -n "$(st 'select(.step == "landed") | .sha')" ] && ! grep -qF "$HX" "$R/a.txt" && grep -qx fix "$R/a.txt" \
    || fail "the card did not land the corrected change only: $(cat "$R/a.txt")"
}

# Bug: a follow-up chain goes past the cap: a card whose issue is a follow-up at the cap (MAX_DEPTH, 2) files another
# level on its last NO-GO, or its leftover finding is in no declined list, or its reason does not name the cap.
# Its last NO-GO is a P2 back after its one fix round (card.sh: the last review, as a third NO-GO is), in two reviews.
t_deep() {
  setup "[$(issue 7 2026-01-01 conveyor-followup bug P1 | jq -c '.body = "Follow-up to #5.\n\nFollow-up depth: 2"')]"
  # The second review names a.txt:12, where the fix's one appended line moves a.txt:11 (rounded()), so it is the same
  # finding back; its text differs from the first's, so the declined one is known to come from the last review.
  for i in 1 2; do printf '%s\n' "[P2] a.txt:1$i wrong word" 'USER-VISIBLE: no' 'VERDICT: NO-GO' > "$STUB/review.$i"; done; provenbug
  mkdir -p "$ST"; landed 5 '[7]' > "$ST/cards.jsonl"
  # A loop run: the choice to decline rather than file at the cap is made inline in card() (card.sh, after its last
  # review), which no engine function exposes alone; fudepth() and decline() are checked directly in the cases below.
  loop run >/dev/null || fail "run exited non-zero"
  [ "$(st 'select(.issue == 7 and .step == "landed") | [.leftover, .followups] | tojson')" = '[true,[]]' ] && [ ! -e "$STUB/filed" ] \
    || fail "a depth-2 card did not land, or filed a follow-up: $(st 'select(.issue == 7 and (.step | IN("landed", "blocked")))')"
  [ "$(jq -c '[.issue, .finding, .by, .why]' "$ST/declined.jsonl")" = '[7,"[P2] a.txt:12 wrong word","code","its issue is a follow-up at the depth cap of 2, so no deeper follow-up is filed"]' ] \
    || fail "the depth-2 card's leftover finding is not in the declined list once, with who and why: $(cat "$ST/declined.jsonl" 2>&1)"
}

# Bug: a follow-up is known only by its depth line, so one with the follow-up label and no such line (a slice of a
# split) counts as depth 0, and its follow-ups as depth 1, so the chain reaches the cap one level late.
t_fuknown() {
  setup "[$(issue 7 2026-01-01 conveyor-followup bug P1 | jq -c '.body = "Follow-up to #5"')]"; echo "$NOGO" > "$STUB/r.review"
  fx_in 'i=$(jq -c ".[0]" "$STUB/issues.json"); fudepth "$i"; followups c1-7 "$i" "$STUB/r.review"'
  [ "$RC" = 0 ] && [ "$(tr '\n' ' ' < "$T/$CASE/run.out")" = '1 [100101] ' ] || fail "a labelled issue with no depth line is not at depth 1: $(cat "$T/$CASE/run.out")"
  jq -r .body "$STUB/filed" | grep -qx 'Follow-up depth: 2' || fail "a follow-up of a labelled issue with no depth line is not at depth 2: $(cat "$STUB/filed")"
}
# Bug: a body past a pipe's 64 KiB (#8's, long lines: 6500 short ones took 100 s) hides its depth line (its read ends
# early), so a card at the cap files another level.
t_fuknownlong() {
  local i; i=$(issue 8 2026-01-02 bug P1 | jq -c '.body = "Follow-up depth: 2\n" + (("filler text " * 70 + "\n") * 100)')
  [ "$(jq -r .body <<<"$i" | wc -c)" -gt 65536 ] || fail "#8's body fits a pipe"
  setup "[$i]"
  fx_in 'fudepth "$(jq -c ".[0]" "$STUB/issues.json")"'
  [ "$RC" = 0 ] && [ "$(cat "$T/$CASE/run.out")" = 2 ] || fail "the depth line of a body past 64 KiB is not read: $(cat "$T/$CASE/run.out")"
}

# Bug: a declined list that cannot be written (here a folder is in its place) loses the findings: decline() says it
# wrote them, so the card ends as landed and clean, and its review goes with its worktree. On its failure (exit
# non-zero) the card ends blocked, its review kept (card.sh).
t_declinefail() {
  setup "[$(issue 7 2026-01-01)]"; mkdir -p "$ST/declined.jsonl"
  fx_in 'printf "%s\n" "[P1] a.txt:1 wrong word" | decline c1-7 7 "$FUCAP"'
  [ "$RC" != 0 ] && grep -q '^conveyor: card c1-7: its declined findings could not be written to ' "$T/$CASE/run.out" \
    || fail "a declined list that cannot be written did not fail decline() saying so: exit $RC, $(cat "$T/$CASE/run.out")"
}
# Bug: card() ignores decline()'s failure after the landing: the depth-capped card ends landed and clean, and its review
# goes with its worktree. A loop run: the landing, then decline(), then the block that keeps the review are joined
# inline in card(), which no engine function exposes alone.
t_declinefailrun() {
  # Its last NO-GO is a P2 back after its one fix round (the last review, as a third NO-GO is), in two reviews.
  setup "[$(issue 7 2026-01-01 conveyor-followup bug P1 | jq -c '.body = "Follow-up depth: 2"')]"; provenbug
  for i in 1 2; do printf '%s\n' '[P2] a.txt:1 wrong word' 'USER-VISIBLE: no' 'VERDICT: NO-GO' > "$STUB/review.$i"; done
  mkdir -p "$ST/declined.jsonl"
  loop run >/dev/null 2>&1 || fail "run exited non-zero"
  [ "$(st 'select(.step | IN("landed", "blocked")) | .step' | tr '\n' ' ')" = 'landed blocked ' ] \
    && st 'select(.step == "blocked") | .reason' | grep -q 'could not write its leftover findings to the declined list' || fail "a card whose findings could not be declined did not end landed, then blocked saying so: $(st 'select(.step | IN("landed", "blocked"))')"
  k=$ST/$(st 'select(.step == "blocked") | .kept'); grep -q 'wrong word' "$k"/*.review || fail "the review of the findings that could not be declined was not kept: $(ls "$k" 2>&1)"
}
