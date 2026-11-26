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
  # `hold` and `release` of card ids of cards with no GitHub issue, alone or with issue numbers (testcardact(),
  # lib/testcardact.sh). A list with an argument that is neither is refused before any card is changed, naming it, as is
  # a card id that is no waiting card (a main-red fix card's, a picked card's, a card not held, to release).
  tcact=${1:-}; tcids=(); tcnums=()
  if [ "$tcact" = hold ] || [ "$tcact" = release ]; then
    for tcx in "${@:2}"; do if [[ $tcx =~ ^c[0-9]{8}T[0-9]{6}-[A-Za-z0-9._-]+-0$ ]]; then tcids+=("$tcx"); else tcnums+=("$tcx"); fi; done
  fi
  if [ ${#tcids[@]} != 0 ]; then
    for tcx in "${tcnums[@]}"; do [[ $tcx =~ ^[1-9][0-9]{0,8}$ ]] || { echo "conveyor: control $tcact: \"$tcx\" is neither an issue number nor a card id of a card with no GitHub issue; nothing changed" >&2; exit 2; }; done
    . "$HERE/lib/testaction.sh" || exit 1
    . "$HERE/lib/testcardact.sh" || exit 1
    testcardact "$tcact" "${tcids[@]}" || exit $?
    # The loop's wait ends, so its next turn reads the record now. With issue numbers, control() wakes it once it has
    # saved their hold or release: a wake before that could let the woken pick take an issue this holds. A control
    # that fails still wakes it here, for the cards changed above.
    if [ ${#tcnums[@]} = 0 ]; then wakeloop; exit 0; fi
    locked control "$tcact" "${tcnums[@]}" && exit 0
    tcrc=$?; wakeloop; exit "$tcrc"
  fi
  locked control "$@"; fi
