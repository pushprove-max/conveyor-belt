#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Refutation tests for repo-wide search classification: every path a search
# names must be bounded, and a search with no path must read piped input.
set -u

HOOK="$(cd "$(dirname "$0")/.." && pwd)/bash-guardrails.sh"
PASS=0 FAIL=0
# A log directory with no checkout in it. The real /tmp/conveyor can hold git
# clones, and a folder holding one is rightly refused as a repo walk. In the scratch space the hook knows
# (bash-guardrails.sh): in this run's TMPDIR when that is in it, so the suite, which removes the TMPDIR it gave, removes
# the folder though the file is stopped (.conveyor/test-full-tmp.test.sh); else under /tmp, as a TMPDIR under $HOME is
# no scratch space, and its searches are rewritten.
case $(cd "${TMPDIR:-/tmp}" 2> /dev/null && pwd -P)/ in
  /tmp/* | /private/tmp/* | /var/folders/* | /private/var/folders/*) LOGS=$(mktemp -d) ;;
  *) LOGS=$(mktemp -d /tmp/pp-search-logs.XXXXXX) ;;
esac
trap 'rm -rf "$LOGS"' EXIT
. "$(dirname "${BASH_SOURCE[0]}")/lib/said.sh" # a FAIL line names the hook's last input (json notes each payload)
# Every case below runs from a throwaway MAIN checkout: a worker pane's unbounded path is rewritten (last section),
# main's is refused, and these cases pin the refusal.
MAINBOX=$(mktemp -d); trap 'rm -rf "$LOGS" "$MAINBOX"' EXIT
git -C "$MAINBOX" init -q; mkdir -p "$MAINBOX/src/services" "$MAINBOX/scripts/ci" "$MAINBOX/.claude"
: > "$MAINBOX/package.json"; : > "$MAINBOX/.gitignore"; : > "$MAINBOX/scripts/ci/lane-inputs.json"
cd "$MAINBOX" || exit 1
REPO_ROOT="$(git rev-parse --show-toplevel)"

run_hook() { echo "$1" | env -u GIT_DIR -u GIT_WORK_TREE -u GIT_COMMON_DIR "$HOOK" >/dev/null 2>&1; echo $?; }
# A FAIL line gives the input first and stays one line: a failure log reader takes FAIL lines and cuts them at 400 characters.
check() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); echo "ok   $1"; else FAIL=$((FAIL+1)); local m="$1 (expected $2, got $3)"; echo "FAIL$(said) ${m//$'\n'/\\n}"; fi }
json() { jq -cn --arg cmd "$1" '{tool_input:{command:$cmd}}' | said_tee; }
# A refused search must hand back a concrete search that passes: replay the
# refusal's `Try:` line through the same hook.
# Main's lone simple search over an unbounded path is never refused (G4): it runs from the checkout root, capped at 200 lines.
check_capped() { # label, command
  local OUT
  OUT=$(json "$2" | "$HOOK" 2>/dev/null; echo "rc=$?")
  check "$1" "0 capped" "${OUT##*rc=} $(grep -q 'head -n 200' <<<"$OUT" && echo capped || echo plain)"
}
check_try() { # label, command
  local OUT TRY
  OUT=$(json "$2" | "$HOOK" 2>&1 >/dev/null; echo "rc=$?")
  check "$1" 2 "${OUT##*rc=}"
  TRY=$(printf '%s\n' "$OUT" | sed -n 's/^Try: //p' | head -1)
  check "$1: the refusal names a Try: command" 1 "$([ -n "$TRY" ] && echo 1 || echo 0)"
  check "$1: its Try: command passes" 0 "$(run_hook "$(json "$TRY")")"
}

check "a single-quoted scoped path passes" 0 \
  "$(run_hook "$(json "rg -n 'foo' 'src/services'")")"
check "a quoted alternation is not a segment boundary" 0 \
  "$(run_hook "$(json "rg -n 'a|b' src/services")")"
check "rg reading piped input passes" 0 \
  "$(run_hook "$(json "printf 'foo\\n' | rg foo")")"
check "an || alternative is not a stdin feed" 2 \
  "$(run_hook "$(json "printf x || rg pattern")")"
check "a pipe into grep -r searches the cwd and blocks" 2 \
  "$(run_hook "$(json "printf x | grep -r pattern")")"
check "file listing with a scoped path passes" 0 \
  "$(run_hook "$(json 'rg --files src/services')")"
check "an attached long pattern option with a scoped path passes" 0 \
  "$(run_hook "$(json 'rg --regexp=foo src/services')")"
check "an attached short pattern option with a scoped path passes" 0 \
  "$(run_hook "$(json 'rg -efoo src/services')")"
check "an escaped quote keeps the scoped path separate" 0 \
  "$(run_hook "$(json 'rg -F "foo\"bar" src/services')")"
check "a top-level directory name alone passes" 0 \
  "$(run_hook "$(json 'rg foo .claude')")"
check_capped "a filename-shaped pattern with no path is rewritten and capped" \
  'rg package.json'
check "a variable-prefixed path passes with a warning (G4)" "0 plain" \
  "$(OUT=$(json 'rg -n foo "$ROOT/src/services"' | "$HOOK" 2>/dev/null; echo "rc=$?"); echo "${OUT##*rc=} $(grep -q 'head -n 200' <<<"$OUT" && echo capped || echo plain)")"
check_capped "the current checkout root is rewritten and capped" \
  "rg foo \"$REPO_ROOT\""
check_capped "dot-slash alone is rewritten and capped" \
  'rg foo ./'
check "an escaped quote before an alternation keeps one quoted span; the scoped path passes" 0 \
  "$(run_hook "$(json 'grep -rnoE "test-isolation[^ \"]*|test-concurrency[^ \"]*" package.json scripts/ci')")"
check_try "the same escaped alternation with no path still blocks" \
  'grep -rnoE "test-isolation[^ \"]*|test-concurrency[^ \"]*"'
# An exact-file operand reads one file, so it is bounded however it is spelled.
# A root-level file has no slash and no top-level directory to match, which is
# why the directory rule alone refused `.gitignore`.
check "an exact root-level dotfile operand passes" 0 \
  "$(run_hook "$(json 'rg foo .gitignore')")"
check "an exact root-level file operand passes" 0 \
  "$(run_hook "$(json 'rg -n foo package.json')")"
# A missing file bounds the search to nothing; only a root-like path widens it.
check "an operand naming no existing file passes" 0 \
  "$(run_hook "$(json 'rg foo nosuchfile.txt')")"

# --- bounded absolute paths, and the roots that stay refused -----------------
# An absolute path is bounded unless it is a checkout root, a parent of one, or
# a spelling that normalizes to one. Refusing every absolute path blocked the
# logged searches of /tmp/conveyor logs (S1-S3) for no benefit.
check "an absolute path into the checkout passes" 0 \
  "$(run_hook "$(json "rg foo $REPO_ROOT/src/services")")"
check_capped "the checkout root with a trailing slash is rewritten and capped" \
  "rg foo $REPO_ROOT/"
check_capped "the checkout root spelled with /. is rewritten and capped" \
  "rg foo $REPO_ROOT/."
check_capped "a subdirectory climbing back to the root is rewritten and capped" \
  "rg foo $REPO_ROOT/src/.."
check_capped "a relative path normalizing to the root is rewritten and capped" \
  'rg foo src/..'
check_capped "the filesystem root is rewritten and capped" \
  'rg foo /'
check_capped "a parent of the checkout is rewritten and capped" \
  "rg foo $(dirname "$REPO_ROOT")"
# Two levels up holds no checkout directly, so only the ancestor test sees it.
check_capped "a grandparent of the checkout is rewritten and capped" \
  "rg foo $(dirname "$(dirname "$REPO_ROOT")")"
# The homes directory: /home on Linux, /Users on macOS.
check_capped "a bare wildcard directory is rewritten and capped" \
  "rg foo '$(dirname "$HOME")/*'"
check_capped "a slash in the pattern is not a path: rewritten and capped" \
  "rg 'src/services'"
check_capped "a scoped path beside a root operand: the root is rewritten and capped" \
  'rg foo . src'
check_capped "a glob option value is not a path: rewritten and capped" \
  "rg foo -g '*.ts'"
check_try "a piped rg that names the root still searches the root" \
  'cat x.log | rg foo .'
check "a quoted pattern with a space is one pattern" 0 \
  "$(run_hook "$(json "rg -n 'foo bar' src/services")")"
check "a glob option beside a scoped path passes" 0 \
  "$(run_hook "$(json "rg foo -g '*.ts' src")")"
check "a literal alias to a log directory passes" 0 \
  "$(run_hook "$(json "L=$LOGS; rg foo \"\$L\"")")"
check_try "a literal alias to dot blocks" \
  'L=.; rg foo "$L"'
check_try "a for-list over the root blocks" \
  'for f in .; do rg foo "$f"; done'
check_try "a multi-word for-list is not resolved and blocks" \
  'for f in /tmp/a .; do rg foo "$f"; done'

# The logged calls. S3 names a log its own first line creates, so the file is
# not on disk when the hook runs.
S1=$(cat <<'EOF'
for f in /tmp/conveyor/u1201-chain-scope-fix-r1-{focused,shell,changed,typecheck,guards,static}.log; do printf '%s\n' "$f"; rg -n "^(ℹ (tests|pass|fail)|pass [0-9]+, fail|test-changed:|> sample-project|Error:|FAIL|PASS|[[:space:]]*[0-9]+ passing|[[:space:]]*[0-9]+ failing)" "$f" | tail -n 12; done
rg -n '"typecheck-root"|"\.claude/"|"keep"' scripts/ci/lane-inputs.json
sed -n '1,70p' scripts/ci/lane-inputs.json
EOF
)
S2=$(cat <<'EOF'
rg -n "EROFS: read-only file system|Test Files[[:space:]]+[0-9]+ passed|Tests[[:space:]]+[0-9]+ passed|ℹ tests [0-9]+|ℹ pass [0-9]+|ℹ fail [0-9]+|ℹ skipped [0-9]+|error TS[0-9]+|STEP |FINAL_STATUSES" /tmp/conveyor -g 'u1206-*.log'; printf 'web-changed-tail: '; tail -n 8 /tmp/conveyor/u1206-web-changed-runner.log | tr '\n' ';'; printf '\ndiff-check-bytes: '; wc -c < /tmp/conveyor/u1206-diff-check.log
EOF
)
S3=$(cat <<'EOF'
npm --prefix infra test -- --runInBand --runTestsByPath test/verification-idle-sweep.test.ts > /tmp/conveyor/u1210-mutation-count.log 2>&1
status=$?
rg -n 'Expected|Received|functions|permissions|Test Suites:|Tests:|Snapshots:|Time:' /tmp/conveyor/u1210-mutation-count.log | tail -n 20
printf 'status=%s\n' "$status"
exit 0
EOF
)
check "S1: a for-list log binding passes" 0 "$(run_hook "$(json "$S1")")"
check "S2: an absolute log directory with a filename glob passes" 0 "$(run_hook "$(json "${S2//\/tmp\/conveyor/$LOGS}")")"
# S3 pins the search rule; from main's checkout the long-job rule refuses its `npm --prefix infra test` first.
check "S3: a log this call creates passes" 0 "$(CONVEYOR_REVIEWER=1 run_hook "$(json "$S3")")"

# --- worker panes: an unbounded path is rewritten to the checkout root, output capped (G1); main and $var stay refused ---
# A throwaway main checkout and a linked worktree of it: the hook tells them apart by git-dir vs git-common-dir.
GBOX=$(mktemp -d); trap 'rm -rf "$LOGS" "$MAINBOX" "$GBOX"' EXIT
git -C "$GBOX" init -q -b main main; git -C "$GBOX/main" -c user.name=t -c user.email=t@t commit -q --allow-empty -m init
git -C "$GBOX/main" worktree add -q "$GBOX/wt" -b u1
in_dir() { (cd "$1" && json "$2" | env -u GIT_DIR -u GIT_WORK_TREE -u GIT_COMMON_DIR "$HOOK" 2>/dev/null); }
WT_ROOT=$(cd "$GBOX/wt" && git rev-parse --show-toplevel)
WL="worker root rewrite capped; main still blocked; \$f still blocked"
OUT=$(in_dir "$GBOX/wt" "rg -n foo")
check "$WL: no path becomes the root, capped" "( set -o pipefail; { 'rg' '-n' 'foo' '$WT_ROOT'; } 2>&1 | { head -n 200; cat >/dev/null; } )" "$(jq -r '.hookSpecificOutput.updatedInput.command' <<<"$OUT")"
check "$WL: no permissionDecision" false "$(jq -r '.hookSpecificOutput | has("permissionDecision")' <<<"$OUT")"
check "$WL: dot becomes the root, capped" "( set -o pipefail; { 'rg' 'foo' '$WT_ROOT'; } 2>&1 | { head -n 200; cat >/dev/null; } )" \
  "$(in_dir "$GBOX/wt" 'rg foo .' | jq -r '.hookSpecificOutput.updatedInput.command')"
check "$WL: a literal parent becomes the root, capped" "( set -o pipefail; { 'rg' 'foo' '$WT_ROOT'; } 2>&1 | { head -n 200; cat >/dev/null; } )" \
  "$(in_dir "$GBOX/wt" "rg foo $GBOX" | jq -r '.hookSpecificOutput.updatedInput.command')"
check "$WL: main is rewritten and capped too" "( set -o pipefail; { 'rg' 'foo' '$(cd "$GBOX/main" && git rev-parse --show-toplevel)'; } 2>&1 | { head -n 200; cat >/dev/null; } )" \
  "$(in_dir "$GBOX/main" 'rg foo .' | jq -r '.hookSpecificOutput.updatedInput.command')"
check "$WL: \$f passes with a warning (G4)" "0 computed" "$(in_dir "$GBOX/wt" 'rg foo "$f"' | jq -r '.hookSpecificOutput.additionalContext' | sed 's/.*\(computed\).*/0 \1/')"
# A rewrite runs a different search than the one asked for when it leaves an unbounded operand or re-quotes what the
# shell would expand; those stay refused.
RW="a rewrite never changes what the search covers or matches"
check "$RW: a second unbounded operand" 2 "$(in_dir "$GBOX/wt" 'rg -n foo . /' >/dev/null; echo $?)"
check "$RW: a variable pattern" 2 "$(in_dir "$GBOX/wt" 'rg -n "$needle" .' >/dev/null; echo $?)"
check "$RW: an unquoted glob" 2 "$(in_dir "$GBOX/wt" 'rg foo* .' >/dev/null; echo $?)"

