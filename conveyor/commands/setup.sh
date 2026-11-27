# SPDX-License-Identifier: Apache-2.0
# `conveyor.sh setup [--owner <name>] [--product <path>]... [--test <command>] [--survey yes|no] [--test-patterns yes|no] [--file-command yes|no] [--test-map yes|no] --fast-lane yes|no --research-lane yes|no [--link yes|no] [--worktree-setup <command>] [--lint <command> --lint-files <pathspec>...] [--lint-ready yes|no] [--lint-shared yes|no] [--size <lines>|no] [--size-files <pathspec>]... [--size-skip <folder>]... [--serena yes|no] [--pin] [--foreman]`:
# the project set up for Conveyor (setup(), lib/setup.sh), from its checkout; `conveyor.sh setup pack-commit [yes | no]`:
# the pack committed on the default branch on the owner's yes (packcommit(), lib/setup.sh); `conveyor.sh setup desktop`:
# /units's bundle for Claude Desktop built, and opened on macOS (desktopbundle(), lib/setup.sh). Sourced by conveyor.sh.
. "$HERE/lib/slots.sh" || exit 1
. "$HERE/lib/prompts.sh" || exit 1
. "$HERE/lib/control.sh" || exit 1
. "$HERE/lib/issues.sh" || exit 1
. "$HERE/lib/pick.sh" || exit 1
. "$HERE/lib/survey.sh" || exit 1
. "$HERE/lib/run.sh" || exit 1
. "$HERE/lib/machine.sh" || exit 1
. "$HERE/lib/install.sh" || exit 1
. "$HERE/lib/push.sh" || exit 1
. "$HERE/lib/testmap.sh" || exit 1
. "$HERE/lib/setup.sh" || exit 1
. "$HERE/lib/lint.sh" || exit 1
git -C "$CALLED" rev-parse --git-dir >/dev/null 2>&1 || { echo "conveyor: setup runs in the checkout of the project" >&2; exit 1; }
case ${2-} in pack-commit) packcommit "${@:3}" ;; desktop) desktopbundle "${@:3}" ;; *) "$@" ;; esac
