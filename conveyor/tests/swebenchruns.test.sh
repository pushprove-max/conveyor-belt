#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 120
# Engine cases: a SWE-bench run archived, restored or deleted (`conveyor.sh bench swe runs archive | restore | delete
# <run>...`, bench/swe.sh's swe_runs), which the Board's Benchmarks pages send. The fixture is swebench.test.sh's swe().
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"

R1=r20261117T090000-1 R2=r20261118T090000-2 R3=r20261119T090000-3
# Three ended runs: R1 made stub-a's results of both tasks (and one task not run); R2, later, reused R1's result of
# proj__a-1; R3 made stub-b's result of proj__a-1. Each run has a tail, and each result its .patch and .log.
swerunsfx() {
  local p a t r
  mkdir -p "$B/tails" && for p in stub-a/proj__a-1/true stub-a/proj__b-2/false stub-b/proj__a-1/true; do IFS=/ read -r a t r <<<"$p"; mkdir -p "$B/results/$a"
      jq -nc --arg a "$a" --arg t "$t" --argjson r "$r" '{task: $t, arm: $a, key: $a, label: $a, resolved: $r, fired: true, sessions: 1, tokens: 1, minutes: 1, steps: []}' > "$B/results/$a/$t.json"
      echo patch > "$B/results/$a/$t.patch"; echo log > "$B/results/$a/$t.log"; done \
    && jq -nc --arg r1 "$R1" --arg r2 "$R2" --arg r3 "$R3" '
      {id: $r1, arms: ["stub-a"], cols: [{arm: "stub-a", key: "stub-a"}], n: 3, started: "2026-11-17T09:00:00Z", state: "done",
        tasks: [{id: "proj__a-1", arm: "stub-a", result: "resolved"}, {id: "proj__b-2", arm: "stub-a", result: "unresolved"}, {id: "proj__c-3", arm: "stub-a", result: "not run: its Docker image could not be fetched or built"}]},
      {id: $r2, arms: ["stub-a"], cols: [{arm: "stub-a", key: "stub-a"}], n: 1, started: "2026-11-18T09:00:00Z", state: "done", tasks: [{id: "proj__a-1", arm: "stub-a", result: "resolved", reused: true}]},
      {id: $r3, arms: ["stub-b"], cols: [{arm: "stub-b", key: "stub-b"}], n: 1, started: "2026-11-19T09:00:00Z", state: "stopped", tasks: [{id: "proj__a-1", arm: "stub-b", result: "resolved"}]}' > "$B/runs.jsonl" \
    && for p in "$R1" "$R2" "$R3"; do echo '{"at":"2026-11-17T09:00:00Z","arm":null,"task":null,"event":"Run started"}' > "$B/tails/$p.jsonl"; done \
    && tail -n 1 "$B/runs.jsonl" > "$B/live.json" || fail "the runs and results could not be written"
}

# Bug (#1053): a failed, refused or test run stayed in the Benchmarks lists, Compare and the infographic for good. An
# archived run is marked archived in history and show (the Board leaves it out of those), keeps its line, tail and
# results, and restore takes the mark off; the other runs' lines stay as they were.
t_swerunsarchive() {
  swe; swerunsfx; local o r2
  r2=$(sed -n 2p "$B/runs.jsonl")
  o=$(loop bench swe runs archive "$R1" "$R3" 2>&1) && [ "$o" = "conveyor: archived $R1, $R3." ] || fail "archive failed or did not say what it did: $o"
  o=$(loop bench swe history 2>&1) && [ "$(jq -c '.runs | map([.id, (.archived | type)])' <<<"$o")" = "[[\"$R3\",\"string\"],[\"$R2\",\"null\"],[\"$R1\",\"string\"]]" ] \
    || fail "history does not mark the archived runs alone: $(jq -c '.runs | map([.id, .archived])' <<<"$o" 2>&1)"
  o=$(loop bench swe show "$R1" 2>&1) && jq -e '(.run.archived | type) == "string" and .tasks[0].cells[0].resolved == true and (.tail | length) == 1' <<<"$o" > /dev/null \
    || fail "an archived run's page lost its mark, its results or its tail: $o"
  [ "$(sed -n 2p "$B/runs.jsonl")" = "$r2" ] && [ "$(ls "$B/results/stub-a" | wc -l)" = 6 ] || fail "archive changed another run's line or a result"
  o=$(loop bench swe runs restore "$R1" 2>&1) && [ "$o" = "conveyor: restored $R1." ] || fail "restore failed: $o"
  [ "$(jq -sc 'map([.id, (.archived | type)])' "$B/runs.jsonl")" = "[[\"$R1\",\"null\"],[\"$R2\",\"null\"],[\"$R3\",\"string\"]]" ] \
    || fail "restore did not take the mark off that run alone: $(cat "$B/runs.jsonl")"
}

