#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 300
# Engine cases: the models: a Claude reviewer, session settings and doctor's model warnings. The proxy's cases are
# modelsproxy.test.sh, which uses this file's helpers (modelsengine, rvcall).
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
# A worktree of main, cards/c$n, with the build's change staged, as a card's review step finds it (engine code).
# shellcheck disable=SC2016 # expanded in the engine shell (modelsengine)
RVWT='w=$CARDS/c$n && git -C "$MAIN" worktree add -q --detach "$w" && echo two >> "$w/a.txt" && git -C "$w" add a.txt'
# reviewed() alone, as a card's review step calls it, on that worktree: what it prints, then a line of its exit and the
# verdict it left (rc=<exit> <verdict>). With fix, the review after a fix round follows, as a card's next review is
# given it: that round's diff in <worktree>.rounds and its re-review section (donewhen.sh rereview()) in the brief.
rvcall() { # <n> [fix]
  # shellcheck disable=SC2016 # expanded in the engine shell (modelsengine)
  modelsengine run "n=$1 f=${2:-}; $RVWT"' && { reviewed "$w" "# Issue: body of the issue"; echo "rc=$? $(verdict "$w.review" 2>/dev/null)"; } \
    && { [ -z "$f" ] || { mkdir -p "$w.rounds" && git -C "$w" diff --cached > "$w.rounds/1.diff" && : > "$w.rounds/findings.jsonl" \
      && b="# Issue: body of the issue

$(rereview "c$n" "$w" 1)" && { reviewed "$w" "$b"; echo "rc=$? $(verdict "$w.review" 2>/dev/null)"; }; }; }'
}

# Bugs: a Claude model is refused as the reviewer, or one named with no CLI, or a Codex effort for it, is
# accepted; the Reviewer choices are not the five models, or its efforts not those of the program in force; a Claude
# reviewer still runs Codex, its GO or NO-GO is misread, its line lacks its model, usage or tokens.claude, or a
# failed one is left out of the cost; it is launched with a tool that writes or runs commands, with settings or
# hooks, without the staged change or AGENTS.md, or with AGENTS.md twice; a write that gets through is left in the
# worktree; health does not name it.
t_claudereview() {
  # No ast-grep installed (the Board's virtualenv in an empty data folder of the case), whatever this machine has: the
  # review keeps Read, Grep and Glob and no shell (reviewtools()).
  export XDG_DATA_HOME=$T/$CASE/data
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
  # The two reviews of a card, called alone (rvcall): a NO-GO, then a GO after a fix round.
  echo "$NOGO" > "$STUB/review.1"; echo "$GO" > "$STUB/review.2"; : > "$STUB/keep-live"
  out=$(rvcall 7 fix)
  [ ! -e "$STUB/codex-ran" ] || fail "a Claude reviewer ran Codex"
  # Issue 1085: its live record names the effort it runs at, which the Board shows beside its model.
  [ "$(jq -c '{model, effort}' "$STUB/live.1" 2>&1)" = '{"model":"claude-opus-5-5","effort":"max"}' ] || fail "the Claude review's live record lost its effort: $(cat "$STUB/live.1" 2>&1)"
  [ "$(sed -n '2p;4p' <<<"$out" | tr '\n' ,)" = 'rc=0 NO-GO,rc=0 GO,' ] \
    && [ "$(sed -n '1p;3p' <<<"$out" | jq -r '"\(.model) \(.effort)"' | sort -u)" = 'claude-opus-5-5 max' ] || fail "a Claude reviewer's NO-GO and GO were not read: $out"
  [ "$(sed -n '1p;3p' <<<"$out" | jq -c '[.tokens, .usage, .stats.turns]' | sort -u)" \
    = '[{"claude":157},{"input":100,"write":50,"write1h":0,"read":1000,"output":7},2]' ] || fail "a Claude review's line lacks tokens.claude or its usage: $out"
  # The write attempt changed nothing: after the last review the worktree holds the build's change alone.
  w=$T/$CASE/cards/c7
  [ "$(git -C "$w" status --porcelain)" = 'M  a.txt' ] && ! grep -q pwned "$w/a.txt" \
    || fail "a review session changed the worktree: $(git -C "$w" status --porcelain) $(cat "$w/a.txt")"
  [ "$(head -n 1 "$STUB/reviews")" = "$(sed -n 2p "$STUB/reviews")" ] || fail "the two reviews were launched differently"
  grep -q -- '-p --model claude-opus-5-5 --effort max --permission-mode default --tools Read,Grep,Glob --setting-sources  --strict-mcp-config' "$STUB/reviews" \
    && ! grep -q -- '--settings' "$STUB/reviews" || fail "the review session was given more than Read, Grep and Glob, or settings or hooks: $(head -n 1 "$STUB/reviews")"
  grep -q '^+two$' "$STUB/staged.1" || fail "the review session was not given the staged change: $(cat "$STUB/staged.1")"
  # The review after the fix reads that fix's diff, given in its own folder as the staged change is; the first is given none.
  [ ! -e "$STUB/fix.1" ] && grep -q '^+two$' "$STUB/fix.2" || fail "the review session after the fix was not given the fix's diff: $(cat "$STUB/fix.2" 2>&1)"
  [ "$(grep -c AGENTS-RULES-MARK "$STUB/asked.1")" = 1 ] && grep -q 'Proof: <proof>' "$STUB/asked.1" && grep -q 'body of the issue' "$STUB/asked.1" \
    || fail "the review session was not given REVIEW, the brief and AGENTS.md once: $(cat "$STUB/asked.1")"
}

