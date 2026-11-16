# SPDX-License-Identifier: Apache-2.0
# `conveyor.sh retry <issue | card id>`: a blocked card's issue queued again, or a blocked main-red fix card by its card
# id (retry(), lib/issues.sh), sourced by conveyor.sh. `retry <issue> --fresh` drops the issue's kept work first (moved
# to a dated folder under the state folder): its next card builds from nothing.
. "$HERE/lib/prompts.sh" || exit 1
. "$HERE/lib/views.sh" || exit 1
. "$HERE/lib/issues.sh" || exit 1
. "$HERE/lib/pick.sh" || exit 1
. "$HERE/lib/followups.sh" || exit 1
. "$HERE/lib/control.sh" || exit 1
. "$HERE/lib/run.sh" || exit 1
. "$HERE/lib/machine.sh" || exit 1
. "$HERE/lib/install.sh" || exit 1
[[ ${2:-} =~ ^([0-9]+|c[0-9]{8}T[0-9]{6}-[A-Za-z0-9._-]+-0)$ ]] && { [ $# = 2 ] || { [ $# = 3 ] && [ "$3" = --fresh ] && [[ $2 =~ ^[0-9]+$ ]]; }; } \
  || { echo "usage: conveyor.sh retry <issue> [--fresh] | retry <the card id of a main-red fix card>" >&2; exit 2; }
locked retry "$2" ${3:+fresh}
