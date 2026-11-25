#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 300
# Engine cases: one Conveyor per machine (`conveyor.sh machine`): what it and a case that started it leave running when
# they end, the lines it says once, the machine's pause and the engine each project runs on. project() and dispatch()
# are lib.sh's.
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"
# The engine folder, as lib.sh sets it: named here too, so the release closure (tools/closure.sh) follows this file's paths.
SRC=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)

# One machine's Conveyor over one project, solo, with issue #1 (or the issues given), started in the background: sets
# S (solo's main checkout) and mp (the machine's Conveyor), its output in $SH/machine.out. With lines given, the
# card's session runs them before its build.
# shellcheck disable=SC2154 # P_solo is set by project(), with printf -v
machine1() { # [issues json] [lines] [notest]
  SH=$T/$CASE/shared; mkdir -p "$SH"; export XDG_CONFIG_HOME=$T/$CASE/config # the machine's folder is the case's own
  project solo "${1:-[$(issue 1 2026-01-01)]}"
  dispatch; watchturns
  S=$P_solo; mkdir -p "$XDG_CONFIG_HOME/conveyor"
  # notest: main has no test file (the per-file fixture's a.test.sh is taken out), so the loop's idle mutation check
  # (mutnext(), lib/mutate.sh) has none to check and writes no line: for a case that counts every line of the output.
  [ -z "${3:-}" ] || { git -C "$S" rm -q a.test.sh && git -C "$S" commit -qm 'no test file'; } || fail "main's a.test.sh could not be taken out"
  [ -z "${2:-}" ] || { printf '%s\n' "$2" "$(cat "$STUB/build")" > "$SH/build" && mv "$SH/build" "$STUB/build"; }
  jq -n --arg s "$S" '{records: [{repo: "so_lo.1", main: $s}]}' > "$XDG_CONFIG_HOME/conveyor/host.json"
  ( cd "$S" && CONVEYOR_MAIN=$S exec bash "$SRC/conveyor.sh" machine > "$SH/machine.out" 2>&1 ) & mp=$!
}
# <pid>...: those of them that still run (one that has ended and is not waited for yet does not), each with its command.
running() { ps -o pid=,stat=,args= -p "$(IFS=,; echo "$*")" 2>/dev/null | awk '$2 !~ /Z/'; }

# What the case inside t_machineleft and t_machinekilled starts (run_case's "t_$CASE": left_killed, left_stays; no
# case of the runner's, their names are not a case's), under a scratch folder $d/in of the case that runs it: a
# machine's Conveyor building a card; a `serve` under `timeout`, as cases start one (it is in timeout's group, with
# nothing over it that is told to end); and, on Linux, a `serve` that has left all the case could be known by: a
# session of its own (setsid), the case's mark out of its environment, no parent. Writes them and all under them to
# $d/all, the conveyor.sh processes among them to $d/procs, their process groups to $d/groups and the case's own to
# $d/group.
# shellcheck disable=SC2154 # P_far is set by project(), with printf -v
left_start() {
  local d=${T%/in} sp far=''
  # The card's session holds until it is killed: the project's own build ends on its own after 600 waits of 0.1 s,
  # and on a loaded machine the starts below took longer, so the session had ended (and its process group with it)
  # before the groups were listed. For the same reason the `serve` under timeout starts last, just before they are.
  machine1 '' ': > "${STUB%/solo/stub}/shared/run/solo-1"; while :; do sleep 1; done' # sleep: a session held until killed
  wait_until '[ -e "$SH/run/solo-1" ]' || fail "#1 did not start: $(cat "$SH/machine.out")"
  if [ "$(uname -s)" = Linux ]; then
    project far '[]'
    CONVEYOR_MAIN=$P_far CONVEYOR_CARDS=$T/$CASE/far-cards setsid env -u CONVEYOR_TEST_CASE_ID \
      bash -c 'echo $$ > "$1"; exec bash "$2" serve > "$3" 2>&1' _ "$d/far" "$SRC/conveyor.sh" "$SH/far.out" &
    turns 1 "$P_far"; far=$(cat "$d/far")
    [ "$(ps -o sid= -p "$far" | tr -d ' ')" != "$(ps -o sid= -p "$BASHPID" | tr -d ' ')" ] || fail "the serve under setsid is in the case's session"
    ! tr '\0' '\n' < "/proc/$far/environ" | grep -q '^CONVEYOR_TEST_CASE_ID=' || fail "the serve under setsid has the case's mark in its environment"
  fi
  project side '[]'
  # shellcheck disable=SC2154 # P_side is set by project(), with printf -v
  ( export CONVEYOR_MAIN=$P_side CONVEYOR_CARDS=$T/$CASE/side-cards; exec timeout 120 bash "$SRC/conveyor.sh" serve > "$SH/serve.out" 2>&1 ) & sp=$!
  turns 1 "$P_side"
  { below "$mp"; below "$sp"; [ -z "$far" ] || below "$far"; } > "$d/all"
  for p in $(cat "$d/all"); do running "$p" | grep -q 'conveyor\.sh' && echo "$p"; done > "$d/procs"
  ps -o pgid= -p "$(paste -sd, "$d/all")" | tr -d ' ' | sort -u > "$d/groups"; ps -o pgid= -p "$BASHPID" | tr -d ' ' > "$d/group"
}
t_left_killed() { left_start; kill -KILL "$BASHPID"; }
t_left_stays() { left_start; : > "${T%/in}/ready"; while :; do sleep 1; done; } # sleep: the case goes on until it is killed
# That the case inside listed what it started: the machine's Conveyor, the project's loop and the card it builds, and
# the `serve` under timeout, at least, and the `serve` under setsid on Linux; the loop and the session under the
# machine's Conveyor, and the two `serve`, each in a process group that is not the case's.
left_listed() {
  local d=$T/$CASE n=4 g
  [ "$(uname -s)" != Linux ] || n=5
  [ "$(wc -l < "$d/procs")" -ge "$n" ] || fail "the case inside did not list its conveyor.sh processes: $(cat "$d/procs")"
  g=$(grep -cvxF -f "$d/group" "$d/groups"); [ "$g" -ge $((n - 1)) ] || fail "the loop and the session under the machine's Conveyor, and each serve, did not leave the case's process group: $(cat "$d/group" "$d/groups")"
}

