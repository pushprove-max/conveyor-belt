#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# The portability helpers (plan docs/plans/conveyor-plugin-2026-11-10.md, section 4). Sourced, never run.
# Conveyor runs on macOS, Linux and WSL. Its timeout, date, stat, find, sed and grep calls are GNU calls: p_path puts
# Homebrew's gnubin folders (coreutils, findutils, gnu-sed, grep: the g-prefixed tools under their plain names) first
# on PATH on macOS, then its keg-only openssl@3 and its bin folder, so every call, a child's or an exec'd one included,
# runs the GNU tool and Homebrew's copy of each requirement (jq 1.8, not Apple's /usr/bin/jq; lib/requires.sh). Every
# reading of the host that differs by system is a helper here; nothing else in conveyor/ reads /proc or /sys, or uses
# `date -d`, `stat -c` or `find -newermt` directly.
# This file must parse in macOS's bash 3.2, so that require_bash can say what is wrong.

# True on macOS: the system's name (uname -s), asked once in each shell that sources this file and kept (P_OS) for
# every later call, a subshell's included.
P_OS=''
p_darwin() { [ -n "$P_OS" ] || P_OS=$(uname -s); [ "$P_OS" = Darwin ]; }

# 0 when this bash is <major>.<minor> or newer.
p_bashok() { # <major.minor>
  local maj=${1%%.*} min=${1#*.}
  [ "${BASH_VERSINFO[0]}" -gt "$maj" ] || { [ "${BASH_VERSINFO[0]}" -eq "$maj" ] && [ "${BASH_VERSINFO[1]}" -ge "$min" ]; }
}
# Exits with the reason when this bash is older than <major>.<minor>.
require_bash() { # <major.minor>
  p_bashok "$1" && return 0
  echo "conveyor: needs bash $1 or newer; this is $BASH $BASH_VERSION (/conveyor-belt:setup installs it)" >&2
  exit 1
}
# Runs <script> with its <args> again in the bash first on PATH (after p_path: on macOS, Homebrew's) when this bash is
# older than <major>.<minor> and that bash is another file: `/usr/bin/env bash` can find macOS's /bin/bash 3.2 ahead of
# it. Else as require_bash: that bash is this one, so it runs once at most.
p_bash() { # <major.minor> <script> [args]
  local b
  if ! p_bashok "$1" && b=$(command -v bash) && [ ! "$b" -ef "$BASH" ]; then shift; exec "$b" "$@"; fi
  require_bash "$1"
}

# Homebrew's prefix on macOS: the one its gtimeout or brew is in (on PATH, or in either default place), else
# /opt/homebrew.
p_brewprefix() {
  local b
  for b in "$(command -v gtimeout 2>/dev/null)" "$(command -v brew 2>/dev/null)" /opt/homebrew/bin/brew /usr/local/bin/brew; do
    [ -n "$b" ] && [ -x "$b" ] && { dirname "$(dirname "$b")"; return 0; }
  done
  echo /opt/homebrew
}
# On macOS, Homebrew's gnubin folders, its openssl@3 and its bin folder first on PATH, each that is there, and
# exported; once only, so a nested call leaves PATH as it is. Elsewhere, nothing.
p_path() {
  local pre d dirs=''
  p_darwin || return 0
  pre=$(p_brewprefix)
  for d in coreutils findutils gnu-sed grep; do [ ! -d "$pre/opt/$d/libexec/gnubin" ] || dirs=$dirs:$pre/opt/$d/libexec/gnubin; done
  [ ! -d "$pre/opt/openssl@3/bin" ] || dirs=$dirs:$pre/opt/openssl@3/bin
  dirs=${dirs#:}${dirs:+:}$pre/bin
  case $PATH in "$dirs:"*) ;; *) PATH=$dirs:$PATH ;; esac
  export PATH
}

