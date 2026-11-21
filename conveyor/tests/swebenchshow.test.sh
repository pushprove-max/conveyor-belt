#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 120
# Engine cases: what the Board's Benchmarks tab reads of `conveyor.sh bench swe` (bench/swe.sh): one run's page
# (`bench swe show`, with the run's cost at list prices), the cost Start shows (`bench swe history`, each arm's perTask), and the arms the form saves
# (`bench swe arms save`, the choices history offers), with the settings a run shares and the reuse of its results
# (`--settings`, swe_inputs). The fixture is swebench.test.sh's swe().
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"

# Bugs (#326): (1) the run page could not open a run of 500 tasks and 6 arms on Linux: show passed the run's line,
# 3,000 task records, to jq as one argument, past the system's 128 KiB limit on one argument; (2) a stopped run showed
# a task as resolved by an arm it never ran there, from the result a later run kept under the arm's key; (3) Start
# showed no cost: each arm's perTask had no dollars of a session, so the Board could only show a dash, and then read
# $STATE.priced as two fields with no header, so jq stopped at the real file's header line and the dash stayed;
# (4) before the first run (no live.json) history and show failed under pipefail, so Start had no arms to offer.
t_sweshow() {
  swe; local o i
  o=$(loop bench swe history 2>&1) || fail "history fails before the first run, so Start offers no arm: $(head -c 300 <<<"$o")"
  [ "$(jq -c '[.runs, (.arms | length > 0)]' <<<"$o")" = '[[],true]' ] || fail "history before the first run has not its arms and no runs: $(head -c 300 <<<"$o")"
  # Bug (#642): history gave no limits, so the Board's Run settings could not show the defaults a run takes.
  [ "$(jq -c .limits <<<"$o")" = "$(jq -c '{cpus: .limits.cpus, memory: .limits.memory, taskTimeout}' "$SRC/bench/swe.json")" ] || fail "history has not swe.json's limits: $(jq -c .limits <<<"$o")"
  for i in stub-a/false stub-b/true; do mkdir -p "$B/results/${i%/*}" && jq -nc --arg a "${i%/*}" --argjson r "${i#*/}" \
      '{task: "proj__a-1", arm: $a, key: $a, label: $a, resolved: $r, fired: true, sessions: 1, tokens: 3, minutes: 1, steps: []}' > "$B/results/${i%/*}/proj__a-1.json" || fail "a result could not be written"; done
  # No live.json here (no run in progress): show and history read runs.jsonl alone. The priced file is as
  # dashboard_limit.py cardlines writes it: a header line, then `<hash>\t<the card priced>\t<what it counts>`.
  jq -nc '{id: "r20261117T090000-1", arms: ["a1", "a2", "a3", "a4", "a5", "a6"], cols: [range(1; 7) | {arm: "a\(.)", key: "k\(.)"}], n: 3000,
      started: "2026-11-17T09:00:00Z", state: "done", tasks: [range(500) as $t | range(1; 7) | {id: "proj__task-\(1000 + $t)", arm: "a\(.)", result: "unresolved"}]}' > "$B/runs.jsonl" \
    && jq -nc '{id: "r20261117T100000-2", arms: ["stub-a", "stub-b"], cols: [{arm: "stub-a", key: "stub-a"}, {arm: "stub-b", key: "stub-b"}], n: 2,
      started: "2026-11-17T10:00:00Z", state: "stopped", tasks: [{id: "proj__a-1", arm: "stub-a", result: "unresolved", minutes: 4},
        {id: "proj__b-2", arm: "stub-a", result: "not run: the harness could not grade it (exit 1)", reused: false, cost: {usd: 0.7, state: "known", unpriced: 0}, minutes: 2.5}],
      interrupted: {arm: "stub-b", task: "proj__a-1", cost: {usd: 0.3, state: "partial", unpriced: 1}, minutes: 1.5}}' >> "$B/runs.jsonl" \
    && { echo "k0 s0"; for i in 2 4 0.5 0; do jq -nc --argjson u "$i" '{card: "c1", steps: [{step: "build", usd: $u, pricedAs: (if $u == 0.5 then "other" else "m" end)}, {step: "review", usd: null}]}' \
      | sed 's/^/h\t/; s/$/\t[]/'; done; } > "$ST/cards.jsonl.priced" || fail "the runs and prices could not be written"
  [ "$(wc -c < "$B/runs.jsonl")" -gt 131072 ] || fail "the big run's line is not past the 128 KiB argument limit, so it proves nothing"
  o=$(loop bench swe show r20261117T090000-1 2>&1) || fail "show cannot open a run of 500 tasks and 6 arms: $(head -c 300 <<<"$o")"
  [ "$(jq -c '[(.tasks | length), (.tasks[0].cells | length), .tasks[499].id]' <<<"$o")" = '[500,6,"proj__task-1499"]' ] \
    || fail "show does not give every task of the big run with its 6 arms: $(head -c 300 <<<"$o")"
  o=$(loop bench swe show r20261117T100000-2 2>&1) || fail "show failed: $o"
  [ "$(jq -c '.tasks[0].cells | map([.arm, .result, .resolved])' <<<"$o")" = '[["stub-a","unresolved",false],["stub-b",null,null]]' ] \
    || fail "the stopped run shows a result for an arm it never ran on the task: $o"
  # Bug (#646): a task not run after its trial ran, and the task Stop interrupted, had no cost in their cells: the run
  # page and its export said unknown for work whose cost the run line keeps.
  [ "$(jq -c '[.tasks[0].cells[1] | .state, .cost.usd, .cost.state] + [.tasks[1].cells[0] | .cost.usd, .cost.state]' <<<"$o")" = '["interrupted",0.3,"partial",0.7,"known"]' ] \
    || fail "the interrupted task's cost or the not run task's cost is not in its cell: $(jq -c '.tasks' <<<"$o")"
  # Bug (#646 review E3): an arm's active time left out a task not run after its trial ran and the interrupted work.
  [ "$(jq -c '.run.cols | map(.wall)' <<<"$o")" = '[6.5,1.5]' ] || fail "an arm's wall does not sum its tasks' and its interrupted work's minutes: $(jq -c .run.cols <<<"$o")"
  o=$(loop bench swe history 2>&1) || fail "history failed: $(head -c 300 <<<"$o")"
  [ "$(jq -c '.arms | map(select(.name | IN("conveyor", "solo")) | [.name, .perTask.session])' <<<"$o")" = '[["conveyor",2.1667],["solo",3]]' ] \
    || fail "an arm's perTask has not the mean dollars of this project's priced sessions (its model's, for an arm with one): $(jq -c '.arms | map([.name, .perTask])' <<<"$o")"
}

