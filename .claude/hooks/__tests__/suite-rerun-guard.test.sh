#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Self-test for suite-rerun-guard.sh. Run directly.
#
# The narrowing it pins, three parts:
#   - only a run that FINISHED blocks the next one. The record used to be
#     written before the command ran, so a call another hook refused, or one the
#     operator interrupted, left "you already ran this" behind for a run that
#     never started -- and the tree stayed stranded for 30 minutes.
#   - the key is the EFFECTIVE directory. `cd infra && npm run test:unit` runs a
#     different suite over a different tree than the same words at the root, and
#     both were keyed to the root.
#   - the `cd` prefix is still stripped from the command TEXT, so the same run
#     spelled with and without it is one key when the directory is the same.
set -u

HOOK="$(cd "$(dirname "$0")/.." && pwd)/suite-rerun-guard.sh"
PASS=0 FAIL=0
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
export CONVEYOR_SUITE_RUNS_DIR="$TMP/state"

REPO="$TMP/repo"
mkdir -p "$REPO/infra"
git -C "$REPO" init -q
git -C "$REPO" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
echo 'export const a = 1;' > "$REPO/a.ts"
git -C "$REPO" add a.ts
git -C "$REPO" -c user.email=t@t -c user.name=t commit -q -m a

run_hook() { echo "$1" | bash "$HOOK" >/dev/null 2>&1; echo $?; }
# The PostToolUse half: what marks the attempt as a run that actually happened.
complete() { echo "$1" | bash "$HOOK" --record-complete >/dev/null 2>&1; }
# One finished run: the PreToolUse pass, then the completion record.
ran() { run_hook "$1" >/dev/null; complete "$1"; }
. "$(dirname "${BASH_SOURCE[0]}")/lib/said.sh" # a FAIL line names the hook's last input: each call is bash "$HOOK"
check() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); echo "ok   $1"; else FAIL=$((FAIL+1)); echo "FAIL $1 (expected $2, got $3)$(said)"; fi }
json() { jq -cn --arg cmd "$1" --arg cwd "${2:-$REPO}" '{tool_input:{command:$cmd},cwd:$cwd}'; }

# --- same run, same tree ----------------------------------------------------
FIRST=$(json 'npm run test:unit 2>&1 | tail -40')
check "first run passes" 0 "$(run_hook "$FIRST")"
complete "$FIRST"
check "same run, same tree, different pipe blocks" 2 \
  "$(run_hook "$(json 'npm run test:unit 2>&1 | grep -E "fail" | head -20')")"
check "same run behind a cd prefix is the same key" 2 \
  "$(run_hook "$(json "cd $REPO && npm run test:unit > /tmp/x.log")")"
check "RERUN=1 lets a flake check through" 0 \
  "$(run_hook "$(json 'RERUN=1 npm run test:unit 2>&1 | tail -5')")"
check "a different suite is a different run" 0 \
  "$(run_hook "$(json 'npm run test:guards 2>&1 | tail -40')")"
TSC=$(json 'npx tsc --noEmit -p tsconfig.json 2>&1 | head -20')
check "tsc is guarded too: first passes" 0 "$(run_hook "$TSC")"
complete "$TSC"
check "tsc rerun on the same tree blocks" 2 \
  "$(run_hook "$(json 'npx tsc --noEmit -p tsconfig.json 2>&1 | tail -3; echo done')")"
# The configured typecheck scripts are tsc runs by another name.
TYPECHECK=$(json 'npm run typecheck:backend 2>&1 | tail -20')
check "npm run typecheck is guarded too: first passes" 0 "$(run_hook "$TYPECHECK")"
complete "$TYPECHECK"
check "npm run typecheck rerun on the same tree blocks" 2 \
  "$(run_hook "$(json 'npm run typecheck:backend 2>&1 | head -5')")"

echo 'export const a = 2;' > "$REPO/a.ts"
check "an edit to a tracked file unlocks the rerun" 0 \
  "$(run_hook "$(json 'npm run test:unit 2>&1 | tail -40')")"
