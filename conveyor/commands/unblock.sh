# SPDX-License-Identifier: Apache-2.0
# `conveyor.sh unblock <issue> --hold`: the Board's Hold on a blocked card of Needs you, sourced by conveyor.sh. Under
# the records' lock, the issue is held (control(), lib/control.sh), then its blocked card is given back as `retry`
# gives it (retry(), lib/issues.sh): its lines move to the retried file and its kept work stays where it is. The card
# leaves Needs you, and the issue is not picked until it is released; the card built then resumes from the kept work.
# The hold comes first, so the loop never picks the issue between the two. A retry that is refused changes nothing:
# the hold is taken off again, unless the issue was held before.
. "$HERE/lib/prompts.sh" || exit 1
. "$HERE/lib/views.sh" || exit 1
. "$HERE/lib/issues.sh" || exit 1
. "$HERE/lib/pick.sh" || exit 1
. "$HERE/lib/followups.sh" || exit 1
. "$HERE/lib/control.sh" || exit 1
. "$HERE/lib/run.sh" || exit 1
. "$HERE/lib/machine.sh" || exit 1
. "$HERE/lib/install.sh" || exit 1
[[ ${2:-} =~ ^[1-9][0-9]{0,8}$ ]] && [ $# = 3 ] && [ "$3" = --hold ] || { echo "usage: conveyor.sh unblock <issue> --hold" >&2; exit 2; }
# Under moved.json's lock: the issue's hold taken off control.json, then its entry put back (movedundo). Both in one
# lock, so a snapshot that reads control.json after the hold is gone writes its sight after the undo, not before it.
unheld() { # <issue> <entry>
  local c new
  c=$(ctl) && new=$(jq -ce --argjson n "$1" '.held -= [$n]' <<<"$c") && ctlput "$c" "$new" && movedundo "$1" "$2"
}
unblock() { # <issue>
  local was m
  was=$(ctl | jq -r --argjson n "$1" '.held | index($n) != null') || { echo "conveyor: cannot read the control record; nothing changed" >&2; return 1; }
  m=$(movedlocked movedheld "$1") || return 1
  # The hold is taken off as it was put on: held alone, and the issue's entry in moved.json (the Board's history) as it
  # was. A release would also mark the issue as released for good (startSeen), so an outside issue no one approved yet
  # would never be held for the owner's yes, and would date a move to Held that never stood.
  retry "$1" >/dev/null || { [ "$was" = true ] || movedlocked unheld "$1" "$m"; return 1; }
  echo "conveyor: issue #$1 is held and its card is off the belt; its kept work is kept. Release it to build it again: conveyor.sh control release $1"
}
locked unblock "$2"
