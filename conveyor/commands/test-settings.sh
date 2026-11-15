# SPDX-License-Identifier: Apache-2.0
# `conveyor.sh test-settings <what> [<file>] [<value>]`: one test setting of the pack saved, from the Board's Tests
# page (testsettings(), lib/testfiles.sh). Sourced by conveyor.sh.
. "$HERE/lib/prompts.sh" || exit 1
. "$HERE/lib/pick.sh" || exit 1
. "$HERE/lib/testfiles.sh" || exit 1
. "$HERE/lib/run.sh" || exit 1
. "$HERE/lib/machine.sh" || exit 1
. "$HERE/lib/install.sh" || exit 1
shift; testsettings "$@"