# Bug: a case that started `conveyor.sh machine` in the background and was killed before its exit trap ran (the
# runner's timeout) left the machine's Conveyor, its loop and its card running: they wrote on for hours to a file of
# the deleted scratch folder until /tmp was full, and every card's tests on the machine failed. A case killed with
# KILL, with all left_start starts running: when its worker (run_case, as the runner starts it) has reported it, no
# conveyor.sh process of it runs, nor any other process it started: those that are not in the case's process group
# (each loop and session is a group of its own), and the one that is in nothing of the case's, are ended all the same.
# shellcheck disable=SC2046 # the files hold one pid a line: each pid is its own argument to running()
t_machineleft() {
  local d=$T/$CASE; mkdir -p "$d/in"
  ( T=$d/in; CASE=left_killed; run_case ) > "$d/report" 2>&1
  [ "$(cat "$d/in/left_killed.rc")" = 137 ] || fail "the case inside was not killed while its machine's Conveyor ran: $(cat "$d/report")"
  left_listed
  [ -z "$(running $(cat "$d/procs") | grep 'conveyor\.sh')" ] || fail "conveyor.sh processes of a killed case run on after it is reported: $(running $(cat "$d/procs"))"
  [ -z "$(running $(cat "$d/all"))" ] || fail "processes of a killed case that left its process group run on after it is reported: $(running $(cat "$d/all"))"
}

# Bug: a runner killed with its workers by a signal none of them can catch (KILL to the runner's process group) ended
# no case: the workers' own ending of their cases never ran, and each case, a process group of its own, ran on with
# its loops. A worker's process group killed with KILL while its case runs, with all left_start starts: nothing of
# the case runs soon after (its keeper, in no group of the runner's, sees the worker gone).
t_machinekilled() {
  local d=$T/$CASE w; mkdir -p "$d/in"
  set -m; ( T=$d/in; CASE=left_stays; run_case ) > "$d/report" 2>&1 & w=$!; set +m
  wait_until '[ -e "$d/ready" ]' || fail "the case inside did not start: $(cat "$d/report" "$d/in/left_stays.out")"
  left_listed
  kill -KILL -- "-$w"; wait "$w" 2>/dev/null
  WAIT_CEILING=20 wait_until '[ -z "$(running $(cat "$d/all"))" ]' 'running $(cat "$d/all")' || fail "processes of a case run on after its worker's process group was killed"
  [ ! -e "$d/in/left_stays.rc" ] || fail "the case inside ended on its own, not with its worker: $(cat "$d/in/left_stays.rc")"
}

