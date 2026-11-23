#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 120
# Engine cases: parts of a release run (commands/release-prep.sh) called on their own, with no suite or release run:
# the record a run starts from (relstart()), the scan for the run's processes (relprocs()), the stop of the mod's
# validate (relminver(), relsig()) and `release-run stop` (releasestop(), relstopwaiting() in lib/fulltest.sh).
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"
# The engine folder, as lib.sh sets it: named here too, so the release closure (tools/closure.sh) follows this file's paths.
SRC=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)

# partrun <script line>...: a bash of its own, in main's checkout, with release-prep.sh's functions loaded as
# conveyor.sh loads them, runs the lines (a run's traps and watcher are its own, as in a real run). Its output is in
# $T/$CASE/run.out and its exit in RC. RUN is the release record.
partrun() {
  RUN=$T/$CASE/cards/release/run.json
  # shellcheck disable=SC2016 # expanded in the run's shell
  mkdir -p "${RUN%/*}" && printf '%s\n' 'R=$CONVEYOR_MAIN; cd "$R" && . "$SRC/conveyor.sh" state-dir > /dev/null && eval "$(sed "/^shift\$/,\$d" "$SRC/commands/release-prep.sh")" || exit 9' \
    "$@" > "$T/$CASE/part.sh" || fail "the fixture could not be made"
  SRC=$SRC STUB=$STUB CONVEYOR_MAIN=$R CONVEYOR_CARDS=$T/$CASE/cards bash "$T/$CASE/part.sh" > "$T/$CASE/run.out" 2>&1; RC=$?
  [ "$RC" != 9 ] || fail "the engine could not be loaded: $(cat "$T/$CASE/run.out")"
}

# Bug (R172): release refused after a release-prep whose failed cases passed alone (flaky) started its next record with
# alone [], so a retry of the release on the same commit lost the flaky verdicts. The passed and failed release-prep
# records kept them; the refused release's record keeps them too.
t_relpartalone() {
  setup '[]'
  mkdir -p "$T/$CASE/cards/release" && jq -n '{kind: "release", step: "release", version: "1.1.0", since: "2026-01-01T00:00:00Z", ended: "2026-01-01T00:10:00Z",
    state: "refused", sha: "0123456789abcdef0123456789abcdef01234567", mode: "parallel", atOnce: 2, machine: null, done: 9, failed: 0, cases: [], reused: null,
    red: null, alone: [{case: "flips", verdict: "flaky", runs: ["ok", "ok", "ok"]}]}' > "$T/$CASE/cards/release/run.json" || fail "the fixture could not be made"
  partrun 'relstart release 1.1.0'
  [ "$RC" = 0 ] && jq -e '.state == "running" and .alone == [{case: "flips", verdict: "flaky", runs: ["ok", "ok", "ok"]}]' "$RUN" > /dev/null \
    || fail "the release retried after a refused one does not keep its flaky verdicts (exit $RC): $(cat "$RUN") $(cat "$T/$CASE/run.out")"
}

# Bug (R174): the scan for a run's processes looked for its mark anywhere in ps's line, arguments too, so a process
# that only had CONVEYOR_RELEASE_RUN=<mark> as an argument was taken for one of the run's, and a stop or the run's end
# signalled it. It is left out; a process with the mark in its environment is still found.
t_relpartmark() {
  setup '[]'
  local ls=()
  # shellcheck disable=SC2016 # expanded in the run's shell
  ls+=('m=4242$$; env -u CONVEYOR_RELEASE_RUN bash -c "sleep 60; :" _ "CONVEYOR_RELEASE_RUN=$m" & a=$!; CONVEYOR_RELEASE_RUN=$m sleep 60 & b=$!') # sleep: an unrelated process (the mark an argument of its bash) and a process of the run (the mark in its environment), which the case ends
  # shellcheck disable=SC2016 # expanded in the run's shell
  ls+=('for i in $(seq 100); do ps -o args= -p "$a" | grep -q " _ CONVEYOR_RELEASE_RUN=" && ps -o args= -p "$b" | grep -q "^sleep" && break; sleep 0.1; done') # sleep: until both run their programs, which only ps shows
  # shellcheck disable=SC2016 # expanded in the run's shell
  ls+=('out=$(relprocs 2147483646 "$m"); pkill -P "$a"; kill "$a" "$b"; echo "a=$a b=$b"; echo "found=$(paste -sd" " - <<<"$out")"')
  partrun "${ls[@]}"
  local a b; a=$(sed -n 's/^a=\([0-9]*\) b=.*/\1/p' "$T/$CASE/run.out"); b=$(sed -n 's/^a=[0-9]* b=\([0-9]*\)$/\1/p' "$T/$CASE/run.out")
  [ -n "$a" ] && [ -n "$b" ] && grep -qx "found=$b" "$T/$CASE/run.out" \
    || fail "relprocs did not find only the process with the mark in its environment ($b), not the one with it as an argument ($a): $(cat "$T/$CASE/run.out")"
}

