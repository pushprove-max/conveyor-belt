# SPDX-License-Identifier: Apache-2.0
# `conveyor.sh control [<action>]`: the control record's actions (control(), lib/control.sh), sourced by conveyor.sh.
# depends changes an issue's body on GitHub, not the control record: it takes no lock (depends(), lib/control.sh).
# A seat set to a CLI has that CLI's models read first (hostclis()), outside the lock: a CLI may take seconds to list them.
# `card <issue> pick` (Pick for me) asks the judge and changes nothing: no lock either (cardpick(), lib/control.sh).
. "$HERE/lib/prompts.sh" || exit 1
. "$HERE/lib/control.sh" || exit 1
. "$HERE/lib/issues.sh" || exit 1
# A resume puts back the cards a sign-in failure blocked (signinback()): retry reads the records (check()), once
# (startonce()), and gives a shut self-heals batch card its entries back (healstake(), lib/followups.sh).
. "$HERE/lib/followups.sh" || exit 1
. "$HERE/lib/views.sh" || exit 1
. "$HERE/lib/session.sh" || exit 1
. "$HERE/lib/pick.sh" || exit 1
. "$HERE/lib/run.sh" || exit 1
. "$HERE/lib/machine.sh" || exit 1
. "$HERE/lib/install.sh" || exit 1
. "$HERE/lib/slices.sh" || exit 1
# `pick <group> next` reads the challengers (PICKTRIAL, PICKLADDER).
. "$HERE/lib/modelpick.sh" || exit 1
# A card's reviewer and judge seats and Pick for me check models against the host's report (modelsallowed()), whose
# only list a CLI gives is Codex's: Codex is read afresh first, so a model it took on since the last report is not refused.
cardclis() { ! command -v codex >/dev/null || hostclis codex >/dev/null; }
shift; if [ "${1:-}" = depends ]; then shift; depends "$@"
elif [ "${1:-}" = card ] && [ "${3:-}" = pick ]; then
  [ $# = 3 ] && [[ $2 =~ ^[1-9][0-9]{0,8}$ ]] || { echo "usage: conveyor.sh control card <issue> pick" >&2; exit 2; }
  cardclis
  # An OpenCode judge runs as a review does (ocrun(), lib/review.sh, on the cores slot_keepwords() gives, lib/slots.sh).
  . "$HERE/lib/slots.sh" || exit 1
  . "$HERE/lib/review.sh" || exit 1
  cardpick "$2"
else case ${1:-}:${2:-} in model:* | reviewer:* | judge:* | tests:*) [[ " $CLINAMES " != *" ${2:-} "* ]] || hostclis "$2" >/dev/null ;; esac
  # A builder seat is not refreshed: its Codex list is codex-builder's (lib/paths.sh), which this refresh does not read.
  case ${1:-}:${3:-}:${4:-} in card:reviewer:?* | card:judge:?*) [ "$4" = clear ] || cardclis ;; esac
  # `release <card id>` of a held card with no GitHub issue (testrelease(), lib/testaction.sh); any other card id is
  # refused by control() as before.
  if [ "${1:-}" = release ] && [ $# = 2 ] && [[ $2 =~ ^c[0-9]{8}T[0-9]{6}-[A-Za-z0-9._-]+-0$ ]]; then
    . "$HERE/lib/testaction.sh" || exit 1
    testrelease "$2"; rc=$?; [ "$rc" = 3 ] || exit "$rc"
  fi
  locked control "$@"; fi
