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
  # A poll: only a running trial has what Stop must end (the run, the sandbox's loop and the trial's
  # container), and the trial reaches its build in its own time.
  wait_until "[ -s '$SWE_FX/pid' ]" || fail "the task's build did not start"
  p=$(cat "$SWE_FX/pid"); id=$(jq -r .id "$B/live.json"); swecheckbox
  out=$(loop bench swe stop "$id" 2>&1) || fail "stop failed: $out"
  [ "$out" = "conveyor: run $id is stopped. Its finished tasks are kept." ] || fail "Stop did not say the run is stopped: $out"
  # A poll: the sandbox's loop is a real process that Stop's signal ends in its own time.
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
  # A poll: only a running trial's grade has the container Stop must remove, and it starts in its own time.
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
  # A poll: only a running preflight has the container Stop must remove, and it starts in its own time.
  wait_until "[ -n \"\$(ls '$SWE_FX/boxes' 2>/dev/null)\" ]" || fail "the preflight's container did not start"
  id=$(jq -r .id "$B/live.json")
  out=$(loop bench swe stop "$id" 2>&1); rm -f "$SWE_FX/phold"
  [ "$out" = "conveyor: run $id is stopped. Its finished tasks are kept." ] || fail "Stop did not end the run in its preflight: $out"
  wait $! 2>/dev/null
  tail -n 1 "$B/runs.jsonl" | jq -e --arg id "$id" '.id == $id and .state == "stopped" and (.stopping | type) == "string"' > /dev/null && [ -z "$(ls "$SWE_FX/boxes")" ] \
    || fail "the stopped run is not recorded with its stopping, or its preflight's container was left: $(cat "$B/runs.jsonl" 2>&1) $(ls "$SWE_FX/boxes")"
}

