#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# The in-place write scan finds python wherever the command runs it: behind an
# `env VAR=x` wrapper, and as the reader of a heredoc piped into it.
set -euo pipefail
# This file's own timeout is a GNU call: on macOS it runs Homebrew's, as Conveyor's does (portable.sh).
. "$(dirname "$0")/../../../conveyor/lib/portable.sh"; p_tools

ROOT=$(git rev-parse --show-toplevel)
HOOK=$ROOT/.claude/hooks/bash-guardrails.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib/said.sh" # a FAIL line names the hook's last input

probe() {
  local rc=0
  jq -cn --arg cmd "$1" --arg cwd "$ROOT" \
    '{session_id:"python-consumer-refute",cwd:$cwd,tool_input:{command:$cmd}}' \
    | bash "$HOOK" >/dev/null 2>&1 || rc=$?
  echo "$rc"
}

ENV_CMD="env MODE=test python3 -c \"open('src/x.ts', 'w').write('x')\""
[ "$(probe "$ENV_CMD")" -eq 2 ] || {
  echo "FAIL: env-prefixed Python source write passed$(said)" >&2
  exit 1
}

PIPE_CMD=$'cat <<\'PY\' | python3\nopen(\'src/x.ts\', \'w\').write(\'x\')\nPY'
[ "$(probe "$PIPE_CMD")" -eq 2 ] || {
  echo "FAIL: heredoc piped into Python passed$(said)" >&2
  exit 1
}

# A heredoc piped into something that is not a script runner is still text.
TEXT_CMD=$'cat <<\'TXT\' | wc -l\nopen(\'src/x.ts\', \'w\')\nTXT'
[ "$(probe "$TEXT_CMD")" -eq 0 ] || {
  echo "FAIL: a heredoc piped into wc was refused$(said)" >&2
  exit 1
}

# A redirect target is not a script file: python still runs the heredoc.
REDIR_CMD=$'cat <<\'PY\' | python3 - > /tmp/log\nopen(\'src/x.ts\', \'w\').write(\'x\')\nPY'
[ "$(probe "$REDIR_CMD")" -eq 2 ] || {
  echo "FAIL: heredoc piped into redirected Python passed$(said)" >&2
  exit 1
}

# An assignment whose value holds a slash is still a wrapper assignment.
PATHENV_CMD="env PYTHONPATH=./src python3 -c \"open('src/x.ts', 'w').write('x')\""
[ "$(probe "$PATHENV_CMD")" -eq 2 ] || {
  echo "FAIL: env PYTHONPATH=./src python3 source write passed$(said)" >&2
  exit 1
}

# After `-`, words are sys.argv for the stdin program, not a script file.
ARGS_CMD=$'cat <<\'PY\' | python3 - arg\nopen(\'src/x.ts\', \'w\').write(\'x\')\nPY'
[ "$(probe "$ARGS_CMD")" -eq 2 ] || {
  echo "FAIL: heredoc piped into python3 - arg passed$(said)" >&2
  exit 1
}

# An incomplete `env -u` wrapper must not hang the hook.
rc=0
# timeout runs bash itself, which lib/said.sh's bash function cannot see: said_tee notes the input.
jq -cn '{tool_input:{command:"env -u"}}' | said_tee | timeout 5 bash "$HOOK" >/dev/null 2>&1 || rc=$?
[ "$rc" -ne 124 ] || { echo "FAIL: env -u hung the hook$(said)" >&2; exit 1; }

# Python reading the heredoc as DATA (-c program, stdin.read) is not running it.
DATA_CMD="cat <<'TXT' | python3 -c \"import sys; print(sys.stdin.read())\"
open('src/x.ts', 'w')
TXT"
[ "$(probe "$DATA_CMD")" -eq 0 ] || {
  echo "FAIL: stdin data read by python3 -c was refused$(said)" >&2
  exit 1
}

echo "PASS"
