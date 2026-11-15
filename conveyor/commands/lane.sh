# SPDX-License-Identifier: Apache-2.0
# `conveyor.sh lane research create | lane fast create | review | land | reset [--drop <sha>]`: the lanes, sourced by
# conveyor.sh. The research lane (lanes/research.sh: its worktree, settings and hooks); the fast lane (lanecreate and
# what follows it, lib/lane.sh).
. "$HERE/lib/slots.sh" || exit 1
. "$HERE/lib/prompts.sh" || exit 1
. "$HERE/lib/control.sh" || exit 1
. "$HERE/lib/views.sh" || exit 1
. "$HERE/lib/issues.sh" || exit 1
. "$HERE/lib/pick.sh" || exit 1
. "$HERE/lib/session.sh" || exit 1
. "$HERE/lib/review.sh" || exit 1
. "$HERE/lib/testrun.sh" || exit 1
. "$HERE/lib/claim.sh" || exit 1
. "$HERE/lib/push.sh" || exit 1
. "$HERE/lib/followups.sh" || exit 1
. "$HERE/lib/flaky.sh" || exit 1
. "$HERE/lib/testaction.sh" || exit 1
. "$HERE/lib/testfiles.sh" || exit 1
. "$HERE/lib/testrules.sh" || exit 1
. "$HERE/lib/survey.sh" || exit 1
. "$HERE/lib/card.sh" || exit 1
. "$HERE/lib/lane.sh" || exit 1
. "$HERE/lib/run.sh" || exit 1
. "$HERE/lib/machine.sh" || exit 1
. "$HERE/lib/install.sh" || exit 1
case ${2:-}:${3:-}:$#:${4:-} in
  research:create:3:) CONVEYOR_MAIN=$MAIN CONVEYOR_STATE_DIR=$ST exec bash "$HERE/lanes/research.sh" create ;;
  fast:create:3: | fast:review:3: | fast:land:3: | fast:reset:3: | fast:reset:5:--drop) names || exit 1; "lane$3" "${@:4}" ;;
  *) echo "usage: conveyor.sh lane research create | lane fast create | review | land | reset [--drop <sha>]" >&2; exit 2 ;;
esac
