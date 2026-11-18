#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 300
# Engine cases: doctor's checks of the pin, the Board's virtualenv, gh, the host file, the pack and the tools. Its own
# file, to keep setup.test.sh under the 600 lines a case file may have. The helpers (doctordone, sample, without,
# uninstalled) are setup.test.sh's.
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"

# A pin that is not a full commit id can climb out of the versions folder: doctor never offers a folder it names for
# removal, here one that exists outside it.
t_doctorclimb() {
  local X out; doctordone
  mkdir -p "$T/$CASE/outside"; cp "$S/.conveyor/project.json" "$T/$CASE/pin"
  jq --arg c "../../../../../../../../../../../../../..$T/$CASE/outside" '.plugin.commit = $c' "$T/$CASE/pin" > "$S/.conveyor/project.json"
  out=$(cd "$S" && bash "$X" doctor 2>&1); mv "$T/$CASE/pin" "$S/.conveyor/project.json"
  [ -d "$T/$CASE/outside" ] && ! grep -q 'rm -\|remove it' <<<"$out" || fail "doctor offered to remove a folder outside the versions folder: $out"
}
# Bug caught (#17): on Debian or Ubuntu with no python3-venv, setup cannot make the Board's virtualenv, and doctor's
# fix, "run setup", failed the same way: with no virtualenv, the fix names python3-venv.
t_doctornovenv() {
  local X out; doctordone; rm -r "$XDG_DATA_HOME/conveyor/board-venv"
  out=$(cd "$S" && bash "$X" doctor 2>&1) && fail "doctor passed with no Board virtualenv: $out"
  grep -qxF "missing: the Board's virtualenv $XDG_DATA_HOME/conveyor/board-venv; fix: run /conveyor-belt:setup, which makes it (on Debian or Ubuntu, first install python3-venv: sudo apt install python3-venv)" <<<"$out" \
    && ! grep -q 'for the Board, in its virtualenv' <<<"$out" || fail "doctor's fix for a missing Board virtualenv does not name python3-venv: $out"
}
# Bug caught (#20): with no python3-venv, python3 -m venv makes bin/python3 and then fails in ensurepip; doctor took
# that virtualenv for made and said only to run setup again, and setup's rerun did not make it again.
t_doctorvenvnopip() {
  local X out py; doctordone; py=$(type -P python3) || fail "no python3 on PATH"
  echo pip > "$G/nopkg" # the virtualenv's python3 has no pip
  # python3 as on Debian with no python3-venv: venv records its arguments and fails.
  printf '#!/usr/bin/env bash\n[ "$1 $2" != "-m venv" ] || { echo "$*" >> "%s/venv"; exit 1; }\nexec "%s" "$@"\n' "$G" "$py" > "$G/python3" && chmod +x "$G/python3"
  ! (cd "$S" && bash "$X" setup --fast-lane no --research-lane no --owner Dana --product src/ --test t --survey no --pin >/dev/null 2>&1) || fail "setup passed with a virtualenv with no pip"
  grep -qxF -- "-m venv --clear $XDG_DATA_HOME/conveyor/board-venv" "$G/venv" || fail "setup did not make again a virtualenv with no pip: $(cat "$G/venv" 2>&1)"
  out=$(cd "$S" && bash "$X" doctor 2>&1) && fail "doctor passed with a virtualenv with no pip: $out"
  grep -qxF "missing: the Board's virtualenv $XDG_DATA_HOME/conveyor/board-venv; fix: run /conveyor-belt:setup, which makes it (on Debian or Ubuntu, first install python3-venv: sudo apt install python3-venv)" <<<"$out" \
    && ! grep -q 'for the Board, in its virtualenv' <<<"$out" || fail "doctor's fix for a virtualenv with no pip does not name python3-venv: $out"
}
# A snapshot folder that says gh is signed in is no word on this machine's gh (signed out here).
# Its doctor run also has a Board that answers but fails the certificate check (curl exit 35, as macOS's curl gives
# for a LibreSSL certificate with explicit curve parameters). Bug caught (#183): doctor said it was not running.
t_doctorsnap() {
  local X out; doctordone; : > "$G/out"
  mkdir -p "$T/$CASE/snap" "$T/$CASE/badcert"; echo true > "$T/$CASE/snap/gh"; printf '#!/bin/sh\nexit 35\n' > "$T/$CASE/badcert/curl"; chmod +x "$T/$CASE/badcert/curl"
  out=$(cd "$S" && CONVEYOR_GITHUB=$T/$CASE/snap PATH=$T/$CASE/badcert:$PATH bash "$X" doctor 2>&1)
  grep -qx 'missing: gh signed in; fix: run /conveyor-belt:setup, which starts gh auth login' <<<"$out" || fail "doctor took a snapshot's word that gh is signed in: $out"
  grep -qxF "warning: something answers on https://localhost:8790/ but fails the check of the Board's certificate (curl exit 35); fix: run conveyor.sh board in the project's checkout, which replaces a certificate that does not name its curve and restarts the Board" <<<"$out" \
    || fail "doctor did not name the Board's certificate problem and its fix: $out"
}
# A private repo needs no terms file; with no host file, that is named; with no pack, setup is the fix.
t_doctorprivate() {
  local X out; doctordone
  jq '.privacy.mode = "private"' "$S/.conveyor/project.json" > "$T/$CASE/p" && mv "$T/$CASE/p" "$S/.conveyor/project.json"
  rm "$XDG_CONFIG_HOME/conveyor/host.json"; out=$(cd "$S" && bash "$X" doctor 2>&1)
  ! grep -q 'terms file' <<<"$out" && grep -q "^missing: the host file $XDG_CONFIG_HOME/conveyor/host.json; fix: run /conveyor-belt:setup" <<<"$out" || fail "doctor, private and no host file: $out"
}
t_doctorhostbad() {
  local X out; doctordone; uninstalled
  jq '.privacy.mode = "private"' "$S/.conveyor/project.json" > "$T/$CASE/p" && mv "$T/$CASE/p" "$S/.conveyor/project.json"
  echo '[' > "$XDG_CONFIG_HOME/conveyor/host.json"; out=$(cd "$S" && bash "$X" doctor 2>&1)
  grep -q '^missing: a readable host file .*; fix: make it a JSON object' <<<"$out" && grep -q '^missing: the install' <<<"$out" || fail "doctor stopped at, or passed, a host file that does not read: $out"
}
t_doctornopack() {
  local X out; doctordone
  rm -r "$S/.conveyor"; out=$(cd "$S" && bash "$X" doctor 2>&1)
  grep -q "^missing: the pack $S/.conveyor/project.json; fix: run /conveyor-belt:setup" <<<"$out" || fail "doctor with no pack: $out"
}
# jq, git and gh not on PATH: each is named, and the project's checks are named as not checked; so is a valid host file.
t_doctortools() {
  local X out; doctordone; rm -r "$S/.conveyor"
  echo '{}' > "$XDG_CONFIG_HOME/conveyor/host.json"; out=$(cd "$S" && CONVEYOR_MAIN=$S PATH=$(without jq git gh) bash "$X" doctor 2>&1) && fail "doctor passed with no jq, git or gh: $out"
  grep -q '^missing: jq 1.8 or newer (none on PATH); fix: run /conveyor-belt:setup, which installs it' <<<"$out" \
    && grep -q '^missing: git (none on PATH); fix: run /conveyor-belt:setup' <<<"$out" && grep -q '^missing: gh, the GitHub CLI (none on PATH); fix: run /conveyor-belt:setup' <<<"$out" \
    && grep -q '^not checked: the pack' <<<"$out" && grep -q '^not checked: the host file' <<<"$out" && ! grep -q 'host file.*fix' <<<"$out" \
    || fail "doctor with no jq, git or gh: $out"
}
# Bug caught (#110): a Mac ran Apple's jq 1.7.1, first on PATH, which rejects the engine's code, and doctor said only
# "ok: jq". It names jq below its minimum, with the version found and where. The stub answers --version as Apple's
# does and passes the rest to this host's jq, so the engine's own jq calls still run.
t_doctorold() {
  local X out d=$T/$CASE/oldjq; doctordone
  mkdir -p "$d" && printf '#!/bin/sh\n[ "$1" != --version ] || { echo jq-1.7.1-apple; exit 0; }\nexec %s "$@"\n' "$(type -P jq)" > "$d/jq" && chmod +x "$d/jq" || fail "the jq stub was not made"
  out=$(cd "$S" && PATH=$d:$PATH bash "$X" doctor 2>&1) && fail "doctor passed with jq 1.7.1 first on PATH: $out"
  grep -qxF "missing: jq 1.8 or newer (found 1.7.1 at $d/jq); fix: run /conveyor-belt:setup, which installs it" <<<"$out" \
    || fail "doctor did not name jq 1.7.1, and where it is: $out"
}
