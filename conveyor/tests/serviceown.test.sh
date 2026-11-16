#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 300
# Engine cases: the service beside the plugin's own checkout, and after a reboot (its fixture, service_start:
# install.test.sh; the other service cases: service.test.sh).
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"
# The engine folder, as lib.sh sets it: named here too, so the release closure (tools/closure.sh) follows this file's paths.
SRC=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)

# Bugs: the plugin's own belt ran as a per-project unit straight from its checkout (no CONVEYOR_MAIN, its pack naming
# no plugin), which install-service could not make a record of; and it refused only after it had stopped and removed
# the other projects' units, so their belts were down until a unit was written back by hand. Such a unit's project is
# the checkout its conveyor.sh is in, recorded as run from that checkout; one run from an install with no
# CONVEYOR_MAIN names no project, and while it is left no unit is stopped or removed.
t_servicecheckout() {
  service_start
  tune --arg c "$A" '.plugin.commit = $c'
  local P=$T/$CASE/plugin W=$T/$CASE/west d=$XDG_CONFIG_HOME/systemd/user u
  git clone -q "$D.git" "$P" 2>/dev/null && mkdir -p "$W" "$d" || fail "the plugin's checkout was not made"
  printf '[Service]\nWorkingDirectory=%s\nExecStart=%s/conveyor/conveyor.sh serve\n' "$P" "$P" > "$d/conveyor-belt.service"
  printf '[Service]\nEnvironment="CONVEYOR_MAIN=%s"\nExecStart="/bin/bash" "%s" serve\n' "$W" "$V/$A/conveyor/conveyor.sh" > "$d/conveyor-west.service"
  printf '[Service]\nExecStart="/bin/bash" "%s" serve\n' "$V/$A/conveyor/conveyor.sh" > "$d/conveyor-inst.service"
  out=$(cd "$R" && bash "$SRC/conveyor.sh" install-service 2>&1) && fail "the machine's service was installed beside a unit whose project is no record: $out"
  grep -q "left conveyor-inst.service running: its project (not named in it)" <<<"$out" && [ ! -e "$d/conveyor-machine.service" ] \
    || fail "a unit run from an install with no CONVEYOR_MAIN was taken for a project, or not said: $out"
  ! grep -q disable "$STUB/svc" 2>/dev/null && [ -e "$d/conveyor-belt.service" ] && [ -e "$d/conveyor-west.service" ] \
    || fail "a per-project unit was stopped or removed though the machine's service was refused: $(cat "$STUB/svc" 2>/dev/null)"
  rm "$d/conveyor-inst.service"
  (cd "$R" && bash "$SRC/conveyor.sh" install-service >/dev/null 2>&1) || fail "install-service exited non-zero beside the plugin's own unit"
  jq -e --arg r "$R" --arg p "$(cd "$P" && pwd -P)" --arg w "$W" '.records == [{repo: "main", main: $r}, {repo: "plugin", main: $p, engine: "checkout"}, {repo: "west", main: $w}]' \
    "$XDG_CONFIG_HOME/conveyor/host.json" >/dev/null || fail "the plugin's belt is not a record run from its checkout: $(cat "$XDG_CONFIG_HOME/conveyor/host.json")"
  for u in conveyor-belt conveyor-west; do
    grep -qx "systemctl --user disable --now $u.service" "$STUB/svc" && [ ! -e "$d/$u.service" ] || fail "the unit $u was left beside the machine's: $(cat "$STUB/svc")"
  done
  grep -qx "systemctl --user enable --now conveyor-machine.service" "$STUB/svc" || fail "the machine's service was not started: $(cat "$STUB/svc")"
  # A record already there, of the checkout, is marked as run from it, and kept where it is.
  jq '.records[1] |= del(.engine)' "$XDG_CONFIG_HOME/conveyor/host.json" > "$STUB/h" && mv "$STUB/h" "$XDG_CONFIG_HOME/conveyor/host.json"
  printf '[Service]\nExecStart="/bin/bash" "%s/conveyor/conveyor.sh" serve\n' "$P" > "$d/conveyor-belt.service"
  (cd "$R" && bash "$SRC/conveyor.sh" install-service >/dev/null 2>&1) || fail "install-service exited non-zero again"
  jq -e '.records[1].engine == "checkout" and (.records | length) == 3' "$XDG_CONFIG_HOME/conveyor/host.json" >/dev/null \
    || fail "the plugin's record already there was not marked as run from its checkout: $(cat "$XDG_CONFIG_HOME/conveyor/host.json")"
}
# install-service run in the plugin's own checkout, its pack pinning and following nothing, its unit of before running
# that checkout's conveyor.sh; beside it a unit of a project that follows the plugin's main, on an install.
ownunits() {
  service_start
  tune '.plugin = {follow: "main"}'; jq -n --arg a "$A" '{commit: $a, taken: [$a]}' > "$R/.git/conveyor-engine.json"
  P=$T/$CASE/plugin; d=$XDG_CONFIG_HOME/systemd/user
  git clone -q "$D.git" "$P" 2>/dev/null && mkdir -p "$P/.conveyor" "$d" && jq 'del(.plugin)' "$R/.conveyor/project.json" > "$P/.conveyor/project.json" \
    || fail "the plugin's checkout was not made"
  P=$(cd "$P" && pwd -P)
  printf '[Service]\nWorkingDirectory=%s\nExecStart=%s/conveyor/conveyor.sh serve\n' "$P" "$P" > "$d/conveyor-belt.service"
  printf '[Service]\nEnvironment="CONVEYOR_MAIN=%s"\nExecStart="/bin/bash" "%s" serve\n' "$R" "$V/$A/conveyor/conveyor.sh" > "$d/conveyor-push.service"
}
# Bug this guards: a checkout whose code has no machine's Conveyor gets a machine's service that cannot start, after
# its unit and the other project's were stopped.
# Bug: install-service read the pack's pin first and refused one with none ("pins Conveyor commit (none)"), so the
# plugin's own belt could never be switched to the machine's service and each belt kept a unit that names a version
# folder pruning removes. Its checkout's code now runs the machine's Conveyor, the belt recorded as run from it.
# Both on one fixture (each case pays about 0.5 CPU s for its keeper and ownunits): the refusal changes nothing, so the
# checkout's code given back its machine's Conveyor is then installed from the units as they were.
t_serviceown() {
  ownunits
  sed -i '/^cmd machine /d' "$P/conveyor/conveyor.sh"
  out=$(cd "$P" && bash "$SRC/conveyor.sh" install-service 2>&1) && fail "a service was installed from a checkout with no machine's Conveyor: $out"
  grep -qF "$P runs Conveyor from its own checkout's $P/conveyor/conveyor.sh, which has no machine's Conveyor to run" <<<"$out" || fail "the refusal does not name the checkout's code: $out"
  [ ! -e "$STUB/svc" ] && [ ! -e "$d/conveyor-machine.service" ] && [ -e "$d/conveyor-belt.service" ] && [ -e "$d/conveyor-push.service" ] \
    && [ ! -e "$XDG_CONFIG_HOME/conveyor/host.json" ] || fail "a refusal changed a service or the host file: $(cat "$STUB/svc" "$XDG_CONFIG_HOME/conveyor/host.json" 2>&1)"
  git -C "$P" checkout -q -- conveyor/conveyor.sh || fail "the checkout's code was not given back its machine's Conveyor"
  out=$(cd "$P" && bash "$SRC/conveyor.sh" install-service 2>&1) || fail "install-service refused in the plugin's own checkout: $out"
  jq -e --arg p "$P" --arg r "$R" '.records == [{repo: "plugin", main: $p, engine: "checkout"}, {repo: "main", main: $r}]' "$XDG_CONFIG_HOME/conveyor/host.json" >/dev/null \
    || fail "both projects are not records, the plugin's as run from its checkout: $(cat "$XDG_CONFIG_HOME/conveyor/host.json")"
  for u in conveyor-belt conveyor-push; do
    grep -qx "systemctl --user disable --now $u.service" "$STUB/svc" && [ ! -e "$d/$u.service" ] || fail "the unit $u was left beside the machine's: $(cat "$STUB/svc")"
  done
  grep -qE "^ExecStart=\"[^\"]*bash\" \"$P/conveyor/conveyor.sh\" machine$" "$d/conveyor-machine.service" \
    && grep -qx "systemctl --user enable --now conveyor-machine.service" "$STUB/svc" || fail "the machine's service does not run the checkout's code, or was not started: $(cat "$d/conveyor-machine.service" "$STUB/svc")"
}
# Bug: after a reboot, a project's service started the engine install it was written with, which refused the pack
# that had moved on since. The machine's service written for a project that follows the plugin's main, started as a
# reboot starts it, runs that project on the commit it has taken since, not the install the unit names.
t_servicereboot() {
  service_start
  tune '.plugin = {follow: "main"}'
  jq -n --arg a "$A" '{commit: $a, taken: [$a]}' > "$R/.git/conveyor-engine.json"
  (cd "$R" && bash "$SRC/conveyor.sh" install-service >/dev/null 2>&1) || fail "install-service exited non-zero"
  local u=$XDG_CONFIG_HOME/systemd/user/conveyor-machine.service c
  c=$(sed -nE 's/^ExecStart="[^"]*" "([^"]*)" machine$/\1/p' "$u")
  [ "$c" = "$V/$A/conveyor/conveyor.sh" ] || fail "the unit does not run the install of the project's engine: $(cat "$u")"
  # Later the project takes the plugin's main as pushed, B.
  (cd "$R" && CONVEYOR_MAIN=$R bash "$c" take >/dev/null 2>&1); [ "$(jq -r .commit "$R/.git/conveyor-engine.json")" = "$B" ] \
    || fail "the project did not take $B: $(cat "$R/.git/conveyor-engine.json")"
  # The reboot: the unit's command, in its folder, with its data and config folders and no project named.
  ( cd "$R" && exec env -u CONVEYOR_MAIN -u CONVEYOR_CARDS XDG_DATA_HOME="$XDG_DATA_HOME" XDG_CONFIG_HOME="$XDG_CONFIG_HOME" bash "$c" machine > "$STUB/machine.out" 2>&1 ) & mp=$!
  trap 'kill -TERM $mp 2>/dev/null; wait $mp 2>/dev/null; chmod -R u+w "$T/$CASE"' EXIT
  wait_until '[ "$(jq -r ".commit // empty" "$ST/loop.json" 2>/dev/null)" = "$B" ]' \
    || fail "after the reboot the project's loop does not run its engine $B: $(cat "$ST/loop.json" 2>/dev/null) $(cat "$STUB/machine.out")"
}
