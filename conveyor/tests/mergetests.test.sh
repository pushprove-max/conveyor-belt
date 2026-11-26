#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 300
# Engine cases: test files at landing: the three-way merge of test files, a pass that stands when main moves (a test
# file a card landed since touches too), the landing turn (lib/claim.sh), and the parse check of merged files.
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

# Bug (#1148): a card ready to land while another card has the landing turn landed, and moved main under the batch that
# had the turn. land() refuses c8-8 while c7-7 has it, main staying where it was, and lands it once the turn has ended.
t_mergeturnrefuse() {
  setup '[]'; mkdir -p "$T/$CASE/cards"; local m; m=$(git -C "$R" rev-parse main)
  git -C "$R" worktree add -q --detach "$T/$CASE/cards/c8-8" main && echo eight > "$T/$CASE/cards/c8-8/b.txt" && git -C "$T/$CASE/cards/c8-8" add -A || fail "c8's change"
  echo "{\"pid\":$$,\"paths\":[\"a.txt\"]}" > "$T/$CASE/cards/c7-7.claim"; echo "{\"card\":\"c7-7\",\"pid\":$$}" > "$T/$CASE/cards/land.turn"
  fx_in 'land c8-8 8 "$CARDS/c8-8" "eight (#8)"; echo "land: $?"; git -C "$R" rev-parse main
    turnfree c7-7; land c8-8 8 "$CARDS/c8-8" "eight (#8)"; echo "land: $?"'
  [ "$(head -n 3 "$T/$CASE/run.out")" = $'another card has the landing turn, as its batch lands first; nothing was landed\nland: 1\n'"$m" ] \
    || fail "c8-8 was not refused while c7-7 had the landing turn, or main moved: $(cat "$T/$CASE/run.out")"
  [ "$(tail -n 1 "$T/$CASE/run.out")" = 'land: 0' ] && [ "$(git -C "$R" show main:b.txt)" = eight ] \
    || fail "c8-8 did not land once the turn ended: $(cat "$T/$CASE/run.out")"
}

# Bug (#1148): a card ready to land while another card has the landing turn landed, or waited saying nothing. c8-8 at
# its land step waits (landwait()) while c7-7 has the turn: its land step's start line is marked waitFor: turn, its
# live record names c7-7, the Board's step line says it waits on #7, and it is idle; once the turn ends it goes on.
t_mergeturnwait() {
  local s
  setup '[]'; mkdir -p "$T/$CASE/cards"
  for n in 7 8; do jq -cn --arg c "c$n-$n" --argjson n "$n" '{card: $c, issue: $n, step: "picked", result: "ok", time: "2026-01-01T00:00:00Z", tokens: {claude: 0, codex: 0}, sha: "", reason: ""}' >> "$ST/cards.jsonl"; done
  echo "{\"pid\":$$,\"paths\":[\"a.txt\"]}" > "$T/$CASE/cards/c7-7.claim"; echo "{\"card\":\"c7-7\",\"pid\":$$}" > "$T/$CASE/cards/land.turn"
  # This polls a real wait: what the Board shows comes from the live record landwait() keeps while it waits.
  fx_in 'landwait c8-8 8 "$CARDS/c8-8"; echo waited' & local p=$!
  wait_until "jq -e '.waits.on == \"c7-7\" and (.action | startswith(\"waiting for card c7-7 to land first\"))' '$T/$CASE/cards/c8-8.live'" && [ -e "$T/$CASE/cards/c8-8.idle" ] \
    || { rm -f "$T/$CASE/cards/land.turn"; fail "the card does not say it waits for c7-7's landing turn: $(cat "$T/$CASE/cards/c8-8.live" 2>&1)"; }
  s=$(loop snapshot --fresh)
  [ "$(jq -c '[.belt[] | select(.issue == 8) | [.step, .waitsOn.issue]]' <<<"$s")" = '[["waiting",7]]' ] \
    || { rm -f "$T/$CASE/cards/land.turn"; fail "the Board's step line does not say the card waits on #7: $(jq -c '[.belt[] | {issue, step, waitsOn, live}]' <<<"$s")"; }
  rm -f "$T/$CASE/cards/land.turn"; wait "$p"
  grep -qx waited "$T/$CASE/run.out" && [ ! -e "$T/$CASE/cards/c8-8.live" ] && [ ! -e "$T/$CASE/cards/c8-8.idle" ] \
    && [ "$(st 'select(.card == "c8-8" and .step == "start") | .waitFor')" = turn ] || fail "the wait did not end with the turn, or left its marks: $(cat "$T/$CASE/run.out")"
  # Bug it catches: stop (halt(), lib/run.sh) left a card in that wait to land after the stop. Nothing of its landing
  # has begun there, as in a wait for a release run, so it is stopped.
  sleep 60 & p=$! # sleep: a stand-in for the card's process, until it is killed
  fx_in "echo '$p c8-8' | halt"; kill -KILL "$p" 2>/dev/null; wait "$p" 2>/dev/null
  [ "$(cat "$T/$CASE/run.out")" = "$p c8-8" ] || fail "stop left the card that waits for a landing turn: $(cat "$T/$CASE/run.out")"
  recok "$ST/cards.jsonl" "the wait for a landing turn"
}

