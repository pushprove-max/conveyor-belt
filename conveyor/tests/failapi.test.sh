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
# The engine shell (fx_in, lib.sh) on card c7's worktree ($FXWT, fx_wt), with no card run around the call: what
# <commands> print is in run.out. Each sleep of apitries()'s waits and of apihold()'s holds first adds the live record
# it sleeps on to $STUB/waits, so a case reads what the card's live record said while it waited, with no watcher.
apicall() { # <commands>
  fx_in 'sleep() { case ${FUNCNAME[1]} in apitries|apihold) cat "$FXWT.live" >> "$STUB/waits" ;; esac; command sleep "$@"; }; '"$1" # sleep: the engine's own wait, passed on unchanged
}
t_apierror() {
  setup '[]'; refusing 1; tune '.tunables.apiPause = 0.02'; fx_wt : b.txt one
  # A build session, as a card's build step starts it: what it prints, then its exit.
  apicall 'session "$FXWT" "Build the issue."; echo "rc=$?"'
  # Refused once: the same session ran again and built the change.
  [ "$(tail -n 1 "$T/$CASE/run.out")" = rc=0 ] && [ "$(wc -l < "$STUB/calls")" = 2 ] && grep -qx two "$FXWT/a.txt" \
    || fail "a session the API refused once did not run again and build its change: $(wc -l < "$STUB/calls") sessions, $(cat "$T/$CASE/run.out")"
  # While it waited, the card's live record said why and when it tries again.
  [ "$(wc -l < "$STUB/waits")" = 1 ] && jq -e '.step == "build" and (.action | test("^waiting: the model API refused \\(403 Cloudflare\\); trying again at [0-2][0-9]:[0-5][0-9]$"))' "$STUB/waits" >/dev/null \
    || fail "the waiting card's live record does not say what it waits for and until when: $(cat "$STUB/waits" 2>&1)"
  # Issue 1085: it keeps the effort of the try that was refused, which the Board shows beside the model.
  jq -e '.effort == "medium"' "$STUB/waits" >/dev/null || fail "the waiting card's live record lost its effort: $(cat "$STUB/waits" 2>&1)"
  # What the refused try used is on the build's record with the try that worked (4 and 35 tokens).
  [ "$(head -n 1 "$T/$CASE/run.out" | jq -r '[.tokens.claude, .usage.input, .usage.output] | join(" ")')" = "39 13 6" ] || fail "the refused try's tokens are not on the build's record: $(cat "$T/$CASE/run.out")"
  # Refused at every try: the session fails after the fifth, naming the error, with the API's own words under it.
  refusing 99; : > "$STUB/calls"; : > "$STUB/waits"
  apicall 'session "$FXWT" "Build the issue."; echo "rc=$?"'
  [ "$(wc -l < "$STUB/calls")" = 5 ] && [ "$(wc -l < "$STUB/waits")" = 4 ] || fail "a session the API kept refusing ran $(wc -l < "$STUB/calls") times, not 5"
  [ "$(tail -n 1 "$T/$CASE/run.out")" = rc=1 ] && head -n 1 "$T/$CASE/run.out" | grep -q '^the model API refused (403 Cloudflare) at each of 5 tries' \
    || fail "the session the API kept refusing did not fail naming the error: $(cat "$T/$CASE/run.out")"
  grep -qF 'API Error: 403 Attention Required! | Cloudflare' "$T/$CASE/run.out" || fail "the failure lost the API's own words: $(cat "$T/$CASE/run.out")"
  [ "$(jq -r .tokens.claude "$FXWT.spent")" = 20 ] || fail "the five refused tries' tokens are not in what the failed step used: $(cat "$FXWT.spent")"
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
# One outage must not burn through the queue: a session the API refused marks the error fresh for 5 times apiPause
# (apitries()), apifresh() says it is fresh until then, and while it is, the loop picks no card.
t_apifresh() {
  setup "[$(issue 7 2026-01-01)]"; printf '%s\n' "$GO" > "$STUB/review.1"; refusing 1; tune '.tunables.apiPause = 0.4 | .tunables.poll = 1'; fx_wt : b.txt one
  # The refused session (its mark kept), then apifresh() at once, and on a mark in the past, then on no time at all.
  apicall 'session "$FXWT" "Build the issue." >/dev/null; echo "rc=$?"; cp "$APIERR" "$STUB/marked"
    for m in refused past none; do apifresh && echo "$m fresh" || echo "$m stale"; [ $m = refused ] && jq -n "now - 1" > "$APIERR" || echo null > "$APIERR"; done'
  [ "$(tail -n 4 "$T/$CASE/run.out" | tr '\n' ,)" = "rc=0,refused fresh,past stale,none stale," ] && [ "$(wc -l < "$STUB/calls")" = 2 ] \
    || fail "apifresh() did not say fresh after a refusal and not fresh after its mark: $(cat "$T/$CASE/run.out")"
  # The refusal marked it fresh for 5 times apiPause (2 s).
  jq -en --argjson first "$(sed -n 1p "$STUB/calls")" --slurpfile u "$STUB/marked" '$u[0] >= $first + 2 and $u[0] < $first + 4' >/dev/null \
    || fail "a refused session did not mark the API error fresh for 5 times apiPause: refused at $(sed -n 1p "$STUB/calls"), fresh until $(cat "$STUB/marked")"
  # The loop's pick (run(), lib/run.sh) is held while the error is fresh: marked fresh for 3 s, the card is picked no sooner.
  # The mark is a whole second, as the pick's time is: against a fractional one, a pick in the mark's own second, up
  # to a second early, passed the check.
  echo 0 > "$STUB/refuse"; jq -n 'now + 3 | ceil' > "$ST/apierror"; cp "$ST/apierror" "$STUB/marked"
  # loop: the pick is held inside run()'s turn, which no function call short of the loop runs
  out=$(loop run 2>&1) || fail "run exited non-zero: $out"
  [ "$(st 'select(.step | IN("blocked", "landed")) | .step')" = landed ] || fail "the card did not land: $(st '[.step, .reason] | join(" ")' | tr '\n' ,)"
  jq -en --argjson p "$(st 'select(.step == "picked") | .time | fromdate')" --slurpfile u "$STUB/marked" '$p >= $u[0]' >/dev/null \
    || fail "the loop picked a card while the API error was fresh: fresh until $(cat "$STUB/marked"), picked at $(st 'select(.step == "picked") | .time')"
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
  # The live record is read by polling it: the card's own loop process writes it, and no call of this shell sees it.
  ( while [ -d "$STUB" ] && [ ! -e "$STUB/waitlive" ]; do jq -e '.action // "" | startswith("waiting")' "$T/$CASE"/cards/*-7.live >/dev/null 2>&1 && cp "$T/$CASE"/cards/*-7.live "$STUB/waitlive"; sleep 0.1; done ) >/dev/null 2>&1 &
  # loop: the hold meets a card already picked and past its review: only the card's own run puts its fix after that review
  out=$(loop run 2>&1) || fail "run exited non-zero: $out"
  [ "$(st 'select(.step | IN("blocked", "landed")) | .step')" = landed ] && [ "$(wc -l < "$STUB/calls")" = 2 ] || fail "the card did not land after one fix: $(st '[.step, .reason] | join(" ")' | tr '\n' ,)"
  jq -en --argjson s "$(sed -n 2p "$STUB/calls")" --slurpfile u "$STUB/marked" '$s >= $u[0]' >/dev/null \
    || fail "a card picked before the API error started a session while it was fresh: fresh until $(cat "$STUB/marked"), its fix session at $(sed -n 2p "$STUB/calls")"
  jq -e '.step == "fix" and (.action | test("^waiting: the model API refused a session; starting at [0-2][0-9]:[0-5][0-9]$"))' "$STUB/waitlive" >/dev/null \
    || fail "the held card's live record does not say what it waits for and until when: $(cat "$STUB/waitlive" 2>&1)"
}
# Bug: a Codex review started while an API error was fresh: only Claude sessions were held. An API error marked fresh
# (as another card's refused session marks it); the Codex review starts only once the error is no longer fresh, the
# card's live record saying meanwhile what it waits for.
# Issue 1604: marked fresh for 1 s before the engine shell loaded, the mark could pass under a full run's load before
# the review reached its hold, so nothing waited. The mark is now an hour ahead, and the hold's first sleep ends the
# outage (moves the mark to that time, in $STUB/marked) in place of the wait, so the hold is met at any load.
t_apicodex() {
  setup '[]'; printf '%s\n' "$GO" > "$STUB/review.1"; fx_wt 'echo two >> a.txt' b.txt one
  # shellcheck disable=SC2016
  echo 'date +%s.%N >> "$STUB/rcalls"' > "$STUB/review-cmd"
  mkdir -p "$ST"; jq -n 'now + 3600' > "$ST/apierror"
  # Each of apihold()'s sleeps adds the live record it sleeps on to $STUB/waits (as apicall's does) and ends the outage.
  local held='sleep() { [ "${FUNCNAME[1]}" = apihold ] || { command sleep "$@"; return; }; cat "$FXWT.live" >> "$STUB/waits"; jq -n now > "$APIERR"; cp "$APIERR" "$STUB/marked"; }; ' # sleep: any other wait of the engine's, passed on unchanged
  apicall "$held"'reviewed "$FXWT" "Build the issue."; echo "rc=$? $(verdict "$FXWT.review")"'
  [ "$(tail -n 1 "$T/$CASE/run.out")" = "rc=0 GO" ] && [ "$(wc -l < "$STUB/rcalls")" = 1 ] || fail "the review did not answer GO once: $(cat "$T/$CASE/run.out")"
  jq -en --argjson s "$(sed -n 1p "$STUB/rcalls")" --slurpfile u "$STUB/marked" '$s >= $u[0]' >/dev/null \
    || fail "a Codex review started while the API error was fresh: fresh until $(cat "$STUB/marked"), the review at $(sed -n 1p "$STUB/rcalls")"
  [ -s "$STUB/waits" ] && jq -se 'all(.step == "review" and (.action | test("^waiting: the model API refused a session; starting at [0-2][0-9]:[0-5][0-9]$")))' "$STUB/waits" >/dev/null \
    || fail "the held review's live record does not say what it waits for and until when: $(cat "$STUB/waits" 2>&1)"
}
# Bug: a Codex review the API refused (429 at every try) was run again once only, as a review without a verdict is,
# then blocked its card, and marked no API error, so the loop went on picking cards into the outage. It is an API-side
# error as a Claude session's is: the same review runs again, up to 5 tries, and each refusal is marked fresh.
t_apicodexrefused() {
  setup '[]'; printf '%s\n' "$GO" > "$STUB/review.3"; echo 2 > "$STUB/refuse"; tune '.tunables.apiPause = 0.02'; fx_wt 'echo two >> a.txt' b.txt one
  # reviewed() alone, as a card's review step calls it: what it prints, then its exit and the verdict it left.
  # shellcheck disable=SC2016 # expanded in the engine shell (apicall)
  cxreview='reviewed "$FXWT" "Build the issue."; echo "rc=$? $(verdict "$FXWT.review")"'
  # shellcheck disable=SC2016
  echo 'n=$(cat "$STUB/refuse"); [ "$n" -le 0 ] || { echo $((n - 1)) > "$STUB/refuse"; cp "$ST/apierror" "$STUB/marked.$n" 2>/dev/null
    echo "{\"type\":\"turn.completed\",\"usage\":{\"input_tokens\":100,\"cached_input_tokens\":60,\"output_tokens\":7}}"
    echo "{\"type\":\"error\",\"message\":\"${REFUSAL:-API Error: 429 Too Many Requests}\"}"; exit 1; }' > "$STUB/review-cmd"
  apicall "$cxreview"
  [ "$(tail -n 1 "$T/$CASE/run.out")" = "rc=0 GO" ] && [ "$(wc -l < "$STUB/reviews")" = 3 ] \
    || fail "a Codex review the API refused twice did not run a third time and answer GO: $(wc -l < "$STUB/reviews") reviews, $(cat "$T/$CASE/run.out")"
  # The first refusal marked the error fresh (the second try saw the mark), so no other card starts into the outage.
  jq -e numbers "$STUB/marked.1" >/dev/null 2>&1 && [ ! -e "$STUB/marked.2" ] || fail "a refused Codex review did not mark the API error: $(ls "$STUB")"
  # One review record with the refused tries' tokens (47 each) and no first attempt: it was never a review without a verdict.
  [ "$(head -n 1 "$T/$CASE/run.out" | jq -c '[.tokens.codex, .firstTry]')" = '[141,null]' ] \
    || fail "the review's record lost the refused tries' tokens, or holds a first attempt: $(cat "$T/$CASE/run.out")"
  # Refused at every try, in Codex's own words for it: the review fails after the fifth, with the status and the kept events file.
  # Bug: the reason copied Codex's words (the last 60 lines of its error), and a password in a URL of them went to the GitHub
  # comment of the block; it names the events file kept for the last try instead and holds none of Codex's words.
  echo 99 > "$STUB/refuse"; : > "$STUB/reviews"; rm -f "$ST/apierror"
  REFUSAL='exceeded retry limit, last status: 429 Too Many Requests at https://demo:pw123@example.com/' apicall "$cxreview"
  [ "$(wc -l < "$STUB/reviews")" = 5 ] || fail "a Codex review the API kept refusing ran $(wc -l < "$STUB/reviews") times, not 5"
  [[ $(tail -n 1 "$T/$CASE/run.out") == "rc=1 "* ]] && head -n 1 "$T/$CASE/run.out" | grep -qE '^the model API refused \(429\) at each of 5 tries.* apart; its events are kept in .*\.review(-[0-9]+)?\.events$' \
    && ! grep -qE 'pw123|example\.com|exceeded retry limit' "$T/$CASE/run.out" || fail "the review the API kept refusing did not fail naming the kept events file alone, with no word of Codex's: $(cat "$T/$CASE/run.out")"
  grep -qF 'pw123@example.com' "$ST/kept/${FXWT##*/}/$(head -n 1 "$T/$CASE/run.out" | sed 's/.*kept in //')" || fail "the events file the reason names was not kept, or lacks Codex's error: $(ls "$ST/kept/${FXWT##*/}" 2>&1)"
  [ "$(jq -r .tokens.codex "$FXWT.spent")" = 235 ] || fail "the five refused tries' tokens are not in what the failed review used: $(cat "$FXWT.spent")"
  # A review that wrote its NO-GO before the API refused it answered: run again, a GO could replace that NO-GO.
  : > "$STUB/reviews"; printf '%s\n' "$NOGO" > "$STUB/review.1"; printf '%s\n' "$GO" > "$STUB/review.2"
  # shellcheck disable=SC2016 # expanded in the codex stub
  echo 'cat "$STUB/review.1" > "$out"; echo "{\"type\":\"error\",\"message\":\"API Error: 429 Too Many Requests\"}"; exit 1' > "$STUB/review-cmd"
  rm -f "$ST/apierror"; apicall "$cxreview"
  [ "$(wc -l < "$STUB/reviews")" = 1 ] && [[ $(tail -n 1 "$T/$CASE/run.out") == "rc=1 "* ]] && head -n 1 "$T/$CASE/run.out" | grep -q '^review failed (exit 1)' \
    || fail "a Codex review that wrote a verdict and was then refused by the API was run again: $(wc -l < "$STUB/reviews") reviews, $(cat "$T/$CASE/run.out")"
  # Bug: that review, kept as answered, marked no API error either, so the queue went on into the outage it met.
  jq -e numbers "$ST/apierror" >/dev/null 2>&1 || fail "a Codex review refused by the API after its verdict did not mark the API error"
  # A refusal Codex prints in plain words is read as one (t_apiwords).
  # Bug: a refusal Codex wrote to stderr alone, its stream empty, was read as no API error either. Refused so at every
  # try, the review runs 5 times and fails naming the status and the kept events file, with no word of Codex's.
  : > "$STUB/reviews"; rm -f "$ST/apierror"
  echo 'echo "API Error: 429 https://demo:pw123@example.com/" >&2; exit 1' > "$STUB/review-cmd"
  apicall "$cxreview"
  [ "$(wc -l < "$STUB/reviews")" = 5 ] && jq -e numbers "$ST/apierror" >/dev/null 2>&1 || fail "a Codex review refused on stderr ran $(wc -l < "$STUB/reviews") times, not 5, or marked no API error"
  head -n 1 "$T/$CASE/run.out" | grep -qE '^the model API refused \(429\) at each of 5 tries.* apart; its events are kept in .*\.events$' && ! grep -qE 'pw123|API Error: 429' "$T/$CASE/run.out" \
    || fail "the review whose stderr said the API refused did not fail naming the status and the kept events file alone: $(cat "$T/$CASE/run.out")"
}
# Bug: a Claude review the API refused was run again once only, as a review without a verdict is, then blocked its
# card; and a refused try whose usage could not be read left a line that looked whole, so part of a step was priced as
# all of it. The review here is refused twice (the first with no usage), then answers GO.
t_apireview() {
  setup '[]'; tune --slurpfile real "$SRC/lib/test-pack.json" '.models.allowed = $real[0].models.allowed | .models.allowed.claude += ["m"] | .tunables.apiPause = 0.02'
  loop control reviewer claude claude-opus-5-5 >/dev/null || fail "a Claude reviewer was not set"
  fx_wt 'echo two >> a.txt' b.txt one
  # stub: the shared stub's reviews always answer; this one is refused twice, as Claude Code ends a refused session
  cat > "$STUB/claude" <<'EOF'
#!/usr/bin/env bash
cat > /dev/null; echo x >> "$STUB/reviews"
case $(wc -l < "$STUB/reviews") in
  1) echo '{"type":"result","is_error":true,"result":"Failed to authenticate. API Error: 403 Attention Required! | Cloudflare"}'; exit 1 ;;
  2) echo '{"type":"result","is_error":true,"result":"Failed to authenticate. API Error: 403 Attention Required! | Cloudflare","usage":{"input_tokens":3,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"output_tokens":1}}'; exit 1 ;;