# Bug: `conveyor.sh machine` given TERM ended, and the project's loop with it, while the cards the loop was building
# and their sessions ran on with no loop over them; or a process that a session started on that TERM, before it ended
# itself, ran on: it is under nothing the machine's Conveyor knew, and one started in a session of its own (setsid)
# is in no process group it knew either. TERM with a card's session running, which on TERM starts a process that
# ignores TERM (its pid in $SH/spawned) and one in a session of its own (with an empty environment too on Linux,
# where it is found whatever it carries; both pids in $SH/spawned) and ends: within 10 s nothing that ran under the
# machine's Conveyor does, nor do the processes started on TERM.
t_machineterm() { term_ends; }
term_ends() {
  local all pre
  pre=$(cat <<'EOF2'
deaf() { trap "" TERM; while :; do sleep 1; done; } # sleep: a stand-in that goes on until it is killed
apart() { python3 -c 'import subprocess, sys; print(subprocess.Popen(["sleep", "60"], start_new_session=True, env={} if sys.platform == "linux" else None).pid)'; }
trap 'deaf & { echo $!; apart; } > "$STUB/spawned" && mv "$STUB/spawned" "${STUB%/solo/stub}/shared/spawned"; exit' TERM
EOF2
  )
  machine1 '' "$pre"
  wait_until '[ -e "$SH/run/solo-1" ]' || fail "#1 did not start: $(cat "$SH/machine.out")"
  # A card id holds its project's name in letters, digits and hyphens only: with a dot or an underscore in it, the
  # reader of the card a card resumes (jq/rows.jq, from) cuts the id short and the time of its earlier tries is lost.
  jq -se 'length > 0 and all(.card | test("^c[0-9]{8}T[0-9]{6}-so-lo-1-[0-9]+$")) and all(.repo == "so_lo.1")' "$S/conveyor/state/cards.jsonl" >/dev/null \
    || fail "a card id carries the project's name as written: $(jq -sc 'map(.card) | unique' "$S/conveyor/state/cards.jsonl")"
  all=$(below "$mp")
  running $all | grep -q 'stub/claude' || fail "no session of #1 runs under the machine's Conveyor: $(running $all)"
  kill -TERM "$mp"
  # One wait, of 10 s from the TERM: for the session's process started on it, and for that and all the others gone.
  WAIT_CEILING=10 wait_until '[ "$(wc -l < "$SH/spawned")" = 2 ] && [ -z "$(running $all $(cat "$SH/spawned"))" ]' 'cat "$SH/spawned"; running $all $(cat "$SH/spawned")' \
    || fail "10 s after its TERM, the machine's Conveyor has not passed it on to the session (which then starts a process), or it, a process under it, or the one started on its TERM, still runs"
}

# Bug: the machine's Conveyor took a variable of its environment (CONVEYOR_MACHINE_KEPT) as its word that it was the
# reaper of all it starts, so one started with that variable set (whoever starts it sets its environment) was not: the
# process a session started on TERM in a session of its own, with an empty environment, was under nothing the
# machine's Conveyor could find, and ran on after it. t_machineterm's TERM, with that variable set: the same end.
t_machinekept() { export CONVEYOR_MACHINE_KEPT=1; term_ends; }

