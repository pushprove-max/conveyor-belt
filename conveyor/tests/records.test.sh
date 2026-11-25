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
  # #1676: the hold a refused `unblock 9 --hold` takes back is a dropped hold, logged as unblock's, not the owner's.
  [ "$(jq -sc 'map({issue, by})' "$S/holds-dropped.jsonl" 2>&1)" = '[{"issue":9,"by":"unblock: its retry was refused"}]' ] \
    || fail "unblock 9 --hold, refused, did not log its hold of #9 dropped by unblock: $(cat "$S/holds-dropped.jsonl" 2>&1)"
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
# Bug (#1627): a refused unblock put the hold back off, but not the owner's release time the hold took out (released),
# so foreman status no longer said the owner had released #9, and the Foreman took the missing hold for a fault.
t_unblockreleased() {
  setup '[]'
  loop control hold 9 >/dev/null && CONVEYOR_NOW=$(jq -n '"2026-11-24T10:15:00Z" | fromdate') loop control release 9 >/dev/null || fail "control hold 9, release 9 failed"
  loop unblock 9 --hold >/dev/null 2>&1 && fail "unblock 9 --hold, #9 with no card, exited 0"
  [ "$(jq -c '[.held, .released]' "$ST/control.json")" = '[[],{"9":"2026-11-24T10:15:00Z"}]' ] \
    || fail "after unblock 9 --hold was refused, the hold or the owner's release time of #9 is not as before: $(jq -c '[.held, .released]' "$ST/control.json")"
}
# Bugs: a retry by the standing review-retry (the Foreman's watcher sends it as CONVEYOR_REVIEWRETRY, foreman/lib.sh
# ask()) released its held issue, so the loop picked an issue the owner never released (#1627 dated it in released as
# the owner's release). It gives the card back and leaves the hold, with no release dated.
t_retrynotowner() {
  local out
  setup "$(issue 7 2026-01-01 | jq -cs .)"
  landed 7 | jq -c '.step = "blocked" | .result = "blocked" | .reason = "review: NO-GO"' >> "$ST/cards.jsonl"
  loop control hold 7 >/dev/null || fail "control hold 7 failed"
  out=$(CONVEYOR_REVIEWRETRY=1 loop retry 7 2>&1) || fail "CONVEYOR_REVIEWRETRY=1 retry 7, #7 held, failed: $out"
  jq -se 'any(.[]; .issue == 7 and .step == "blocked" and .retriedBy == "review-retry")' "$ST/retried.jsonl" >/dev/null 2>&1 \
    || fail "CONVEYOR_REVIEWRETRY=1 retry 7 did not give the card of #7 back: $out"
  [ "$(jq -c '[.held, .released]' "$ST/control.json")" = '[[7],{}]' ] && grep -qF 'issue #7 is held, and stays held' <<<"$out" \
    || fail "CONVEYOR_REVIEWRETRY=1 retry 7, #7 held, released #7, dated a release, or did not say it stays held: $(jq -c '[.held, .released]' "$ST/control.json"); $out"
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

# Bug: unblock read #9's entry in moved.json, then held #9, each in a lock of its own. A snapshot that wrote #9's first
# Queue entry between the two was erased by a refused unblock's undo, which put back the older read (none), and the
# next snapshot dated #9 in Queue anew. A stand-in snapshot runs just before the hold, if moved.json's lock is free
# then; the refused unblock must leave #9's entry as it was just before the hold. The command's own unblock() runs (its
# file loaded without its last line, the call), so the stand-in can wrap control() after the file loads lib/control.sh.
t_unblockrace() {
  setup '[]'
  fx_in 'set -- unblock 9 --hold; eval "$(sed "\$d" "$SRC/commands/unblock.sh")"
    eval "$(declare -f control | sed "1s/^control/realcontrol/")"
    control() { ! flock -n "$MOVED.lock" true || movedsaw "{\"9\":{\"col\":\"queue\",\"other\":false,\"by\":null,\"alone\":false}}" 2026-11-05T00:00:00Z >/dev/null
      movedread | jq -c ".[\"9\"]" > "$STUB/before"; realcontrol "$@"; }
    locked unblock 9 && exit 3; jq -c ".[\"9\"]" "$MOVED" > "$STUB/after"'
  [ "$RC" != 3 ] || fail "unblock 9 --hold, #9 with no card, exited 0: $(cat "$T/$CASE/run.out")"
  [ -s "$STUB/before" ] || fail "unblock 9 --hold did not hold #9 through control(): $(cat "$T/$CASE/run.out")"
  [ "$(cat "$STUB/after")" = "$(cat "$STUB/before")" ] \
    || fail "the refused unblock 9 --hold left #9's moved.json entry $(cat "$STUB/after"), but it was $(cat "$STUB/before") just before the hold"
}

# Bug: a refused unblock took #9's hold off control.json, then put back #9's entry in moved.json, each in a lock of its
# own. A snapshot that read control.json between the two wrote #9's first Queue entry, and the undo wrote "none" over
# it. A stand-in snapshot (a Queue sight dated after the hold) starts just after the hold is taken off: at once if
# moved.json's lock is free then, else in the background, where it waits for the lock. Its Queue entry must stay.
# The case polls for the background stand-in's mark: only a second process can wait on the lock the rollback holds.
t_unblockundo() {
  setup '[]'
  fx_in 'set -- unblock 9 --hold; eval "$(sed "\$d" "$SRC/commands/unblock.sh")"
    eval "$(declare -f ctlput | sed "1s/^ctlput/realctlput/")"
    snap() { movedsaw "{\"9\":{\"col\":\"queue\",\"other\":false,\"by\":null,\"alone\":false}}" 2099-01-01T00:00:00Z >/dev/null; touch "$STUB/snapped"; }
    ctlput() { realctlput "$@" || return 1; jq -e ".held | index(9) == null" <<<"$2" >/dev/null || return 0
      if flock -n "$MOVED.lock" true; then movedlocked snap; else ( unset MOVED_IN; movedlocked snap ) 3>&- & fi; }
    locked unblock 9 && exit 3; exit 0'
  [ "$RC" != 3 ] || fail "unblock 9 --hold, #9 with no card, exited 0: $(cat "$T/$CASE/run.out")"
  wait_until '[ -e "$STUB/snapped" ]' || fail "the stand-in snapshot did not run after unblock 9 --hold took the hold off: $(cat "$T/$CASE/run.out")"
  local after; after=$(jq -c '.["9"] | [.col, .seen]' "$ST/moved.json")
  [ "$after" = '["queue","2099-01-01T00:00:00Z"]' ] \
    || fail "a snapshot that read control.json after the refused unblock 9 --hold took the hold off lost its Queue entry for #9: $after"
}

# Bug (#1472): a snapshot copies control.json without the records' lock, so a copy taken while a refused
# unblock held #9 for a moment still lists #9 held when the snapshot dates its sight, after the rollback. Written then,
# the sight dated a Held move that never stood, and the next hold kept its time. The sight of an issue held by your hold
# alone (alone) that the live control record no longer holds is not written: #9 stays without an entry, and #8 keeps its
# whole Queue entry (its time too). #7, still held, is dated; so is #6, which a rule keeps in Held (not alone): its
# hold taken off (a release) does not take its Held time away.
t_unblocksnap() {
  setup '[]'
  # Bug it catches (E1): movedsaw gave jq moved.json and control.json as arguments, and a file over 128 KiB (one
  # argument's limit on Linux) stopped jq with "Argument list too long". Both are padded over it: moved.json with old
  # Queue entries of other issues (dropped as not seen since), control.json with a field nothing reads.
  jq -c '.held = [7] | .pad = ("x" * 140000)' "$ST/control.json" > "$STUB/c.new" && mv "$STUB/c.new" "$ST/control.json"
  echo '{"8":{"col":"queue","other":false,"by":null,"seen":"2026-11-01T00:00:00Z","at":"2026-11-01T00:00:00Z"}}' > "$STUB/moved.was"
  jq -c '. + ([range(10000; 12000) | {key: tostring, value: {col: "queue", other: false, by: null, seen: "2026-10-01T00:00:00Z",
    at: "2026-10-01T00:00:00Z", pad: "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"}}] | from_entries)' "$STUB/moved.was" > "$ST/moved.json"
  jq -cn '[6, 7, 8, 9] | map({key: tostring, value: {col: "held", other: false, by: null, alone: (. != 6)}}) | from_entries' > "$STUB/cols.json"
  # Each jq movedsaw starts is noted: it runs on every snapshot, and the live control record's read (gone) added a jq.
  fx_in 'jq() { echo jq >> "$STUB/jq.log"; command jq "$@"; }; movedlocked movedsaw "$(cat "$STUB/cols.json")" 2026-11-05T00:00:00Z'
  [ "$RC" = 0 ] || fail "movedsaw with a copy that held #6, #7, #8 and #9 exited $RC: $(cat "$T/$CASE/run.out")"
  # Bug it catches (snapexec over its bound): movedsaw read moved.json, the stays, the live control record (gone) and the
  # sight each with a jq of its own; one jq works all out.
  [ "$(wc -l < "$STUB/jq.log")" -eq 1 ] || fail "movedsaw with a copy that held #6, #7, #8 and #9 started $(wc -l < "$STUB/jq.log") jq, not 1"
  [ "$(jq -c '[(.["6", "7"] | .at), has("9")]' "$ST/moved.json")" = '["2026-11-05T00:00:00Z","2026-11-05T00:00:00Z",false]' ] \
    || fail "#6 (a rule keeps it) and #7 (held) are not dated, or #9 (no longer held) is: $(cat "$ST/moved.json")"
  [ "$(jq -cS '.["8"]' "$ST/moved.json")" = "$(jq -cS '.["8"]' "$STUB/moved.was")" ] || fail "#8, no longer held, lost its Queue entry or its time: $(cat "$ST/moved.json")"
}