# The owner's pick (#1777): a card's pass stands when main moves, but a change a session had to rework to fit is still
# tested again. Card A (#7) passes its tests; during that run card-b lands (a commit on main), changing A's line of
# lib/panel.sh and its test file lib/view.test.sh. A is brought onto main by its rebuild session, reviewed and tested
# again, and lands its fitted change. Bug it catches: a reworked change landing on the pass of the change before it.
t_mergepassconflict() {
  setup "[$(issue 7 2026-01-01)]"; for i in 1 2; do echo "$GO" > "$STUB/review.$i"; done
  mkdir -p "$R/lib"; echo panel > "$R/lib/panel.sh"; echo case1 > "$R/lib/view.test.sh"
  git -C "$R" add lib; linkset '{"lib/panel.sh": ["lib/view.test.sh"]}' # A's change runs lib/view.test.sh
  echo "if grep -q '^# Landing conflict' \"\$STUB/brief\"; then sed -i 's/^panelC\$/panelC seven/' lib/panel.sh; else sed -i 's/^panel\$/seven/' lib/panel.sh; fi" > "$STUB/build"
  cat >> "$STUB/test-cmd" <<'EOF'
n=$(( $(cat "$STUB/n" 2>/dev/null || echo 0) + 1 )); echo "$n" > "$STUB/n"
[ "$n" != 1 ] || { echo card-b >> "$R/lib/view.test.sh"; sed -i 's/^panel$/panelC/' "$R/lib/panel.sh"; git -C "$R" commit -qam "card-b lands"; }
EOF
  # loop: only a whole card run shows card-b landing during A's tests, then A's rebuild session, review and run again
  out=$(loop run 2>&1) || fail "run exited non-zero: $out"
  st 'select(.issue == 7 and .step == "rebase") | .reason' | grep -q '^rebase onto main conflicts' \
    || fail "#7 was not fitted onto main after card-b's conflicting change: $(st 'select(.issue == 7) | "\(.step) \(.result) \(.reason)"' | tr '\n' ,)"
  [ "$(cat "$STUB/n")" = 2 ] && [ "$(wc -l < "$STUB/reviews")" = 2 ] && [ "$(st 'select(.issue == 7 and .step == "landed") | .issue')" = 7 ] \
    && [ "$(tr '\n' ' ' < "$R/lib/panel.sh")" = "panelC seven " ] \
    || fail "#7's fitted change was not reviewed and tested again before it landed: runs $(cat "$STUB/n"), reviews $(wc -l < "$STUB/reviews"); $(cat "$R/lib/panel.sh")"
}

