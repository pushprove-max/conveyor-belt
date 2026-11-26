#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 300
# Engine cases: a Claude build whose output holds no token usage.
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"

# One card of issue 10, its build on the default login, whose folder is the loop's own $HOME/.claude here: the build's
# output names its session and holds no usage (its result has none). With <transcript>, the stub writes that file as
# Claude Code's transcript of the session, in the projects folder of the worktree it runs in. No push, and no test
# run (no test is linked).
TSID=0b7c2a4e-1f3d-4c5b-9a8e-6d2f1e3c4b5a
tsrun() { # [transcript]
  setup "[$(issue 10 2026-01-04)]"
  jq -c '.rules.push = false' "$ST/control.json" > "$STUB/c.new" && mv "$STUB/c.new" "$ST/control.json" || fail "the control record"
  echo "$GO" > "$STUB/review.1"
  [ -z "${1:-}" ] || printf '%s\n' "$1" > "$STUB/transcript"
  cat > "$STUB/claude" <<EOF
#!/usr/bin/env bash
[ "\${1:-}" != --version ] || { echo '2.1.322 (Claude Code)'; exit 0; }
cat > /dev/null; echo four >> b.txt
if [ -e "$STUB/transcript" ]; then
  d=\$HOME/.claude/projects/\$(pwd -P | sed 's/[^A-Za-z0-9]/-/g'); mkdir -p "\$d" && cp "$STUB/transcript" "\$d/$TSID.jsonl"
fi
echo '{"type":"system","subtype":"init","session_id":"$TSID","model":"m"}'
echo '{"type":"result","subtype":"success","is_error":false,"session_id":"$TSID","result":"done","num_turns":2}'
EOF
  mkdir -p "$T/$CASE/home"
  HOME=$T/$CASE/home loop run --only 10 > /dev/null 2> "$STUB/run.err" || fail "run of #10 exited non-zero: $(cat "$STUB/run.err")"
  [ -n "$(st 'select(.issue == 10 and .step == "landed") | .sha')" ] || fail "#10 did not land: $(st 'select(.issue == 10)')"
  card=$(st 'select(.issue == 10 and .step == "build") | .card')
}
tsbuild() { loop snapshot | jq -c '.landed[] | select(.issue == 10) | .metrics.timeline[] | select(.step == "build")'; }

# Bug (issue 452): a Claude build whose output held no usage was left unpriced, while Claude's own transcript of the
# session held every answer's usage. The step is recorded with the transcript's totals, each answer counted once
# (msg_1 has two events, the last one whole: counted twice, input would be 8 and output 101), and priced on the Board.
t_transcript() {
  tsrun "$(jq -cn --arg s "$TSID" '
    {type: "user", sessionId: $s, message: {role: "user", content: "the brief"}},
    {type: "assistant", sessionId: $s, message: {id: "msg_1", model: "claude-sonnet-5-5", usage: {input_tokens: 3, cache_creation_input_tokens: 100, cache_read_input_tokens: 0, output_tokens: 1}}},
    {type: "assistant", sessionId: $s, message: {id: "msg_1", model: "claude-sonnet-5-5", usage: {input_tokens: 3, cache_creation_input_tokens: 100, cache_read_input_tokens: 0, output_tokens: 40}}},
    {type: "assistant", sessionId: $s, message: {id: "msg_2", model: "claude-sonnet-5-5", usage: {input_tokens: 2, cache_creation_input_tokens: 50, cache_read_input_tokens: 100, output_tokens: 60}}}')"
  [ "$(st 'select(.issue == 10 and .step == "build") | [.model, .usage, .tokens.claude, .stats.models, has("unread")]' | jq -c .)" \
    = '["m",{"input":5,"write":150,"write1h":0,"read":100,"output":100},255,["claude-sonnet-5-5"],false]' ] \
    || fail "the build line does not hold the transcript's totals: $(st 'select(.issue == 10 and .step == "build")')"
  # Bug (E1): transcribed() dropped cacheFirst, so a build priced from its transcript had no record of its first answer's cache.
  [ "$(st 'select(.issue == 10 and .step == "build") | .cacheFirst' | jq -c .)" = '{"read":0,"write":100}' ] \
    || fail "the build line does not hold the transcript's first answer cache (cacheFirst): $(st 'select(.issue == 10 and .step == "build")')"
  [ "$(tsbuild | jq -c '[(.usd | type == "number" and . > 0), .unpriced]')" = '[true,null]' ] || fail "the build is not priced on the Board: $(tsbuild)"
  [ ! -e "$ST/kept/$card/$card.build.out" ] || fail "the output of a build priced from its transcript was kept"
}

# Bug (issue 452): a build with no usage in its output or a transcript is unpriced, and its output, removed as the card
# lands, was the only place its cause could be read. It is kept beside the card's kept work, and the Board says why
# the step has no price.
t_transcriptnone() {
  tsrun
  [ "$(st 'select(.issue == 10 and .step == "build") | [has("usage"), .unread] | tostring')" = '[false,"the session output holds no token usage"]' ] \
    || fail "the build line does not say its usage could not be read: $(st 'select(.issue == 10 and .step == "build")')"
  [ ! -e "$T/$CASE/cards/$card.out" ] && grep -q "\"session_id\":\"$TSID\"" "$ST/kept/$card/$card.build.out" \
    || fail "the build's output was not kept beside the card's kept work: $(ls -R "$ST/kept" 2>&1)"
  [ "$(tsbuild | jq -c '[.usd, .unpriced]')" = '[null,"its token usage could not be read: the session output holds no token usage"]' ] \
    || fail "the Board does not list the build as unpriced with its reason: $(tsbuild)"
}

