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

# npm logging options do not narrow a suite.
check 2 'npm run --silent test:guards'
check 2 'npm run --silent test:unit'
check 2 'npm --prefix web run --silent test:unit'
check 2 'cd web && npm run --silent test:unit:raw'

# Shell line continuation preserves the positional file filter.
check 0 'cd web && npm run test:unit:raw -- \
  src/a.test.tsx'

# Absolute and relative prefixes identify the same focused web run.
check 0 "npm --prefix $TMP/wt/web run test:unit:raw -- src/a.test.tsx"

printf '%s passed, %s failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
