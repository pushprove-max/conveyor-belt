# SPDX-License-Identifier: Apache-2.0
# `conveyor.sh control [<action>]`: the control record's actions (control(), lib/control.sh), sourced by conveyor.sh.
# depends changes an issue's body on GitHub, not the control record: it takes no lock (depends(), lib/control.sh).
# A seat set to a CLI has that CLI's models read first (hostclis()), outside the lock: a CLI may take seconds to list them.
. "$HERE/lib/prompts.sh" || exit 1
. "$HERE/lib/control.sh" || exit 1
. "$HERE/lib/issues.sh" || exit 1
. "$HERE/lib/pick.sh" || exit 1
. "$HERE/lib/run.sh" || exit 1
. "$HERE/lib/machine.sh" || exit 1
. "$HERE/lib/install.sh" || exit 1
shift; if [ "${1:-}" = depends ]; then shift; depends "$@"
else case ${1:-}:${2:-} in model:* | reviewer:* | judge:* | tests:*) [[ " $CLINAMES " != *" ${2:-} "* ]] || hostclis "$2" >/dev/null ;; esac
  locked control "$@"; fi
