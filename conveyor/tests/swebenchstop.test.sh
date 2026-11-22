#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 120
# Engine cases: Stop of a SWE-bench run (`conveyor.sh bench swe stop [<run id>]`, bench/swe.sh's swe_stop): in its
# setup, in a trial and in its grade, of a run whose process is gone, a repeated Stop and a late one; and the end of a
# Conveyor arm's trial whose card only waits (swe_watch). The fixture is swebench.test.sh's swe().
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"

# An arms check's container, which runs apart from any run: a Stop or a run's end leaves it.
swecheckbox() {
  mkdir -p "$SWE_FX/boxes/conveyor-swe-check-other-x" "$B/check/other.h" && echo conveyor-swe-check-other-x > "$B/check/other.h/box" \
    || fail "the check's container was not made"
}
# <shell code> run with bench/swe.sh's functions on the state folder $T/$CASE/bench (no fixture), docker a stand-in
# that lists no container and logs each call to $T/$CASE/docker.log.
swedirect() { # <shell code>
  (export HERE=$SRC RTAG=x ST=$T/$CASE/state; . "$SRC/bench/swe.sh" || exit 9; SWE_DIR=$T/$CASE/bench; mkdir -p "$SWE_DIR" || exit 9
    docker() { printf '%s\n' "$*" >> "$T/$CASE/docker.log"; }; swe_board() { :; }; eval "$1")
}
# A run <id> live.json shows going on the first task, whose process is gone with no end written (killed), with its
# trial's container left.
swegone() { # <run id>
  local t; t=$(sweorder | head -n 1)
  mkdir -p "$B/work/$t.h" "$SWE_FX/boxes/conveyor-swe-$1-conveyor-$t" && echo "conveyor-swe-$1-conveyor-$t" > "$B/work/$t.h/box" \
    && jq -nc --arg id "$1" --arg t "$t" '{id: $id, pid: 2147483646, arm: "conveyor", arms: ["conveyor"], n: 2, done: 0, resolved: 0, current: $t,
      active: {arm: "conveyor", task: $t, phase: "Building"}, seq: 3, started: "2026-11-19T00:00:00Z", state: "running", tasks: []}' > "$B/live.json" \
    || fail "the run whose process is gone was not made"
}

# Bugs: Stop left the run, or the engine loop building in its sandbox, running, or wrote no end for the run; Stop
# killed the docker client only, so the trial's container, with the logins copied into it, was left running. (#645)
# Stop took no run ID, recorded no stopping, and removed an arms check's container with the run's.
t_swestop() {
  swe; local p out id
  : > "$SWE_FX/hold"
  loop bench swe 2 > "$T/$CASE/run.out" 2>&1 &
  wait_until "[ -s '$SWE_FX/pid' ]" || fail "the task's build did not start"
  p=$(cat "$SWE_FX/pid"); id=$(jq -r .id "$B/live.json"); swecheckbox
  out=$(loop bench swe stop "$id" 2>&1) || fail "stop failed: $out"
  [ "$out" = "conveyor: run $id is stopped. Its finished tasks are kept." ] || fail "Stop did not say the run is stopped: $out"
  wait_until "! kill -0 $p 2>/dev/null" || fail "the engine loop of the sandbox still runs after Stop"
  wait $! 2>/dev/null
  # Bug (#646 review E3): the arm's active time left out the work Stop interrupted: its wall minutes are kept. A run
  # stopped by you is not gone.
  tail -n 1 "$B/runs.jsonl" | jq -e --arg id "$id" '.id == $id and .state == "stopped" and (.stopping | type) == "string" and .ended >= .stopping
      and (.interrupted.minutes | type) == "number" and .gone == null' > /dev/null \
    && [ "$(jq -sc 'map(.event)[-2:]' "$B/tails/$id.jsonl")" = '["Stopping","Run stopped"]' ] \
    || fail "the run's line does not say stopped, or the run did not record its stopping before its end, or the interrupted work's minutes: $(tail -n 1 "$B/runs.jsonl") $(cat "$B/tails/$id.jsonl" 2>&1)"
  out=$(loop bench swe show "$id" 2>&1) && [ "$(jq -c '[.tasks[].cells[0].state, .run.cost]' <<<"$out")" = '["interrupted","not reached",{"usd":0,"state":"known"}]' ] \
    || fail "show does not tell the task Stop interrupted from the one never reached (#643), or the task stopped before its card recorded anything reads as an unknown cost, not \$0 (#644): $out"
  [ ! -d "$B/work" ] && [ -z "$(ls "$B"/results/*-"$EB" 2>/dev/null)" ] || fail "the stopped task left a sandbox or a result"
  [ "$(ls "$SWE_FX/boxes")" = conveyor-swe-check-other-x ] || fail "the stopped trial's container was left, or an arms check's removed: $(ls "$SWE_FX/boxes")"
}