# Bugs (#634): the Board's arm form had no way to keep an arm (save it, read it back by an ID, and keep the old one when
# it is edited), no list of the models the project allows each seat to offer, and nothing refused a CLI and model the
# project does not allow, so a form could run a Codex review model as the builder of a pack that lists no Codex builder.
t_swearmsave() {
  swe; local o id1 id2 s1='{"kind":"conveyor","seats":{"model":{"cli":"claude","model":"m","effort":"high"},"reviewer":{"cli":"codex","model":"x"}}}'
  o=$(loop bench swe history 2>&1) || fail "history failed: $(head -c 300 <<<"$o")"
  [ "$(jq -c '.choices | [.source, .builder.claude[-1], .builder.codex, .reviewer.codex[-1], .agent.codex[-1], .efforts.codex[0]]' <<<"$o")" = '["project","m",[],"x","x","minimal"]' ] \
    || fail "history does not publish the models the project allows each seat pool, by CLI: $(jq -c .choices <<<"$o")"
  id1=$(loop bench swe arms save 'Claude builds, Codex reviews' "$s1" 2>&1) && [[ $id1 =~ ^arm-[0-9a-f]{12}$ ]] || fail "the arm was not saved: $id1"
  o=$(loop bench swe arms show "$id1" 2>&1) && [ "$(jq -cS '[.id, .name, .spec]' <<<"$o")" = "$(jq -cSn --arg i "$id1" --argjson s "$s1" '[$i, "Claude builds, Codex reviews", $s]')" ] \
    || fail "the saved arm does not read back by its ID as it was saved: $o"
  # An edit is a new revision under the same name; the first stays as it was, for the runs that used it.
  id2=$(loop bench swe arms save 'Claude builds, Codex reviews' '{"kind":"conveyor","seats":{"model":{"cli":"claude","model":"m"}}}' 2>&1) && [ "$id2" != "$id1" ] \
    || fail "the edit did not make a new revision: $id2"
  o=$(loop bench swe arms show "$id1" 2>&1) && [ "$(jq -cS .spec <<<"$o")" = "$(jq -cS . <<<"$s1")" ] || fail "the edit changed the earlier revision: $o"
  # Refused, nothing kept: a Codex review model as the builder; a model of another CLI for an agent; a seat effort its
  # CLI does not take; rules other than engine or project; a review policy the control record cannot hold; a command
  # given through the form.
  for o in '{"kind":"conveyor","seats":{"model":{"cli":"codex","model":"x"}}}/does not allow "x" on codex for the builder seat' \
      '{"kind":"agent","recipe":"solo","cli":"claude","model":"x"}/does not allow "x" on claude' \
      '{"kind":"conveyor","seats":{"reviewer":{"cli":"codex","model":"x","effort":"max"}}}/codex takes no effort "max"' \
      '{"kind":"conveyor","rules":"all"}/the rules are engine or project, not "all"' \
      '{"kind":"conveyor","policy":{"judgeOn":"no"}}/judgeOn and P0 to P3 are true or false' \
      '{"kind":"conveyor","policy":{"judgeAlways":["-x"]}}/judgeAlways is a list of at most 20 finding kinds, each a word of letters, digits, _ and -' \
      '{"kind":"conveyor","policy":{"P4":true}}/the policy takes judgeOn, judgeAlways and P0 to P3 only' \
      '{"kind":"agent","recipe":"solo","cli":"claude","model":"m","run":"true"}/takes kind, recipe, cli, model and effort only, not run' \
      '{"kind":"agent","recipe":"solo","cli":"claude","model":"m","effort":"minimal"}/claude takes no effort "minimal"'; do
    id2=$(loop bench swe arms save bad "${o%%/*}" 2>&1) && fail "a choice the project does not allow was saved: ${o%%/*}"
    grep -qF "${o#*/}; nothing saved" <<<"$id2" || fail "the refusal does not say why: $id2"
  done
  [ "$(ls "$B/arms" | wc -l)" = 2 ] || fail "a refused arm was kept: $(ls "$B/arms")"
  # Bug (#641): history listed the host arms only, so after a reload the Board's arm form could not show, check or reuse
  # a saved revision, had no recipe facts to offer an agent arm's method, and could not say what a seat left out runs on.
  # The project sets a test repair seat of its own (its fix follows the builder) and its judge on.
  jq -c '.testFix = {cli: "claude", model: "m", effort: "high"} | .judgeOn = true | .judgeAlways = ["style"]' "$ST/control.json" > "$ST/c.new" && mv "$ST/c.new" "$ST/control.json" \
    || fail "the control record was not changed"
  o=$(loop bench swe history 2>&1) || fail "history failed: $(head -c 300 <<<"$o")"
  [ "$(jq -c --arg a "$id1" '[.arms[] | select(.revision != null) | [.name == $a, .label, .kind, .state, .revision.name, .revision.recipe, .spec.seats.model.effort]] | sort' <<<"$o")" \
    = '[[false,"Claude builds, Codex reviews","conveyor","unchecked","Claude builds, Codex reviews","conveyor",null],[true,"Claude builds, Codex reviews","conveyor","unchecked","Claude builds, Codex reviews","conveyor","high"]]' ] \
    || fail "history does not list both saved revisions with their name, state and own spec: $(jq -c '.arms | map([.name, .label, .state, .revision, .spec])' <<<"$o")"
  [ "$(jq -c '[.arms[] | select(.name | IN("solo", "conveyor")) | [.name, .revision, .spec, .sessions, .effort]]' <<<"$o")" \
    = '[["conveyor",null,{"kind":"conveyor"},null,false],["solo",null,{"kind":"agent","recipe":"solo","cli":"claude","model":"m"},1,true]]' ] \
    || fail "a host arm has not the spec a copy starts from and its recipe facts: $(jq -c '[.arms[] | select(.name | IN("solo", "conveyor")) | [.name, .revision, .spec, .sessions, .effort]]' <<<"$o")"
  [ "$(jq -c .defaults <<<"$o")" = '{"seats":{"model":{"model":"m","effort":"medium","agent":"claude"},"reviewer":{"model":"x","effort":"medium","agent":"codex"},"judge":{"model":"claude-opus-5-5","effort":"medium","agent":"claude"},"fix":null,"testFix":{"model":"m","effort":"high","agent":"claude"}},"judgeOwn":false,"judgeOn":true,"judgeAlways":["style"]}' ] || fail "history does not publish the seats an arm that sets none runs on: $(jq -c .defaults <<<"$o")"
}

# Bug (#634, #637): a saved agent arm's recipe ran on its own model (solo's: the builder's, m), not on the saved one,
# and the saved effort never reached the CLI.
t_swearmsaveagent() {
  swe; local o id2
  tune '.models.allowed.claude += ["m2"]'
  id2=$(loop bench swe arms save 'Claude alone on m2' '{"kind":"agent","recipe":"solo","cli":"claude","model":"m2","effort":"high"}' 2>&1) || fail "an agent arm on an allowed model was refused: $id2"
  echo 'echo fixed > x.py' > "$STUB/build"
  o=$(loop bench swe 1 --arm "$id2" 2>&1) || fail "the saved agent arm's run failed: $o"
  [[ $(tail -n 1 "$STUB/sessions") == *'--model m2 --effort high '* ]] || fail "the recipe was not given the saved arm's model and effort: $(tail -n 1 "$STUB/sessions")"
}