# Bug (#1053): a run could not be deleted. Delete of two runs at once removes both lines, their tails and the
# results they made, but not R1's result that R2 reused: R2 still shows it, history tells the Board's confirm so
# before (shared), and delete says it stays. live.json of a deleted run goes, so Stop no longer names it.
t_swerunsdelete() {
  swe; swerunsfx; local o
  o=$(loop bench swe history 2>&1) && [ "$(jq -c '.runs | map([.id, .shared])' <<<"$o")" = "[[\"$R3\",{}],[\"$R2\",{\"stub-a/proj__a-1\":[\"$R1\"]}],[\"$R1\",{\"stub-a/proj__a-1\":[\"$R2\"]}]]" ] \
    || fail "history does not name, for each run's results, the other runs that show them: $(jq -c '.runs | map([.id, .shared])' <<<"$o" 2>&1)"
  o=$(loop bench swe runs delete "$R1" "$R3" 2>&1) && [ "$o" = "conveyor: deleted $R1, $R3; 1 result stays: another run shows it." ] || fail "delete failed or did not say a result stays: $o"
  [ "$(jq -sc 'map(.id)' "$B/runs.jsonl")" = "[\"$R2\"]" ] || fail "delete did not remove both runs' lines alone: $(cat "$B/runs.jsonl")"
  [ "$(ls "$B/tails")" = "$R2.jsonl" ] || fail "delete did not remove both runs' tails alone: $(ls "$B/tails")"
  [ "$(cd "$B/results" && find . -type f | sort | tr '\n' ' ')" = './stub-a/proj__a-1.json ./stub-a/proj__a-1.log ./stub-a/proj__a-1.patch ' ] \
    || fail "delete left a result the runs made, or removed the one R2 reused: $(cd "$B/results" && find . | sort | tr '\n' ' ')"
  [ ! -e "$B/live.json" ] && [ "$(jq -c .live "$B/board.json")" = null ] || fail "the deleted run's live.json, or the Board's copy of it, stayed"
  o=$(loop bench swe show "$R2" 2>&1) && jq -e '.tasks[0].cells[0] | .reused and .resolved == true' <<<"$o" > /dev/null || fail "the run that reused the kept result no longer shows it: $o"
  o=$(loop bench swe runs delete "$R1" 2>&1) && fail "a run deleted already was deleted again: $o"
  [ "$o" = "conveyor: no SWE-bench run $R1" ] || fail "delete of a run that is not there did not say so: $o"
  # The last run that shows the result R1 made: its delete removes it, though R2 only reused it.
  o=$(loop bench swe runs delete "$R2" 2>&1) && [ "$o" = "conveyor: deleted $R2." ] || fail "delete of the last run failed: $o"
  [ -z "$(find "$B/results" -type f)" ] || fail "the result R2 reused stayed after every run that showed it was deleted: $(find "$B/results" -type f)"
}

# Bug (#1053): a run that has written its end in live.json (swe_end) and waits on runs.lock to append its line was in
# neither file delete read, so delete removed the result it reused. Here R2 is at that point: live.json's ended line.
t_swerunsdeleteending() {
  swe; swerunsfx; local o
  sed -n 2p "$B/runs.jsonl" > "$B/live.json" && sed -i 2d "$B/runs.jsonl" || fail "R2 was not put at its end"
  o=$(loop bench swe runs delete "$R1" 2>&1) && [ "$o" = "conveyor: deleted $R1; 1 result stays: another run shows it." ] || fail "delete failed or did not keep R2's result: $o"
  [ -e "$B/results/stub-a/proj__a-1.json" ] && [ ! -e "$B/results/stub-a/proj__b-2.json" ] || fail "delete removed the result R2 reused, or kept R1's own: $(find "$B/results" -type f)"
}

