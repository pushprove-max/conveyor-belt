# SPDX-License-Identifier: Apache-2.0
# `conveyor.sh bench responsiveness`: a short command start and a 10 ms CPU task timed beside card work, steered and
# not by turns (bench_responsiveness, lib/busy.sh). Sourced by conveyor.sh.
. "$HERE/lib/slots.sh" || exit 1
. "$HERE/lib/busy.sh" || exit 1
case $#:${2:-} in 2:responsiveness) bench_responsiveness ;; *) echo "usage: conveyor.sh bench responsiveness" >&2; exit 2 ;; esac
