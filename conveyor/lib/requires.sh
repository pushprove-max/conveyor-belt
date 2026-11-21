#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# What Conveyor needs on this machine (docs/setup.md, Requirements), each at its minimum version, checked and installed.
#   requires.sh check: one `ok:` or `missing:` line for each requirement; exit 1 when one is missing.
#   requires.sh install [--password-file <file>]: installs each requirement that is missing or too old, with Homebrew
#     on macOS and apt-get or dnf on Linux (npm for the Claude Code and Codex CLIs), then checks it again. Exit 0 when
#     every one is there; 1, naming the requirement and the reason, when an install fails or leaves it missing; 3 when
#     a Linux install needs sudo and sudo asks for a password: /conveyor-belt:setup asks the user for it and runs this
#     again with it in <file>, which is read and deleted before anything else is done.
#   requires.sh run <command> [args]: runs <command> on the PATH the checks read (Homebrew's folders first on macOS), so
#     a CLI the install put there (gh, codex) is found though the caller's PATH does not have it.
# Each check reads the program the engine and the Board run: the first on PATH once p_path (lib/portable.sh) has put
# Homebrew's folders first on macOS, as conveyor.sh does. A newer copy further on PATH, or off it, does not count.
# /conveyor-belt:setup runs this before conveyor.sh, which needs bash 5.1, so it must run in macOS's bash 3.2: no
# associative arrays, no mapfile, no empty arrays under set -u. Its functions are named req_*; doctor (lib/setup.sh)
# sources this file for req_report and req_guards.
REQ_HERE=.; [[ ${BASH_SOURCE[0]} != */* ]] || REQ_HERE=${BASH_SOURCE[0]%/*}
. "$REQ_HERE/portable.sh" || exit 1

# The requirements, in the order they are installed. The GNU tools are macOS's only.
req_names() {
  echo bash jq git flock python3 gh claude codex openssl
  [ "$(uname -s)" != Darwin ] || echo coreutils findutils gnu-sed grep
}
# What a requirement is, as its lines name it.
req_desc() {
  case $1 in
    bash) echo "bash 5.1 or newer" ;; jq) echo "jq 1.8 or newer" ;; python3) echo "Python 3 with venv" ;;
    gh) echo "gh, the GitHub CLI" ;; claude) echo "the Claude Code CLI (claude) 2.1.322 or newer" ;;
    codex) echo "the Codex CLI (codex)" ;; openssl) echo "openssl, with -addext" ;;
    coreutils|findutils|gnu-sed|grep) echo "Homebrew's $1" ;; *) echo "$1" ;;
  esac
}
req_min() { case $1 in bash) echo 5.1 ;; jq) echo 1.8 ;; claude) echo 2.1.322 ;; esac; }
# 0 when the dotted version <a> is <b> or newer.
req_vge() { # <a> <b>
  local IFS=. a b i=0
  read -ra a <<<"$1"; read -ra b <<<"$2"
  while [ $i -lt ${#b[@]} ]; do
    [ "${a[$i]:-0}" -gt "${b[$i]}" ] && return 0
    [ "${a[$i]:-0}" -lt "${b[$i]}" ] && return 1
    i=$((i + 1))
  done
}
# A requirement's state: REQ_AT (the file found, or none), REQ_VER (its version, when it says one) and REQ_WHY (empty
# when it is there at its minimum; else why not).
req_state() { # <name>
  local m p
  REQ_AT=''; REQ_VER=''; REQ_WHY=''
  case $1 in
    coreutils|findutils|gnu-sed|grep)
      case $1 in coreutils) p='timeout' ;; findutils) p='find' ;; *) p=${1#gnu-} ;; esac
      p=$(p_brewprefix)/opt/$1/libexec/gnubin/$p
      if [ -x "$p" ]; then REQ_AT=$p; else REQ_WHY="none at $p"; fi
      return 0 ;;
  esac
  # type -P: the file, never the engine's own function of that name (git).
  p=$(type -P "$1") || { REQ_WHY="none on PATH"; return 0; }
  REQ_AT=$p
  if [ "$1" = openssl ]; then REQ_VER=$("$p" version 2>/dev/null); else REQ_VER=$("$p" --version 2>/dev/null); fi
  REQ_VER=$(printf '%s\n' "$REQ_VER" | sed -n '1s/^[^0-9]*\([0-9][0-9]*\(\.[0-9][0-9]*\)*\).*/\1/p')
  m=$(req_min "$1")
  if [ -n "$m" ] && { [ -z "$REQ_VER" ] || ! req_vge "$REQ_VER" "$m"; }; then REQ_WHY="found ${REQ_VER:-no version} at $p"
  elif [ "$1" = python3 ] && ! "$p" -c 'import venv, ensurepip' >/dev/null 2>&1; then REQ_WHY="found ${REQ_VER:-no version} at $p, with no venv"
  elif [ "$1" = openssl ]; then case $("$p" req -help 2>&1) in *-addext*) ;; *) REQ_WHY="found ${REQ_VER:-no version} at $p, whose req takes no -addext" ;; esac
  fi
}
# What req_state found, as `<program> <version>, at <file>`.
req_found() { # <name>
  echo "$(case $1 in coreutils|findutils|gnu-sed|grep) req_desc "$1" ;; *) echo "$1" ;; esac)${REQ_VER:+ $REQ_VER}, at $REQ_AT"
}
# One line for each requirement, `ok: <program> <version>, at <file>` or `missing: <what> (<why>); fix: ...`. 1 when
# one is missing.
req_report() {
  local n bad=0
  for n in $(req_names); do
    req_state "$n"
    if [ -z "$REQ_WHY" ]; then echo "ok: $(req_found "$n")"
    else echo "missing: $(req_desc "$n") ($REQ_WHY); fix: run /conveyor-belt:setup, which installs it"; bad=1; fi
  done
  return $bad
}
# A card's guard hooks (card-settings.json) carry "onFailure": "block", so a guard that fails to run blocks the call;
# Claude Code before 2.1.329 ignores the field and lets the call through. One missing: line when the claude found is
# older (none when it is not there: req_report names that); 1 then.
req_guards() {
  req_state claude
  [ -n "$REQ_AT" ] && [ -n "$REQ_VER" ] && ! req_vge "$REQ_VER" 2.1.329 || return 0
  echo "missing: Claude Code 2.1.329 or later for the card guards (found $REQ_VER at $REQ_AT): card guards need 2.1.329 or later, as an older one lets a tool call through when a guard fails to run; fix: run $REQ_AT update"
  return 1
}

