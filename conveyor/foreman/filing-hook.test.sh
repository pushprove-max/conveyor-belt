#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 60
# The plugin's filing and filed hook lines (hooks/hooks.json, filing-hook.sh), as Claude Code runs them, with the shim
# stubbed: the stub notes each start of the engine, then runs this checkout's.
# Bug (#610): every Bash call of the Foreman waited for both hooks' shim to find the project's engine, though nearly
# every call files no issue and the two had nothing to do for it.
set -uo pipefail
SRC=$(cd "$(dirname "$0")" && pwd -P)
ROOT=$(cd "$SRC/../.." && pwd -P)
B=$(mktemp -d) || exit 1
trap 'rm -rf "$B"' EXIT
cd "$B" || exit 1
unset CONVEYOR_FOREMAN CONVEYOR_FOREMAN_DIR CONVEYOR_FOREMAN_ASK CONVEYOR_MAIN CONVEYOR_MACHINE_ID CLAUDE_PROJECT_DIR
# line <event>: the plugin's one Bash hook line of that event that is filing's or filed's.
line() { jq -er --arg e "$1" '[.hooks[$e][] | select(.matcher == "Bash") | .hooks[].command | select(test("\\bfil(ing|ed)$"))] | select(length == 1)[0]' "$ROOT/hooks/hooks.json"; }
# input <command> [<more, as jq>]: a Bash hook input whose output links issue 41 of example/alpha.
input() { jq -cn --arg c "$1" '{session_id: "s1", tool_use_id: "x", tool_input: {command: $c},
  tool_response: {stdout: "https://github.com/example/alpha/issues/41\n", stderr: ""}} + '"${2:-"{}"}"; }
# case_ <name>: the plugin folder P (the Foreman's scripts, the stub shim) and a project alpha with a research lane's
# folder, which runs filing and filed with no session marked; each record command is noted in calls.
case_() {
  T=$B/$1 M=$B/$1/alpha P=$B/$1/plugin
  fail() { echo "FAIL [$CASE]: $*" >&2; exit 1; }
  export XDG_CONFIG_HOME=$T/config HOME=$T/home CONVEYOR_LANE=research CONVEYOR_FOREMAN_DIR=$T/fd CONVEYOR_MAIN=$M CLAUDE_PROJECT_DIR=$M CLAUDE_PLUGIN_ROOT=$P
  export CONVEYOR_FOREMAN_ASK="echo \"\$CONVEYOR_REPO \$CONVEYOR_CMD\" >> $T/calls; case \$CONVEYOR_CMD in control) echo '{\"start\":\"queue\"}' ;; 'control adopt'*) echo '{\"held\":[41]}' ;; esac"
  mkdir -p "$XDG_CONFIG_HOME/conveyor" "$HOME" "$T/fd" "$P/conveyor" && git init -q "$M" && cp -R "$SRC" "$P/conveyor/foreman" \
    && printf '#!/usr/bin/env bash\necho "$*" >> %q\nexec bash %q/"$1" "${@:2}"\n' "$T/marks" "$ROOT" > "$P/shim.sh" && chmod +x "$P/shim.sh" \
    && jq -n --arg m "$M" '{records: [{repo: "alpha", main: $m}]}' > "$XDG_CONFIG_HOME/conveyor/host.json" || fail "the fixture was not made"
}
run() { (cd "$M" && sh -c "$1" <<<"$2" 2>&1); } # <hook line> <input>: as Claude Code runs a hook

