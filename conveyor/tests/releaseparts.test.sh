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

# Bug (R178): the stop read the run's pid, then its version: a run that ended meanwhile, and a release-prep 1.2.0 whose
# record was written between the two reads, made the stop say the run of 1.2.0 was stopped. The kill that checks the
# pid writes that new record here; the stop names 1.1.0, the run it stopped, and leaves the new record as it is.
t_relpartstopversion() {
  setup '[]'; fakerun
  # shellcheck disable=SC2016 # expanded in the run's shell
  partrun 'kill() { [ "$1" != -0 ] || jq ".pid = 1 | .since = \"2099-01-01T00:00:00Z\" | .version = \"1.2.0\"" "$RELRUN" > "$RELRUN.new" && mv "$RELRUN.new" "$RELRUN"; builtin kill "$@"; }' \
    'releasestop'
  builtin kill "$FAKE" 2>/dev/null
  [ "$RC" = 0 ] && grep -qx 'conveyor: release-run: the release run of 1.1.0 is stopped' "$T/$CASE/run.out" && jq -e '.version == "1.2.0" and .ended == null' "$RUN" > /dev/null \
    || fail "the stop did not name 1.1.0, the run it stopped, or changed the next run's record (exit $RC): $(cat "$T/$CASE/run.out") $(cat "$RUN")"
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
