# SPDX-License-Identifier: Apache-2.0
# `conveyor.sh full-test [push | anyway <run id> [--by <who>]]`: the full test suite on main, from the Board: run
# alone, or behind a push of what landed, or a push over a red one (fulltest(), lib/fulltest.sh). Also `conveyor.sh
# push-now`: what landed, pushed as the loop pushes it, with no full test run (pushnow()). Sourced by conveyor.sh.
. "$HERE/lib/slots.sh" || exit 1
. "$HERE/lib/prompts.sh" || exit 1
. "$HERE/lib/control.sh" || exit 1
. "$HERE/lib/issues.sh" || exit 1
. "$HERE/lib/pick.sh" || exit 1
. "$HERE/lib/session.sh" || exit 1
. "$HERE/lib/testrun.sh" || exit 1
. "$HERE/lib/push.sh" || exit 1
. "$HERE/lib/followups.sh" || exit 1
. "$HERE/lib/flaky.sh" || exit 1
. "$HERE/lib/testfiles.sh" || exit 1
. "$HERE/lib/fulltest.sh" || exit 1
. "$HERE/lib/run.sh" || exit 1
. "$HERE/lib/machine.sh" || exit 1
. "$HERE/lib/install.sh" || exit 1
names || exit 1
if [ "$1" = push-now ]; then shift; pushnow "$@"; else shift; fulltest "$@"; fi
