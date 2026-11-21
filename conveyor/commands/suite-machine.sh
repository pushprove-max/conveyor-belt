# SPDX-License-Identifier: Apache-2.0
# `conveyor.sh suite-machine check [--json]`: what the machine a release's suite runs on has (hostcheck(),
# lib/suitehost.sh), sourced by conveyor.sh.
. "$HERE/lib/slots.sh" || exit 1
. "$HERE/lib/prompts.sh" || exit 1
. "$HERE/lib/control.sh" || exit 1
. "$HERE/lib/suitehost.sh" || exit 1
shift
case $* in check) hostcheck ;; "check --json") hostcheck json ;; *) echo "usage: conveyor.sh suite-machine check [--json]" >&2; exit 2 ;; esac
