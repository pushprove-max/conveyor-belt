# SPDX-License-Identifier: Apache-2.0
# `conveyor.sh testrules <what> [<argument>...]`: the test rules' preview, which files nothing, and their switch,
# guards and rules (testrules(), lib/testrules.sh). Sourced by conveyor.sh.
. "$HERE/lib/prompts.sh" || exit 1
. "$HERE/lib/control.sh" || exit 1
. "$HERE/lib/issues.sh" || exit 1
. "$HERE/lib/pick.sh" || exit 1
. "$HERE/lib/flaky.sh" || exit 1
. "$HERE/lib/testfiles.sh" || exit 1
. "$HERE/lib/testrules.sh" || exit 1
. "$HERE/lib/run.sh" || exit 1
. "$HERE/lib/machine.sh" || exit 1
. "$HERE/lib/install.sh" || exit 1
shift; testrules "$@"