# Bugs (#637): a saved agent arm's effort never reached its CLI (Codex alone, or a Claude method such as Superpowers);
# a recipe that cannot pass an effort, or that runs on another CLI, was not refused at the save; and a method arm
# that did not fire must keep why in its result. The recipes are the real ones, with nothing to install; the Codex
# stand-in notes its arguments, and the Claude stub fires Superpowers' filter on the preflight's task alone.
t_swearmeffort() {
  swe; local a o cx sp first
  first=$(sweorder | head -n 1)
  tune '.models.allowed.claude += ["m2"]'
  for a in codex-sol superpowers; do jq '.install = "true" | .preflight = "true"' "$SRC/bench/arms/$a.json" > "$SWE_FX/arms/$a.json" || fail "the recipe $a was not copied"; done
  jq 'del(.effort)' "$SWE_FX/arms/solo.json" > "$SWE_FX/arms/no-effort.json" || fail "the recipe with no effort was not made"
  for o in '{"kind":"agent","recipe":"no-effort","cli":"claude","model":"m2","effort":"high"}/the arm no-effort takes no effort' \
      '{"kind":"agent","recipe":"superpowers","cli":"codex","model":"x"}/the arm superpowers does not run on codex alone' \
      '{"kind":"agent","recipe":"codex-sol","cli":"codex","model":"x","effort":"max"}/codex takes no effort "max"'; do
    a=$(loop bench swe arms save bad "${o%%/*}" 2>&1) && fail "an incompatible method was saved: ${o%%/*}"
    grep -qF "${o#*/}" <<<"$a" || fail "the refusal does not say why: $a"
  done
  printf '%s\n' '#!/usr/bin/env bash' 'echo "$*" >> "$SWE_FX/codex-args"; cat > /dev/null; [ ! -e hello.py ] || echo "print(\"hello\")" > hello.py; [ ! -e x.py ] || echo fixed > x.py' \
    'echo "{\"type\":\"turn.completed\",\"usage\":{\"input_tokens\":1,\"output_tokens\":1}}"' > "$SWE_FX/bin/codex" && chmod +x "$SWE_FX/bin/codex" || fail "the Codex stand-in was not made"
  echo 'if [ -e hello.py ]; then echo "print(\"hello\")" > hello.py; echo "{\"type\":\"assistant\",\"message\":{\"content\":[{\"type\":\"tool_use\",\"name\":\"Skill\",\"input\":{\"skill\":\"superpowers:x\"}}]}}"; else echo fixed > x.py; fi' > "$STUB/build"
  cx=$(loop bench swe arms save 'Codex on x' '{"kind":"agent","recipe":"codex-sol","cli":"codex","model":"x","effort":"low"}' 2>&1) || fail "the Codex arm was refused: $cx"
  sp=$(loop bench swe arms save 'Superpowers on m2' '{"kind":"agent","recipe":"superpowers","cli":"claude","model":"m2","effort":"max"}' 2>&1) || fail "the method arm was refused: $sp"
  o=$(loop bench swe 1 --arm "$cx" --arm "$sp" 2>&1) || fail "the run failed: $o"
  [ -s "$SWE_FX/codex-args" ] && ! grep -v -- '-m x -c model_reasoning_effort="low" -' "$SWE_FX/codex-args" || fail "Codex was not given the saved model and effort: $(cat "$SWE_FX/codex-args")"
  [ -s "$STUB/sessions" ] && ! grep -v -- '--model m2 --effort max$' "$STUB/sessions" || fail "the method's Claude was not given the saved model and effort: $(cat "$STUB/sessions")"
  jq -e '.resolved' "$B"/results/"$cx"-*/"$first.json" > /dev/null || fail "the Codex arm did not resolve its task: $(cat "$B"/results/"$cx"-*/"$first.json" 2>&1)"
  jq -e '.fired == false and .why == "it did not fire: its output shows no use of its method"' "$B"/results/"$sp"-*/"$first.json" > /dev/null \
    && grep -qF "unresolved (it did not fire: its output shows no use of its method)" <<<"$o" || fail "the method that did not fire lost why: $o $(cat "$B"/results/"$sp"-*/"$first.json" 2>&1)"
}

# Bug (#634): a conveyor arm's seat models were added to the sandbox pack's models.allowed under the seat's CLI, so a
# saved arm with a Codex builder put that builder model in the Codex review list: a form could add a model to the
# project's choices. A saved arm's run gives the engine its seats on the project's own list.
t_swearmsaverun() {
  swe; local id o
  tune '.models.allowed["codex-builder"] = ["xb"]'
  id=$(loop bench swe arms save 'Codex builds' '{"kind":"conveyor","seats":{"model":{"cli":"codex","model":"xb"}}}' 2>&1) || fail "the arm was not saved: $id"
  o=$(loop bench swe 1 --arm "$id" 2>&1) || fail "the saved arm's run failed: $o"
  grep -q "^Resolved 1 of 1 with Codex builds on engine main ($EB); not run: 0\.$" <<<"$o" || fail "the saved arm did not run under its name: $o"
  # Bug (#640): the Board's Start had no receipt of the run it started, only a guess that its process still ran; the
  # run prints its id once its record is written.
  [ "$(head -n 1 <<<"$o")" = "conveyor: run $(tail -n 1 "$B/runs.jsonl" | jq -r .id) started" ] || fail "the run printed no receipt of its record first: $o"
  # Bug (#640): a check that named a saved revision not there still admitted and ran the other arms' checks, so the
  # Board's request neither failed nor got every receipt; it is refused whole, no check admitted.
  o=$(loop bench swe arms check "$id" arm-ffffffffffff 2>&1) && fail "a check of an unknown revision was taken: $o"
  [ "$o" = 'conveyor: no arm arm-ffffffffffff: `conveyor.sh bench swe arms` lists them' ] || fail "the check of an unknown revision admitted another arm's: $o"
  jq -e '.model == {cli: "codex", model: "xb"}' "$SWE_FX/control.seen" > /dev/null || fail "the engine was not given the saved arm's builder: $(cat "$SWE_FX/control.seen")"
  [ "$(jq -c .models.allowed "$SWE_FX/pack.seen")" = "$(jq -c .models.allowed "$R/.conveyor/project.json")" ] \
    || fail "the saved arm changed the sandbox's allowed models: $(jq -c .models.allowed "$SWE_FX/pack.seen")"
}

