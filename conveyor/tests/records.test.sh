#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 300
# Engine cases: the report, the card list, retry and an issue already fixed.
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"
# The engine folder, as lib.sh sets it: named here too, so the release closure (tools/closure.sh) follows this file's paths.
SRC=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)

# Bugs: the report miscounts landed, product, median (an even count takes the mean of the middle two) or blocked share,
# does not flag an open card that has gone past 5 reviews (nothing caps the rounds, so the owner stops it by hand), or hides a
# card that stopped with no closing line.
t_report() {
  setup '[]'; mkdir -p "$ST"; d=$(date -u +%F)
  row() { jq -cn --arg c "$1" --arg s "$2" --arg t "${d}T$3Z" --argjson x "$4" '{card:$c,issue:1,step:$s,time:$t,tokens:{claude:100,codex:10},result:$s,sha:"",reason:""} + $x'; }
  { row cA picked 10:00:00 '{}'; row cA landed 10:30:00 '{"product":true,"sha":"abc"}'; row cB picked 11:00:00 '{}'
    row cB blocked 11:10:00 '{"reason":"NO-GO twice"}'; row cC picked 12:00:00 '{}'; } > "$ST/cards.jsonl"
  [ "$(loop cards | jq -c '[.landed, .blocked, .open, (.cards | map(.step))]')" = '[1,1,1,["landed","blocked","picked"]]' ] || fail "dashboard cards: $(loop cards)"
  out=$(CONVEYOR_MAIN=$R bash "$SRC/report.sh") || fail "report exited non-zero"
  week=$(sed -n '/^== week/,/^$/p' <<<"$out")
  grep -Eq '^cards landed +1$' <<<"$week" || fail "landed row: $week"
  grep -Eq '^landed, changed product code +1$' <<<"$week" || fail "product row: $week"
  grep -Eq '^fresh tokens per landed card +220$' <<<"$week" || fail "tokens row: $week"
  grep -Eq '^median start-to-landed \(min\) +30$' <<<"$week" || fail "median row: $week"
  grep -Eq '^share of cards blocked +50%$' <<<"$week" || fail "blocked row: $week"
  grep -q "^== $d" <<<"$out" && grep -q 'open.*cC' <<<"$out" && grep -q '^blocked, for Dana: cB.*NO-GO twice' <<<"$out" || fail "day block, open card or blocked list missing"
  { row cA picked 10:00:00 '{}'; row cA landed 10:10:00 '{"product":false,"sha":"abc"}'; row cB picked 11:00:00 '{}'
    row cB landed 12:50:00 '{"product":false,"sha":"abd"}'; } > "$ST/cards.jsonl"
  CONVEYOR_MAIN=$R bash "$SRC/report.sh" | sed -n '/^== week/,/^$/p' | grep -Eq '^median start-to-landed \(min\) +60$' || fail "median of 10 and 110 is not 60"
  { row cE picked 13:00:00 '{}'; for m in 1 2 3 4 5 6; do row cE review "13:0$m:00" '{}'; done
    row cF picked 14:00:00 '{}'; for m in 1 2 3 4 5; do row cF review "14:0$m:00" '{}'; done; } >> "$ST/cards.jsonl"
  out=$(CONVEYOR_MAIN=$R bash "$SRC/report.sh"); grep -q 'past 5 reviews.*cE.*: 6 reviews' <<<"$out" && ! grep -q 'past 5 reviews.*cF' <<<"$out" || fail "an open card past 5 reviews is not flagged, or one at 5 is"
}

# Bugs: a card in the middle of a build, review or fix shows the step before it, or not when the step began;
# a closed card loses its stage, reason, kept folder or the tokens and seconds of its steps.
t_cards() {
  setup '[]'; mkdir -p "$ST"; d=$(date -u +%F)
  row() { jq -cn --arg s "$1" --arg t "${d}T00:0$2:00Z" --argjson x "$3" '{card:"c1",issue:1,step:$s,time:$t,tokens:{claude:0,codex:0},result:"ok",sha:"",reason:""} + $x' >> "$ST/cards.jsonl"; }
  at() { loop cards | jq -r '.cards[0] | "\(.step) \(.stage) \(.stepAt[15:16])"'; }
  while read -r step m x want; do row "$step" "$m" "$x"; [ "$(at)" = "$want $m" ] || fail "after $step: $(at)"; done <<'EOF'
picked 0 {"title":"T"} picked 0
worktree 1 {} picked 0
brief 2 {} build 1
build 3 {"tokens":{"claude":35,"codex":0}} review 2
review 4 {"result":"NO-GO"} fix 3
fix 5 {} review 4
review 6 {"result":"NO-GO"} fix 3
blocked 7 {"result":"blocked","reason":"why","kept":"/k"} blocked 3
EOF
  [ "$(loop cards | jq -c '.cards[0] | [.title, .reviews, .reason, .kept, (.steps | map(.step) | join(" ")), .steps[0].sec, .steps[0].tokens.claude, .startedAt[15:16]]')" \
    = '["T",2,"why","/k","build review fix review",60,35,"0"]' ] || fail "closed row: $(loop cards)"
  sed -i '7,8d' "$ST/cards.jsonl"; row review 6 '{"result":"GO"}'; [ "$(at)" = "landing 5 6" ] || fail "after a GO: $(at)"
  # Bug: a card whose changed tests are running, failed or passed shows as picked, or its test run is not a step.
  row test 7 '{"result":"fail","sec":60}'; [ "$(at)" = "fix 3 7" ] || fail "after a failed test run: $(at)"
  row fix 8 '{}'; row review 8 '{"result":"GO"}'; row test 9 '{"result":"pass","sec":60}'; [ "$(at)" = "landing 5 9" ] || fail "after a passed test run: $(at)"
  [ "$(loop cards | jq -c '.cards[0].steps | map(select(.step == "test") | .sec)')" = '[60,60]' ] || fail "the test runs are not steps of the row: $(loop cards)"
  row landed 9 '{"sha":"abc","product":false}'; [ "$(at) $(loop cards | jq -c '[.landed, .open, .cards[0].sha]')" = 'landed 5 9 [1,0,"abc"]' ] || fail "landed row: $(loop cards)"
  sed -i "s/${d}T/2020-01-01T/" "$ST/cards.jsonl"; [ "$(loop cards | jq -c '[.landed, .cards]')" = '[1,[]]' ] || fail "a card closed long ago is still a row"
  # Bugs: an open card picked before titles were recorded stays untitled for good; a closed one
  # costs a gh read; the answer does not name this checkout's own models or GitHub address, so the dashboard prices
  # and links another repo's cards with its own.
  echo "[$(issue 1 2026-01-01)]" > "$STUB/issues.json"; : > "$ST/cards.jsonl"; row picked 0 '{}'
  [ "$(loop cards | jq -c '[.cards[0].title, .models, .repoUrl]')" = '["title 1",{"claude":"m","codex":"x"},null]' ] || fail "untitled open card, models or no origin: $(loop cards)"
  git -C "$R" remote set-url origin "git${AT}github.com:o/r.git"; echo '[]' > "$STUB/issues.json"
  [ "$(loop cards | jq -c '[.cards[0].title, .repoUrl]')" = '["","https://github.com/o/r"]' ] || fail "a failed title read, or the repo address: $(loop cards)"
  row blocked 1 '{"result":"blocked"}'; echo 'echo x >> "$STUB/gh-calls"' >> "$STUB/gh"; loop cards >/dev/null
  [ ! -e "$STUB/gh-calls" ] || fail "a closed card cost a gh read"
}

