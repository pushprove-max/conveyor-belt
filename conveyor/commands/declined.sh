# SPDX-License-Identifier: Apache-2.0
# `conveyor.sh declined add <card> <issue> <code | judge | owner> <why> <finding> [<kind>] | declined build <id> | declined
# dismiss [--by <who>] <id>...`: the declined list (lib/followups.sh), sourced by conveyor.sh.
. "$HERE/lib/prompts.sh" || exit 1
. "$HERE/lib/control.sh" || exit 1
. "$HERE/lib/issues.sh" || exit 1
. "$HERE/lib/pick.sh" || exit 1
. "$HERE/lib/followups.sh" || exit 1
. "$HERE/lib/run.sh" || exit 1
. "$HERE/lib/machine.sh" || exit 1
. "$HERE/lib/install.sh" || exit 1
case ${2:-}:$# in add:7 | add:8) declined "${@:3}" ;; build:3) declinedbuild "$3" ;; dismiss:*) declineddismiss "${@:3}" ;;
  *) echo "usage: conveyor.sh declined add <card> <issue> <code | judge | owner> <why> <finding> [<kind>] | declined build <id> | declined dismiss [--by <who>] <id>..." >&2; exit 2 ;; esac
