# SPDX-License-Identifier: Apache-2.0
# `conveyor.sh take`: a pack that follows the plugin's main: its pushed main taken when it passes its check (take(),
# lib/install.sh); then the machine's service, when it runs older Conveyor than the project's, is started again on
# the project's commit (servicerenew()). Sourced by conveyor.sh. `conveyor.sh take wait`: the same, after a take
# that runs now ends (one with no wait ends at once).
# `conveyor.sh take stale`: the line that says the project runs an old engine here, with no remote read (stalenote()):
# nothing when it does not. The Foreman's start and /units print it.
. "$HERE/lib/prompts.sh" || exit 1
. "$HERE/lib/pick.sh" || exit 1
. "$HERE/lib/run.sh" || exit 1
. "$HERE/lib/machine.sh" || exit 1
. "$HERE/lib/install.sh" || exit 1
case $#:${2:-} in
  1:) take && servicerenew ;;
  2:wait) take wait && servicerenew ;;
  2:stale) stalenote ;;
  *) echo "usage: conveyor.sh take [wait|stale]" >&2; exit 2 ;;
esac
