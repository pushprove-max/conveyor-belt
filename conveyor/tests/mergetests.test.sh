#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 300
# Engine cases: test files at landing: the three-way merge of test files, a test file shared with a card landed since,
# and the parse check of merged files.
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"
# The engine folder, as lib.sh sets it: named here too, so the release closure (tools/closure.sh) follows this file's paths.
SRC=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)

# Main's test file a.test.sh, one case: two changes that each add a case at its end conflict in a three-way merge.
casefile() { echo case1 > "$R/a.test.sh"; git -C "$R" add a.test.sh; git -C "$R" commit -qm "a test file"; }

# Bug (#435: 5 of 11 landing clashes in a day): two cards that both add a case at the end of one test file clashed at
# landing, and the second went to a merge session. Card c7 (fx_wt), made on main before another card landed, adds
# case8; that card's case7 lands meanwhile. At c7's landing, where its plain three-way merge conflicts, the test file
# is merged keeping both sides (unionfit(), its own lines outside the test files being unionx()'s), with no session.
# Bug (#451: a union merge, which git calls clean, can leave a test file that no longer parses): the union-merged file
# is checked to parse (parses(), here through the pack's land.parse, which records each file it checks). What a file
# that fails the check leads to is t_mergeparseclean's.
t_mergetests() {
  setup '[]'; fx_wt 'echo case8 >> a.test.sh' a.test.sh case1
  echo "{ tr '\n' ' ' < \"\$1\"; echo; } >> '$STUB/parsed'; exec bash -n \"\$1\"" > "$STUB/parse"
  tune --arg c "sh $STUB/parse" '.land.parse = {"*.test.sh": $c}'
  echo case7 >> "$R/a.test.sh"; git -C "$R" commit -qam "case7 lands"
  fx_in 'cd "$FXWT" && tf=$(git diff --cached --name-only --no-renames | testpaths) && ix=$(unionx "$FXWT" "$tf") && echo "tf=$tf" \
    && git diff --cached --binary --no-renames > "$FXWT.patch" && git reset -q --hard main && ! git apply --3way --index "$FXWT.patch" >/dev/null 2>&1 \
    && git reset -q --hard main && unionfit "$FXWT" a.test.sh "$tf" "$ix" && parses "$FXWT"'
  [ "$RC" = 0 ] && grep -qx 'tf=a.test.sh' "$T/$CASE/run.out" \
    || fail "the two cases' clash in a.test.sh was not merged keeping both, or the merge was found not to parse: $(cat "$T/$CASE/run.out")"
  [ "$(git -C "$FXWT" show :a.test.sh | tr '\n' ' ')" = "case1 case7 case8 " ] && [ "$(git -C "$FXWT" rev-parse HEAD)" = "$(git -C "$R" rev-parse main)" ] \
    || fail "the merged test file is not both cases staged on main: $(git -C "$FXWT" show :a.test.sh | tr '\n' ' ')"
  [ "$(cat "$STUB/parsed" 2>/dev/null)" = 'case1 case7 case8 ' ] || fail "the union-merged test file was not checked to parse: $(cat "$STUB/parsed" 2>/dev/null)"
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
  # loop: settle() drops the union merge's pass in its own body, and card() then runs the merged file and sends its failure to the fix: no function shows that order
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
# the card landed meanwhile touched a test file of its own. Card c7 (fx_wt) changes lib/rows.sh; the card landed
# meanwhile, lib/panel.sh: the test links give both lib/view.test.sh. Once main holds that landing, sharedtests() names
# lib/view.test.sh, so the card runs it again on main as it is now (card()) and does not land red; a landing that
# touches none of the card's test files (a.txt) names none, so the card lands on the run it passed.
t_mergesharedtests() {
  setup '[]'; mkdir -p "$R/lib"; linkset '{"lib/panel.sh": ["lib/view.test.sh"], "lib/rows.sh": ["lib/view.test.sh"]}'
  fx_wt 'echo eight >> lib/rows.sh' lib/panel.sh panel lib/rows.sh rows lib/view.test.sh case1
  # Each landing, then c7's change brought onto main as it is now (settle()), and what sharedtests() prints and returns.
  fx_in 'cd "$FXWT" && b=$(git rev-parse HEAD) || exit 3
    for f in a.txt lib/panel.sh; do echo landed >> "$R/$f" && git -C "$R" commit -qam "$f lands" && git diff --cached --binary --no-renames > "$FXWT.patch" \
      && git reset -q --hard main && git apply --index "$FXWT.patch" || exit 3; t=$(sharedtests "$FXWT" "$b"); echo "$f: $? $t"; done'
  [ "$RC" = 0 ] && [ "$(tr '\n' ',' < "$T/$CASE/run.out")" = "a.txt: 1 ,lib/panel.sh: 0 lib/view.test.sh," ] \
    || fail "the test file c7 shares with a card landed since was not named, or one with a landing that touches none was: $(cat "$T/$CASE/run.out")"
}

# #447: card A (#7) passes; card-b lands touching A's test file lib/view.test.sh; A runs that file again and passes;
# card-c lands touching it again (and, given "conflict", A's line of lib/panel.sh too). card-b and card-c stand for
# cards that landed: a commit on main and its landed line. Each run of A's tests logs the file, and the n-th lands the
# n-th of them.
sharedonce() { # [conflict]
  setup "[$(issue 7 2026-01-01)]"; for i in 1 2 3; do echo "$GO" > "$STUB/review.$i"; done
  mkdir -p "$R/lib"; echo panel > "$R/lib/panel.sh"; echo case1 > "$R/lib/view.test.sh"
  git -C "$R" add lib; linkset '{"lib/panel.sh": ["lib/view.test.sh"]}' # A's change runs lib/view.test.sh
  echo "if grep -q '^# Landing conflict' \"\$STUB/brief\"; then sed -i 's/^panelC\$/panelC seven/' lib/panel.sh; else sed -i 's/^panel\$/seven/' lib/panel.sh; fi" > "$STUB/build"
  [ -z "${1:-}" ] || : > "$STUB/conflict"
  cat >> "$STUB/test-cmd" <<'EOF'
n=$(( $(cat "$STUB/n" 2>/dev/null || echo 0) + 1 )); echo "$n" > "$STUB/n"
echo "== lib/view.test.sh"; printf "%s\n" "== lib/view.test.sh" "-- ok lib/view.test.sh" "TESTRUN sec	lib/view.test.sh	1	1" >> "$CONVEYOR_TEST_LOG/run.log"
c=''; case $n in 1) c=card-b ;; 2) c=card-c ;; esac
[ -z "$c" ] || { echo "$c" >> "$R/lib/view.test.sh"; [ "$c" != card-c ] || [ ! -e "$STUB/conflict" ] || sed -i 's/^panel$/panelC/' "$R/lib/panel.sh"
  git -C "$R" commit -qam "$c lands"; jq -cn --arg c "$c" --arg s "$(git -C "$R" rev-parse HEAD)" '{card: $c, issue: 90, step: "landed", result: "ok", sha: $s}' >> "$ST/cards.jsonl"; }
