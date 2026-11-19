#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 300
# Engine cases: the models: a Claude reviewer, session settings and the proxy.
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"
# The engine folder, as lib.sh sets it: named here too, so the release closure (tools/closure.sh) follows this file's paths.
SRC=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)

# An engine function called alone in the engine shell, as `conveyor.sh <command>` loads it (the libraries
# commands/<command>.sh sources), with no loop run: a case about one function (the review, a session's route, doctor's
# route lines) pays for that function, not for a whole card around it.
modelsengine() { # <run|doctor|snapshot> <the engine command>
  mkdir -p "$T/$CASE/cards"
  # shellcheck source=/dev/null # the command's libraries, by its . lines or its SNAPLIBS list (commands/snapshot.sh)
  ( export CONVEYOR_MAIN=$R CONVEYOR_CARDS=$T/$CASE/cards; . "$SRC/conveyor.sh" state-dir > /dev/null \
    && eval "$(grep -e '^\. "\$HERE/lib/' -e '^SNAPLIBS=' "$SRC/commands/$1.sh")" \
    && for l in ${SNAPLIBS-}; do . "$HERE/lib/$l.sh" || exit 1; done && names && eval "$2" )
}
# The snapshot's modelSettings (what the Board's model choices show), as snapshot() makes it: the host's CLI report read
# when due (hostclis), then modelsettings(), with no whole snapshot around them.
msettings() { modelsengine snapshot 'hostclis due >/dev/null 2>&1; modelsettings'; }
# reviewed() alone, as a card's review step calls it, on a worktree of main (cards/c<n>) with the build's change
# staged: what it prints, then a last line of its exit and the verdict it left (rc=<exit> <verdict>).
rvcall() { # <n>
  modelsengine run "w=\$CARDS/c$1"' && git -C "$MAIN" worktree add -q --detach "$w" && echo two >> "$w/a.txt" && git -C "$w" add a.txt \
    && { reviewed "$w" "# Issue: body of the issue"; echo "rc=$? $(verdict "$w.review" 2>/dev/null)"; }'
}

# Bugs: a Claude model is refused as the reviewer, or one named with no CLI, or a Codex effort for it, is
# accepted; the Reviewer choices are not the five models, or its efforts not those of the program in force; a Claude
# reviewer still runs Codex, its GO or NO-GO is misread, its line lacks its model, usage or tokens.claude, or a
# failed one is left out of the cost; it is launched with a tool that writes or runs commands, with settings or
# hooks, without the staged change or AGENTS.md, or with AGENTS.md twice; a write that gets through is left in the
# worktree; health does not name it.
t_claudereview() {
  setup "[$(issue 7 2026-01-01)]"
  echo 'AGENTS-RULES-MARK' > "$R/AGENTS.md"; git -C "$R" add AGENTS.md; git -C "$R" commit -qm agents
  tune --slurpfile real "$SRC/lib/test-pack.json" '.models.allowed = $real[0].models.allowed | .models.allowed.claude += ["m"]'; seatset reviewer gpt-6.1-sol
  ctl() { loop control "$@" 2>&1; }
  rv() { msettings | jq -c '.reviewer | [.choices, .efforts]'; }
  [ "$(rv)" = '[["gpt-6.1-sol","gpt-6-astra","claude-opus-5-5","claude-sonnet-5-5","claude-fable-5-2"],["minimal","low","medium","high","xhigh"]]' ] \
    || fail "the Reviewer choices are not the five models, or a Codex reviewer's efforts are not Codex's: $(rv)"
  was=$(cat "$ST/control.json")
  for bad in 'reviewer claude-opus-5-5' 'reviewer claude claude-opus-5-5 minimal'; do
    # shellcheck disable=SC2086
    out=$(ctl $bad); [ $? = 2 ] && [ "$(cat "$ST/control.json")" = "$was" ] || fail "control $bad was not refused with nothing changed: $out"
  done
  [ "$(ctl reviewer claude claude-opus-5-5 max | jq -c .reviewer)" = '{"cli":"claude","model":"claude-opus-5-5","effort":"max"}' ] || fail "a Claude reviewer was not accepted"
  [ "$(rv | jq -c '.[1]')" = '["low","medium","high","xhigh","max"]' ] || fail "a Claude reviewer's efforts are not Claude's: $(rv)"
  [ "$(loop health | jq -c '[.models.codex, .efforts.codex]')" = '["claude-opus-5-5","max"]' ] || fail "health does not name the Claude reviewer: $(loop health)"
  claude_stub
  echo "$NOGO" > "$STUB/review.1"; echo "$GO" > "$STUB/review.2"
  loop run --only 7 >/dev/null || fail "run of #7 exited non-zero"
  [ ! -e "$STUB/codex-ran" ] || fail "a Claude reviewer ran Codex"
  [ "$(st 'select(.issue == 7 and .step == "review") | "\(.result) \(.counts.P1) \(.model) \(.effort)"' | tr '\n' ,)" = 'NO-GO 1 claude-opus-5-5 max,GO 0 claude-opus-5-5 max,' ] \
    && [ -n "$(st 'select(.issue == 7 and .step == "landed") | .sha')" ] || fail "a Claude reviewer's NO-GO and GO were not read: $(st 'select(.issue == 7)')"
  [ "$(st 'select(.issue == 7 and .step == "review") | [.tokens, .usage, .stats.turns] | tojson' | sort -u)" \
    = '[{"claude":157,"codex":0},{"input":100,"write":50,"write1h":0,"read":1000,"output":7},2]' ] || fail "a Claude review's line lacks tokens.claude or its usage: $(st 'select(.issue == 7 and .step == "review")')"
  # The write attempt changed nothing: after the last review the worktree holds the build's change alone.
  [ "$(cat "$STUB/status")" = 'M  a.txt' ] && ! grep -q pwned "$STUB/a" && ! git -C "$R" show HEAD --stat | grep -q z.txt \
    || fail "a review session changed the worktree: $(cat "$STUB/status") $(cat "$STUB/a")"
  [ "$(head -n 1 "$STUB/reviews")" = "$(sed -n 2p "$STUB/reviews")" ] || fail "the two reviews were launched differently"
  grep -q -- '-p --model claude-opus-5-5 --effort max --permission-mode default --tools Read,Grep,Glob --setting-sources  --strict-mcp-config' "$STUB/reviews" \
    && ! grep -q -- '--settings' "$STUB/reviews" || fail "the review session was given more than Read, Grep and Glob, or settings or hooks: $(head -n 1 "$STUB/reviews")"
  grep -q '^+two$' "$STUB/staged.1" || fail "the review session was not given the staged change: $(cat "$STUB/staged.1")"
  # The review after the fix reads that fix's diff, given in its own folder as the staged change is; the first is given none.
  [ ! -e "$STUB/fix.1" ] && grep -q '^+two$' "$STUB/fix.2" || fail "the review session after the fix was not given the fix's diff: $(cat "$STUB/fix.2" 2>&1)"
  [ "$(grep -c AGENTS-RULES-MARK "$STUB/asked.1")" = 1 ] && grep -q 'Proof: <proof>' "$STUB/asked.1" && grep -q 'body of 7' "$STUB/asked.1" \
    || fail "the review session was not given REVIEW, the brief and AGENTS.md once: $(cat "$STUB/asked.1")"
}

# The stubs of a Claude reviewer's cases: a build session as before; a review session (the one given --tools) answers
# review.N, and first does what a session that got a write through would do: it writes in the worktree, whatever it
# was launched with. Codex fails, and says it ran.
claude_stub() {
  cat > "$STUB/claude" <<'EOF'
#!/usr/bin/env bash
case " $* " in *" --tools "*) ;; *) cat > "$STUB/brief"; echo "$*" >> "$STUB/sessions"; . "$STUB/build"
  echo '{"type":"result","is_error":false,"usage":{"input_tokens":10,"cache_creation_input_tokens":20,"cache_read_input_tokens":999,"output_tokens":5}}'; exit 0 ;; esac
