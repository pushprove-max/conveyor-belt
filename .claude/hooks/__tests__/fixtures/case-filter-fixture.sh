#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Three dummy checks and a `w`-style wrapper row behind the shared case filter (lib/case-filter.sh), for the
# case_filter_runs_only_matching checks in bash-guardrails-refusals.test.sh. Every check passes; a selector decides which run.
. "$(dirname "${BASH_SOURCE[0]}")/../lib/case-filter.sh"
cf_refuse_empty
PASS=0 FAIL=0 ON=1 HITS=$(mktemp); trap 'rm -f "$HITS"' EXIT
[ -z "${CONVEYOR_SHELL_TEST_CASE+x}" ] || cf_install "$HITS"
check() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); echo "ok   $1"; else FAIL=$((FAIL+1)); echo "FAIL $1 (expected $2, got $3)"; fi }
w() { check "wrapped: $1" 1 1; }

check "group_a: first check" 1 1
check "group_a: second check" 1 1
check "group_b: third check" 1 1
w "fourth row"
trap - DEBUG  # cf_missed's body holds the word check, so the filter would skip it

echo "$PASS passed, $FAIL failed"
[ -z "${CONVEYOR_SHELL_TEST_CASE+x}" ] || cf_missed "$HITS" || exit 2
[ "$FAIL" -eq 0 ]
