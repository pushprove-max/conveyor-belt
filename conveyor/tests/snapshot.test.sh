#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 120
# Engine cases: what the snapshot (lib/snapshot.sh) reads of the machine beyond the cards' records: the test slots, and
# a bug card's proof run on main's code.
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"

# Board 3D's deck shows the machine's free test slots (issue 393): the snapshot's testSlots must be the pool's own
# count, read as a test run reads it (the host file's testSlots and testSlotsDir), and change as a slot is taken and
# given back; a count of the card cap or a fixed figure would show slots free while every test run waits for one.
t_snapslots() {
  local f
  export XDG_CONFIG_HOME=$T/$CASE/config
  mkdir -p "$XDG_CONFIG_HOME/conveyor" && echo "{\"testSlots\": 2, \"testSlotsDir\": \"$T/$CASE/slots\"}" > "$XDG_CONFIG_HOME/conveyor/host.json"
  setup "[]"
  [ "$(loop snapshot --fresh | jq -c .testSlots)" = '{"used":0,"of":2}' ] || fail "with no slot held: $(loop snapshot --fresh | jq -c .testSlots)"
  # A test run holds slot 1, as slot_try takes it: a lock on its file.
  exec {f}>>"$T/$CASE/slots/1"; flock -n "$f" || fail "slot 1 could not be taken"
  [ "$(loop snapshot --fresh | jq -c .testSlots)" = '{"used":1,"of":2}' ] || fail "with slot 1 held: $(loop snapshot --fresh | jq -c .testSlots)"
  exec {f}>&-
  [ "$(loop snapshot --fresh | jq -c .testSlots)" = '{"used":0,"of":2}' ] || fail "once slot 1 was given back: $(loop snapshot --fresh | jq -c .testSlots)"
}

