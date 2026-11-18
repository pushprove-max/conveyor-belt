# SPDX-License-Identifier: Apache-2.0
# `conveyor.sh github <folder>`: what GitHub holds for the snapshot, read into the folder (github(), lib/issues.sh),
# sourced by conveyor.sh.
. "$HERE/lib/prompts.sh" || exit 1
. "$HERE/lib/control.sh" || exit 1
. "$HERE/lib/issues.sh" || exit 1
. "$HERE/lib/pick.sh" || exit 1
. "$HERE/lib/run.sh" || exit 1
. "$HERE/lib/push.sh" || exit 1
. "$HERE/lib/machine.sh" || exit 1
. "$HERE/lib/install.sh" || exit 1
names || exit 1
[ -d "${2:-}" ] || { echo "usage: conveyor.sh github <folder>" >&2; exit 2; }
# shellcheck disable=SC2034 # GITHUB is read in lib/issues.sh and lib/control.sh
GITHUB=''; github "$2"