# Bug (#645): Stop during the grade killed the harness only, so its container (sweb.eval.*) was left running; only
# the stopped run's grading container is removed, not another run's.
t_swestopgrade() {
  swe; local out id other=sweb.eval.proj__a-1.conveyor-r20261119T000000-1-proj__a-1
  : > "$SWE_FX/ghold"; mkdir -p "$SWE_FX/boxes/$other"
  loop bench swe 1 --arm stub-a > "$T/$CASE/run.out" 2>&1 &
  wait_until "ls '$SWE_FX/boxes' | grep -v '^$other\$' | grep -q '^sweb\\.eval\\.'" || fail "the grade's container did not start: $(cat "$T/$CASE/run.out")"
  id=$(jq -r .id "$B/live.json")
  out=$(loop bench swe stop "$id" 2>&1); rm -f "$SWE_FX/ghold"
  [ "$out" = "conveyor: run $id is stopped. Its finished tasks are kept." ] || fail "Stop did not end the run in its grade: $out"
  wait $! 2>/dev/null
  [ "$(ls "$SWE_FX/boxes")" = "$other" ] || fail "the stopped grade's container was left, or another run's removed: $(ls "$SWE_FX/boxes")"
}

# Bug: Stop found no run while an arm's preflight ran, as the run was recorded only after its preflights.
t_swestoppre() {
  swe; local out id
  : > "$SWE_FX/phold"
  loop bench swe 1 --arm stub-slow > "$T/$CASE/run.out" 2>&1 &
  wait_until "[ -n \"\$(ls '$SWE_FX/boxes' 2>/dev/null)\" ]" || fail "the preflight's container did not start"
  id=$(jq -r .id "$B/live.json")
  out=$(loop bench swe stop "$id" 2>&1); rm -f "$SWE_FX/phold"
  [ "$out" = "conveyor: run $id is stopped. Its finished tasks are kept." ] || fail "Stop did not end the run in its preflight: $out"
  wait $! 2>/dev/null
  tail -n 1 "$B/runs.jsonl" | jq -e --arg id "$id" '.id == $id and .state == "stopped" and (.stopping | type) == "string"' > /dev/null && [ -z "$(ls "$SWE_FX/boxes")" ] \
    || fail "the stopped run is not recorded with its stopping, or its preflight's container was left: $(cat "$B/runs.jsonl" 2>&1) $(ls "$SWE_FX/boxes")"
}