# Bug: ps joins a process's environment entries with spaces, so a process whose other variable's value held
# " CONVEYOR_RELEASE_RUN=<mark> " read as one of the run's, and a stop or the run's end signalled it. Each entry is now
# read apart from the others (p_envhas: /proc on Linux, the kernel's sysctl on macOS), so it is left out.
t_relpartmarkvalue() {
  setup '[]'
  local ls=()
  # shellcheck disable=SC2016 # expanded in the run's shell
  ls+=('m=4243$$; env -u CONVEYOR_RELEASE_RUN OTHER="x CONVEYOR_RELEASE_RUN=$m y" sleep 60 & a=$!; CONVEYOR_RELEASE_RUN=$m sleep 60 & b=$!') # sleep: an unrelated process (the mark inside another variable's value) and a process of the run (the mark an entry of its own), which the case ends
  # shellcheck disable=SC2016 # expanded in the run's shell
  ls+=('for i in $(seq 100); do ps -o args= -p "$a" | grep -q "^sleep" && ps -o args= -p "$b" | grep -q "^sleep" && break; sleep 0.1; done') # sleep: until both run their programs, which only ps shows
  # shellcheck disable=SC2016 # expanded in the run's shell
  ls+=('out=$(relprocs 2147483646 "$m"); kill "$a" "$b"; echo "a=$a b=$b"; echo "found=$(paste -sd" " - <<<"$out")"')
  partrun "${ls[@]}"
  local a b; a=$(sed -n 's/^a=\([0-9]*\) b=.*/\1/p' "$T/$CASE/run.out"); b=$(sed -n 's/^a=[0-9]* b=\([0-9]*\)$/\1/p' "$T/$CASE/run.out")
  [ -n "$a" ] && [ -n "$b" ] && grep -qx "found=$b" "$T/$CASE/run.out" \
    || fail "relprocs did not find only the process with the mark as an entry of its own ($b), not the one with it inside OTHER's value ($a): $(cat "$T/$CASE/run.out")"
}

