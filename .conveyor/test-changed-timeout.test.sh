#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# test-changed.sh's one-file mode (`--file <path>`) stopped at the file's own time limit, as a card's Test step runs it
# (conveyor/lib/fileeach.sh fileeach(): `timeout --kill-after=10 <limit>`, which sends TERM to the run and to its whole
# process group). Bug it catches (issue 1607): the group's TERM ends the case file's worker as it reaches the run, so
# the run's `wait "$p"` can take the worker's exit just before the TERM trap (eend()) cuts it short; bash then keeps the
# worker as a running job that is no child of the shell, and the trap's bare `wait` wrote `wait: pid <n> is not a child
# of this shell` again and again until the KILL 10 s later (a card's test log of 886 MB), so the file was read as
# failed, not as timed out, and the case that passed before the limit was lost in that output.
set -u
HERE=$(cd "$(dirname "$0")" && pwd -P); ROOT=$(dirname "$HERE")
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
AT=@
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t${AT}example.com GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t${AT}example.com
unset CONVEYOR_TEST_LOG CONVEYOR_SHELL_TEST_CASE CONVEYOR_TEST_FILE CONVEYOR_TEST_FILELIST BASH_ENV CONVEYOR_TEST_RERUN CONVEYOR_TEST_SLOT CONVEYOR_TEST_SLOTS CONVEYOR_TEST_POOL CONVEYOR_TEST_CASES
fails=0
no() { echo "not ok - $1"; fails=1; }

# A scratch repo: the real script, a map of two areas (a: x.sh and a.test.sh's two cases, with a time limit of 8 s;
# c: z.sh and c.test.sh's one, which the change does not select, so a is not every case file), and a runner stub that
# passes aone, then outlives the limit in atwo, busy on a CPU at the lowest priority (below). The change touches x.sh.
# A run starts its case in 1 to 2 s on an idle machine; on a loaded one, 3 s was too short for most runs to get there.
# The stub marks that aone passed (.git/aone, which no git command of the run sees): a run that got no further than its
# start before the limit has no case that passed to keep.
R=$T/r; mkdir -p "$R/.conveyor" "$R/conveyor/tests"
cp "$HERE/test-changed.sh" "$HERE/test-share.sh" "$HERE/lint-shell.sh" "$HERE/test-lint.sh" "$HERE/no-browser-tests.sh" "$HERE/no-records-split.sh" "$R/.conveyor/"
printf '%s\n' '{"area": "a", "file": "conveyor/x.sh"}' '{"area": "a", "test": "a.test.sh"}' \
  '{"area": "c", "file": "conveyor/z.sh"}' '{"area": "c", "test": "c.test.sh"}' > "$R/.conveyor/engine-areas.json"
printf '# timeout: 8\nt_aone() {\n  :\n}\nt_atwo() {\n  :\n}\n' > "$R/conveyor/tests/a.test.sh"
printf 't_cone() {\n  :\n}\n' > "$R/conveyor/tests/c.test.sh"
printf '%s\n' 'echo "ok aone"; : > .git/aone' 'exec nice -n 19 bash -c "while :; do :; done"' > "$R/conveyor/conveyor.test.sh"
echo one > "$R/conveyor/x.sh"; echo one > "$R/conveyor/z.sh"
echo '{"test": {"files": {"conveyor/conveyor.test.sh": {"wholeOnly": true}}}}' > "$R/.conveyor/project.json"
git -C "$R" init -q && git -C "$R" add -A && git -C "$R" commit -qm init
echo two >> "$R/conveyor/x.sh"
# The checks, run once for the tree as the loop's Test step runs them before its one-file runs (test.checkCommand:
# conveyor/lib/donewhen.sh treecheck()) and kept for each run as checks/<commit>-<tree> of its log folder (checkskept()):
# twelve runs of them side by side took past a 3 s limit before a case ran, so the runs reuse this one.
(cd "$R" && bash .conveyor/test-changed.sh --checks > "$T/checks.out" 2>&1); echo $? > "$T/checks.rc"
key=$(git -C "$R" rev-parse HEAD)-$(. "$ROOT/conveyor/lib/donewhen.sh" && treeof "$R") || no "the tree key of the scratch repo"

