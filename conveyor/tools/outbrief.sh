#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# outbrief.sh <output file> <exit code>: prints a card session's command output, saved whole in <output file>, and
# exits with <exit code>. Output of 8,000 characters or less prints whole, and the file is removed. Longer output prints
# its first 60 lines, the number of lines left out, its last 40 lines (each cut at 400 characters) and the file's path,
# and the file is kept for the session to read by line range or search. A long result stays in every later turn of the
# session (issue #543). The command guard (.claude/hooks/bash-guardrails.sh) runs a card session's non-test call with
# its output in the file, then this.
[ $# = 2 ] && [ -f "$1" ] && [[ $2 =~ ^[0-9]+$ ]] || { echo "usage: outbrief.sh <output file> <exit code>" >&2; exit 2; }
out=$1 rc=$2
chars=$(wc -c < "$out" | tr -d ' ')
if [ "$chars" -le 8000 ]; then
  cat "$out"; rm -f "$out"; exit "$rc"
fi
lines=$(awk 'END { print NR }' "$out")
if [ "$lines" -gt 100 ]; then
  head -n 60 "$out" | cut -c 1-400
  echo "outbrief: ... $((lines - 100)) line(s) left out; lines 61 to $((lines - 40)) are in the file below ..."
  tail -n 40 "$out" | cut -c 1-400
else
  cut -c 1-400 "$out"
fi
echo "outbrief: exit $rc; the whole output ($lines lines, $chars characters) is in $out; lines here are cut at 400 characters; read a part of it by line range, or search it. To print a call whole, put CONVEYOR_WHOLE=1 in it."
exit "$rc"
