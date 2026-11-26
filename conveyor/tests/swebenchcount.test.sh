#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 120
# Engine cases: what a SWE-bench trial and run count (bench/swe.sh, bench/swe_arms.sh): a conveyor arm's sessions from
# its card's lines (swe_cardsum), the prices a trial's cost takes (swe_cost) and the share of the week left after a
# trial (swe_weeks). The fixture is swebench.test.sh's swe(); swefn is swebenchshow.test.sh's.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"

# Bugs (#1454 R147, R148): a trial's sessions counted a judge that never started (judgecall() refused its seat, or the
# findings could not be read: its judge holds failed and no sec) and a reused review (reusable(): no session ran), and
# left out the first attempt of a review that ran twice (its firstTry). Each card holds a build and one review: one
# whose judge never started (2 sessions), one whose judge ran (3), a reused one (1) and one that ran twice (3).
t_swesessions() {
  local o d=$T/$CASE b='{"card":"c1","issue":1,"step":"build","result":"ok"}' r='{"card":"c1","issue":1,"step":"review","result":"GO"'
  mkdir -p "$d" && printf '%s\n' "$b" "$r"',"judge":{"model":"j","failed":"the judge seat was refused"}}' > "$d/nojudge.jsonl" \
    && printf '%s\n' "$b" "$r"',"judge":{"model":"j","effort":"low","sec":30}}' > "$d/judge.jsonl" \
    && printf '%s\n' "$b" "$r"',"reused":"2026-11-01T00:00:00Z"}' > "$d/reused.jsonl" \
    && printf '%s\n' "$b" "$r"',"firstTry":{"reason":"the review ended without one clear verdict","spent":{"model":"m"}}}' > "$d/twice.jsonl" \
    || fail "the card lines were not written"
  o=$(swefn 'for f in "$@"; do swe_cardsum 60 "$f" | jq .sessions; done | jq -sc .' "$d/nojudge.jsonl" "$d/judge.jsonl" "$d/reused.jsonl" "$d/twice.jsonl" 2>&1)
  [ "$o" = '[2,3,1,3]' ] || fail "the sessions of a card whose judge never started, whose judge ran, whose review was reused and whose review ran twice are not [2,3,1,3]: $o"
}

# Bug (#1741): a review's judge is on its review line (judge) and on a line of its own (step judge, reviewlines(), lib/card.sh): a
# trial counted its tokens, usage and steps twice. The card holds a build, a review whose judge ran (7 tokens), and the judge's line.
# The steps keep each line's usage (the cost reads it): the build's and the review's own, the judge's only inside its review's judge.
t_swejudgeline() {
  local o d=$T/$CASE b='{"card":"c1","issue":1,"step":"build","result":"ok","tokens":{"claude":10,"codex":0},"model":"b","usage":{"input":10,"output":1}}' j='"judge":{"model":"j","sec":30,"tokens":{"claude":7,"codex":0},"usage":{"input":7,"output":3}}'
  local r='{"card":"c1","issue":1,"step":"review","result":"GO","tokens":{"claude":0,"codex":5},"model":"r","usage":{"input":5,"output":2},'"$j"'}'
  mkdir -p "$d" && printf '%s\n' "$b" "$r" > "$d/line.jsonl" \
    && printf '%s\n' "$b" '{"card":"c1","issue":1,"step":"judge","result":"ok","of":"review","model":"j","sec":30,"tokens":{"claude":7,"codex":0},"usage":{"input":7,"output":3}}' "$r" > "$d/both.jsonl" \
    || fail "the card lines were not written"
  o=$(swefn 'for f in "$@"; do swe_cardsum 60 "$f" | jq -c "[.tokens, .sessions, .steps]"; done | jq -sc "[.[0] == .[1], .[0][:2], (.[0][2] | map([.usage, .judge.usage]))]"' "$d/line.jsonl" "$d/both.jsonl" 2>&1)
  [ "$o" = '[true,[22,3],[[{"input":10,"output":1},null],[{"input":5,"output":2},{"input":7,"output":3}]]]' ] \
    || fail "a card with the judge's line as well as the review's judge field does not count the same tokens, sessions and steps (with their usage) as one without it ([22,3], the build's and the review's own usage, the judge's under the review's judge): $o"
}

# Bug (#1454 R152): a trial's cost took the prices of the project's pack as it is now, not the run's copy of it
# (swe_freeze), so a price changed between two tasks of a run priced the later task at the new rate. The run's copy
# prices bench-m input at $1 a million, the live pack at $5 since; a build of 1M input costs $1. swe_cost is called
# directly with the run's copy in use (SWE_FZ, as swe_use sets it for each task of the run).
t_swecostfrozen() {
  swe; local o fz=$T/$CASE/frozen
  tune '.prices = {"bench-m": {input: 1, output: 2, cacheRead: 0.5}}'
  mkdir -p "$fz/main/.conveyor" && cp "$R/.conveyor/project.json" "$fz/main/.conveyor/project.json" || fail "the run's copy of the pack was not made"
  tune '.prices = {"bench-m": {input: 5, output: 10, cacheRead: 2.5}}'
  o=$(set -- bench; export CONVEYOR_MAIN=$R CONVEYOR_CARDS=$T/$CASE/cards HERE=$SRC; . "$SRC/lib/paths.sh" && . "$SRC/lib/prompts.sh" && . "$SRC/lib/control.sh" \
    && . "$SRC/bench/swe.sh" && export SWE_FZ=$fz && printf '%s\n' '{"card":"c1","issue":1,"step":"build","result":"ok","model":"bench-m","usage":{"input":1000000}}' \
    | swe_cost 2>&1)
  jq -e '.usd == 1 and .basis["bench-m"].input == 1' <<<"$o" > /dev/null || fail "a build of 1M bench-m input, with the run's copy of the pack at \$1 a million and the live pack at \$5, is not priced at the copy's rate: $o"
}

