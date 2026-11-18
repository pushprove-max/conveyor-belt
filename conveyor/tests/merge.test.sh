#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 300
# Engine cases: the three-way merge at landing and at the same-file claim, and documentation files at the claim.
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"
# The engine folder, as lib.sh sets it: named here too, so the release closure (tools/closure.sh) follows this file's paths.
SRC=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)

# Main's a.txt as nine lines, l1 to l9: a change to l4 and one to l6 leave l5 between them, so neither applies plainly
# on the other (each one's context holds the other's line) and they merge three-way with no conflict.
nine() { seq 9 | sed 's/^/l/' > "$R/a.txt"; git -C "$R" commit -qam "a.txt of nine lines"; }

# Bug (the owner, 2026-11-13: 24 rebuild sessions in a day): a card whose change no longer applied plainly to a main
# that moved went to a rebuild session, a new review and its tests again, though main changed other lines of the file.
# #7 changes l4; during its tests main changes l6. Its change merges three-way onto main with no conflict: it lands with
# no rebuild session, no second review and no second test run, both lines in main.
t_mergeclean() {
  setup "[$(issue 7 2026-01-01)]"; echo "$GO" > "$STUB/review.1"; nine
  echo "sed -i 's/^l4\$/seven/' a.txt" > "$STUB/build"
  echo '[ -e "$STUB/moved" ] || { : > "$STUB/moved"; sed -i "s/^l6\$/main6/" "$R/a.txt"; git -C "$R" commit -qam "main moves"; }' >> "$STUB/test-cmd"
  out=$(loop run 2>&1) || fail "run exited non-zero: $out"
  [ -e "$STUB/moved" ] || fail "main did not move during the card's tests"
  [ -z "$(st 'select(.step | IN("rebase", "fix")) | .step')" ] && [ "$(wc -l < "$STUB/sessions")" = 1 ] \
    || fail "a session rebuilt the change though it merges three-way with no conflict: $(st '"\(.step) \(.reason)"' | tr '\n' ,)"
  [ "$(st "select(.issue == 7 and $NOMARK) | .step" | tr '\n' ' ')" = "picked worktree brief build review test test landed " ] \
    && [ "$(st 'select(.issue == 7 and .step == "test") | .reused // false' | tr '\n' ' ')" = "false true " ] \
    && [ "$(wc -l < "$STUB/reviews")" = 1 ] && [ "$(wc -l < "$STUB/tests")" = 1 ] \
    || fail "the merged change was reviewed or tested again: $(st "select(.issue == 7) | \"\(.step) \(.reused)\"" | tr '\n' ,)"
  [ "$(grep -cx 'seven\|main6' "$R/a.txt")" = 2 ] && [ -z "$(git -C "$R" status --porcelain)" ] \
    || fail "main does not hold both changes, or its checkout is dirty: $(cat "$R/a.txt")"
}

# The three-way merge is tried only to spare a rebuild: a change whose lines main changed too still goes to the
# rebuild session. #7 changes l4; during its tests main changes l4 too. The rebuild session brings #7 onto main, and it
# is reviewed and tested again.
t_mergeconflict() {
  setup "[$(issue 7 2026-01-01)]"; for i in 1 2; do echo "$GO" > "$STUB/review.$i"; done; nine
  echo "if grep -q '^# Landing conflict' \"\$STUB/brief\"; then sed -i 's/^main4\$/seven/' a.txt; else sed -i 's/^l4\$/seven/' a.txt; fi" > "$STUB/build"
  echo '[ -e "$STUB/moved" ] || { : > "$STUB/moved"; sed -i "s/^l4\$/main4/" "$R/a.txt"; git -C "$R" commit -qam "main moves"; }' >> "$STUB/test-cmd"
  out=$(loop run 2>&1) || fail "run exited non-zero: $out"
  st 'select(.issue == 7 and .step == "rebase") | .reason' | grep -q '^rebase onto main conflicts' \
    || fail "the conflicting change did not go to the rebuild session: $(st '"\(.step) \(.reason)"' | tr '\n' ,)"
  [ "$(wc -l < "$STUB/reviews")" = 2 ] && [ "$(wc -l < "$STUB/tests")" = 2 ] && [ "$(st 'select(.step == "landed") | .issue')" = 7 ] \
    && grep -qx seven "$R/a.txt" && ! grep -q main4 "$R/a.txt" || fail "the rebuilt change was not reviewed and tested again before it landed: $(cat "$R/a.txt")"
}