# Bugs: a blocked card can only be run again by editing the records by hand; `retry` drops the old lines
# instead of keeping them, or touches the records of an open card, a landed card or an issue with no card; a running
# loop takes a retried issue only when one of its cards ends, or not at all once its max-cards are used up; a
# retried card uses up one of the run's max-cards.
# Each part is a case of its own on a main of its own (retry, retrywait, retryfirst), so they run side by side.
# retrylines: the lines of cards of #5, #8 and #9 that no retry may take. #5 landed and was pushed; a restart then
# blocked it, the blocked line timed after the pushed line though written before it. Its commit is on main: giving
# its issue back would build it again.
retrylines() {
  mkdir -p "$ST"
  { landed 8 | jq -c '.step = "picked"'; landed 9
    landed 5 | jq -c '.time = "2026-11-12T16:52:10Z"'; landed 5 | jq -c '.step = "blocked" | .result = "blocked" | .time = "2026-11-12T16:52:13Z"'
    landed 5 | jq -c '.step = "pushed" | .time = "2026-11-12T16:52:12Z"'; } >> "$ST/cards.jsonl"
}
t_retry() {
  setup "$(jq -cs . <(issue 8 2026-02-01) <(issue 9 2026-03-01))"; S=$ST
  retrylines; before=$(cat "$S/cards.jsonl")
  for n in 5 8 9 99; do
    loop retry "$n" >/dev/null 2>&1 && fail "retry of #$n (5 pushed then blocked, 8 open, 9 landed, 99 unknown) exited 0"
    [ "$(cat "$S/cards.jsonl")" = "$before" ] && [ ! -s "$S/retried.jsonl" ] || fail "a refused retry of #$n changed the records"
  done
}

# Bugs: a held issue's blocked card (setup holds every open issue), which health lists as blocked (foreman status
# reads that list), is not given back by `retry`, or is given back and left held, so the loop never builds it.
t_retryheld() {
  setup "$(jq -cs . <(issue 7 2026-01-01))"; mkdir -p "$ST"
  landed 7 | jq -c '.step = "blocked" | .result = "blocked" | .reason = "build: it failed"' >> "$ST/cards.jsonl"
  loop control hold 7 >/dev/null || fail "the hold of #7"
  [ "$(loop health | jq -c '[.blocked[].issue]')" = '[7]' ] || fail "health does not list #7 as blocked, so the case proves nothing"
  out=$(loop retry 7 2>&1) || fail "retry of the held, blocked #7 exited non-zero: $out"
  [ "$(loop health | jq -c '[.blocked[].issue]')" = '[]' ] && grep -q '"step":"blocked"' "$ST/retried.jsonl" || fail "#7's blocked card was not given back: $(cat "$ST/cards.jsonl")"
  [ "$(jq -c .held "$ST/control.json")" = '[]' ] && grep -qF 'issue #7 was held; it is released' <<<"$out" || fail "#7 is still held, or retry did not say it released it: $(jq -c .held "$ST/control.json"); $out"
}

# Bugs: retry of an issue with no card says only "nothing to retry": not which state folder it read, not that a card
# of the issue is in another state folder an older engine wrote to, and not what to do instead; doctor does not name
# that other folder, so the owner never learns the belt cannot see those cards.
t_retrynocard() {
  setup '[]'; local old=$R/conveyor/state out
  # The host file names another state folder for this checkout, so the checkout's own conveyor/state is not read.
  mkdir -p "$XDG_CONFIG_HOME/conveyor"; jq -n --arg d "$T/$CASE/state" '{stateDir: $d}' > "$XDG_CONFIG_HOME/conveyor/host.json"
  ST=$(loop state-dir); mkdir -p "$ST" "$old"
  landed 7 | jq -c '.step = "blocked" | .result = "blocked"' > "$old/cards.jsonl"
  out=$(loop retry 7 2>&1) && fail "retry of #7, which has no card in the state folder, exited 0"
  grep -qF "issue #7 has no card in the state folder $ST; nothing to retry. A card of it is in another state folder, which an older engine wrote to and this belt does not read: $old (doctor names it). If the issue is held, release it with \`conveyor.sh control release 7\`, which starts a new card" <<<"$out" \
    || fail "retry's message: $out"
  out=$(loop retry 9 2>&1); grep -qF 'issue #9 has no card in the state folder' <<<"$out" && ! grep -qF 'another state folder' <<<"$out" || fail "retry of #9, of no folder, names another folder: $out"
  out=$(cd "$R" && loop doctor 2>&1)
  grep -qF "missing: card records only in the state folder $ST: $old holds others, written by an older engine (blocked there: #7)" <<<"$out" || fail "doctor does not name $old: $out"
}

