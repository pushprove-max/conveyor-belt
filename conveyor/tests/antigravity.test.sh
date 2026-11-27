#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 300
# Engine cases: the builder seat on the Antigravity CLI (agy, lib/agy.sh): the seat set to it, its headless launch,
# its reader, its end at the step's time limit and doctor's check of its sign-in.
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"
# The engine folder, as lib.sh sets it: named here too, so the release closure (tools/closure.sh) follows this file's paths.
# shellcheck disable=SC2034 # the closure tool reads this line; the cases here do not use SRC
SRC=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)

# A stub `agy` on PATH ($STUB): `agy models` lists two models, as agy does (a slug, then its name); any other call
# keeps its arguments, one a line (agy-args), its folder (agy-dir) and what it was given on stdin (agy-in), then runs
# $STUB/agy-cmd, its output kept in agy-out too.
agysetup() { # <issues json>
  setup "$1"
  # stub: agy is not installed where the tests run, and a real one would call Google's API
  cat > "$STUB/agy" <<'EOF'
#!/usr/bin/env bash
set -o pipefail
[ "$1" != models ] || { printf '%s\n' 'gem-1                Gem 1' 'gem-2-high           Gem 2 (High)'; exit 0; }
printf '%s\n' "$@" > "$STUB/agy-args"; pwd > "$STUB/agy-dir"; cat > "$STUB/agy-in"
. "$STUB/agy-cmd" | tee "$STUB/agy-out"
EOF
  chmod +x "$STUB/agy"
}

