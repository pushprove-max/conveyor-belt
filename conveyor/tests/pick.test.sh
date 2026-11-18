#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 300
# Engine cases: which issue is picked, and when.
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"
# The engine folder, as lib.sh sets it: named here too, so the release closure (tools/closure.sh) follows this file's paths.
SRC=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)

# Bugs: an older, higher-priority issue is built before a waiting follow-up; a follow-up Conveyor filed
# that no landed line names (its parent has not landed) is built; a follow-up labelled by hand, which no landed
# line will ever name, is never built; a push is allowed while a P0 or
# P1 follow-up is waiting, or held for a P2 one, or still held once the follow-up has a landed line.
t_pushable() {
  setup "$(jq -cs . <(issue 6 2026-01-01 P1) <(issue 50 2026-06-01 conveyor-followup bug P1 backlog) <(issue 51 2026-06-02 conveyor-followup bug P2 | jq -c '.body = "Follow-up to #4 (Conveyor card c0-4). Its review 3 said NO-GO."') <(issue 52 2026-06-03 conveyor-followup bug P2))"
  mkdir -p "$ST"; landed 5 '[50]' > "$ST/cards.jsonl" # #50's parent landed; #51's did not; #52 was filed by hand
  out=$(loop pushable) && fail "pushable with a P1 follow-up waiting"
  grep -q '^#50 P1 title 50$' <<<"$out" && ! grep -Eq '^#(51|52|6) ' <<<"$out" || fail "pushable listed: $out"
  tune '.worktree.setup = "exit 1"'; loop run 1 >/dev/null
  [ "$(st 'select(.step == "picked") | .issue')" = 50 ] || fail "first pick was not the follow-up (its backlog label is for information only): $(st 'select(.step == "picked") | .issue')"
  ! loop pushable >/dev/null || fail "pushable with the P1 follow-up blocked, not landed"
}
# After t_pushable's first run (#50 picked and blocked, its lines as a card's), a case of its own so its two cards run
# beside t_pushable's: a follow-up whose parent has not landed is not picked, one filed by hand is picked before #6,
# and once #50 has a landed line, with only a P2 follow-up waiting, main is pushable.
t_pushablenext() {
  setup "$(jq -cs . <(issue 6 2026-01-01 P1) <(issue 50 2026-06-01 conveyor-followup bug P1 backlog) <(issue 51 2026-06-02 conveyor-followup bug P2 | jq -c '.body = "Follow-up to #4 (Conveyor card c0-4). Its review 3 said NO-GO."') <(issue 52 2026-06-03 conveyor-followup bug P2))"
  mkdir -p "$ST"; landed 5 '[50]' > "$ST/cards.jsonl"
  for s in picked blocked; do
    jq -cn --arg s "$s" '{card:"c1-50",issue:50,step:$s,time:"2026-11-01T00:00:00Z",tokens:{claude:0,codex:0},result:(if $s == "blocked" then "blocked" else "ok" end),sha:"",reason:""}' >> "$ST/cards.jsonl"
  done
  loop pushable >/dev/null && fail "pushable with the P1 follow-up blocked, not landed"
  tune '.worktree.setup = "exit 1"'
  loop run >/dev/null; [ "$(st 'select(.step == "picked") | .issue' | tr '\n' ' ')" = "50 52 6 " ] || fail "a follow-up whose parent has not landed was picked, or one filed by hand was not picked before #6: $(st 'select(.step == "picked") | .issue' | tr '\n' ' ')"
  landed 50 >> "$ST/cards.jsonl"
  out=$(loop pushable) || fail "not pushable though the P1 follow-up has a landed line and only a P2 one waits: $out"
}

# Bug: a common area word pulls hundreds of rulings into the brief, and the review refuses it as too large. The
# brief is the check, so the card's build fails and ends it there.
t_bulk() {
  setup "[$(issue 7 2026-01-01 area:billing)]"; echo 'exit 1' > "$STUB/build"
  for i in $(seq 1 25); do jq -cn --arg i "$i" '{id: ("r-b" + $i), question: "billing?", answer: ("y" * 5000)}'; done >> "$STUB/rulings"
  loop run >/dev/null || fail "run exited non-zero"
  grep -q '"r-b25"' "$STUB/brief" && ! grep -q '"r-b5"' "$STUB/brief" || fail "brief does not hold just the newest 20 rulings"
  [ "$(wc -c < "$STUB/brief")" -lt 20000 ] || fail "brief rulings not cut short: $(wc -c < "$STUB/brief") bytes"
}