# The Board's Hold on a blocked card (`unblock <issue> --hold`). Bugs: the issue is not held, so the loop builds it
# again at once; its card stays blocked, so it stays in Needs you; its kept work is dropped, so once released it builds
# from nothing; a refused unblock (no blocked card) leaves a hold behind, or takes off a hold the owner had set.
t_unblockhold() {
  setup "$(jq -cs . <(issue 7 2026-01-01) <(issue 8 2026-01-02))"; S=$ST; mkdir -p "$S/kept/c0-7"
  echo two >> "$R/a.txt"; git -C "$R" diff > "$S/kept/c0-7/c0-7.patch"; git -C "$R" reset -q --hard
  landed 7 | jq -c '.step = "blocked" | .result = "blocked" | .kept = "kept/c0-7" | .reason = "build: it failed"' >> "$S/cards.jsonl"
  loop unblock 7 --hold >/dev/null || fail "unblock 7 --hold exited non-zero"
  [ "$(jq -c .held "$S/control.json")" = '[7]' ] || fail "the issue is not held: $(jq -c .held "$S/control.json")"
  ! grep -q '"issue":7,' "$S/cards.jsonl" && grep -q '"step":"blocked"' "$S/retried.jsonl" || fail "the blocked card did not leave the card records for the retried file"
  [ -s "$S/kept/c0-7/c0-7.patch" ] || fail "the kept patch went: $(ls -R "$S/kept")"
  # Refused (no blocked card): no hold is left, and a hold set before stays.
  loop unblock 9 --hold >/dev/null 2>&1 && fail "unblock of #9, which has no card, exited 0"
  loop control hold 8 >/dev/null; loop unblock 8 --hold >/dev/null 2>&1
  [ "$(jq -c .held "$S/control.json")" = '[7,8]' ] || fail "a refused unblock changed the holds: $(jq -c .held "$S/control.json")"
  # Released, its next card resumes from the kept patch: the pick takes #7, and card() runs to its worktree step,
  # which applies the patch; its deps step, the next one, notes what is staged there and stops the card.
  loop control release 7 8 >/dev/null
  fx_in 'cd "$R" && read -r c n _ <<<"$(locked pick "" "" "$(asked)")" && [ "$n" = 7 ] || { echo "pick took ${n:-nothing}"; exit 3; }
    deps() { git -C "$1" diff --cached --name-only > "$STUB/resumed-with"; return 1; }; card "$c" "$n"'
  [ "$RC" != 3 ] || fail "the released #7 was not picked: $(cat "$T/$CASE/run.out")"
  st 'select(.issue == 7 and .step == "worktree") | .reason' | grep -q '^resumed from the kept patch of card c0-7:' && [ "$(cat "$STUB/resumed-with" 2>&1)" = a.txt ] \
    || fail "the released #7 did not resume from its kept patch: $(st 'select(.issue == 7) | "\(.step) \(.result) \(.reason)"' | tr '\n' ,)"
}

# A run whose max-cards are used up (run 1, its one card #10 on the belt) picks with `pick retried` (run(),
# lib/run.sh): that pick takes the retried #7 and nothing else, so the run builds it while it waits on #10.
t_retrywait() {
  setup "$(jq -cs . <(issue 7 2026-01-01 P1) <(issue 10 2026-04-01))"; S=$ST; mkdir -p "$S"
  landed 7 | jq -c '.step = "picked"' >> "$S/cards.jsonl"; landed 7 | jq -c '.step = "blocked" | .result = "blocked" | .reason = "build: it failed"' >> "$S/cards.jsonl"
  retrylines
  fx_in 'locked pick retried "" "$(asked)"'
  [ "$RC" = 0 ] && [ ! -s "$T/$CASE/run.out" ] || fail "a pick of retried issues alone took one before any retry (exit $RC): $(cat "$T/$CASE/run.out")"
  old=$(grep '"issue":7,' "$S/cards.jsonl"); card=c0-7
  loop retry 7 >/dev/null || fail "retry of the blocked #7 exited non-zero"
  fx_in 'locked pick retried "" "$(asked)"; locked pick retried "" "$(asked)"'
  [ "$RC" = 0 ] && [ "$(cut -d' ' -f2- "$T/$CASE/run.out")" = '7 true' ] || fail "a run with its max-cards used up did not pick the retried #7 alone, as a retried card (exit $RC): $(cat "$T/$CASE/run.out")"
  [ "$(jq -c 'del(.retriedAt)' "$S/retried.jsonl")" = "$old" ] && [ -n "$old" ] && ! grep -q "\"card\":\"$card\"" "$S/cards.jsonl" || fail "the blocked card's lines were not moved whole to the retried file"
  grep -q '"issue":8,' "$S/cards.jsonl" && grep -q '"issue":9,' "$S/cards.jsonl" || fail "retry took another issue's lines"
  # The blocked line carries when the owner gave the card back: the wait ends there, not at the next pick.
  [ "$(jq -r 'select(.step == "blocked") | .retriedAt | fromdate | now - . < 60' "$S/retried.jsonl")" = true ] \
    && [ "$(jq -c 'select(.step != "blocked") | .retriedAt' "$S/retried.jsonl" | sort -u)" = null ] \
    || fail "the retried blocked line does not say when it was retried: $(cat "$S/retried.jsonl")"
  loop check || fail "the records do not check after a retry"
}

# A retried issue picked first leaves the run's one card for the next issue: pick says the retried #11's card is a
# retried one (true), which run() does not count toward max-cards, and the next pick takes #12 as a new one (false).
t_retryfirst() {
  setup "$(jq -cs . <(issue 11 2026-01-01 P1) <(issue 12 2026-02-01))"; mkdir -p "$ST"
  landed 11 | jq -c '.step = "blocked" | .result = "blocked"' >> "$ST/cards.jsonl"; loop retry 11 >/dev/null || fail "retry of #11 exited non-zero"
  fx_in 'locked pick "" "" "$(asked)"; locked pick "" "" "$(asked)"'
  [ "$RC" = 0 ] && [ "$(cut -d' ' -f2- "$T/$CASE/run.out" | tr '\n' ,)" = '11 true,12 false,' ] || fail "a retried card is not picked first as a retried one, or uses up the run's max-cards (exit $RC): $(cat "$T/$CASE/run.out")"
}