esac
jq -cn --arg r "$GO" '{type: "result", is_error: false, result: $r, num_turns: 2, usage: {input_tokens: 100, cache_creation_input_tokens: 50, cache_read_input_tokens: 1000, output_tokens: 7}}'
EOF
  export GO; apicall 'reviewed "$FXWT" "Build the issue."; echo "rc=$? $(verdict "$FXWT.review")"'
  [ "$(tail -n 1 "$T/$CASE/run.out")" = "rc=0 GO" ] && [ "$(wc -l < "$STUB/reviews")" = 3 ] \
    || fail "a review the API refused twice did not run a third time and answer GO: $(wc -l < "$STUB/reviews") reviews, $(cat "$T/$CASE/run.out")"
  # One review record, holding what the tries with a readable usage used (4 and 157 tokens), and unread: the first
  # try's usage is unknown, so the step is not priced as if this were all of it.
  [ "$(head -n 1 "$T/$CASE/run.out" | jq -c '[.tokens.claude, .usage.input, .unread, .firstTry]')" = '[161,103,"the session output holds no token usage",null]' ] \
    || fail "the review's record lost a refused try's tokens, or the mark that one's usage is unread: $(cat "$T/$CASE/run.out")"
}
# Bug: a session the API refused before it wrote any result says so on stderr only ("API Error: 503 Service
# Unavailable", exit 1, no result line): it blocked its card at once, as a failure of the card's own. It is the same
# outage: a build and a Claude review that each end so once run again, and end well. One that ends so at every try
# fails naming the error, the API's own words (stderr's) under it.
t_apistderr() {
  setup '[]'; tune --slurpfile real "$SRC/lib/test-pack.json" '.models.allowed = $real[0].models.allowed | .models.allowed.claude += ["m"] | .tunables.apiPause = 0.02'
  loop control reviewer claude claude-opus-5-5 >/dev/null || fail "a Claude reviewer was not set"
  fx_wt : b.txt one
  cat > "$STUB/claude" <<'EOF'
#!/usr/bin/env bash
cat > /dev/null
case " $* " in *" --tools "*) f=reviews ;; *) f=builds ;; esac; echo x >> "$STUB/$f"
[ "$(wc -l < "$STUB/$f")" -gt "$(cat "$STUB/refuse")" ] || { printf 'API Error: 503 Service Unavailable\n' >&2; exit 1; }
[ $f = reviews ] || { echo two >> a.txt; echo '{"type":"result","is_error":false,"usage":{"input_tokens":10,"cache_creation_input_tokens":20,"cache_read_input_tokens":999,"output_tokens":5}}'; exit 0; }
jq -cn --arg r "$GO" '{type: "result", is_error: false, result: $r, num_turns: 2, usage: {input_tokens: 100, cache_creation_input_tokens: 50, cache_read_input_tokens: 1000, output_tokens: 7}}'
EOF
  # The build, then the review of its change, as a card's steps call them: each one's exit (and the review's verdict).
  echo 1 > "$STUB/refuse"; export GO
  apicall 'session "$FXWT" "Build the issue."; echo "build rc=$?"; git -C "$FXWT" add -A; reviewed "$FXWT" "Build the issue."; echo "review rc=$? $(verdict "$FXWT.review")"'
  grep -qx 'build rc=0' "$T/$CASE/run.out" && grep -qx 'review rc=0 GO' "$T/$CASE/run.out" && grep -qx two "$FXWT/a.txt" \
    && [ "$(wc -l < "$STUB/builds")" = 2 ] && [ "$(wc -l < "$STUB/reviews")" = 2 ] \
    || fail "a build and a review the API refused on stderr only did not each run again and end well: $(cat "$STUB/builds" "$STUB/reviews" 2>/dev/null | wc -l) sessions, $(cat "$T/$CASE/run.out")"
  # Refused so at every try: the build fails after the fifth, naming the error, with stderr's words under it.
  echo 99 > "$STUB/refuse"; : > "$STUB/builds"; rm -f "$ST/apierror"
  apicall 'session "$FXWT" "Build the issue."; echo "rc=$?"'
  [ "$(wc -l < "$STUB/builds")" = 5 ] || fail "a session the API kept refusing on stderr ran $(wc -l < "$STUB/builds") times, not 5"
  [ "$(tail -n 1 "$T/$CASE/run.out")" = rc=1 ] && head -n 1 "$T/$CASE/run.out" | grep -q '^the model API refused (503) at each of 5 tries' \
    || fail "the session the API kept refusing on stderr did not fail naming the error: $(cat "$T/$CASE/run.out")"
  grep -qF 'API Error: 503 Service Unavailable' "$T/$CASE/run.out" || fail "the failure lost the API's own words: $(cat "$T/$CASE/run.out")"
}