# The stubs of a Claude reviewer's cases: a review session answers review.N, and first does what a session that got a
# write through would do: it writes in the worktree, whatever it was launched with. Codex fails, and says it ran.
claude_stub() {
  cat > "$STUB/claude" <<'EOF'
#!/usr/bin/env bash
cat > "$STUB/asked"; printf '%s\n' "$*" >> "$STUB/reviews"; n=$(wc -l < "$STUB/reviews"); cp "$STUB/asked" "$STUB/asked.$n"
echo pwned > a.txt; echo pwned > z.txt
# With $STUB/keep-live, the review's live record (<worktree>.live), copied once watch() has written it: watch() starts
# beside this process and removes the record as the review ends, so it is read here, while the review runs.
[ ! -f "$STUB/keep-live" ] || { i=0; while [ ! -s "$PWD.live" ] && [ $i -lt 100 ]; do i=$((i + 1)); sleep 0.05; done; cp "$PWD.live" "$STUB/live.$n"; }
f=$(grep -o 'the file [^ ]*staged\.diff' "$STUB/asked" | cut -d' ' -f3); cp "$f" "$STUB/staged.$n" 2>/dev/null
f=$(grep -o 'are in the folder [^ ]*/rounds' "$STUB/asked" | cut -d' ' -f5); [ -z "$f" ] || cp "$f/1.diff" "$STUB/fix.$n"
[ ! -f "$STUB/review-nostart" ] || { rm "$STUB/review-nostart"; echo 'stderr: stopped before any work' >&2; exit 1; }
[ ! -f "$STUB/review-bare" ] || { rm "$STUB/review-bare"; echo 'stderr: bare' >&2; echo '{"type":"result","is_error":false,"result":"Review interrupted"}'; exit 0; }
[ ! -f "$STUB/review-part" ] || { rm "$STUB/review-part"; echo 'stderr: part' >&2; echo '{"type":"result","is_error":false,"result":"x","usage":{"input_tokens":100,"cache_creation_input_tokens":50,"cache_read_input_tokens":1000,"output_tokens":7}}'
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
  # The review alone, then what the review step does with its failure (card(), lib/card.sh: block()), on card c8.
  # shellcheck disable=SC2016 # expanded in the engine shell (modelsengine)
  modelsengine run "n=8; $RVWT"' && { t=$(reviewed "$w" "# Issue: body of the issue") || block c8 8 "$w" "review 1: $t"; }' >/dev/null 2>&1
  [ "$(wc -l < "$STUB/reviews")" = 2 ] && st 'select(.issue == 8 and .step == "blocked") | .reason' | grep -q 'run again after 0s: review failed (exit 1)' \
    || fail "a Claude review that failed with no verdict was not run once more before the card blocked: $(st 'select(.issue == 8)')"
  # Both attempts are priced: the blocked line's tokens and the usage the dashboard prices hold the first's beside the second's.
  [ "$(st 'select(.issue == 8 and .step == "blocked") | [.spent.step, .spent.model, .spent.firstTry.spent.tokens.claude, .spent.tokens.claude, .tokens.claude,
      .spent.usage == {input: 200, write: 100, write1h: 0, read: 2000, output: 14}] | tojson')" = '["review","claude-opus-5-5",157,314,314,true]' ] \
    || fail "a failed Claude review left its cost out: $(st 'select(.issue == 8 and .step == "blocked")')"
}
# The three below call the review alone (rvcall), as t_claudereview does: what the review step does with a failure is t_claudefail's.
t_claudeexit() {
  claude_reviewer "[$(issue 9 2026-01-03)]"
  echo "$NOGO" > "$STUB/review.1"; : > "$STUB/review-exit"
  out=$(rvcall 9)
  # Its events are kept (reviewkeep()), and the reason names them.
  [ "$(wc -l < "$STUB/reviews")" = 1 ] && [ "$(head -n 1 <<<"$out")" = 'review failed (exit 3); its events are kept in c9.review.events' ] && [ "$(tail -n 1 <<<"$out")" = 'rc=1 none' ] \
    || fail "a Claude review that gave its NO-GO and then exited non-zero was run again: $out"
}
t_claudebare() {
  claude_reviewer "[$(issue 10 2026-01-04)]"
  # An answer that ends cleanly with neither a verdict nor token usage is no verdict: it runs once more. Its events are kept (reviewkeep()).
  echo "$GO" > "$STUB/review.2"; : > "$STUB/review-bare"
  out=$(rvcall 10)
  [ "$(wc -l < "$STUB/reviews")" = 2 ] && [ "$(head -n 1 <<<"$out" | jq -r .firstTry.reason)" = "review reported no token usage; its events are kept in c10.review.events" ] && [ "$(tail -n 1 <<<"$out")" = 'rc=0 GO' ] \
    || fail "a Claude answer with no verdict and no usage was not run again, or its reason names no kept events file: $out"
  # Bug: reviewed() removed the first attempt's events and the retry wrote its err again, so why it failed was lost.
  grep -q 'Review interrupted' "$ST/kept/c10/c10.review.events" && grep -qx 'stderr: bare' "$ST/kept/c10/c10.review.err" \
    || fail "the events or err of a Claude review that reported no token usage were not kept: $(ls "$ST/kept/c10" 2>&1)"
}
# Bug: a Claude review that exited before any work took nostart()'s reason alone, which does not name the kept events file.
t_claudenostart() {
  claude_reviewer "[$(issue 15 2026-01-09)]"
  echo "$GO" > "$STUB/review.2"; : > "$STUB/review-nostart"
  out=$(rvcall 15)
  [ "$(wc -l < "$STUB/reviews")" = 2 ] && [ "$(tail -n 1 <<<"$out")" = 'rc=0 GO' ] \
    && [ "$(head -n 1 <<<"$out" | jq -r .firstTry.reason)" = 'the claude CLI stopped before any work (exit 1): fix what its words below say; its events are kept in c15.review.events'$'\n''stderr: stopped before any work' ] \
    || fail "a Claude review that stopped before any work was not run again, or its reason does not name the kept events file above its words: $out"
  grep -qx 'stderr: stopped before any work' "$ST/kept/c15/c15.review.err" || fail "the err of a Claude review that stopped before any work was not kept: $(ls "$ST/kept/c15" 2>&1)"
}
t_claudepart() {
  claude_reviewer "[$(issue 11 2026-01-05)]"
  # A first attempt whose usage is only part of what it used (one of its results holds none) leaves the step unread,
  # though the retry's usage is whole: it is priced at the tokens counted as an estimate, never as the exact cost.
  echo "$GO" > "$STUB/review.2"; : > "$STUB/review-part"
  out=$(rvcall 11)
  [ "$(head -n 1 <<<"$out" | jq -c '[.tokens.claude, (.unread | test("1 of 2 results"))]')" = '[314,true]' ] && [ "$(tail -n 1 <<<"$out")" = 'rc=0 GO' ] \
    || fail "a retried review whose first attempt's usage was partial is priced as whole: $out"
  # Bug: the first attempt returned at once with its part usage, so reviewed() removed its events and the run again
  # wrote its err again, and why it ended with no verdict was lost.
  grep -q 'Review interrupted' "$ST/kept/c11/c11.review.events" && grep -qx 'stderr: part' "$ST/kept/c11/c11.review.err" \
    || fail "the events or err of a Claude review with part usage and no verdict were not kept: $(ls "$ST/kept/c11" 2>&1)"
  # Bug (#1718): claudereview() and reviewed() each kept that try, so its files were in the kept folder twice.
  [ ! -e "$ST/kept/c11/c11.review-2.events" ] || fail "a Claude try with part usage and no verdict was kept twice: $(ls "$ST/kept/c11")"
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
[ ! -e "$STUB/oc-nostart" ] || { rm "$STUB/oc-nostart"; echo 'stderr: stopped before any step' >&2; exit 1; }
echo '{"type":"step_start","timestamp":1,"sessionID":"s","part":{"type":"step-start"}}'
echo '{"type":"text","timestamp":1,"sessionID":"s","part":{"type":"text","text":"I read the change first."}}'
echo '{"type":"tool_use","timestamp":1,"sessionID":"s","part":{"type":"tool","tool":"read","state":{"status":"completed"}}}'
step 0.25 '{"input":100,"output":5,"reasoning":3,"cache":{"read":1000,"write":50}}'
# sleep: the first review holds after its first step until the case has read its live record.
[ "$n" != 1 ] || for i in $(seq 1200); do [ -e "$STUB/go" ] && break; sleep 0.1; done
[ ! -e "$STUB/refuse-api" ] || { rm "$STUB/refuse-api"; echo 'API Error: 429 Too Many Requests' >&2; exit 1; }
echo '{"type":"step_start","timestamp":2,"sessionID":"s","part":{"type":"step-start"}}'
[ -f "$STUB/review.$n" ] || { echo "stderr: no answer $n" >&2; exit 1; }
jq -cn --rawfile r "$STUB/review.$n" '{type: "text", timestamp: 2, sessionID: "s", part: {type: "text", text: $r}}'
[ ! -e "$STUB/oc-part" ] || { rm "$STUB/oc-part"; echo 'stderr: part usage' >&2; step 0.5 '{"input":20}'; exit 0; }
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
  # The two reviews of a card, called alone (rvcall): a NO-GO, then a GO after a fix round.
  echo "$NOGO" > "$STUB/review.1"; echo "$GO" > "$STUB/review.2"
  wt=$T/$CASE/cards/c7
  rvcall 7 fix > "$STUB/out" 2>&1 & run=$!
  # Its live record, read as an OpenCode run's (not as a Codex review's, whose events these are not): the step it
  # finished is a turn with its usage and cost, and its tool call is the action. A poll: the record is there only
  # while the review runs, which the stub holds after its first step until the case has read it.
  wait_until "jq -e '.step == \"review\" and .turns == 1' '$wt.live'" || { : > "$STUB/go"; wait $run; fail "the live record never counted the OpenCode review's first step: $(cat "$wt.live" 2>/dev/null)"; }
  # Its effort too (issue 1085): the Board shows it beside the model of the running step.
  live=$(jq -c '{model, effort, turns, action, usage}' "$wt.live")
  : > "$STUB/go"; wait $run || fail "the reviews exited non-zero: $(cat "$STUB/out")"
  [ "$live" = '{"model":"opencode:prov/vendor/m-1","effort":"high","turns":1,"action":"read","usage":{"input":100,"write":50,"write1h":0,"read":1000,"output":8,"cost":0.25}}' ] \
    || fail "the live record of an OpenCode review lost its effort, turns, action or usage: $live"
  [ ! -e "$STUB/codex-ran" ] && [ ! -e "$STUB/sessions" ] || fail "an OpenCode reviewer ran Codex or Claude"
  out=$(cat "$STUB/out")
  [ "$(sed -n '2p;4p' <<<"$out" | tr '\n' ,)" = 'rc=0 NO-GO,rc=0 GO,' ] \
    && [ "$(sed -n '1p;3p' <<<"$out" | jq -r '"\(.model) \(.effort)"' | sort -u)" = 'opencode:prov/vendor/m-1 high' ] \
    || fail "an OpenCode reviewer's NO-GO and GO were not read: $out"
  # What it reports: input, cache writes and output (reasoning counted as output) as tokens; its cost, summed, in its
  # usage (usage.cost), where the Board prices an OpenCode step from: anywhere else the review is unpriced.
  [ "$(sed -n '1p;3p' <<<"$out" | jq -c '[.tokens, .usage, .cost, .stats]' | sort -u)" \
    = '[{"codex":185},{"input":120,"write":50,"read":1500,"output":15,"cost":0.75},null,{"turns":2,"tools":{"read":1}}]' ] \
    || fail "an OpenCode review's line lacks the tokens, usage or cost it reported: $out"
  # The Board's price of each review, from the two lines written as the review step writes them (record()), priced as
  # the snapshot prices the cards' steps (rows(), then dashboard_limit.py cardlines).
  # shellcheck disable=SC2034 # read by the engine code below (modelsengine's subshell)
  l1=$(sed -n 1p <<<"$out") l2=$(sed -n 3p <<<"$out")
  # shellcheck disable=SC2016 # expanded in the engine shell (modelsengine)
  priced=$(modelsengine snapshot 'record c7 7 picked ok && record c7 7 review NO-GO "$l1" && record c7 7 review GO "$l2" && d=$T/$CASE/priced && mkdir -p "$d" \
    && rows "$STATE" | jq -c ".[]" > "$d/all" && jq -cn "{prices: {}, since: (now - 86400 | todate)}" \
    | python3 "$HERE/../.claude/scripts/dashboard_limit.py" cardlines "$d/all" "$d/kept" "$d/priced" >/dev/null && jq -c "[.steps[] | select(.step == \"review\") | [.usd, .unpriced]]" "$d/priced"')
  [ "$priced" = '[[0.75,null],[0.75,null]]' ] || fail "the Board does not price the OpenCode reviews at the cost OpenCode reported: $priced"
  # Run in the worktree, read-only, on the model and the effort set, given the staged change; its write undone.
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
  [ "$(git -C "$wt" status --porcelain)" = 'M  a.txt' ] && ! grep -q pwned "$wt/a.txt" || fail "an OpenCode review changed the worktree: $(git -C "$wt" status --porcelain) $(cat "$wt/a.txt")"
  loop check >/dev/null || fail "the review lines do not pass the record check"
}
# The OpenCode review's runs again and its failure, each a review called alone (rvcall) on the reviewer above.
t_opencoderetry() {
  opencode_reviewer; : > "$STUB/go" # no live record to wait for
  # An answer with no verdict runs once more; both attempts' usage and cost are on the line.
  echo 'I looked at it.' > "$STUB/review.1"; echo "$GO" > "$STUB/review.2"
  out=$(rvcall 8)
  [ "$(wc -l < "$STUB/oc-runs")" = 2 ] && [ "$(tail -n 1 <<<"$out")" = 'rc=0 GO' ] \
    && [ "$(head -n 1 <<<"$out" | jq -c '[.firstTry.reason, .tokens.codex, .usage.cost]')" = '["the review ended without one clear verdict; its events are kept in c8.review.events",370,1.5]' ] \
    || fail "an OpenCode answer with no verdict was not run again, or its first attempt left out of the line: $out"
  # Bug (#1718): reviewed() removed that answer's events before the run again, so why it gave no verdict could not be read.
  grep -qF 'I looked at it.' "$ST/kept/c8/c8.review.events" || fail "the events of an OpenCode answer with no verdict were not kept: $(ls "$ST/kept/c8" 2>&1)"
  # A try the model API refused (after one step) runs again; what it used and cost is on the line with the next.
  : > "$STUB/refuse-api"; echo "$GO" > "$STUB/review.4"; tune '.tunables.apiPause = 0.1'
  out=$(rvcall 10)
  [ "$(wc -l < "$STUB/oc-runs")" = 4 ] && [ "$(tail -n 1 <<<"$out")" = 'rc=0 GO' ] && [ "$(head -n 1 <<<"$out" | jq -c '[.tokens.codex, .usage.output, .usage.cost]')" = '[343,23,1]' ] \
    || fail "an OpenCode review the API refused once was not run again with the refused try's usage and cost on its line: $out"
  # OpenCode gone from the host by the time the review runs: the review fails, naming it, and is not run again.
  # The PATH keeps the stubs but no host's own opencode, which would otherwise be found in place of the removed stub.
  # This host's report listed opencode, so the review first reads the host again SEAT_TRIES times (seatwait(),
  # lib/control.sh): watchturns notes each SEAT_PAUSE as a line `seatwait` in place of waiting it out (4 x 30 s).
  rm "$STUB/opencode"; watchturns
  nooc=$(tr ':' '\n' <<< "$PATH" | while IFS= read -r d; do [ "$d" != "$STUB" ] && [ -e "$d/opencode" ] || printf '%s\n' "$d"; done | paste -sd: -)
  out=$(PATH=$nooc rvcall 9)
  [ "$(wc -l < "$STUB/oc-runs")" = 4 ] && grep -q 'the reviewer is set to opencode prov/vendor/m-1, and opencode is not installed on this host' <<<"$out" && [ "$(tail -n 1 <<<"$out")" = 'rc=1 none' ] \
    && [ "$(grep -cx seatwait "$TURNS")" = 4 ] || fail "a review with no opencode on the host did not fail naming it after reading the host again four times: $out $(cat "$TURNS")"
}
# Bug: an OpenCode review that failed with no verdict lost its events and err: reviewed() removed the events, and the
# run again wrote its err again, so why the first attempt failed could not be read.
t_opencodekept() {
  opencode_reviewer; : > "$STUB/go" # no live record to wait for
  echo "$GO" > "$STUB/review.2" # no review.1: the first attempt exits 1 after one step, with no answer
  out=$(rvcall 12)
  [ "$(wc -l < "$STUB/oc-runs")" = 2 ] && [ "$(tail -n 1 <<<"$out")" = 'rc=0 GO' ] \
    && [ "$(head -n 1 <<<"$out" | jq -r '.firstTry.reason | split("\n")[0]')" = 'review failed (exit 1); its events are kept in c12.review.events' ] \
    || fail "a failed OpenCode review was not run again, or its reason names no kept events file on its first line: $out"
  grep -q step_finish "$ST/kept/c12/c12.review.events" && grep -qx 'stderr: no answer 1' "$ST/kept/c12/c12.review.err" \
    || fail "the events or err of a failed OpenCode review were not kept: $(ls "$ST/kept/c12" 2>&1)"
}
# Bug: an OpenCode review that ended with no whole token usage lost its events and err as a failed one did (above).
t_opencodeunread() {
  opencode_reviewer; : > "$STUB/go" # no live record to wait for
  echo 'Review interrupted' > "$STUB/review.1"; : > "$STUB/oc-part"; echo "$GO" > "$STUB/review.2"
  out=$(rvcall 13)
  [ "$(wc -l < "$STUB/oc-runs")" = 2 ] && [ "$(tail -n 1 <<<"$out")" = 'rc=0 GO' ] \
    && [ "$(head -n 1 <<<"$out" | jq -r .firstTry.reason)" = 'review reported no token usage; its events are kept in c13.review.events' ] \
    || fail "an OpenCode review with no whole usage was not run again, or its reason names no kept events file: $out"
  grep -q 'Review interrupted' "$ST/kept/c13/c13.review.events" && grep -qx 'stderr: part usage' "$ST/kept/c13/c13.review.err" \
    || fail "the events or err of an OpenCode review with no whole usage were not kept: $(ls "$ST/kept/c13" 2>&1)"
}
# Bug: an OpenCode review that exited before any work took nostart()'s reason alone, which does not name the kept events file.
t_opencodenostart() {
  opencode_reviewer; : > "$STUB/go" # no live record to wait for
  : > "$STUB/oc-nostart"; echo "$GO" > "$STUB/review.2"
  out=$(rvcall 14)
  [ "$(wc -l < "$STUB/oc-runs")" = 2 ] && [ "$(tail -n 1 <<<"$out")" = 'rc=0 GO' ] \
    && [ "$(head -n 1 <<<"$out" | jq -r .firstTry.reason)" = 'the opencode CLI stopped before any work (exit 1): fix what its words below say; its events are kept in c14.review.events'$'\n''stderr: stopped before any step' ] \
    || fail "an OpenCode review that stopped before any work was not run again, or its reason does not name the kept events file above its words: $out"
}
# Bug: the review step's record() (lib/card.sh) drops or misplaces the cost OpenCode reported, so a landed card's
# timeline shows its review unpriced. A whole card run: t_opencodereview writes the review lines itself, so only a
# card that reaches its review step and lands shows what that step records.
t_opencodeland() {
  opencode_reviewer; : > "$STUB/go" # no live record to wait for
  echo "$GO" > "$STUB/review.1"
  loop run --only 7 > "$STUB/log" 2>&1 || fail "run of #7 exited non-zero: $(cat "$STUB/log")"
  [ -n "$(st 'select(.issue == 7 and .step == "landed") | .sha')" ] || fail "#7 did not land: $(st 'select(.issue == 7)')"
  # The snapshot's clock is #7's landing (CONVEYOR_NOW): .landed holds the cards landed on the clock's local day, so a
  # snapshot read past midnight after the landing left #7 out.
  tl=$(CONVEYOR_NOW=$(st 'select(.issue == 7 and .step == "landed") | .time | fromdate') loop snapshot --fresh \
    | jq -c '[.landed[] | select(.issue == 7) | .metrics.timeline[] | select(.step == "review") | [.usd, .unpriced]]')
  [ "$tl" = '[[0.75,null]]' ] || fail "the landed timeline does not price the OpenCode review at the cost OpenCode reported: $tl"
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