# The cases below give movedsaw() the sight of a snapshot whose copy of the control record saw P3 #9 in Held, at <saw>,
# with your hold alone (<alone>: true) or with the P3 rule (false), and with a label or dependency (<other>: true; false
# when left out), and run `control` at the times it names.
rulesaw() { # <saw> <alone> [<other>]
  jq -cn --argjson a "$2" --argjson x "${3:-false}" '{"9": {col: "held", other: $x, alone: $a, by: {labels: [], fu: false, p: "P3"}}}' > "$STUB/cols.json"
  fx_in 'movedlocked movedsaw "$(cat "$STUB/cols.json")" '"$1"'T00:00:00Z'
  [ "$RC" = 0 ] || fail "movedsaw of P3 #9 at $1 exited $RC: $(cat "$T/$CASE/run.out")"
}
ruleon() { local t=$1; shift; CONVEYOR_NOW=$(date -u -d "$t" +%s) loop "$@" >/dev/null; }

# Bug (follow-up of #1472): a snapshot's copy saw the new P3 #9 held by start-in-Held alone; then `control rules P3=off`
# and `control release 9` came before it dated its sight. #9 stays in Held by the rule, but the sight was not written
# (alone, no longer held), so the next snapshot dated #9 later than its first sight.
t_rulesnap() {
  setup '[]'
  jq -c '.held = [9]' "$ST/control.json" > "$STUB/c.new" && mv "$STUB/c.new" "$ST/control.json"
  ruleon 2026-10-02 control rules P3=off; ruleon 2026-10-02 control release 9
  rulesaw 2026-10-01 true; rulesaw 2026-10-03 false
  [ "$(jq -c '.["9"] | [.col, .at, .left]' "$ST/moved.json")" = '["held","2026-10-01T00:00:00Z",null]' ] \
    || fail "#9, released after P3=off and so in Held all along, is not held since the sight at 2026-10-01: $(cat "$ST/moved.json")"
}

