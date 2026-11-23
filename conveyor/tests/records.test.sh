#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 300
# Engine cases: the report, the card list and retry.
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

# Bug (#1457, R78): a refused unblock took its hold off with `control release`, which also marks the issue as released
# for good (startSeen). An outside issue under Held with no card yet (#9) was left released by `unblock 9 --hold`, so
# the filing hook's adopt no longer held it and the loop would build an issue no one approved. The refused unblock
# leaves held and startSeen as they were, and adopt still holds #9.
t_unblockseen() {
  setup '[]'
  jq -c '.start = "held" | .startHeld = [{from: 6, to: null}]' "$ST/control.json" > "$STUB/c.new" && mv "$STUB/c.new" "$ST/control.json"
  loop unblock 9 --hold >/dev/null 2>&1 && fail "unblock 9 --hold, #9 with no card, exited 0"
  [ "$(jq -c '[.held, .startSeen]' "$ST/control.json")" = '[[],[]]' ] || fail "the refused unblock 9 --hold left held or startSeen changed: $(cat "$ST/control.json")"
  [ "$(loop control adopt 9 | jq -c .held)" = '[9]' ] || fail "control adopt 9, after the refused unblock 9 --hold, did not hold #9: $(cat "$ST/control.json")"
}

# Bug (#1472): a refused unblock took its hold off control.json but left the move to Held in moved.json, the Board's
# history, so the next snapshot or adopt kept the failed command's Held time. The refused unblock leaves the issue's
# entry as it was (none for #9, its Queue entry for #8) and the entry of another issue (#5) alone.
t_unblockmoved() {
  setup '[]'
  echo '{"8":{"col":"queue","other":false,"by":null,"seen":"2026-11-01T00:00:00Z","at":"2026-11-01T00:00:00Z"},"5":{"col":"held","at":"2026-11-02T00:00:00Z","seen":"2026-11-02T00:00:00Z"}}' > "$ST/moved.json"
  cp "$ST/moved.json" "$STUB/moved.was"
  loop unblock 9 --hold >/dev/null 2>&1 && fail "unblock 9 --hold, #9 with no card, exited 0"
  loop unblock 8 --hold >/dev/null 2>&1 && fail "unblock 8 --hold, #8 with no card, exited 0"
  [ "$(jq -cS . "$ST/moved.json")" = "$(jq -cS . "$STUB/moved.was")" ] || fail "a refused unblock 9 --hold and 8 --hold left moved.json changed: $(cat "$ST/moved.json")"
}

# Bug (#1472): a snapshot copies control.json without the records' lock, so a copy taken while a refused
# unblock held #9 for a moment still lists #9 held when the snapshot dates its sight, after the rollback. Written then,
# the sight dated a Held move that never stood, and the next hold kept its time. The sight of an issue held by your hold
# alone (alone) that the live control record no longer holds is not written: #9 stays without an entry, and #8 keeps its
# whole Queue entry (its time too). #7, still held, is dated; so is #6, which a rule keeps in Held (not alone): its
# hold taken off (a release) does not take its Held time away.
t_unblocksnap() {
  setup '[]'
  jq -c '.held = [7]' "$ST/control.json" > "$STUB/c.new" && mv "$STUB/c.new" "$ST/control.json"
  echo '{"8":{"col":"queue","other":false,"by":null,"seen":"2026-11-01T00:00:00Z","at":"2026-11-01T00:00:00Z"}}' > "$ST/moved.json"
  cp "$ST/moved.json" "$STUB/moved.was"
  jq -cn '[6, 7, 8, 9] | map({key: tostring, value: {col: "held", other: false, by: null, alone: (. != 6)}}) | from_entries' > "$STUB/cols.json"
  fx_in 'movedlocked movedsaw "$(cat "$STUB/cols.json")" 2026-11-05T00:00:00Z'
  [ "$RC" = 0 ] || fail "movedsaw with a copy that held #6, #7, #8 and #9 exited $RC: $(cat "$T/$CASE/run.out")"
  [ "$(jq -c '[(.["6", "7"] | .at), has("9")]' "$ST/moved.json")" = '["2026-11-05T00:00:00Z","2026-11-05T00:00:00Z",false]' ] \
    || fail "#6 (a rule keeps it) and #7 (held) are not dated, or #9 (no longer held) is: $(cat "$ST/moved.json")"
  [ "$(jq -cS '.["8"]' "$ST/moved.json")" = "$(jq -cS '.["8"]' "$STUB/moved.was")" ] || fail "#8, no longer held, lost its Queue entry or its time: $(cat "$ST/moved.json")"
}

# Bug (#1472): a release that came while a snapshot ran, after its copy of the control record, took the Held time of
# #9 away: #9 stays in Held (a P3 rule is off), but the snapshot dated no entry for it, and the next snapshot gave it
# its own time. #8 (held by your hold alone, then released) gets no entry for a Held it left. This runs the snapshot
# because it is the snapshot that says which issues are held by your hold alone.
t_releasesnap() {
  setup "[$(issue 5 2026-03-01 P2)]"
  loop control start held >/dev/null 2>&1 || fail "start held was refused"
  jq -c ". + [$(issue 8 2026-03-02 P2), $(issue 9 2026-03-02 P3)]" "$STUB/issues.json" > "$STUB/i" && mv "$STUB/i" "$STUB/issues.json"
  loop control rules P3=off >/dev/null
  on() { local t=$1; shift; CONVEYOR_NOW=$(date -u -d "$t" +%s) loop "$@"; }
  # The pack's progress command runs after the snapshot's copy of the control record and before it dates its sight.
  tuned '.checks = {run: [], progress: "CONVEYOR_NOW=$(date -u -d 2026-10-02 +%s) bash '"$SRC"'/conveyor.sh control release 8 9 >/dev/null"}' on 2026-10-01 snapshot --fresh >/dev/null
  [ "$(jq -c '[has("8"), .["9"].col, .["9"].at]' "$ST/moved.json")" = '[false,"held","2026-10-01T00:00:00Z"]' ] \
    || fail "#8 (held by your hold alone) has an entry, or #9 (a rule keeps it) has none, after the release: $(cat "$ST/moved.json")"
  out=$(on 2026-10-03 snapshot --fresh) || fail "the second snapshot exited non-zero"
  [ "$(jq -c '.open.held | map([.issue, .since])' <<<"$out")" = '[[9,"2026-10-01T00:00:00Z"]]' ] || fail "#9, in Held all along, is not held since its first sight: $(jq -c '.open.held' <<<"$out")"
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
