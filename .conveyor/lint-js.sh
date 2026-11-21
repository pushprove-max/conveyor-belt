#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# The pack's lint command for the Board's JavaScript (.conveyor/project.json, lint): ESLint, with eslint.config.js,
# on the files given, read only (no --fix) and with no warning let through (--max-warnings 0). Run at the checkout's
# top. Each finding is one line `<path>:<line>:<column>: <rule> <message>`, <path> from the top; a message with no
# rule (a parse error) has the rule `eslint`. Exit 0: no finding; 1: findings; 127: `lint: missing eslint`, when
# node_modules/.bin/eslint is absent (npm ci installs it); 2 or more: ESLint failed, its own exit and why.
# Usage: bash .conveyor/lint-js.sh <file>...
set -u
eslint=node_modules/.bin/eslint
[ -x "$eslint" ] || { echo 'lint: missing eslint'; exit 127; }
top=$(pwd -P) || exit 2
json=$("$eslint" --max-warnings 0 --format json -- "$@"); rc=$?
[ "$rc" = 0 ] || [ "$rc" = 1 ] || { echo "lint: eslint exited $rc"; exit "$rc"; }
jq -r --arg top "$top/" '.[] | (.filePath | ltrimstr($top)) as $f | .messages[]
  | "\($f):\(.line // 1):\(.column // 1): \(.ruleId // "eslint") \(.message | gsub("[\r\n]+"; " "))"' <<<"$json" \
  || { echo "lint: the output of eslint could not be read"; exit 2; }
exit "$rc"