# Bug (E1): the entry the filing hook's adopt wrote (`control hold` writes the same: no `by`) let a release after
# `control rules P3=off` mark #9 as gone from Held, so the next snapshot dated it anew, though the rule kept it there.
t_ruleadopt() {
  setup '[]'
  ruleon 2026-10-01 control hold 9
  ruleon 2026-10-03 control rules P3=off; ruleon 2026-10-03 control release 9
  rulesaw 2026-10-02 true; rulesaw 2026-10-04 false
  [ "$(jq -c '.["9"] | [.col, .at, .left]' "$ST/moved.json")" = '["held","2026-10-01T00:00:00Z",null]' ] \
    || fail "#9, held at 2026-10-01 and released after P3=off, lost its Held time: $(cat "$ST/moved.json")"
}

# The cases below run `control hold 9` (no `by`) on 2026-10-01, then `control release 9` with P3 on and `control
# depends 9 add 8` on 2026-10-02, and a real snapshot on 2026-10-03: it is the snapshot that builds other and nodep from
# the reasons #9 is held for, which a sight given to movedsaw() by hand would set itself. Prints #9's [col, at, left].
depafter() {
  ghedits
  ruleon 2026-10-01 control hold 9; ruleon 2026-10-02 control release 9; ruleon 2026-10-02 control depends 9 add 8
  ruleon 2026-10-03 snapshot --fresh || fail "the snapshot at 2026-10-03 exited non-zero"
  jq -c '.["9"] | [.col, .at, .left]' "$ST/moved.json"
}