# Bugs: antigravity cannot be set as the builder, or is set with an effort agy does not take, or as a seat no agy run
# serves yet, or offered for one in the Board's pickers; `conveyor.sh clis` does not list it, or its models (`agy models`), with agy installed; an agy build runs
# on Claude Code, outside the worktree, not headless, with no stream-JSON, without the card's prompt on stdin, its
# effort or a time limit; its answer is not read, by the Done-when check either (a reply with every D<n> line fails
# it, and costs a fix); its line has no tokens, usage or effort, or the seat's model in place of the one agy names.
# The guards: an agy session runs with no card guard (agy reads them from the worktree's .agents/hooks.json); a
# command, a file write or a tool the card's guards refuse runs; a command they rewrite runs as written, or is refused in place of
# being given back rewritten; one they
# allow is refused; a command can undo the hooks file. The stub runs the hook as agy does: the command the hooks file
# names, through a shell, each call on stdin as agy gives it ({toolCall: {name, args}}).
t_agybuild() {
  command -v node >/dev/null || fail "node is needed to run the guard hook as agy would"
  agysetup "[$(issue 7 2026-01-01 | jq -c '.body = "body of 7\n\n## Done when\n- a.txt has a second line"')]"; echo "$GO" > "$STUB/review.1"; tune '.tunables.buildTimeout = 900'
  out=$(loop control model antigravity gem-1 turbo 2>&1); [ $? = 2 ] && grep -qF 'antigravity takes no effort turbo (it takes low, medium, high, xhigh, max)' <<<"$out" \
    || fail "control model antigravity gem-1 turbo: the builder was given an effort agy does not take: $out"
  out=$(loop control reviewer antigravity gem-1 2>&1); [ $? = 2 ] && grep -qF 'antigravity runs only the builder seat' <<<"$out" \
    || fail "control reviewer antigravity gem-1: a seat no agy run serves was set: $out"
  loop control model antigravity gem-1 high >/dev/null 2>&1 || fail "control model antigravity gem-1 high failed with agy on PATH: $(loop control model antigravity gem-1 high 2>&1)"
  [ "$(jq -c .model "$ST/control.json")" = '{"cli":"antigravity","model":"gem-1","effort":"high"}' ] \
    || fail "control model antigravity gem-1 high did not set the builder seat: $(jq -c .model "$ST/control.json")"
  [ "$(loop clis | jq -c .antigravity)" = '["gem-1","gem-2-high"]' ] || fail "conveyor.sh clis does not list antigravity with the models agy lists: $(loop clis)"
  # The Board's seat pickers (modelsettings' clis): antigravity for the builder alone, as no other seat can be saved on it.
  fx_in 'modelsettings | jq -c "[.builder, .reviewer, .judge] | map(.clis | has(\"antigravity\"))"'
  [ "$(cat "$T/$CASE/run.out")" = '[true,false,false]' ] || fail "modelsettings: antigravity is not offered for the builder alone (builder, reviewer, judge): $(cat "$T/$CASE/run.out")"
  # The calls, one a line: the tool and its arguments, as agy names them.
  jq -cn '["run_command", {CommandLine: "node --test a.test.js", Cwd: "."}], ["run_command", {CommandLine: "rg two"}], ["run_command", {CommandLine: "cat a.txt"}],
    ["run_command", {CommandLine: "rm .agents/hooks.json"}], ["invoke_subagent", {Subagents: []}],
    ["write_to_file", {TargetFile: "package.json", CodeContent: "{\"dependencies\": {\"leftpad\": \"1.0.0\"}}"}],
    ["replace_file_content", {TargetFile: "a.txt", TargetContent: "one", ReplacementContent: "three"}]' > "$STUB/calls"
  cat > "$STUB/agy-cmd" <<'EOF'
cmd=$(jq -r '.["conveyor-card-guard"].PreToolUse[] | select(.matcher == "*") | .hooks[0].command' .agents/hooks.json)
while IFS= read -r c; do
  jq -c --arg d "$PWD" '{conversationId: "c1", workspacePaths: [$d], stepIdx: 1, toolCall: {name: .[0], args: .[1]}}' <<<"$c" \
    | bash -c "$cmd" > "$STUB/o" 2>/dev/null; printf '%s\t%s\n' "$(jq -r '.[0]' <<<"$c")" "$(cat "$STUB/o")" >> "$STUB/agy-guard"
done < "$STUB/calls"
echo '{"event":"init","conversation_id":"c1","init":{"cwd":".","tools":["run_command"],"permission_mode":"auto","model":"gem-1-0427"}}'
echo two >> a.txt
echo '{"event":"step_update","step_update":{"conversation_id":"c1","step_index":1,"state":"DONE","step_type":"tool","tool_name":"run_command"}}'
echo '{"event":"result","result":{"conversation_id":"c1","status":"SUCCESS","response":"Added the line.\n\n## Done when\nD1 met: a.txt:2 holds the line","num_turns":2,"usage":{"input_tokens":1000,"output_tokens":80,"thinking_tokens":30,"cache_read_tokens":600,"total_tokens":1080}}}'
EOF
  # loop: only a card run shows the seat set by `control model` reaching builder(), the guards' hooks file written before agy starts, the Done-when check reading agy's reply and the step's line written from agy's output
  out=$(loop run 2>&1) || fail "run exited non-zero: $out"
  c=$(st 'select(.step == "picked") | .card'); wt=$T/$CASE/cards/$c
  [ "$(paste -sd ' ' "$STUB/agy-args")" = "-p The task is in the message on stdin. --input-format stream-json --output-format stream-json --mode auto --print-timeout 900s --model gem-1 --effort high" ] \
    && [ "$(cat "$STUB/agy-dir")" = "$wt" ] || fail "agy was not run headless on the model and effort in the worktree with the step's time limit: $(cat "$STUB/agy-args" "$STUB/agy-dir")"
  p=$(jq -sr 'select(length == 1 and .[0].event == "user") | .[0].message.content' "$STUB/agy-in")
  head -n 1 <<<"$p" | grep -qF "Conveyor card $c." && grep -qF 'body of 7' <<<"$p" || fail "agy was not given the card's prompt as one stream-JSON message on stdin: $(head -c 300 "$STUB/agy-in")"
  # The model is the one agy's init names (gem-1-0427), not the seat's (gem-1).
  [ "$(st 'select(.step == "build") | [.model, .effort, .tokens.claude, .usage, .stats.turns, .stats.tools] | tojson')" \
    = '["gem-1-0427","high",480,{"input":400,"write":0,"write1h":0,"read":600,"output":80},2,{"run_command":1}]' ] \
    || fail "the build line does not hold agy's model, effort and tokens: $(st 'select(.step == "build")')"
  [ "$(st 'select(.step == "build") | .doneWhen | tojson')" = '{"items":1,"met":1,"failed":[]}' ] && [ -z "$(st 'select(.step == "fix") | .step')" ] \
    || fail "the Done-when check did not read agy's reply (its D1 line): $(st 'select(.step == "build" or .step == "fix")')"
  [ ! -e "$STUB/sessions" ] || fail "Claude Code ran for an antigravity builder: $(cat "$STUB/sessions")"
  [ "$(st 'select(.step == "landed") | .issue')" = 7 ] || fail "the card did not land: $(st '"\(.step) \(.reason)"')"
  # The guards, call by call: the input each was given, then the hook's answer.
  g=$(cat "$STUB/agy-guard")
  [ "$(grep -c '^run_command	$' <<<"$g")" = 1 ] || fail "the allowed command (cat a.txt) was refused, or more than one command was let through: $g"
  [ "$(grep -c '^replace_file_content	$' <<<"$g")" = 1 ] || fail "an allowed edit of a.txt was refused: $g"
  grep -qF 'run_command	{"decision":"deny","reason":"BLOCKED: bare node --test without --max-old-space-size=4096, or with a larger heap flag beside it. Use the npm script (npm run test:unit / test:guards) or add the flag and drop any larger one. .claude/rules/tests.md, Heap cap.' <<<"$g" \
    || fail "the call run_command {CommandLine: node --test a.test.js} was not refused with the guard's message: $g"
  # A rewrite is given back for agy to run (overwrite), never refused: a guard that counts a command's runs as it
  # rewrites it (test-changed.sh) would refuse the retry of a refused one as a second run.
  grep -qF "run_command	{\"decision\":\"allow\",\"overwrite\":{\"CommandLine\":\"( set -o pipefail; { 'rg' 'two' '$wt'; }" <<<"$g" \
    || fail "the call run_command {CommandLine: rg two} was let through unbounded, or not given back rewritten (overwrite): $g"
  grep -qxF 'run_command	{"decision":"deny","reason":"conveyor: this call names .agents/, which holds the card'"'"'s guard hook (.agents/hooks.json): refused"}' <<<"$g" \
    || fail "the call run_command {CommandLine: rm .agents/hooks.json} was let through: $g"
  grep -q '^invoke_subagent	{"decision":"deny","reason":"conveyor: the tool invoke_subagent is not one a card session may use' <<<"$g" \
    || fail "the call invoke_subagent {Subagents: []} was let through: $g"
  grep -qF "write_to_file	{\"decision\":\"deny\",\"reason\":\"BLOCKED: adding a new dependency ('leftpad' in NEW file $wt/package.json) requires the owner's explicit approval first." <<<"$g" \
    || fail "the call write_to_file {TargetFile: package.json, a new dependency} was not refused with the guard's message: $g"
  # The hooks file is never part of the change: git's exclude file names it.
  ! git -C "$R" show --stat --format= main | grep -q '\.agents' || fail "the change carries the agy hooks file: $(git -C "$R" show --stat --format= main)"
  # The answer: the response of agy's result, read as a session's last reply is (a question to the owner, a block).
  fx_in 'lastreply "$STUB/agy-out" whole'
  [ "$(cat "$T/$CASE/run.out")" = $'Added the line.\n\n## Done when\nD1 met: a.txt:2 holds the line' ] || fail "the answer of agy's output was not read: $(cat "$T/$CASE/run.out")"
}