# flock everywhere; on macOS the GNU tools first on PATH (p_path). Exits with what is missing.
p_tools() {
  local miss='' pre pkg
  if p_darwin; then
    p_path; pre=$(p_brewprefix)
    for pkg in coreutils:timeout coreutils:date coreutils:stat findutils:find gnu-sed:sed grep:grep; do
      [ -x "$pre/opt/${pkg%%:*}/libexec/gnubin/${pkg#*:}" ] || miss="$miss g${pkg#*:}"
    done
  fi
  command -v flock >/dev/null 2>&1 || miss="$miss flock"
  [ -z "$miss" ] && return 0
  echo "conveyor: missing:$miss (/conveyor-belt:setup installs them)" >&2
  exit 1
}

# The 1-minute load average.
p_load() {
  if p_darwin; then sysctl -n vm.loadavg 2>/dev/null | awk '{print $2}'
  else local l; { read -r l _ < /proc/loadavg && printf '%s\n' "$l"; } 2>/dev/null; fi
}

# "<used KiB> <total KiB>"; used is what is not available (macOS: free, inactive and speculative pages are available).
p_mem() {
  if p_darwin; then
    { sysctl -n hw.memsize; vm_stat; } 2>/dev/null | awk 'NR == 1 {t = $1 / 1024; next} /page size of/ {p = $8}
      /^Pages (free|inactive|speculative):/ {gsub(/\./, "", $NF); a += $NF} END {if (t && p) printf "%d %d", t - a * p / 1024, t}'
  else awk '/^MemTotal:/ {t = $2} /^MemAvailable:/ {a = $2} END {if (t) printf "%d %d", t - a, t}' /proc/meminfo 2>/dev/null; fi
}

# "<size> <mtime epoch>" of each file, one line each; a file that is not there gives no line.
p_stat() { stat -c '%s %Y' "$@" 2>/dev/null; } # <file>...
# "<mtime epoch> <path>" of each file, one line each; a file that is not there gives no line.
p_mtimes() { stat -c '%Y %n' "$@" 2>/dev/null; } # <file>...
# "<size> <mtime> <ctime> <inode> <path>" of a file, the times to the nanosecond: a file written since, even to the same
# size within the same second, gives another line. Fails, with no line, when the file is not there.
p_filekey() { stat -c '%s %.9Y %.9Z %i %n' -- "$1" 2>/dev/null; } # <file>
# The mtime of each file in nanoseconds since the epoch, one line each: a file written later in the same second gives a
# larger number, in any locale (stat writes the decimal point of LC_NUMERIC: a comma in de_DE). A file that is not there
# gives no line.
p_mtimens() { LC_ALL=C stat -c '%.9Y' -- "$@" 2>/dev/null | tr -d .; } # <file>...
# The same with each file's ctime, which no program sets back: a rename or a chmod changes it, and keeps the mtime.
p_ctimens() { LC_ALL=C stat -c '%.9Z' -- "$@" 2>/dev/null | tr -d .; } # <file>...

# <date> (as GNU date -d reads it: "6 days ago", "2026-11-10") in <format>.
p_date() { date -d "$1" "$2"; } # <date> <+format>
# Each <date> on stdin (one a line, as p_date's) in <format>, one a line, from one date program.
p_dates() { date -f - "$1"; } # <+format>

# True when <file> changed in the last <seconds>.
p_newer() { [ -n "$(find "$1" -newermt "@$(($(date +%s) - $2))" 2>/dev/null)" ]; } # <file> <seconds>

