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
. "$(dirname "${BASH_SOURCE[0]}")/lib/said.sh" # a FAIL line names the hook's last input (every, bash_hook and the shim call note it)
check() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); echo "ok   $1"; else FAIL=$((FAIL+1)); echo "FAIL $1 (expected $2, got $3)$(said)"; fi }
# The limit of a hook run: its 30 s timeout times the load factor (CONVEYOR_LOAD_FACTOR, held between 1 and 3), kept
# under 60 s, how long the take's stub below waits: a hook that waited for the take must still fail.
LF=$(awk -v f="${CONVEYOR_LOAD_FACTOR:-1}" 'BEGIN { f += 0; if (f < 1) f = 1; if (f > 3) f = 3; print f }')
LIMIT=$(awk -v f="$LF" 'BEGIN { l = 30 * f; if (l > 59) l = 59; print l }')
# input <session> <tool>: a PreToolUse input for <tool> in <session>.
input() {
  case $2 in
    Bash) jq -cn --arg s "$1" '{session_id: $s, hook_event_name: "PreToolUse", tool_name: "Bash", tool_input: {command: "echo hello-from-bash"}}' ;;
    Edit) jq -cn --arg s "$1" '{session_id: $s, hook_event_name: "PreToolUse", tool_name: "Edit", tool_input: {file_path: "a.txt", old_string: "a", new_string: "b"}}' ;;
    AskUserQuestion) jq -cn --arg s "$1" '{session_id: $s, hook_event_name: "PreToolUse", tool_name: "AskUserQuestion", tool_input: {questions: [{question: "Go on?", options: [{label: "yes"}, {label: "no"}]}]}}' ;;
  esac
}
# every <project> <session>: runs every registered command with each input, side by side as Claude Code runs a tool
# call's hooks; prints one line per run that exited non-zero or wrote to stderr (naming its tool and hook command), then
# all their stdout. The project, the session and each tool's input are noted for the checks' FAIL lines.
every() {
  local d i=0 c tool p; d=$(mktemp -d "$T/runs.XXXXXX")
  said_in "$(jq -cn --arg d "$1" --arg s "$2" \
    --argjson t "[$(input "$2" Bash | jq -c .tool_input),$(input "$2" Edit | jq -c .tool_input),$(input "$2" AskUserQuestion | jq -c .tool_input)]" \
    '{project: $d, session: $s, "every hook given each of these tool inputs": $t}')"
  for tool in Bash Edit AskUserQuestion; do
    p=$(input "$2" "$tool")
    for c in "${CMDS[@]}"; do
      i=$((i+1)); printf 'tool %s, hook [%s]' "$tool" "$c" > "$d/$i.what"
      ( cd "$1" && printf '%s\n' "$p" | CLAUDE_PROJECT_DIR=$1 bash -c "$c" > "$d/$i.out" 2> "$d/$i.err"; echo $? > "$d/$i.rc" ) &
    done
  done
  wait
  for c in "$d"/*.rc; do
    [ "$(cat "$c")" = 0 ] && [ ! -s "${c%.rc}.err" ] || echo "BAD $(cat "${c%.rc}.what"), exit $(cat "$c"): $(cat "${c%.rc}.err")"
  done
  cat "$d"/*.out
}

# A git folder with no .conveyor/project.json is no Conveyor project: every hook does nothing, so no tool is blocked.
git init -q "$T/plain"
out=$(every "$T/plain" s-plain)
check "${#CMDS[@]} hooks x 3 tools, no pack: each exits 0 and prints nothing" "" "$out"
# Bug: a failed check printed only the two values, never the payloads that produced them. The probe fails on purpose,
# in a subshell, so it adds to no count.
check "a failed check names the tool inputs the hooks were given" 0 \
  "$(check probe x y | grep -qF "$(input s-plain Edit | jq -c .tool_input)" && echo 0 || echo 1)"
# Bug: a BAD line named the hook command and its payload but not the tool. One failing hook stands for the list.
bad=$(CMDS=('echo oops >&2; exit 3'); every "$T/plain" s-bad | grep -F 'tool Edit')
check "a BAD line names its tool and hook command" "BAD tool Edit, hook [echo oops >&2; exit 3], exit 3: oops" "$bad"

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
# (said.sh's bash notes this call's words after the script, with no input.)
err=$(cd "$T/pinned" && CLAUDE_PROJECT_DIR=$T/pinned bash "$SRC/shim.sh" conveyor/conveyor.sh health 2>&1 >/dev/null < /dev/null); rc=$?
check "pin not installed: a skill's call still fails, naming the commit" "1 conveyor: the project's Conveyor commit $PIN is not installed; run /conveyor-belt:setup" "$rc $err"

# A set-up project (its pin installed): the guards block what they block, through the same commands.
mkdir -p "$T/data/conveyor/versions/$PIN/.claude/hooks/lib"
cp "$SRC/.claude/hooks/git-safety.sh" "$T/data/conveyor/versions/$PIN/.claude/hooks/"
cp "$SRC/.claude/hooks/lib/"*.sh "$T/data/conveyor/versions/$PIN/.claude/hooks/lib/"
gs=$(printf '%s\n' "${CMDS[@]}" | grep -m1 'git-safety\.sh$')
bash_hook() { # <command>: the exit of the registered git-safety hook on a Bash call of <command>
  (cd "$T/pinned" && jq -cn --arg c "$1" '{session_id: "s-set", tool_name: "Bash", tool_input: {command: $c}}' \
    | said_tee | CLAUDE_PROJECT_DIR=$T/pinned bash -c "$gs" >/dev/null 2>&1); echo $?
}
check "set up: git-safety still refuses a forced push to main" 2 "$(bash_hook 'git push --force origin main')"
check "set up: git-safety lets git status through" 0 "$(bash_hook 'git status')"

# Issue 18: a project that follows the plugin's releases, on a machine that has taken no commit. The first take waits
# on its lock and on GitHub for longer than a hook's 30 s timeout, so a hook that waits for it blocks the call. Here the
# plugin copy's take is a stub that waits up to 60 s for $T/go: each hook must end well before that, with the notice
# once, and the take must still be started beside it.
# The plugin copy also holds the filing hook's own lines (hooks.json runs them from it, not through the shim).
mkdir -p "$T/plug/conveyor/foreman" "$T/takes"; cp "$SRC/shim.sh" "$T/plug/"
cp "$SRC/conveyor/foreman/filing-hook.sh" "$SRC/conveyor/foreman/files.jq" "$T/plug/conveyor/foreman/"
printf '#!/usr/bin/env bash\ntouch "%s/takes/$$"\nfor i in $(seq 600); do [ -e "%s/go" ] && break; sleep 0.1; done\nrm -f "%s/takes/$$"\n' \
  "$T" "$T" "$T" > "$T/plug/conveyor/conveyor.sh"
git init -q "$T/follow"; mkdir -p "$T/follow/.conveyor"
jq -n '{plugin: {follow: "releases"}}' > "$T/follow/.conveyor/project.json"
start=$SECONDS
out=$(CLAUDE_PLUGIN_ROOT=$T/plug every "$T/follow" s-follow)
took=$((SECONDS - start))
check "no commit taken: every hook ends within its timeout, not after the take" yes \
  "$(awk -v t="$took" -v l="$LIMIT" 'BEGIN { exit !(t < l) }' && echo yes || echo "no, $took s (limit $LIMIT s, load factor $LF)")"
check "no commit taken: no hook fails, and the session hears it once" "$want" "$out"
for i in $(seq 100); do compgen -G "$T/takes/*" >/dev/null && break; sleep 0.1; done
check "no commit taken: the hooks started the take" yes "$(compgen -G "$T/takes/*" >/dev/null && echo yes || echo no)"
touch "$T/go"; for i in $(seq 100); do compgen -G "$T/takes/*" >/dev/null || break; sleep 0.1; done

echo
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