# Bug: two cards that changed different parts of one file waited one behind the other whenever their changes did not
# apply together plainly, though they merge three-way with no conflict. #7 changes l4 and #8 l6: both hold a.txt at
# once (#7's tests end only once #8 holds it, or after 30 s), and neither waits. #8's tests end only once #7 landed;
# #8 is then merged onto main with no session and no second review, on the tests it passed.
t_mergetogether() {
  setup "[$(issue 7 2026-01-01),$(issue 8 2026-01-02)]"; for i in 1 2 3; do echo "$GO" > "$STUB/review.$i"; done; nine
  cat > "$STUB/build" <<'EOF'
case $PWD in
  *-7) sed -i 's/^l4$/seven/' a.txt ;;
  *) while [ -d "$STUB" ]; do [ -e "$STUB/inreview.7" ] && break; sleep 0.1; done; sed -i 's/^l6$/eight/' a.txt ;;
esac
EOF
  cat > "$STUB/review-cmd" <<'EOF'
n=${PWD##*-}; : > "$STUB/inreview.$n"
[ "$n" = 7 ] || while [ -d "$STUB" ]; do jq -e .held ../*-7.claim >/dev/null 2>&1 && break; sleep 0.1; done
EOF
  cat >> "$STUB/test-cmd" <<'EOF'
case $PWD in
  *-7) i=0; while [ -d "$STUB" ] && [ $i -lt 300 ]; do jq -e .held ../*-8.claim >/dev/null 2>&1 && { cat ../*-7.claim ../*-8.claim > "$STUB/claims"; break; }; i=$((i + 1)); sleep 0.1; done ;;
  *) [ -e "$STUB/tested.8" ] || { : > "$STUB/tested.8"
    while [ -d "$STUB" ]; do jq -e 'select(.issue == 7 and .step == "landed")' "$ST/cards.jsonl" >/dev/null 2>&1 && break; sleep 0.1; done; } ;;
esac
EOF
  out=$(loop run 2>&1) || fail "run exited non-zero: $out"
  [ "$(jq -sc 'map([.held, .paths])' "$STUB/claims" 2>/dev/null)" = '[[true,["a.txt"]],[true,["a.txt"]]]' ] && ! grep -q "waits on card" <<<"$out" \
    || fail "#8 waited on #7, whose change merges with its own: $(cat "$STUB/claims" 2>/dev/null) $out"
  [ -z "$(st 'select(.step | IN("rebase", "fix")) | .step')" ] || fail "a session brought a change onto main though it merges: $(st '"\(.issue) \(.step) \(.reason)"' | tr '\n' ,)"
  [ "$(st "select(.issue == 8 and $NOMARK) | .step" | tr '\n' ' ')" = "picked worktree brief build review test test landed " ] \
    && [ "$(st 'select(.issue == 8 and .step == "test") | .reused // false' | tr '\n' ' ')" = "false true " ] \
    || fail "#8, merged onto main with #7's change, did not land on the tests it passed: $(st "select(.issue == 8) | \"\(.step) \(.reused)\"" | tr '\n' ,)"
  [ "$(st 'select(.step == "landed") | .issue' | tr '\n' ' ')" = "7 8 " ] && [ "$(grep -cx 'seven\|eight' "$R/a.txt")" = 2 ] && [ "$(wc -l < "$STUB/reviews")" = 2 ] \
    || fail "both did not land in turn with one review each: $(cat "$R/a.txt")"
}

# Bug (2026-11-13: three of six finished cards waited on another over README.md alone, one for 55 minutes): a
# documentation file shared by two cards made one wait for the other. #7 and #8 both rewrite README.md's one line, a
# conflict: neither waits, both holding their claims at once with no file named. #7 lands first; #8 meets the conflict
# at its landing, and its rebuild session resolves it, as any conflict at landing.
t_mergedocs() {
  setup "[$(issue 7 2026-01-01),$(issue 8 2026-01-02)]"; for i in 1 2 3; do echo "$GO" > "$STUB/review.$i"; done
  echo title > "$R/README.md"; git -C "$R" add README.md; git -C "$R" commit -qm "a README"
  cat > "$STUB/build" <<'EOF'
if grep -q '^# Landing conflict' "$STUB/brief"; then printf 'seven\neight\n' > README.md
else case $PWD in
  *-7) echo seven > README.md ;;
  *) while [ -d "$STUB" ]; do [ -e "$STUB/inreview.7" ] && break; sleep 0.1; done; echo eight > README.md ;;
esac; fi
EOF
  cat > "$STUB/review-cmd" <<'EOF'
n=${PWD##*-}; : > "$STUB/inreview.$n"
[ "$n" = 7 ] || [ -e "$STUB/tested.8" ] || while [ -d "$STUB" ]; do jq -e .held ../*-7.claim >/dev/null 2>&1 && break; sleep 0.1; done
EOF
  cat >> "$STUB/test-cmd" <<'EOF'
case $PWD in
  *-7) i=0; while [ -d "$STUB" ] && [ $i -lt 300 ]; do jq -e .held ../*-8.claim >/dev/null 2>&1 && { cat ../*-7.claim ../*-8.claim > "$STUB/claims"; break; }; i=$((i + 1)); sleep 0.1; done ;;
  *) [ -e "$STUB/tested.8" ] || { : > "$STUB/tested.8"
    while [ -d "$STUB" ]; do jq -e 'select(.issue == 7 and .step == "landed")' "$ST/cards.jsonl" >/dev/null 2>&1 && break; sleep 0.1; done; } ;;
esac
EOF
  out=$(loop run 2>&1) || fail "run exited non-zero: $out"
  [ "$(jq -sc 'map([.held, .paths])' "$STUB/claims" 2>/dev/null)" = '[[true,[]],[true,[]]]' ] && ! grep -q "waits on card" <<<"$out" \
    || fail "#8 waited on #7 over README.md alone: $(cat "$STUB/claims" 2>/dev/null) $out"
  st 'select(.issue == 8 and .step == "rebase") | .reason' | grep -q '^rebase onto main conflicts' \
    || fail "#8's conflict in README.md was not resolved by its rebuild session: $(st '"\(.issue) \(.step) \(.reason)"' | tr '\n' ,)"
  [ "$(st 'select(.step == "landed") | .issue' | tr '\n' ' ')" = "7 8 " ] && [ "$(tr '\n' ' ' < "$R/README.md")" = "seven eight " ] \
    || fail "both did not land in turn: $(cat "$R/README.md")"
}

# A three-way merge of a change main holds already is clean, and leaves no change: that is not the card's change. Two
# cards that make the same change, l4 to seven and a new b.txt, overlap (their merge would land the second as nothing),
# and once main holds that change the card is not ready. Bug too: git apply --cached --3way wrote the merged b.txt
# into the work tree, main's checkout, which then refused the landing of b.txt. The cards' change merges as the same
# change onto a main that changed l6 alone: ready.
t_mergesame() {
  setup '[]'; nine; CARDS=$T/$CASE/cards; mkdir -p "$CARDS"
  for n in 7 8; do
    git -C "$R" worktree add -q "$CARDS/c$n-$n" -b "card-$n" main
    sed -i 's/^l4$/seven/' "$CARDS/c$n-$n/a.txt"; echo bee > "$CARDS/c$n-$n/b.txt"; git -C "$CARDS/c$n-$n" add -A
  done
  git -C "$CARDS/c7-7" diff --cached --binary --no-renames > "$CARDS/c7-7.cpatch"; git -C "$CARDS/c8-8" diff --cached --binary --no-renames > "$CARDS/c8-8.cpatch.new"
  # ready() and together() as the engine has them, and what they call, run from main's checkout.
  eval "$(sed -n '/^together() {/,/^}/p; /^ready() {/,/^}/p; /^fits() {/,/^}/p; /^merge3() {/,/^}/p; /^cardpatch() {/p' "$SRC/lib/claim.sh")"
  sed -i 's/^l6$/main6/' "$R/a.txt"; git -C "$R" commit -qam "main changes l6" # the cards' change no longer applies plainly
  (cd "$R" && BRANCH=main ready "$CARDS/c7-7") || fail "a change that merges three-way onto main as the same change is not ready"
  a=$(cd "$R" && BRANCH=main together "$CARDS/c8-8.cpatch.new" '["a.txt","b.txt"]' '[{"card":"c7-7","paths":["a.txt","b.txt"]}]' "$(cardpatch "$CARDS/c8-8" ':(exclude)*.md')") \
    || fail "together() failed"
  [ "$a" = '[]' ] || fail "two cards that make the same change were taken to merge together: $a"
  [ ! -e "$R/b.txt" ] && [ -z "$(git -C "$R" status --porcelain)" ] || fail "the three-way merge wrote into main's checkout: $(git -C "$R" status --porcelain)"
  sed -i 's/^l4$/seven/' "$R/a.txt"; echo bee > "$R/b.txt"; git -C "$R" add -A; git -C "$R" commit -qm "main makes the cards' change"
  ! (cd "$R" && BRANCH=main ready "$CARDS/c7-7") || fail "a change main holds already was taken as merged onto it"
}

# A merge at landing. #7 (its issue has a `## Done when`) changes l4; during its review main changes l4 too, so at its
# landing claim one session brings #7 onto main (settle()). That session writes a.txt as the merged lines and then
# runs <its own edit> on it; its reply has no D<n> line. Each session's reply is $STUB/reply.<its number>.
mergedw() { # <the merge session's own edit>
  setup "[$(issue 7 2026-01-01 | jq -c '.body = "body of 7\n\n## Done when\n- l4 is seven"')]"; for i in 1 2; do echo "$GO" > "$STUB/review.$i"; done; nine
  cat > "$STUB/claude" <<'EOF'
#!/usr/bin/env bash
cat > "$STUB/brief"; echo "$*" >> "$STUB/sessions"; cp "$STUB/brief" "$STUB/brief.$(wc -l < "$STUB/sessions")"; . "$STUB/build"
jq -cn --rawfile r "$STUB/reply.$(wc -l < "$STUB/sessions")" '{type: "result", is_error: false, result: $r, usage: {input_tokens: 10, cache_creation_input_tokens: 20, cache_read_input_tokens: 999, output_tokens: 5}}'
EOF
  { echo "if grep -q '^# Main moved: apply the same change' \"\$STUB/brief\"; then printf '%s\n' l1 l2 l3 main4 seven l5 l6 l7 l8 l9 > a.txt; $1"
    echo "else sed -i 's/^l4\$/seven/' a.txt; fi"; } > "$STUB/build"
  echo '[ -e "$STUB/moved" ] || { : > "$STUB/moved"; sed -i "s/^l4\$/main4/" "$R/a.txt"; git -C "$R" commit -qam "main moves"; }' > "$STUB/review-cmd"
  printf 'Built.\n\n## Done when\nD1 met: a.txt:4 holds seven\n' > "$STUB/reply.1"; echo 'Merged.' > "$STUB/reply.2"
  printf 'Fixed.\n\n## Done when\nD1 met: a.txt:5 holds seven\n' > "$STUB/reply.3"
  out=$(loop run 2>&1) || fail "run exited non-zero: $out"
  grep -q '^# Main moved: apply the same change' "$STUB/brief.2" || fail "#7 was not brought onto main by a session at its landing claim: $(st '"\(.step) \(.reason)"' | tr '\n' ,)"
}

# Bug (#407 blocked, #305 lost 10.5 minutes): the merge session's reply went through the Done-when check, and a merge
# reply leaves out the D<n> lines, so the card was sent to a fix session and blocked. A merge that changed only the
# conflict is not checked: no Done-when fix session, and #7 is reviewed, tested and lands as merged.
t_mergedwconflict() {
  mergedw :
  [ "$(wc -l < "$STUB/sessions")" = 2 ] && [ -z "$(st 'select(.step == "blocked") | .reason')" ] \
    || fail "the merge that changed only the conflict was given the Done-when check: $(st '"\(.step) \(.reason) \(.doneWhen)"' | tr '\n' ,)"
  [ "$(st "select(.issue == 7 and $NOMARK) | .step" | tr '\n' ' ')" = "picked worktree brief build review fix review test landed " ] \
    && [ "$(st 'select(.step == "fix") | .doneWhen')" = null ] || fail "steps of #7: $(st "select(.issue == 7) | \"\(.step) \(.doneWhen)\"" | tr '\n' ,)"
  [ "$(grep -cx 'main4\|seven\|l8' "$R/a.txt")" = 3 ] || fail "main does not hold the merge: $(cat "$R/a.txt")"
}

# A merge session that also changes a line outside the conflict (l8) is checked as any fix session: its reply with no
# D<n> line is sent to one Done-when fix session, and #7 then goes through review and test before it lands.
t_mergedwoutside() {
  mergedw "sed -i 's/^l8\$/eight/' a.txt"
  [ "$(wc -l < "$STUB/sessions")" = 3 ] && grep -q '^# The Done-when check failed' "$STUB/brief.3" \
    || fail "the merge that changed a line outside the conflict was not given the Done-when check: $(st '"\(.step) \(.reason) \(.doneWhen)"' | tr '\n' ,)"
  [ "$(st "select(.issue == 7 and $NOMARK) | .step" | tr '\n' ' ')" = "picked worktree brief build review fix fix review test landed " ] \
    && [ "$(st 'select(.step == "fix") | .doneWhen.failed | length' | tr '\n' ' ')" = "1 0 " ] && [ "$(wc -l < "$STUB/reviews")" = 2 ] && [ "$(wc -l < "$STUB/tests")" = 1 ] \
    || fail "#7 did not go through its Done-when fix, review and test: $(st "select(.issue == 7) | \"\(.step) \(.doneWhen)\"" | tr '\n' ,)"
  grep -qx eight "$R/a.txt" || fail "main does not hold the session's change: $(cat "$R/a.txt")"
}

# Bug (review of #434): inconflicts() read only the `@@` lines of the diff, so a merge session that resolved the conflict
# and also changed the file's mode (`chmod a+x`) was taken to have changed only the conflict and skipped the check.
t_mergedwmode() {
  eval "$(sed -n '/^inconflicts() {/,/^}/p' "$SRC/lib/claim.sh")"
  local w=$T/$CASE/w mt
  mkdir -p "$w" && git -C "$w" init -q && printf '%s\n' l1 '<<<<<<< ours' main4 ======= seven '>>>>>>> theirs' l5 > "$w/a.txt"
  git -C "$w" add -A && mt=$(git -C "$w" write-tree) && printf '%s\n' l1 main4 seven l5 > "$w/a.txt" && git -C "$w" add -A
  inconflicts "$w" "$mt" a.txt || fail "a merge that changed only the conflict was taken to change more"
  chmod a+x "$w/a.txt"; git -C "$w" add -A
  ! inconflicts "$w" "$mt" a.txt || fail "a merge that also changed the file's mode was taken to change only the conflict"
}

# Main's test file a.test.sh, one case: two changes that each add a case at its end conflict in a three-way merge.
casefile() { echo case1 > "$R/a.test.sh"; git -C "$R" add a.test.sh; git -C "$R" commit -qm "a test file"; }

# Bug (#435: 5 of 11 landing clashes in a day): two cards that both add a case at the end of one test file clashed at
# landing, and the second went to a merge session. #7 and #8 each add a case; #8, made on main before #7 landed, meets
# #7's case at its landing: the test file is merged keeping both sides, with no session, and both cases land.
# Bug (#451: a union merge, which git calls clean, can leave a test file that no longer parses): the union-merged file
# is checked to parse (parses(), here through the pack's land.parse, which records each file it checks) before its
# tests run on it. What a file that fails the check leads to is t_mergeparseclean's.
t_mergetests() {
  setup "[$(issue 7 2026-01-01),$(issue 8 2026-01-02)]"; for i in 1 2; do echo "$GO" > "$STUB/review.$i"; done; casefile
  cat > "$STUB/build" <<'EOF'
case $PWD in
  *-7) while [ -d "$STUB" ]; do ls -d ../*-8 >/dev/null 2>&1 && break; sleep 0.1; done; echo case7 >> a.test.sh ;;
  *) while [ -d "$STUB" ]; do jq -e 'select(.issue == 7 and .step == "landed")' "$ST/cards.jsonl" >/dev/null 2>&1 && break; sleep 0.1; done; echo case8 >> a.test.sh ;;
esac
EOF
  echo "{ tr '\n' ' ' < \"\$1\"; echo; } >> '$STUB/parsed'; exec bash -n \"\$1\"" > "$STUB/parse"
  tune --arg c "sh $STUB/parse" '.land.parse = {"*.test.sh": $c}'
  echo '[ "$(tr "\n" " " < a.test.sh)" != "case1 case7 case8 " ] || grep -qx "case1 case7 case8 " "$STUB/parsed" 2>/dev/null || : > "$STUB/unparsed"' >> "$STUB/test-cmd"
  out=$(loop run 2>&1) || fail "run exited non-zero: $out"
  grep -qx 'case1 case7 case8 ' "$STUB/parsed" 2>/dev/null && [ ! -e "$STUB/unparsed" ] \
    || fail "the union-merged test file was not checked to parse before its tests ran: $(cat "$STUB/parsed" 2>/dev/null)"
  [ "$(wc -l < "$STUB/sessions")" = 2 ] && [ -z "$(st 'select(.step | IN("rebase", "fix", "blocked")) | .step')" ] \
    || fail "a session merged the two cards' cases: $(st '"\(.issue) \(.step) \(.reason)"' | tr '\n' ,)"
  [ "$(st 'select(.step == "landed") | .issue' | tr '\n' ' ')" = "7 8 " ] && [ "$(tr '\n' ' ' < "$R/a.test.sh")" = "case1 case7 case8 " ] \
    && [ -z "$(git -C "$R" status --porcelain)" ] || fail "both cases did not land, in turn: $(cat "$R/a.test.sh")"
}

# The merged test file is run before the card lands, though the card's own lines are the ones that passed: two cases
# kept side by side may not work together. #7 adds a case; during its tests main adds one too. The merged file holds
# both and its run fails: #7 goes to its fix, and lands after it with both cases.
t_mergetestsrun() {
  setup "[$(issue 7 2026-01-01)]"; for i in 1 2; do echo "$GO" > "$STUB/review.$i"; done; casefile
  echo "if grep -q '^# The changed tests fail' \"\$STUB/brief\"; then echo fixed >> a.test.sh; else echo case7 >> a.test.sh; fi" > "$STUB/build"
  # The failed run writes the runner's log naming its file: one that names only the test command is no result (voidrun()).
  cat >> "$STUB/test-cmd" <<'EOF'
[ -e "$STUB/moved" ] || { : > "$STUB/moved"; echo main-case >> "$R/a.test.sh"; git -C "$R" commit -qam "main adds a case"; }
! { grep -qx main-case a.test.sh && grep -qx case7 a.test.sh && ! grep -qx fixed a.test.sh; } || { cp a.test.sh "$STUB/merged"; echo "FAIL a.test.sh: the two cases clash"; printf "%s\n" "== a.test.sh" "-- FAIL a.test.sh" >> "$CONVEYOR_TEST_LOG/run.log"; exit 1; }
EOF
  out=$(loop run 2>&1) || fail "run exited non-zero: $out"
  [ "$(tr '\n' ' ' < "$STUB/merged" 2>/dev/null)" = "case1 main-case case7 " ] \
    || fail "the merged test file was not run before the card landed: $(st 'select(.step == "test") | "\(.result) \(.reused)"' | tr '\n' ,)"
  [ "$(st 'select(.issue == 7 and .step == "test") | .result' | tr '\n' ' ')" = "pass fail pass " ] && [ "$(wc -l < "$STUB/sessions")" = 2 ] \
    && grep -q '^# The changed tests fail' "$STUB/brief" && [ "$(st 'select(.step == "landed") | .issue')" = 7 ] \
    || fail "the failed run of the merged file did not send #7 to its fix, then land: $(st '"\(.step) \(.result) \(.reason)"' | tr '\n' ,)"
  [ "$(tr '\n' ' ' < "$R/a.test.sh")" = "case1 main-case case7 fixed " ] || fail "main does not hold both cases and the fix: $(cat "$R/a.test.sh")"
}

# Bug (#334: two cards that each added a row to one panel passed their tests alone, and its test file failed on main
# once both landed): a card whose change still applied to a main that moved landed on the tests it passed before, though
# the card landed meanwhile touched a test file of its own. #7 changes lib/panel.sh and #8 lib/rows.sh, both tested by
# lib/view.test.sh, which fails with both changes. No name or map links that file to them: only the project's test
# command selects it, so the shared file is found from what each card's run ran (its log), not from testsel(). #8's
# tests pass before #7 lands; at its landing that test file runs again on main with #7's change, fails, and #8 goes to
# its fix: it does not land red.
t_mergesharedtests() {
  setup "[$(issue 7 2026-01-01),$(issue 8 2026-01-02)]"; for i in 1 2 3 4; do echo "$GO" > "$STUB/review.$i"; done
  mkdir -p "$R/lib"; echo panel > "$R/lib/panel.sh"; echo rows > "$R/lib/rows.sh"; echo case1 > "$R/lib/view.test.sh"
  git -C "$R" add lib; git -C "$R" commit -qm "a panel, its rows and their test"
  cat > "$STUB/build" <<'EOF'
case $PWD in
  *-7) echo seven >> lib/panel.sh ;;
  *) if grep -q '^# The changed tests fail' "$STUB/brief"; then echo fixed >> lib/rows.sh; else echo eight >> lib/rows.sh; fi ;;
esac
EOF
  # #8's first run ends only once #7 landed. The run fails, naming the test file, on both changes with no fix. As the
  # project's own command does, it skips the file when its list (CONVEYOR_TEST_RERUN) names it passed and not failed:
  # #7's change does not select it, so a run again that kept its pass would pass without running it.
  cat >> "$STUB/test-cmd" <<'EOF'
case $PWD in *-8) [ -e "$STUB/tested.8" ] || { : > "$STUB/tested.8"
  while [ -d "$STUB" ]; do jq -e 'select(.issue == 7 and .step == "landed")' "$ST/cards.jsonl" >/dev/null 2>&1 && break; sleep 0.1; done; } ;; esac
! grep -qx "pass	lib/view.test.sh" "${CONVEYOR_TEST_RERUN:-/dev/null}" || grep -qx "fail	lib/view.test.sh.*" "$CONVEYOR_TEST_RERUN" || exit 0
echo "== lib/view.test.sh"; printf "%s\n" "== lib/view.test.sh" >> "$CONVEYOR_TEST_LOG/run.log"
! { grep -qx seven lib/panel.sh && grep -qx eight lib/rows.sh && ! grep -qx fixed lib/rows.sh; } \
  || { echo "FAIL lib/view.test.sh: the two rows clash"; echo "-- FAIL lib/view.test.sh" >> "$CONVEYOR_TEST_LOG/run.log"; exit 1; }
printf "%s\n" "-- ok lib/view.test.sh" "TESTRUN sec	lib/view.test.sh	1	1" >> "$CONVEYOR_TEST_LOG/run.log"
EOF
  out=$(loop run 2>&1) || fail "run exited non-zero: $out"
  grep -q 'card .*-8: cards landed since its tests ran touch its test files too.*lib/view.test.sh' <<<"$out" \
    && [ "$(st 'select(.issue == 8 and .step == "test") | .result' | tr '\n' ' ')" = "pass fail pass " ] \
    || fail "#8 landed on the tests it passed before #7 landed, not run again with #7's change: $(st 'select(.issue == 8) | "\(.step) \(.result) \(.reason)"' | tr '\n' ,)"
  grep -q '^# The changed tests fail' "$STUB/brief" && [ "$(st 'select(.step == "landed") | .issue' | tr '\n' ' ')" = "7 8 " ] \
    && [ "$(tr '\n' ' ' < "$R/lib/rows.sh")" = "rows eight fixed " ] \
    || fail "#8's failure on the combined code did not go to its fix before it landed: $(cat "$R/lib/rows.sh")"
}

# Bug (#451: #415's merge, which git called clean, left a test file with two openings and one end, and only its test
# step, minutes later, found the file no longer parsed; a broken file that no selected test loads would have landed).
# A clean three-way merge: a.test.mjs holds a test turned off in a block comment; #7 rewrites a line inside it to open a
# test of its own (still a comment: #7's file parses), and during its tests main turns the old test back on (main's
# file parses). Their lines are apart, so the three-way merge is clean with #7's lines as they were (settle()'s clean
# path, no session), and it leaves two openings and one end. The parse check finds it before any test runs on it, and
# #7's fix session is given the file and node's SyntaxError; #7 lands after it with a file that parses.
t_mergeparseclean() {
  setup "[$(issue 7 2026-01-01)]"; for i in 1 2; do echo "$GO" > "$STUB/review.$i"; done
  printf '%s\n' "import test from 'node:test';" '/* off until a() is fixed' "test('one', () => {" '  a();' '  b();' '});' '*/' > "$R/a.test.mjs"
  git -C "$R" add a.test.mjs; git -C "$R" commit -qm "a test file"
  cat > "$STUB/build" <<'EOF'
if grep -q '^# A file no longer parses' "$STUB/brief"; then cp "$STUB/brief" "$STUB/parsebrief"; sed -i '2d' a.test.mjs
else sed -i "4s/.*/test('one, by the card', () => {/" a.test.mjs; fi
EOF
  cat >> "$STUB/test-cmd" <<'EOF'
[ -e "$STUB/moved" ] || { : > "$STUB/moved"; sed -i '2d;7d' "$R/a.test.mjs"; git -C "$R" commit -qam "main turns the test back on"; }
node --check a.test.mjs 2>/dev/null || cp a.test.mjs "$STUB/brokenrun"
EOF
  out=$(loop run 2>&1) || fail "run exited non-zero: $out"
  [ ! -e "$STUB/brokenrun" ] || fail "a test step ran on the merged file that does not parse: $(cat "$STUB/brokenrun")"
  grep -q 'a\.test\.mjs: `node --check` failed:' "$STUB/parsebrief" 2>/dev/null && grep -q 'SyntaxError' "$STUB/parsebrief" \
    || fail "#7's fix session was not given the file that does not parse and its error: $(st '"\(.step) \(.reason)"' | tr '\n' ,)"
  [ "$(st "select(.issue == 7 and $NOMARK) | .step" | tr '\n' ' ')" = "picked worktree brief build review test fix review test landed " ] \
    && st 'select(.step == "fix") | .reason' | grep -q 'no longer parses after the merge onto main: a.test.mjs' \
    || fail "#7 did not go from the parse check to its fix, then land: $(st '"\(.step) \(.result) \(.reason)"' | tr '\n' ,)"
  # A merge in doubt is a full run the owner allows (issue 461): the run after the parse fix is not refused.
  [ "$(st 'select(.issue == 7 and .step == "test") | .refused // "none"' | tr '\n' ' ')" = "none none " ] \
    || fail "the whole run after a merge in doubt was refused: $(st 'select(.step == "test") | .refused')"
  node --check "$R/a.test.mjs" || fail "main holds a file that does not parse: $(cat "$R/a.test.mjs")"
}

