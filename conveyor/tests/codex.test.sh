#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 300
# Engine cases: the builder seat on Codex (README.md, Codex builder): its launch and sandbox, its live record and usage,
# its guards, its stop, Claude's limit, and a Claude build beside it unchanged.
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"
# The engine folder, as lib.sh sets it: named here too, so the release closure (tools/closure.sh) follows this file's paths.
SRC=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)

# One issue, #7, its builder the Codex model cx-1 the pack allows (models.allowed.codex-builder), its review a GO, a
# Codex home of the case's own, and a stub `codex`: a review (-o) runs as lib.sh's stub does; `exec --help` names
# --dangerously-bypass-hook-trust unless $STUB/cx-old is there, and then goes on long, as Codex's does (a check that
# stops reading at the flag must not read the help it cut short as a Codex without hooks); a session keeps its arguments one a line (cx-args),
# its folder (cx-pwd) and the prompt it was given on stdin (cx-brief), then runs $STUB/cx-cmd.
cxsetup() {
  setup "[$(issue 7 2026-01-01)]"; echo "$GO" > "$STUB/review.1"
  export CODEX_HOME=$T/$CASE/codex-home; mkdir -p "$CODEX_HOME/sessions/2026"
  tune '.models.allowed["codex-builder"] = ["cx-1"]'; seatset model cx-1
  mv "$STUB/codex" "$STUB/codex-review"
  cat > "$STUB/codex" <<'EOF'
#!/usr/bin/env bash
case " $* " in *" -o "*) exec "$STUB/codex-review" "$@" ;; esac
[ "$1" != --version ] || { echo 'codex-cli 0.167.0'; exit 0; }
[ "$1" != debug ] || exit 1 # `codex debug models` (the host's report, read before the seat starts) is no session: it lists none
[ "$1 $2" != "exec --help" ] || { [ -e "$STUB/cx-old" ] || echo '      --dangerously-bypass-hook-trust'; seq -f '      --option-%g' 20000; exit 0; }
printf '%s\n' "$@" > "$STUB/cx-args"; pwd > "$STUB/cx-pwd"; cat > "$STUB/cx-brief"; . "$STUB/cx-cmd"
EOF
  chmod +x "$STUB/codex"
}
# The opening of a Codex stream, and the session file Codex keeps for it under its home, holding a running total.
cxstart() { # <thread id> <input> <cached> <output>
  echo "{\"type\":\"thread.started\",\"thread_id\":\"$1\"}"
  echo '{"type":"item.completed","item":{"id":"item_0","type":"error","message":"`--dangerously-bypass-hook-trust` is enabled."}}'
  echo '{"type":"turn.started"}'
  echo "{\"type\":\"event_msg\",\"payload\":{\"type\":\"token_count\",\"info\":{\"total_token_usage\":{\"input_tokens\":$2,\"cached_input_tokens\":$3,\"output_tokens\":$4}}}}" \
    > "$CODEX_HOME/sessions/2026/rollout-2026-01-01T00-00-00-$1.jsonl"
}

