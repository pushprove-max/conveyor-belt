# SPDX-License-Identifier: Apache-2.0
# `conveyor.sh check`: the pack when there is one (packok(), lib/prompts.sh), then the records (check(), lib/views.sh).
# Sourced by conveyor.sh.
. "$HERE/lib/prompts.sh" || exit 1
. "$HERE/lib/views.sh" || exit 1
. "$HERE/lib/pick.sh" || exit 1
. "$HERE/lib/run.sh" || exit 1
. "$HERE/lib/machine.sh" || exit 1
. "$HERE/lib/install.sh" || exit 1
{ [ ! -f "$PACK" ] || packok; } && check
