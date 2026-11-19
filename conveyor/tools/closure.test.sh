#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 600
# Release 1 runs from its computed closure alone (plan section 11): closure.sh's set, staged into an empty folder with
# no host project's checkout reachable, holds exactly the set's paths (a path missing and a path beyond the set each
# fail, named), none of them product code or what stays in the host project, and passes one smoke check there: the
# engine (conveyor.sh state-dir), the Board server's module (loaded, no server started) and a hook (bash-write-rules).
# No test file runs from the copy: a release runs each one in the checkout, as part of the whole suite.
set -uo pipefail
SRC=$(cd "$(dirname "$0")" && pwd -P); TOP=$(cd "$SRC/../.." && pwd -P)
# This file's own sed -i is a GNU call: on macOS it runs Homebrew's, as the engine's does (portable.sh).
. "$SRC/../lib/portable.sh"; p_tools
# The machine's test slots: each case, run beside the others, holds one.
. "$SRC/../lib/slots.sh"; slot_pool || exit 1
# The install's HOME is a fresh folder, not the user's; it sits under the user's HOME, not under scratch space, which
# hook tests treat apart (bash-guardrails-search's checkout box).
T=$(mktemp -d); H=$(mktemp -d "$HOME/.closure-test.XXXXXX"); trap 'rm -rf "$T" "$H"' EXIT
fail() { echo "FAIL [$CASE]: $*" >&2; exit 1; }
SET=$T/set; bash "$SRC/closure.sh" > "$SET" || { echo "FAIL: closure.sh exited non-zero" >&2; exit 1; }
# Bug (issue 563): a shipped file the set misses (one sourced through a path built at run time) is listed here in
# seconds, and install() fails on it before it makes the copy.
UNREACHED=$T/unreached; bash "$SRC/closure.sh" --unreached > "$UNREACHED" || { echo "FAIL: closure.sh --unreached exited non-zero" >&2; exit 1; }
# The set's files copied into a folder, with their modes and times, by one tar each way, not a mkdir and a cp a file.
copyset() { mkdir -p "$1" && tar -C "$TOP" -cf - -T "$SET" | tar -C "$1" -xpf -; }

# Bugs: a dependency the plan names (section 11) is left out of the set; the pack's hooks, which section 11 keeps in
# the host project, are pulled into a set that will be published. Bug (issue 775): the Foreman's archive.py, reached
# only through lib.sh's FHERE, was in the set only because the whole conveyor/foreman/ folder was.
t_set() {
  local f
  for f in .claude/hooks/lib/edit-payload.sh .claude/hooks/lib/strip-quoted.sh .claude/scripts/decision.sh \
    conveyor/conveyor.sh conveyor/lib/pack.sh conveyor/jq/rows.jq .claude/dashboard/panels/belt.js conveyor/foreman/archive.py; do
    grep -qxF "$f" "$SET" || fail "the set misses $f"
  done
  # Bug: the plugin's hooks.json runs a file (the shim, a hook) the install does not hold, so the hook fails there.
  grep -qxF hooks/hooks.json "$SET" || fail "the set misses hooks/hooks.json"
  jq -r '.hooks[][].hooks[].command' "$TOP/hooks/hooks.json" | grep -oE '(\$\{CLAUDE_PLUGIN_ROOT\}"?/)?[^ "]+\.sh' \
    | sed 's|^${CLAUDE_PLUGIN_ROOT}"*/||' | sort -u > "$T/plugin-hooks"
  grep -qxF shim.sh "$T/plugin-hooks" || fail "read no shim.sh from hooks/hooks.json"
  while IFS= read -r f; do grep -qxF "$f" "$SET" || fail "the set misses $f, which hooks/hooks.json runs"; done < "$T/plugin-hooks"
  # Bug (#166): /units (hooks/units.tsx) runs its fetch script by a path built at run time, which the set missed, so
  # the Board's readers failed from the install with "units-fetch.sh: No such file or directory".
  f=$(sed -n "s/^const FETCH = '\([^']*\)'.*/\1/p" "$TOP/hooks/units.tsx"); [ -n "$f" ] || fail "read no fetch script from hooks/units.tsx"
  grep -qxF "$f" "$SET" || fail "the set misses $f, which hooks/units.tsx runs"
  # The pack's hooks: a fixture checkout (the set, the test pack's hooks.json as its pack's, each hook it names beside
  # the release-1 hooks), never this repo's .conveyor/, whose pack may name no hooks.
  local d=$T/packhooks.d f
  copyset "$d" || fail "cannot copy the set"
  mkdir -p "$d/.conveyor" && cp "$TOP/conveyor/lib/test-hooks.json" "$d/.conveyor/hooks.json" || fail "cannot copy the test pack's hooks.json"
  sed -n 's|.*"\$CLAUDE_PROJECT_DIR\\*"*/\([^"\\]*\).*|\1|p' "$d/.conveyor/hooks.json" > "$T/packhooks"
  [ "$(wc -l < "$T/packhooks")" -ge 3 ] || fail "read no hooks from the pack's hooks.json"
  while IFS= read -r f; do printf '#!/usr/bin/env bash\nexit 0\n' > "$d/$f" || fail "cannot make $f"; done < "$T/packhooks"
  git -C "$d" init -q && git -C "$d" add -A || fail "cannot make the fixture a repository"
  bash "$SRC/closure.sh" "$d" > "$T/packhooks.set" || fail "the closure of the fixture failed"
  ! grep -xFf "$T/packhooks" "$T/packhooks.set" || fail "the set holds the pack's hooks"
}