# Bugs: a Codex builder model is run on Claude Code, or Codex runs outside the worktree, on another model or effort,
# without the card's prompt, with no sandbox, with /tmp or $TMPDIR taken out of the sandbox (the brief's background
# runs, `mktemp -d` in the engine's test runner and the default test slots folder then fail) or without the host's
# test slots folder writable (a test run takes no slot), without the guard
# hook or with hooks waiting on a trust prompt, or with a terminal for its commands (`write_stdin` then types a command
# into a running shell, and Codex runs no PreToolUse hook for it, so the command gets past every guard); its events leave the live record empty (no turns, action or usage, its
# running total unread) or are read as a Claude stream; its line has no tokens or usage.
t_codexbuild() {
  cxsetup; export -f cxstart
  # The host's own test slots folder, which is not under /tmp's default one.
  mkdir -p "$XDG_CONFIG_HOME/conveyor" && echo "{\"testSlots\": 1, \"testSlotsDir\": \"$T/$CASE/slots\"}" > "$XDG_CONFIG_HOME/conveyor/host.json"
  # One turn: a command starts and holds until the case has read the live record ($STUB/go).
  cat > "$STUB/cx-cmd" <<'EOF'
cxstart th-1 1000 600 40
echo '{"type":"item.started","item":{"id":"item_1","type":"command_execution","command":"/bin/bash -lc '"'"'echo two >> a.txt'"'"'","status":"in_progress"}}'
echo two >> a.txt
echo '{"type":"item.completed","item":{"id":"item_1","type":"command_execution","command":"echo two >> a.txt","exit_code":0,"status":"completed"}}'
for i in $(seq 1200); do [ -e "$STUB/go" ] && break; sleep 0.1; done # sleep: the session holds until the case has read its live record
echo '{"type":"item.completed","item":{"id":"item_2","type":"file_change","changes":[{"path":"b.txt","kind":"add"}],"status":"completed"}}'
echo '{"type":"item.completed","item":{"id":"item_3","type":"agent_message","text":"done"}}'
echo '{"type":"turn.completed","usage":{"input_tokens":5000,"cached_input_tokens":4000,"output_tokens":90,"reasoning_output_tokens":30}}'
EOF
  loop run > "$STUB/log" 2>&1 & run=$!
  wait_until "jq -e '.turns == 1 and .usage != null' '$T/$CASE'/cards/*.live" || { : > "$STUB/go"; wait $run; fail "the live record never counted the first item and the running total: $(cat "$STUB/log")"; }
  live=$(jq -c '{step, model, turns, action, usage, last: (.last | type)}' "$T/$CASE"/cards/*.live)
  : > "$STUB/go"; wait $run || fail "run exited non-zero: $(cat "$STUB/log")"
  c=$(st 'select(.step == "picked") | .card'); wt=$T/$CASE/cards/$c
  [ "$live" = '{"step":"build","model":"cx-1","turns":1,"action":"command: /bin/bash -lc '"'"'echo two >> a.txt'"'"'","usage":{"input":400,"write":0,"write1h":0,"read":600,"output":40},"last":"string"}' ] \
    || fail "the live record of the Codex build: $live"
  hook=$(grep '^hooks.PreToolUse=' "$STUB/cx-args")
  [ "$(grep -v '^hooks.PreToolUse=' "$STUB/cx-args")" = "$(printf '%s\n' exec --json -s workspace-write -C "$wt" --add-dir "$T/$CASE/slots" -m cx-1 -c 'model_reasoning_effort="medium"' \
      -c 'web_search="disabled"' \
      --enable hooks --dangerously-bypass-hook-trust --disable unified_exec_tty -c -)" ] && [ "$(cat "$STUB/cx-pwd")" = "$wt" ] \
    || fail "Codex was not run on the model, in the worktree, writing in it, /tmp, \$TMPDIR and the test slots folder, with hooks on and no terminal for its commands: $(cat "$STUB/cx-args" "$STUB/cx-pwd")"
  # The hook is one TOML value (as Codex parses it): one PreToolUse hook on every tool, the guard hook on the card's settings.
  [ "$(python3 -I -c 'import sys, tomllib, json; print(json.dumps(tomllib.loads("h = " + sys.argv[1].split("=", 1)[1])["h"]))' "$hook" | jq -c .)" \
    = "$(jq -cn --arg c "node '$SRC/codex/guard.mjs' '$wt.settings' '$wt'" '[{matcher: "*", hooks: [{type: "command", command: $c, timeout: 600}]}]')" ] \
    || fail "Codex was not given the guard hook on every tool: $hook"
  head -n 1 "$STUB/cx-brief" | grep -qF "Conveyor card $c." && grep -qF 'body of 7' "$STUB/cx-brief" || fail "Codex was not given the card's prompt: $(head -c 300 "$STUB/cx-brief")"
  [ "$(st 'select(.step == "build") | [.model, .effort, .tokens, .usage, .stats.turns, .stats.tools] | tojson')" \
    = '["cx-1","medium",{"claude":0,"codex":1090},{"input":1000,"write":0,"write1h":0,"read":4000,"output":90},3,{"command_execution":1,"file_change":1}]' ] \
    || fail "the build line: $(st 'select(.step == "build")')"
  [ ! -e "$STUB/sessions" ] || fail "Claude Code ran for a Codex model: $(cat "$STUB/sessions")"
  [ -z "$(find "$CODEX_HOME/sessions" -name 'rollout-*')" ] || fail "the session file Codex kept was left behind"
  [ "$(st 'select(.step == "landed") | .issue')" = 7 ] || fail "the card did not land: $(st '"\(.step) \(.reason)"')"
  [ "$(loop snapshot | jq -c '.modelSettings.builder | [.model, .effort, .agent, (.efforts | length)]')" = '["cx-1","medium","codex",5]' ] \
    || fail "the Board's builder settings are not Codex's: $(loop snapshot | jq -c .modelSettings.builder)"
}

# Bugs: a Codex build that `control stop` ends before its turn completed loses what it used so far (its running total,
# in the session file Codex keeps), or is read as a Claude stream.
t_codexstop() {
  cxsetup; export -f cxstart; tune '.tunables.idle = 1 | .tunables.poll = 1'
  printf '%s\n' 'cxstart th-2 900 100 8' 'sleep 60 & : > "$STUB/building"; wait' > "$STUB/cx-cmd" # sleep: the build's child, there to be stopped with it
  ( export CONVEYOR_MAIN=$R CONVEYOR_CARDS=$T/$CASE/cards
    exec timeout 120 bash "$SRC/conveyor.sh" serve > "$STUB/serve.out" 2>&1 ) & pid=$!; trap 'kill $pid 2>/dev/null' EXIT
  wait_until "[ -e '$STUB/building' ]" || fail "serve did not start #7: $(cat "$STUB/serve.out")"
  card=$(st 'select(.issue == 7 and .step == "picked") | .card'); loop control stop >/dev/null
  wait_until "[ -z \"\$(st 'select(.issue == 7) | .card')\" ]" || fail "stop did not end the card: $(cat "$STUB/serve.out")"
  [ "$(jq -c --arg c "$card" 'select(.card == $c and .step == "build") | [.result, .model, .tokens.codex, .usage]' "$ST/retried.jsonl")" \
    = '["stopped","cx-1",808,{"input":800,"write":0,"write1h":0,"read":100,"output":8}]' ] \
    || fail "the stopped Codex build's spend is not recorded: $(jq -c --arg c "$card" 'select(.card == $c)' "$ST/retried.jsonl")"
  kill $pid 2>/dev/null; wait $pid 2>/dev/null; trap - EXIT
}

# Bugs: a command the Bash guardrails refuse runs in a Codex session, or is refused without the guard's message (Codex
# reads a refusal from exit 2 and stderr); a command they rewrite (an unbounded search) runs as written; a command
# they allow is refused; a subagent is let through; apply_patch, Codex's file
# tool, goes unscreened. The stub runs the hook as Codex does: the command its arguments name, through a shell, the
# call on stdin.
t_codexguard() {
  command -v node >/dev/null || fail "node is needed to run the guard hook as Codex would"
  cxsetup
  # The calls, one a line: the tool and its input, as Codex names them.
  jq -cn '["Bash", {command: "node --test a.test.js"}], ["Bash", {command: "rg two"}], ["Bash", {command: "cat a.txt"}], ["spawn_agent", {message: "x"}],
    ["apply_patch", {command: "*** Begin Patch\n*** Update File: a.txt\n@@\n-one\n+three\n*** End Patch"}],
    ["apply_patch", {command: "*** Begin Patch\n*** Add File: b.txt\n+x\n*** Add File: package.json\n+{\"dependencies\": {\"leftpad\": \"1.0.0\"}}\n*** End Patch"}]' > "$STUB/calls"
  cat > "$STUB/cx-cmd" <<'EOF'
cmd=$(python3 -I -c 'import sys, tomllib; print(tomllib.loads("h = " + sys.argv[1].split("=", 1)[1])["h"][0]["hooks"][0]["command"])' "$(grep '^hooks.PreToolUse=' "$STUB/cx-args")")
while IFS= read -r c; do
  jq -c --arg d "$PWD" '{session_id: "s1", cwd: $d, hook_event_name: "PreToolUse", tool_name: .[0], tool_input: .[1]}' <<<"$c" \
    | bash -c "$cmd" > "$STUB/o" 2> "$STUB/e"; rc=$?; echo "$(jq -r '.[0]' <<<"$c") rc=$rc out=$(cat "$STUB/o") err=$(head -n 1 "$STUB/e")" >> "$STUB/cx-guard"
done < "$STUB/calls"
echo two >> a.txt
echo '{"type":"thread.started","thread_id":"th-3"}'
echo '{"type":"turn.completed","usage":{"input_tokens":10,"cached_input_tokens":0,"output_tokens":1}}'
EOF
  out=$(loop run 2>&1) || fail "run exited non-zero: $out"
  g=$(cat "$STUB/cx-guard"); c=$(st 'select(.step == "picked") | .card')
  grep -qx 'Bash rc=2 out= err=BLOCKED: bare node --test without --max-old-space-size=4096, or with a larger heap flag beside it. Use the npm script (npm run test:unit / test:guards) or add the flag and drop any larger one. .claude/rules/tests.md, Heap cap.' <<<"$g" \
    || fail "an uncapped test run was not refused with the guard's message: $g"
  grep -qxF "Bash rc=0 out=$(jq -cn --arg c "( set -o pipefail; { 'rg' 'two' '$T/$CASE/cards/$c'; } 2>&1 | { head -n 200; cat >/dev/null; } )" \
      '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "allow", updatedInput: {command: $c}}}') err=" <<<"$g" \
    || fail "an unbounded search was not rewritten as the guard rewrites it: $g"
  grep -qx 'Bash rc=0 out= err=' <<<"$g" && grep -q '^spawn_agent rc=2 out= err=conveyor: the tool spawn_agent is not one a card session may use' <<<"$g" \
    || fail "an allowed command was refused, or a subagent let through: $g"
  grep -qx 'apply_patch rc=0 out= err=' <<<"$g" \
    && grep -qx "apply_patch rc=2 out= err=BLOCKED: adding a new dependency ('leftpad' in NEW file $T/$CASE/cards/$c/package.json) requires the owner's explicit approval first." <<<"$g" \
    || fail "apply_patch was not screened file by file: $g"
}

# Bugs: a Codex build starts with a Codex that cannot run hooks headless, or with the guard hook missing, and runs
# unguarded; the card is blocked without saying why.
t_codexnoguard() {
  cxsetup; echo 'echo two >> a.txt' > "$STUB/cx-cmd"; : > "$STUB/cx-old"
  loop run > "$STUB/log" 2>&1
  [ ! -e "$STUB/cx-args" ] && st 'select(.step == "blocked") | .reason' | grep -qF 'cannot run hooks in a headless session (its exec has no --dangerously-bypass-hook-trust): a Codex session would run without the command guards, so it does not start' \
    || fail "a Codex that cannot run hooks headless started, or the block does not say why: $(st 'select(.step == "blocked") | .reason')"
  CASE=${CASE}v; cxsetup; echo 'echo two >> a.txt' > "$STUB/cx-cmd"
  CONVEYOR_CODEX_GUARD=$T/$CASE/nosuch/guard.mjs loop run > "$STUB/log" 2>&1
  [ ! -e "$STUB/cx-args" ] && st 'select(.step == "blocked") | .reason' | grep -qF "the Codex guard hook $T/$CASE/nosuch/guard.mjs (or opencode/screen.mjs or opencode/guard.sh beside it) is missing" \
    || fail "Codex started with the guard hook missing, or the block does not say why: $(st 'select(.step == "blocked") | .reason')"
}

# Bugs: with Codex builder models allowed, a Claude build is launched otherwise than before (its arguments, its
# settings, its effort), or is run by Codex; its line is read as a Codex session's.
t_codexclaude() {
  cxsetup; seatset model m
  out=$(loop run 2>&1) || fail "run exited non-zero: $out"
  c=$(st 'select(.step == "picked") | .card')
  [ "$(cat "$STUB/sessions")" = "-p --model m --effort medium --permission-mode bypassPermissions --disallowedTools Agent --setting-sources  --strict-mcp-config --settings $T/$CASE/cards/$c.settings --output-format stream-json --verbose" ] \
    || fail "the Claude build was not launched as before: $(cat "$STUB/sessions")"
  [ ! -e "$STUB/cx-args" ] || fail "Codex ran the Claude build: $(cat "$STUB/cx-args")"
  [ "$(st 'select(.step == "build") | [.model, .effort, .tokens, .usage] | tojson')" = '["m","medium",{"claude":35,"codex":0},{"input":10,"write":20,"write1h":0,"read":999,"output":5}]' ] \
    || fail "the Claude build's line: $(st 'select(.step == "build")')"
  [ "$(st 'select(.step == "landed") | .issue')" = 7 ] || fail "the card did not land: $(st '"\(.step) \(.reason)"')"
}

# Bugs: Claude's weekly limit holds back a card whose builder is Codex (with a Codex reviewer, no Claude session runs);
# or, the other way, it stops holding back a Claude builder's card.
t_codexlimit() {
  cxsetup; printf '%s\n' 'echo two >> a.txt' 'echo "{\"type\":\"thread.started\",\"thread_id\":\"th-4\"}"' \
    'echo "{\"type\":\"turn.completed\",\"usage\":{\"input_tokens\":1,\"output_tokens\":1}}"' > "$STUB/cx-cmd"
  tune '.tunables.limitTtl = 0'; export CONVEYOR_LIMIT_CMD='echo "{\"seven_day\":{\"utilization\":95}}"'
  loop control guard 90 >/dev/null
  seatset model m; out=$(loop run 1 2>&1); grep -q 'paused by guard' <<<"$out" && [ -z "$(st 'select(.step == "picked") | .issue')" ] \
    || fail "a Claude builder's card was not held at the limit: $out"
  seatset model cx-1; out=$(loop run 2>&1) || fail "run exited non-zero: $out"
  [ "$(st 'select(.step == "landed") | .issue')" = 7 ] && [ -e "$STUB/cx-args" ] || fail "Claude's limit held back the Codex builder's card: $out"
}

# Bug: a Codex build the API refused (in Codex's own words, "exceeded retry limit, last status: 429") was read as
# Claude's stream, so as no API error: the card blocked at once, nothing was marked, and the loop went on picking cards
# into the outage. It runs again, as a Claude session does, and the refused try's tokens are on its line.
t_codexapi() {
  cxsetup; tune '.tunables.apiPause = 0.1'; echo 1 > "$STUB/refuse"
  # shellcheck disable=SC2016
  printf '%s\n' 'echo x >> "$STUB/cx-tries"; n=$(cat "$STUB/refuse"); echo "{\"type\":\"thread.started\",\"thread_id\":\"th-5\"}"' \
    '[ "$n" -le 0 ] || { echo 0 > "$STUB/refuse"; echo "{\"type\":\"error\",\"message\":\"exceeded retry limit, last status: 429 Too Many Requests\"}"' \
    '  echo "{\"type\":\"turn.failed\",\"error\":{\"message\":\"exceeded retry limit, last status: 429 Too Many Requests\"}}"; exit 1; }' \
    'echo two >> a.txt; echo "{\"type\":\"turn.completed\",\"usage\":{\"input_tokens\":10,\"cached_input_tokens\":0,\"output_tokens\":1}}"' > "$STUB/cx-cmd"
  out=$(loop run 2>&1) || fail "run exited non-zero: $out"
  [ "$(wc -l < "$STUB/cx-tries")" = 2 ] && [ "$(st 'select(.step | IN("blocked", "landed")) | .step')" = landed ] \
    || fail "a Codex build the API refused once was not run again and landed: $(wc -l < "$STUB/cx-tries") tries, $(st '[.step, .reason] | join(" ")' | tr '\n' ,)"
  jq -e numbers "$ST/apierror" >/dev/null 2>&1 || fail "a Codex build the API refused marked no API error"
  [ "$(st 'select(.step == "build") | .tokens.codex')" = 11 ] || fail "the build line: $(st 'select(.step == "build")')"
}
