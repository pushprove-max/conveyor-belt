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
# is Pick for me, once $STUB/pick is there (before, it is a card run's same-file check, answered NONE): its prompt is kept in $STUB/pick-asked, its account folder and route in $STUB/pick-env, and its answer is $STUB/pick; any other is a session.
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
  *"--tools  "*) [ -f "$STUB/pick" ] || { cat > /dev/null; echo NONE; exit; } # a same-file check of a card run (overlapcall())
    cat > "$STUB/pick-asked"; echo "$*" >> "$STUB/picks"; echo "${CLAUDE_CONFIG_DIR:-default} ${ANTHROPIC_BASE_URL:-login}" > "$STUB/pick-env"; cat "$STUB/pick"; exit ;;
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

# Bugs: Pick for me with an OpenCode judge failed, as the control command had not loaded the OpenCode runner (ocrun);
# and it refused every answer for an OpenCode builder, which takes no effort, as an effort was required of each seat.
t_cardpickoc() {
  seatsetup "[$(issue 7 2026-01-01)]"
  tune '.models.allowed.opencode = ["opencode:prov/mod-1"]'
  jq -c '.judge = {cli: "opencode", model: "opencode:prov/mod-1", effort: "high"}' "$ST/control.json" > "$STUB/c.new" && mv "$STUB/c.new" "$ST/control.json"
  jq -cn '{type: "text", part: {type: "text", text: "{\"builder\": {\"model\": \"opencode:prov/mod-1\", \"effort\": null, \"why\": \"cheap\"}, \"reviewer\": {\"model\": \"x\", \"effort\": \"low\", \"why\": \"small\"}, \"judge\": {\"model\": \"j\", \"effort\": \"medium\", \"why\": \"fine\"}}"}}' > "$STUB/oc-answer"
  printf '%s\n' '#!/usr/bin/env bash' 'cat > "$STUB/oc-asked"; echo "$*" > "$STUB/oc-run"; cat "$STUB/oc-answer"' > "$STUB/opencode"; chmod +x "$STUB/opencode"
  out=$(loop control card 7 pick 2>&1) || fail "Pick for me with an OpenCode judge failed: $out"
  [ "$(jq -c '[.builder.effort, .model]' <<<"$out")" = '[null,"opencode:prov/mod-1"]' ] || fail "the pick of an OpenCode builder: $out"
  grep -q -- '-m prov/mod-1 --variant high' "$STUB/oc-run" && grep -qx 'body of 7' "$STUB/oc-asked" || fail "OpenCode was not asked as the judge: $(cat "$STUB/oc-run")"
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
