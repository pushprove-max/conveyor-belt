# SPDX-License-Identifier: Apache-2.0
# `conveyor.sh take`: a pack that follows the plugin's main: its pushed main taken when it passes its check (take(),
# lib/install.sh). Sourced by conveyor.sh.
. "$HERE/lib/prompts.sh" || exit 1
. "$HERE/lib/pick.sh" || exit 1
. "$HERE/lib/run.sh" || exit 1
. "$HERE/lib/machine.sh" || exit 1
. "$HERE/lib/install.sh" || exit 1
[ $# = 1 ] || { echo "usage: conveyor.sh take" >&2; exit 2; }; take
