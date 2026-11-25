#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 300
# Engine cases: the review loop, landing and follow-ups.
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"
# A page of the repository says <text> (lines joined, spaces folded). A case that has just run the behaviour a page describes
# calls this with what the run showed, so the page and the run cannot disagree. Each case file that calls it defines its own,
# named after the file: the bug check puts only the card's test files on main's code, where a helper in lib.sh is missing,
# and the runner sources the case files into one shell, where one name cannot be defined twice.
pagesays_review() { tr '\n' ' ' < "$SRC/../$1" | tr -s ' ' | grep -qF -- "$2" || fail "$1 does not say \"$2\": $3"; } # <page> <text> <what the run showed>
# The engine folder, as lib.sh sets it: named here too, so the release closure (tools/closure.sh) follows this file's paths.
SRC=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)

# What card() does after a review (afterreview(), lib/card.sh) on fixture state, with no card run: card c7's staged
# change in $FXWT (fx_wt), its review in $FXWT.review, <issue json> as card() holds it, and the state card() holds
# after its first review (pass 1: no carried rounds, rebase, test fix, lint fix, mode or privacy fix round) unless
# <before> changes it (pass=3, a fix round: told). <after> runs once it has decided, in the same shell. The outcome
# card() acts on is $AFTER: {res, after, last, stop, hard, last0, isfu, priv, why}; last is the one card() reads to
# land a last review with its follow-ups filed or declined. AFTERREVIEW, the call, also runs on the
# card that takes up kept work, after resumeplan (resumed, port.test.sh). Used by the cases of reviewback, fail and
# judge too (the runner loads every case file into one shell; .conveyor/test-links.json runs them when this file
# changes).
AFTERREVIEW='res=$(verdict "$wt.review"); afterreview
  jq -cn --arg res "$res" --arg after "$after" --arg last "$last" --arg stop "$stop" --arg hard "$hard" --arg last0 "$last0" --arg isfu "$isfu" --arg priv "$priv" --arg why "$why" \
    "{\$res, \$after, \$last, \$stop, \$hard, \$last0, \$isfu, \$priv, \$why}" > "$T/$CASE/after.json" || exit 3'
# The state card() holds at its first review that AFTERREVIEW reads, apart from what resumeplan sets (mode, rounds,
# fin, finend).
FIRSTPASS='pass=1 finrev="" earlier="" rebased="" tfix="" lfix="" privfix="" p1fix="" isfu="" why=""'
afterrun() { # <issue json> [<before>] [<after>]
  rm -f "$T/$CASE/after.json"
  ISSUE=$1 fx_in 'wt=$FXWT issue=$ISSUE mode="" rounds=0 fin="" finend="{}"; '"$FIRSTPASS"'
    '"${2:-}"'
    '"$AFTERREVIEW"'
    '"${3:-}"
  AFTER=$(cat "$T/$CASE/after.json" 2>/dev/null)
  [ "$RC" = 0 ] && [ -n "$AFTER" ] || fail "afterreview could not be called, or the commands around it failed: $(cat "$T/$CASE/run.out")"
}
# Fix round <round> of card c7 ($FXWT) as card() records it, in afterrun's <before>: the findings of its review with
# their ids (donewhen.sh numbered()), its fix <change> made and staged, and the round's findings and diff kept (donewhen.sh rounded()), which
# the review after it reads (donewhen.sh repeats()).
told() { # <round> <change>
  local ids old w=$FXWT
  ids=$(numbered "$w") && old=$(git -C "$w" write-tree) && (cd "$w" && eval "$2") && git -C "$w" add -A && mkdir -p "$w.rounds" \
    && git -C "$w" diff "$old" "$(git -C "$w" write-tree)" > "$w.rounds/$1.diff" && rounded "$w" "$1" "$ids"
}

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
  # loop: each review's line (its tail, counts, excerpts and reason) is written in cardreview(), and the fix sessions' flags are session()'s: afterreview gives neither
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

