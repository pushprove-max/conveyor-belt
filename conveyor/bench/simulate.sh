#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Benchmark phase 0, gate 4: the figures of measured review calls, and a simulation of check rules on their noise.
# Input: one JSON line per review call (the repeats of each case, 5 cases 5 times each in phase 0):
#   {case, pass (true when the review gave the case's expected answer), tokens, seconds (wall, the API waits and
#    retries included), sessions (the launches the call took, replay.sh's count), login, shareBefore, shareAfter
#    (that login's usage share as read before and after the call, in percent; null when it was not read)}
# Each case's pass rate is (passes + 1) / (runs + 2): five passes in five runs is not taken for a case that never fails.
# A rule is <name>:<ref>:<stable>:<confirm>: <ref> reference runs of each case on the old engine and one run on the
# new; a case is a flip suspect when its new run fails and either <stable> is 0 and one of its reference runs passed,
# or <stable> is 1 and all of them passed; each suspect is run <confirm> times more on the new engine and the drop is
# confirmed when every one of those runs fails. Each trial draws every run from the cases' rates; the drop trials put
# one more case in the draw whose rate falls from 0.9 to 0.3 on the new engine.
# Usage: simulate.sh <calls.jsonl> <rule> [<rule> ...]   (env BENCH_TRIALS, default 20000; BENCH_SEED, default 1)
# Prints one JSON object: figures (per case: runs, passes, rate, mean tokens and seconds, sessions, and each login's
# mean share per call) and, per rule: power (the drop case confirmed), falseConfirm (any case confirmed with no
# drop), suspects (the mean count with no drop), and sessions and seconds per check (the mean session count and
# seconds of a call, as measured, times the runs the rule makes with no drop, its confirm runs included; the seconds
# are of calls run one after another).
set -euo pipefail
[ $# -ge 2 ] || { echo "usage: simulate.sh <calls.jsonl> <rule> [<rule> ...]" >&2; exit 2; }
IN=$1; shift
for r in "$@"; do [[ $r =~ ^[a-z0-9-]+:[1-9][0-9]*:[01]:[1-9][0-9]*$ ]] || { echo "simulate: $r is no rule <name>:<ref>:<stable>:<confirm>" >&2; exit 2; }; done
FIG=$(jq -sce 'if length == 0 then error("no calls") else . end
  | (map(select((.case | type) == "string" and (.pass | type) == "boolean" and ([.tokens, .seconds, .sessions] | all(type == "number"))))) as $ok
  | if ($ok | length) != length then error("a call lacks case, pass, tokens, seconds or sessions") else . end
  | {cases: (group_by(.case) | map({case: .[0].case, runs: length, passes: (map(select(.pass)) | length),
       tokens: (map(.tokens) | add / length), seconds: (map(.seconds) | add / length), sessions: (map(.sessions) | add / length)})
       | map(. + {rate: ((.passes + 1) / (.runs + 2))})),
     sessionsPerCall: (map(.sessions) | add / length), secondsPerCall: (map(.seconds) | add / length),
     shares: (map(select(.login and (.shareBefore | type) == "number" and (.shareAfter | type) == "number")) | group_by(.login)
       | map({login: .[0].login, calls: length, sharePerCall: (map(.shareAfter - .shareBefore) | add / length)}))}' "$IN") \
  || { echo "simulate: $IN holds no calls, or a call lacks case, pass, tokens, seconds or sessions" >&2; exit 2; }
RULES=$(printf '%s\n' "$@" | awk -F: -v trials="${BENCH_TRIALS:-20000}" -v seed="${BENCH_SEED:-1}" \
  -v rates="$(jq -r '.cases | map(.rate) | join(" ")' <<<"$FIG")" -v sess="$(jq -r .sessionsPerCall <<<"$FIG")" -v secs="$(jq -r .secondsPerCall <<<"$FIG")" '
  BEGIN { srand(seed); n = split(rates, p, " ") }
  # One check: the cases 1..m on the old engine at rate a[i], on the new at b[i]. Sets SUS (suspects) and CON[i].
  function check(m, ref, stable, confirm,   i, j, hit, f) {
    SUS = 0; RUNS = 0; split("", CON)
    for (i = 1; i <= m; i++) {
      hit = 0; for (j = 1; j <= ref; j++) if (rand() < a[i]) hit++
      RUNS += ref + 1
      if (rand() < b[i]) continue
      if (stable ? hit < ref : hit == 0) continue
      SUS++; RUNS += confirm; f = 0
      for (j = 1; j <= confirm; j++) if (rand() >= b[i]) f++
      if (f == confirm) CON[i] = 1
    }
  }
  {
    ref = $2; stable = $3; confirm = $4; pw = 0; fc = 0; ss = 0; rs = 0
    for (t = 1; t <= trials; t++) {
      for (i = 1; i <= n; i++) { a[i] = p[i]; b[i] = p[i] }
      check(n, ref, stable, confirm); ss += SUS; rs += RUNS; for (i in CON) { fc++; break }
      a[n + 1] = 0.9; b[n + 1] = 0.3
      check(n + 1, ref, stable, confirm); if ((n + 1) in CON) pw++
    }
    printf "{\"rule\":\"%s\",\"ref\":%d,\"stable\":%d,\"confirm\":%d,\"power\":%.4f,\"falseConfirm\":%.4f,\"suspects\":%.4f,\"sessions\":%.2f,\"seconds\":%.1f}\n", \
      $1, ref, stable, confirm, pw / trials, fc / trials, ss / trials, rs / trials * sess, rs / trials * secs
  }')
jq -cn --argjson f "$FIG" --argjson t "${BENCH_TRIALS:-20000}" '{figures: $f, trials: $t, rules: [inputs]}' <<<"$RULES"
