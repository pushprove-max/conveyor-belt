#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 120
# Engine cases: where a release's whole suite runs (lib/suitehost.sh): this machine, or a Linux box over ssh, as the
# control record's suiteMachine says (docs/releases.md, Where the suite runs). The box is a stand-in ssh (boxsetup,
# below), so no case reaches a real remote machine. The release fixture is releaseboard.test.sh's runsetup
# (release.test.sh's cutsetup).
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"

# boxsetup [cpus] [ssh's exit]: an ssh on PATH that runs the command here, in $STUB/box (the box's home), with only
# HOME, PATH (the box's nproc first: <cpus>, 3 by default; then this machine's, or the folder named in $STUB/box/path) and STUB of this machine's environment, and none of its
# open files but ssh's input and output, as a login there would have: no mark of the release run, no GitHub token and
# no release lock. It notes each target in $STUB/ssh-calls. With <ssh's
# exit>, it runs nothing and fails so, as an ssh that cannot reach the box does. BOX is the run's folder there with the
# rule boxrule sets. The box's host file names testSlots 2, fewer than its CPUs, and a pool folder of its own.
boxsetup() {
  mkdir -p "$STUB/box/bin" "$STUB/box/.config/conveyor" && printf '#!/usr/bin/env bash\necho %s\n' "${1:-3}" > "$STUB/box/bin/nproc" && chmod +x "$STUB/box/bin/nproc" \
    && jq -cn --arg d "$STUB/box/slots" '{testSlots: 2, testSlotsDir: $d}' > "$STUB/box/.config/conveyor/host.json" || fail "the fixture could not be made"
  # stub: ssh to a box, with no network: the command runs here in the box's folder, its environment cleared
  printf '%s\n' '#!/usr/bin/env bash' 'while [ "${1:-}" = -o ]; do shift 2; done; [ "$1" != -- ] || shift' 'printf "%s\n" "$1" >> "$STUB/ssh-calls"; shift' \
    "${2:+echo 'ssh: connect to host box.example.com port 22: Connection refused' >&2; exit $2}" \
    'for f in /dev/fd/*; do f=${f##*/}; [ "$f" -le 2 ] || eval "exec $f>&-"; done 2> /dev/null' \
    'cd "$STUB/box" && exec env -i HOME="$STUB/box" PATH="$STUB/box/bin:$(cat "$STUB/box/path" 2> /dev/null || printf %s "$PATH")" STUB="$STUB" bash -c "$*"' > "$STUB/ssh" && chmod +x "$STUB/ssh" || fail "the fixture could not be made"
  BOX=$STUB/box/suite/main
}
# boxrule: the control record's suiteMachine, as `control suite-machine ssh` writes it, a box over ssh with its
# folder ~/suite.
boxrule() {
  local out
  # shellcheck disable=SC2088 # ~ is the box's home, given as text for the box to read
  out=$(loop control suite-machine ssh tester@box.example.com --dir '~/suite' 2>&1) && jq -e '.suiteMachine.kind == "ssh"' "$ST/control.json" > /dev/null \
    || fail "control suite-machine ssh tester@box.example.com --dir ~/suite did not set the rule: $out"
}
# The suite's body for these cases: it notes where it ran and the files at once it was told, and names two cases and
# two files as ended, in its log folder and its output, as a runner does.
BOXSUITE='pwd > "$STUB/full-pwd"; echo "$CONVEYOR_SUITE_AT_ONCE" > "$STUB/full-atonce"; mkdir -p "$CONVEYOR_TEST_LOG/cases/ok" && touch "$CONVEYOR_TEST_LOG/cases/ok/alpha" "$CONVEYOR_TEST_LOG/cases/ok/beta"; printf "TESTRUN files=2\n-- ok t/a.test.sh\n-- ok t/b.test.sh\n"'