cat > "$STUB/asked"; printf '%s\n' "$*" >> "$STUB/reviews"; n=$(wc -l < "$STUB/reviews"); cp "$STUB/asked" "$STUB/asked.$n"
echo pwned > a.txt; echo pwned > z.txt
f=$(grep -o 'the file [^ ]*staged\.diff' "$STUB/asked" | cut -d' ' -f3); cp "$f" "$STUB/staged.$n" 2>/dev/null
f=$(grep -o 'are in the folder [^ ]*/rounds' "$STUB/asked" | cut -d' ' -f5); [ -z "$f" ] || cp "$f/1.diff" "$STUB/fix.$n"
[ ! -f "$STUB/review-bare" ] || { rm "$STUB/review-bare"; echo '{"type":"result","is_error":false,"result":"Review interrupted"}'; exit 0; }
[ ! -f "$STUB/review-part" ] || { rm "$STUB/review-part"; echo '{"type":"result","is_error":false,"result":"x","usage":{"input_tokens":100,"cache_creation_input_tokens":50,"cache_read_input_tokens":1000,"output_tokens":7}}'
  echo '{"type":"result","is_error":false,"result":"Review interrupted"}'; exit 0; }
echo '{"type":"assistant","message":{"id":"m1","model":"claude-opus-5-5","content":[{"type":"tool_use","id":"t1","name":"Read","input":{"file_path":"a.txt"}}],"usage":{"input_tokens":100,"cache_creation_input_tokens":50,"cache_read_input_tokens":1000,"output_tokens":7}}}'
[ -f "$STUB/review.$n" ] || exit 1
jq -cn --rawfile r "$STUB/review.$n" '{type: "result", is_error: false, result: $r, num_turns: 2,
  usage: {input_tokens: 100, cache_creation_input_tokens: 50, cache_read_input_tokens: 1000, output_tokens: 7},
  modelUsage: {"claude-opus-5-5": {inputTokens: 100, cacheCreationInputTokens: 50, cacheReadInputTokens: 1000, outputTokens: 7}}}'
[ ! -f "$STUB/review-exit" ] || exit 3
EOF
  # `codex debug models` (the host's report, read again before a seat starts: seatready()) is no review.
  printf '#!/usr/bin/env bash\n[ "${1:-}" != debug ] || exit 1\ntouch "$STUB/codex-ran"; exit 1\n' > "$STUB/codex"
  echo 'git status --porcelain > "$STUB/status"; cat a.txt > "$STUB/a"' > "$STUB/test-cmd"
}
# A Claude reviewer (claude-opus-5-5 at max, as t_claudereview sets it) on a main with the given issues and AGENTS.md,
# and its stubs: each review run after t_claudereview's is a case of its own, so they run side by side.
claude_reviewer() { # <issues json>
  setup "$1"
  echo 'AGENTS-RULES-MARK' > "$R/AGENTS.md"; git -C "$R" add AGENTS.md; git -C "$R" commit -qm agents
  tune --slurpfile real "$SRC/lib/test-pack.json" '.models.allowed = $real[0].models.allowed | .models.allowed.claude += ["m"]'; seatset reviewer gpt-6.1-sol
  [ "$(loop control reviewer claude claude-opus-5-5 max 2>&1 | jq -c .reviewer)" = '{"cli":"claude","model":"claude-opus-5-5","effort":"max"}' ] || fail "a Claude reviewer was not accepted"
  claude_stub
}
t_claudefail() {
  claude_reviewer "[$(issue 8 2026-01-02)]"
  # A review that fails is recorded with what it spent, under tokens.claude, never left out of the cost. It ended with
  # no verdict, so it ran once more before the card blocked; one that answered with a verdict and then failed did not.
  loop run --only 8 >/dev/null 2>&1
  [ "$(wc -l < "$STUB/reviews")" = 2 ] && st 'select(.issue == 8 and .step == "blocked") | .reason' | grep -q 'run again after 0s: review failed (exit 1)' \
    || fail "a Claude review that failed with no verdict was not run once more before the card blocked: $(st 'select(.issue == 8)')"
  # Both attempts are priced: the blocked line's tokens and the usage the dashboard prices hold the first's beside the second's.
  [ "$(st 'select(.issue == 8 and .step == "blocked") | [.spent.step, .spent.model, .spent.firstTry.spent.tokens.claude, .spent.tokens.claude, .tokens.claude,
      .spent.usage == {input: 200, write: 100, write1h: 0, read: 2000, output: 14}] | tojson')" = '["review","claude-opus-5-5",157,314,314,true]' ] \
    || fail "a failed Claude review left its cost out: $(st 'select(.issue == 8 and .step == "blocked")')"
}
# The three below call the review alone (rvcall): what a card does with its answer is t_claudereview's and t_claudefail's.
t_claudeexit() {
  claude_reviewer "[$(issue 9 2026-01-03)]"
  echo "$NOGO" > "$STUB/review.1"; : > "$STUB/review-exit"
  out=$(rvcall 9)
  [ "$(wc -l < "$STUB/reviews")" = 1 ] && [ "$(head -n 1 <<<"$out")" = 'review failed (exit 3)' ] && [ "$(tail -n 1 <<<"$out")" = 'rc=1 none' ] \
    || fail "a Claude review that gave its NO-GO and then exited non-zero was run again: $out"
}
t_claudebare() {
  claude_reviewer "[$(issue 10 2026-01-04)]"
  # An answer that ends cleanly with neither a verdict nor token usage is no verdict: it runs once more.
  echo "$GO" > "$STUB/review.2"; : > "$STUB/review-bare"
  out=$(rvcall 10)
  [ "$(wc -l < "$STUB/reviews")" = 2 ] && [ "$(head -n 1 <<<"$out" | jq -r .firstTry.reason)" = "review reported no token usage" ] && [ "$(tail -n 1 <<<"$out")" = 'rc=0 GO' ] \
    || fail "a Claude answer with no verdict and no usage was not run again: $out"
}
t_claudepart() {
  claude_reviewer "[$(issue 11 2026-01-05)]"
  # A first attempt whose usage is only part of what it used (one of its results holds none) leaves the step unpriced,
  # though the retry's usage is whole: merged, it would be priced under what it cost.
  echo "$GO" > "$STUB/review.2"; : > "$STUB/review-part"
  out=$(rvcall 11)
  [ "$(head -n 1 <<<"$out" | jq -c '[.tokens.claude, (.unread | test("1 of 2 results"))]')" = '[314,true]' ] && [ "$(tail -n 1 <<<"$out")" = 'rc=0 GO' ] \
    || fail "a retried review whose first attempt's usage was partial is priced as whole: $out"
}

