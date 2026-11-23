#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 300
# Engine cases: install, and the fixtures the service's cases share (the service: service.test.sh, serviceown.test.sh;
# the Board: board.test.sh; shim.sh: shim.test.sh).
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
  # The engine without its tests (half its files): no case runs them, and every case copies, clones and hashes the rest.
  mkdir -p "$D/conveyor"; ln -s "$SRC/../.claude" "$D/.claude"; cp -r "$SRC"/* "$D/conveyor/"; rm -rf "$D/conveyor/state" "$D/conveyor/tests"
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
# The fixture of the service's cases (service.test.sh, serviceown.test.sh), the Board's (board.test.sh) and shim.sh's
# from a plugin copy (shim.test.sh).
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

# Bugs: an install is kept that is not the commit asked for (an abbreviated id, a commit the repo does not have, a
# folder already there holding something else), or is left half made; an install can be written to, so the code a
# pin names can change under it; install makes a state folder in the checkout it runs from.
t_install() {
  coderepo; X=$D/conveyor/conveyor.sh; trap 'chmod -R u+w "$T/$CASE"' EXIT
  bash "$X" install "${A:0:12}" >/dev/null 2>&1 && fail "an abbreviated commit id was installed"
  [ ! -e "$V/${A:0:12}" ] || fail "an abbreviated commit id left a version folder"
  bad=$(printf '%040d' 0)
  bash "$X" install "$bad" >/dev/null 2>&1 && fail "a commit the repo does not have was installed"
  [ ! -e "$V/$bad" ] && ! compgen -G "$V/$bad.part*" >/dev/null || fail "a commit that could not be verified left a folder: $(ls "$V")"
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
  [ ! -e "$V/$A" ] && ! compgen -G "$V/$A.part*" >/dev/null || fail "a fresh clone a checkout hook changed left a folder: $(ls "$V")"
  # Then, on the same code repo (each case pays about 0.3 CPU s for its keeper and its code repo), the install made.
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
# A version folder already there that is the commit but can be written: changed, even where the change is hidden from
# status, it is refused; as cloned, it is made read-only. One writable checkout for all of it, each change undone
# before the next is made (each case pays about 0.3 CPU s for its keeper and its code repo): the last install, of the
# checkout as cloned, passes only if no change was left behind.
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
  # The same writable checkout, each change undone: changes hidden from status are refused too.
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
  # A link at the version folder to a writable clone of the commit: the read-only check does not follow it.
  mv "$V/$B" "$T/$CASE/linked" && ln -s "$T/$CASE/linked" "$V/$B" || fail "the linked version folder was not made"
  bash "$X" install "$B" >/dev/null 2>&1 && fail "a link at the version folder was taken as installed"
  rm "$V/$B" && mv "$T/$CASE/linked" "$V/$B" || fail "the linked version folder was not undone"
  bash "$X" install "$B" >/dev/null || fail "a writable version folder as cloned was refused"
  [ -z "$(find "$V/$B" ! -type l -perm /222)" ] || fail "a writable version folder was taken as installed and left writable"
  [ ! -e "$D/conveyor/state" ] || fail "install made a state folder in the checkout it ran from"
}

# Bug: two projects' loops take the same commit at once. The second install waits on the mirror's lock while the
# first makes the version folder and moves it in; it then made its own .part and moved it into that read-only folder
# ("mv: cannot move ... Permission denied"), so its project took the commit only at its next take.
t_installrace() {
  coderepo; X=$D/conveyor/conveyor.sh; local w=$T/$CASE ip lk rc
  # Set aside in the same folder: a read-only folder cannot be moved to another one.
  bash "$X" install "$A" >/dev/null && mv "$V/$A" "$V/first" || fail "the first install was not made"
  trap 'kill ${lk:-} ${ip:-} 2>/dev/null; chmod -R u+w "$T/$CASE"' EXIT
  # The first install holds the mirror's lock; the second is started and waits on it.
  ( flock 9 && : > "$w/locked" && until [ -e "$w/go" ]; do sleep 0.1; done ) 9>>"$V/mirror.git.lock" & lk=$!
  until [ -e "$w/locked" ]; do kill -0 $lk 2>/dev/null || fail "the lock was not taken"; sleep 0.1; done
  bash "$X" install "$A" > "$w/out" 2>&1 & ip=$!
  until for p in $(below $ip); do ps -o args= -p "$p"; done 2>/dev/null | grep -q '^flock -w 600'; do
    kill -0 $ip 2>/dev/null || fail "the second install did not wait on the lock: $(cat "$w/out")"; sleep 0.1; done
  # The first one's folder is moved in, and its lock let go.
  mv "$V/first" "$V/$A" && : > "$w/go" || fail "the first install's folder was not moved in"
  wait $ip; rc=$?
  [ "$rc" = 0 ] && grep -q "conveyor: $A is installed in $V/$A, read-only" "$w/out" || fail "the second install of the same commit failed: $(cat "$w/out")"
  ! compgen -G "$V/$A.part*" >/dev/null && ! compgen -G "$V/$A/$A.part*" >/dev/null && [ -z "$(find "$V/$A" ! -type l -perm /222)" ] \
    || fail "the second install left its own copy, or the folder writable: $(ls -a "$V" "$V/$A")"
}

# Bug: an older engine lets the mirror's lock go before it moves its own folder of the same commit in, so its move
# can come after this install's check that none is there; this install's move then failed into that read-only folder,
# and its project took the commit only at its next take. A stand-in mv puts the other folder in place just before this
# install's move.
t_installmv() {
  coderepo; X=$D/conveyor/conveyor.sh; local w=$T/$CASE rc
  # Text check, as a comment has no behaviour: the one above the move said the older engine predates the mirror's lock,
  # but that engine takes the lock and lets it go before its move.
  grep -B2 '^ *chmod -R a-w "$p" && mv "$p" "$d"' "$SRC/lib/install.sh" | grep -q "lets the mirror's lock go before it moves" \
    && ! grep -q 'older than this lock' "$SRC/lib/install.sh" || fail "install.sh's comment above the move misstates when an older engine moves its folder in"
  bash "$X" install "$A" >/dev/null && mv "$V/$A" "$V/first" || fail "the first install was not made"
  trap 'chmod -R u+w "$T/$CASE"' EXIT
  mkdir -p "$w/bin" && printf '%s\n' '#!/usr/bin/env bash' \
    '[[ $1 != "$V/$A".part.* || $2 != "$V/$A" ]] || [ ! -e "$V/first" ] || command -p mv "$V/first" "$V/$A"' 'exec command -p mv "$@"' > "$w/bin/mv" \
    && chmod +x "$w/bin/mv" || fail "the stand-in mv was not made"
  export V A; PATH=$w/bin:$PATH bash "$X" install "$A" > "$w/out" 2>&1; rc=$?
  [ "$rc" = 0 ] && [ ! -e "$V/first" ] && grep -q "conveyor: $A is installed in $V/$A, read-only" "$w/out" \
    || fail "the install whose move met the other engine's folder failed: rc=$rc $(cat "$w/out")"
  ! compgen -G "$V/$A.part*" >/dev/null && [ -z "$(find "$V/$A" ! -type l -perm /222)" ] || fail "the install left its own copy, or the folder writable: $(ls -a "$V")"
}

# Bug (O202): an older engine builds in the shared <commit>.part and lets the mirror's lock go before its chmod and
# move. A new install then took the lock, found no version folder, removed that .part and cloned into it, so the old
# engine's move could publish the new install's half-made, unverified clone. Here the old engine's .part stands, with
# a file of its own, outside the lock: the new install neither removes nor uses it, and the folder it publishes is the
# commit, read-only.
t_installold() {
  coderepo; X=$D/conveyor/conveyor.sh; local w=$T/$CASE
  trap 'chmod -R u+w "$T/$CASE"' EXIT
  mkdir -p "$V/$A.part" && echo old > "$V/$A.part/old-engine" || fail "the old engine's folder was not made"
  bash "$X" install "$A" > "$w/out" 2>&1 || fail "the install beside the old engine's folder failed: $(cat "$w/out")"
  [ "$(ls -A "$V/$A.part")" = old-engine ] && [ "$(cat "$V/$A.part/old-engine")" = old ] \
    || fail "the install removed or used the old engine's $V/$A.part: $(ls -A "$V/$A.part" 2>&1)"
  # installed ro: its HEAD, every tracked file's content and mode as commit A has them, nothing added, nothing writable.
  ( . "$SRC/lib/install.sh" && installed "$A" ro "$V/$A" ) && [ "$(compgen -G "$V/$A.part*")" = "$V/$A.part" ] \
    || fail "the published $V/$A does not pass installed $A ro, or the install left its own folder: $(ls -a "$V")"
}