# Issue 1309. Bug it catches: a build session the API refused ran again from nothing, its whole brief once more, and
# its block, refused at each try, was in the class "session failed", as any failed session's. Refused twice here: the
# first try after the refusal resumes the refused session by its id (claude --resume), told the resume brief, and the
# try after that starts from nothing; the build's record has resumed 1. failclass() names each failed build's class.
t_apiresume() {
  setup '[]'; refusing 2; tune '.tunables.apiPause = 0.02'; fx_wt : b.txt one
  sed -i '1i echo "{\\"type\\":\\"system\\",\\"session_id\\":\\"0aa1-b2\\"}"' "$STUB/build"
  apicall 'session "$FXWT" "Build the issue."; echo "rc=$?"
    for r in "the model API refused (403) at each of 5 tries" "stalled twice at build: no progress" "session failed (exit 124, the 60s timeout)" "session failed (exit 1)"; do echo "class=$(failclass "$r")"; done'
  [ "$(sed -n 's/^class=//p' "$T/$CASE/run.out" | tr '\n' ,)" = 'api error,stall,timeout,,' ] \
    || fail "failclass() did not name the API error, the stall and the time limit, or named another failure: $(cat "$T/$CASE/run.out")"
  grep -qx rc=0 "$T/$CASE/run.out" && [ "$(wc -l < "$STUB/sessions")" = 3 ] || fail "a build the API refused twice did not run 3 times and end well: $(cat "$STUB/sessions") $(cat "$T/$CASE/run.out")"
  [ "$(grep -c -- '--resume 0aa1-b2 ' "$STUB/sessions")" = 1 ] && sed -n 2p "$STUB/sessions" | grep -q -- --resume \
    || fail "the first try after the refusal did not resume the refused session, or a later try did too: $(cat "$STUB/sessions")"
  [ "$(head -n 1 "$T/$CASE/run.out" | jq -r .resumed)" = 1 ] || fail "the build's record does not say it was resumed: $(head -n 1 "$T/$CASE/run.out")"
}

