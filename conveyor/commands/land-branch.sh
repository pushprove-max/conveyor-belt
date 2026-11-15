# SPDX-License-Identifier: Apache-2.0
# `conveyor.sh land-branch <branch>`: a branch landed as a card lands (landbranch(), lib/lane.sh), sourced by conveyor.sh.
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
names || exit 1
[ -n "${2:-}" ] || { echo "usage: conveyor.sh land-branch <branch>" >&2; exit 2; }; landbranch "$2"