echo 'x' > "$REPO/new-untracked.ts"
UNTRACKED=$(json 'npm run test:unit 2>&1 | tail -40')
check "a new untracked file unlocks it too" 0 "$(run_hook "$UNTRACKED")"
complete "$UNTRACKED"
check "and the tree is fixed again after that" 2 \
  "$(run_hook "$(json 'npm run test:unit')")"

# Untracked input identity includes the path, not just concatenated bytes.
mv "$REPO/new-untracked.ts" "$REPO/renamed-untracked.ts"
check "renaming identical untracked bytes changes tested inputs" 0 "$(run_hook "$UNTRACKED")"
complete "$UNTRACKED"
check "the unchanged renamed input is blocked again"      2 "$(run_hook "$UNTRACKED")"

# Index state is independently meaningful even when the working bytes and
# HEAD diff stay unchanged.
INDEXED=$(json 'npm run test:guards')
check "a changed tracked input starts a guards run"        0 "$(run_hook "$INDEXED")"
complete "$INDEXED"
check "the unchanged tracked input is blocked again"      2 "$(run_hook "$INDEXED")"
git -C "$REPO" add a.ts
check "staging the same working bytes changes tested inputs" 0 "$(run_hook "$INDEXED")"
complete "$INDEXED"
check "the unchanged staged index is blocked again"       2 "$(run_hook "$INDEXED")"

# Completion retains the PRE-run fingerprint. A fixture changed while the
# command is in flight must unlock the next run rather than certify new bytes.
echo 'before-run' > "$REPO/pre-run.ts"
SNAPSHOT=$(json 'npm run test:unit')
check "a run starts against its pre-run snapshot"          0 "$(run_hook "$SNAPSHOT")"
echo 'during-run' > "$REPO/during-run.ts"
complete "$SNAPSHOT"
check "a change made during the run unlocks the next run"  0 "$(run_hook "$SNAPSHOT")"

# --- a run that never finished is not a run -----------------------------------
echo 'export const a = 3;' > "$REPO/a.ts"
ATTEMPT=$(json 'npm run test:unit')
check "an attempt on a fresh tree passes"                0 "$(run_hook "$ATTEMPT")"
check "the SAME attempt, never completed, passes again"  0 "$(run_hook "$ATTEMPT")"
complete "$ATTEMPT"
check "once it completes, the rerun blocks"              2 "$(run_hook "$ATTEMPT")"

echo 'export const a = 4;' > "$REPO/a.ts"
INTERRUPTED=$(jq -cn --arg cmd 'npm run test:unit' --arg cwd "$REPO" \
  '{tool_input:{command:$cmd},cwd:$cwd,tool_response:{interrupted:true}}')
check "an interrupted run passes on the way in"          0 "$(run_hook "$ATTEMPT")"
echo "$INTERRUPTED" | bash "$HOOK" --record-complete >/dev/null 2>&1
check "an interrupted run does not block the retry"      0 "$(run_hook "$ATTEMPT")"

# --- the key is the effective directory ---------------------------------------
# Same words, different place: the infra suite is not the root suite.
echo 'export const a = 5;' > "$REPO/a.ts"
git -C "$REPO/infra" init -q
git -C "$REPO/infra" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
ROOT_RUN=$(json 'npm run test:guards')
ran "$ROOT_RUN"
check "the same words in infra/ are a different run"     0 \
  "$(run_hook "$(json "cd infra && npm run test:guards")")"
check "and the root run is still blocked"                2 "$(run_hook "$ROOT_RUN")"

# --- a longer command is not a repeat of its first words --------------
# A full verification refused as "already ran" would be reported as passed
# without ever running.
SMALL=$(json 'LOG=/tmp/v.log; npm run test:unit 2>&1 | tee $LOG')
ran "$SMALL"
check "a later suite after the same first words is a new run" 0 \
  "$(run_hook "$(json 'LOG=/tmp/v.log; npm run test:unit 2>&1 | tee $LOG; npm run typecheck:backend')")"