# Bugs: the loop picks an issue the order excludes, or records a card when nothing qualifies; a qualifying issue
# listed after the first 1,000 open ones is never picked. An issue labelled awaiting-deploy (built, open until
# the owner deploys it) is built again: alone, or as a follow-up whose parent landed.
# A held issue labelled backlog, dormant or ux-change is picked, or a released one is not (the labels are for
# information only; a hold keeps an issue off the belt).
t_empty() {
  setup "$(jq -cs . <(issue 1 2026-01-01 backlog) <(issue 2 2026-01-01 dormant) <(issue 3 2026-01-01 ux-change) \
    <(issue 4 2026-01-01 awaiting-deploy P0) <(issue 5 2026-01-01 conveyor-followup awaiting-deploy P0))"
  loop control hold 1 2 3 >/dev/null
  loop run | grep -q 'no issue qualifies' || fail "did not say nothing qualifies"
  [ ! -s "$ST/cards.jsonl" ] || fail "recorded a card for an excluded issue"
  # The Board finds the last push's marker in the folder `state-dir` names, never a path of its own.
  [ "$(find "$T/$CASE" -name cards.jsonl)" = "$(loop state-dir)/cards.jsonl" ] || fail "state-dir named $(loop state-dir), not the folder the records are in"
  [ "$(loop snapshot | jq -c '.open.held | map([.issue, (.reasons | map(.label // .kind) | join(","))])')" \
    = '[[1,"you"],[2,"you"],[3,"you"],[4,"awaiting-deploy"],[5,"awaiting-deploy"]]' ] \
    || fail "a held labelled issue is not shown as held by you: $(loop snapshot | jq -c .open.held)"
}
# Released (t_empty holds them), a case of its own so its three cards run beside t_empty: there is no skip list,
# CONVEYOR_SKIP naming the labels keeps none of the released issues off the belt, and the awaiting-deploy ones stay off.
t_emptyrelease() {
  setup "$(jq -cs . <(issue 1 2026-01-01 backlog) <(issue 2 2026-01-01 dormant) <(issue 3 2026-01-01 ux-change) \
    <(issue 4 2026-01-01 awaiting-deploy P0) <(issue 5 2026-01-01 conveyor-followup awaiting-deploy P0))"
  loop control hold 1 2 3 >/dev/null
  loop control release 1 2 3 >/dev/null; tune '.worktree.setup = "exit 1"'; CONVEYOR_SKIP='["backlog","dormant","ux-change"]' loop run >/dev/null
  [ "$(st 'select(.step == "picked") | .issue' | sort -n | tr '\n' ' ')" = "1 2 3 " ] || fail "a released backlog, dormant or ux-change issue was not picked: $(st 'select(.step == "picked") | .issue' | tr '\n' ' ')"
}
# The qualifying issue listed after the first 1,000 open ones, a case of its own beside t_empty. The 1,000 are made
# from one issue in one jq, not one jq each (that took about 2 s).
t_emptyfar() {
  setup "[$(issue 1001 2026-01-01 P1)]"; tune '.worktree.setup = "exit 1"'
  jq -c --argjson t "$(issue 0 2026-01-01 awaiting-deploy)" '[range(1; 1001) as $n | $t | .number = $n | .title = "title \($n)" | .body = "body of \($n)"] + .' \
    "$STUB/issues.json" > "$STUB/issues.new" && mv "$STUB/issues.new" "$STUB/issues.json"
  [ "$(jq -c '[length, .[0].number, .[999].number, .[1000].number, (.[:1000] | all(.labels == [{name: "awaiting-deploy"}]))]' "$STUB/issues.json")" = '[1001,1,1000,1001,true]' ] \
    || fail "the 1,000 awaiting-deploy issues were not listed before the qualifying one"
  loop run 1 >/dev/null
  [ "$(st 'select(.step == "picked") | .issue')" = 1001 ] || fail "the qualifying issue past the first 1,000 was not picked"
}

