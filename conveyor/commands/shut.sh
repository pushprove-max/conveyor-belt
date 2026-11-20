# SPDX-License-Identifier: Apache-2.0
# `conveyor.sh shut <issue | card id>`: the Board's Close, once it has closed the issue: its blocked card is shut now
# (shut(), lib/issues.sh), not at the loop's next turn, which a stopped loop never takes, so it leaves Needs you at once.
# Also the owner's stop of an open card. It prints what it did; when it did nothing, it says why and exits 1.
# Sourced by conveyor.sh.
. "$HERE/lib/prompts.sh" || exit 1
. "$HERE/lib/views.sh" || exit 1
. "$HERE/lib/issues.sh" || exit 1
. "$HERE/lib/pick.sh" || exit 1
# What block() and gonewt() need, to end a card stuck in flight first (unstick(), lib/run.sh).
. "$HERE/lib/session.sh" || exit 1
. "$HERE/lib/review.sh" || exit 1
. "$HERE/lib/testrun.sh" || exit 1
. "$HERE/lib/claim.sh" || exit 1
. "$HERE/lib/push.sh" || exit 1
. "$HERE/lib/followups.sh" || exit 1
. "$HERE/lib/run.sh" || exit 1
. "$HERE/lib/machine.sh" || exit 1
. "$HERE/lib/install.sh" || exit 1
# An open card (#1030), the issue's or the one named by its card id, is ended first, whatever its step: its processes
# ended and the card blocked with its work kept, outside the lock (shutopen(), lib/run.sh), so it is shut as a blocked
# card is. A main-red fix card, or a land-branch card of issue 0, which has no issue, is shut by its card id; so is
# any other card. The cards it ended are passed to shut() by id, so each is closed as the owner's stop even when the
# loop blocked it first, with its own reason, once its process was killed.
[[ ${2:-} =~ ^(c[0-9]{8}T[0-9]{6}-[A-Za-z0-9._-]+-[0-9]+|[0-9]+)$ ]] || { echo "usage: conveyor.sh shut <issue | card id>" >&2; exit 2; }
ended=$(shutopen "$2"); [ -z "$ended" ] || echo "$ended"
own=$(sed -n 's/^conveyor: card \([^ ]*\) was open .*/\1/p' <<<"$ended" | jq -Rsc 'split("\n") - [""]') || exit 1
if [[ $2 =~ ^[0-9]+$ ]]; then closed=$(locked shut "[$2]" "$own") || exit 1; else locked shut "$2" "$own"; exit; fi
[ -z "$closed" ] || echo "$closed"
[ -z "$ended$closed" ] || exit 0
# Nothing shut: why is said, and the exit is 1.
why=$(stdb ask issue cards "$2" | jq -rs --argjson n "$2" --arg shut "$SHUT" --arg own "$OWNSHUT" 'map(select(.issue == $n))
  | if length == 0 then "has no card"
    elif any(.step | IN("landed", "pushed")) or any(.step == "closed" and (.reason | IN($shut, $own) | not)) then "has a card that landed, or that closed it as already fixed"
    elif any(.step == "closed") then "has a card that was shut already: `conveyor.sh retry \($n)` takes it again"
    else "has no open card that shut can stop and no blocked card" end') || exit 1
echo "conveyor: issue #$2 $why; nothing changed" >&2; exit 1