# Bug: a loop held back wrote why at every turn, the same line each time, so the output of the machine's Conveyor
# grew for as long as it ran (a pack that does not read holds every turn's push and pick: one line a second). Held
# for many turns by the same reason, the loop says it once; and once more when it holds the loop again later.
t_machinesame() {
  local said="so_lo.1: conveyor pack: .*project.json: no such file" pj
  machine1 '[]' '' notest; pj=$S/.conveyor/project.json
  said() { grep -c "^$said" "$SH/machine.out"; }
  turns 2 "$S"
  # The pack is taken away between two turns (atturn), here and below: taken in a turn, after the check that says
  # why the loop holds, that turn's pick read it again and wrote that it does not read, one more line of the reason.
  atturn "[ ! -e $(printf %q "$pj") ] || mv $(printf %q "$pj") $(printf %q "$SH/pack")"; turns 1 "$S"
  wait_until '[ "$(said)" -ge 1 ]' || fail "the loop does not say its pack does not read: $(cat "$SH/machine.out")"
  turns 6 "$S"
  [ "$(said)" = 1 ] || fail "held for 6 turns by one reason, the loop said it $(said) times: $(cat "$SH/machine.out")"
  [ "$(wc -l < "$SH/machine.out")" = 1 ] || fail "the loop wrote more than the reason in those turns: $(cat "$SH/machine.out")"
  cp "$SH/pack" "$pj"; turns 2 "$S"
  atturn "rm -f $(printf %q "$pj")"; turns 1 "$S"
  wait_until '[ "$(said)" -ge 2 ]' || fail "the loop does not say that its pack, read again since, does not read once more: $(cat "$SH/machine.out")"
  turns 4 "$S"
  [ "$(said)" = 2 ] || fail "held a second time, the loop said its reason $(($(said) - 1)) times: $(cat "$SH/machine.out")"
  kill -TERM "$mp"; wait "$mp" 2>/dev/null
}

# Bug: the machine's Conveyor wrote that its host file's records are not understood at every turn for as long as the
# file did not read, the same line each time. A host file that does not read for many turns: said once; and once
# more when the file, read again since, does not read again.
t_machinehost() {
  local said="conveyor: the records of .*host.json are not understood" H
  machine1 '[]' '' notest; H=$XDG_CONFIG_HOME/conveyor/host.json
  said() { grep -c "^$said" "$SH/machine.out"; }
  turns 2 machine
  cp "$H" "$SH/host"; echo '{' > "$H"
  wait_until '[ "$(said)" -ge 1 ]' || fail "the machine's Conveyor does not say its host file does not read: $(cat "$SH/machine.out")"
  turns 4 machine
  [ "$(said)" = 1 ] || fail "with a host file that did not read for 3 turns, the machine's Conveyor said so $(said) times: $(cat "$SH/machine.out")"
  [ "$(wc -l < "$SH/machine.out")" = 1 ] || fail "the machine's Conveyor wrote more than the reason in those turns: $(cat "$SH/machine.out")"
  cp "$SH/host" "$H"; turns 2 machine
  echo '{' > "$H"
  wait_until '[ "$(said)" -ge 2 ]' || fail "the machine's Conveyor does not say that its host file, read again since, does not read once more: $(cat "$SH/machine.out")"
  kill -TERM "$mp"; wait "$mp" 2>/dev/null
}