# The two cases above call pick; this one runs the loop, as only a run shows what run() does with pick's answer
# (lib/run.sh: a retried card leaves `left` as it was, and with `left` at 0 the turn picks with `pick retried`).
# Bugs: run 1 counts the retried #11 as its one card and never builds #12; or, with #12 its last card, a retry of #7
# released while #12 builds waits until #12 ends. #12's build tells the case it began (pipe twelve), and then waits
# up to 120 s on pipe seven, which #7's build writes as it begins: #12 notes whether it heard #7 before it ended.
# Bug: with its one new card #12 taken, the turn picks with no `retried` mode and starts the new #13 too; #13 is the
# open issue after #12, so only `pick retried` leaves it unbuilt.
# The bugs are in what the turn picks and when, so each session changes nothing: its card is blocked after its build,
# with no review, test run, landing or push to wait on.
t_retryturn() {
  setup "$(jq -cs . <(issue 11 2026-01-01 P1) <(issue 12 2026-02-01) <(issue 7 2026-03-01) <(issue 13 2026-04-01))"; mkdir -p "$ST"
  { landed 11; landed 7; } | jq -c '.step = "blocked" | .result = "blocked"' >> "$ST/cards.jsonl"; loop retry 11 >/dev/null || fail "retry of #11 exited non-zero"
  mkfifo "$STUB/twelve" "$STUB/seven" || fail "the build pipes"
  cat > "$STUB/claude" <<'EOF'
#!/usr/bin/env bash
[ "${1:-}" != --version ] || { echo '2.1.322 (Claude Code)'; exit 0; }
n=$(sed -n 's/^# Issue #\([0-9]*\):.*/\1/p' | head -n 1)
case $n in
  12) exec 3<>"$STUB/seven"; echo began 1<>"$STUB/twelve"; read -r -t 120 -u 3 _ && echo heard > "$STUB/twelve-heard" || echo none > "$STUB/twelve-heard" ;;
  7) echo began 1<>"$STUB/seven" ;;
esac
echo '{"type":"result","is_error":false,"usage":{"input_tokens":1,"cache_creation_input_tokens":1,"output_tokens":1}}'
EOF
  exec 4<>"$STUB/twelve" # open before the run, so #12's line waits in the pipe for the read below
  tune '.tunables.poll = 1'; loop run 1 4<&- > "$T/$CASE/loop.out" 2>&1 & run=$!
  read -r -t 120 -u 4 _ || fail "#12's build did not begin: $(cat "$T/$CASE/loop.out")"
  exec 4<&-
  loop retry 7 >/dev/null || fail "retry of the blocked #7 exited non-zero"
  wait "$run" || fail "run 1 exited non-zero: $(cat "$T/$CASE/loop.out")"
  [ "$(cat "$STUB/twelve-heard")" = heard ] || fail "the retried #7 did not start before the run's last card #12 ended its build"
  [ "$(st 'select(.step == "build") | .issue' | sort -n | tr '\n' ' ')" = '7 11 12 ' ] \
    || fail "run 1 did not build the retried #11 and #7 beside its one new card #12: $(st '"\(.issue) \(.step)"' | tr '\n' ,)"
  [ -z "$(st 'select(.issue == 13) | .step')" ] || fail "run 1 started the new #13 after its one new card #12: $(st 'select(.issue == 13) | .step' | tr '\n' ,)"
}