# Bugs (#645): a Stop sent for a run that had ended stopped the run started after it, as Stop took no run ID; a second
# Stop of a stopped run wrote its end again. Run 1 builds the first task; run 2 reuses it and is on the second when a
# late Stop of run 1 comes, then Stop of run 2 comes twice.
t_swestopstale() {
  swe; local first second a b p out
  { read -r first; read -r second; } < <(sweorder)
  out=$(loop bench swe 1 2>&1) || fail "the first run failed: $out"
  a=$(jq -r .id "$B/live.json"); rm -f "$SWE_FX/pid"; : > "$SWE_FX/hold"
  loop bench swe 2 > "$T/$CASE/run.out" 2>&1 &
  wait_until "[ -s '$SWE_FX/pid' ]" || fail "the second run's build did not start"
  p=$(cat "$SWE_FX/pid"); b=$(jq -r .id "$B/live.json")
  out=$(loop bench swe stop "$a" 2>&1) && [ "$out" = "conveyor: run $a finished before Stop." ] || fail "the late Stop did not say its run had ended: $out"
  kill -0 "$p" 2>/dev/null && jq -e --arg b "$b" '.id == $b and .state == "running" and .stopping == null' "$B/live.json" > /dev/null \
    || fail "the late Stop of run 1 stopped run 2: $(cat "$B/live.json")"
  out=$(loop bench swe stop "$b" 2>&1) && [ "$out" = "conveyor: run $b is stopped. Its finished tasks are kept." ] || fail "Stop did not end run 2: $out"
  wait $! 2>/dev/null
  out=$(loop bench swe stop "$b" 2>&1) && [ "$out" = "conveyor: run $b is stopped. Its finished tasks are kept." ] || fail "the second Stop of run 2 failed: $out"
  [ "$(grep -c "\"$b\"" "$B/runs.jsonl")" = 1 ] && [ "$(jq -sc 'map(select(.event == "Run stopped")) | length' "$B/tails/$b.jsonl")" = 1 ] \
    || fail "the second Stop wrote run 2's end again: $(cat "$B/runs.jsonl")"
  tail -n 1 "$B/runs.jsonl" | jq -e --arg f "$first" --arg s "$second" '.tasks == [{id: $f, arm: "conveyor", result: "resolved", reused: true}] and .interrupted.task == $s' > /dev/null \
    && [ -s "$B/results/$(jq -r .key "$B/live.json")/$first.json" ] || fail "the stopped run lost its finished task: $(tail -n 1 "$B/runs.jsonl")"
}

# Bug (#645): Stop of a run whose process had gone with no end written said no run was going and left the run shown
# running, with its trial's container. Its end is recorded and only its own container removed.
t_swestopgone() {
  swe; local out id=r20261119T000000-1
  swegone "$id"; swecheckbox
  # Bug (#646): the run page read this run as stopped like any other, so it said "Stopped by you" and offered no Stop
  # run, which records its end and removes its container. gone tells the page it still needs one.
  out=$(loop bench swe show "$id" 2>&1) && [ "$(jq -c '.run | [.state, .gone]' <<<"$out")" = '["stopped",true]' ] \
    || fail "show does not say the run's process is gone with no end written: $(jq -c .run <<<"$out" 2>&1 || echo "$out")"
  out=$(loop bench swe stop "$id" 2>&1) || fail "stop failed: $out"
  [ "$out" = "conveyor: run $id was interrupted: its process had ended. Its end is recorded, its containers are removed, and its finished tasks are kept." ] \
    || fail "Stop did not say the run was interrupted: $out"
  # Bug (#646 review E2): the end Stop recorded for it read as any stopped run's, so the run page said "Stopped by
  # you" once its end was written. gone stays on the end.
  tail -n 1 "$B/runs.jsonl" | jq -e --arg id "$id" --arg t "$(sweorder | head -n 1)" '.id == $id and .state == "stopped" and .interrupted.task == $t and .gone == true' > /dev/null \
    || fail "the run's end was not recorded, or not as the end of a run whose process was gone: $(cat "$B/runs.jsonl" 2>&1)"
  [ "$(ls "$SWE_FX/boxes")" = conveyor-swe-check-other-x ] || fail "the run's container was left, or an arms check's removed: $(ls "$SWE_FX/boxes")"
}