check "and the smaller run itself still blocks" 2 "$(run_hook "$SMALL")"
# A quoted test-name filter picks which tests run, so it is part of the run.
NAMED=$(json 'npx vitest run src/x.test.tsx -t "first case"')
ran "$NAMED"
check "a different quoted test-name filter is a new run" 0 \
  "$(run_hook "$(json 'npx vitest run src/x.test.tsx -t "second case"')")"
check "and the same filter still blocks" 2 "$(run_hook "$NAMED")"

# --- the key keeps every argument and drops only redirections -----------------
# A value refused as "already ran" is a test never run; a redirection kept in
# the key lets the same run through again.
ran "$(json 'npx vitest run src/x.test.tsx -t 1')"
check "a different digit filter is a new run" 0 \
  "$(run_hook "$(json 'npx vitest run src/x.test.tsx -t 2')")"
ran "$(json 'npx vitest run src/x.test.tsx -t 1 2>/dev/null')"
check "a digit filter before an fd redirection is kept" 0 \
  "$(run_hook "$(json 'npx vitest run src/x.test.tsx -t 2 2>/dev/null')")"
ran "$(json 'npx vitest run src/x.test.tsx -t 1 > /tmp/a.log')"
check "a digit filter before a spaced redirection is kept" 0 \
  "$(run_hook "$(json 'npx vitest run src/x.test.tsx -t 2 > /tmp/a.log')")"
ran "$(json 'npx vitest run src/x1.test.tsx')"
check "a trailing digit in a file name is kept" 0 \
  "$(run_hook "$(json 'npx vitest run src/x2.test.tsx')")"
ran "$(json 'npx vitest run src/x.test.tsx -t=1')"
check "an -t=value filter is kept" 0 \
  "$(run_hook "$(json 'npx vitest run src/x.test.tsx -t=2')")"
ran "$(json 'npx vitest run src/x.test.tsx -t "a b"')"
check "one quoted filter is not two bare words" 0 \
  "$(run_hook "$(json 'npx vitest run src/x.test.tsx -t a b')")"
check "single and double quotes are the same filter" 2 \
  "$(run_hook "$(json "npx vitest run src/x.test.tsx -t 'a b'")")"
# A filter is a regex: its spacing is part of what it selects.
ran "$(json 'npx vitest run src/s.test.tsx -t "a  b"')"
check "a quoted filter that differs only in spacing is a new run" 0 \
  "$(run_hook "$(json 'npx vitest run src/s.test.tsx -t "a b"')")"
check "the same spaced filter again is the same run" 2 \
  "$(run_hook "$(json 'npx vitest run src/s.test.tsx -t "a  b"')")"
ran "$(json 'npx vitest run src/r.test.tsx -t 1')"
for redir in '2>&1 | tail -5' '>/tmp/o.log' '> /tmp/o.log' '2>/dev/null' \
  '2>> /tmp/o.log' '&>/tmp/o.log' '|& tail -5' '>| /tmp/o.log' '>&2'; do
  check "the same run with $redir blocks" 2 \
    "$(run_hook "$(json "npx vitest run src/r.test.tsx -t 1 $redir")")"
done