# Issue 1323. Bug it catches: only the first try after a refusal could resume. A first try refused on stderr alone
# names no session id, so the second starts from nothing; when that one named its id and was refused too, the third
# started from nothing again, and the step was never resumed. The first try that can resume does.
t_apiresumelater() {
  setup '[]'; tune '.tunables.apiPause = 0.02'; fx_wt : b.txt one
  cat > "$STUB/build" <<'EOT'
echo x >> "$STUB/calls"; n=$(wc -l < "$STUB/calls")
[ "$n" != 1 ] || { printf 'API Error: 503 Service Unavailable\n' >&2; exit 1; }
[ "$n" != 2 ] || { echo '{"type":"system","session_id":"0aa1-b2"}'; echo '{"type":"result","session_id":"0aa1-b2","is_error":true,"result":"API Error: 503 Service Unavailable","usage":{"input_tokens":3,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"output_tokens":1}}'; exit 1; }
echo two >> a.txt
EOT
  apicall 'session "$FXWT" "Build the issue."; echo "rc=$?"'
  grep -qx rc=0 "$T/$CASE/run.out" && [ "$(wc -l < "$STUB/sessions")" = 3 ] || fail "a build refused on stderr, then refused after it named its id, did not run 3 times and end well: $(cat "$STUB/sessions") $(cat "$T/$CASE/run.out")"
  [ "$(grep -c -- '--resume' "$STUB/sessions")" = 1 ] && sed -n 3p "$STUB/sessions" | grep -q -- '--resume 0aa1-b2 ' \
    || fail "the try after the refused try that named its id did not resume it, or another try resumed: $(cat "$STUB/sessions")"
  [ "$(head -n 1 "$T/$CASE/run.out" | jq -r .resumed)" = 1 ] || fail "the build's record does not say it was resumed: $(head -n 1 "$T/$CASE/run.out")"
}

# Issue 1309. Bug it catches: a build that stalled was resumed, and when the API refused that resumed try, the try
# after the refusal, which stalled again after it named its session, resumed that session too, while its record said
# resumed 1. One resume a step: the stall's resume is the step's one, so no later try of the step resumes.
t_apiresumestall() {
  setup '[]'; tune '.tunables.apiPause = 0.02 | .tunables.stuck = 2 | .tunables.reviewPause = 1'; fx_wt : b.txt one
  echo "Failed to authenticate. API Error: 403 Attention Required! | Cloudflare" > "$STUB/refusal"
  # The first try stalls, its resume is refused by the API, the try after that stalls too, the one after that builds the change.
  cat > "$STUB/build" <<'EOT'
echo x >> "$STUB/calls"; n=$(wc -l < "$STUB/calls")
[ "$n" != 1 ] && [ "$n" != 3 ] || { echo "{\"type\":\"system\",\"session_id\":\"0aa1-b$n\"}"; exec sleep 60; } # sleep: a stalled try, ended by the engine
[ "$n" != 2 ] || { jq -cn --rawfile r "$STUB/refusal" '{type: "result", session_id: "0aa1-b2", is_error: true, result: ($r | rtrimstr("\n")), usage: {input_tokens: 3, cache_creation_input_tokens: 0, cache_read_input_tokens: 0, output_tokens: 1}}'; exit 1; }
echo two >> a.txt
EOT
  apicall 'session "$FXWT" "Build the issue."; echo "rc=$?"'
  grep -qx rc=0 "$T/$CASE/run.out" && [ "$(wc -l < "$STUB/sessions")" = 4 ] || fail "a build that stalled, was refused, then stalled again, did not run 4 times and end well: $(cat "$STUB/sessions") $(cat "$T/$CASE/run.out")"
  [ "$(grep -c -- '--resume' "$STUB/sessions")" = 1 ] && sed -n 2p "$STUB/sessions" | grep -q -- '--resume 0aa1-b1 ' \
    || fail "the stalled build was not resumed exactly once, the try after the refusal resumed it again: $(cat "$STUB/sessions")"
  [ "$(grep -m 1 '^{' "$T/$CASE/run.out" | jq -r .resumed)" = 1 ] || fail "the build's record does not say it was resumed once: $(cat "$T/$CASE/run.out")"
}

