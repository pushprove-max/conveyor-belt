# SPDX-License-Identifier: Apache-2.0
# `conveyor.sh pr merge` (the Board's Merge): the owner merges the open pull request of Land as pr now, whatever the
# rule Merge PR says (prmerge(), lib/push.sh). Exit 2: no pull request is open; 1: GitHub refused the merge (the
# pull request stays open, and the Board shows why); 3: merged, but main or an issue was not brought in line after it.
# Sourced by conveyor.sh.
. "$HERE/lib/slots.sh" || exit 1
. "$HERE/lib/prompts.sh" || exit 1
. "$HERE/lib/control.sh" || exit 1
. "$HERE/lib/issues.sh" || exit 1
. "$HERE/lib/pick.sh" || exit 1
. "$HERE/lib/session.sh" || exit 1
. "$HERE/lib/testrun.sh" || exit 1
. "$HERE/lib/push.sh" || exit 1
. "$HERE/lib/followups.sh" || exit 1
. "$HERE/lib/flaky.sh" && . "$HERE/lib/testfiles.sh" || exit 1 # testowners(): a flaky case's test file, for its issue's area label (casefile())
. "$HERE/lib/run.sh" || exit 1
. "$HERE/lib/machine.sh" || exit 1
. "$HERE/lib/install.sh" || exit 1
names || exit 1
shift
[ "$*" = merge ] || { echo "usage: conveyor.sh pr merge" >&2; exit 2; }
prmerge button