# Bug (#1053): a run found a kept result to reuse, a delete then removed it, and the run recorded it as reused. The
# reuse (swe_reuse) takes runs.lock, which a delete holds: here the lock is held, the result removed, then let go.
# The sleep gives a reuse that does not wait on the lock the time to record the result: no direct check shows a
# process waiting on a lock.
t_swerunsreuselock() {
  swe; swerunsfx; local o f s
  o=$(export HERE=$SRC RTAG=x; . "$SRC/bench/swe.sh" && export SWE_DIR=$B SWE_KEY=stub-a SWE_ARM=stub-a SWE_INPUTS='{"i":1}'
    jq -c '.inputs = {i: 1}' "$B/results/stub-a/proj__a-1.json" > "$B/r.new" && mv "$B/r.new" "$B/results/stub-a/proj__a-1.json" \
      && jq -c '.state = "running" | .tasks = [] | .done = 0 | .resolved = 0' "$B/live.json" > "$B/l.new" && mv "$B/l.new" "$B/live.json" || exit 9
    exec {f}>>"$B/runs.lock"; flock "$f"
    # The reuse's shell closes its copy of the lock: with it open, the lock stays held and the reuse fails on its
    # 60 s wait, as it would with no result. The time check tells the two apart.
    (exec {f}>&-; swe_reuse proj__a-1; echo "rc=$?") > "$B/reuse.out" 2>&1 &
    s=$SECONDS; sleep 1; rm -f "$B/results/stub-a/proj__a-1.json"; exec {f}>&-; wait; cat "$B/reuse.out"; jq -c '.tasks' "$B/live.json"; [ $((SECONDS - s)) -lt 30 ] || echo "waited out the lock") # sleep: no direct check shows a process waiting on a lock
  [ "$o" = $'rc=1\n[]' ] || fail "a reuse did not wait on runs.lock, so it recorded a result a delete removed, or it waited out the lock: $o"
}

# Bug (#1053): a Stop that came while a reuse held runs.lock ran the run's end (swe_stopping) there, whose line waits
# on the same lock (swe_runlog) until Stop killed the run, so the run lost its end. Here the TERM comes while the lock
# is held, and the trap checks the lock is free when it runs, and that the reuse was recorded first.
t_swerunsreusestop() {
  swe; swerunsfx; local o g
  o=$(export HERE=$SRC RTAG=x; . "$SRC/bench/swe.sh" && export SWE_DIR=$B SWE_KEY=stub-a SWE_ARM=stub-a SWE_INPUTS='{"i":1}'
    jq -c '.state = "running" | .tasks = [] | .done = 0 | .resolved = 0' "$B/live.json" > "$B/l.new" && mv "$B/l.new" "$B/live.json" || exit 9
    swe_reused() { kill -TERM "$BASHPID"; }; swe_board() { :; } # the Board's copy is not this case's, and needs the engine's settings
    trap 'exec {g}>>"$B/runs.lock"; if flock -n "$g"; then echo free; else echo held; fi; jq -c ".tasks | map(.id)" "$B/live.json"; exit 143' TERM
    swe_reuse proj__a-1; echo "the TERM was lost")
  [ "$o" = $'free\n["proj__a-1"]' ] || fail "a Stop during a reuse ran its trap with runs.lock held, or was lost: $o"
}

# Bug (#1053): archive and delete must not touch a run that has not ended: its process still writes its line and
# results. One going, and one whose process is gone with no end written, are refused with the reason, and nothing
# changes when one of the runs named is refused.
t_swerunsrunning() {
  swe; swerunsfx; local o v before
  jq -nc --arg id r20261120T090000-4 --argjson pid "$$" '{id: $id, pid: $pid, arms: ["stub-a"], n: 1, started: "2026-11-20T09:00:00Z", state: "running", tasks: []}' > "$B/live.json" || fail "the running run was not made"
  before=$(cat "$B/runs.jsonl")
  for v in archive delete; do
    o=$(loop bench swe runs "$v" "$R1" r20261120T090000-4 2>&1) && fail "$v of a running run was done: $o"
    [ "$o" = 'conveyor: run r20261120T090000-4 has not ended: stop it first (`conveyor.sh bench swe stop r20261120T090000-4`)' ] || fail "$v of a running run did not say why: $o"
  done
  jq -c '.pid = 2147483646' "$B/live.json" > "$B/l.new" && mv "$B/l.new" "$B/live.json"
  o=$(loop bench swe runs delete r20261120T090000-4 2>&1) && fail "delete of a run whose process is gone, with no end written, was done: $o"
  [ "$(cat "$B/runs.jsonl")" = "$before" ] && [ -e "$B/tails/$R1.jsonl" ] && [ -e "$B/results/stub-a/proj__b-2.json" ] || fail "a refused archive or delete changed a run"
}
