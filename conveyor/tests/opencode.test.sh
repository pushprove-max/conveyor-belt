#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 300
# Engine cases: the builder seat on OpenCode (README.md, OpenCode builder): its launch, its live record and usage,
# its guards, and a Claude build beside it unchanged.
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"
# The engine folder, as lib.sh sets it: named here too, so the release closure (tools/closure.sh) follows this file's paths.
SRC=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)

# One issue, #7, its builder an OpenCode model the pack allows, its review a GO, and a stub `opencode`: it says its
# version ($STUB/oc-version, else 1.19.5) and its one model (`opencode models`), keeps the prompt it was given on stdin (oc-brief), its arguments and folder
# (oc-run), the environment the engine gave it (oc-env) and its config file (oc-config), then runs $STUB/oc-cmd.
ocsetup() {
  setup "[$(issue 7 2026-01-01)]"; echo "$GO" > "$STUB/review.1"
  tune '.models.allowed.opencode = ["opencode:prov/mod-1"]'; seatset model opencode:prov/mod-1
  cat > "$STUB/opencode" <<'EOF'
#!/usr/bin/env bash
[ "$1" != --version ] || { cat "$STUB/oc-version" 2>/dev/null || echo 1.19.5; exit 0; }
[ "$1" != models ] || { echo prov/mod-1; exit 0; }
cat > "$STUB/oc-brief"; { echo "$*"; pwd; } > "$STUB/oc-run"
env | grep -E '^(OPENCODE_CONFIG|OPENCODE_DISABLE_PROJECT_CONFIG|CONVEYOR_GUARD_SETTINGS|CLAUDE_PROJECT_DIR)=' | sort > "$STUB/oc-env"
cp "$OPENCODE_CONFIG" "$STUB/oc-config"; . "$STUB/oc-cmd"
EOF
  chmod +x "$STUB/opencode"
}

