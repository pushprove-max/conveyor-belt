#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# The decision-log tests' fixture. Sourced. Makes, under a fresh temp folder $T: a copy of the plugin ($PLUG, its own
# git repo, as an install is), a project main checkout ($MAIN, whose Board ledger is $LEDGER) with one linked
# worktree ($CARD, a card session), and a host file naming the state folder ($T/state) and the id prefix q. The log
# is $LOG. Removes $T on exit.
SRC=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
PLUG=$T/plugin MAIN=$T/main CARD=$T/card LOG=$T/state/foreman/rulings.jsonl LEDGER=$T/main/.claude/metrics/decisions.jsonl
mkdir -p "$PLUG/.claude" "$T/config/conveyor" "${LOG%/*}"
cp -r "$SRC/conveyor" "$PLUG/conveyor"; cp -r "$SRC/.claude/hooks" "$SRC/.claude/scripts" "$PLUG/.claude/"
git -C "$PLUG" init -q
git init -q "$MAIN" && git -C "$MAIN" -c user.email= -c user.name=t commit -q --allow-empty -m init
git -C "$MAIN" worktree add -q "$CARD" -b card
jq -n --arg s "$T/state" '{stateDir: $s, rulingPrefix: "q"}' > "$T/config/conveyor/host.json"
export XDG_CONFIG_HOME=$T/config
unset CLAUDE_PROJECT_DIR CONVEYOR_MAIN
PASS=0 FAIL=0
check() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); echo "ok   $1"; else FAIL=$((FAIL+1)); echo "FAIL $1 (expected $2, got $3)"; fi }
finish() { echo; echo "$PASS passed, $FAIL failed"; [ "$FAIL" -eq 0 ]; }
