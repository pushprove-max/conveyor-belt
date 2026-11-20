#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 300
# Self-test for bash-guardrails.sh. Run directly. This file has the repo-wide search, the Try lines of refusals, aws profiles, caller hunts and the case filter; bash-guardrails.test.sh and bash-guardrails-writes.test.sh have the other cases.
set -u
export CONVEYOR_REVIEWER=0

HOOK="$(cd "$(dirname "$0")/.." && pwd)/bash-guardrails.sh"
PASS=0 FAIL=0

# The file runs itself once per part, side by side, and prints the parts in
# order: a hook call costs about 0.2 s. Every
# line runs in every part, so each part has all fixtures and helpers; outside
# its own part a run has `true` for the hook and check records nothing.
# One part alone: GUARDRAILS_TEST_PART=<n> in front. The parts are cut at the
# measured times of their hook calls (2026-11-12). Move a `part` line when a part grows.
#
# A case filter: CONVEYOR_SHELL_TEST_CASE=<text>[,<text>] runs only the top-level checks whose text
# holds one of the texts; lib/case-filter.sh says how. A part with no selected check prints `0 passed, 0 failed`
# and is accepted; each text must select a check in some part.
. "$(dirname "${BASH_SOURCE[0]}")/lib/case-filter.sh"
PARTS=3
if [ -z "${GUARDRAILS_TEST_PART:-}" ]; then
  cf_refuse_empty
  OUT=$(mktemp -d); trap 'rm -rf "$OUT"' EXIT; : > "$OUT/hits"
  for P in $(seq "$PARTS"); do GUARDRAILS_TEST_PART=$P GUARDRAILS_TEST_HITS=$OUT/hits bash "$0" > "$OUT/$P" 2>&1 & done
  wait
  for P in $(seq "$PARTS"); do
    # A part that died before its count, or ran no case, is a failure, never a shorter list. Under a selector a
    # part may select nothing.
    if [[ $(tail -1 "$OUT/$P") =~ ^([0-9]+)\ passed,\ ([0-9]+)\ failed$ ]] \
      && { grep -qE '^(ok  |FAIL) ' "$OUT/$P" || { [ -n "${CONVEYOR_SHELL_TEST_CASE+x}" ] && [ "${BASH_REMATCH[1]}${BASH_REMATCH[2]}" = 00 ]; }; }; then
      PASS=$((PASS+BASH_REMATCH[1])) FAIL=$((FAIL+BASH_REMATCH[2]))
      sed '$d' "$OUT/$P" | sed '${/^$/d;}'
    else
      cat "$OUT/$P"; echo "FAIL part $P of $PARTS did not finish"; FAIL=$((FAIL+1))
    fi
  done
  echo
  echo "$PASS passed, $FAIL failed"
  # Each text must run a check of its own: one matching text would otherwise hide a misspelled one.
  [ -z "${CONVEYOR_SHELL_TEST_CASE+x}" ] || cf_missed "$OUT/hits" || exit 2
  [ "$FAIL" -eq 0 ]; exit
fi
case "$GUARDRAILS_TEST_PART" in [1-$PARTS]) ;; *) echo "FAIL no such part: $GUARDRAILS_TEST_PART (parts: 1 to $PARTS)" >&2; exit 2 ;; esac
# Each part records the texts that select a check in it, so the parent can name a text that ran nothing.
[ -z "${CONVEYOR_SHELL_TEST_CASE+x}" ] || cf_install "${GUARDRAILS_TEST_HITS:-}"
REAL_HOOK=$HOOK
part() { if [ "$1" = "$GUARDRAILS_TEST_PART" ]; then ON=1 HOOK=$REAL_HOOK; else ON=0 HOOK=true; fi; }
part 1

# Every default case runs from a disposable repository, so a run from a card's
# worktree reads the same checkout shape as a run from main's.
MAIN_TMP=$(mktemp -d)
git -C "$MAIN_TMP" init -q
printf '{}\n' > "$MAIN_TMP/package.json"
trap 'rm -rf "$MAIN_TMP"' EXIT

