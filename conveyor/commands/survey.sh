# SPDX-License-Identifier: Apache-2.0
# `conveyor.sh survey`: the monthly test-speed survey's issue, when one is due (survey(), lib/survey.sh): what `serve`
# looks at once a minute. Sourced by conveyor.sh.
. "$HERE/lib/prompts.sh" || exit 1
. "$HERE/lib/control.sh" || exit 1
. "$HERE/lib/issues.sh" || exit 1
. "$HERE/lib/pick.sh" || exit 1
. "$HERE/lib/survey.sh" || exit 1
. "$HERE/lib/run.sh" || exit 1
. "$HERE/lib/machine.sh" || exit 1
. "$HERE/lib/install.sh" || exit 1
names || exit 1
[ $# = 1 ] || { echo "usage: conveyor.sh survey" >&2; exit 2; }; survey
