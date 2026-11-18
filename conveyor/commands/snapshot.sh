# SPDX-License-Identifier: Apache-2.0
# `conveyor.sh snapshot`: the snapshot the Board reads (snapshot(), lib/snapshot.sh), sourced by conveyor.sh.
# Until #398: where the state folder holds snapshot.kept.on, a reader prints the last finished snapshot
# (snapshot.kept.json) at once, and when it is over 15 s old, one build at a time (snapshot.kept.lock) makes the next
# one in the background. With no finished snapshot yet, the reader starts that build too and waits up to 40 s for it.
# CONVEYOR_SNAPSHOT_FRESH=1 always builds.
if [ -z "${CONVEYOR_SNAPSHOT_FRESH:-}" ] && [ -f "$ST/snapshot.kept.on" ]; then
  kept=$ST/snapshot.kept.json
  if [ ! -s "$kept" ] || ! p_newer "$kept" 15; then
    ( exec 9> "$kept.lock"; flock -n 9 || exit 0
      CONVEYOR_SNAPSHOT_FRESH=1 bash "$HERE/conveyor.sh" snapshot > "$kept.new" 2>/dev/null && [ -s "$kept.new" ] && mv -f "$kept.new" "$kept"
      rm -f "$kept.new" ) < /dev/null > /dev/null 2>&1 &
  fi
  for _ in $(seq 40); do [ -s "$kept" ] && break; sleep 1; done
  [ -s "$kept" ] || { echo "conveyor: the first snapshot is still being made" >&2; exit 1; }
  cat "$kept"; exit 0
fi
. "$HERE/lib/slots.sh" || exit 1
. "$HERE/lib/prompts.sh" || exit 1
. "$HERE/lib/control.sh" || exit 1
. "$HERE/lib/views.sh" || exit 1
. "$HERE/lib/snapshot.sh" || exit 1
. "$HERE/lib/issues.sh" || exit 1
. "$HERE/lib/pick.sh" || exit 1
. "$HERE/lib/testrun.sh" || exit 1
. "$HERE/lib/push.sh" || exit 1
. "$HERE/lib/flaky.sh" || exit 1
. "$HERE/lib/fulltest.sh" || exit 1
. "$HERE/lib/testaction.sh" || exit 1
. "$HERE/lib/testfiles.sh" || exit 1
. "$HERE/lib/testrules.sh" || exit 1
. "$HERE/lib/lane.sh" || exit 1
. "$HERE/lib/run.sh" || exit 1
. "$HERE/lib/machine.sh" || exit 1
. "$HERE/lib/install.sh" || exit 1
names || exit 1
snapshot