# Bug (#1383 R32): a run's end (swe_end) read box files, which an arm can write, and read each one twice: a file that
# named the run's container for the check named another for docker rm -f. Here each box file names the run's
# container, and cat stands in for an arm that rewrites it after its first read: every later read of it gives another
# container's name. Docker lists the run's container and an arms check's; only the run's goes.
t_swestopbox() {
  local id=r20261119T000000-1 d=$T/$CASE/bench out
  mkdir -p "$d/work/t1" "$d/work/t2.h" && echo "conveyor-swe-$id-a-t1" > "$d/work/t1/box" && echo "conveyor-swe-$id-a-t2" > "$d/work/t2.h/box" \
    && jq -nc --arg id "$id" '{id: $id, state: "running", active: null}' > "$d/live.json" || fail "the run was not made"
  swedirect "SWE_RUN=$id"'; cat() { case ${1-} in */box) echo >> "$1.reads"; [ "$(wc -l < "$1.reads")" = 1 ] && command cat "$1" || echo another ;; *) command cat "$@" ;; esac; }
    docker() { printf "%s\n" "$*" >> "$T/$CASE/docker.log"; [ "$1" != ps ] || printf "%s\n" "conveyor-swe-$SWE_RUN-a-t2" conveyor-swe-check-a-x; }
    swe_end stopped' > /dev/null 2>&1
  out=$(grep '^rm ' "$T/$CASE/docker.log" 2>&1)
  [ "$out" = "rm -f conveyor-swe-$id-a-t2" ] \
    || fail "the end of run $id, with box files (work/t1/box, work/t2.h/box) that change after their first read and Docker listing conveyor-swe-$id-a-t2 and conveyor-swe-check-a-x, removed other containers than the run's: $out"
}

# Bug (#1383 R37): Stop trusted kill -0 on live.json's pid, so once the run's process had ended and its pid was another
# process's, Stop sent that process SIGTERM, and SIGKILL after 30 s. A free run lock says the run's process has ended.
t_swestopreused() {
  local id=r20261119T000000-1 d=$T/$CASE/bench p out
  # Not this shell's child: an ended child left unreaped would still answer kill -0.
  p=$(sleep 120 > /dev/null 2>&1 & echo $!) # sleep: the unrelated process that holds the reused pid; nothing waits on it
  mkdir -p "$d" && jq -nc --arg id "$id" --argjson p "$p" '{id: $id, pid: $p, state: "running", active: null}' > "$d/live.json" \
    || { kill "$p"; fail "the run was not made"; }
  out=$(swedirect "swe_stop $id" 2>&1)
  kill -0 "$p" 2>/dev/null || fail "Stop of run $id (live.json pid $p, a sleep of no run, run.lock free) ended that process: $out"
  kill "$p"
  [ "$out" = "conveyor: run $id was interrupted: its process had ended. Its end is recorded, its containers are removed, and its finished tasks are kept." ] \
    || fail "Stop of run $id with its run lock free did not record the end of a run whose process was gone: $out"
}

# Bug (#645): a run started while live.json still showed a run whose process had gone, so a late Stop of that run,
# reading it as going, could act on the new run's work. The new run records its end first, under the stop lock.
t_swestopnext() {
  swe; local out id=r20261119T000000-1
  swegone "$id"
  out=$(loop bench swe 1 2>&1) || fail "the run failed: $out"
  [ "$(jq -sc --arg id "$id" 'map([.id == $id, .state])' "$B/runs.jsonl")" = '[[true,"stopped"],[false,"done"]]' ] \
    || fail "the new run did not record the end of the run whose process had gone before its own: $(cat "$B/runs.jsonl")"
  [ -z "$(ls "$SWE_FX/boxes")" ] || fail "the gone run's container was left: $(ls "$SWE_FX/boxes")"
}