# The parse check's commands (parses()): the engine's own by file type, the pack's land.parse adding a glob (whose *
# matches a / too) and replacing one of the engine's, run on each file the change keeps; py_compile leaves no file in
# the worktree. A failure names the file and the command.
t_mergeparsepack() {
  eval "$(sed -n '/^PARSE=/p; /^parses() {/,/^}/p' "$SRC/lib/claim.sh")"
  packget() { printf -v "$2" '%s' '{"*.txt": "grep -qx ok", "*.js": "true"}'; }
  local w=$T/$CASE/w out
  mkdir -p "$w/d" && git -C "$w" init -q && echo gone > "$w/gone.sh" && git -C "$w" add -A && git -C "$w" -c user.name=t -c user.email=t@example.com commit -qm base
  echo ok > "$w/d/ok.txt"; echo 'x = (' > "$w/x.js"; echo 'print(1)' > "$w/p.py"; echo '{"a": 1}' > "$w/j.json"; rm "$w/gone.sh"; git -C "$w" add -A
  out=$(parses "$w") || fail "files that all parse were found not to: $out"
  [ -z "$(git -C "$w" ls-files -o)" ] || fail "the check left files in the worktree: $(git -C "$w" ls-files -o)"
  echo no > "$w/d/bad.txt"; echo 'if' > "$w/b.sh"; git -C "$w" add -A
  out=$(parses "$w"); [ $? = 1 ] && grep -q '^d/bad\.txt: `grep -qx ok` failed:' <<<"$out" && grep -q '^b\.sh: `bash -n` failed:' <<<"$out" \
    && [ "$(grep -c ' failed:$' <<<"$out")" = 2 ] || fail "the failing files were not each named with their command, and no other: $out"
}