# Bugs: the whole machine could be paused only by editing the host file by hand, so the Board had no control for it;
# the Board could not say whether the machine is paused or what its cap is, as no record a project gives named them;
# a pause of the machine rewrote a project's own record, so resuming the machine resumed a project its owner paused.
# shellcheck disable=SC2154 # P_alpha and P_beta are set by project(), with printf -v
t_machinemode() {
  SH=$T/$CASE/shared; mkdir -p "$SH"; export XDG_CONFIG_HOME=$T/$CASE/config # the machine's folder is the case's own
  project alpha '[]'
  project beta '[]'
  local A=$P_alpha B=$P_beta H=$XDG_CONFIG_HOME/conveyor/host.json out
  loop() { CONVEYOR_MAIN=$1 bash "$SRC/conveyor.sh" "${@:2}"; }
  mkdir -p "${H%/*}"
  jq -n --arg a "$A" --arg b "$B" '{records: [{repo: "alpha", main: $a}, {repo: "beta", main: $b}], cap: 4}' > "$H"
  [ "$(loop "$A" health | jq -c .machine)" = '{"cap":4,"paused":false}' ] || fail "health does not name the machine's settings: $(loop "$A" health | jq -c .machine)"
  loop "$B" control pause >/dev/null || fail "beta's own pause was refused"
  out=$(loop "$A" machine pause) && grep -q "the machine's Conveyor is paused" <<<"$out" || fail "the machine's pause was refused: $out"
  [ "$(jq -c '[.mode, .cap, (.records | map(.repo))]' "$H")" = '["pause",4,["alpha","beta"]]' ] || fail "the pause is not the host file's mode, or it lost a setting or a record: $(cat "$H")"
  # Every project says the machine is paused; a project's own record is as it was.
  [ "$(loop "$A" health | jq -c '[.machine.paused, .machine.cap, .state]')" = '[true,4,"running"]' ] || fail "alpha does not say the machine is paused, or its own record changed: $(loop "$A" health | jq -c '{machine, state}')"
  [ "$(loop "$B" snapshot --fresh | jq -c '[.health.machine.paused, .health.state]')" = '[true,"paused"]' ] || fail "beta's snapshot does not say the machine is paused: $(loop "$B" snapshot --fresh | jq -c '.health | {machine, state}')"
  out=$(loop "$B" machine resume) && grep -q "the machine's Conveyor runs again" <<<"$out" || fail "the machine's resume was refused: $out"
  [ "$(jq -c '[has("mode"), .cap, (.records | length)]' "$H")" = '[false,4,2]' ] || fail "the resume did not take the mode away, or it lost a setting or a record: $(cat "$H")"
  [ "$(loop "$A" health | jq -c .machine.paused)" = false ] || fail "the machine still reads as paused after its resume"
  [ "$(loop "$B" health | jq -r .state)" = paused ] || fail "the machine's resume resumed beta, which its owner paused"
  # Bug: the pause was written under the machine's lock alone, and a lane's note replaces the host file under the
  # host file's own lock: a note that read the file before the pause wrote its older reading over it, and the machine
  # ran on. The pause waits for the host file's lock, so it reads what the note wrote.
  flock "$H.lock" sh -c 'touch "$1.held"; until [ -e "$1.go" ]; do sleep 0.1; done; jq ".noted = true" "$1" > "$1.note" && mv "$1.note" "$1"' sh "$H" & local lk=$!
  until [ -e "$H.held" ]; do sleep 0.1; done
  loop "$A" machine pause >/dev/null & local mp=$!
  # While the lock is held, the pause waits at it (its flock runs) and has neither ended nor written.
  wait_until 'under "$mp" flock || ! kill -0 "$mp" 2>/dev/null'; kill -0 "$mp" 2>/dev/null && [ "$(jq -r '.mode // "none"' "$H")" = none ] \
    || { touch "$H.go"; fail "the machine's pause did not wait for the host file's lock: $(cat "$H")"; }
  touch "$H.go"; wait "$mp" || fail "the machine's pause failed after waiting for the host file's lock"
  wait "$lk"; [ "$(jq -c '[.mode, .noted, .cap]' "$H")" = '["pause",true,4]' ] || fail "the pause or the other writer's change was lost: $(cat "$H")"
  loop "$A" machine resume >/dev/null || fail "the machine's resume was refused"
  # A host file that does not read is left as it is; anything but pause or resume is a usage error.
  echo '{"cap": 4' > "$H"
  ! loop "$A" machine pause >/dev/null 2>&1 && [ "$(cat "$H")" = '{"cap": 4' ] || fail "a host file that does not read was written over"
  jq -n '{}' > "$H"; out=$(loop "$A" machine stop 2>&1); [ $? = 2 ] && grep -q 'usage: conveyor.sh machine \[pause | resume\]' <<<"$out" || fail "machine stop is not a usage error: $out"
  # Issue 347: steer is removed, so `machine steer off` is a usage error and writes no steer to the host file.
  out=$(loop "$A" machine steer off 2>&1); [ $? = 2 ] && [ "$(jq -c . "$H")" = '{}' ] || fail "machine steer is still taken: $out $(cat "$H")"
  # No machine setting: the record's machine is null, as a host file that sets none caps and pauses nothing.
  jq -n --arg a "$A" '{records: [{repo: "alpha", main: $a}]}' > "$H"
  [ "$(loop "$A" health | jq -c .machine)" = null ] || fail "a host file that sets nothing reads as a machine setting: $(loop "$A" health | jq -c .machine)"
}