# Bug (R176): a stop while `claude plugin validate` ran left the plugin unpacked for it in the temporary folder: the
# stop's trap exits once validate returns, before the rm after it. The stand-in validate notes the folder it is given
# and sleeps until the case ends it, as a stop's reap does; the run then exits 143 and the folder is gone.
t_relpartvalidate() {
  local pkg
  setup '[]'
  mkdir -p "$R/.claude-plugin" "$R/hooks" && jq -n '{name: "p", version: "1.0.0", engines: {"claude-code": ">=1.0.0"}}' > "$R/.claude-plugin/plugin.json" \
    && echo 'export {}' > "$R/hooks/a.ts" && git -C "$R" add -A && git -C "$R" commit -qm 'the mod' || fail "the fixture could not be made"
  local c=$T/$CASE/cards/release/claude-code-1.0.0/node_modules/.bin/claude
  # shellcheck disable=SC2016 # expanded in the stub
  local v='echo $$ > "$STUB/validate.pid"; echo "$3" > "$STUB/pkg"; exec sleep 60' # sleep: a validate that runs until the stop ends it
  # stub: the oldest Claude Code as relminver() installs it in the cards folder (not on PATH, where the shared stub is): its version, and that validate
  mkdir -p "${c%/*}" && printf '%s\n' '#!/usr/bin/env bash' '[ "$1" != --version ] || { echo "1.0.0 (Claude Code)"; exit 0; }' "$v" > "$c" && chmod +x "$c" || fail "the fixture could not be made"
  # shellcheck disable=SC2016 # expanded in the run's shell
  ( partrun 'echo $$ > "$STUB/run.pid"; relstart release-prep 1.1.0; relminver release-prep "$(git rev-parse HEAD)"; echo "validate ended with no stop"'; echo "$RC" > "$STUB/rc" ) &
  # wait_until: the run starts validate in the background of this case; only its note shows when it has.
  wait_until '[ -s "$STUB/validate.pid" ] && [ -s "$STUB/pkg" ]' || fail "validate did not start: $(cat "$T/$CASE/run.out" 2>&1)"
  pkg=$(cat "$STUB/pkg")
  [ -d "$pkg" ] || fail "validate was not given the unpacked plugin: $pkg"
  # The stop: TERM to the run's bash, as relreap's, and to validate, which the reap ends too.
  kill -TERM "$(cat "$STUB/run.pid")" "$(cat "$STUB/validate.pid")" || fail "the stop's signals could not be sent"
  # wait_until: the run ends a moment after its validate does.
  wait_until '[ -s "$STUB/rc" ]' || fail "the run did not end after the stop"
  [ "$(cat "$STUB/rc")" = 143 ] && [ ! -e "$pkg" ] \
    || { rm -rf "$pkg"; fail "the stopped run did not exit 143 (it exited $(cat "$STUB/rc")), or left the unpacked plugin $pkg: $(cat "$T/$CASE/run.out")"; }
}

# A stand-in run under way for `release-run stop`: a process whose command line names conveyor.sh, as releasestop()
# requires of the record's pid, sleeping until the stop ends it, and its record (version 1.1.0) with the jq <changes>
# made to it. Its pid is in FAKE.
fakerun() { # [<jq changes>]
  ( exec -a "bash conveyor.sh release-run 1.1.0" sleep 60 ) & FAKE=$! # sleep: the stand-in run, ended by the stop
  RUN=$T/$CASE/cards/release/run.json
  mkdir -p "${RUN%/*}" && jq -n --argjson p "$FAKE" '{kind: "release", step: "release-prep", version: "1.1.0", since: "2026-01-01T00:00:00Z", ended: null,
    state: "running", sha: null, pid: $p, reasons: [], done: 0, failed: 0} | '"${1:-.}" > "$RUN" || fail "the fixture could not be made"
}

# The box's run of a stopped run, named in its record: a box over ssh whose run has not ended.
BOXREC='.machine = {kind: "ssh", name: "box.example.com", target: "tester@box.example.com", dir: "~/suite", lease: null, step: "run"}'