# A clash in a README alone at landing. #7 changes l4 of a.txt and README.md's one line; main rewrites that line while
# #7 is in <hook> (review-cmd: its review; test-cmd: its tests). One session merges README.md (settle()'s, at its
# landing claim, or the landing rebuild), writing a.txt as #7 had it, and then runs <its own edit>.
readme() { # <review-cmd|test-cmd> <the merge session's own edit>
  setup "[$(issue 7 2026-01-01)]"; for i in 1 2; do echo "$GO" > "$STUB/review.$i"; done; nine
  echo title > "$R/README.md"; git -C "$R" add README.md; git -C "$R" commit -qm "a README"
  { echo "if grep -q '^# \(Landing conflict\|Main moved\)' \"\$STUB/brief\"; then sed -i 's/^l4\$/seven/' a.txt; printf '%s\n' main seven > README.md; $2"
    echo "else sed -i 's/^l4\$/seven/' a.txt; echo seven > README.md; fi"; } > "$STUB/build"
  echo '[ -e "$STUB/moved" ] || { : > "$STUB/moved"; echo main > "$R/README.md"; git -C "$R" commit -qam "main moves"; }' >> "$STUB/$1"
  out=$(loop run 2>&1) || fail "run exited non-zero: $out"
  [ "$(st 'select(.step == "landed") | .issue')" = 7 ] && [ "$(tr '\n' ' ' < "$R/README.md")" = "main seven " ] && grep -qx seven "$R/a.txt" \
    || fail "#7 did not land merged: $(st '"\(.step) \(.reason)"' | tr '\n' ,)"
}

