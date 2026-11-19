#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 120
# Engine cases: what the Board's Benchmarks tab reads of `conveyor.sh bench swe` (bench/swe.sh): one run's page
# (`bench swe show`), the cost Start shows (`bench swe history`, each arm's perTask), and the arms the form saves
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
  for i in stub-a/false stub-b/true; do mkdir -p "$B/results/${i%/*}" && jq -nc --arg a "${i%/*}" --argjson r "${i#*/}" \
      '{task: "proj__a-1", arm: $a, key: $a, label: $a, resolved: $r, fired: true, sessions: 1, tokens: 3, minutes: 1, steps: []}' > "$B/results/${i%/*}/proj__a-1.json" || fail "a result could not be written"; done
  # No live.json here (no run in progress): show and history read runs.jsonl alone. The priced file is as
  # dashboard_limit.py cardlines writes it: a header line, then `<hash>\t<the card priced>\t<what it counts>`.
  jq -nc '{id: "r20261117T090000-1", arms: ["a1", "a2", "a3", "a4", "a5", "a6"], cols: [range(1; 7) | {arm: "a\(.)", key: "k\(.)"}], n: 3000,
      started: "2026-11-17T09:00:00Z", state: "done", tasks: [range(500) as $t | range(1; 7) | {id: "proj__task-\(1000 + $t)", arm: "a\(.)", result: "unresolved"}]}' > "$B/runs.jsonl" \
    && jq -nc '{id: "r20261117T100000-2", arms: ["stub-a", "stub-b"], cols: [{arm: "stub-a", key: "stub-a"}, {arm: "stub-b", key: "stub-b"}], n: 2,
      started: "2026-11-17T10:00:00Z", state: "stopped", tasks: [{id: "proj__a-1", arm: "stub-a", result: "unresolved"}]}' >> "$B/runs.jsonl" \
    && { echo "k0 s0"; for i in 2 4 0.5 0; do jq -nc --argjson u "$i" '{card: "c1", steps: [{step: "build", usd: $u, pricedAs: (if $u == 0.5 then "other" else "m" end)}, {step: "review", usd: null}]}' \
      | sed 's/^/h\t/; s/$/\t[]/'; done; } > "$ST/cards.jsonl.priced" || fail "the runs and prices could not be written"
  [ "$(wc -c < "$B/runs.jsonl")" -gt 131072 ] || fail "the big run's line is not past the 128 KiB argument limit, so it proves nothing"
  o=$(loop bench swe show r20261117T090000-1 2>&1) || fail "show cannot open a run of 500 tasks and 6 arms: $(head -c 300 <<<"$o")"
  [ "$(jq -c '[(.tasks | length), (.tasks[0].cells | length), .tasks[499].id]' <<<"$o")" = '[500,6,"proj__task-1499"]' ] \
    || fail "show does not give every task of the big run with its 6 arms: $(head -c 300 <<<"$o")"
  o=$(loop bench swe show r20261117T100000-2 2>&1) || fail "show failed: $o"
  [ "$(jq -c '.tasks[0].cells | map([.arm, .result, .resolved])' <<<"$o")" = '[["stub-a","unresolved",false],["stub-b",null,null]]' ] \
    || fail "the stopped run shows a result for an arm it never ran on the task: $o"
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
  # An agent arm's recipe runs on the saved model, not on its own (solo's: the builder's, m), and on the saved effort
  # (#637: the effort never reached the CLI).
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
    && jq -nc '{task: "proj__a-1", arm: "stub-a", label: "Stub a", key: "stub-a", resolved: true, fired: true, sessions: 1, tokens: 7, minutes: 1, steps: [], at: "2026-11-01T00:00:00Z"}' \
      > "$B/results/stub-a/proj__a-1.json" \
    && jq -nc '{task: "proj__a-1", arm: "stub-b", label: "Stub b", key: "stub-b-0123456789ab", resolved: true, fired: true, sessions: 1, tokens: 3, minutes: 1, steps: [],
      at: "2026-11-02T00:00:00Z", inputs: {limits: {cpus: 1, memory: "8g", taskTimeout: 14400}}}' > "$B/results/stub-b-0123456789ab/proj__a-1.json" || fail "the results were not made"
  o=$(loop bench swe diff stub-a stub-b --json 2>&1) && [ "$(jq -c '[.tasks, .same, .a.totals.tokens, .b.totals.tokens]' <<<"$o")" = '[1,["proj__a-1"],7,3]' ] \
    || fail "Compare did not read the arms' kept results: $o"
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

