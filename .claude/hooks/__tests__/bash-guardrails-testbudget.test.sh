#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# bash-guardrails.sh in a card's build or fix session: the session test budget (conveyor/README.md, The session test
# budget). The guard runs each test command it lets through behind a trap that adds the call's CPU seconds to the
# session's ledger, and refuses the session's next test command once the ledger is over the pack's test.sessionBudget.
# Without it a session could rerun tests without end: one build session ran browser cases 21 times in an hour.
set -u
HOOK=$(cd "$(dirname "$0")/.." && pwd)/bash-guardrails.sh
T=$(mktemp -d); SID3=s3-$$-$RANDOM; trap 'chmod -R u+w "$T"; rm -rf "$T" /tmp/conveyor-test-budget-"$(id -u)"/c1-"$SID3"*' EXIT
mkdir -p "$T/p/.conveyor" "$T/p/t" "$T/state" "$T/home"
printf '%s\n' '{"test": {"command": "CI=1 timeout 600 bash t/all.sh", "changed": "t/changed.sh", "sessionBudget": 1}}' > "$T/p/.conveyor/project.json"
# A test file that uses <$1> CPU s, over the 1 s budget, and fails: the rewrite must keep its exit status. It burns until
# its own user time says so, so a busy machine makes it slower, never short of its CPU.
cat > "$T/p/t/slow.test.sh" <<'EOF'
f=$(mktemp)
until times > "$f" && awk -v n="$1" 'NR == 1 { split($1, a, "m"); exit !(a[1] * 60 + a[2] > n) }' "$f"; do
  for i in {1..20000}; do :; done
done
rm -f "$f"; exit 3
EOF
# A test file that waits 2 s, over the budget in clock seconds, and uses no CPU.
printf '%s\n' 'sleep 2' > "$T/p/t/wait.test.sh"
FAIL=0
. "$(dirname "${BASH_SOURCE[0]}")/lib/said.sh" # a FAIL line names the hook's last input
# The input comes first and the line stays one line: a failure log reader takes FAIL lines and cuts them at 400 characters.
fail() { local m=$1; echo "FAIL$(said) ${m//$'\n'/\\n}"; FAIL=1; }
# guard <session id> <command>: the hook's exit in RC, its stdout in OUT, its stderr in $T/err. Its state folder is
# STATE; an empty STATE gives the hook's default.
STATE=$T/state
guard() {
  RC=0
  OUT=$(jq -cn --arg c "$2" --arg d "$T/p" --arg s "$1" '{tool_input: {command: $c}, cwd: $d, session_id: $s}' \
    | (cd "$T/p" && CONVEYOR_CARD=c1 CLAUDE_PROJECT_DIR=$T/p CONVEYOR_GUARD_STATE=$STATE HOME=$T/home bash "$HOOK") 2> "$T/err") || RC=$?
}
# run [<shell>]: the command as the guard rewrote it, run by <shell> (bash by default) as the session's shell runs it;
# what the session sees in $T/run.out.
run() { RUN_RC=0; (cd "$T/p" && "${1:-bash}" -c "$(jq -r '.hookSpecificOutput.updatedInput.command' <<<"$OUT")") > "$T/run.out" 2>&1 || RUN_RC=$?; }
refused() { # <session id> <command> <why it matters>
  guard "$1" "$2"
  if [ "$RC" = 2 ] && grep -qF 'over its test budget of 1 CPU s' "$T/err" && grep -qF 'stop and report what you know' "$T/err"; then echo "ok   refused: $2"
  else fail "$2 (exit $RC, wanted 2 with the budget message): $3"; sed 's/^/     /' "$T/err"; fi
}

# The budget is CPU seconds: a test that waits 2 s spends none of the 1 s budget.
guard s1 'bash t/wait.test.sh'
run
# A test run under the budget runs, timed, and keeps its own exit status.
guard s1 'bash t/slow.test.sh 1.2'
[ "$RC" = 0 ] || fail "a test run after one that waited 2 s was refused (exit $RC): the budget counted clock seconds, not CPU"
run
[ "$RUN_RC" = 3 ] || fail "the timed test run exited $RUN_RC, not its own 3: the rewrite hid a failing test"
# Over the budget, the next test command is refused, in each form the guard counts.
refused s1 'bash t/slow.test.sh 1.2' 'a session over its test budget ran its tests again'
refused s1 'node --max-old-space-size=4096 --test t/a.test.mjs' 'node --test is a test run as well'
refused s1 'python3 -m pytest t' 'pytest behind python3 -m is a test run as well'
# A non-test command still runs, not timed (it is run through outbrief.sh, issue #543).
guard s1 'ls t'
{ [ "$RC" = 0 ] && ! grep -qF '__cv_end' <<<"$OUT"; } || fail "ls after the budget was spent (exit $RC, output $OUT): only test commands are refused or timed"
# A new session starts at 0.
guard s2 'bash t/slow.test.sh 1.2'
[ "$RC" = 0 ] || fail "a new session's first test run was refused (exit $RC): the budget is per session"

