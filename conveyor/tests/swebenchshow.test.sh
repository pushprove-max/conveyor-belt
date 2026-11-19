#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 120
# Engine cases: what the Board's Benchmarks tab reads of `conveyor.sh bench swe` (bench/swe.sh): one run's page
# (`bench swe show`) and the cost Start shows (`bench swe history`, each arm's perTask). The fixture is swebench.test.sh's swe().

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