# Bug: a release-1 file that reads a file of the project pack folder (.conveyor/) by a literal path pulls it into the
# set, so the import refuses the whole set.
t_pack() {
  local d=$T/pack
  copyset "$d" || fail "cannot copy the set"
  sed -i '1a HERE=$(dirname "$0"); cat "$HERE/../.conveyor/x" "$(git rev-parse --show-toplevel)/.conveyor/y"' "$d/conveyor/conveyor.sh"
  mkdir -p "$d/.conveyor" && echo x > "$d/.conveyor/x" && echo y > "$d/.conveyor/y"
  git -C "$d" init -q && git -C "$d" add -A || fail "cannot make the fixture a repository"
  bash "$SRC/closure.sh" "$d" > "$T/pack.set" || fail "the closure of the fixture failed"
  grep -qxF conveyor/conveyor.sh "$T/pack.set" || fail "the fixture's closure misses its entry point"
  ! grep '^\.conveyor/' "$T/pack.set" || fail "a read of the project pack is followed"
}

# Bug: a file the code needs is left out of the set because the code first tests for it, though its absence stops the
# code ([ -f x ] || exit 1; . x), as if it were optional. Bug (#757): a file of conveyor/lib named at run time
# (commands/snapshot.sh's "$HERE/lib/$l.sh") was taken for a read of the whole folder, so the optional files were in the set.
t_required() {
  local d=$T/req l
  copyset "$d" || fail "cannot copy the set"
  for l in '[ -f "$HERE/lib/req1.sh" ] || exit 1; . "$HERE/lib/req1.sh"' \
    '[ -e "$HERE/lib/req2.sh" ] || { echo "no req2" >&2; exit 2; }; . "$HERE/lib/req2.sh"' \
    '[ ! -f "$HERE/lib/req3.sh" ] \&\& exit 1; . "$HERE/lib/req3.sh"' \
    '[ -f "$HERE/lib/opt1.sh" ] || exit 0; . "$HERE/lib/opt1.sh"' '[ ! -e "$HERE/lib/opt2.sh" ] || . "$HERE/lib/opt2.sh"'; do
    sed -i "1a HERE=\$(dirname \"\$0\"); $l" "$d/conveyor/conveyor.sh"
  done
  for l in req1 req2 req3 opt1 opt2; do echo : > "$d/conveyor/lib/$l.sh"; done
  git -C "$d" init -q && git -C "$d" add -A || fail "cannot make the fixture a repository"
  bash "$SRC/closure.sh" "$d" > "$T/req.set" || fail "the closure of the fixture failed"
  for l in req1 req2 req3; do grep -qxF "conveyor/lib/$l.sh" "$T/req.set" || fail "a file whose absence stops the code ($l) is left out"; done
  ! grep -E 'conveyor/lib/opt[12]\.sh' "$T/req.set" || fail "an optional file is in the set"
}

