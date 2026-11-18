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
  [ "$(wc -l < "$STUB/reviews")" = 3 ] && [ "$(wc -l < "$STUB/sessions")" = 3 ] || fail "not a fix session and a new review after each NO-GO"
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
  sed -i 's|^cat > /dev/null; echo x|cat > "$STUB/asked"; echo x|' "$STUB/codex"
  printf '%s\n' 'UNPROVEN: b.txt may be read before it is written' 'USER-VISIBLE: no' 'VERDICT: GO' > "$STUB/review.1"
  loop run >/dev/null || fail "run of #8 exited non-zero"
  [ "$(st 'select(.issue == 8 and .step == "review") | [.result, .counts.P1] | tojson')" = '["GO",0]' ] \
    && [ -n "$(st 'select(.issue == 8 and .step == "landed") | .sha')" ] || fail "a review whose only other line is UNPROVEN did not land as a GO with no finding counted: $(st 'select(.issue == 8)')"
  st 'select(.issue == 8 and .step == "review") | .reason' | grep -qx 'UNPROVEN: b.txt may be read before it is written' || fail "the UNPROVEN line is not in the review's record"
  grep -q 'Proof: <proof>' "$STUB/asked" && grep -q 'A problem you cannot prove that way is one line `UNPROVEN: what`' "$STUB/asked" \
    && grep -q 'look for the same mistake elsewhere in the staged change' "$STUB/asked" && grep -q '^- bypass and trust:' "$STUB/asked" \
    && grep -q '^- behaviour:' "$STUB/asked" && grep -q '^- tests and words:' "$STUB/asked" && grep -q 'is a P1 finding' "$STUB/asked" \
    && grep -q 'a smaller change that fully solves the issue is a finding' "$STUB/asked" || fail "the reviewer is not asked for proofs, the same mistake elsewhere, the angles or the checks"
}

# Bugs: an UNPROVEN line is counted as a finding, or filed as a follow-up after a last NO-GO; a proven finding beside a
# GO lets the card land; the fix session is not told to fix the same mistake elsewhere in the change.
t_proven() {
  # #7: a proven finding beside a GO is a NO-GO; the third NO-GO lands and files only the proven finding.
  setup "[$(issue 7 2026-01-02)]"
  F='[P1] a.txt:1 wrong word. Proof: a.txt line 2 reads "two"'
  printf '%s\n' "$(moved 1 "$F")" 'UNPROVEN: b.txt may be stale' 'USER-VISIBLE: no' 'VERDICT: GO' > "$STUB/review.1"
  printf '%s\n' "$(moved 2 "$F")" 'UNPROVEN: b.txt may be stale' 'USER-VISIBLE: no' 'VERDICT: NO-GO' > "$STUB/review.2"
  printf '%s\n' "$F" 'UNPROVEN: b.txt may be stale' 'USER-VISIBLE: no' 'VERDICT: NO-GO' > "$STUB/review.3"
  loop run --only 7 >/dev/null || fail "run of #7 exited non-zero"
  [ "$(st 'select(.issue == 7 and .step == "review") | "\(.result) \(.counts.P1)"' | tr '\n' ,)" = 'NO-GO 1,NO-GO 1,NO-GO 1,' ] \
    || fail "a proven finding beside a GO did not make it a NO-GO, or the UNPROVEN line was counted: $(st 'select(.issue == 7 and .step == "review")')"
  [ "$(jq -r .title "$STUB/filed")" = "$F" ] && [ "$(st 'select(.issue == 7 and .step == "landed") | .followups | tojson')" = '[100101]' ] \
    || fail "follow-ups filed after the last NO-GO are not the proven finding alone: $(cat "$STUB/filed")"
  grep -q '^# Reviewer findings: fix these findings, and every other place in this change that makes the same mistake; nothing else$' "$STUB/brief" \
    && grep -qF "$(moved 2 "$F")" "$STUB/brief" || fail "the fix session's prompt lacks the same-mistake instruction or the finding: $(cat "$STUB/brief")"
}