# --- a stale record (over 30 minutes) does not block --------------------------
for f in "$CONVEYOR_SUITE_RUNS_DIR"/*; do
  read -r _ tree < "$f"; printf '%s %s\n' "$(( $(date +%s) - 2000 ))" "$tree" > "$f"
done
check "a record older than 30 min passes" 0 \
  "$(run_hook "$(json 'npm run test:unit')")"

# --- bare npm test -----------------------------------------------------------
check "bare npm test blocks at the repo root" 2 \
  "$(run_hook "$(json 'npm test 2>&1 | tail -25')")"
check "npm test with a filter still blocks (only the infra leg gets it)" 2 \
  "$(run_hook "$(json 'npm test -- kms-grant-parity')")"
check "cd infra && npm test passes" 0 \
  "$(run_hook "$(json 'cd infra && npm test -- kms-grant-parity')")"
check "npm test from an infra cwd passes" 0 \
  "$(run_hook "$(json 'npm test' "$REPO/infra")")"
# A quoted message body that names a suite is prose, not a run.
PROSE=$(json 'orca-ide orchestration send --body "ran npm test then npm run test:unit"')
check "a quoted body naming npm test passes" 0 "$(run_hook "$PROSE")"
complete "$PROSE"
check "and is not keyed as a rerun once complete" 0 "$(run_hook "$PROSE")"
check "a real npm test segment after prose still blocks" 2 \
  "$(run_hook "$(json 'echo hi; npm test')")"

# --- not a suite -------------------------------------------------------------
check "an ordinary command passes" 0 \
  "$(run_hook "$(json 'git status --short')")"
check "a grep that mentions a suite name passes" 0 \
  "$(run_hook "$(json 'grep -n "test:unit" package.json')")"
check "test:changed is its own key, first run passes" 0 \
  "$(run_hook "$(json 'timeout 900 npm run test:changed 2>&1 | tail -10')")"

# --- builders leave the merge chain's checks to the chain -------------
# Two builders spent ~29 minutes in whole-project checks the merge chain runs
# anyway. A builder is a linked worktree seat; main and the chain never block.
# A fresh state dir keeps the rerun records above out of these cases.
export CONVEYOR_SUITE_RUNS_DIR="$TMP/state-chain"
WT="$TMP/wt"
git -C "$REPO" worktree add -q "$WT" -b wtb >/dev/null 2>&1
mkdir -p "$WT/web" "$REPO/web"
for C in 'npm run test:guards' 'npm --prefix web run test:guards' 'cd web && npm run test:guards' \
  'npm run test:unit' 'npm --prefix web run test:unit' 'cd web && npm run test:unit > /tmp/conveyor/u-1.log 2>&1' \
  'npm run --silent test:unit' 'npx vitest run' 'cd web && npx vitest run 2>&1 | tail -20' \
  'npx vitest run --config vitest.unit.config.ts' \
  'npm run test:coverage:gate' 'npm run --silent test:coverage' 'npm --prefix web run test:coverage' \
  'bash scripts/test-coverage.sh gate > /tmp/conveyor/c.log 2>&1'; do
  check "worktree: '$C' blocks" 2 "$(run_hook "$(json "$C" "$WT")")"
  check "main checkout: '$C' passes" 0 "$(run_hook "$(json "$C" "$REPO")")"
done
# The coverage gate's self-test compares fixture reports and runs no suite.
check "worktree: coverage gate self-test passes" 0 \
  "$(run_hook "$(json 'npm run test:coverage:gate:self-test' "$WT")")"
# npm appends `-- <file>` after the root script's full file list, so this still
# runs every test.
check "worktree: root npm run test:unit -- <file> blocks" 2 \
  "$(run_hook "$(json 'npm run test:unit -- src/x.test.ts' "$WT")")"
OUT=$(json 'npm run test:unit -- src/x.test.ts' "$WT" | bash "$HOOK" 2>&1 >/dev/null)
check "that block names the one-file command" 1 \
  "$([[ $OUT == *"node --max-old-space-size=4096 --test --require ts-node/register <file>"* ]] && echo 1 || echo 0)"
# The web test:unit integrity wrapper ignores file arguments, so naming one
# still runs the whole suite.
for C in 'npm --prefix web run test:unit -- src/a.test.tsx' 'cd web && npm run test:unit -- src/a.test.tsx'; do
  check "worktree: web test:unit wrapper with a file blocks: '$C'" 2 "$(run_hook "$(json "$C" "$WT")")"
done
OUT=$(json 'npm --prefix web run test:unit -- src/a.test.tsx' "$WT" | bash "$HOOK" 2>&1 >/dev/null)
check "that block names the raw one-file command" 1 \
  "$([[ $OUT == *"npm --prefix web run test:unit:raw -- src/x.test.tsx"* ]] && echo 1 || echo 0)"
check "worktree: bare web test:unit:raw blocks" 2 \
  "$(run_hook "$(json 'npm --prefix web run test:unit:raw' "$WT")")"
# npm options between `run` and the script, with or without a value, do not
# hide the script name.
check "worktree: npm option with a value after run still blocks" 2 \
  "$(run_hook "$(json 'npm run --prefix web test:unit:raw' "$WT")")"
check "worktree: and still lets one named file through" 0 \
  "$(run_hook "$(json 'npm run --prefix web --silent test:unit:raw -- src/a.test.tsx' "$WT")")"
# Named files narrow a raw web run, so a builder iterating on one test stays unblocked.
for C in 'npm --prefix web run test:unit:raw -- src/a.test.tsx' 'cd web && npm run test:unit:raw -- "src/a.test.tsx"' \
  'cd web && npx vitest run src/components/__tests__/A.test.tsx'; do
  check "worktree: named web test file passes: '$C'" 0 "$(run_hook "$(json "$C" "$WT")")"
done
# A Vitest flag with no value leaves the next word a file filter; an option
# that takes a value swallows it, so that run is still the whole suite.
for C in 'cd web && npx vitest run --no-isolate src/a.test.tsx' 'cd web && npx vitest run --coverage src/a.test.tsx' \
  'cd web && npx vitest run --passWithNoTests src/a.test.tsx' 'cd web && npx vitest run --sequence.shuffle src/a.test.tsx' \
  '(cd web && npm run test:unit:raw -- src/a.test.tsx)'; do
  check "worktree: file after a no-value flag passes: '$C'" 0 "$(run_hook "$(json "$C" "$WT")")"
done
for C in 'cd web && npx vitest run --project src/a.test.tsx' 'cd web && npx vitest run -u src/a.test.tsx' \
  'cd web && npx vitest run --coverage.exclude src/a.test.tsx'; do
  check "worktree: file as an option value blocks: '$C'" 2 "$(run_hook "$(json "$C" "$WT")")"
done
# A builder once ran the whole backend suite with coverage, twice, from a script
# file the command line never showed (cfp4-lcov.sh). The script's contents get
# the same checks, and the whole-suite file list under `node --test` is the
# coverage gate whether typed or scripted. Fixtures are trimmed copies.
cat > "$TMP/cfp4-lcov.sh" <<'EOF'
# Backend coverage run, same flags as scripts/test-coverage.sh backend, plus an lcov report
files="$(scripts/test-unit-files.sh --unit; scripts/test-unit-files.sh --guards)"
# shellcheck disable=SC2086
TS_NODE_TRANSPILE_ONLY=1 \
scripts/with-suite-lock.sh node \
  --max-old-space-size=4096 \
  --experimental-test-coverage \
  --test --test-timeout=120000 --test-concurrency=4 \
  --test-reporter=lcov --test-reporter-destination=/tmp/conveyor/cfp4-final.lcov \
  --require ts-node/register $files
echo "exit $?" >> /tmp/conveyor/cfp4-final-run.log
EOF
cat > "$TMP/cfp4-run.sh" <<'EOF'
# runs two tests with coverage + lcov, like the gate.
TS_NODE_TRANSPILE_ONLY=1 \
node --max-old-space-size=4096 --experimental-test-coverage --test --test-timeout=120000 \
  --test-reporter=lcov --test-reporter-destination="/tmp/conveyor/cfp4-run.lcov" \
  --require ts-node/register src/a.test.ts src/b.test.ts
echo "exit $?"
EOF
cat > "$TMP/cfp4-hist.sh" <<'EOF'
F=src/config/test-coverage-floor.json
for c in $(git log --format=%h -40 -- "$F"); do git show "$c:$F" | jq -c .; done
EOF
printf 'npm run test:guards > /tmp/conveyor/g.log 2>&1\n' > "$TMP/guards.sh"
chmod +x "$TMP/cfp4-lcov.sh"
INLINE='files="$(scripts/test-unit-files.sh --unit; scripts/test-unit-files.sh --guards)"; node --max-old-space-size=4096 --experimental-test-coverage --test --require ts-node/register $files'
for C in "bash $TMP/cfp4-lcov.sh" "cd $TMP && bash cfp4-lcov.sh > /tmp/conveyor/l.log 2>&1" "$TMP/cfp4-lcov.sh" \
  "source $TMP/cfp4-lcov.sh" "$INLINE" "bash $TMP/guards.sh" \
  'node --max-old-space-size=4096 --test --require ts-node/register $(scripts/test-unit-files.sh --unit)'; do
  check "worktree: whole suite, typed or scripted, blocks: '$C'" 2 "$(run_hook "$(json "$C" "$WT")")"
  check "main checkout: '$C' passes" 0 "$(run_hook "$(json "$C" "$REPO")")"
done
OUT=$(json "bash $TMP/cfp4-lcov.sh" "$WT" | bash "$HOOK" 2>&1 >/dev/null)
check "the scripted block is the coverage gate's rule 3 message" 1 \
  "$([[ $OUT == "BLOCKED: the coverage gate"*"_implementer-tools.md rule 3"* ]] && echo 1 || echo 0)"
for C in "bash $TMP/cfp4-run.sh" "bash $TMP/cfp4-hist.sh" 'scripts/test-unit-files.sh --unit | wc -l' \
  'orca orchestration send --body "the guard now blocks scripts/test-unit-files.sh under node --test"'; do
  check "worktree: targeted coverage or no test run passes: '$C'" 0 "$(run_hook "$(json "$C" "$WT")")"
done

OUT=$(json 'npm run test:coverage' "$WT" | bash "$HOOK" 2>&1 >/dev/null)
check "the coverage block says record and go on" 1 \
  "$([[ $OUT == *"Do not ask main: if you still need that check, record it as a main-only deferred item (one line under ## Main-only (deferred) in the evidence file) and go on." ]] && echo 1 || echo 0)"
for C in 'npm run test:guards' 'npm run test:unit' 'npm --prefix web run test:unit' 'npx vitest run'; do
  check "the whole-suite block for '$C' says do not ask main" 1 \
    "$(json "$C" "$WT" | bash "$HOOK" 2>&1 >/dev/null | grep -c 'Do not ask main: if you still need that check')"
done
OUT=$(json 'npm run test:guards' "$WT" | bash "$HOOK" 2>&1 >/dev/null)
check "the block is one line naming rule 3 and what to run" 1 \
  "$([ "$(printf '%s\n' "$OUT" | wc -l)" = 1 ] && [[ $OUT == *"_implementer-tools.md rule 3"*"Run instead: npm run test:changed"* ]] && echo 1 || echo 0)"
check "worktree: a quoted mention is text, not a run" 0 \
  "$(run_hook "$(json 'git commit -m "stop npm run test:guards in worktrees"' "$WT")")"
check "worktree: the PostToolUse half never blocks" 0 \
  "$(json 'npm run test:guards' "$WT" | bash "$HOOK" --record-complete >/dev/null 2>&1; echo $?)"
check "worktree: RERUN=1 does not excuse a full suite" 2 \
  "$(run_hook "$(json 'RERUN=1 npm run test:guards' "$WT")")"

# The tools note hands builders the named-file web command this hook's refusal
# offers, so a builder never tries the whole web test:unit first.
NOTE="$(dirname "$HOOK")/../briefs/_implementer-tools.md"
# The command as the refusal gives it (that it gives one is checked above, by "that block names the raw one-file command").
WEB_ONE=$(json 'npm --prefix web run test:unit -- src/a.test.tsx' "$WT" | bash "$HOOK" 2>&1 >/dev/null | sed -n 's/.*one file: \(.* -- \).*/\1/p')
check "the tools note gives the same one-file web command" 1 "$([ -n "$WEB_ONE" ] && grep -qF -- "$WEB_ONE" "$NOTE" && echo 1 || echo 0)"

