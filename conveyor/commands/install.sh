# SPDX-License-Identifier: Apache-2.0
# `conveyor.sh install <commit>`: the plugin's commit installed for the project (install(), lib/install.sh), sourced
# by conveyor.sh.
. "$HERE/lib/prompts.sh" || exit 1
. "$HERE/lib/pick.sh" || exit 1
. "$HERE/lib/run.sh" || exit 1
. "$HERE/lib/machine.sh" || exit 1
. "$HERE/lib/install.sh" || exit 1
[ $# = 2 ] || { echo "usage: conveyor.sh install <commit>" >&2; exit 2; }; install "$2"