# Bugs (#638): a run's settings did not reach its trials: every container took swe.json's CPU and memory limits and
# its time limit, the tasks came in the pinned seed's order, the grade read the pinned dataset revision; a result kept
# on other limits was reused, as an agent arm's results were kept under its name alone; and Start took a preflight
# passed on another image or other limits.
t_swesettings() {
  swe; local s o set f0 f1 d=$T/$CASE/bin rv=0123456789abcdef0123456789abcdef01234567; f0=$(sweorder | head -n 1)
  for s in s1 s2 s3 s4 s5 s6 s7 s8; do [ "$(sweorder "$s" | head -n 1)" = "$f0" ] || break; done; f1=$(sweorder "$s" | head -n 1)
  [ "$f1" != "$f0" ] || fail "no seed of s1 to s8 puts the tasks in another order"
  # The first run keeps the chosen revision's task list in the pinned seed's order.
  o=$(loop bench swe 1 --arm stub-a --settings "{\"revision\": \"$rv\"}" 2>&1) && grep -q "^1/1 $f0: resolved$" <<<"$o" || fail "the run on the revision failed: $o"
  [ "$(cat "$SWE_FX/graded")" = "$(jq -r .dataset "$SRC/bench/swe.json") $rv $f0" ] || fail "the grade did not read the revision chosen: $(cat "$SWE_FX/graded")"
  # timeout notes the limit it is given and the script it runs: an install ends "; true", a stub-a run writes creds-seen.
  mkdir -p "$d" && printf '%s\n' '#!/usr/bin/env bash' '{ printf "%s\t" "$1"; printf "%s" "${@: -1}" | tr "\n" " "; echo; } >> "$SWE_FX/timeouts"' 'exec "$SWE_TIMEOUT" "$@"' > "$d/timeout" \
    && chmod +x "$d/timeout" || fail "the timeout stand-in was not made"
  export SWE_TIMEOUT; SWE_TIMEOUT=$(command -v timeout); export PATH=$d:$PATH; : > "$SWE_FX/docker.log"
  set=$(jq -cn --arg s "$s" --arg r "$rv" '{seed: $s, revision: $r, cpus: 0.5, memory: "600m", taskTimeout: 123}')
  # Bug: the list kept for that revision was read for another seed.
  o=$(loop bench swe 1 --arm stub-a --settings "$set" 2>&1) && grep -q "^1/1 $f1: resolved$" <<<"$o" || fail "the run did not take the first task of the seed's order: $o"
  [ "$(grep -c '^create ' "$SWE_FX/docker.log")" = 2 ] && ! grep '^create ' "$SWE_FX/docker.log" | grep -qv -- '--cpus 0.5 --memory 600m ' \
    || fail "the preflight's and the trial's containers did not get the limits: $(grep '^create ' "$SWE_FX/docker.log")"
  [ "$(grep -c $'^123\t.*; true$' "$SWE_FX/timeouts")" = 2 ] && [ "$(grep -c $'^123\t.*creds-seen' "$SWE_FX/timeouts")" = 2 ] \
    || fail "the install and the run of the preflight and of the task were not each held to taskTimeout: $(cat "$SWE_FX/timeouts")"
  tail -n 1 "$B/runs.jsonl" | jq -e --arg s "$s" --arg r "$rv" '.set.seed == $s and .set.revision == $r and .limits == {cpus: 0.5, memory: "600m", taskTimeout: 123}' > /dev/null \
    || fail "the run's line does not keep its settings: $(tail -n 1 "$B/runs.jsonl")"
  # Bug: the preflight passed on the first task's image of the seed was taken for the pinned order's first task.
  : > "$SWE_FX/docker.log"; o=$(loop bench swe 1 --arm stub-a --settings "$(jq -c 'del(.seed)' <<<"$set")" 2>&1) \
    && grep -q "^create .*-preflight .* img-$f0 infinity" "$SWE_FX/docker.log" || fail "a preflight on another image was taken: $o $(grep '^create ' "$SWE_FX/docker.log")"
  o=$(loop bench swe arms check --settings "$(jq -c '.cpus = 0.25' <<<"$set")" stub-a 2>&1) && [ "$(grep '^create ' "$SWE_FX/docker.log" | tail -n 1 | grep -o -- '--cpus [^ ]*')" = '--cpus 0.25' ] \
    || fail "the check's container did not get its CPU limit: $o $(grep '^create ' "$SWE_FX/docker.log" | tail -n 1)"
  # Bug: Start took that check, passed on other limits.
  : > "$SWE_FX/docker.log"; o=$(loop bench swe 1 --arm stub-a --settings "$set" 2>&1) && grep -q "^1/1 $f1: resolved (reused)$" <<<"$o" \
    || fail "the result of the same settings was not reused: $o"
  grep -q '^create .*-preflight .*--cpus 0\.5 ' "$SWE_FX/docker.log" || fail "a preflight on other limits was taken: $(grep '^create ' "$SWE_FX/docker.log")"
  o=$(loop bench swe 1 --arm stub-a --settings "$(jq -c '.cpus = 1' <<<"$set")" 2>&1) && grep -q "^1/1 $f1: resolved$" <<<"$o" || fail "a run on another CPU limit returned the former result: $o"
  # A limit past this machine is refused before anything starts.
  o=$(loop bench swe 1 --arm stub-a --settings '{"memory": "9999999g"}' 2>&1); [ $? = 2 ] && grep -q 'memory is at most the .* this machine holds' <<<"$o" \
    || fail "memory past this machine's was not refused: $o"
}

# Bug (#638): a conveyor arm's results were kept under its engine commit alone, so a run after the builder's model
# changed returned the result built on the former model.
t_swereuse() {
  swe; local o first; first=$(sweorder | head -n 1)
  o=$(loop bench swe 1 2>&1) && o=$(loop bench swe 1 2>&1) && grep -q "^1/1 $first: resolved (reused)$" <<<"$o" || fail "the unchanged arm's result was not reused: $o"
  # Bug (#640): a run that reused every result printed its receipt, so the Board's Start answered the receipt and not
  # the result. It prints none: Start waits for its end and answers its result.
  ! grep -q '^conveyor: run .* started$' <<<"$o" && grep -q '^Resolved 1 of 1 with ' <<<"$o" || fail "the run of reused results printed a receipt, or no result: $o"
  # Bug (#642): that answer named no run, so the Board's Start could not open the results of a run that had ended.
  [ "$(tail -n 1 <<<"$o")" = "conveyor: run $(tail -n 1 "$B/runs.jsonl" | jq -r 'select(.state == "done") | .id') ended" ] || fail "the run of reused results did not end by naming its recorded run: $o"
  jq -c '.model.effort = "high"' "$ST/control.json" > "$ST/c.new" && mv "$ST/c.new" "$ST/control.json"
  o=$(loop bench swe 1 2>&1) && grep -q "^1/1 $first: resolved$" <<<"$o" || fail "a run on another builder effort returned the former result: $o"
}