# Outside its own part a call runs no hook, though each $(json ...) and $(run_hook ...) around it still forks a
# subshell; inside it, one more fork that becomes the hook (no echo or pipe forks).
run_hook() { [ "$ON" = 1 ] || return 0; ( cd "$MAIN_TMP" && exec "$HOOK" <<<"$1" >/dev/null 2>&1 ); echo $?; }
check() { [ "$ON" = 1 ] || return 0; if [ "$2" = "$3" ]; then PASS=$((PASS+1)); echo "ok   $1"; else FAIL=$((FAIL+1)); echo "FAIL $1 (expected $2, got $3)"; fi }
# Outside its own part a run builds no payload: the parts each paid a jq per case for nothing.
# Inside it, the payload is escaped in bash: a jq per case cost about a seventh of the case. A control character
# other than tab, newline and CR takes jq's \u escape, so such a command still goes through jq.
json() {
  [ "$ON" = 1 ] || return 0
  local s=$1 t=${1//[$'\t\n\r']/}
  if [[ $t == *[[:cntrl:]]* ]]; then jq -cn --arg cmd "$1" '{tool_input:{command:$cmd}}'; return; fi
  s=${s//\\/\\\\}; s=${s//\"/\\\"}; s=${s//$'\t'/\\t}; s=${s//$'\n'/\\n}; s=${s//$'\r'/\\r}
  printf '{"tool_input":{"command":"%s"}}\n' "$s"
}
# A refusal these guards keep must hand back a concrete command. Take its
# `Try:` line and replay it in the same seat: it has to pass, or the advice is
# a placeholder or something another guard blocks.
check_try() { # label, command, [seat dir]
  [ "$ON" = 1 ] || return 0
  local DIR=${3:-$MAIN_TMP} OUT TRY
  OUT=$(cd "$DIR" && json "$2" | "$HOOK" 2>&1 >/dev/null; echo "rc=$?")
  check "$1" 2 "${OUT##*rc=}"
  TRY=$(printf '%s\n' "$OUT" | sed -n 's/^Try: //p' | head -1)
  check "$1: the refusal names a Try: command" 1 "$([ -n "$TRY" ] && echo 1 || echo 0)"
  check "$1: its Try: command passes" 0 "$(cd "$DIR" && json "$TRY" | "$HOOK" >/dev/null 2>&1; echo $?)"
}

# A guard retired or turned into a rewrite: the call runs, as written or rewritten.
check_ok() { # label, command
  check "$1" 0 "$(run_hook "$(json "$2")")"
}

# The heap cap is agent-independent and stays that way.
check "a Codex payload still gets the heap cap" 2 \
  "$(AGENT_KIND=codex bash -c 'echo "$1" | "$0" >/dev/null 2>&1; echo $?' "$HOOK" "$(json 'node --test x.test.ts')")"

# --- repo-wide text search (.claude/rules/agents.md, Token efficiency) -------
# Catches: a Try line that names only `src`, so the whole-repo question gets a command that cannot answer it.
check "rg_try_names_the_roots" "rg -n -e 'foo' src web shared lambdas infra scripts .claude" \
  "$(cd "$MAIN_TMP" && json 'rg foo | head' | "$HOOK" 2>&1 >/dev/null | sed -n 's/^Try: //p' | head -1)"

# Catches: a refusal a command can correct that ends with no Try line, or one whose Try line the same hook refuses.
# One row per guard Try site: hook, refused command, seat (main or wt), run_in_background, a recorded earlier run.
# The hook is handed the text; nothing runs. The Try line is replayed to the same hook in the same seat.
guard_refusals_print_try() {
  [ "$ON" = 1 ] || return 0
  local HOOKS_DIR TRY_BOX
  HOOKS_DIR=$(dirname "$REAL_HOOK"); TRY_BOX=$(mktemp -d)
  git -C "$TRY_BOX" init -q -b main; git -C "$TRY_BOX" -c user.name=t -c user.email=t@t -c core.hooksPath=/dev/null commit -q --allow-empty -m init
  git -C "$TRY_BOX" worktree add -q "$TRY_BOX-wt" >/dev/null 2>&1
  printf 'gen.json linguist-generated=true\n' > "$TRY_BOX/.gitattributes"; seq 1 300 > "$TRY_BOX/gen.json"
  try_payload() { # tool, text, dir, background
    if [ "$1" = Read ]; then jq -cn --arg f "$2" --arg d "$3" '{tool_name:"Read",tool_input:{file_path:$f},cwd:$d,session_id:"try-row"}'
    else jq -cn --arg c "$2" --arg d "$3" --argjson b "${4:-false}" '{tool_name:"Bash",tool_input:{command:$c,run_in_background:$b},cwd:$d,session_id:"try-row"}'; fi
  }
  try_row() { # hook file, refused text, seat, [background], [recorded]
    local H=$HOOKS_DIR/$1 DIR=$MAIN_TMP TOOL=Bash OUT TRY L="$1: $2"
    case "$3" in wt) DIR=$TRY_BOX-wt ;; box) DIR=$TRY_BOX ;; esac
    [ "$1" = generated-read-guard.sh ] && TOOL=Read
    [ "${5:-}" != recorded ] || (cd "$DIR" && try_payload Bash "$2" "$DIR" "${4:-false}" | CLAUDE_PROJECT_DIR=$DIR "$H" >/dev/null 2>&1
      try_payload Bash "$2" "$DIR" "${4:-false}" | CLAUDE_PROJECT_DIR=$DIR "$H" --record-complete >/dev/null 2>&1)
    OUT=$(cd "$DIR" && try_payload "$TOOL" "$2" "$DIR" "${4:-false}" | CLAUDE_PROJECT_DIR=$DIR "$H" 2>&1 >/dev/null; echo "rc=$?")
    TRY=$(printf '%s\n' "$OUT" | sed -n 's/^Try: //p' | head -1)
    check "guard_refusals_print_try: $L refuses" 2 "${OUT##*rc=}"
    check "guard_refusals_print_try: $L prints a Try:" 1 "$([ -n "$TRY" ] && echo 1 || echo 0)"
    check "guard_refusals_print_try: $L Try passes the same hook: $TRY" 0 \
      "$(cd "$DIR" && try_payload Bash "$TRY" "$DIR" "${4:-false}" | CLAUDE_PROJECT_DIR=$DIR "$H" >/dev/null 2>&1; echo $?)"
  }
  try_row bash-guardrails.sh 'rg foo | head' main
  try_row git-safety.sh 'git push -f origin HEAD' main
  try_row git-safety.sh 'git push --force origin HEAD' main
  try_row git-safety.sh 'git push -fu origin HEAD' main
  try_row git-safety.sh 'git push origin +HEAD' main
  try_row git-safety.sh 'git checkout -f main' main
  try_row git-safety.sh 'git gc --prune=now' main
  try_row suite-rerun-guard.sh 'npm test' main
  try_row suite-rerun-guard.sh 'npm run test:unit' box false recorded
  rm -rf "$TRY_BOX" "$TRY_BOX-wt"
}
guard_refusals_print_try