# A rewrite replaces the call's text, so it must run exactly what the call would: anything the shell would expand,
# split or run, and any discarded stage that writes or runs, keeps the refusal the call had before the rewrite.
RR="a rewrite runs exactly what the call would"
refused_worker() { # <label> <dir> <command>
  local O; O=$(in_dir "$2" "$3"; echo "rc=$?")
  check "$RR: $1" "refused rc=2" "$(grep -q updatedInput <<<"$O" && echo rewritten || echo refused) ${O##*$'\n'}"
}
refused_worker "a quote kind hiding a glob" "$GBOX/wt" "rg \"a'b\" * \"c'd\""
refused_worker "a command substitution pattern" "$GBOX/wt" 'rg -n "$(touch x)" .'
refused_worker "a backslash" "$GBOX/wt" 'rg -n a\ b .'
refused_worker "a second unbounded operand" "$GBOX/wt" 'rg -n foo . /'
refused_worker "a variable pattern" "$GBOX/wt" 'rg -n "$needle" .'
refused_worker "an unquoted glob" "$GBOX/wt" 'rg foo* .'
refused_worker "a command substitution from a plain checkout" "$GBOX/main" 'rg -n "$(touch x)" .'
refused_worker "mixed quotes and a glob from a plain checkout" "$GBOX/main" "rg \"a'b\" * \"c'd\""
refused_worker "a piped second command" "$GBOX/wt" 'rg -n foo . | sort -o /tmp/x'
check "$RR: a worker's rg -n foo . is still rewritten" "( set -o pipefail; { 'rg' '-n' 'foo' '$WT_ROOT'; } 2>&1 | { head -n 200; cat >/dev/null; } )" \
  "$(in_dir "$GBOX/wt" 'rg -n foo .' | jq -r '.hookSpecificOutput.updatedInput.command')"

