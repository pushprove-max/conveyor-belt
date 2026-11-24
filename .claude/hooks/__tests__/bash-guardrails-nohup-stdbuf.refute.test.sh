#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# `nohup python3 -c` and `stdbuf -o L python3 -c` are wrapped pythons: the inline
# script check must look past both wrappers, called by name or by path, and
# stdbuf's separate mode word after a short or a shortened long option
# (`--out L`), or a source write in the script passes the in-place write guard. Behind them, `env -C DIR` runs the
# script in DIR, so its relative paths are judged from there.
set -euo pipefail

ROOT=$(git rev-parse --show-toplevel)
HOOK=$ROOT/.claude/hooks/bash-guardrails.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib/said.sh" # a FAIL line names the hook's last input

FAILED=0
W="python3 -c \"open('src/a.ts','w')\""
for CMD in "nohup $W" "stdbuf -o L $W" "/usr/bin/nohup $W" "/usr/bin/stdbuf --out L $W"; do
  RC=0
  jq -cn --arg cmd "$CMD" --arg cwd "$ROOT" \
    '{session_id:"nohup-stdbuf-refute",cwd:$cwd,tool_input:{command:$cmd}}' \
    | bash "$HOOK" >/dev/null 2>&1 || RC=$?
  [ "$RC" -eq 2 ] || { echo "FAIL: wrapped Python source write passed with $RC for: $CMD$(said)" >&2; FAILED=1; }
done
# `env -C .claude` runs Python inside a source folder: the script's relative `hooks/x.sh` is .claude/hooks/x.sh. The
# check stopped at the folder word, so no script was found, with or without a wrapper in front. In the last two cases
# a heredoc body reaches two Pythons in a pipe, either of which can run it, so it is judged from each one's folder: one
# folder only made `src/x.ts` look like /tmp/src/x.ts, or `hooks/x.sh` look like /tmp/hooks/x.sh when the first
# Python copies the body to a second in .claude.
E="env -C .claude python3 -c \"open('hooks/x.sh','w')\""
for CMD in "$E" "nohup $E" "stdbuf -o L $E" "/usr/bin/nohup env --chdir=.claude python3 -c \"open('hooks/x.sh','w')\"" \
  "env -C .claude python3 <<'EOF'
open('hooks/x.sh','w')
EOF" \
  "python3 - <<'EOF' | env -C /tmp python3 -
open('src/x.ts','w')
EOF" \
  "env -C /tmp python3 -c 'import sys; print(sys.stdin.read())' <<'EOF' | env -C .claude python3 -
open('hooks/x.sh','w')
EOF"; do
  RC=0
  jq -cn --arg cmd "$CMD" --arg cwd "$ROOT" \
    '{session_id:"nohup-stdbuf-refute",cwd:$cwd,tool_input:{command:$cmd}}' \
    | bash "$HOOK" >/dev/null 2>&1 || RC=$?
  [ "$RC" -eq 2 ] || { echo "FAIL: env -C Python source write passed with $RC for: $CMD$(said)" >&2; FAILED=1; }
done
# The folder is what makes the path a source path: the same script in /tmp is scratch, and a redirect on the segment
# is the shell's, written in the shell's folder, not in the env -C folder. A script's path is judged from its own
# folder only: `x.sh` and `src/x.ts` written in /tmp are scratch, even beside a script in .claude, and are not
# judged again from the shell's folder.
for CMD in "nohup env -C /tmp python3 -c \"open('hooks/x.sh','w')\"" "env -C .claude python3 -c 'print(1)' > hooks/x.txt" \
  "env -C .claude python3 -c 'print(1)' && env -C /tmp python3 -c \"open('x.sh','w')\"" \
  "env -C /tmp python3 -c \"open('src/x.ts','w')\""; do
  RC=0
  jq -cn --arg cmd "$CMD" --arg cwd "$ROOT" \
    '{session_id:"nohup-stdbuf-refute",cwd:$cwd,tool_input:{command:$cmd}}' \
    | bash "$HOOK" >/dev/null 2>&1 || RC=$?
  [ "$RC" -eq 0 ] || { echo "FAIL: env -C Python with no source write refused with $RC for: $CMD$(said)" >&2; FAILED=1; }
done
[ "$FAILED" = 0 ] || exit 1
echo "PASS"