check_ok "rg with a bare pattern and no path is rewritten, not refused" \
  'rg foo'
check_ok "rg with a quoted pattern and no path is rewritten, not refused" \
  "rg -n 'foo bar'"
check_ok "rg over . is rewritten, not refused" \
  "rg -n 'foo' ."
check_ok "rg over the checkout root is rewritten, not refused" \
  "rg foo $HOME/repos/sample-project"
check_ok "grep -r over . is rewritten, not refused" \
  'grep -rn foo .'
check_try "rg piped into head still blocks" \
  "rg 'foo' | head"
check "rg with a directory passes" 0 \
  "$(run_hook "$(json "rg -n 'foo' src/services")")"
check "rg with a bare pattern and an existing directory passes" 0 \
  "$(run_hook "$(json 'rg foo .claude/scripts')")"
check "rg with a root file and no directory passes" 0 \
  "$(run_hook "$(json "rg 'foo' package.json")")"
check "rg with a quoted pattern and a nested path passes" 0 \
  "$(run_hook "$(json "rg -l 'foo' web/src/pages")")"
check "grep without -r passes" 0 \
  "$(run_hook "$(json 'grep foo package.json')")"
check "grep -r with a directory passes" 0 \
  "$(run_hook "$(json 'grep -rn foo src/routes')")"

# BOUNDED IS ANYTHING BELOW THE ROOT. About 20 of 55 refusals were real
# bounded searches: a top-level folder off the old allowlist, a glob, a path
# after the command's own cd. The root, its parents and a pathless search stay out.
mkdir -p "$MAIN_TMP/policy" && touch "$MAIN_TMP/tsconfig.json" "$MAIN_TMP/tsconfig.web.json"
LOG_TMP=$(mktemp -d) && touch "$LOG_TMP/file.log"
check "rg over a top-level folder off the old allowlist passes" 0 \
  "$(run_hook "$(json 'rg x policy')")"
check "rg over a glob of root files passes" 0 \
  "$(run_hook "$(json 'rg x tsconfig*.json')")"
check "rg over a bare wildcard inside a folder passes" 0 \
  "$(run_hook "$(json 'rg x policy/*')")"
check "rg over a file named relative to the command's own cd passes" 0 \
  "$(run_hook "$(json "cd $LOG_TMP && rg x file.log")")"
check_ok "rg x with no path is rewritten, not refused" 'rg x'
check_ok "rg x . from the root is rewritten, not refused" 'rg x .'
check_ok "rg x .. from the root is rewritten, not refused" 'rg x ..'
check_try "a bare * glob is the whole checkout and still blocks" 'rg x *'
check_try "rg . after a cd to the checkout's parent still blocks" "cd $MAIN_TMP/.. && rg x ."
# A FAILED cd DOES NOT MOVE THE SHELL, so it must not move the search base: with
# `;` the rg still runs in the checkout root. `&&` is judged the same way.
check_try "rg . after a failed cd into a missing child still blocks" "cd $MAIN_TMP/missing; rg needle ."
check_try "rg . after a failed cd with && blocks the same way" "cd $MAIN_TMP/missing && rg needle ."
check "a failed cd keeps the old base for a bounded file" 0 \
  "$(run_hook "$(json "cd $MAIN_TMP/missing; rg x package.json")")"
rm -rf "$LOG_TMP"
# A VARIABLE AFTER A FIXED PREFIX IS JUDGED AS A GLOB FROM THE `$` ON. 19 of 20
# unbounded refusals on 2026-09-27 named a log such as /tmp/conveyor/x-$n.log.
check "rg over an absolute log path holding a variable passes" 0 \
  "$(run_hook "$(json 'rg x /tmp/conveyor/x-$n.log')")"
check "rg over a relative folder holding a variable passes" 0 \
  "$(run_hook "$(json 'rg x policy/$f')")"
