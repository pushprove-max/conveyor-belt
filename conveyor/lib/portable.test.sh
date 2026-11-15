#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 60
# The portability helpers (portable.sh, plan section 4), on this host and on a macOS stood in for by stubs on PATH.
set -uo pipefail
SRC=$(cd "$(dirname "$0")" && pwd -P)
# The helpers and this file's touch -d are GNU calls: on macOS they run Homebrew's, as the engine's do.
. "$SRC/portable.sh"; p_tools
. "$SRC/../tests/wait.sh"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
fail() { echo "FAIL [$CASE]: $*" >&2; exit 1; }
p() { bash -c '. "$0/portable.sh" && "$@"' "$SRC" "$@"; } # <helper> [args]: one helper, in a fresh bash

# Bug: an older bash runs on and fails later on `wait -n -p` (5.1), or a new enough one is refused.
t_bash() {
  out=$(p require_bash 99.0 2>&1) && fail "bash 99.0 was not refused"
  grep -q "needs bash 99.0 or newer" <<<"$out" || fail "the refusal does not say what it needs: $out"
  out=$(p require_bash "${BASH_VERSINFO[0]}.$((BASH_VERSINFO[1] + 1))" 2>&1) && fail "a newer minor of this major was not refused"
  p require_bash "${BASH_VERSINFO[0]}.${BASH_VERSINFO[1]}" || fail "this bash's own version was refused"
  p require_bash 4.4 || fail "an older major was refused"
}