# The system's package for a requirement: Homebrew's formula, or apt-get's or dnf's packages; none for the npm ones.
req_pkg() { # brew|apt-get|dnf <name>
  case $2 in
    claude|codex) return 0 ;;
    flock) [ "$1" = brew ] && echo flock || echo util-linux ;;
    python3) case $1 in brew) echo python ;; apt-get) echo python3 python3-venv ;; *) echo python3 ;; esac ;;
    openssl) [ "$1" = brew ] && echo openssl@3 || echo openssl ;;
    *) echo "$2" ;;
  esac
}
# The installer: brew on macOS, else apt-get or dnf; empty when there is none.
req_pm() {
  if [ "$(uname -s)" = Darwin ]; then type -P brew || { [ ! -x "$(p_brewprefix)/bin/brew" ] || echo "$(p_brewprefix)/bin/brew"; }
  else type -P apt-get || type -P dnf; fi
}
# Runs <command> as root on Linux: as it is for root, else through sudo, with the password given when sudo asks for one.
req_root() { # <command>...
  if [ "$(id -u)" = 0 ]; then "$@"
  # -k: sudo reads the password every time, so it never reaches the command's input.
  elif [ -n "${REQ_PW:-}" ]; then printf '%s\n' "$REQ_PW" | sudo -k -S -p '' "$@"
  else sudo -n "$@"; fi
}
# 0 when installing <name> needs root: a Linux system package, or an npm install whose global folder is not writable.
req_needsroot() { # <name>
  local d
  [ "$(uname -s)" != Darwin ] || return 1
  case $1 in
    claude) [ -z "$REQ_AT" ] || return 1 ;; # a Claude Code CLI too old updates itself
  esac
  case $1 in
    claude|codex) type -P npm >/dev/null || return 0
      d=$(npm prefix -g 2>/dev/null) && [ -w "$d" ] && return 1; return 0 ;;
  esac
  return 0
}
# Runs one install command, saying so; on failure says which requirement failed, and why, on stderr.
req_run() { # <name> <command>...
  local n=$1 rc c; shift
  c=$*; c=${c#req_root }
  echo "conveyor: installing $(req_desc "$n"): $c"
  "$@"; rc=$?
  [ $rc = 0 ] && return 0
  echo "conveyor: the install of $(req_desc "$n") failed: $c exited $rc" >&2
  return 1
}
# Installs one requirement with the machine's installer. REQ_AT is what req_state found.
req_install() { # <name>
  local n=$1 pm pkgs
  pm=$(req_pm)
  [ -n "$pm" ] || { echo "conveyor: $(req_desc "$n") could not be installed: no $([ "$(uname -s)" = Darwin ] && echo "Homebrew (brew)" || echo "apt-get or dnf") on this machine" >&2; return 1; }
  case $n in
    claude|codex)
      # A Claude Code CLI there but too old: its own update. Else npm, installed first when it is not there.
      [ "$n" != claude ] || [ -z "$REQ_AT" ] || { req_run "$n" "$REQ_AT" update; return; }
      type -P npm >/dev/null || req_syspkg npm || return 1
      pkgs=$([ "$n" = claude ] && echo @anthropic-ai/claude-code || echo @openai/codex)
      if req_needsroot "$n"; then req_run "$n" req_root npm install -g "$pkgs"; else req_run "$n" npm install -g "$pkgs"; fi ;;
    *) req_syspkg "$n" ;;
  esac
}
# Installs the system package of <name> (npm: node's).
REQ_UPDATED=''
req_syspkg() { # <name>
  local pm pkgs
  pm=$(req_pm)
  case $1 in npm) [ "${pm##*/}" = brew ] && pkgs=node || pkgs=npm ;; *) pkgs=$(req_pkg "${pm##*/}" "$1") ;; esac
  case ${pm##*/} in
    brew) req_run "$1" "$pm" install $pkgs ;;
    apt-get)
      [ -n "$REQ_UPDATED" ] || { req_run "$1" req_root env DEBIAN_FRONTEND=noninteractive "$pm" update -q || return 1; REQ_UPDATED=1; }
      req_run "$1" req_root env DEBIAN_FRONTEND=noninteractive "$pm" install -y -q $pkgs ;;
    *) req_run "$1" req_root "$pm" install -y $pkgs ;;
  esac
}

