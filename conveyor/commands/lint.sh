# SPDX-License-Identifier: Apache-2.0
# `conveyor.sh lint`: the pack's lint commands on the tree of the worktree it was called in (CALLED), as `git add -A`
# would stage it, without staging, the change being from the commit the worktree is on (lintreport(), lib/lint.sh),
# sourced by conveyor.sh. It makes no state folder (lib/records.sh) and no base worktree.
. "$HERE/lib/slots.sh" || exit 1
. "$HERE/lib/prompts.sh" || exit 1
. "$HERE/lib/lint.sh" || exit 1
[ $# = 1 ] || { echo "usage: conveyor.sh lint" >&2; exit 2; }
LINTTOP=$(git -C "$CALLED" rev-parse --show-toplevel 2>/dev/null) && LINTBASE=$(git -C "$LINTTOP" rev-parse -q --verify HEAD) \
  || { echo "conveyor lint: $CALLED is in no git checkout with a commit" >&2; exit 2; }
lintreport "$LINTTOP" "$LINTBASE"
