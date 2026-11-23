#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 300
# Engine cases: one issue's own builder, reviewer and judge (the control record's cards, `control card`), and Pick for
# me (`control card <issue> pick`), which asks the project's judge for them.
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"

# The setup: the pack allows the builder m and m2 (Claude), the review x and x2 (Codex) and j and j2 (Claude), so the
# project's seats are m, x and the judge j, each at medium. A Claude call with the review's read-only tools is the
# judge: its arguments are kept in $STUB/judges and its answer is $STUB/judge; a Claude call with no tools (askmodel)
# is Pick for me or the judge's pick of the rule Pick settings, once $STUB/pick or $STUB/pick-json is there (before, it is a card run's same-file check, answered NONE): its prompt is kept in $STUB/pick-asked, its account folder and route in $STUB/pick-env, and its answer is $STUB/pick (or the whole JSON output $STUB/pick-json); any other is a session.
seatsetup() { # <issues json>
  setup "$1"
  tune '.models.allowed = {claude: ["m", "m2"], codex: ["x", "x2"], "claude-reviewer": ["j", "j2"]}'
  sed -i '2i echo "$*" >> "$STUB/reviewargs"' "$STUB/codex" # its arguments, before the stub reads them away
  cat > "$STUB/claude" <<'EOF'
#!/usr/bin/env bash
case "$*" in
  *"--tools Read,Grep,Glob"*) cat > /dev/null; echo "$*" >> "$STUB/judges"
    jq -cn --rawfile r "$STUB/judge" '{type: "result", is_error: false, result: $r, usage: {input_tokens: 3, cache_creation_input_tokens: 0, cache_read_input_tokens: 0, output_tokens: 2}}'
    exit ;;
  *"--tools  "*) if [ -f "$STUB/pick" ] || [ -f "$STUB/pick-json" ]; then
      cat > "$STUB/pick-asked"; echo "$*" >> "$STUB/picks"; echo "${CLAUDE_CONFIG_DIR:-default} ${ANTHROPIC_BASE_URL:-login}" > "$STUB/pick-env"
      [ ! -f "$STUB/pick-delay" ] || sleep "$(cat "$STUB/pick-delay")" # sleep: a judge slower than PICK_TIMEOUT, so the call times out
      # $STUB/pick-json, when it is there, is the JSON output as it is; else $STUB/pick is its result.
      j=$(cat "$STUB/pick-json" 2>/dev/null || jq -cn --rawfile r "$STUB/pick" '{type: "result", is_error: false, subtype: "success", result: $r, num_turns: 1}')
    else cat > /dev/null; j='{"type":"result","is_error":false,"result":"NONE","num_turns":1}'; fi # a same-file check of a card run (overlapcall())
    # As Claude Code does, the JSON output only with --output-format json, else only its result.
    [[ " $* " == *" --output-format json "* ]] && echo "$j" || jq -r .result <<<"$j"; exit ;;
esac
cat > "$STUB/brief"; echo "$*" >> "$STUB/sessions"; . "$STUB/build"
echo '{"type":"result","is_error":false,"usage":{"input_tokens":10,"cache_creation_input_tokens":20,"cache_read_input_tokens":999,"output_tokens":5}}'
EOF
}