# Python puts the working directory first on sys.path under -c, so a shlex.py in
# the project would run inside this hook. -I must keep it out.
PLANT="$TMP/plant"
mkdir -p "$PLANT"
printf 'open("%s/pwned", "w").close()\nraise SystemExit(0)\n' "$TMP" > "$PLANT/shlex.py"
PLANTED=$(json 'npm run test:unit 2>&1 | tail -9')
PLANT_RC=$(cd "$PLANT" && { echo "$PLANTED" | bash "$HOOK" >/dev/null 2>&1; echo "$PLANTED" | bash "$HOOK" --record-complete >/dev/null 2>&1; echo "$PLANTED" | bash "$HOOK" >/dev/null 2>&1; echo $?; })
check "a shlex.py in the working directory is not imported" 1 "$([ ! -e "$TMP/pwned" ] && echo 1 || echo 0)"
check "the guard still blocks a finished rerun with a shlex.py planted" 2 "$PLANT_RC"

# --- a worker sees its diff once before its first suite run ------------------------------------------------
# A linked worktree (the worker's), 21 untracked files and one committed change against main. The advice rides on the
# first suite run of a session as additionalContext, never blocks, and prints once per session even when two calls start
# together; main's checkout, a reviewer pane and a pane with no session_id (Codex) get nothing.
GREPO="$TMP/grepo" GWT="$TMP/gwt"
git init -q -b main "$GREPO"
git -C "$GREPO" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
git -C "$GREPO" worktree add -q -b unit "$GWT"
echo 'export const c = 1;' > "$GWT/changed.ts"
git -C "$GWT" add changed.ts; git -C "$GWT" -c user.email=t@t -c user.name=t commit -q -m work
echo x > "$GWT/a b.txt"; for i in $(seq -w 1 20); do echo x > "$GWT/f$i.txt"; done
jsid() { jq -cn --arg cmd "$1" --arg cwd "$2" --arg sid "$3" 'if $sid == "" then {tool_input:{command:$cmd},cwd:$cwd} else {tool_input:{command:$cmd},cwd:$cwd,session_id:$sid} end'; }
advice() { echo "$1" | bash "$HOOK" 2>/dev/null | jq -r '.hookSpecificOutput.additionalContext // empty'; }
TC='npm run typecheck:backend'
OUT1=$(advice "$(jsid "$TC" "$GWT" s-one)")
check "first suite run in a worktree prints the diffstat: the committed change is named" 1 "$(grep -c 'changed.ts' <<<"$OUT1")"
check "first suite run in a worktree: 20 untracked files are named, the 21st is a count of 1" "1 0 1" \
  "$(grep -c 'a b.txt' <<<"$OUT1") $(grep -c 'f20.txt' <<<"$OUT1") $(grep -c 'and 1 more' <<<"$OUT1")"
