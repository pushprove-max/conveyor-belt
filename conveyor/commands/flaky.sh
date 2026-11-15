# SPDX-License-Identifier: Apache-2.0
# `conveyor.sh flaky add | off <case> <source> <note>`: a case that failed and then passed when run again, from outside
# a card; off adds it and files no issue (flaky(), lib/flaky.sh). Sourced by conveyor.sh.
. "$HERE/lib/prompts.sh" || exit 1
. "$HERE/lib/control.sh" || exit 1
. "$HERE/lib/issues.sh" || exit 1
. "$HERE/lib/pick.sh" || exit 1
. "$HERE/lib/flaky.sh" || exit 1
. "$HERE/lib/run.sh" || exit 1
. "$HERE/lib/machine.sh" || exit 1
. "$HERE/lib/install.sh" || exit 1
names || exit 1
[[ ${2:-} =~ ^(add|off)$ ]] && [ $# = 5 ] && [ -n "$3" ] && [ -n "$4" ] || { echo "usage: conveyor.sh flaky add <case> <source> <note> | flaky off <case> <source> <note>" >&2; exit 2; }
flaky "$4" "$(jq -cn --arg c "$3" --arg n "$5" '[{case: $c, note: $n}]')" "$([ "$2" = off ] && echo nofile)"
