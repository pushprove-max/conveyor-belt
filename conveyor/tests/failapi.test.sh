#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 300
# Engine cases: sessions and reviews the model API refused, and the loop that waits while the API error is fresh.
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"
# The engine folder, as lib.sh sets it: named here too, so the release closure (tools/closure.sh) follows this file's paths.
SRC=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)

# Bug: a session the model API refused (a Cloudflare 403 challenge on every request for some minutes) blocked its card
# as "session failed (exit 1)": four cards in three minutes, each retried by hand once the API answered again.
# $STUB/refuse holds how many sessions the API still refuses: each ends as Claude Code ends one then.
refusing() { # <sessions refused>
  echo "$1" > "$STUB/refuse"; echo "Failed to authenticate. API Error: 403 Attention Required! | Cloudflare" > "$STUB/refusal"
  cat > "$STUB/build" <<'EOT'
date +%s.%N >> "$STUB/calls"; n=$(cat "$STUB/refuse")
[ "$n" -le 0 ] || { echo $((n - 1)) > "$STUB/refuse"
  jq -cn --rawfile r "$STUB/refusal" '{type: "result", is_error: true, result: ($r | rtrimstr("\n")), usage: {input_tokens: 3, cache_creation_input_tokens: 0, cache_read_input_tokens: 0, output_tokens: 1}}'; exit 1; }
echo two >> a.txt
EOT
}
t_apierror() {
  setup "[$(issue 7 2026-01-01)]"; printf '%s\n' "$GO" > "$STUB/review.1"; refusing 1; tune '.tunables.apiPause = 1 | .tunables.poll = 1'
  # While the card waits, its live record says why and when it tries again: kept here as it stood then.
  ( while [ -d "$STUB" ] && [ ! -e "$STUB/waitlive" ]; do jq -e '.action // "" | startswith("waiting")' "$T/$CASE"/cards/*-7.live >/dev/null 2>&1 && cp "$T/$CASE"/cards/*-7.live "$STUB/waitlive"; sleep 0.1; done ) >/dev/null 2>&1 &
  out=$(loop run 2>&1) || fail "run exited non-zero: $out"
  # Refused once: the same session ran again, and the card is built and landed, never blocked.
  [ "$(st 'select(.step | IN("blocked", "landed")) | .step')" = landed ] && [ "$(wc -l < "$STUB/calls")" = 2 ] && grep -qx two "$R/a.txt" \
    || fail "a session the API refused once did not run again and land its card: $(st '[.step, .reason] | join(" ")' | tr '\n' ,)"
  jq -e '.step == "build" and (.action | test("^waiting: the model API refused \\(403 Cloudflare\\); trying again at [0-2][0-9]:[0-5][0-9]$"))' "$STUB/waitlive" >/dev/null \
    || fail "the waiting card's live record does not say what it waits for and until when: $(cat "$STUB/waitlive" 2>&1)"
  # What the refused try used is on the build's line with the try that worked (4 and 35 tokens).
  [ "$(st 'select(.step == "build") | [.tokens.claude, .usage.input, .usage.output] | join(" ")')" = "39 13 6" ] || fail "the refused try's tokens are not on the build line: $(st 'select(.step == "build")')"
  # Refused at every try: the card blocks after the fifth, naming the error, with the API's own words under it.
  echo "[$(issue 8 2026-01-01)]" > "$STUB/issues.json"; refusing 99; : > "$STUB/calls"; tune '.tunables.apiPause = 0.1'
  loop run >/dev/null 2>&1
  [ "$(wc -l < "$STUB/calls")" = 5 ] || fail "a session the API kept refusing ran $(wc -l < "$STUB/calls") times, not 5"
  st 'select(.issue == 8 and .step == "blocked") | .reason' | grep -q '^build: the model API refused (403 Cloudflare) at each of 5 tries' \
    || fail "the card the API kept refusing is not blocked naming the error: $(st 'select(.issue == 8) | [.step, .reason] | join(" ")' | tr '\n' ,)"
  st 'select(.issue == 8 and .step == "blocked") | .tail' | grep -q 'API Error: 403 Attention Required! | Cloudflare' || fail "the blocked line lost the API's own words: $(st 'select(.issue == 8 and .step == "blocked") | .tail')"
  [ "$(st 'select(.issue == 8 and .step == "blocked") | .spent.tokens.claude')" = 20 ] || fail "the five refused tries' tokens are not on the blocked line: $(st 'select(.issue == 8 and .step == "blocked") | .spent')"
}
# Which words of a failed session are an API-side error, read as the engine reads them (session.sh's APIERROR, on the
# session's output and stderr): an error it names is retried as t_apierror's 403 is (and t_apicodexrefused's 429), and
# one it does not name fails the card at once as any failed session does (t_fail). No card run is needed for the words.
apiread() { # <codex: true or false> <the session's output> [its stderr]
  # shellcheck disable=SC2034 # APISAID is read where the eval'd APIERROR is built from it
  local APISAID APIERROR; eval "$(sed -n "/^APISAID='/,/^APIERR=/p" "$SRC/lib/session.sh" | sed '$d')"
  [ -n "$APIERROR" ] || fail "session.sh no longer defines APIERROR where this case reads it"
  jq -rRn --argjson codex "$1" --rawfile e <(printf '%s' "${3:-}") "$APIERROR" <<<"$2"
}
claudesaid() { jq -cn --arg r "$1" '{type: "result", is_error: true, result: $r}'; } # <result>
t_apiwords() {
  [ "$(apiread false "$(claudesaid 'Failed to authenticate. API Error: 403 Attention Required! | Cloudflare')")" = "403 Cloudflare" ] \
    || fail "the Cloudflare 403 is no longer read as an API error, so this case's other answers prove nothing"
  # A failure that is the card's own is still one: an error result that names no API-side error blocks at once.
  [ -z "$(apiread false "$(claudesaid 'API Error: 403 forbidden: this account may not use the model')")" ] || fail "a 403 that is no Cloudflare challenge was read as an API error"
  # Bug: a failed result that names an HTTP status in the card's own words (a failing test's) was read as an outage:
  # five sessions, and a queue paused for nothing. Only the words "API Error" before the status make it the API's.
  [ -z "$(apiread false "$(claudesaid 'Test failed: expected status 500, got 200')")" ] || fail "a status named in the card's own words was read as an API error"
  # Bug: a connection reset or an overloaded result that does not start with the words "API Error" blocked at once.
  # Each is an API-side error as the 403 is, so the session runs again.
  [ "$(apiread false "$(claudesaid 'Connection reset (ECONNRESET)')")" = "connection reset" ] || fail "a connection reset was not read as an API error"
  [ "$(apiread false "$(claudesaid 'Overloaded')")" = overloaded ] || fail "an overloaded result was not read as an API error"
  # Bug: a refusal Codex prints in plain words, no JSON event, was read as no API error: the review ran again once
  # only, as one without a verdict, and marked nothing.
  [ "$(apiread true 'API Error: 429')" = 429 ] || fail "a Codex refusal in plain words was not read as an API error"
}
# One outage must not burn through the queue: while a session's API error is fresh (5 times apiPause), the loop picks
# no card. Two issues, one builder: the first card is refused once and lands; the second card's session starts only
# once the error is no longer fresh, though the builder was free before that.
t_apifresh() {
  setup "[$(issue 7 2026-01-01),$(issue 8 2026-01-02)]"; printf '%s\n' "$GO" > "$STUB/review.1"; printf '%s\n' "$GO" > "$STUB/review.2"; refusing 1
  loop control cap 1 >/dev/null; tune '.tunables.apiPause = 2 | .tunables.poll = 1'
  out=$(loop run 2>&1) || fail "run exited non-zero: $out"
  [ "$(st 'select(.step | IN("blocked", "landed")) | "\(.issue) \(.step)"' | tr '\n' ,)" = "7 landed,8 landed," ] || fail "the two cards did not land: $(st '[.issue, .step, .reason] | join(" ")' | tr '\n' ,)"
  # The sessions: #7 refused, #7 again, #8. The error was fresh until the time in the state folder's apierror.
  [ "$(wc -l < "$STUB/calls")" = 3 ] || fail "$(wc -l < "$STUB/calls") sessions ran, not 3"
  jq -en --argjson s "$(sed -n 3p "$STUB/calls")" --argjson first "$(sed -n 1p "$STUB/calls")" --slurpfile u "$ST/apierror" '$u[0] >= $first + 10 and $s >= $u[0]' >/dev/null \
    || fail "a new card started a session while the API error was fresh: refused at $(sed -n 1p "$STUB/calls"), fresh until $(cat "$ST/apierror"), next card's session at $(sed -n 3p "$STUB/calls")"
}
# Bug: only the pick was held, so a card picked before the outage started its session into it: the first review here
# marks an API error fresh for 3 s (as another card's refused session does) and asks for a fix; the fix session
# starts only once the error is no longer fresh, the card's live record saying meanwhile what it waits for.
t_apihold() {
  setup "[$(issue 7 2026-01-01)]"; printf '%s\n' "$NOGO" > "$STUB/review.1"; printf '%s\n' "$GO" > "$STUB/review.2"
  # shellcheck disable=SC2016
  echo 'date +%s.%N >> "$STUB/calls"; echo two >> a.txt' > "$STUB/build"
  # shellcheck disable=SC2016
  echo '[ -e "$STUB/marked" ] || { jq -n "now + 3" > "$STUB/marked"; cp "$STUB/marked" "$ST/apierror"; }' > "$STUB/review-cmd"
  ( while [ -d "$STUB" ] && [ ! -e "$STUB/waitlive" ]; do jq -e '.action // "" | startswith("waiting")' "$T/$CASE"/cards/*-7.live >/dev/null 2>&1 && cp "$T/$CASE"/cards/*-7.live "$STUB/waitlive"; sleep 0.1; done ) >/dev/null 2>&1 &
  out=$(loop run 2>&1) || fail "run exited non-zero: $out"
  [ "$(st 'select(.step | IN("blocked", "landed")) | .step')" = landed ] && [ "$(wc -l < "$STUB/calls")" = 2 ] || fail "the card did not land after one fix: $(st '[.step, .reason] | join(" ")' | tr '\n' ,)"
  jq -en --argjson s "$(sed -n 2p "$STUB/calls")" --slurpfile u "$STUB/marked" '$s >= $u[0]' >/dev/null \
    || fail "a card picked before the API error started a session while it was fresh: fresh until $(cat "$STUB/marked"), its fix session at $(sed -n 2p "$STUB/calls")"
  jq -e '.step == "fix" and (.action | test("^waiting: the model API refused a session; starting at [0-2][0-9]:[0-5][0-9]$"))' "$STUB/waitlive" >/dev/null \
    || fail "the held card's live record does not say what it waits for and until when: $(cat "$STUB/waitlive" 2>&1)"
}
# Bug: a Codex review started while an API error was fresh: only Claude sessions were held. The build here marks an API
# error fresh for 3 s; the Codex review after it starts only once the error is no longer fresh, the card's live record
# saying meanwhile what it waits for.
t_apicodex() {
  setup "[$(issue 7 2026-01-01)]"; printf '%s\n' "$GO" > "$STUB/review.1"
  # shellcheck disable=SC2016
  echo 'jq -n "now + 3" > "$STUB/marked"; cp "$STUB/marked" "$ST/apierror"; echo two >> a.txt' > "$STUB/build"
  # shellcheck disable=SC2016
  echo 'date +%s.%N >> "$STUB/rcalls"' > "$STUB/review-cmd"
  ( while [ -d "$STUB" ] && [ ! -e "$STUB/waitlive" ]; do jq -e '.action // "" | startswith("waiting")' "$T/$CASE"/cards/*-7.live >/dev/null 2>&1 && cp "$T/$CASE"/cards/*-7.live "$STUB/waitlive"; sleep 0.1; done ) >/dev/null 2>&1 &
  out=$(loop run 2>&1) || fail "run exited non-zero: $out"
  [ "$(st 'select(.step | IN("blocked", "landed")) | .step')" = landed ] && [ "$(wc -l < "$STUB/rcalls")" = 1 ] || fail "the card did not land after one review: $(st '[.step, .reason] | join(" ")' | tr '\n' ,)"
  jq -en --argjson s "$(sed -n 1p "$STUB/rcalls")" --slurpfile u "$STUB/marked" '$s >= $u[0]' >/dev/null \
    || fail "a Codex review started while the API error was fresh: fresh until $(cat "$STUB/marked"), the review at $(sed -n 1p "$STUB/rcalls")"
  jq -e '.step == "review" and (.action | test("^waiting: the model API refused a session; starting at [0-2][0-9]:[0-5][0-9]$"))' "$STUB/waitlive" >/dev/null \
    || fail "the held review's live record does not say what it waits for and until when: $(cat "$STUB/waitlive" 2>&1)"
}
# Bug: a Codex review the API refused (429 at every try) was run again once only, as a review without a verdict is,
# then blocked its card, and marked no API error, so the loop went on picking cards into the outage. It is an API-side
# error as a Claude session's is: the same review runs again, up to 5 tries, and each refusal is marked fresh.
t_apicodexrefused() {
  # A turn every second: while the API error is fresh the loop starts no card and waits out a whole turn (30 s by default).
  setup "[$(issue 7 2026-01-01)]"; printf '%s\n' "$GO" > "$STUB/review.3"; echo 2 > "$STUB/refuse"; tune '.tunables.apiPause = 0.1 | .tunables.poll = 1'
  # shellcheck disable=SC2016
  echo 'n=$(cat "$STUB/refuse"); [ "$n" -le 0 ] || { echo $((n - 1)) > "$STUB/refuse"; cp "$ST/apierror" "$STUB/marked.$n" 2>/dev/null
    echo "{\"type\":\"turn.completed\",\"usage\":{\"input_tokens\":100,\"cached_input_tokens\":60,\"output_tokens\":7}}"
    echo "{\"type\":\"error\",\"message\":\"${REFUSAL:-API Error: 429 Too Many Requests}\"}"; exit 1; }' > "$STUB/review-cmd"
  out=$(loop run 2>&1) || fail "run exited non-zero: $out"
  [ "$(st 'select(.step | IN("blocked", "landed")) | .step')" = landed ] && [ "$(wc -l < "$STUB/reviews")" = 3 ] \
    || fail "a Codex review the API refused twice did not run a third time and land its card: $(wc -l < "$STUB/reviews") reviews, $(st '[.step, .reason] | join(" ")' | tr '\n' ,)"
  # The first refusal marked the error fresh (the second try saw the mark), so no other card starts into the outage.
  jq -e numbers "$STUB/marked.1" >/dev/null 2>&1 && [ ! -e "$STUB/marked.2" ] || fail "a refused Codex review did not mark the API error: $(ls "$STUB")"
  # One review line, GO, with the refused tries' tokens (47 each) and no first attempt: it was never a review without a verdict.
  [ "$(st 'select(.step == "review") | [.result, .tokens.codex, .firstTry] | tojson')" = '["GO",141,null]' ] \
    || fail "the review line lost the refused tries' tokens, or holds a first attempt: $(st 'select(.step == "review")')"
  # Refused at every try, in Codex's own words for it: the card blocks after the fifth, naming the error.
  echo "[$(issue 8 2026-01-01)]" > "$STUB/issues.json"; echo 99 > "$STUB/refuse"; : > "$STUB/reviews"
  REFUSAL='exceeded retry limit, last status: 429 Too Many Requests' loop run >/dev/null 2>&1
  [ "$(wc -l < "$STUB/reviews")" = 5 ] || fail "a Codex review the API kept refusing ran $(wc -l < "$STUB/reviews") times, not 5"
  st 'select(.issue == 8 and .step == "blocked") | .reason' | grep -q 'the model API refused (429) at each of 5 tries' \
    || fail "the card whose review the API kept refusing is not blocked naming the error: $(st 'select(.issue == 8) | [.step, .reason] | join(" ")' | tr '\n' ,)"
  [ "$(st 'select(.issue == 8 and .step == "blocked") | .spent.tokens.codex')" = 235 ] || fail "the five refused tries' tokens are not on the blocked line: $(st 'select(.issue == 8 and .step == "blocked") | .spent')"
  # A review that wrote its NO-GO before the API refused it answered: run again, a GO could replace that NO-GO.
  echo "[$(issue 9 2026-01-01)]" > "$STUB/issues.json"; : > "$STUB/reviews"; printf '%s\n' "$NOGO" > "$STUB/review.1"; printf '%s\n' "$GO" > "$STUB/review.2"
  echo 'cat "$STUB/review.1" > "$out"; echo "{\"type\":\"error\",\"message\":\"API Error: 429 Too Many Requests\"}"; exit 1' > "$STUB/review-cmd"
  rm -f "$ST/apierror"; loop run >/dev/null 2>&1
  [ "$(wc -l < "$STUB/reviews")" = 1 ] && st 'select(.issue == 9 and .step == "blocked") | .reason' | grep -q '^review 1: review failed (exit 1)' \
    || fail "a Codex review that wrote a verdict and was then refused by the API was run again: $(wc -l < "$STUB/reviews") reviews, $(st 'select(.issue == 9) | [.step, .reason] | join(" ")' | tr '\n' ,)"
  # Bug: that review, kept as answered, marked no API error either, so the queue went on into the outage it met.
  jq -e numbers "$ST/apierror" >/dev/null 2>&1 || fail "a Codex review refused by the API after its verdict did not mark the API error"
  # A refusal Codex prints in plain words is read as one (t_apiwords).
  # Bug: a refusal Codex wrote to stderr alone, its stream empty, was read as no API error either. Refused so at every
  # try, the review runs 5 times and its card blocks naming the error, with the words stderr held.
  echo "[$(issue 11 2026-01-01)]" > "$STUB/issues.json"; : > "$STUB/reviews"; rm -f "$ST/apierror"
  echo 'echo "API Error: 429" >&2; exit 1' > "$STUB/review-cmd"
  loop run >/dev/null 2>&1
  [ "$(wc -l < "$STUB/reviews")" = 5 ] && jq -e numbers "$ST/apierror" >/dev/null 2>&1 || fail "a Codex review refused on stderr ran $(wc -l < "$STUB/reviews") times, not 5, or marked no API error"
  st 'select(.issue == 11 and .step == "blocked") | .reason + "\n" + (.tail // "")' | tr '\n' ' ' | grep -q 'the model API refused (429) at each of 5 tries.*API Error: 429' \
    || fail "the card whose review stderr said the API refused is not blocked naming the error: $(st 'select(.issue == 11) | [.step, .reason] | join(" ")' | tr '\n' ,)"
}
# Bug: a Claude review the API refused was run again once only, as a review without a verdict is, then blocked its
# card; and a refused try whose usage could not be read left a line that looked whole, so part of a step was priced as
# all of it. The review here is refused twice (the first with no usage), then answers GO.
t_apireview() {
  setup "[$(issue 7 2026-01-01)]"; tune --slurpfile real "$SRC/lib/test-pack.json" '.models.allowed = $real[0].models.allowed | .models.allowed.claude += ["m"] | .tunables.apiPause = 0.1'
  loop control reviewer claude claude-opus-5-5 >/dev/null || fail "a Claude reviewer was not set"
  cat > "$STUB/claude" <<'EOF'
#!/usr/bin/env bash
case " $* " in *" --tools "*) ;; *) cat > /dev/null; echo two >> a.txt
  echo '{"type":"result","is_error":false,"usage":{"input_tokens":10,"cache_creation_input_tokens":20,"cache_read_input_tokens":999,"output_tokens":5}}'; exit 0 ;; esac
cat > /dev/null; echo x >> "$STUB/reviews"
case $(wc -l < "$STUB/reviews") in
  1) echo '{"type":"result","is_error":true,"result":"Failed to authenticate. API Error: 403 Attention Required! | Cloudflare"}'; exit 1 ;;
  2) echo '{"type":"result","is_error":true,"result":"Failed to authenticate. API Error: 403 Attention Required! | Cloudflare","usage":{"input_tokens":3,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"output_tokens":1}}'; exit 1 ;;
esac
jq -cn --arg r "$GO" '{type: "result", is_error: false, result: $r, num_turns: 2, usage: {input_tokens: 100, cache_creation_input_tokens: 50, cache_read_input_tokens: 1000, output_tokens: 7}}'
EOF
  export GO; out=$(loop run 2>&1) || fail "run exited non-zero: $out"
  [ "$(st 'select(.step | IN("blocked", "landed")) | .step')" = landed ] && [ "$(wc -l < "$STUB/reviews")" = 3 ] \
    || fail "a review the API refused twice did not run a third time and land its card: $(wc -l < "$STUB/reviews") reviews, $(st '[.step, .reason] | join(" ")' | tr '\n' ,)"
  # One review line, GO, holding what the tries with a readable usage used (4 and 157 tokens), and unread: the first
  # try's usage is unknown, so the step is not priced as if this were all of it.
  [ "$(st 'select(.step == "review") | [.result, .tokens.claude, .usage.input, .unread, .firstTry] | tojson')" = '["GO",161,103,"the session output holds no token usage",null]' ] \
    || fail "the review line lost a refused try's tokens, or the mark that one's usage is unread: $(st 'select(.step == "review")')"
}
# Bug: a session the API refused before it wrote any result says so on stderr only ("API Error: 503 Service
# Unavailable", exit 1, no result line): it blocked its card at once, as a failure of the card's own. It is the same
# outage: a build and a Claude review that each end so once run again, and the card lands. One that ends so at every
# try blocks naming the error, the API's own words (stderr's) under it.
t_apistderr() {
  setup "[$(issue 7 2026-01-01)]"; tune --slurpfile real "$SRC/lib/test-pack.json" '.models.allowed = $real[0].models.allowed | .models.allowed.claude += ["m"] | .tunables.apiPause = 0.1 | .tunables.poll = 1'
  loop control reviewer claude claude-opus-5-5 >/dev/null || fail "a Claude reviewer was not set"
  cat > "$STUB/claude" <<'EOF'
#!/usr/bin/env bash
cat > /dev/null
case " $* " in *" --tools "*) f=reviews ;; *) f=builds ;; esac; echo x >> "$STUB/$f"
[ "$(wc -l < "$STUB/$f")" -gt "$(cat "$STUB/refuse")" ] || { printf 'API Error: 503 Service Unavailable\n' >&2; exit 1; }
[ $f = reviews ] || { echo two >> a.txt; echo '{"type":"result","is_error":false,"usage":{"input_tokens":10,"cache_creation_input_tokens":20,"cache_read_input_tokens":999,"output_tokens":5}}'; exit 0; }
jq -cn --arg r "$GO" '{type: "result", is_error: false, result: $r, num_turns: 2, usage: {input_tokens: 100, cache_creation_input_tokens: 50, cache_read_input_tokens: 1000, output_tokens: 7}}'
EOF
  echo 1 > "$STUB/refuse"; export GO; out=$(loop run 2>&1) || fail "run exited non-zero: $out"
  [ "$(st 'select(.step | IN("blocked", "landed")) | .step')" = landed ] && [ "$(wc -l < "$STUB/builds")" = 2 ] && [ "$(wc -l < "$STUB/reviews")" = 2 ] \
    || fail "a build and a review the API refused on stderr only did not each run again and land the card: $(cat "$STUB/builds" "$STUB/reviews" 2>/dev/null | wc -l) sessions, $(st '[.step, .reason] | join(" ")' | tr '\n' ,)"
  # Refused so at every try: the card blocks after the fifth, naming the error, with stderr's words under it.
  echo "[$(issue 8 2026-01-01)]" > "$STUB/issues.json"; echo 99 > "$STUB/refuse"; : > "$STUB/builds"
  loop run >/dev/null 2>&1
  [ "$(wc -l < "$STUB/builds")" = 5 ] || fail "a session the API kept refusing on stderr ran $(wc -l < "$STUB/builds") times, not 5"
  st 'select(.issue == 8 and .step == "blocked") | .reason' | grep -q '^build: the model API refused (503) at each of 5 tries' \
    || fail "the card the API kept refusing on stderr is not blocked naming the error: $(st 'select(.issue == 8) | [.step, .reason] | join(" ")' | tr '\n' ,)"
  st 'select(.issue == 8 and .step == "blocked") | .tail' | grep -q 'API Error: 503 Service Unavailable' || fail "the blocked line lost the API's own words: $(st 'select(.issue == 8 and .step == "blocked") | .tail')"
}