# Bugs: an OpenCode model is run on Claude Code, or OpenCode runs outside the worktree, on another model, without the
# card's prompt, or without the guard plugin and the card's settings; its events leave the live record empty (no
# turns, no action, no usage) or are read as a Claude stream; its line has no tokens, usage or cost, or names an
# effort OpenCode was never given; the Board prices it at nothing or at a list price, not at OpenCode's cost.
t_opencodebuild() {
  ocsetup
  # Two calls of the model: the first runs a command and holds until the case has read the live record ($STUB/go).
  cat > "$STUB/oc-cmd" <<'EOF'
echo '{"type":"step_start","timestamp":1,"sessionID":"s1","part":{"type":"step-start"}}'
echo '{"type":"tool_use","timestamp":2,"sessionID":"s1","part":{"type":"tool","tool":"bash","state":{"status":"completed","input":{"command":"echo two >> a.txt"}}}}'
echo two >> a.txt
echo '{"type":"step_finish","timestamp":3,"sessionID":"s1","part":{"type":"step-finish","cost":0.02,"tokens":{"input":100,"output":20,"reasoning":5,"cache":{"read":1000,"write":50}}}}'
for i in $(seq 1200); do [ -e "$STUB/go" ] && break; sleep 0.1; done # sleep: the session holds until the case has read its live record
echo '{"type":"text","timestamp":4,"sessionID":"s1","part":{"type":"text","text":"done"}}'
echo '{"type":"step_finish","timestamp":5,"sessionID":"s1","part":{"type":"step-finish","cost":0.005,"tokens":{"input":10,"output":3,"reasoning":0,"cache":{"read":1100,"write":0}}}}'
EOF
  loop run > "$STUB/log" 2>&1 & run=$!
  wait_until "jq -e '.turns == 1' '$T/$CASE'/cards/*.live" || { : > "$STUB/go"; wait $run; fail "the live record never counted the first call: $(cat "$STUB/log")"; }
  live=$(jq -c '{step, model, turns, action, usage, last: (.last | type)}' "$T/$CASE"/cards/*.live)
  : > "$STUB/go"; wait $run || fail "run exited non-zero: $(cat "$STUB/log")"
  c=$(st 'select(.step == "picked") | .card'); wt=$T/$CASE/cards/$c
  [ "$live" = '{"step":"build","model":"opencode:prov/mod-1","turns":1,"action":"bash: echo two >> a.txt","usage":{"input":100,"write":50,"write1h":0,"read":1000,"output":25,"cost":0.02},"last":"string"}' ] \
    || fail "the live record of the OpenCode build: $live"
  [ "$(head -n 1 "$STUB/oc-run")" = 'run --model prov/mod-1 --format json --auto' ] && [ "$(sed -n 2p "$STUB/oc-run")" = "$wt" ] \
    || fail "OpenCode was not run on the model in the worktree: $(cat "$STUB/oc-run")"
  head -n 1 "$STUB/oc-brief" | grep -qF "Conveyor card $c." && grep -qF 'body of 7' "$STUB/oc-brief" || fail "OpenCode was not given the card's prompt: $(head -c 300 "$STUB/oc-brief")"
  [ "$(cat "$STUB/oc-env")" = "$(printf '%s\n' "CLAUDE_PROJECT_DIR=$wt" "CONVEYOR_GUARD_SETTINGS=$wt.settings" "OPENCODE_CONFIG=$wt.opencode.json" OPENCODE_DISABLE_PROJECT_CONFIG=1)" ] \
    && [ "$(jq -c .plugin "$STUB/oc-config")" = "[\"file://$SRC/opencode/guard.mjs\"]" ] || fail "OpenCode was not given the guard plugin and the card's settings: $(cat "$STUB/oc-env" "$STUB/oc-config")"
  [ "$(st 'select(.step == "build") | [.model, .effort, .tokens.claude, .usage, .stats.turns, .stats.tools] | tojson')" \
    = '["opencode:prov/mod-1",null,188,{"input":110,"write":50,"write1h":0,"read":2100,"output":28,"cost":0.025},2,{"bash":1}]' ] \
    || fail "the build line: $(st 'select(.step == "build")')"
  [ ! -e "$STUB/sessions" ] || fail "Claude Code ran for an OpenCode model: $(cat "$STUB/sessions")"
  [ "$(st 'select(.step == "landed") | .issue')" = 7 ] || fail "the card did not land: $(st '"\(.step) \(.reason)"')"
  # The Rules panel names no effort for the OpenCode builder (it is given none), not the seed's medium. One snapshot
  # serves this check and the price check below: each fresh one is made from the whole card records.
  snap=$(loop snapshot --fresh)
  [ "$(jq -c '.modelSettings.builder | [.model, .effort, .agent, .efforts]' <<<"$snap")" = '["opencode:prov/mod-1",null,"opencode",[]]' ] \
    || fail "the Board's builder settings name an effort OpenCode is not given: $(jq -c .modelSettings.builder <<<"$snap")"
  # The OpenCode builder takes no effort, though an OpenCode reviewer takes one (its --variant, models.test.sh).
  out=$(loop control model opencode prov/mod-1 high 2>&1); [ $? = 2 ] && grep -qF 'opencode takes no effort high (it takes none: name the model alone)' <<<"$out" \
    || fail "the OpenCode builder was given an effort: $out"
  # The Board prices the step at the dollars OpenCode reported.
  [ "$(jq -c --arg c "$c" '.metrics.cards[] | select(.card == $c) | [.metrics.timeline[] | select(.step == "build") | .usd]' <<<"$snap")" = '[0.025]' ] \
    || fail "the build is not priced at OpenCode's cost: $(jq -c --arg c "$c" '.metrics.cards[] | select(.card == $c) | .metrics.timeline' <<<"$snap")"
}

# Bugs: an OpenCode build that `control stop` ends is read as a Claude stream, so what it used so far (its tokens,
# usage and cost) is lost from the records.
t_opencodestop() {
  ocsetup; tune '.tunables.idle = 1 | .tunables.poll = 1'
  printf '%s\n' 'echo "{\"type\":\"step_finish\",\"part\":{\"cost\":0.03,\"tokens\":{\"input\":700,\"output\":5,\"reasoning\":0,\"cache\":{\"read\":0,\"write\":0}}}}"' \
    'sleep 60 & : > "$STUB/building"; wait' > "$STUB/oc-cmd" # sleep: the build's child, there to be stopped with it
  ( export CONVEYOR_MAIN=$R CONVEYOR_CARDS=$T/$CASE/cards
    exec timeout 120 bash "$SRC/conveyor.sh" serve > "$STUB/serve.out" 2>&1 ) & pid=$!; trap 'kill $pid 2>/dev/null' EXIT
  wait_until "[ -e '$STUB/building' ]" || fail "serve did not start #7: $(cat "$STUB/serve.out")"
  card=$(st 'select(.issue == 7 and .step == "picked") | .card'); loop control stop >/dev/null
  wait_until "[ -z \"\$(st 'select(.issue == 7) | .card')\" ]" || fail "stop did not end the card: $(cat "$STUB/serve.out")"
  [ "$(jq -c --arg c "$card" 'select(.card == $c and .step == "build") | [.result, .model, .tokens.claude, .usage]' "$ST/retried.jsonl")" \
    = '["stopped","opencode:prov/mod-1",705,{"input":700,"write":0,"write1h":0,"read":0,"output":5,"cost":0.03}]' ] \
    || fail "the stopped OpenCode build's spend is not recorded: $(jq -c --arg c "$card" 'select(.card == $c)' "$ST/retried.jsonl")"
  kill $pid 2>/dev/null; wait $pid 2>/dev/null; trap - EXIT
}

# Bugs: a command the Bash guardrails refuse runs in an OpenCode session, or is refused without the guard's message; a
# command they rewrite (an unbounded search) runs as written; a command they allow is refused; a tool with no Claude
# guard (a subagent) is let through; apply_patch, the file tool GPT models get, is refused outright, or a file of it
# goes unscreened. The stub loads the plugin as OpenCode does, from the config file the engine
# wrote, and calls its tool.execute.before hook. The session changes nothing, so its card ends after the build: the
# hook's answers are all the case reads, and a landing would add its time and prove no more. The case runs the loop
# because t_opencodeguardrules calls guard.sh directly with settings it writes itself: only a run shows the plugin as
# the engine wires it for a session (the config file, its settings and the session's environment) screens the calls.
t_opencodeguard() {
  command -v node >/dev/null || fail "node is needed to load the guard plugin as OpenCode would"
  ocsetup
  cat > "$STUB/oc-cmd" <<'EOF'
p=$(jq -r '.plugin[0]' "$OPENCODE_CONFIG"); p=${p#file://}
node --input-type=module -e '
const h = await (await import(process.argv[1])).default.server({ directory: process.cwd(), worktree: process.cwd() })
const patch = (f, body) => ({ patchText: "*** Begin Patch\n*** Update File: " + f + "\n@@\n-one\n+" + body + "\n*** End Patch" })
const calls = [["bash", { command: "node --test a.test.js" }], ["bash", { command: "rg two" }], ["bash", { command: "cat a.txt" }], ["task", { prompt: "x" }],
  ["apply_patch", patch("a.txt", "three")],
  ["apply_patch", { patchText: "*** Begin Patch\n*** Add File: b.txt\n+x\n*** Add File: package.json\n+{\"dependencies\": {\"leftpad\": \"1.0.0\"}}\n*** End Patch" }],
  ["apply_patch", { patchText: "*** Update File: package.json\n@@\n+x" }]]
for (const [tool, args] of calls) {
  const out = { args }
  try { await h["tool.execute.before"]({ tool, sessionID: "s1", callID: "c1" }, out); console.log("allowed " + tool + ": " + (out.args.command ?? out.args.patchText.split("\n")[1])) }
  catch (e) { console.log("refused " + tool + ": " + e.message.split("\n")[0]) }
}' "$p" > "$STUB/oc-guard" 2>&1
echo '{"type":"step_finish","timestamp":1,"sessionID":"s1","part":{"type":"step-finish","cost":0.01,"tokens":{"input":1,"output":1,"reasoning":0,"cache":{"read":0,"write":0}}}}'
EOF
  out=$(loop run 2>&1) || fail "run exited non-zero: $out"
  g=$(cat "$STUB/oc-guard")
  grep -qx 'refused bash: BLOCKED: bare node --test without --max-old-space-size=4096, or with a larger heap flag beside it. Use the npm script (npm run test:unit / test:guards) or add the flag and drop any larger one. .claude/rules/tests.md, Heap cap.' <<<"$g" \
    || fail "an uncapped test run was not refused with the guard's message: $g"
  c=$(st 'select(.step == "picked") | .card')
  grep -qxF "allowed bash: ( set -o pipefail; { 'rg' 'two' '$T/$CASE/cards/$c'; } 2>&1 | { head -n 200; cat >/dev/null; } )" <<<"$g" \
    || fail "an unbounded search was not run as the guard rewrote it: $g"
  grep -qx 'allowed bash: cat a.txt' <<<"$g" && grep -q '^refused task: conveyor: the tool task is not one a card session may use' <<<"$g" \
    || fail "an allowed command was refused, or a subagent let through: $g"
  # apply_patch (GPT models' file tool) is screened file by file: an allowed edit runs; a patch whose second file adds
  # a dependency is refused with that guard's message; one with no Begin/End markers, whose files cannot be read, too.
  grep -qx 'allowed apply_patch: \*\*\* Update File: a.txt' <<<"$g" \
    && grep -qx "refused apply_patch: BLOCKED: adding a new dependency ('leftpad' in NEW file $T/$CASE/cards/$c/package.json) requires the owner's explicit approval first." <<<"$g" \
    && grep -q '^refused apply_patch: conveyor: this apply_patch call has no \*\*\* Begin Patch' <<<"$g" \
    || fail "apply_patch was not screened file by file: $g"
}

# guard.sh's refusals as Claude Code makes them. Bugs: a hook's JSON deny is read as an allow; a hook the settings
# mark blocking that crashes lets the call through, or the message does not name it; one not marked blocking that
# crashes refuses; a hook of another tool's matcher runs; a read the settings deny runs; with no settings file every
# call is allowed.
t_opencodeguardrules() {
  d=$T/$CASE; mkdir -p "$d/wt"
  printf '%s\n' '#!/usr/bin/env bash' 'echo "{\"hookSpecificOutput\":{\"permissionDecision\":\"deny\",\"permissionDecisionReason\":\"no edits to x\"}}"' > "$d/deny.sh"
  printf '%s\n' '#!/usr/bin/env bash' 'exit 1' > "$d/crash.sh"; chmod +x "$d/deny.sh" "$d/crash.sh"
  # Each command as cardsettings() writes the engine's: the folder in single quotes ($q), then the script.
  jq -n --arg d "$d" --arg q "'" '{permissions: {deny: ["Read(**/secret.txt)"]}, hooks: {PreToolUse: [
      {matcher: "Bash", hooks: [{type: "command", command: "\($q)\($d)\($q)/crash.sh", onFailure: "block"}]},
      {matcher: "Edit|Write", hooks: [{type: "command", command: "\($q)\($d)\($q)/deny.sh"}, {type: "command", command: "\($q)\($d)\($q)/crash.sh"}]},
      {matcher: "Read", hooks: [{type: "command", command: "\($q)\($d)\($q)/crash.sh"}]}]}}' > "$d/s.json"
  g() { jq -cn --arg t "$1" --argjson i "$2" '{tool_name: $t, tool_input: $i}' | CLAUDE_PROJECT_DIR=$d/wt bash "$SRC/opencode/guard.sh" "${3:-$d/s.json}" 2>&1; echo "rc=$?"; }
  [ "$(g Edit '{"file_path":"x"}')" = $'no edits to x\nrc=2' ] || fail "a JSON deny was not a refusal with its reason: $(g Edit '{"file_path":"x"}')"
  g Bash '{"command":"ls"}' | grep -qz "the guard crash.sh exited 1 and the card's settings mark its failure as blocking: the call is refused.*rc=2" \
    || fail "a blocking hook that crashed let the call through: $(g Bash '{"command":"ls"}')"
  [ "$(g Read '{"file_path":"a.txt"}')" = rc=0 ] || fail "a hook not marked blocking that crashed refused the call: $(g Read '{"file_path":"a.txt"}')"
  [ "$(g Read "{\"file_path\":\"$d/wt/sub/secret.txt\"}")" = "conveyor: the card's settings deny Read(**/secret.txt): $d/wt/sub/secret.txt is not to be read or written in a card session"$'\nrc=2' ] \
    || fail "a read the settings deny was not refused: $(g Read "{\"file_path\":\"$d/wt/sub/secret.txt\"}")"
  g Glob '{"pattern":"*"}' | grep -qx rc=0 || fail "a tool no hook matches was refused: $(g Glob '{"pattern":"*"}')"
  g Glob '{"pattern":"*"}' "$d/nosuch.json" | grep -qz 'cannot be read, so no guard can run on this call: it is refused.*rc=2' || fail "with no settings file a call was allowed"
}

