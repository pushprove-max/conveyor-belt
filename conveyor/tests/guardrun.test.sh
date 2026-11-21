#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 300
# Engine cases: the guard runner (guardrun.sh), which every blocking guard hook of a card session runs behind.
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"
# The engine folder, as lib.sh sets it: named here too, so the release closure (tools/closure.sh) follows this file's paths.
SRC=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)

# grcall <worktree> <timeout> <command>: one call through the guard runner, as Claude Code runs the hook; prints its
# stdout, its stderr, then rc=<exit>.
grcall() {
  echo '{"tool_name":"Bash","tool_input":{"command":"ls"}}' | CLAUDE_PROJECT_DIR=$1 bash "$SRC/guardrun.sh" "$2" "$3" 2>&1; echo "rc=$?"
}

# Bugs: a guard that crashes or is missing refuses the call with no word of which guard failed or why, so the session
# cannot say what is wrong; a second failure of the same guard lets the session go on; a guard that answers (allows,
# rewrites, refuses) has its answer changed or counted as a failure.
t_guardrun() {
  local d=$T/$CASE w out
  w=$d/wt; mkdir -p "$w"
  printf '%s\n' 'echo "first line" >&2; echo "crash.sh: cannot read its rules file" >&2; exit 1' > "$d/crash.sh"; chmod +x "$d/crash.sh"
  out=$(grcall "$w" 30 "'$d'/crash.sh")
  [ "$out" = $'conveyor: the guard crash.sh failed to run: it crashed with exit 1: crash.sh: cannot read its rules file. The call is refused.\nrc=2' ] \
    || fail "a crashed guard's refusal does not name it, its exit and its last error line: $out"
  [ "$(cat "$w.guardfail")" = $'crash.sh\tit crashed with exit 1: crash.sh: cannot read its rules file' ] || fail "the failure was not recorded: $(cat "$w.guardfail" 2>&1)"
  out=$(grcall "$w" 30 "'$d'/nosuch.sh")
  grep -q '^conveyor: the guard nosuch.sh failed to run: its file is missing (.*No such file or directory). The call is refused.$' <<<"$out" && [ "${out##*$'\n'}" = rc=2 ] \
    || fail "a missing guard's refusal does not say its file is missing: $out"
  # The second failure of one guard stops the session: Claude Code ends it on "continue": false, and the call is denied.
  out=$(grcall "$w" 30 "'$d'/crash.sh")
  # OpenCode and Codex (opencode/guard.sh) read only the deny's reason, so it names the guard as stopReason does.
  [ "${out##*$'\n'}" = rc=0 ] && jq -e '.continue == false and .hookSpecificOutput.permissionDecision == "deny"
      and (.stopReason | test("^conveyor: the guard crash.sh failed to run: it crashed with exit 1: .* the session stops and the card blocks[.]$"))
      and .hookSpecificOutput.permissionDecisionReason == .stopReason' <<<"${out%$'\n'*}" >/dev/null \
    || fail "a guard's second failure did not stop the session with its reason: $out"
  # A guard's own answers pass through, and are no failure.
  printf '%s\n' 'echo "refused: no" >&2; exit 2' > "$d/no.sh"; printf '%s\n' 'cat > /dev/null; echo "{\"x\":1}"' > "$d/yes.sh"; chmod +x "$d/no.sh" "$d/yes.sh"
  [ "$(grcall "$w" 30 "'$d'/no.sh")" = $'refused: no\nrc=2' ] && [ "$(grcall "$w" 30 "'$d'/yes.sh")" = $'{"x":1}\nrc=0' ] \
    && [ "$(wc -l < "$w.guardfail")" = 3 ] || fail "a guard's answer was changed or counted as a failure: $(grcall "$w" 30 "'$d'/no.sh") $(cat "$w.guardfail")"
}