# A build of #8 on an agy that never answers (print mode stalls on a tool call that asks for a permission), with the
# pack's tunables changed by the jq filter: session() runs as card() runs it, on a card worktree with its settings
# file, with no loop, and the card is blocked with its reason as card() blocks it.
agyhang() { # <jq filter of the pack>
  agysetup '[]'; loop control model antigravity gem-1 >/dev/null 2>&1 || fail "control model antigravity gem-1 failed"
  echo 'exec sleep 30' > "$STUB/agy-cmd" # sleep: an agy that never answers
  CARDS=$T/$CASE/cards; mkdir -p "$CARDS"; git -C "$R" worktree add -q --detach "$CARDS/c8-8" refs/heads/main || fail "no worktree"
  landed 8 | jq -c '.card = "c8-8" | .step = "picked"' >> "$ST/cards.jsonl"
  tuned "$1" fx_in 'w=$CARDS/c8-8; cd "$R" && began c8-8 8 build && cardsettings "$w.settings" || exit 1
    t=$(session "$w" "Build the issue.") || block c8-8 8 "$w" "build: $t"; echo "step: $?"'
}

# Bugs: an agy session that never answers hangs the card, or ends with a reason that does not say agy ran to its time
# limit; with the stuck limit under the step's time limit (as the pack's defaults are), the stall check ends it twice
# before that limit ("stalled twice"); a seat with no effort gives agy an --effort all the same.
t_agytimeout() {
  start=$SECONDS; agyhang '.tunables.buildTimeout = 3 | .tunables.stuck = 1 | .tunables.reviewPause = 1'
  [ $((SECONDS - start)) -lt 25 ] || fail "the agy session that never answers was not ended at its 3s time limit"
  grep -qx -- '--print-timeout' "$STUB/agy-args" && grep -qx 3s "$STUB/agy-args" || fail "agy was not given the step's time limit: $(cat "$STUB/agy-args")"
  ! grep -qx -- '--effort' "$STUB/agy-args" || fail "control model antigravity gem-1 (no effort): agy was given an --effort: $(cat "$STUB/agy-args")"
  st 'select(.issue == 8 and .step == "blocked") | .reason' | grep -q '^build: agy ended at the step time limit, buildTimeout (3s), with no answer (exit 124, the 3s timeout)' \
    || fail "the agy session that never answered (stuck 1s, buildTimeout 3s) is not blocked at its time limit with a reason that names agy: $(st 'select(.issue == 8 and .step == "blocked") | .reason') $(cat "$T/$CASE/run.out")"
}