# Bug: a run that died in its preflight left its container, found only through the box file in check/<arm>.h, which the
# next standalone check of that arm (it starts that folder over) replaced. Stop finds the container by the run's ID in
# its name, so it goes with no box file.
t_swestoppredead() {
  swe; local id=r20261119T000000-1 c
  c=conveyor-swe-$id-stub-a-preflight
  swegone "$id"; swecheckbox; rm -f "$B"/work/*.h/box; mkdir -p "$SWE_FX/boxes/$c" "$B/check/stub-a.h" && echo conveyor-swe-check-stub-a-preflight > "$B/check/stub-a.h/box"     || fail "the dead run's preflight container was not made"
  loop bench swe stop "$id" > "$T/$CASE/stop.out" 2>&1 || fail "stop failed: $(cat "$T/$CASE/stop.out")"
  [ "$(ls "$SWE_FX/boxes")" = conveyor-swe-check-other-x ] || fail "Stop of run $id left its preflight container $c, or removed an arms check's: $(ls "$SWE_FX/boxes")"
}

# Bug (#1051): a Conveyor arm's card whose every failing case fails on main too waits for main to change, which never
# changes in a trial, so the trial sat until its time limit (taskTimeout, 4 hours) with nothing running, its task
# shown at Testing. Here the fake engine's card stages its fix, commits nothing, and then only waits, for 30 s at
# most: the trial ends while it waits, its card's staged change is graded (its HEAD and main have nothing on them), and
# the task's record says why it ended.
# loop: only a whole trial shows its command stopped, the card's staged change read and graded, and the reason kept.
t_swewaitmain() {
  swe; local first out t0
  first=$(sweorder | head -n 1); : > "$SWE_FX/ewait"; t0=$SECONDS
  out=$(loop bench swe 1 2>&1) || fail "the run failed: $out"
  lim=$(loadlimit 25 30) # under the card's 30 s wait
  [ $((SECONDS - t0)) -lt "$lim" ] || fail "the trial did not end while its card waited: it took $((SECONDS - t0)) s (limit $lim s: 25 s times the load factor $CASE_LOAD)"
  jq -e '.resolved == true and .fired == true and .ended == "its card waited for main to change: tests/t.py fail on main at 0123456789ab too"' \
    "$B"/results/*-"$EB/$first.json" > /dev/null || fail "the waiting card's patch was not graded, or the record does not name the wait: $(cat "$B"/results/*-"$EB/$first.json")"
  grep -q '^+fixed' "$B"/results/*-"$EB/$first.patch" || fail "the patch is not the card's staged change: $(cat "$B"/results/*-"$EB/$first.patch")"
  # The run page (bench swe show) carries the reason for the task's cell.
  out=$(loop bench swe show "$(tail -n 1 "$B/runs.jsonl" | jq -r .id)" 2>&1) && jq -e '[.tasks[].cells[] | .ended | strings] | length == 1' <<<"$out" > /dev/null \
    || fail "show does not carry why the trial ended: $out"
}

# Bug (#1051): which card records end a trial. Only a card of the task's issue that has not ended and whose idle mark
# stands (the engine stands it only while the card sleeps out a wait) ends it: a card in a session (its live record and
# no idle mark), an idle mark of another card, or a card that ended, does not.
t_swewaited() {
  local d=$T/$CASE/cards o
  # The card records given, then what SWE_IDLE reads of the cards folder, through swe_waited.
  waited() { (export HERE=$SRC RTAG=x ST=$T/$CASE/state; . "$SRC/bench/swe.sh" && { printf '%s\n' '{"card":"c1","issue":1,"step":"start","result":"ok","of":"test"}' "$@"
    SWE_CARDS=$d bash -c "$SWE_IDLE"; } | swe_waited); }
  mkdir -p "$d" && echo '{"step":"build","action":"editing x.py"}' > "$d/c1.live" || fail "the cards folder was not made"
  o=$(waited) || fail "swe_waited failed: $o"
  [ -z "$o" ] || fail "a card in a session ended the trial: $o"
  : > "$d/c0.idle"; o=$(waited)
  [ -z "$o" ] || fail "another card's idle mark ended the trial: $o"
  # Bug (#1383 R39): a session stood its own idle mark (`touch $PWD.idle` from its worktree) and ended the trial,
  # so its half-made change was graded. Its live record, which names its model, says a session runs.
  echo '{"step":"build","model":"bench-m","action":"editing x.py"}' > "$d/c1.live" && : > "$d/c1.idle"; o=$(waited)
  [ -z "$o" ] || fail "a card in a session with an idle mark ended the trial (live record $(cat "$d/c1.live")): $o"
  echo '{"step":"test","action":"waiting for main to change: t fail on main at abc too"}' > "$d/c1.live" && : > "$d/c1.idle"; o=$(waited)
  [ "$o" = '{"card":"c1","why":"its card waited for main to change: t fail on main at abc too"}' ] || fail "the waiting card did not end the trial: $o"
  o=$(waited '{"card":"c1","issue":1,"step":"landed","result":"ok"}')
  [ -z "$o" ] || fail "a card that landed ended the trial: $o"
}
