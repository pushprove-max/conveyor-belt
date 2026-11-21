#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Pins (#1084) that a guard hook test made to fail names the command it gave the hook (lib/said.sh), so its failure
# log can be read with no run again: a guard test that failed under load printed only `expected true, got false`.
# Two guard tests, one for each way lib/said.sh notes the input, each run as a copy beside a stub hook that allows
# every call, so the check named fails: bash-guardrails.test.sh ("bare node --test blocks", part 1), whose payload
# builder notes the input it gives the hook it runs itself (said_in), and git-safety.test.sh ("a bare force push
# blocks", part 1), whose `bash "$HOOK"` the bash function of lib/said.sh notes. It runs those real test files: a
# check of lib/said.sh alone cannot show that a guard test's own FAIL lines carry the input. The two run side by side.
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
# fixture <name> <test file> <hook file>: the copy of the test file and lib/, and the stub hook, under $T/<name>.
fixture() {
  mkdir -p "$T/$1/hooks/__tests__/lib" "$T/$1/tmp" && cp "$HERE/$2" "$T/$1/hooks/__tests__/" \
    && cp "$HERE/lib/said.sh" "$HERE/lib/case-filter.sh" "$T/$1/hooks/__tests__/lib/" \
    && printf '%s\n' '#!/usr/bin/env bash' 'cat > /dev/null; exit 0' > "$T/$1/hooks/$3" && chmod +x "$T/$1/hooks/$3"
}
fixture gr bash-guardrails.test.sh bash-guardrails.sh && fixture gs git-safety.test.sh git-safety.sh \
  || { echo "FAIL the fixture could not be made"; exit 1; }
( TMPDIR=$T/gr/tmp GUARDRAILS_TEST_PART=1 CONVEYOR_SHELL_TEST_CASE='bare node --test blocks' \
  bash "$T/gr/hooks/__tests__/bash-guardrails.test.sh" > "$T/gr.out" 2>&1; echo $? > "$T/gr.rc" ) &
( TMPDIR=$T/gs/tmp GIT_SAFETY_TEST_PART=1 bash "$T/gs/hooks/__tests__/git-safety.test.sh" > "$T/gs.out" 2>&1; echo $? > "$T/gs.rc" ) &
wait
FAIL=0
# check <name> <test file> <the FAIL line it must print>
check() {
  local out; out=$(cat "$T/$1.out")
  [ "$(cat "$T/$1.rc")" != 0 ] || { echo "FAIL the copy of $2 passed against a hook that allows every call: $out"; FAIL=1; }
  grep -qxF "$3" <<<"$out" || { echo "FAIL the failed assertion of $2 does not name the command it gave the hook: no line $3 in $(grep '^FAIL' <<<"$out" | head -c 2000)"; FAIL=1; }
  [ -z "$(ls -A "$T/$1/tmp")" ] || { echo "FAIL $2 left the note of the hook's input behind: $(ls -A "$T/$1/tmp")"; FAIL=1; }
}
check gr bash-guardrails.test.sh "FAIL bare node --test blocks (expected 2, got 0) [the hook's last command \"node --test src/x.test.ts\"]"
check gs git-safety.test.sh "FAIL a bare force push blocks (expected 2, got 0) [the hook's last command \"git push --force origin main\"]"
# A hook copied outside a hooks/ folder ("a missing strip-quoted.sh blocks") is noted too: when only hooks/ calls
# were, this check named the command of the check before it, git pu''sh --force.
check gs git-safety.test.sh "FAIL a missing strip-quoted.sh blocks (expected 2, got 0) [the hook's last command \"git push --force\"]"
# A call's words after the script are its input too (adversarial-review-gate.sh --hash-range <a> <b>), and a later
# call with none and a command clears them. Run on lib/said.sh itself: the words are what the check must name.
printf '%s\n' 'cat > /dev/null' > "$T/x.sh"
got=$( . "$HERE/lib/said.sh"; bash "$T/x.sh" --hash-range 'no/such ref' HEAD < /dev/null; said
  echo; bash "$T/x.sh" <<<'{"tool_input":{"command":"ls"}}'; said )
want=$(printf '%s\n' " [the hook's last call \"--hash-range no/such\\\\ ref HEAD\"]" " [the hook's last command \"ls\"]")
[ "$got" = "$want" ] || { echo "FAIL a hook call's words are not named, or stay named after the next call: $got"; FAIL=1; }
[ "$FAIL" = 1 ] || echo "ok   a guard hook test made to fail names the command it checked"
exit $FAIL
