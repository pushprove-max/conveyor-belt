# SPDX-License-Identifier: Apache-2.0
# `conveyor.sh work [--json]`: the busy processes, by card and step, the heaviest first, and the busy work no card
# owns, of every project of the host file's records (busy_work, lib/busy.sh). Sourced by conveyor.sh.
. "$HERE/lib/busy.sh" || exit 1
. "$HERE/lib/machine.sh" || exit 1
case $#:${2:-} in 1:|2:--json) busy_table 1 | busy_work ${2:+"$2"} ;; *) echo "usage: conveyor.sh work [--json]" >&2; exit 2 ;; esac