# Bug (follow-up of #1472): #9 went to Queue on the release and came back on the dependency, but the snapshot saw
# `other` and took it as held all along, so #9 kept the time of its first hold and the two stays in Held counted as one.
t_ruledepafter() {
  setup "$(jq -cs . <(issue 8 2026-01-01 P3) <(issue 9 2026-01-01 P3))"
  [ "$(depafter)" = '["held","2026-10-03T00:00:00Z",null]' ] \
    || fail "#9, released and back in Held by a dependency added after the release, keeps its first Held time: $(cat "$ST/moved.json")"
}

# Bug (E1): `control depends 9 add 8` for #9 with no entry in moved.json wrote the file blank, so every other issue's
# Held and Queue time was lost.
t_ruledepnew() {
  setup "$(jq -cs . <(issue 8 2026-01-01 P3) <(issue 9 2026-01-01 P3))"
  ghedits; mkdir -p "$ST"; echo '{"7":{"col":"held","at":"2026-10-01T00:00:00Z","seen":"2026-10-01T00:00:00Z"}}' > "$ST/moved.json"
  ruleon 2026-10-02 control depends 9 add 8
  [ "$(jq -c 'keys' "$ST/moved.json")" = '["7"]' ] || fail "control depends 9 add 8, #9 with no entry, did not keep #7's entry in moved.json: $(cat "$ST/moved.json")"
}

# Bug (E2): with a label (awaiting-deploy) that kept #9 in Held all along, a dependency added after `control release 9`
# masked the label too, so the snapshot gave #9 a new Held time though it never left Held. Also caught (E6): a snapshot
# that left the label out of nodep.
t_ruledeplabel() {
  setup "$(jq -cs . <(issue 8 2026-01-01 P3) <(issue 9 2026-01-01 P3 awaiting-deploy))"
  [ "$(depafter)" = '["held","2026-10-01T00:00:00Z",null]' ] \
    || fail "#9, kept in Held by a label, got a new Held time when a dependency was added after the release: $(cat "$ST/moved.json")"
}

# Bug (E3): #9 already named #7, open but landed (push off), so it did not wait on it; the dependency on #8 added after
# the release was taken as not its first, and the snapshot kept #9's first Held time for two stays in Held.
t_ruledeplanded() {
  setup "$(jq -cs . <(issue 7 2026-01-01 P3) <(issue 8 2026-01-01 P3) <(dep "$(issue 9 2026-01-01 P3)" 'Depends on: #7'))"
  mkdir -p "$ST"; landed 7 >> "$ST/cards.jsonl"
  [ "$(depafter)" = '["held","2026-10-03T00:00:00Z",null]' ] \
    || fail "#9, waiting on no landed #7 and back in Held by #8 added after the release, keeps its first Held time: $(cat "$ST/moved.json")"
}

