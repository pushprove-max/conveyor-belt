#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 300
# Engine cases: the control record.
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"
# The engine folder, as lib.sh sets it: named here too, so the release closure (tools/closure.sh) follows this file's paths.
SRC=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)

# Bugs: a control action changes the record when it should not (a bad argument, a seat with no CLI, a model a
# CLI would read as an option, an effort the CLI does not take), or does not change it; a record with no file, or one that names no
# cap, seat or effort, or a default, is not the seed; a paused, stopped or guarded loop picks; a
# guard with no reading pauses, or health does not say the reading is missing; a held or excluded issue is picked;
# the order list is not picked first; the cap in force is not the record's; a model change reaches a session already
# running, or not the next one; a seat the record names no model for is said to have one; a step's line does not name its
# model, or is priced at another one; stop blocks its card, or leaves its worktree or its issue out of the queue;
# the snapshot leaves out the record, the queue, the held and skipped issues, the forecast or the models in force.
# One case for each part (t_control, t_controlpick, t_controlcap, t_controlmodel, t_controlstop), so they run side by
# side; each starts from the seeded record (setup) with the pack's models and limit reading below.
controlsetup() { # <issues json>
  setup "$1"
  S=$ST; C=$S/control.json; for i in $(seq 12); do echo "$GO" > "$STUB/review.$i"; done
  tune '.models.allowed = {claude: ["m", "m2"], codex: ["x", "x2"], "claude-reviewer": []} | .tunables.limitTtl = 0'
  export CONVEYOR_LIMIT_CMD='cat "$STUB/limit"'
  ctl() { loop control "$@" 2>&1; }
  picks() { st 'select(.step == "picked") | .issue' | tr '\n' ' '; }
}
t_control() {
  controlsetup "$(jq -cs . <(issue 5 2026-01-01 P2) <(issue 6 2026-02-01 P1 area:billing) <(issue 8 2026-03-01 P2) <(issue 9 2026-04-01 P0))"
  # The actions. No file: the record the engine reads (ctlread) is the defaults, the plugin project's own settings
  # (#593; bug: a new project started on one card at once, no guard, no judge and no seat set, or pushed every landing
  # with nobody asked: push is off). Each seat names a
  # model this pack does not list, so it runs on the seed: the first model the pack allows it, at medium.
  rm "$C"; [ "$(ctl | jq -c '[.mode, .cap, .guard, .held, .order, .model, .reviewer, .judge, .judgeOn, .judgeAlways, .rules, .depGuard, .start]')" \
    = '["run",6,98,[],[],{"model":"claude-opus-5-5","effort":"medium"},{"model":"gpt-6.1-sol","effort":"medium"},{"model":"claude-opus-5-5","effort":"medium"},true,[],{"P0":true,"P1":true,"P2":true,"P3":true,"followups":true,"push":false,"visible":false,"split":"on","pick":"off","lint":true,"testissues":true,"foremanissues":true,"followupissues":true,"releaseissues":true,"splitissues":true,"healsdays":30,"never":[]},true,"queue"]' ] \
    && [ ! -e "$C" ] || fail "no record does not read as the plugin project's settings: $(ctl)"
  h=$(loop health)
  [ "$(jq -c '[.models, .efforts, .builderCap]' <<<"$h")" = '[{"claude":"m","codex":"x"},{"claude":"medium","codex":"medium"},6]' ] || fail "no record does not have the seed's seats and the defaults' cap: $h"
  [ "$(jq -c '.homes | [.["control.cap"].value, (.["control.model"] | [.value.model, .home])]' <<<"$h")" = '[6,["m","seed"]]' ] \
    || fail "health does not name the seed as the seat's home: $(jq -c .homes <<<"$h")"
  # A pack allowing only Sonnet and Astra builds on them with no control command.
  [ "$(tuned '.models.allowed = {claude: ["claude-sonnet-5-5"], codex: ["gpt-6-astra"], "claude-reviewer": []}' loop health | jq -c .models)" = '{"claude":"claude-sonnet-5-5","codex":"gpt-6-astra"}' ] \
    || fail "the seed is not the pack's first allowed model: $(loop health)"
  echo '{"cap":3,"model":null,"reviewer":{"model":"x2"}}' > "$C"
  [ "$(loop health | jq -c '[.models, .efforts, .builderCap]')" = '[{"claude":"m","codex":"x2"},{"claude":"medium","codex":"medium"},3]' ] || fail "a record with no seat or effort does not have the seed's: $(loop health)"
  rm "$C"
  # A seat is a CLI and a model: a model alone, a CLI that is none of the three, a model a CLI would read as an option,
  # or an effort its CLI does not take is refused.
  for bad in 'cap 101' 'cap 0' 'cap 08' 'guard 101' 'hold' 'hold x' 'unpin' 'unpin x' 'rules P4=off' 'rules P1=maybe' 'rules push=maybe' 'rules visible=maybe' 'rules lint=maybe' 'rules wholeSuite=on' 'rules split=maybe' 'rules visible=shadow' 'pause now' 'frob' 'model claude m bogus' 'model m' 'model nosuch m' 'reviewer m' 'model claude --help' 'reviewer codex x max' 'model default high'; do
    # shellcheck disable=SC2086
    out=$(ctl $bad); [ $? = 2 ] && [ ! -e "$C" ] || fail "control $bad was not refused with nothing changed: $out"
  done
  # A default clears the setting, so the seed is in force again.
  [ "$(ctl cap 9 | jq .cap)" = 9 ] && [ "$(ctl cap off | jq .cap)" = null ] && [ "$(ctl model claude m2 high | jq -c .model)" = '{"cli":"claude","model":"m2","effort":"high"}' ] \
    && [ "$(ctl model default | jq -c .model)" = null ] && [ "$(ctl reviewer codex x2 low | jq -c .reviewer)" = '{"cli":"codex","model":"x2","effort":"low"}' ] \
    && [ "$(ctl reviewer default | jq -c .reviewer)" = null ] || fail "a default does not clear the setting: $(cat "$C")"
  [ "$(ctl cap 9 | jq .cap)" = 9 ] && [ "$(ctl cap 100 | jq .cap)" = 100 ] && [ "$(ctl | jq .cap)" = 100 ] \
    && [ "$(ctl cap 1 | jq .cap)" = 1 ] && [ "$(ctl guard 50 | jq .guard)" = 50 ] && [ "$(ctl hold 8 6 | jq -c .held)" = '[6,8]' ] && [ "$(ctl release 6 | jq -c .held)" = '[8]' ] \
    && [ "$(ctl order 9 5 9 | jq -c .order)" = '[9,5]' ] && [ "$(ctl order 9 5 8 | jq -c .order)" = '[9,5,8]' ] && [ "$(ctl unpin 5 6 | jq -c .order)" = '[9,8]' ] \
    && [ "$(ctl order 9 5 | jq -c .order)" = '[9,5]' ] &&[ "$(ctl rules P1=off area:billing=off followups=off | jq -c .rules)" = '{"P0":true,"P1":false,"P2":true,"P3":true,"followups":false,"push":false,"visible":false,"split":"on","pick":"off","lint":true,"testissues":true,"foremanissues":true,"followupissues":true,"releaseissues":true,"splitissues":true,"healsdays":30,"never":["area:billing"]}' ] \
    && [ "$(ctl rules area:billing=on followups=on | jq -c '[.rules.never, .rules.followups]')" = '[[],true]' ] \
    && [ "$(ctl rules push=on | jq -c '[.rules.push, .rules.never]')" = '[true,[]]' ] && [ "$(ctl | jq .rules.push)" = true ] && [ "$(ctl rules push=off | jq .rules.push)" = false ] \
    && [ "$(ctl rules foremanissues=off followupissues=off releaseissues=off splitissues=off | jq -c '[.rules.foremanissues, .rules.followupissues, .rules.releaseissues, .rules.splitissues, .rules.never]')" = '[false,false,false,false,[]]' ] \
    && [ "$(ctl rules foremanissues=on splitissues=on | jq -c '[.rules.foremanissues, .rules.followupissues, .rules.releaseissues, .rules.splitissues]')" = '[true,false,false,true]' ] \
    && [ "$(ctl rules lint=off | jq -c '[.rules.lint, .rules.never]')" = '[false,[]]' ] && [ "$(ctl rules lint=on | jq .rules.lint)" = true ] \
    && [ "$(ctl rules visible=off | jq -c '[.rules.visible, .rules.never]')" = '[false,[]]' ] && [ "$(ctl | jq .rules.visible)" = false ] && [ "$(ctl rules visible=on | jq .rules.visible)" = true ] \
    && [ "$(ctl rules split=on | jq -c '[.rules.split, .rules.never]')" = '["on",[]]' ] && [ "$(ctl | jq -r .rules.split)" = on ] && [ "$(ctl rules split=off | jq -r .rules.split)" = off ] && [ "$(ctl rules split=shadow | jq -r .rules.split)" = shadow ] \
    && [ "$(ctl model claude m2 high | jq -c .model)" = '{"cli":"claude","model":"m2","effort":"high"}' ] && [ "$(ctl reviewer codex x2 low | jq -c .reviewer)" = '{"cli":"codex","model":"x2","effort":"low"}' ] \
    && [ "$(ctl reviewer codex x2 medium | jq -c .reviewer)" = '{"cli":"codex","model":"x2","effort":"medium"}' ] && [ "$(ctl model claude m | jq -c .model)" = '{"cli":"claude","model":"m","effort":null}' ] \
    && [ "$(ctl model claude m2 | jq -c .model)" = '{"cli":"claude","model":"m2","effort":null}' ] && [ "$(ctl model claude m2 high | jq -c .model)" = '{"cli":"claude","model":"m2","effort":"high"}' ] \
    && [ "$(ctl pause | jq -r .mode)" = pause ] && [ "$(ctl stop | jq -r .mode)" = stop ] && [ "$(ctl resume | jq -r .mode)" = run ] \
    && [ "$(ctl guard off | jq .guard)" = null ] && [ "$(ctl cap 5 | jq .cap)" = 5 ] && [ "$(ctl order | jq -c .order)" = '[]' ] \
    || fail "an action did not change the record as asked: $(cat "$C")"
  h=$(loop health)
  [ "$(jq -c '[.models, .efforts, .builderCap]' <<<"$h")" = '[{"claude":"m2","codex":"x2"},{"claude":"high","codex":"medium"},5]' ] || fail "health does not name the models in force: $h"
  # Each value in force and its home (plan section 6).
  [ "$(jq -c '.homes | [.["tunables.poll"], .["tunables.limitTtl"], .["models.allowed"].home, .["rulings.log"].home, .["checks"].home, .["control.cap"], (.["control.model"] | [.value.model, .home])]' <<<"$h")" \
    = '[{"value":30,"home":"pack"},{"value":0,"home":"pack"},"pack","pack","pack",{"value":5,"home":"control record"},["m2","control record"]]' ] || fail "health does not name each value's home: $(jq -c .homes <<<"$h")"
  [ "$(tuned 'del(.tunables.poll) | del(.checks) | del(.rulings)' loop health | jq -c '.homes | [.["tunables.poll"], .["checks"], .["rulings.log"]]')" \
    = '[{"value":30,"home":"schema default"},{"value":[],"home":"schema default"},{"value":null,"home":"none"}]' ] || fail "health does not name a schema default as the home: $(loop health | jq -c .homes)"
  # The Board's model settings: each in force, where it comes from, and the choices the pack allows.
  settings() { loop snapshot --fresh | jq -c '.modelSettings | [(.builder, .reviewer) | [.model, .effort, .modelFrom, .effortFrom, .choices, (.efforts | length)]]'; }
  [ "$(settings)" = '[["m2","high","control","control",["m","m2"],5],["x2","medium","control","control",["x","x2"],5]]' ] || fail "snapshot model settings set by the record: $(settings)"
  # A seat the record names no model for, or one the pack no longer allows, has the seed's: health and the Board say so.
  jq -c '.model = null' "$C" > "$C.new" && mv "$C.new" "$C"
  [ "$(loop health | jq -c '[.models, .efforts]')" = '[{"claude":"m","codex":"x2"},{"claude":"medium","codex":"medium"}]' ] || fail "a seat with no model does not have the seed's: $(loop health)"
  [ "$(settings)" = '[["m","medium","seed","seed",["m","m2"],5],["x2","medium","control","control",["x","x2"],5]]' ] || fail "snapshot model settings with no builder model: $(settings)"
  jq -c '.model = {model: "gone", effort: "high"}' "$C" > "$C.new" && mv "$C.new" "$C"
  [ "$(loop health | jq -c '[.models.claude, .efforts.claude]')" = '["m","medium"]' ] || fail "a model the pack no longer allows is said to be in force: $(loop health)"
  # A record that does not read: nothing is picked, and health says so.
  echo '{"mode":"sideways"}' > "$C"; loop run >/dev/null 2>&1 && fail "a run went on over a control record that does not read"
  [ -z "$(picks)" ] && [ "$(loop health | jq -r .state)" = "control record unreadable" ] || fail "an unreadable record: $(picks) $(loop health)"
}
t_controlpick() {
  controlsetup "$(jq -cs . <(issue 5 2026-01-01 P2) <(issue 6 2026-02-01 P1 area:billing) <(issue 8 2026-03-01 P2) <(issue 9 2026-04-01 P0))"
  # Paused: nothing picked. Held #8, P1 off (#6): the run takes #9 (order first), then #5, and never #6 or #8.
  ctl pause >/dev/null; out=$(loop run 2>&1); [ -z "$(picks)" ] && grep -q 'the loop is paused' <<<"$out" || fail "a paused loop picked, or did not say so: $(picks) $out"
  [ "$(loop health | jq -r .state)" = paused ] || fail "health of a paused loop: $(loop health)"
  ctl resume >/dev/null; ctl hold 8 >/dev/null; ctl rules P1=off >/dev/null; ctl order 5 >/dev/null
  out=$(loop snapshot --fresh) || fail "snapshot exited non-zero"
  [ "$(jq -c '[(.queue.order | map(.issue)), (.queue.holding | map(del(.since))), .queue.skipped, .control.held, (.queue.next | map(.issue))]' <<<"$out")" \
    = '[[5,9],[{"issue":8,"title":"title 8","priority":"P2","followup":false,"retried":false,"created":"2026-03-01","waitsFor":[]}],[{"issue":6,"title":"title 6","rule":"P1"}],[8],[5,9]]' ] || fail "snapshot queue and record: $(jq -c '[.queue, .control]' <<<"$out")"
  # Held by you and skipped by a rule are both in Held, each with its reason; the four counts add up.
  [ "$(jq -c '.open | [.split, (.held | map([.issue, (.reasons | map(.rule // .kind) | join(","))]))]' <<<"$out")" = '[{"queued":2,"you":1,"labelOrRule":1,"landed":0,"belt":0},[[6,"P1"],[8,"you"]]]' ] \
    || fail "the held issues and their reasons: $(jq -c .open <<<"$out")"
  [ "$(jq -c '[.forecast.cards, .forecast.usd, .forecast.pausesAt, .health.models]' <<<"$out")" = '[2,null,null,{"claude":"m","codex":"x"}]' ] \
    || fail "forecast with nothing landed, or the models in force: $(jq -c '[.forecast, .health.models]' <<<"$out")"
  # The guard: a reading at or over it pauses; one under it does not; no reading pauses nothing and health says so.
  # The run under the guard is the run that checks the pick order, so the case builds two cards, not three. These are
  # real loop runs, as only one shows what a run does: the guard's "paused by guard" message and exit, the reading the
  # loop asks for and records, and the picked lines it writes in order. The dry pick reads a reading and writes nothing.
  ctl order 9 >/dev/null; ctl guard 50 >/dev/null
  echo '{"seven_day":{"utilization":50}}' > "$STUB/limit"
  out=$(loop run 2>&1); [ -z "$(picks)" ] && grep -q 'paused by guard' <<<"$out" || fail "a reading at the guard did not pause the loop: $(picks) $out"
  [ "$(loop health | jq -c '[.state, .guard.at, .guard.reading, .guard.missing]')" = '["paused by guard",50,50,false]' ] || fail "health under the guard: $(loop health)"
  rm "$S/limit.jsonl"; rm "$STUB/limit"
  [ "$(loop health | jq -c '[.state, .guard.reading, .guard.missing]')" = '["running",null,true]' ] || fail "no reading paused the loop, or health did not say it is missing: $(loop health)"
  echo '{"seven_day":{"utilization":49}}' > "$STUB/limit"; loop run >/dev/null 2>&1 || fail "run exited non-zero"
  [ "$(picks)" = "9 5 " ] || fail "picks under the guard with #9 ordered first, #8 held and P1 off: $(picks)"
  # Area labels never built: #6 is P1 and billing; P1 on again, billing still off. This is a real loop run, as only
  # one shows that a run, which asks GitHub (the stub) for the open issues with their labels, writes no picked line
  # for #6; the dry pick reads a file of issues and writes nothing. Nothing is picked, so it builds no card.
  ctl rules P1=on area:billing=off >/dev/null; loop run >/dev/null 2>&1; [ "$(picks)" = "9 5 " ] || fail "an issue of an area never built was picked: $(picks)"
  out=$(loop snapshot --fresh)
  [ "$(jq -c '.queue.skipped | map([.issue, .rule])' <<<"$out")" = '[[6,"area:billing"]]' ] || fail "the skipped rule of #6: $(jq -c .queue <<<"$out")"
  # billing on again and #8 released: #6 (P1) is the next pick. The dry pick is the loop's own pick (upnext) on the
  # same records and the run's last reading (49), with no third card built.
  ctl rules area:billing=on >/dev/null; ctl release 8 >/dev/null
  [ "$(loop pick --dry --issues "$STUB/issues.json" --state "$S")" = 6 ] || fail "#6 is not picked with billing on again: $(loop pick --dry --issues "$STUB/issues.json" --state "$S" 2>&1)"
  # The reading at the guard again: the guard pauses at #6, the queue's first, with #8 after it. Two cards have landed,
  # and the stub's model m has no price: no dollars.
  echo '{"seven_day":{"utilization":50}}' > "$STUB/limit"
  out=$(loop snapshot --fresh)
  [ "$(jq -c '[.forecast.pausesAt, .forecast.cards, .forecast.usd]' <<<"$out")" = '[6,2,null]' ] || fail "the forecast under the guard: $(jq -c .forecast <<<"$out")"
}
t_controlcap() {
  # The cap in force: with cap 1 two cards never run at once. Two issues are enough: a loop that did not keep the cap
  # picks the second before the first lands.
  controlsetup "$(jq -cs . <(issue 20 2026-06-01 P2) <(issue 21 2026-06-01 P2))"
  # A build lasts a whole turn of the loop (two of its waits begun, lib.sh), the turn in which a loop that did not keep
  # the cap would pick the next card: the record then has a pick before the landing of the card in flight.
  watchturns
  echo 'k=$(wc -l < "$TURNS"); while [ -d "$STUB" ] && [ "$(wc -l < "$TURNS")" -lt $((k + 2)) ]; do sleep 0.1; done; echo two >> a.txt' > "$STUB/build"
  ctl cap 1 >/dev/null; tuned '.tunables.poll = 1' loop run 2 >/dev/null 2>&1
  [ "$(st 'select(.issue >= 20 and (.step | IN("picked", "landed"))) | .step' | tr '\n' ' ')" = "picked landed picked landed " ] \
    || fail "cap 1 let two cards run at once, or the two did not land: $(st 'select(.issue >= 20 and (.step | IN("picked", "landed"))) | "\(.issue) \(.step)"' | tr '\n' ,)"
}
# The record is read at every use, but checked only when its text is not the one last checked (ctlread). Bugs: it is
# checked again at every use, one jq run each, though it has not changed (about 37 in one card's run); or the check
# of the old text is kept after the record changed, so the loop goes on picking once it is paused.
t_controlread() {
  controlsetup "$(jq -cs . <(issue 5 2026-01-01 P2) <(issue 6 2026-01-02 P2))"
  ctl cap 1 >/dev/null
  # jq, counting the record's checks (the one program that reads judgeAlways) and the loop's turns (the cap in force,
  # read once a turn: run()).
  printf '#!/usr/bin/env bash\ncase "$*" in *"judgeAlways | type"*) echo >> "$STUB/checks" ;; *".cap // \\$d end"*) echo >> "$STUB/turns" ;; esac\nexec %q "$@"\n' \
    "$(command -v jq)" > "$STUB/jq" && chmod +x "$STUB/jq"
  : > "$STUB/checks"; : > "$STUB/turns"
  # #5's build pauses the loop: the turn after it reads the changed record and picks nothing.
  echo 'echo two >> a.txt; jq -c ".mode = \"pause\"" "'"$C"'" > "$STUB/c.new" && mv "$STUB/c.new" "'"$C"'"' > "$STUB/build"
  loop run >/dev/null 2>&1
  c=$(wc -l < "$STUB/checks") t=$(wc -l < "$STUB/turns"); rm "$STUB/jq"
  [ "$(picks)" = "5 " ] && [ -n "$(st 'select(.issue == 5 and .step == "landed")')" ] || fail "the loop picked after a card paused it, or #5 did not land: $(picks)"
  # Checked once per text in the loop's shell and in each process that reads it before the loop does: 9 here, where a
  # check at every use is 28.
  [ "$t" -ge 4 ] && [ "$c" -le 12 ] || fail "the same control record was checked again at its uses: $c checks in $t turns"
}
# The seats in force, the host's CLIs and whether each seat can start (seat, hostclis, seatready) are worked out once
# for the texts they are read from, in the loop's shell at each turn, and kept for the turn's subshells and the cards
# it starts. Bugs: each ask works them out again, one to three jq runs each; or what was kept is used after the
# record changed, so the review runs on the reviewer set before its build.
t_seatread() {
  controlsetup "[$(issue 5 2026-01-01 P2)]"
  ctl cap 1 >/dev/null
  # jq, counting the seats worked out (the runs given seatnow's definition), the host's reports read (the runs that
  # take a CLI's models from CLIS's clis), the seats' start checks (missing) and the loop's turns (the cap in force).
  printf '#!/usr/bin/env bash\ncase "$*" in *"def seatnow("*) echo >> "$STUB/seats" ;; *"\\$o.clis["*) echo >> "$STUB/hosts" ;; *"missing(\\$h) // empty"*) echo >> "$STUB/ready" ;; *".cap // \\$d end"*) echo >> "$STUB/turns" ;; esac\nexec %q "$@"\n' \
    "$(command -v jq)" > "$STUB/jq" && chmod +x "$STUB/jq"
  : > "$STUB/seats"; : > "$STUB/hosts"; : > "$STUB/ready"; : > "$STUB/turns"
  # #5's build sets the reviewer: its review runs on the new one.
  echo 'echo two >> a.txt; jq -c ".reviewer = {model: \"x2\", effort: \"low\"}" "'"$C"'" > "$STUB/c.new" && mv "$STUB/c.new" "'"$C"'"' > "$STUB/build"
  loop run 1 >/dev/null 2>&1
  s=$(wc -l < "$STUB/seats") h=$(wc -l < "$STUB/hosts") r=$(wc -l < "$STUB/ready") t=$(wc -l < "$STUB/turns"); rm "$STUB/jq"
  [ "$(st 'select(.issue == 5 and .step == "review") | "\(.model) \(.effort)"')" = "x2 low" ] && [ -n "$(st 'select(.issue == 5 and .step == "landed")')" ] \
    || fail "the review did not run on the reviewer its build set, or #5 did not land: $(st 'select(.issue == 5) | [.step, .model, .effort] | tostring' | tr '\n' ' ')"
  # Each once per text, in the loop's shell and in the card that reads the changed record: 3, 3 and 4 here, where
  # working them out at each ask is 19, 12 and 12 (in 5 turns; each turn asks again).
  [ "$t" -ge 2 ] && [ "$s" -le 5 ] && [ "$h" -le 5 ] && [ "$r" -le 5 ] \
    || fail "the seats or the host's CLIs were worked out again at each ask: $s seats, $h host reports and $r start checks in $t turns"
}
t_controlmodel() {
  # The model: changed while the build runs, the build keeps its model (the seed's, m at medium) and the next session
  # (the fix) and the next review take the new ones;
  # the step lines name each, and each is priced at its own model.
  controlsetup "[$(issue 30 2026-07-01 P0)]"; printf '%s\n' "$NOGO" > "$STUB/review.1"
  # The build holds until $STUB/go, however long that takes; the stub folder gone (the test's end) ends the hold too.
  echo 'while [ -d "$STUB" ] && [ ! -e "$STUB/go" ]; do sleep 0.1; done; echo two >> a.txt' > "$STUB/build"
  : > "$STUB/sessions"; loop run 1 >/dev/null 2>&1 & run=$!
  until [ -s "$STUB/sessions" ] || ! kill -0 $run 2>/dev/null; do sleep 0.1; done # the build's session, or the run's end
  ctl model claude m2 high >/dev/null; ctl reviewer codex x2 low >/dev/null; : > "$STUB/go"; wait $run
  [ "$(cut -d' ' -f1-5 "$STUB/sessions" | tr '\n' ,)" = "-p --model m --effort medium,-p --model m2 --effort high," ] || fail "sessions ran on: $(cat "$STUB/sessions")"
  [ "$(st 'select(.issue == 30 and (.step | IN("build", "review", "fix"))) | "\(.step) \(.model) \(.effort)"' | tr '\n' ,)" = "build m medium,review x2 low,fix m2 high,review x2 low," ] \
    || fail "the step lines do not name the model that ran them: $(st 'select(.issue == 30) | [.step, .result, .model, .effort, .reason[0:80]] | tostring' | tr "\n" " ")"
  loop check || fail "the record check refuses a line naming its model"
  priced=$(echo '{"cards":[{"models":{"claude":"claude-fable-5-2","codex":"gpt-6.1-sol"},"steps":[{"step":"build","model":"claude-opus-5-5","usage":{"input":1000000,"write":0,"write1h":0,"read":0,"output":0}},{"step":"fix","usage":{"input":1000000,"write":0,"write1h":0,"read":0,"output":0}}]}]}' \
    | python3 "$SRC/../.claude/scripts/dashboard_limit.py" cards | jq -c '.cards[0] | [(.steps | map(.usd | numbers |= round)), .usd, .steps[1].unpriced]')
  # A step whose line names no model is unpriced and says so, never priced at the models in force now.
  [ "$priced" = '[[4,null],null,"no model recorded"]' ] || fail "a step is not priced at the model its line names: $priced"
}
t_controlstop() {
  # stop: the card in progress ends, its lines go to the retried file, no blocked line, no worktree; resume picks it again.
  controlsetup "[$(issue 40 2026-08-01 P0)]"
  # The build has answered once when it is stopped: what it used so far stays in the records, as a build line
  # whose result is stopped, priced at the model it ran on (the seed's, m).
  printf '%s\n' 'echo "{\"type\":\"assistant\",\"message\":{\"id\":\"s1\",\"usage\":{\"input_tokens\":700,\"output_tokens\":5}}}"' \
    'sleep 60 & echo $! > "$STUB/sleeper"; : > "$STUB/building"; wait' > "$STUB/build"; rm -f "$STUB/building" # sleep: the build's child, there to be stopped with it
  tune '.tunables.idle = 1 | .tunables.poll = 1'
  # serve ends at its own time limit: each wait below is for what it does, until that is there or serve has ended.
  ( export CONVEYOR_MAIN=$R CONVEYOR_CARDS=$T/$CASE/cards
    exec timeout 120 bash "$SRC/conveyor.sh" serve > "$STUB/serve.out" 2>&1 ) & pid=$!; trap 'kill $pid 2>/dev/null' EXIT
  until [ -e "$STUB/building" ] || ! kill -0 $pid 2>/dev/null; do sleep 0.1; done; [ -e "$STUB/building" ] || fail "serve did not start #40: $(cat "$STUB/serve.out")"
  card=$(st 'select(.issue == 40 and .step == "picked") | .card'); ctl stop >/dev/null
  until [ -z "$(st 'select(.issue == 40) | .card')" ] || ! kill -0 $pid 2>/dev/null; do sleep 0.1; done
  [ -z "$(st 'select(.issue == 40) | .card')" ] && [ -n "$(jq -r --arg c "$card" 'select(.card == $c and .step == "picked") | .card' "$S/retried.jsonl")" ] \
    && [ -z "$(jq -r --arg c "$card" 'select(.card == $c and .step == "blocked")' "$S/retried.jsonl")" ] && [ ! -e "$T/$CASE/cards/$card" ] \
    && ! pgrep -f "$STUB/claude" >/dev/null && ! kill -0 "$(cat "$STUB/sleeper")" 2>/dev/null && grep -q "stopped card $card" "$STUB/serve.out" \
    || fail "stop did not end card $card as asked: $(st 'select(.issue == 40)') $(cat "$STUB/serve.out")"
  [ "$(jq -c --arg c "$card" 'select(.card == $c and .step == "build") | [.result, .tokens.claude, .usage.input, .usage.output, .model]' "$S/retried.jsonl")" = '["stopped",705,700,5,"m"]' ] \
    || fail "the stopped build's spend is not recorded: $(jq -c --arg c "$card" 'select(.card == $c)' "$S/retried.jsonl")"
  loop check || fail "the stopped build line does not check"
  kill -0 $pid 2>/dev/null || fail "serve ended on a stop"
  [ "$(loop snapshot --fresh | jq -c '[.health.state, (.queue.order | map(.issue) | index(40) != null)]')" = '["stopped",true]' ] || fail "the stopped issue is not back in the queue"
  echo 'echo two >> a.txt' > "$STUB/build"; ctl resume >/dev/null
  until [ -n "$(st 'select(.issue == 40 and .step == "landed")')" ] || ! kill -0 $pid 2>/dev/null; do sleep 0.1; done
  [ -n "$(st 'select(.issue == 40 and .step == "landed")')" ] || fail "resume did not pick the stopped issue again: $(cat "$STUB/serve.out")"
  kill $pid; wait $pid 2>/dev/null; :
}