# Bugs: a card goes round past 3 reviews, or is blocked on the third NO-GO instead of landing; a leftover
# finding is not filed, or filed with the wrong mark, depth, labels or milestone; a NEW CARD line is filed as one;
# the landed line does not name the follow-ups; a run limited to an issue leaves that issue's follow-up unbuilt;
# a follow-up's card files a follow-up of its own, or its leftover findings leave no trace in the declined list.
t_leftover() {
  setup "$(jq -cs . <(issue 7 2026-01-01 area:billing P3 | jq -c '.milestone = {title: "M1"}') <(issue 3 2025-01-01 P1))"
  for i in 1 2; do moved $i "$NOGO" > "$STUB/review.$i"; done; for i in 4 5; do moved $i "$NOGO3" > "$STUB/review.$i"; done
  echo "$NOGO3" | tee "$STUB/review.3" > "$STUB/review.6"; provenbug # the second run builds #7's follow-up, a bug card
  loop run --only 7 >/dev/null || fail "run exited non-zero"
  [ "$(wc -l < "$STUB/reviews")" = 3 ] && [ "$(wc -l < "$STUB/sessions")" = 3 ] || fail "$(wc -l < "$STUB/reviews") reviews and $(wc -l < "$STUB/sessions") sessions, not 3 and 3"
  [ "$(st 'select(.step == "landed") | [.sha, .leftover, .followups] | tojson')" = "[\"$(git -C "$R" rev-parse HEAD)\",true,[100101,100102,100103]]" ] \
    && [ -z "$(ls "$T/$CASE/cards")" ] || fail "third NO-GO did not land with its follow-ups named: $(st 'select(.step | IN("landed", "blocked"))')"
  [ "$(jq -r '[.title, (.labels | map(.name) | join(" ")), .milestone.title] | join(" | ")' "$STUB/filed")" = '[P0] a.txt:1 wrong word | conveyor-followup bug P0 area:billing | M1
b.txt:22 no mark here | conveyor-followup bug P1 area:billing | M1
[P2] c.txt:3 a nit | conveyor-followup bug P2 area:billing | M1' ] || fail "follow-ups filed: $(cat "$STUB/filed")"
  card=$(st 'select(.step == "landed") | .card')
  [ "$(jq -rs --arg c "$card" 'map(select((.body | contains("#7")) and (.body | contains($c)) and (.body | test("(^|\n)Follow-up depth: 1(\n|$)")))) | length' "$STUB/filed")" = 3 ] \
    && jq -rs '.[1].body' "$STUB/filed" | grep -q 'b.txt:22' || fail "a follow-up's body lacks the parent, the card, the file:line or the depth line: $(cat "$STUB/filed")"
  [ ! -e "$STUB/comments" ] && [ ! -e "$STUB/closed" ] || fail "a card that landed posted a blocked comment or withdrew a follow-up"
  # The run is limited to #7: it now builds #7's follow-up, and not #3. That card's issue is itself a follow-up, so
  # its third NO-GO lands and files nothing (follow-ups of follow-ups were half the engine's commits, built with no
  # one asked): each finding is in the declined list, declined by code, with the reason.
  [ ! -e "$ST/declined.jsonl" ] || fail "the card of #7, no follow-up, declined a finding: $(cat "$ST/declined.jsonl")"
  jq -cs --slurpfile old "$STUB/issues.json" '[.[0]] + ($old[0] | map(select(.number == 3)))' "$STUB/filed" > "$STUB/issues.new" && mv "$STUB/issues.new" "$STUB/issues.json"
  loop run --only 7 >/dev/null || fail "second run exited non-zero"
  [ "$(st 'select(.step == "picked") | .issue' | tr '\n' ' ')" = "7 100101 " ] || fail "picks of a run limited to #7: $(st 'select(.step == "picked") | .issue' | tr '\n' ' ')"
  [ "$(st 'select(.issue == 100101 and .step == "landed") | [.leftover, .followups] | tojson')" = '[true,[]]' ] && [ "$(wc -l < "$STUB/filed")" = 3 ] \
    && [ "$(st 'select(.issue == 100101 and .step == "filed") | .step')" = '' ] || fail "a follow-up's card filed a follow-up of its own, or did not land: $(st 'select(.issue == 100101 and (.step | IN("landed", "blocked", "filed")))'; cat "$STUB/filed")"
  card=$(st 'select(.issue == 100101 and .step == "landed") | .card')
  [ "$(jq -c --arg c "$card" 'select(.card == $c and .issue == 100101 and (.time | type) == "string") | [.finding, .by, .why]' "$ST/declined.jsonl")" = '["[P0] a.txt:1 wrong word","code","follow-up of a follow-up"]
["b.txt:22 no mark here","code","follow-up of a follow-up"]
["[P2] c.txt:3 a nit","code","follow-up of a follow-up"]' ] || fail "the declined list does not hold each leftover finding of the follow-up's card once, with who and why: $(cat "$ST/declined.jsonl" 2>&1)"
}

# Bugs: with one card in flight and nothing else to pick, the run stops picking, and the follow-ups that
# card files wait for another run; a follow-up is picked before its parent has landed (here #8's card ends while
# #7's second follow-up is still being filed, so the loop picks again with #100101 open and #7 not landed).
t_chain() {
  setup "$(jq -cs . <(issue 7 2026-01-01 P1) <(issue 8 2026-01-02 P2))"; : > "$STUB/list-filed"
  # The filing of the second follow-up goes on until #8's card has ended and the loop has taken a whole turn after it
  # (two of its waits begun, lib.sh), the turn in which it would pick #100101.
  tune '.tunables.poll = 1'; watchturns; provenbug # the follow-ups are bug cards
  cat > "$STUB/create-cmd" <<'EOF'
[ "$n" != 100102 ] || { while [ -d "$STUB" ]; do jq -e 'select(.issue == 8 and .step == "blocked")' "$ST/cards.jsonl" >/dev/null 2>&1 && break; sleep 0.1; done
  k=$(wc -l < "$TURNS"); while [ -d "$STUB" ] && [ "$(wc -l < "$TURNS")" -lt $((k + 2)) ]; do sleep 0.1; done; }
EOF
  cat > "$STUB/claude" <<'EOF'
#!/usr/bin/env bash
case $(cat) in *'# Issue #8:'*) while [ -d "$STUB" ]; do [ -e "$STUB/filed" ] && break; sleep 0.1; done; exit 1 ;; esac
. "$STUB/build"
echo '{"type":"result","is_error":false,"usage":{"input_tokens":10,"cache_creation_input_tokens":20,"cache_read_input_tokens":999,"output_tokens":5}}'
EOF
  cat > "$STUB/codex" <<'EOF'
#!/usr/bin/env bash
while [ $# -gt 0 ]; do [ "$1" = -o ] && out=$2; shift; done
case $(cat) in *'# Issue #7:'*) k=$(echo x >> "$STUB/reviews7"; wc -l < "$STUB/reviews7"); printf '[P1] a.txt:%s1 wrong word\n[P2] a.txt:%s2 a nit\nUSER-VISIBLE: no\nVERDICT: NO-GO\n' "$k" "$k" ;; *) printf 'USER-VISIBLE: no\nVERDICT: GO\n' ;; esac > "$out"
echo '{"type":"turn.completed","usage":{"input_tokens":100,"cached_input_tokens":60,"output_tokens":7}}'
EOF
  loop run >/dev/null || fail "run exited non-zero"
  steps=$(st 'select(.step | IN("picked", "landed", "blocked")) | "\(.issue) \(.step)"')
  at() { grep -nx "$1" <<<"$steps" | cut -d: -f1; }
  [ "$(st 'select(.step == "landed") | [.issue, .followups] | tojson' | sort | tr '\n' ' ')" = '[100101,null] [100102,null] [7,[100101,100102]] ' ] \
    || fail "the follow-ups were not built in the run that filed them: $(tr '\n' ',' <<<"$steps")"
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
  for i in 1 2; do moved $i "$NOGO" > "$STUB/review.$i"; done
  printf '%s\n' "[P2] b.txt:3 reads $HX/notes, and ${HX//\//\\/} and $KX too" 'USER-VISIBLE: no' 'VERDICT: NO-GO' > "$STUB/review.3"
  loop run >/dev/null || fail "run exited non-zero"
  [ "$(st 'select(.step == "landed") | .followups | tojson')" = '[100101]' ] || fail "the card did not land with its follow-up filed: $(st 'select(.step | IN("landed", "blocked"))')"
  [ "$(jq -r .title "$STUB/filed")" = '[P2] b.txt:3 reads <home path> and <home path> and <token> too' ] && jq -r .body "$STUB/filed" | grep -q 'Conveyor masked the parts' \
    && ! grep -qF -e "${HX#/}" -e "${KX#-----}" "$STUB/filed" || fail "the follow-up's text is not masked, or does not say so: $(cat "$STUB/filed")"
}

# Bug: a last finding that is a privacy hit in the card's own change (a line the card added holds a home path) was
# filed as a follow-up, which would land the hit on main, instead of going to a fix round.
t_privfix() {
  setup "[$(issue 7 2026-01-01)]"; export HX
  echo 'if [ -e "$STUB/built" ]; then echo fix >> a.txt; ! grep -qF "$HX/bench" "$STUB/brief" || { grep -vF "$HX/bench" a.txt > a.new; mv a.new a.txt; }
    else : > "$STUB/built"; printf "two\ncd %s/bench\n" "$HX" >> a.txt; fi' > "$STUB/build"
  for i in 1 2; do moved $i "$NOGO" > "$STUB/review.$i"; done; echo "$GO" > "$STUB/review.4"
  printf '%s\n' "[P0] a.txt:3 flags $HX/bench" 'USER-VISIBLE: no' 'VERDICT: NO-GO' > "$STUB/review.3"
  loop run >/dev/null || fail "run exited non-zero"
  [ "$(st 'select(.step == "review") | .result' | tr '\n' ' ')" = "NO-GO NO-GO NO-GO GO " ] && [ ! -e "$STUB/filed" ] \
    || fail "the privacy finding on the card's own line did not go to a fix round: $(st 'select(.step == "review") | .result' | tr '\n' ' ') $(cat "$STUB/filed" 2>&1)"
  [ -n "$(st 'select(.step == "landed") | .sha')" ] && ! grep -qF "$HX" "$R/a.txt" || fail "the card did not land without the hit: $(cat "$R/a.txt")"
}

# Bug: a follow-up chain goes on: a card whose issue is a follow-up at any depth (here 2, filed before a follow-up's
# card filed none) files another level on its third NO-GO, or its leftover finding is in no declined list.
t_deep() {
  setup "$(issue 7 2026-01-01 conveyor-followup bug P1 | jq -c '[.body = "Follow-up to #5.\n\nFollow-up depth: 2"]')"
  for i in 1 2 3 4; do moved $i "$NOGO" > "$STUB/review.$i"; done; provenbug
  mkdir -p "$ST"; landed 5 '[7]' > "$ST/cards.jsonl"
  loop run >/dev/null || fail "run exited non-zero"
  [ "$(wc -l < "$STUB/reviews")" = 3 ] || fail "$(wc -l < "$STUB/reviews") reviews, not 3"
  [ "$(st 'select(.issue == 7 and .step == "landed") | [.sha, .leftover, .followups] | tojson')" = "[\"$(git -C "$R" rev-parse HEAD)\",true,[]]" ] \
    && [ ! -e "$STUB/filed" ] && [ -z "$(ls "$T/$CASE/cards")" ] || fail "a depth-2 card did not land, or filed a follow-up, or the worktree is left: $(st 'select(.issue == 7 and (.step | IN("landed", "blocked")))')"
  [ "$(jq -c '[.issue, .finding, .by, .why]' "$ST/declined.jsonl")" = '[7,"[P1] a.txt:31 wrong word","code","follow-up of a follow-up"]' ] \
    || fail "the depth-2 card's leftover finding is not in the declined list once, with who and why: $(cat "$ST/declined.jsonl" 2>&1)"
}

# Bugs: a follow-up is known only by its depth line, so one with the follow-up label and no such line files another
# generation; a body past a pipe's 64 KiB (#8's, long lines: 6500 short ones took 100 s) hides it (its read ends early).
# fukept <issue json>: that bug card's three NO-GO reviews land it with its leftover finding declined, filing none.
fukept() {
  local n; n=$(jq .number <<<"$1")
  setup "[$1]"; provenbug; for i in 1 2 3; do moved $i "$NOGO" > "$STUB/review.$i"; done
  mkdir -p "$ST"; landed 5 '[7]' > "$ST/cards.jsonl"
  loop run >/dev/null || fail "run exited non-zero"
  [ "$(st 'select(.step == "landed" and .issue != 5) | [.issue, .leftover, .followups] | tojson')" = "[$n,true,[]]" ] && [ ! -e "$STUB/filed" ] \
    || fail "a card whose issue has the follow-up label, or a depth line in a long body, filed a follow-up or did not land: $(st 'select(.step | IN("landed", "blocked", "filed"))'; cat "$STUB/filed" 2>&1)"
  [ "$(jq -c '[.issue, .why]' "$ST/declined.jsonl")" = "[$n,\"follow-up of a follow-up\"]" ] || fail "its leftover finding is not in the declined list: $(cat "$ST/declined.jsonl" 2>&1)"
}
t_fuknown() { fukept "$(issue 7 2026-01-01 conveyor-followup bug P1 | jq -c '.body = "Follow-up to #5"')"; }
t_fuknownlong() {
  local i; i=$(issue 8 2026-01-02 bug P1 | jq -c '.body = "Follow-up depth: 1\n" + (("filler text " * 70 + "\n") * 100)')
  [ "$(jq -r .body <<<"$i" | wc -c)" -gt 65536 ] || fail "#8's body fits a pipe"
  fukept "$i"
}

# Bug: a declined list that cannot be written (here a folder is in its place) loses the findings: the card ends as
# landed and clean, and its review goes with its worktree. It has landed, and ends blocked with its review kept.
t_declinefail() {
  setup "[$(issue 7 2026-01-01 conveyor-followup bug P1)]"; for i in 1 2 3; do moved $i "$NOGO" > "$STUB/review.$i"; done; provenbug
  mkdir -p "$ST/declined.jsonl"
  loop run >/dev/null 2>&1 || fail "run exited non-zero"
  [ "$(st 'select(.step | IN("landed", "blocked")) | .step' | tr '\n' ' ')" = 'landed blocked ' ] \
    && st 'select(.step == "blocked") | .reason' | grep -q 'could not write its leftover findings to the declined list' || fail "a card whose findings could not be declined did not end landed, then blocked saying so: $(st 'select(.step | IN("landed", "blocked"))')"
  k=$ST/$(st 'select(.step == "blocked") | .kept'); grep -q 'wrong word' "$k"/*.review || fail "the review of the findings that could not be declined was not kept: $(ls "$k" 2>&1)"
}

# The owner approves every change to how the engine builds, reviews, fixes, tests, lands or pushes. Bugs: a leftover
# finding on a file the pack lists as a pipeline file is filed like any other and built with no one asked; it is filed
# with no "Cost to every card:" line, or not held, or the loop picks it while held; Needs you does not list it; a
# finding on any other file is held too, or gets the cost line, or is no longer picked; once released it is not built.
t_pipeline() {
  setup "[$(issue 7 2026-01-01 P1)]"; tune '.pipelineFiles = ["a.txt", "lib/"]'
  # Another spelling of a listed file is that file; a longer name that starts with one is another file.
  . <(sed -n '/^onpipeline() {/,/^}/p' "$SRC/lib/followups.sh")
  [ "$(for f in '[P1] ./a.txt:9 x' '[P1] lib/./b.sh:9 x' '[P1] lib//c/../b.sh:9 x' 'in `c/../a.txt`.' '[P1] a.txt.bak:9 x' '[P1] library/b.sh:9 x' '[P1] c/a.txt:9 x'; do
    echo "[$(onpipeline "$f" <<<'["a.txt", "lib/"]')]"; done | tr -d '\n')" = '[1][1][1][1][][][]' ] || fail "a pipeline file under another spelling is not held, or a file that only starts with its name is"
  # A listed name with a space in it is that name, quoted or not; one of its words alone is not.
  [ "$(for f in '[P1] `ci/build engine.sh`:9 wrong command' 'see ci/build engine.sh:9.' '[P1] ci/build:9 x' '[P1] engine.sh:9 x'; do
    echo "[$(onpipeline "$f" <<<'["ci/build engine.sh"]')]"; done | tr -d '\n')" = '[1][1][][]' ] || fail "a pipeline file whose name holds a space is not held, or one of its words alone is"
  for i in 1 2; do moved $i "$NOGO3" > "$STUB/review.$i"; done; echo "$NOGO3" > "$STUB/review.3"; for i in 4 5 6 7; do echo "$GO" > "$STUB/review.$i"; done
  loop run --only 7 >/dev/null || fail "run exited non-zero"
  [ "$(st 'select(.step == "landed") | .followups | tojson')" = '[100101,100102,100103]' ] || fail "the third NO-GO did not land with its three follow-ups: $(st 'select(.step | IN("landed", "blocked"))')"
  [ "$(jq -rs 'map(.body | split("\n") | map(select(startswith("Cost to every card: "))) | join(",")) | join("|")' "$STUB/filed")" = 'Cost to every card: not assessed||' ] \
    && jq -rs '.[0].body' "$STUB/filed" | grep -qx 'Follow-up depth: 1' || fail "only the finding on the pipeline file a.txt gets the cost line, and keeps its depth line: $(cat "$STUB/filed")"
  [ "$(jq -c .held "$ST/control.json")" = '[100101]' ] || fail "the control record holds $(jq -c .held "$ST/control.json"), not the follow-up on the pipeline file alone"
  # The loop builds a follow-up on another file, as before, and never the held one (a run with no --only: one limited
  # to #7 goes on polling for the held follow-up). One such follow-up (#100102) is open: a second proves no more and
  # costs a card. A bug card (provenbug).
  jq -cs '.[:2]' "$STUB/filed" > "$STUB/issues.json"; provenbug
  loop run >/dev/null || fail "second run exited non-zero"
  [ "$(st 'select(.step == "picked") | .issue' | tr '\n' ' ')" = "7 100102 " ] || fail "picks with the pipeline follow-up held: $(st 'select(.step == "picked") | .issue' | tr '\n' ' ')"
  [ "$(st 'select(.step == "landed") | .issue' | tr '\n' ' ')" = "7 100102 " ] || fail "the follow-up on another file did not land: $(st 'select(.step | IN("landed", "blocked"))')"
  jq -cs '[.[0]]' "$STUB/filed" > "$STUB/issues.json"
  [ "$(loop snapshot | jq -c '.needsYou.pipeline | map([.issue, .title, .cost, .parent])')" = '[[100101,"[P0] a.txt:1 wrong word","not assessed",7]]' ] \
    || fail "Needs you does not list the held pipeline follow-up with its cost line: $(loop snapshot | jq -c .needsYou.pipeline)"
  # The owner releases it: it is built like any follow-up, and leaves Needs you.
  loop control release 100101 >/dev/null; loop run >/dev/null || fail "third run exited non-zero"
  [ "$(st 'select(.step == "landed") | .issue' | tr '\n' ' ')" = "7 100102 100101 " ] || fail "the released pipeline follow-up was not built: $(st 'select(.step | IN("picked", "landed", "blocked")) | [.step, .issue] | join(":")' | tr '\n' ' ')"
  [ "$(loop snapshot | jq -c .needsYou.pipeline)" = '[]' ] || fail "a released pipeline follow-up is still in Needs you"
}

# A finding that comes back after its fix round stops the loop. Bugs: the same finding comes back round after round,
# each round a fix session and a review, until the round limit; the fix session after a repeat is not told the
# finding came back, nor shown the earlier fix, so it repeats it. Its cases (cameback*) each run one issue's card.
# A cameback case's main and stubs: its one issue; each session's brief kept as $STUB/brief.<its number>.
backsetup() { # <issue>
  setup "[$(issue "$1" 2026-01-01)]"; steps() { st "select(.issue == $1 and $NOMARK) | \"\(.step) \(.result)\"" | tr '\n' ,; }
  echo 'cp "$STUB/brief" "$STUB/brief.$(wc -l < "$STUB/sessions")"; echo "fix$(wc -l < "$STUB/sessions")" >> a.txt' > "$STUB/build"
}

t_cameback() {
  backsetup 7
  # #7: a P2 finding back after its fix round (its proof in other words, its line text the same), every finding P2 or
  # P3: the card lands at once and files it, with no second fix session.
  printf '%s\n' '[P2] a.txt:1 The nit stays here. Proof: line 2 reads fix1' 'USER-VISIBLE: no' 'VERDICT: NO-GO' > "$STUB/review.1"
  printf '%s\n' '[P2] a.txt:1 the nit stays here. Proof: line 3 reads fix2' '[P3] c.txt:3 a style nit' 'USER-VISIBLE: no' 'VERDICT: NO-GO' > "$STUB/review.2"
  loop run --only 7 >/dev/null || fail "run of #7 exited non-zero"
  [ "$(steps 7)" = "picked ok,worktree ok,brief ok,build ok,review NO-GO,fix ok,review NO-GO,test pass,landed ok," ] && [ "$(wc -l < "$STUB/sessions")" = 2 ] \
    || fail "a P2 finding back after its fix did not land the card at once: $(steps 7) $(wc -l < "$STUB/sessions") sessions: $(cat "$STUB/sessions")"
  [ "$(st 'select(.issue == 7 and .step == "landed") | [.leftover, .followups] | tojson')" = '[true,[100101,100102]]' ] \
    && [ "$(jq -r .title "$STUB/filed" | tr '\n' '|')" = '[P2] a.txt:1 the nit stays here. Proof: line 3 reads fix2|[P3] c.txt:3 a style nit|' ] \
    || fail "the card that landed on a repeat did not file its findings: $(cat "$STUB/filed" 2>&1)"
  ! grep -q 'came back after a fix round' "$STUB/brief.2" || fail "the first fix session was told of a repeat"
}

t_camebackp1() {
  backsetup 8; head=$(git -C "$R" rev-parse HEAD)
  # #8: a P1 finding back after its fix round blocks the card for the owner, with no second fix session and nothing filed.
  printf '%s\n' '[P1] a.txt:1 wrong word' '[P2] c.txt:3 a nit' 'USER-VISIBLE: no' 'VERDICT: NO-GO' > "$STUB/review.1"
  printf '%s\n' '[P1] a.txt:1 wrong word. Proof: line 3 reads fix2' 'USER-VISIBLE: no' 'VERDICT: NO-GO' > "$STUB/review.2"
  loop run --only 8 >/dev/null || fail "run of #8 exited non-zero"
  [ "$(steps 8)" = "picked ok,worktree ok,brief ok,build ok,review NO-GO,fix ok,review NO-GO,blocked blocked," ] && [ "$(wc -l < "$STUB/sessions")" = 2 ] \
    && [ "$(st 'select(.issue == 8 and .step == "blocked") | .reason')" = 'the fix for [P1] a.txt:1 wrong word. Proof: line 3 reads fix2 did not hold after 1 round' ] \
    || fail "a P1 finding back after its fix did not block the card with the reason: $(steps 8) $(st 'select(.issue == 8 and .step == "blocked") | .reason')"
  [ "$(git -C "$R" rev-parse HEAD)" = "$head" ] && [ ! -e "$STUB/filed" ] && [ -z "$(ls "$T/$CASE/cards")" ] || fail "#8 landed, filed, or left its worktree"
  # Issue 306: the review that blocks keeps its answer beside the finding's first location and proof.
  [ "$(st 'select(.issue == 8 and .step == "review") | .answers | tojson' | tr '\n' ' ')" \
    = 'null [{"id":"E1","answer":"[P1] a.txt:1 wrong word. Proof: line 3 reads fix2","first":{"round":1,"at":"a.txt:1","line":"[P1] a.txt:1 wrong word"}}] ' ] \
    || fail "the review that blocked lost its answer or the first proof: $(st 'select(.issue == 8 and .step == "review") | .answers | tojson' | tr '\n' ' ')"
}

t_camebacktold() {
  backsetup 9
  # #9: a P2 finding comes back beside a new P1: the fix session is told it came back, with the earlier review's
  # finding and the diff of the fix round after it; the GO after it lands the card.
  printf '%s\n' '[P2] a.txt:1 a nit. Proof: line 2 reads fix1' 'USER-VISIBLE: no' 'VERDICT: NO-GO' > "$STUB/review.1"
  printf '%s\n' '[P2] a.txt:1 a nit. Proof: line 3 reads fix2' '[P1] b.txt:2 a new bug' 'USER-VISIBLE: no' 'VERDICT: NO-GO' > "$STUB/review.2"
  printf '%s\n' 'EARLIER: E2 holds' "$GO" > "$STUB/review.3"
  loop run --only 9 >/dev/null || fail "run of #9 exited non-zero"
  [ "$(steps 9)" = "picked ok,worktree ok,brief ok,build ok,review NO-GO,fix ok,review NO-GO,fix ok,review GO,test pass,landed ok," ] \
    || fail "a P2 repeat beside a new P1 was not fixed and reviewed again: $(steps 9)"
  b=$STUB/brief.3
  grep -qx '# These findings came back after a fix round for them' "$b" && grep -qx '## \[P2\] a.txt:1 a nit. Proof: line 3 reads fix2' "$b" \
    && grep -qx 'It came back after 1 fix round for it. The earlier review said:' "$b" && grep -qx '\[P2\] a.txt:1 a nit. Proof: line 2 reads fix1' "$b" \
    && grep -qx '+fix2' "$b" && ! grep -qx '+fix1' "$b" || fail "the fix session after a repeat was not told it came back with the earlier fix's diff: $(cat "$b")"
  ! grep -q '^## \[P1\] b.txt:2' "$b" || fail "a new finding was given as one that came back"
  # Issue 306: the finding that came back keeps its id in the fix brief, the new one has the next id, and the
  # review's line and the Board's snapshot name the one that came back.
  grep -qx 'E1 \[P2\] a.txt:1 a nit. Proof: line 3 reads fix2' "$b" && grep -qx 'E2 \[P1\] b.txt:2 a new bug' "$b" || fail "the fix session was not given the findings' ids: $(cat "$b")"
  [ "$(st 'select(.issue == 9 and .step == "review") | .survived | tojson' | tr '\n' ' ')" = 'null [{"id":"E1","rounds":1}] null ' ] \
    && [ "$(loop snapshot | jq -c '.landed[] | select(.issue == 9) | .rounds | map(.survived)')" = '[[],[{"id":"E1","rounds":1}],[]]' ] \
    || fail "the review line or the snapshot does not name the finding that came back: $(st 'select(.issue == 9 and .step == "review") | .survived | tojson' | tr '\n' ' ') $(loop snapshot | jq -c '.landed[] | select(.issue == 9) | .rounds')"
  # The GO that ends the loop keeps its `EARLIER: E2 holds` beside E2's first location and proof.
  [ "$(st 'select(.issue == 9 and .step == "review" and .result == "GO") | .answers | tojson')" = '[{"id":"E2","answer":"holds","first":{"round":2,"at":"b.txt:2","line":"[P1] b.txt:2 a new bug"}}]' ] \
    || fail "the GO lost its answer on E2: $(st 'select(.issue == 9 and .step == "review" and .result == "GO") | .answers | tojson')"
}

# A card retried from a kept patch carries its earlier review rounds. Bug: a retry began the round count again, so
# a card blocked after two reviews had three more.
t_retryrounds() {
  setup "[$(issue 7 2026-01-01)]"; steps() { st "select(.issue == 7 and $NOMARK) | \"\(.step) \(.result)\"" | tr '\n' ,; }
  for i in 1 2; do moved $i "$NOGO" > "$STUB/review.$i"; done; echo "$NOGO" > "$STUB/review.3"
  # The fix session after the second review fails: the card blocks after two rounds, its patch kept.
  echo '[ "$(wc -l < "$STUB/sessions")" != 3 ] || exit 1; echo two >> a.txt' > "$STUB/build"
  loop run >/dev/null; st 'select(.step == "blocked") | .reason' | grep -q '^fix: ' || fail "#7 was not blocked on its failed fix: $(steps)"
  loop retry 7 >/dev/null && loop run >/dev/null || fail "run of the retried #7 exited non-zero"
  # One round left: the resumed session, one review whose NO-GO is the last, and it lands with its finding filed.
  [ "$(steps)" = "picked ok,worktree ok,brief ok,build ok,review NO-GO,test pass,landed ok," ] && [ "$(wc -l < "$STUB/reviews")" = 3 ] && [ "$(wc -l < "$STUB/sessions")" = 4 ] \
    || fail "the retried card did not have one review round left: $(steps)"
  [ "$(st 'select(.step == "landed") | [.leftover, .followups] | tojson')" = '[true,[100101]]' ] && [ "$(jq -r .title "$STUB/filed")" = '[P1] a.txt:1 wrong word' ] \
    || fail "the last review of the retried card did not file its finding: $(cat "$STUB/filed" 2>&1)"
}

# A repeat is known whatever else ends the loop. Bugs: a P1 finding back after its fix on the last round lands with
# follow-ups instead of blocking; a card that blocks deletes its fix rounds, so its retry fixes a finding that came
# back as if new; a card whose patch could not be kept deletes them too. Its cases (repeatkept*) each run one issue's
# card. A repeatkept case's main and stubs: its one issue, each session adding a line fix<n> to a.txt.
keptsetup() { # <issue>
  setup "[$(issue "$1" 2026-01-01)]"; steps() { st "select(.issue == $1 and $NOMARK) | \"\(.step) \(.result)\"" | tr '\n' ,; }
  echo 'echo "fix$(wc -l < "$STUB/sessions")" >> a.txt' > "$STUB/build"; B='[P1] b.txt:2 broken'; head=$(git -C "$R" rev-parse HEAD)
}

t_repeatkept() {
  keptsetup 10
  # #10: the third review, the round limit, repeats a P1 its fix round was told to fix: blocked, nothing filed.
  echo "$NOGO" > "$STUB/review.1"; printf '%s\n' "$B" 'USER-VISIBLE: no' 'VERDICT: NO-GO' | tee "$STUB/review.2" > "$STUB/review.3"
  loop run --only 10 >/dev/null || fail "run of #10 exited non-zero"
  [ "$(st 'select(.issue == 10 and .step == "blocked") | .reason')" = "the fix for $B did not hold after 1 round" ] && [ ! -e "$STUB/filed" ] \
    && [ "$(git -C "$R" rev-parse HEAD)" = "$head" ] || fail "a P1 repeat on the last round did not block: $(steps 10) $(cat "$STUB/filed" 2>&1)"
  # Its retry: the resumed session is told the finding came back, with the diff of the fix round told to fix it.
  echo "$GO" > "$STUB/review.4"; loop retry 10 >/dev/null && loop run --only 10 >/dev/null || fail "run of the retried #10 exited non-zero"
  grep -qx '# These findings came back after a fix round for them' "$STUB/brief" && grep -qx "## \\$B" "$STUB/brief" && grep -qx '+fix3' "$STUB/brief" \
    || fail "the resumed session of a card blocked on a repeat was not told it came back with the earlier fix's diff: $(cat "$STUB/brief")"
}

t_repeatkeptfail() {
  keptsetup 11
  # #11: a NO-GO, its fix, then a review that fails: blocked with its patch and its fix round kept. The retry's review
  # repeats the P1: blocked, with no fix session after it.
  for i in 1 2 3 4; do printf '%s\n' "$B" 'USER-VISIBLE: no' 'VERDICT: NO-GO' > "$STUB/review.$i"; done
  echo '[ "$(wc -l < "$STUB/reviews")" = 1 ] || [ ! -e "$STUB/review-fail" ] || exit 3' > "$STUB/review-cmd"; : > "$STUB/review-fail"
  loop run --only 11 >/dev/null; k=$(st 'select(.issue == 11 and .step == "blocked") | "\($ENV.ST)/\(.kept)/\(.card)"')
  [ -s "$k.patch" ] && [ "$(jq -r .line "$k.rounds/findings.jsonl")" = "$B" ] && grep -qx '+fix2' "$k.rounds/1.diff" \
    || fail "a card blocked after a fix round did not keep that round: $(steps 11) $(ls "${k%/*}")"
  rm "$STUB/review-fail"; loop retry 11 >/dev/null && loop run --only 11 >/dev/null || fail "run of the retried #11 exited non-zero"
  [ "$(st 'select(.issue == 11 and .step == "blocked") | .reason')" = "the fix for $B did not hold after 1 round" ] && [ "$(wc -l < "$STUB/sessions")" = 3 ] \
    || fail "a retry did not know a repeat of its earlier card's fix round: $(steps 11) $(wc -l < "$STUB/sessions") sessions"
  ! grep -q 'came back after a fix round' "$STUB/brief" || fail "the resumed session was told of a repeat its kept review, written before the fix round, cannot show"
}

t_repeatkeptstage() {
  keptsetup 12
  # #12: as #11 (t_repeatkeptfail), but the change cannot be staged when it blocks: the worktree stays, and its fix
  # round is kept.
  echo "$NOGO" > "$STUB/review.1"
  echo '[ "$(wc -l < "$STUB/reviews")" = 1 ] || { for w in "$STUB"/../cards/*-12; do : > "$(git -C "$w" rev-parse --git-path index.lock)"; done; exit 3; }' > "$STUB/review-cmd"
  loop run --only 12 >/dev/null; k=$(st 'select(.issue == 12 and .step == "blocked") | "\($ENV.ST)/\(.kept)/\(.card)"')
  st 'select(.issue == 12 and .step == "blocked") | .reason' | grep -q 'could not be kept as a patch' && [ "$(jq -r .line "$k.rounds/findings.jsonl" | head -n 1)" = '[P1] a.txt:1 wrong word' ] \
    && grep -qx '+fix2' "$k.rounds/1.diff" || fail "a card whose patch could not be kept lost its fix round: $(steps 12) $(ls "${k%/*}")"
}

t_repeatkeptmove() {
  keptsetup 13
  # #13: its fix rounds cannot be moved to the kept folder (one of that name is there): they stay beside the worktree.
  echo "$NOGO" > "$STUB/review.1"
  echo '[ "$(wc -l < "$STUB/reviews")" = 1 ] || exit 3' > "$STUB/review-cmd"
  echo 'mkdir -p "$ST/kept/${PWD##*/}/${PWD##*/}.rounds/x"; echo "fix$(wc -l < "$STUB/sessions")" >> a.txt' > "$STUB/build"
  loop run --only 13 >/dev/null; c=$(st 'select(.issue == 13 and .step == "blocked") | .card')
  st 'select(.issue == 13 and .step == "blocked") | .reason' | grep -q 'evidence not moved' && [ "$(jq -r .line "$T/$CASE/cards/$c.rounds/findings.jsonl" 2>&1)" = '[P1] a.txt:1 wrong word' ] \
    || fail "fix rounds that could not be moved were deleted: $(steps 13) $(ls "$T/$CASE/cards")"
  # Its retry takes the fix rounds left beside the worktree, not the folder that stopped their move: the repeat is known.
  rm "$STUB/review-cmd"; echo 'echo "fix$(wc -l < "$STUB/sessions")" >> a.txt' > "$STUB/build"; echo "$NOGO" > "$STUB/review.$(($(wc -l < "$STUB/reviews") + 1))"; loop retry 13 >/dev/null && loop run --only 13 >/dev/null || fail "run of the retried #13 exited non-zero"
  [ "$(st 'select(.issue == 13 and .step == "blocked") | .reason' | tail -n 1)" = 'the fix for [P1] a.txt:1 wrong word did not hold after 1 round' ] && [ "$(wc -l < "$STUB/sessions")" = 3 ] \
    || fail "a retry copied the folder that stopped the move instead of the fix rounds left beside the worktree: $(steps 13)"
}

# A kept patch reviewed again with no build (an approval with a condition) carries its loop's rounds. Bug: that
# review began with no fix rounds, so a P1 back after its fix round was fixed again instead of blocking the card.
t_reviewrounds() {
  setup "[$(issue 7 2026-01-01)]"; YES='USER-VISIBLE: yes: guests see a new Pay button'; steps() { st "select(.issue == 7 and $NOMARK) | \"\(.step) \(.result)\"" | tr '\n' ,; }
  echo 'echo "fix$(wc -l < "$STUB/sessions")" >> a.txt; mkdir -p web; echo pay >> web/pay.ts' > "$STUB/build"
  # Two reviews repeat a P2 after its fix round: the last review, visible, so the card stops for the owner's yes.
  for i in 1 2; do printf '%s\n' '[P2] a.txt:1 wrong word' "$YES" 'VERDICT: NO-GO' > "$STUB/review.$i"; done
  loop run >/dev/null; st 'select(.step == "blocked") | .reason' | grep -q "needs Dana's yes" || fail "#7 was not blocked for Dana's yes: $(steps)"
  # A yes with a condition: the kept patch is reviewed with no build, and that review repeats the finding as a P1.
  issue 7 2026-01-01 | jq -c '[.body += "\nVisible change approved: r-11, only for admins"]' > "$STUB/issues.json"
  printf '%s\n' '[P1] a.txt:1 wrong word' "$YES" 'VERDICT: NO-GO' > "$STUB/review.3"; echo "$GO" > "$STUB/review.4"
  loop retry 7 >/dev/null && loop run >/dev/null || fail "run of the retried #7 exited non-zero"
  [ "$(steps)" = "picked ok,worktree ok,brief ok,review NO-GO,blocked blocked," ] && [ "$(wc -l < "$STUB/sessions")" = 2 ] \
    && [ "$(st 'select(.issue == 7 and .step == "blocked") | .reason')" = 'the fix for [P1] a.txt:1 wrong word did not hold after 1 round' ] \
    || fail "a kept patch reviewed again did not know a repeat of its loop's fix round: $(steps) $(wc -l < "$STUB/sessions") sessions"
}

# A kept patch reviewed again with no build counts its loop's reviews toward the round limit. Bug: its count began
# again, so a NO-GO on the third review of the issue (a finding no fix round was told) was fixed and reviewed again.
t_reviewlimit() {
  setup "[$(issue 7 2026-01-01)]"; YES='USER-VISIBLE: yes: guests see a new Pay button'; steps() { st "select(.issue == 7 and $NOMARK) | \"\(.step) \(.result)\"" | tr '\n' ,; }
  echo 'echo "fix$(wc -l < "$STUB/sessions")" >> a.txt; mkdir -p web; echo pay >> web/pay.ts' > "$STUB/build"
  for i in 1 2; do printf '%s\n' '[P2] a.txt:1 wrong word' "$YES" 'VERDICT: NO-GO' > "$STUB/review.$i"; done
  loop run >/dev/null; st 'select(.step == "blocked") | .reason' | grep -q "needs Dana's yes" || fail "#7 was not blocked for Dana's yes: $(steps)"
  issue 7 2026-01-01 | jq -c '[.body += "\nVisible change approved: r-11, only for admins"]' > "$STUB/issues.json"
  printf '%s\n' '[P1] b.txt:2 another word' "$YES" 'VERDICT: NO-GO' > "$STUB/review.3"; echo "$GO" > "$STUB/review.4"
  loop retry 7 >/dev/null && loop run >/dev/null || fail "run of the retried #7 exited non-zero"
  # Its third review is the last: no fix session, and it lands with the new finding filed.
  [ "$(steps)" = "picked ok,worktree ok,brief ok,review NO-GO,test pass,landed ok," ] && [ "$(wc -l < "$STUB/sessions")" = 2 ] && [ "$(wc -l < "$STUB/reviews")" = 3 ] \
    && [ "$(jq -r .title "$STUB/filed")" = '[P1] b.txt:2 another word' ] \
    || fail "a kept patch reviewed again did not count its loop's reviews: $(steps) $(wc -l < "$STUB/sessions") sessions $(cat "$STUB/filed" 2>&1)"
}

# The declined list: every finding that is not built is one line of the project's state. Bugs: a finding declined by
# code or by the judge leaves no line, or one without who declined it and why; a finding declined again for its card
# is listed twice; a decline by no one known is taken; the snapshot does not give the list newest first; "file as
# issue" files no issue, one that does not name the finding, a follow-up, or a second issue when asked again; a line is
# gone from the snapshot, and so from the Board with its "File as issue", once 200 newer ones follow it.
t_declined() {
  local on id out
  setup "[$(issue 7 2026-01-01)]"
  on() { local t=$1; shift; CONVEYOR_NOW=$(date -u -d "$t" +%s) loop "$@"; }
  on 2026-03-04T10:00:00Z declined add c1-7 7 code 'follow-up of a follow-up' '[P2] a.txt:1 wrong word' || fail "a finding declined by code was not taken"
  on 2026-03-04T11:00:00Z declined add c1-7 7 judge 'its proof needs a stub built to misbehave' '[P1] b.txt:2 no mark here' || fail "a finding declined by the judge was not taken"
  # The reviewer raises the judge's one again in the next round of the card, and it is declined again.
  on 2026-03-04T12:00:00Z declined add c1-7 7 judge 'its proof needs a stub built to misbehave' '[P1] b.txt:2 no mark here' || fail "a finding declined again was refused"
  [ "$(jq -c '[.time, .card, .issue, .finding, .by, .why]' "$ST/declined.jsonl" | tr '\n' ' ')" \
    = '["2026-03-04T10:00:00Z","c1-7",7,"[P2] a.txt:1 wrong word","code","follow-up of a follow-up"] ["2026-03-04T11:00:00Z","c1-7",7,"[P1] b.txt:2 no mark here","judge","its proof needs a stub built to misbehave"] ' ] \
    || fail "each declined finding is not one line with who declined it and why: $(cat "$ST/declined.jsonl")"
  loop declined add c1-7 7 reviewer 'no' '[P1] c.txt:3 a nit' 2>/dev/null; [ $? = 2 ] && [ "$(wc -l < "$ST/declined.jsonl")" = 2 ] || fail "a decline by neither code, judge nor owner was taken"
  [ "$(on 2026-03-05T00:00:00Z snapshot | jq -c '.declined | map([.by, .why, .built])')" = '[["judge","its proof needs a stub built to misbehave",null],["code","follow-up of a follow-up",null]]' ] \
    || fail "the snapshot does not give the declined list newest first: $(on 2026-03-05T00:00:00Z snapshot | jq -c .declined)"
  # "File as issue": one ordinary issue that names the finding; asked again, none.
  id=$(jq -r 'select(.by == "code") | .id' "$ST/declined.jsonl")
  out=$(loop declined build "$id") || fail "build this failed: $out"
  out=$(loop declined build "$id") && [[ $out == *'already filed as #100101'* ]] || fail "build this, asked again, did not say the finding is filed: $out"
  [ "$(jq -c '[.title, .labels, (.body | test("(^|\n)Finding: \\[P2\\] a\\.txt:1 wrong word\n")), (.body | contains("follow-up of a follow-up"))]' "$STUB/filed")" = '["[P2] a.txt:1 wrong word",[],true,true]' ] \
    || fail "build this did not file one ordinary issue naming the finding: $(cat "$STUB/filed" 2>&1)"
  [ "$(jq -c '[.by, .built]' "$ST/declined.jsonl" | tr '\n' ' ')" = '["code",100101] ["judge",null] ' ] || fail "the line does not keep the issue filed for it: $(cat "$ST/declined.jsonl")"
  loop declined build d000000000000 2>/dev/null; [ $? = 2 ] && [ "$(wc -l < "$STUB/filed")" = 1 ] || fail "a line the list does not have filed an issue"
  jq -cn 'range(200) | {id: "dx\(.)", time: "2026-03-05T00:00:00Z", card: "c2-8", issue: 8, finding: "[P2] f.txt:\(.) a nit", by: "judge", why: "no proof", repo: "sample"}' >> "$ST/declined.jsonl"
  # The built line has left the panel's part for the rest, where "Show every line" reaches it.
  [ "$(on 2026-03-06T00:00:00Z snapshot | jq -c '[(.declined | length), .declined[-1].finding, (.declinedRest | map([.finding, .built]))]')" = '[201,"[P1] b.txt:2 no mark here",[["[P2] a.txt:1 wrong word",100101]]]' ] \
    || fail "the snapshot lost the oldest declined findings behind 200 newer ones: $(on 2026-03-06T00:00:00Z snapshot | jq -c '[(.declined | length), .declined[-1].finding, .declinedRest]')"
}

# Dismiss on the Board's Declined panel. Bugs: a dismissed line is gone from the declined list, or keeps no record of
# who dismissed it and when; it is still in the panel's part of the snapshot, or lost from the rest ("Show every
# line"); a line over 7 days old stays in the panel's part; a second dismissal rewrites the first; an id the list does
# not have dismisses the others named with it. (Its reason still reaching the reviewer: t_donotraise.)
t_dismissed() {
  local on a b
  setup "[$(issue 7 2026-01-01)]"
  on() { local t=$1; shift; CONVEYOR_NOW=$(date -u -d "$t" +%s) loop "$@"; }
  on 2026-02-01T10:00:00Z declined add c1-7 7 judge 'too old to show' '[P2] o.txt:1 an old nit' \
    && on 2026-03-04T10:00:00Z declined add c1-7 7 code 'follow-up of a follow-up' '[P2] a.txt:1 wrong word' \
    && on 2026-03-04T11:00:00Z declined add c1-7 7 judge 'its proof needs a stub built to misbehave' '[P1] b.txt:2 no mark here' || fail "the declined list was not made"
  a=$(jq -r 'select(.by == "code") | .id' "$ST/declined.jsonl"); b=$(jq -r 'select(.finding | startswith("[P1]")) | .id' "$ST/declined.jsonl")
  on 2026-03-05T00:00:00Z declined dismiss --by 'Board user owner' "$a" >/dev/null || fail "dismiss failed"
  on 2026-03-05T01:00:00Z declined dismiss "$a" >/dev/null || fail "dismiss of a line dismissed already failed"
  [ "$(jq -c '[.finding, .dismissed]' "$ST/declined.jsonl" | tr '\n' ' ')" \
    = '["[P2] o.txt:1 an old nit",null] ["[P2] a.txt:1 wrong word",{"time":"2026-03-05T00:00:00Z","by":"Board user owner"}] ["[P1] b.txt:2 no mark here",null] ' ] \
    || fail "the dismissed line is not kept in the list with who dismissed it and when, once: $(cat "$ST/declined.jsonl")"
  [ "$(on 2026-03-05T02:00:00Z snapshot | jq -c '[(.declined | map(.id)), (.declinedRest | map([.finding, .dismissed.by]))]')" \
    = "[[\"$b\"],[[\"[P2] a.txt:1 wrong word\",\"Board user owner\"],[\"[P2] o.txt:1 an old nit\",null]]]" ] \
    || fail "the panel's part holds a dismissed or 7-day-old line, or the rest lost one: $(on 2026-03-05T02:00:00Z snapshot | jq -c '[.declined, .declinedRest]')"
  loop declined dismiss "$b" d000000000000 2>/dev/null; [ $? = 2 ] && [ "$(jq -c --arg b "$b" 'select(.id == $b) | .dismissed' "$ST/declined.jsonl")" = null ] \
    || fail "an id the list does not have did not refuse the dismissal, or the other line named was dismissed"
}

# The reviewer is told what not to raise. Bugs: the review prompt lacks the project's stated limits (its README's
# accepted limits) or the reasons of the declined findings, so the reviewer raises the same class on the next card;
# it takes the README's other sections for limits; it still forbids a finding the owner asked to be built; a finding
# still declined is left out because many lines the owner asked to be built came after it, or because it was dismissed
# from the Board's panel.
t_donotraise() {
  setup "[$(issue 8 2026-01-02)]"
  sed -i 's|^cat > /dev/null; echo x|cat > "$STUB/asked"; echo x|' "$STUB/codex"
  echo "$GO" > "$STUB/review.1"
  printf '%s\n' '# Sample' '' '## Run' 'Run it with care.' '' '## Accepted limits' '' '- Two changes that each pass alone can fail together on main.' '' '## License' 'Any.' > "$R/README.md"
  git -C "$R" add README.md && git -C "$R" commit -qm readme && git -C "$R" push -q origin main || fail "the README was not committed"
  loop declined add c1-7 7 judge 'its proof needs a stub built to misbehave' '[P1] b.txt:2 no mark here' \
    && loop declined add c1-7 7 code 'follow-up of a follow-up' '[P2] a.txt:1 wrong word' \
    && loop declined build "$(jq -r 'select(.by == "code") | .id' "$ST/declined.jsonl")" >/dev/null \
    && loop declined dismiss "$(jq -r 'select(.by == "judge") | .id' "$ST/declined.jsonl")" >/dev/null || fail "the declined list was not made"
  jq -cn 'range(200) | {id: "dx\(.)", time: "2026-03-05T00:00:00Z", card: "c2-9", issue: 9, finding: "[P2] f.txt:\(.) a nit", by: "judge", why: "built after all", repo: "sample", built: (200 + .)}' >> "$ST/declined.jsonl"
  loop run --only 8 >/dev/null || fail "run of #8 exited non-zero"
  [ "$(st 'select(.issue == 8 and .step == "landed") | .result')" = ok ] || fail "#8 did not land"
  grep -qx '# Do not raise these' "$STUB/asked" && grep -qx -- '- Two changes that each pass alone can fail together on main.' "$STUB/asked" \
    || fail "the review prompt lacks the README's accepted limits: $(grep -n -A6 'Do not raise' "$STUB/asked")"
  ! grep -qx 'Run it with care.' "$STUB/asked" && ! grep -qx 'Any.' "$STUB/asked" || fail "the review prompt takes the README's other sections for limits"
  grep -qxF -- '- its proof needs a stub built to misbehave (the finding: [P1] b.txt:2 no mark here)' "$STUB/asked" \
    || fail "the review prompt lacks the reason of a declined finding: $(grep -n -A8 'Do not raise' "$STUB/asked")"
  ! grep -q 'follow-up of a follow-up\|built after all' "$STUB/asked" || fail "the reviewer is told not to raise a finding the owner asked to be built"
  # The issue comes after the instructions, as before.
  [ "$(grep -n -m1 '^# Do not raise these$' "$STUB/asked" | cut -d: -f1)" -lt "$(grep -n -m1 'body of 8' "$STUB/asked" | cut -d: -f1)" ] || fail "what not to raise is not part of the review's instructions"
}

# Bug: a project with no limit and no declined finding gets an empty "Do not raise these".
t_donotraisenone() {
  setup "[$(issue 7 2026-01-01)]"
  sed -i 's|^cat > /dev/null; echo x|cat > "$STUB/asked"; echo x|' "$STUB/codex"
  echo "$GO" > "$STUB/review.1"
  loop run --only 7 >/dev/null || fail "run of #7 exited non-zero"
  grep -q '^Review the staged change' "$STUB/asked" && ! grep -q 'Do not raise these' "$STUB/asked" || fail "a project with nothing declined and no stated limit is told not to raise something: $(grep -n -A3 'Do not raise' "$STUB/asked")"
}
