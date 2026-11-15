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

# Option values do not select a focused set of tests.
check 2 'cd web && npx vitest run --config vitest.unit.config.ts --reporter=json --outputFile /tmp/conveyor/unit.test.json'
check 2 'npm --prefix web run test:unit:raw -- --exclude src/a.test.tsx'

# These execute the same focused web script as the accepted leading-cd form.
check 0 'pwd && cd web && npm run test:unit:raw -- src/a.test.tsx'
check 0 "cd 'web' && npm run test:unit:raw -- src/a.test.tsx"

# A quoted argument is prose even when it spans lines; a newline outside quotes
# still starts a command that runs.
check 0 'echo "... for every npm test run ..." >> /tmp/file'
check 0 $'echo "first line\nfor every npm test run ..." >> /tmp/file'
check 2 'npm test'
check 2 $'echo hi\nnpm test'
check 2 $'echo "a\nb" >> /tmp/file\nnpm test'
# A comment ends at its newline: the `cd web` after it still moves the run.
check 0 $'echo hi # comment\ncd web\nnpm run test:unit:raw -- src/a.test.tsx'
# A quote that never closes (a heredoc body's apostrophe) costs only its own
# line: the `cd web` after it still moves the run.
check 0 $'git commit -F- <<EOF\nit\'s fine\nEOF\ncd web && npm run test:unit:raw -- src/a.test.tsx'
# Fail closed (main's ruling): a command with a heredoc operator is
# judged one line at a time, body included, as before. A suite named in a
# body blocks (an accepted false positive); one after the body is never hidden.
check 2 $'cat <<-EOF\n\tit\'s\n\tEOF\nnpm test\n# it\'s'
check 2 $'cat <<\'EOF\'\nit\'s\nEOF\nnpm test\n# it\'s'
check 2 $'cat <<"EOF"\nit\'s\nEOF\nnpm test\n# it\'s'
check 2 $'cat <<EOF\nnpm test\nEOF'
check 2 $'bash <<EOF\nnpm test\nEOF'
check 2 $'echo "x <<EOF"\nnpm test'
check 2 $'cat <<EOF\n$(npm test -- foo)\nEOF'
# Main's verdict: a suite run glued to `)` or a backtick is not bare `npm test`,
# so its first run is allowed (and recorded) as it is on main.
check 0 $'cat <<EOF\nit\'s `npm test`\nEOF'
check 0 $'cat <<\'EOF\'\n$(npm test)\nEOF'
check 2 $'/bin/bash <<EOF\nnpm test\nEOF'
# A `<<` in a comment is no heredoc: a quote spanning lines stays prose.
check 0 $'echo "a\nnpm test b" >> /tmp/file\n# see <<EOF'
check 2 $'echo "<<EOF"\nnpm test\ncat <<EOF\nx\nEOF'
# Only a `#` that starts a word starts a comment: one inside a word hides
# nothing, and a commented `<<EOF` or `bash` opens and feeds nothing.
check 2 'echo a#b; npm test'
check 2 'echo ok \# note; npm test'
check 2 'echo a\\#b; npm test'
check 2 $'cat <<EOF\nhello\nEOF\necho a#b; npm test'
check 2 $'cat <<123\nit\'s\n123\nnpm test\n# it\'s'
check 2 $'echo ok # <<EOF\nnpm test\nEOF'
check 2 $'cat <<\'EOF\' # sh\nit\'s\nEOF\nnpm test\n# it\'s'

printf '%s passed, %s failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
