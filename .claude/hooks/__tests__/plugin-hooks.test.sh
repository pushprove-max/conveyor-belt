#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Pins what the plugin's hooks do in a project that has not run setup. The plugin is on for its user's every project,
# so a hook that fails there blocks each Bash, Edit, Write and AskUserQuestion call in all of them (issue 12). Each
# case runs the commands hooks/hooks.json registers, so through shim.sh, as Claude Code runs them.
set -u
SRC=$(cd "$(dirname "$0")/../../.." && pwd)
PIN=0123456789abcdef0123456789abcdef01234567
NOTICE="Conveyor's guards are off in this project until /conveyor-belt:setup installs its commit"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
export CLAUDE_PLUGIN_ROOT=$SRC XDG_DATA_HOME=$T/data TMPDIR=$T/tmp CONVEYOR_HOOK_FIRE_LOG=$T/fire.jsonl
mkdir -p "$T/tmp" "$T/data"
mapfile -t CMDS < <(jq -r '.hooks[][].hooks[].command' "$SRC/hooks/hooks.json")

PASS=0 FAIL=0
check() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); echo "ok   $1"; else FAIL=$((FAIL+1)); echo "FAIL $1 (expected $2, got $3)"; fi }
# input <session> <tool>: a PreToolUse input for <tool> in <session>.
input() {
  case $2 in
    Bash) jq -cn --arg s "$1" '{session_id: $s, hook_event_name: "PreToolUse", tool_name: "Bash", tool_input: {command: "echo hello-from-bash"}}' ;;
    Edit) jq -cn --arg s "$1" '{session_id: $s, hook_event_name: "PreToolUse", tool_name: "Edit", tool_input: {file_path: "a.txt", old_string: "a", new_string: "b"}}' ;;
    AskUserQuestion) jq -cn --arg s "$1" '{session_id: $s, hook_event_name: "PreToolUse", tool_name: "AskUserQuestion", tool_input: {questions: [{question: "Go on?", options: [{label: "yes"}, {label: "no"}]}]}}' ;;
  esac
}
# every <project> <session>: runs every registered command with each input, side by side as Claude Code runs a tool
# call's hooks; prints one line per run that exited non-zero or wrote to stderr, then all their stdout.
every() {
  local d i=0 c tool; d=$(mktemp -d "$T/runs.XXXXXX")
  for tool in Bash Edit AskUserQuestion; do
    for c in "${CMDS[@]}"; do
      i=$((i+1))
      ( cd "$1" && input "$2" "$tool" | CLAUDE_PROJECT_DIR=$1 bash -c "$c" > "$d/$i.out" 2> "$d/$i.err"; echo $? > "$d/$i.rc" ) &
    done
  done
  wait
  for c in "$d"/*.rc; do
    [ "$(cat "$c")" = 0 ] && [ ! -s "${c%.rc}.err" ] || echo "BAD exit $(cat "$c"): $(cat "${c%.rc}.err")"
  done
  cat "$d"/*.out
}

# A git folder with no .conveyor/project.json is no Conveyor project: every hook does nothing, so no tool is blocked.
git init -q "$T/plain"
out=$(every "$T/plain" s-plain)
check "${#CMDS[@]} hooks x 3 tools, no pack: each exits 0 and prints nothing" "" "$out"

# Not a git checkout, even with a pack: the same.
mkdir -p "$T/nogit/.conveyor"; jq -n --arg c "$PIN" '{plugin: {commit: $c}}' > "$T/nogit/.conveyor/project.json"
out=$(every "$T/nogit" s-nogit)
check "not a git checkout: each hook exits 0 and prints nothing" "" "$out"

# A Conveyor project whose pinned commit is not installed: no hook blocks, and the user is told once a session, not
# once per hook or call.
git init -q "$T/pinned"; mkdir -p "$T/pinned/.conveyor"; cp "$T/nogit/.conveyor/project.json" "$T/pinned/.conveyor/"
want=$(jq -cn --arg m "$NOTICE" '{systemMessage: $m}')
out=$(every "$T/pinned" s-one)
check "pin not installed: no hook fails, and the first session hears it once" "$want" "$out"
out=$(every "$T/pinned" s-one)
check "pin not installed: the same session's next calls stay quiet" "" "$out"
out=$(every "$T/pinned" s-two)
check "pin not installed: another session hears it once too" "$want" "$out"
# A skill's call (no CONVEYOR_HOOK) still fails and says why, so setup and the /auto band see it.
err=$(cd "$T/pinned" && CLAUDE_PROJECT_DIR=$T/pinned bash "$SRC/shim.sh" conveyor/conveyor.sh health 2>&1 >/dev/null); rc=$?
check "pin not installed: a skill's call still fails, naming the commit" "1 conveyor: the project's Conveyor commit $PIN is not installed; run /conveyor-belt:setup" "$rc $err"

# A set-up project (its pin installed): the guards block what they block, through the same commands.
mkdir -p "$T/data/conveyor/versions/$PIN/.claude/hooks/lib"
cp "$SRC/.claude/hooks/git-safety.sh" "$T/data/conveyor/versions/$PIN/.claude/hooks/"
cp "$SRC/.claude/hooks/lib/"*.sh "$T/data/conveyor/versions/$PIN/.claude/hooks/lib/"
gs=$(printf '%s\n' "${CMDS[@]}" | grep -m1 'git-safety\.sh$')
bash_hook() { # <command>: the exit of the registered git-safety hook on a Bash call of <command>
  (cd "$T/pinned" && jq -cn --arg c "$1" '{session_id: "s-set", tool_name: "Bash", tool_input: {command: $c}}' \
    | CLAUDE_PROJECT_DIR=$T/pinned bash -c "$gs" >/dev/null 2>&1); echo $?
}
check "set up: git-safety still refuses a forced push to main" 2 "$(bash_hook 'git push --force origin main')"
check "set up: git-safety lets git status through" 0 "$(bash_hook 'git status')"

echo
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
