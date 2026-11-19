#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# This project's full test suite (.conveyor/test-full.sh) in parallel mode, stopped by its timeout while a file still
# runs. Bug: the case a still-running engine case file had already ended was named only in that file's own log
# folder, which the suite removed when it was stopped, so the run's progress (fulltest.sh suiteprog()) lost it; and
# timeout's second TERM (to the process group) stopped the suite's copy of it partway.
set -u
HERE=$(cd "$(dirname "$0")" && pwd -P)
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
AT=@
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t${AT}example.com GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t${AT}example.com

# A scratch repo with the real script and one engine case file: it names one case as ended in the test log, notes
# that it did, then runs on until it is stopped.
R=$T/r; mkdir -p "$R/.conveyor" "$R/conveyor/tests"
cp "$HERE/test-full.sh" "$R/.conveyor/"
printf '%s\n' 'mkdir -p "$CONVEYOR_TEST_LOG/cases/ok" && : > "$CONVEYOR_TEST_LOG/cases/ok/fx-a-1"' \
  ': > "$(dirname "$0")/../../ready"; sleep 60' > "$R/conveyor/tests/fx-a.test.sh"
echo ready > "$R/.gitignore"
git -C "$R" init -q && git -C "$R" add -A && git -C "$R" commit -qm init

mkdir "$T/log" "$T/config"
(cd "$R" && unset CONVEYOR_TEST_SLOT CONVEYOR_CARD CONVEYOR_TEST_WHOLE && XDG_CONFIG_HOME=$T/config CONVEYOR_TEST_POOL=2:$T/pool \
  CONVEYOR_TEST_SLOTS=$HERE/../conveyor/lib/slots.sh CONVEYOR_TEST_LOG=$T/log CONVEYOR_SUITE_MODE=parallel \
  exec timeout --kill-after=30 60 bash .conveyor/test-full.sh) > "$T/out" 2>&1 &
pid=$!
# The suite is stopped once its file has ended a case, as the test step's clock (testrun.sh testclock()) stops it, by
# SIGALRM to its timeout: only a real stopped run shows what its exit removes and keeps, so this polls the file's mark.
i=0; while [ ! -e "$R/ready" ] && [ $i -lt 200 ]; do sleep 0.1; i=$((i + 1)); done
[ -e "$R/ready" ] || { echo "not ok - the case file did not start: $(cat "$T/out")"; kill "$pid"; exit 1; }
kill -ALRM "$pid"; wait "$pid"
[ -e "$T/log/cases/ok/fx-a-1" ] || { echo "not ok - the case a still-running file ended is not named in the run's log once the suite timed out: $(cd "$T/log" && find . -type f)"; exit 1; }
exit 0