check "the second suite run of the same session prints nothing" "" "$(advice "$(jsid 'npm run typecheck:frontend' "$GWT" s-one)")"
check "a new session prints it again" 1 "$(advice "$(jsid "$TC" "$GWT" s-two)" | grep -c 'changed.ts')"
check "the advice never blocks" 0 "$(run_hook "$(jsid 'npm run typecheck:infra' "$GWT" s-three)")"
check "main's checkout prints nothing" "" "$(advice "$(jsid "$TC" "$REPO" s-main)")"
check "a reviewer pane prints nothing" "" "$(echo "$(jsid "$TC" "$GWT" s-rev)" | CONVEYOR_REVIEWER=1 bash "$HOOK" 2>/dev/null | jq -r '.hookSpecificOutput.additionalContext // empty')"
check "a pane with no session_id (Codex) prints nothing" "" "$(advice "$(jsid "$TC" "$GWT" "")")"
# Two first runs released together in one session: O_EXCL lets exactly one create the marker. Five rounds, each a fresh
# session, so a test-then-create marker would show 2 in at least one of them.
# One check a round. The rounds send one command and differ only in session id, which a FAIL line does not print, so
# the round number is in the check's name.
for r in 1 2 3 4 5; do
  P=$(jsid "$TC" "$GWT" "conc$r")
  for k in a b; do ( while [ ! -e "$TMP/gate$r" ]; do :; done; echo "$P" | bash "$HOOK" > "$TMP/conc$r$k" 2>/dev/null ) & done
  : > "$TMP/gate$r"; wait
  check "two first suite runs released at once in one session print the diffstat exactly once (round $r)" 1 \
    "$(cat "$TMP/conc$r"a "$TMP/conc$r"b | grep -c additionalContext)"
