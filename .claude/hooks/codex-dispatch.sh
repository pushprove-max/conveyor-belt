#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Codex hook dispatcher: runs THIS repo's `.claude` hooks for Codex.
#
# WHY. `.claude/settings.json` is the one source of truth for which guard runs
# on which tool. Claude Code reads it; Codex does not, so every mechanical rule
# in this repo -- heap cap, git safety, cast tripwires, dependency guard,
# orchestrator lane -- was prose for Codex and enforcement for Claude. Rather
# than a second copy of the rule list in `~/.codex/hooks.json`, one entry per
# EVENT per Codex home points here and this script reads settings.json.
#
# SHAPE MAP (https://developers.openai.com/codex/hooks). Codex's payload is
# already Claude-shaped: `hook_event_name`, `cwd`, `tool_name`, `tool_input`.
#   Codex `Bash`         -> Claude `Bash`   (tool_input.command, identical)
#   A group is selected by matching the payload's tool name against the group's
#   matcher REGEX, exactly as Claude Code does -- not by string equality.
#
#   Codex `apply_patch`  -> one Claude `Write`/`Edit` payload per file in the
#                           patch, so the ~20 Edit|Write hooks see the shape
#                           they were written against (lib/edit-payload.sh).
#   Codex `Stop`         -> the Stop matcher's hooks, payload UNCHANGED. Codex's
#                           Stop event already carries `cwd`, `session_id`,
#                           `stop_hook_active` and `transcript_path` under the
#                           same names, plus `last_assistant_message`, which
#                           Claude Code does not send.
# `Delete File` sections produce no payload: no content hook screens a removal.
#
# THE PAYLOAD'S OWN EVENT DECIDES, and only the five events below are dispatched.
# The tool name used to decide alone, so a Codex PostToolUse Bash payload ran the
# PRE-tool Bash guards a second time and reached none of the post ones -- the
# read tracker, the staged-index warning and the rerun guard's completion record
# were Claude-only, and so were the post-edit typecheck and brief freshness
# passes behind an apply_patch. An event this script does not know is not
# guessed at: it exits 0 rather than running some other event's rules.
#
# WARNINGS ARE OUTPUT TOO. Half the post hooks say their piece and exit 0
# (a freshness note, an ignore warning, an audit result). Relaying stderr only
# for a non-zero exit dropped every one of them, which is the whole value of the
# post events. Anything a hook writes to stderr is relayed; for SessionStart and
# UserPromptSubmit, whose product is context on STDOUT, stdout is relayed too.
#
# The registration in each Codex home names the events it sends. An event
# missing there never reaches this script, so adding a case here is half of
# turning it on.
#
# CEILING, stated. The `old_string` synthesised for an Update is the hunk's
# context+removed lines, which is an approximation of what Claude's Edit tool
# would send. The content tripwires need the NEW text and the path, and both are
# exact. Hosted Codex tools (WebSearch) never reach a hook at all.
#
# Both Codex homes pin the copy of this script IN THE MAIN CHECKOUT, so a change
# made in a worktree is not live for any Codex pane until it merges. Testing a
# change here means invoking this file directly with a payload, not launching
# Codex and watching.
#
# TRUST. The registration is user-level, so Codex hands this script every
# project, trusted or not. It runs a checkout's hooks only when that checkout
# (or the main checkout behind a linked worktree) is trusted in the active
# Codex home -- see the gate below.
#
# A hook that CANNOT work for Codex -- one keyed to Claude-only session state,
# or one whose whole message is "use the Read tool" -- carries `# codex: skip`
# in its own header, and every skip is logged so a silently-absent rule is
# visible. That marker is the only per-hook knob; there is no second list here.
#
# Codex-safe by construction: bash, jq, git, python3. No Claude env, no MCP.
#
# A DISPATCHER THAT COULD NOT RUN MUST NEVER READ AS A CLEAN TURN. Exit 2 is a
# denial and exit 0 is an allow, so "I could not run" is exit 1 and one line --
# the same shape as tier1-stop.sh's skip(). A silent 0 here is worse than
# anywhere else: it takes every hook in settings.json down with it, so a Codex
# turn ends looking guarded by rules that never fired.
#
# Self-test: bash .claude/hooks/__tests__/codex-dispatch.test.sh

cannot_run() { echo "codex-dispatch: $1 -- this repo's hooks did NOT run for this turn." >&2; exit 1; }

