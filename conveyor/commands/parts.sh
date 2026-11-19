# SPDX-License-Identifier: Apache-2.0
# `conveyor.sh parts <parent> <issue>...`: the issues given attached to <parent> as its GitHub sub-issues (its parts,
# attachparts(), lib/slices.sh), for a split the Foreman makes itself. A pick never takes the parent, and the loop
# closes it once its parts are all closed (umbrellas()). Sourced by conveyor.sh.
. "$HERE/lib/prompts.sh" || exit 1
. "$HERE/lib/issues.sh" || exit 1
. "$HERE/lib/pick.sh" || exit 1
. "$HERE/lib/run.sh" || exit 1
. "$HERE/lib/machine.sh" || exit 1
. "$HERE/lib/install.sh" || exit 1
. "$HERE/lib/slices.sh" || exit 1
shift
[ $# -ge 2 ] && ! printf '%s\n' "$@" | grep -qvE '^[1-9][0-9]*$' || { echo "usage: conveyor.sh parts <parent> <issue>..." >&2; exit 2; }
p=$1; shift
for n; do [ "$n" != "$p" ] || { echo "conveyor: #$p cannot be a part of itself; nothing attached" >&2; exit 2; }; done
x=$(attachparts "$p" "$@") || { echo "conveyor: $x" >&2; exit 1; }
echo "conveyor: $(printf '#%s, ' "$@" | sed 's/, $//') attached to #$p as its parts"