# Bug (#1454 R161): the week left after a trial was read as the guard reads it, asked again only once LIMIT_TTL old,
# so a run that ended within that time of its start kept its start's reading. The reading is 30% at the start and 40%
# once the trial ran, both within LIMIT_TTL (the pack's default, 300 s): the week left goes from 70 to 60.
# loop: only a run reads the week at its start and again after its trial, the reading changed between the two.
t_sweweekfresh() {
  swe; local p
  echo '{"seven_day":{"utilization":30}}' > "$SWE_FX/use.json" && : > "$SWE_FX/hold" && rm -f "$SWE_FX/pid" || fail "the reading or the hold was not set"
  export CONVEYOR_LIMIT_CMD='cat "$SWE_FX/use.json"'
  loop bench swe 1 > "$T/$CASE/run.out" 2>&1 & p=$!
  # A poll on the run: the fake engine's pid file says the trial runs, after the run's start read the week.
  wait_until "[ -s '$SWE_FX/pid' ]" || fail "the task's engine did not start: $(cat "$T/$CASE/run.out")"
  echo '{"seven_day":{"utilization":40}}' > "$SWE_FX/use.json"; rm -f "$SWE_FX/hold"
  wait "$p" || fail "the run failed: $(cat "$T/$CASE/run.out")"
  [ "$(tail -n 1 "$B/runs.jsonl" | jq -c '[.weekStart.conveyor, .weekLeft.conveyor]')" = '[70,60]' ] \
    || fail "the run's week left (reading 30% at its start, 40% after its trial) is not 70 then 60: $(tail -n 1 "$B/runs.jsonl" | jq -c '{weekStart, weekLeft}')"
}

# Bug (#1454 review E4): with a conveyor arm and another arm on the builder's one Claude account, the week left after
# a trial asked that account twice, and two askings can differ: here the first says 30% used, the second 31%, and the
# run kept 70 and 69 for one account, shared false. The conveyor guard's asking is the other arm's reading too.
t_sweweekone() {
  swe; local o
  export CONVEYOR_LIMIT_CMD='n=$(cat "$SWE_FX/n" 2>/dev/null || echo 30); echo $((n + 1)) > "$SWE_FX/n"; echo "{\"seven_day\":{\"utilization\":$n}}"'
  o=$(set -- bench; export CONVEYOR_MAIN=$R CONVEYOR_CARDS=$T/$CASE/cards HERE=$SRC; . "$SRC/lib/paths.sh" && . "$SRC/lib/records.sh" && . "$SRC/lib/prompts.sh" \
    && . "$SRC/lib/control.sh" && tunables && . "$SRC/bench/swe.sh" && swe_weeks 1 1 fresh 2>&1)
  [ "$o" = '{"conveyor":70,"agent":70,"shared":true}' ] \
    || fail "swe_weeks 1 1 fresh, a conveyor and another arm on the builder's account (askings 30%, then 31%), does not give one share left for both: $o"
}

# Bug (#1454 follow-up): with both roles on a proxy the conveyor guard reads no account, and that empty list matched
# the default login's empty name, so the other arm took the kept start reading (30%) in place of asking again (40%).
t_sweweekproxy() {
  swe; local o
  jq -c 'del(.account)' "$ST/control.json" > "$ST/c.new" && mv "$ST/c.new" "$ST/control.json" || fail "the default account was not set"
  tune '.models.claudeProxy = {baseUrl: "http://192.0.2.1:4141", roles: {builder: "proxy", reviewer: "proxy"}}'
  export CONVEYOR_LIMIT_CMD='echo "{\"seven_day\":{\"utilization\":$(cat "$SWE_FX/n" 2>/dev/null || echo 30)}}"'
  o=$(set -- bench; export CONVEYOR_MAIN=$R CONVEYOR_CARDS=$T/$CASE/cards HERE=$SRC; . "$SRC/lib/paths.sh" && . "$SRC/lib/records.sh" && . "$SRC/lib/prompts.sh" \
    && . "$SRC/lib/control.sh" && tunables && . "$SRC/bench/swe.sh" && swe_weeks '' 1 > /dev/null && echo 40 > "$SWE_FX/n" && swe_weeks 1 1 fresh 2>&1)
  [ "$o" = '{"conveyor":null,"agent":60,"shared":false}' ] \
    || fail "swe_weeks 1 1 fresh, both roles on a proxy and the default account (start reading 30%, then 40%), does not give the other arm 60 left: $o"
}