req_main() {
  local n todo='' root='' f
  REQ_PW=''
  case ${1-} in
    check) [ $# = 1 ] || set -- x ;;
    run) [ $# -ge 2 ] || set -- x ;;
    install) [ $# = 1 ] || { [ $# = 3 ] && [ "$2" = --password-file ] && [ -n "$3" ]; } || set -- x ;;
    *) set -- x ;;
  esac
  [ "$1" != x ] || { echo "usage: requires.sh check | install [--password-file <file>] | run <command> [args]" >&2; return 2; }
  [ "$1" != run ] || { shift; p_path; exec "$@"; }
  # The password is read and its file deleted first, whatever happens next.
  if [ $# = 3 ]; then f=$3; IFS= read -r REQ_PW < "$f"; rm -f "$f"; fi
  p_path
  [ "$1" = install ] || { req_report; return; }
  for n in $(req_names); do
    req_state "$n"
    [ -n "$REQ_WHY" ] || continue
    echo "conveyor: missing: $(req_desc "$n") ($REQ_WHY)"
    todo="$todo $n"; ! req_needsroot "$n" || root=1
  done
  [ -n "$todo" ] || { echo "conveyor: every requirement is installed"; return 0; }
  # sudo that asks for a password, and none given: setup asks the user for it (exit 3) before anything is installed.
  if [ -n "$root" ] && [ "$(id -u)" != 0 ]; then
    type -P sudo >/dev/null || { echo "conveyor: installing$todo needs root, and this machine has no sudo" >&2; return 1; }
    if [ -n "$REQ_PW" ]; then
      printf '%s\n' "$REQ_PW" | sudo -k -S -p '' true >/dev/null 2>&1 \
        || { echo "conveyor: sudo refused the password given; installing$todo needs this user's sudo password" >&2; return 3; }
    elif ! sudo -n true >/dev/null 2>&1; then
      echo "conveyor: installing$todo needs this user's sudo password" >&2; return 3
    fi
  fi
  for n in $todo; do
    req_state "$n"; req_install "$n" || return 1
    # PATH again: a folder the install made (Homebrew's keg-only openssl@3) goes first, as the engine puts it.
    p_path; hash -r; req_state "$n"
    [ -z "$REQ_WHY" ] || { echo "conveyor: $(req_desc "$n") is still missing after its install: $REQ_WHY" >&2; return 1; }
    echo "conveyor: installed $(req_found "$n")"
  done
}
[ "${BASH_SOURCE[0]}" != "$0" ] || { req_main "$@"; exit $?; }