# Bugs: agy's sign-in check does not ask agy headless, or with no sign-in does not fail and say the command that
# signs in; a Gemini API key set up as agy reads it is not taken as a sign-in; modelProvider gemini with no key is
# not missing, or gives no command.
t_agysignin() {
  agysetup '[]'
  printf '%s\n' 'echo "Error: authentication required: sign in with an interactive agy session first" >&2' 'exit 1' > "$STUB/agy-cmd"
  fx_in 'agysignin; echo "rc=$?"'
  grep -qF 'missing: a sign-in for antigravity (agy): it has no cached credentials and no Gemini API key; fix: run agy in a terminal and sign in' "$T/$CASE/run.out" \
    && grep -qx 'rc=1' "$T/$CASE/run.out" || fail "agysignin with agy signed out is not missing with the command that signs in: $(cat "$T/$CASE/run.out")"
  [ "$(paste -sd ' ' "$STUB/agy-args")" = '-p Reply with the one word OK. --output-format json --print-timeout 50s' ] || fail "agysignin did not ask agy headless: $(cat "$STUB/agy-args")"
  rm -f "$STUB/agy-args"; mkdir -p "$T/$CASE/home/.gemini/antigravity-cli"; echo '{"modelProvider": "gemini"}' > "$T/$CASE/home/.gemini/antigravity-cli/settings.json"
  fx_in 'HOME=$T/$CASE/home GEMINI_API_KEY=k agysignin; HOME=$T/$CASE/home GEMINI_API_KEY= agysignin; echo "rc=$?"'
  grep -q '^ok: antigravity (agy), signed in with the Gemini API key' "$T/$CASE/run.out" && [ ! -e "$STUB/agy-args" ] \
    || fail "agysignin with GEMINI_API_KEY=k and modelProvider gemini: the key is not taken as agy's sign-in: $(cat "$T/$CASE/run.out")"
  grep -qF 'missing: a Gemini API key for antigravity (agy): modelProvider is gemini in '"$T/$CASE"'/home/.gemini/antigravity-cli/settings.json, and GEMINI_API_KEY is not set; fix: export GEMINI_API_KEY=<your Gemini API key>' "$T/$CASE/run.out" \
    && grep -qx 'rc=1' "$T/$CASE/run.out" || fail "agysignin with no GEMINI_API_KEY and modelProvider gemini is not missing with the command that sets the key: $(cat "$T/$CASE/run.out")"
}