# STEP TRACE. Off unless CONVEYOR_CODEX_TRACE names a file; off costs
# one builtin test per step and no process. On, each step appends one row:
# epoch seconds, pid, event:tool, step. Hook names and exit codes only, never a
# payload. It is read from the hook's own environment, which Codex sets and a
# sandboxed command cannot. Needs bash 5 for EPOCHREALTIME, like the fire log.
T0=${EPOCHREALTIME:-}
trace() { # step, [timestamp]
  [ -n "${CONVEYOR_CODEX_TRACE:-}" ] || return 0
  printf '%s\t%s\t%s\t%s\n' "${2:-${EPOCHREALTIME:-}}" "$$" "$EVENT:$TOOL" "$1" >>"$CONVEYOR_CODEX_TRACE" 2>/dev/null
}

INPUT=$(cat)
. "${BASH_SOURCE[0]%/*}/lib/hook-fire-log.sh" 2>/dev/null && hook_fire_log_arm "$INPUT"

# The three tools this script itself needs. jq reads every payload, python3
# parses the trust table and the patch, git resolves the checkout: without any
# one of them nothing below can run at all.
for tool in jq python3 git; do
  command -v "$tool" >/dev/null 2>&1 || cannot_run "$tool is not installed"
done

CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null)
[ -n "$CWD" ] && [ -d "$CWD" ] || cannot_run 'the payload carries no usable cwd'

# Resolve the repo from the SESSION cwd, never from this script's own location:
# the registration pins ONE dispatcher, and a worktree must run its own
# checkout's hooks (a worktree's guards can differ from main's mid-plan).
#
# Exit 0, not 1: the registration is user-level, so Codex opens plenty of
# folders that are no checkout at all. There is no settings.json to run there,
# which is not-applicable rather than a failure.
ROOT=$(git -C "$CWD" rev-parse --show-toplevel 2>/dev/null) || exit 0

LOG="${XDG_CACHE_HOME:-$HOME/.cache}/conveyor/codex-dispatch.log"
mkdir -p "${LOG%/*}" 2>/dev/null

# ONLY A CHECKOUT CODEX ALREADY TRUSTS GETS TO RUN CODE THROUGH THIS SCRIPT.
# The registration is user-level, and Codex loads user hooks in UNTRUSTED
# projects too, so without this gate opening any unrelated repo in Codex would
# `eval` that repo's `.claude/settings.json` commands on the first tool call.
# Claude Code runs those same hooks only after its own trust prompt; this is
# the matching gate. A linked worktree counts when its MAIN checkout is
# trusted -- the Orca worktrees are not in that table themselves, and a
# ROOT-only test would silently un-guard every reviewer pane.
#
# Both exits below are 0 on purpose, and neither is a could-not-run: an
# untrusted project and a config too broken to name one are the same answer --
# we do not know this checkout is trusted, so we run none of its code.
CODEX_CONFIG="${CODEX_HOME:-$HOME/.codex}/config.toml"
MAIN=$(git -C "$CWD" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)
MAIN=${MAIN%/.git}
python3 -I - "$CODEX_CONFIG" "$ROOT" "$MAIN" <<'PY' || {
import sys, tomllib
try:
    projects = tomllib.load(open(sys.argv[1], "rb")).get("projects", {})
except Exception:
    sys.exit(1)
sys.exit(0 if any(projects.get(p, {}).get("trust_level") == "trusted"
                  for p in sys.argv[2:]) else 1)
PY
  printf '%s\t%s\t%s\tuntrusted\n' "$(date -Is)" "-" "$ROOT" >>"$LOG" 2>/dev/null
  exit 0
}

# Exit 0 for the same reason as the checkout test above: a repo that registers
# no hooks has nothing this script could have failed to run.
SETTINGS="$ROOT/.claude/settings.json"
[ -f "$SETTINGS" ] || exit 0

