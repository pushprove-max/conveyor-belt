# SPDX-License-Identifier: Apache-2.0
# The builder seat on the Antigravity CLI: the CLI antigravity, whose command is agy (CLIBIN, lib/paths.sh). Its
# session (agyrun()), its reader (AGYREAD), the check it starts with (agyready()), the reason of a session that failed
# (agyfailed()) and doctor's check of its sign-in (agysignin()). Sourced by lib/session.sh.
# AGYREAD: the fields of an agy session's line, from its output (agyread.jq), as OPENCODEREAD gives an OpenCode one's.
# shellcheck disable=SC2034 # read by session1() in lib/session.sh, which sources this file
AGYREAD=$(<"$HERE/jq/agyread.jq")
# The word -p is given: in stream-JSON input agy takes the prompt from stdin and drops the one a flag gives.
AGYP='The task is in the message on stdin.'
# One agy build, fix or rebase session (builder(), lib/session.sh), run as a Claude one is: headless (agy -p), in the
# worktree, the prompt on stdin as one user message of stream-JSON input (stdin then ends, so agy ends after that
# turn), its events as stream-JSON lines in <worktree>.out, on the seat's model, at its effort when the seat names
# one (else agy's default for the model). Its mode is auto, which runs a tool call with no prompt where agy can: in
# print mode nobody answers one. Its time limit (--print-timeout) is the step's, buildTimeout, under which timeout
# also ends it, as it ends the other CLIs: a tool call that would ask for a permission can stall agy's print mode with
# no output and no end. The card's guards run before each of its tool calls: the hooks file agyready() wrote.
agyrun() { # <worktree> <prompt> <model> [effort]
  local m e=(); m=$(jq -cn --arg p "$2" '{event: "user", message: {content: $p}}') || exit 1
  [ -z "${4:-}" ] || e=(--effort "$4")
  export CLAUDE_PROJECT_DIR=$1
  exec "${KEEP[@]}" timeout --kill-after=30 "$BUILD_TIMEOUT" agy -p "$AGYP" --input-format stream-json --output-format stream-json \
    --mode auto --print-timeout "${BUILD_TIMEOUT}s" --model "$3" "${e[@]}" <<<"$m" > "$1.out" 2> "$1.err" 8>&-
}
# An agy session starts only with every guard in place, else it prints why and fails: agy on PATH, node for the guard
# hook, the guard hook and what it runs (AGY_GUARD, ../opencode/screen.mjs and guard.sh) and the card's settings file.
# It then writes the worktree's .agents/hooks.json, the workspace hooks file agy reads: one PreToolUse hook on every
# tool, the guard hook on the card's settings (agy/guard.mjs). git's exclude file for the repository (read by every
# worktree of it, as deps() in lib/push.sh uses it) names that file once, so it is never part of the change; a project
# that tracks its own .agents/hooks.json starts no agy session, as the guard's file would replace it.
agyready() { # <worktree>
  local g=${AGY_GUARD%/*}/../opencode x
  command -v agy >/dev/null || { echo "agy is not on PATH, for the Antigravity builder model"; return 1; }
  command -v node >/dev/null || { echo "node is not on PATH, for the agy guard hook: an agy session would run without the command guards, so it does not start"; return 1; }
  [ -f "$AGY_GUARD" ] && [ -f "$g/screen.mjs" ] && [ -x "$g/guard.sh" ] \
    || { echo "the agy guard hook $AGY_GUARD (or opencode/screen.mjs or opencode/guard.sh beside it) is missing: an agy session would run without the command guards, so it does not start"; return 1; }
  [ -s "$1.settings" ] || { echo "the card's settings file $1.settings is missing: an agy session would run without the command guards, so it does not start"; return 1; }
  ! git -C "$1" ls-files --error-unmatch -- .agents/hooks.json >/dev/null 2>&1 \
    || { echo "the project tracks its own .agents/hooks.json, which the agy guard hook's file would replace: an agy session would run without the command guards, so it does not start"; return 1; }
  x=$(git -C "$1" rev-parse --path-format=absolute --git-path info/exclude) && mkdir -p "${x%/*}" "$1/.agents" \
    && { grep -qxF /.agents/hooks.json "$x" 2>/dev/null || { { [ ! -s "$x" ] || [ -z "$(tail -c 1 "$x")" ] || echo >> "$x"; } && echo /.agents/hooks.json >> "$x"; }; } \
    && jq -n --arg c "node $(sq "$AGY_GUARD") $(sq "$1.settings") $(sq "$1")" \
      '{"conveyor-card-guard": {PreToolUse: [{matcher: "*", hooks: [{type: "command", command: $c, timeout: 600}]}]}}' > "$1/.agents/hooks.json" \
    || { echo "the agy hooks file $1/.agents/hooks.json could not be written: an agy session would run without the command guards, so it does not start"; return 1; }
}
# The reason of an agy session that ended with an exit that is not 0, its stderr's last 60 lines below it. One ended
# at the step's time limit (timeout's exit 124, or agy's own words for its --print-timeout) says so, naming agy.
agyfailed() { # <exit> <worktree>
  if [ "$1" = 124 ] || tail -n 20 "$2.err" 2>/dev/null | grep -Eqi 'print.?timeout'; then
    printf 'agy ended at the step time limit, buildTimeout (%ss), with no answer (%s): in print mode agy can stall with no output on a tool call that asks for a permission\n' \
      "$BUILD_TIMEOUT" "$(exitsaid "$1" "$BUILD_TIMEOUT")"
  else printf 'agy session failed (%s)\n' "$(exitsaid "$1" "$BUILD_TIMEOUT")"; fi
  tail -n 60 "$2.err" 2>/dev/null
}
# doctor's check of agy's sign-in, when agy is on PATH: a Gemini API key (agy's settings file sets modelProvider gemini,
# and GEMINI_API_KEY is set: either alone does nothing), else the cached sign-in of an interactive agy session. agy
# keeps that one in the system keyring, which no file shows, so one headless call with no tools asks: one that says
# its sign-in is missing names the command that signs in. With modelProvider gemini and no GEMINI_API_KEY, agy runs
# on no sign-in at all (it reports the key not set), so that is missing, with the command that sets the key; no call
# is made. Prints one ok, missing or warning line; fails on missing.
agysignin() {
  local s=$HOME/.gemini/antigravity-cli/settings.json d o rc
  if jq -e '.modelProvider == "gemini"' "$s" >/dev/null 2>&1; then
    [ -n "${GEMINI_API_KEY:-}" ] || {
      echo "missing: a Gemini API key for antigravity (agy): modelProvider is gemini in $s, and GEMINI_API_KEY is not set; fix: export GEMINI_API_KEY=<your Gemini API key> in the environment Conveyor runs in"; return 1; }
    echo "ok: antigravity (agy), signed in with the Gemini API key (GEMINI_API_KEY, and modelProvider gemini in $s)"; return 0
  fi
  d=$(mktemp -d) || { echo "warning: antigravity (agy): its sign-in was not checked (no folder for its call)"; return 0; }
  echo "conveyor: asking agy one question to check its sign-in (up to 60 s)..." >&2
  o=$(cd "$d" && timeout --kill-after=10 60 agy -p 'Reply with the one word OK.' --output-format json --print-timeout 50s < /dev/null 2>&1 8>&-); rc=$?
  rm -rf "$d"
  if [ "$rc" = 0 ]; then echo "ok: antigravity (agy), signed in"
  elif grep -Eqi "$LOGINSAID" <<<"$o"; then
    echo "missing: a sign-in for antigravity (agy): it has no cached credentials and no Gemini API key; fix: run agy in a terminal and sign in, or set modelProvider gemini in $s and GEMINI_API_KEY"; return 1
  else echo "warning: antigravity (agy) did not answer a call to check its sign-in ($(exitsaid "$rc" 60)): $(cliwords "$o" | tail -n 1)"; fi
}