# Bug (R178): the stop read the run's pid, then its version: a run that ended meanwhile, and a release-prep 1.2.0 whose
# record was written between the two reads, made the stop say the run of 1.2.0 was stopped. The kill that checks the
# pid writes that new record here; the stop names 1.1.0, the run it stopped, and leaves the new record as it is.
# Bug: the stop read the record's machine with no check that the record was still the stopped run's, so the next run's
# suite on its box (the record's machine, kept in the new record here) was stopped too: the stop sends nothing to the
# box (hostssh).
# Bug: the stop then said the run was stopped (exit 0), while its suite on the box, sent no stop, still ran: it fails and
# says the box's suite is not stopped.
# Bug: it then said that suite goes on until it ends, while the next run's checkout on the same box (hostcheckout(),
# lib/suitehost.sh) stops it: it says that checkout can stop it.
t_relpartstopversion() {
  setup '[]'; fakerun "$BOXREC"
  # shellcheck disable=SC2016 # expanded in the run's shell
  partrun 'kill() { [ "$1" != -0 ] || jq ".pid = 1 | .since = \"2099-01-01T00:00:00Z\" | .version = \"1.2.0\"" "$RELRUN" > "$RELRUN.new" && mv "$RELRUN.new" "$RELRUN"; builtin kill "$@"; }' \
    'hostssh() { printf "%s\n" "$1" >> "$STUB/hostssh"; }' 'releasestop'
  builtin kill "$FAKE" 2>/dev/null
  [ "$RC" = 1 ] && grep -q "the release run of 1.1.0 is stopped, but not its suite's run on box.example.com" "$T/$CASE/run.out" \
    && grep -qF "goes on until it ends, or until a release run's checkout on box.example.com stops it" "$T/$CASE/run.out" && jq -e '.version == "1.2.0" and .ended == null and .machine.step == "run"' "$RUN" > /dev/null \
    && [ ! -e "$STUB/hostssh" ] \
    || fail "the stop did not name 1.1.0, the run it stopped, did not fail saying its box's suite was not stopped, changed the next run's record, or sent a stop to the next run's box (exit $RC; box commands: $(cat "$STUB/hostssh" 2>/dev/null)): $(cat "$T/$CASE/run.out") $(cat "$RUN")"
}

# Bug: a stop that could not take the release lock (a release-prep started next holds it) still sent the box its stop
# from the record it read before the next run wrote its own, so that run's suite on the same box could be stopped. The
# lock file opens, and its flock -w times out (the stub, for the 10 s wait): the stop sends nothing to the box
# (hostssh), fails, and says the box's suite is not stopped.
t_relpartstopboxnolock() {
  setup '[]'; fakerun "$BOXREC"
  # shellcheck disable=SC2016 # expanded in the run's shell
  partrun 'flock() { [ "$1" != -w ] && command flock "$@"; }' 'hostssh() { printf "%s\n" "$1" >> "$STUB/hostssh"; }' 'releasestop'
  builtin kill "$FAKE" 2>/dev/null
  [ "$RC" = 1 ] && [ ! -e "$STUB/hostssh" ] && grep -q "release/lock; .*the suite of the run on box.example.com is not stopped" "$T/$CASE/run.out" \
    || fail "release-run stop whose flock on the release lock timed out sent a stop to the box, did not fail, or did not say the box's suite is not stopped (exit $RC; box commands: $(cat "$STUB/hostssh" 2>/dev/null)): $(cat "$T/$CASE/run.out")"
}

# Bug: the stop sent the box its stop before it took the release lock, so a release-prep could start meanwhile and
# write its own record and box. The stop's box command (hostssh) notes whether the lock was free as it ran: it is held.
t_relpartstopboxlock() {
  setup '[]'; fakerun "$BOXREC"
  # shellcheck disable=SC2016 # expanded in the run's shell
  partrun 'hostssh() { if flock -n "$CARDS/release/lock" true; then echo free; else echo held; fi >> "$STUB/hostssh"; }' 'releasestop'
  builtin kill "$FAKE" 2>/dev/null
  [ "$RC" = 0 ] && [ "$(cat "$STUB/hostssh" 2>/dev/null)" = held ] \
    || fail "release-run stop of a run on a box did not send the box its stop once, holding the release lock (exit $RC; lock as the stop ran: $(cat "$STUB/hostssh" 2>/dev/null)): $(cat "$T/$CASE/run.out")"
}

# Bug (R179): a stop whose release lock could not be opened (here the lock's path is a folder) ended on bash's "lk:
# unbound variable", as conveyor.sh runs with set -u, and not with its own message.
t_relpartstoplock() {
  local out
  setup '[]'; fakerun
  mkdir -p "$T/$CASE/cards/release/lock" || fail "the fixture could not be made"
  out=$(loop release-run stop 2>&1); RC=$?
  kill "$FAKE" 2>/dev/null
  [ "$RC" = 1 ] && grep -q 'still holds .*release/lock' <<<"$out" && ! grep -q 'unbound variable' <<<"$out" \
    || fail "release-run stop with a lock that cannot be opened did not fail with its lock message (exit $RC): $out"
}

