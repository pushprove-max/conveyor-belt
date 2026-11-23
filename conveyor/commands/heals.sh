# SPDX-License-Identifier: Apache-2.0
# `conveyor.sh heals sort | heals batch <area | ->`: the self-heals list (lib/heals.sh). sort: the queued follow-up
# cards and open finding issues sorted by harm or self-heals (healssort()); batch: one audit card for an area's
# entries (healsbatch(), the Board's Self-heals panel). Sourced by conveyor.sh.
. "$HERE/lib/slots.sh" || exit 1
. "$HERE/lib/prompts.sh" || exit 1
. "$HERE/lib/control.sh" || exit 1
. "$HERE/lib/issues.sh" || exit 1
. "$HERE/lib/pick.sh" || exit 1
. "$HERE/lib/session.sh" || exit 1
. "$HERE/lib/review.sh" || exit 1
. "$HERE/lib/followups.sh" || exit 1
. "$HERE/lib/testaction.sh" || exit 1
. "$HERE/lib/heals.sh" || exit 1
. "$HERE/lib/run.sh" || exit 1
. "$HERE/lib/machine.sh" || exit 1
. "$HERE/lib/install.sh" || exit 1
names || exit 1
case ${2:-}:$# in sort:2) healssort ;; batch:3) healsbatch "$3" ;;
  *) echo "usage: conveyor.sh heals sort | heals batch <area | ->" >&2; exit 2 ;; esac