# Issue 1324. Bug it catches: the resumed try emitted its session id but reported no usage, so the transcript of that
# session, which holds the refused try too, was read as the resumed try's usage, and the refused try's usage was
# added to it again: the build's tokens counted twice. A resumed try's usage is not read from the transcript; the
# step says unread instead of showing a count with the refused try in it twice.
t_apiresumetokens() {
  setup '[]'; tune '.tunables.apiPause = 0.02'; fx_wt : b.txt one
  cat > "$STUB/build" <<'EOT'
echo x >> "$STUB/calls"; n=$(wc -l < "$STUB/calls")
echo '{"type":"system","session_id":"0aa1-b2"}'
[ "$n" != 1 ] || { echo '{"type":"result","session_id":"0aa1-b2","is_error":true,"result":"API Error: 503 Service Unavailable","usage":{"input_tokens":3,"cache_creation_input_tokens":100,"cache_read_input_tokens":0,"output_tokens":40}}'; exit 1; }
echo two >> a.txt; echo '{"type":"result","session_id":"0aa1-b2","is_error":false,"num_turns":1,"usage":"n/a"}'; exit 0 # the claude stub would print its own usage after this
EOT
  # The default login's transcript of the session: the refused try's answer, which the resumed session carries on.
  local h=$T/$CASE/home p; p=$h/.claude/projects/$(cd "$FXWT" && pwd -P | sed 's/[^A-Za-z0-9]/-/g'); mkdir -p "$p"
  jq -cn '{type: "assistant", sessionId: "0aa1-b2", message: {id: "msg_1", model: "claude-sonnet-5-5", usage: {input_tokens: 3, cache_creation_input_tokens: 100, cache_read_input_tokens: 0, output_tokens: 40}}}' > "$p/0aa1-b2.jsonl"
  apicall 'HOME='"$h"'; session "$FXWT" "Build the issue."; echo "rc=$?"'
  grep -qx rc=0 "$T/$CASE/run.out" && [ "$(grep -c -- '--resume 0aa1-b2 ' "$STUB/sessions")" = 1 ] \
    || fail "a build refused once did not resume and end well: $(cat "$STUB/sessions") $(cat "$T/$CASE/run.out")"
  # The step keeps the refused try's own usage (APIFOLD: priced from it as an estimate, #1585) and says unread: read
  # from the transcript, which holds the refused try too, the resumed try would count its 40 output tokens twice (80).
  [ "$(head -n 1 "$T/$CASE/run.out" | jq -c '[.usage.output, (.unread | type)]')" = '[40,"string"]' ] \
    || fail "the resumed try's usage was read from a transcript that holds the refused try too: $(head -n 1 "$T/$CASE/run.out")"
}