# Bug (#638): a conveyor arm's sandbox read the project's control record and rules again at each task, so a change
# made while a run went gave its later tasks other seats and rules than its first, kept under the run's inputs.
t_swefrozen() {
  swe; local o p second; second=$(sweorder | tail -n 1)
  jq '.rules = "project" | .label = "Conveyor, project rules"' "$SWE_FX/arms/conveyor.json" > "$SWE_FX/arms/conveyor-rules.json" && echo 'Rule A.' > "$R/.conveyor/card-rules.md" \
    && jq -c '.model.effort = "high"' "$ST/control.json" > "$ST/c.new" && mv "$ST/c.new" "$ST/control.json" || fail "the arm, its rules or the record were not made"
  # Its preflight passed, as swe() keeps the conveyor arm's.
  mkdir -p "$B/preflight/conveyor-rules" && jq -c --arg k "conveyor-rules-$EA" '.arm = "conveyor-rules" | .key = $k | .spec = $s[0]' --slurpfile s <(jq -cS '.name = "conveyor-rules"' "$SWE_FX/arms/conveyor-rules.json") \
    "$B/preflight/conveyor/$EA.json" > "$B/preflight/conveyor-rules/conveyor-rules-$EA.json" || fail "the preflight pass was not kept"
  : > "$SWE_FX/hold"; rm -f "$SWE_FX/pid"
  loop bench swe 2 --arm conveyor-rules --engine v1.0.0 > "$T/$CASE/run.out" 2>&1 & p=$!
  wait_until "[ -s '$SWE_FX/pid' ]" || fail "the first task's build did not start"
  # The reviewer moves from Codex to Claude too.
  jq -c '.model.effort = "low" | .reviewer = {cli: "claude", model: "m"}' "$ST/control.json" > "$ST/c.new" && mv "$ST/c.new" "$ST/control.json" && echo 'Rule B.' > "$R/.conveyor/card-rules.md" && rm -f "$SWE_FX/hold"
  wait "$p" && grep -q "^2/2 $second: resolved$" "$T/$CASE/run.out" || fail "the run failed: $(cat "$T/$CASE/run.out")"
  # The second task's sandbox is the last the fake engine noted.
  [ "$(jq -r .model.effort "$SWE_FX/control.seen")" = high ] && grep -q 'Rule A' "$SWE_FX/rules.seen" && ! grep -q 'Rule B' "$SWE_FX/rules.seen" \
    || fail "the second task built on the record or rules changed while the run went: $(jq -c .model "$SWE_FX/control.seen") $(cat "$SWE_FX/rules.seen")"
  # Bug (#638): the container's logins followed the project's seats now, so the second task's frozen Codex reviewer
  # ran in a container with no Codex login.
  [ "$(jq -r .reviewer.model "$SWE_FX/control.seen")" = x ] && [ "$(cat "$SWE_FX/codex.seen" 2>/dev/null)" = CODEX-LOGIN ] \
    || fail "the second task's Codex reviewer had no Codex login: $(jq -c .reviewer "$SWE_FX/control.seen") $(cat "$SWE_FX/codex.seen" 2>&1)"
}

# Bug (#638): Compare read an arm's results under the key of swe.json's settings and the project's seats now, so it
# lost the results kept under an arm's name before inputs were recorded, and those of a run on other settings.
t_swediffkeys() {
  swe; local o
  mkdir -p "$B/results/stub-a" "$B/results/stub-b-0123456789ab" \
    && jq -nc '{task: "proj__a-1", arm: "stub-a", label: "Stub a", key: "stub-a", resolved: true, fired: true, sessions: 1, tokens: 7, minutes: 1, steps: [], at: "2026-11-01T00:00:00Z",
      cost: {usd: 0.5, state: "known", unpriced: 0}}' > "$B/results/stub-a/proj__a-1.json" \
    && jq -nc '{task: "proj__a-1", arm: "stub-b", label: "Stub b", key: "stub-b-0123456789ab", resolved: true, fired: true, sessions: 1, tokens: 3, minutes: 1, steps: [],
      at: "2026-11-02T00:00:00Z", inputs: {limits: {cpus: 1, memory: "8g", taskTimeout: 14400}}}' > "$B/results/stub-b-0123456789ab/proj__a-1.json" || fail "the results were not made"
  o=$(loop bench swe diff stub-a stub-b --json 2>&1) && [ "$(jq -c '[.tasks, .same, .a.totals.tokens, .b.totals.tokens]' <<<"$o")" = '[1,["proj__a-1"],7,3]' ] \
    || fail "Compare did not read the arms' kept results: $o"
  # Bug (#646): Compare's totals had no cost, so the Board could not tell a recorded cost from one never kept. A
  # result kept before costs were (stub-b's) is unknown, not $0.
  [ "$(jq -c '[.a.totals.cost, .b.totals.cost]' <<<"$o")" = '[{"usd":0.5,"state":"known"},{"usd":null,"state":"unknown"}]' ] \
    || fail "Compare's totals did not tell a recorded cost from an unknown one: $o"
}

# Bug (#638): a conveyor arm on the project's rules kept its results under its engine commit alone, so a run after the
# card rules changed returned the result built on the former rules.
t_swerulesreuse() {
  swe; local o
  jq '.rules = "project" | .label = "Conveyor, project rules"' "$SWE_FX/arms/conveyor.json" > "$SWE_FX/arms/conveyor-rules.json" && echo 'Rule A.' > "$R/.conveyor/card-rules.md" \
    || fail "the arm or its rules were not made"
  o=$(loop bench swe 1 --arm conveyor-rules 2>&1) && grep -q "Rule A" "$SWE_FX/rules.seen" || fail "the run on rules A failed: $o $(cat "$SWE_FX/rules.seen" 2>&1)"
  echo 'Rule B.' > "$R/.conveyor/card-rules.md"
  o=$(loop bench swe 1 --arm conveyor-rules 2>&1) && grep -q ": resolved$" <<<"$o" && grep -q "Rule B" "$SWE_FX/rules.seen" \
    || fail "a run on other card rules returned the former result: $o"
}

# bench/swe.sh's functions called directly, in place of a held run: on the swe fixture's bench folder ($B) or the
# case's own, with the pack's list prices for bench-m (packget) and no Board copy (swe_board needs the engine's settings).
swefn() { # <shell code> [<argument>...]
  (export HERE=$SRC RTAG=x ST=$T/$CASE/state; . "$SRC/bench/swe.sh" || exit 9; SWE_DIR=${B:-$T/$CASE/bench}; mkdir -p "$SWE_DIR" || exit 9
    packget() { printf -v "$2" '%s' '{"bench-m": {"input": 1, "output": 2, "cacheRead": 0.5}}'; }; swe_board() { :; }
    local c=$1; shift; eval "$c")
}
# In swefn: a run going (its process this shell's) with the conveyor arm on two tasks, its read revision 5, the
# active work given and the tasks it did; the task list is written unless the fixture has one.
sweliveseed() { # <run id> <active json> [<tasks json>]
  local f; f=$(swe_list "$(swe_conf .revision)" "$(swe_conf .seed)")
  [ -e "$f" ] || printf '%s\n' '{"id":"proj__a-1"}' '{"id":"proj__b-2"}' > "$f" || return 1
  jq -nc --arg id "$1" --argjson a "$2" --argjson t "${3:-[]}" --argjson p "$$" '{id: $id, arm: "conveyor", arms: ["conveyor"], cols: [{arm: "conveyor", key: "k"}],
    n: 2, started: "2026-11-01T00:00:00Z", state: "running", pid: $p, seq: 5, tasks: $t, done: 0, resolved: 0, active: $a}' > "$SWE_DIR/live.json"
}