# Bug: on macOS the BSD tools answer GNU calls wrongly (or not at all), or a missing GNU tool or flock goes unsaid.
t_darwin() {
  B=$T/darwin; mkdir -p "$B/bin" "$B/os"
  printf '#!/bin/sh\necho Darwin\n' > "$B/os/uname"
  for t in timeout date stat find sed grep flock; do printf '#!/bin/sh\necho gnu-%s\n' "$t" > "$B/os/$t"; done
  chmod +x "$B/os"/*
  for g in coreutils:timeout coreutils:date coreutils:stat findutils:find gnu-sed:sed grep:grep; do
    mkdir -p "$B/opt/${g%%:*}/libexec/gnubin"; printf '#!/bin/sh\necho brew-%s\n' "${g#*:}" > "$B/opt/${g%%:*}/libexec/gnubin/${g#*:}"
  done
  printf '#!/bin/sh\n' > "$B/bin/gtimeout"; chmod +x "$B/bin/gtimeout" "$B"/opt/*/libexec/gnubin/*
  out=$(PATH=$B/bin:$B/os:$PATH bash -c '. "$0/portable.sh" && p_tools && for t in timeout date stat find sed grep; do "$t"; done' "$SRC" 2>&1) \
    || fail "p_tools refused a complete Homebrew: $out"
  [ "$(tr '\n' ' ' <<<"$out")" = "brew-timeout brew-date brew-stat brew-find brew-sed brew-grep " ] || fail "a call did not reach Homebrew's GNU tool: $out"
  # This host's own flock is not on that PATH: only what p_tools runs besides the stubs.
  rm "$B/opt/gnu-sed/libexec/gnubin/sed" "$B/os/flock"; ln -s "$(command -v dirname)" "$B/os/dirname"
  out=$(PATH=$B/bin:$B/os "$BASH" -c '. "$0/portable.sh" && p_tools && echo went on' "$SRC" 2>&1) && fail "a missing gsed and flock were not refused: $out"
  grep -q 'missing: gsed flock' <<<"$out" || fail "the refusal does not name what is missing: $out"
}

# Bug: a host reading comes back in another shape than the sample expects, or a process is known by its pid alone.
t_host() {
  [[ $(p p_load) =~ ^[0-9]+(\.[0-9]+)?$ ]] || fail "load: $(p p_load)"
  read -r u t <<<"$(p p_mem)"; [[ $u =~ ^[0-9]+$ && $t =~ ^[0-9]+$ ]] && [ "$u" -le "$t" ] || fail "memory: $(p p_mem)"
  printf abc > "$T/f"; touch -d @1700000000 "$T/f"
  [ "$(p p_stat "$T/f" "$T/none")" = "3 1700000000" ] || fail "stat: $(p p_stat "$T/f" "$T/none")"
  [ "$(TZ=UTC p p_date 2026-11-10 +%s)" = 1794268800 ] || fail "date: $(TZ=UTC p p_date 2026-11-10 +%s)"
  p p_newer "$T/f" 60 && fail "a file changed long ago is new"
  touch "$T/f"; p p_newer "$T/f" 60 || fail "a file changed now is not new"
  sleep 30 & k=$!; s=$(p p_started $k) # sleep: a stand-in for a running process
  [ -n "$s" ] && p p_alive $k "$s" || fail "a running process with its start time is not alive: $s"
  p p_alive $k "Thu Jan  1 00:00:00 1970" && fail "a pid with another start time is alive"
  p p_alive $k "" && fail "a pid with no start time is alive"
  # A process is found with its parent and command line, the folder it runs in and what its environment held: doctor
  # tells a loop of another project, and of another host file, by them.
  grep -qx " *$k  *$BASHPID  *[a-z/]* 30" <<<"$(p p_procs)" || fail "the process list does not hold the process: $(p p_procs | grep " $k ")"
  ( cd "$T" && P_T='a b' exec sleep 30 ) & e=$! # sleep: a stand-in for a running process, in a folder and with a variable of its own
  wait_until '[ "$(p p_cwd $e)" -ef "$T" ]' || fail "the folder a process runs in: $(p p_cwd $e)"
  [ "$(p p_env $e P_T)" = 'a b' ] || fail "a variable of a process: $(p p_env $e P_T)"
  s2=$(p p_env $e P_NONE) && [ -z "$s2" ] || fail "a variable a process does not have: $s2"
  # Its arguments come apart where the system keeps them so (Linux), a space inside one kept: doctor tells a loop from
  # a process that only has the engine's path among its arguments by them.
  c='sleep 30 & echo $!; wait'; bash -c "$c" 'a b' c > "$T/argv" & s2=$! # sleep: keeps the bash, whose arguments are read, running
  wait_until '[ -s "$T/argv" ]' || fail "the process with arguments did not start"
  [ "$(uname -s)" = Darwin ] || [ "$(p p_argv $s2 | tr '\0' '\n')" = $'bash\n-c\n'"$c"$'\na b\nc' ] || fail "the arguments of a process: $(p p_argv $s2 | tr '\0' '|')"
  kill "$(cat "$T/argv")" $s2; wait $s2 2>/dev/null
  kill $e; wait $e 2>/dev/null; p p_env $e P_T >/dev/null && fail "an ended process has an environment"
  kill $k; wait $k 2>/dev/null; p p_alive $k "$s" && fail "an ended process is alive"
  # A process whose parent never reaps it stays a zombie, with its start time: it is not alive.
  bash -c 'sleep 0.2 & echo $!; exec sleep 30' > "$T/z" & k=$! # sleep: a child that ends, and a parent that goes on without reaping it
  wait_until '[ "$(ps -o stat= -p "$(cat "$T/z")" | tr -d " ")" = Z ]' || fail "no zombie: $(ps -o stat= -p "$(cat "$T/z")")"
  z=$(cat "$T/z")
  s=$(p p_started "$z"); [ -n "$s" ] || fail "a zombie has no start time"
  p p_alive "$z" "$s" && fail "a zombie is alive"
  kill $k; wait $k 2>/dev/null
  :
}

ALL="bash darwin host"
SEL=${CONVEYOR_SHELL_TEST_CASE:-$ALL}; SEL=${SEL//,/ }
for CASE in $SEL; do case " $ALL " in *" $CASE "*) ;; *) echo "unknown case $CASE" >&2; exit 2 ;; esac; done
for CASE in $SEL; do ( "t_$CASE" ) || exit 1; echo "ok $CASE"; done