# Bug: the machine's Conveyor ran every project on its own engine, so the plugin's own belt (served from its checkout,
# its pack naming no plugin to follow or pin) could not run under it: its loop would run the machine's code for good,
# never its checkout's, and install-service left its per-project service running. A record run from its own checkout
# ("engine": "checkout") runs that checkout's conveyor.sh and restarts on the checkout's new code; any other record
# runs the machine's; a record whose engine changes is restarted on the other; an engine mistyped is not taken.
# shellcheck disable=SC2034 # h is read in the conditions wait_until evals
t_machinecheckout() {
  SH=$T/$CASE/shared; mkdir -p "$SH"; export XDG_CONFIG_HOME=$T/$CASE/config # the machine's folder is the case's own
  project alpha '[]'
  project beta '[]'
  dispatch
  local A=$P_alpha B=$P_beta H=$XDG_CONFIG_HOME/conveyor/host.json f h
  # alpha's checkout holds the engine (its conveyor/ beside its state folder), as the plugin's own checkout does.
  for f in "$SRC"/*; do [ "${f##*/}" = state ] || cp -r "$f" "$A/conveyor/" || fail "the engine was not copied into alpha's checkout"; done
  mkdir -p "${H%/*}"
  jq -n --arg a "$A" --arg b "$B" '{records: [{repo: "alpha", main: $a, engine: "checkout"}, {repo: "beta", main: $b}]}' > "$H"
  ( cd "$B" && CONVEYOR_MAIN=$B exec bash "$SRC/conveyor.sh" machine > "$SH/machine.out" 2>&1 ) & mp=$!
  trap 'kill -TERM $mp 2>/dev/null; wait $mp 2>/dev/null' EXIT
  ran() { jq -r ".$2 // empty" "$1/conveyor/state/loop.json" 2>/dev/null; } # <main> <field> of its loop's own record
  h=$(git -C "$A" rev-parse HEAD)
  wait_until '[ "$(ran "$A" checkout)" -ef "$A/conveyor" ] && [ "$(ran "$A" commit)" = "$h" ]' \
    || fail "alpha, run from its own checkout, does not run that checkout's code: $(cat "$A/conveyor/state/loop.json" 2>/dev/null) $(cat "$SH/machine.out")"
  wait_until '[ "$(ran "$B" checkout)" -ef "$SRC" ]' || fail "beta does not run the machine's own code: $(cat "$B/conveyor/state/loop.json" 2>/dev/null)"
  # beta has shown it; its loop stops, so it does not take its turns through the rest (alpha's record is as it was).
  jq 'del(.records[1])' "$H" > "$SH/h" && mv "$SH/h" "$H"
  # The checkout moves on: alpha's loop restarts on its new code, as a `serve` from a checkout does.
  git -C "$A" commit -q --allow-empty -m next && h=$(git -C "$A" rev-parse HEAD)
  wait_until '[ "$(ran "$A" commit)" = "$h" ] && [ "$(ran "$A" checkout)" -ef "$A/conveyor" ]' \
    || fail "alpha's loop did not restart on its checkout's new code: $(cat "$A/conveyor/state/loop.json") $(cat "$SH/machine.out")"
  # Its record no longer says so: its loop is stopped and runs the machine's code.
  jq '.records[0] |= del(.engine)' "$H" > "$SH/h" && mv "$SH/h" "$H"
  wait_until '[ "$(ran "$A" checkout)" -ef "$SRC" ]' || fail "alpha's loop did not move to the machine's code once its record dropped its engine: $(cat "$A/conveyor/state/loop.json")"
  # An engine mistyped: the records are not understood, and no loop runs on an engine its record does not name.
  jq '.records[0].engine = "chekout"' "$H" > "$SH/h" && mv "$SH/h" "$H"
  wait_until 'grep -q "conveyor: the records of .*host.json are not understood" "$SH/machine.out"' || fail "a mistyped engine was taken: $(cat "$SH/machine.out")"
}