# Bug: an area:prism issue with the verification integrity label or milestone is never picked, and shows as
# held by a standing rule though the control record does not hold it. Holding it is the one way to keep it off the belt.
t_prism() {
  vi=verification-'integrity' # split so the issue's check, that no file under conveyor/ names the label, still holds
  setup "$(jq -cs . <(issue 6 2026-01-01 area:prism "$vi") <(issue 7 2026-01-02 area:prism | jq -c --arg m "$vi" '.milestone = {title: $m}') \
    <(issue 8 2026-01-03 area:prism "$vi"))"
  loop control hold 8 >/dev/null || fail "control hold failed"
  tune '.worktree.setup = "exit 1"'; loop run >/dev/null
  [ "$(st 'select(.step == "picked") | .issue' | tr '\n' ' ')" = "6 7 " ] || fail "the unheld prism issues were not both picked, or the held one was: $(st 'select(.step == "picked") | .issue' | tr '\n' ' ')"
  [ "$(loop snapshot | jq -c '[.open.held[] | select(.issue == 8) | .reasons[].kind]')" = '["you"]' ] || fail "the held prism issue is not held by the control record alone: $(loop snapshot | jq -c .open.held)"
}

# Bugs: P3 cannot be turned off like P0-P2, so the owner cannot stop the loop building the lowest level; off, an
# issue labelled P3 or with no priority (read as P3) is picked, or is not listed as skipped by the rule P3; on again,
# they are not picked; a record saved before P3 had a switch does not read as P3 on. What is picked is the check, so
# in this file's cases that check only the pick, each card's worktree setup fails and ends it there, before its brief
# and build session (a card that lands costs those, a review and a test run more).
t_p3rule() {
  setup "$(jq -cs . <(issue 5 2026-01-01 P3) <(issue 6 2026-02-01) <(issue 7 2026-03-01 P1))"
  tune '.worktree.setup = "exit 1"'
  picks() { st 'select(.step == "picked") | .issue' | sort | tr '\n' ' '; }
  jq -e '.rules | has("P3") | not' "$ST/control.json" >/dev/null || fail "the seeded record already has a P3 key"
  [ "$(loop control | jq -c .rules.P3)" = true ] || fail "a record with no P3 key does not read as P3 on: $(loop control)"
  [ "$(loop control rules P3=off | jq -c .rules.P3)" = false ] || fail "rules P3=off did not turn P3 off: $(cat "$ST/control.json")"
  [ "$(loop snapshot | jq -c '[(.queue.skipped | map([.issue, .rule]) | sort), (.queue.next | map(.issue))]')" = '[[[5,"P3"],[6,"P3"]],[7]]' ] \
    || fail "P3 off: the P3 and unprioritised issues are not skipped by the rule P3: $(loop snapshot | jq -c .queue)"
  loop run >/dev/null 2>&1; [ "$(picks)" = "7 " ] || fail "P3 off picked a P3 or unprioritised issue: $(picks)"
}
# On again (t_p3rule turns it off), a case of its own so the two runs go side by side: the P3 and unprioritised
# issues are picked. A case's processes share one core (lib/slots.sh), so it has those two cards alone.
t_p3on() {
  setup "$(jq -cs . <(issue 5 2026-01-01 P3) <(issue 6 2026-02-01))"
  tune '.worktree.setup = "exit 1"'
  picks() { st 'select(.step == "picked") | .issue' | sort | tr '\n' ' '; }
  [ "$(loop control rules P3=off | jq -c .rules.P3)" = false ] || fail "rules P3=off did not turn P3 off: $(cat "$ST/control.json")"
  [ "$(loop control rules P3=on | jq -c .rules.P3)" = true ] || fail "rules P3=on did not turn P3 on: $(cat "$ST/control.json")"
  loop run >/dev/null 2>&1; [ "$(picks)" = "5 6 " ] || fail "P3 on did not pick the P3 and unprioritised issues: $(picks)"
}

