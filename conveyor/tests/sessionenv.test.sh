#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 120
# Engine cases: what each Claude session a card starts is launched with: the tools a builder is not given, and no
# auto memory in any session.
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"
# The engine folder, as lib.sh sets it: named here too, so the release closure (tools/closure.sh) follows this file's paths.
SRC=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)

# Bugs: a builder or fixer session was given the scheduling, messaging and orchestration tools (a headless run with
# a wakeup pending waits for it, even past its time limit); and card sessions loaded Claude Code's auto memory, notes
# carried from card to card. Each launcher (the build, which a fix also runs on, the Claude review, the judge, the
# pick's and the split's askmodel(), a test action) is called alone in the engine shell as `conveyor.sh run` loads it;
# the claude stub keeps, per call, the auto-memory setting it was given and its arguments.
t_sessionenv() {
  local out a
  setup "[$(issue 7 2026-01-01)]"
  # stub: one line per call, the session's auto-memory setting and its arguments; any call answers one result line.
  cat > "$STUB/claude" <<'EOF'
#!/usr/bin/env bash
cat > /dev/null; printf '%s\t%s\n' "${CLAUDE_CODE_DISABLE_AUTO_MEMORY:-unset}" "$*" >> "$STUB/calls"
echo '{"type":"result","is_error":false,"result":"F1 DECLINE: wrong","num_turns":1,"usage":{"input_tokens":3,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"output_tokens":2}}'
EOF
  chmod +x "$STUB/claude"; mkdir -p "$T/$CASE/cards"
  out=$( ( unset CLAUDE_CODE_DISABLE_AUTO_MEMORY; export CONVEYOR_MAIN=$R CONVEYOR_CARDS=$T/$CASE/cards
    . "$SRC/conveyor.sh" state-dir > /dev/null && eval "$(grep '^\. "\$HERE/lib/' "$SRC/commands/run.sh")" && names || exit 1
    w=$CARDS/c7 && git -C "$MAIN" worktree add -q --detach "$w" && echo two >> "$w/a.txt" && git -C "$w" add a.txt || exit 1
    claude=$(command -v claude); for k in build review judge pick split testaction; do
      case $k in
        build) ( builder "$w" brief m medium "" claude ) ;;
        review) claudereview "$w" brief instructions m medium ;;
        judge) CALLSEAT='{"agent":"claude","model":"m","effort":"low"}' judgecall "$w" judge "F1 a finding" ;;
        pick) d=$(mktemp -d) && askmodel "$d" 60 low "" question ;;
        split) d=$(mktemp -d) && ASKSEAT=judge askmodel "$d" 60 low '{"judge":{"agent":"claude","model":"m"}}' question ;;
        testaction) mkdir -p "$CARDS/ta" "$TESTACTS" && tarun '{"id": "ta1", "cli": "claude", "model": "m", "effort": "low", "action": "explain"}' "$CARDS/ta" question ;;
      esac
      echo "$k $(wc -l < "$STUB/calls" 2>/dev/null || echo 0) $claude"
    done ) 2>&1 )
  # Each launcher made exactly one more claude call than the one before it.
  [ "$(grep -cE '^(build 1|review 2|judge 3|pick 4|split 5|testaction 6) ' <<<"$out")" = 6 ] \
    || fail "a launcher did not start exactly one claude session: $out $(cat "$STUB/calls" 2>&1)"
  [ "$(cut -f 1 "$STUB/calls" | sort -u)" = 1 ] || fail "a card session ran with auto memory on: $(cat "$STUB/calls")"
  a=$(sed -n 1p "$STUB/calls")
  for t in ScheduleWakeup CronCreate CronDelete CronList Monitor RemoteTrigger PushNotification SendMessage ListAgents Workflow Agent; do
    [[ $a =~ --disallowedTools\ ([^ ]*) ]] && [[ ,${BASH_REMATCH[1]}, == *,$t,* ]] || fail "the builder is given $t: $a"
  done
  [[ $a != *WebFetch* && $a != *WebSearch* ]] || fail "the builder is not given WebFetch or WebSearch: $a"
}