# Bugs: a release-run prep with the ssh rule ran the suite here, or on the box with no checkout of the commit, or its
# record kept none of the box's counts; it held a test slot of this machine; its files at once were capped at this
# machine's slots, or at the box's CPUs, not its test slots (which its runner caps the run at); the status named no
# machine, or named the box's host, which a public status must not.
# This machine's pool is one slot, held by the case for the whole run, so a run that takes one here never ends; the box
# has 3 CPUs and 2 test slots, and suiteAtOnce is 9, so the cap is the box's 2.
t_hostssh() {
  local O RUN out pool=$T/$CASE/pool held
  runsetup "$BOXSUITE"; boxsetup 3; boxrule
  jq -c '.suiteAtOnce = 9' "$ST/control.json" > "$STUB/c.new" && mv "$STUB/c.new" "$ST/control.json" && mkdir -p "$pool" && : > "$pool/1" || fail "the fixture could not be made"
  # flock waits for the lock, as the try below holds it a moment, and a -n here then gave up and held no slot
  flock -o "$pool/1" sleep 120 & held=$! # sleep: holds this machine's one slot (flock's own lock) until the case ends it
  # wait_until: flock takes the lock in the background; only a try of the lock shows when it holds it.
  wait_until "! flock -n '$pool/1' true" || fail "the case could not hold the slot"
  out=$(unset CONVEYOR_TEST_SLOT; CONVEYOR_TEST_POOL=1:$pool loop release-run prep 1.1.0 --parallel 2>&1) || fail "release-run prep did not start the run: $out"
  # relwait: release-run starts the run in the background and returns; only its record shows when the run has ended.
  relwait "the run on the box did not end (one that waits for this machine's held slot never does)" '.ended != null'
  pkill -P "$held" 2>/dev/null; kill "$held" 2>/dev/null
  jq -e '.state == "passed" and .done == 2 and .files.done == 2 and .failed == 0' "$RUN" > /dev/null || fail "the run did not pass with the box's counts, 2 cases and 2 files: $(cat "$RUN") $(cat "$T/$CASE/cards/release/run.log")"
  jq -e '.machine | .kind == "ssh" and .name == "box.example.com" and .step == "done" and .reason == null and (.secs | keys) == ["checkout", "results", "run", "setup", "start"]' "$RUN" > /dev/null \
    || fail "the record's machine is not the box, done, with each step's seconds: $(jq -c .machine "$RUN")"
  [[ $(cat "$STUB/full-pwd") == "$BOX/wt" ]] && [ "$(git -C "$BOX/wt" rev-parse HEAD)" = "$O" ] && [ "$(cat "$STUB/full-at")" = "$O" ] \
    || fail "the suite did not run on the box's checkout of $O: it ran in $(cat "$STUB/full-pwd" 2>&1) on $(cat "$STUB/full-at" 2>&1)"
  [ -z "$(git -C "$BOX/wt" remote)" ] || fail "the box's checkout was given a remote, though it needs no clone access: $(git -C "$BOX/wt" remote -v)"
  [ "$(jq .atOnce "$RUN")" = 2 ] && [ "$(cat "$STUB/full-atonce")" = 2 ] || fail "files at once was not the box's 2 slots (suiteAtOnce 9, its 3 CPUs, this machine 1): record $(jq .atOnce "$RUN"), suite told $(cat "$STUB/full-atonce")"
  grep -q 'description=The whole suite (test.full) passed on a Linux box over ssh$' "$STUB/gh-calls" && ! grep -q 'box.example.com' "$STUB/gh-calls" \
    || fail "the status does not name the machine as a box over ssh, or names its host: $(cat "$STUB/gh-calls")"
}
# Bug: a red suite on the box ran its failed case alone here, on this machine's slots and checkout, not on the box. The
# box's suite fails naming the case flips; each run alone of it (CONVEYOR_TEST_RERUN set) passes and notes where it
# ran and the list it was given, so the suite passes with flips judged flaky.
t_hostalone() {
  local O RUN out
  runsetup 'if [ -n "${CONVEYOR_TEST_RERUN:-}" ]; then pwd >> "$STUB/alone-pwd"; cat "$CONVEYOR_TEST_RERUN" >> "$STUB/alone-list"; else echo "FAIL [flips]: off"; exit 1; fi'
  boxsetup 3; boxrule
  out=$(loop release-run prep 1.1.0 2>&1) || fail "release-run prep did not start the run: $out"
  # relwait: release-run starts the run in the background and returns; only its record shows when the run has ended.
  relwait "the run did not end" '.ended != null'
  jq -e '.state == "passed" and (.alone | map([.case, .verdict])) == [["flips", "flaky"]]' "$RUN" > /dev/null || fail "the box's red suite did not pass with flips judged flaky: $(cat "$RUN") $(cat "$T/$CASE/cards/release/run.log")"
  [ "$(sort -u "$STUB/alone-pwd")" = "$BOX/wt" ] && [ "$(wc -l < "$STUB/alone-pwd")" = 3 ] && grep -q $'^fail\t.*flips$' "$STUB/alone-list" \
    || fail "flips was not run alone 3 times on the box's checkout with its list: ran in $(sort "$STUB/alone-pwd" 2>&1 | uniq -c | paste -sd' ' -), list $(cat "$STUB/alone-list" 2>&1)"
}
# Bug: a box that cannot be reached still ran the suite here, or ended as refused or failed, with a failure posted on
# the commit, rather than not started with ssh's reason. Nothing runs anywhere and no worktree is made.
t_hostnostart() {
  local O RUN out
  runsetup "$BOXSUITE"; boxsetup 3 255; boxrule
  out=$(loop release-run prep 1.1.0 2>&1) || fail "release-run prep did not start the run: $out"
  # relwait: release-run starts the run in the background and returns; only its record shows when the run has ended.
  relwait "the run did not end" '.ended != null'
  jq -e '.state == "not started" and (.machine.reason | test("does not answer over ssh: .*Connection refused")) and .machine.step == "start"
    and any(.reasons[]; test("the suite was not started on box.example.com"))' "$RUN" > /dev/null \
    || fail "a box that ssh cannot reach did not end the run not started with ssh's reason: $(cat "$RUN")"
  # Bug (#1271): the record named no commit until the box was ready, so the Board's line for the box's first steps had none.
  jq -e '.sha | strings | test("^[0-9a-f]{40}$")' "$RUN" > /dev/null || fail "a run not started on its box has no commit in its record: $(cat "$RUN")"
  [ ! -e "$STUB/runs" ] && [ ! -e "$T/$CASE/cards/release/wt" ] || fail "the suite ran, or its worktree was made, though the box could not start: $(cat "$STUB/runs" 2>&1)"
  ! grep -q -- '-X POST' "$STUB/gh-calls" 2>/dev/null || fail "a run not started posted a status: $(cat "$STUB/gh-calls")"
}
# Bug (#1285): a box with no jq was started on: its check named git alone, and slot_pool there ignores a missing jq and
# falls back to the CPU count, so the suite started where its jq cases cannot run. The box's PATH holds the tools the
# check needs and no jq: the run ends not started, naming jq, with nothing run.
t_hostnojq() {
  local O RUN out t
  runsetup "$BOXSUITE"; boxsetup 3; boxrule
  mkdir -p "$STUB/box/nojq" || fail "the fixture could not be made"
  for t in bash git grep sed cat tr sort tail head wc mkdir dirname uname flock getconf readlink env; do
    ln -sf "$(command -v "$t")" "$STUB/box/nojq/$t" || fail "the fixture could not be made: $t"
  done
  printf %s "$STUB/box/nojq" > "$STUB/box/path"
  out=$(loop release-run prep 1.1.0 2>&1) || fail "release-run prep did not start the run: $out"
  # relwait: release-run starts the run in the background and returns; only its record shows when the run has ended.
  relwait "the run did not end" '.ended != null'
  jq -e '.state == "not started" and (.machine.reason | test("jq is not installed there")) and .machine.step == "start"' "$RUN" > /dev/null     || fail "a box with no jq did not end the run not started, naming jq: $(cat "$RUN")"
  [ ! -e "$STUB/runs" ] && [ ! -e "$T/$CASE/cards/release/wt" ] || fail "the suite ran, or its worktree was made, though the box has no jq: $(cat "$STUB/runs" 2>&1)"
}
# Bug: a control record with no suiteMachine ran the suite anywhere but here, or reached for ssh. The record leaves the
# key out, as one written before the rule did.
t_hostlocal() {
  local O RUN out
  runsetup "$BOXSUITE"; boxsetup 3
  jq -c 'del(.suiteMachine)' "$ST/control.json" > "$STUB/c.new" && mv "$STUB/c.new" "$ST/control.json" || fail "the fixture could not be made"
  out=$(loop release-run prep 1.1.0 2>&1) || fail "release-run prep did not start the run: $out"
  # relwait: release-run starts the run in the background and returns; only its record shows when the run has ended.
  relwait "the run did not end" '.ended != null'
  jq -e '.state == "passed" and .done == 2 and (.machine | .kind == "local" and .name == "this machine" and .step == "done")' "$RUN" > /dev/null \
    || fail "the run with no suiteMachine did not pass here: $(cat "$RUN") $(cat "$T/$CASE/cards/release/run.log")"
  [ "$(cat "$STUB/full-pwd")" = "$T/$CASE/cards/release/wt" ] && [ ! -e "$STUB/ssh-calls" ] || fail "the suite did not run in this machine's worktree, or ssh was called: $(cat "$STUB/full-pwd") $(cat "$STUB/ssh-calls" 2>&1)"
  grep -q 'description=The whole suite (test.full) passed on the build machine$' "$STUB/gh-calls" || fail "the status does not name the build machine: $(cat "$STUB/gh-calls")"
}
# Bugs: release-run's --machine local still ran the suite on the box the rule names, or changed the rule, so later runs
# ran here too; or it reused a pass of every file the box had made on the same commit, so no test ran here and the
# record still named this machine. The suite record holds such a pass on the commit.
t_hostonce() {
  local O RUN out
  runsetup "$BOXSUITE"; boxsetup 3; boxrule
  jq -cn --arg o "$O" '{sha: $o, time: "t1", by: "release-prep", machine: "ssh", files: {"t/a.test.sh": "ok", "t/b.test.sh": "ok"}}' > "$ST/suites.jsonl" || fail "the fixture could not be made"
  out=$(loop release-run prep 1.1.0 --serial --machine local 2>&1) || fail "release-run prep --machine local did not start the run: $out"
  # relwait: release-run starts the run in the background and returns; only its record shows when the run has ended.
  relwait "the run did not end" '.ended != null'
  jq -e '.state == "passed" and .mode == "serial" and .machine.kind == "local" and .reused == null' "$RUN" > /dev/null || fail "the run with --machine local did not pass here, or reused the box's pass: $(cat "$RUN") $(cat "$T/$CASE/cards/release/run.log")"
  [ "$(cat "$STUB/full-pwd")" = "$T/$CASE/cards/release/wt" ] && [ ! -e "$STUB/ssh-calls" ] || fail "--machine local reached the box: $(cat "$STUB/ssh-calls" 2>&1)"
  jq -e '.suiteMachine == {kind: "ssh", target: "tester@box.example.com", dir: "~/suite"}' "$ST/control.json" > /dev/null || fail "--machine local changed the rule: $(jq -c .suiteMachine "$ST/control.json")"
}
# Bug: `release-run prep <version> --machine local` exports CONVEYOR_RELEASE_MACHINE to the suite it runs, and this
# project's suite runs these cases: with it set, hostrule took this machine over the fixture's ssh rule and hostcheck failed.
# A fresh bash (bash -c) sources the shared setup with the variable set, as that suite's environment has it.
t_hostenv() {
  local out
  out=$(CONVEYOR_RELEASE_MACHINE=local bash -c '. "$1/tests/lib.sh"; printf "%s" "${CONVEYOR_RELEASE_MACHINE-unset}"' _ "$SRC" 2>&1)
  [ "${out##*$'\n'}" = unset ] || fail "tests/lib.sh left CONVEYOR_RELEASE_MACHINE=local set for the cases: $out"
}
# Bug: release-run <version> --machine local, after a release-prep of that version passed on the box on main's head,
# released on the box's pass, so no suite ran here. The run record is that pass; the run must run release-prep here.
t_hostoncego() {
  local O RUN out
  runsetup "$BOXSUITE"; boxsetup 3; boxrule
  mkdir -p "$T/$CASE/cards/release" && jq -cn --arg o "$O" '{kind: "release", step: "release-prep", version: "1.1.0", state: "passed", sha: $o, moved: false, ended: "t1",
    machine: {kind: "ssh", name: "box.example.com", target: "tester@box.example.com", dir: "~/suite", step: "done", secs: {}, reason: null}}' > "$RUN" || fail "the fixture could not be made"
  out=$(loop release-run 1.1.0 --machine local 2>&1) && grep -q 'release-prep 1.1.0 is running, then release 1.1.0' <<<"$out" \
    || fail "release-run 1.1.0 --machine local did not start release-prep here over the box's pass on $O: $out"
  # relwait: release-run starts the run in the background and returns; only its record shows when the run has ended.
  relwait "the run did not end released" '.step == "release" and .ended != null'
  [ "$(cat "$STUB/full-pwd")" = "$T/$CASE/cards/release/wt" ] && [ ! -e "$STUB/ssh-calls" ] || fail "the suite did not run here, or the box was reached: $(cat "$STUB/full-pwd" 2>&1) $(cat "$STUB/ssh-calls" 2>&1)"
}
# Bug (#1284): a release-prep with the local rule reused a pass of every file the box had made on the same commit, and
# its record named this machine alone, so a later release-run --machine local took that pass as one made here. The
# record's reused must name the box.
t_hostreusebox() {
  local O RUN out
  runsetup "$BOXSUITE"
  jq -cn --arg o "$O" '{sha: $o, time: "t1", by: "release-prep", machine: "ssh", files: {"t/a.test.sh": "ok", "t/b.test.sh": "ok"}}' > "$ST/suites.jsonl" || fail "the fixture could not be made"
  out=$(loop release-run prep 1.1.0 2>&1) || fail "release-run prep did not start the run: $out"
  # relwait: release-run starts the run in the background and returns; only its record shows when the run has ended.
  relwait "the run did not end" '.ended != null'
  jq -e --arg o "$O" '.state == "passed" and .machine.kind == "local" and .reused == {sha: $o, time: "t1", ran: [], kept: 2, machine: "ssh"}' "$RUN" > /dev/null \
    || fail "release-run prep over the box's pass on $O did not reuse it, or its record does not say the pass is the box's: $(cat "$RUN") $(cat "$T/$CASE/cards/release/run.log")"
}
# Bug (#1284): release-run <version> --machine local, after a release-prep here that reused the box's pass on main's
# head, released on that pass, so no suite ran here. The run record is that pass; the run must run release-prep here.
t_hostreusego() {
  local O RUN out
  runsetup "$BOXSUITE"
  mkdir -p "$T/$CASE/cards/release" && jq -cn --arg o "$O" '{kind: "release", step: "release-prep", version: "1.1.0", state: "passed", sha: $o, moved: false, ended: "t1",
    machine: {kind: "local", name: "this machine", target: "", dir: "", step: "done", secs: {}, reason: null}, reused: {sha: $o, time: "t0", ran: [], kept: 2, machine: "ssh"}}' > "$RUN" || fail "the fixture could not be made"
  out=$(loop release-run 1.1.0 --machine local 2>&1) && grep -q 'release-prep 1.1.0 is running, then release 1.1.0' <<<"$out" \
    || fail "release-run 1.1.0 --machine local did not start release-prep here over the reused box's pass on $O: $out"
  # relwait: release-run starts the run in the background and returns; only its record shows when the run has ended.
  relwait "the run did not end released" '.step == "release" and .ended != null'
  [ "$(cat "$STUB/full-pwd" 2>/dev/null)" = "$T/$CASE/cards/release/wt" ] || fail "release-run 1.1.0 --machine local ran no suite here: $(cat "$T/$CASE/cards/release/run.log")"
}
# Bug: release-run stop ended the run here but left its suite running on the box. The box's processes are no child of
# the run and carry no mark of it (boxsetup), as on a real box, so only a stop sent over ssh ends them.
t_hoststop() {
  local O RUN out
  runsetup 'sleep 300 & echo $! > "$STUB/box-sleep"; wait'; boxsetup 3; boxrule # sleep: the box's suite, which only the stop ends
  out=$(loop release-run prep 1.1.0 2>&1) || fail "release-run prep did not start the run: $out"
  # wait_until: the suite starts on the box in the background; only its note there shows when it runs.
  wait_until '[ -s "$STUB/box-sleep" ]' || fail "the suite did not start on the box: $(cat "$T/$CASE/cards/release/run.log" 2>&1)"
  jq -e '.machine.step == "run"' "$RUN" > /dev/null || fail "the record does not say the box's run is under way: $(jq -c .machine "$RUN")"
  out=$(loop release-run stop 2>&1) || fail "the stop failed: $out"
  # wait_until: a process sent TERM ends a moment later; only a check of it shows when it has.
  wait_until "! kill -0 $(cat "$STUB/box-sleep") 2>/dev/null" || { kill "$(cat "$STUB/box-sleep")"; fail "the suite still runs on the box after release-run stop: $out"; }
  jq -e '.state == "stopped"' "$RUN" > /dev/null || fail "the record does not say stopped: $(cat "$RUN")"
}
# The box's .conveyor/test-machine.sh runs once a blob (hostsetup(), called as relsuite() calls it): a commit with the
# same script does not run it again, one that changes it does. Bug: it ran on every release, or never again once a
# box had run it. It notes each run, and where it ran, in $STUB/setups.
t_hostsetuponce() {
  local s1 s2 n
  setup '[]'; boxsetup 3
  mkdir -p "$R/.conveyor" && printf 'pwd >> "$STUB/setups"\n' > "$R/.conveyor/test-machine.sh" && git -C "$R" add -f .conveyor/test-machine.sh && git -C "$R" commit -qm setup \
    && s1=$(git -C "$R" rev-parse HEAD) && echo '# a change' >> "$R/.conveyor/test-machine.sh" && git -C "$R" commit -qam 'setup again' && s2=$(git -C "$R" rev-parse HEAD) \
    || fail "the fixture could not be made"
  # shellcheck disable=SC2034,SC2088 # the variables are suitehost.sh's, read by its functions; ~ is the box's home, as text
  n=$(cd "$R" && REPO=main; relrec() { :; }; . "$SRC/lib/suitehost.sh" && SH_KIND=ssh SH_TARGET=tester@box.example.com SH_DIR='~/suite' && hostd \
    && hostsetup t "$s1" && hostsetup t "$s1" && wc -l < "$STUB/setups" && hostsetup t "$s2" && wc -l < "$STUB/setups") || fail "the setup failed: $n"
  [ "$(paste -sd' ' <<<"$n")" = '1 2' ] && [ "$(sort -u "$STUB/setups")" = "$STUB/box/suite/main" ] \
    || fail "the setup did not run once for each blob, in the box's folder: counts $(paste -sd' ' <<<"$n"), ran in $(sort -u "$STUB/setups" | paste -sd' ' -)"
}
# boxrun <worktree> <suite command> [<name>=<value>...]: hosttests() on the box as relsuite() calls it, the pack's
# test.full given as <suite command>, with each variable set; prints its exit.
boxrun() {
  local w=$1 c=$2; shift 2
  mkdir -p "$BOX/wt" || fail "the fixture could not be made"
  # shellcheck disable=SC2034,SC2088 # the variables are suitehost.sh's, read by its functions; ~ is the box's home, as text
  (cd "$R" && REPO=main; relrec() { :; }; packget() { printf -v "$2" %s "$c"; }; . "$SRC/lib/suitehost.sh" && for v; do export "${v?}"; done \
    && SH_KIND=ssh SH_NAME=box.example.com SH_TARGET=tester@box.example.com SH_DIR='~/suite' SH_STEP=run && hostd && { hosttests "$w" test.full; echo $?; })
}
# Bug: a suite on a box over ssh ran on past the pack's testTimeout, where a run here is stopped there, so the release,
# and every card held for it, waited on it. The box's suite sleeps 300 s, the limit is 2 s and a poll 3 s (HOSTPOLL): it
# is stopped there a poll past the limit and the exit is 124, a run here's that timed out. The wait for its end is 20 s,
# far short of the sleep, so a suite left running fails the case.
t_hostdeadline() {
  local rc w=$T/$CASE/wt
  setup '[]'; boxsetup 3
  rc=$(boxrun "$w" 'sleep 300 & echo $! > "$STUB/box-sleep"; wait' TEST_TIMEOUT=2 HOSTPOLL=3) # sleep: the box's suite, which only the time limit ends
  [ "$rc" = 124 ] && grep -q 'ran past its time limit, 2 s (testTimeout), on box.example.com and was stopped there' "$w.test" \
    || fail "hosttests with testTimeout 2 and a box's suite that sleeps 300 s did not end it at the limit with exit 124: exit $rc, output $(cat "$w.test" 2>&1)"
  # wait_until: a process sent TERM ends a moment later; only a check of it shows when it has.
  WAIT_CEILING=20 wait_until "! kill -0 $(cat "$STUB/box-sleep") 2>/dev/null" || { kill "$(cat "$STUB/box-sleep")"; fail "the suite still runs on the box after its time limit"; }
}
# Bug: a box's suite that ended with 0 past testTimeout passed, as its exit was copied back before the limit was
# checked, where a run here past it is stopped and fails. The suite sleeps 3 s with a limit of 2 s and passes.
t_hostlate() {
  local rc w=$T/$CASE/wt
  setup '[]'; boxsetup 3
  rc=$(boxrun "$w" 'sleep 3' TEST_TIMEOUT=2) # sleep: a box's suite that ends, with 0, a second past the limit
  [ "$rc" = 124 ] && grep -qx 'conveyor: the suite ran past its time limit, 2 s (testTimeout), on box.example.com' "$w.test" \
    || fail "hosttests with testTimeout 2 and a box's suite that ends with 0 after 3 s did not end with exit 124 as timed out: exit $rc, output $(cat "$w.test" 2>&1)"
}
# Bug: a poll of the box that ssh reached but that never ended (here the box's tar, which sends the run's output back,
# hangs) held the run for ever: no live record, no failed poll counted. Each poll ends at HOSTPOLL (2 s here), so six
# such polls end the run as a box that stopped answering, with its live record kept up to date meanwhile.
t_hoststall() {
  local rc w=$T/$CASE/wt t
  setup '[]'; boxsetup 3; t=$(command -v tar)
  printf '#!/usr/bin/env bash\n[ "$1" != -cf ] || exec sleep 60\nexec %q "$@"\n' "$t" > "$STUB/box/bin/tar" && chmod +x "$STUB/box/bin/tar" || fail "the fixture could not be made" # sleep: a tar that never sends its archive, as on a box that stalls
  rc=$(boxrun "$w" ':' HOSTPOLL=2)
  [ "$rc" = 1 ] && grep -q 'box.example.com stopped answering over ssh while the suite ran there' "$w.test" && jq -e '.step == "test" and .last != ""' "$w.live" > /dev/null \
    || fail "hosttests with HOSTPOLL 2 and a box whose polls stall did not end as a box that stopped answering, with a live record: exit $rc, output $(cat "$w.test" 2>&1), live $(cat "$w.live" 2>&1)"
}
# `suite-machine check` names each need of the rule's box, ok or missing. Bugs: a tool .conveyor/test-machine.sh names
# was not checked, a missing one passed the check, or the box's slots were its CPUs, not its pool's. The box has 3 CPUs
# and 2 test slots, and the script names a tool no box has.
t_hostcheck() {
  local out
  setup '[]'; boxsetup 3; boxrule
  mkdir -p "$R/.conveyor" && printf '# tools: git notatool-1273\n' > "$R/.conveyor/test-machine.sh" || fail "the fixture could not be made"
  out=$(loop suite-machine check 2>&1); [ $? = 1 ] && grep -qx 'ok: ssh: tester@box.example.com answers' <<<"$out" && grep -qx 'ok: bash 5.1+: bash [0-9.]*' <<<"$out" \
    && grep -qx 'missing: notatool-1273: not installed (.conveyor/test-machine.sh)' <<<"$out" && grep -qx 'ok: test slots: 3 CPUs, 2 test slots' <<<"$out" \
    || fail "suite-machine check did not name each need of the box, with the missing tool: $out"
  out=$(loop suite-machine check --json 2>&1)
  jq -e '.kind == "ssh" and .ok == false and .cpus == 3 and .slots == 2 and ([.needs[] | select(.ok | not) | .need] == ["notatool-1273"])
    and ([.needs[].need] == ["ssh", "bash 5.1+", "jq", "git", "notatool-1273", "test slots"])' <<<"$out" > /dev/null \
    || fail "suite-machine check --json does not hold the box's needs, with only the tool missing: $out"
  # Bug: `release-run atonce`, which the Foreman's release question names, printed this machine's cap with the ssh
  # rule. suiteAtOnce is 9 and this machine has one slot: the box's 2 is the answer.
  jq -c '.suiteAtOnce = 9' "$ST/control.json" > "$STUB/c.new" && mv "$STUB/c.new" "$ST/control.json" || fail "the fixture could not be made"
  out=$(unset CONVEYOR_TEST_SLOT; CONVEYOR_TEST_POOL=1:$T/$CASE/pool loop release-run atonce 2>&1) && [ "$out" = 2 ] \
    || fail "release-run atonce with the ssh rule, suiteAtOnce 9, the box's 3 CPUs and 2 slots and one slot here did not print 2: $out"
}
# The stand-in devbox of the cases below: no case reaches a Namespace account. It notes each call in $STUB/devbox-calls,
# an exec by what its script does (facts, setup, checkout, upload, run, poll or kill: the box's steps), and runs the script in
# the box's folder as boxsetup's ssh does; a lease it handed out (acquire) is held until release, and an exec or a
# release of any other lease, or of one given back, fails. A file $STUB/devbox-nologin is a login that has expired.
DEVBOX='#!/usr/bin/env bash
L=lease-1274
note() { printf "%s\n" "$*" >> "$STUB/devbox-calls"; }
case $1 in
  auth) note "$@"; [ ! -e "$STUB/devbox-nologin" ] || { echo "not logged in" >&2; exit 1; } ;;
  acquire) note "$@"; echo "Leasing a devbox"; echo "$L"; : > "$STUB/devbox-leased" ;;
  release) note "$@"; [ "$2 $3" = "--lease_id $L" ] && [ -e "$STUB/devbox-leased" ] || { echo "no such lease" >&2; exit 1; }; rm -f "$STUB/devbox-leased"; echo "$L" >> "$STUB/devbox-released" ;;
  exec) shift; d=; [ "${1:-}" != -d ] || { d=-d; shift; }
    [ "$1 $2 $3" = "--lease_id $L --" ] && [ -e "$STUB/devbox-leased" ] || { echo "no such lease" >&2; exit 1; }
    shift 3; s=$*
    case $s in *setup.blob*) t=setup ;; *wt.bundle*) t=checkout ;; *nohup*) t=run ;; *"tar -cf"*) t=poll ;; *"tar -xf"*) t=upload ;; *"kill -TERM"*) t=kill ;; *) t=facts ;; esac
    note "exec${d:+ -d} $t"
    [ -z "$d" ] || exec < /dev/null
    for f in /dev/fd/*; do f=${f##*/}; [ "$f" -le 2 ] || eval "exec $f>&-"; done 2> /dev/null
    cd "$STUB/box" && exec env -i HOME="$STUB/box" PATH="$STUB/box/bin:$(cat "$STUB/box/path" 2> /dev/null || printf %s "$PATH")" STUB="$STUB" "$@" ;;
  *) note "$@"; exit 2 ;;