# Bugs: lowest priority or newest picked first; an issue with a card (open after a restart) picked again; a second
# loop started beside a running one, so the two together pass the builder cap.
t_pick() {
  setup "$(jq -cs . <(issue 5 2026-01-01 P3) <(issue 6 2026-02-01 P1) <(issue 4 2026-03-01 P1) <(issue 8 2026-04-01) <(issue 9 2026-05-01))"
  tune '.worktree.setup = "exit 1"'; mkdir -p "$ST"
  echo '{"card":"c0-4","issue":4,"step":"picked","time":"2026-11-01T00:00:00Z","tokens":{"claude":0,"codex":0},"result":"ok","sha":"","reason":""}' > "$ST/cards.jsonl"
  # Every card writes its lines under the records' lock, so a slow GitHub must never be waited for while it is held:
  # the open issues are never asked for under it. The asker is under it when it inherited the lock's descriptor (an open
  # file of the records) and the lock is held: a lock held only by another process (the card writing its lines while a
  # later turn or the sample asks, as under load) is not the asker's.
  echo 'echo x >> "$STUB/list-asked"; for f in /dev/fd/*; do [ "$f" -ef "$ST/cards.jsonl" ] && ! flock -n "$ST/cards.jsonl" true && echo x >> "$STUB/list-locked"; done; true' > "$STUB/list-cmd"
  loop run 1 >/dev/null; [ "$(st 'select(.step == "picked") | .issue' | tail -1)" = 6 ] || fail "first pick was not the oldest P1 without a card"
  [ -s "$STUB/list-asked" ] || fail "the loop picked without asking for the open issues"
  [ ! -e "$STUB/list-locked" ] || fail "the open issues were asked for while the records' lock was held"
  rm -f "$STUB/list-cmd"
  # The first loop's card holds in its worktree setup from $STUB/building until $STUB/go (or the stub folder is gone:
  # the test's end), so the second loop is tried while the first runs, however slowly a loaded machine starts either.
  tune --arg s ': > "$STUB/building"; while [ -d "$STUB" ] && [ ! -e "$STUB/go" ]; do sleep 0.1; done; exit 1' '.worktree.setup = $s'
  loop run 1 >/dev/null & run=$!
  until [ -e "$STUB/building" ] || ! kill -0 $run 2>/dev/null; do sleep 0.1; done
  out=$(loop run 2>&1) && fail "a second loop ran beside the first"; grep -q 'already running' <<<"$out" || fail "second loop: $out"
  : > "$STUB/go"; wait; [ "$(st 'select(.step == "picked") | .issue' | sort | tr '\n' ' ')" = "4 5 6 " ] || fail "picks: $(st 'select(.step == "picked") | .issue' | tr '\n' ' ')"
}