# D1: a Bash call that files no issue: each of the three lines exits 0, prints nothing and starts no engine.
t_quiet() {
CASE=quiet; case_ quiet
for e in PreToolUse PostToolUse PostToolUseFailure; do
  h=$(line "$e") || fail "no one filing or filed Bash hook line of $e in hooks.json"
  out=$(run "$h" "$(input ls "{hook_event_name: \"$e\"}")"); rc=$?
  [ "$rc" = 0 ] && [ -z "$out" ] || fail "the $e line for ls did not end quietly (exit $rc): $out"
done
[ ! -e "$T/marks" ] || fail "a Bash call that files no issue started the engine: $(cat "$T/marks")"
[ ! -e "$T/calls" ] || fail "a Bash call that files no issue reached a record: $(cat "$T/calls")"
}

# D2: a call that files an issue still reaches foreman.sh filing and filed, and the issue is held as before; one run in
# the background is still refused.
t_files() {
CASE=files; case_ files
local c='gh issue create -R example/alpha --title example --body example'
out=$(run "$(line PreToolUse)" "$(input "$c" '{hook_event_name: "PreToolUse"}')")
[ -z "$out" ] || fail "filing an issue was refused: $out"
grep -qx 'conveyor/foreman/foreman.sh filing' "$T/marks" 2>/dev/null || fail "the filing line did not start foreman.sh filing: $(cat "$T/marks" 2>/dev/null)"
grep -qx 'alpha control start held' "$T/calls" || fail "new issues do not start held before the filing command runs: $(cat "$T/calls")"
out=$(run "$(line PostToolUse)" "$(input "$c" '{hook_event_name: "PostToolUse"}')")
grep -qx 'conveyor/foreman/foreman.sh filed' "$T/marks" || fail "the filed line did not start foreman.sh filed: $(cat "$T/marks")"
grep -qx 'alpha control adopt 41' "$T/calls" || fail "the issue filed is not held: $(cat "$T/calls")"
[ "$(tail -n 1 "$T/calls")" = 'alpha control start queue filed' ] || fail "new issues are not set back to the queue once the filed one is held: $(cat "$T/calls")"
jq -e '.hookSpecificOutput.additionalContext | test("Held in Conveyor \\(alpha: 41\\)")' <<<"$out" >/dev/null || fail "filed did not say the issue is held: $out"
out=$(run "$(line PreToolUse)" "$(input "$c" '{hook_event_name: "PreToolUse", tool_input: {command: $c, run_in_background: true}}')")
jq -e '.hookSpecificOutput.permissionDecision == "deny"' <<<"$out" >/dev/null || fail "a filing command run in the background was not refused: $out"
}

# A testissue command files through the engine, not gh: its filing hook still starts foreman.sh filing (which refuses a
# fix issue with no Cause section, filing-cause.test.sh), and its filed hook has nothing to do.
t_testissue() {
CASE=testissue; case_ testissue
local c='foreman.sh ask alpha testissue conveyor/x.test.sh Slow body'
out=$(run "$(line PreToolUse)" "$(input "$c" '{hook_event_name: "PreToolUse"}')")
grep -qx 'conveyor/foreman/foreman.sh filing' "$T/marks" 2>/dev/null || fail "the filing line did not start foreman.sh filing; command: $c; marks: $(cat "$T/marks" 2>/dev/null)"
: > "$T/marks"
out=$(run "$(line PostToolUse)" "$(input "$c" '{hook_event_name: "PostToolUse"}')")
[ ! -s "$T/marks" ] || fail "the filed line started the engine; command: $c; marks: $(cat "$T/marks")"
}

cases=(quiet files testissue)
# The cases CONVEYOR_SHELL_TEST_CASE names (comma-separated), as the runner selects them; all of them with none set.
SEL=${CONVEYOR_SHELL_TEST_CASE:-${cases[*]}}; SEL=${SEL//,/ }
for c in $SEL; do case " ${cases[*]} " in *" $c "*) ;; *) echo "unknown case $c" >&2; exit 2 ;; esac; done
read -ra cases <<<"$SEL"
for c in "${cases[@]}"; do (t_"$c" && : > "$B/$c.passed") > "$B/$c.out" 2>&1 & done
wait
. "$SRC/tests/casesreport-helper.sh"
casesreport "$B" '' "${cases[@]}" || exit 1
echo "ok [filing-hook]"
