#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 60
# The Foreman's filing hook (foreman.sh filing, no_cause) refuses a fix issue with no `## Cause` section (#1293).
# Bug caught: the Foreman filed a fix that named a symptom ("the reader is over its size cap") and never the source of
# the problem, because nothing in the filing path asked for the cause.
set -uo pipefail
SRC=$(cd "$(dirname "$0")" && pwd -P)
B=$(mktemp -d) || exit 1
trap 'rm -rf "$B"' EXIT
cd "$B" || exit 1
unset CONVEYOR_FOREMAN CONVEYOR_FOREMAN_DIR CONVEYOR_FOREMAN_ASK CONVEYOR_LANE CONVEYOR_MAIN CONVEYOR_MACHINE_ID CLAUDE_PROJECT_DIR
# case_ <name>: a project alpha and a host file naming it; every record command is noted in calls.
case_() {
  T=$B/$1 M=$B/$1/alpha CASE=$1
  export XDG_CONFIG_HOME=$T/config HOME=$T/home CONVEYOR_FOREMAN_DIR=$T/fd CONVEYOR_MAIN=$M
  export CONVEYOR_FOREMAN_ASK="echo \"\$CONVEYOR_REPO \$CONVEYOR_CMD\" >> $T/calls; case \$CONVEYOR_CMD in control) echo '{\"start\":\"queue\"}' ;; esac"
  mkdir -p "$XDG_CONFIG_HOME/conveyor" "$HOME" "$T/fd" && git init -q "$M" \
    && jq -n --arg m "$M" '{records: [{repo: "alpha", main: $m}]}' > "$XDG_CONFIG_HOME/conveyor/host.json" || fail "the fixture was not made"
}
fail() { echo "FAIL [$CASE]: $*" >&2; exit 1; }
# hook <command>: foreman.sh filing's output for the command as the Foreman's PreToolUse hook sees it.
hook() { (cd "$M" && jq -cn --arg c "$1" '{session_id: "s1", tool_use_id: "x", hook_event_name: "PreToolUse", tool_input: {command: $c}}' | CONVEYOR_FOREMAN=1 bash "$SRC/foreman.sh" filing 2>&1); }
refused() { # <command>: the refusal says what the Cause section holds
  out=$(hook "$1")
  jq -e '.hookSpecificOutput.permissionDecision == "deny" and (.hookSpecificOutput.permissionDecisionReason | test("## Cause") and test("where the bad data or behaviour comes from and why it is there at all") and test("already solves the same problem, or that none was found") and test("stale or missing"))' <<<"$out" >/dev/null \
    || fail "a fix issue with no Cause section was not refused with what the section holds; command: $1; output: $out"
}
passes() { out=$(hook "$1"); [ -z "$out" ] || fail "the command was refused though it needed no Cause section; command: $1; output: $out"; }
body() { printf 'gh issue create --title "Fix it" %s --body "$(cat <<'"'EOF'"'\n%s\nEOF\n)"' "${2:-}" "$1"; }

# D1: `## What happens now` with no `## Cause` is refused (gh and `ask <project> testissue`); the same body with one passes.
t_what() {
case_ what
refused "$(body $'## What happens now\nThe pane shows no board.')"
refused "foreman.sh ask alpha testissue conveyor/x.test.sh 'Slow' '## What happens now
It is slow.'"
refused "gh issue create --title 'Fix it' --body '## What happens now\nIt breaks.\n## Causes\nnone'"
passes "$(body $'## What happens now\nThe pane shows no board.\n## Cause\nThe file is never trimmed.')"
passes "foreman.sh ask alpha testissue conveyor/x.test.sh 'Slow' '## What happens now
It is slow.
## Cause
The file grows.'"
printf '## What happens now\nIt breaks.\n' > "$T/body.md"
refused "gh issue create --title 'Fix it' --body-file $T/body.md"
printf '## What happens now\nIt breaks.\n## Cause\nThe cache is stale.\n' > "$T/body.md"
passes "gh issue create --title 'Fix it' --body-file $T/body.md"
}

# D2: a `bug` label makes it a fix issue, whatever its body. `testissue` files with the pack's type label (`bug` here),
# so a testissue with no Cause section is refused though its body has no `## What happens now` either.
t_bug() {
case_ bug
refused "foreman.sh ask alpha testissue conveyor/x.test.sh 'Speed up tests' 'Measured: 12 CPU s.'"
passes "foreman.sh ask alpha testissue conveyor/x.test.sh 'Speed up tests' 'Measured: 12 CPU s.
## Cause
The suite runs twice.'"
refused "$(body $'Something is wrong.' '--label bug')"
refused "$(body $'Something is wrong.' '-l priority,bug')"
refused "$(body $'Something is wrong.' '--label=Bug')"
passes "$(body $'Something is wrong.\n## Cause\nA stale file.' '--label bug')"
passes "$(body $'Something is wrong.' '--label debugging')"
}

# D3: ordered new work with neither passes, and so does a fix issue of a session that is not the Foreman's: the engine
# files its follow-ups, release fixes and main fixes itself, through no Foreman hook, and a hook of another session
# does nothing.
t_new() {
case_ new
passes "$(body $'## Done when\nThe page shows the new row.' '--label enhancement')"
passes "gh issue view 7 --label bug"
# Bug caught (#1347): `ask <project> card` (a Foreman's order, or with --release a release fix card) was checked for a Cause section
# as a fix issue is, so the Foreman could not order a card with no GitHub issue, whatever its Rules switch; the engine itself asks an order that files an issue for its Cause section (cardnew(), testcards.test.sh nioff).
passes "foreman.sh ask alpha card 'Add a row' 'Make it so.'"
passes "foreman.sh ask alpha card --release 1.1.0 'Fix a.test.sh' 'It fails.'"
out=$(cd "$M" && jq -cn --arg c "$(body $'## What happens now\nIt breaks.')" '{session_id: "s2", tool_use_id: "x", tool_input: {command: $c}}' | bash "$SRC/foreman.sh" filing 2>&1)
[ -z "$out" ] || fail "a fix issue filed in a session that is not the Foreman's was checked; command: $(body $'## What happens now\nIt breaks.'); output: $out"
}

cases=(what bug new)
SEL=${CONVEYOR_SHELL_TEST_CASE:-${cases[*]}}; SEL=${SEL//,/ }
for c in $SEL; do case " ${cases[*]} " in *" $c "*) ;; *) echo "unknown case $c" >&2; exit 2 ;; esac; done
read -ra cases <<<"$SEL"
for c in "${cases[@]}"; do (t_"$c" && : > "$B/$c.passed") > "$B/$c.out" 2>&1 & done
wait
bad=0
for c in "${cases[@]}"; do cat "$B/$c.out" >&2; [ -e "$B/$c.passed" ] || bad=1; done
[ "$bad" = 0 ] || exit 1
echo "ok [filing-cause]"