# A capped search keeps rg's own exit: the cap must not turn "no match" (1) or "bad pattern" (2) into the exit of head,
# and a full 200-line cap must not surface as a SIGPIPE 141. The shell may be zsh, so each shell the box has is run.
seq 1 300 | sed 's/^/capline /' > "$GBOX/wt/capped-hits.txt"
CAPCASE="a capped search keeps rg's own exit"
for SH in bash zsh; do
  command -v "$SH" >/dev/null 2>&1 || continue
  # cap_run <rg args>: the rewritten command run in $SH from the worker checkout; prints "<exit> <output lines>".
  cap_run() {
    local RW_CMD OUTPUT RC
    RW_CMD=$(in_dir "$GBOX/wt" "rg $1 ." | jq -r '.hookSpecificOutput.updatedInput.command')
    OUTPUT=$(cd "$GBOX/wt" && "$SH" -c "$RW_CMD"); RC=$?
    echo "$RC $(printf '%s' "$OUTPUT" | grep -c '')"
  }
  check "$CAPCASE ($SH): no match exits 1" "1 0" "$(cap_run "-q 'a^'")"
  check "$CAPCASE ($SH): a bad pattern exits 2" 2 "$(cap_run "'['" | cut -d' ' -f1)"
  check "$CAPCASE ($SH): 300 matches exit 0 with exactly 200 lines" "0 200" "$(cap_run "capline")"