# Main moves under card c7 (#7), whose test step then runs on the main that moved: its change is not marked as passed
# (as after a failed run fitted onto main). The pack sets test.changed: its test command reads the list's `main`
# lines. The links are <links>; c7 makes <c7's change>, by default adding `eight` to lib/rows.sh. Its list (c7.rerun)
# is as a run on m0 leaves it: lib/view.test.sh passed. Card c8 lands, adding <c8's line> to lib/panel.sh (its commit
# and landed line), and c7's change is brought onto main as it is now. $STUB/test-cmd stands for the project's
# command: it adds each file it is given to $STUB/given and runs the file unless the list keeps it as passed and names
# no `main` line, adding to $STUB/ran `<file> <case>` for each of the file's cases it runs: those CONVEYOR_TEST_CASES
# names of it, else all its t_ cases. Asked for its selection (CONVEYOR_TEST_LIST), it lists the files it is given but
# those $STUB/unselected names.
mainmoved() { # <links json> <c8's line> [<c7's change> [<lib/view.test.sh text> [<lib/other.test.sh text>]]]
  setup "[$(issue 7 2026-01-01)]"; tune '.test.changed = "sel.sh"'; mkdir -p "$R/lib"; linkset "$1"
  fx_wt "${3:-echo eight >> lib/rows.sh}" lib/panel.sh panel lib/rows.sh rows lib/other.test.sh "${5:-exit 0}" lib/view.test.sh "${4:-exit 0}"
  m0=$(git -C "$R" rev-parse main)
  printf 'change\t%s\nbase\t%s\ntree\t%s\npass\tlib/view.test.sh\n' "$(git -C "$FXWT" diff --cached --binary --no-renames HEAD | git hash-object --stdin)" \
    "$m0" "$(git -C "$FXWT" write-tree)" > "$FXWT.rerun"
  echo "$2" >> "$R/lib/panel.sh"; git -C "$R" commit -qam "title 8 (#8)" || fail "#8 could not land"
  landed 8 | jq -c --arg s "$(git -C "$R" rev-parse main)" '.card = "c8-8" | .sha = $s' >> "$ST/cards.jsonl"
  git -C "$FXWT" diff --cached --binary --no-renames > "$FXWT.patch" && git -C "$FXWT" reset -q --hard main \
    && git -C "$FXWT" apply --index "$FXWT.patch" || fail "c7's change could not be brought onto main as it is now"
  cat > "$STUB/test-cmd" <<'EOF'
# Asked for its selection (CONVEYOR_TEST_LIST: runfiles()), it lists the files it is given, but those $STUB/unselected names.
[ -z "${CONVEYOR_TEST_LIST:-}" ] || { [ -d "${CONVEYOR_TEST_LOG:-}" ] && echo "log cases=${CONVEYOR_TEST_CASES-unset}" > "$STUB/selenv"; grep -vxFf <(cat "$STUB/unselected" 2>/dev/null) "$CONVEYOR_TEST_FILELIST" > "$CONVEYOR_TEST_LIST"; exit 0; }
f=$CONVEYOR_TEST_FILE; echo "$f" >> "$STUB/given"
if grep -q "^main	" "$CONVEYOR_TEST_RERUN" || ! grep -qxF "pass	$f" "$CONVEYOR_TEST_RERUN"; then
  cs=$(printf '%s\n' "${CONVEYOR_TEST_CASES:-}" | awk -F'\t' -v f="$f" '$1 == f { print $2 }'); [ -n "$cs" ] || cs=$(sed -n 's/^t_\([a-z]*\)() {.*/\1/p' "$f")
  for c in $cs; do echo "$f $c" >> "$STUB/ran"; done; bash "$f"
fi
EOF
}
# card()'s test step (cardtest()) on c7, as card() calls it, with the real testedhere() and tests(): the lint gate,
# checks and batches stubbed. run.out ends with the run's exit.
mainmovedtest() {
  fx_in 'c=c7 n=7 wt=$FXWT issue="{}" sprompt="" br="" parsecheck="" tmain="" away="" apart="" me=$$ cmsg=x mates=()
    lintgate() { return 0; }; checks() { :; }; treecheck() { :; }; gather() { return 1; }
    cardtest; echo "rc $rc"'
}