# The install: the set staged into an empty folder, made a repository of its own. run() runs a command in it with the
# checkout out of reach: every worktree of the checkout's repository is an empty folder (bwrap; on macOS, which has no
# bwrap, sandbox-exec denies reading or writing it), its own PID namespace leaves no host process's /proc/<pid>/root
# to reach the host's filesystem through, no variable of its environment comes along (CONVEYOR_*, GIT_*,
# CLAUDE_PROJECT_DIR), none of its folders is on PATH and HOME is a fresh folder holding only a git identity, so no
# other host configuration is read.
printf '[user]\n\tname = t\n\temail = t@users.noreply.github.com\n' > "$H/.gitconfig"
install() {
  local f p w hide=()
  [ ! -s "$UNREACHED" ] || fail "$(sed 's/$/: closure.sh does not reach it: add an anchored source, or a line to the left-out list/' "$UNREACHED")"
  [ "$(uname -s)" = Darwin ] || command -v bwrap >/dev/null || fail "bwrap is not installed: the install cannot run with the checkout out of reach"
  I=$T/install; mkdir -p "$T/tmp"
  copyset "$I" || fail "cannot copy the set"
  # Bug (issue 775): the copy is what ships, but the check compared the set with what closure.sh walks from the copy,
  # not with the files the copy holds, and a file the walk does not reach was not seen. Its paths are the set's, each
  # way: a path of the set the copy misses, and a path the copy holds beyond the set (a folder the set named, which tar
  # copies whole), each fails, named.
  (cd "$I" && find . \( -type f -o -type l \) | sed 's|^\./||' | LC_ALL=C sort) > "$T/staged" || fail "cannot list the staged copy"
  LC_ALL=C comm -23 "$SET" "$T/staged" > "$T/staged.miss" && LC_ALL=C comm -13 "$SET" "$T/staged" > "$T/staged.extra" \
    || fail "cannot compare the staged copy with the set"
  [ ! -s "$T/staged.miss" ] || fail "$(sed 's/^/the staged copy misses /' "$T/staged.miss")"
  [ ! -s "$T/staged.extra" ] || fail "$(sed 's/.*/the staged copy holds &, which is not in the set/' "$T/staged.extra")"
  # What will be published holds no product code, nor what section 11 keeps in the host project (the pack, the area
  # rule files, the startup instructions).
  ! grep -E '^(src|web|shared|lambdas|infra|ml)/' "$T/staged" || fail "the staged copy holds product code"
  ! grep -E '^(\.claude/rules/|\.claude/commands/|\.conveyor/|AGENT_STARTUP\.md$|CLAUDE\.md$)' "$T/staged" \
    || fail "the staged copy holds what stays in the host project"
  ! grep -rlF "$TOP" "$I" || fail "a file of the set names the checkout"
  path=''; IFS=: read -ra p <<<"$PATH"; for f in "${p[@]}"; do case $f/ in "$TOP"/*) ;; *) path=${path:+$path:}$f ;; esac; done
  # The Board's virtualenv (setup fills it; the Board's server loads its packages) is a dependency: mounted read-only
  # where the install's fresh HOME looks for it. A machine with none mounts none, and the smoke check says to run setup.
  bv=$(readlink -f "${XDG_DATA_HOME:-$HOME/.local/share}/conveyor/board-venv") && [ -d "$bv" ] || bv=''
  [ -z "$bv" ] || mkdir -p "$H/.local/share/conveyor" || fail "cannot make the install's data folder"
  if [ "$(uname -s)" = Darwin ]; then
    # The last rule that matches wins: the worktrees are denied, then the virtualenv (which may sit in one) allowed back
    # to read, never to write, through a link in its place. macOS has no /proc, so no process's root reaches the host's
    # filesystem.
    local sb='(version 1)(allow default)'
    while IFS= read -r w; do sb+="(deny file-read* file-write* (subpath \"${w#worktree }\"))"; done < <(git -C "$TOP" worktree list --porcelain | grep '^worktree ')
    [ -z "$bv" ] || { sb+="(allow file-read* (subpath \"$bv\"))(deny file-write* (subpath \"$bv\"))"; ln -sfn "$bv" "$H/.local/share/conveyor/board-venv"; }
    BW=(sandbox-exec -p "$sb")
  else
    while IFS= read -r w; do hide+=(--tmpfs "${w#worktree }"); done < <(git -C "$TOP" worktree list --porcelain | grep '^worktree ')
    # /tmp is the run's own: what the hook writes there is not left on the machine.
    BW=(bwrap --die-with-parent --unshare-pid --bind / / --dev /dev --proc /proc "${hide[@]}" --bind "$T/tmp" /tmp --bind "$T" "$T")
    [ -z "$bv" ] || { mkdir -p "$H/.local/share/conveyor/board-venv"; BW+=(--ro-bind "$bv" "$H/.local/share/conveyor/board-venv"); }
  fi
  ( cd "$I" && run git init -q && run git add -A && run git commit -qm release-1 ) || fail "cannot make the install a repository"
  ( cd "$I" && run test ! -e "$TOP/conveyor/conveyor.sh" ) || fail "the checkout is reachable from the install's runs"
  ( cd "$I" && run bash -c 'for p in "/proc/$1" /proc/[0-9]*; do [ ! -e "$p/root$2" ] || exit 1; done' _ "$$" "$TOP/conveyor/conveyor.sh" ) \
    || fail "the checkout is reachable from the install's runs through a process's root"
}
run() { "${BW[@]}" env -i HOME="$H" PATH="$path" TMPDIR="$T/tmp" LANG=C.UTF-8 USER="${USER:-t}" "$@"; }

# Bugs: closure.sh misses a file a release-1 part reaches (the part runs in the checkout and fails from the install),
# the staged copy misses a path of the set or holds one beyond it, or the set needs the checkout (a file of it read
# through the environment or a path outside the set). The smoke check, from the install: the engine runs
# (conveyor.sh state-dir gives the install's own state folder), the Board server's module loads with every module it
# imports (no server started: a server would not end within the timeout), and bash-write-rules (the install ships no
# rules) gives a shell write the project's rule for its path, and a project with no rules nothing and no error.
t_install() {
  local p=$T/project o w
  install
  # The engine names its checkout by its physical path (pwd -P), so on macOS, where /tmp is a link to /private/tmp, the
  # state folder is compared with the install's physical path.
  w=$(cd "$I" && pwd -P)/conveyor/state || fail "cannot read the install's physical path"
  o=$(cd "$I" && run bash conveyor/conveyor.sh state-dir 2>&1) && [ "$o" = "$w" ] \
    || fail "conveyor.sh state-dir from the install did not give its state folder ($w): $o"
  [ -n "$bv" ] || fail "the Board's virtualenv is missing (${XDG_DATA_HOME:-$HOME/.local/share}/conveyor/board-venv): run conveyor.sh setup"
  o=$(cd "$I" && run timeout 60 "$H/.local/share/conveyor/board-venv/bin/python3" -I -c \
    'import sys; sys.path.insert(0, ".claude/scripts"); import dashboard_server' 2>&1) \
    || fail "the Board server's module did not load from the install: $o"
  [ ! -e "$I/.claude/rules" ] || fail "the install ships rules of its own"
  mkdir -p "$p/.claude/rules" "$p.bare" && printf -- '---\npaths: ["docs/zz/**"]\n---\nZZ-RULE\n' > "$p/.claude/rules/zz.md"
  bwr() { # <project> -> the hook's output and errors for a shell write into docs/zz there
    ( cd "$1" && jq -cn --arg cwd "$1" '{session_id: "closure-\(now)", cwd: $cwd, tool_input: {command: "echo x > docs/zz/a.md"}}' \
      | run env CLAUDE_PROJECT_DIR="$1" bash "$I/.claude/hooks/bash-write-rules.sh" 2>&1 )
  }
  bwr "$p" | grep -q ZZ-RULE || fail "bash-write-rules from the install did not give the project's rule"
  o=$(bwr "$p.bare") && [ -z "$o" ] || fail "bash-write-rules from the install, for a project with no rules, said: $o"
  rm -f /tmp/claude-bash-rules-zz-closure-*
}

ALL="set required pack install"
SEL=${CONVEYOR_SHELL_TEST_CASE:-$ALL}; SEL=${SEL//,/ }
for CASE in $SEL; do case " $ALL " in *" $CASE "*) ;; *) echo "unknown case $CASE" >&2; exit 2 ;; esac; done
# The cases side by side, each holding a test slot. Each case's output is kept apart and shown in turn once all are done.
for CASE in $SEL; do { slot_take; slot_mine; ( "t_$CASE" ); echo $? > "$T/$CASE.rc"; } > "$T/$CASE.log" 2>&1 & done; wait
for CASE in $SEL; do cat "$T/$CASE.log"; [ "$(cat "$T/$CASE.rc")" = 0 ] || exit 1; echo "ok $CASE"; done