# Bugs (#643): (1) a task in progress showed no arm or step until its result was kept; (2) a step that changed with
# nothing else left the read revision the same, so the Board did not refresh; (3) the run page listed only the tasks
# with a result, never the ones still waiting; (4) the run kept no log of its events once it ended, and the step text
# shown could be any word a container wrote in its card's records; (6, #646) an arm's active time had no start for
# its task in progress and no minutes for a task that ran.
t_swelive() {
  local o u='Running Conveyor. Step unavailable.' b r j1 j2
  # (4, 5) The step a conveyor arm's card is at, from its card lines and live records (a live record has no card): its
  # last start line's step; the judge's live record (judgecall()) is the review step's, so the run said Reviewing
  # while the judge read the findings, but a judge's record older than the review's start line is an earlier pass's;
  # an engine that writes no start line, or a start line of no known step, shows no step, never the container's word.
  b='{"card":"c1","issue":1,"step":"start","result":"ok","of":"build"}'
  # The older judge record comes after the start line, as swe_watch puts the live records after the card lines: its
  # time, not its place, says it is an earlier pass's.
  r=$b$'\n{"card":"c1","issue":1,"step":"start","result":"ok","of":"review","time":"2026-01-01T00:00:02Z"}\n{"step":"review","at":"2026-01-01T00:00:01Z","action":"the judge reads the findings"}'
  j1=$r$'\n{"step":"review","at":"2026-01-01T00:00:03Z","action":"the judge reads the findings"}'
  j2=$j1$'\n{"card":"c1","issue":1,"step":"start","result":"ok","of":"sk-SECRET"}'
  o=$(swefn 'for x in "$@"; do printf "%s\n" "$x" | swe_stepof; done' '{"card":"c1","issue":1,"step":"build","result":"ok"}' "$b" "$r" "$j1" "$j2" 2>&1)
  [ "$o" = "$u"$'\nBuilding\nReviewing\nJudging\n'"$u" ] || fail "the step shown is not the card's start line's, Judging only for a judge newer than the review's start, or no step for an unknown one: $o"
  # (1, 2, 3, 6) The active work names its arm and task before any result; each phase change advances the read
  # revision (seq), with start, the time its work on the task began, and its cost so far kept; the run page shows the
  # active task at its phase and the one not reached as waiting; each phase is an event of the run's tail, with its
  # fields only.
  o=$(swefn 'sweliveseed r20261101T000000-1 "{\"arm\": \"conveyor\", \"task\": \"proj__a-1\", \"phase\": \"Setting up\", \"start\": \"2026-01-01T00:00:00Z\", \"cost\": {\"usd\": 1, \"state\": \"known\", \"unpriced\": 0}}" \
    && export SWE_RUN=r20261101T000000-1 SWE_ARM=conveyor SWE_TASK=proj__a-1 && swe_phase Building && jq -c "[.seq, .active]" "$SWE_DIR/live.json" \
    && swe_phase Reviewing && jq -c "[.seq, .active]" "$SWE_DIR/live.json" && swe_show r20261101T000000-1 && cat "$SWE_DIR/tails/r20261101T000000-1.jsonl"' 2>&1)
  jq -se '.[0] as $b | .[1] as $r | $b[0] == 6 and $r[0] == 7 and ([$b[1], $r[1]] | all(.arm == "conveyor" and .task == "proj__a-1" and .start == "2026-01-01T00:00:00Z"
      and .cost == {usd: 1, state: "known", unpriced: 0})) and $b[1].phase == "Building" and $r[1].phase == "Reviewing"' <<<"$o" > /dev/null \
    || fail "a phase change did not advance the read revision, or lost the active work's arm, task, start or cost: $o"
  jq -se '.[2] | .run.seq == 7 and .run.active.start == "2026-01-01T00:00:00Z"
      and [.tasks[] | [.id, .cells[0].state, .cells[0].phase]] == [["proj__a-1", "active", "Reviewing"], ["proj__b-2", "waiting", null]]' <<<"$o" > /dev/null \
    || fail "the run page does not show the active task at its phase and the waiting one, or its read revision and start: $o"
  jq -se '.[3:] | map(.event) == ["Building", "Reviewing"] and all(keys == ["arm", "at", "event", "task"] and .arm == "conveyor" and .task == "proj__a-1")' <<<"$o" > /dev/null \
    || fail "the tail does not hold each phase as an event with its fields only: $o"
  # (4, 6) After a whole run: its tail survives its cleanup, with each task's events, the preflight's and the run's
  # end, and each task the arm ran keeps the wall minutes of its work, which the arm's wall sums for its active time.
  # The run is the swe fixture's fake engine, not held: only a run shows what swe_run writes as it goes and ends.
  local id first; swe; first=$(sweorder | head -n 1)
  o=$(loop bench swe 2 2>&1) || fail "the run failed: $o"
  id=$(tail -n 1 "$B/runs.jsonl" | jq -r .id)
  [ ! -e "$B/work" ] && [ -s "$B/tails/$id.jsonl" ] || fail "the run's tail did not survive its cleanup: $(ls "$B" 2>&1)"
  jq -se 'all(keys == ["arm", "at", "event", "task"])' "$B/tails/$id.jsonl" > /dev/null || fail "the tail holds other fields: $(cat "$B/tails/$id.jsonl")"
  o=$(loop bench swe show "$id" 2>&1) && jq -e --arg f "$first" '[.tail[] | select(.arm == "conveyor" and .task == $f) | .event] as $e
    | all("Preparing image", "Setting up", "Reading patch"; IN($e[])) and ($e[-1] | IN("Resolved", "Unresolved"))
    and any(.tail[]; . == (. | {at} + {arm: "conveyor", task: null, event: "Checking"}))
    and .tail[-1] == (.tail[-1] | {at} + {arm: null, task: null, event: "Run done"}) and all(.tasks[].cells[]; .state == "finished")' <<<"$o" > /dev/null \
    || fail "show does not give the run's events after it ended: $o"
  tail -n 1 "$B/runs.jsonl" | jq -e '(.tasks | length) == 2 and all(.tasks[]; (.minutes | type) == "number")' > /dev/null \
    && jq -e '(.run.cols[0].wall | type) == "number"' <<<"$o" > /dev/null || fail "a task's or the arm's wall minutes are not kept: $(tail -n 1 "$B/runs.jsonl") $(jq -c .run.cols <<<"$o")"
}

