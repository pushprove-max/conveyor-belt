#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 30
# The project instructions every Claude Code session (CLAUDE.md) and every reviewer (AGENTS.md) loads. Bugs it catches:
# - a path, file or command CLAUDE.md names in backticks that the repo does not have (a file moved or renamed, a
#   command dropped), so a session is sent to something that is not there;
# - AGENTS.md missing, or a second copy of CLAUDE.md that can drift from it: it is a link to CLAUDE.md, so Codex (which
#   reads AGENTS.md by itself) and the reviews given the worktree's AGENTS.md (conveyor/lib/review.sh) read the same text.
set -uo pipefail
SRC=$(cd "$(dirname "$0")" && pwd -P)
fail() { echo "FAIL [claude-md]: $*" >&2; exit 1; }
cd "$SRC" || exit 1

[ -L AGENTS.md ] && [ "$(readlink AGENTS.md)" = CLAUDE.md ] || fail "AGENTS.md is not a link to CLAUDE.md"
[ -s CLAUDE.md ] || fail "CLAUDE.md is missing or empty"

files=$(git ls-files -co --exclude-standard) || fail "git could not list the repo's files"
# has <path or glob>: a file the repo tracks (or adds) is at that path, under it when it ends in /, or matches the glob.
has() {
  local p=${1%/}
  case $1 in
    *'*'*) local f; for f in $p; do [ -e "$f" ] && grep -qxF -- "$f" <<<"$files" && return 0; done; return 1 ;;
    */) grep -q "^$(sed 's/[.[\*^$]/\\&/g' <<<"$p")/" <<<"$files" ;;
    *) grep -qxF -- "$p" <<<"$files" || grep -q "^$(sed 's/[.[\*^$]/\\&/g' <<<"$p")/" <<<"$files" ;;
  esac
}
cmds=$(sed -nE 's/^cmd ([a-z][a-z-]*) .*/\1/p' conveyor/conveyor.sh); [ -n "$cmds" ] || fail "conveyor.sh's command table was not read"
n=0
while IFS= read -r span; do
  read -ra w <<<"$span"
  # A command: npm runs a script package.json has; conveyor.sh takes a command of its table.
  if [ "${w[0]}" = npm ] && [ "${w[1]:-}" = run ]; then
    jq -e --arg s "${w[2]:-}" '.scripts[$s]' package.json > /dev/null || fail "CLAUDE.md names \`$span\`; package.json has no script ${w[2]:-}"
    n=$((n + 1)); continue
  fi
  for i in "${!w[@]}"; do
    t=${w[$i]}
    case $t in
      '<'*|'$'*|*'$HOME'*) continue ;;                                  # a placeholder or a variable
      /*) [ -f "commands/${t#/}.md" ] || [ -f "hooks/${t#/}.tsx" ] || fail "CLAUDE.md names $t; the plugin has no such command or view" ;;
      */*|*.md|*.sh|*.json|*.py|*.tsx|*.ts|*.mjs)
        if [[ $t == */* ]] || [ -e "$t" ]; then has "$t" || fail "CLAUDE.md names $t, which the repo does not have"
        else grep -qE "(^|/)$(sed 's/[.[\*^$]/\\&/g' <<<"$t")\$" <<<"$files" || fail "CLAUDE.md names $t, which no file of the repo is"; fi
        [[ $t != */conveyor.sh && $t != conveyor.sh ]] || [ -z "${w[$((i + 1))]:-}" ] || [[ ${w[$((i + 1))]} == '<'* ]] \
          || grep -qxF -- "${w[$((i + 1))]}" <<<"$cmds" || fail "CLAUDE.md names \`$span\`; conveyor.sh has no command ${w[$((i + 1))]}" ;;
      *) continue ;;
    esac
    n=$((n + 1))
  done
done < <(tr '\n' ' ' < CLAUDE.md | grep -oE '`[^`]+`' | tr -d '`')
[ "$n" -ge 20 ] || fail "only $n paths and commands were read from CLAUDE.md; the reading of its backticks broke"
echo "ok: CLAUDE.md names $n paths and commands, each in the repo; AGENTS.md links it"
