# SPDX-License-Identifier: Apache-2.0
# `conveyor.sh pick --dry --issues <file> --state <dir>`: the issue the loop would pick, from the files given, with
# nothing written (drypick(), lib/pick.sh). Sourced by conveyor.sh.
. "$HERE/lib/prompts.sh" || exit 1
. "$HERE/lib/control.sh" || exit 1
. "$HERE/lib/issues.sh" || exit 1
. "$HERE/lib/pick.sh" || exit 1
. "$HERE/lib/run.sh" || exit 1
. "$HERE/lib/machine.sh" || exit 1
. "$HERE/lib/install.sh" || exit 1
names || exit 1
[ $# = 6 ] && [ "$2" = --dry ] && [ "$3" = --issues ] && [ "$5" = --state ] && set -- "$1" "$2" "$3" "$(cd "$CALLED" && realpath -e -- "$4")" "$5" "$(cd "$CALLED" && realpath -e -- "$6")" \
  && [ -f "$4" ] && [ -d "$6" ] || { echo "usage: conveyor.sh pick --dry --issues <file> --state <dir>" >&2; exit 2; }
drypick "$4" "$6"
