#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 60
# Engine cases: the requirements setup installs (lib/requires.sh), each at its minimum version, with stub installers.
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"
# The engine folder, as lib.sh sets it: named here too, so the release closure (tools/closure.sh) follows this file's paths.
SRC=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)

# A machine of stubs, $R, on no PATH of this host's: <os> (Darwin or Linux) is what uname says. $R/os is the system's
# folder, first on PATH, with every requirement at its minimum (each stub prints its version line, takes python3's
# venv import and has openssl's -addext), this host's sed, dirname, rm, cat, env, true and chmod, and a uid of 1000. On Darwin,
# $R is Homebrew's prefix: brew in $R/bin (last on PATH; p_path puts it first) installs <formula> as a stub in $R/bin
# printing the version line in $R/brew-<formula>, and the GNU tools are in its gnubin folders. On Linux, apt-get and
# sudo are in $R/os: apt-get installs each package <p> named by a file $R/apt-<p> (its program and version line) into
# $R/os, and fails while $R/aptfail is there; sudo -n runs the command unless $R/sudopw is there, and -k -S runs it
# when the line it reads is $R/sudopw's (kept in $R/sudo-got). brew and apt-get log their arguments in $R/log.
reqhost() { # <os>
  R=$T/$CASE/host; local t
  mkdir -p "$R/os" "$R/bin" || fail "the stub machine was not made"
  for t in sed dirname rm cat env true chmod; do ln -s "$(type -P "$t")" "$R/os/$t"; done
  printf '#!/bin/sh\necho %s\n' "$1" > "$R/os/uname"; printf '#!/bin/sh\necho 1000\n' > "$R/os/id"; chmod +x "$R/os/uname" "$R/os/id"
  stub "$R/os/bash" 'GNU bash, version 5.1.0(1)-release'; stub "$R/os/jq" jq-1.8.0; stub "$R/os/git" 'git version 2.40.0'
  stub "$R/os/flock" 'flock 2.39'; stub "$R/os/python3" 'Python 3.12.0'; stub "$R/os/gh" 'gh version 2.80.0'
  stub "$R/os/claude" '2.1.322 (Claude Code)'; stub "$R/os/codex" 'codex-cli 0.50.0'; stub "$R/os/openssl" 'OpenSSL 3.0.0'
  if [ "$1" = Darwin ]; then
    for t in coreutils:timeout findutils:find gnu-sed:sed grep:grep; do
      mkdir -p "$R/opt/${t%%:*}/libexec/gnubin" && ln -s "$(type -P "${t#*:}")" "$R/opt/${t%%:*}/libexec/gnubin/${t#*:}"
    done
    cat > "$R/bin/brew" <<EOF
#!/bin/sh
echo "\$*" >> "$R/log"
[ "\$1" = install ] && [ -e "$R/brew-\$2" ] || exit 1
printf '#!/bin/sh\\ncase "\$1" in --version|version) echo "%s" ;; esac\\n' "\$(cat "$R/brew-\$2")" > "$R/bin/\$2" && chmod +x "$R/bin/\$2"
EOF
    chmod +x "$R/bin/brew"
  else
    cat > "$R/os/apt-get" <<EOF
#!/bin/sh
echo "\$*" >> "$R/log"
[ ! -e "$R/aptfail" ] || exit 100
[ "\$1" = install ] || exit 0
for p; do [ ! -e "$R/apt-\$p" ] || { read -r n v < "$R/apt-\$p"; printf '#!/bin/sh\\necho "%s"\\n' "\$v" > "$R/os/\$n"; chmod +x "$R/os/\$n"; }; done
EOF
    cat > "$R/os/sudo" <<EOF
#!/bin/sh
if [ "\$1" = -n ]; then [ ! -e "$R/sudopw" ] || exit 1; shift; exec "\$@"; fi
[ "\$1 \$2 \$3" = "-k -S -p" ] || exit 1; shift 4
read -r pw; [ "\$pw" = "\$(cat "$R/sudopw")" ] || exit 1; echo "\$pw" > "$R/sudo-got"; exec "\$@"
EOF
    chmod +x "$R/os/apt-get" "$R/os/sudo"
  fi
  PATH0=$R/os:$R/bin
}
stub() { printf '#!/bin/sh\ncase "$1" in --version|version) echo "%s" ;; req) echo " -addext val" ;; esac\nexit 0\n' "$2" > "$1" && chmod +x "$1"; } # <file> <version line>
# requires.sh <args> on the stub machine; its output in OUT, its exit in RC.
req() { OUT=$(PATH=$PATH0 "$BASH" "$SRC/lib/requires.sh" "$@" 2>&1); RC=$?; }

# Bug caught (#110): a Mac had Apple's jq 1.7.1 (/usr/bin/jq), which rejects the engine's code, and setup neither
# installed jq 1.8 nor said it was missing, so the Board was left with no data. Here Apple's jq is first on PATH and a
# jq 1.8.1 is further on: the one first on PATH is read, found too old, and Homebrew's is installed, which the engine's
# PATH then puts first, and only it.
t_requiresold() {
  reqhost Darwin; stub "$R/os/jq" jq-1.7.1-apple; mkdir -p "$R/later" && stub "$R/later/jq" jq-1.8.1
  PATH0=$R/os:$R/later:$R/bin; echo jq-1.8.1 > "$R/brew-jq"
  req install; [ $RC = 0 ] || fail "setup's install failed: $OUT"
  grep -qxF "conveyor: missing: jq 1.8 or newer (found 1.7.1 at $R/os/jq)" <<<"$OUT" || fail "jq 1.7.1 first on PATH was not found too old: $OUT"
  [ "$(cat "$R/log")" = 'install jq' ] || fail "Homebrew did not install jq, and it alone: $(cat "$R/log")"
  grep -qxF "conveyor: installed jq 1.8.1, at $R/bin/jq" <<<"$OUT" || fail "the jq installed is not the one first on the engine's PATH: $OUT"
}

# Bug caught (#110): the install's PATH ended with it, so setup's `gh auth login` and `codex login` then ran on the
# caller's PATH and did not find the CLIs Homebrew had put in its own folder. `run` runs a command on the PATH the
# checks read: Homebrew's jq here, not the older one first on the caller's PATH.
t_requiresrun() {
  reqhost Darwin; stub "$R/os/jq" jq-1.7.1-apple; stub "$R/bin/jq" jq-1.8.1
  req run jq --version; [ $RC = 0 ] && [ "$OUT" = jq-1.8.1 ] || fail "run did not use Homebrew's jq first on PATH ($RC): $OUT"
}

# Bug: a requirement not on the machine at all was left for the owner to install. Here gh is missing on Linux:
# apt-get installs it, through sudo with no password asked, and it is checked again.
t_requiresmissing() {
  reqhost Linux; rm "$R/os/gh"; echo 'gh gh version 2.81.0' > "$R/apt-gh"
  req install; [ $RC = 0 ] || fail "setup's install failed: $OUT"
  [ "$(cat "$R/log")" = $'update -q\ninstall -y -q gh' ] || fail "apt-get did not install gh, and it alone: $(cat "$R/log")"
  grep -qxF "conveyor: installed gh 2.81.0, at $R/os/gh" <<<"$OUT" || fail "the gh installed was not named: $OUT"
}

# Bug: an install that failed, or one that left the requirement too old (a distribution's jq below 1.8), let setup go
# on. Each fails it, naming the requirement and why.
t_requiresfail() {
  reqhost Linux; rm "$R/os/gh"; touch "$R/aptfail"
  req install; [ $RC = 1 ] || fail "a failed install did not fail setup ($RC): $OUT"
  grep -qF 'conveyor: the install of gh, the GitHub CLI failed: env DEBIAN_FRONTEND=noninteractive' <<<"$OUT" || fail "the failed install did not name gh: $OUT"
  rm "$R/aptfail" "$R/log"; stub "$R/os/gh" 'gh version 2.80.0'; stub "$R/os/jq" jq-1.7.1; echo 'jq jq-1.7.1' > "$R/apt-jq"
  req install; [ $RC = 1 ] || fail "an install that left jq 1.7.1 did not fail setup ($RC): $OUT"
  grep -qxF "conveyor: jq 1.8 or newer is still missing after its install: found 1.7.1 at $R/os/jq" <<<"$OUT" || fail "jq left too old was not named: $OUT"
}

# Bug: setup stopped with a list of sudo commands for the owner to run. With sudo asking for a password, it exits 3
# before installing anything (setup then asks the user through Claude Code); the password is given in a file, which is
# deleted, and is refused when sudo refuses it; the right one installs.
t_requiressudo() {
  reqhost Linux; rm "$R/os/jq"; echo 'jq jq-1.8.1' > "$R/apt-jq"; echo right > "$R/sudopw"
  req install; [ $RC = 3 ] && grep -qF "conveyor: installing jq needs this user's sudo password" <<<"$OUT" && [ ! -e "$R/log" ] \
    || fail "sudo asking for a password did not stop setup, before any install, with exit 3 ($RC): $OUT"
  echo wrong > "$T/$CASE/pw"; req install --password-file "$T/$CASE/pw"
  [ $RC = 3 ] && grep -qF 'conveyor: sudo refused the password given' <<<"$OUT" && [ ! -e "$T/$CASE/pw" ] && [ ! -e "$R/log" ] \
    || fail "a wrong password was not refused, or its file was kept ($RC): $OUT"
  echo right > "$T/$CASE/pw"; req install --password-file "$T/$CASE/pw"
  [ $RC = 0 ] && [ ! -e "$T/$CASE/pw" ] && [ "$(cat "$R/sudo-got")" = right ] && grep -qx 'install -y -q jq' "$R/log" \
    || fail "the right password did not install jq through sudo, or its file was kept ($RC): $OUT"
}
