# SPDX-License-Identifier: Apache-2.0
# `conveyor.sh doctor`: what the project and the host lack for Conveyor (doctor(), lib/setup.sh), sourced by conveyor.sh.
. "$HERE/lib/prompts.sh" || exit 1
. "$HERE/lib/control.sh" || exit 1
. "$HERE/lib/views.sh" || exit 1
. "$HERE/lib/issues.sh" || exit 1
. "$HERE/lib/pick.sh" || exit 1
. "$HERE/lib/run.sh" || exit 1
. "$HERE/lib/machine.sh" || exit 1
. "$HERE/lib/install.sh" || exit 1
. "$HERE/lib/push.sh" || exit 1
. "$HERE/lib/setup.sh" || exit 1
. "$HERE/lib/requires.sh" || exit 1
[ $# = 1 ] || { echo "usage: conveyor.sh doctor" >&2; exit 2; }; doctor