# The owner's trade-off (#1777, "a pass stands"), kept in view: c7 and c8 each pass lib/view.test.sh alone and fail it
# together. c8 lands first, a change to that test file too. c7 then lands on its own pass with no second run, and the
# main run (the whole test on main) after that second landing fails: the main-red fix card fixes it. Bug it catches: a
# card whose tests passed ran them again because another card landed on the same test file, or the main run missed the pair.
t_mainmovedpair() {
  export XDG_CONFIG_HOME=$T/$CASE/config # the host file the main run changes is the case's own
  setup '[]'; mkdir -p "$R/lib"; linkset '{"lib/rows.sh": ["lib/view.test.sh"], "lib/panel.sh": ["lib/view.test.sh"]}'
  tune '.test.main = "bash lib/view.test.sh"'
  fx_wt 'echo eight >> lib/rows.sh' lib/panel.sh panel lib/rows.sh rows \
    lib/view.test.sh '! { grep -qx eight lib/rows.sh && grep -qx landed lib/panel.sh; } || { echo "FAIL [pair]: eight beside landed"; exit 1; }'
  echo 'echo run >> "$STUB/ran"; bash "$CONVEYOR_TEST_FILE"' > "$STUB/test-cmd"
  git -C "$R" worktree add -q --detach "$T/$CASE/cards/c8" main && echo landed >> "$T/$CASE/cards/c8/lib/panel.sh" \
    && sed -i '1i # the case of #8' "$T/$CASE/cards/c8/lib/view.test.sh" && git -C "$T/$CASE/cards/c8" add -A || fail "c8's change"
  # Each passes its test file alone, its pass recorded (tested()) with the commit its run was on (.rerun, as a run's
  # list names it); then c8 lands on its pass.
  fx_in 'for w in "$FXWT" "$CARDS/c8"; do (cd "$w" && bash lib/view.test.sh) || exit 3; echo "{}" > "$w.ready"; tested "$w"
      printf "base\t%s\n" "$(git -C "$w" rev-parse HEAD)" > "$w.rerun"; done
    land c8 8 "$CARDS/c8" "title 8 (#8)"; echo "land: $?"'
  [ "$(tail -n 1 "$T/$CASE/run.out")" = 'land: 0' ] || fail "c8, which passes alone, did not land: $(cat "$T/$CASE/run.out")"
  CONVEYOR_NOW=1800000000 loop main-test || fail "the main run after c8 landed failed to run"
  [ "$(jq -r .pass "$ST/maintest.json")" = "$(git -C "$R" rev-parse main)" ] || fail "main is not green with c8 alone: $(cat "$ST/maintest.json")"
  git -C "$FXWT" diff --cached --binary --no-renames > "$FXWT.patch" && git -C "$FXWT" reset -q --hard main \
    && git -C "$FXWT" apply --index "$FXWT.patch" || fail "c7's change could not be brought onto main as it is now"
  mainmovedtest
  [ "$(tail -n 1 "$T/$CASE/run.out")" = "rc 0" ] && [ ! -e "$STUB/ran" ] \
    || fail "c7's tests ran again after c8 landed on its test file, or its test step did not pass: $(cat "$T/$CASE/run.out")"
  fx_in 'land c7 7 "$FXWT" "title 7 (#7)"; echo "land: $?"'
  [ "$(tail -n 1 "$T/$CASE/run.out")" = 'land: 0' ] && grep -qx eight <(git -C "$R" show main:lib/rows.sh) \
    && grep -qx landed <(git -C "$R" show main:lib/panel.sh) || fail "c7 did not land on its pass beside c8: $(cat "$T/$CASE/run.out")"
  CONVEYOR_NOW=1800003600 loop main-test
  [ "$(jq -r '.fail.to' "$ST/maintest.json")" = "$(git -C "$R" rev-parse main)" ] \
    || fail "the main run after c7 landed did not fail on the pair: $(cat "$ST/maintest.json")"
}