# Bug it catches: the same, for the stop of a run that waits on its release notes card (relstopwaiting()).
t_relpartstopwaitlock() {
  local out
  setup '[]'
  mkdir -p "$T/$CASE/cards/release/lock" && jq -n '{kind: "release", step: "release-prep", version: "1.1.0", since: "2026-01-01T00:00:00Z",
    ended: "2026-01-01T00:10:00Z", state: "waiting", restarted: null, notes: {card: "c1"}}' > "$T/$CASE/cards/release/run.json" || fail "the fixture could not be made"
  out=$(loop release-run stop 2>&1); RC=$?
  [ "$RC" = 1 ] && grep -q 'the record of release 1.1.0 could not be written' <<<"$out" && ! grep -q 'unbound variable' <<<"$out" \
    || fail "release-run stop of a waiting run with a lock that cannot be opened did not fail with its own message (exit $RC): $out"
}

# Bug (R181): a run stopped while its failed cases ran alone kept .counts, the suite's counts of that time, which the
# snapshot reads only of a run with no end, so the stopped record showed the counts of no run. The stop takes them
# into the record, as the run's own end does, and none is left.
t_relpartstopcounts() {
  local out
  setup '[]'; fakerun '.counts = {done: 40, failed: 2}'
  out=$(loop release-run stop 2>&1) || fail "the stop failed: $out"
  kill "$FAKE" 2>/dev/null
  jq -e '.state == "stopped" and (has("counts") | not) and .done == 40 and .failed == 2' "$RUN" > /dev/null \
    || fail "the stopped record keeps .counts, or not the suite's counts: $(cat "$RUN")"
}

# Bug (follow-up of #1461): the Board's Stop sent `release-run stop` with no version, so a Stop shown for 1.0.0, clicked
# once 1.0.0 had ended and 1.1.0 had started from a terminal, stopped the run of 1.1.0. `release-run stop 1.0.0` stops
# no run of 1.1.0: it fails, the run's process lives and its record is not marked stopped; `stop 1.1.0` stops it.
t_relpartstopother() {
  local out
  setup '[]'; fakerun
  out=$(loop release-run stop 1.0.0 2>&1); RC=$?
  kill -0 "$FAKE" 2>/dev/null || fail "release-run stop 1.0.0 ended the process of the run of 1.1.0: $out"
  [ "$RC" = 1 ] && grep -q 'under way is of 1.1.0, not 1.0.0; nothing stopped' <<<"$out" && jq -e '.state == "running" and .ended == null' "$RUN" > /dev/null \
    || { kill "$FAKE" 2>/dev/null; fail "release-run stop 1.0.0 of a run of 1.1.0 did not fail, or marked it stopped (exit $RC): $out; $(cat "$RUN")"; }
  out=$(loop release-run stop 1.1.0 2>&1) || { kill "$FAKE" 2>/dev/null; fail "release-run stop 1.1.0 of the run of 1.1.0 failed: $out"; }
  kill "$FAKE" 2>/dev/null
  jq -e '.state == "stopped"' "$RUN" > /dev/null || fail "release-run stop 1.1.0 did not mark the run of 1.1.0 stopped: $(cat "$RUN")"
}