# Bugs (#643): (1) a task in progress showed no arm or step until its result was kept; (2) a step that changed with
# nothing else left the read revision the same, so the Board did not refresh; (3) the run page listed only the tasks
# with a result, never the ones still waiting; (4) the run kept no log of its events once it ended, and the step text
# shown could be any word a container wrote in its card's records.
t_swelive() {
  swe; local o s c l id p first second u='Running Conveyor. Step unavailable.'; first=$(sweorder | head -n 1); second=$(sweorder | tail -n 1)
  # The fake engine waits at hold; the case writes its card's start lines, as the real loop does at each step.
  : > "$SWE_FX/hold"
  loop bench swe 2 > "$T/$CASE/run.out" 2>&1 & p=$!
  wait_until "jq -e --arg u '$u' --arg f '$first' '.live.active | .phase == \$u and .task == \$f' '$B/board.json' > /dev/null" \
    || fail "the first task's card did not start, or showed a step before its start line: $(cat "$B/live.json" 2>&1)"
  c=$(echo "$B/work/$first"/swe-*/conveyor/state)/cards.jsonl
  echo '{"card":"c1","issue":1,"step":"start","result":"ok","of":"build"}' >> "$c" || fail "the build's start line was not written"
  wait_until "jq -e '.live.active.phase == \"Building\"' '$B/board.json' > /dev/null" || fail "the held card's build step was not shown: $(cat "$B/live.json" 2>&1)"
  [ "$(jq -c '.live.active | [.arm, .task]' "$B/board.json")" = "[\"conveyor\",\"$first\"]" ] && [ -z "$(ls "$B/results" 2>/dev/null)" ] \
    || fail "the active work does not name its arm and task before any result: $(jq -c .live.active "$B/board.json") $(ls -R "$B/results" 2>&1)"
  id=$(jq -r .live.id "$B/board.json"); o=$(loop bench swe show "$id" 2>&1) || fail "show failed while the run goes: $o"
  [ "$(jq -c '[.tasks[] | [.id, .cells[0].state, .cells[0].phase]]' <<<"$o")" = "[[\"$first\",\"active\",\"Building\"],[\"$second\",\"waiting\",null]]" ] \
    || fail "the matrix does not show the active task and the waiting one: $(jq -c .tasks <<<"$o")"
  s=$(jq .live.seq "$B/board.json")
  # (5) the judge's live record (judgecall()) is the review step's, so the run said Reviewing while the judge read the
  # findings. A judge's record older than the review's start line is an earlier pass's: it is not this review's judge.
  l=$(echo "$B/work/$first")/cards/c1.live; mkdir -p "${l%/*}" \
    && echo '{"step":"review","at":"2026-01-01T00:00:01Z","action":"the judge reads the findings"}' > "$l" || fail "the earlier judge's live record was not written"
  echo '{"card":"c1","issue":1,"step":"start","result":"ok","of":"review","time":"2026-01-01T00:00:02Z"}' >> "$c" || fail "the review's start line was not written"
  wait_until "jq -e '.live.active.phase == \"Reviewing\" and .live.seq > $s' '$B/board.json' > /dev/null" \
    || fail "the step change did not advance the read revision: $s $(jq -c '.live | [.seq, .active]' "$B/board.json")"
  o=$(loop bench swe show "$id" 2>&1) && jq -e --argjson s "$s" '.run.seq > $s and .tasks[0].cells[0].phase == "Reviewing"' <<<"$o" > /dev/null \
    || fail "show's read revision did not advance with the step: $s $(jq -c '[.run.seq, .tasks[0].cells[0]]' <<<"$o")"
  echo '{"step":"review","at":"2026-01-01T00:00:03Z","action":"the judge reads the findings"}' > "$l" || fail "the judge's live record was not written"
  wait_until "jq -e '.live.active.phase == \"Judging\"' '$B/board.json' > /dev/null" || fail "the judge reading the findings was not shown: $(jq -c .live.active "$B/board.json")"
  echo '{"card":"c1","issue":1,"step":"start","result":"ok","of":"sk-SECRET"}' >> "$c" || fail "the odd start line was not written"
  wait_until "jq -e --arg u '$u' '.live.active.phase == \$u' '$B/board.json' > /dev/null" || fail "a start line of no known step was not shown as no step: $(jq -c .live.active "$B/board.json")"
  rm -f "$SWE_FX/hold"; wait "$p" || fail "the run failed: $(cat "$T/$CASE/run.out")"
  [ ! -e "$B/work" ] && [ -s "$B/tails/$id.jsonl" ] || fail "the run's tail did not survive its cleanup: $(ls "$B" 2>&1)"
  jq -se 'all(keys == ["arm", "at", "event", "task"])' "$B/tails/$id.jsonl" > /dev/null && ! grep -q SECRET "$B/tails/$id.jsonl" \
    || fail "the tail holds other fields or a container's text: $(cat "$B/tails/$id.jsonl")"
  o=$(loop bench swe show "$id" 2>&1) && jq -e --arg f "$first" --arg u "$u" '[.tail[] | select(.arm == "conveyor" and .task == $f) | .event] as $e
    | all("Preparing image", "Setting up", "Building", "Reviewing", $u, "Reading patch"; IN($e[])) and ($e[-1] | IN("Resolved", "Unresolved"))
    and any(.tail[]; . == (. | {at} + {arm: "conveyor", task: null, event: "Checking"}))
    and .tail[-1] == (.tail[-1] | {at} + {arm: null, task: null, event: "Run done"}) and all(.tasks[].cells[]; .state == "finished")' <<<"$o" > /dev/null \
    || fail "show does not give the run's events after it ended: $o"
}