# Bug (#1332): a card's build session started a test in the background, and its shell ended before the test did, so
# the test's parent was the machine's Conveyor (on Linux the reaper of all it starts). The session then sent TERM to
# that test and to its parent, which it took for a process of its own. The machine's Conveyor took that TERM for a
# stop of its service and ended, and its loop and every card in flight ended with it, with no line of its own. Under
# its service (a systemctl here that names it the service's main process, the service active), such a TERM is no
# stop: it says so, and the machine, its loop and the card's session go on. A TERM once the service is stopping ends it.
# Linux only: elsewhere no process is the reaper of what it starts, and the machine's service is not a systemd one.
t_machineparent() {
  [ "$(uname -s)" = Linux ] || return 0
  local n pre all
  # The card's session: it waits until the case knows the machine's pid, starts the background test, then TERMs it
  # and its parent.
  # shellcheck disable=SC2016 # run by the card's session
  pre='d=${STUB%/solo/stub}/shared; until [ -s "$d/mp" ]; do command sleep 0.1; done'
  # shellcheck disable=SC2016 # run by the card's session
  pre+=$'\n''( command sleep 600 & echo $! > "$d/stray" )' # sleep: the background test, which outlives the shell that started it
  # shellcheck disable=SC2016 # run by the card's session
  pre+=$'\n''q=$(ps -o ppid= -p "$(cat "$d/stray")" | tr -d " "); echo "$q" > "$d/strayparent"; kill -TERM "$q" "$(cat "$d/stray")"; : > "$d/killed"'
  machine1 '' "$pre"
  printf '#!/usr/bin/env bash\nprintf "ActiveState=%%s\\nMainPID=%%s\\n" "$(cat %q)" "$(cat %q)"\n' "$SH/state" "$SH/mp" > "$SH/bin/systemctl" \
    && chmod +x "$SH/bin/systemctl" && echo active > "$SH/state" && echo "$mp" > "$SH/mp" || fail "the systemctl of the case could not be made"
  # The polls: the bug is one of a running machine with a card's session under it. Only there is the machine the
  # parent of the process the session left (the reaper of all it starts), so the session's TERM reaches it, and only
  # there can its loop and that session be seen to go on after it; a call of machinenostop shows neither. Each poll
  # fails after its ceiling.
  wait_until '[ -e "$SH/killed" ]' || fail "the card's session did not send its TERM: $(cat "$SH/machine.out")"
  [ "$(cat "$SH/strayparent")" = "$mp" ] || fail "the process the session started did not have the machine's Conveyor ($mp) as its parent once its shell ended: $(cat "$SH/strayparent")"
  n=$(grep -cx machine "$TURNS")
  # The poll: two more turns of the machine show that it went on after the TERM; a machine that ends stops it at once.
  wait_until "[ \"\$(grep -cx machine '$TURNS')\" -ge $((n + 2)) ] || [ -z \"\$(running $mp)\" ]"
  [ -n "$(running "$mp")" ] || fail "the machine's Conveyor ended on the TERM a card's session sent to the parent of a process it had started: $(cat "$SH/machine.out")"
  mapfile -t all < <(below "$mp")
  [ -e "$SH/run/solo-1" ] && running "${all[@]}" | grep -q 'stub/claude' || fail "the card's session did not go on after that TERM: $(running "${all[@]}")"
  grep -q "^conveyor: the machine's Conveyor was sent TERM while its service conveyor-machine runs, so by no stop of the service: it goes on" "$SH/machine.out" \
    || fail "the machine's Conveyor did not say that it goes on after a TERM that was no stop: $(cat "$SH/machine.out")"
  echo deactivating > "$SH/state"; kill -TERM "$mp"
  # The poll: a TERM once the service stops ends the running machine, with its loop and the card's session.
  WAIT_CEILING=10 wait_until '[ -z "$(running "$mp")" ]' || fail "the machine's Conveyor did not end on a TERM while its service stops: $(cat "$SH/machine.out")"
  ! grep -q "Conveyor ends:" "$SH/machine.out" || fail "the machine's Conveyor said it ends on its stop: $(cat "$SH/machine.out")"
}