# Bug: the same, for a run that waits on its notes card (relstopwaiting()): a late Stop of 1.0.0 ended the wait of 1.1.0.
t_relpartstopwaitother() {
  local out run=$T/$CASE/cards/release/run.json
  setup '[]'
  mkdir -p "${run%/*}" && jq -n '{kind: "release", step: "release-prep", version: "1.1.0", since: "2026-01-01T00:00:00Z",
    ended: "2026-01-01T00:10:00Z", state: "waiting", restarted: null, notes: {card: "c1"}}' > "$run" || fail "the fixture could not be made"
  out=$(loop release-run stop 1.0.0 2>&1); RC=$?
  [ "$RC" = 1 ] && grep -q 'that waits is of 1.1.0, not 1.0.0; nothing stopped' <<<"$out" && jq -e '.state == "waiting"' "$run" > /dev/null \
    || fail "release-run stop 1.0.0 of the wait of 1.1.0 did not fail, or ended the wait (exit $RC): $out; $(cat "$run")"
  out=$(loop release-run stop 1.1.0 2>&1) && jq -e '.state == "stopped"' "$run" > /dev/null \
    || fail "release-run stop 1.1.0 did not end the wait of 1.1.0: $out; $(cat "$run")"
}

# Follow-up of #1461. Bug it catches: the Board's Stop, sent while the panel showed the notes wait, reached the host after
# relfixes() had started that run again, and the stop killed the suite under way. The stop names the waiting run's
# start (2025-12-31T23:50:00Z here); the run under way began later, so it is not stopped and its record is left as it is.
t_relpartstopsincelive() {
  setup '[]'; fakerun
  partrun 'releasestop 2025-12-31T23:50:00Z'
  local alive=no; kill -0 "$FAKE" 2>/dev/null && alive=yes; kill "$FAKE" 2>/dev/null
  [ "$RC" = 1 ] && [ $alive = yes ] && jq -e '.state == "running" and .ended == null' "$RUN" > /dev/null && grep -q 'no longer waits' "$T/$CASE/run.out" \
    || fail "releasestop 2025-12-31T23:50:00Z, with the run of 2026-01-01T00:00:00Z under way, stopped it or did not refuse (exit $RC, run alive: $alive): $(cat "$RUN") $(cat "$T/$CASE/run.out")"
}

# Follow-up of #1461. Bug it catches: `release-run stop <since>`, the Board's Stop of a wait, is refused, or does not end
# the wait of the run that began at <since>.
t_relpartstopsincewait() {
  local out
  setup '[]'
  RUN=$T/$CASE/cards/release/run.json
  mkdir -p "${RUN%/*}" && jq -n '{kind: "release", step: "release-prep", version: "1.1.0", since: "2026-01-01T00:00:00Z",
    ended: "2026-01-01T00:10:00Z", state: "waiting", restarted: null, notes: {card: "c1"}}' > "$RUN" || fail "the fixture could not be made"
  out=$(loop release-run stop 2026-01-01T00:00:00Z 2>&1); RC=$?
  [ "$RC" = 0 ] && jq -e '.state == "stopped" and .reasons == ["stopped by the owner"]' "$RUN" > /dev/null \
    || fail "release-run stop 2026-01-01T00:00:00Z did not end the wait of the run that began then (exit $RC): $out $(cat "$RUN")"
}

# Follow-up of #1461. Bug it catches: a late Stop of the wait of the run that began at 2025-12-31T23:50:00Z ended the
# wait of a newer run (it started again, failed its notes check once more and now waits from 2026-01-01T00:00:00Z), so
# that run no longer starts when its notes card lands.
t_relpartstopsincenewer() {
  local out
  setup '[]'
  RUN=$T/$CASE/cards/release/run.json
  mkdir -p "${RUN%/*}" && jq -n '{kind: "release", step: "release-prep", version: "1.1.0", since: "2026-01-01T00:00:00Z",
    ended: "2026-01-01T00:10:00Z", state: "waiting", restarted: null, notes: {card: "c1"}}' > "$RUN" || fail "the fixture could not be made"
  out=$(loop release-run stop 2025-12-31T23:50:00Z 2>&1); RC=$?
  [ "$RC" = 1 ] && jq -e '.state == "waiting" and .since == "2026-01-01T00:00:00Z" and has("reasons") == false' "$RUN" > /dev/null && grep -q 'no longer waits' <<<"$out" \
    || fail "release-run stop 2025-12-31T23:50:00Z ended the wait of the run that began at 2026-01-01T00:00:00Z, or did not refuse (exit $RC): $out $(cat "$RUN")"
}