esac'
# devboxsetup [cpus]: the release fixture with the stand-in box (boxsetup), the stand-in devbox on PATH and the devbox
# rule (control suite-machine devbox); BOX is the run's folder, under the box's home. Fails the case when the devbox on
# PATH is not the stand-in, so a real one is never called.
devboxsetup() {
  local out
  boxsetup "${1:-3}"
  # stub: a devbox with no Namespace account, which hands out one lease
  printf '%s\n' "$DEVBOX" > "$STUB/devbox" && chmod +x "$STUB/devbox" || fail "the fixture could not be made"
  [ "$(command -v devbox)" = "$STUB/devbox" ] || fail "devbox on PATH is not the stand-in: $(command -v devbox)"
  out=$(loop control suite-machine devbox --size 4x8 2>&1) || fail "control suite-machine devbox --size 4x8 did not set the rule: $out"
  BOX=$STUB/box/conveyor-suite/main
}
# devboxcalls: the calls the stand-in devbox had, each run of equal calls once, joined by ";".
devboxcalls() { uniq "$STUB/devbox-calls" | paste -sd';' -; }
# Bugs (D1, D7): a release-run prep with the devbox rule did not lease the devbox with the size and the idle stop, ran a
# step out of its order (start, setup, checkout, run, results), ran the suite elsewhere than the devbox's checkout of
# the commit, started the run attached (not `exec -d`), reached for ssh, named another machine in the record or the
# status, or left the lease held. The stand-in devbox fails an exec on a lease given back.
t_devboxrun() {
  local O RUN out
  runsetup "$BOXSUITE"; devboxsetup 3
  # The commit carries a .conveyor/test-machine.sh that notes where it ran: only the devbox's own run of it proves the setup step ran.
  mkdir -p "$R/.conveyor" && printf 'pwd >> "$STUB/setups"\n' > "$R/.conveyor/test-machine.sh" && git -C "$R" add -f .conveyor/test-machine.sh && git -C "$R" commit -qm 'machine setup' \
    && git -C "$R" push -q origin main && O=$(git -C "$R" rev-parse HEAD) || fail "the fixture could not be made"
  out=$(loop release-run prep 1.1.0 2>&1) || fail "release-run prep did not start the run: $out"
  # relwait: release-run starts the run in the background and returns; only its record shows when the run has ended.
  relwait "the run on the devbox did not end" '.ended != null'
  jq -e '.state == "passed" and .done == 2 and .failed == 0' "$RUN" > /dev/null || fail "the run did not pass with the devbox's counts: $(cat "$RUN") $(cat "$T/$CASE/cards/release/run.log")"
  jq -e '.machine | .kind == "devbox" and .name == "Namespace Devbox 4x8" and .lease == "lease-1274" and .target == null and .dir == null and .step == "done" and .reason == null
    and (.secs | keys_unsorted) == ["start", "setup", "checkout", "run", "results"]' "$RUN" > /dev/null \
    || fail "the record's machine is not the devbox, done, with each step's seconds in order: $(jq -c .machine "$RUN")"
  [ "$(devboxcalls)" = 'auth check-login;acquire conveyor-suite-main --size 4x8 --auto_stop_idle_timeout 15m;exec facts;exec setup;exec checkout;exec upload;exec -d run;exec poll;release --lease_id lease-1274' ] \
    || fail "the devbox's calls are not login, acquire, facts, setup, checkout, upload, run detached, polls, release: $(devboxcalls)"
  [ "$(cat "$STUB/devbox-released")" = lease-1274 ] && [ ! -e "$STUB/devbox-leased" ] && [ ! -e "$STUB/ssh-calls" ] || fail "the lease was not given back once, or ssh was called: $(cat "$STUB/devbox-released" 2>&1) $(cat "$STUB/ssh-calls" 2>&1)"
  [ "$(cat "$STUB/setups" 2>&1)" = "$BOX" ] || fail "the commit's .conveyor/test-machine.sh did not run once in the devbox's run folder $BOX: $(cat "$STUB/setups" 2>&1)"
  [ "$(cat "$STUB/full-pwd")" = "$BOX/wt" ] && [ "$(git -C "$BOX/wt" rev-parse HEAD)" = "$O" ] || fail "the suite did not run on the devbox's checkout of $O: $(cat "$STUB/full-pwd" 2>&1)"
  grep -q 'description=The whole suite (test.full) passed on Namespace Devbox 4x8$' "$STUB/gh-calls" || fail "the status does not name the machine as Namespace Devbox 4x8: $(cat "$STUB/gh-calls")"
  out=$(loop snapshot --fresh | jq -c '.suites[] | select(.kind == "release") | .machine.name') && [ "$out" = '"Namespace Devbox 4x8"' ] || fail "the snapshot does not name the run's machine as Namespace Devbox 4x8: $out"
  # Bug: suite-machine check named no login for the devbox rule, or asked a devbox that is leased for a run only for
  # bash, tools and slots, so it always read missing.
  out=$(loop suite-machine check 2>&1) && [ "$out" = "$(printf 'conveyor: suite-machine: the suite runs on Namespace Devbox 4x8\nok: Namespace login: logged in')" ] \
    || fail "suite-machine check with a login did not report the Namespace login alone as ok: $out"
  # Bug: release-run atonce printed this machine's cap for the devbox rule, as the box's slots are known only to a run.
  out=$(loop release-run atonce 2>&1); [ $? = 1 ] && grep -q 'read when a run leases it' <<<"$out" || fail "release-run atonce with the devbox rule did not refuse to print a number: $out"
}
# Bug (D5): release-run stop during a run on a devbox ended the run here and left the suite going on the devbox, and the
# lease held until its idle stop. The suite is a sleep the devbox's processes carry no mark of: only a stop sent to the
# devbox ends it, and the lease is given back.
t_devboxstop() {
  local O RUN out
  runsetup 'sleep 300 & echo $! > "$STUB/box-sleep"; wait'; devboxsetup 3 # sleep: the devbox's suite, which only the stop ends
  out=$(loop release-run prep 1.1.0 2>&1) || fail "release-run prep did not start the run: $out"
  # wait_until: the suite starts on the devbox in the background; only its note there shows when it runs.
  wait_until '[ -s "$STUB/box-sleep" ]' || fail "the suite did not start on the devbox: $(cat "$T/$CASE/cards/release/run.log" 2>&1)"
  jq -e '.machine.step == "run" and .machine.lease == "lease-1274"' "$RUN" > /dev/null || fail "the record does not say the devbox's run is under way, with its lease: $(jq -c .machine "$RUN")"
  [ ! -e "$STUB/devbox-released" ] || fail "the lease was given back while the suite ran: $(cat "$STUB/devbox-released")"
  out=$(loop release-run stop 2>&1) || fail "the stop failed: $out"
  # wait_until: a process sent TERM ends a moment later; only a check of it shows when it has.
  wait_until "! kill -0 $(cat "$STUB/box-sleep") 2>/dev/null" || { kill "$(cat "$STUB/box-sleep")"; fail "the suite still runs on the devbox after release-run stop: $out"; }
  jq -e '.state == "stopped"' "$RUN" > /dev/null || fail "the record does not say stopped: $(cat "$RUN")"
  [ "$(cat "$STUB/devbox-released" 2>&1)" = lease-1274 ] && [ ! -e "$STUB/devbox-leased" ] || fail "release-run stop did not give the lease back once: $(cat "$STUB/devbox-released" 2>&1); calls $(devboxcalls)"
}
# Bug ("Not logged in to Namespace"): a run with an expired login went on to acquire a devbox, or ended refused or
# failed, with a status posted, rather than not started with that reason; suite-machine check reported the login ok.
t_devboxlogin() {
  local O RUN out
  runsetup "$BOXSUITE"; devboxsetup 3; : > "$STUB/devbox-nologin"
  out=$(loop release-run prep 1.1.0 2>&1) || fail "release-run prep did not start the run: $out"
  # relwait: release-run starts the run in the background and returns; only its record shows when the run has ended.
  relwait "the run did not end" '.ended != null'
  jq -e '.state == "not started" and .machine.reason == "Not logged in to Namespace" and .machine.step == "start" and .machine.lease == null
    and any(.reasons[]; test("the suite was not started on Namespace Devbox 4x8: Not logged in to Namespace"))' "$RUN" > /dev/null \
    || fail "an expired login did not end the run not started with Not logged in to Namespace: $(cat "$RUN")"
  [ "$(devboxcalls)" = 'auth check-login' ] && [ ! -e "$STUB/runs" ] && [ ! -e "$T/$CASE/cards/release/wt" ] || fail "the run went on past the login: $(devboxcalls); $(cat "$STUB/runs" 2>&1)"
  ! grep -q -- '-X POST' "$STUB/gh-calls" 2>/dev/null || fail "a run not started posted a status: $(cat "$STUB/gh-calls")"
  out=$(loop suite-machine check --json 2>&1); [ $? = 1 ] && jq -e '.kind == "devbox" and .ok == false and .needs == [{need: "Namespace login", ok: false, detail: "Not logged in to Namespace"}]' <<<"$out" > /dev/null \
    || fail "suite-machine check --json with an expired login did not report the Namespace login as missing: $out"
}
# Bug: a devbox leased for a run that then failed to start (here its box has no jq, so the check ends the run not
# started) stayed leased until its idle stop. The lease is given back once, and nothing runs.
t_devboxfail() {
  local O RUN out t
  runsetup "$BOXSUITE"; devboxsetup 3
  mkdir -p "$STUB/box/nojq" || fail "the fixture could not be made"
  for t in bash git grep sed cat tr sort tail head wc mkdir dirname uname flock getconf readlink env; do
    ln -sf "$(command -v "$t")" "$STUB/box/nojq/$t" || fail "the fixture could not be made: $t"
  done
  printf %s "$STUB/box/nojq" > "$STUB/box/path"
  out=$(loop release-run prep 1.1.0 2>&1) || fail "release-run prep did not start the run: $out"
  # relwait: release-run starts the run in the background and returns; only its record shows when the run has ended.
  relwait "the run did not end" '.ended != null'
  jq -e '.state == "not started" and (.machine.reason | test("jq is not installed there")) and .machine.step == "start"' "$RUN" > /dev/null || fail "a devbox with no jq did not end the run not started, naming jq: $(cat "$RUN")"
  [ "$(cat "$STUB/devbox-released" 2>&1)" = lease-1274 ] && [ ! -e "$STUB/devbox-leased" ] && [ ! -e "$STUB/runs" ] || fail "the lease was not given back once, or the suite ran: $(cat "$STUB/devbox-released" 2>&1); calls $(devboxcalls)"
}