check_ok "rg over a bare variable passes with a warning (G4)" 'rg x $X'
check_try "rg over a variable right under / still blocks" 'rg x /$X'
check_try "rg over a variable at the checkout root still blocks" "rg x $MAIN_TMP/\$X"
check_try "rg over a variable in the checkout's parent still blocks" "rg x $MAIN_TMP/../\$X"
# A LOOP VARIABLE BOUND TO BOUNDED PATHS IS BOUNDED. Only a one-word
# for-list resolved, so `for f in a b; do rg x "$f"; done` was refused though
# every value it can take is a bounded path.
check "a for loop over two bounded paths lets rg \"\$f\" pass" 0 \
  "$(run_hook "$(json 'for f in policy package.json; do rg x "$f"; done')")"
check "a for loop over a bounded glob and a file lets rg \$f pass" 0 \
  "$(run_hook "$(json 'for f in policy/* package.json; do rg x $f; done')")"
check "a later reassignment of the loop variable does not undo the loop's binding" 0 \
  "$(run_hook "$(json 'for f in policy package.json; do rg x "$f"; done; f=package.json')")"
check_try "a for loop with the checkout root among its paths still blocks" 'for f in policy .; do rg x "$f"; done'
check_ok "a for loop whose list holds a variable passes with a warning (G4)" 'for f in policy $X; do rg x "$f"; done'
check_try "a bare pathless rg inside a for loop still blocks" 'for f in policy package.json; do rg x; done'
# A VARIABLE BOUND BY `read` IS A LIST OF PATHS FED IN, ONE AT A TIME:
# each `rg "$f"` searches one listed path, never a bare repo-wide search, so it
# passes. What feeds the list is not judged (a read fed the checkout root is the
# accepted residual). `D=$(...)` stays refused: its value is unknown.
check "a while-read loop lets rg \"\$f\" pass" 0 \
  "$(run_hook "$(json 'git diff --name-only | while IFS= read -r f; do rg -n x "$f"; done')")"
check "a plain read binding lets rg \${f} pass" 0 \
  "$(run_hook "$(json 'while read f; do rg x ${f}; done < /tmp/conveyor/list')")"
check "a read with an input redirect binds its variable too" 0 \
  "$(run_hook "$(json 'read -r f < /tmp/conveyor/list; rg x "$f"')")"
check_ok "a read binding does not bound another variable: the other one warns (G4)" 'while read -r f; do rg x "$g"; done < /tmp/conveyor/list'
check_try "a later literal reassignment replaces the read binding" 'read -r f < /tmp/conveyor/list; f=.; rg x "$f"'
check_ok "a command-substitution assignment passes with a warning (G4)" 'D=$(git rev-parse --show-toplevel); rg x "$D"'
check_try "a bare pathless rg inside a read loop still blocks" 'while read -r f; do rg x; done < /tmp/conveyor/list'

# THE REFUSAL NAMES THE WHOLE-REPO FORM. This is the most-fired rule in
# the repo, and 19 of 51 blocks were followed by another block of the same rule,
# because it said what was forbidden and never what to ask instead.
SEARCH_REFUSAL=$(cd "$MAIN_TMP" && json 'rg -n foo . | head' | "$HOOK" 2>&1 >/dev/null)
check "the unbounded refusal names serena find_symbol" 1 \
  "$(grep -q 'serena find_symbol'<<<"$SEARCH_REFUSAL" && echo 1 || echo 0)"
check "the unbounded refusal names the roots to search instead" 1 \
  "$(grep -q 'src web shared lambdas infra scripts .claude' <<<"$SEARCH_REFUSAL" && echo 1 || echo 0)"

# A SESSION'S OWN TRANSCRIPTS ARE SEARCHABLE. They live under
# ~/.claude/projects/<project>/, outside every checkout, and both home forms
# were refused as unbounded before the path was ever resolved.
check "rg under ~/.claude/projects passes" 0 \
  "$(run_hook "$(json 'rg -n foo ~/.claude/projects/-home-x')")"
check "rg under \$HOME/.claude/projects passes" 0 \
  "$(run_hook "$(json 'rg -n foo $HOME/.claude/projects/-home-x')")"
# The home directory itself still holds every checkout, so it stays refused.
check_try "rg over the home directory still blocks" \
  'rg -n foo ~'
check "git grep passes" 0 \
  "$(run_hook "$(json 'git grep -n foo')")"
check "grep as a filter passes" 0 \
  "$(run_hook "$(json 'npm run typecheck 2>&1 | grep -c error')")"

part 2
# The chain runner that a direct local-checks run was sent to is gone: the full checks run directly.
check "a direct local-checks run passes" 0 \
  "$(run_hook "$(json 'bash scripts/ci/local-checks.sh --full --reuse-unchanged')")"

