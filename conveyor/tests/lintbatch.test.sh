#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 240
# Engine cases: the lint gate for a batch (lintbatch() and lintleave(), conveyor/lib/lint.sh), called by batch() and
# rebatch() in conveyor/lib/claim.sh on the batch's combined change, before its product checks.
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"

# The case's main with batches on (landBatch 3), <run> as the pack's one lint command on *.txt files ($L in it the
# stub linter $STUB/lint: it notes each run in $STUB/lint-args and prints `<file>:<n>: E1 a bad word` for each line
# holding BAD, exit 1 then) and no product check. Cards c7-7, c8-8 and c9-9 have worktrees on main, each adding the file
# <n>.txt, its line the case's <line of n> (`<n>` when not given). Each is ready; #7's tests passed on its change
# (tested()), and #7 runs the batch: #8 and #9 are marked taken by it (<worktree>.batch). In the engine shell (fx_in),
# tests() is a stand-in that notes the files of each run's change in $STUB/runs and passes: the cases are about the
# lint gate, not the test run. Then <shell> runs there, with W the worktree of #7.
lbsetup() { # <line of 7> <line of 8> <run> <shell>
  local n l
  setup '[]'
  printf '%s\n' 'echo "run $*" >> "$STUB/lint-args"; r=0' \
    'for f; do n=0; while IFS= read -r l; do n=$((n + 1)); [[ $l != *BAD* ]] || { echo "$f:$n: E1 a bad word"; r=1; }; done < "$f"; done; exit $r' \
    > "$STUB/lint" || fail "the stub linter"
  tune --arg l "bash $STUB/lint" --arg r "$3" '.landBatch = 3 | .checks = [] | .lint = {commands: [{files: ["*.txt"], run: ($r | gsub("\\$L"; $l))}]}'
  CARDS=$T/$CASE/cards; mkdir -p "$CARDS"
  for n in 7 8 9; do
    git -C "$R" worktree add -q --detach "$CARDS/c$n-$n" main || fail "the worktree of card $n"
    l=$n; [ "$n" != 7 ] || l=${1:-7}; [ "$n" != 8 ] || l=${2:-8}
    echo "$l" > "$CARDS/c$n-$n/$n.txt" && git -C "$CARDS/c$n-$n" add -A || fail "the change of card $n"
    echo "{\"issue\":$n,\"msg\":\"title $n (#$n)\",\"extra\":{}}" > "$CARDS/c$n-$n.ready"
    [ "$n" = 7 ] || echo '{"by":"c7-7","pid":1}' > "$CARDS/c$n-$n.batch"
  done
  fx_in 'cd "$R" || exit 9; W=$CARDS/c7-7
    tests() { git -C "$1" diff --cached --name-only | paste -sd " " >> "$STUB/runs"; echo ran > "$1.test"; TEST_WAIT="" TEST_RUN="" TEST_FREE=""; } # tests: a stand-in that notes the run and passes
    tested "$W"
    '"$4"
}
# The batch's result as card() reads it: its exit, apart and mates.
BATCH='batch c7-7 "$W" "$@"; echo "batch: $? apart=$apart mates=${mates[*]}"'
lintruns() { paste -sd , "$STUB/runs" 2>/dev/null; } # each test run's files, in order

# Bug: a batch whose combined change has a finding from a card it took (#8) fails the batch's tests for it, so #8 is
# told a test failure and goes to a test fix, or the whole batch fails. The split finds #8; it leaves by unbatch with
# no test failure (no fail in its mark, no test output of its own), and is no longer ready, so no batch takes it again
# before its landing gate gives it its fix on main. #7 and #9 land; no test ran on a change that held #8's.
t_lintbatchtaken() {
  lbsetup '' 'eight BAD' '$L {files}' "echo batch > \"\$W.cpatch\"; set -- c7-7 c8-8 c9-9; $BATCH"
  grep -qx 'batch: 0 apart= mates=c7-7 c9-9' "$T/$CASE/run.out" || fail "the batch did not land #7 and #9 without #8: $(cat "$T/$CASE/run.out")"
  # Bug: #7's kept change (gather()) still held #8's, so #8 was stacked onto its own change and its fit found nothing to do.
  [ ! -e "$CARDS/c7-7.cpatch" ] || fail "#7 still keeps the batch's change, #8's among it"
  [ ! -e "$CARDS/c8-8.batch" ] && [ ! -e "$CARDS/c8-8.ready" ] && [ ! -e "$CARDS/c8-8.test" ] \
    || fail "#8 is still in the batch, still ready, or was told a test failure: $(cat "$CARDS/c8-8.batch" "$CARDS/c8-8.test" 2>&1)"
  jq -e 'has("fail") | not' "$CARDS/c9-9.batch" > /dev/null || fail "#9 lost its place in the batch: $(cat "$CARDS/c9-9.batch" 2>&1)"
  [ "$(lintruns)" = '7.txt,7.txt 9.txt' ] || fail "a test run held #8's change, or the batch did not run #7 and #9: $(lintruns)"
  grep -qx 'conveyor: card c8-8: the lint check failed on its change in the batch of card c7-7: it leaves the batch with no test failure, and its landing gate deals with it on main' "$T/$CASE/run.out" \
    || fail "batch() did not say why #8 left: $(cat "$T/$CASE/run.out")"
}