done

# --- main's searches are never refused (G4), judged from a checkout that does not live under scratch space ---
# The fixtures above sit in mktemp space, where the /tmp pass is off by design; this box is under $HOME.
PINBOX=$(mktemp -d "$HOME/.pp-search-pin.XXXXXX"); trap 'rm -rf "$LOGS" "$MAINBOX" "$GBOX" "$PINBOX"' EXIT
git -C "$PINBOX" init -q; : > "$PINBOX/package.json"
pin_out() { (cd "$PINBOX" && json "$1" | env -u GIT_DIR -u GIT_WORK_TREE -u GIT_COMMON_DIR "$HOOK" 2>/dev/null; echo "rc=$?"); }
git -C "$LOGS" init -q clone
OUT=$(pin_out "rg x $LOGS --glob '*.log'")
check "main_tmp_path_passes: a scratch directory holding a clone is searched as asked" "rc=0" "$(printf '%s\n' "$OUT" | tail -1)"
check "main_tmp_path_passes: and is not rewritten" 0 "$(grep -c updatedInput <<<"$OUT")"
OUT=$(pin_out 'rg x "$F"')
check "main_unresolved_var_warns: exits 0" "rc=0" "$(printf '%s\n' "$OUT" | tail -1)"
check "main_unresolved_var_warns: names the computed path" "0 computed" "$(head -1 <<<"$OUT" | jq -r '.hookSpecificOutput.additionalContext' | sed 's/.*\(computed\).*/0 \1/')"
OUT=$(pin_out 'rg foo')
check "main_no_path_rewritten_capped: the checkout root, 200 lines" "1 1" \
  "$(grep -c "'$PINBOX'" <<<"$OUT") $(grep -c 'head -n 200' <<<"$OUT")"
