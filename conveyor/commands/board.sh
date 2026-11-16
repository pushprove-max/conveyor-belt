# SPDX-License-Identifier: Apache-2.0
# `conveyor.sh board`: the Board installed as this user's service, for the project whose checkout it runs in (board(),
# lib/install.sh). Sourced by conveyor.sh.
. "$HERE/lib/prompts.sh" || exit 1
. "$HERE/lib/pick.sh" || exit 1
. "$HERE/lib/run.sh" || exit 1
. "$HERE/lib/machine.sh" || exit 1
. "$HERE/lib/install.sh" || exit 1
if [ $# = 1 ]; then board
elif [ $# = 3 ] && [ "$2" = --password-file ] && [ -n "$3" ]; then board "$3"
else echo "usage: conveyor.sh board [--password-file <file>]" >&2; exit 2; fi