# Bug it catches: a last review whose NO-GO holds an UNPROVEN line and no finding (it ends the loop before its
# nofinding check, afterreview()) blocked the card with no word of what the reviewer said. The block reason the filing
# gives (followups(); cardland() gives the same one for a follow-up at the depth cap, nofiling(): t_capnogounproven)
# quotes that line.
t_lastnogounproven() {
  setup "[$(issue 7 2026-01-01)]"
  printf '%s\n' 'UNPROVEN: b.txt may be read before it is written' 'USER-VISIBLE: no' 'VERDICT: NO-GO' > "$STUB/r.review"
  fx_in 'followups c1-7 "$(jq -c ".[0]" "$STUB/issues.json")" "$STUB/r.review"'
  [ "$RC" != 0 ] && [ "$(cat "$T/$CASE/run.out")" = 'the last review said NO-GO and named no finding to file: UNPROVEN: b.txt may be read before it is written' ] \
    && [ ! -e "$STUB/filed" ] || fail "a last NO-GO with only an UNPROVEN line did not block with that line (exit $RC): $(cat "$T/$CASE/run.out")"
}

# Bug it catches: a card whose issue is a follow-up at the depth cap (isfu) files nothing, so cardland() blocks a last
# NO-GO with no finding itself; that block said "named no finding to file" with no word of the reviewer's UNPROVEN line.
t_capnogounproven() {
  setup "[$(issue 7 2026-01-01 conveyor-followup bug P1 | jq -c '.body = "Follow-up to #5.\n\nFollow-up depth: 2"')]"
  fx_wt 'echo two >> a.txt' b.txt base
  printf '%s\n' 'UNPROVEN: b.txt may be read before it is written' 'USER-VISIBLE: no' 'VERDICT: NO-GO' > "$FXWT.review"
  fx_in 'releasewait() { :; }; landwait() { :; }
    c=c7 n=7 wt=$FXWT issue=$(jq -c ".[0]" "$STUB/issues.json") last=1 isfu=1 res=NO-GO merged="" earlier="" br="" mates=(); cardland'
  [ "$(st 'select(.issue == 7 and .step == "blocked") | .reason')" = 'the last review said NO-GO and named no finding to file: UNPROVEN: b.txt may be read before it is written' ] \
    && [ ! -e "$STUB/filed" ] || fail "a last NO-GO at the depth cap with only an UNPROVEN line did not block with that line (exit $RC): $(st 'select(.issue == 7)') $(cat "$T/$CASE/run.out")"
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
  # That review as the card's first goes to a fix round, whose brief (fixprompt() of the findings with their ids,
  # donewhen.sh fixlines(), as card() gives it to session()) has the proven finding, with its id, under the same-mistake instruction.
  fx_wt 'echo two >> a.txt' b.txt base; cp "$STUB/r.review" "$FXWT.review"
  afterrun "$(jq -c '.[0]' "$STUB/issues.json")" '' 'fixprompt "" "$(fixlines "$wt" "$(numbered "$wt")")" > "$T/$CASE/fix"'
  [ "$AFTER" = '{"res":"NO-GO","after":"fix","last":"","stop":"","hard":"","last0":"","isfu":"","priv":"","why":""}' ] || fail "a proven finding beside a GO on the first review did not go to a fix round: $AFTER"
  grep -qx '# Reviewer findings: fix these findings, and every other place in this change that makes the same mistake; nothing else' "$T/$CASE/fix" \
    && grep -qxF "E1 $F" "$T/$CASE/fix" \
    || fail "the fix session's brief lacks the same-mistake instruction or the proven finding: $(grep -n -e '^# Reviewer findings' -e 'wrong word' "$T/$CASE/fix")"
}

