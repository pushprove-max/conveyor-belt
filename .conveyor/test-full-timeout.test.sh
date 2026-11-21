#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# This project's full test suite (.conveyor/test-full.sh) in parallel mode, stopped by its timeout while a file still
# runs. Bug: the case a still-running engine case file had already ended was named only in that file's own log
# folder, which the suite removed when it was stopped, so the run's progress (fulltest.sh suiteprog()) lost it;
# timeout's second TERM (to the process group) stopped the suite's copy of it partway; and a stopped run's timeout was
# taken for one file's (#1007 review).
set -u
HERE=$(cd "$(dirname "$0")" && pwd -P)
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
AT=@
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t${AT}example.com GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t${AT}example.com

# A scratch repo with the real script and one engine case file: it names one case as ended in the test log, notes
# that it did, then runs on until it is stopped.
R=$T/r; mkdir -p "$R/.conveyor" "$R/conveyor/tests"
cp "$HERE/test-full.sh" "$HERE/test-share.sh" "$R/.conveyor/"
printf '%s\n' 'mkdir -p "$CONVEYOR_TEST_LOG/cases/ok" && : > "$CONVEYOR_TEST_LOG/cases/ok/fx-a-1"' \
  ': > "$(dirname "$0")/../../ready"; sleep 60' > "$R/conveyor/tests/fx-a.test.sh"
echo ready > "$R/.gitignore"
git -C "$R" init -q && git -C "$R" add -A && git -C "$R" commit -qm init

# The run's output and log folder are named as the engine's test step names them (<dir>.test, <dir>.testlog), so the
# engine's own reading of the run (testrun.sh testfails()) can read them below.
mkdir "$T/run.testlog" "$T/config"
(cd "$R" && unset CONVEYOR_TEST_SLOT CONVEYOR_CARD CONVEYOR_TEST_WHOLE && XDG_CONFIG_HOME=$T/config CONVEYOR_TEST_POOL=2:$T/pool \
  CONVEYOR_TEST_SLOTS=$HERE/../conveyor/lib/slots.sh CONVEYOR_TEST_LOG=$T/run.testlog CONVEYOR_SUITE_MODE=parallel \
  exec timeout --kill-after=30 60 bash .conveyor/test-full.sh) > "$T/run.test" 2>&1 &
pid=$!
# The suite is stopped once its file has ended a case, as the test step's clock (testlist.sh testclock()) stops it, by
# SIGALRM to its timeout: only a real stopped run shows what its exit removes and keeps, so this polls the file's mark.
i=0; while [ ! -e "$R/ready" ] && [ $i -lt 200 ]; do sleep 0.1; i=$((i + 1)); done
[ -e "$R/ready" ] || { echo "not ok - the case file did not start: $(cat "$T/run.test")"; kill "$pid"; exit 1; }
kill -ALRM "$pid"; wait "$pid"; rc=$?
[ -e "$T/run.testlog/cases/ok/fx-a-1" ] || { echo "not ok - the case a still-running file ended is not named in the run's log once the suite timed out: $(cd "$T/run.testlog" && find . -type f)"; exit 1; }
# Bug (#1007 review): a suite stopped at its timeout left a log naming the file still running, so the engine took it
# for the run's timeout, and its run alone could pass the release though the suite never ran the rest. A stopped run
# leaves no test-full.log: the timeout is the suite's, and its run alone runs the suite whole. In parallel this fails when the
# log is written as the run goes and names a file once it starts (the serial case is in test-full.test.sh).
full=$(jq -r '.test.full' "$HERE/project.json")
got=$( eval "$(sed -n '/^testfails() {/,/^}/p' "$HERE/../conveyor/lib/testrun.sh"; sed -n '/^testlogs() {/,/^}/p' "$HERE/../conveyor/lib/session.sh")"
  packget() { printf -v "$2" '%s' "$full"; } # the pack's test.full
  TEST_TIMEOUT=60 testfails "$T/run.test" "$rc" test.full | jq -r '.timeout.file' )
[ "$got" = "$full" ] || { echo "not ok - a stopped parallel suite's timeout (exit $rc) is not the suite's but $got: $(cat "$T/run.test")"; exit 1; }
exit 0