# Bug: a guard that hangs is ended by Claude Code with no word of which guard it was; the runner ends it at its own
# time-out and says so.
t_guardtimeout() {
  local d=$T/$CASE out start=$SECONDS
  mkdir -p "$d/wt"; echo 'exec sleep 30' > "$d/hang.sh"; chmod +x "$d/hang.sh" # sleep: a guard that hangs, ended by its 1 s time-out
  out=$(grcall "$d/wt" 1 "'$d'/hang.sh")
  [ "$out" = $'conveyor: the guard hang.sh failed to run: it ran past its 1s time-out. The call is refused.\nrc=2' ] && [ $((SECONDS - start)) -lt 10 ] \
    || fail "a hung guard's refusal does not say it ran past its time-out: $out"
}

# Bug: a card session whose guard keeps crashing goes on with every call refused, and its card is not blocked, or is
# blocked with no word of the guard. The pack's crashing guard, marked blocking, runs behind the runner in the card's
# settings (cardsettings()); the build stub runs it on two Bash calls as Claude Code runs a PreToolUse hook, then goes
# on as an OpenCode or Codex session does (they do not obey "continue": false); the session is ended at once, the card
# blocks naming the guard, and the snapshot's Needs you shows it.
t_guardblock() {
  local d=$T/$CASE c=c7-7 out r start
  setup '[]'; CARDS=$d/cards; mkdir -p "$CARDS"
  printf '%s\n' 'echo "crash.sh: cannot read its rules file" >&2; exit 1' > "$d/crash.sh"; chmod +x "$d/crash.sh"
  jq -n --arg c "$(printf "'%s'/crash.sh" "$d")" '{hooks: {PreToolUse: [{matcher: "Bash", hooks: [{type: "command", command: $c, onFailure: "block"}]}]}}' > "$R/.conveyor/hooks.json"
  git -C "$R" worktree add -q --detach "$CARDS/$c" refs/heads/main || fail "the card's worktree could not be made"
  landed 7 | jq -c --arg c "$c" '.card = $c | .step = "picked"' >> "$ST/cards.jsonl"
  cat > "$STUB/build" <<'EOF'
h=$(jq -r '.hooks.PreToolUse[] | select(.matcher == "Bash") | .hooks[].command | select(test("crash"))' "$PWD.settings")
for i in 1 2; do echo '{"tool_name":"Bash","tool_input":{"command":"ls"}}' | CLAUDE_PROJECT_DIR=$PWD sh -c "$h" > "$STUB/hook.$i" 2>&1; echo "rc=$?" >> "$STUB/hook.$i"; done
exec sleep 60 # sleep: a session that goes on after the second refusal, which the engine must end
EOF
  start=$SECONDS
  fx_in 'w=$CARDS/c7-7; cd "$R" && cardsettings "$w.settings" && began c7-7 7 build || { echo "began failed"; exit 1; }
    t=$(session "$w" "Build the issue."); rc=$?; [ $rc = 0 ] || block c7-7 7 "$w" "build: $t"; echo "step: $rc"'
  [ "$(tail -n 1 "$d/run.out")" = "step: 1" ] || fail "the session with a guard that failed twice did not fail: $(cat "$d/run.out")"
  [ $((SECONDS - start)) -lt 30 ] || fail "the session went on for $((SECONDS - start))s after its guard failed twice"
  # The failures are read once: a next session of the card starts with none of them.
  [ ! -e "$CARDS/$c.guardfail" ] || fail "the session left its guard failures for the next one: $(cat "$CARDS/$c.guardfail")"
  # The text the session sees on the first refusal names the guard and its error.
  [ "$(cat "$STUB/hook.1")" = $'conveyor: the guard crash.sh failed to run: it crashed with exit 1: crash.sh: cannot read its rules file. The call is refused.\nrc=2' ] \
    || fail "the first refusal does not name the guard and its error: $(cat "$STUB/hook.1" 2>&1)"
  r=$(st 'select(.step == "blocked") | .reason')
  [ "$r" = "build: guard crash.sh is failing: it crashed with exit 1: crash.sh: cannot read its rules file" ] || fail "the card was not blocked naming the guard and its error: $r $(cat "$d/run.out")"
  out=$(loop snapshot --fresh) || fail "snapshot exited non-zero"
  jq -e '[.needsYou.blocked[] | select(.issue == 7) | .reason | test("guard crash.sh is failing")] == [true]' <<<"$out" >/dev/null \
    || fail "Needs you does not show the failing guard: $(jq -c '.needsYou.blocked' <<<"$out")"
}