EOF
  out=$(loop run 2>&1) || fail "run exited non-zero: $out"
  grep -q 'card .*-7: cards landed since its tests ran touch its test files too.*lib/view.test.sh' <<<"$out" \
    || fail "#7 did not run its test file again after card-b landed on it: $(st 'select(.issue == 7) | "\(.step) \(.result) \(.reason)"' | tr '\n' ,)"
}

# Bug it catches: after its shared run again passed, card-c landed on the file again and A ran it again, on and on:
# each run let another card land, and A never landed (#447). A lands with no third run, and its log names card-c only.
t_mergesharedonce() {
  sharedonce
  [ "$(cat "$STUB/n")" = 2 ] && [ "$(st 'select(.issue == 7 and .step == "test") | "\(.result) \(.reused // false)"' | tr '\n' ,)" = "pass false,pass false,pass true," ] \
    && [ "$(st 'select(.issue == 7 and .step == "landed") | .issue')" = 7 ] \
    || fail "#7 ran its shared test file again after card-c landed, or did not land: runs $(cat "$STUB/n"); $(st 'select(.issue == 7) | "\(.step) \(.result) \(.reason)"' | tr '\n' ,)"
  grep -q 'card .*-7: .*lands with no second run again\. Cards landed since: card-c$' <<<"$out" \
    || fail "#7's log does not say it lands with no second run, naming card-c alone: $(grep 'card .*-7' <<<"$out" | tail -5)"
  [ "$(tr '\n' ' ' < "$R/lib/panel.sh")" = "seven " ] || fail "main does not hold #7's change: $(cat "$R/lib/panel.sh")"
}

# Bug it catches: a card past its one shared run again (#447) landing on that pass when its change no longer applies.
# card-c changes A's line too: A is fitted onto main as before (its rebuild session), reviewed and tested again, and
# lands. The three-way merge is tried only to spare a rebuild: a change whose lines main changed too still goes to the
# rebuild session, and the rebuilt change lands, not main's line.
t_mergesharedonceconflict() {
  sharedonce conflict
  st 'select(.issue == 7 and .step == "rebase") | .reason' | grep -q '^rebase onto main conflicts' \
    || fail "#7 was not fitted onto main after card-c's conflicting change: $(st 'select(.issue == 7) | "\(.step) \(.result) \(.reason)"' | tr '\n' ,)"
  [ "$(cat "$STUB/n")" = 3 ] && [ "$(wc -l < "$STUB/reviews")" = 2 ] && [ "$(st 'select(.issue == 7 and .step == "landed") | .issue')" = 7 ] \
    && [ "$(tr '\n' ' ' < "$R/lib/panel.sh")" = "panelC seven " ] \
    || fail "#7's fitted change was not reviewed and tested again before it landed: runs $(cat "$STUB/n"), reviews $(wc -l < "$STUB/reviews"); $(cat "$R/lib/panel.sh")"
}

# Bug (#345): unshare() named a shared file that had passed only as failed, so the run again logged "did not pass" for
# it. Each shared file no `fail` line names gets a `shared` line beside its `fail` line; one that failed a case (c) gets
# none, as it did fail; so does each file whose passes it drops when the shared files could not be listed.
t_mergeunshare() {
  eval "$(sed -n '/^unshare() {/,/^}/p' "$SRC/lib/claim.sh")"
  local w=$T/$CASE/w
  mkdir -p "$T/$CASE"; printf 'change\tx\npass\ta\npass\tb\nfail\tc\tone\nok\tc\ttwo\n' > "$w.rerun"
  unshare "$w" $'a\nc\ne'
  [ "$(sort "$w.rerun" | tr '\t\n' ':|')" = "change:x|fail:a|fail:c|fail:c:one|fail:e|pass:b|shared:a|shared:e|" ] \
    || fail "the shared files that passed are not each named shared, or one that failed is: $(cat "$w.rerun")"
  printf 'change\tx\npass\ta\nfail\tc\tone\nok\tc\ttwo\n' > "$w.rerun"
  unshare "$w" "(the test files of the change or of main's could not be listed)"
  [ "$(sort "$w.rerun" | tr '\t\n' ':|')" = "change:x|fail:c:one|shared:a|" ] \
    || fail "with no list of shared files, the files that passed are not each named shared: $(cat "$w.rerun")"
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
  # loop: card() runs parses() before the test step, gives its failure to the fix session's brief and runs the tests whole after it: only a card run shows that order
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
