# SPDX-License-Identifier: Apache-2.0
# `conveyor.sh test-settings <what> [<file>] [<value>]`: one test setting of the pack saved, from the Board's Tests
# page (testsettings(), lib/testfiles.sh; record-times: recordtimes(), lib/setup.sh). Sourced by conveyor.sh.
. "$HERE/lib/prompts.sh" || exit 1
. "$HERE/lib/control.sh" || exit 1
. "$HERE/lib/issues.sh" || exit 1
. "$HERE/lib/pick.sh" || exit 1
. "$HERE/lib/testfiles.sh" || exit 1
. "$HERE/lib/run.sh" || exit 1
. "$HERE/lib/machine.sh" || exit 1
. "$HERE/lib/install.sh" || exit 1
. "$HERE/lib/testaction.sh" || exit 1
. "$HERE/lib/setup.sh" || exit 1
# record-times (recordtimes(), lib/setup.sh) is the one setting that can file a held card, so it loads testaction.sh and setup.sh too.
shift; case ${1:-} in record-times) shift; recordtimes "$@" ;; *) testsettings "$@" ;; esac