# The rule Only the Test step runs tests reaches the card's command guard as CONVEYOR_TESTSTEPONLY, which builder()
# sets from the record the card started on (CARDCTL). Bugs it catches: with the rule on, the guard was not told, so the
# session's test commands still ran; or a 1 the loop's own shell inherited reached a card whose rule is off.
t_sessionteststep() {
  local out
  setup "[$(issue 7 2026-01-01)]"
  # stub: one line per call, the rule the session was given; any call answers one result line.
  cat > "$STUB/claude" <<'EOF'
#!/usr/bin/env bash
cat > /dev/null; echo "${CONVEYOR_TESTSTEPONLY:-unset}" >> "$STUB/calls"
echo '{"type":"result","is_error":false,"result":"done","num_turns":1,"usage":{"input_tokens":3,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"output_tokens":2}}'
EOF
  chmod +x "$STUB/claude"; mkdir -p "$T/$CASE/cards"
  out=$( ( export CONVEYOR_MAIN=$R CONVEYOR_CARDS=$T/$CASE/cards CONVEYOR_TESTSTEPONLY=1
    . "$SRC/conveyor.sh" state-dir > /dev/null && eval "$(grep '^\. "\$HERE/lib/' "$SRC/commands/run.sh")" && names || exit 1
    w=$CARDS/c7 && git -C "$MAIN" worktree add -q --detach "$w" || exit 1
    ( CARDCTL='{"rules": {"teststeponly": false}}' builder "$w" brief m medium "" claude )
    ( CARDCTL='{"rules": {"teststeponly": true}}' builder "$w" brief m medium "" claude ) ) 2>&1 )
  [ "$(paste -sd ' ' "$STUB/calls" 2>/dev/null)" = '0 1' ] \
    || fail "the builder sessions (rule off, then on) were not given CONVEYOR_TESTSTEPONLY 0 then 1: $(cat "$STUB/calls" 2>&1) $out"
}

# Bugs: a build or fix session (Claude, Codex or OpenCode) in a project with ast-grep installed could not run `ast-grep`
# by its bare name, as a card session loads no plugin, so its CLI puts no plugin bin/ on its PATH; or, with ast-grep not
# installed, the session's PATH changed. builder() (a fix runs on it too) is called alone in the engine shell, as
# `conveyor.sh run` loads it. ast-grep is the plugin's bin/ast-grep, which runs the Board's virtualenv's
# ($XDG_DATA_HOME): here a stand-in that says it ran and with what.
t_sessionast() {
  local d=$T/$CASE v a out
  setup "[$(issue 7 2026-01-01)]"
  v=$d/data/conveyor/board-venv/bin; mkdir -p "$v" "$d/bin" "$d/none" "$d/cards" || fail "the fixture folders could not be made"
  printf '#!/bin/sh\n[ "$1" != --version ] || exit 0\necho "ast-grep ran: $*"\n' > "$v/ast-grep" && chmod +x "$v/ast-grep" || fail "the ast-grep stand-in"
  for a in claude codex opencode; do
    # stub: each CLI the builder starts runs ast-grep by its bare name and keeps its name, what ast-grep printed and its PATH.
    printf '#!/usr/bin/env bash\ncat > /dev/null\nprintf "%%s\\t%%s\\t%%s\\n" %s "$(ast-grep run -p x -l bash 2>&1 | head -n 1)" "$PATH" >> %q\n' "$a" "$d/calls" > "$d/bin/$a" \
      && chmod +x "$d/bin/$a" || fail "the $a stub could not be made"
  done
  out=$( ( export CONVEYOR_MAIN=$R CONVEYOR_CARDS=$d/cards PATH=$d/bin:$PATH
    . "$SRC/conveyor.sh" state-dir > /dev/null && eval "$(grep '^\. "\$HERE/lib/' "$SRC/commands/run.sh")" && names || exit 1
    w=$CARDS/c7 && git -C "$MAIN" worktree add -q --detach "$w" && echo '{}' > "$w.settings" || exit 1
    for x in "$d/data" "$d/none"; do
      export XDG_DATA_HOME=$x
      ( builder "$w" brief m medium "" claude ); ( builder "$w" brief x medium "" codex ); ( builder "$w" brief opencode:p/m "" "" opencode )
    done ) 2>&1 )
  [ "$(cut -f 1 "$d/calls" 2>/dev/null | paste -sd ' ' -)" = 'claude codex opencode claude codex opencode' ] \
    || fail "builder() with each CLI, ast-grep installed then not, did not start the six sessions: $(cat "$d/calls" 2>&1) $out"
  while IFS=$'\t' read -r a v _; do
    [ "$v" = 'ast-grep ran: run -p x -l bash' ] || fail "with ast-grep installed, a $a session's \`ast-grep run -p x -l bash\` printed: $v"
  done < <(head -n 3 "$d/calls")
  while IFS=$'\t' read -r a _ v; do
    [[ :$v: != *":${SRC%/*}/bin:"* ]] || fail "with ast-grep not installed (none under $d/none), a $a session's PATH has the plugin's bin/: $v"
  done < <(tail -n 3 "$d/calls")
}
