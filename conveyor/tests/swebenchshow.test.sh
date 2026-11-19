#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 120
# Engine cases: what the Board's Benchmarks tab reads of `conveyor.sh bench swe` (bench/swe.sh): one run's page
# (`bench swe show`), the cost Start shows (`bench swe history`, each arm's perTask), and the arms the form saves
# (`bench swe arms save`, the choices history offers). The fixture is swebench.test.sh's swe().

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
  # CLI does not take; a command given through the form.
  for o in '{"kind":"conveyor","seats":{"model":{"cli":"codex","model":"x"}}}/does not allow "x" on codex for the builder seat' \
      '{"kind":"agent","recipe":"solo","cli":"claude","model":"x"}/does not allow "x" on claude' \
      '{"kind":"conveyor","seats":{"reviewer":{"cli":"codex","model":"x","effort":"max"}}}/codex takes no effort "max"' \
      '{"kind":"agent","recipe":"solo","cli":"claude","model":"m","run":"true"}/takes kind, recipe, cli and model only, not run'; do
    id2=$(loop bench swe arms save bad "${o%%/*}" 2>&1) && fail "a choice the project does not allow was saved: ${o%%/*}"
    grep -qF "${o#*/}; nothing saved" <<<"$id2" || fail "the refusal does not say why: $id2"
  done
  [ "$(ls "$B/arms" | wc -l)" = 2 ] || fail "a refused arm was kept: $(ls "$B/arms")"
  # An agent arm's recipe runs on the saved model, not on its own (solo's: the builder's, m).
  tune '.models.allowed.claude += ["m2"]'
  id2=$(loop bench swe arms save 'Claude alone on m2' '{"kind":"agent","recipe":"solo","cli":"claude","model":"m2"}' 2>&1) || fail "an agent arm on an allowed model was refused: $id2"
  echo 'echo fixed > x.py' > "$STUB/build"
  o=$(loop bench swe 1 --arm "$id2" 2>&1) || fail "the saved agent arm's run failed: $o"
  [[ $(tail -n 1 "$STUB/sessions") == *'--model m2 '* ]] || fail "the recipe was not given the saved arm's model: $(tail -n 1 "$STUB/sessions")"
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
  jq -e '.model == {cli: "codex", model: "xb"}' "$SWE_FX/control.seen" > /dev/null || fail "the engine was not given the saved arm's builder: $(cat "$SWE_FX/control.seen")"
  [ "$(jq -c .models.allowed "$SWE_FX/pack.seen")" = "$(jq -c .models.allowed "$R/.conveyor/project.json")" ] \
    || fail "the saved arm changed the sandbox's allowed models: $(jq -c .models.allowed "$SWE_FX/pack.seen")"
}