# Bug (#359): `foreman status` failed with "FileNotFoundError: .../T/tmp.XXXXXXXXXX/cardruns.jq" while the loop worked.
# The cause: the Foreman's ask stops a snapshot past its wait with `timeout`, which sends TERM to the snapshot's whole
# process group. When it comes as the snapshot's shell starts cardruns.py, the shell takes it only once the fork is
# made, and the new cardruns.py never gets it. With no TERM trap of its own, the shell then runs its EXIT trap at once
# and removes the scratch folder under cardruns.py, which fails on its first file, as reported. Here two snapshots run
# at once, each under `timeout` (its own process group, as the ask's); the first whose cardruns.py starts sends that
# TERM to its own group, from a sitecustomize on PYTHONPATH (a python3 on PATH would not do: on macOS p_path puts
# Homebrew's first), as from a cardruns.py that never got it. Bug it catches: a stopped snapshot that removes its
# folder while cardruns.py still reads it, or a stop that ends the snapshot made beside it.
t_snapstop() {
  local py=$T/$CASE/py tmp=$T/$CASE/tmp i n=0 stopped='' made=''
  setup "[]"
  mkdir -p "$py" "$tmp"
  cat > "$py/sitecustomize.py" <<'PY'
import atexit, os, signal, sys, time
if sys.argv[0].endswith("cardruns.py"):
    try:
        os.close(os.open(os.environ["SNAPSTOP"], os.O_CREAT | os.O_EXCL | os.O_WRONLY))
    except FileExistsError:
        pass
    else:
        failed = []
        hook = sys.excepthook
        sys.excepthook = lambda *e: (failed.append(1), hook(*e))
        atexit.register(lambda: open(os.environ["SNAPSTOP"] + ".rc", "w").write("1" if failed else "0"))
        signal.signal(signal.SIGTERM, signal.SIG_IGN)  # as one started after the TERM was sent: it never gets it
        os.killpg(0, signal.SIGTERM)
        time.sleep(1)
        signal.signal(signal.SIGTERM, signal.SIG_DFL)
PY
  for i in 1 2; do
    ( SNAPSTOP=$T/$CASE/stop PYTHONPATH=$py TMPDIR=$tmp CONVEYOR_MAIN=$R CONVEYOR_CARDS=$T/$CASE/cards \
        timeout -k 2 60 bash "$SRC/conveyor.sh" snapshot > "$T/$CASE/out$i" 2>&1; echo $? > "$T/$CASE/rc$i" ) &
  done 2>/dev/null
  wait
  # The stopped snapshot's shell and its cardruns.py outlive the timeout (its top shell ended at the TERM): wait for them.
  while { [ ! -e "$T/$CASE/stop.rc" ] || [ -n "$(ls -A "$tmp")" ]; } && [ $((n++)) -lt 100 ]; do sleep 0.1; done
  for i in 1 2; do
    if [ "$(cat "$T/$CASE/rc$i")" = 143 ]; then stopped+="$i"
    elif [ "$(cat "$T/$CASE/rc$i")" = 0 ] && jq -e '.belt | arrays' "$T/$CASE/out$i" >/dev/null 2>&1; then made+="$i"; fi
  done
  [ ${#stopped} = 1 ] && [ ${#made} = 1 ] \
    || fail "not one snapshot stopped and one made (exits $(cat "$T/$CASE/rc1") and $(cat "$T/$CASE/rc2")): $(cat "$T/$CASE/out1" "$T/$CASE/out2")"
  [ "$(cat "$T/$CASE/stop.rc" 2>/dev/null)" = 0 ] && ! grep -q Traceback "$T/$CASE/out$stopped" \
    || fail "cardruns.py lost its scratch folder as the snapshot was stopped: $(cat "$T/$CASE/out$stopped")"
  [ -z "$(ls -A "$tmp")" ] || fail "a snapshot left its scratch folder: $(ls -A "$tmp")"
}

# Bug (#281): while a bug card's new tests ran on main's code without its fix (testrun.sh bugproof(), its live record
# $CARDS/mainrun/<card>.unfixed.live), the card's records ended with its build line, so the snapshot named the review
# after it ("review 1 of 3", the reviewer's model) though no review ran. That run is the card's step in progress: proof,
# on Build, with its files run. Once the review starts, a proof record left behind is not shown over it.
t_snapproof() {
  local s c=c20261117T100000-r-7
  setup "[]"
  # A line of the card's records: <step> <result> <minute of 2026-11-17T10> [extra json].
  snapproof_line() { jq -cn --arg c "$c" --arg s "$1" --arg r "$2" --arg t "2026-11-17T10:$3:00Z" --argjson x "${4:-{\}}" \
    '{card: $c, issue: 7, step: $s, time: $t, tokens: {claude: 0, codex: 0}, result: $r, sha: "", reason: "", repo: "r"} * $x'; }
  { snapproof_line picked ok 00 '{"title": "a bug", "created": "2026-11-17T09:59:00Z"}'; snapproof_line worktree ok 01
    snapproof_line deps ok 01; snapproof_line brief ok 02; snapproof_line start ok 02 '{"of": "build"}'; snapproof_line build ok 05; } > "$ST/cards.jsonl"
  mkdir -p "$T/$CASE/cards/mainrun"
  echo '{"step": "test", "at": "2026-11-17T10:06:00Z", "last": null, "turns": 0, "files": {"run": 297, "of": 1161}, "tests": null}' \
    > "$T/$CASE/cards/mainrun/$c.unfixed.live"
  s=$(loop snapshot --fresh | jq -c '.belt[0] | [.step, .review, .model, .track.label, .track.at, .track.detailAt, .track.files, .track.since]')
  [ "$s" = '["proof",null,null,"proof run",0,5,{"run":297,"of":1161},"2026-11-17T10:06:00Z"]' ] || fail "a card in its proof run: $s"
  # While it waits for a test slot (testrun.sh writes that action, no file run), the belt says so, not that tests run.
  echo '{"step": "test", "at": "2026-11-17T10:06:00Z", "last": null, "turns": 0, "files": {"run": 0, "of": null}, "tests": null, "action": "waiting for a test slot (2 of 2 in use)"}' \
    > "$T/$CASE/cards/mainrun/$c.unfixed.live"
  s=$(loop snapshot --fresh | jq -c '.belt[0] | [.step, .live.action]')
  [ "$s" = '["proof","waiting for a test slot (2 of 2 in use)"]' ] || fail "a proof run waiting for a test slot: $s"
  snapproof_line start ok 30 '{"of": "review"}' >> "$ST/cards.jsonl"
  s=$(loop snapshot --fresh | jq -c '.belt[0] | [.step, .review, .track.label, .track.files]')
  [ "$s" = '["review",1,"review 1 of 3",null]' ] || fail "a proof record left behind is shown over the review: $s"
}

# Bug (#320): the Board showed a card as testing for 46 minutes while a fix session ran. A card's step and its time came
# from its last step line (start lines left out): a test run after a GO was timed from the review's end, a fix after a
# failed test run from that run's end, and a session that fits a card onto main after its GO (claim.sh settle(), no
# test line) was shown as its tests. While its step runs, the live record names that step and when it began.
t_snapfixlive() {
  local s a=c20261117T100000-r-8 b=c20261117T100000-r-9
  setup "[]"
  # A line of the card's records: <card> <step> <result> <time of 2026-11-17T, hh:mm> [extra json].
  snapfixlive_line() { jq -cn --arg c "$1" --arg s "$2" --arg r "$3" --arg t "2026-11-17T$4:00Z" --argjson x "${5:-{\}}" \
    '{card: $c, issue: ($c | ltrimstr("c20261117T100000-r-") | tonumber), step: $s, time: $t, tokens: {claude: 0, codex: 0}, result: $r, sha: "", reason: "", repo: "r"} * $x'; }
  # Built, reviewed with a GO, then its changed tests.
  snapfixlive_go() { snapfixlive_line "$1" picked ok 10:00 '{"title": "t", "created": "2026-11-17T09:59:00Z"}'; snapfixlive_line "$1" worktree ok 10:01
    snapfixlive_line "$1" deps ok 10:01; snapfixlive_line "$1" brief ok 10:02; snapfixlive_line "$1" start ok 10:02 '{"of": "build"}'
    snapfixlive_line "$1" build ok 10:05; snapfixlive_line "$1" start ok 10:05 '{"of": "review"}'; snapfixlive_line "$1" review GO 10:28
    snapfixlive_line "$1" start ok 10:28 '{"of": "land"}'; }
  { snapfixlive_go "$a"; snapfixlive_line "$a" start ok 10:30 '{"of": "test"}'; } > "$ST/cards.jsonl"
  mkdir -p "$T/$CASE/cards"
  echo '{"step": "test", "at": "2026-11-17T10:30:07Z", "last": null, "turns": 0, "files": {"run": 4, "of": 6}, "tests": null}' > "$T/$CASE/cards/$a.live"
  s=$(loop snapshot --fresh | jq -c --arg a "$a" '.belt[] | select(.card == $a) | [.step, .stepAt, .track.since, .track.files]')
  [ "$s" = '["tests","2026-11-17T10:30:07Z","2026-11-17T10:30:07Z",{"run":4,"of":6}]' ] || fail "a test run after a GO: $s"
  # Its test run failed and its fix runs; card b's session fits it onto main after its GO, with no test run.
  { snapfixlive_line "$a" test fail 11:13; snapfixlive_line "$a" start ok 11:14 '{"of": "fix"}'
    snapfixlive_go "$b"; snapfixlive_line "$b" start ok 10:41 '{"of": "fix"}'; } >> "$ST/cards.jsonl"
  echo '{"step": "fix", "at": "2026-11-17T11:14:11Z", "last": null, "turns": 2, "model": "claude-x"}' > "$T/$CASE/cards/$a.live"
  echo '{"step": "fix", "at": "2026-11-17T10:41:05Z", "last": null, "turns": 1, "model": "claude-x"}' > "$T/$CASE/cards/$b.live"
  s=$(loop snapshot --fresh | jq -c '[.belt[] | [.card[-1:], .step, .stepAt, .track.since, .review]]')
  [ "$s" = '[["8","fix","2026-11-17T11:14:11Z","2026-11-17T11:14:11Z",null],["9","fix","2026-11-17T10:41:05Z","2026-11-17T10:41:05Z",null]]' ] \
    || fail "a fix after failed tests, and one that fits a card onto main after its GO: $s"
}