# Bugs: an OpenCode build starts with the guard plugin missing and runs unguarded; the card is blocked without saying
# why. It runs the loop: a direct ocready() call shows the refusal text, but not that the loop starts no OpenCode
# session and records that text as the card's block reason.
t_opencodenoguard() {
  ocsetup; echo 'echo two >> a.txt' > "$STUB/oc-cmd"
  CONVEYOR_OPENCODE_GUARD=$T/$CASE/nosuch/guard.mjs loop run > "$STUB/log" 2>&1
  [ ! -e "$STUB/oc-run" ] || fail "OpenCode started with the guard plugin missing"
  st 'select(.step == "blocked") | .reason' | grep -qF "the OpenCode guard plugin $T/$CASE/nosuch/guard.mjs (or guard.sh beside it) is missing: an OpenCode session would run without the command guards, so it does not start" \
    || fail "the card was not blocked saying the plugin is missing: $(st 'select(.step == "blocked") | .reason')"
}

# Bugs: an OpenCode build starts with an OpenCode whose plugin API the plugin is not written for (OpenCode 2) and runs
# unguarded; the card is blocked without saying why. It runs the loop for the reason t_opencodenoguard does.
t_opencodenov2() {
  ocsetup; echo 'echo two >> a.txt' > "$STUB/oc-cmd"; echo 2.3.0 > "$STUB/oc-version"
  loop run > "$STUB/log" 2>&1
  [ ! -e "$STUB/oc-run" ] && st 'select(.step == "blocked") | .reason' | grep -qF 'OpenCode 2.3.0 is not 1.x' \
    || fail "an OpenCode of another plugin API started, or the block does not say why: $(st 'select(.step == "blocked") | .reason')"
}