TOOL=$(printf '%s' "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)
EVENT=$(printf '%s' "$INPUT" | jq -r '.hook_event_name // empty' 2>/dev/null)
trace start "$T0"; trace gate
# The names of what Codex handed the hook, never the values: the one enumerated
# field aside, a value can be a command, a prompt or a path.
[ -n "${CONVEYOR_CODEX_TRACE:-}" ] && trace "keys $(printf '%s' "$INPUT" | jq -r '(keys_unsorted | join(" ")) + " permission_mode=" + (.permission_mode // "" | tostring)' 2>/dev/null)"

# The existing hooks resolve their own paths from CLAUDE_PROJECT_DIR and take
# their Claude/Codex branch from AGENT_KIND (default `claude`, so nothing
# changes for Claude Code, which never sets it).
export AGENT_KIND=codex
export CLAUDE_PROJECT_DIR="$ROOT"

# Every hook command this event+tool reaches, in file order.
#
# The matcher is a REGEX over tool names, so the group is chosen by matching,
# never by string equality. Equality worked only while every group's matcher was
# spelled `Edit|Write|MultiEdit` verbatim: the moment a hook that can only act on
# a Write was narrowed to a `Write` group, Codex stopped reaching it entirely,
# because the apply_patch lane asked for the literal three-tool string. An event
# with no tool (Stop) takes the `*` groups. Each line is the hook's `onFailure`
# (`-` when it has none), a tab, then its command.
hook_commands() {
  jq -r --arg e "$1" --arg t "$2" '
    .hooks[$e][]?
    | select((.matcher // "*") as $m
             | $m == "*" or $m == ""
               or (($t != "") and ($t | test("^(" + $m + ")$"))))
    | .hooks[]? | select(.command) | "\(.onFailure // "-")\t\(.command)"' "$SETTINGS" 2>/dev/null
}

# A READ-ONLY RUN RUNS ONLY THE GUARDS ON THIS KEEP-LIST (the owner's
# rulings). A
# review reads, with no write access and no network, so every other guard is
# dropped for that run, on every tool. A new guard is dropped for a read-only
# run unless it is added here. Warning: the read-only proof below is then the
# only thing between a write-capable run and almost no guards; never loosen it.
# mac-test-refusal.sh protects the Mac itself, as bash-guardrails.sh does (the ruling's reason for keeping that one).
READ_ONLY_KEEP=' bash-guardrails.sh mac-test-refusal.sh suite-rerun-guard.sh '

# Whether THIS run is read-only, decided once per dispatch and only when a
# guard off the keep-list comes up. Codex's payload names no sandbox (its permission_mode
# reads bypassPermissions in a read-only run), so the answer is the session
# record Codex itself writes and names in transcript_path. It counts only when
# no sandboxed run could have written it:
#   - its real path, links followed, is under the sessions folder of a real
#     Codex home. The two homes are typed here because the repo has no one list
#     of them; a pattern would make any folder named like one a home.
#   - it is outside the run's own folder, which a workspace-write run can write.
#   - EVERY turn row says read-only with approvals off, exactly. A run that was
#     ever write-capable, or that may ask to run a command outside the sandbox,
#     skips nothing. Rows are parsed, so prompt text spelling one is not one.
# A record that is missing, unreadable or has no turn row skips nothing.
# HOME is the dispatcher's own, set by whoever started Codex, not by a command.
# Ceiling: a full-access run can rewrite its own record. It can rewrite
# hooks.json too, so this gives it nothing it lacked.
# Emptied here: a READ_ONLY inherited from the environment is not an answer.
READ_ONLY=
read_only_run() {
  if [ -z "${READ_ONLY:-}" ]; then
    READ_ONLY=0
    python3 -I - "$(printf '%s' "$INPUT" | jq -r '.transcript_path // empty' 2>/dev/null)" \
      "$CWD" "$ROOT" "${HOME:-/nonexistent}/.codex" "${HOME:-/nonexistent}/.codex-review" <<'PY' 2>/dev/null && READ_ONLY=1
import json, os, sys

path, cwd, root, *homes = sys.argv[1:]
if not path:
    sys.exit(1)
real = os.path.realpath(path)


def under(folder):
    folder = os.path.realpath(folder)
    return os.path.commonpath([real, folder]) == folder


rows = 0
try:
    if not any(under(os.path.join(home, "sessions")) for home in homes):
        sys.exit(1)
    if under(cwd) or under(root):
        sys.exit(1)
    with open(real, "rb") as record:
        for line in record:
            if b'"turn_context"' not in line:
                continue
            row = json.loads(line)
            if row.get("type") != "turn_context":
                continue
            turn = row.get("payload") or {}
            if turn.get("sandbox_policy") != {"type": "read-only"} or turn.get("approval_policy") != "never":
                sys.exit(1)
            rows += 1
except Exception:
    sys.exit(1)
sys.exit(0 if rows else 1)
PY
  fi
  [ "$READ_ONLY" = 1 ]
}

# Run one event+tool's hooks against one payload. Relays ANY stderr a hook
# writes, whatever it exits with: a hook that says "I could not run" exits 1, and
# a hook that WARNS exits 0 -- both were swallowed while only failures were
# relayed. SessionStart and UserPromptSubmit deliver their product on stdout, so
# that is passed through for those two. Returns 2 on the FIRST denial, 0
# otherwise. A denial is exit 2, a refusal written as JSON, or any other failure
# of a hook settings.json marks `onFailure: block`.
run_matcher() {
  local event=$1 tool=$2 payload=$3
  local cmd onfail script rc relay_stdout=0 out why

  case "$event" in SessionStart|UserPromptSubmit) relay_stdout=1 ;; esac

  while IFS=$'\t' read -r onfail cmd; do
    [ -n "$cmd" ] || continue

    # The script path for the marker check. settings.json spells every command
    # as `"$CLAUDE_PROJECT_DIR"/.claude/hooks/<name>`, so substituting the root
    # and taking the first word is the whole parse; anything else is left to
    # the shell below, which runs the command exactly as Claude Code does.
    script=${cmd//\"\$CLAUDE_PROJECT_DIR\"/$ROOT}
    script=${script%% *}

    if [ -f "$script" ] && head -40 "$script" | grep -q '^# codex: skip'; then
      printf '%s\t%s\t%s\tskipped\n' "$(date -Is)" "${TOOL:-$event}" "${script##*/}" >>"$LOG" 2>/dev/null
      trace "skip ${script##*/}"
      continue
    fi

    # Stderr is never captured, so a warning lands on this script's stderr
    # whatever the exit code. Stdout is relayed whole when it IS the event's
    # product, and read for the hook's answer otherwise.
    # Stop too: its hooks check the worktree's pending edits, never a read-only run's own.
    if { [ -n "$tool" ] || [ "$event" = Stop ]; } && [[ $READ_ONLY_KEEP != *" ${script##*/} "* ]] && read_only_run; then
      printf '%s\t%s\t%s\tskipped-read-only\n' "$(date -Is)" "${tool:-$event}" "${script##*/}" >>"$LOG" 2>/dev/null
      trace "skip-read-only ${script##*/}"
      continue
    fi

    trace "hook-start ${script##*/}"
    if [ "$relay_stdout" = 1 ]; then
      printf '%s' "$payload" | (cd "$ROOT" && eval "$cmd")
      rc=$?
    else
      # A hook answers on stdout: advice for the model, or a refusal written as
      # JSON with exit 0, which read as an allow while it was dropped. Stop
      # takes this path too; its advice is never printed, its refusal counts.
      out=$(printf '%s' "$payload" | (cd "$ROOT" && eval "$cmd"))
      rc=$?
      if [ "$rc" -eq 0 ] && [ -n "$out" ]; then
        if why=$(jq -er 'select(.decision == "block" or .hookSpecificOutput.permissionDecision == "deny") | .hookSpecificOutput.permissionDecisionReason // .reason // "refused with no reason given"' <<<"$out" 2>/dev/null); then
          printf '%s\n' "$why" >&2
          rc=2
        else
          out=$(jq -r '.hookSpecificOutput.additionalContext // empty' <<<"$out" 2>/dev/null)
          [ -n "$out" ] && ADVICE="${ADVICE:+$ADVICE$NL}$out"
        fi
      fi
    fi
    # A hook marked `onFailure: block` that gave no answer -- crashed, killed,
    # or not there to run -- refuses the call, as it does for Claude.
    if [ "$onfail" = block ] && [ "$rc" -ne 0 ] && [ "$rc" -ne 2 ]; then
      echo "codex-dispatch: ${script##*/} exited $rc and settings.json marks its failure as blocking -- refused." >&2
      rc=2
    fi
    trace "hook-end ${script##*/} rc=$rc"
    [ "$rc" -eq 2 ] && return 2
  done < <(hook_commands "$event" "$tool")

  return 0
}

# What the tool hooks of this event told the model, relayed once at the end.
ADVICE=""
NL=$'\n'

# The three tool-less events go straight through: their hooks take the `*`
# groups and read the fields Codex already spells the same way.
case "$EVENT" in
  Stop|SessionStart|UserPromptSubmit)
    run_matcher "$EVENT" '' "$INPUT" || exit 2
    exit 0
    ;;
  PreToolUse|PostToolUse) ;;
  *) exit 0 ;;
