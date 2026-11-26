# SPDX-License-Identifier: Apache-2.0
# `conveyor.sh heals sort | heals batch <area | -> [--held | --queue] [--prio P2|P3] [--title <text>] [<id>...] | heals docs <area | ->
# [the same] | heals harm <id>... | heals drop <id>... | heals areas`:
# the self-heals list and the docs list (lib/heals.sh). sort: the queued follow-up cards and open finding issues sorted
# by the judge's kinds (healssort()); batch: one audit card for an area's entries of the self-heals list (healsbatch(),
# the Board's Self-heals panel); docs: one docs sweep card for an area's entries of the docs list (the Board's Docs
# list); harm: entries moved up to harm, each filed as its own follow-up (healsharm(), the Board's Self-heals page);
# drop: entries taken off the list now (healsdiscard()); areas: the one pass that gives the entries and the open issues
# with no area the area of the file they name, from the pack's path-to-area map (healsareas(), lib/areas.sh). Sourced by conveyor.sh.
. "$HERE/lib/slots.sh" || exit 1
. "$HERE/lib/prompts.sh" || exit 1
. "$HERE/lib/control.sh" || exit 1
. "$HERE/lib/issues.sh" || exit 1
. "$HERE/lib/pick.sh" || exit 1
. "$HERE/lib/session.sh" || exit 1
. "$HERE/lib/review.sh" || exit 1
. "$HERE/lib/followups.sh" || exit 1
. "$HERE/lib/testaction.sh" || exit 1
. "$HERE/lib/redfix.sh" || exit 1 # redissue(): the parent of an entry a main-red fix card listed (healsred())
. "$HERE/lib/heals.sh" || exit 1
. "$HERE/lib/run.sh" || exit 1
. "$HERE/lib/machine.sh" || exit 1
. "$HERE/lib/install.sh" || exit 1
names || exit 1
case ${2:-}:$# in sort:2) healssort ;; batch:[3-9]|batch:[1-9][0-9]*) healsbatch "$3" '' "${@:4}" ;; docs:[3-9]|docs:[1-9][0-9]*) healsbatch "$3" docs "${@:4}" ;;
  harm:*) healsharm "${@:3}" ;; drop:*) healsdiscard "${@:3}" ;; areas:2) healsareas ;;
  *) echo "usage: conveyor.sh heals sort | heals batch <area | -> [--held | --queue] [--prio P2|P3] [--title <text>] [<id>...] | heals docs <area | -> [the same] | heals harm <id>... | heals drop <id>... | heals areas" >&2; exit 2 ;; esac