# Card c1-7's build stopped by `control stop` (stopped(), called as the loop calls it) when its output holds only the
# init event, naming its session. With <transcript>, Claude Code's transcript of that session is in the default
# login's projects folder ($HOME/.claude, here $T/$CASE/home) for the card's worktree. With <account>, the card's
# worktree line names that account, the host file gives it the folder $T/$CASE/acct, and the transcript is there.
stoprun() { # [transcript] [account]
  local w=$T/$CASE/cards/c1-7 d=$T/$CASE/home/.claude
  setup '[]'; mkdir -p "$w" "$T/$CASE/home" || fail "the card's worktree"
  if [ -n "${2:-}" ]; then
    d=$T/$CASE/acct; mkdir -p "$XDG_CONFIG_HOME/conveyor" && jq -n --arg n "$2" --arg d "$d" '{accounts: [{name: $n, configDir: $d}]}' > "$XDG_CONFIG_HOME/conveyor/host.json" || fail "the host file"
    jq -cn --arg a "$2" '{card: "c1-7", issue: 7, time: "2026-11-01T00:00:00Z", tokens: {claude: 0, codex: 0}, sha: "", reason: "", step: "worktree", result: "ok", account: $a}' >> "$ST/cards.jsonl"
  fi
  jq -cn '{card: "c1-7", issue: 7, time: "2026-11-01T00:00:00Z", tokens: {claude: 0, codex: 0}, sha: "", reason: "", step: "start", result: "", of: "build"}' >> "$ST/cards.jsonl"
  echo "{\"type\":\"system\",\"subtype\":\"init\",\"session_id\":\"$TSID\",\"model\":\"m\"}" > "$w.out"
  if [ -n "${1:-}" ]; then d=$d/projects/$(cd "$w" && pwd -P | sed 's/[^A-Za-z0-9]/-/g'); mkdir -p "$d" && printf '%s\n' "$1" > "$d/$TSID.jsonl" || fail "the transcript"; fi
  HOME=$T/$CASE/home fx_in 'stopped c1-7 7'; [ "$RC" = 0 ] || fail "stopped() exited $RC: $(cat "$T/$CASE/run.out")"
}

# R117. Bug it catches: a Claude build that `control stop` ended after its init event and before its first usage
# event had a stopped line with no usage, as stopped() read only its output, not the session's transcript, as a
# session's own line does (transcribed()). The stopped line holds the transcript's usage.
t_transcriptstop() {
  stoprun "$(jq -cn --arg s "$TSID" '{type: "assistant", sessionId: $s, message: {id: "msg_1", model: "claude-sonnet-5-5", usage: {input_tokens: 3, cache_creation_input_tokens: 100, cache_read_input_tokens: 0, output_tokens: 40}}}')"
  [ "$(st 'select(.step == "build") | [.result, .usage, has("unread")]' | jq -c .)" = '["stopped",{"input":3,"write":100,"write1h":0,"read":0,"output":40},false]' ] \
    || fail "the stopped build's line does not hold the transcript's usage: $(st 'select(.step == "build")')"
  [ ! -e "$ST/kept/c1-7/c1-7.build.out" ] || fail "the output of a stopped build priced from its transcript was kept"
}

# Bug it catches: stopped() looked for the transcript of a card started on a named account (`control account`) under
# the loop's own account, the default login, as the loop that calls it never takes the card's: the stopped line had
# no usage. The transcript is read from the folder of the account the card's worktree line names.
t_transcriptstopacct() {
  stoprun "$(jq -cn --arg s "$TSID" '{type: "assistant", sessionId: $s, message: {id: "msg_1", model: "claude-sonnet-5-5", usage: {input_tokens: 3, cache_creation_input_tokens: 100, cache_read_input_tokens: 0, output_tokens: 40}}}')" second
  [ "$(st 'select(.step == "build") | [.result, .usage.output]' | jq -c .)" = '["stopped",40]' ] \
    || fail "the stopped build of a card on the account 'second' does not hold its transcript's usage: $(st 'select(.step == "build")')"
}

# R117. Bug it catches: a stopped build with no usage in its output or a transcript lost its output as the card was
# cleaned up, as stopped() wrote its line with no outkeep(), as a session's line has: the output is kept beside the
# card's kept work, so the cause can be read.
t_transcriptstopnone() {
  stoprun
  [ "$(st 'select(.step == "build") | [.result, has("usage")]' | jq -c .)" = '["stopped",false]' ] || fail "the stopped build's line: $(st 'select(.step == "build")')"
  grep -q "\"session_id\":\"$TSID\"" "$ST/kept/c1-7/c1-7.build.out" || fail "the stopped build's output was not kept beside the card's kept work: $(ls -R "$ST/kept" 2>&1)"
}
