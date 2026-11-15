#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# testbrief.sh -- <command>...: runs a test command once for a card session, writes its whole output (stdout and stderr)
# to a log file, and prints only a short brief: the lines that tell of a failure, each with its line number in the log
# (at most 40), the last 10 lines of the log (where test runners put their summary), and the log's path. It exits with
# the command's exit code. A big test log printed whole stays in every later turn of the session (issue #540), so the
# session reads the brief and then only the lines of the log it needs. The command guard
# (.claude/hooks/bash-guardrails.sh) runs a card session's test command through it when the session did not.
[ $# -ge 2 ] && [ "$1" = -- ] || { echo "usage: testbrief.sh -- <command>..." >&2; exit 2; }
shift
log=$(mktemp "${TMPDIR:-/tmp}/testbrief.XXXXXX") || exit 1
"$@" > "$log" 2>&1
rc=$?
# Each runner's own word for a failed case or an error: the engine's and the hooks' FAIL, TAP's `not ok`, node's ✖,
# pytest's FAILED, E lines and Traceback, jest's and vitest's FAIL, ✗, × and ●, and a shell's or Python's Error.
pat='(^|[^[:alnum:]_])(FAIL|FAILED|not ok|ERROR|[A-Za-z]*Error:|Traceback)([^[:alnum:]_]|$)|✖|✗|×|●|^E {3}'
n=$(grep -cE "$pat" "$log")
lines=$(wc -l < "$log" | tr -d ' ')
if [ "$n" -gt 0 ]; then
  echo "testbrief: $n line(s) of failure in the log, with their line numbers:"
  grep -nE "$pat" "$log" | head -n 40 | cut -c 1-400
  [ "$n" -le 40 ] || echo "testbrief: ... $((n - 40)) more in the log"
fi
echo "testbrief: the last lines of the log:"
tail -n 10 "$log" | cut -c 1-400
echo "testbrief: exit $rc; the whole output ($lines lines) is in $log; read a part of it by line range, or search it."
exit $rc