# A7: `pick --dry` answers from frozen inputs, the same each time and the issue the loop then picks, and writes
# nothing: not in the state folder it reads, not in main's, and no card. Issue 7 is opened while new issues start held:
# a dry pick that did not apply adopt()'s hold would answer 7 (P0), not 6.
t_dry() {
  local d=$T/$CASE/frozen mark=$T/$CASE.mark a b before
  setup "$(jq -cs . <(issue 5 2026-01-01 P3) <(issue 6 2026-02-01 P1) <(issue 4 2026-03-01 P1) <(issue 7 2026-04-01 P0))"
  tune '.worktree.setup = "exit 1"'
  jq -c '.start = "held" | .startHeld = [{from: 6, to: null}]' "$ST/control.json" > "$STUB/c.new" && mv "$STUB/c.new" "$ST/control.json"
  echo '{"card":"c0-4","issue":4,"step":"picked","time":"2026-11-01T00:00:00Z","tokens":{"claude":0,"codex":0},"result":"ok","sha":"","reason":""}' > "$ST/cards.jsonl"
  mkdir -p "$d"; cp "$ST/cards.jsonl" "$ST/control.json" "$d/"
  listing() { find "$d" "$ST" "$T/$CASE" -maxdepth 1 | sort; find "$d" "$ST" -type f -exec cksum {} + | sort; }
  # Every file and folder there, and the mark, are dated 2000: one written from here on is newer than the mark, however
  # coarse the filesystem's times and however soon the write comes.
  before=$(listing); find "$d" "$ST" "$T/$CASE" -exec touch -h -t 200001010000 {} +; touch -t 200001010000 "$mark"
  a=$(loop pick --dry --issues "$STUB/issues.json" --state "$d") || fail "dry pick failed"
  b=$(loop pick --dry --issues "$STUB/issues.json" --state "$d") || fail "second dry pick failed"
  [ "$a" = 6 ] && [ "$b" = "$a" ] || fail "dry picks: '$a' then '$b', not 6 both times"
  # Bug: a dry pick of the state folder itself asked the state database, which made (or wrote) state.db there.
  [ "$(loop pick --dry --issues "$STUB/issues.json" --state "$ST")" = 6 ] || fail "a dry pick of the state folder did not answer 6"
  [ "$(listing)" = "$before" ] && [ -z "$(find "$d" "$ST" "$T/$CASE" -newer "$mark")" ] || fail "a dry pick wrote a file: $(find "$d" "$ST" "$T/$CASE" -newer "$mark")"
  loop run 1 >/dev/null; [ "$(st 'select(.step == "picked") | .issue' | tail -1)" = "$a" ] || fail "the loop picked $(st 'select(.step == "picked") | .issue' | tail -1), the dry pick $a"
  # Relative paths are read from where it is called; a reading at the guard picks nothing, as the loop picks nothing.
  [ "$(cd "$d" && loop pick --dry --issues "$STUB/issues.json" --state .)" = 6 ] || fail "a relative state folder was not read from the caller's folder"
  jq -c '.guard = 50' "$d/control.json" > "$STUB/c.new" && mv "$STUB/c.new" "$d/control.json"
  jq -cn '{time: (now | todate), pct: 50}' > "$d/limit.jsonl"
  [ "$(loop pick --dry --issues "$STUB/issues.json" --state "$d")" = '' ] || fail "a dry pick ignored the guard"
  # A reading older than limitOld is no reading, as in the loop: the guard does not hold and 6 is picked.
  echo '{"time":"2020-01-01T00:00:00Z","pct":50}' > "$d/limit.jsonl"
  [ "$(loop pick --dry --issues "$STUB/issues.json" --state "$d")" = 6 ] || fail "a dry pick held the guard on an expired reading"
  # A paused record picks nothing (the guard lifted, so only the pause can stop it); a missing state folder is a usage error.
  jq -c '.guard = null | .mode = "pause"' "$d/control.json" > "$STUB/c.new" && mv "$STUB/c.new" "$d/control.json"
  [ "$(loop pick --dry --issues "$STUB/issues.json" --state "$d")" = '' ] || fail "a paused record was picked from"
  loop pick --dry --issues "$STUB/issues.json" --state "$d/none" 2>/dev/null; [ $? = 2 ] || fail "a missing state folder is not a usage error"
}

# Bug: a ready issue whose number is no JSON text made the pick step's jq --argjson fail; the pick failed with only
# jq's own error in the log (no step, no issue), and the other ready issue was not picked on that turn, nor on any later
# one, as the same issue came first again. pick() is called as the loop calls it, once.
t_pickjson() {
  setup "[$(issue 5 2026-01-01 | jq -c '.number = "5x"'), $(issue 6 2026-02-01)]"
  local out err; mkdir -p "$ST" && : > "$ST/cards.jsonl"
  out=$( ( export CONVEYOR_MAIN=$R CONVEYOR_CARDS=$T/$CASE/cards; . "$SRC/conveyor.sh" state-dir > /dev/null \
    && eval "$(grep '^\. "\$HERE/lib/' "$SRC/commands/run.sh")" && names && pick '' '' "$(cat "$STUB/issues.json")" ) 2> "$T/$CASE/err") \
    || fail "the pick failed: $(cat "$T/$CASE/err")"
  err=$(cat "$T/$CASE/err")
  [ "${out#* }" = '6 false' ] && [ "$(st 'select(.step == "picked") | .issue')" = 6 ] || fail "the other ready issue was not picked by the same pick: out=$out $(st .)"
  grep -qF 'conveyor: the pick step could not read the title and created time of #5x as JSON; #5x is skipped, and the next ready issue is picked' <<<"$err" \
    || fail "the issue skipped is not named with the step in the log: $err"
}
