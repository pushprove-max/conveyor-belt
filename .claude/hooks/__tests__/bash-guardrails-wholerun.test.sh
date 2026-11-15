#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# bash-guardrails.sh in a card's build or fix session (CONVEYOR_CARD set): the three whole-suite runs the owner refused
# there on 2026-11-14 are blocked, each named by the project's pack, and the same command naming a case or file runs.
# A card session that ran the whole suite by hand cost minutes the loop's Test step spends again before the card lands.
set -u
HOOK=$(cd "$(dirname "$0")/.." && pwd)/bash-guardrails.sh
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
mkdir -p "$T/p/.conveyor" "$T/p/tests/unit" "$T/p/tools" "$T/p/ci" "$T/state"
# The pack names the project's own commands: the guard reads them, never a name of its own.
printf '%s\n' '{"test": {"command": "bash ci/run-changed.sh", "wholeCommands": ["tools/all.test.sh"], "changed": "ci/run-changed.sh"}}' > "$T/p/.conveyor/project.json"
FAIL=0
# <expected exit> <session id> <card, or empty for no card session> <command> <why it matters> [<what a refusal says to do>]
check() {
  local rc=0
  jq -cn --arg c "$4" --arg d "$T/p" --arg s "$2" '{tool_input: {command: $c}, cwd: $d, session_id: $s}' \
    | (cd "$T/p" && CONVEYOR_CARD=$3 CLAUDE_PROJECT_DIR=$T/p CONVEYOR_GUARD_STATE=$T/state bash "$HOOK") > /dev/null 2> "$T/err" || rc=$?
  if [ "$rc" = "$1" ] && { [ -z "${6:-}" ] || grep -qF "$6" "$T/err"; }; then echo "ok   $4"
  else echo "FAIL $4 (exit $rc, wanted $1${6:+, saying: $6}): $5"; sed 's/^/     /' "$T/err"; FAIL=1; fi
}
check 2 s1 c1 'timeout 240 bash tools/all.test.sh > /tmp/all.out 2>&1' 'the whole runner with no case named runs every case' 'name the cases'
check 0 s1 c1 'timeout 240 bash tools/all.test.sh rerun' 'naming a case is the run a card session is to make'
check 0 s1 c1 'CONVEYOR_SHELL_TEST_CASE=rerun bash ./tools/all.test.sh' 'cases named by the runner variable are named cases'
check 2 s1 c1 '/usr/bin/timeout 240 /bin/bash tools/all.test.sh' 'a shell or wrapper named by its path still runs every case' 'name the cases'
check 0 s1 c1 '/bin/bash tools/all.test.sh rerun' 'by a shell named by its path, naming a case is still allowed'
# A wrapper option that takes the next word must not leave that word read as the command (a whole run let through).
check 2 s1 c1 'env -u CONVEYOR_SHELL_TEST_CASE bash tools/all.test.sh' 'env -u NAME left NAME read as the command' 'name the cases'
check 2 s1 c1 'CONVEYOR_SHELL_TEST_CASE=rerun env -u CONVEYOR_SHELL_TEST_CASE bash tools/all.test.sh' 'the cases unset again name none' 'name the cases'
check 2 s1 c1 'CONVEYOR_SHELL_TEST_CASE=rerun env -i bash tools/all.test.sh' 'env -i clears the cases named before it' 'name the cases'
check 2 s1 c1 'bash -o pipefail tools/all.test.sh' 'bash -o OPTION left OPTION read as the command' 'name the cases'
check 2 s1 c1 "env -S 'bash tools/all.test.sh'" 'env -S runs its text as the command' 'name the cases'
check 2 s1 c1 'env -C tools bash all.test.sh' 'env -C moves the directory the command is read from' 'name the cases'
check 0 s1 c1 'env -C tools true && bash all.test.sh' 'env -C moves only its own segment: all.test.sh after it is not tools/all.test.sh'
check 0 s7 c1 'env -u CONVEYOR_SHELL_TEST_CASE bash ci/run-changed.sh' 'a run behind env -u is the session'"'"'s one run'
check 2 s7 c1 'env -u CONVEYOR_SHELL_TEST_CASE bash ci/run-changed.sh' 'a second run behind env -u is still a second run' 'name the cases'
check 2 s1 c1 'env -u CONVEYOR_SHELL_TEST_CASE node --max-old-space-size=4096 --test tests/' 'node behind env -u over a folder still runs every file' 'name the files'
check 0 s1 '' 'bash tools/all.test.sh' 'outside a card session (the owner, the Foreman) a whole run is not this rule'
check 2 s1 c1 'cd tools && bash all.test.sh' 'the whole runner reached through a cd still runs every case' 'name the cases'
check 0 s1 c1 'cd tools && bash all.test.sh rerun' 'through a cd, naming a case is still allowed'
check 0 s2 c1 'bash ci/run-changed.sh' 'the first run of the changed tests in a session is allowed'
check 2 s2 c1 'bash ci/run-changed.sh' 'a second run of the changed tests in one session runs them all again' 'name the cases'
check 2 s2 c1 'cd ci && bash run-changed.sh' 'a second run reached through a cd is still a second run' 'name the cases'
check 0 s3 c1 'bash ci/run-changed.sh' 'another session of the card gets its own one run'
check 2 s4 c1 'bash ci/run-changed.sh && bash ci/run-changed.sh' 'two runs in one call are a second run in the session' 'run it once'
check 0 s4 c1 'bash ci/run-changed.sh' 'the refused call ran nothing, so the session keeps its one run'
check 0 s5 c1 'cd ci && bash run-changed.sh' 'a run reached through a cd is the session'"'"'s one run'
check 2 s5 c1 'bash ci/run-changed.sh' 'after a run reached through a cd, another is a second run' 'name the cases'
check 0 s6 c1 '/bin/bash ci/run-changed.sh' 'the first run by a shell named by its path is the session'"'"'s one run'
check 2 s6 c1 '/bin/bash ci/run-changed.sh' 'a second run by a shell named by its path is still a second run' 'name the cases'
check 2 s1 c1 'node --max-old-space-size=4096 --test tests/' 'node over a folder runs every test file in it' 'name the files'
check 2 s1 c1 'cd tests && node --max-old-space-size=4096 --test unit/' 'a folder named from where cd went is still a folder' 'name the files'
check 2 s1 c1 'node --max-old-space-size=4096 --test' 'node with no file runs every test file it finds' 'name the files'
check 0 s1 c1 'node --max-old-space-size=4096 --test tests/one.test.mjs' 'naming the test file is allowed'
exit $FAIL