done

# The post-fix runner is a tracked script (seg_script does not inspect it), so it is keyed only by its npm name.
echo 'export const a = 5;' > "$REPO/a.ts"
POSTFIX=$(json 'npm run test:post-fix 2>&1 | tail -40')
check "test:post-fix first run passes" 0 "$(run_hook "$POSTFIX")"
complete "$POSTFIX"
check "test:post-fix repeat on an unchanged tree blocks" 2 "$(run_hook "$(json 'npm run test:post-fix > /tmp/x.log 2>&1')")"

# A heredoc ahead of `npm test` never hides it: any `<<` outside a comment reads line by line.
# Each row runs the hook with its own fresh state dir and the repo root as cwd.
srg_heredoc_rc() { # command -> the hook's exit status
  local root state rc=0
  root=$(git -C "$(dirname "$0")" rev-parse --show-toplevel)
  state=$(mktemp -d)
  jq -cn --arg c "$1" --arg cwd "$root" '{cwd:$cwd,tool_input:{command:$c}}' |
    CONVEYOR_HOOK_FIRE_LOG="$state/fires.jsonl" CONVEYOR_SUITE_RUNS_DIR="$state/state" bash "$HOOK" >/dev/null 2>&1 || rc=$?
  rm -rf "$state"
  echo "$rc"
}
# row: an apostrophe in the body, a comment after npm test
check "heredoc_npm_test_blocks" 2 \
  "$(srg_heredoc_rc $'cat <<EOF\nit\'s fine\nEOF\nnpm test\n# it\'s a follow-up comment')"
