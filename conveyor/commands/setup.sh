# SPDX-License-Identifier: Apache-2.0
# `conveyor.sh setup [--owner <name>] [--product <path>]... [--test <command>] [--survey yes|no] --fast-lane yes|no --research-lane yes|no [--pin] [--foreman]`:
# the project set up for Conveyor (setup(), lib/setup.sh), from its checkout. Sourced by conveyor.sh.
. "$HERE/lib/prompts.sh" || exit 1
. "$HERE/lib/issues.sh" || exit 1
. "$HERE/lib/pick.sh" || exit 1
. "$HERE/lib/survey.sh" || exit 1
. "$HERE/lib/run.sh" || exit 1
. "$HERE/lib/machine.sh" || exit 1
. "$HERE/lib/install.sh" || exit 1
. "$HERE/lib/setup.sh" || exit 1
git -C "$CALLED" rev-parse --git-dir >/dev/null 2>&1 || { echo "conveyor: setup runs in the checkout of the project" >&2; exit 1; }; "$@"
