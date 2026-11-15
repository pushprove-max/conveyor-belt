#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
set -eu

HOOK="$(cd "$(dirname "$0")/.." && pwd)/suite-rerun-guard.sh"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

git init -q "$TMP/repo"
git -C "$TMP/repo" -c user.name=Test -c user.email=test@noreply.example.com \
  -c core.hooksPath=/dev/null commit -q --allow-empty -m fixture
git -C "$TMP/repo" -c core.hooksPath=/dev/null \
  worktree add -q --detach "$TMP/wt" HEAD
mkdir -p "$TMP/wt/web"
export CONVEYOR_SUITE_RUNS_DIR="$TMP/state"
PASS=0 FAIL=0

check() {
  local expected=$1 command=$2 actual=0
  jq -cn --arg command "$command" --arg cwd "$TMP/wt" \
    '{tool_input:{command:$command},cwd:$cwd}' |
    bash "$HOOK" >/dev/null 2>&1 || actual=$?
  if [ "$actual" -eq "$expected" ]; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    printf 'FAIL expected=%s actual=%s: %s\n' \
      "$expected" "$actual" "$command"
  fi
}

# The integrity wrapper ignores positional filename arguments.
check 2 'npm --prefix web run test:unit -- src/a.test.tsx'
check 2 'cd web && npm run test:unit -- src/a.test.tsx'

# Shell quoting must preserve a genuine Vitest filename filter.
check 0 'cd web && npx vitest run --config vitest.unit.config.ts src/a.test.tsx'
check 0 "cd web && npx vitest run --config vitest.unit.config.ts 'src/a.test.tsx'"
check 0 'cd web && npx vitest run --config vitest.unit.config.ts "src/a.test.tsx"'

# Bug: a one-file run by variable was refused as a full run; a bare or
# unknowable run (`"$@"`, `"$(ls)"`, an option's value) must stay blocked.
for word in '$F' '"$F"' '${F}' '"${F}"'; do
  check 0 "cd web && npx vitest run --config vitest.unit.config.ts $word"
done
check 2 'cd web && npx vitest run "$@"'
check 2 'cd web && npx vitest run "$(ls)"'
check 2 'cd web && npx vitest run --config "$CFG"'

printf '%s passed, %s failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
