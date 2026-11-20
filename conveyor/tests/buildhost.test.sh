#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 300
# Engine cases: doctor in a checkout whose Conveyor runs on a build machine the host file names (issue 167). Uses
# setup.test.sh's sample and doctor.test.sh's doctordone.
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"
# The engine folder, as lib.sh sets it: named here too, so the release closure (tools/closure.sh) follows this file's paths.
SRC=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)

# Bug caught (#167): the host file named a build machine (its ssh) and its record of this project (by the name setup
# gives it, the checkout's folder) named the checkout there, a path not on this machine. Doctor compared only each
# record's main with this checkout, printed `missing:` with a fix that adds a record of this checkout (a second engine
# on the same repository), and so setup offered to start Conveyor as this machine's service. Doctor names the project
# as served on the build machine, with no `missing:` line for its record, and that line is the one setup's step 5
# names to not offer the service.
t_doctorbuildhost() {
  local X out l p; doctordone
  jq --arg m "$T/$CASE/build/sample" '. + {host: "buildbox", ssh: "buildbox", main: $m, records: [{repo: "sample", main: $m}]}' \
    "$XDG_CONFIG_HOME/conveyor/host.json" > "$T/$CASE/h" && mv "$T/$CASE/h" "$XDG_CONFIG_HOME/conveyor/host.json" || fail "the host file was not rewritten"
  # The Board's check asks over ssh: it gets no answer, and nothing is asked of a real host.
  mkdir -p "$T/$CASE/bin" && printf '#!/bin/sh\nexit 255\n' > "$T/$CASE/bin/ssh" && chmod +x "$T/$CASE/bin/ssh" || fail "the ssh stub was not made"
  out=$(cd "$S" && PATH=$T/$CASE/bin:$PATH bash "$X" doctor 2>&1)
  l="ok: the project sample is served on the build machine buildbox (its record of the host file $XDG_CONFIG_HOME/conveyor/host.json): Conveyor for it runs there, not on this machine"
  grep -qxF "$l" <<<"$out" || fail "doctor did not name the project as served on the build machine: $out"
  ! grep -q '^missing: a record of the host file' <<<"$out" || fail "doctor asked for a record of this checkout beside the build machine's: $out"
  # commands/setup.md is instructions to a Claude session, so no behaviour of it can run here: its step 5 names the
  # line on which it offers no service on this machine, and that line must be the one doctor prints.
  p=$(grep -o '`ok: the project <name> is served on the build machine <host>` line, do not ask the' "$SRC/../commands/setup.md") \
    || fail "setup's step 5 does not hold back the service question on the build machine's line"
  p=${p#\`}; p=${p%%\`*}; p=${p//<name>/sample}; p=${p//<host>/buildbox}
  [[ $l == "$p"* ]] || fail "setup's step 5 names a line doctor does not print: $p"
}