# Bug caught: a plain test command printed its whole log into the session, which then stayed in every later turn
# (issue #540). The guard runs it through the short-summary wrapper (conveyor/tools/testbrief.sh): the session sees the
# failure and the log's path, not the 2,000 lines of noise, and the command's own exit status.
printf '%s\n' 'for i in $(seq 2000); do echo "noise $i"; done; echo "FAIL [one]: broke"; exit 3' > "$T/p/t/long.test.sh"
guard s4 'bash t/long.test.sh'
WRAPPED=$(jq -r '.hookSpecificOutput.updatedInput.command' <<<"$OUT")
grep -qF 'conveyor/tools/testbrief.sh'"'"' --from "$__cv_t" --rc "$__cv_r"' <<<"$WRAPPED" \
  || fail "a plain test command was not rewritten to go through testbrief.sh: $OUT"
# Bug caught (issue #967): the rewrite handed its output file to testbrief.sh through `sh -c '...; rm -f "$1"; ...'`,
# and Claude Code refuses a `sh -c` script that runs rm, so no test call ran. The call has no `sh -c`, and the wrapper
# (from `__cv_test() {` on; the budget's EXIT trap above it is plain shell text) has no rm.
{ ! grep -qF 'sh -c' <<<"$WRAPPED" && ! sed -n '/^__cv_test() {$/,$p' <<<"$WRAPPED" | sed 1,2d | grep -qE '(^|[^[:alnum:]_])rm( |$)'; } \
  || fail "the rewritten test call has a sh -c script or an rm in its wrapper: $WRAPPED"
# Bug caught (issue #873): the rewrite ran the call as an `export -f` function in a child bash. zsh, the session's
# shell on macOS, exports no function, so every test call failed with `__cv_test: command not found` (127). The
# rewritten call must run, with the call's exit code, under bash, under sh (which has no `export -f` either) and
# under zsh when it is installed. Each run has its own $TMPDIR, which must hold only the brief's log after it (#967:
# testbrief.sh --from removes the output file the session's shell wrote).
for sh in bash sh zsh; do
  command -v "$sh" > /dev/null || { echo "skip $sh is not installed"; continue; }
  mkdir "$T/tmp-$sh"; TMPDIR=$T/tmp-$sh run "$sh"
  { [ "$RUN_RC" = 3 ] && grep -qxF '2001:FAIL [one]: broke' "$T/run.out" && grep -q "^testbrief: exit 3; the whole output (2001 lines) is in $T/tmp-$sh/testbrief\." "$T/run.out" \
    && [ "$(wc -l < "$T/run.out")" -le 20 ]; } || fail "the wrapped test run under $sh (exit $RUN_RC) did not run the call and print only the brief: $(head -c 600 "$T/run.out")"
  [ -z "$(find "$T/tmp-$sh" -mindepth 1 ! -name 'testbrief.*')" ] || fail "the wrapped test run under $sh left a file under \$TMPDIR besides the brief's log: $(ls "$T/tmp-$sh")"
done
# One already through the engine's wrapper is not wrapped again, and its time still counts to the budget.
TB=$(cd "$(dirname "$0")/../../../conveyor/tools" && pwd -P)/testbrief.sh
guard s4 "$TB -- bash t/long.test.sh"
{ [ "$RC" = 0 ] && ! grep -qF '__cv_test' <<<"$OUT" && grep -qF '__cv_end' <<<"$OUT"; } \
  || fail "a test command already through testbrief.sh was wrapped again, or not timed: $OUT"
# A wrapper of another name's file, or the engine's on another segment of the call, does not excuse a plain test run.
printf '%s\n' 'cat' > "$T/p/t/testbrief.sh"
for c in 'bash t/testbrief.sh -- bash t/long.test.sh' "$TB -- true; bash t/long.test.sh"; do
  guard s4 "$c"
  grep -qF '__cv_test' <<<"$OUT" || fail "$c was not run through the engine's testbrief.sh: $OUT"
done
# Bug caught: the pack's own test commands (test.command, test.changed; this repository's is
# `bash .conveyor/test-changed.sh`) have no test runner's name, so they printed their whole output. They are wrapped
# too, and not timed: the budget counts what it counted before.
for c in 'bash t/all.sh' './t/changed.sh'; do
  guard s5 "$c"
  { [ "$RC" = 0 ] && grep -qF '__cv_test' <<<"$OUT" && ! grep -qF '__cv_end' <<<"$OUT"; } \
    || fail "the pack's test command $c was not run through testbrief.sh, or was timed: $OUT"
done

# A test left running in the background counts once it ends: the card's own pattern for a long run is `( ... ) &`.
# Its CPU is sampled each second, so it uses 2.5 CPU s: its last second is not seen.
# This session has the default state folder and a home it cannot write in, as in a Codex session's sandbox, which lets
# it write in the worktree, /tmp and $TMPDIR only: its ledger must still be written, under /tmp.
STATE=''; chmod a-w "$T/home"
guard "$SID3" '(bash t/slow.test.sh 2.5 > /dev/null 2>&1) &'
[ "$RC" = 0 ] || fail "the background test run was refused (exit $RC)"
run
i=0; while ! [ -s "$(ls /tmp/conveyor-test-budget-"$(id -u)"/c1-"$SID3"*.testsec 2>/dev/null)" ] && [ $i -lt 100 ]; do sleep 0.2; i=$((i + 1)); done
refused "$SID3" 'bash t/slow.test.sh 1.2' 'the CPU of a background test run was not counted when it ended, or its ledger was not under /tmp, where a Codex sandbox can write'
[ "$FAIL" = 0 ] && echo "ok   session test budget"
exit $FAIL
