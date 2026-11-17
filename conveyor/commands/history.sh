# SPDX-License-Identifier: Apache-2.0
# `conveyor.sh history`: the lists the snapshot cuts to their newest, whole, as the last snapshot left them (history(),
# lib/snapshot.sh); `conveyor.sh history test <test file>`: the older runs and test edits of one test file, which the
# snapshot leaves out (testolder(), lib/testfiles.sh). Sourced by conveyor.sh.
. "$HERE/lib/slots.sh" || exit 1
. "$HERE/lib/prompts.sh" || exit 1
. "$HERE/lib/control.sh" || exit 1
. "$HERE/lib/views.sh" || exit 1
. "$HERE/lib/snapshot.sh" || exit 1
. "$HERE/lib/issues.sh" || exit 1
. "$HERE/lib/pick.sh" || exit 1
. "$HERE/lib/testrun.sh" || exit 1
. "$HERE/lib/push.sh" || exit 1
. "$HERE/lib/flaky.sh" || exit 1
. "$HERE/lib/fulltest.sh" || exit 1
. "$HERE/lib/testaction.sh" || exit 1
. "$HERE/lib/testfiles.sh" || exit 1
. "$HERE/lib/testrules.sh" || exit 1
. "$HERE/lib/lane.sh" || exit 1
. "$HERE/lib/run.sh" || exit 1
. "$HERE/lib/machine.sh" || exit 1
. "$HERE/lib/install.sh" || exit 1
names || exit 1
case $#:${2:-} in
  1:) history ;;
  3:test) testolder "$3" ;;
  *) echo "usage: conveyor.sh history [test <test file>]" >&2; exit 2 ;;
esac
