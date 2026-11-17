#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# test-changed.sh's run of an engine case file with no case selected: the split check's rerun line
# `fail<TAB><case file><TAB>conveyor-no-case` (lib/testrun.sh splitstart()), whose CPU seconds are the start-up
# allowance of each file a split adds. Bug it catches (#191): the case file ran with every one of its cases, through
# the runner, so the run named cases, the check could not use it, and an honest split was refused against the pack's
# 1 CPU s guess. The run must run the file's start-up alone (the runner with no case) and time it as that file.
set -u
HERE=$(cd "$(dirname "$0")" && pwd -P)
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
AT=@
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t${AT}example.com GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t${AT}example.com
unset CONVEYOR_TEST_LOG CONVEYOR_SHELL_TEST_CASE CONVEYOR_TEST_FILE CONVEYOR_TEST_FILES BASH_ENV CONVEYOR_TEST_RERUN CONVEYOR_TEST_SLOTS
fails=0
no() { echo "not ok - $1"; fails=1; }

# A scratch repo: the real script, and a runner whose start-up takes 0.6 CPU s and each case 1 CPU s more; its one
# case file starts it as the engine's do (run alone, it gives the runner its own cases when none is chosen).
R=$T/r; mkdir -p "$R/.conveyor" "$R/conveyor/tests"
cp "$HERE/test-changed.sh" "$HERE/test-lint.sh" "$HERE/no-browser-tests.sh" "$R/.conveyor/"
printf '%s\n' '{"area": "a", "file": "conveyor/x.sh"}' '{"area": "a", "test": "a.test.sh"}' > "$R/.conveyor/engine-areas.json"
echo 'echo one' > "$R/conveyor/x.sh"
cat > "$R/conveyor/tests/a.test.sh" <<'EOF'
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"
t_aone() {
  :
}
EOF
cat > "$R/conveyor/conveyor.test.sh" <<'EOF'
burn() { python3 -c 'import sys, time
s = time.process_time()
while time.process_time() - s < float(sys.argv[1]): pass' "$1"; }
burn 0.6
for c in ${CONVEYOR_SHELL_TEST_CASE:-aone}; do burn 1; echo "ok $c"; done
EOF
echo '{"test": {"files": {"conveyor/conveyor.test.sh": {"wholeOnly": true}}}}' > "$R/.conveyor/project.json"
git -C "$R" init -q && git -C "$R" add -A && git -C "$R" commit -qm init

mkdir "$T/log"; printf 'fail\tconveyor/tests/a.test.sh\tconveyor-no-case\n' > "$T/rerun"
(cd "$R" && CONVEYOR_TEST_LOG=$T/log CONVEYOR_TEST_RERUN=$T/rerun bash .conveyor/test-changed.sh) > "$T/out" 2>&1 \
  || no "the run with no case failed: $(tail -n 20 "$T/out")"
! grep -q '^ok ' "$T/out" || no "the run with no case ran cases: $(grep '^ok ' "$T/out")"
cpu=$(sed -n 's/^TESTRUN sec\tconveyor\/tests\/a\.test\.sh\t[^\t]*\t//p' "$T"/log/*.log | tail -n 1)
awk -v c="$cpu" 'BEGIN { exit !(c != "" && c >= 0.48 && c <= 0.72) }' \
  || no "the run with no case did not time the file's start-up of 0.6 CPU s within 20%: '$cpu'"

[ $fails = 0 ] && echo "ok - test-changed no-case run" || exit 1
