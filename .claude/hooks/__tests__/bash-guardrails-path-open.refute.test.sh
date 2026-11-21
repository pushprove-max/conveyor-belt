#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# A pathlib `Path(...).open("w")` writes a source file in place and skips every
# Edit/Write hook, exactly as `open(path, "w")` does, so the in-place write guard
# refuses it too.
set -euo pipefail

ROOT=$(git rev-parse --show-toplevel)
HOOK=$ROOT/.claude/hooks/bash-guardrails.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib/said.sh" # a FAIL line names the hook's last input
CMD="python3 -c \"from pathlib import Path; Path('src/x.ts').open('w').write('x')\""

set +e
jq -cn --arg cmd "$CMD" --arg cwd "$ROOT" \
  '{session_id:"path-open-refute",cwd:$cwd,tool_input:{command:$cmd}}' \
  | bash "$HOOK" >/dev/null 2>&1
RC=$?
set -e

[ "$RC" -eq 2 ] || {
  echo "FAIL: Path.open write should be refused, got $RC$(said)" >&2
  exit 1
}
echo "PASS"
