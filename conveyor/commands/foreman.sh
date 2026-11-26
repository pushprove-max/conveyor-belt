# SPDX-License-Identifier: Apache-2.0
# `conveyor.sh foreman [<claude argument>...]`: Foreman mode (foreman/foreman.sh): `claude` in the main checkout with
# CONVEYOR_FOREMAN=1 and the Foreman's settings (MAIN, lib/paths.sh, which conveyor.sh loads). Sourced by conveyor.sh.
# `conveyor.sh foreman status [<project>]`: the state of the Foreman's records as short plain text
# (foreman/watch-conveyor.sh --status).
# `conveyor.sh foreman note ...`: the Foreman's notes on this record's blocked cards (commands/foreman-note.sh).
shift
[ "${1:-}" != status ] || { shift; CONVEYOR_MAIN=$MAIN exec bash "$HERE/foreman/watch-conveyor.sh" --status "$@"; }
[ "${1:-}" != note ] || { shift; . "$HERE/commands/foreman-note.sh"; exit; }
CONVEYOR_MAIN=$MAIN exec bash "$HERE/foreman/foreman.sh" launch "$@"