# Bugs: doctor passes with agy signed out and the builder on antigravity, or does not name the command that signs in;
# an agy signed out fails doctor (so setup offers no start) on a project whose seats do not use it. doctordone: the
# sample set up, on which doctor passes with no other fault, so its exit is the agy check's.
t_agydoctor() {
  local X out b=$T/$CASE/agybin; doctordone
  # stub: agy is not installed where the tests run; this one lists one model and is signed out, as its headless call finds it
  mkdir -p "$b" && printf '%s\n' '#!/bin/sh' '[ "$1" != models ] || { echo "gem-1  Gem 1"; exit 0; }' \
    'echo "Error: authentication required: sign in with an interactive agy session first" >&2; exit 1' > "$b/agy" && chmod +x "$b/agy" || fail "the agy stub was not made"
  # HOME: the case's own, so no agy settings file of the machine's (~/.gemini) is read.
  out=$(cd "$S" && HOME=$T/$CASE/home PATH=$b:$PATH bash "$X" doctor 2>&1) || fail "doctor failed with agy signed out and no seat on antigravity: $out"
  grep -qF 'warning: no seat runs on antigravity now, so agy needs no sign-in yet: a sign-in for antigravity (agy)' <<<"$out" \
    || fail "doctor with agy signed out and no seat on antigravity did not warn: $out"
  (cd "$S" && CONVEYOR_MAIN=$S PATH=$b:$PATH bash "$X" control model antigravity gem-1 >/dev/null 2>&1) || fail "control model antigravity gem-1 failed"
  out=$(cd "$S" && HOME=$T/$CASE/home PATH=$b:$PATH bash "$X" doctor 2>&1) && fail "doctor passed with agy signed out and the builder on antigravity: $out"
  grep -qF 'missing: a sign-in for antigravity (agy): it has no cached credentials and no Gemini API key; fix: run agy in a terminal and sign in' <<<"$out" \
    || fail "doctor with agy signed out and the builder on antigravity does not name the command that signs in: $out"
}

# Bug: a card blocked on an unknown agy model is never put back once the operator sets a model agy has: the check
# that it can start again (startcheck()) never asks agy.
t_agystartcheck() {
  agysetup '[]'; echo 'echo OK' > "$STUB/agy-cmd"
  fx_in 'startcheck "{\"seat\": \"builder\", \"cli\": \"antigravity\", \"model\": \"gem-2\", \"account\": \"\"}"; echo "rc=$?"'
  grep -qx 'rc=0' "$T/$CASE/run.out" && [ "$(paste -sd ' ' "$STUB/agy-args")" = '-p Reply with the one word OK. --model gem-2 --print-timeout 110s' ] \
    || fail "startcheck {cli: antigravity, model: gem-2} did not ask agy on that model: $(cat "$T/$CASE/run.out" "$STUB/agy-args" 2>&1)"
}