# When <pid> started, as ps says it: with the pid, it names one process, so a pid used again is not taken for it.
# watch.py asks ps the same way; the two must match.
p_started() { local s; s=$(LC_ALL=C ps -o lstart= -p "$1" 2>/dev/null) || return 1; s=${s#"${s%%[![:space:]]*}"}; printf '%s\n' "${s%"${s##*[![:space:]]}"}"; } # <pid>

# True when <pid> runs and started at <started> (p_started's answer when it was recorded). A zombie, ended but not yet
# reaped by its parent, keeps its start time but does not run.
p_alive() { [ -n "$2" ] && [ "$(p_started "$1")" = "$2" ] && [[ $(ps -o stat= -p "$1" 2>/dev/null) != *Z* ]]; } # <pid> <started>

# A process held by a stop signal (SIGSTOP, SIGTSTP: state T) runs no more until it is given SIGCONT, and p_alive
# still counts it as running. ps's stat starts with the state letter on Linux and macOS alike ("T", "Tl", "T+", "TN"),
# after spaces on some; Linux's "t", stopped by a debugger, is not this: a SIGCONT does not resume it.
# True when <pid> is so stopped.
p_stopped() { [[ $(LC_ALL=C ps -o stat= -p "$1" 2>/dev/null) =~ ^[[:space:]]*T ]]; } # <pid>
# The pids of every process so stopped, one a line.
p_stoppedpids() { LC_ALL=C ps -A -o pid= -o stat= 2>/dev/null | awk '$2 ~ /^T/ { print $1 }'; }
# The pids of <pid> and of every process under it so stopped, one a line, <pid> first: a stop signal sent to a whole
# tree holds each of them, and a SIGCONT to <pid> alone leaves the rest stopped (a builder under its timeout wrapper).
p_stoppedtree() { # <pid>
  LC_ALL=C ps -A -o pid= -o ppid= -o stat= 2>/dev/null | awk -v r="$1" '{ p[NR] = $1; pp[NR] = $2; s[NR] = $3 }
    END { t[r] = 1; do { n = 0; for (i = 1; i <= NR; i++) if ((pp[i] in t) && !(p[i] in t)) { t[p[i]] = 1; n = 1 } } while (n)
      for (i = 1; i <= NR; i++) if (p[i] == r && s[i] ~ /^T/) print p[i]
      for (i = 1; i <= NR; i++) if (p[i] != r && (p[i] in t) && s[i] ~ /^T/) print p[i] }'
}

# Runs <command> as the leader of a session of its own (no controlling terminal, a process group of its own) and
# exits as it does: setsid on Linux; macOS has no setsid command, so perl's POSIX::setsid there.
p_setsid() { # <command> [args]
  if p_darwin; then perl -MPOSIX -e 'POSIX::setsid(); exec @ARGV or die "$ARGV[0]: $!\n"' "$@"; else setsid -w "$@"; fi
}

# Replaces this shell with <command>, as the leader of a session of its own: the same pid, which is then its own
# process group. For a background child (`p_execsid <command> &`, so $! names the command): no job control (set -m),
# whose setpgid fails with "Operation not permitted" in a hook on macOS. The caller must lead no process group
# (a background child of a shell without set -m does not): if it does, setsid forks on Linux and the pid changes,
# and on macOS the command does not run and the shell exits with "setsid: Operation not permitted".
p_execsid() { # <command> [args]
  if p_darwin; then exec perl -MPOSIX -e 'POSIX::setsid() > 0 or die "setsid: $!\n"; exec @ARGV or die "$ARGV[0]: $!\n"' "$@"; else exec setsid "$@"; fi
}

# Every process, one line each: "<pid> <its parent's pid> <its command line>".
p_procs() { ps -A -ww -o pid=,ppid=,args= 2>/dev/null; }

# <pid>'s arguments, each one ended by a NUL byte, where the system gives them apart: Linux. Nothing on macOS, where ps
# gives only the line p_procs has, an argument with a space in it reading as two.
p_argv() { p_darwin || cat "/proc/$1/cmdline" 2>/dev/null; } # <pid>

# The folder <pid> runs in.
p_cwd() { # <pid>
  if p_darwin; then lsof -a -p "$1" -d cwd -Fn 2>/dev/null | sed -n 's/^n//p'
  else readlink "/proc/$1/cwd" 2>/dev/null; fi
}

# What <name> was in <pid>'s environment when it started (nothing when it was not set). Fails when the environment
# cannot be read: the process is gone, or another user's.
p_env() { # <pid> <name>
  local s
  if p_darwin; then
    s=$(ps -E -ww -o command= -p "$1" 2>/dev/null) && [ -n "$s" ] || return 1
    printf '%s\n' "$s" | sed -n "s/.* $2=//p" | sed 's/ [A-Za-z_][A-Za-z0-9_]*=.*//'
  else
    [ -r "/proc/$1/environ" ] || return 1
    tr '\0' '\n' < "/proc/$1/environ" 2>/dev/null | sed -n "s/^$2=//p" | sed -n 1p
  fi
}