# The Board's Close on a pipeline change held for the owner: it runs what dashboard_server.py's close runs on the host
# (gh-write issue close with the Board's comment, then shut), on a held follow-up that has no card. Bugs: shut fails,
# or touches the card records, when the issue has no blocked card, so the Board shows a refusal though the issue was
# closed; the comment does not say it was closed from the Board; the closed issue stays in Needs you because the
# control record still holds it.
t_heldclose() {
  setup "$(jq -cn '[{number: 41, title: "[P1] a.txt:1 a slow gate", body: "Follow-up to #7 (Conveyor card c1-7).\n\nCost to every card: not assessed",
    milestone: null, createdAt: "2026-01-01", labels: [{name: "P1"}]}]')"
  loop control hold 41 >/dev/null || fail "hold 41 exited non-zero"
  [ "$(loop snapshot --fresh | jq -c '.needsYou.pipeline | map(.issue)')" = '[41]' ] || fail "the held follow-up is not in Needs you: $(loop snapshot --fresh | jq -c .needsYou.pipeline)"
  touch "$ST/cards.jsonl"; before=$(cat "$ST/cards.jsonl")
  # shut exits 4 when it shuts nothing, which the Board's close takes as no failure (dashboard_server_control.py).
  loop gh-write issue close 41 --comment "Closed from the Board's Needs you list." >/dev/null && { loop shut 41 >/dev/null 2>&1 || [ $? = 4 ]; } || fail "the Board's close of #41, which has no card, exited non-zero"
  [ "$(cat "$STUB/closed")" = 41 ] && [ "$(cat "$STUB/close-comments")" = "--comment Closed from the Board's Needs you list." ] \
    || fail "#41 was not closed with the Board's comment: $(cat "$STUB/closed" "$STUB/close-comments" 2>&1)"
  [ "$(cat "$ST/cards.jsonl")" = "$before" ] || fail "the close of #41 changed the card records, though #41 has no card"
  # GitHub lists it closed now: it leaves Needs you, though the control record still holds it.
  echo '[]' > "$STUB/issues.json"
  [ "$(jq -c .held "$ST/control.json")" = '[41]' ] && [ "$(loop snapshot --fresh | jq -c .needsYou.pipeline)" = '[]' ] \
    || fail "the closed #41 is still in Needs you: $(loop snapshot --fresh | jq -c .needsYou.pipeline)"
}
# A newer engine adds a key to the control record while a card runs the older copy in its own worktree (#516 added
# tests). Bugs: the older copy's check refuses the record for a key it does not know, at the top or in rules, and the
# card blocks; it lets a bad value of a key it knows through beside the new key; or one of its control actions drops
# the new key when it writes the record, so the newer engine loses its setting.
t_controlnewkey() {
  local CTL0 r; CTL0=$(jq -c . "$SRC/lib/control-defaults.json")
  eval "$(sed -n '/^ctlcheck() {/,/^}/p' "$SRC/lib/control.sh")"
  r=$(jq -c '.later = {cli: "codex"} | .rules.later = "on"' <<<"$CTL0")
  [ "$(ctlcheck <<<"$r" | jq -c '[.later, .rules.later]')" = '[{"cli":"codex"},"on"]' ] \
    || fail "a whole record with keys this copy does not know was refused, or the keys were not passed through"
  ! ctlcheck <<<"$(jq -c '.mode = "fast"' <<<"$r")" >/dev/null || fail "a bad mode beside an unknown key was accepted"
  ! ctlcheck <<<"$(jq -c '.rules.push = "yes"' <<<"$r")" >/dev/null || fail "a bad rules.push beside an unknown rule was accepted"
}
t_controlnewkeywrite() {
  setup '[]'
  jq -c '.later = {cli: "codex"} | .rules.later = "on"' "$ST/control.json" > "$STUB/c.new" && mv "$STUB/c.new" "$ST/control.json"
  loop control hold 7 >/dev/null || fail "hold 7 refused a record with keys this copy does not know"
  [ "$(jq -c '[.held, .later, .rules.later]' "$ST/control.json")" = '[[7],{"cli":"codex"},"on"]' ] \
    || fail "the control action dropped the keys it does not know: $(cat "$ST/control.json")"
}
# A project's own record keeps every value it sets; only the keys it leaves out take the defaults (#593). Bugs: the
# new defaults' cap 6 or judge on win over a record's cap 2 and judge off, or a key the record leaves out is not the
# defaults' (no guard, no seat, the judge's seat lost); conveyor/README.md gives a rule the record leaves out another
# value than it reads (#446: "reads that rule as on" while visible is off); the push-off default overrides a record
# that turned push on.
t_controlkept() {
  # shellcheck disable=SC2034 # CTL_K and HERE are read by ctlread, run by the eval
  local CTL0 CTL_K=() CTL_V CONTROL=$T/$CASE/control.json HERE=$SRC
  CTL0=$(jq -c . "$SRC/lib/control-defaults.json")
  eval "$(sed -n '/^ctlread() {/,/^}/p; /^ctlcheck() {/,/^}/p; /^notwhole() {/p' "$SRC/lib/control.sh")"
  mkdir -p "$T/$CASE" && echo '{"cap":2,"judgeOn":false}' > "$CONTROL"
  ctlread || fail "a record that sets cap and judgeOn alone did not read"
  [ "$(jq -c '[.cap, .judgeOn, .guard, .model, .reviewer, .judge, .rules.visible, .rules.push, .rules.split, .depGuard, .start]' <<<"$CTL_V")" \
    = '[2,false,98,{"model":"claude-opus-5-5","effort":"medium"},{"model":"gpt-6.1-sol","effort":"medium"},{"model":"claude-opus-5-5","effort":"medium"},false,false,"on",true,"queue"]' ] \
    || fail "the record's cap 2 and judge off were not kept, or a key it leaves out is not the new defaults': $CTL_V"
  # conveyor/README.md's rule defaults paragraph must say what this record (saved with no rules) reads (#446): its
  # rules are what the paragraph claims for an older record, built from its own words, not a copy of them.
  local para off split want
  para=$(awk '/^Every rule is on by default/ {p = 1} p && /^$/ {exit} p' "$SRC/README.md" | tr '\n' ' ')
  off=$(sed -n 's/.*except \(.*\), which are off.*/\1/p' <<<"$para" | grep -o '`[A-Za-z0-9]*`' | tr -d '`' | jq -Rsc 'split("\n") | map(select(. != ""))')
  # Split's default, from the paragraph too: the value it names ("`split`, which is `shadow`"), else off when it is in
  # the off list, else on as every rule. Bug caught: a paragraph that gave Split another default still passed.
  split=$(sed -n 's/.*`split`, which is `\([a-z]*\)`.*/\1/p' <<<"$para")
  [ -n "$split" ] || split=$(jq -r 'if IN(.[]; "split") then "off" else "on" end' <<<"$off")
  case $para in
    *"saved before a rule existed reads that rule at its default"*)
      want=$(jq -c --argjson off "$off" --arg split "$split" '{P0: true, P1: true, P2: true, P3: true, followups: true, push: true, visible: true}
        | with_entries(.value = (.key | IN($off[]) | not)) + {split: $split}' <<<null) ;;
    *"saved before a rule existed reads that rule as on"*)
      want='{"P0":true,"P1":true,"P2":true,"P3":true,"followups":true,"push":true,"visible":true,"split":"on"}' ;;
    *) want='"no rule for an older record"' ;;
  esac
  [ "$(jq -c '.rules | {P0, P1, P2, P3, followups, push, visible, split}' <<<"$CTL_V")" = "$want" ] \
    || fail "conveyor/README.md's rule defaults paragraph claims $want for a record saved before its rules, but it reads $(jq -c .rules <<<"$CTL_V")"
  # The Split entry in the rules list names its own default ("It is on by default"); it must say what the record reads
  # too. Bug caught: that entry gave another default ("It is `shadow` by default") and the case still passed, as it
  # read only the paragraph above. The whole entry is read, its indented continuation lines joined, so a sentence
  # that wraps onto the next line is still found.
  local entry
  entry=$(awk 'p && !/^  / {exit} /^- `split`:/ {p = 1} p' "$SRC/README.md" | tr -s ' \n' '  ' \
    | sed -n 's/.*It is `\{0,1\}\([a-z]*\)`\{0,1\} by default.*/\1/p')
  [ "$entry" = "$(jq -r .rules.split <<<"$CTL_V")" ] \
    || fail "conveyor/README.md's Split entry says its default is '$entry', but a record that leaves it out reads $(jq -r .rules.split <<<"$CTL_V")"
  # Split is on for a record that leaves it out (above); a project that set shadow keeps it. Bug caught: the new
  # default overrides a project's own setting, so its large issues start to be split without its choice.
  echo '{"rules":{"split":"shadow"}}' > "$CONTROL"
  ctlread && [ "$(jq -r .rules.split <<<"$CTL_V")" = shadow ] || fail "a record that set split shadow did not keep it over the default on: $CTL_V"
  echo '{"rules":{"push":true}}' > "$CONTROL"
  ctlread && [ "$(jq .rules.push <<<"$CTL_V")" = true ] || fail "a record with push on did not keep it over the defaults: $CTL_V"
}
# The Board's setup (issue 250) reopens until the record says the project is onboarded. Bugs: a new record reads as
# onboarded, so the setup never opens; `control onboarded` does not write when and the rules confirmed (or keeps a
# rule twice), so the Board cannot tell a rule added later; a bad key is written; an onboarded entry of another shape reads.
t_controlonboarded() {
  setup '[]'
  # The key must be there, null: the Board asks only a record that has it (a missing key also reads null in jq).
  [ "$(loop control | jq -c 'has("onboarded") and .onboarded == null')" = true ] || fail "a new record does not read as not onboarded: $(loop control)"
  local out; out=$(loop control onboarded build cap build 2>&1)
  [ "$(jq -c '.onboarded.rules' <<<"$out")" = '["build","cap"]' ] && jq -e '.onboarded.at | test("^20[0-9]{2}-[0-9]{2}-[0-9]{2}T")' <<<"$out" >/dev/null \
    && [ "$(jq -c .onboarded.rules "$ST/control.json")" = '["build","cap"]' ] || fail "control onboarded did not write when and the rules: $out"
  for bad in 'onboarded' 'onboarded Build' 'onboarded -x' 'onboarded a=b'; do
    # shellcheck disable=SC2086
    out=$(loop control $bad 2>&1); [ $? = 2 ] && [ "$(jq -c .onboarded.rules "$ST/control.json")" = '["build","cap"]' ] || fail "control $bad was not refused with nothing changed: $out"
  done
  jq -c '.onboarded = {at: "x", rules: "build"}' "$ST/control.json" > "$STUB/c.new" && mv "$STUB/c.new" "$ST/control.json"
  ! loop control >/dev/null 2>&1 || fail "an onboarded entry whose rules are not a list was read"
}
# The most test files a release suite runs at once in parallel mode, the stored setting suiteAtOnce (#1174), which
# release-prep reads (relsuite()). Bugs: a record that leaves it out reads no number, or one other than 2, so the suite
# runs on every slot of the machine; a value that is no whole number from 1 reads, and the suite is given it.
t_controlatonce() {
  local CTL0 v; CTL0=$(jq -c . "$SRC/lib/control-defaults.json")
  eval "$(sed -n '/^ctlcheck() {/,/^}/p' "$SRC/lib/control.sh")"
  [ "$(ctlcheck <<<'{}' | jq .suiteAtOnce)" = 2 ] || fail "a record with no suiteAtOnce does not read 2: $(ctlcheck <<<'{}' | jq .suiteAtOnce)"
  [ "$(ctlcheck <<<'{"suiteAtOnce":4}' | jq .suiteAtOnce)" = 4 ] || fail "the record {\"suiteAtOnce\":4} did not keep its 4"
  for v in 0 -1 1.5 '"2"' null; do
    ! ctlcheck <<<"{\"suiteAtOnce\":$v}" >/dev/null || fail "the record {\"suiteAtOnce\":$v} was read, though $v is no whole number from 1"
  done
}
# `control atonce <n>`, which the Rules tab's Test files at once sends (#1175), writes suiteAtOnce, the record that
# release-prep reads for a parallel suite (relatonce()). Bugs: the write goes to another key, so the next parallel run
# still reads 2; 0, a negative number, a fraction or a word is written, or is refused with no reason, or with the
# record changed.
t_controlatoncerule() {
  local v out
  controlsetup '[]'
  [ "$(ctl atonce 3 | jq .suiteAtOnce)" = 3 ] && [ "$(jq .suiteAtOnce "$C")" = 3 ] && [ "$(loop control | jq .suiteAtOnce)" = 3 ] \
    || fail "control atonce 3 did not write suiteAtOnce 3: $(jq -c . "$C")"
  for v in 0 -1 1.5 two 1000 ''; do
    out=$(loop control atonce "$v" 2>&1); [ $? = 2 ] && [[ $out == *"is not a whole number from 1"* ]] && [ "$(jq .suiteAtOnce "$C")" = 3 ] \
      || fail "control atonce '$v' was not refused with its reason and nothing changed: $out"
  done
}
# `control suite-mode <serial|parallel>` writes suiteMode, the mode a release-prep or release-run given no flag takes
# (#1364). Bugs: the write goes to another key, so a release still runs one by one; a word other than the two is written
# (the next run reads a mode it has no word for) or is refused with exit 1, or with the record changed; a record with
# no suiteMode reads anything but serial, so other projects' releases change; a stored word that is no mode is read.
t_controlsuitemode() {
  local v out CTL0; CTL0=$(jq -c . "$SRC/lib/control-defaults.json")
  eval "$(sed -n '/^ctlcheck() {/,/^}/p' "$SRC/lib/control.sh")"
  [ "$(ctlcheck <<<'{}' | jq -r .suiteMode)" = serial ] || fail "a record with no suiteMode does not read serial: $(ctlcheck <<<'{}' | jq -c .suiteMode)"
  for v in '"mixed"' null 1 '"Parallel"'; do
    ! ctlcheck <<<"{\"suiteMode\":$v}" >/dev/null || fail "the record {\"suiteMode\":$v} was read, though $v is no mode"
  done
  controlsetup '[]'
  [ "$(ctl suite-mode parallel | jq -r .suiteMode)" = parallel ] && [ "$(jq -r .suiteMode "$C")" = parallel ] && [ "$(loop control | jq -r .suiteMode)" = parallel ] \
    || fail "control suite-mode parallel did not write suiteMode parallel: $(jq -c . "$C")"
  for v in mixed Parallel '' 'serial parallel'; do
    out=$(loop control suite-mode "$v" 2>&1); [ $? = 2 ] && [ "$(jq -r .suiteMode "$C")" = parallel ] \
      || fail "control suite-mode '$v' was not refused with exit 2 and nothing changed: $out"
  done
  out=$(loop control suite-mode 2>&1); [ $? = 2 ] || fail "control suite-mode with no mode was not refused with exit 2: $out"
  [ "$(ctl suite-mode serial | jq -r .suiteMode)" = serial ] || fail "control suite-mode serial did not set the rule back: $(jq -c . "$C")"
}
# Where a release's whole suite runs, the stored rule suiteMachine (lib/suitehost.sh), which `control suite-machine`
# writes. Bugs: a record that leaves it out reads no rule, or one other than this machine, so a suite reaches for a box;
# the ssh form wrote no folder, or wrote a target ssh would read as an option (-oProxyCommand=... runs a command
# here) or a folder the box cannot place; a refusal changed the record.
t_controlsuitemachine() {
  local CTL0 a out; CTL0=$(jq -c . "$SRC/lib/control-defaults.json")
  eval "$(sed -n '/^ctlcheck() {/,/^}/p' "$SRC/lib/control.sh")"
  [ "$(ctlcheck <<<'{}' | jq -c .suiteMachine)" = '{"kind":"local"}' ] || fail "a record with no suiteMachine does not read this machine: $(ctlcheck <<<'{}' | jq -c .suiteMachine)"
  for a in '{"kind":"ssh","target":"-oProxyCommand=x","dir":"~"}' '{"kind":"ssh","target":"h","dir":"rel"}' '{"kind":"ssh","target":"h"}' '{"kind":"box"}' '{"kind":"local","target":"h"}'; do
    ! ctlcheck <<<"{\"suiteMachine\":$a}" >/dev/null || fail "the record {\"suiteMachine\":$a} was read"
  done
  controlsetup '[]'
  [ "$(ctl suite-machine ssh tester@box.example.com | jq -c .suiteMachine)" = '{"kind":"ssh","target":"tester@box.example.com","dir":"~/conveyor-suite"}' ] \
    || fail "control suite-machine ssh tester@box.example.com did not write the rule with the folder ~/conveyor-suite: $(jq -c .suiteMachine "$C")"
  [ "$(ctl suite-machine ssh box --dir /srv/suite | jq -c .suiteMachine)" = '{"kind":"ssh","target":"box","dir":"/srv/suite"}' ] && [ "$(loop control | jq -r .suiteMachine.dir)" = /srv/suite ] \
    || fail "control suite-machine ssh box --dir /srv/suite did not write that folder: $(jq -c .suiteMachine "$C")"
  for a in 'ssh -oProxyCommand=x' 'ssh box --dir rel/path' 'ssh' 'ssh box --dir' 'box' 'local x'; do
    # shellcheck disable=SC2086 # each word an argument
    out=$(loop control suite-machine $a 2>&1); [ $? = 2 ] && [ "$(jq -c .suiteMachine "$C")" = '{"kind":"ssh","target":"box","dir":"/srv/suite"}' ] \
      || fail "control suite-machine $a was not refused with nothing changed: $out"
  done
  # The devbox rule (#1274). Bugs: the rule had no size or the idle stop, or a tag that is not the project's, so two
  # projects share a devbox; a size that jq or the devbox command would read as an option was written; a record whose
  # devbox rule lacks a key, or has a bad tag, size or idle stop, was read; a refusal changed the record.
  [ "$(ctl suite-machine devbox | jq -c .suiteMachine)" = '{"kind":"devbox","size":"4x8","tag":"conveyor-suite-main","idleStop":"15m"}' ] \
    || fail "control suite-machine devbox did not write the rule with the size 4x8, the project's tag and 15m: $(jq -c .suiteMachine "$C")"
  [ "$(ctl suite-machine devbox --size 8x16 | jq -c .suiteMachine)" = '{"kind":"devbox","size":"8x16","tag":"conveyor-suite-main","idleStop":"15m"}' ] \
    || fail "control suite-machine devbox --size 8x16 did not write that size: $(jq -c .suiteMachine "$C")"
  # Bug: saving the same devbox rule again (`suite-machine devbox --size 8x16`) dropped the setupAt the runs kept, so the Board said "set-up time not kept" for a box a run had set up; a new size is a new box, and has none.
  jq -c '.suiteMachine.setupAt = "2026-11-20T15:04:00Z"' "$C" > "$C.new" && mv "$C.new" "$C" || fail "the fixture could not be made"
  [ "$(ctl suite-machine devbox --size 8x16 | jq -r .suiteMachine.setupAt)" = 2026-11-20T15:04:00Z ] || fail "control suite-machine devbox --size 8x16 again dropped the box's setupAt: $(jq -c .suiteMachine "$C")"
  [ "$(ctl suite-machine devbox --size 4x8 | jq -c '.suiteMachine | has("setupAt")')" = false ] || fail "control suite-machine devbox --size 4x8 kept the setupAt of the 8x16 box: $(jq -c .suiteMachine "$C")"
  # Bug: the Board's Undo of "Use this machine" put the devbox back with no setupAt (a local rule keeps none), so the Box row said "set-up time not kept"; --setup-at gives it back, and a bad time is refused.
  ctl suite-machine local > /dev/null
  [ "$(ctl suite-machine devbox --size 8x16 --setup-at 2026-11-20T15:04:00Z | jq -c '.suiteMachine | [.size, .setupAt]')" = '["8x16","2026-11-20T15:04:00Z"]' ] || fail "control suite-machine devbox --size 8x16 --setup-at <time> from a local rule did not keep the time: $(jq -c .suiteMachine "$C")"
  out=$(loop control suite-machine devbox --size 8x16 --setup-at yesterday 2>&1); [ $? = 2 ] && [ "$(jq -r .suiteMachine.setupAt "$C")" = 2026-11-20T15:04:00Z ] || fail "control suite-machine devbox --setup-at yesterday was not refused with the record left as it was: $out"
  ctl suite-machine local > /dev/null  # a local rule keeps no setupAt: the next rule has none
  ctl suite-machine devbox --size 8x16 > /dev/null || fail "control suite-machine devbox --size 8x16 did not set the rule back"
  for a in 'devbox --size' 'devbox --size -oX' 'devbox --size a/b' 'devbox 4x8' 'devbox --size 4x8 x' 'devbox --setup-at 2026-11-20T15:04:00Z' 'devbox --dir ~' 'devbox --box' 'devbox --box -oX' 'devbox --box a/b'; do
    # shellcheck disable=SC2086 # each word an argument
    out=$(loop control suite-machine $a 2>&1); [ $? = 2 ] && [ "$(jq -c .suiteMachine "$C")" = '{"kind":"devbox","size":"8x16","tag":"conveyor-suite-main","idleStop":"15m"}' ] \
      || fail "control suite-machine $a was not refused with nothing changed: $out"
  done
  for a in '{"kind":"devbox","size":"4x8","tag":"conveyor-suite-x"}' '{"kind":"devbox","size":"-x","tag":"conveyor-suite-x","idleStop":"15m"}' '{"kind":"devbox","size":"4x8","tag":"x","idleStop":"15m"}' \
    '{"kind":"devbox","size":"4x8","tag":"conveyor-suite-x","idleStop":"soon"}' '{"kind":"devbox","size":"4x8","tag":"conveyor-suite-x","idleStop":"15m","target":"h"}'; do
    ! ctlcheck <<<"{\"suiteMachine\":$a}" >/dev/null || fail "the record {\"suiteMachine\":$a} was read"
  done
  ctlcheck <<<'{"suiteMachine":{"kind":"devbox","size":"4x8","tag":"conveyor-suite-x","idleStop":"15m"}}' > /dev/null || fail "a record with a whole devbox rule was not read"
  # Bug: a devbox record with the time its script last ran (setupAt, hostsetup()) was refused as not whole, so a run that kept it stopped every pick; a bad time, or one on another kind, is still refused.
  ctlcheck <<<'{"suiteMachine":{"kind":"devbox","size":"4x8","tag":"conveyor-suite-x","idleStop":"15m","setupAt":"2026-11-20T15:04:00Z"}}' > /dev/null || fail "a devbox rule with setupAt was not read"
  for a in '{"kind":"devbox","size":"4x8","tag":"conveyor-suite-x","idleStop":"15m","setupAt":"yesterday"}' '{"kind":"ssh","target":"h","dir":"~","setupAt":"2026-11-20T15:04:00Z"}'; do
    ! ctlcheck <<<"{\"suiteMachine\":$a}" >/dev/null || fail "the record {\"suiteMachine\":$a} was read"
  done
  # Bug (an account's own devbox could not be used): the rule had no way to name a devbox that exists, so a box with no tag was never
  # found and a new one was refused at the account's limit. --box keeps the name in the rule, the set-up time stays only for the same box,
  # and a record with a bad box name is not read.
  [ "$(ctl suite-machine devbox --box hand-made | jq -c .suiteMachine)" = '{"kind":"devbox","size":"4x8","tag":"conveyor-suite-main","idleStop":"15m","box":"hand-made"}' ] \
    || fail "control suite-machine devbox --box hand-made did not write the box: $(jq -c .suiteMachine "$C")"
  ctl suite-machine devbox --size 4x8 --box hand-made --setup-at 2026-11-20T15:04:00Z > /dev/null || fail "control suite-machine devbox --size 4x8 --box hand-made --setup-at <time> did not set the rule"
  [ "$(ctl suite-machine devbox --box hand-made | jq -r .suiteMachine.setupAt)" = 2026-11-20T15:04:00Z ] || fail "saving the same named box again dropped its setupAt: $(jq -c .suiteMachine "$C")"
  # Bug: the Size choice sends --size with the same --box, and the save dropped the set-up time of a box whose size the rule does not use.
  [ "$(ctl suite-machine devbox --size 8x16 --box hand-made | jq -r .suiteMachine.setupAt)" = 2026-11-20T15:04:00Z ] || fail "a new size with the same named box dropped its setupAt: $(jq -c .suiteMachine "$C")"
  [ "$(ctl suite-machine devbox --box other | jq -c '.suiteMachine | has("setupAt")')" = false ] || fail "another box kept the setupAt of hand-made: $(jq -c .suiteMachine "$C")"
  [ "$(ctl suite-machine devbox | jq -c '.suiteMachine | has("box")')" = false ] || fail "control suite-machine devbox kept the box named before: $(jq -c .suiteMachine "$C")"
  ! ctlcheck <<<'{"suiteMachine":{"kind":"devbox","size":"4x8","tag":"conveyor-suite-x","idleStop":"15m","box":"-x"}}' > /dev/null || fail "a devbox rule with the box name -x was read"
  [ "$(ctl suite-machine local | jq -c .suiteMachine)" = '{"kind":"local"}' ] || fail "control suite-machine local did not write this machine: $(jq -c .suiteMachine "$C")"
}
# Bug (issue 1333): a hold sent the running loop nothing, so the loop took the new record only once its turn's timer
# ended. A hold wakes (URG) the process loop.json names, and only while loop.json's start time is that process's: a
# pid used again by another process after the loop ended is sent nothing. The stand-in counts each URG it is sent.
t_controlwake() {
  controlsetup "[$(issue 4 2026-01-01)]"
  bash -c 'trap "echo urg >> \"\$0.urg\"" URG; : > "$0.ready"; sleep 60 & s=$!; while kill -0 "$s" 2>/dev/null; do wait "$s"; done' "$STUB/loop" & e=$! # sleep: the stand-in loop's own wait
  wait_until '[ -e "$STUB/loop.ready" ]' || fail "the stand-in loop did not start"
  jq -cn --argjson p "$e" '{pid: $p, started: "Thu Jan  1 00:00:00 1970"}' > "$S/loop.json"
  ctl hold 4 >/dev/null || fail "hold 4 was refused"
  sleep 0.5 # sleep: a URG sent would have been counted by now
  [ ! -e "$STUB/loop.urg" ] || fail "control hold 4 woke pid $e, which loop.json names with another start time: $(cat "$S/loop.json")"
  jq -cn --argjson p "$e" --arg t "$(p_started "$e")" '{pid: $p, started: $t}' > "$S/loop.json"
  ctl hold 4 >/dev/null || fail "hold 4 was refused"
  WAIT_CEILING=10 wait_until '[ -s "$STUB/loop.urg" ]' || fail "control hold 4 did not wake the loop loop.json names: $(cat "$S/loop.json")"
  kill "$e" 2>/dev/null; wait "$e" 2>/dev/null; return 0
}
# Bug (issue 1333): a release sent the running loop nothing, so a loop asleep on its idle timer (the pack's idle, here
# 100 s) picked the released issue only once the timer ended. Here #4 is picked well before the timer would end.
# It runs the real `serve` loop, as only its own turn shows that the wake ends the wait and that the pick follows it.
t_controlwakeloop() {
  controlsetup "[$(issue 4 2026-01-01)]"; tune '.tunables.idle = 100 | .tunables.poll = 1'; watchturns
  ctl hold 4 >/dev/null || fail "hold 4 was refused"
  loop serve > "$STUB/serve.out" 2>&1 & lp=$! # loop: only the loop's own turn shows its idle wait ending on the release
  # The loop's first timer: it has picked nothing (#4 held) and sleeps on its idle timer.
  wait_until "grep -qxF '$R' '$TURNS'" "cat '$STUB/serve.out'" || fail "the loop took no turn"
  ctl release 4 >/dev/null || fail "release 4 was refused"
  WAIT_CEILING=$(loadlimit 20 100) wait_until "[ -n \"\$(st 'select(.issue == 4 and .step == \"picked\") | .card' 2>/dev/null)\" ]" "cat '$STUB/serve.out'" \
    || fail "control release 4 did not wake the loop asleep on its 100 s idle timer: #4 was not picked"
  kill "$lp" 2>/dev/null; wait "$lp" 2>/dev/null; return 0
}
# Bug (issue 1349): `control release` of an issue the record's held does not list (held by a card, a rule or a split)
# changed nothing and said nothing, so the Foreman took it for released. It now says so on stderr; exit stays 0.
t_controlreleasenothing() {
  controlsetup "$(jq -cs . <(issue 5 2026-01-01) <(issue 6 2026-02-01))"
  loop control hold 6 >/dev/null || fail "hold 6 was refused"
  before=$(loop control); rc=0; err=$(loop control release 5 2>&1 >/dev/null) || rc=$?
  [ "$rc" = 0 ] || fail "control release 5, not held, exited $rc: $err"
  [ "$err" = 'conveyor: #5 is not held in this record, so nothing changed; foreman status says what holds it' ] \
    || fail "control release 5, not held, printed on stderr: $err"
  [ "$(loop control | jq -c .held)" = "$(jq -c .held <<<"$before")" ] || fail "control release 5, not held, changed held: $(loop control)"
  err=$(loop control release 6 2>&1 >/dev/null) || fail "control release 6, held, failed: $err"
  [ -z "$err" ] || fail "control release 6, held, printed on stderr: $err"
  [ "$(loop control | jq -c .held)" = '[]' ] || fail "control release 6 did not release #6: $(loop control)"
}