# A linked worktree, where git-dir and git-common-dir differ: a real one rather than a stub, because the stub
# is the thing most likely to drift.
# Only this part reads it, so only this part builds it.
WORKER_TMP=/nonexistent
if [ "$ON" = 1 ]; then
  WORKER_TMP=$(mktemp -d)
  git -C "$WORKER_TMP" init -q 2>/dev/null
  git -C "$WORKER_TMP" -c user.email=t@t -c user.name=t commit -q --allow-empty -m x 2>/dev/null
  git -C "$WORKER_TMP" worktree add -q "$WORKER_TMP/wt" -b wtb >/dev/null 2>&1
fi

# --- aws must name a profile in every seat: the default credentials may reach an account no agent may touch
# The hook reads AWS_PROFILE from its own environment, so each case pins it.
aws_hook() { # <AWS_PROFILE value or "" for unset> <command> [seat dir]
  [ "$ON" = 1 ] || return 0
  ( cd "${3:-$MAIN_TMP}" && json "$2" | if [ -n "$1" ]; then AWS_PROFILE=$1 "$HOOK"; else env -u AWS_PROFILE "$HOOK"; fi >/dev/null 2>&1; echo $? )
}
SAVED_AWS_PROFILE=${AWS_PROFILE-}; unset AWS_PROFILE
check_try "aws with no profile and none in the environment blocks" 'aws sts get-caller-identity'
check_try "aws with an empty --profile= blocks" 'aws s3 ls --profile='
check_try "aws whose AWS_PROFILE prefix is empty blocks" "AWS_PROFILE='' aws s3 ls"
[ -z "$SAVED_AWS_PROFILE" ] || export AWS_PROFILE=$SAVED_AWS_PROFILE
check "aws in a worker worktree with no profile blocks too" 2 "$(aws_hook '' 'aws s3 ls' "$WORKER_TMP/wt")"
check "aws --profile X passes" 0 "$(aws_hook '' 'aws --profile sample-dev sts get-caller-identity')"
check "aws --profile=X after the subcommand passes" 0 "$(aws_hook '' 'aws s3 ls --profile=sample-dev')"
check "an AWS_PROFILE=X prefix passes" 0 "$(aws_hook '' 'AWS_PROFILE=sample-dev aws s3 ls')"
check "an exported AWS_PROFILE before aws passes" 0 "$(aws_hook '' 'export AWS_PROFILE=sample-dev && aws s3 ls')"
check "aws with AWS_PROFILE in the environment passes" 0 "$(aws_hook sample-dev 'aws s3 ls')"
check "env -u AWS_PROFILE aws blocks even with AWS_PROFILE set" 2 "$(aws_hook sample-dev 'env -u AWS_PROFILE aws sts get-caller-identity')"
check "env -i aws blocks even with AWS_PROFILE set" 2 "$(aws_hook sample-dev 'env -i aws s3 ls')"
check "aws --version passes" 0 "$(aws_hook '' 'aws --version')"
check "aws later in a pipeline is still checked" 2 "$(aws_hook '' 'echo x | aws s3 cp - s3://b/k')"

[ "$ON" = 1 ] && rm -rf "$WORKER_TMP"

# The serena-down marker stands the symbols hint down. No session
# writes it, on an errored serena call; a worker that touches it by hand runs
# a whole cut with the gates off (2026-09-18).
check "touching the serena-down marker is refused" 2 \
  "$(run_hook "$(json 'touch /tmp/claude-serena-down-abc123')")"
check "writing the marker through a redirect is refused" 2 \
  "$(run_hook "$(json 'echo > "/tmp/claude-serena-down-$SID"')")"
check "an unrelated touch in /tmp passes" 0 \
  "$(run_hook "$(json 'touch /tmp/claude-other-marker')")"


# _implementer-tools.md said nothing of the bounded-path rule: one cut lost 10
# calls to those refusals (2026-09-18). The note names the path rule.
NOTE="$(dirname "$REAL_HOOK")/../briefs/_implementer-tools.md"
check "the tools note states the rg/grep rewrite and cap rule" 1 "$(grep -qE 'rg.*grep -r.*rewritten' "$NOTE" && echo 1 || echo 0)"

part 3
for FN in renameSync copyFileSync; do
  check "copy_destination_literal_resolved: node $FN to '/tmp/x' from a repo file passes" 0 \
    "$(run_hook "$(json "node -e \"require('fs').$FN(require('path').resolve('src/a.ts'), '/tmp/x')\"")")"
  check "copy_destination_literal_resolved: node $FN onto 'src/a.ts' from a computed source is refused" 2 \
    "$(run_hook "$(json "node -e \"require('fs').$FN(require('path').resolve('/tmp/y'), 'src/a.ts')\"")")"
done
check "copy_destination_literal_resolved: a variable assigned pathlib.Path('/tmp/x') passes" 0 \
  "$(run_hook "$(json "python3 -c \"import shutil, pathlib; d=pathlib.Path('/tmp/x'); shutil.copy('src/a.ts', d)\"")")"