OUT=$(pin_out 'rg foo .')
check "root_search_capped: main's rg foo . is rewritten, 200 lines" "1 1" \
  "$(grep -c updatedInput <<<"$OUT") $(grep -c 'head -n 200' <<<"$OUT")"

# An assignment after && or || may never run, so it must not move the path a search is judged on.
# Catches: `false && F=/tmp/x; rg foo "$F"` resolved $F to /tmp/x and judged that path.
OUT=$(pin_out 'false && F=/tmp/x; rg foo "$F"')
check "assignment_after_and_never_judges_path" "rc=0 1" "$(printf '%s\n' "$OUT" | tail -1) $(grep -c computed <<<"$OUT")"
# Catches: the same for the || alternative.
OUT=$(pin_out 'true || F=/tmp/x; rg foo "$F"')
check "assignment_after_or_never_judges_path" "rc=0 1" "$(printf '%s\n' "$OUT" | tail -1) $(grep -c computed <<<"$OUT")"
# conditional_reassignment_drops_alias: catches (pass 15) an `&&`/`||` reassignment that kept the earlier alias, so
# `F=/tmp/x; true && F=.; rg foo "$F"` was judged as /tmp/x while it searches the checkout root.
# One hook call a check, so its FAIL line names the call that failed.
OUT=$(pin_out 'F=/tmp/x; true && F=.; rg foo "$F"')
check "conditional_reassignment_drops_alias: after &&, \$F is judged computed, never /tmp/x" "rc=0 1" \
  "$(printf '%s\n' "$OUT" | tail -1) $(grep -c computed <<<"$OUT")"
OUT=$(pin_out 'F=/tmp/x; false || F=.; rg foo "$F"')
check "conditional_reassignment_drops_alias: after ||, \$F is judged computed, never /tmp/x" "rc=0 1" \
  "$(printf '%s\n' "$OUT" | tail -1) $(grep -c computed <<<"$OUT")"
# Pin (passes today): a `;` assignment always runs, so it still resolves and the path is judged as named.
OUT=$(pin_out 'F=/tmp/x; rg foo "$F"')
check "assignment_after_semicolon_still_resolves" "rc=0 0" "$(printf '%s\n' "$OUT" | tail -1) $(grep -c computed <<<"$OUT")"

echo
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
