#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 120
# Engine cases: a release's suite runs its test files in the mode chosen for the run (release-prep and release-run
# --parallel or --serial, serial by default; docs/releases.md), with this repository's suite command,
# .conveyor/test-full.sh. Their fixture is modesetup, below, on releaseboard.test.sh's runsetup (release.test.sh's
# cutsetup).
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"

# modesetup: runsetup, with the pack's test.full this repository's .conveyor/test-full.sh, committed, and four tracked
# test files t/f1 to t/f4 that each note in $STUB/times when they start and end, with a pause between, so two files run
# at once overlap. The suite's slots are a pool of two of the case's own (CONVEYOR_TEST_POOL, the case's slot of the
# runner's pool unset), so a busy machine's pool cannot make a parallel run serial, and four files on two slots show
# the limit of files at once. Sets POOL.
modesetup() {
  local i
  runsetup true
  tune '.test.full = "bash .conveyor/test-full.sh"'
  mkdir -p "$R/t" && cp "$SRC/../.conveyor/test-full.sh" "$SRC/../.conveyor/test-share.sh" "$R/.conveyor/" || fail "the fixture could not be made"
  POOL=2:$T/$CASE/pool
  # Each start line also names the pool slot the file was started on, "none" when it holds none: the slot file that
  # CONVEYOR_TEST_SLOT's descriptor is open on (a turn on the run's home slot, <fd>.t, names the home slot's descriptor).
  for i in 1 2 3 4; do
    printf '%s\n' "p=${POOL#2:}" 'd=${CONVEYOR_TEST_SLOT:-}; d=${d%%.*}; k=none; for s in 1 2; do [ -n "$d" ] && [ "/dev/fd/$d" -ef "$p/$s" ] && k=$s; done' \
      'echo "$0 start $EPOCHREALTIME $k" >> "$STUB/times"' 'sleep 0.5' 'echo "$0 end $EPOCHREALTIME" >> "$STUB/times"' > "$R/t/f$i.test.sh" # sleep: a stand-in test file that runs a while, so files run at once overlap
  done
  git -C "$R" add -f .conveyor/test-full.sh .conveyor/test-share.sh t && git -C "$R" commit -qm 'the suite' && git -C "$R" push -q origin main || fail "the fixture could not be made"
}
# The most of the four files that ran at once, from $STUB/times; fails unless each file started and ended once.
atonce() {
  [ "$(awk '{ print $1, $2 }' "$STUB/times" 2>/dev/null | sort | paste -sd' ' -)" = "t/f1.test.sh end t/f1.test.sh start t/f2.test.sh end t/f2.test.sh start t/f3.test.sh end t/f3.test.sh start t/f4.test.sh end t/f4.test.sh start" ] \
    || fail "the suite did not run each of the four files once: $(cat "$STUB/times" 2>&1)"
  tr , . < "$STUB/times" | sort -k3,3g | awk '$2 == "start" { n++; if (n > m) m = n } $2 == "end" { n-- } END { print m + 0 }'
}
# Bug: the suite ran one test file at a time while most of the machine's cores stood idle (release 1.6.0: about 3.4
# of 16 busy). In parallel mode, chosen on the Board's release-run, files run at once, each file's result line is in
# the output, and the record says the mode.
t_relparallel() {
  local RUN out wt=$T/$CASE/cards/release/wt f
  modesetup
  # Bug: the suite was not told the suite record, so it started its files in list order, the longest last. The record
  # times f4 and f3 longest: they start first.
  mkdir -p "$ST" && jq -cn '{time: "2026-11-01T00:00:00Z", how: "release", sha: "", files: {"t/f1.test.sh": {result: "ok", sec: 1, cpu: 1},
    "t/f2.test.sh": {result: "ok", sec: 2, cpu: 2}, "t/f3.test.sh": {result: "ok", sec: 30, cpu: 30}, "t/f4.test.sh": {result: "ok", sec: 40, cpu: 40}}}' > "$ST/suiteruns.jsonl"
  out=$(unset CONVEYOR_TEST_SLOT; CONVEYOR_TEST_POOL=$POOL loop release-run prep 1.1.0 --parallel 2>&1) || fail "release-run prep --parallel did not start the run: $out"
  # release-run starts release-prep in the background and returns: its record is where the run's end shows.
  relwait "the run did not end" '.ended != null'
  jq -e '.state == "passed" and .mode == "parallel"' "$RUN" > /dev/null || fail "the parallel run did not pass with mode parallel in its record: $(cat "$RUN") $(cat "$T/$CASE/cards/release/run.log")"
  # Bug (#1174): the record did not say how many files ran at once. The control record has no suiteAtOnce: 2, the
  # default, on a pool of two slots.
  jq -e '.atOnce == 2' "$RUN" > /dev/null || fail "the parallel run's record does not name the 2 files it ran at once: $(cat "$RUN")"
  for f in 1 2 3 4; do grep -qxF -- "-- ok t/f$f.test.sh" "$wt.test" || fail "the suite's output has no result line of t/f$f.test.sh: $(cat "$wt.test")"; done
  # Two exactly: files ran at once, and never more than the pool's two slots.
  [ "$(atonce)" = 2 ] || fail "the four files did not run two at once on a pool of two slots: $(cat "$STUB/times")"
  # The two started first, in either order, as both start at once.
  [ "$(tr , . < "$STUB/times" | awk '$2 == "start"' | sort -k3,3g | head -2 | awk '{ print $1 }' | sort | paste -sd' ' -)" = "t/f3.test.sh t/f4.test.sh" ] \
    || fail "the two files the suite record times longest did not start first: $(cat "$STUB/times")"
  # Bug: a scheduler that kept to two files at once but took no slot for each (no slot_take, slot_mine, slot_free)
  # still passed the checks above: its files all ran on the run's own slot, beside each other, while other cards took
  # the slots and cores the run used. Each file starts on a slot of the pool, and no two files at once on the same one.
  tr , . < "$STUB/times" | sort -k3,3g | awk '$2 == "start" { if ($4 != 1 && $4 != 2) bad = bad " " $1 " held no slot of the pool;"
      for (f in on) if (on[f] == $4) bad = bad " " $1 " and " f " held slot " $4 " at once;"; on[$1] = $4 }
    $2 == "end" { delete on[$1] } END { if (bad != "") { print bad; exit 1 } }' > "$T/$CASE/slots" \
    || fail "the files did not each hold a slot of their own:$(cat "$T/$CASE/slots") $(cat "$STUB/times")"
}
# Bug: a run with no mode chosen ran its files at once, though serial is the default. Each file runs alone.
t_relserial() {
  local RUN out SUITE line
  modesetup
  # Bug (#1174): a setting of files at once reached serial mode. It is 4 here, and serial runs one, its record's atOnce.
  jq -c '.suiteAtOnce = 4' "$ST/control.json" > "$STUB/c.new" && mv "$STUB/c.new" "$ST/control.json" || fail "the fixture could not be made"
  out=$(unset CONVEYOR_TEST_SLOT; CONVEYOR_TEST_POOL=$POOL loop release-prep 1.1.0 2>&1) || fail "release-prep failed: $out"
  jq -e '.state == "passed" and .mode == "serial" and .atOnce == 1 and .reasons == []' "$RUN" > /dev/null || fail "the serial run did not pass with mode serial, atOnce 1 and no reason in its record: $(cat "$RUN")"
  # Bug: a bash warning on the run's stderr was a passed run's reason, and the Foreman's watcher woke on "release
  # 1.6.0 passed on <commit> at <time>: <the warning>". The watcher's own line for the record ends at the time.
  eval "$(sed -n "/^SUITE='/,/end;'\$/p" "$SRC/foreman/watch-conveyor.sh")"
  line=$(jq -r --argjson now 0 "$SUITE"'suiteline($now)' "$RUN") && [ "$line" = "release 1.1.0 passed on $(jq -r '"\(.sha[0:12]) at \(.ended)"' "$RUN")" ] \
    || fail "the watcher's line for the passed run is not its result, commit and time alone: $line"
  [ "$(atonce)" = 1 ] || fail "two files ran at once in serial mode: $(cat "$STUB/times")"
}
# release-run <flags> with the control record's suiteMode <rule> (none: the record has no suiteMode), then waits for the
# run's end. The whole run is started, as the mode is what the release-prep it starts is given and records.
moderun() { # <rule: serial | parallel | none> [<flag>]
  local out
  modesetup
  [ "$1" = none ] || { jq -c --arg m "$1" '.suiteMode = $m' "$ST/control.json" > "$STUB/c.new" && mv "$STUB/c.new" "$ST/control.json" || fail "the fixture could not be made"; }
  out=$(unset CONVEYOR_TEST_SLOT; CONVEYOR_TEST_POOL=$POOL loop release-run prep 1.1.0 ${2:+"$2"} 2>&1) || fail "release-run prep ${2:-} with suiteMode $1 did not start the run: $out"
  relwait "the run did not end" '.ended != null'
}
# Bug (#1364): a release-run given no mode ran its suite one by one, though the project's rule is parallel: release-run
# passed --serial for the mode it was not given. With suiteMode parallel and no flag, it runs in parallel.
t_relmoderule() {
  local RUN
  moderun parallel
  jq -e '.state == "passed" and .mode == "parallel" and .atOnce == 2' "$RUN" > /dev/null || fail "release-run prep with suiteMode parallel and no flag did not run in parallel: $(cat "$RUN") $(cat "$T/$CASE/cards/release/run.log")"
  [ "$(atonce)" = 2 ] || fail "release-run prep with suiteMode parallel and no flag did not run two files at once: $(cat "$STUB/times")"
}
# A flag given wins for that run: --serial over suiteMode parallel runs one by one.
t_relmodeflag() {
  local RUN
  moderun parallel --serial
  jq -e '.state == "passed" and .mode == "serial" and .atOnce == 1' "$RUN" > /dev/null || fail "release-run prep --serial with suiteMode parallel did not run one by one: $(cat "$RUN") $(cat "$T/$CASE/cards/release/run.log")"
  [ "$(atonce)" = 1 ] || fail "release-run prep --serial with suiteMode parallel ran two files at once: $(cat "$STUB/times")"
}
# A record with no suiteMode keeps today's behaviour: release-run with no flag runs one by one.
t_relmodenone() {
  local RUN
  moderun none
  jq -e '.state == "passed" and .mode == "serial" and .atOnce == 1' "$RUN" > /dev/null || fail "release-run prep with no suiteMode and no flag did not run one by one: $(cat "$RUN") $(cat "$T/$CASE/cards/release/run.log")"
}
# The stored setting of files at once (#1174) reaches a parallel suite, and `release-run atonce` prints it, at most
# the slots. Bugs: release-prep did not tell the suite the setting, so it ran at the suite's own default of 2; a whole
# number written 1.0 (or 4.0), which the control record keeps, stopped the run, as bash arithmetic reads no 1.0. A
# whole release-prep runs here, as only the suite's files running side by side show how many it was told to run at
# once.
t_relatonce() {
  local RUN out
  modesetup
  jq -c '.suiteAtOnce = 9' "$ST/control.json" > "$STUB/c.new" && mv "$STUB/c.new" "$ST/control.json" || fail "the fixture could not be made"
  out=$(unset CONVEYOR_TEST_SLOT; CONVEYOR_TEST_POOL=$POOL loop release-run atonce 2>&1) && [ "$out" = 2 ] \
    || fail "release-run atonce with suiteAtOnce 9 on a pool of two slots did not print 2: $out"
  jq -c '.suiteAtOnce = 1.0' "$ST/control.json" > "$STUB/c.new" && mv "$STUB/c.new" "$ST/control.json" || fail "the fixture could not be made"
  out=$(unset CONVEYOR_TEST_SLOT; CONVEYOR_TEST_POOL=$POOL loop release-run atonce 2>&1) && [ "$out" = 1 ] \
    || fail "release-run atonce with suiteAtOnce 1.0 did not print 1: $out"
  out=$(unset CONVEYOR_TEST_SLOT; CONVEYOR_TEST_POOL=$POOL loop release-prep 1.1.0 --parallel 2>&1) || fail "release-prep --parallel with suiteAtOnce 1.0 failed: $out"
  jq -e '.state == "passed" and .mode == "parallel" and .atOnce == 1' "$RUN" > /dev/null || fail "the parallel run with suiteAtOnce 1.0 did not pass with atOnce 1 in its record: $(cat "$RUN")"
  [ "$(atonce)" = 1 ] || fail "the parallel run with suiteAtOnce 1.0 ran more than one file at once on a pool of two slots: $(cat "$STUB/times")"
}
