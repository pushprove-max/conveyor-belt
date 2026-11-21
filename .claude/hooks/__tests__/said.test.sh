#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Pins (#1084) that a guard hook test made to fail names the command it gave the hook (lib/said.sh), so its failure
# log can be read with no run again: a guard test that failed under load printed only `expected true, got false`.
# Guard tests of each way a test gives lib/said.sh the input, each run as a copy beside a stub hook that allows every
# call, so the check named fails: bash-guardrails.test.sh ("bare node --test blocks", part 1), whose payload builder
# notes the input it gives the hook it runs itself (said_in); git-safety.test.sh ("a bare force push blocks", part 1),
# whose `bash "$HOOK"` the bash function of lib/said.sh notes; suite-rerun-guard.test.sh (#1132), whose hook was run
# as "$HOOK" and is now `bash "$HOOK"` in a pipe; new-test-file-guard.test.sh (#1132), whose hook runs under timeout,
# out of that function's sight, so each call notes its payload; and worker-ask-guard.test.sh (#1132), whose check is
# the one lib/rulings-fixture.sh gives every decision-log test. It runs those real test files: a check of lib/said.sh
# alone cannot show that a guard test's own FAIL lines carry the input. The copies run side by side.
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
# fixture <name> <test file> <hook file>...: under $T/<name>, laid out as the checkout is, the copy of the test file
# and lib/, a stub of each hook, and conveyor/lib/portable.sh, which new-test-file-guard.test.sh reads. The copy is
# named copy-of-<test file>, a path no tracked test file has, so the card's test step does not take this file for a
# meta-runner of the real test files (none of them reads its own name).
fixture() {
  local d=$T/$1/.claude/hooks h
  mkdir -p "$d/__tests__/lib" "$T/$1/.claude/scripts" "$T/$1/conveyor/lib" "$T/$1/tmp" && cp "$HERE/$2" "$d/__tests__/copy-of-$2" \
    && cp "$HERE"/lib/*.sh "$d/__tests__/lib/" && cp "$HERE/../../../conveyor/lib/portable.sh" "$T/$1/conveyor/lib/" || return
  for h in "${@:3}"; do printf '%s\n' '#!/usr/bin/env bash' 'cat > /dev/null; exit 0' > "$d/$h" && chmod +x "$d/$h" || return; done
}
# copy <name> <test file> [<NAME=value>...]: runs the copy in the background, its output in $T/<name>.out, its exit in
# $T/<name>.rc.
copy() { ( env TMPDIR="$T/$1/tmp" "${@:3}" bash "$T/$1/.claude/hooks/__tests__/copy-of-$2" > "$T/$1.out" 2>&1; echo $? > "$T/$1.rc" ) & }
fixture gr bash-guardrails.test.sh bash-guardrails.sh && fixture gs git-safety.test.sh git-safety.sh \
  && fixture sr suite-rerun-guard.test.sh suite-rerun-guard.sh \
  && fixture nt new-test-file-guard.test.sh new-test-file-guard.sh codex-dispatch.sh \
  && fixture wa worker-ask-guard.test.sh worker-ask-guard.sh || { echo "FAIL the fixture could not be made"; exit 1; }
copy gr bash-guardrails.test.sh GUARDRAILS_TEST_PART=1 'CONVEYOR_SHELL_TEST_CASE=bare node --test blocks'
copy gs git-safety.test.sh GIT_SAFETY_TEST_PART=1
copy sr suite-rerun-guard.test.sh
copy nt new-test-file-guard.test.sh
copy wa worker-ask-guard.test.sh
wait
FAIL=0
# check <name> <test file> <the FAIL line it must print>
check() {
  local out; out=$(cat "$T/$1.out")
  [ "$(cat "$T/$1.rc")" != 0 ] || { echo "FAIL the copy of $2 passed against a hook that allows every call: $out"; FAIL=1; }
  grep -qxF "$3" <<<"$out" || { echo "FAIL the failed assertion of $2 does not name the input it gave the hook: no line $3 in $(grep '^FAIL' <<<"$out" | head -c 2000)"; FAIL=1; }
  [ -z "$(ls -A "$T/$1/tmp")" ] || { echo "FAIL $2 left the note of the hook's input behind: $(ls -A "$T/$1/tmp")"; FAIL=1; }
}
check gr bash-guardrails.test.sh "FAIL bare node --test blocks (expected 2, got 0) [the hook's last command \"node --test src/x.test.ts\"]"
check gs git-safety.test.sh "FAIL a bare force push blocks (expected 2, got 0) [the hook's last command \"git push --force origin main\"]"
# A hook copied outside a hooks/ folder ("a missing strip-quoted.sh blocks") is noted too: when only hooks/ calls
# were, this check named the command of the check before it, git pu''sh --force.
check gs git-safety.test.sh "FAIL a missing strip-quoted.sh blocks (expected 2, got 0) [the hook's last command \"git push --force\"]"
check sr suite-rerun-guard.test.sh "FAIL tsc rerun on the same tree blocks (expected 2, got 0) [the hook's last command \"npx tsc --noEmit -p tsconfig.json 2>&1 | tail -3; echo done\"]"
check nt new-test-file-guard.test.sh "FAIL a relative in-scope path still resolves (expected 2, got 0) [the hook's last input {\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"src/services/__tests__/second-transfer.test.ts\",\"content\":\"import { createTransfer } from '../transfer-service';\"}}]"
check wa worker-ask-guard.test.sh "FAIL a card session is refused when CLAUDE_PROJECT_DIR names it (expected 2, got 0) [the hook's last input {\"tool_name\":\"AskUserQuestion\",\"tool_input\":{}}]"
# A call's words after the script are its input too (adversarial-review-gate.sh --hash-range <a> <b>), and a later
# call with none and a command clears them. Run on lib/said.sh itself: the words are what the check must name.
printf '%s\n' 'cat > /dev/null' > "$T/x.sh"
got=$( . "$HERE/lib/said.sh"; bash "$T/x.sh" --hash-range 'no/such ref' HEAD < /dev/null; said
  echo; bash "$T/x.sh" <<<'{"tool_input":{"command":"ls"}}'; said )
want=$(printf '%s\n' " [the hook's last call \"--hash-range no/such\\\\ ref HEAD\"]" " [the hook's last command \"ls\"]")
[ "$got" = "$want" ] || { echo "FAIL a hook call's words are not named, or stay named after the next call: $got"; FAIL=1; }
[ "$FAIL" = 1 ] || echo "ok   a guard hook test made to fail names the input it checked"
exit $FAIL