# Bugs: an OpenCode model OpenCode lists is refused as the reviewer;
# its review runs Codex or Claude, outside the worktree, with a tool that writes or runs commands (or as the host's
# default agent, whose own permissions could allow them), with the worktree's
# own OpenCode config, without the staged change, or without its effort as the variant; a write that gets through
# is left in the worktree; its GO or NO-GO is misread, or an answer with no verdict is not run again; the tokens,
# usage and cost it reports are not on the review's line, or a retried review's cost (after no verdict, or a try the
# model API refused) is the last attempt's alone; its live record is read as a Codex review's, so it shows no turns,
# usage or action while it runs;
# with no opencode on the host the review fails without naming it.
# An OpenCode reviewer (prov/vendor/m-1 at high) on a main with issue 7, and its stubs.
opencode_reviewer() {
  setup "[$(issue 7 2026-01-01)]"
  # An OpenCode name listed under Codex is still OpenCode's; one with no provider, or a name of another shape listed
  # under OpenCode, is no OpenCode model.
  tune --slurpfile real "$SRC/lib/test-pack.json" '.models.allowed = $real[0].models.allowed | .models.allowed.claude += ["m"]
    | .models.allowed.codex += ["opencode:prov/vendor/m-1"] | .models.allowed.opencode = ["opencode:prov/vendor/m-1", "opencode:no-provider", "gpt-6.1-sol"]'
  ctl() { loop control "$@" 2>&1; }
  # The stub: it lists the one model it has registered (`opencode models`), keeps what it was asked and how it ran,
  # tries to write in the worktree, and answers review.N over two steps (a tool call, then the answer), each reporting
  # its usage as OpenCode does.
  cat > "$STUB/opencode" <<'EOF'
#!/usr/bin/env bash
[ "$1" != models ] || { echo prov/vendor/m-1; exit 0; }
cat > "$STUB/oc-asked"; printf '%s\n' "$*" >> "$STUB/oc-runs"; n=$(wc -l < "$STUB/oc-runs")
printf '%s\n' "$PWD" "$OPENCODE_CONFIG_CONTENT" "${OPENCODE_DISABLE_PROJECT_CONFIG:-}" > "$STUB/oc-env.$n"
f=$(grep -o 'the file [^ ]*staged\.diff' "$STUB/oc-asked" | cut -d' ' -f3); cp "$f" "$STUB/oc-staged.$n" 2>/dev/null
echo pwned > a.txt
step() { jq -cn --argjson c "$1" --argjson t "$2" '{type: "step_finish", timestamp: 1, sessionID: "s", part: {type: "step-finish", reason: "stop", cost: $c, tokens: $t}}'; }
echo '{"type":"step_start","timestamp":1,"sessionID":"s","part":{"type":"step-start"}}'
echo '{"type":"text","timestamp":1,"sessionID":"s","part":{"type":"text","text":"I read the change first."}}'
echo '{"type":"tool_use","timestamp":1,"sessionID":"s","part":{"type":"tool","tool":"read","state":{"status":"completed"}}}'
step 0.25 '{"input":100,"output":5,"reasoning":3,"cache":{"read":1000,"write":50}}'
# sleep: the first review holds after its first step until the case has read its live record.
[ "$n" != 1 ] || for i in $(seq 1200); do [ -e "$STUB/go" ] && break; sleep 0.1; done
[ ! -e "$STUB/refuse-api" ] || { rm "$STUB/refuse-api"; echo 'API Error: 429 Too Many Requests' >&2; exit 1; }
echo '{"type":"step_start","timestamp":2,"sessionID":"s","part":{"type":"step-start"}}'
[ -f "$STUB/review.$n" ] || exit 1
jq -cn --rawfile r "$STUB/review.$n" '{type: "text", timestamp: 2, sessionID: "s", part: {type: "text", text: $r}}'
step 0.5 '{"input":20,"output":7,"reasoning":0,"cache":{"read":500,"write":0}}'
EOF
  chmod +x "$STUB/opencode"; printf '#!/usr/bin/env bash\n[ "${1:-}" != debug ] || exit 1\ntouch "$STUB/codex-ran"; exit 1\n' > "$STUB/codex"
  # The model it lists is taken, as OpenCode names it (one it does not list is taken too: clis.test.sh, t_clisseat).
  [ "$(ctl reviewer opencode prov/vendor/m-1 high | jq -c .reviewer)" = '{"cli":"opencode","model":"prov/vendor/m-1","effort":"high"}' ] || fail "an OpenCode reviewer was not accepted"
}
t_opencodereview() {
  opencode_reviewer
  [ "$(msettings | jq -c '.reviewer | [.choices, .agent, .efforts]')" \
    = '[["gpt-6.1-sol","gpt-6-astra","claude-opus-5-5","claude-sonnet-5-5","claude-fable-5-2","opencode:prov/vendor/m-1"],"opencode",["minimal","low","medium","high","xhigh","max"]]' ] \
    || fail "the Reviewer choices do not list the OpenCode model once, run by OpenCode with its efforts: $(msettings | jq -c .reviewer)"
  echo 'git status --porcelain > "$STUB/status"; cat a.txt > "$STUB/a"' > "$STUB/test-cmd"
  # #7: a NO-GO, its finding sent to the fix, then a GO.
  echo "$NOGO" > "$STUB/review.1"; echo "$GO" > "$STUB/review.2"
  loop run --only 7 > "$STUB/log" 2>&1 & run=$!
  # Its live record, read as an OpenCode run's (not as a Codex review's, whose events these are not): the step it
  # finished is a turn with its usage and cost, and its tool call is the action.
  wait_until "jq -e '.step == \"review\" and .turns == 1' '$T/$CASE'/cards/*.live" || { : > "$STUB/go"; wait $run; fail "the live record never counted the OpenCode review's first step: $(cat "$T/$CASE"/cards/*.live 2>/dev/null)"; }
  live=$(jq -c '{model, turns, action, usage}' "$T/$CASE"/cards/*.live)
  : > "$STUB/go"; wait $run || fail "run of #7 exited non-zero: $(cat "$STUB/log")"
  [ "$live" = '{"model":"opencode:prov/vendor/m-1","turns":1,"action":"read","usage":{"input":100,"write":50,"write1h":0,"read":1000,"output":8,"cost":0.25}}' ] \
    || fail "the live record of an OpenCode review lost its turns, action or usage: $live"
  [ ! -e "$STUB/codex-ran" ] && ! grep -q -- '--tools' "$STUB/sessions" || fail "an OpenCode reviewer ran Codex or Claude"
  [ "$(st 'select(.issue == 7 and .step == "review") | "\(.result) \(.counts.P1) \(.model) \(.effort)"' | tr '\n' ,)" = 'NO-GO 1 opencode:prov/vendor/m-1 high,GO 0 opencode:prov/vendor/m-1 high,' ] \
    && grep -qxF 'E1 [P1] a.txt:1 wrong word' "$STUB/brief" && [ -n "$(st 'select(.issue == 7 and .step == "landed") | .sha')" ] \
    || fail "an OpenCode reviewer's NO-GO, its finding, and its GO were not read: $(st 'select(.issue == 7)')"
  # What it reports: input, cache writes and output (reasoning counted as output) as tokens; its cost, summed, in its
  # usage (usage.cost), where the Board prices an OpenCode step from: anywhere else the review is unpriced.
  [ "$(st 'select(.issue == 7 and .step == "review") | [.tokens, .usage, .cost, .stats] | tojson' | sort -u)" \
    = '[{"claude":0,"codex":185},{"input":120,"write":50,"read":1500,"output":15,"cost":0.75},null,{"turns":2,"tools":{"read":1}}]' ] \
    || fail "an OpenCode review's line lacks the tokens, usage or cost it reported: $(st 'select(.issue == 7 and .step == "review")')"
  [ "$(loop snapshot --fresh | jq -c '[.landed[] | select(.issue == 7) | .metrics.timeline[] | select(.step == "review") | [.usd, .unpriced]]')" = '[[0.75,null],[0.75,null]]' ] \
    || fail "the Board does not price the OpenCode reviews at the cost OpenCode reported: $(loop snapshot --fresh | jq -c '[.landed[] | select(.issue == 7) | .metrics.timeline]')"
  # Run in the worktree, read-only, on the model and the effort set, given the staged change; its write undone.
  wt=$T/$CASE/cards/$(st 'select(.issue == 7 and .step == "review") | .card' | head -n 1)
  [ "$(head -n 1 "$STUB/oc-runs")" = 'run --pure --format json --agent conveyor-readonly -m prov/vendor/m-1 --variant high' ] && [ "$(sed -n 1p "$STUB/oc-env.1")" = "$wt" ] \
    || fail "OpenCode was not run in the worktree on the model and effort set: $(head -n 1 "$STUB/oc-runs") in $(sed -n 1p "$STUB/oc-env.1")"
  # OpenCode takes the last rule that matches: the deny of everything comes first, the reads after it. It runs as its
  # own agent holding those permissions (named on its command line, above): the host's default agent, whose own
  # permissions would win over the global ones, is never the one that runs.
  sed -n 2p "$STUB/oc-env.1" | jq -e --arg rv "$wt.rv/**" '.permission as $p | .default_agent == "conveyor-readonly"
      and .agent["conveyor-readonly"] == {mode: "primary", permission: $p}
      and ($p | keys_unsorted) == ["*", "read", "glob", "grep", "list", "external_directory"] and ($p | del(.external_directory) | .["*"] == "deny" and ([.[]] - ["deny"] | all(. == "allow")))
      and ($p.external_directory | keys_unsorted == ["*", $rv] and .["*"] == "deny" and .[$rv] == "allow")' >/dev/null \
    && [ "$(sed -n 3p "$STUB/oc-env.1")" = 1 ] || fail "OpenCode was not run with every tool but reading denied, over the worktree's own config: $(cat "$STUB/oc-env.1")"
  grep -q '^+two$' "$STUB/oc-staged.1" && grep -q 'Proof: <proof>' "$STUB/oc-asked" || fail "OpenCode was not given REVIEW and the staged change"
  [ "$(cat "$STUB/status")" = 'M  a.txt' ] && ! grep -q pwned "$STUB/a" || fail "an OpenCode review changed the worktree: $(cat "$STUB/status") $(cat "$STUB/a")"
  loop check >/dev/null || fail "the cards' lines do not pass the record check"
}
# The OpenCode review's runs again and its failure, each a review called alone (rvcall) on the reviewer above.
t_opencoderetry() {
  opencode_reviewer; : > "$STUB/go" # no live record to wait for
  # An answer with no verdict runs once more; both attempts' usage and cost are on the line.
  echo 'I looked at it.' > "$STUB/review.1"; echo "$GO" > "$STUB/review.2"
  out=$(rvcall 8)
  [ "$(wc -l < "$STUB/oc-runs")" = 2 ] && [ "$(tail -n 1 <<<"$out")" = 'rc=0 GO' ] \
    && [ "$(head -n 1 <<<"$out" | jq -c '[.firstTry.reason, .tokens.codex, .usage.cost]')" = '["the review ended without one clear verdict",370,1.5]' ] \
    || fail "an OpenCode answer with no verdict was not run again, or its first attempt left out of the line: $out"
  # A try the model API refused (after one step) runs again; what it used and cost is on the line with the next.
  : > "$STUB/refuse-api"; echo "$GO" > "$STUB/review.4"; tune '.tunables.apiPause = 0.1'
  out=$(rvcall 10)
  [ "$(wc -l < "$STUB/oc-runs")" = 4 ] && [ "$(tail -n 1 <<<"$out")" = 'rc=0 GO' ] && [ "$(head -n 1 <<<"$out" | jq -c '[.tokens.codex, .usage.output, .usage.cost]')" = '[343,23,1]' ] \
    || fail "an OpenCode review the API refused once was not run again with the refused try's usage and cost on its line: $out"
  # OpenCode gone from the host by the time the review runs: the review fails, naming it, and is not run again.
  # The PATH keeps the stubs but no host's own opencode, which would otherwise be found in place of the removed stub.
  rm "$STUB/opencode"
  nooc=$(tr ':' '\n' <<< "$PATH" | while IFS= read -r d; do [ "$d" != "$STUB" ] && [ -e "$d/opencode" ] || printf '%s\n' "$d"; done | paste -sd: -)
  out=$(PATH=$nooc rvcall 9)
  [ "$(wc -l < "$STUB/oc-runs")" = 4 ] && grep -q 'the reviewer is set to opencode prov/vendor/m-1, and opencode is not installed on this host' <<<"$out" && [ "$(tail -n 1 <<<"$out")" = 'rc=1 none' ] \
    || fail "a review with no opencode on the host did not fail naming it: $out"
}

# Bugs: a card session never reaches the proxy the user set (its base URL, key and ENABLE_TOOL_SEARCH left out); a
# reviewer family name (sol) is passed to Codex as written, or resolves to an older or another family's model; the
# proxy key is on a command line (ps); a GitHub Copilot API proxy is sent a key; no match lets a card start, or
# fails without naming the setting to set; Codex's local models_cache.json is not the fallback; doctor does not
# say each role's route; with no proxy anything changes; a proxy named with no key is sent another Anthropic key the
# user holds; a proxy list with none of the family keeps models_cache.json from answering; a quoted or dotted TOML
# key, an inline table or a multiline string, is not read; the key follows a redirect to another origin; doctor calls
# a base URL the engine's environment holds direct; land-branch starts a card whose reviewer family resolves to no model;
# a key held in a variable named like an engine variable (v, key, e, ENV0, FETCH) is lost or replaced by that variable, or
# is taken from the reviewer's environment; an
# escaped quote in a multiline string ends it early, so the settings after it are not read.
proxy_start() { # <issue>: a main with that one issue, the stub proxy serving, Codex and the pack routed through it
  setup "[$(issue "$1" 2026-01-01)]"
  # Doctor's route lines, from its routes() alone; and in doctor's own output, among its checks of this machine (some of
  # which this case's machine fails), where a key's variable may meet doctor's own (t_proxykeys). Then the Anthropic
  # variables a card session gets from proxyenv(), called alone as the session's subshell calls it before claude starts.
  routes() { { modelsengine doctor routes || :; } | grep -E '^(builder|reviewer):'; }
  # Doctor runs in the project's checkout, as a user runs it: started in the case's own folder (no checkout), it stops at
  # "missing: a git checkout of the project" before its route lines.
  doctorroutes() { { (cd "$R" && loop doctor) 2>/dev/null || :; } | grep -E '^(builder|reviewer):'; }
  # Fails when the call does, so a direct session's empty list is never a call that did not run.
  pxenv() { local o; o=$(modelsengine run 'proxyenv && env') || return 1; grep -E '^(ANTHROPIC_BASE_URL|ANTHROPIC_AUTH_TOKEN|ANTHROPIC_API_KEY|ENABLE_TOOL_SEARCH)=' <<<"$o" | sort; return 0; }
  unset ANTHROPIC_BASE_URL ANTHROPIC_AUTH_TOKEN ANTHROPIC_API_KEY ENABLE_TOOL_SEARCH
  echo "$GO" > "$STUB/review.1"; sed -i '2i echo " $* " >> "$STUB/codex-args"' "$STUB/codex"
  # The stub proxy: GET .../models answers $STUB/models; each request logs its Authorization header and, while the
  # asker waits, every process's command line.
  cat > "$STUB/proxy.py" <<'PY'
import http.server, os, subprocess, sys
stub = sys.argv[1]
class H(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        with open(f"{stub}/auth", "a") as f:
            f.write((self.headers.get("Authorization") or "-") + "\n")
        n = len(os.listdir(stub))
        with open(f"{stub}/ps.{n}", "w") as f:
            f.write(subprocess.run(["ps", "-eww", "-o", "args="], capture_output=True, text=True).stdout)
        if self.path.startswith("/redir/"):
            self.send_response(302); self.send_header("Location", f"http://localhost:{self.server.server_address[1]}{self.path[6:]}")
            self.end_headers(); return
        body = open(f"{stub}/models", "rb").read() if self.path.endswith("/models") else b"{}"
        self.send_response(200 if self.path.endswith("/models") else 404); self.end_headers(); self.wfile.write(body)
    def log_message(self, *a): pass
s = http.server.ThreadingHTTPServer(("127.0.0.1", 0), H)
open(f"{stub}/port.new", "w").write(str(s.server_address[1])); os.rename(f"{stub}/port.new", f"{stub}/port")
s.serve_forever()
PY
  python3 -I "$STUB/proxy.py" "$STUB" & srv=$!; trap 'kill $srv 2>/dev/null' EXIT
  until [ -s "$STUB/port" ] || ! kill -0 $srv 2>/dev/null; do sleep 0.1; done # the port, or the server's end
  base=http://127.0.0.1:$(cat "$STUB/port")
  echo '{"data":[{"id":"gpt-6.2-sol"},{"id":"gpt-6.10-sol"},{"id":"gpt-7-astra"},{"id":"gpt-6.11-sol-mini"}]}' > "$STUB/models"
  export CODEX_HOME=$T/$CASE/codex PROXY_KEY=k-$RANDOM$RANDOM-secret; mkdir -p "$CODEX_HOME"
  # TOML's literal (single-quoted) strings and quoted keys name the provider and its table as well as bare ones do.
  printf '"model_provider" = \047proxy\047 # the proxy\n\n[model_providers.\047proxy\047]\nname = "Proxy"\nbase_url = \047%s/v1\047\nenv_key = "PROXY_KEY"\n' "$base" > "$CODEX_HOME/config.toml"
  tune --arg b "$base" '.models.allowed.codex += ["sol"] | .models.claudeProxy = {baseUrl: $b, keyEnv: "PROXY_KEY"}'; seatset reviewer sol
  echo 'env | grep -E "^(ANTHROPIC_BASE_URL|ANTHROPIC_AUTH_TOKEN|ANTHROPIC_API_KEY|ENABLE_TOOL_SEARCH)=" | sort > "$STUB/env"; ps -eww -o args= > "$STUB/ps.session"; echo two >> a.txt' > "$STUB/build"
  cp "$CODEX_HOME/config.toml" "$T/$CASE/config.toml" # as written here, for a part that changed it to put back
}

t_proxy() {
  proxy_start 7
  # The session's key in a variable named v, a variable of proxyenv()'s callers in a card, so only a whole card proves it
  # still carries the key it holds; a key apart from PROXY_KEY's, so a lookup of the wrong variable fails the check.
  tune '.models.claudeProxy.keyEnv = "v"'
  vkey=v-$RANDOM$RANDOM-secret
  v=$vkey loop run >/dev/null || fail "run exited non-zero"
  tune '.models.claudeProxy.keyEnv = "PROXY_KEY"'
  [ "$(st 'select(.step == "review") | .model')" = gpt-6.10-sol ] || fail "the family sol did not resolve to the newest gpt-<version>-sol: $(st 'select(.step == "review") | .model')"
  grep -q -- ' -m gpt-6.10-sol ' "$STUB/codex-args" && ! grep -q -- ' -m sol ' "$STUB/codex-args" || fail "Codex was not run with the resolved model id: $(cat "$STUB/codex-args")"
  [ "$(cat "$STUB/env")" = "$(printf 'ANTHROPIC_AUTH_TOKEN=%s\nANTHROPIC_BASE_URL=%s\nENABLE_TOOL_SEARCH=true' "$vkey" "$base")" ] \
    || fail "the card session's environment does not carry the proxy, or a key in a variable named v was lost: $(cat "$STUB/env")"
  grep -qx "Bearer $PROXY_KEY" "$STUB/auth" || fail "the proxy was not asked with its key: $(cat "$STUB/auth")"
  grep -l build_opener "$STUB"/ps.[0-9]* >/dev/null || fail "no command line was read while the models list was asked for"
  ! grep -l -e "$PROXY_KEY" -e "$vkey" "$STUB"/ps.* >/dev/null || fail "a proxy key is on a command line: $(grep -l -e "$PROXY_KEY" -e "$vkey" "$STUB"/ps.*)"
  # A redirect to another origin (127.0.0.1 to localhost) is followed without the key.
  : > "$STUB/auth"; sed -i "s|$base/v1|$base/redir/v1|" "$CODEX_HOME/config.toml"
  [ "$(routes | sed -n 2p)" = "reviewer: gpt-6.10-sol (codex) through $base/redir/v1, Codex's model_provider proxy, key in PROXY_KEY" ] \
    && [ "$(cat "$STUB/auth")" = "Bearer $PROXY_KEY"$'\n-' ] || fail "the key followed a redirect to another origin: $(cat "$STUB/auth")"
  cp "$T/$CASE/config.toml" "$CODEX_HOME/config.toml"
  out=$(doctorroutes)
  # The key is only in this shell's environment, which the machine's service does not have: doctor calls through the
  # proxy with none, as the service does, and as that call works it says the proxy needs no key (bug: it said "the
  # service finds no key" and then that the call works, which read as a fault), with no missing: line.
  [ "$out" = "builder: m (claude) through $base, key in PROXY_KEY; the proxy needs no key: one call through it with none works
reviewer: gpt-6.10-sol (codex) through $base/v1, Codex's model_provider proxy, key in PROXY_KEY" ] || fail "doctor's routes: $out"
}

# Each part below is a case of its own on its own proxy (proxy_start), so they run side by side.
t_proxytool() {
  proxy_start 8
  # toolSearch named otherwise is what the session gets; a proxy named with no key variable is sent none of the
  # Anthropic keys the user holds for a direct route, only the stand-in key (so not the machine's own login either).
  tune '.models.claudeProxy.toolSearch = "false" | del(.models.claudeProxy.keyEnv)'
  [ "$(ANTHROPIC_AUTH_TOKEN=direct-secret ANTHROPIC_API_KEY=direct-key pxenv)" = "$(printf 'ANTHROPIC_AUTH_TOKEN=no-key\nANTHROPIC_BASE_URL=%s\nENABLE_TOOL_SEARCH=false' "$base")" ] \
    || fail "toolSearch named false did not reach the session, or a direct key went to the proxy: $(ANTHROPIC_AUTH_TOKEN=direct-secret ANTHROPIC_API_KEY=direct-key pxenv)"
  # A key variable named like a variable of the engine's own (e, envof()'s, which proxyenv() called alone runs as well),
  # or ENV0, still carries the key it holds (v, which only a card proves, is t_proxy's).
  tune '.models.claudeProxy.keyEnv = "e"'
  [ "$(e=e-secret pxenv)" = "$(printf 'ANTHROPIC_AUTH_TOKEN=e-secret\nANTHROPIC_BASE_URL=%s\nENABLE_TOOL_SEARCH=false' "$base")" ] \
    || fail "a key in a variable named e did not reach the session: $(e=e-secret pxenv)"
  tune '.models.claudeProxy.keyEnv = "ENV0"'
  [ "$(ENV0=env0-secret pxenv)" = "$(printf 'ANTHROPIC_AUTH_TOKEN=env0-secret\nANTHROPIC_BASE_URL=%s\nENABLE_TOOL_SEARCH=false' "$base")" ] \
    || fail "a key in a variable named ENV0 did not reach the session: $(ENV0=env0-secret pxenv)"
}
# Each whole doctor asks the proxy once for the reviewer's family, with the key (bug #822: modelswarn() and routes()
# each asked it, and the auth log held two lines). Each run is given its host report of Codex's models (clis.json, as
# doctor reads it while fresh): a list, so modelswarn() resolves the family and routes() takes its answer; no list, so
# modelswarn() asks for no family, astra included (the pack's, not a seat's); a list but no sol in the proxy's list or
# models_cache.json, so routes() takes modelswarn()'s failed answer and names the setting.
t_proxykeys() {
  proxy_start 7
  clis() { jq -cn --argjson c "$1" '{at: (now | floor), clis: {codex: $c}}' > "$ST/clis.json"; } # <Codex's list, or null>
  : > "$STUB/auth"; sed -i 's/env_key = "PROXY_KEY"/env_key = "key"/' "$CODEX_HOME/config.toml"; clis '["gpt-6.10-sol"]'
  key=key-secret doctorroutes | grep '^reviewer: gpt-6.10-sol ' >/dev/null || fail "doctor failed with the key in a variable named key"
  [ "$(cat "$STUB/auth")" = "Bearer key-secret" ] || fail "a key in a variable named key was not sent, or sent twice: $(cat "$STUB/auth")"
  : > "$STUB/auth"; sed -i 's/env_key = "key"/env_key = "e"/' "$CODEX_HOME/config.toml"; clis null; tune '.models.allowed.codex += ["astra"]'
  e=e-secret doctorroutes | grep '^reviewer: gpt-6.10-sol ' >/dev/null || fail "doctor failed with the key in a variable named e"
  [ "$(cat "$STUB/auth")" = "Bearer e-secret" ] || fail "a key in a variable named e was not sent, or the proxy was asked for a family with no list to warn against: $(cat "$STUB/auth")"
  : > "$STUB/auth"; sed -i 's/env_key = "e"/env_key = "ENV0"/' "$CODEX_HOME/config.toml"; tune '.models.allowed.codex -= ["astra"]'
  echo '{"data":[{"id":"gpt-7-astra"}]}' > "$STUB/models"; echo '{"models":[{"slug":"gpt-7-astra"}]}' > "$CODEX_HOME/models_cache.json"; clis '["gpt-7-astra"]'
  ENV0=env0-secret doctorroutes | grep '^reviewer: the reviewer model sol is a family name .*models.allowed.codex' >/dev/null || fail "doctor with no sol model did not name the setting"
  [ "$(cat "$STUB/auth")" = "Bearer env0-secret" ] || fail "a key in a variable named ENV0 was not sent, or the unresolved family was asked for twice: $(cat "$STUB/auth")"
}
t_proxyfetch() {
  proxy_start 7
  # A key in a variable named like an engine global (FETCH) is sent to the proxy and reaches Codex as the user set it.
  : > "$STUB/auth"; sed -i 's/env_key = "PROXY_KEY"/env_key = "FETCH"/' "$CODEX_HOME/config.toml"; sed -i '2i printf %s "$FETCH" > "$STUB/codex-fetch"' "$STUB/codex"
  # So does the claudeProxy key variable ENV0 (Codex reads a provider's env_key from the reviewer's own environment).
  tune '.models.claudeProxy.keyEnv = "ENV0"'; echo 'printf %s "${ENV0-unset}" > "$STUB/review-env0"' > "$STUB/review-cmd"
  # The review alone (rvcall), as a card's review step calls it: it asks the proxy for the family's newest model and
  # runs Codex on it.
  out=$(FETCH=fetch-secret ENV0=env0-secret rvcall 14)
  [ "$(tail -n 1 <<<"$out")" = 'rc=0 GO' ] || fail "the review through the proxy did not end GO: $out"
  [ "$(sort -u "$STUB/auth")" = "Bearer fetch-secret" ] && [ "$(cat "$STUB/codex-fetch")" = fetch-secret ] \
    || fail "a key in a variable named FETCH was not sent, or Codex did not inherit it: $(cat "$STUB/auth") $(cat "$STUB/codex-fetch")"
  [ "$(cat "$STUB/review-env0")" = env0-secret ] || fail "the variable ENV0 did not reach the Codex reviewer: $(cat "$STUB/review-env0")"
}
t_proxytoml() {
  proxy_start 7
  # A basic string's escapes are decoded, in a single-line and in a multiline string alike.
  for q in '"' '"""'; do
    printf 'model_provider = %spro\\u0078y%s\n[model_providers.proxy]\nbase_url = "%s/v1"\n' "$q" "$q" "$base" > "$CODEX_HOME/config.toml"
    [ "$(routes | sed -n 2p)" = "reviewer: gpt-6.10-sol (codex) through $base/v1, Codex's model_provider proxy, key in no variable" ] \
      || fail "the escaped provider name $q...$q was not decoded: $(loop doctor)"
  done
  # An escaped quote before a multiline string's close does not close it: the provider table after it is read.
  printf 'model_provider = "proxy"\ninstructions = """a\\"""\nb"""\n[model_providers.proxy]\nbase_url = "%s/v1"\n' "$base" > "$CODEX_HOME/config.toml"
  [ "$(routes | sed -n 2p)" = "reviewer: gpt-6.10-sol (codex) through $base/v1, Codex's model_provider proxy, key in no variable" ] \
    || fail "an escaped quote closed a multiline string: $(cat "$CODEX_HOME/config.toml") $(loop doctor)"
  cp "$T/$CASE/config.toml" "$CODEX_HOME/config.toml"
  # A GitHub Copilot API proxy is asked with no key.
  : > "$STUB/auth"; sed -i 's/proxy/copilot/g' "$CODEX_HOME/config.toml"
  routes | grep '^reviewer: gpt-6.10-sol ' >/dev/null || fail "doctor failed through the Copilot proxy"
  [ "$(cat "$STUB/auth")" = - ] || fail "the Copilot proxy was sent a key: $(cat "$STUB/auth")"
}
t_proxytables() {
  proxy_start 7
  # The provider named in TOML's dotted keys is the same route. The proxy lists none of the family, or no model at
  # all: Codex's models_cache.json answers.
  printf 'model_provider = "copilot"\nmodel_providers.copilot.base_url = "%s/v1"\nmodel_providers . "copilot" . env_key = "PROXY_KEY"\n' "$base" > "$CODEX_HOME/config.toml"
  echo '{"models":[{"slug":"gpt-6-sol"}]}' > "$CODEX_HOME/models_cache.json"
  for list in '{"data":[{"id":"gpt-7-astra"}]}' '{"data":[]}'; do
    echo "$list" > "$STUB/models"
    [ "$(routes | sed -n 2p)" = "reviewer: gpt-6-sol (codex) through $base/v1, Codex's model_provider copilot, key in PROXY_KEY" ] \
      || fail "the dotted provider keys were not read, or the proxy list $list kept models_cache.json from answering: $(loop doctor)"
  done
}
t_proxyinline() {
  proxy_start 7
  # The provider named in an inline table, under its table's header or nested at the top level, is the same route.
  echo '{"data":[{"id":"gpt-6.4-sol"}]}' > "$STUB/models"
  for cfg in '[model_providers]\ncopilot = { base_url = "%s/v1", env_key = "PROXY_KEY" } # inline\n' \
    'model_providers = { copilot = { name = "C", query_params = { "api-version" = "1" }, base_url = \047%s/v1\047, env_key = "PROXY_KEY" } }\n' \
    '[model_providers.copilot]\nbase_url = """\n%s/v1"""\nenv_key = \047\047\047PROXY_KEY\047\047\047\n'; do
    printf "model_provider = \"copilot\"\n$cfg" "$base" > "$CODEX_HOME/config.toml"
    [ "$(routes | sed -n 2p)" = "reviewer: gpt-6.4-sol (codex) through $base/v1, Codex's model_provider copilot, key in PROXY_KEY" ] \
      || fail "the inline provider table was not read: $(cat "$CODEX_HOME/config.toml") $(loop doctor)"
  done
}
t_proxynomatch() {
  proxy_start 7
  # The inline table t_proxytables ends on.
  printf 'model_provider = "copilot"\n[model_providers.copilot]\nbase_url = """\n%s/v1"""\nenv_key = \047\047\047PROXY_KEY\047\047\047\n' "$base" > "$CODEX_HOME/config.toml"
  # No match: nothing is picked, by run or by land-branch, and each names the setting to set.
  echo '{"data":[{"id":"gpt-7-astra"}]}' > "$STUB/models"; echo "[$(issue 9 2026-01-03)]" > "$STUB/issues.json"
  out=$(loop run 2>&1) && fail "a run whose reviewer family matches no model exited zero"
  grep -q 'models.allowed.codex in .conveyor/project.json' <<<"$out" && [ -z "$(st 'select(.issue == 9)')" ] || fail "a card started, or the fix is not named: $out"
  n=$(st 'select(.step == "picked") | .card' | wc -l)
  git -C "$R" worktree add -q -b lane-x "$T/$CASE/lane-x" main && echo bee > "$T/$CASE/lane-x/b.txt" && git -C "$T/$CASE/lane-x" add b.txt && git -C "$T/$CASE/lane-x" commit -qm 'fix(tooling): lane change'
  out=$(loop land-branch lane-x 2>&1) && fail "land-branch with a reviewer family that matches no model exited zero"
  grep -q 'models.allowed.codex in .conveyor/project.json' <<<"$out" && [ "$(st 'select(.step == "picked") | .card' | wc -l)" = "$n" ] || fail "land-branch started a card, or the fix is not named: $out"
  # The proxy unreachable: Codex's models_cache.json answers.
  kill $srv; wait $srv 2>/dev/null
  echo '{"models":[{"slug":"gpt-6.3-sol"},{"slug":"gpt-6-sol"}]}' > "$CODEX_HOME/models_cache.json"
  [ "$(routes | sed -n 2p)" = "reviewer: gpt-6.3-sol (codex) through $base/v1, Codex's model_provider copilot, key in PROXY_KEY" ] || fail "models_cache.json is not the fallback: $(loop doctor)"
}
t_proxydirect() {
  proxy_start 10
  kill $srv; wait $srv 2>/dev/null # as t_proxynomatch leaves it
  # Direct: no proxy anywhere, a full id used as written; the session's environment has none of the proxy's.
  rm "$CODEX_HOME/config.toml"; tune 'del(.models.claudeProxy)'; seatset reviewer x
  [ "$(routes)" = $'builder: m (claude) direct\nreviewer: x (codex) direct' ] || fail "doctor's direct routes: $(loop doctor)"
  # A base URL the engine's own environment holds reaches the card session, so doctor names it.
  [ "$(ANTHROPIC_BASE_URL=https://example.com/v1 routes | sed -n 1p)" = "builder: m (claude) through https://example.com/v1, from the environment Conveyor runs in" ] \
    || fail "doctor called an inherited base URL direct: $(ANTHROPIC_BASE_URL=https://example.com/v1 loop doctor)"
  out=$(pxenv) && [ -z "$out" ] || fail "a direct session was given the proxy's environment, or proxyenv failed: $out"
}

# Bug (#794): a pack's models.allowed that named a model Codex does not report (a typo, or one the account lost), or
# left out one Codex reports, was found only when a seat on it did not start or a menu showed it. Doctor warns of
# each, by its name: the pack lists gpt-a and gpt-c, Codex reports gpt-a and gpt-b. For OpenCode the same: the pack's
# opencode:prov/gone, which OpenCode does not report, is warned of without its mark, and the fix for a reported model
# names it with its opencode: mark, as models.allowed.opencode takes it. A bare name there is not compared: the bare
# other/vendor/m-2 leaves its warning in place, and the bare prov/bare, which OpenCode does not report, gets none.
# A family name the seat resolves (sol, to gpt-6-sol in Codex's models cache) is a model Codex has,
# so doctor does not tell the user to correct it; one that resolves to none (luna) is warned of. The checks run the
# whole doctor: a call of modelswarn alone passes when doctor does not call it.
t_modelsdiff() {
  setup '[]'
  export CODEX_HOME=$T/$CASE/codex-home; mkdir -p "$CODEX_HOME"
  echo '{"models":[{"slug":"gpt-a"},{"slug":"gpt-b"},{"slug":"gpt-6-sol"}]}' > "$CODEX_HOME/models_cache.json"
  jq -cn '{at: (now | floor), clis: {codex: ["gpt-a", "gpt-b", "gpt-6-sol"], opencode: ["prov/m-1", "other/vendor/m-2"]}}' > "$ST/clis.json"
  tune '.models.allowed.codex = ["gpt-a", "gpt-c", "sol", "luna"] | .models.allowed.opencode = ["opencode:prov/m-1", "opencode:prov/gone", "other/vendor/m-2", "prov/bare"]'
  out=$( { (cd "$R" && loop doctor) 2>&1 || :; } | grep "^warning: .*models.allowed")
  [ "$(wc -l <<<"$out")" = 6 ] && ! grep -q "prov/bare" <<<"$out" \
    && grep -q "^warning: the pack's models.allowed lists gpt-c for Codex, which Codex does not report" <<<"$out" \
    && grep -q "^warning: the pack's models.allowed lists luna for Codex, which Codex does not report" <<<"$out" \
    && grep -q "^warning: Codex reports gpt-b, which the pack's models.allowed leaves out.*fix: add gpt-b to models.allowed.codex " <<<"$out" \
    && grep -q "^warning: Codex reports gpt-6-sol, which the pack's models.allowed leaves out" <<<"$out" \
    && grep -q "^warning: the pack's models.allowed lists prov/gone for OpenCode, which OpenCode does not report" <<<"$out" \
    && grep -q "^warning: OpenCode reports other/vendor/m-2, which .*fix: add opencode:other/vendor/m-2 to models.allowed.opencode " <<<"$out" \
    || fail "doctor does not warn of gpt-c, luna and prov/gone, listed and not reported, and gpt-b, gpt-6-sol and other/vendor/m-2, reported and not listed (bare names not compared), alone (sol resolves), with the name to add: $out"
}
# Bug (#794): a Claude-only pack (an empty codex list) takes no Codex models, so it gets no warning for each one Codex
# reports, even with a codex-builder model. The whole doctor runs, as in t_modelsdiff.
t_modelsdiffnone() {
  setup '[]'
  jq -cn '{at: (now | floor), clis: {codex: ["gpt-a", "gpt-b"]}}' > "$ST/clis.json"
  tune '.models.allowed = {claude: ["m"], codex: [], "codex-builder": ["gpt-a"], "claude-reviewer": ["claude-opus-5-5"]}'
  out=$( { (cd "$R" && loop doctor) 2>&1 || :; } | grep "^warning: .*models.allowed")
  [ -z "$out" ] || fail "doctor warns of Codex models a pack with an empty codex list does not take: $out"
}