for DST in "os.path.join('/tmp', 'x')" "f'/tmp/{n}'" "'/tmp/' + n" "Path('/tmp') / '../../src/a.ts'" "d" "pick('/tmp/x')"; do
  OUT=$( [ "$ON" = 1 ] && cd "$MAIN_TMP" && json "python3 -c \"import os, shutil; from pathlib import Path; n='x'; d='/tmp/' + n; shutil.copy('src/a.ts', $DST)\"" | "$HOOK" 2>&1 >/dev/null; echo "rc=$?")
  check "copy_destination_unreadable_refused_with_cp_hint: $DST" "rc=2 hint" \
    "$(grep -o 'rc=[0-9]*' <<<"$OUT")$(grep -q 'use plain cp or mv' <<<"$OUT" && echo ' hint')"
done
# A call whose arguments the parser cannot split hid its destination entirely: refused, not skipped.
for SCR in $'python3 -c "import shutil; from pathlib import Path; shutil.copy(Path(str(\'/tmp/y\')), \'src/a.ts\')"' \
  $'python3 - <<\'EOF\'\nimport shutil\nshutil.copy(\'/tmp/y\',\n  \'src/a.ts\')\nEOF'; do
  OUT=$( [ "$ON" = 1 ] && cd "$MAIN_TMP" && json "$SCR" | "$HOOK" 2>&1 >/dev/null; echo "rc=$?")
  check "copy_arguments_unreadable_refused_with_cp_hint: ${SCR:0:60}" "rc=2 hint" \
    "$(grep -o 'rc=[0-9]*' <<<"$OUT")$(grep -q 'use plain cp or mv' <<<"$OUT" && echo ' hint')"
done

