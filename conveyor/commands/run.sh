# SPDX-License-Identifier: Apache-2.0
# `conveyor.sh run [--only <issue>[,<issue>...]] [max-cards]`: the loop (run(), lib/run.sh), sourced by conveyor.sh.
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
. "$HERE/lib/fulltest.sh" || exit 1
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
# shellcheck disable=SC2034 # ONLY is read in lib/pick.sh
[ "${2:-}" != --only ] || { [[ ${3:-} =~ ^[1-9][0-9]*(,[1-9][0-9]*)*$ ]] || { echo "usage: conveyor.sh run [--only <issue>[,<issue>...]] [max-cards]" >&2; exit 2; }
  ONLY="[$3]"; shift 2; }
run "${2:-}"