# Bug (#436: two of a day's 11 landing clashes shared only a README, and cost 40.5 minutes): a clash in a README alone
# after the card's tests passed sent it, after the rebuild session merged the README, to a new review and a new test
# run. Its change outside documentation is the one reviewed and tested: it lands on that review and that run.
t_mergereadme() {
  readme test-cmd :
  [ "$(st "select(.issue == 7 and $NOMARK) | .step" | tr '\n' ' ')" = "picked worktree brief build review test rebase test landed " ] \
    && [ "$(st 'select(.step == "test") | .reused // false' | tr '\n' ' ')" = "false true " ] \
    && [ "$(wc -l < "$STUB/reviews")" = 1 ] && [ "$(wc -l < "$STUB/tests")" = 1 ] \
    || fail "#7 was reviewed or tested again after a clash in README.md alone: $(st "select(.issue == 7) | \"\(.step) \(.reused)\"" | tr '\n' ,)"
}

# The review and the test pass stand only for the same change: a rebuild session that also changes a line of code (l8)
# sends #7 to a new review and a new test run.
t_mergereadmecode() {
  readme test-cmd "sed -i 's/^l8\$/eight/' a.txt"
  [ "$(wc -l < "$STUB/reviews")" = 2 ] && [ "$(wc -l < "$STUB/tests")" = 2 ] && grep -qx eight "$R/a.txt" \
    || fail "#7's changed code was not reviewed and tested again: $(st "select(.issue == 7) | \"\(.step) \(.reused)\"" | tr '\n' ,)"
}

# The same at the landing claim (settle()): a clash in a README alone during the review is merged by one session, and
# the card goes on to its tests with no second review.
t_mergereadmewait() {
  readme review-cmd :
  [ "$(st "select(.issue == 7 and $NOMARK) | .step" | tr '\n' ' ')" = "picked worktree brief build review fix test landed " ] \
    && [ "$(wc -l < "$STUB/reviews")" = 1 ] && [ "$(wc -l < "$STUB/tests")" = 1 ] \
    || fail "#7 was reviewed again after its landing claim merged README.md alone: $(st "select(.issue == 7) | \"\(.step) \(.reused)\"" | tr '\n' ,)"
}