# Bug: a batch whose combined change has a finding from the card that runs it (#7, last in the batch's order) sends #7
# to a test fix, or lands none of the batch. #7 is apart (batch() returns 0, as for a patch that no longer applies), no
# longer ready, and #8 and #9 are the cards that land; card() then fits #7 onto main, where its landing gate runs.
t_lintbatchrunner() {
  lbsetup 'seven BAD' '' '$L {files}' "set -- c8-8 c9-9 c7-7; $BATCH"
  grep -qx 'batch: 0 apart=lint mates=c8-8 c9-9' "$T/$CASE/run.out" || fail "#7 is not apart, #8 and #9 landing: $(cat "$T/$CASE/run.out")"
  [ ! -e "$CARDS/c7-7.ready" ] && [ ! -e "$CARDS/c7-7.batchtest" ] || fail "#7 is still ready, or kept the run that found its lint as its test run"
  [ "$(git -C "$CARDS/c7-7" diff --cached --name-only)" = 7.txt ] || fail "#7's worktree does not hold its own change again"
  [ "$(lintruns)" = '8.txt,8.txt 9.txt' ] || fail "a test run held #7's change: $(lintruns)"
}

# Bug: a lint execution error on a batch's combined change sends its cards to a fix session or a test fix. Each card
# the split finds (#8, #9: every run with one of them errs) leaves with no test failure, and #7, its other cards all
# gone, is left alone in no batch, to land with no second lint run: its own gate passed where its tests did, and the
# gate never ran on its change alone.
t_lintbatcherror() {
  lbsetup '' '' '$L {files} > /dev/null; echo "lint: config broken"; exit 2' "set -- c7-7 c8-8 c9-9; $BATCH"
  grep -qx 'batch: 0 apart= mates=' "$T/$CASE/run.out" || fail "#7 is not left alone in no batch: $(cat "$T/$CASE/run.out")"
  [ ! -e "$CARDS/c8-8.batch" ] && [ ! -e "$CARDS/c9-9.batch" ] && [ ! -e "$CARDS/c8-8.test" ] && [ ! -e "$CARDS/c9-9.test" ] \
    || fail "#8 or #9 stayed in the batch, or was told a test failure: $(cat "$CARDS"/c[89]-[89].batch 2>&1)"
  ! grep -qx 'run 7.txt' "$STUB/lint-args" || fail "the gate ran again on #7's change alone: $(cat "$STUB/lint-args")"
  [ "$(lintruns)" = 7.txt ] || fail "a test run held a change that erred, or #7 ran no test: $(lintruns)"
  grep -q '^conveyor: card c7-7: the lint check found an execution error (.*config broken.*) on the change of c7-7 c8-8 c9-9' "$T/$CASE/run.out" \
    || fail "batch() did not say the lint check erred: $(cat "$T/$CASE/run.out")"
}

# Bug: a linter that is not installed stops a batch, or splits it. Its gate goes on, as for a pass: one run of the
# whole batch's tests, and every card lands.
t_lintbatchskip() {
  lbsetup 'seven BAD' 'eight BAD' 'echo "lint: missing shellcheck"; exit 127' "set -- c7-7 c8-8 c9-9; $BATCH"
  grep -qx 'batch: 0 apart= mates=c7-7 c8-8 c9-9' "$T/$CASE/run.out" || fail "the batch with a missing linter did not land every card: $(cat "$T/$CASE/run.out")"
  [ "$(lintruns)" = '7.txt 8.txt 9.txt' ] && [ -e "$CARDS/c8-8.ready" ] || fail "not one test run of the whole batch: $(lintruns)"
}

# Bug: a batch whose run passed while main moved is fitted onto main as it is now and lands on its run, with no lint
# of its change there (rebatch()). The gate runs there too: #8's finding is a red run, so rebatch() returns 3 with all
# three cards; batch() run there, as card() runs it, lands #7 and #9 and #8 leaves.
t_lintbatchmoved() {
  lbsetup '' 'eight BAD' '$L {files}' '
    for m in c7-7 c8-8 c9-9; do git -C "$CARDS/$m" diff --cached --binary --no-renames > "$CARDS/$m.bpatch"; done
    echo other > other.txt && git add other.txt && git commit -qm "another card" || exit 9
    mates=(c7-7 c8-8 c9-9); rebatch c7-7 "$W"; echo "rebatch: $? mates=${mates[*]}"
    [ "$(git -C "$W" rev-parse HEAD)" = "$(git rev-parse main)" ] || echo "#7 is not on main as it is now"
    set -- "${mates[@]}"; '"$BATCH"
  grep -qx 'rebatch: 3 mates=c7-7 c8-8 c9-9' "$T/$CASE/run.out" || fail "rebatch() did not find a red run: $(cat "$T/$CASE/run.out")"
  grep -qx "conveyor: card c7-7: the lint check failed on its batch's change on main as it is now, a red run, so the batch is run again there" "$T/$CASE/run.out" \
    || fail "rebatch() did not say its lint check failed: $(cat "$T/$CASE/run.out")"
  grep -qx 'batch: 0 apart= mates=c7-7 c9-9' "$T/$CASE/run.out" || fail "the batch on main as it is now did not land #7 and #9 without #8: $(cat "$T/$CASE/run.out")"
  [ ! -e "$CARDS/c8-8.batch" ] && [ ! -e "$CARDS/c8-8.ready" ] || fail "#8 is still in the batch, or still ready"
}
