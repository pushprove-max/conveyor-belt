#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# bash-guardrails.sh in a card's build or fix session: a call with no test command runs through
# conveyor/tools/outbrief.sh (issue #543). Long output of a `git diff`, a log or a search printed whole stays in every
# later turn of the session; the guard prints its start, its end and the path of a file with the whole output.
set -u
HOOK=$(cd "$(dirname "$0")/.." && pwd)/bash-guardrails.sh
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
mkdir -p "$T/p/.conveyor" "$T/p/sub" "$T/tmp"
printf '%s\n' '{"test": {"command": "bash t/all.sh"}}' > "$T/p/.conveyor/project.json"
FAIL=0
. "$(dirname "${BASH_SOURCE[0]}")/lib/said.sh" # a FAIL line names the hook's last input
# The input comes first and the line stays one line: a failure log reader takes FAIL lines and cuts them at 400 characters.
fail() { local m=$1; echo "FAIL$(said) ${m//$'\n'/\\n}"; FAIL=1; }
# guard <command>: the hook's exit in RC and its stdout in OUT.
guard() {
  RC=0
  OUT=$(jq -cn --arg c "$1" --arg d "$T/p" '{tool_input: {command: $c}, cwd: $d, session_id: "s1"}' \
    | (cd "$T/p" && CONVEYOR_CARD=c1 CLAUDE_PROJECT_DIR=$T/p CONVEYOR_GUARD_STATE=$T/state bash "$HOOK") 2> "$T/err") || RC=$?
}
# run <command> [<text after it>]: the command as the guard rewrote it (or as written, when it was not), then the
# text after it, in one shell as the session's runs them; what the session sees in $T/run.out, the exit in RUN_RC.
run() {
  local c; c=$(jq -r '.hookSpecificOutput.updatedInput.command // empty' <<<"$OUT"); c=${c:-$1}
  # CONVEYOR_BRIEFS: the card's own folder for kept outputs, as conveyor/lib/session.sh builder() names it.
  RUN_RC=0; (cd "$T/p" && TMPDIR=$T/tmp CONVEYOR_BRIEFS=$T/keep bash -c "$c${2:+$'\n'$2}") > "$T/run.out" 2>&1 || RUN_RC=$?
}
LONG="seq -f 'line %g' 2000; exit 4"
seq -f 'line %g' 2000 > "$T/whole"

# D1. Bug caught: a non-test command's 2,000 lines reached the session whole. The session sees the first 60 lines, the
# count left out, the last 40 lines and the saved file's path; the file holds the whole output; the exit code stays 4.
guard "$LONG"; run "$LONG"
SAVED=$(sed -n 's/^outbrief: exit 4; the whole output (2000 lines, [0-9]* characters) is in \([^;]*\);.*/\1/p' "$T/run.out")
{ [ "$RC" = 0 ] && [ "$RUN_RC" = 4 ] && [ "$(head -n 60 "$T/run.out")" = "$(seq -f 'line %g' 60)" ] \
  && [ "$(sed -n 61p "$T/run.out")" = 'outbrief: ... 1900 line(s) left out; lines 61 to 1960 are in the file below ...' ] \
  && [ "$(sed -n 62,101p "$T/run.out")" = "$(seq -f 'line %g' 1961 2000)" ] && [ "$(wc -l < "$T/run.out")" = 102 ]; } \
  || fail "a 2,000-line command (guard exit $RC, run exit $RUN_RC, not 4) did not print its start, the count left out and its end: $(head -c 600 "$T/run.out")"
[ -n "$SAVED" ] && cmp -s "$SAVED" "$T/whole" || fail "the brief does not give a file with the whole output: $(tail -n 1 "$T/run.out")"

# D2. Bug caught: a session that needs the middle could not get it printed. A call that names CONVEYOR_WHOLE=1 is not
# rewritten and prints whole.
guard "CONVEYOR_WHOLE=1 $LONG"; run "CONVEYOR_WHOLE=1 $LONG"
{ [ -z "$OUT" ] && [ "$RUN_RC" = 4 ] && cmp -s "$T/run.out" "$T/whole"; } \
  || fail "a call with CONVEYOR_WHOLE=1 was rewritten ($OUT) or did not print whole (exit $RUN_RC): $(head -c 300 "$T/run.out")"

# D3. Bug caught: a command after a pipe read the shortened output. Only what reaches the session is shortened.
guard "seq -f 'line %g' 2000 | wc -l"; run x
[ "$(tr -d ' ' < "$T/run.out")" = 2000 ] || fail "wc -l after a pipe did not count the whole output: $(head -c 300 "$T/run.out")"

# Bug caught: the session's shell no longer moved with a cd in the call, so its next call ran in the old directory;
# or a short output was not printed whole, or its files were left behind. Bug caught (#1238): D1's kept file was
# left in $TMPDIR, where nothing removed it (6,402 filled /tmp); it is in the card's folder, $T/keep, alone.
guard 'cd sub && echo short'; run x 'pwd -P'
{ [ "$(cat "$T/run.out")" = "short"$'\n'"$(cd "$T/p/sub" && pwd -P)" ] && [ -z "$(ls -A "$T/tmp")" ] && [ "$SAVED" = "$T/keep/$(ls "$T/keep")" ]; } \
  || fail "a cd in a rewritten call did not move the shell, the short output was not whole or its file kept, or D1's kept file ($SAVED) is not in the card's folder alone, with none in \$TMPDIR: $(cat "$T/run.out"); tmp: $(ls -A "$T/tmp"); keep: $(ls -A "$T/keep")"
# Bug caught: a search over the checkout root, which the guard rewrites and exits on before the brief above, printed
# up to 200 lines of long output and saved no copy. It is shortened the same way, its whole output in the saved file.
git -C "$T/p" init -q && cp "$T/whole" "$T/p/sub/many.txt"
guard 'rg --no-filename --no-line-number line'; run x
SAVED=$(sed -n 's/^outbrief: exit 0; the whole output (2000 lines, [0-9]* characters) is in \([^;]*\);.*/\1/p' "$T/run.out")
{ [ "$RC" = 0 ] && [ "$RUN_RC" = 0 ] && [ -n "$SAVED" ] && [ "$(wc -l < "$T/run.out")" = 102 ] \
  && cmp -s "$SAVED" "$T/whole"; } \
  || fail "a rewritten root search (guard exit $RC, run exit $RUN_RC) was not shortened with its whole output saved: $(head -c 300 "$T/run.out")"
[ "$FAIL" = 0 ] && echo "ok   long output of a non-test command is shortened"
exit $FAIL
