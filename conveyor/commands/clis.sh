# SPDX-License-Identifier: Apache-2.0
# `conveyor.sh clis`: the host's report, read afresh: each CLI installed here and the models it has registered
# (hostclis(), lib/control.sh). Sourced by conveyor.sh.
. "$HERE/lib/prompts.sh" || exit 1
. "$HERE/lib/control.sh" || exit 1
. "$HERE/lib/pick.sh" || exit 1
. "$HERE/lib/run.sh" || exit 1
. "$HERE/lib/machine.sh" || exit 1
. "$HERE/lib/install.sh" || exit 1
[ $# = 1 ] || { echo "usage: conveyor.sh clis" >&2; exit 2; }; hostclis fresh
