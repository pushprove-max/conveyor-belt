#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 120
# Engine cases: a devbox whose `devbox exec` passes no standard input (lib/suitehost.sh). Its own file, to keep the
# suitehost case file under the 600 lines a case file may have. The helpers and the stand-in devbox are that file's
# (devboxsetup, DEVBOX, whose exec gives the box no input, as the real one does).
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"

# Bug: `devbox exec` passes no standard input, so the box read none of lib/slots.sh, slot_pool was not defined there, and the
# test slots were empty: a release suite never started ("its test slots cannot be read"), and suite-machine check passed
# a named box with no CPU count or slots. Here exec gives the box no input; the check reads both, and says not fit when
# the box cannot give its slots (no mkdir: slot_pool cannot make its slot folder).
t_devboxnostdin() {
  local out t
  setup '[]'; devboxsetup 3
  echo '[{"name":"hand-made"}]' > "$STUB/devbox-list"
  loop control suite-machine devbox --box hand-made > /dev/null 2>&1 || fail "control suite-machine devbox --box hand-made did not set the rule"
  out=$(loop suite-machine check --json 2>&1) && jq -e '.ok and .cpus == 3 and .slots == 2 and (.needs | map(select(.need == "test slots" and .ok)) | length == 1)' <<<"$out" > /dev/null \
    || fail "check of a named box whose devbox exec passes no input did not report 3 CPUs and 2 test slots: $out"
  # A member's check on the Board (--no-create) reads the named box too: it creates nothing.
  out=$(loop suite-machine check --json --no-create 2>&1) && jq -e '.ok and .cpus == 3 and .slots == 2' <<<"$out" > /dev/null \
    || fail "check --no-create of a named box did not report 3 CPUs and 2 test slots: $out"
  mkdir -p "$STUB/box/nomkdir" || fail "the fixture could not be made"
  for t in bash git jq grep sed cat tr sort tail head wc dirname uname flock getconf readlink env; do
    ln -sf "$(command -v "$t")" "$STUB/box/nomkdir/$t" || fail "the fixture could not be made: $t"
  done
  printf %s "$STUB/box/nomkdir" > "$STUB/box/path"
  out=$(loop suite-machine check --json 2>&1); [ $? = 1 ] && jq -e '.ok == false and .cpus == 3 and .slots == null and (.needs | map(select(.need == "test slots" and (.ok | not))) | length == 1)' <<<"$out" > /dev/null \
    || fail "check of a named box that cannot read its test slots did not say not fit: $out"
}
# Bug: the release's setup script, the commit's bundle and the run's files went to a named box on `devbox exec`'s input,
# which the real one does not pass: the script ran empty, `git fetch` read an empty bundle and the checkout failed, so the
# suite never started. Here exec gives the box no input; the run on hand-made passes, the commit's script ran there, and
# each input went by `devbox upload` and was removed once read. A whole release run: only it sends the three inputs in turn.
t_devboxnamedinput() {
  local O RUN out
  runsetup "$BOXSUITE"; devboxsetup 3
  echo '[{"name":"hand-made"}]' > "$STUB/devbox-list"
  mkdir -p "$R/.conveyor" && printf 'pwd >> "$STUB/setups"\n' > "$R/.conveyor/test-machine.sh" && git -C "$R" add -f .conveyor/test-machine.sh && git -C "$R" commit -qm 'machine setup' \
    && git -C "$R" push -q origin main && O=$(git -C "$R" rev-parse HEAD) || fail "the fixture could not be made"
  out=$(loop control suite-machine devbox --box hand-made 2>&1) || fail "control suite-machine devbox --box hand-made did not set the rule: $out"
  out=$(loop release-run prep 1.1.0 2>&1) || fail "release-run prep did not start the run: $out"
  # relwait: release-run starts the run in the background and returns; only its record shows when the run has ended. The
  # record has its end (relend) before the box's last step is done (hostfinish()), so the wait is for both.
  relwait "the run on the named devbox did not end" '.ended != null and (.machine.step == "done" or .machine.reason != null)'
  jq -e '.state == "passed" and .machine.box == "hand-made" and .machine.step == "done"' "$RUN" > /dev/null \
    || fail "the run on a named box whose devbox exec passes no input did not pass: $(cat "$RUN") $(cat "$T/$CASE/cards/release/run.log")"
  [ "$(cat "$STUB/setups" 2>&1)" = "$BOX" ] || fail "the commit's .conveyor/test-machine.sh did not run once in $BOX on the named box: $(cat "$STUB/setups" 2>&1)"
  [ "$(git -C "$BOX/wt" rev-parse HEAD 2>&1)" = "$O" ] && [ "$(cat "$STUB/full-pwd" 2>&1)" = "$BOX/wt" ] || fail "the suite did not run on the named box's checkout of $O: $(cat "$STUB/full-pwd" 2>&1)"
  [ "$(devboxcalls)" = 'auth check-login;exec start;exec facts;exec dir;upload hand-made wt.in;exec setup;exec dir;upload hand-made wt.in;exec checkout;exec dir;upload hand-made wt.in;exec upload;exec -d run;exec poll' ] \
    || fail "the setup script, the bundle and the run's files did not each go by devbox upload before their exec: $(devboxcalls)"
  [ ! -e "$BOX/wt.in" ] || fail "the uploaded input $BOX/wt.in was left on the box after the run"
}