# Bug: Stop found no run during a run's setup (the task list's fetch, the engine's install), as the run wrote live.json
# only after it: Stop said no run was going, and the run then started. A harness in front of the fixture's holds the
# task list's fetch while $SWE_FX/thold is there. Then a run that ends before it is one (an engine not released) puts
# live.json back as it was, and records no run.
t_swestopsetup() {
  swe; local out id
  printf '%s\n' '#!/usr/bin/env bash' \
    '[ "$2" != tasks ] || { : > "$SWE_FX/tasks-asked"; while [ -e "$SWE_FX/thold" ]; do sleep 0.1; done; } # sleep: held until the case removes thold' \
    'exec "$SWE_FX/py" "$@"' > "$T/$CASE/py" && chmod +x "$T/$CASE/py" && : > "$SWE_FX/thold" || fail "the held harness was not made"
  CONVEYOR_BENCH_PYTHON=$T/$CASE/py loop bench swe 1 > "$T/$CASE/run.out" 2>&1 &
  wait_until "[ -e '$SWE_FX/tasks-asked' ]" "cat '$T/$CASE/run.out'" || fail "the run did not reach its task list's fetch"
  id=$(jq -r 'select(.state == "running") | .id' "$B/live.json" 2>/dev/null)
  out=$(loop bench swe stop 2>&1); rm -f "$SWE_FX/thold"
  [ -n "$id" ] && [ "$out" = "conveyor: run $id is stopped. Its finished tasks are kept." ] || fail "bench swe stop during the run's setup did not stop it: $out (live.json: $(cat "$B/live.json" 2>&1))"
  wait $! 2>/dev/null
  tail -n 1 "$B/runs.jsonl" | jq -e --arg id "$id" '.id == $id and .state == "stopped"' > /dev/null && [ ! -s "$SWE_FX/log" ] && ! grep -q '^create ' "$SWE_FX/docker.log" 2>/dev/null \
    || fail "the run stopped in its setup is not recorded stopped, or it went on to a check or a trial: $(cat "$B/runs.jsonl" 2>&1) $(cat "$T/$CASE/run.out")"
  out=$(loop bench swe 1 --engine v9.9.9 2>&1) && fail "a run on an engine not released started: $out"
  jq -e --arg id "$id" '.id == $id and .state == "stopped"' "$B/live.json" > /dev/null && [ "$(wc -l < "$B/runs.jsonl")" = 1 ] \
    || fail "bench swe 1 --engine v9.9.9 did not put live.json back, or recorded a run: $(cat "$B/live.json") $(cat "$B/runs.jsonl")"
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
  # A poll: only a second run still running shows that a late Stop of the first leaves it running, and it reaches its
  # build in its own time.
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

# Bug (#1448 review): a run that Docker refused cleared its Stop trap before it looked up the release of its engine's
# commit, which can wait 20 s for the origin; a Stop in that lookup killed it and recorded its end with no stopping time.
# The git stand-in holds ls-remote once Docker has refused (the lookup), until the hold file is gone.
t_swestoprelname() {
  swe; local out id g=$T/$CASE/gitbin
  mkdir -p "$g" && : > "$T/$CASE/hold" && printf '%s\n' '#!/usr/bin/env bash' \
    "if [ \"\$1\" = ls-remote ] && [ -e '$SWE_FX/nodocker' ] && grep -qx info '$SWE_FX/docker.log' 2>/dev/null; then" \
    "  : > '$T/$CASE/inlookup'; while [ -e '$T/$CASE/hold' ]; do sleep 0.1; done; fi" \
    "PATH=\${PATH#*gitbin:} exec git \"\$@\"" > "$g/git" && chmod +x "$g/git" && : > "$SWE_FX/nodocker" || fail "the git stand-in was not made"
  PATH=$g:$PATH loop bench swe 1 --solo --arm conveyor --engine "$EA" > "$T/$CASE/run.out" 2>&1 &
  # A poll: the run reaches the lookup in its own time, after its setup is refused.
  wait_until "[ -e '$T/$CASE/inlookup' ]" || fail "the run did not look up the release after Docker refused: $(cat "$T/$CASE/run.out")"
  id=$(jq -r .id "$B/live.json")
  out=$(loop bench swe stop "$id" 2>&1); rm -f "$T/$CASE/hold"; wait $! 2>/dev/null
  [ "$out" = "conveyor: run $id is stopped. Its finished tasks are kept." ] || fail "Stop in the release lookup did not stop run $id: $out"
  tail -n 1 "$B/runs.jsonl" | jq -e --arg id "$id" '.id == $id and .state == "stopped" and (.stopping | type) == "string" and .gone == null' > /dev/null \
    || fail "Stop in the release lookup of run $id recorded its end without the time it reached the run: $(tail -n 1 "$B/runs.jsonl")"
}

# Bug (#1051): which card records end a trial. Only a card of the task's issue that has not ended and whose idle mark
# stands (the engine stands it only while the card sleeps out a wait) ends it: a card in a session (its live record and
# no idle mark), an idle mark of another card, or a card that ended, does not.
t_swewaited() {
  local d=$T/$CASE/cards o P=$T/$CASE/proc m
  mkdir -p "$d" "$T/$CASE/main" && m=$(cd -P "$T/$CASE/main" && pwd) || fail "the cards or main folder was not made"
  # The process list SWE_IDLE reads: a folder with one <n>/cwd link to each given folder, from process 2 on, and process 1
  # (the container's `sleep infinity`) in the image's own folder, as /testbed (none given: only process 1).
  proc() { local i=1 t; rm -rf "$P"; mkdir -p "$P/1" && ln -s "$T/$CASE/testbed" "$P/1/cwd" || fail "the process list was not made"
    for t in "$@"; do i=$((i + 1)); mkdir -p "$P/$i" && ln -s "$t" "$P/$i/cwd" || fail "the process list was not made"; done; }
  proc / "$m"
  # The card log with the records given, then what swe_watch reads (SWE_READ: the log's tail, the live records as they
  # stand, SWE_IDLE), through swe_waited.
  waited() { (export HERE=$SRC RTAG=x ST=$T/$CASE/state; . "$SRC/bench/swe.sh" && { mkdir -p "$T/$CASE/log" && printf '%s\n' '{"card":"c1","issue":1,"step":"start","result":"ok","of":"test"}' "$@" > "$T/$CASE/log/cards.jsonl"
    SWE_SST=$T/$CASE/log SWE_CARDS=$d SWE_MAINDIR=$m SWE_PROC=$P bash -c "$SWE_READ"; } | swe_waited); }
  echo '{"step":"build","action":"editing x.py"}' > "$d/c1.live" || fail "the cards folder was not made"
  o=$(waited) || fail "swe_waited failed: $o"
  [ -z "$o" ] || fail "a card in a session ended the trial: $o"
  # c0 has an idle mark and a waiting live record (so SWE_IDLE lists it): only swe_waited's card match leaves it out.
  echo '{"step":"test","action":"waiting for main to change: t fail on main at abc too"}' > "$d/c0.live" && : > "$d/c0.idle"; o=$(waited)
  [ -z "$o" ] || fail "another card's idle mark ended the trial: $o"
  # Bug (#1383 R39): a session stood its own idle mark (`touch $PWD.idle` from its worktree) and ended the trial,
  # so its half-made change was graded. Its live record, which names its model, says a session runs.
  # The record has a wait's action, so only its model keeps the trial running.
  echo '{"step":"build","model":"bench-m","action":"waiting for main to change: x"}' > "$d/c1.live" && : > "$d/c1.idle"; o=$(waited)
  [ -z "$o" ] || fail "a card in a session with an idle mark ended the trial (live record $(cat "$d/c1.live")): $o"
  # Bug (#1503): a session removed its live record (the engine writes it) and left the idle mark: no model was read, so
  # the idle mark looked like a wait and ended the trial.
  rm -f "$d/c1.live"; o=$(waited)
  [ -z "$o" ] || fail "an idle mark with no live record ended the trial: $o"
  # Bug (#1503 E1): a session emptied its live record instead (the file stands, no model is read): that is no wait either.
  : > "$d/c1.live"; o=$(waited)
  [ -z "$o" ] || fail "an idle mark with an empty live record ended the trial: $o"
  echo 'not json' > "$d/c1.live"; o=$(waited)
  [ -z "$o" ] || fail "an idle mark with an unreadable live record ended the trial: $o"
  # Bug (#1503 E2): a session left no model and an action of its own (a test run's live record names none), with the
  # idle mark: only a wait's action ("waiting ...") is a wait.
  echo '{"step":"test","action":"running the tests"}' > "$d/c1.live"; o=$(waited)
  [ -z "$o" ] || fail "an idle mark beside a live record with the action 'running the tests' ended the trial: $o"
  # Bug (#1503 E1): `{}` is an object with no model, and passed as a wait; a wait's live record always has an action.
  echo '{}' > "$d/c1.live"; o=$(waited)
  [ -z "$o" ] || fail "an idle mark with a live record of {} ended the trial: $o"
  # Bug (#1503 E1): a live record that holds an idle record of its own (here with no idle mark) was read as the engine's.
  rm -f "$d/c1.idle"; printf '%s\n' '{"idle":"c1","action":"waiting for main to change: x","model":""}' > "$d/c1.live"; o=$(waited)
  [ -z "$o" ] || fail "a live record holding an idle record ended the trial: $o"
  : > "$d/c1.idle"; printf '%s\n' '{"model":"","idles":[{"idle":"c1","action":"waiting x","model":""}]}' > "$d/c1.live"; o=$(waited)
  [ -z "$o" ] || fail "a live record holding an idles list ended the trial: $o"
  # Bug (#1503 E4): a live record that holds a card record of another card of the issue (c0, with a mark and a waiting
  # live record of its own) made c0 the newest card of the issue, and its mark ended the trial while c1 ran.
  # The record is one line that is a card record and a wait both: only reading card records before the first "---" line leaves it out.
  rm -f "$d/c1.idle"; printf '%s\n' '{"card":"c0","issue":1,"step":"start","result":"ok","of":"test","action":"waiting for main to change: x"}' > "$d/c0.live"; o=$(waited)
  [ -z "$o" ] || fail "a live record holding a card record of another card ended the trial: $o"
  echo '{"step":"test","action":"waiting for main to change: t fail on main at abc too"}' > "$d/c1.live" && : > "$d/c1.idle"; o=$(waited)
  [ "$o" = '{"card":"c1","why":"its card waited for main to change: t fail on main at abc too"}' ] || fail "the waiting card did not end the trial: $o"
  # Bug (#1503 E3): a session wrote the idle mark and a live record of a wait, exactly the engine's (the session can
  # write the cards folder), and ended the trial. A running session is a process whose cwd is its worktree; a wait has
  # only the engine (cwd: the main checkout) and the scan (cwd "/"). The process list is a folder of cwd links (SWE_PROC),
  # as the session cannot write what the kernel lists; each case below changes only that list.
  # Bug (#1503 E8): the scan counted process 1 (`sleep infinity`, in the image's folder, as /testbed) as a session, so a
  # waiting card ran to the time limit: this plain wait has process 1 in /testbed, and must end the trial.
  proc / "$m"; o=$(waited)
  [ -n "$o" ] || fail "the waiting card, with only the engine (cwd: the main checkout) and the scan running, did not end the trial"
  proc / "$m" "$d/c1"; o=$(waited)
  [ -z "$o" ] || fail "a card with a process in its worktree (a session) and a live record of a wait ended the trial: $o"
  # Bug (#1503 E6): the session moved its worktree out of the cards folder (here beside it, and into the main checkout),
  # so a cwd prefix check of the cards folder did not see its process.
  proc / "$m" "$T/$CASE/moved"; o=$(waited)
  [ -z "$o" ] || fail "a session with its worktree moved beside the cards folder ended the trial: $o"
  proc / "$m" "$m/moved"; o=$(waited)
  [ -z "$o" ] || fail "a session with its worktree moved into the main checkout ended the trial: $o"
  # A process that cannot be read counts as a session, and so does an empty list: neither shows a wait.
  proc / "$m"; mkdir -p "$P/9" && : > "$P/9/cwd"; o=$(waited) # a plain file: readlink fails on it, as on a process the scan may not read
  [ -z "$o" ] || fail "a process whose cwd cannot be read ended the trial: $o"
  proc; o=$(waited)
  [ -z "$o" ] || fail "a process list of only process 1 ended the trial: $o"
  # Bug (#1503 E6): a worktree whose path is the main checkout's and a newline: $(readlink) dropped the newline.
  mkdir -p "$m"$'\n' && proc / "$m" "$m"$'\n'; o=$(waited)
  [ -z "$o" ] || fail "a session in a folder named like the main checkout and a newline ended the trial: $o"
  # Bug (#1503 E4): the session appended a start line of another card (c0, with a mark and a live record of a wait, no
  # process) to the card log it can write, and c0 became the newest card of the issue while c1's session ran.
  proc / "$m" "$d/c1"; rm -f "$d/c1.idle"; echo '{"step":"test","action":"waiting for main to change: x"}' > "$d/c0.live"; : > "$d/c0.idle"
  o=$(waited '{"card":"c0","issue":1,"step":"start","result":"ok","of":"test"}')
  [ -z "$o" ] || fail "a card record of another card in the card log, appended while a session ran, ended the trial: $o"
  rm -f "$d/c0.idle" "$d/c0.live"; : > "$d/c1.idle"
  # Bug (#1503 E7): the session writes the first folder of the PATH swe_in gives ($HOME/.local/bin), so a program there
  # (here a readlink that names no process but the scan's) hid its own process from the scan.
  mkdir -p "$d/bin" && printf '#!/bin/sh\necho /\n' > "$d/bin/readlink" && chmod +x "$d/bin/readlink" || fail "the program of the session's PATH was not made"
  o=$(PATH=$d/bin:$PATH waited)
  [ -z "$o" ] || fail "a program of the session's PATH hid its process from the scan, and the trial ended: $o"
  proc / "$m"
  o=$(waited '{"card":"c1","issue":1,"step":"landed","result":"ok"}')
  [ -z "$o" ] || fail "a card that landed ended the trial: $o"
}

# The stand-in docker with <shell code> run first on each call (its arguments "$@"), then the fixture's own.
swedocker() { # <shell code>
  mv "$SWE_FX/bin/docker" "$SWE_FX/bin/docker.real" && printf '%s\n' '#!/usr/bin/env bash' "$1" 'exec "$SWE_FX/bin/docker.real" "$@"' > "$SWE_FX/bin/docker" \
    && chmod +x "$SWE_FX/bin/docker" || fail "the docker stand-in's hook was not made"
}
# A stand-in for timeout that gives the trial's command a limit of 1 s, and keeps the host process that runs it (its
# parent) in $SWE_FX/trial.
swetimeout1() {
  printf '%s\n' '#!/usr/bin/env bash' 't=$(PATH=${PATH//"$SWE_FX/bin:"/} command -v timeout)' \
    'case "$*" in *SWE_SB=*/work/*SWE_PROMPT=*) echo "$PPID" > "$SWE_FX/trial"; shift; exec "$t" 1 "$@" ;; esac' 'exec "$t" "$@"' \
    > "$SWE_FX/bin/timeout" && chmod +x "$SWE_FX/bin/timeout" || fail "the timeout stand-in was not made"
}
# Run <id>'s conveyor trial on <task>, its checkout <main> in the sandbox, at Stop: the build's line (2M input: $2),
# which swe_watch last read, and the review's (1M cache reads: $0.50), written since, in its container. A session goes
# on there: it adds a fix line (1M cache reads) once Stop has read the records, at the run's end's docker ps (the list
# of its containers to remove), unless it was ended before; that ps waits for its line or its end.
swecostbox() { # <run id> <task> <main>
  local s=$B/work/$2/$3/conveyor/state c=conveyor-swe-$1-conveyor-$2
  mkdir -p "$s" "$SWE_FX/boxes/$c" && printf '%s\n' '{"card":"c1","issue":1,"step":"build","result":"ok","model":"bench-m","usage":{"input":2000000}}' \
    '{"card":"c1","issue":1,"step":"start","result":"ok","of":"review"}' '{"card":"c1","issue":1,"step":"review","result":"GO","model":"bench-m","usage":{"read":1000000}}' > "$s/cards.jsonl" \
    || fail "the trial's container and its card's lines were not made"
  swedocker 'if [ "$1" = ps ]; then : > "$SWE_FX/go"; i=0; while [ ! -e "$SWE_FX/wrote" ] && kill -0 "$(cat "$SWE_FX/writer")" 2>/dev/null && [ $i -lt 100 ]; do sleep 0.1; i=$((i + 1)); done; fi' # sleep: the stand-in's ps holds Stop at its weak point while a session still running writes
  docker exec "$c" bash -c "$(wait_fn)"'; echo $$ > "$SWE_FX/writer"; wait_poll [ -e "$SWE_FX/go" ]
    echo "{\"card\":\"c1\",\"issue\":1,\"step\":\"fix\",\"result\":\"ok\",\"model\":\"bench-m\",\"usage\":{\"read\":1000000}}" >> "$1/cards.jsonl"; : > "$SWE_FX/wrote"' _ "$s" > /dev/null 2>&1 &
  # A poll on the session: it runs in the container (its process group the stand-in keeps) before Stop comes.
  wait_until "[ -s '$SWE_FX/writer' ] && [ -n \"\$(ls '$SWE_FX/boxes/$c/groups' 2>/dev/null)\" ]" || fail "the session in the trial's container did not start"
}
# Bugs (#1454 R157): Stop kept the cost swe_watch last read of the trial it interrupted (at most every 2 s, and only
# when the records changed), so a session's usage written after that read was lost; a session that went on in the
# container wrote usage after Stop's read, before the container was removed. The cost Stop keeps is that of every line
# in the container at the trial's end: $2.50 (the session ended before the read), never $2.50 with its fix line written.
t_swestopcostlast() {
  swe; local o id=r20261101T000000-4 t=proj__b-2
  swecostbox "$id" "$t" swe-x
  o=$(swefn 'sweliveseed "$1" "{\"arm\": \"conveyor\", \"task\": \"$2\", \"phase\": \"Reviewing\", \"start\": \"2026-01-01T00:00:00Z\", \"cost\": {\"usd\": 2, \"state\": \"known\", \"unpriced\": 0}}" \
    && SWE_RUN=$1 SWE_KIND=conveyor SWE_ARMJ="{\"name\": \"conveyor\"}" && swe_end stopped && tail -n 1 "$SWE_DIR/runs.jsonl" | jq -c .interrupted.cost' "$id" "$t" 2>&1)
  [ ! -e "$SWE_FX/wrote" ] || fail "Stop of run $id on $t left its session running after it read the trial's records: it wrote a fix line the cost leaves out ($o)"
  [ "$o" = '{"usd":2.5,"state":"known","unpriced":0}' ] \
    || fail "Stop of run $id on $t (cost last read \$2; a build and a review line in its container) did not keep the cost of the review line written since: $o"
}
# Bug (#1454 R157, review E2): Stop of a run whose process is gone read no records in its trial's container, so it
# kept the cost swe_watch last read. Its column names its kind; its prices are the run's copy of the pack: the live
# pack's prices change after the copy (ten times as much), so a cost priced from the live pack is $25, not $2.50.
t_swestopcostgone() {
  swe; local o id=r20261119T000000-1 t
  t=$(sweorder | head -n 1); swegone "$id"; swecostbox "$id" "$t" "swe-${R##*/}"
  tune '.prices = {"bench-m": {input: 1, output: 2, cacheRead: 0.5}}'
  mkdir -p "$B/frozen/conveyor/main/.conveyor" && cp "$R/.conveyor/project.json" "$B/frozen/conveyor/main/.conveyor/" \
    && jq -c '.cols = [{arm: "conveyor", key: "k", kind: "conveyor"}] | .active.cost = {usd: 2, state: "known", unpriced: 0}' "$B/live.json" > "$B/l.new" && mv "$B/l.new" "$B/live.json" \
    && tune '.prices = {"bench-m": {input: 10, output: 20, cacheRead: 5}}' \
    || fail "the run's copy of the pack or its column was not made"
  o=$(loop bench swe stop "$id" 2>&1) || fail "stop failed: $o"
  [ ! -e "$SWE_FX/wrote" ] || fail "Stop of gone run $id on $t left its session running after it read the trial's records: it wrote a fix line the cost leaves out"
  o=$(tail -n 1 "$B/runs.jsonl" | jq -c .interrupted.cost)
  [ "$o" = '{"usd":2.5,"state":"known","unpriced":0}' ] \
    || fail "Stop of gone run $id on $t (cost last read \$2; a build and a review line in its container) did not keep the cost of the review line written since, at the prices of the run's copy of the pack: $o"
}

# Bug (#1454 R155): the time limit ended only the host's docker client, as docker exec passes no signal on, so the
# arm's command went on in the container while its patch was read, and a file it wrote after its limit was graded.
# The stand-in's exec runs its script apart from its client, as a container does; the limit here is 1 s
# (swetimeout1), the read of the change takes 3 s, and stub-late writes late.py 2 s after it starts.
# loop: only a whole run gives the trial's command its time limit and grades the patch read after it.
t_swetriallate() {
  swe; local first o p r
  first=$(sweorder | head -n 1)
  r='if [ -e hello.py ]; then echo "print(\"hello\")" > hello.py; echo "{\"type\": \"done\"}"; else echo fixed > x.py; echo "{\"type\": \"done\"}"; (sleep 2; echo late > late.py) & sleep 4; fi' # sleep: the arm's late write after its limit, and its command still running past it
  jq -n --arg r "$r" \
    '{label: "Stub late", kind: "agent", login: ["claude"], preflight: "true", run: $r, fired: "any(.type == \"done\")", tokens: "map(.tokens // 0) | add", sessions: 1}' > "$SWE_FX/arms/stub-late.json" \
    || fail "the arm was not made"
  swetimeout1; swedocker 'case "$*" in *SWE_SB=*/work/*"git add -A"*) sleep 3 ;; esac' # sleep: the slow read of the change, longer than the arm takes to write late
  o=$(loop bench swe 1 --arm stub-late 2>&1) || fail "the run failed: $o"
  p=$(echo "$B"/results/stub-late*/"$first.patch")
  jq -e '.timedOut == true' "$B"/results/stub-late*/"$first.json" > /dev/null && grep -q '^+fixed' "$p" \
    || fail "the trial of stub-late on $first did not reach its 1 s limit with x.py fixed: $(cat "$B"/results/stub-late*/"$first.json" "$p" 2>&1) $o"
  ! grep -q late "$p" || fail "the graded patch of stub-late on $first holds late.py, written 2 s after its 1 s limit: $(cat "$p")"
}

# Bug (#1454 R155, review E3): when a conveyor arm's docker client ended at its time limit, swe_watch read its
# container once more while the engine went on there, and the engine was stopped only after that read, so a fix it
# landed in that time was graded. The engine holds ($SWE_FX/hold) past its 1 s limit (swetimeout1); a swe_watch read
# once the trial's host process has ended lets it go and waits for it to end: an engine still running lands "fixed".
# loop: only a whole run gives the trial's command its time limit, watches it and grades the patch read after it.
t_swetriallatecv() {
  swe; local first o
  first=$(sweorder | head -n 1); : > "$SWE_FX/hold"; swetimeout1
  swedocker 'case "$*" in *"tail -n 200"*) p=$(cat "$SWE_FX/trial" 2>/dev/null); if [ -n "$p" ] && ! kill -0 "$p" 2>/dev/null; then rm -f "$SWE_FX/hold"
    e=$(cat "$SWE_FX/pid" 2>/dev/null); i=0; while [ -n "$e" ] && kill -0 "$e" 2>/dev/null && [ $i -lt 100 ]; do sleep 0.1; i=$((i + 1)); done; fi ;; esac' # sleep: the stand-in's read holds swe_watch at its weak point while an engine still running lands
  o=$(loop bench swe 1 2>&1) || fail "the run failed: $o"
  [ -s "$SWE_FX/pid" ] && [ -s "$SWE_FX/trial" ] || fail "the trial's engine did not start under its 1 s limit: $o"
  jq -e '.resolved == false' "$B"/results/*/"$first.json" > /dev/null && ! grep -q fixed "$B"/results/*/"$first.patch" \
    || fail "the trial on $first graded the fix its engine landed after its 1 s limit, while swe_watch read its container: $(cat "$B"/results/*/"$first.patch" 2>&1) $o"
}