# --- caller hunts go to serena's reference lookup -------------------
# 38 rg searches and no find_referencing_symbols call in one cut (2026-09-18).
# A HINT, NEVER A REFUSAL: 73% of refusals were retried unchanged, so the
# block cost a turn and redirected nothing. The search runs; the first caller
# hunt of a session carries the serena pointer as additionalContext.
HUNT_SID="guardrails-hunt-$$"
HUNT_HOME=$(mktemp -d)
printf '{"mcpServers":{"serena":{}}}\n' > "$HUNT_HOME/.claude.json"
trap 'rm -rf "$MAIN_TMP" "$HUNT_HOME" /tmp/claude-serena-tracker-$HUNT_SID* /tmp/claude-caller-hunt-$HUNT_SID* /tmp/claude-serena-down-$HUNT_SID*' EXIT
hunt() { # <session suffix> <command> -- prints hint, quiet, or rc=<n>
  [ "$ON" = 1 ] || return 0
  local OUT RC
  OUT=$(cd "$MAIN_TMP" && jq -cn --arg cmd "$2" --arg sid "$HUNT_SID-$1" '{session_id:$sid,tool_input:{command:$cmd}}' | env -u CLAUDE_CONFIG_DIR HOME=$HUNT_HOME "$HOOK" 2>/dev/null); RC=$?
  [ "$RC" = 0 ] || { echo "rc=$RC"; return; }
  jq -e '.hookSpecificOutput.hookEventName == "PreToolUse" and (.hookSpecificOutput.additionalContext | contains("find_referencing_symbols"))' <<<"$OUT" >/dev/null 2>&1 && echo hint || echo quiet
}
check "a call-site hunt runs and carries the serena hint" hint "$(hunt a 'rg -n "analyzeRecapture\(" src')"
check "the identical retry runs with no second hint" quiet "$(hunt a 'rg -n "analyzeRecapture\(" src')"
check "another hunt in the same session is not hinted again" quiet "$(hunt a "rg -n 'ForgeryDetector\\b' lambdas")"
check "a snake_case config key search is not a hunt" quiet "$(hunt b 'rg -n "vt_capture_mode" src')"
check "a bounded PascalCase hunt is hinted" hint "$(hunt b "rg -n 'ForgeryDetector\\b' lambdas")"
check "a bounded camelCase hunt with grep -r is hinted" hint "$(hunt c "grep -rn '\\bforgeryDetector' shared")"
# A recorded lookup is one `refs:<name>` line per symbol in the session's tracker file.
printf 'refs:ForgeryDetector\nrefs:analyze\n' > "/tmp/claude-serena-tracker-$HUNT_SID-d"
check "after find_referencing_symbols named the symbol, no hint" quiet "$(hunt d "rg -n 'ForgeryDetector\\b' web/src")"
check "a quoted literal is a string search, no hint" quiet "$(hunt e "rg -n \"'analyzeRecapture('\" src")"
check "a caller hunt outside the source roots, no hint" quiet "$(hunt e 'rg -n "analyzeRecapture\(" docs')"
check "neither of those spent the session's one hint" hint "$(hunt e 'rg -n "analyzeRecapture\(" src')"
touch "/tmp/claude-serena-down-$HUNT_SID-f"
check "a serena error this session stands the hint down" quiet "$(hunt f 'rg -n "otherThing\(" src')"
check "a hinted hunt that another rule refuses still blocks" rc=2 "$(hunt g 'rg -n "otherThing\(" src; node --test x.test.ts')"
# A profile pane's .claude.json is CLAUDE_CONFIG_DIR/.claude.json; ~/.claude.json is not the file Claude Code reads there.
profile_hunt() { # <session suffix> <HOME .claude.json text> <profile .claude.json text> -> hint | quiet
  [ "$ON" = 1 ] || return 0
  local H P OUT; H=$(mktemp -d); P=$(mktemp -d); printf '%s\n' "$2" > "$H/.claude.json"; printf '%s\n' "$3" > "$P/.claude.json"
  OUT=$(cd "$MAIN_TMP" && jq -cn --arg cmd 'rg -n "analyzeRecapture\(" src' --arg sid "$HUNT_SID-$1" '{session_id:$sid,tool_input:{command:$cmd}}' \
    | HOME=$H CLAUDE_CONFIG_DIR=$P "$HOOK" 2>/dev/null); rm -rf "$H" "$P"
  jq -e '.hookSpecificOutput.additionalContext | contains("find_referencing_symbols")' <<<"$OUT" >/dev/null 2>&1 && echo hint || echo quiet
}
check "serena configured only in the profile's .claude.json still gets the hint" hint "$(profile_hunt p1 '{}' '{"mcpServers":{"serena":{}}}')"
PROFILE_DISABLED=$(jq -cn --arg p "$(git -C "$MAIN_TMP" rev-parse --show-toplevel)" '{mcpServers:{serena:{}},projects:{($p):{disabledMcpServers:["serena"]}}}')
check "serena disabled for the repo in the profile's .claude.json stands the hint down" quiet \
  "$(profile_hunt p2 '{"mcpServers":{"serena":{}}}' "$PROFILE_DISABLED")"

# --- red-proof.sh, the approved red-before-green helper ---------------
# Builders hand-built scratch copies to show a test red and met 15 refusals; the helper breaks the line in its
# own scratch worktree, so its call is allowed even when the break it names reads like a source write. The
# test command it runs is still screened like any other.
check "red-proof.sh on a source line is allowed" 0 \
  "$(run_hook "$(json "bash .claude/scripts/red-proof.sh src/x.ts 12 'return 0;' -- npm run test:files -- src/__tests__/x.test.ts")")"
check "red-proof.sh whose replacement reads like a source write is allowed" 0 \
  "$(run_hook "$(json "bash .claude/scripts/red-proof.sh .claude/hooks/a.sh 3 'sed -i s/a/b/ src/x.ts > src/y.ts' -- bash t.sh")")"
check "red-proof.sh still refuses a bare node --test as its test" 2 \
  "$(run_hook "$(json "bash .claude/scripts/red-proof.sh src/x.ts 1 x -- node --test src/x.test.ts")")"

# --- the case filter -----------------------------------------------------------------------------
# The filter (lib/case-filter.sh) lets a fix round rerun the checks it names, not the 193 s file. Its variants run
# against fixtures/case-filter-fixture.sh, which sources the same filter: milliseconds, where a nested run of this
# file costs minutes. fx prints the fixture's exit status, its ok count and each text it named as unmatched.
if [ "$ON" = 1 ]; then
  CF_FIXTURE=$(dirname "${BASH_SOURCE[0]}")/fixtures/case-filter-fixture.sh
  # `chec[k]`: the filter takes a function whose body holds the word for a check, and would skip fx's call.
  fx() { # [selector] -- no argument runs the fixture with the selector unset
    local OUT; OUT=$(env -u CONVEYOR_SHELL_TEST_CASE ${1+CONVEYOR_SHELL_TEST_CASE="$1"} bash "$CF_FIXTURE" 2>&1)
    echo "$? $(grep -c '^ok   ' <<<"$OUT")$(sed -n "s/^FAIL no chec[k] matched the text '\(.*\)'$/ missed:\1/p" <<<"$OUT" | tr -d '\n')"
  }
  check "case_filter_runs_only_matching: unset runs every check" "0 4" "$(fx)"
  check "case_filter_runs_only_matching: a full group id runs that group's checks" "0 2" "$(fx 'group_a')"
  check "case_filter_runs_only_matching: a label substring runs that check alone" "0 1" "$(fx 'second check')"
  check "case_filter_runs_only_matching: a group id and a label together run both" "0 2" "$(fx 'group_b,second check')"
  check "case_filter_runs_only_matching: a wrapper row's text runs its nested check" "0 1" "$(fx 'fourth row')"
  check "case_filter_runs_only_matching: two texts matching the same check both count as matched" "0 1" \
    "$(fx 'group_a: first,first check')"
  check "case_filter_runs_only_matching: a misspelled text beside a matching one exits 2 and names the text" \
    "2 2 missed:grup_b" "$(fx 'group_a,grup_b')"
  check "case_filter_runs_only_matching: a selector matching nothing exits 2 with no ok line and names it" \
    "2 0 missed:no such label" "$(fx 'no such label')"
  check "case_filter_runs_only_matching: an empty selector exits 2" "2 0" "$(fx '')"
  check "case_filter_runs_only_matching: a selector of only a comma exits 2" "2 0" "$(fx ',')"
fi

# --- Rewrites and passes in place of refusals -------------------------------------------------------------------
# Bug caught: a shell append to a plan or doc skipped no Edit hook that matters for prose, yet was refused as a source write.
check "shell_append_to_md_passes" 0 "$(run_hook "$(json 'echo "- note" >> src/notes/plan.md')")"
check "shell_append_to_md_passes: a source file is still refused" 2 "$(run_hook "$(json 'echo "x" >> src/services/a.ts')")"
# Bug caught: the aws profile guard refused a profile that sat in a variable the command itself assigned.
check "aws_profile_in_variable_passes" 0 "$(aws_hook '' 'P="--profile sample-dev"; aws $P sts get-caller-identity')"
check "aws_var_without_profile_blocks" 2 "$(aws_hook '' 'P="--region us-east-1"; aws $P sts get-caller-identity')"
# Bug caught: a profile setting that never takes effect vouched for a call that ran on the default credentials, which
# may reach an account no agent may touch (passes 1-3): set after the call, on another command's prefix, under `false &&`, unset or
# emptied again, cleared before a repeated call, written as an argument, dropped by `env -i`, or a call inside `$(...)`,
# which was never checked at all; or a profile value the shell expands at run time, empty or not (pass 4). After the
# bar, the forms that do take effect still pass.
AWS_NEVER=('aws sts get-caller-identity $P; P=--profile=sample-dev' 'aws s3 ls; export AWS_PROFILE=sample-dev'
  'AWS_PROFILE=sample-dev true; aws s3 ls' 'P=--profile=sample-dev true; aws s3 ls $P'
  'false && P=--profile=sample-dev; aws s3 ls $P' 'export AWS_PROFILE=sample-dev; unset AWS_PROFILE; aws s3 ls'
  'export AWS_PROFILE=sample-dev; AWS_PROFILE=; aws s3 ls' 'P=--profile=sample-dev; aws s3 ls $P; P=; aws s3 ls $P'
  'aws s3 ls AWS_PROFILE=sample-dev' 'X=$(aws s3 ls)'
  'AWS_PROFILE="$UNSET_PROFILE" aws s3 ls' 'export AWS_PROFILE=sample-dev; AWS_PROFILE="$UNSET_PROFILE" aws s3 ls'
  "AWS_PROFILE='\$UNSET_PROFILE' aws s3 ls" 'aws --profile "$UNSET_PROFILE" s3 ls' 'aws --profile=$UNSET_PROFILE s3 ls'
  "P='--profile \$X'; aws s3 ls \$P" "export AWS_PROFILE='\$X'; aws s3 ls")
AWS_GOT=""; for C in "${AWS_NEVER[@]}"; do AWS_GOT+="$(aws_hook '' "$C") "; done
AWS_GOT+="$(aws_hook sample-dev 'unset AWS_PROFILE; aws s3 ls') $(aws_hook sample-dev 'AWS_PROFILE=; aws s3 ls') $(aws_hook sample-dev "AWS_PROFILE='' aws s3 ls") $(aws_hook '' 'export AWS_PROFILE=sample-dev; env -i aws s3 ls') $(aws_hook sample-dev 'aws --profile "$UNSET_PROFILE" s3 ls') $(aws_hook sample-dev "P='--profile \$X'; aws s3 ls \$P") |"
AWS_GOT+=" $(aws_hook '' 'P=--profile=sample-dev; aws s3 ls $P') $(aws_hook '' 'P="--profile sample-dev"; aws sts get-caller-identity $P') $(aws_hook '' 'X=1; export AWS_PROFILE=sample-dev && aws s3 ls') $(aws_hook sample-dev 'X=1; aws s3 ls') $(aws_hook sample-dev 'AWS_PROFILE=sample-dev; aws s3 ls') $(aws_hook '' 'aws --profile sample-dev s3 ls') $(aws_hook '' 'AWS_PROFILE="sample-dev" aws s3 ls')"
check "aws_profile_only_effective_vouches" "2 2 2 2 2 2 2 2 2 2 2 2 2 2 2 2 2 2 2 2 2 2 2 | 0 0 0 0 0 0 0" "$AWS_GOT"

# A block that names no way forward costs a retry. Every BLOCKED message states what to run instead
# on a line of its own (`Instead:` or `Try:`) within the statement that prints it.
if [ "$ON" = 1 ]; then
  MISSING=$(awk '/BLOCKED/ && !/^[[:space:]]*#/ { if (n) print n; n = NR; ok = 0 }
    n && /(^|[^A-Za-z])(Instead|Try):/ { n = 0 }
    END { if (n) print n }' "$REAL_HOOK" | tr '\n' ' ')
  check "every BLOCKED message carries an Instead: or Try: line (unmatched at lines: ${MISSING:-none})" "" "$MISSING"
fi

echo
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
