#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 300
# Engine cases: the check run the snapshot shows (checks.progress, checkRun).
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"
# The engine folder, as lib.sh sets it: named here too, so the release closure (tools/closure.sh) follows this file's paths.
SRC=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)

# After setup: the pack's checks.progress prints $STUB/run.json (and notes each run in $STUB/ran). Each case is on a
# main of its own, so the two that wait out the command's 5 s (t_checkrunleft, t_checkrunbad) run beside the first.
# crjson prints what the snapshot's checkRun is made of: the engine's own checkrun() (lib/snapshot.sh), with the engine
# sourced as conveyor.sh sources it and the case's main. A whole snapshot for each look cost this file about 0.4 CPU s a
# look, over 20 looks, and took it past the 8 CPU s budget (#477): the snapshot is looked at whole only where what is
# proven is the snapshot's (no field without a progress command, the stream, the rest of a snapshot standing).
crpack() {
  tune --arg c "echo x >> $STUB/ran; cat $STUB/run.json" '.checks = {run: [], progress: $c}'
  mkrun() { # <passed> <failed> <running> <queued> <ended: seconds ago, or null>
    jq -cn --argjson p "$1" --argjson f "$2" --argjson r "$3" --argjson q "$4" --argjson e "$5" --argjson now "$(date +%s)" '
      {name: "nightly", sha: "0123456789ab", started: ($now - 600 - ($e // 0) | todate), ended: (if $e == null then null else $now - $e | todate end),
       result: (if $e == null then null else "fail" end),
       lanes: ([range($p) | {name: "pass-\(.)", state: "passed", started: null, sec: 60}] + [range($f) | {name: "broken-\(.)", state: "failed", started: null, sec: 120}]
         + [range($r) | {name: "busy-\(.)", state: "running", started: ($now - 90 | todate), sec: null}] + [range($q) | {name: "wait-\(.)", state: "queued", started: null, sec: null}])}' > "$STUB/run.json"
    rm -f "$ST/checkrun.json"  # its last answer, kept for 10 s
  }
  crjson() {
    # shellcheck source=/dev/null # the snapshot's libraries, by the list snapshot.sh names (SNAPLIBS)
    ( export CONVEYOR_MAIN=$R CONVEYOR_CARDS=$T/$CASE/cards; . "$SRC/conveyor.sh" state-dir > /dev/null && eval "$(grep '^SNAPLIBS=' "$SRC/commands/snapshot.sh")" && for l in $SNAPLIBS; do . "$HERE/lib/$l.sh" || exit 1; done || exit 1
      d=$(mktemp -d "$T/$CASE/cr.XXXXXX") || exit 1; checkrun "$d"; rc=$?; rm -rf "$d"; exit $rc )
  }
  cr() { crjson | jq -c ".checkRun | $1"; }
}

# The run's counts, time left and block in the snapshot and in the stream; the command run once in 10 s, also when
# two snapshots ask at once; a progress that is not a command refused by the pack check.
t_checkrun() {
  setup '[]'
  [ "$(loop snapshot --fresh | jq 'has("checkRun")')" = false ] || fail "a pack without checks.progress gives a checkRun field"
  jq '.checks = {progress: 3}' "$R/.conveyor/project.json" > "$R/.conveyor/bad.json"
  out=$("$SRC/lib/pack.sh" check "$R/.conveyor/bad.json" 2>&1) && fail "a progress that is not a command passed the pack check"
  grep -q '\.checks\.progress: number, not string' <<<"$out" || fail "a progress that is not a command failed the pack check for another reason: $out"
  crpack
  "$SRC/lib/pack.sh" check "$R/.conveyor/project.json" || fail "a pack with checks.progress fails its check"
  mkrun 3 1 2 4 null
  [ "$(cr '[.counts, .done, .all, .leftSec, [.lanes[] | select(.state == "failed") | .name], [.lanes[] | select(.state == "running") | .name]]')" \
    = '[{"passed":3,"failed":1,"running":2,"queued":4,"reused":0},4,10,225,["broken-0"],["busy-0","busy-1"]]' ] || fail "the run of 10 lanes: $(cr .)"
  # The block /units prints above ON THE BELT.
  [ "$(cr '.lines | join("|")')" = '"CHECK RUN nightly 0123456 · 4/10 lanes · 10m · ~3m left|✓ 3 ✗ 1 ▶ 2 … 4|  ✗ broken-0|  ▶ busy-0 1m|  ▶ busy-1 1m"' ] \
    || fail "the terminal block of the run of 10 lanes: $(cr .lines)"
  # The stream (`conveyor.sh watch`, which stream.json /units reads is made of) carries that block, line for line.
  # This checks the stream's JSON only: /units is the host project's command, not in this repository, so nothing
  # here runs it or reads what it prints; that it prints the lines it reads is for the host's own tests.
  # The stream prints the kept snapshot, which the case's first call made before the pack named checks.progress (the
  # pack is no input the writer watches): the case asks for the view after its own change, as the issue says a caller does.
  loop snapshot --fresh > /dev/null || fail "the snapshot with checks.progress failed"
  W=$T/$CASE/watch.out
  ( export CONVEYOR_WATCH_GITHUB_FIRST=1 CONVEYOR_MAIN=$R CONVEYOR_CARDS=$T/$CASE/cards
    exec timeout 60 bash "$SRC/conveyor.sh" watch > "$W" 2> "$W.err" ) & pid=$!
  until grep -q '"type":"snapshot"' "$W" 2>/dev/null || ! kill -0 $pid 2>/dev/null; do sleep 0.05; done # the snapshot, or the stream's end
  kill $pid 2>/dev/null; wait $pid 2>/dev/null
  [ "$(jq -c 'select(.type == "snapshot") | .snap.checkRun.lines | join("|")' "$W" | head -n 1)" \
    = '"CHECK RUN nightly 0123456 · 4/10 lanes · 10m · ~3m left|✓ 3 ✗ 1 ▶ 2 … 4|  ✗ broken-0|  ▶ busy-0 1m|  ▶ busy-1 1m"' ] \
    || fail "the stream's snapshot JSON does not carry checkRun.lines, the block /units prints: $(head -c 600 "$W") $(cat "$W.err")"
  # Asked again within 10 s, the command is not run again.
  rm -f "$STUB/ran" "$ST/checkrun.json"; cr .name >/dev/null; cr .name >/dev/null
  [ "$(wc -l < "$STUB/ran")" = 1 ] || fail "the progress command ran $(wc -l < "$STUB/ran") times in two snapshots 10 s apart or less"
  # Two snapshots at once: still one run. They are at the lock at once whatever the machine's pace: the case holds
  # the lock until each waits there (its flock runs under it), and from then on no step is the case's to take in time.
  rm -f "$STUB/ran" "$ST/checkrun.json"
  ( exec 9>>"$ST/checkrun.json.lock"; flock 9; : > "$STUB/held"; until [ -e "$STUB/go" ] || [ ! -d "$STUB" ]; do sleep 0.1; done ) &
  wait_until '[ -e "$STUB/held" ]' || fail "the case could not hold the progress command's lock"
  cr .name > /dev/null & first=$!; cr .name > /dev/null & second=$!
  wait_until "under $first flock && under $second flock" || fail "two snapshots at once did not both wait at the progress command's lock"
  : > "$STUB/go"; wait
  [ "$(wc -l < "$STUB/ran")" = 1 ] || fail "the progress command ran $(wc -l < "$STUB/ran") times in two snapshots at once"
}

# The time left, and a run that ended; a command that leaves a child in the background.
t_checkrunleft() {
  setup '[]'; crpack
  mkrun 2 0 2 6 null; [ "$(cr .leftSec)" = null ] || fail "a time left with 2 of 10 lanes done: $(cr .leftSec)"
  mkrun 3 0 2 5 null; [ "$(cr .leftSec)" = 210 ] || fail "no time left, or the wrong one, with 3 of 10 lanes done: $(cr .leftSec)"
  mkrun 9 1 0 0 3660; [ "$(cr .)" = null ] || fail "a run that ended 61 minutes ago is shown: $(cr .)"
  mkrun 9 1 0 0 3540; [ "$(cr '[.result, .leftSec, .done, .lines[0]]')" = '["fail",null,10,"CHECK RUN nightly 0123456 · 10/10 lanes · 10m · fail"]' ] \
    || fail "a run that ended 59 minutes ago, with its result: $(cr .)"
  : > "$STUB/run.json"; rm -f "$ST/checkrun.json"; [ "$(cr .)" = null ] || fail "no run yet is not null: $(cr .)"
  # A command that leaves a child in the background is not waited for past the 5 s.
  mkrun 3 1 2 4 null; tune --arg c "sleep 60 & cat $STUB/run.json" '.checks.progress = $c' # sleep: the child the command leaves in the background
  rm -f "$ST/checkrun.json"; s=$SECONDS; out=$(cr .name)
  [ $((SECONDS - s)) -lt 10 ] && [ "$out" = '"nightly"' ] || fail "a command that leaves a child in the background: $out after $((SECONDS - s)) s"
}

# Bad JSON, JSON of another shape, a run or a lane missing a field, a failing and a hanging command: each is said,
# and the rest of the snapshot stands (one whole snapshot, of the failing command: the snapshot adds checkrun()'s
# object to the rest as it is, whatever the command did).
t_checkrunbad() {
  setup '[]'; crpack; mkrun 3 1 2 4 null
  for c in "echo '{oops'" "echo '{\"name\":1}'" "jq -c 'del(.ended, .result)' $STUB/run.json" "jq -c 'del(.lanes[0].started, .lanes[0].sec)' $STUB/run.json" \
    "echo gone >&2; exit 3" "sleep 8"; do # sleep: a command that hangs past the 5 s it is given
    tune --arg c "$c" '.checks.progress = $c'; rm -f "$ST/checkrun.json"
    out=$(crjson) || fail "checkrun() failed with the progress command $c"
    jq -e '.checkRun.error | startswith("check run: progress unreadable: ")' <<<"$out" >/dev/null || fail "the progress command $c: $out"
  done
  [ "$(jq -r .checkRun.error <<<"$out")" = "check run: progress unreadable: it took over 5 s" ] || fail "a hanging command: $out"
  tune --arg c "echo gone >&2; exit 3" '.checks.progress = $c'; rm -f "$ST/checkrun.json"
  out=$(loop snapshot --fresh) || fail "the snapshot failed with a failing progress command"
  jq -e '(.checkRun.error == "check run: progress unreadable: gone") and (.belt | type == "array") and (.health | type == "object")' <<<"$out" >/dev/null \
    || fail "a failing progress command: $(jq -c .checkRun <<<"$out")"
}
