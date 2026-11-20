# SPDX-License-Identifier: Apache-2.0
# `conveyor.sh shut <issue | card id>`: the Board's Close, once it has closed the issue: its blocked card is shut now
# (shut(), lib/issues.sh), not at the loop's next turn, which a stopped loop never takes, so it leaves Needs you at once.
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
# A main-red fix card, or a land-branch card of issue 0, which has no issue, is shut by its card id.
if [[ ${2:-} =~ ^c[0-9]{8}T[0-9]{6}-[A-Za-z0-9._-]+-0$ ]]; then locked shut "$2"; exit; fi
[[ ${2:-} =~ ^[0-9]+$ ]] || { echo "usage: conveyor.sh shut <issue | the card id of a main-red fix card or of a land-branch card of issue 0>" >&2; exit 2; }
# The issue's card stuck in flight (its process gone, or no process of its step for the pack's stuck) is ended first,
# blocked with its work kept, outside the lock (unstick(), lib/run.sh), so it is shut as a blocked card is.
unstick "$2"; locked shut "[$2]"
