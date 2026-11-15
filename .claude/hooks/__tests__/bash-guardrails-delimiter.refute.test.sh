#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# A heredoc delimiter is the whole word (`PY-CODE`), not its identifier prefix;
# a truncated one never closes, and the in-place write scan then misreads every
# later line: a harmless echo is refused, and a real write after a non-python
# heredoc passes.
set -euo pipefail
ROOT=$(git rev-parse --show-toplevel)
probe() { local RC=0; jq -cn --arg cmd "$1" '{session_id:"delimiter-refute",tool_input:{command:$cmd}}' | bash "$ROOT/.claude/hooks/bash-guardrails.sh" >/dev/null 2>&1 || RC=$?; echo "$RC"; }
CMD=$'python3 - <<\'PY-CODE\'\nprint(1)\nPY-CODE\necho "open(\'src/x.ts\', \'w\')"'
[ "$(probe "$CMD")" -eq 0 ] || { echo "FAIL: harmless echo after a python heredoc was refused"; exit 1; }
CMD=$'cat > /tmp/conveyor/note <<\'TEXT-END\'\nhello\nTEXT-END\npython3 -c "open(\'src/x.ts\', \'w\').write(\'x\')"'
[ "$(probe "$CMD")" -eq 2 ] || { echo "FAIL: a source write after a cat heredoc passed"; exit 1; }
echo PASS
