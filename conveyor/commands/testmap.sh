# SPDX-License-Identifier: Apache-2.0
# `conveyor.sh testmap`: the test map's state, as /units shows it (mapstate(), lib/testmap.sh; hooks/units-fetch.sh
# runs it), one JSON object. `conveyor.sh testmap build`: the map made now by hand, on a test slot, in the background
# (mapask()); `conveyor.sh testmap stop`: that build stopped (mapquit()). Sourced by conveyor.sh.
. "$HERE/lib/slots.sh" || exit 1
. "$HERE/lib/prompts.sh" || exit 1
. "$HERE/lib/issues.sh" || exit 1
. "$HERE/lib/testmap.sh" || exit 1
. "$HERE/lib/testaction.sh" || exit 1 # taend(), which ends a stopped build's processes
shift
case ${1:-}:$# in
  :0) mapstate "$MAIN" ;;
  build:1) mapask ;;
  stop:1) mapquit ;;
  *) echo "usage: conveyor.sh testmap [build | stop]" >&2; exit 2 ;;
esac