# The engine's own run of the file: fileeach() with the pack's fileCommand and the time limits as testrun.sh reads them,
# so the limit is the file's 8 s (times the load factor) and the KILL comes 10 s after it.
# Why many real runs, not one: the bug needs the TERM to reach the run just after its `wait` took the worker's exit,
# within microseconds, and nothing outside bash can force that order. A worker that is asleep at the TERM wakes as late
# as the run does (about one run in twenty hits it); with the stand-in case busy on a CPU, the worker ends first in 6
# to 9 runs of 24 with a bare `wait` in eend(). One round of 24 then missed it about one time in 150, and the test passed
# with the bug. So the runs go in rounds of N side by side, each run on a copy of the scratch repo, until NEED of them
# got to their case (.git/aone) before the limit: at one run in five, all 60 miss it about one time in 650,000. A test
# with fewer in MAXR rounds fails, as its runs could not show the bug. The busy case's low priority keeps the other
# runs' starts within the limit.
# Under a tracer (the engine's input trace, strace -f -e trace=%file, follows each process of the test), every file
# open stops for the one tracer: at the TERM each run's eend() pkill reads /proc whole, thousands of opens, and 24 of
# them at once queued past the 10 s KILL, so the runs "did not end on its TERM". Traced, the runs go 6 side by side in
# more rounds, the same 120 runs at most.
# Each output is cut at 20 MB (ulimit -f): a run that writes the error again and again ends there.
N=24 NEED=60 MAXR=5 began=0 round=0
[ "$(awk '/^TracerPid:/ { print $2 }' /proc/self/status 2>/dev/null)" -gt 0 ] 2>/dev/null && N=6 MAXR=20
while [ "$began" -lt $NEED ] && [ $round -lt $MAXR ] && [ $fails = 0 ]; do
  ks=$(seq $((round * N + 1)) $((round * N + N))); round=$((round + 1))
  for k in $ks; do
    cp -a "$R" "$T/r$k" && mkdir -p "$T/log$k/checks" && echo conveyor/tests/a.test.sh > "$T/list$k" \
      && cp "$T/checks.out" "$T/log$k/checks/$key.out" && cp "$T/checks.rc" "$T/log$k/checks/$key.rc" || { no "the copy $k of the scratch repo"; break; }
    # fileeach() ends with exit: its own subshell.
    ( ( cd "$T/r$k" && . "$ROOT/conveyor/lib/fileeach.sh" && eval "$(grep -E '^(FILELIMIT|LOADSCALE)=' "$ROOT/conveyor/lib/testrun.sh")" \
        && export CONVEYOR_TEST_LOG=$T/log$k CONVEYOR_TEST_FILELIST=$T/list$k && ulimit -f 20480 \
        && fileeach one "bash .conveyor/test-changed.sh --file" "$FILELIMIT" "$LOADSCALE" "$T/log$k/files" conveyor/tests/a.test.sh )
      echo $? > "$T/rc$k" ) > "$T/out$k" 2>&1 &
  done
  wait
  for k in $ks; do
    o=$T/out$k l=$T/log$k; rc=$(cat "$T/rc$k" 2>/dev/null)
    grep -q 'their result is kept' "$o" || no "the one-file run $k ran the checks again, not the kept ones of its tree $key: $(head -c 1000 "$o")"
    # A run ended at the KILL exits 137 (timeout's), which fileeach() logs as `-- FAIL`: the timeout line, and the run's
    # exit 124, say it ended on its TERM, within the kill time.
    grep -qxF -- '-- timeout conveyor/tests/a.test.sh' "$l/files" && [ "$rc" = 124 ] \
      || no "the one-file run $k past its time limit did not end on its TERM: exit $rc: $(head -c 1000 "$l/files"): $(head -c 1000 "$o")"
    n=$(grep -c 'not a child' "$o")
    [ "$n" = 0 ] || no "the one-file run $k past its time limit wrote $n 'not a child' lines: $(grep -m 3 'not a child' "$o")"
    [ -e "$T/r$k/.git/aone" ] || continue
    began=$((began + 1))
    grep -qxF '== conveyor/tests/a.test.sh (cases: aone atwo)' "$o" && grep -qxF 'ok aone' "$o" \
      && grep -qxF '== conveyor/tests/a.test.sh' "$l/test-changed.log" && ! grep -q '^-- ' "$l/test-changed.log" \
      || no "the one-file run $k past its time limit lost the case that passed before it: $(head -c 1000 "$o"): $(head -c 1000 "$l/test-changed.log")"
  done
done
# Too few runs at their case at the TERM could all have missed the race: a pass would then show nothing of the bug.
[ $fails = 1 ] || [ "$began" -ge $NEED ] || no "only $began of $((round * N)) one-file runs got to their case (.git/aone) within the 8 s limit, in $round rounds; $NEED are needed: $(head -c 1000 "$T/out1")"

[ $fails = 0 ] && echo "ok - test-changed's one-file run past its time limit ends on its TERM" || exit 1