# The machine's Conveyor as `conveyor.sh machine` runs it (machineloop, in a shell of the engine), in the background,
# over one record whose main checkout is not there: its loop ends at once, and the machine says so at its next turn,
# a second later. Sets mp; its output is in $T/$CASE/out. The shell runs <commands> once the engine is loaded. It
# starts with INT and HUP as the service and a terminal give them (not ignored, as a job in the background of a script
# has INT and a run under nohup, as the suite on a box starts, has HUP, which bash cannot trap). On Linux it is first
# made the reaper of all it starts, as machineloop makes itself, so machineloop does not start conveyor.sh again,
# which the commands would not reach.
bare() { # [commands]
  local d=$T/$CASE w
  export XDG_CONFIG_HOME=$d/config; mkdir -p "$XDG_CONFIG_HOME/conveyor" && git init -q "$d/m" || fail "the case's checkout could not be made"
  jq -n --arg m "$d/gone" '{records: [{repo: "gone", main: $m}]}' > "$XDG_CONFIG_HOME/conveyor/host.json"
  w=(python3 -I -c 'import ctypes, os, signal, sys
signal.signal(signal.SIGINT, signal.SIG_DFL)
signal.signal(signal.SIGHUP, signal.SIG_DFL)
sys.platform != "linux" or ctypes.CDLL(None).prctl(36, 1) == 0 or sys.exit("prctl"); os.execvp(sys.argv[1], sys.argv[1:])')
  cat > "$d/machine.sh" <<'EOF'
. "$1/conveyor.sh" state-dir > /dev/null && eval "$(grep '^\. "\$HERE/lib/' "$1/commands/machine.sh")" || exit 9
MACHINE_POLL=1; eval "$2"; machineloop
EOF
  ( cd "$d/m" && CONVEYOR_MAIN=$d/m exec "${w[@]}" bash "$d/machine.sh" "$SRC" "${1:-}" ) > "$d/out" 2>&1 & mp=$!
}

# Bug (#1332): the machine's Conveyor that ended by itself said nothing of it: the journal showed its loop's last
# line, then the service's restart. Ended by an error (a variable it reads is not set, so under set -u the shell
# ends: the line that says its loop ended reads it), its last line names that error, its exit status and the command.
# The shell's own line for the error is the line before; a last line without the error left the cause off it.
t_machineerror() {
  local rc last
  bare 'unset MACHINE_RESTART'
  # The poll: a wait on a machine that does not end (the bug) would never return; this one fails after its ceiling.
  WAIT_CEILING=20 wait_until '[ -z "$(running "$mp")" ]' || fail "the machine's Conveyor did not end on its error: $(cat "$T/$CASE/out")"
  wait "$mp"; rc=$?; last=$(tail -n 1 "$T/$CASE/out")
  [ "$rc" = 1 ] || fail "the machine's Conveyor ended on its error with exit status $rc: $(cat "$T/$CASE/out")"
  # shellcheck disable=SC2016 # the command as the shell names it
  [[ $last == "conveyor: the machine's Conveyor ends: the shell's error \"MACHINE_RESTART: unbound variable\", exit status 1 at the command: echo \"conveyor: the loop of \$r ended;"*'${MACHINE_RESTART}'* ]] \
    || fail "the last line of the machine's Conveyor does not name the error it ended on, its exit status and the command: $(cat "$T/$CASE/out")"
}

# The machine's Conveyor (bare) sent <signal> once its first turn is over: it ends with <status>, and its last line
# names the signal.
sigend() { # <signal> <status> [unit: the signal goes to the machine's children too, its stderr reader among them]
  local rc
  bare
  # The poll: the signal goes to the running machine once its first turn is over (its traps are set before it), as
  # only a running process can show how it ends on it: it says its loop ended.
  wait_until 'grep -q "the loop of gone ended" "$T/$CASE/out"' || fail "the machine's Conveyor did not take its first turn: $(cat "$T/$CASE/out")"
  [ "${3:-}" != unit ] || kill "-$1" $(pgrep -P "$mp") 2>/dev/null
  kill "-$1" "$mp"
  # The poll: a wait on a machine that does not end on the signal would never return; this one fails after its ceiling.
  WAIT_CEILING=20 wait_until '[ -z "$(running "$mp")" ]' || fail "the machine's Conveyor did not end on $1: $(cat "$T/$CASE/out")"
  wait "$mp"; rc=$?
  [ "$rc" = "$2" ] && [ "$(tail -n 1 "$T/$CASE/out")" = "conveyor: the machine's Conveyor ends: it was sent SIG$1" ] \
    || fail "the machine's Conveyor ended on $1 with exit status $rc, its last line not naming the signal: $(cat "$T/$CASE/out")"
}

# Bug (#1332): ended by a signal that is not its stop (HUP, QUIT, USR1, USR2 or ALRM: here HUP), the machine's
# Conveyor ended at once and said nothing. It ends its loops as on TERM, and its last line names the signal.
t_machinehup() { sigend HUP 129; }

# Bug (#1332): on INT (Ctrl+C on `conveyor.sh machine`) the machine's Conveyor ended as on its stop, with no line.
# It ends its loops as on TERM, and its last line names the signal.
t_machineint() { sigend INT 130; }

# Bug it catches: the stderr reader trapped only TERM, INT and HUP, so a USR1 sent to the whole unit (a service
# manager's signal to all its processes) killed it with the machine; the machine's last line then had no reader to
# write it, and the exit cause was lost.
t_machineunit() { sigend USR1 138 unit; }
