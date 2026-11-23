# SPDX-License-Identifier: Apache-2.0
# `conveyor.sh heals sort | heals batch <area | -> | heals docs <area | ->`: the self-heals list and the docs list
# (lib/heals.sh). sort: the queued follow-up cards and open finding issues sorted by the judge's kinds (healssort());
# batch: one audit card for an area's entries of the self-heals list (healsbatch(), the Board's Self-heals panel);
# docs: one docs sweep card for an area's entries of the docs list (the Board's Docs list). Sourced by conveyor.sh.
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
case ${2:-}:$# in sort:2) healssort ;; batch:3) healsbatch "$3" ;; docs:3) healsbatch "$3" docs ;;
  *) echo "usage: conveyor.sh heals sort | heals batch <area | -> | heals docs <area | ->" >&2; exit 2 ;; esac
