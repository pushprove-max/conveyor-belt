# SPDX-License-Identifier: Apache-2.0
# `conveyor.sh testmap`: the test map's state, as /units shows it (mapstate(), lib/testmap.sh; hooks/units-fetch.sh
# runs it), one JSON object. Sourced by conveyor.sh.
. "$HERE/lib/prompts.sh" || exit 1
. "$HERE/lib/issues.sh" || exit 1
. "$HERE/lib/testmap.sh" || exit 1
mapstate "$MAIN"
