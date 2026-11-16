#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 300
# Engine cases: install-service, the machine's service on Linux and macOS (its fixture, service_start: install.test.sh;
# beside the plugin's own checkout and after a reboot: serviceown.test.sh).
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"
# The engine folder, as lib.sh sets it: named here too, so the release closure (tools/closure.sh) follows this file's paths.
SRC=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)

# Bugs: the service runs Conveyor from a checkout, or a commit other than the pin, or for another project; it starts
# with a bare PATH, so gh, jq, claude, codex (and on macOS the GNU tools) are not found, or a PATH systemd reads
# otherwise (a quote or backslash in it); it starts without the data folder the installs are in, so the loop does not
# know its own commit and never restarts on a new pin, or without the config folder the host file is in; a pin that
# is not installed gets a service that cannot start. One Conveyor per machine: install-service in a second project
# installs a second loop, or leaves a per-project unit of before running beside the machine's (their caps add up), or
# stops a unit that is not Conveyor's loop; the project is not made a record of the host file, so the machine's loop
# never serves it; a per-project unit or agent of before is removed without its project made a record, so that
# project's loop stops for good; a per-project unit or agent that could not be stopped is removed anyway, so its loop
# runs on beside the machine's unseen; a pin with no machine's Conveyor gets a service that cannot start, and the
# per-project services it replaces are removed.
# Each part (t_service, t_serviceunits, t_servicesecond, t_servicemac here; t_servicecheckout, t_serviceown,
# t_servicereboot in serviceown.test.sh) is a case of its own from service_start, side by side.
t_service() {
  service_start
  tune --arg c "$B" '.plugin.commit = $c'
  (cd "$R" && bash "$SRC/conveyor.sh" install-service >/dev/null 2>&1) && fail "a service was installed for a pin that is not installed"
  [ ! -e "$STUB/svc" ] && [ ! -d "$XDG_CONFIG_HOME/systemd" ] || fail "a pin that is not installed got a unit"
  # A version folder holding a script and no verified clone, and a clone of the commit that can still be written.
  mkdir -p "$V/$B/conveyor"; echo 'exit 0' > "$V/$B/conveyor/conveyor.sh"
  (cd "$R" && bash "$SRC/conveyor.sh" install-service >/dev/null 2>&1) && fail "a service was installed for a pin whose folder is no verified clone"
  rm -rf "${V:?}/$B"; git clone -q "$D.git" "$V/$B" 2>/dev/null && git -C "$V/$B" -c advice.detachedHead=false checkout -q --detach "$B" || fail "the writable checkout was not made"
  (cd "$R" && bash "$SRC/conveyor.sh" install-service >/dev/null 2>&1) && fail "a service was installed for a pin whose clone can be written"
  [ ! -e "$STUB/svc" ] && [ ! -d "$XDG_CONFIG_HOME/systemd" ] || fail "a pin that is not a read-only verified install got a unit"
  # A pin with no machine's Conveyor: the unit's `machine` would not run, so no service is made, stopped or removed.
  machineless; tune --arg c "$C" '.plugin.commit = $c'
  out=$(cd "$R" && bash "$SRC/conveyor.sh" install-service 2>&1) && fail "a service was installed for a pin with no machine's Conveyor: $out"
  grep -q "pins Conveyor commit $C, which has no machine's Conveyor" <<<"$out" && [ ! -e "$STUB/svc" ] && [ ! -d "$XDG_CONFIG_HOME/systemd" ] \
    || fail "a pin with no machine's Conveyor got a unit, or was not said: $out"
}
t_serviceunits() {
  service_start
  tune --arg c "$A" '.plugin.commit = $c'; mkdir -p "$R/sub"
  # A per-project unit of before (its project, west, not yet a record; a % in its path, doubled in the unit), one whose
  # project's checkout is gone, and a unit of the same prefix that is not Conveyor's loop.
  mkdir -p "$XDG_CONFIG_HOME/systemd/user"; W=$T/$CASE/w%1/west; mkdir -p "$W"
  printf '[Service]\nEnvironment="CONVEYOR_MAIN=%s"\nExecStart="/bin/bash" "%s" serve\n' "${W//%/%%}" "$V/$A/conveyor/conveyor.sh" > "$XDG_CONFIG_HOME/systemd/user/conveyor-main-1.service"
  printf '[Service]\nEnvironment="CONVEYOR_MAIN=%s"\nExecStart="/bin/bash" "%s" serve\n' "$T/$CASE/gone" "$V/$A/conveyor/conveyor.sh" > "$XDG_CONFIG_HOME/systemd/user/conveyor-gone-2.service"
  printf '[Service]\nExecStart=/usr/bin/python3 board.py\n' > "$XDG_CONFIG_HOME/systemd/user/conveyor-board.service"
  # And one that cannot be stopped: it stays, as removing its file under a running loop leaves a second loop.
  K=$T/$CASE/stuck; mkdir -p "$K"
  printf '[Service]\nEnvironment="CONVEYOR_MAIN=%s"\nExecStart="/bin/bash" "%s" serve\n' "$K" "$V/$A/conveyor/conveyor.sh" > "$XDG_CONFIG_HOME/systemd/user/conveyor-stuck-4.service"
  P='/tmp/a"b\c/bin'
  u=$XDG_CONFIG_HOME/systemd/user/conveyor-machine.service
  out=$(cd "$R/sub" && PATH=$PATH:$P bash "$SRC/conveyor.sh" install-service 2>&1) && fail "the machine's service was installed beside a per-project loop whose project is no record: $out"
  [ ! -e "$u" ] && ! grep -qs conveyor-machine "$STUB/svc" && grep -q "the machine's Conveyor is not started while a per-project loop is left running beside it (conveyor-gone-2.service)" <<<"$out" \
    || fail "the machine's service was written or started beside a per-project loop left running (their cards and its pass the machine cap), or it was not said: $out $(cat "$STUB/svc")"
  # Bug: install-service stopped and removed the units it could make records of before it found one it could not,
  # then refused to start the machine's service: those projects had no loop at all. While one is left, none is stopped.
  ! grep -qs disable "$STUB/svc" && [ -e "$XDG_CONFIG_HOME/systemd/user/conveyor-main-1.service" ] && [ -e "$XDG_CONFIG_HOME/systemd/user/conveyor-stuck-4.service" ] \
    || fail "a per-project unit was stopped or removed though the machine's service was refused: $(cat "$STUB/svc" 2>/dev/null)"
  # The owner sees to the one whose project is no record; the stuck one cannot be stopped: the machine's service is not
  # started beside it, and the unit stopped before it (main-1) is started again, so its project is not left without a loop.
  mv "$XDG_CONFIG_HOME/systemd/user/conveyor-gone-2.service" "$STUB/gone.was"
  o2=$(cd "$R/sub" && PATH=$PATH:$P bash "$SRC/conveyor.sh" install-service 2>&1) && fail "the machine's service was installed beside a per-project unit that could not be stopped: $o2"
  [ ! -e "$u" ] && ! grep -q conveyor-machine "$STUB/svc" && grep -q "left running beside it (conveyor-stuck-4.service)" <<<"$o2" \
    || fail "the machine's service was written or started beside a per-project unit that could not be stopped: $o2"
  grep -qx "systemctl --user enable --now conveyor-main-1.service" "$STUB/svc" && [ -e "$XDG_CONFIG_HOME/systemd/user/conveyor-main-1.service" ] \
    || fail "the unit stopped before the one that could not be was not started again, or was removed: $(cat "$STUB/svc")"
  out+=$'\n'$o2
  # The owner stops the stuck one by hand.
  rm "$XDG_CONFIG_HOME/systemd/user/conveyor-stuck-4.service" || fail "a per-project unit that could not be stopped was removed"
  # The machine's service does not start: the units stopped for it are started again, and kept.
  : > "$STUB/nomachine"; : > "$STUB/svc"
  o2=$(cd "$R/sub" && PATH=$PATH:$P bash "$SRC/conveyor.sh" install-service 2>&1) && fail "install-service exited zero though the machine's service did not start: $o2"
  [ "$(grep -c conveyor-main-1 "$STUB/svc")" = 2 ] && tail -1 "$STUB/svc" | grep -qx "systemctl --user enable --now conveyor-main-1.service" \
    && [ -e "$XDG_CONFIG_HOME/systemd/user/conveyor-main-1.service" ] && grep -q "could not be started" <<<"$o2" \
    || fail "a per-project unit stopped for a machine's service that did not start was not started again, or was removed: $o2 $(cat "$STUB/svc")"
  rm "$STUB/nomachine"
  (cd "$R/sub" && PATH=$PATH:$P bash "$SRC/conveyor.sh" install-service >/dev/null 2>&1) || fail "install-service exited non-zero with no per-project loop left"
  grep -qE "^ExecStart=\"[^\"]*bash\" \"$V/$A/conveyor/conveyor.sh\" machine$" "$u" && grep -qxF "Environment=\"PATH=$PATH:/tmp/a\\\"b\\\\c/bin\"" "$u" \
    && ! grep -q CONVEYOR_MAIN "$u" && grep -qxF "WorkingDirectory=$R" "$u" \
    && grep -qxF "Environment=\"XDG_DATA_HOME=$XDG_DATA_HOME\"" "$u" && grep -qxF "Environment=\"XDG_CONFIG_HOME=$XDG_CONFIG_HOME\"" "$u" || fail "the unit: $(cat "$u")"
  grep -qx "systemctl --user enable --now conveyor-machine.service" "$STUB/svc" || fail "the unit was not enabled and started: $(cat "$STUB/svc")"
  # Bug: the unit names the install by its path, and pruning old installs (prune()) removes it under the service.
  grep -qxF "$u" "$XDG_DATA_HOME/conveyor/uses" || fail "the unit was not listed in the uses file, which prune() reads"
  grep -qx "systemctl --user disable --now conveyor-main-1.service" "$STUB/svc" && [ ! -e "$XDG_CONFIG_HOME/systemd/user/conveyor-main-1.service" ] \
    || fail "the per-project unit of before was left beside the machine's: $(cat "$STUB/svc")"
  [ -e "$STUB/gone.was" ] && ! grep -q conveyor-gone-2 "$STUB/svc" && grep -q "left conveyor-gone-2.service running: its project ($T/$CASE/gone)" <<<"$out" \
    || fail "a per-project unit whose project could not be made a record was stopped, or not said: $out"
  [ -e "$XDG_CONFIG_HOME/systemd/user/conveyor-board.service" ] && ! grep -q conveyor-board "$STUB/svc" || fail "a unit that is not Conveyor's loop was stopped"
  grep -q "left the per-project unit conveyor-stuck-4.service: it could not be stopped" <<<"$out" \
    || fail "a per-project unit that could not be stopped was removed, or not said: $out"
  jq -e --arg r "$R" --arg w "$W" --arg k "$K" '.records == [{repo: "main", main: $r}, {repo: "west", main: $w}, {repo: "stuck", main: $k}]' "$XDG_CONFIG_HOME/conveyor/host.json" >/dev/null \
    || fail "the project, or the project of the unit removed, is not a record: $(cat "$XDG_CONFIG_HOME/conveyor/host.json")"
}
# A second project, its folder named like the first: no second unit, and a name of its own is asked for.
t_servicesecond() {
  service_start
  tune --arg c "$A" '.plugin.commit = $c'
  (cd "$R" && bash "$SRC/conveyor.sh" install-service >/dev/null 2>&1) || fail "install-service exited non-zero"
  O=$T/$CASE/other/main; mkdir -p "$O"; git -C "$O" init -q -b main && cp -r "$R/.conveyor" "$O/" || fail "the other repo was not made"
  out=$(cd "$O" && bash "$SRC/conveyor.sh" install-service 2>&1) && fail "a second project of the same name was taken: $out"
  grep -q 'another record .* is named main' <<<"$out" || fail "the clash of names was not said: $out"
  jq --arg o "$O" '.records += [{repo: "other", main: $o}]' "$XDG_CONFIG_HOME/conveyor/host.json" > "$STUB/h" && mv "$STUB/h" "$XDG_CONFIG_HOME/conveyor/host.json"
  (cd "$O" && bash "$SRC/conveyor.sh" install-service >/dev/null) || fail "install-service for the other repo exited non-zero"
  # shellcheck disable=SC2010 # the unit files are the engine's own, named conveyor-<name>.service
  [ "$(ls "$XDG_CONFIG_HOME/systemd/user" | grep -c '^conveyor-[^bgs]')" = 1 ] && [ "$(jq '.records | length' "$XDG_CONFIG_HOME/conveyor/host.json")" = 2 ] \
    || fail "two projects got two loops, or a record twice: $(ls "$XDG_CONFIG_HOME/systemd/user") $(cat "$XDG_CONFIG_HOME/conveyor/host.json")"
}
t_servicemac() {
  service_start
  tune --arg c "$A" '.plugin.commit = $c'; K=$T/$CASE/stuck; mkdir -p "$K"
  # macOS, with Homebrew's GNU tools as p_tools finds them: the agent's PATH puts them first, then Homebrew's bin
  # folder, so the agent runs Homebrew's jq 1.8 ahead of Apple's /usr/bin/jq (#110).
  H=$T/$CASE/home; b=$STUB/brew; mkdir -p "$STUB/mac" "$b/bin" "$H"; printf '#!/bin/sh\necho Darwin\n' > "$STUB/mac/uname"; chmod +x "$STUB/mac/uname"
  ln -s "$(command -v timeout)" "$b/bin/gtimeout"
  for k in coreutils:timeout coreutils:date coreutils:stat findutils:find gnu-sed:sed grep:grep; do
    mkdir -p "$b/opt/${k%%:*}/libexec/gnubin"; ln -s "$(command -v "${k#*:}")" "$b/opt/${k%%:*}/libexec/gnubin/${k#*:}"
  done
  # A per-project agent of before, its project (an & in its path) not yet a record.
  E=$T/$CASE/e\&1/east; mkdir -p "$E" "$H/Library/LaunchAgents"
  printf '<dict>\n  <array><string>/bin/bash</string><string>%s</string><string>serve</string></array>\n  <dict>\n    <key>CONVEYOR_MAIN</key><string>%s</string>\n  </dict>\n</dict>\n' \
    "$V/$A/conveyor/conveyor.sh" "$(sed 's/&/\&amp;/g' <<<"$E")" > "$H/Library/LaunchAgents/conveyor.east-3.plist"
  # And one, loaded, that cannot be stopped: it stays.
  printf '<dict>\n  <array><string>/bin/bash</string><string>%s</string><string>serve</string></array>\n  <dict>\n    <key>CONVEYOR_MAIN</key><string>%s</string>\n  </dict>\n</dict>\n' \
    "$V/$A/conveyor/conveyor.sh" "$K" > "$H/Library/LaunchAgents/conveyor.stuck-5.plist"
  a=$H/Library/LaunchAgents/conveyor-machine.plist
  out=$(cd "$R" && HOME=$H PATH=$STUB/mac:$b/bin:$PATH bash "$SRC/conveyor.sh" install-service 2>&1) && fail "the machine's agent was installed beside a per-project agent left running: $out"
  [ -e "$H/Library/LaunchAgents/conveyor.stuck-5.plist" ] && grep -q "left the per-project agent conveyor.stuck-5: it could not be stopped" <<<"$out" \
    || fail "a per-project agent that could not be stopped was removed, or not said: $out"
  [ ! -e "$a" ] && ! grep -q "launchctl bootstrap.*conveyor-machine" "$STUB/svc" && grep -q "the machine's Conveyor is not started while a per-project loop is left running beside it (conveyor.stuck-5.plist)" <<<"$out" \
    || fail "the machine's agent was written or loaded beside a per-project agent left running (their cards and its pass the machine cap), or it was not said: $out $(cat "$STUB/svc")"
  # The loaded agent stopped before the stuck one is loaded again and kept, so its project is not left without a loop.
  grep -qx "launchctl bootstrap gui/$(id -u) $H/Library/LaunchAgents/conveyor.east-3.plist" "$STUB/svc" && [ -e "$H/Library/LaunchAgents/conveyor.east-3.plist" ] \
    || fail "the agent stopped before the one that could not be was not loaded again, or was removed: $(cat "$STUB/svc")"
  # The owner stops it by hand: the machine's agent is installed.
  rm "$H/Library/LaunchAgents/conveyor.stuck-5.plist"
  (cd "$R" && HOME=$H PATH=$STUB/mac:$b/bin:$PATH bash "$SRC/conveyor.sh" install-service >/dev/null 2>&1) || fail "install-service on macOS exited non-zero with no per-project agent left"
  grep -qx "launchctl bootout gui/$(id -u)/conveyor.east-3" "$STUB/svc" && [ ! -e "$H/Library/LaunchAgents/conveyor.east-3.plist" ] \
    && jq -e --arg e "$E" 'any(.records[]; . == {repo: "east", main: $e})' "$XDG_CONFIG_HOME/conveyor/host.json" >/dev/null \
    || fail "the per-project agent of before was left, or its project not made a record: $(cat "$STUB/svc") $(cat "$XDG_CONFIG_HOME/conveyor/host.json")"
  a=$H/Library/LaunchAgents/conveyor-machine.plist
  grep -qF "<string>$V/$A/conveyor/conveyor.sh</string><string>machine</string>" "$a" \
    && grep -qF "<key>PATH</key><string>$b/opt/coreutils/libexec/gnubin:$b/opt/findutils/libexec/gnubin:$b/opt/gnu-sed/libexec/gnubin:$b/opt/grep/libexec/gnubin:$b/bin:$STUB/mac:$b/bin:$PATH</string>" "$a" \
    && ! grep -q CONVEYOR_MAIN "$a" && grep -qF "<key>XDG_DATA_HOME</key><string>$XDG_DATA_HOME</string>" "$a" \
    && grep -qF "<key>XDG_CONFIG_HOME</key><string>$XDG_CONFIG_HOME</string>" "$a" || fail "the agent: $(cat "$a")"
  grep -qx "launchctl bootstrap gui/$(id -u) $a" "$STUB/svc" || fail "the agent was not loaded: $(cat "$STUB/svc")"
}
