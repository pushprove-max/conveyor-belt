# SPDX-License-Identifier: Apache-2.0
# `conveyor.sh gh-write <gh arguments>`: the Board's GitHub writes (plan section 8, P5), through the engine's one
# privacy gate (gh_write(), lib/issues.sh). Sourced by conveyor.sh.
. "$HERE/lib/prompts.sh" || exit 1
. "$HERE/lib/issues.sh" || exit 1
. "$HERE/lib/pick.sh" || exit 1
. "$HERE/lib/run.sh" || exit 1
. "$HERE/lib/machine.sh" || exit 1
. "$HERE/lib/install.sh" || exit 1
shift; [ $# -gt 0 ] || { echo "usage: conveyor.sh gh-write <gh arguments>" >&2; exit 2; }; gh_write "$@"
