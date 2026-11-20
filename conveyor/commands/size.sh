# SPDX-License-Identifier: Apache-2.0
# `conveyor.sh size --list`: the files over the limit of the pack's size entries in the tree of the worktree it was
# called in (CALLED), one path a line (lintsizelist(), lib/lint.sh), sourced by conveyor.sh. It makes no state folder
# (lib/records.sh) and changes nothing.
. "$HERE/lib/slots.sh" || exit 1
. "$HERE/lib/prompts.sh" || exit 1
. "$HERE/lib/lint.sh" || exit 1
[ $# = 2 ] && [ "$2" = --list ] || { echo "usage: conveyor.sh size --list" >&2; exit 2; }
SIZETOP=$(git -C "$CALLED" rev-parse --show-toplevel 2>/dev/null) || { echo "conveyor size: $CALLED is in no git checkout" >&2; exit 2; }
lintsizelist "$SIZETOP" || exit 2