# Bug (#1020): a NO-GO with no finding, only an UNPROVEN line, blocked with "the engine could not give the review's
# findings their ids", which says nothing of what the reviewer said. It blocks with that line, and starts no fix session.
t_nogounproven() {
  setup "[$(issue 7 2026-01-03)]"
  U="UNPROVEN: the sandbox could not start git diff $(printf 'x%.0s' {1..300})"
  printf '%s\n' "$U" 'USER-VISIBLE: no' 'VERDICT: NO-GO' > "$STUB/review.1"
  # loop: the block is made in cardfix() (card.sh) after the review, which no engine function returns alone.
  loop run --only 7 >/dev/null
  [ "$(wc -l < "$STUB/sessions")" = 1 ] || fail "a fix session was started for a NO-GO with no finding: $(cat "$STUB/sessions")"
  [ "$(st 'select(.step == "blocked") | .reason')" = "review 1 is NO-GO with no finding to fix: ${U:0:200}" ] \
    || fail "the block does not quote the review's UNPROVEN line: $(st 'select(.step == "blocked") | .reason')"
  # Bug (#1436): the guide's list of how the fix loop ends had no block for a NO-GO with no finding; the run above blocked on review 1.
  pagesays_review docs/cards.md 'review <n> is NO-GO with no finding to fix:' "the card blocked with: $(st 'select(.step == "blocked") | .reason' | cut -c1-80)"
  pagesays_review docs/cards.md 'blocks the card when none of the reasons above ends the loop at that review' "a NO-GO of an unproven line alone blocked the card"
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
  # The last review holds no P0 and no P1 (a P1 gets its own fix round first: t_p1lastnew), so its findings are filed.
  setup "[$(issue 7 2026-01-01)]"; for i in 1 2; do moved $i "$NOGO3" > "$STUB/review.$i"; done; n3=${NOGO3/\[P0\]/[P2]}; echo "${n3/b.txt:22/[P2] b.txt:22}" > "$STUB/review.3"; head=$(git -C "$R" rev-parse HEAD)
  echo '[ "$n" != 100102 ] || { echo "could not add label" >&2; exit 1; }' > "$STUB/create-cmd"
  # loop: only a whole card run files a last review's findings, then withdraws them when a filing fails
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
  [ "$(cat "$k"/*.withdrawn)" = '#100101 [P2] a.txt:1 wrong word' ] && grep -q -- '--reason not planned --comment .*#7 ' "$STUB/close-comments" \
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
# Bug: afterreview() does not join privown() to the fix round: a last-review privacy hit on a line the card added is
# filed as a follow-up (landing the hit on main) or blocks the card as a last P0, or its fix round is not given, or
# that round is not told the hit. The third review (the last) of a card whose change adds the line.
t_privfixrun() {
  setup "[$(issue 7 2026-01-01)]"; fx_wt "printf 'two\ncd %s/bench\n' '$HX' >> a.txt" b.txt base
  printf '%s\n' "[P0] a.txt:3 flags $HX/bench" 'USER-VISIBLE: no' 'VERDICT: NO-GO' > "$FXWT.review"
  afterrun "$(issue 7 2026-01-01)" 'pass=3' 'fixlines "$wt" "$(numbered "$wt")" > "$T/$CASE/fix"'
  [ "$AFTER" = "$(jq -cn --arg p "[P0] a.txt:3 flags $HX/bench" '{res: "NO-GO", after: "fix", last: "", stop: "", hard: "", last0: "", isfu: "", priv: $p, why: ""}')" ] \
    || fail "the privacy finding on the card's own line on its last review did not go to a fix round: $AFTER"
  grep -qxF "E1 [P0] a.txt:3 flags $HX/bench" "$T/$CASE/fix" || fail "the fix round is not told the privacy finding: $(cat "$T/$CASE/fix")"
}
# Bug (#1502): privwords() fails when the host file names a terms file that cannot be read, and privown() took that
# for "the check could not be made" and found nothing: the privacy gate of the card's own change was off for a home path.
# It still finds the built-in hit now, with a terms file that is missing.
t_privownterms() {
  setup "[$(issue 7 2026-01-01)]"; mkdir -p "$XDG_CONFIG_HOME/conveyor"
  jq -n --arg t "$STUB/none" '{terms: $t}' > "$XDG_CONFIG_HOME/conveyor/host.json"
  fx_wt "printf 'two\ncd %s/bench\n' '$HX' >> a.txt" b.txt b
  printf '%s\n' "[P0] a.txt:3 flags $HX/bench" 'USER-VISIBLE: no' 'VERDICT: NO-GO' > "$FXWT.review"
  fx_in 'privown "$FXWT"'
  [ "$RC" = 0 ] && [ "$(cat "$T/$CASE/run.out")" = "[P0] a.txt:3 flags $HX/bench" ] \
    || fail "privown with a host file naming a missing terms file ($STUB/none) did not find the home path the card adds (exit $RC): $(cat "$T/$CASE/run.out")"
}
# Bug (#1502): the same with a terms file that passes the readable test but cannot be opened (a socket). The built-in
# check was handed that file again and failed again, so privown() found nothing: it must not use the terms file at all.
t_privownsocket() {
  setup "[$(issue 7 2026-01-01)]"; mkdir -p "$XDG_CONFIG_HOME/conveyor"
  python3 -c 'import socket,sys; socket.socket(socket.AF_UNIX).bind(sys.argv[1])' "$T/$CASE/sock" || fail "no socket made"
  jq -n --arg t "$T/$CASE/sock" '{terms: $t}' > "$XDG_CONFIG_HOME/conveyor/host.json"
  fx_wt "printf 'two\ncd %s/bench\n' '$HX' >> a.txt" b.txt b
  printf '%s\n' "[P0] a.txt:3 flags $HX/bench" 'USER-VISIBLE: no' 'VERDICT: NO-GO' > "$FXWT.review"
  fx_in 'privown "$FXWT"'
  [ "$RC" = 0 ] && [ "$(cat "$T/$CASE/run.out")" = "[P0] a.txt:3 flags $HX/bench" ] \
    || fail "privown with a host file naming a terms file that cannot be opened ($T/$CASE/sock) did not find the home path the card adds (exit $RC): $(cat "$T/$CASE/run.out")"
}
# Issue 1670: a privacy hit in the card's own change on a last review gets fix sessions until a last review finds none,
# then the card lands: here the hit ($HY, a home path the change adds) takes two. Review 3 names it: fix session 1
# leaves it; review 4 names it again: fix session 2 takes the line out; review 5 holds a P2 alone: the card goes on to
# land (go ''). cardfix() runs as card() runs it, the session replaced. Bugs: the hit found again after the first fix
# session blocked the card for the owner; privown() was not asked again after it (#1385), so a hit landed with a follow-up.
t_privfixagain() {
  local HY=/hom"e"/y # a home path, put together as HX is
  setup "[$(issue 7 2026-01-01)]"; fx_wt "printf 'two\ncd %s/bench\n' '$HY' >> a.txt" b.txt base
  printf '%s\n' "[P2] a.txt:3 flags $HY/bench" 'USER-VISIBLE: no' 'VERDICT: NO-GO' > "$FXWT.review"
  ISSUE=$(issue 7 2026-01-01) fx_in 'wt=$FXWT issue=$ISSUE mode="" rounds=0 fin="" finend="{}" c=c7 n=7 rline="" fixed=0 sprompt="" br="" go=end; '"$FIRSTPASS"'; privfix=0
    block() { printf "%s\n" "$4" >> "$T/$CASE/blocked"; }; checked() { :; }
    session() { [ "$fixed" = 0 ] || sed -i "/bench/d" "$1/a.txt"; }
    for pass in 3 4 5; do
      [ "$pass" != 5 ] || printf "%s\n" "[P2] c.txt:3 a nit" "USER-VISIBLE: no" "VERDICT: NO-GO" > "$wt.review"
      res=$(verdict "$wt.review"); go=end; cardfix; echo "$pass $after [$go] $privfix" >> "$T/$CASE/after"
    done'
  [ "$RC" = 0 ] && [ "$(cat "$T/$CASE/after" 2>/dev/null)" = $'3 fix [next] 1\n4 fix [next] 2\n5 last [] 2' ] && [ ! -e "$T/$CASE/blocked" ] \
    || fail "a privacy hit (review: [P2] a.txt:3 flags \$HY/bench) that a second fix session takes out did not get two fix sessions and then land: $(cat "$T/$CASE/after" "$T/$CASE/blocked" "$T/$CASE/run.out" 2>&1)"
  # Bug (#1436): the guide said a card has at most three reviews, but a fourth review follows the privacy fix round.
  pagesays_review docs/cards.md 'at most three times, once more after each fix of a privacy hit on the last review' "review 4 and 5 came after the privacy fixes: $(cat "$T/$CASE/after")"
}
# Issue 1670: a privacy hit still there after PRIVFIXES (3) fix sessions shuts the card with its work kept and puts
# the hit on the self-heals list as a possible false hit of the privacy check: no Needs you entry, nothing landed.
# cardfix() runs as card() runs it, from the first last review (3) with no privacy round given, the session replaced
# by one that leaves the hit; block() and shut() are real. Bugs it catches: the card blocked and waited for the owner;
# it was shut after fewer than 3 fix sessions; review 6, which holds the hit and a new P1, gave the P1 a fix round and
# so the hit a fourth one; needsask(), the job that runs beside the card, read the block before the shut (the lock
# taken for shut() runs it here first) and put the card to the owner; the closed line said the owner shut it.
t_privshut() {
  local HY=/hom"e"/y # a home path, put together as HX is
  setup "[$(issue 7 2026-01-01)]"; fx_wt "printf 'two\ncd %s/bench\n' '$HY' >> a.txt" b.txt base
  printf '%s\n' "[P2] a.txt:3 flags $HY/bench" 'USER-VISIBLE: no' 'VERDICT: NO-GO' > "$FXWT.review"
  kline c7 7 picked ok >> "$ST/cards.jsonl"; export CONVEYOR_LEDGER=$T/$CASE/decisions.jsonl
  ISSUE=$(issue 7 2026-01-01) fx_in 'wt=$FXWT issue=$ISSUE mode="" rounds=0 fin="" finend="{}" c=c7 n=7 rline="" fixed=0 sprompt="" br="" go=end; '"$FIRSTPASS"'; privfix=0
    checked() { :; }; session() { :; }
    eval "real$(declare -f locked)"; locked() { [ "$1" != shut ] || needsask; reallocked "$@"; }
    for pass in 3 4 5 6; do
      [ "$pass" != 6 ] || printf "%s\n" "[P2] a.txt:3 flags $HY/bench" "[P1] c.txt:9 drops what the issue asks" "USER-VISIBLE: no" "VERDICT: NO-GO" > "$wt.review"
      res=$(verdict "$wt.review"); go=end; cardfix; echo "$pass $after [$go] $privfix" >> "$T/$CASE/after"
    done'
  [ "$RC" = 0 ] && [ "$(cat "$T/$CASE/after" 2>/dev/null)" = $'3 fix [next] 1\n4 fix [next] 2\n5 fix [next] 3\n6 priv [end] 3' ] \
    || fail "a privacy hit that no fix session takes out (review: [P2] a.txt:3 flags \$HY/bench; review 6 adds [P1] c.txt:9) did not get exactly 3 fix sessions and then shut the card: $(cat "$T/$CASE/after" "$T/$CASE/run.out" 2>&1)"
  [ "$(st 'select(.card == "c7") | .step' | tail -n 1)" = closed ] && [ "$(st 'select(.card == "c7" and .step == "closed") | .reason')" = 'shut by the engine' ] \
    && st 'select(.card == "c7" and .step == "blocked") | .reason' | grep -qF "after its 3 fix rounds: review 6 still holds it, so the card is shut with its work kept" \
    && grep -qF bench "$ST/kept/c7/c7.patch" || fail "the card (review 6: [P2] a.txt:3 flags \$HY/bench) did not end shut by the engine with its patch kept: $(st 'select(.card == "c7")') $(ls "$ST/kept/c7" 2>&1)"
  [ "$(jq -c 'select(.card == "c7") | [.issue, .effect, .finding, (.why | startswith("a possible false hit of the privacy check"))]' "$ST/selfheals.jsonl" 2>&1)" = "[7,\"self-heals\",\"[P2] a.txt:3 flags $HY/bench\",true]" ] \
    || fail "the hit (review 6: [P2] a.txt:3 flags \$HY/bench) is not on the self-heals list as a possible false hit: $(cat "$ST/selfheals.jsonl" 2>&1)"
  ! grep -qF '"blocked-c7"' "$CONVEYOR_LEDGER" 2>/dev/null && [ "$(loop snapshot --fresh | jq -c '[.needsYou.blocked[], .needsYou.waiting[]] | map(.issue)')" = '[]' ] \
    || fail "the shut card (review 6: [P2] a.txt:3 flags \$HY/bench) is in Needs you, or needsask() put it to the owner before the shut: $(cat "$CONVEYOR_LEDGER" 2>&1) $(loop snapshot --fresh | jq -c .needsYou)"
}

# Bug: a P1 that is new in a last review (the fix-only review after its one fix round finds another, not the one fixed,
# so repeats() does not see it) landed as a follow-up. The first last review with a P1 goes to a fix round (after fix, no
# stop); once that round is given (p1fix) a last review that holds a P1 lands with it as a follow-up (issue 1670: it
# blocked), as one with only a P2 does.
t_p1lastnew() {
  setup "[$(issue 7 2026-01-01)]"; fx_wt 'echo fix1 >> a.txt' b.txt base
  printf '%s\n' '[P1] a.txt:3 drops what the issue asks' '[P2] c.txt:3 a nit' 'USER-VISIBLE: no' 'VERDICT: NO-GO' > "$FXWT.review"
  afterrun "$(issue 7 2026-01-01)" 'pass=3'
  [ "$(jq -c '[.after, .stop, .last]' <<<"$AFTER")" = '["fix","",""]' ] || fail "a new P1 on the last review did not go to one fix round: $AFTER"
  afterrun "$(issue 7 2026-01-01)" 'pass=4 p1fix=1'
  [ "$(jq -c '[.after, .stop, .last]' <<<"$AFTER")" = '["last","max-reviews","1"]' ] || fail "a new P1 after the P1 fix round (review 4: [P1] a.txt:3 drops what the issue asks) did not land: $AFTER"
  printf '%s\n' '[P2] c.txt:3 a nit' 'USER-VISIBLE: no' 'VERDICT: NO-GO' > "$FXWT.review"
  afterrun "$(issue 7 2026-01-01)" 'pass=4 p1fix=1'
  [ "$(jq -c '[.after, .stop, .last]' <<<"$AFTER")" = '["last","max-reviews","1"]' ] || fail "a last review with only a P2 after the P1 fix round did not land: $AFTER"
}

# Issue 1670: a third review (the last) that says NO-GO with a P0 lands the card: cardfix() writes no blocked line and
# goes on to land (go ''), with no P1 fix round first, and the card files each finding as a follow-up, the P0 too
# (followups(), as card() calls it). A finding the judge declined (its DECLINED line) is not filed. Bugs: the card
# blocked for the owner on the P0 ("review 3 is the last review and still holds a P0 finding") and filed nothing; a
# declined finding was filed.
t_lastp0() {
  setup "[$(issue 7 2026-01-01)]"; fx_wt 'echo fix1 >> a.txt' b.txt base
  printf '%s\n' '[P0] a.txt:3 drops the payment' '[P2] c.txt:3 a nit' 'DECLINED: [P1] b.txt:1 a matter of taste (judge: no defect)' 'USER-VISIBLE: no' 'VERDICT: NO-GO' > "$FXWT.review"
  afterrun "$(issue 7 2026-01-01)" 'pass=3' 'c=c7 n=7 rline=""; cardfix; echo "[$go]" > "$T/$CASE/go"
    [ "$after" != last ] || [ -n "$isfu" ] || followups c7 "$issue" "$wt.review" > "$T/$CASE/ups"'
  [ "$AFTER" = '{"res":"NO-GO","after":"last","last":"1","stop":"max-reviews","hard":"","last0":"[P0] a.txt:3 drops the payment","isfu":"","priv":"","why":""}' ] \
    && [ "$(cat "$T/$CASE/go" 2>&1)" = '[]' ] && [ -z "$(st 'select(.step == "blocked")' 2>/dev/null)" ] \
    || fail "a last NO-GO with a P0 (review 3: [P0] a.txt:3 drops the payment) did not go on to land: $AFTER go $(cat "$T/$CASE/go" 2>&1) $(st 'select(.step == "blocked")' 2>&1)"
  [ "$(cat "$T/$CASE/ups" 2>&1)" = '[100101,100102]' ] && [ "$(jq -r .title "$STUB/filed" | tr '\n' '|')" = '[P0] a.txt:3 drops the payment|[P2] c.txt:3 a nit|' ] \
    || fail "the last review's P0 and P2 were not filed as follow-ups, or its declined [P1] b.txt:1 was: $(cat "$T/$CASE/ups" "$STUB/filed" 2>&1)"
}

# Bug (#1436): the guide gave one more review for the fix of a P1 or of a privacy hit, as if the two shared it. Each has its
# own fix round (privfix, p1fix): review 4, which follows a privacy fix round (privfix=1), holds a P1 that is no privacy
# hit, and it still goes to its own fix round (and a review 5), and does not land first.
t_privfixthenp1() {
  setup "[$(issue 7 2026-01-01)]"; fx_wt 'echo fix1 >> a.txt' b.txt base
  printf '%s\n' '[P1] a.txt:3 drops what the issue asks' 'USER-VISIBLE: no' 'VERDICT: NO-GO' > "$FXWT.review"
  afterrun "$(issue 7 2026-01-01)" 'pass=4 privfix=1'
  [ "$(jq -c '[.after, .stop, .last]' <<<"$AFTER")" = '["fix","",""]' ] || fail "a P1 on review 4, after a privacy fix round, did not go to its own fix round: $AFTER"
  pagesays_review docs/cards.md 'once more after each fix of a privacy hit on the last review and once more after the fix of a P1 on a last review' "review 4 held a P1 after the privacy fix and got a fix round: $AFTER"
}

# Bug: a follow-up chain goes past the cap: a card whose issue is a follow-up at the cap (MAX_DEPTH, 2) files another
# level on its last NO-GO, or its leftover finding is on no list, or its reason does not name the cap. Issue 1670: the
# finding went to the declined list, where nothing builds it; it goes on the self-heals list instead.
# Its last NO-GO is a P2 back after its one fix round (afterreview(): the last review, as a third NO-GO is), in two
# reviews; card() puts the findings of a card at the cap (isfu) on the self-heals list with capheals(), as called here.
t_deep() {
  setup "[$(issue 7 2026-01-01 conveyor-followup bug P1 | jq -c '.body = "Follow-up to #5.\n\nFollow-up depth: 2"')]"
  # The second review names a.txt:12, where the fix's one appended line moves a.txt:11 (donewhen.sh rounded()), so it is the same
  # finding back; its text differs from the first's, so the listed one is known to come from the last review.
  fx_wt 'echo two >> a.txt' b.txt base
  for i in 1 2; do printf '%s\n' "[P2] a.txt:1$i wrong word" 'USER-VISIBLE: no' 'VERDICT: NO-GO' > "$STUB/review.$i"; done; cp "$STUB/review.1" "$FXWT.review"
  afterrun "$(jq -c '.[0]' "$STUB/issues.json")" 'told 1 "echo two >> a.txt" && cp "$STUB/review.2" "$wt.review" && pass=2' \
    '[ -z "$isfu" ] || leftovers "$wt.review" | capheals c7 7 "$ISSUE"'
  [ "$AFTER" = '{"res":"NO-GO","after":"last","last":"1","stop":"repeat","hard":"","last0":"","isfu":"1","priv":"","why":""}' ] \
    || fail "a depth-2 card's last review did not land with its findings listed, not filed: $AFTER"
  [ "$(jq -c '[.issue, .finding, .effect, .why]' "$ST/selfheals.jsonl")" = '[7,"[P2] a.txt:12 wrong word","self-heals","its issue is a follow-up at the depth cap of 2, so no deeper follow-up is filed"]' ] \
    && [ ! -e "$ST/declined.jsonl" ] || fail "the depth-2 card's leftover finding is not on the self-heals list once, with why, and off the declined list: $(cat "$ST/selfheals.jsonl" "$ST/declined.jsonl" 2>&1)"
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

# Bug: a self-heals list that cannot be written (here a folder is in its place) loses the findings at the depth cap:
# capheals() says it wrote them, so the card ends as landed and clean, and its review goes with its worktree. On its failure (exit
# non-zero) the card ends blocked, its review kept (card.sh).
t_declinefail() {
  setup "[$(issue 7 2026-01-01)]"; mkdir -p "$ST/selfheals.jsonl"
  fx_in 'printf "%s\n" "[P1] a.txt:1 wrong word" | capheals c1-7 7 "$(jq -c ".[0]" "$STUB/issues.json")"'
  [ "$RC" != 0 ] && grep -q '^conveyor: card c1-7: its findings at the follow-up depth cap could not be written to ' "$T/$CASE/run.out" \
    || fail "a self-heals list that cannot be written did not fail capheals() saying so: exit $RC, $(cat "$T/$CASE/run.out")"
}
# Bug: card() ignores capheals()'s failure after the landing: the depth-capped card ends landed and clean, and its review
# goes with its worktree. A loop run: the landing, then capheals(), then the block that keeps the review are joined
# in cardland() (cardland.sh), which no engine function exposes alone.
t_declinefailrun() {
  # Its last NO-GO is a P2 back after its one fix round (the last review, as a third NO-GO is), in two reviews.
  setup "[$(issue 7 2026-01-01 conveyor-followup bug P1 | jq -c '.body = "Follow-up depth: 2"')]"; provenbug
  # Review 2 gives the same finding (its id mark, E1) in words of its own, so the review kept is shown to be the last
  # one: with the same words in both, a block that kept review 1 only passed.
  printf '%s\n' '[P2] a.txt:1 wrong word' 'USER-VISIBLE: no' 'VERDICT: NO-GO' > "$STUB/review.1"
  printf '%s\n' '[P2] [E1] a.txt:1 wrong word, seen again in review 2' 'USER-VISIBLE: no' 'VERDICT: NO-GO' > "$STUB/review.2"
  mkdir -p "$ST/selfheals.jsonl"
  # loop: the order of the landing, capheals() and the block that keeps the review is card()'s own, after afterreview
  loop run >/dev/null 2>&1 || fail "run exited non-zero"
  [ "$(st 'select(.step | IN("landed", "blocked")) | .step' | tr '\n' ' ')" = 'landed blocked ' ] \
    && st 'select(.step == "blocked") | .reason' | grep -q 'could not write its leftover findings to the self-heals list' || fail "a card whose findings could not be listed did not end landed, then blocked saying so: $(st 'select(.step | IN("landed", "blocked"))')"
  k=$ST/$(st 'select(.step == "blocked") | .kept'); grep -q 'seen again in review 2' "$k"/*.review || fail "the last review, of the findings that could not be listed, was not kept: $(ls "$k" 2>&1)"
}

# Bug it catches: cardreview() did not give judged() the tree before the last fix round (fixtree), so the judge's
# message after that fix lost the cited line the fix deleted (f2), though judgefindings() keeps it when given the tree.
# cardreview() is called in the state card() holds after fix round 1 (told(); refix and fixtree both set, as card()
# sets them), with the real judged(); the review session and the judge's call are stubbed, the judge's call keeping
# the message it is given.
t_judgedfixtree() {
  setup "[$(issue 17 2026-01-01)]"; fx_wt 'printf "%s\n" f1 f2 f3 > f.txt' b.txt base
  printf '%s\n' '[P1] f.txt:2 f2 is wrong' 'USER-VISIBLE: no' 'VERDICT: NO-GO' > "$FXWT.review"
  fx_in 'c=c7 n=17 wt=$FXWT br="" sprompt="" sf="" sk="" pk="" pt="" mode="" kept="" grown=1 fin="" vmode="" pass=2 rounds=0 rv=$REVIEW prv=""
    issue=$(jq -c ".[0]" "$STUB/issues.json"); fixtree=$(git -C "$wt" write-tree) && told 1 "printf \"%s\n\" f1 f3 > f.txt" && refix=1 || exit 3
    redbrief() { :; }; trialflag() { :; }; lintgate() { return 0; }; began() { :; }; reusable() { return 1; }; minor() { :; }; judgeon() { echo "[]"; }
    reviewed() { printf "%s\n" "[P1] f.txt:2 the fix deleted f2" "USER-VISIBLE: no" "VERDICT: NO-GO" > "$1.review"; printf "%s\n" "$2" > "$T/$CASE/brief"; echo "{}"; }
    judgecall() { printf "%s\n" "$3" > "$T/$CASE/judged"; echo "{\"failed\": \"stub\"}"; return 1; }
    cardreview'
  # The review was told about fix round 1 (rereview()), so the case ran the path card() takes after a fix round.
  [ "$RC" = 0 ] && grep -qF "$FXWT.rounds/1.diff" "$T/$CASE/brief" 2>/dev/null \
    || fail "the review after fix round 1 (refix=1) was not told that round, so the case missed card()'s path after a fix round (exit $RC): $(cat "$T/$CASE/run.out" 2>&1)"
  [ "$RC" = 0 ] && [ "$(grep -A3 -xF '  Lines at f.txt:2 (the code before the last fix round):' "$T/$CASE/judged" 2>/dev/null)" = '  Lines at f.txt:2 (the code before the last fix round):
    1: f1
    2: f2
    3: f3' ] || fail "the judge's message after fix round 1 (review: [P1] f.txt:2 the fix deleted f2) lost the lines before that fix (exit $RC): $(cat "$T/$CASE/judged" "$T/$CASE/run.out" 2>&1)"
}