# row: a heredoc opener inside a comment
check "heredoc_comments_npm_test_blocks" 2 \
  "$(srg_heredoc_rc $'# cat <<EOF\nnpm test\nEOF')"
# row: a trailing comment on the opener line
check "heredoc_comments_npm_test_blocks" 2 \
  "$(srg_heredoc_rc $'cat <<EOF # bash\nit\'s fine\nEOF\nnpm test\n# it\'s a follow-up comment')"
# row: a single-quoted spaced delimiter
check "quoted_delimiters_npm_test_blocks" 2 \
  "$(srg_heredoc_rc $'cat <<\'a b\'\nit\'s fine\na b\nnpm test\n# it\'s a follow-up')"
# row: a double-quoted spaced delimiter
check "quoted_delimiters_npm_test_blocks" 2 \
  "$(srg_heredoc_rc $'cat <<"a b"\nit\'s fine\na b\nnpm test\n# it\'s a follow-up')"
# row: a partly quoted delimiter
check "quoted_delimiters_npm_test_blocks" 2 \
  "$(srg_heredoc_rc $'cat <<E\'O\'F\nit\'s fine\nEOF\nnpm test\n# it\'s a follow-up')"
# row: a backslash-escaped delimiter
check "quoted_delimiters_npm_test_blocks" 2 \
  "$(srg_heredoc_rc $'cat <<\\E\\O\\F\nit\'s fine\nEOF\nnpm test\n# it\'s a follow-up')"

echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
