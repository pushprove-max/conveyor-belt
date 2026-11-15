# SPDX-License-Identifier: Apache-2.0
# `conveyor.sh product <sha>`: the product paths a commit changed (product(), lib/issues.sh), sourced by conveyor.sh.
. "$HERE/lib/prompts.sh" || exit 1
. "$HERE/lib/issues.sh" || exit 1
. "$HERE/lib/pick.sh" || exit 1
. "$HERE/lib/run.sh" || exit 1
. "$HERE/lib/machine.sh" || exit 1
. "$HERE/lib/install.sh" || exit 1
names || exit 1
product "$2"