# Bug it catches (#1595): after main moved, a card's run started every file of its list, though the move selected no case of
# a file that had passed: each start of the file command paid its set-up and ran no case (1,001 of 1,804 such starts, about
# 5 s each). c7's list holds lib/view.test.sh and lib/other.test.sh, both passed. The links give both files to c8's
# lib/panel.sh, and the stub for the project's command ($STUB/unselected) selects nothing of lib/other.test.sh, as the real
# command does when main's change touches no case of it. The file command is started for lib/view.test.sh alone; the step
# passes, and lib/other.test.sh keeps its pass.
t_mainmovedunselected() {
  mainmoved '{"lib/rows.sh": ["lib/view.test.sh", "lib/other.test.sh"], "lib/panel.sh": ["lib/view.test.sh", "lib/other.test.sh"]}' other; printf 'pass\tlib/other.test.sh\n' >> "$FXWT.rerun"
  echo lib/other.test.sh > "$STUB/unselected"; mainmovedtest
  [ "$(tail -n 1 "$T/$CASE/run.out")" = "rc 0" ] && [ "$(sort -u "$STUB/given" | tr '\n' ' ')" = "lib/view.test.sh " ] \
    || fail "c7's run again after main moved was not given lib/view.test.sh alone, or did not pass (given: $(cat "$STUB/given" 2>&1)): $(cat "$T/$CASE/run.out")"
  grep -qxF $'pass\tlib/other.test.sh' "$FXWT.rerun" || fail "lib/other.test.sh, not started, lost its pass: $(cat "$FXWT.rerun" 2>&1)"
  # The selection was given the run's log folder (it logs the cases it keeps of the file it leaves out there, which the test
  # record sums) and the cases the card names (a case outside them is no reason to start a file).
  [ -f "$STUB/selenv" ] && [ "$(cat "$STUB/selenv")" != "log cases=unset" ] || fail "the selection was given no log folder, or no CONVEYOR_TEST_CASES: $(cat "$STUB/selenv" 2>&1)"
}

# Bug it catches (#1595): the list of files the move selects was read as the files to skip, or dropped a file it names. With
# the same list, main's change now selects lib/other.test.sh too: it is started beside lib/view.test.sh, and each runs its
# cases (lib/other.test.sh holds t_a and t_b, lib/view.test.sh t_a): the file names alone cannot show a started file that ran none.
t_mainmovedselected() {
  mainmoved '{"lib/rows.sh": ["lib/view.test.sh", "lib/other.test.sh"], "lib/panel.sh": ["lib/view.test.sh", "lib/other.test.sh"]}' other '' \
    $'t_a() {\n  :\n}' $'t_a() {\n  :\n}\nt_b() {\n  :\n}'; printf 'pass\tlib/other.test.sh\n' >> "$FXWT.rerun"
  mainmovedtest
  [ "$(tail -n 1 "$T/$CASE/run.out")" = "rc 0" ] && [ "$(sort -u "$STUB/given" | tr '\n' ' ')" = "lib/other.test.sh lib/view.test.sh " ] \
    || fail "c7's run again after main moved was not given both files its move selects, or did not pass (given: $(cat "$STUB/given" 2>&1)): $(cat "$T/$CASE/run.out")"
  [ "$(sort "$STUB/ran" | tr '\n' '|')" = 'lib/other.test.sh a|lib/other.test.sh b|lib/view.test.sh a|' ] \
    || fail "the two files c7's run again was given did not run their cases (ran: $(cat "$STUB/ran" 2>&1)): $(cat "$T/$CASE/run.out")"
}

# Bug it catches (#1595, review): only a file with a `pass` line was left out when the move selected nothing of it. c7's
# list holds lib/other.test.sh with no `pass` and no `fail` line, only the `ok` and `off` lines of its one case t_b (kept off as
# flaky, flakyoff()), as after a fix that edits only that case; the selection names nothing of it (the case is off), and
# the file command was still started for it and ran no case. It is not started; lib/view.test.sh, passed, is.
t_mainmovedoff() {
  mainmoved '{"lib/rows.sh": ["lib/view.test.sh", "lib/other.test.sh"], "lib/panel.sh": ["lib/view.test.sh", "lib/other.test.sh"]}' other '' '' $'t_b() {\n  :\n}'
  printf 'ok\tlib/other.test.sh\tb\noff\tlib/other.test.sh\tb\n' >> "$FXWT.rerun"
  echo lib/other.test.sh > "$STUB/unselected"; mainmovedtest
  [ "$(tail -n 1 "$T/$CASE/run.out")" = "rc 0" ] && [ "$(sort -u "$STUB/given" | tr '\n' ' ')" = "lib/view.test.sh " ] \
    || fail "c7's run again was started for lib/other.test.sh, of which only an ok and an off line were kept, or did not pass (given: $(cat "$STUB/given" 2>&1)): $(cat "$T/$CASE/run.out")"
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
