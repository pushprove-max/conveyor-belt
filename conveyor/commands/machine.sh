# SPDX-License-Identifier: Apache-2.0
# `conveyor.sh machine [pause | resume]`: the machine's Conveyor
# (lib/machine.sh), sourced by conveyor.sh.
. "$HERE/lib/prompts.sh" || exit 1
. "$HERE/lib/pick.sh" || exit 1
. "$HERE/lib/run.sh" || exit 1
. "$HERE/lib/machine.sh" || exit 1
. "$HERE/lib/install.sh" || exit 1
case $#:${2:-} in 1:) machineloop ;; 2:pause|2:resume) mlocked machinemode "$2" ;; *) echo "usage: conveyor.sh machine [pause | resume]" >&2; exit 2 ;; esac