# Bugs: with OpenCode models allowed, a Claude build is launched otherwise than before (its arguments, its settings,
# its effort), is given OpenCode's environment, or is run by OpenCode; its line is read as an OpenCode session's.
t_opencodeclaude() {
  ocsetup; seatset model m
  echo 'echo "${OPENCODE_CONFIG:-none} ${CONVEYOR_GUARD_SETTINGS:-none}" > "$STUB/claude-env"; echo two >> a.txt' > "$STUB/build"
  out=$(loop run 2>&1) || fail "run exited non-zero: $out"
  c=$(st 'select(.step == "picked") | .card')
  [ "$(cat "$STUB/sessions")" = "-p --model m --effort medium --permission-mode bypassPermissions --disallowedTools Agent --setting-sources  --strict-mcp-config --settings $T/$CASE/cards/$c.settings --output-format stream-json --verbose" ] \
    || fail "the Claude build was not launched as before: $(cat "$STUB/sessions")"
  [ "$(cat "$STUB/claude-env")" = 'none none' ] && [ ! -e "$STUB/oc-run" ] || fail "the Claude build was given OpenCode's environment, or OpenCode ran: $(cat "$STUB/claude-env")"
  [ "$(st 'select(.step == "build") | [.model, .effort, .tokens.claude, .usage] | tojson')" = '["m","medium",35,{"input":10,"write":20,"write1h":0,"read":999,"output":5}]' ] \
    || fail "the Claude build's line: $(st 'select(.step == "build")')"
  [ "$(st 'select(.step == "landed") | .issue')" = 7 ] || fail "the card did not land: $(st '"\(.step) \(.reason)"')"
}

