# SPDX-License-Identifier: Apache-2.0
# `conveyor.sh why <pid | name> [--json]`: the process, its parents, and the card, step and project it is of, or that
# no card owns it, of any project of the host file's records (busy_why, lib/busy.sh). Sourced by conveyor.sh.
. "$HERE/lib/busy.sh" || exit 1
. "$HERE/lib/machine.sh" || exit 1
case $#:${3:-} in 2:|3:--json) busy_table 0 | busy_why "$2" ${3:+"$3"} ;; *) echo "usage: conveyor.sh why <pid | name> [--json]" >&2; exit 2 ;; esac