# Bugs (#644): a benchmark run kept no cost, so the Board could show none. (1) A session's known token usage gave no
# list price (the pack's prices over the Board's table); (2) a task with only part of its usage priced read as whole,
# and one with none as $0; (3) a step's final line was added to what its live record had said, not put in its place;
# (4) a reused result added its cost again; (5) the cost of the task Stop interrupted was lost; (6) a run or result
# kept before costs were read as $0, as did an old run stopped on its first task; (8) a failed session's usage (its
# blocked line's spent) was not priced, the reviewer's charge was dropped while its judge ran, a review run again
# lost its first attempt's charge (or priced it twice in the pause), and a loop ended mid-session (the task's time
# limit) kept a cost from the card's lines alone, dropping what its live records said; (9) a session run again after
# it stalled read as whole, its first try left out. This case checks (1), (2), (3) and (9) on swe_cost and swe_sofar,
# and one run for the figure a task's result and its run line keep, with (8)'s loop ended mid-review; the swecost
# cases after it check the others: Stop and the retry with no run (swe_end, swe_cost), the solo case one run, and the
# old-costs case none (it seeds old lines).
t_swecost() {
  local o a b one='{"input":1000000}' first p s
  # (1) The running build's live record, 1M input: $1. (3) The build's line (2M input: $2) replaces its live record;
  # the review (1M cache reads: $0.50) and its judge (1M output: $2) are priced; (2) the fix running has reported no
  # usage yet (zero), so it is unpriced, not $0. (9) The fix stalled and runs again (its live record names the stall),
  # 1M input so far ($1): its first try, which no record the container shows holds, is unpriced, not left out.
  a='{"card":"c1","issue":1,"step":"start","result":"ok","of":"build"}'
  b=$a$'\n{"card":"c1","issue":1,"step":"build","result":"ok","model":"bench-m","usage":{"input":2000000}}'
  b=$b$'\n{"card":"c1","issue":1,"step":"review","result":"GO","model":"bench-m","usage":{"read":1000000},"judge":{"model":"bench-m","usage":{"output":1000000}}}'
  b=$b$'\n{"card":"c1","issue":1,"step":"start","result":"ok","of":"fix"}'
  o=$(swefn 'for x in "$@"; do printf "%s\n" "$x" | swe_cost; done' "$a"$'\n{"step":"build","model":"bench-m","usage":'"$one}" \
    "$b"$'\n{"step":"fix","model":"bench-m","zero":true,"usage":{"input":0}}' "$b"$'\n{"step":"fix","model":"bench-m","stalled":"2026-11-01T00:00:00Z","usage":'"$one}" 2>&1)
  jq -se 'map({usd, state, unpriced}) == [{usd: 1, state: "known", unpriced: 0}, {usd: 4.5, state: "partial", unpriced: 1}, {usd: 5.5, state: "partial", unpriced: 1}]
      and all(.basis == {"bench-m": {input: 1, output: 2, cacheRead: 0.5, cacheWrite: 1.25}})' <<<"$o" > /dev/null \
    || fail "a running session gave no list price, a step's line did not replace its live figure, or an unpriced or stalled session read as whole: $o"
  # The cost so far is the active work's (written only when it changed), and the run page's cost counts it while the run goes.
  o=$(swefn 'sweliveseed r20261101T000000-1 "{\"arm\": \"conveyor\", \"task\": \"proj__a-1\", \"phase\": \"Fixing\", \"start\": \"2026-01-01T00:00:00Z\"}" \
    && k=$(printf "%s\n" "$1" | swe_cost) && swe_sofar "$k" && jq -c "[.seq, .active.cost]" "$SWE_DIR/live.json" && swe_sofar "$k" && jq -c .seq "$SWE_DIR/live.json" \
    && swe_show r20261101T000000-1 | jq -c "[.run.cost, .run.cols[0].cost]"' "$b"$'\n{"step":"fix","model":"bench-m","zero":true,"usage":{"input":0}}' 2>&1)
  [ "$o" = $'[6,{"usd":4.5,"state":"partial","unpriced":1}]\n6\n[{"usd":4.5,"state":"partial"},{"usd":4.5,"state":"partial"}]' ] \
    || fail "the active work's cost so far was not kept, was written again unchanged, or the run page gives none while the run goes: $o"
  # The figure a task's result keeps, and its run line's (swe_trial), with its price basis and the usage of its steps
  # and judge; (8) a loop ended mid-session (the task's time limit) keeps what its live records said too. Only a run
  # shows what the trial copies out of its container and keeps. The fake engine waits at hold (its pid written first);
  # the case then writes the card's lines (the build and review above, and the next review's start line) and the
  # records that review left: it ran again, so its first attempt's usage (1M input: $1) is on its .firsttry, and its
  # second attempt has written its events; its judge's live record (no usage yet, unpriced); and the second attempt's
  # last record (1M input: $1), as swe_watch keeps it in <sb>.h/reviewer. The issue closed, the fake engine ends with
  # no line of its own. A final read that dropped the first attempt (or the live records) keeps less than $6.50.
  swe; first=$(sweorder | head -n 1); tune '.prices = {"bench-m": {input: 1, output: 2, cacheRead: 0.5}}'
  : > "$SWE_FX/hold"; rm -f "$SWE_FX/pid"
  loop bench swe 1 > "$T/$CASE/run.out" 2>&1 & p=$! # loop: only a run copies the trial's records out of its container and keeps its cost
  # A poll on the run: the fake engine's pid file says the sandbox's state folder is there for the card's lines.
  wait_until "[ -s '$SWE_FX/pid' ]" || fail "the first task's engine did not start: $(cat "$T/$CASE/run.out")"
  s='{"card":"c1","issue":1,"step":"start","result":"ok","of":"review","time":"2026-11-01T00:00:00Z"}'
  printf '%s\n' "$b" "$s" | grep -v '"of":"fix"' >> "$(echo "$B/work/$first"/swe-*/conveyor/state)/cards.jsonl" && mkdir -p "$B/work/$first/cards" \
    && echo '{"step":"review","at":"2026-11-01T00:00:04Z","model":"bench-m","action":"the judge reads the findings","turns":0}' > "$B/work/$first/cards/c1.live" \
    && echo '{"reason":"the review ended without one clear verdict","spent":{"model":"bench-m","usage":{"input":1000000}}}' > "$B/work/$first/cards/c1.firsttry" \
    && echo '{"type":"event"}' > "$B/work/$first/cards/c1.events" \
    && jq -nc --argjson s "$s" '{reviewer: {of: $s, live: {step: "review", at: "2026-11-01T00:00:03Z", model: "bench-m", usage: {input: 1000000}}, second: true}}' > "$B/work/$first.h/reviewer" \
    && : > "$B/work/$first/closed" || fail "the card's lines and records were not written"
  rm -f "$SWE_FX/hold"; wait "$p" || fail "the run failed: $(cat "$T/$CASE/run.out")"
  jq -e '.cost == {usd: 6.5, state: "partial", unpriced: 1, basis: {"bench-m": {input: 1, output: 2, cacheRead: 0.5, cacheWrite: 1.25}}}
      and (.steps | map(select(.usage)) | length) == 2 and .steps[1].judge == {model: "bench-m", usage: {output: 1000000}}' "$B"/results/*/"$first.json" > /dev/null \
    && [ "$(tail -n 1 "$B/runs.jsonl" | jq -c '.tasks[0].cost')" = '{"usd":6.5,"state":"partial","unpriced":1}' ] \
    || fail "the task's result or run line keeps no cost with its price basis, not the usage it was priced from, or drops what the live records of a loop ended mid-review said (its first attempt, its judge):$(cat "$B"/results/*/"$first.json") $(tail -n 1 "$B/runs.jsonl")"
}

# Bug (#644 (4), (5)): a reused result added its cost again, and the cost of the task Stop interrupted was lost.
t_swecoststop() {
  swe; local o id=r20261101T000000-3
  # A run reused the first task, whose kept result has a cost (a run that added a reused task's cost again would
  # show it), and Stop ended it on the second, whose build had used 3M input tokens ($3 so far): its end (swe_end, as
  # Stop runs it) keeps that work as interrupted, with its cost, on the run's line in runs.jsonl.
  o=$(swefn 'sweliveseed "$1" "{\"arm\": \"conveyor\", \"task\": \"proj__b-2\", \"phase\": \"Building\", \"start\": \"2026-01-01T00:00:00Z\", \"cost\": {\"usd\": 3, \"state\": \"known\", \"unpriced\": 0}}" \
    "[{\"id\": \"proj__a-1\", \"arm\": \"conveyor\", \"result\": \"resolved\", \"reused\": true, \"cost\": {\"usd\": 4.5, \"state\": \"partial\", \"unpriced\": 2}}]" \
    && SWE_RUN=$1 && swe_end stopped' "$id" 2>&1) || fail "the run's end failed: $o"
  o=$(loop bench swe history 2>&1) && jq -e --arg id "$id" '.runs[] | select(.id == $id) | [.cost, .interrupted.cost] == [{usd: 3, state: "known"}, {usd: 3, state: "known", unpriced: 0}]' <<<"$o" > /dev/null \
    || fail "the stopped run lost its interrupted task's cost, or added the reused task's again: $(jq -c --arg id "$id" '.runs[] | select(.id == $id)' <<<"$o" 2>&1 || echo "$o")"
}

# Bug (#644 (8)): a failed session's usage was not priced, the reviewer's charge was dropped while its judge ran, a
# review run again lost its first attempt's charge (or priced it twice in the pause), and a loop ended mid-session
# kept a cost from the card's lines alone.
t_swecostretry() {
  local o c f r1 r2 j s='{"card":"c1","issue":1,"step":"start","result":"ok","of":"review","time":"2026-11-01T00:00:00Z"}'
  # A first card was blocked on a failed build that used 1M input ($1, on the blocked line's spent). The next card's
  # review ended with no verdict after 1M input ($1, kept in its .firsttry, as SWE_LIVES reads it): in the pause the
  # live record is still that attempt's, so it is not priced again; the second attempt (its events written: second
  # true) used 2M input ($2); then its judge runs, whose live record takes the place of the review's, and the
  # reviewer's last record is the one swe_watch kept. The failed build, both review attempts and the judge (no usage
  # yet, unpriced) all count. The same records give the trial's final figure (swe_trial) when the loop ends on that
  # start line, as the task's time limit ends it, with no review line written: swecost's run checks that figure, both
  # attempts and the judge copied out of the container.
  c='{"card":"c0","issue":1,"step":"blocked","result":"blocked","spent":{"step":"build","model":"bench-m","usage":{"input":1000000}}}'$'\n'$s
  f='"firsttry":{"reason":"the review ended without one clear verdict","spent":{"model":"bench-m","usage":{"input":1000000}}}}'
  r1='{"step":"review","at":"2026-11-01T00:00:01Z","model":"bench-m","action":"reads x.py","usage":{"input":1000000}}'
  r2='{"step":"review","at":"2026-11-01T00:00:03Z","model":"bench-m","action":"reads x.py","usage":{"input":2000000}}'
  j='{"step":"review","at":"2026-11-01T00:00:04Z","model":"bench-m","action":"the judge reads the findings","turns":0}'
  o=$(swefn 'for x in "$@"; do printf "%s\n" "$x" | swe_cost; done' "$c"$'\n{"second":false,'"$f"$'\n'"$r1" \
    "$c"$'\n{"second":true,'"$f"$'\n'"$r2" "$c"$'\n{"second":true,'"$f"$'\n'"$j"$'\n{"reviewer":{"of":'"$s"',"live":'"$r2"',"second":true}}' 2>&1)
  jq -se 'map({usd, state, unpriced}) == [{usd: 2, state: "known", unpriced: 0}, {usd: 4, state: "known", unpriced: 0}, {usd: 4, state: "partial", unpriced: 1}]' <<<"$o" > /dev/null \
    || fail "the failed build or the review's first attempt was not priced (or priced twice in the pause), or the reviewer's charge was dropped while the judge runs: $o"
}

# Bug (#644 (6)): a run and a result kept before costs were read as $0, as did an old run stopped on its first task:
# they are unknown.
t_swecostold() {
  swe; local first o; first=$(sweorder | head -n 1)
  mkdir -p "$B/results/old" && jq -nc --arg t "$first" '{task: $t, arm: "conveyor", key: "old", resolved: true, sessions: 2, tokens: 3, minutes: 1, steps: []}' > "$B/results/old/$first.json" \
    && jq -nc --arg t "$first" '{id: "r20261101T000000-1", arms: ["conveyor"], cols: [{arm: "conveyor", key: "old"}], n: 1, started: "2026-11-01T00:00:00Z", state: "done",
      tasks: [{id: $t, arm: "conveyor", result: "resolved"}]}, {id: "r20261101T000000-2", arms: ["conveyor"], cols: [{arm: "conveyor", key: "old"}], n: 1,
      started: "2026-11-01T00:00:00Z", state: "stopped", tasks: [], interrupted: {arm: "conveyor", task: $t}}' >> "$B/runs.jsonl" || fail "the old runs could not be written"
  o=$(loop bench swe show r20261101T000000-1 2>&1) && [ "$(jq -c '[.run.cost, .run.cols[0].cost, .tasks[0].cells[0].cost]' <<<"$o")" = '[{"usd":null,"state":"unknown"},{"usd":null,"state":"unknown"},null]' ] \
    || fail "a run or result kept before costs does not read as unknown: $o"
  o=$(loop bench swe history 2>&1) && jq -e '.runs[] | select(.id == "r20261101T000000-2") | .cost == {usd: null, state: "unknown"}' <<<"$o" > /dev/null \
    || fail "an old run stopped on its first task reads as a known cost: $(jq -c '.runs[] | select(.id == "r20261101T000000-2")' <<<"$o" 2>&1 || echo "$o")"
}

# Bug (#644 (7)): an agent arm reports no usage by model, and its cost read as $0: it is unknown.
t_swecostsolo() {
  swe; local first o; first=$(sweorder | head -n 1)
  tune '.prices = {"bench-m": {input: 1, output: 2, cacheRead: 0.5}}'
  o=$(loop bench swe 1 --solo 2>&1) || fail "the solo run failed: $o"
  jq -e '.cost == {usd: null, state: "unknown", unpriced: 1, basis: {}}' "$B"/results/solo-*/"$first.json" > /dev/null \
    && tail -n 1 "$B/runs.jsonl" | jq -e '.tasks[0].cost == {usd: null, state: "unknown", unpriced: 1}' > /dev/null \
    || fail "the agent arm's cost is not unknown: $(cat "$B"/results/solo-*/"$first.json" 2>&1) $(tail -n 1 "$B/runs.jsonl")"
}
