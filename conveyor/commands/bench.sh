# SPDX-License-Identifier: Apache-2.0
# `conveyor.sh bench responsiveness`: a short command start and a 10 ms CPU task timed beside card work, steered and
# not by turns (bench_responsiveness, lib/busy.sh). `conveyor.sh bench drift [<engine commit>]`: the cards of an engine
# commit against those of the one before it, from the card records and the retried file (bench/drift.sh). Sourced by
# conveyor.sh.
. "$HERE/lib/slots.sh" || exit 1
. "$HERE/lib/busy.sh" || exit 1
benchdrift() { # [<engine commit>]
  local f rc
  f=$(mktemp) || return 1
  { stdb ask lines cards && stdb ask lines retried; } > "$f" || { rm -f "$f"; echo "conveyor: bench drift: the card records could not be read" >&2; return 1; }
  "$HERE/bench/drift.sh" "$f" "$@"; rc=$?; rm -f "$f"; return $rc
}
case $#:${2:-} in
  2:responsiveness) bench_responsiveness ;;
  2:drift) benchdrift ;;
  3:drift) benchdrift "$3" ;;
  *) echo "usage: conveyor.sh bench responsiveness | bench drift [<engine commit>]" >&2; exit 2 ;;
esac
