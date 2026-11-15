#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Usage: ruling-id.sh "<verbatim phrase>"
# Prints the decision-log id, time and pick of every logged question, answer or typed message containing the phrase (any
# case), so a note can cite ruling:<id> for something the owner said. Exits 1 when nothing matches.
# A void row (machine text) is never the owner's word and never printed.
# The log is written by .claude/hooks/ruling-log.sh; .claude/hooks/lib/rulings.sh names it.
. "${BASH_SOURCE[0]%/*}/../hooks/lib/rulings.sh"
[ -n "${1:-}" ] || { echo "usage: ruling-id.sh \"<verbatim phrase>\"" >&2; exit 2; }
LOG=$(rulings_log) || { echo "ruling-id: the state folder cannot be named (conveyor.sh state-dir failed)" >&2; exit 1; }
[ -f "$LOG" ] || { echo "no ruling log at $LOG" >&2; exit 1; }
# A damaged line is skipped and counted, never fatal: one bad row must not hide every ruling after it.
# "\u0001" marks a skipped line; no printed ruling line can be that alone.
jq -rR --arg p "$1" '
  select(test("\\S")) | [fromjson?] | if length == 0 then "\u0001" else .[0]
  | select(type == "object" and (.void | not))
  | select(([.question, .answer] | map(. // "" | ascii_downcase) | join("\n")) | contains($p | ascii_downcase))
  | "\(.id)  \(.time)  (\(.pick))  \(.answer | .[0:80] | gsub("\n"; " "))" end' "$LOG" |
  awk -v f="$LOG" '$0 == "\001" { s++; next } { print; n++ }
    END { if (s) printf "ruling-id: skipped %d unreadable line(s) in %s\n", s, f > "/dev/stderr"; exit n ? 0 : 1 }'
