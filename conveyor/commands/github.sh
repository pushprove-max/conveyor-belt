# SPDX-License-Identifier: Apache-2.0
# `conveyor.sh github <folder>`: what GitHub holds for the snapshot, read into the folder (github(), lib/issues.sh),
# sourced by conveyor.sh. Beside what github() keeps: cardfar, the state of each issue of another repository that a
# waiting card with no GitHub issue names (queuedfar(), lib/snapshot.sh).
. "$HERE/lib/prompts.sh" || exit 1
. "$HERE/lib/control.sh" || exit 1
. "$HERE/lib/issues.sh" || exit 1
. "$HERE/lib/pick.sh" || exit 1
. "$HERE/lib/run.sh" || exit 1
. "$HERE/lib/push.sh" || exit 1
. "$HERE/lib/machine.sh" || exit 1
. "$HERE/lib/install.sh" || exit 1
. "$HERE/lib/testaction.sh" || exit 1
. "$HERE/lib/snapshot.sh" || exit 1
names || exit 1
[ -d "${2:-}" ] || { echo "usage: conveyor.sh github <folder>" >&2; exit 2; }
# shellcheck disable=SC2034 # GITHUB is read in lib/issues.sh and lib/control.sh
GITHUB=''; github "$2"
queuedfarkeep "$2"
