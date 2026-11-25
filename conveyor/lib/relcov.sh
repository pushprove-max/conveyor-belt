# SPDX-License-Identifier: Apache-2.0
# The coverage map a release makes again and commits (issue 1593; the pack's coverageMap: command, which writes file, a
# path from the repository root). No other run writes it: a card's test step only reads it.
# relcov <command name> <worktree> <commit>: after the whole suite ran on <commit>, passed or failed, and its result
# was written and reported (relsuite(), commands/release-prep.sh), runs the command on the machine the suite ran on, in
# its worktree of that commit: here, or on a box over ssh or a devbox before it is given back, which sends the map
# back (hostmap(), lib/suitehost.sh). It keeps the map in $CARDS/release/coverage.<tree of the commit>, for the release of that tree to
# commit (relcovput()), whether release or release-prep ran the suite (a failed one: for release --anyway). A command
# that fails is named, with the end of its output, and the map it still wrote is kept: a traced run whose unit failed
# still holds what the other units ran.
# A map kept of another tree is removed. While the command runs, the run's record says so (coverage: "running"), so the
# Release panel shows the suite's result, not a suite that runs; relsuite() may write that mark before (relcovon()),
# and relcov() takes it out however it ends.
# relcovon: whether the pack names the map's command and its file, so relcov() runs the command.
relcovon() { local cmd f; packget coverageMap.command cmd coverageMap.file f 2>/dev/null && [ -n "$cmd" ] && [ -n "$f" ]; }
relcov() {
  local n=$1 wt=$2 cmd f k rc
  packget coverageMap.command cmd coverageMap.file f 2>/dev/null && [ -n "$cmd" ] && [ -n "$f" ] || return 0
  k=$(git -C "$wt" rev-parse -q --verify "$3^{tree}") || { relrec 'del(.coverage)'; return 0; }
  k=$CARDS/release/coverage.$k
  rm -f "$CARDS/release/coverage."* "$wt/$f"
  relrec '.coverage = "running"'
  echo "conveyor: $n: makes the coverage map, $f, again on ${3:0:12}, on $SH_NAME: $cmd"
  if [ "$SH_KIND" != local ]; then hostmap "$wt" "$cmd" "$f" "$wt.coverage"; rc=$?
  else (cd "$wt" && unset CONVEYOR_SUITE_MODE CONVEYOR_SUITE_RECORD CONVEYOR_SUITE_AT_ONCE CONVEYOR_SUITE_FILES && bash -c "$cmd") > "$wt.coverage" 2>&1 < /dev/null; rc=$?; fi
  [ $rc = 0 ] || { echo "conveyor: $n: the coverage map's command failed (exit $rc); the end of its output:"; tail -n 20 "$wt.coverage"; } >&2
  if [ -s "$wt/$f" ] && cp "$wt/$f" "$k.new" && mv "$k.new" "$k"; then echo "conveyor: $n: the coverage map of ${3:0:12} is kept for its release to commit"
  else rm -f "$k.new"; echo "conveyor: $n: the coverage map's command wrote no $f; the release commits none" >&2; fi
  relrec 'del(.coverage)'
}
# relcovput <commit> <terms file, or nothing>: the map relcov() kept of <commit>'s tree, put at its path in the
# checkout and staged for the release commit; prints that path, or nothing when none is put. None is put, and the
# release goes on without it, when the privacy check (with the release's terms file) finds something in the map or
# cannot read it, as the release pushes it; or when the checkout holds a map at that path that <commit> does not hold
# (the Foreman's map, made by hand and not committed yet): it is left as it is. A put that fails half way is undone.
# With no map kept of <commit>'s tree (its command wrote none, or the run was stopped while it ran, after the suite's
# status was posted, which this release reuses), the output says so and the release commits none.
relcovput() {
  local f k
  packget coverageMap.file f 2>/dev/null && [ -n "$f" ] || return 0
  k=$CARDS/release/coverage.$(git rev-parse -q --verify "$1^{tree}") && [ -s "$k" ] \
    || { echo "conveyor: release: no coverage map of ${1:0:12} is kept (its command wrote none, or the run was stopped while it ran); the release commits none" >&2; return 0; }
  if [ -e "$f" ] && ! { git cat-file -e "$1:$f" 2>/dev/null && git diff --quiet "$1" -- "$f"; }; then
    echo "conveyor: release: the checkout holds a $f that ${1:0:12} does not; it is left as it is, and the release commits no coverage map" >&2; return 0
  fi
  "$HERE/privacy/check.sh" ${2:+--terms "$2"} "$k" > /dev/null 2>&1 \
    || { echo "conveyor: release: the privacy check finds something in the coverage map, or cannot read it ($HERE/privacy/check.sh $k); the release commits no coverage map" >&2; return 0; }
  cp "$k" "$f" && git add -- "$f" && echo "$f" || { relcovundo "$1"; return 1; }
}
# relcovundo <commit>: the map's path in the checkout as it is at <commit> (after the release's undo resets the index
# to it): as committed there, or removed when that commit has none. Called only after relcovput() put a map there.
relcovundo() {
  local f
  packget coverageMap.file f 2>/dev/null && [ -n "$f" ] || return 0
  if git cat-file -e "$1:$f" 2>/dev/null; then git checkout -q "$1" -- "$f"; else rm -f "$f"; fi
}
