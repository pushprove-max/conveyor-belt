# SPDX-License-Identifier: Apache-2.0
# `conveyor.sh control [<action>]`: the control record's actions (control(), lib/control.sh), sourced by conveyor.sh.
# depends changes an issue's body on GitHub, not the control record: it takes no lock (depends(), lib/control.sh).
# A seat set to a CLI has that CLI's models read first (hostclis()), outside the lock: a CLI may take seconds to list them.
# `card <issue> pick` (Pick for me) asks the judge and changes nothing: no lock either (cardpick(), lib/control.sh).
. "$HERE/lib/prompts.sh" || exit 1
. "$HERE/lib/control.sh" || exit 1
. "$HERE/lib/issues.sh" || exit 1
# A resume puts back the cards a sign-in failure blocked (signinback()): retry reads the records (check()), once
# (startonce()).
. "$HERE/lib/views.sh" || exit 1
. "$HERE/lib/session.sh" || exit 1
. "$HERE/lib/pick.sh" || exit 1
. "$HERE/lib/run.sh" || exit 1
. "$HERE/lib/machine.sh" || exit 1
. "$HERE/lib/install.sh" || exit 1
. "$HERE/lib/slices.sh" || exit 1
# `pick <group> next` reads the challengers (PICKTRIAL, PICKLADDER).
. "$HERE/lib/modelpick.sh" || exit 1
shift; if [ "${1:-}" = depends ]; then shift; depends "$@"
elif [ "${1:-}" = card ] && [ "${3:-}" = pick ]; then
  [ $# = 3 ] && [[ $2 =~ ^[1-9][0-9]{0,8}$ ]] || { echo "usage: conveyor.sh control card <issue> pick" >&2; exit 2; }
  # An OpenCode judge runs as a review does (ocrun(), lib/review.sh, on the cores slot_keepwords() gives, lib/slots.sh).
  . "$HERE/lib/slots.sh" || exit 1
  . "$HERE/lib/review.sh" || exit 1
  cardpick "$2"
else case ${1:-}:${2:-} in model:* | reviewer:* | judge:* | tests:*) [[ " $CLINAMES " != *" ${2:-} "* ]] || hostclis "$2" >/dev/null ;; esac
  locked control "$@"; fi