# Bug: an issue given its own builder, reviewer and judge was built, reviewed and judged on the project's seats, or
# its seats leaked into another card of the same run.
t_cardseatrun() {
  seatsetup "[$(issue 7 2026-01-01),$(issue 8 2026-01-02)]"
  loop control judge on >/dev/null || fail "control judge on was refused"
  loop control card 7 builder m2 high >/dev/null && loop control card 7 reviewer x2 low >/dev/null && loop control card 7 judge j2 >/dev/null \
    || fail "control card did not take #7's seats"
  # Each first review finds one thing and the judge declines it, so each card has a judge call; the review of the
  # second card's port onto main (below) is a GO.
  printf '%s\n' '[P1] a.txt:2 wrong word' 'USER-VISIBLE: no' 'VERDICT: NO-GO' > "$STUB/review.1"; cp "$STUB/review.1" "$STUB/review.2"
  printf '%s\n' 'USER-VISIBLE: no' 'VERDICT: GO' > "$STUB/review.3"
  echo 'F1 DECLINE: no' > "$STUB/judge"
  # loop: only whole cards of one run show each card's seats kept to it, through its build, review, judge and port
  : > "$STUB/sessions"; loop run >/dev/null || fail "run exited non-zero"
  [ "$(st 'select(.step == "build") | "#\(.issue) \(.model) \(.effort)"' | sort | tr '\n' ,)" = "#7 m2 high,#8 m medium," ] \
    || fail "the builds did not run on each card's builder: $(st 'select(.step == "build") | [.issue, .model, .effort] | tostring' | tr '\n' ' ')"
  # Both change a.txt, so the card that lands second brings its change onto main in one more session, on its builder.
  [ "$(cut -d' ' -f1-5 "$STUB/sessions" | sort -u | tr '\n' ,)" = "-p --model m --effort medium,-p --model m2 --effort high," ] \
    || fail "the build sessions ran on: $(cut -d' ' -f1-5 "$STUB/sessions") $(st 'select(.step | IN("build", "fix", "review")) | [.issue, .step, .result, .model] | tostring' | tr '\n' ' ')"
  [ "$(st 'select(.step == "review" and .judge != null) | "#\(.issue) \(.model) \(.effort) \(.judge.model)"' | sort | tr '\n' ,)" = "#7 x2 low j2,#8 x medium j," ] \
    || fail "the reviews and judges did not run on each card's: $(st 'select(.step == "review") | [.issue, .model, .effort, .judge.model] | tostring' | tr '\n' ' ')"
  [ "$(sed -n 's/.* -m \([^ ]*\) -c model_reasoning_effort="\([a-z]*\)" -o .*-main-\([0-9]*\)\.review\.new.*/#\3 \1 \2/p' "$STUB/reviewargs" | sort -u | tr '\n' ,)" = "#7 x2 low,#8 x medium," ] \
    || fail "Codex reviewed on: $(cat "$STUB/reviewargs")"
  grep -c -- '--model j2 --effort medium ' "$STUB/judges" | grep -qx 1 && grep -c -- '--model j --effort medium ' "$STUB/judges" | grep -qx 1 \
    || fail "the judge calls ran on: $(cat "$STUB/judges")"
  [ "$(st 'select(.step == "landed") | .issue' | sort | tr '\n' ' ')" = "7 8 " ] || fail "the cards did not both land"
}

# Bug: a card given only its own reviewer, of another family than the project's (here j2, a Claude one, for the
# project's Codex x), was judged by a default worked out from its reviewer (x, a Codex one), while the Board shows it
# the project's judge (j). A card with no judge of its own has the project's.
t_cardseatjudge() {
  seatsetup '[]'
  loop control card 7 reviewer j2 >/dev/null || fail "control card did not take #7's reviewer"
  out=$( export CONVEYOR_MAIN=$R CONVEYOR_CARDS=$T/$CASE/cards; . "$SRC/conveyor.sh" state-dir > /dev/null \
    && eval "$(grep '^\. "\$HERE/lib/' "$SRC/commands/serve.sh")" && SEATCARD=7 seat reviewer | jq -r .model && SEATCARD=7 seat judge | jq -r '"\(.model) \(.agent)"' && SEATCARD='' seat judge | jq -r .model 2>&1)
  [ "$out" = $'j2\nj claude\nj' ] || fail "#7's reviewer or judge is not its own reviewer and the project's judge (j2, j claude, j): $out"
}

# Bug: the fix of a review's findings and the fix of failed changed tests ran on the builder's model and effort, when
# the control record names a fix and a testFix seat of their own. The build stays on the builder (m, medium), the
# review fix runs on fix (m2, high), the test fix on testFix (m2, low) one level up, as the card's second fix (medium),
# and the test command calls no model.
t_cardseatfix() {
  seatsetup "[$(issue 7 2026-01-01)]"
  jq -c '.fix = {model: "m2", effort: "high"} | .testFix = {model: "m2", effort: "low"}' "$ST/control.json" > "$STUB/c.new" && mv "$STUB/c.new" "$ST/control.json"
  printf '%s\n' '[P1] a.txt:1 wrong word' 'USER-VISIBLE: no' 'VERDICT: NO-GO' > "$STUB/review.1"
  for i in 2 3 4; do echo "$GO" > "$STUB/review.$i"; done
  # The changed tests fail, every run, until the session told they fail has run.
  echo 'echo two >> a.txt; ! grep -q "The changed tests fail" "$STUB/brief" || touch "$STUB/testfixed"' > "$STUB/build"
  echo '[ -e "$STUB/testfixed" ] || { echo "FAIL a.test.sh"; exit 1; }' > "$STUB/test-cmd"
  # loop: only a whole card has the review's fix and then the failed tests' fix in turn, each on its own seat
  : > "$STUB/sessions"; loop run >/dev/null || fail "run exited non-zero"
  [ "$(st 'select(.issue == 7 and (.step | IN("build", "fix"))) | "\(.step) \(.model) \(.effort)"' | tr '\n' ,)" = "build m medium,fix m2 high,fix m2 medium," ] \
    || fail "the build, review fix and test fix did not run on builder, fix and testFix: $(st 'select(.issue == 7) | [.step, .result, .model, .effort] | tostring' | tr '\n' ' ')"
  [ "$(cut -d' ' -f1-5 "$STUB/sessions" | tr '\n' ,)" = "-p --model m --effort medium,-p --model m2 --effort high,-p --model m2 --effort medium," ] \
    || fail "the Claude sessions ran on: $(cut -d' ' -f1-5 "$STUB/sessions")"
  [ "$(st 'select(.step == "landed") | .issue')" = 7 ] || fail "the card did not land"
}

# #1306. Two NO-GO reviews, then a GO: the card's fix rounds, each on the builder's seat (m at medium) as the control
# record sets no fix seat, with the jq filter given (when any) applied to the pack. It sets $got to the efforts of the
# card's sessions, comma-joined (not printed: the setup must stay in the case's shell).
fixrounds() { # [pack filter]
  seatsetup "[$(issue 7 2026-01-01)]"; [ -z "${1:-}" ] || tune "$1"
  printf '%s\n' '[P2] a.txt:1 wrong word' 'USER-VISIBLE: no' 'VERDICT: NO-GO' > "$STUB/review.1"
  # A P1: a review 2 of new P2s alone ends the loop (loopstop(): new-p2), with no second fix round.
  printf '%s\n' '[P1] a.txt:2 another wrong word' 'USER-VISIBLE: no' 'VERDICT: NO-GO' > "$STUB/review.2"
  echo "$GO" > "$STUB/review.3"; echo 'echo "$RANDOM" >> a.txt' > "$STUB/build"
  : > "$STUB/sessions"; loop run >/dev/null || fail "run exited non-zero" # loop: only a whole card has a second fix round, with its own seat's effort
  got=$(cut -d' ' -f5 "$STUB/sessions" | tr '\n' ,)
}
# Bug it catches: a second fix round on a card ran at the effort of the first, so a round that failed once ran again
# the same way. The build and the first fix run at medium, the second fix one level up (high).
t_cardfixup() {
  fixrounds; [ "$got" = "medium,medium,high," ] || fail "the build, first fix and second fix did not run at medium, medium and high: $(cut -d' ' -f1-5 "$STUB/sessions" | tr '\n' ,)"
}
# Bug it catches: the second fix round went above the pack's max for the model (pick.builder.m max medium): it must
# stay at medium.
t_cardfixupmax() {
  fixrounds '.pick.builder.m = {max: "medium"}'; [ "$got" = "medium,medium,medium," ] || fail "the second fix went above the pack's max (medium): $(cut -d' ' -f1-5 "$STUB/sessions" | tr '\n' ,)"
}

# Bug it catches: a test fix that is the card's first fix ran one level up, because the reviews before it were counted as
# fix rounds. Its one review is a GO, the changed tests fail once, and the build and the test fix both run at medium.
t_cardfixupfirst() {
  seatsetup "[$(issue 7 2026-01-01)]"
  for i in 1 2 3; do echo "$GO" > "$STUB/review.$i"; done
  echo 'echo "$RANDOM" >> a.txt; ! grep -q "The changed tests fail" "$STUB/brief" || touch "$STUB/testfixed"' > "$STUB/build"
  echo '[ -e "$STUB/testfixed" ] || { echo "FAIL a.test.sh"; exit 1; }' > "$STUB/test-cmd"
  : > "$STUB/sessions"; loop run >/dev/null || fail "run exited non-zero" # loop: only a whole card has a test fix after its reviews
  [ "$(cut -d' ' -f5 "$STUB/sessions" | tr '\n' ,)" = "medium,medium," ] || fail "the build and the first (test) fix did not both run at medium: $(cut -d' ' -f1-5 "$STUB/sessions" | tr '\n' ,)"
}
# Bug it catches: a second fix went above the pack's max when the effort of its seat already was above it (a control
# record can set one the pack does not allow): `max` on a model the pack caps at xhigh stepped to `max`, not xhigh.
# The step is the engine's own function (effortup()), run on that pack.
t_effortupcap() {
  seatsetup "[$(issue 7 2026-01-01)]"; tune '.pick.builder.m = {max: "xhigh"}'
  local out
  out=$( export CONVEYOR_MAIN=$R CONVEYOR_CARDS=$T/$CASE/cards; . "$SRC/conveyor.sh" state-dir > /dev/null \
    && eval "$(grep '^\. "\$HERE/lib/' "$SRC/commands/serve.sh")" && echo "$(effortup claude m max) $(effortup claude m high) $(effortup claude m xhigh) $(effortup claude m2 xhigh)" 2>&1)
  [ "$out" = "xhigh xhigh xhigh max" ] || fail "effortup claude m max/high/xhigh and m2 xhigh (m capped at xhigh) gave: $out, not xhigh xhigh xhigh max"
}

# Bug: a card with no fix or testFix seat set repaired on another model than its own builder (here #7's own m2 at
# high, not the project's m): an ordinary card inherits its builder for both repairs.
t_cardseatfixfollow() {
  local out s
  seatsetup '[]'
  loop control card 7 builder m2 high >/dev/null || fail "control card did not take #7's builder"
  out=$( export CONVEYOR_MAIN=$R CONVEYOR_CARDS=$T/$CASE/cards; . "$SRC/conveyor.sh" state-dir > /dev/null \
    && eval "$(grep '^\. "\$HERE/lib/' "$SRC/commands/serve.sh")" && for s in fix testFix; do SEATCARD=7 seat "$s" | jq -r '"\(.model) \(.effort)"'; SEATCARD='' seat "$s" | jq -r '"\(.model) \(.effort)"'; done 2>&1)
  [ "$out" = $'m2 high\nm medium\nm2 high\nm medium' ] || fail "the fix and testFix seats are not #7's builder and the project's builder: $out"
}

# Bug: with a Codex builder and reviewer the guard read no Claude account, so a Claude fix or testFix seat repaired
# on the builder's account past its usage limit. And the Board named that account's use "build and fix" (the
# "build" role) though it only repairs: its role is "fix", and a Claude builder's stays "build".
t_cardseatfixguard() {
  local out k
  seatsetup '[]'
  jq -cn '{time: (now | todate), pct: 90}' > "$ST/limit.jsonl"
  out=$( export CONVEYOR_MAIN=$R CONVEYOR_CARDS=$T/$CASE/cards; . "$SRC/conveyor.sh" state-dir > /dev/null \
    && eval "$(grep '^\. "\$HERE/lib/' "$SRC/commands/serve.sh")" && tunables && c=$(jq -c '.model = {cli: "codex", model: "x"} | .reviewer = {cli: "codex", model: "x"}' "$ST/control.json") \
    && for k in '' fix testFix; do jq -c --arg k "$k" 'if $k == "" then . else .[$k] = {model: "m"} end' <<<"$c" | { read -r r; guardread "$r" | jq -r .pct; subaccts "$r" | cut -d ' ' -f 1; echo "$k:"; }; done \
    && jq -c '.model = {cli: "claude", model: "m"} | .reviewer = {cli: "codex", model: "x"} | .testFix = {cli: "codex", model: "x"}' <<<"$c" | { read -r r; subaccts "$r" | cut -d ' ' -f 1; } 2>&1)
  [ "$out" = $':\n90\nfix\nfix:\n90\nfix\ntestFix:\nbuild' ] || fail "the guard did not read the builder's account for a Claude repair seat alone (or read it for none), or named a repair-only account's role build, or a Claude builder's not build: $out"
}

# Bug: a per-card seat took a model the pack does not allow that seat (a session would start on a model nobody
# chose), or an effort its CLI does not take, without saying which models are allowed; clear left the seat set.
t_cardseatset() {
  seatsetup "[$(issue 7 2026-01-01)]"; before=$(cksum < "$ST/control.json")
  out=$(loop control card 7 builder x 2>&1); [ $? = 2 ] \
    && [[ $out == *"x is not one of the models the pack's models.allowed lets the builder run: it allows m, m2; nothing changed"* ]] \
    || fail "a builder model outside models.allowed was not refused naming the allowed models: $out"
  out=$(loop control card 7 judge m 2>&1); [ $? = 2 ] && [[ $out == *"it allows x, x2, j, j2"* ]] || fail "a judge model outside models.allowed was not refused: $out"
  out=$(loop control card 7 reviewer x2 max 2>&1); [ $? = 2 ] && [[ $out == *"codex takes no effort max"* ]] || fail "an effort Codex does not take was not refused: $out"
  [ "$(cksum < "$ST/control.json")" = "$before" ] || fail "a refused seat changed the record: $(cat "$ST/control.json")"
  [ "$(loop control card 7 builder m2 | jq -c '.cards["7"]')" = '{"builder":{"model":"m2"}}' ] \
    && [ "$(loop control card 7 judge j2 high | jq -c '.cards["7"]')" = '{"builder":{"model":"m2"},"judge":{"model":"j2","effort":"high"}}' ] \
    && [ "$(loop control card 7 builder clear | jq -c '.cards["7"]')" = '{"judge":{"model":"j2","effort":"high"}}' ] \
    && [ "$(loop control card 7 clear | jq -c .cards)" = '{}' ] || fail "control card did not set and clear #7's seats: $(cat "$ST/control.json")"
}

# Bug: Pick for me changed the issue's seats with nobody's apply, gave no reason for a choice, or offered a model the
# pack does not allow the seat; the judge was not given the issue, its allowed models and their prices.
t_cardpick() {
  seatsetup "[$(issue 7 2026-01-01)]"
  printf '%s\n' 'Here you are:' '{"builder": {"model": "m2", "effort": "high", "why": "a wide change"},' \
    '"reviewer": {"model": "x", "effort": "low", "why": "small diff"}, "judge": {"model": "j", "effort": "medium", "why": "cheapest"}}' > "$STUB/pick"
  before=$(cksum < "$ST/control.json" 2>/dev/null)
  out=$(loop control card 7 pick) || fail "Pick for me failed: $out"
  [ "$(jq -c . <<<"$out")" = '{"issue":7,"builder":{"model":"m2","effort":"high","why":"a wide change"},"reviewer":{"model":"x","effort":"low","why":"small diff"},"judge":{"model":"j","effort":"medium","why":"cheapest"},"model":"j"}' ] \
    || fail "Pick for me did not answer the judge's settings with a reason each: $out"
  [ "$(cksum < "$ST/control.json" 2>/dev/null)" = "$before" ] || fail "Pick for me changed the control record before any apply: $(cat "$ST/control.json")"
  grep -q -- '--model j ' "$STUB/picks" && grep -qx 'body of 7' "$STUB/pick-asked" && grep -qx -- '- m2 (claude; efforts: low, medium, high, xhigh, max; no price)' "$STUB/pick-asked" \
    && grep -qx -- '- j (claude; efforts: low, medium, high, xhigh, max; no price)' "$STUB/pick-asked" || fail "the judge was not asked with the issue and its allowed models: $(cat "$STUB/pick-asked")"
  # A model the pack prices is offered with its price.
  tune '.prices = {"m2": {"input": 3, "output": 15, "cacheRead": 0.3}}'; loop control card 7 pick >/dev/null || fail "Pick for me failed with a price set"
  grep -qx -- '- m2 (claude; efforts: low, medium, high, xhigh, max; $3 input, $15 output per million tokens)' "$STUB/pick-asked" || fail "the judge was not given the price: $(grep -- '- m2' "$STUB/pick-asked")"
  # Applying is the owner's: the three seats set as picked.
  loop control card 7 builder m2 high >/dev/null && loop control card 7 reviewer x low >/dev/null && loop control card 7 judge j medium >/dev/null \
    && [ "$(jq -c '.cards["7"]' "$ST/control.json")" = '{"builder":{"model":"m2","effort":"high"},"reviewer":{"model":"x","effort":"low"},"judge":{"model":"j","effort":"medium"}}' ] \
    || fail "applying the pick did not set #7's seats: $(cat "$ST/control.json")"
  # A choice the seat does not take is refused, with why.
  sed -i 's/"model": "x"/"model": "m"/' "$STUB/pick"
  out=$(loop control card 7 pick 2>&1) && fail "Pick for me took a reviewer model the review does not allow: $out"
  [[ $out == *"the judge's choice for the reviewer is refused: m is not one of the models"* ]] || fail "a refused pick did not say why: $out"
}

# Issue 800. Bug: a Claude judge that exits 0 with an empty result (Claude's JSON output says success) read as an
# answer, so Pick for me failed with "the judge's answer held no JSON object of the three seats:" and an empty text,
# never saying the judge sent back nothing. The same JSON output with the three seats in its result is the pick.
t_cardpickempty() {
  seatsetup "[$(issue 7 2026-01-01)]"
  echo '{"is_error":false,"subtype":"success","result":"","num_turns":2}' > "$STUB/pick-json"
  out=$(loop control card 7 pick 2>&1) && fail "Pick for me passed on an empty answer: $out"
  grep -qF "conveyor: the judge (j) did not answer: the judge sent back an empty answer (exit 0, 2 turns)" <<<"$out" && ! grep -q 'held no JSON object' <<<"$out" \
    || fail "Pick for me did not say the judge sent back an empty answer, with the turns: $out"
  jq -cn --arg r '{"builder": {"model": "m2", "effort": "high", "why": "w"}, "reviewer": {"model": "x", "effort": "low", "why": "s"}, "judge": {"model": "j", "effort": "medium", "why": "c"}}' \
    '{is_error: false, subtype: "success", result: $r, num_turns: 2}' > "$STUB/pick-json"
  out=$(loop control card 7 pick 2>&1) || fail "Pick for me failed on an answer: $out"
  [ "$(jq -c '[.builder.model, .reviewer.model, .judge.model, .model]' <<<"$out")" = '["m2","x","j","j"]' ] || fail "Pick for me did not print the pick: $out"
}

# Bugs: Pick for me with an OpenCode judge failed, as the control command had not loaded the OpenCode runner (ocrun);
# and it refused every answer for an OpenCode builder, which takes no effort, as an effort was required of each seat.
t_cardpickoc() {
  seatsetup "[$(issue 7 2026-01-01)]"
  tune '.models.allowed.opencode = ["opencode:prov/mod-1"]'
  jq -c '.judge = {cli: "opencode", model: "opencode:prov/mod-1", effort: "high"}' "$ST/control.json" > "$STUB/c.new" && mv "$STUB/c.new" "$ST/control.json"
  # The shared opencode stub (tests/stubs/opencode) answers it, and logs the ask (brief) and its arguments (sessions).
  echo '{"builder": {"model": "opencode:prov/mod-1", "effort": null, "why": "cheap"}, "reviewer": {"model": "x", "effort": "low", "why": "small"}, "judge": {"model": "j", "effort": "medium", "why": "fine"}}' > "$STUB/opencode-answer"
  out=$(loop control card 7 pick 2>&1) || fail "Pick for me with an OpenCode judge failed: $out"
  [ "$(jq -c '[.builder.effort, .model]' <<<"$out")" = '[null,"opencode:prov/mod-1"]' ] || fail "the pick of an OpenCode builder: $out"
  grep -q -- '-m prov/mod-1 --variant high' "$STUB/sessions" && grep -qx 'body of 7' "$STUB/brief" || fail "OpenCode was not asked as the judge: $(cat "$STUB/sessions")"
}

# Bugs: Pick for me called the judge on the builder's route (through the builder's proxy); and on the reviewAccount
# with a Codex reviewer, where a card's judge runs on the account (RACCT is set only for a Claude reviewer, cardaccts()).
t_cardpickroute() {
  unset CLAUDE_CONFIG_DIR
  export XDG_CONFIG_HOME=$T/$CASE/config; mkdir -p "$XDG_CONFIG_HOME/conveyor" "$T/$CASE/acct1" "$T/$CASE/acct2"
  jq -cn --arg a "$T/$CASE/acct1" --arg b "$T/$CASE/acct2" '{accounts: [{name: "first", configDir: $a}, {name: "second", configDir: $b}]}' > "$XDG_CONFIG_HOME/conveyor/host.json"
  seatsetup "[$(issue 7 2026-01-01)]"
  tune '.models.claudeProxy = {baseUrl: "http://192.0.2.1:9", roles: {builder: "proxy", reviewer: "subscription"}}'
  loop control account first >/dev/null && loop control review-account second >/dev/null || fail "the accounts were not set"
  printf '%s\n' '{"builder": {"model": "m2", "effort": "high", "why": "w"}, "reviewer": {"model": "x", "effort": "low", "why": "s"}, "judge": {"model": "j", "effort": "medium", "why": "c"}}' > "$STUB/pick"
  out=$(loop control card 7 pick 2>&1) || fail "Pick for me failed: $out"
  [ "$(cat "$STUB/pick-env")" = "$T/$CASE/acct1 login" ] || fail "with a Codex reviewer, the judge was not called on the account and the review's route: $(cat "$STUB/pick-env")"
  loop control reviewer claude j2 >/dev/null && loop control judge claude j >/dev/null || fail "a Claude reviewer and judge were refused"
  out=$(loop control card 7 pick 2>&1) || fail "Pick for me failed: $out"
  [ "$(cat "$STUB/pick-env")" = "$T/$CASE/acct2 login" ] || fail "with a Claude reviewer, the judge was not called on the reviewAccount: $(cat "$STUB/pick-env")"
}

# The judge's pick of the rule Pick settings (pickjudge(), lib/modelpick.sh), called as card() calls modelpick():
# PJ prints the pick's asked, then the builder, reviewer and judge the card's steps get (seat()), one line each.
PJ='SEATCARD=$N; PICK=""; PICKCARD=""; PICKSEAT=""; PICKSEATS=""; modelpick c1-$N $N 2>/dev/null; jq -c ".asked" <<<"${PICK:-null}"
  for s in builder reviewer judge; do seat $s | jq -r "\"\(.model) \(.effort)\""; done'
pjask() { # <builder> <reviewer> <judge>: the judge's answer, each seat "<model> <effort>"
  jq -cn --arg b "$1" --arg r "$2" --arg j "$3" 'def s($x): $x | split(" ") | {model: .[0], effort: .[1], why: "w"};
    {builder: s($b), reviewer: s($r), judge: s($j)}' > "$STUB/pick"
}
# The card's price and its steps' as the Board prices them (rows(), then dashboard_limit.py cardlines, as the
# snapshot does), at the prices <prices json>: [usd, [[step, usd], ...]] in $T/$CASE/run.out.
pjusd() {
  # shellcheck disable=SC2016 # expanded in the engine shell
  fx_in 'd=$T/$CASE/priced && mkdir -p "$d" && rows "$STATE" | jq -c ".[]" > "$d/all" && jq -cn --argjson p '"'$1'"' "{prices: \$p, since: (now - 86400 | todate)}" \
    | python3 "$HERE/../.claude/scripts/dashboard_limit.py" cardlines "$d/all" "$d/kept" "$d/priced" >/dev/null && jq -c "[.usd, [.steps[] | [.step, .usd]]]" "$d/priced"'
}

# Bugs: with the rule On, the card did not build on the judge's builder, or took an effort outside its model's range
# (pick.builder.m, medium to high: the judge's low is medium), or a reviewer model the pack does not allow (zz:
# the project's x, at the judge's effort), or the pick did not say what was moved and why; or the call's tokens were
# not on the card as a step the Board prices (pjusd()); or a restarted card reused the judge's earlier answer and did
# not ask the judge again (its new answer, reviewer x2 at medium, is not used), or did not fit the new answer to the
# pack as it is now (the builder's range moved to low only: m at low).
# The judge j answers with 1,000,000 input and 500,000 output tokens, at $1 and $2 a million: $2.
t_pickjudgeon() {
  seatsetup "[$(issue 7 2026-01-01)]"
  tune '.models.allowed.claude = ["m"] | .pick = {builder: {m: {min: "medium", max: "high"}}} | .prices = {j: {input: 1, output: 2, cacheRead: 0}}'
  # The project's builder at high, so a card that does not build on the judge's (m at medium) is told apart.
  loop control rules pick=on >/dev/null && loop control model claude m high >/dev/null || fail "control rules pick=on or control model was refused"
  jq -cn --arg r '{"builder": {"model": "m", "effort": "low", "why": "w"}, "reviewer": {"model": "zz", "effort": "low", "why": "r"}, "judge": {"model": "j2", "effort": "high", "why": "j"}}' \
    '{type: "result", is_error: false, result: $r, num_turns: 1, usage: {input_tokens: 1000000, cache_creation_input_tokens: 0, cache_read_input_tokens: 0, output_tokens: 500000}}' > "$STUB/pick-json"
  fx_in "N=7; record c1-7 7 picked ok; $PJ"
  out=$(cat "$T/$CASE/run.out")
  [ "$(sed -n '2,4p' <<<"$out" | paste -sd,)" = 'm medium,x low,j2 high' ] || fail "the card's seats are not the judge's, fitted to the pack: $out"
  [ "$(head -n 1 <<<"$out" | jq -r '.builder.clamp, .reviewer.clamp, .judge.clamp // "none", .model')" \
    = $'low is not one of the efforts the builder may take on m (medium, high): m at medium\nzz is not a model the pack allows the reviewer: x at low\nnone\nj' ] \
    || fail "the pick does not name each clamp: $out"
  [ "$(st 'select(.step == "seats") | [.result, .model, .tokens.claude, .usage.output, (.pick.asked.builder.effort)] | tostring')" = '["ok","j",1500000,500000,"medium"]' ] \
    || fail "the judge's call has no seats line with its tokens: $(st 'select(.step == "seats")')"
  recok "$ST/cards.jsonl" "the judge's pick"
  pjusd '{"j": {"input": 1, "output": 2, "cacheRead": 0}}'
  [ "$(cat "$T/$CASE/run.out")" = '[2.0,[["seats",2.0]]]' ] || fail "the Board does not price the judge's call on the card: $(cat "$T/$CASE/run.out")"
  tune '.pick.builder.m = {min: "low", max: "low"}'
  rm -f "$STUB/pick-json"; pjask 'm high' 'x2 medium' 'j2 high'
  # The deps line carries the pick with the judge's builder as its choice, as a card's later lines do.
  fx_in "N=7; $PJ; record c1-7 7 deps ok"
  [ "$(sed -n '2,3p' "$T/$CASE/run.out" | paste -sd,)" = 'm low,x2 medium' ] && [ "$(wc -l < "$STUB/picks")" = 2 ] \
    || fail "the restarted card did not ask the judge again and fit its new answer to the pack as it is now: $(cat "$T/$CASE/run.out") $(wc -l < "$STUB/picks")"
  # Bug: a retry whose judge call failed kept the earlier card's choice (the judge's m low) while it built on the
  # project's builder, so the Board counted the retry under a builder it did not run on.
  tune '.pick.builder.m = {min: "medium", max: "high"}'
  echo '{"type":"result","is_error":true,"result":"overloaded","num_turns":1}' > "$STUB/pick-json"
  # Also: it kept the earlier card's judged, so the Board credited the Judge with the project's builder.
  fx_in "N=7; $PJ; jq -r '\"\(.choice.model) \(.choice.effort) \(.judged)\"' <<<\"\$PICK\""
  [ "$(sed -n '2p;5p' "$T/$CASE/run.out" | paste -sd,)" = 'm high,m high null' ] \
    || fail "the retry's failed pick kept a choice that is not the builder it runs on: $(cat "$T/$CASE/run.out")"
  # Bug: a retry in Shadow took the judge's builder as its choice (from the deps line, or its new answer at
  # medium), while it builds on the project's m at high.
  rm -f "$STUB/pick-json"; pjask 'm medium' 'x2 medium' 'j2 high'
  loop control rules pick=shadow >/dev/null || fail "control rules pick=shadow was refused"
  fx_in "N=7; $PJ; jq -c '.choice' <<<\"\$PICK\""
  [ "$(sed -n '2p;5p' "$T/$CASE/run.out" | paste -sd,)" = 'm high,{"model":"m","effort":"high"}' ] \
    || fail "the retry in Shadow does not record the builder it builds on: $(cat "$T/$CASE/run.out")"
}

# Bugs (#1067), with the rule On and pick lists for the builder (Opus 5.5 at medium to high, and m at any effort) and
# the reviewer (x at low only, x2 at high to xhigh), and none for the judge: the judge's Sonnet 5.5 at low did not
# become the chosen model nearest in price (Opus 5.5, $30 a million to Sonnet's $18, not m's $0.20 nor the project's
# m), at the nearest end of its range (medium), with both clamps in the record; the reviewer's x2 at high, inside
# x2's range though outside x's, was moved; the judge's j2 at max, with no list, was moved; or the judge was offered a
# model the lists leave out, or efforts outside a model's range.
t_pickjudgelists() {
  seatsetup "[$(issue 7 2026-01-01)]"
  tune '.models.allowed.claude += ["claude-opus-5-5", "claude-sonnet-5-5"]
    | .pick = {builder: {"claude-opus-5-5": {min: "medium", max: "high"}, m: {}}, reviewer: {x: {min: "low", max: "low"}, x2: {min: "high", max: "xhigh"}}}
    | .prices = {"claude-opus-5-5": {input: 5, output: 25, cacheRead: 0}, "claude-sonnet-5-5": {input: 3, output: 15, cacheRead: 0}, m: {input: 0.1, output: 0.1, cacheRead: 0}}'
  loop control rules pick=on >/dev/null || fail "control rules pick=on was refused"
  pjask 'claude-sonnet-5-5 low' 'x2 high' 'j2 max'
  fx_in "N=7; $PJ"
  out=$(cat "$T/$CASE/run.out")
  [ "$(sed -n '2,4p' <<<"$out" | paste -sd,)" = 'claude-opus-5-5 medium,x2 high,j2 max' ] || fail "the card's seats are not the judge's, fitted to the pick lists: $out"
  [ "$(head -n 1 <<<"$out" | jq -r '.builder.clamp, .reviewer.clamp // "none", .judge.clamp // "none"')" \
    = $'claude-sonnet-5-5 is not one of the models pick.builder lets the pick give the builder; low is not one of the efforts the builder may take on claude-opus-5-5 (medium, high): claude-opus-5-5 at medium\nnone\nnone' ] \
    || fail "the record does not name the builder's two clamps alone: $out"
  grep -qF -- '- claude-opus-5-5 (claude; efforts: medium, high;' "$STUB/pick-asked" && grep -qF -- '- x2 (codex; efforts: high, xhigh;' "$STUB/pick-asked" \
    && grep -qF -- '- j2 (claude; efforts: low, medium, high, xhigh, max;' "$STUB/pick-asked" && ! grep -q -- '^- claude-sonnet-5-5 ' "$STUB/pick-asked" \
    || fail "the judge was not given the chosen models of each seat at their ranges: $(cat "$STUB/pick-asked")"
}

# Bug (R275): the judge's price table left out the pack's price aliases, so a builder named by its alias
# (anthropic/claude-sonnet-4-6) had no price, and the clamp fell back to the first chosen model (Opus 5.5), not the
# model the alias names; and the judge's prompt gave a reviewer allowed by its alias `no price`.
t_pickjudgealias() {
  seatsetup "[$(issue 7 2026-01-01)]"
  tune '.models.allowed.claude += ["claude-opus-5-5", "claude-sonnet-4-6"] | .models.allowed."claude-reviewer" += ["anthropic/claude-sonnet-4-6"] | .pick = {builder: {"claude-opus-5-5": {}, "claude-sonnet-4-6": {}}}
    | .prices = {"claude-opus-5-5": {input: 5, output: 25, cacheRead: 0}, "claude-sonnet-4-6": {input: 3, output: 15, cacheRead: 0, aliases: ["anthropic/claude-sonnet-4-6"]}}'
  loop control rules pick=on >/dev/null || fail "control rules pick=on was refused"
  pjask 'anthropic/claude-sonnet-4-6 medium' 'x2 high' 'j2 max'
  fx_in "N=7; $PJ"
  [ "$(sed -n 2p "$T/$CASE/run.out")" = 'claude-sonnet-4-6 medium' ] \
    || fail "the judge's builder anthropic/claude-sonnet-4-6 (an alias of claude-sonnet-4-6) was not clamped to claude-sonnet-4-6: $(cat "$T/$CASE/run.out")"
  grep -qx -- '- anthropic/claude-sonnet-4-6 (claude; efforts: low, medium, high, xhigh, max; $3 input, $15 output per million tokens)' "$STUB/pick-asked" \
    || fail "the judge's prompt did not price the reviewer anthropic/claude-sonnet-4-6 as claude-sonnet-4-6: $(grep -- '^- ' "$STUB/pick-asked")"
}

# Bugs: a seat the owner set for the issue (`control card`) was moved to the judge's; a trial card left its challenger
# for the judge's builder, or did not take the judge's effort fitted to the builder's range (xhigh: high), or its
# reviewer was moved off the project's (a trial card's review stays at the defaults); or its choice took that effort,
# so the snapshot, which counts a group's trials by the challenger's model and effort, left it out. Issue 10 is in the
# trial share. Also: the pick asked the issue's judge (j2 at high) and recorded the project's (j at medium).
t_pickjudgeowner() {
  seatsetup "[$(issue 7 2026-01-01),$(issue 10 2026-01-01)]"
  tune '.models.allowed.claude += ["claude-sonnet-5-5"] | .pick = {builder: {m: {min: "medium", max: "high"}, m2: {}, "claude-sonnet-5-5": {min: "medium", max: "high"}}}'
  loop control rules pick=on >/dev/null && loop control card 7 builder m2 high >/dev/null && loop control card 7 reviewer x2 medium >/dev/null \
    && loop control card 7 judge j2 high >/dev/null || fail "control rules pick=on or control card was refused"
  pjask 'm medium' 'x low' 'j2 low'
  fx_in "N=7; $PJ"
  [ "$(sed -n '2,4p' "$T/$CASE/run.out" | paste -sd,)" = 'm2 high,x2 medium,j2 high' ] || fail "the owner's seats did not stand over the judge's: $(cat "$T/$CASE/run.out")"
  grep -q -- '--model j --effort medium ' "$STUB/picks" && [ "$(st 'select(.step == "seats") | "\(.model) \(.effort)"')" = 'j medium' ] \
    || fail "the pick did not ask the project's judge, the one its line names: $(cat "$STUB/picks") $(st 'select(.step == "seats")')"
  pjask 'm xhigh' 'x2 low' 'j2 low'
  fx_in "N=10; $PJ; jq -c '[.trial, .choice, .trialEffort]' <<<\"\$PICK\"; record c1-10 10 deps ok"
  [ "$(sed -n '2,5p' "$T/$CASE/run.out" | paste -sd,)" = 'claude-sonnet-5-5 high,x medium,j medium,[true,{"model":"claude-sonnet-5-5","effort":"medium"},"high"]' ] \
    || fail "the trial card did not keep its challenger at the judge's effort in range, with the project's review: $(cat "$T/$CASE/run.out")"
  # Bug: the blocked trial's retry, no longer a trial, kept its trialEffort, so the record check set its lines aside.
  fx_in "PICK=\$(jq -c 'select(.card == \"c1-10\") | .pick | objects' \"\$ST/cards.jsonl\" | tail -n 1); PICKCARD=c1-10; record c1-10 10 blocked failed {}
    PICK=''; PICKCARD=''; PICKSEAT=''; PICKSEATS=''; SEATCARD=10; modelpick c2-10 10 2>/dev/null; jq -c '[.trial, .trialEffort, .choice]' <<<\"\$PICK\"; seat builder | jq -r '\"\(.model) \(.effort)\"'; record c2-10 10 deps ok"
  # Bug (#1055): the retry, which builds on the default, took the judge's builder (m at high) for the project's.
  [ "$(cat "$T/$CASE/run.out")" = $'[false,null,{"model":"m","effort":"medium"}]\nm medium' ] \
    || fail "the retry of a blocked trial kept its trialEffort, or did not build on the project's builder: $(cat "$T/$CASE/run.out")"
  # Bug (#1055): the retry blocked too, so the next one's last pick was no trial and it took the judge's builder.
  fx_in "PICK=\$(jq -c 'select(.card == \"c2-10\") | .pick | objects' \"\$ST/cards.jsonl\" | tail -n 1); PICKCARD=c2-10; record c2-10 10 blocked failed {}
    PICK=''; PICKCARD=''; PICKSEAT=''; PICKSEATS=''; SEATCARD=10; modelpick c3-10 10 2>/dev/null; seat builder | jq -r '\"\(.model) \(.effort)\"'; record c3-10 10 deps ok"
  [ "$(cat "$T/$CASE/run.out")" = 'm medium' ] || fail "the second retry of a blocked trial did not build on the project's builder: $(cat "$T/$CASE/run.out")"
  recok "$ST/cards.jsonl" "a trial card's pick, and its retry's"
}

# Bugs (#1056, #1067): with a builder list of the Codex model cb alone, at minimal, issue 10's trial card built on the
# challenger (Sonnet 5.5), which the list does not name, at its own medium; it is no trial, and builds on the judge's
# Codex builder at minimal.
t_pickjudgetrialrange() {
  seatsetup "[$(issue 10 2026-01-01),$(issue 15 2026-01-01)]"
  tune '.models.allowed.claude += ["claude-sonnet-5-5"] | .models.allowed["codex-builder"] = ["cb"] | .pick = {builder: {cb: {min: "minimal", max: "minimal"}}}'
  loop control rules pick=on >/dev/null || fail "control rules pick=on was refused"
  pjask 'cb minimal' 'x medium' 'j medium'
  fx_in "N=10; $PJ; jq -c '[.trial, .choice, .trialEffort, .judged]' <<<\"\$PICK\""
  [ "$(sed -n '2p;5p' "$T/$CASE/run.out" | paste -sd,)" = 'cb minimal,[false,{"model":"cb","effort":"minimal"},null,true]' ] \
    || fail "the trial card built outside the builder's effort range: $(cat "$T/$CASE/run.out")"
  # Bug: with Sonnet 5.5 in the list at high only, a judge that failed (here, an answer with no model, which
  # leaves pickjudge() as a timeout does) left issue 15's trial card at the challenger's medium.
  tune '.pick = {builder: {"claude-sonnet-5-5": {min: "high", max: "high"}}}'
  printf '%s\n' '{"builder": {"model": null, "effort": "low"}}' > "$STUB/pick"
  fx_in "N=15; $PJ; jq -c '[.trial, .choice, .trialEffort]' <<<\"\$PICK\""
  [ "$(sed -n '2p;5p' "$T/$CASE/run.out" | paste -sd,)" = 'claude-sonnet-5-5 high,[true,{"model":"claude-sonnet-5-5","effort":"medium"},"high"]' ] \
    && jq -e .failed <<<"$(head -n 1 "$T/$CASE/run.out")" >/dev/null \
    || fail "the trial card of a failed judge built outside the builder's effort range: $(cat "$T/$CASE/run.out")"
}

# Bug (#1055): with the rule On, the card in the share of a promoted group (issue 15, 1 in 5), which the snapshot's
# cost check compares with the promoted cards, built on the judge's builder (m2 high), not the project's (m medium).
t_pickjudgeshare() {
  seatsetup "[$(issue 15 2026-01-01)]"
  loop control rules pick=on >/dev/null && loop control pick small code promote >/dev/null || fail "control rules pick=on or control pick was refused"
  pjask 'm2 high' 'x2 low' 'j2 low'
  # judged (null): the Board credits the Judge with a builder only when the pick says the card took it, or its choice
  # is the Judge's builder (seatsof()); this choice is not.
  fx_in "N=15; $PJ; jq -c '[.group, .trial, .promoted, .choice, .judged]' <<<\"\$PICK\""
  [ "$(sed -n '2,5p' "$T/$CASE/run.out" | paste -sd,)" = 'm medium,x2 low,j2 low,["small code",false,null,{"model":"m","effort":"medium"},null]' ] \
    || fail "the promoted group's card in the share did not build on the project's builder: $(cat "$T/$CASE/run.out")"
}

# Bugs: with Shadow the judge's pick was not recorded, or moved a seat; with Off the judge was asked. Also: a seat with
# no pick list did not take every effort its model's program takes (the judge's max is kept, no clamp).
t_pickjudgeshadow() {
  seatsetup "[$(issue 7 2026-01-01),$(issue 8 2026-01-01)]"
  loop control rules pick=shadow >/dev/null || fail "control rules pick=shadow was refused"
  pjask 'm2 high' 'x2 low' 'j2 max'
  fx_in "N=7; $PJ"
  [ "$(head -n 1 "$T/$CASE/run.out" | jq -r '[.builder, .reviewer, .judge] | map("\(.model) \(.effort) \(.clamp // "")") | join(",")')" = 'm2 high ,x2 low ,j2 max ' ] \
    || fail "the judge's pick is not recorded in Shadow: $(cat "$T/$CASE/run.out")"
  [ "$(sed -n '2,4p' "$T/$CASE/run.out" | paste -sd,)" = 'm medium,x medium,j medium' ] || fail "Shadow moved the card off the project's seats: $(cat "$T/$CASE/run.out")"
  loop control rules pick=off >/dev/null || fail "control rules pick=off was refused"
  fx_in "N=8; $PJ"
  [ "$(wc -l < "$STUB/picks")" = 1 ] && [ "$(head -n 1 "$T/$CASE/run.out")" = null ] || fail "with Off the judge was asked: $(cat "$STUB/picks")"
}

# Bugs: a judge that failed, timed out or named no model (or only blank ones) blocked the card or moved a seat, or
# left no reason. Each
# answer is asked again for the same issue: a failed pick is asked again, not reused.
t_pickjudgefail() {
  seatsetup "[$(issue 7 2026-01-01)]"
  loop control rules pick=on >/dev/null || fail "control rules pick=on was refused"
  echo '{"type":"result","is_error":true,"result":"overloaded","num_turns":1}' > "$STUB/pick-json"
  fx_in "N=7; $PJ"
  out=$(cat "$T/$CASE/run.out"); rm -f "$STUB/pick-json"
  pjask 'm2 high' 'x2 low' 'j2 low'; echo 3 > "$STUB/pick-delay"
  fx_in "N=7; PICK_TIMEOUT=1; $PJ"
  out+=$'\n'$(cat "$T/$CASE/run.out"); rm -f "$STUB/pick-delay"
  # A blank model name is no model: it once kept the project's builder and moved it to the answer's low effort.
  echo '{"builder": {"model": "", "effort": "low"}, "reviewer": "fast", "judge": {"model": " ", "effort": "high"}}' > "$STUB/pick"
  fx_in "N=7; $PJ"
  out+=$'\n'$(cat "$T/$CASE/run.out")
  [ "$(grep -c -x 'm medium\|x medium\|j medium' <<<"$out")" = 9 ] || fail "a failed pick moved a seat off the project's: $out"
  [ "$(grep '^{' <<<"$out" | jq -r .failed)" = "the judge (j) did not answer: the judge sent back an error (exit 0, 1 turn): overloaded; no error output
the judge (j) did not answer: exit 124; 124 is the 1s timeout
the judge's answer named no model for any seat: {\"builder\":{\"model\":null,\"effort\":\"low\",\"why\":null},\"reviewer\":null,\"judge\":{\"model\":null,\"effort\":\"high\",\"why\":null}}" ] || fail "a failed pick does not say why: $out"
  [ "$(st 'select(.step == "seats") | .result' | sort -u)" = failed ] || fail "the failed calls have no failed seats line: $(st 'select(.step == "seats")')"
  recok "$ST/cards.jsonl" "a failed pick"
}

# Bug: with a Codex reviewer, pick read the guard on the builder's account alone; a judge that picked a Claude
# reviewer (j2) moved the card's review onto the reviewAccount, which is at the weekly limit guard (95 over 90).
t_pickjudgeguard() {
  export XDG_CONFIG_HOME=$T/$CASE/config; mkdir -p "$XDG_CONFIG_HOME/conveyor" "$T/$CASE/acct1" "$T/$CASE/acct2"
  jq -cn --arg a "$T/$CASE/acct1" --arg b "$T/$CASE/acct2" '{accounts: [{name: "first", configDir: $a}, {name: "second", configDir: $b}]}' > "$XDG_CONFIG_HOME/conveyor/host.json"
  seatsetup "[$(issue 7 2026-01-01)]"
  loop control rules pick=on >/dev/null && loop control account first >/dev/null && loop control review-account second >/dev/null && loop control guard 90 >/dev/null \
    || fail "control rules, account or guard was refused"
  jq -cn '{time: (now | todate), pct: 95, account: "second"}' >> "$ST/limit.jsonl"
  pjask 'm2 high' 'j2 low' 'j2 low'
  fx_in "N=7; $PJ; record c1-7 7 deps ok"
  [ "$(sed -n '2,4p' "$T/$CASE/run.out" | paste -sd,)" = 'm medium,x medium,j medium' ] && head -n 1 "$T/$CASE/run.out" | jq -e '.guard | test("weekly limit guard")' >/dev/null \
    || fail "the judge's seats moved the card onto an account at the guard, or the pick does not say why not: $(cat "$T/$CASE/run.out")"
  recok "$ST/cards.jsonl" "a pick held by the guard"
}

# Bug (R243): a card's seat was checked against the host's saved CLI report alone, so a Codex model Codex took on since
# that (fresh) report was refused until `conveyor.sh clis` ran. Codex is read afresh first. The saved report has px
# false: with no px, hostclis() reads Codex again on any read, and the case would pass without the refresh.
t_cardseatfresh() {
  seatsetup "[$(issue 7 2026-01-01)]"
  jq -cn '{at: (now | floor), clis: {codex: ["x", "x2"]}, px: false}' > "$ST/clis.json"
  export CODEX_HOME=$T/$CASE/codex; mkdir -p "$CODEX_HOME" && echo '{"models":[{"slug":"gpt-new","visibility":"list"}]}' > "$CODEX_HOME/models_cache.json"
  out=$(loop control card 7 reviewer gpt-new 2>&1) && [ "$(jq -c '.cards["7"]' <<<"$out")" = '{"reviewer":{"model":"gpt-new"}}' ] \
    || fail "control card 7 reviewer gpt-new, with Codex listing gpt-new and the saved report not, was refused: $out"
  # Bug (E13): a builder seat waited for the Codex refresh too, though the builder's Codex list (codex-builder) is not
  # the one it refreshes. The saved report is left as it was.
  jq -cn '{at: (now | floor), clis: {codex: ["x", "x2"]}, px: false}' > "$ST/clis.json"; cp "$ST/clis.json" "$T/$CASE/clis.before"
  out=$(loop control card 7 builder m2 2>&1) && cmp -s "$ST/clis.json" "$T/$CASE/clis.before" \
    || fail "control card 7 builder m2 refreshed the saved Codex report or was refused: $out; the report: $(cat "$ST/clis.json")"
  # Pick for me reads Codex afresh too: the judge's reviewer gpt-new is taken, with the saved report made stale again.
  jq -cn '{at: (now | floor), clis: {codex: ["x", "x2"]}, px: false}' > "$ST/clis.json"
  printf '%s\n' '{"builder": {"model": "m2", "effort": "high", "why": "w"}, "reviewer": {"model": "gpt-new", "effort": "low", "why": "s"},' \
    '"judge": {"model": "j", "effort": "medium", "why": "c"}}' > "$STUB/pick"
  out=$(loop control card 7 pick 2>&1) && [ "$(jq -r .reviewer.model <<<"$out")" = gpt-new ] \
    || fail "control card 7 pick, with the judge choosing reviewer gpt-new, Codex listing it and the saved report not, was refused: $out"
}

# Bug: a Codex judge's call was recorded with no tokens (its output went unread), so the card had no price. Its
# events give 1,000,000 input and 500,000 output tokens, at $1 and $2 a million: $2. Also: a judge set by its family
# name (sol) was recorded as sol, which has no price, not as the model id it ran on (gpt-6.2-sol).
t_pickjudgecodex() {
  seatsetup "[$(issue 7 2026-01-01)]"
  export CODEX_HOME=$T/$CASE/codex; mkdir -p "$CODEX_HOME" && echo '{"models":[{"slug":"gpt-6.2-sol","visibility":"list"}]}' > "$CODEX_HOME/models_cache.json"
  tune '.models.allowed.codex += ["sol"]'
  jq -c '.judge = {cli: "codex", model: "sol", effort: "low"}' "$ST/control.json" > "$STUB/c.new" && mv "$STUB/c.new" "$ST/control.json"
  loop control rules pick=shadow >/dev/null || fail "control rules pick=shadow was refused"
  pjask 'm2 high' 'x2 low' 'j2 low'; cp "$STUB/pick" "$STUB/codex-answer"
  echo '{"type":"turn.completed","usage":{"input_tokens":1000000,"cached_input_tokens":0,"output_tokens":500000}}' > "$STUB/codex-usage"
  fx_in "N=7; record c1-7 7 picked ok; $PJ"
  [ "$(st 'select(.step == "seats") | [.result, .model, .tokens.codex, .usage.output] | tostring')" = '["ok","gpt-6.2-sol",1500000,500000]' ] \
    || fail "the Codex judge's call has no seats line with its tokens and its model id: $(st 'select(.step == "seats")') $(cat "$T/$CASE/run.out")"
  pjusd '{"gpt-6.2-sol": {"input": 1, "output": 2, "cacheRead": 0}}'
  [ "$(cat "$T/$CASE/run.out")" = '[2.0,[["seats",2.0]]]' ] || fail "the Board does not price the Codex judge's call on the card: $(cat "$T/$CASE/run.out")"
}

# Issue 1059. Bug: a Codex judge that timed out (124) before its turn completed was recorded with no tokens, though
# the session file Codex keeps held its running total (1,000,000 input, 400,000 of them cached, and 50,000 output),
# so the card had no price. The file is kept, as the Board reads Codex's session files for its usage reading and
# weekly API spend.
t_pickjudgecodexcut() {
  seatsetup "[$(issue 7 2026-01-01)]"
  export CODEX_HOME=$T/$CASE/codex; mkdir -p "$CODEX_HOME/sessions/d"
  jq -c '.judge = {cli: "codex", model: "x", effort: "low"}' "$ST/control.json" > "$STUB/c.new" && mv "$STUB/c.new" "$ST/control.json"
  loop control rules pick=shadow >/dev/null || fail "control rules pick=shadow was refused"
  pjask 'm2 high' 'x2 low' 'j2 low'; cp "$STUB/pick" "$STUB/codex-answer"; echo 124 > "$STUB/codex-rc"
  echo '{"type":"thread.started","thread_id":"th1"}' > "$STUB/codex-usage"
  echo '{"type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":1000000,"cached_input_tokens":400000,"output_tokens":50000}}}}' \
    > "$CODEX_HOME/sessions/d/rollout-1-th1.jsonl"
  fx_in "N=7; record c1-7 7 picked ok; $PJ"
  [ "$(st 'select(.step == "seats") | [.result, .tokens.codex, .usage.input, .usage.read, .usage.output] | tostring')" = '["failed",650000,600000,400000,50000]' ] \
    || fail "the timed-out Codex judge's call has no tokens from its session file: $(st 'select(.step == "seats")') $(cat "$T/$CASE/run.out")"
  [ -s "$CODEX_HOME/sessions/d/rollout-1-th1.jsonl" ] || fail "the judge's session file was removed, so the Board's usage reading and API spend miss the call"
}

# Bug: an OpenCode judge's call was recorded with no tokens and no cost (its events went unread), so the card had no
# price. The shared stub's step costs $0.01, as OpenCode prices it.
t_pickjudgeoc() {
  seatsetup "[$(issue 7 2026-01-01)]"
  tune '.models.allowed.opencode = ["opencode:prov/mod-1"]'
  jq -c '.judge = {cli: "opencode", model: "opencode:prov/mod-1", effort: "high"}' "$ST/control.json" > "$STUB/c.new" && mv "$STUB/c.new" "$ST/control.json"
  loop control rules pick=shadow >/dev/null || fail "control rules pick=shadow was refused"
  pjask 'm2 high' 'x2 low' 'j2 low'; cp "$STUB/pick" "$STUB/opencode-answer"
  fx_in "N=7; record c1-7 7 picked ok; $PJ"
  [ "$(st 'select(.step == "seats") | [.result, .tokens.claude, .usage.cost] | tostring')" = '["ok",170,0.01]' ] \
    || fail "the OpenCode judge's call has no seats line with its tokens and cost: $(st 'select(.step == "seats")') $(cat "$T/$CASE/run.out")"
  pjusd '{}'
  [ "$(cat "$T/$CASE/run.out")" = '[0.01,[["seats",0.01]]]' ] || fail "the Board does not price the OpenCode judge's call on the card: $(cat "$T/$CASE/run.out")"
}
