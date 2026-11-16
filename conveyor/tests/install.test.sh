#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 300
# Engine cases: install and the service.
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"
# The engine folder, as lib.sh sets it: named here too, so the release closure (tools/closure.sh) follows this file's paths.
SRC=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)

# Two commits of Conveyor in a code repo whose origin is a bare repo beside it, as `install` clones from: $A takes a
# cap of 1 to 8 only, $B is this code. The installs go under $XDG_DATA_HOME, in $V. Made once per run (codemake,
# lib.sh template) and copied: made afresh, with its copy of the engine, it cost each case about 0.35 s; copied, 0.03 s.
coderepo() {
  export XDG_DATA_HOME=$T/$CASE/data; V=$T/$CASE/data/conveyor/versions; D=$T/$CASE/code
  template code codemake && mkdir -p "$T/$CASE" && cp -a "$FIXTURE.code/code" "$D" && cp -a "$FIXTURE.code/code.git" "$D.git" \
    && git -C "$D" remote set-url origin "$D.git" && A=$(git -C "$D" rev-parse HEAD~1) && B=$(git -C "$D" rev-parse HEAD) \
    || fail "the code repo was not made"
}
codemake() { # <folder>: the code repo coderepo copies, in <folder>/code, its origin in <folder>/code.git
  local D=$1/code
  mkdir -p "$1" && git init -q --bare -b main "$D.git" && git clone -q "$D.git" "$D" 2>/dev/null || return 1
  mkdir -p "$D/conveyor"; ln -s "$SRC/../.claude" "$D/.claude"; cp -r "$SRC"/* "$D/conveyor/"; rm -rf "$D/conveyor/state"
  sed -i 's/\. >= 1 and \. <= 100 and \. == floor/. >= 1 and . <= 8 and . == floor/' "$D/conveyor/lib/control.sh"
  grep -q '<= 8 and . == floor' "$D/conveyor/lib/control.sh" || { echo "the old code's cap bound was not set" >&2; return 1; }
  git -C "$D" add -A && git -C "$D" commit -qm A && cp "$SRC/lib/control.sh" "$D/conveyor/lib/" && git -C "$D" commit -qam B \
    && git -C "$D" push -q origin main || { echo "the code repo's commits were not made" >&2; return 1; }
}
# After coderepo: C, a commit of it with no machine's Conveyor (as every commit before it), installed.
machineless() {
  sed -i '/^cmd machine /d' "$D/conveyor/conveyor.sh" && git -C "$D" commit -qam C && C=$(git -C "$D" rev-parse HEAD) && git -C "$D" push -q origin main \
    && bash "$D/conveyor/conveyor.sh" install "$C" >/dev/null || fail "the commit with no machine's Conveyor was not installed"
}

# Bugs: an install is kept that is not the commit asked for (an abbreviated id, a commit the repo does not have, a
# folder already there holding something else), or is left half made; an install can be written to, so the code a
# pin names can change under it; install makes a state folder in the checkout it runs from.
t_install() {
  coderepo; X=$D/conveyor/conveyor.sh; trap 'chmod -R u+w "$T/$CASE"' EXIT
  bash "$X" install "${A:0:12}" >/dev/null 2>&1 && fail "an abbreviated commit id was installed"
  [ ! -e "$V/${A:0:12}" ] || fail "an abbreviated commit id left a version folder"
  bad=$(printf '%040d' 0)
  bash "$X" install "$bad" >/dev/null 2>&1 && fail "a commit the repo does not have was installed"
  [ ! -e "$V/$bad" ] && [ ! -e "$V/$bad.part" ] || fail "a commit that could not be verified left a folder: $(ls "$V")"
  mkdir -p "$V/$B"; bash "$X" install "$B" >/dev/null 2>&1 && fail "a version folder that is not its commit was taken as installed"
  rmdir "$V/$B"
  # An empty version folder inside a checkout of that very commit: Git would find the checkout above it.
  mkdir -p "$D/data/conveyor/versions/$B"
  XDG_DATA_HOME=$D/data bash "$X" install "$B" >/dev/null 2>&1 && fail "an empty version folder was taken as installed through the checkout above it"
  rm -rf "$D/data"
  # A Git template's post-checkout hook changes the code the fresh clone's checkout wrote; HEAD is still the commit.
  mkdir -p "$T/$CASE/tpl/hooks" && printf '#!/bin/sh\nprintf "\\necho altered\\n" >> conveyor/conveyor.sh\n' > "$T/$CASE/tpl/hooks/post-checkout" \
    && chmod +x "$T/$CASE/tpl/hooks/post-checkout" || fail "the template hook was not made"
  GIT_TEMPLATE_DIR=$T/$CASE/tpl bash "$X" install "$A" >/dev/null 2>&1 && fail "a fresh clone a checkout hook changed was installed"
  [ ! -e "$V/$A" ] && [ ! -e "$V/$A.part" ] || fail "a fresh clone a checkout hook changed left a folder: $(ls "$V")"
}
# Each part below is a case of its own, on a code repo of its own, so they run side by side.
t_installok() {
  coderepo; X=$D/conveyor/conveyor.sh; trap 'chmod -R u+w "$T/$CASE"' EXIT
  bash "$X" install "$A" >/dev/null || fail "install of a commit the repo has exited non-zero"
  [ "$(git -C "$V/$A" rev-parse HEAD)" = "$A" ] && [ "$(cat "$V/$A/conveyor/conveyor.sh")" = "$(git -C "$D" show "$A:conveyor/conveyor.sh")" ] \
    || fail "the install is not commit $A"
  [ -z "$(find "$V/$A" ! -type l -perm /222)" ] || fail "the install has files or folders that can be written: $(find "$V/$A" ! -type l -perm /222 | head -3)"
  if [ "$(id -u)" != 0 ]; then
    { echo x >> "$V/$A/conveyor/conveyor.sh"; } 2>/dev/null && fail "the installed code was written to"
    { : > "$V/$A/conveyor/new.sh"; } 2>/dev/null && fail "a file was added to the install"
  fi
  bash "$X" install "$A" >/dev/null || fail "installing an installed commit again failed"
}
# A version folder already there that is the commit but can be written: changed, it is refused (here and in
# t_installhidden, where the change is hidden from status); as cloned, it is made read-only.
t_installkept() {
  coderepo; X=$D/conveyor/conveyor.sh; trap 'chmod -R u+w "$T/$CASE"' EXIT
  git clone -q "$D.git" "$V/$B" 2>/dev/null && git -C "$V/$B" -c advice.detachedHead=false checkout -q --detach "$B" || fail "the writable checkout was not made"
  echo x >> "$V/$B/conveyor/conveyor.sh"
  bash "$X" install "$B" >/dev/null 2>&1 && fail "a version folder with a changed file was taken as installed"
  git -C "$V/$B" checkout -q -- conveyor/conveyor.sh; : > "$V/$B/new.sh"
  bash "$X" install "$B" >/dev/null 2>&1 && fail "a version folder with an added file was taken as installed"
  rm "$V/$B/new.sh"
  # A changed file the index is told to take as unchanged (or to skip) does not show in status.
  for f in assume-unchanged skip-worktree; do
    git -C "$V/$B" update-index --$f conveyor/conveyor.sh && echo x >> "$V/$B/conveyor/conveyor.sh" || fail "the $f file was not made"
    bash "$X" install "$B" >/dev/null 2>&1 && fail "a version folder with a changed $f file was taken as installed"
    git -C "$V/$B" update-index --no-$f conveyor/conveyor.sh && git -C "$V/$B" checkout -q -- conveyor/conveyor.sh || fail "the $f file was not undone"
  done
}
t_installhidden() {
  coderepo; X=$D/conveyor/conveyor.sh; trap 'chmod -R u+w "$T/$CASE"' EXIT
  git clone -q "$D.git" "$V/$B" 2>/dev/null && git -C "$V/$B" -c advice.detachedHead=false checkout -q --detach "$B" || fail "the writable checkout was not made"
  # A replacement ref puts $A's code under $B's id: HEAD is $B, and status, with the replacement, shows nothing.
  git -C "$V/$B" replace "$B" "$A" && git -C "$V/$B" reset -q --hard "$B" && [ -z "$(git -C "$V/$B" status --porcelain)" ] \
    && [ "$(git -C "$V/$B" rev-parse HEAD)" = "$B" ] || fail "the replacement ref was not made"
  bash "$X" install "$B" >/dev/null 2>&1 && fail "a version folder holding another commit's code under a replacement ref was taken as installed"
  git -C "$V/$B" replace -d "$B" >/dev/null && git -C "$V/$B" reset -q --hard "$B" || fail "the replacement ref was not undone"
  # A clean filter shows Git the committed file in place of a changed one, so status (its index refreshed) shows nothing.
  git -C "$V/$B" config filter.mask.clean 'cat >/dev/null; git show HEAD:conveyor/conveyor.sh' \
    && echo 'conveyor/conveyor.sh filter=mask' > "$V/$B/.git/info/attributes" && echo 'echo altered' >> "$V/$B/conveyor/conveyor.sh" \
    && git -C "$V/$B" add conveyor/conveyor.sh && [ -z "$(git -C "$V/$B" status --porcelain)" ] || fail "the clean filter was not made"
  bash "$X" install "$B" >/dev/null 2>&1 && fail "a version folder with a changed file a clean filter hides was taken as installed"
  # The committed file is written back and added by hand: the index holds the altered file's size and time, so checkout
  # skips it as unchanged unless the change and the add fell in the same second (on a loaded machine they need not).
  rm "$V/$B/.git/info/attributes" && git -C "$V/$B" config --remove-section filter.mask \
    && git -C "$V/$B" show HEAD:conveyor/conveyor.sh > "$V/$B/conveyor/conveyor.sh" && git -C "$V/$B" add conveyor/conveyor.sh \
    || fail "the clean filter was not undone"
  # A script that lost its executable bit, with core.filemode false so that status does not show it: packget cannot run it.
  git -C "$V/$B" config core.filemode false && chmod a-x "$V/$B/conveyor/lib/pack.sh" && [ -z "$(git -C "$V/$B" status --porcelain)" ] \
    || fail "the lost executable bit was not made"
  bash "$X" install "$B" >/dev/null 2>&1 && fail "a version folder with a script that cannot run was taken as installed"
  chmod a+x "$V/$B/conveyor/lib/pack.sh" && git -C "$V/$B" config --unset core.filemode || fail "the lost executable bit was not undone"
}
t_installlink() {
  coderepo; X=$D/conveyor/conveyor.sh; trap 'chmod -R u+w "$T/$CASE"' EXIT
  git clone -q "$D.git" "$V/$B" 2>/dev/null && git -C "$V/$B" -c advice.detachedHead=false checkout -q --detach "$B" || fail "the writable checkout was not made"
  # A link at the version folder to a writable clone of the commit: the read-only check does not follow it.
  mv "$V/$B" "$T/$CASE/linked" && ln -s "$T/$CASE/linked" "$V/$B" || fail "the linked version folder was not made"
  bash "$X" install "$B" >/dev/null 2>&1 && fail "a link at the version folder was taken as installed"
  rm "$V/$B" && mv "$T/$CASE/linked" "$V/$B" || fail "the linked version folder was not undone"
  bash "$X" install "$B" >/dev/null || fail "a writable version folder as cloned was refused"
  [ -z "$(find "$V/$B" ! -type l -perm /222)" ] || fail "a writable version folder was taken as installed and left writable"
  [ ! -e "$D/conveyor/state" ] || fail "install made a state folder in the checkout it ran from"
}

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
# Each part (t_service, t_serviceunits, t_servicecheckout, t_serviceown, t_serviceownold, t_servicereboot, t_servicesecond, t_servicemac) is a case of its own from service_start, side
# by side.
service_start() { # main and a code repo whose commit A is installed; systemctl and launchctl stubs
  export XDG_CONFIG_HOME=$T/$CASE/config # the host file it makes records in is the case's own, not the other cases'
  setup '[]'; coderepo; trap 'chmod -R u+w "$T/$CASE"' EXIT
  bash "$D/conveyor/conveyor.sh" install "$A" >/dev/null || fail "install of $A failed"
  # A unit or agent named stuck cannot be stopped; agents east and stuck are loaded, every other is not. With
  # $STUB/nomachine, the machine's unit does not start.
  printf '#!/bin/sh\necho "systemctl $*" >> "$STUB/svc"\ncase "$*" in *stuck*) exit 1;; *"enable --now conveyor-machine"*) [ ! -e "$STUB/nomachine" ];; esac\n' > "$STUB/systemctl"
  printf '#!/bin/sh\necho "launchctl $*" >> "$STUB/svc"\ncase "$*" in "bootout "*stuck*) exit 1;; "print "*east*|"print "*stuck*) exit 0;; print*) exit 1;; esac\n' > "$STUB/launchctl"
  chmod +x "$STUB/systemctl" "$STUB/launchctl"
}
t_service() {
  service_start
  tune --arg c "$B" '.plugin.commit = $c'
  (cd "$R" && bash "$SRC/conveyor.sh" install-service >/dev/null 2>&1) && fail "a service was installed for a pin that is not installed"
  [ ! -e "$STUB/svc" ] && [ ! -d "$XDG_CONFIG_HOME/systemd" ] || fail "a pin that is not installed got a unit"
  # A version folder holding a script and no verified clone, and a clone of the commit that can still be written.
  mkdir -p "$V/$B/conveyor"; echo 'exit 0' > "$V/$B/conveyor/conveyor.sh"
  (cd "$R" && bash "$SRC/conveyor.sh" install-service >/dev/null 2>&1) && fail "a service was installed for a pin whose folder is no verified clone"
  rm -rf "$V/$B"; git clone -q "$D.git" "$V/$B" 2>/dev/null && git -C "$V/$B" -c advice.detachedHead=false checkout -q --detach "$B" || fail "the writable checkout was not made"
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
# Bug: install-service read the pack's pin first and refused one with none ("pins Conveyor commit (none)"), so the
# plugin's own belt could never be switched to the machine's service and each belt kept a unit that names a version
# folder pruning removes. Its checkout's code now runs the machine's Conveyor, the belt recorded as run from it.
t_serviceown() {
  ownunits
  out=$(cd "$P" && bash "$SRC/conveyor.sh" install-service 2>&1) || fail "install-service refused in the plugin's own checkout: $out"
  jq -e --arg p "$P" --arg r "$R" '.records == [{repo: "plugin", main: $p, engine: "checkout"}, {repo: "main", main: $r}]' "$XDG_CONFIG_HOME/conveyor/host.json" >/dev/null \
    || fail "both projects are not records, the plugin's as run from its checkout: $(cat "$XDG_CONFIG_HOME/conveyor/host.json")"
  for u in conveyor-belt conveyor-push; do
    grep -qx "systemctl --user disable --now $u.service" "$STUB/svc" && [ ! -e "$d/$u.service" ] || fail "the unit $u was left beside the machine's: $(cat "$STUB/svc")"
  done
  grep -qE "^ExecStart=\"[^\"]*bash\" \"$P/conveyor/conveyor.sh\" machine$" "$d/conveyor-machine.service" \
    && grep -qx "systemctl --user enable --now conveyor-machine.service" "$STUB/svc" || fail "the machine's service does not run the checkout's code, or was not started: $(cat "$d/conveyor-machine.service" "$STUB/svc")"
}
# Bug this guards: a checkout whose code has no machine's Conveyor gets a machine's service that cannot start, after
# its unit and the other project's were stopped.
t_serviceownold() {
  ownunits
  sed -i '/^cmd machine /d' "$P/conveyor/conveyor.sh"
  out=$(cd "$P" && bash "$SRC/conveyor.sh" install-service 2>&1) && fail "a service was installed from a checkout with no machine's Conveyor: $out"
  grep -qF "$P runs Conveyor from its own checkout's $P/conveyor/conveyor.sh, which has no machine's Conveyor to run" <<<"$out" || fail "the refusal does not name the checkout's code: $out"
  [ ! -e "$STUB/svc" ] && [ ! -e "$d/conveyor-machine.service" ] && [ -e "$d/conveyor-belt.service" ] && [ -e "$d/conveyor-push.service" ] \
    && [ ! -e "$XDG_CONFIG_HOME/conveyor/host.json" ] || fail "a refusal changed a service or the host file: $(cat "$STUB/svc" "$XDG_CONFIG_HOME/conveyor/host.json" 2>&1)"
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
  [ "$(ls "$XDG_CONFIG_HOME/systemd/user" | grep -c '^conveyor-[^bgs]')" = 1 ] && [ "$(jq '.records | length' "$XDG_CONFIG_HOME/conveyor/host.json")" = 2 ] \
    || fail "two projects got two loops, or a record twice: $(ls "$XDG_CONFIG_HOME/systemd/user") $(cat "$XDG_CONFIG_HOME/conveyor/host.json")"
}
t_servicemac() {
  service_start
  tune --arg c "$A" '.plugin.commit = $c'; K=$T/$CASE/stuck; mkdir -p "$K"
  # macOS, with Homebrew's GNU tools as p_tools finds them: the agent's PATH puts them first.
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
    && grep -qF "<key>PATH</key><string>$b/opt/coreutils/libexec/gnubin:$b/opt/findutils/libexec/gnubin:$b/opt/gnu-sed/libexec/gnubin:$b/opt/grep/libexec/gnubin:$STUB/mac:$b/bin:$PATH</string>" "$a" \
    && ! grep -q CONVEYOR_MAIN "$a" && grep -qF "<key>XDG_DATA_HOME</key><string>$XDG_DATA_HOME</string>" "$a" \
    && grep -qF "<key>XDG_CONFIG_HOME</key><string>$XDG_CONFIG_HOME</string>" "$a" || fail "the agent: $(cat "$a")"
  grep -qx "launchctl bootstrap gui/$(id -u) $a" "$STUB/svc" || fail "the agent was not loaded: $(cat "$STUB/svc")"
}
# Bug: the Board was installed from a clone of its own, by four commands typed in turn (find the release, clone it, add
# an admin, install). `conveyor.sh board` alone, in the project's checkout, installs it from the install of the commit
# the project pins, reading that project, and lists the service so prune() keeps the install the Board runs from.
# Bug caught (#108): with no admin yet, board first asked for a typed admin password, so setup's agent could not start
# the Board. It now asks for none (No login on this device lets this machine in), starts the service with no terminal
# and names the address to open. The install's own check (dashboard_server.py can-open) is dashboard.test.sh's.
t_board() {
  service_start
  tune --arg c "$A" '.plugin.commit = $c'
  local h=$T/$CASE/home u out py=$XDG_DATA_HOME/conveyor/board-venv/bin/python3
  mkdir -p "${py%/*}" "$h" || fail "the Board's virtualenv was not made"
  # The Board's python3: every call passes (can-open: No login on this device lets this machine in).
  printf '#!/bin/sh\necho "$CONVEYOR_MAIN $*" >> "$STUB/py"\n' > "$py" && chmod +x "$py"
  if [ "$(uname -s)" = Darwin ]; then u=$h/Library/LaunchAgents/com.conveyor.dashboard.plist; else u=$h/.config/systemd/user/dashboard.service; fi
  # Run from the read-only install, as docs/setup.md says: from there the command must act for the checkout it is
  # called in and write no state into the install (it exited before installing anything when it did).
  out=$(cd "$R" && HOME=$h CONVEYOR_DASHBOARD_PORT=8791 bash "$V/$A/conveyor/conveyor.sh" board 2>&1 </dev/null) || fail "board from the install exited non-zero: $out"
  grep -qxF "$R $V/$A/.claude/scripts/dashboard_server.py can-open" "$STUB/py" && ! grep -q ' add-user \| set-password ' "$STUB/py" \
    || fail "board did not check the project's Board from the install it pins, or asked for a password: $(cat "$STUB/py")"
  grep -qF "$V/$A/.claude/scripts/dashboard.sh" "$u" && grep -qF "CONVEYOR_MAIN" "$u" && grep -qF "$R" "$u" \
    || fail "the Board's service does not run the install's Board for the project: $(cat "$u" 2>&1)"
  grep -qx 'systemctl --user restart dashboard.service\|launchctl bootstrap .*com\.conveyor\.dashboard\.plist' "$STUB/svc" \
    || fail "board did not start the Board's service: $(cat "$STUB/svc" 2>&1)"
  grep -qxF "conveyor: the Board runs from $V/$A/.claude/scripts for $R, at https://localhost:8791/" <<<"$out" || fail "board did not name the Board's address: $out"
  grep -qxF "$u" "$XDG_DATA_HOME/conveyor/uses" || fail "the Board's service is not listed, so prune would remove its install: $(cat "$XDG_DATA_HOME/conveyor/uses" 2>&1)"
}
# Bug caught (#108): with No login on this device off and no admin with a password, the Board cannot be opened, and
# the only way on was a password typed in a terminal, which setup's agent cannot do. Given the file setup writes from
# Claude Code's prompt, board adds the admin with that password on stdin (never on a command line), removes the file
# and starts the service.
t_boardpassword() {
  service_start
  tune --arg c "$A" '.plugin.commit = $c'
  local h=$T/$CASE/home u out pf=$T/$CASE/pw py=$XDG_DATA_HOME/conveyor/board-venv/bin/python3
  mkdir -p "${py%/*}" "$h" || fail "the Board's virtualenv was not made"
  # The Board's python3: can-open fails until add-user has run; add-user keeps what it read on stdin.
  printf '#!/bin/sh\necho "$CONVEYOR_MAIN $*" >> "$STUB/py"\n[ "$2" != add-user ] || cat > "$STUB/pwin"\n[ "$2" != can-open ] || [ -e "$STUB/pwin" ]\n' > "$py" && chmod +x "$py"
  if [ "$(uname -s)" = Darwin ]; then u=$h/Library/LaunchAgents/com.conveyor.dashboard.plist; else u=$h/.config/systemd/user/dashboard.service; fi
  echo 'pw-example-9e1' > "$pf" || fail "the password file was not made"
  out=$(cd "$R" && HOME=$h bash "$V/$A/conveyor/conveyor.sh" board --password-file "$pf" 2>&1 </dev/null) || fail "board with a password file exited non-zero: $out"
  grep -qxF "$R $V/$A/.claude/scripts/dashboard_server.py add-user admin --admin" "$STUB/py" \
    && [ "$(cat "$STUB/pwin")" = $'pw-example-9e1\npw-example-9e1' ] || fail "board did not add the admin with the password on stdin: $(cat "$STUB/py" "$STUB/pwin" 2>&1)"
  ! grep -q pw-example "$STUB/py" && [[ $out != *pw-example* ]] || fail "the password was on a command line or in board's output"
  [ ! -e "$pf" ] || fail "board left the password file"
  grep -qF "$V/$A/.claude/scripts/dashboard.sh" "$u" && grep -qx 'systemctl --user restart dashboard.service\|launchctl bootstrap .*com\.conveyor\.dashboard\.plist' "$STUB/svc" \
    || fail "board did not start the Board's service: $(cat "$u" "$STUB/svc" 2>&1)"
}
# Bug caught (#108): an `admin` added on the account page, its setup link unused, has no password; board's add-user
# stopped at "admin is already a user" and the Board was not started. board gives that admin the password (on stdin)
# and the admin role instead, then starts the service.
t_boardpasswordset() {
  service_start
  tune --arg c "$A" '.plugin.commit = $c'
  local h=$T/$CASE/home u out pf=$T/$CASE/pw auth=$T/$CASE/auth.json py=$XDG_DATA_HOME/conveyor/board-venv/bin/python3
  mkdir -p "${py%/*}" "$h" || fail "the Board's virtualenv was not made"
  jq -n '{noLoginHere: false, users: {admin: {role: "member", devices: {}}}}' > "$auth" || fail "the login store was not made"
  # The Board's python3: add-user refuses `admin` as the real one does; can-open fails until set-password has run.
  printf '#!/bin/sh\necho "$CONVEYOR_MAIN $*" >> "$STUB/py"\n[ "$2" != add-user ] || { echo "admin is already a user" >&2; exit 1; }\n[ "$2" != set-password ] || cat > "$STUB/pwin"\n[ "$2" != can-open ] || [ -e "$STUB/pwin" ]\n' > "$py" && chmod +x "$py"
  if [ "$(uname -s)" = Darwin ]; then u=$h/Library/LaunchAgents/com.conveyor.dashboard.plist; else u=$h/.config/systemd/user/dashboard.service; fi
  echo 'pw-example-9e1' > "$pf" || fail "the password file was not made"
  out=$(cd "$R" && HOME=$h CONVEYOR_DASHBOARD_AUTH=$auth bash "$V/$A/conveyor/conveyor.sh" board --password-file "$pf" 2>&1 </dev/null) || fail "board for an admin with no password exited non-zero: $out"
  grep -qxF "$R $V/$A/.claude/scripts/dashboard_server.py set-password admin" "$STUB/py" && grep -qxF "$R $V/$A/.claude/scripts/dashboard_server.py set-role admin admin" "$STUB/py" \
    && ! grep -q ' add-user ' "$STUB/py" && [ "$(cat "$STUB/pwin")" = $'pw-example-9e1\npw-example-9e1' ] \
    || fail "board did not give the existing admin the password on stdin and the admin role: $(cat "$STUB/py" "$STUB/pwin" 2>&1)"
  ! grep -q pw-example "$STUB/py" && [ ! -e "$pf" ] || fail "the password was on a command line, or the file was left"
  grep -qx 'systemctl --user restart dashboard.service\|launchctl bootstrap .*com\.conveyor\.dashboard\.plist' "$STUB/svc" \
    || fail "board did not start the Board's service: $(cat "$u" "$STUB/svc" 2>&1)"
}

# Bugs: a command run through shim.sh from an install takes the install's version folder, read-only and with no .git,
# as the project: git prints `fatal:` and its state folder is made inside the install, so `control` fails; or the shim
# drops the main checkout its caller names.
t_shimmain() {
  setup '[]'; local c=0123456789abcdef0123456789abcdef01234567 v o=$T/$CASE/other out
  v=$T/$CASE/data/conveyor/versions/$c; trap 'chmod -R u+w "$T/$CASE"' EXIT
  mkdir -p "$v" && cp -a "$SRC" "$v/conveyor" && cp "$SRC/../shim.sh" "$v/" && chmod -R a-w "$v" && cp -a "$R" "$o" \
    || fail "the fixture install could not be made"
  tune --arg c "$c" '.plugin.commit = $c'
  shim() { (cd "$R" && exec env -u CLAUDE_PROJECT_DIR -u CONVEYOR_CARDS -u CONVEYOR_MAIN XDG_DATA_HOME="$T/$CASE/data" "$@" bash "$v/shim.sh" conveyor/conveyor.sh control hold 1 2>&1); }
  # sd <checkout>: its state folder, as the engine finds it; held <checkout>: the issues its control record holds.
  sd() { CONVEYOR_MAIN=$1 bash "$SRC/conveyor.sh" state-dir; }
  held() { jq -c .held "$(sd "$1")/control.json"; }
  [ "$(sd "$R")" != "$(sd "$o")" ] || fail "the two checkouts share a state folder: $(sd "$R")"
  out=$(shim) && [ "$(held "$R")" = '[1]' ] || fail "the hold through the shim did not reach the project's state folder: $out"
  ! grep -q 'fatal:' <<<"$out" || fail "the shim's command ran git in the version folder: $out"
  out=$(shim CONVEYOR_MAIN="$o") && [ "$(held "$o")" = '[1]' ] \
    || fail "the shim did not keep the caller's CONVEYOR_MAIN: $out"
}

# Bugs: from a marketplace install, the engine runs from a folder in no git checkout (Claude Code's plugin copy, which
# setup runs) or from a version folder; the main checkout was looked up there for every command but a few, so git
# printed `fatal: not a git repository` and the empty answer became the folder `/` (`mkdir: cannot create directory
# '//conveyor'`): retry queued no card. Every command run from the plugin copy also printed it, reading the commit it
# runs. The fixture: the project's main checkout, a verified install of the commit it pins, and the plugin copy, with
# shim.sh at its top and no .git, apart from both.
t_shimmarket() {
  service_start; tune --arg c "$A" '.plugin.commit = $c'
  local p=$T/$CASE/plugins/cache/m/conveyor-belt/1.1.1 n=$T/$CASE/nogit x i=6 err=$T/$CASE/err out
  mkdir -p "$p" "$n" && cp -a "$SRC" "$p/conveyor" && ln -s "$SRC/../.claude" "$p/.claude" && cp "$SRC/../shim.sh" "$p/" \
    && ! git -C "$p" rev-parse --git-dir >/dev/null 2>&1 && ! git -C "$n" rev-parse --git-dir >/dev/null 2>&1 \
    || fail "the plugin copy, in no git checkout, could not be made"
  for x in 7 8 9; do
    jq -cn --argjson i "$x" '{card: "c\($i)", issue: $i, step: "blocked", time: "2026-03-01T00:02:00Z", tokens: {claude: 0, codex: 0}, result: "blocked", sha: "", reason: "build: failed"}' >> "$ST/cards.jsonl"
  done
  # run <folder> <conveyor.sh, or shim.sh and its path> <arg>...: the command as a user runs it there, its stderr in $err.
  run() { (cd "$1" && exec env -u CLAUDE_PROJECT_DIR -u CONVEYOR_CARDS -u CONVEYOR_MAIN HOME="$T/$CASE/home" bash "${@:2}" 2>"$err"); }
  # The plugin's shim, the plugin copy's conveyor.sh (as /conveyor-belt:setup runs it) and the install's (docs/setup.md).
  for x in "$p/shim.sh conveyor/conveyor.sh" "$p/conveyor/conveyor.sh" "$V/$A/conveyor/conveyor.sh"; do
    i=$((i + 1))
    # shellcheck disable=SC2086 # the shim and its path are two words
    out=$(run "$R" $x retry "$i") && jq -se --argjson i "$i" 'any(.issue == $i)' "$ST/retried.jsonl" >/dev/null \
      || fail "retry $i through $x did not queue the card: $out $(cat "$err")"
    ! grep -q 'not a git repository' "$err" || fail "retry through $x ran git outside the project's checkout: $(cat "$err")"
  done
  # Each command the plugin's setup runs from the plugin copy; their outcomes here (no virtualenv, no answers) are not
  # what is tested, only that none reads git outside a checkout.
  for x in setup doctor install-service board; do
    run "$R" "$p/conveyor/conveyor.sh" "$x" >/dev/null
    ! grep -q 'not a git repository' "$err" || fail "$x from the plugin copy ran git outside the project's checkout: $(cat "$err")"
  done
  # The plugin copy has no commit to pin and no origin to clone: each says so, naming its folder, with no git error.
  tune 'del(.plugin)'; x=$(cd "$p/conveyor" && pwd -P) # the engine's folder as it names itself, its links followed
  run "$R" "$p/conveyor/conveyor.sh" setup --fast-lane no --research-lane no --survey no --pin >/dev/null && fail "setup --pin from the plugin copy did not fail"
  [ "$(cat "$err")" = "conveyor: the pin could not be written: $x is in no git checkout, so its commit cannot be read" ] \
    || fail "setup --pin from the plugin copy did not say why it wrote no pin: $(cat "$err")"
  run "$R" "$p/conveyor/conveyor.sh" install "$B" >/dev/null && fail "install from the plugin copy did not fail"
  [ "$(cat "$err")" = "conveyor: $x is in no git checkout with an origin to clone" ] \
    || fail "install from the plugin copy did not say why it cloned nothing: $(cat "$err")"
  tune --arg c "$A" '.plugin.commit = $c'
  # Called in a folder in no git checkout, the lookup has no answer: the command stops at once and names that folder.
  run "$n" "$V/$A/conveyor/conveyor.sh" retry 7 >/dev/null && fail "retry in a folder in no git checkout did not fail"
  [ "$(cat "$err")" = "conveyor: the project's main checkout cannot be found: $(cd "$n" && pwd) is in no git checkout; run conveyor.sh in the project's checkout, or name it in CONVEYOR_MAIN" ] \
    || fail "the empty lookup did not stop with its message alone: $(cat "$err")"
}
