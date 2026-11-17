#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 120
# Engine cases: the Board's Record CPU time on a Wall only test file (#190): cpuplan() (lib/testfiles.sh) says whether
# conveyor/tools/testtime.sh can wrap the pack's test command for the file, `conveyor.sh test-settings cpu-time <file>`
# saves that command, and a run of it records the file's CPU seconds (timed(), lib/testrun.sh). fx_in and fx_wt are in
# lib.sh.
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"

# Bug it catches: a Wall only file had no way to record its CPU seconds, or the saved command still gave none. The test
# command runs one test file, w.test.sh, so the plan wraps it; test-settings cpu-time saves that command; and the next
# run of it, as a card's Test step runs it, records w.test.sh with CPU seconds, so its Wall only status clears. The
# run adds the runner's report args (test.report.args, reportask()) at the command's end, as a card's run does: they
# reach the test command, not the wrapper's own last word (a passing run failed with "exit: too many arguments").
t_cputimesave() {
  setup '[]'; tune '.test.command = "bash w.test.sh" | del(.test.list) | .test.report = {runner: "bash", args: "--report <file>"}'
  fx_wt ':' w.test.sh '[ "$1" = --report ] || exit 4; i=0; while [ $i -lt 20000 ]; do i=$((i + 1)); done; echo done-w'
  fx_in 'p=$(cpuplan) && jq -e ".file == \"w.test.sh\" and .was == \"bash w.test.sh\"" <<<"$p" > /dev/null && testsettings cpu-time w.test.sh \
    && [ "$(jq -r .test.command "$R/.conveyor/project.json")" = "$(jq -r .command <<<"$p")" ] \
    && TEST_CMD=$(jq -r .command <<<"$p") tests "$FXWT" test.command alone && grep -q done-w "$FXWT.test" && timed "$FXWT"'
  [ "$RC" = 0 ] || fail "Record CPU time was not saved, or its run failed: $(cat "$T/$CASE/run.out")"
  jq -e '."w.test.sh" | .cpu | numbers' < <(tail -n 1 "$T/$CASE/run.out") > /dev/null || fail "the run of the saved command gave w.test.sh no CPU seconds: $(cat "$T/$CASE/run.out")"
  # Its exit is the file's own: a failing file still fails the run.
  printf 'exit 3\n' > "$FXWT/w.test.sh"
  fx_in '! tests "$FXWT" test.command alone'
  [ "$RC" = 0 ] || fail "the wrapped command passed a failing test file"
}

# Bug it catches: Record CPU time saved a wrapper where it cannot time one file, so every file got the same time or
# none. With a test list, a command of more than one part, or one that names more than one test file, the plan says
# why, and test-settings cpu-time refuses and leaves the pack as it was.
t_cputimerefused() {
  local p before
  FXWT=; setup '[]'; printf 'exit 0\n' > "$R/a.test.sh"; printf 'exit 0\n' > "$R/b.test.sh"; git -C "$R" add a.test.sh b.test.sh && git -C "$R" commit -qm tests
  for p in '"bash a.test.sh"|args|given the test files of each card' '"bash a.test.sh; true"||not one plain command' \
    '"bash a.test.sh b.test.sh"||runs more than one test file' '"bash tests"|none|runs more than one test file'; do
    tune --argjson c "${p%%|*}" --arg l "$(cut -d'|' -f2 <<<"$p")" '.test.command = $c | if $l == "" then del(.test.list) else .test.list = $l end'
    before=$(cat "$R/.conveyor/project.json")
    fx_in 'cpuplan; ! testsettings cpu-time a.test.sh'
    [ "$RC" = 0 ] && grep -qF -- "${p##*|}" "$T/$CASE/run.out" || fail "the command ${p%%|*} was not refused with why: $(cat "$T/$CASE/run.out")"
    [ "$(cat "$R/.conveyor/project.json")" = "$before" ] || fail "a refused Record CPU time changed the pack (${p%%|*})"
  done
}
