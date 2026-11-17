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
  [ "$(uname -s)" = Darwin ] || return 0
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
  if [ "$(uname -s)" = Darwin ]; then
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
  if [ "$(uname -s)" = Darwin ]; then sysctl -n vm.loadavg 2>/dev/null | awk '{print $2}'
  else cut -d' ' -f1 /proc/loadavg 2>/dev/null; fi
}

# "<used KiB> <total KiB>"; used is what is not available (macOS: free, inactive and speculative pages are available).
p_mem() {
  if [ "$(uname -s)" = Darwin ]; then
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

# <date> (as GNU date -d reads it: "6 days ago", "2026-11-10") in <format>.
p_date() { date -d "$1" "$2"; } # <date> <+format>

# True when <file> changed in the last <seconds>.
p_newer() { [ -n "$(find "$1" -newermt "@$(($(date +%s) - $2))" 2>/dev/null)" ]; } # <file> <seconds>

# When <pid> started, as ps says it: with the pid, it names one process, so a pid used again is not taken for it.
# watch.py asks ps the same way; the two must match.
p_started() { local s; s=$(LC_ALL=C ps -o lstart= -p "$1" 2>/dev/null) || return 1; s=${s#"${s%%[![:space:]]*}"}; printf '%s\n' "${s%"${s##*[![:space:]]}"}"; } # <pid>

# True when <pid> runs and started at <started> (p_started's answer when it was recorded). A zombie, ended but not yet
# reaped by its parent, keeps its start time but does not run.
p_alive() { [ -n "$2" ] && [ "$(p_started "$1")" = "$2" ] && [[ $(ps -o stat= -p "$1" 2>/dev/null) != *Z* ]]; } # <pid> <started>

# Runs <command> as the leader of a session of its own (no controlling terminal, a process group of its own) and
# exits as it does: setsid on Linux; macOS has no setsid command, so perl's POSIX::setsid there.
p_setsid() { # <command> [args]
  if [ "$(uname -s)" = Darwin ]; then perl -MPOSIX -e 'POSIX::setsid(); exec @ARGV or die "$ARGV[0]: $!\n"' "$@"; else setsid -w "$@"; fi
}

# Every process, one line each: "<pid> <its parent's pid> <its command line>".
p_procs() { ps -A -ww -o pid=,ppid=,args= 2>/dev/null; }

# <pid>'s arguments, each one ended by a NUL byte, where the system gives them apart: Linux. Nothing on macOS, where ps
# gives only the line p_procs has, an argument with a space in it reading as two.
p_argv() { [ "$(uname -s)" = Darwin ] || cat "/proc/$1/cmdline" 2>/dev/null; } # <pid>

# The folder <pid> runs in.
p_cwd() { # <pid>
  if [ "$(uname -s)" = Darwin ]; then lsof -a -p "$1" -d cwd -Fn 2>/dev/null | sed -n 's/^n//p'
  else readlink "/proc/$1/cwd" 2>/dev/null; fi
}

# What <name> was in <pid>'s environment when it started (nothing when it was not set). Fails when the environment
# cannot be read: the process is gone, or another user's.
p_env() { # <pid> <name>
  local s
  if [ "$(uname -s)" = Darwin ]; then
    s=$(ps -E -ww -o command= -p "$1" 2>/dev/null) && [ -n "$s" ] || return 1
    printf '%s\n' "$s" | sed -n "s/.* $2=//p" | sed 's/ [A-Za-z_][A-Za-z0-9_]*=.*//'
  else
    [ -r "/proc/$1/environ" ] || return 1
    tr '\0' '\n' < "/proc/$1/environ" 2>/dev/null | sed -n "s/^$2=//p" | sed -n 1p
  fi
}