# #1444 (R300). Bug it catches: the try after a resumed try that stalled runs fresh, in a session of its own, but the
# step still took it for the resumed try, so its transcript was not read: a fresh try whose output holds no usage
# (only Claude Code's transcript of its session does) left the step's usage unread, and the step unpriced.
t_apiresumefresh() {
  setup '[]'; tune '.tunables.apiPause = 0.02 | .tunables.stuck = 2 | .tunables.reviewPause = 1'; fx_wt : b.txt one
  # Refused by the API, its resume stalls, the fresh try after that builds the change and gives no usage in its output.
  cat > "$STUB/build" <<'EOT'
echo x >> "$STUB/calls"; n=$(wc -l < "$STUB/calls")
[ "$n" != 1 ] || { echo '{"type":"result","session_id":"0aa1-b1","is_error":true,"result":"API Error: 503 Service Unavailable","usage":{"input_tokens":3,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"output_tokens":1}}'; exit 1; }
[ "$n" != 2 ] || { echo '{"type":"system","session_id":"0aa1-b1"}'; exec sleep 60; } # sleep: the resumed try stalls, ended by the engine
echo '{"type":"system","session_id":"0aa1-b3"}'; echo two >> a.txt; echo '{"type":"result","session_id":"0aa1-b3","is_error":false,"num_turns":1,"usage":"n/a"}'; exit 0 # the claude stub would print its own usage after this
EOT
  # The default login's transcript of the fresh try's session.
  local h=$T/$CASE/home p; p=$h/.claude/projects/$(cd "$FXWT" && pwd -P | sed 's/[^A-Za-z0-9]/-/g'); mkdir -p "$p"
  jq -cn '{type: "assistant", sessionId: "0aa1-b3", message: {id: "msg_3", model: "claude-sonnet-5-5", usage: {input_tokens: 5, cache_creation_input_tokens: 100, cache_read_input_tokens: 0, output_tokens: 40}}}' > "$p/0aa1-b3.jsonl"
  apicall 'HOME='"$h"'; session "$FXWT" "Build the issue."; echo "rc=$?"'
  grep -qx rc=0 "$T/$CASE/run.out" && [ "$(wc -l < "$STUB/sessions")" = 3 ] && [ "$(grep -c -- '--resume' "$STUB/sessions")" = 1 ] && sed -n 2p "$STUB/sessions" | grep -q -- '--resume 0aa1-b1 ' \
    || fail "a build refused once, whose resume stalled, did not run fresh once more and end well: $(cat "$STUB/sessions") $(cat "$T/$CASE/run.out")"
  # Its 40 output tokens are counted (with the refused try's 1); the stalled try's output holds none, which unread still says.
  [ "$(grep -m 1 '^{' "$T/$CASE/run.out" | jq -c '.usage.output')" = 41 ] \
    || fail "the fresh try's usage, in its own transcript only, was not read: $(grep -m 1 '^{' "$T/$CASE/run.out")"
}
# Bug caught (#1585 review): a retry left the tokens one try counted out of the step's usage, so the pricer gave a step
# with tokens counted a median, or left out what a try on another model counted. Both folds, BOTHTRIES (a review's two
# attempts) and APIFOLD (the tries the model API refused), keep them: the counted usage when the step's own try read
# none, and a try's on another model (x) in alsoUsed, priced at that model. Bug caught (#1585 review): that try's
# own word on the model that ran it (stats.byModel, y) was dropped, so its tokens were priced at the model it asked for.
# Bug caught (#1585 review): unread named the model that try asked for (x), not the one it ran on (y).
t_triesusage() {
  setup '[]'
  local d=$T/$CASE/folds u='{"input":10,"read":0,"output":1}' b='{"byModel":{"y":{"input":10,"write":0,"read":0,"output":1}}}'; mkdir -p "$d"
  echo '{"model":"m","sec":1,"unread":"none read"}' > "$d/none"; echo "{\"model\":\"m\",\"sec\":1,\"usage\":$u}" > "$d/m"
  echo "{\"model\":\"x\",\"sec\":1,\"usage\":$u,\"stats\":{\"turns\":1,\"byModel\":$(jq -c .byModel <<<"$b")}}" > "$d/x"
  # shellcheck disable=SC2016 # expanded in the engine shell
  fx_in 'for t in none:m m:x; do s=$(cat "'"$d"'/${t#*:}")
      jq -c --argjson f "{\"spent\": $s}" "$BOTHTRIES | [.usage, .unread, .alsoUsed]" "'"$d"'/${t%:*}"; jq -c --argjson p "$s" "$APIFOLD | [.usage, .unread, .alsoUsed]" "'"$d"'/${t%:*}"; done'
  [ "$(cat "$T/$CASE/run.out")" = "[$u,\"none read\",null]
[$u,\"none read\",null]
[$u,\"the first attempt ran on another model (y): one model cannot price both\",[{\"model\":\"x\",\"usage\":$u,\"stats\":$b}]]
[$u,\"a try the model API refused ran on another model (y): one model cannot price both\",[{\"model\":\"x\",\"usage\":$u,\"stats\":$b}]]" ] \
    || fail "the folds of a step whose own try read no usage ($d/none beside $d/m) and of one beside a try on another model ($d/m beside $d/x): $(cat "$T/$CASE/run.out")"
}
# Bug caught (#1585 review): a first try that asked for s and ran on o, beside a retry that asked for o and ran on o,
# kept the reason "the first attempt ran on another model (s)": both ran on o. The reason says it asked for s. Bug
# caught (#1585 review): adding the two tries' usage and splits as one left such a first try's 1-hour writes with no
# model of the retry's split to price them at, and made an old line's first try (firstused, jq/rows.jq) counted twice.
# Both folds keep it apart, in alsoUsed, at its own split, as for a try on another model.
# Bug caught (#1585 review): a first try that asked for s and ran on h and o (two) kept the reason "ran on another
# model (h, o)": the retry ran on o too. The reason names h alone.
t_triesranon() {
  setup '[]'
  local d=$T/$CASE/folds; mkdir -p "$d"
  echo '{"model":"s","sec":1,"usage":{"input":10},"stats":{"byModel":{"o":{"input":10}}}}' > "$d/first"
  echo '{"model":"s","sec":1,"usage":{"input":10},"stats":{"byModel":{"h":{"input":4},"o":{"input":6}}}}' > "$d/two"
  echo '{"model":"o","sec":1,"usage":{"input":10},"stats":{"byModel":{"o":{"input":10}}}}' > "$d/retry"
  # shellcheck disable=SC2016 # expanded in the engine shell
  fx_in 'for t in first two; do s=$(cat "'"$d"'/$t"); jq -c --argjson f "{\"spent\": $s}" "$BOTHTRIES | [.usage, .stats, .unread, (.alsoUsed | length)]" "'"$d"'/retry"
      jq -c --argjson p "$s" "$APIFOLD | [.usage, .stats, .unread, (.alsoUsed | length)]" "'"$d"'/retry"; done'
  [ "$(cat "$T/$CASE/run.out")" = "[{\"input\":10},{\"byModel\":{\"o\":{\"input\":10}}},\"the first attempt asked for another model (s): each is priced at the models that ran it\",1]
[{\"input\":10},{\"byModel\":{\"o\":{\"input\":10}}},\"a try the model API refused asked for another model (s): each is priced at the models that ran it\",1]
[{\"input\":10},{\"byModel\":{\"o\":{\"input\":10}}},\"the first attempt ran on another model (h): one model cannot price both\",1]
[{\"input\":10},{\"byModel\":{\"o\":{\"input\":10}}},\"a try the model API refused ran on another model (h): one model cannot price both\",1]" ] \
    || fail "the folds of $d/first (asked for s, ran on o) and of $d/two (asked for s, ran on h and o) before $d/retry (asked for o, ran on o): $(cat "$T/$CASE/run.out")"
}
# Bug caught (#1585 review): two tries asked of one model added their usage and kept only the last try's split by model
# (stats.byModel), so the price table priced the first try's tokens at the models the last one named (a refused try
# that ran on y, its retry on z: all at z). Both folds keep each try's tokens with the models it named (TRYFOLD): the
# two splits added (b beside a); the usage added at the one model a names, beside a try that names none (c); a try
# that names z with no split beside a, apart in alsoUsed, with unread (d); and the split of the try whose usage is
# taken when the other read none (none beside a).
t_triessplit() {
  setup '[]'
  local d=$T/$CASE/folds u='{"input":10,"read":0,"output":1}' y='{"input":10,"write":0,"read":0,"output":1}' w; mkdir -p "$d"
  echo "{\"model\":\"m\",\"sec\":1,\"usage\":$u,\"stats\":{\"byModel\":{\"y\":$y}}}" > "$d/a"
  echo "{\"model\":\"m\",\"sec\":1,\"usage\":$u,\"stats\":{\"turns\":1,\"byModel\":{\"z\":$y}}}" > "$d/b"
  echo "{\"model\":\"m\",\"sec\":1,\"usage\":$u}" > "$d/c"
  echo "{\"model\":\"m\",\"sec\":1,\"usage\":$u,\"stats\":{\"models\":[\"z\"]}}" > "$d/d"
  echo '{"model":"m","sec":1,"unread":"none read","stats":{"turns":2,"byModel":{"z":{"input":0}}}}' > "$d/none"
  # shellcheck disable=SC2016 # expanded in the engine shell
  fx_in 'for t in b c d none; do s=$(cat "'"$d"'/a")
      jq -c --argjson f "{\"spent\": $s}" "$BOTHTRIES | [.usage, .stats, .unread, .alsoUsed]" "'"$d"'/$t"; jq -c --argjson p "$s" "$APIFOLD | [.usage, .stats, .unread, .alsoUsed]" "'"$d"'/$t"; done'
  w="[{\"input\":20,\"read\":0,\"output\":2},{\"turns\":1,\"byModel\":{\"z\":$y,\"y\":$y},\"models\":[\"y\",\"z\"]},null,null]
[{\"input\":20,\"read\":0,\"output\":2},{\"byModel\":{\"y\":{\"input\":20,\"write\":0,\"read\":0,\"output\":2}},\"models\":[\"y\"]},null,null]
[$u,{\"models\":[\"z\"]},\"a try named other models that ran it (y) than the other (z): one split cannot price both\",[{\"model\":\"m\",\"usage\":$u,\"stats\":{\"byModel\":{\"y\":$y}}}]]
[$u,{\"turns\":2,\"byModel\":{\"y\":$y}},\"none read\",null]"
  # Each line twice: BOTHTRIES's, then APIFOLD's.
  [ "$(cat "$T/$CASE/run.out")" = "$(sed p <<<"$w")" ] \
    || fail "the folds of $d/a, a try that named y as the model that ran it, beside $d/b (z), $d/c (none named), $d/d (z, no split) and $d/none (no usage read): $(cat "$T/$CASE/run.out")"
}
# Bug caught (#1585 review): a try with usage and no split (1, 100 input tokens) folded beside one split on y (2)
# added its usage only; a third try split on z (3) then made the split two models, which the price table prices from
# the split alone, so the first try's 100 tokens were left out of the cost. The split keeps every try's tokens.
t_triesthird() {
  setup '[]'
  local d=$T/$CASE/folds; mkdir -p "$d"
  echo '{"model":"m","sec":1,"usage":{"input":100,"write":0,"write1h":0,"read":0,"output":0}}' > "$d/1"
  echo '{"model":"m","sec":1,"usage":{"input":100,"write":0,"read":0,"output":0},"stats":{"byModel":{"y":{"input":100,"write":0,"read":0,"output":0}}}}' > "$d/2"
  echo '{"model":"m","sec":1,"usage":{"input":100,"write":0,"read":0,"output":0},"stats":{"byModel":{"z":{"input":100,"write":0,"read":0,"output":0}}}}' > "$d/3"
  # shellcheck disable=SC2016 # expanded in the engine shell
  fx_in 'p=$(jq -c --argjson p "$(cat "'"$d"'/1")" "$APIFOLD" "'"$d"'/2"); jq -c --argjson p "$p" "$APIFOLD | [.usage.input, (.stats.byModel | map_values(.input)), .unread]" "'"$d"'/3"'
  [ "$(cat "$T/$CASE/run.out")" = '[300,{"z":100,"y":200},null]' ] \
    || fail "APIFOLD of $d/1 (usage alone), then $d/2 (split on y), then $d/3 (split on z): the split must hold all 300 input tokens: $(cat "$T/$CASE/run.out")"
}

# E4. Bug it catches: the API refused a build twice before either try reported usage, and the third try built the
# change. Only the first refused try's output was kept beside the card (apitries() kept none once <card>.out.first was
# there), so the second's was lost from the unpriced line's kept outputs. Each one is kept, in try order, then the last.
t_apikeepeach() {
  setup '[]'; tune '.tunables.apiPause = 0.02'; fx_wt : b.txt one
  cat > "$STUB/build" <<'EOT'
echo x >> "$STUB/calls"; n=$(wc -l < "$STUB/calls")
[ "$n" -gt 2 ] || { jq -cn --arg n "$n" '{type: "result", is_error: true, result: "API Error: 429 Too Many Requests, try \($n)"}'; exit 1; }
echo two >> a.txt
EOT
  # shellcheck disable=SC2016 # expanded in fx_in's shell
  apicall 'f=$(session "$FXWT" "Build the issue.") && record c7 7 build ok "$f" && echo recorded'
  grep -qx recorded "$T/$CASE/run.out" && [ "$(wc -l < "$STUB/calls")" = 3 ] || fail "the build refused twice did not run a third time and write its line: $(cat "$T/$CASE/run.out")"
  grep -qF 'try 1' "$ST/kept/c7/c7.build.out" 2>/dev/null && grep -qF 'try 2' "$ST/kept/c7/c7.build-2.out" 2>/dev/null && [ -s "$ST/kept/c7/c7.build-3.out" ] \
    || fail "the outputs of the two tries the API refused with no usage were not both kept, in order, before the last: $(ls "$ST/kept/c7" 2>&1)"
}
# E2 (review). Bug it catches: try 1 refused with no usage, try 2 refused with its usage: apitries() read try 2's price
# from <card>.spent after APIFOLD had added try 1's unread to it, so try 2's output, which has its price, was kept as
# one with none. Only try 1's is kept before the last try's.
t_apikeeppriced() {
  setup '[]'; tune '.tunables.apiPause = 0.02'; fx_wt : b.txt one
  cat > "$STUB/build" <<'EOT'
echo x >> "$STUB/calls"; n=$(wc -l < "$STUB/calls")
[ "$n" -gt 2 ] || { jq -cn --argjson n "$n" '{type: "result", is_error: true, result: "API Error: 429 Too Many Requests, try \($n)"}
  + if $n > 1 then {usage: {input_tokens: 3, cache_creation_input_tokens: 0, cache_read_input_tokens: 0, output_tokens: 1}} else {} end'; exit 1; }
echo two >> a.txt
EOT
  # shellcheck disable=SC2016 # expanded in fx_in's shell
  apicall 'f=$(session "$FXWT" "Build the issue.") && record c7 7 build ok "$f" && echo recorded'
  grep -qx recorded "$T/$CASE/run.out" && [ "$(wc -l < "$STUB/calls")" = 3 ] || fail "the build refused twice did not run a third time and write its line: $(cat "$T/$CASE/run.out")"
  grep -qF 'try 1' "$ST/kept/c7/c7.build.out" 2>/dev/null && ! grep -qsF 'try 2' "$ST/kept/c7/"* \
    || fail "with try 1 refused with no usage and try 2 refused with its usage, try 1's output alone of the two was not kept: $(grep -c 'try' "$ST/kept/c7/"* 2>&1)"
}
# `control stop` while a build waits after the model API refused it: the loop ends the card, then writes its stopped
# line (stopped()) and removes its outputs (clean()). Try 1 is refused with no usage, try 2 with it. The stopped build
# keeps try 1's output once, and only that.
# - first (bug it catches): apitries() copied try 1's output to <card>.out.first before its wait, so a stop in that
#   wait kept the same try twice, from .out.first and from .out.
# - second (E11, review; bug it catches): stopped in try 2's wait, the line stopped() writes reads try 2 alone, priced,
#   and outkeep() kept nothing, so clean() removed try 1's output with no price to read.
# - stderr (issue 1628; bug it catches): try 2 is refused on stderr alone (the 503 of t_apistderr), so <card>.out is
#   empty in its wait. stopped() returned with no line, as it read <card>.out alone, and clean() removed try 1's output.
# A direct call cannot show it: the stop's order (the card ended, then stopped(), then clean()) is the loop's own, so
# the case runs the loop and polls for the refused try and the stopped line.
apistop() { # <the try whose wait the stop comes in: 1 or 2> [stderr: try 2 is refused on stderr alone]
  local pid card cd=$T/$CASE/cards
  setup "$(issue 7 2026-01-01 | jq -cs .)"; tune '.tunables.apiPause = 30 | .tunables.idle = 1 | .tunables.poll = 1'
  [ -z "${2:-}" ] || : > "$STUB/stderr"
  cat > "$STUB/build" <<'EOT'
echo x >> "$STUB/calls"; n=$(wc -l < "$STUB/calls")
[ "$n" = 1 ] || [ ! -e "$STUB/stderr" ] || { printf 'API Error: 503 Service Unavailable\n' >&2; exit 1; }
jq -cn --argjson n "$n" '{type: "result", is_error: true, result: "API Error: 429 Too Many Requests, try \($n)"}
  + if $n > 1 then {usage: {input_tokens: 3, cache_creation_input_tokens: 0, cache_read_input_tokens: 0, output_tokens: 1}} else {} end'
exit 1
EOT
  # loop: the card must be stopped by `control stop` through the loop, which ends it before stopped() and clean() run.
  ( export CONVEYOR_MAIN=$R CONVEYOR_CARDS=$cd; exec timeout 120 bash "$SRC/conveyor.sh" serve > "$STUB/serve.out" 2>&1 ) & pid=$!; SERVEPID=$pid; trap 'kill "$SERVEPID" 2>/dev/null' EXIT
  # The stop comes only once apitries() has begun try <n>'s wait: session1() writes <card>.spent before apitries()
  # reads the refusal, so a stop then lands before the wait's stop path runs. <card>.spent is removed as each try
  # starts and written as it fails, after watch() writes that try's own live record; apitries() then writes its
  # "trying again" live record just before it sleeps. With try <n> made, <card>.spent there and that record, try <n>'s
  # wait has begun (not try <n>-1's: its record was written over by try <n>'s watch() before <card>.spent was).
  until { [ -s "$STUB/calls" ] && [ "$(wc -l < "$STUB/calls")" = "$1" ] && compgen -G "$cd/*.spent" >/dev/null \
    && jq -se 'any(.action | strings | test("^waiting: the model API refused \\(.*\\); trying again at "))' "$cd"/*.live >/dev/null 2>&1; } \
    || ! kill -0 $pid 2>/dev/null; do sleep 0.1; done
  card=$(st 'select(.step == "picked") | .card'); [ -n "$card" ] && [ -s "$cd/$card.spent" ] && jq -e '.action | test("trying again at ")' "$cd/$card.live" >/dev/null 2>&1 \
    || fail "serve did not begin the wait after try $1 of the build: $(cat "$STUB/serve.out")"
  loop control stop >/dev/null
  until [ -n "$(jq -r --arg c "$card" 'select(.card == $c and .step == "build") | .card' "$ST/retried.jsonl" 2>/dev/null)" ] || ! kill -0 $pid 2>/dev/null; do sleep 0.1; done
  kill $pid; wait $pid 2>/dev/null
  [ "$(jq -r --arg c "$card" 'select(.card == $c and .step == "build") | .result' "$ST/retried.jsonl" 2>/dev/null)" = stopped ] && [ "$(wc -l < "$STUB/calls")" = "$1" ] \
    || fail "the build was not stopped in the wait after try $1: $(cat "$STUB/serve.out")"
  [ "$(ls "$ST/kept/$card" 2>&1)" = "$card.build.out" ] && grep -qF 'try 1' "$ST/kept/$card/$card.build.out" \
    || fail "the build stopped in the wait after try $1${2:+ (try 2 refused on stderr alone)} did not keep try 1's output, with no usage, once and alone: $(ls "$ST/kept/$card" 2>&1)"
  # Counted: the stopped line holds what the tries used (apitries()' fold), so try 1's unread usage is said on it; its
  # model, which the Board prices the estimate at (estimate_rest()); and its seconds from the build's start, try 1's
  # 30-second wait in them (the fold sums only the tries' own run time).
  [ -z "${2:-}" ] || jq -e --arg c "$card" 'select(.card == $c and .step == "build") | (.unread | type) == "string" and (.model | type) == "string" and .model != "" and .sec >= 30' "$ST/retried.jsonl" >/dev/null 2>&1 \
    || fail "the build stopped in the wait after a stderr-only refused try 2 did not write the tries' use, its model and its time with the waits on its line: $(jq -c --arg c "$card" 'select(.card == $c and .step == "build")' "$ST/retried.jsonl" 2>&1)"
}
t_apistopfirst() { apistop 1; }
t_apistopsecond() { apistop 2; }
t_apistopstderr() { apistop 2 stderr; }
# Bug (issue 1628, review E2): tries 1 and 3 refused on stderr alone, try 2 a 429 on stdout with no usage. outfirst()
# left an empty <card>.out.first (try 1) and try 2's output in <card>.out.first-2; stopped in try 3's wait, stopped()
# looked at <card>.out.first alone, wrote no line, and clean() removed try 2's output. The stop is the loop's own two
# calls (stopped(), then clean(), lib/run.sh), made here in that wait: no other order of them is in question.
t_apistopthird() {
  setup '[]'; tune '.tunables.apiPause = 0.02'; fx_wt : b.txt one
  cat > "$STUB/build" <<'EOT'
echo x >> "$STUB/calls"; n=$(wc -l < "$STUB/calls")
[ "$n" = 2 ] || { printf 'API Error: 503 Service Unavailable\n' >&2; exit 1; }
echo '{"type": "result", "is_error": true, "result": "API Error: 429 Too Many Requests, try 2"}'; exit 1
EOT
  # shellcheck disable=SC2016 # expanded in fx_in's shell
  local stop='sleep() { [ "${FUNCNAME[1]}" != apitries ] || { echo x >> "$STUB/sleeps"; [ "$(wc -l < "$STUB/sleeps")" -lt 3 ] || { stopped c7 7; clean "$FXWT"; echo stopped; exit 0; }; }; command sleep "$@"; }' # sleep: the engine's own wait, passed on unchanged until the third, where the stop comes
  apicall "$stop"'; began c7 7 build && session "$FXWT" "Build the issue."'
  grep -qx stopped "$T/$CASE/run.out" && [ "$(wc -l < "$STUB/calls")" = 3 ] || fail "the build was not stopped in the wait after try 3: $(cat "$T/$CASE/run.out")"
  [ "$(ls "$ST/kept/c7" 2>&1)" = c7.build.out ] && grep -qF 'try 2' "$ST/kept/c7/c7.build.out" \
    || fail "the build stopped in try 3's wait did not keep try 2's output, with no usage, once and alone: $(ls "$ST/kept/c7" 2>&1)"
  st 'select(.card == "c7" and .step == "build")' | jq -se 'length == 1 and (.[0] | .result == "stopped" and (.unread | type) == "string" and (.model | type) == "string" and .model != "")' >/dev/null \
    || fail "the build stopped in try 3's wait did not write one stopped line with the tries' unread use and its model: $(st 'select(.card == "c7")' | jq -c . 2>&1)"
}
# Bug (follow-up of issue 1628; it catches): try 1 a 429 on stdout with no usage, try 2 refused on stderr alone. Stopped
# after try 2's <card>.spent was written and before apitries() wrote its live file again (watch() removed it), stopped()
# read no model from the live file and dropped .spent's from the line, so the Board could not price it. The stop is the
# loop's two calls, made from nostart(), which session1() calls after it writes <card>.spent: in that window.
t_apistopnolive() {
  setup '[]'; tune '.tunables.apiPause = 0.02'; fx_wt : b.txt one
  cat > "$STUB/build" <<'EOT'
echo x >> "$STUB/calls"; n=$(wc -l < "$STUB/calls")
[ "$n" = 1 ] || { printf 'API Error: 503 Service Unavailable\n' >&2; exit 1; }
echo '{"type": "result", "is_error": true, "result": "API Error: 429 Too Many Requests, try 1"}'; exit 1
EOT
  # shellcheck disable=SC2016 # expanded in fx_in's shell
  local stop='eval "$(declare -f nostart | sed "1s/nostart/realnostart/")"; nostart() { [ "$(wc -l < "$STUB/calls")" -lt 2 ] || { [ ! -e "$FXWT.live" ] && [ -s "$FXWT.spent" ] && echo window; stopped c7 7; clean "$FXWT"; echo stopped; exit 0; }; realnostart "$@"; }' # nostart: the engine's own, until try 2, where the stop comes
  apicall "$stop"'; began c7 7 build && session "$FXWT" "Build the issue."'
  grep -qx window "$T/$CASE/run.out" && grep -qx stopped "$T/$CASE/run.out" && [ "$(wc -l < "$STUB/calls")" = 2 ] \
    || fail "the build was not stopped after try 2 wrote <card>.spent with no live file: $(cat "$T/$CASE/run.out")"
  st 'select(.card == "c7" and .step == "build")' | jq -se 'length == 1 and (.[0] | .result == "stopped" and (.model | type) == "string" and .model != "")' >/dev/null \
    || fail "the build stopped with no live file after try 2's stderr-only refusal did not keep .spent's model on its stopped line: $(st 'select(.card == "c7")' | jq -c . 2>&1)"
}