# Bugs: Claude's weekly limit holds back a card whose builder is OpenCode (with a Codex reviewer, no Claude session
# runs); or, the other way, it stops holding back a Claude builder's card. The OpenCode session changes nothing, so
# its card ends after the build: that OpenCode ran is what shows the card was not held, and a landing would add its
# time and prove no more. The case runs the loop because a direct call of the guard check (lib/pick.sh) shows only
# its answer: whether the loop then writes no picked line, prints the pause, or goes on to launch OpenCode is decided
# by the run that reads the seat's builder and acts on that answer, which only a run shows.
t_opencodelimit() {
  ocsetup; echo 'echo "{\"type\":\"step_finish\",\"part\":{\"cost\":0.01,\"tokens\":{\"input\":1,\"output\":1}}}"' > "$STUB/oc-cmd"
  tune '.tunables.limitTtl = 0'; export CONVEYOR_LIMIT_CMD='echo "{\"seven_day\":{\"utilization\":95}}"'
  loop control guard 90 >/dev/null
  seatset model m; out=$(loop run 1 2>&1); grep -q 'paused by guard' <<<"$out" && [ -z "$(st 'select(.step == "picked") | .issue')" ] \
    || fail "a Claude builder's card was not held at the limit: $out"
  seatset model opencode:prov/mod-1; out=$(loop run 2>&1) || fail "run exited non-zero: $out"
  [ "$(st 'select(.step == "picked") | .issue')" = 7 ] && [ -e "$STUB/oc-run" ] || fail "Claude's limit held back the OpenCode builder's card: $out"
}