# Bug (E4): #9 already named other/repo#600, closed, so it did not wait on it; `control depends` read that issue with
# no state and took it as open, so the dependency on #8 was not its first, and #9 kept its first Held time.
t_ruledepfar() {
  setup "$(jq -cs . <(issue 8 2026-01-01 P3) <(dep "$(issue 9 2026-01-01 P3)" 'Depends on: other/repo#600'))"
  echo CLOSED > "$STUB/repo.other_repo.600"
  [ "$(depafter)" = '["held","2026-10-03T00:00:00Z",null]' ] \
    || fail "#9, waiting on no closed other/repo#600 and back in Held by #8 added after the release, keeps its first Held time: $(cat "$ST/moved.json")"
}

# Bug (E5): #9's line `Depends on: # 2 3` is not a list of #N, so a rule held #9 before the release and after it; the
# dependency on #8 added after the release was taken as its first, and the snapshot gave #9 a new Held time.
t_ruledepbad() {
  setup "$(jq -cs . <(issue 8 2026-01-01 P3) <(dep "$(issue 9 2026-01-01 P3)" 'Depends on: # 2 3'))"
  [ "$(depafter)" = '["held","2026-10-01T00:00:00Z",null]' ] \
    || fail "#9, kept in Held by the line 'Depends on: # 2 3', got a new Held time when #8 was added after the release: $(cat "$ST/moved.json")"
}

# Bug (E3): a snapshot's copy saw the new P3 #9 held by start-in-Held and a label (awaiting-deploy), with P3 on; a
# `control release 9` before it dated its sight wrote a release with no column, which took the place of the sight and
# was then dropped, so the next snapshot dated #9 later, though the label kept it in Held all along.
t_rulelabel() {
  setup '[]'
  jq -c '.held = [9]' "$ST/control.json" > "$STUB/c.new" && mv "$STUB/c.new" "$ST/control.json"
  ruleon 2026-10-02 control release 9
  rulesaw 2026-10-01 false true; rulesaw 2026-10-03 false true
  [ "$(jq -c '.["9"] | [.col, .at, .left]' "$ST/moved.json")" = '["held","2026-10-01T00:00:00Z",null]' ] \
    || fail "#9, released while a label kept it in Held, is not held since the sight at 2026-10-01: $(cat "$ST/moved.json")"
}

# Bug (E2): `control release 9` with the P3 rule on sends #9 to Queue; `control rules P3=off` after it brings #9 back.
# A sight from a copy taken before both kept its first Held time, so the two stays in Held counted as one.
t_rulelater() {
  setup '[]'
  jq -c '.held = [9]' "$ST/control.json" > "$STUB/c.new" && mv "$STUB/c.new" "$ST/control.json"
  ruleon 2026-10-02 control release 9; ruleon 2026-10-02 control rules P3=off
  rulesaw 2026-10-01 true; rulesaw 2026-10-03 false
  [ "$(jq -c '.["9"] | [.col, .at]' "$ST/moved.json")" = '["held","2026-10-03T00:00:00Z"]' ] \
    || fail "#9, released and back in Held by P3=off after the sight at 2026-10-01, keeps a Held time from before it left: $(cat "$ST/moved.json")"
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
  [ "$(jq -c 'del(.retriedAt, .retriedBy)' "$S/retried.jsonl")" = "$old" ] && [ -n "$old" ] && ! grep -q "\"card\":\"$card\"" "$S/cards.jsonl" || fail "the blocked card's lines were not moved whole to the retried file"
  grep -q '"issue":8,' "$S/cards.jsonl" && grep -q '"issue":9,' "$S/cards.jsonl" || fail "retry took another issue's lines"
  # The blocked line carries when the owner gave the card back: the wait ends there, not at the next pick. It also
  # says the owner gave it back (retriedBy owner), which lets review-retry give the issue back once more (reviewretried()).
  [ "$(jq -r 'select(.step == "blocked") | (.retriedAt | fromdate | now - . < 60) and .retriedBy == "owner"' "$S/retried.jsonl")" = true ] \
    && [ "$(jq -c 'select(.step != "blocked") | [.retriedAt, .retriedBy]' "$S/retried.jsonl" | sort -u)" = '[null,null]' ] \
    || fail "the retried blocked line does not say when it was retried, or that the owner retried it: $(cat "$S/retried.jsonl")"
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