# Bugs: a blocked card whose issue was closed (for any reason) stays under "Needs you" and in health's blocked list,
# with no way to clear it; it does not end closed with a line saying why; its kept patch is deleted; the blocked card
# of an issue that was not closed leaves too; it is given back while an open list still shows it but GitHub says it is
# closed; once it is opened again, no turn of the loop gives it back with no `retry` (#599), or its lines stay in the
# card records. The turn's parts are called as a turn calls them: shut() under the lock with the
# issues found closed, then reopened() with the open list.
# shutrec <issue>...: the blocked card c0-<issue> of each, its patch (a.txt gets the line two) kept in kept/c0-<issue>/.
shutrec() {
  local n; mkdir -p "$ST"
  for n; do
    mkdir -p "$ST/kept/c0-$n" && echo two >> "$R/a.txt" && git -C "$R" diff > "$ST/kept/c0-$n/c0-$n.patch" && git -C "$R" reset -q --hard || fail "the kept patch of c0-$n"
    landed "$n" | jq -c --arg k "kept/c0-$n" '(.step = "picked"), (.step = "blocked" | .result = "blocked" | .reason = "build: it failed" | .kept = $k)' >> "$ST/cards.jsonl"
  done
}
t_shut() {
  local c7=c0-7 c8=c0-8 open
  setup "$(jq -cs . <(issue 7 2026-01-01) <(issue 8 2026-02-01))"; shutrec 7 8; open="[$(issue 7 2026-01-01)]"
  [ "$(loop health | jq -c '.blocked | map(.issue)')" = '[7,8]' ] || fail "#7 and #8 were not blocked to start with: $(loop health)"
  # #7 is closed on GitHub: the turn shuts its card and leaves #8's blocked.
  fx_in 'locked shut "[7]"'
  [ "$RC" = 0 ] || fail "shut [7] exited $RC: $(cat "$T/$CASE/run.out")"
  [ "$(loop health | jq -c '[(.blocked | map(.card)), (.waiting | map(.card))]')" = "[[\"$c8\"],[]]" ] || fail "health's blocked lists after #7 was closed: $(loop health | jq -c '[.blocked, .waiting]')"
  snap=$(loop snapshot --fresh) || fail "snapshot exited non-zero"
  [ "$(jq -c '[.needsYou.blocked[], .needsYou.waiting[]] | map(.issue)' <<<"$snap")" = '[8]' ] || fail "Needs you still lists the closed #7: $(jq -c .needsYou <<<"$snap")"
  [ "$(loop cards | jq -r --arg c "$c7" '.cards[] | select(.card == $c) | .step')" = closed ] || fail "#7's card does not end closed: $(loop cards | jq -c .cards)"
  [ "$(loop cards | jq -c '[.landed, .blocked]')" = '[0,1]' ] || fail "the cards summary counts the closed #7, which landed nothing, as landed: $(loop cards | jq -c '[.landed, .blocked]')"
  [ "$(st "select(.card == \"$c7\") | .step" | tail -n 1)" = closed ] \
    && [ "$(st "select(.card == \"$c7\" and .step == \"closed\") | [.result, .reason] | join(\"|\")")" = 'ok|the issue was closed by hand while the card was blocked' ] \
    || fail "no closed line says #7 was closed while its card was blocked: $(grep "$c7" "$ST/cards.jsonl")"
  # Bug: the owner's report still lists the closed #7 as blocked, for the owner.
  out=$(CONVEYOR_MAIN=$R bash "$SRC/report.sh") || fail "report exited non-zero"
  [ "$(grep -c '^blocked, for ' <<<"$out")" = 1 ] && grep -q "^blocked, for .*: $c8 issue #8: " <<<"$out" || fail "the report's blocked cards after #7 was closed: $out"
  grep -Eq '^cards landed +0$' <<<"$out" || fail "the report counts the closed #7, which landed nothing, as landed: $out"
  [ -s "$ST/kept/$c7/$c7.patch" ] || fail "the kept patch of #7's card is gone"
  loop check || fail "the records do not check after a closed issue's card was closed"
  # The open list still shows #7, its card shut: it is asked whether it was opened again; GitHub says closed, so
  # nothing is given back.
  echo "$open" > "$STUB/closed-issues.json"; rm -f "$STUB/closed-viewed"
  fx_in "reopened '$open'"
  [ "$(cat "$STUB/closed-viewed" 2>&1)" = 7 ] && [ ! -s "$ST/retried.jsonl" ] && [ "$(st "select(.card == \"$c7\") | .step" | tail -n 1)" = closed ] \
    || fail "#7, shown open but closed on GitHub, was not asked, or was given back (exit $RC): $(cat "$ST/retried.jsonl" "$STUB/closed-viewed" 2>&1)"
  # Opened again, #7 is given back with no retry: its shut card's lines move to the retried file, its kept work stays,
  # and #8's card is left as it was.
  echo '[]' > "$STUB/closed-issues.json"
  fx_in "reopened '$open'"
  [ "$(jq -r .card "$ST/retried.jsonl" | sort -u)" = "$c7" ] && ! grep -q "\"card\":\"$c7\"" "$ST/cards.jsonl" \
    || fail "the reopened #7's shut card did not move alone out of the card records (exit $RC): $(cat "$ST/retried.jsonl" 2>&1)"
  [ -s "$ST/kept/$c7/$c7.patch" ] && [ "$(st "select(.card == \"$c8\") | .step" | tr '\n' ' ')" = 'picked blocked ' ] || fail "the kept patch of #7 went, or #8's card changed"
}

# t_shut calls shut() and reopened() with the issues it names; this case runs the loop, as only a turn shows run()
# (lib/run.sh) asking GitHub for each blocked card's issue and taking the closed ones out of the open list it read.
# Bugs: the stale open list still shows the closed #7, and the turn picks it again or leaves it in the sample's list
# (issues.json); #8, open but left out of the list, is taken for closed and shut; once #7 is opened again, its new
# card does not start from the kept patch.
t_shutturn() {
  local c7=c0-7 c8=c0-8
  setup "[$(issue 7 2026-01-01)]"; shutrec 7 8; cp "$STUB/issues.json" "$STUB/closed-issues.json"
  loop run 1 >/dev/null 2>&1
  [ "$(sort -n "$STUB/closed-viewed" 2>&1 | tr '\n' ' ')" = '7 8 ' ] || fail "the turn did not ask GitHub for each blocked card's issue: $(cat "$STUB/closed-viewed" 2>&1)"
  [ "$(st "select(.card == \"$c7\") | .step" | tail -n 1)" = closed ] && [ "$(st 'select(.issue == 7) | .card' | sort -u)" = "$c7" ] \
    || fail "the turn did not shut #7's card, or picked the closed #7 again: $(st 'select(.issue == 7) | "\(.card) \(.step)"' | tr '\n' ,)"
  [ "$(jq -c 'map(.number)' "$ST/issues.json")" = '[]' ] || fail "the sample's open list still counts the closed #7: $(cat "$ST/issues.json")"
  [ "$(st "select(.card == \"$c8\") | .step" | tr '\n' ' ')" = 'picked blocked ' ] || fail "#8, open but not in the open list, was shut: $(grep "$c8" "$ST/cards.jsonl")"
  echo '[]' > "$STUB/closed-issues.json"; echo 'cat a.txt > "$STUB/resumed"; exit 1' > "$STUB/build"
  loop run 1 >/dev/null 2>&1
  grep -q "\"card\":\"$c7\"" "$ST/retried.jsonl" && ! grep -q "\"card\":\"$c7\"" "$ST/cards.jsonl" || fail "the turn did not give back the reopened #7"
  [ -n "$(st "select(.issue == 7 and .step == \"worktree\" and (.reason | contains(\"kept patch of card $c7\"))) | .card")" ] \
    && [ "$(cat "$STUB/resumed" 2>&1)" = $'one\ntwo' ] || fail "#7, reopened, did not start from its kept patch: $(st 'select(.issue == 7) | "\(.step) \(.reason)"'; cat "$STUB/resumed" 2>&1)"
}

# The Board's Close shuts the card itself (`shut`), with no turn of the loop: a stopped loop would leave it under
# Needs you for good. Bug: #8's card stays blocked until a loop runs, or shut touches the records of an issue with
# no blocked card. A case of its own on a main of its own, beside t_shut.
t_shutboard() {
  local c8=c0-8
  setup "[$(issue 8 2026-02-01)]"; shutrec 8
  before=$(cat "$ST/cards.jsonl"); loop shut 9 >/dev/null || fail "shut of #9, which has no card, exited non-zero"
  [ "$(cat "$ST/cards.jsonl")" = "$before" ] || fail "shut 9 changed the card records, though #9 has no card"
  loop shut 8 >/dev/null || fail "shut 8 exited non-zero"
  [ "$(loop health | jq -c '.blocked | map(.issue) | index(8)')" = null ] && [ "$(loop snapshot --fresh | jq -c '[.needsYou.blocked[], .needsYou.waiting[]] | map(.issue) | index(8)')" = null ] \
    || fail "#8 is still under Needs you after shut 8: $(loop health | jq -c '[.blocked, .waiting]')"
  [ "$(st "select(.card == \"$c8\") | [.step, .reason] | join(\"|\")" | tail -n 1)" = 'closed|the issue was closed by hand while the card was blocked' ] \
    || fail "no closed line says #8 was shut: $(grep "$c8" "$ST/cards.jsonl")"
  loop check || fail "the records do not check after shut"
}

# A hand change landed by land-branch is a card of issue 0. Blocked by its review, then landed by a second land-branch,
# it stayed under Needs you for good: shut took only a main-red fix card's id (#878). Bugs: `shut <its card id>` is
# refused, or loses its kept patch or moves its branch; Needs you does not say that its branch's change is already on
# main, or says so of a branch whose change is not; shut takes the id of an issue-0 card that is neither kind.
t_shutbranch() {
  local c=c20261120T013602-x-0 b=c20261120T013603-x-0 o=c20261120T013604-x-0 snap before tip
  setup '[]'; mkdir -p "$ST/kept/$c"
  # hand/one: its change is on main (made at main's tip). hand/two: a change main does not have.
  git -C "$R" branch hand/one && git -C "$R" switch -q -c hand/two && echo three >> "$R/a.txt" && git -C "$R" commit -qam three \
    && git -C "$R" switch -q - && echo two >> "$R/a.txt" && git -C "$R" diff > "$ST/kept/$c/$c.patch" && git -C "$R" reset -q --hard \
    || fail "the branches and the kept patch of $c"
  tip=$(git -C "$R" rev-parse hand/one)
  jq -cn --arg c "$c" --arg b "$b" --arg o "$o" --arg k "kept/$c" '{issue:0,time:"2026-11-01T00:00:00Z",tokens:{claude:0,codex:0},result:"ok",sha:"",reason:""}
    | (. + {card:$c,step:"picked",title:"hand one",branch:"hand/one"}), (. + {card:$c,step:"blocked",result:"blocked",reason:"NO-GO: review 1.",kept:$k}),
      (. + {card:$b,step:"picked",title:"hand two",branch:"hand/two"}), (. + {card:$b,step:"blocked",result:"blocked",reason:"NO-GO: review 1."}),
      (. + {card:$o,step:"picked",title:"neither"}), (. + {card:$o,step:"blocked",result:"blocked",reason:"build: it failed"})' > "$ST/cards.jsonl"
  snap=$(loop snapshot --fresh) || fail "snapshot exited non-zero"
  # The reason stays as recorded: the Board reads a review's finding and the failing tests by its form.
  [ "$(jq -c '.needsYou.blocked | map(select(.onMain == true)) | map(.card)' <<<"$snap")" = "[\"$c\"]" ] \
    && jq -e --arg c "$c" '.needsYou.blocked[] | select(.card == $c) | .reason == "NO-GO: review 1."' <<<"$snap" >/dev/null \
    || fail "Needs you does not say that hand/one alone is already on main, or changed its reason: $(jq -c '.needsYou.blocked | map([.card, .onMain, .reason])' <<<"$snap")"
  before=$(cat "$ST/cards.jsonl")
  ! loop shut "$o" >/dev/null 2>&1 && [ "$(cat "$ST/cards.jsonl")" = "$before" ] || fail "shut took $o, an issue-0 card that is no main-red fix card and no land-branch card"
  loop shut "$c" >/dev/null || fail "shut $c exited non-zero"
  [ "$(st "select(.card == \"$c\") | [.step, .reason] | join(\"|\")" | tail -n 1)" = "closed|the issue was closed by hand while the card was blocked" ] \
    || fail "no closed line says $c was shut: $(grep "$c" "$ST/cards.jsonl")"
  [ "$(loop snapshot --fresh | jq -c '.needsYou.blocked | map(.card)')" = "[\"$b\",\"$o\"]" ] || fail "Needs you after shut $c is not the other two cards"
  [ -s "$ST/kept/$c/$c.patch" ] && [ "$(git -C "$R" rev-parse hand/one)" = "$tip" ] || fail "shut lost the kept patch of $c, or moved its branch"
}

# A reopened issue is given back by a turn only when its newest card was shut (#599). Bugs: an open issue whose card
# landed is given back (its lines moved, a new card picked: its work is on main); a shut card whose process is still
# ending is given back before that process ends (it would write a blocked line after its lines moved, and lose its
# change); once it has ended, the shut card is still not given back.
t_reopenonly() {
  local p t open
  setup "$(jq -cs . <(issue 5 2026-01-01) <(issue 6 2026-02-01))"; mkdir -p "$ST"; open=$(cat "$STUB/issues.json")
  sleep 60 & p=$!; t=$(. "$SRC/lib/portable.sh"; p_started "$p") # sleep: a stand-in for the shut card's process, still ending
  { landed 5
    jq -cn --argjson p "$p" --arg t "$t" '{card:"c0-6",issue:6,time:"2026-11-01T00:00:00Z",tokens:{claude:0,codex:0},result:"ok",sha:"",reason:""}
      | (. + {step:"picked"}), (. + {step:"worktree",pid:$p,started:$t}), (. + {step:"blocked",result:"blocked",reason:"NO-GO"}),
        (. + {step:"closed",reason:"the issue was closed by hand while the card was blocked"})'; } > "$ST/cards.jsonl"
  loop check || fail "the fixture does not check"; before=$(cat "$ST/cards.jsonl")
  fx_in "reopened '$open'"
  [ "$(cat "$ST/cards.jsonl")" = "$before" ] && [ ! -s "$ST/retried.jsonl" ] || fail "a turn moved lines of the landed #5 or of #6 while its card's process ran: $(cat "$ST/retried.jsonl" 2>/dev/null)"
  kill "$p"; wait "$p" 2>/dev/null; fx_in "reopened '$open'"
  [ "$(jq -r .card "$ST/retried.jsonl" | sort -u)" = c0-6 ] || fail "once its process ended, #6's shut card alone was not given back (exit $RC): $(cat "$ST/retried.jsonl" 2>/dev/null)"
  [ "$(st '"\(.issue) \(.step)"')" = '5 landed' ] || fail "the landed #5 lost its lines, or #6's stayed: $(st '"\(.issue) \(.step)"' | tr '\n' ',')"
}

# Bugs: a card whose issue is already fixed on main is blocked for leaving no change, and the issue stays
# open; the brief does not ask for the ALREADY-DONE line; the session's word alone closes an issue, or closes it
# over the reviewer's NO-GO; a session that left no change and no such line (or one that is not its last line) is
# reviewed or closed instead of blocked; the report lists a closed card as open, or the dashboard does not count it;
# the reviewer reads the main the session started from, not today's; a GO closes the issue although main moved
# during that review (another card may have removed the fix); the closed line has no waitSec, so the drift watch
# (bench/drift.sh) leaves the closed card out of its mean wait.
# The cards' steps after a session that changed nothing are called as card() calls them: nochange() (the reply's last
# line, the review of an ALREADY-DONE line, the block), and closed() under the lock (main moved during the review).
# donewt <issue> <reply>...: a fresh main with those issues, a picked line of card c0-<issue> of each and its worktree on
# main, cards/c0-<issue>, beside which its session, which changed nothing, left the reply (its .out, and an empty .err);
# the reviewer's prompt is kept in $STUB/asked; head is main's commit.
donewt() {
  local s='' n
  for ((n = 1; n < $#; n += 2)); do s+="$(issue "${!n}" 2026-01-01),"; done
  setup "[${s%,}]"; mkdir -p "$ST" "$T/$CASE/cards"; head=$(git -C "$R" rev-parse HEAD)
  while [ $# -gt 1 ]; do
    landed "$1" | jq -c '.step = "picked" | .sha = "" | .title = "title \(.issue)" | del(.product)' >> "$ST/cards.jsonl"
    git -C "$R" worktree add -q --detach "$T/$CASE/cards/c0-$1" || fail "the worktree of c0-$1"
    jq -cn --arg r "$2" '{type: "result", is_error: false, result: $r}' > "$T/$CASE/cards/c0-$1.out" && : > "$T/$CASE/cards/c0-$1.err"
    shift 2
  done
  sed -i 's|^cat > /dev/null; echo x|cat > "$STUB/asked"; echo x|' "$STUB/codex"
}
DONE='ALREADY-DONE: a.txt already holds the word one'
# Main moves after the session began: the reviewer reads the new main, not the one the session started from. The
# brief is the card's own (brief()), and the card has waited 4 s on other cards (waitsec, as card() keeps it).
t_done() {
  donewt 7 $'I looked.\n\n'"$DONE"$'\n'; echo "$GO" > "$STUB/review.1"
  git -C "$R" commit -q --allow-empty -m "landed during the session"; head=$(git -C "$R" rev-parse HEAD)
  echo 'git rev-parse HEAD > "$STUB/reviewed"' > "$STUB/review-cmd"
  fx_in 'cd "$R" && waitsec=4 && b=$(brief c0-7 "$(gh issue view 7 --json number,title,body,labels,milestone)" "$(header)") && nochange c0-7 7 "$CONVEYOR_CARDS/c0-7" "$b"'
  [ "$RC" = 0 ] || fail "nochange exited $RC: $(cat "$T/$CASE/run.out")"
  grep -q 'ALREADY-DONE: <where it is fixed' "$STUB/asked" || fail "the brief does not ask for the ALREADY-DONE line"
  grep -q 'changed nothing' "$STUB/asked" && grep -q '# Issue #7:' "$STUB/asked" && [ "$(tail -n 1 "$STUB/asked")" = "$DONE" ] \
    && ! grep -q 'git diff --cached' "$STUB/asked" || fail "the reviewer was not asked to confirm the issue and the ALREADY-DONE line: $(cat "$STUB/asked")"
  [ "$(cat "$STUB/reviewed")" = "$head" ] || fail "the reviewer did not read main as it stood when the review started"
  [ "$(st '.step' | tr '\n' ' ')" = "picked start review closed " ] || fail "steps of a card whose issue is already fixed: $(st '.step' | tr '\n' ' ')"
  [ "$(st 'select(.step == "closed") | [.result, .sha, .reason] | join("|")')" = "ok||$DONE" ] || fail "closed line: $(st 'select(.step == "closed")')"
  [ "$(st 'select(.step == "closed") | .waitSec')" = 4 ] || fail "the closed line does not carry the card's wait: $(st 'select(.step == "closed")')"
  [ "$(cat "$STUB/closed")" = 7 ] && grep -qF "$DONE" "$STUB/close-comments" || fail "issue #7 was not closed with the ALREADY-DONE line: $(cat "$STUB/close-comments" 2>&1)"
  [ "$(git -C "$R" rev-parse HEAD)" = "$head" ] && [ -z "$(git -C "$R" status --porcelain)" ] && [ -z "$(ls "$T/$CASE/cards")" ] || fail "something was committed, or main is dirty, or the worktree is left: $(ls "$T/$CASE/cards")"
  loop check || fail "the record check refuses a closed line"
  [ "$(loop cards | jq -c '[.landed, .blocked, .open, .cards[0].step]')" = '[1,0,0,"closed"]' ] || fail "a closed card is not counted like a landed one: $(loop cards)"
  out=$(CONVEYOR_MAIN=$R bash "$SRC/report.sh") || fail "report exited non-zero"
  grep -Eq '^cards landed +1$' <<<"$out" && ! grep -q '^open ' <<<"$out" || fail "the report does not count a closed card like a landed one: $out"
  ! loop retry 7 >/dev/null 2>&1 || fail "retry took back a card that closed its issue"
}

# The reviewer disagrees: blocked, its findings posted, the issue left open.
t_donenogo() {
  donewt 8 "$DONE"; echo "$NOGO" > "$STUB/review.1"
  fx_in 'cd "$R" && nochange c0-8 8 "$CONVEYOR_CARDS/c0-8" "the brief of # Issue #8:"'
  [ "$RC" = 0 ] || fail "nochange exited $RC: $(cat "$T/$CASE/run.out")"
  # Bug (#495): the reason said the kept folder holds the session's errors, but the review writes its own in their place.
  local c=c0-8
  st 'select(.issue == 8 and .step == "blocked") | .reason' | grep -qF "the issue asks. Its session's output and the last error output (of its review, when the review started) are kept in kept/$c/. ALREADY-DONE: a.txt already" || fail "a NO-GO on ALREADY-DONE does not say the kept errors are the review's: $(st 'select(.issue == 8 and .step == "blocked") | .reason')"
  st 'select(.issue == 8 and .step == "blocked") | .reason' | grep -q 'reviewer says that main does not do what the issue asks.*ALREADY-DONE: a.txt already' || fail "a NO-GO on ALREADY-DONE did not block with the reason: $(st 'select(.issue == 8) | "\(.step) \(.reason)"')"
  [ "$(st 'select(.issue == 8 and .step == "review") | .result')" = NO-GO ] && grep -q '^8 --body .*blocked' "$STUB/comments" && grep -q 'wrong word' "$STUB/comments" || fail "the disagreeing review is not recorded or not posted on the issue"
  [ ! -e "$STUB/closed" ] && [ "$(wc -l < "$STUB/reviews")" = 1 ] || fail "issue #8 was closed over a NO-GO, or it got a second review"
}

# closed() on card c0-<issue>'s worktree, at main's commit h as the reviewer read it, after main moved to m by
# <move> during the review. Its exit is in $RC, the reason it prints in run.out.
donemove() { # <issue> <move>
  donewt "$1" "$DONE"
  (cd "$R" && eval "$2") && [ "$(git -C "$R" rev-parse HEAD)" != "$head" ] || fail "main did not move during the review"
  fx_in "cd \"\$R\" && locked closed c0-$1 $1 \"\$CONVEYOR_CARDS/c0-$1\" '$DONE'"
}
# Main moves during the review and replaces the word one in a.txt, the line the ALREADY-DONE line cites, so the fix
# is gone: closed() refuses, saying why, and the issue stays open.
t_donemoved() {
  donemove 11 'echo two > a.txt && git commit -qam "landed during the review"'
  [ "$RC" = 1 ] && grep -q '^the reviewer confirmed that main already fixes the issue, but main changed during that review' "$T/$CASE/run.out" \
    || fail "a GO for a main that moved and changed a.txt was not refused with the reason (exit $RC): $(cat "$T/$CASE/run.out")"
  [ ! -e "$STUB/closed" ] && [ -z "$(st 'select(.issue == 11 and .step == "closed")')" ] || fail "issue #11 was closed although main moved during the review"
}

# Bug (#552): main moved during the review but left a.txt, the file the ALREADY-DONE line names, as it was; the card
# was blocked anyway, and on a busy belt every retry's review met another move. The engine checks the named file
# against the new main and closes the issue.
t_donemovedkept() {
  donemove 12 'echo other > other.txt && git add other.txt && git commit -qm "landed during the review"'
  [ "$RC" = 0 ] && [ ! -s "$T/$CASE/run.out" ] || fail "closed() refused although main kept a.txt (exit $RC): $(cat "$T/$CASE/run.out")"
  [ "$(cat "$STUB/closed" 2>&1)" = 12 ] && grep -qF "$DONE" "$STUB/close-comments" && [ "$(st 'select(.issue == 12 and .step == "closed") | [.result, .reason] | join("|")')" = "ok|$DONE" ] \
    || fail "issue #12 was not closed although main kept a.txt: $(st 'select(.issue == 12) | "\(.step) \(.reason)"')"
}

# t_donemoved calls closed() alone; this runs the card's step, nochange(), whose reviewer moves main and replaces
# a.txt, the file the line cites. Bug: closed()'s refusal is lost in nochange() (lib/followups.sh), so the issue is
# closed, or the card is left with no blocked line, or one that does not say why.
t_donereviewmoved() {
  donewt 13 "$DONE"; echo "$GO" > "$STUB/review.1"
  echo '(cd "$R" && echo two > a.txt && git commit -qam "landed during the review")' > "$STUB/review-cmd"
  fx_in 'cd "$R" && nochange c0-13 13 "$CONVEYOR_CARDS/c0-13" "the brief of # Issue #13:"'
  [ "$RC" = 0 ] && [ "$(git -C "$R" show HEAD:a.txt)" = two ] || fail "nochange exited $RC, or main did not move during the review: $(cat "$T/$CASE/run.out")"
  st 'select(.issue == 13 and .step == "blocked") | .reason' | grep -qF "but main changed during that review. The fix is possibly not on main now, so the engine did not close the issue. Its session's output" \
    && st 'select(.issue == 13 and .step == "blocked") | .reason' | grep -qF "$DONE" || fail "the card was not blocked with closed()'s reason: $(st 'select(.issue == 13) | "\(.step) \(.reason)"')"
  [ ! -e "$STUB/closed" ] && [ -z "$(st 'select(.issue == 13 and .step == "closed")')" ] || fail "issue #13 was closed although the cited a.txt changed during the review"
}

# No change and no ALREADY-DONE last line (#9 says it, but not last; #10 does not say it): blocked as before, with no review.
# Bug (#495): the reason did not say what the session replied or where its output and errors are kept, so the owner
# could not tell why it stopped. It quotes the last reply, on one line, and names the kept folder, which holds both.
t_doneempty() {
  donewt 9 $'ALREADY-DONE: a.txt holds it\nI changed nothing.' 10 $'I looked.\n\nI could not find the file named in the issue'
  local c r said n
  fx_in 'cd "$R" && nochange c0-9 9 "$CONVEYOR_CARDS/c0-9" brief && nochange c0-10 10 "$CONVEYOR_CARDS/c0-10" brief'
  [ "$RC" = 0 ] || fail "nochange exited $RC: $(cat "$T/$CASE/run.out")"
  for n in 9 10; do
    c=c0-$n; r=$(st "select(.issue == $n and .step == \"blocked\") | .reason")
    case $n in 9) said='ALREADY-DONE: a.txt holds it I changed nothing.' ;; 10) said='I looked. I could not find the file named in the issue' ;; esac
    [ "$r" = "the session made no change, so there is nothing to review. Its session's output and errors are kept in kept/$c/. Its last reply: $said" ] \
      || fail "issue $n: no change and no ALREADY-DONE last line was not blocked with its reply and kept folder: $r"
    [ -s "$ST/kept/$c/$c.out" ] && [ -e "$ST/kept/$c/$c.err" ] && [ ! -e "$T/$CASE/cards/$c.out" ] || fail "issue $n: the session's output and errors are not in kept/$c/: $(ls "$ST/kept/$c" 2>&1)"
    # Bug: with no findings and no patch, block() did not post the reason, so the issue did not say where the logs are.
    grep -qF "$n --body Conveyor card $c is blocked: $r" "$STUB/comments" || fail "issue $n: the reason naming its kept folder was not posted on the issue: $(cat "$STUB/comments" 2>&1)"
  done
  [ ! -e "$STUB/reviews" ] && [ ! -e "$STUB/closed" ] && [ "$(git -C "$R" rev-parse HEAD)" = "$head" ] || fail "a card with no change and no ALREADY-DONE line was reviewed, closed or landed"
}