esac

case "$TOOL" in
  # MCP calls pass through too: read-tracker.sh counts serena
  # use, and a Codex worker without it trips the MCP UNUSED escalation.
  # write_stdin is Codex-only; its settings.json group is the long-poll guard.
  Bash|mcp__*|write_stdin)
    run_matcher "$EVENT" "$TOOL" "$INPUT" || exit 2
    ;;

  apply_patch)
    # One Claude-shaped Edit/Write payload per file in the patch, as JSON lines.
    PAYLOADS=$(printf '%s' "$INPUT" | CWD="$CWD" EVENT="$EVENT" python3 -I -c '
import json, os, sys

try:
    event = json.load(sys.stdin)
except Exception:
    sys.exit(0)

patch = (event.get("tool_input") or {}).get("command") or ""
cwd = os.environ.get("CWD", "")

files, cur = [], None
# split("\n"), not splitlines(): splitlines() eats the \r of a CRLF line, and
# edit-content-tripwires.sh screens for exactly that character. The header paths are
# .strip()ed, so a stray \r never reaches a file_path.
for line in patch.split("\n"):
    for verb in ("Add File", "Update File", "Delete File"):
        marker = "*** %s: " % verb
        if line.startswith(marker):
            cur = {"verb": verb, "path": line[len(marker):].strip(),
                   "old": [], "new": [], "hunks": [([], [])]}
            files.append(cur)
            break
    else:
        # A rename is `Update File: <old>` then `Move to: <new>`; the hooks
        # must screen the path the content lands at, not the one it left.
        move = "*** Move to: "
        if line.startswith(move) and cur is not None:
            cur["left"] = cur["path"]
            cur["path"] = line[len(move):].strip()
            continue
        if line.startswith("*** End Patch"):
            # Closes the last section, so the empty string after the final
            # newline is not appended to it as a context line.
            cur = None
            continue
        if line.startswith("@@") and cur is not None:
            cur["hunks"].append(([], []))
        if line.startswith("***") or line.startswith("@@"):
            continue
        if cur is None:
            continue
        # Each line lands in the file-wide text and in the text of its own hunk.
        olds, news = (cur["old"], cur["hunks"][-1][0]), (cur["new"], cur["hunks"][-1][1])
        if line.startswith("+"):
            for l in news: l.append(line[1:])
        elif line.startswith("-"):
            for l in olds: l.append(line[1:])
        else:
            # Context: it is in the file both before and after the edit.
            body = line[1:] if line.startswith(" ") else line
            for l in olds + news: l.append(body)

def absolute(path):
    return path if os.path.isabs(path) else os.path.normpath(os.path.join(cwd, path))


def emit(tool, tool_input):
    print(json.dumps({
        "session_id": event.get("session_id", ""),
        "cwd": cwd,
        "hook_event_name": os.environ.get("EVENT", "PreToolUse"),
        "tool_name": tool,
        "tool_input": tool_input,
    }))


for f in files:
    # A path the patch removes -- a deleted file, the file a rename leaves -- is
    # shown to the hooks as an edit with no text: a guard that protects the path
    # reads it, and the content guards have nothing to screen.
    if f["verb"] == "Delete File" or "left" in f:
        emit("Edit", {"file_path": absolute(f.get("left", f["path"])), "old_string": "", "new_string": ""})
    if f["verb"] == "Delete File":
        continue
    path = absolute(f["path"])
    tool_input = {"file_path": path}
    if f["verb"] == "Add File":
        tool = "Write"
        tool_input["content"] = "\n".join(f["new"])
    else:
        tool = "Edit"
        tool_input["old_string"] = "\n".join(f["old"])
        tool_input["new_string"] = "\n".join(f["new"])
        # The joined text of a patch with several hunks is in the file nowhere,
        # so a hook that applies the edit to the file could not: one edit per
        # hunk, in the shape a MultiEdit has.
        hunks = [h for h in f["hunks"] if h[0] or h[1]]
        if len(hunks) > 1:
            tool = "MultiEdit"
            tool_input = {"file_path": path, "edits": [
                {"old_string": "\n".join(o), "new_string": "\n".join(n)} for o, n in hunks]}
    emit(tool, tool_input)
' 2>/dev/null) || cannot_run 'the apply_patch payload could not be adapted'

    while IFS= read -r one; do
      [ -n "$one" ] || continue
      # Each adapted payload names its own tool: an "Add File" becomes a Write
      # and must reach the Write-only groups too.
      run_matcher "$EVENT" "$(printf '%s' "$one" | jq -r '.tool_name // empty' 2>/dev/null)" "$one" || exit 2
    done <<<"$PAYLOADS"
    ;;
esac

# One answer for the whole event: a patch runs its hooks once per file, and
# Codex reads one JSON document.
[ -z "$ADVICE" ] || jq -cn --arg e "$EVENT" --arg c "$ADVICE" '{hookSpecificOutput: {hookEventName: $e, additionalContext: $c}}'
exit 0
