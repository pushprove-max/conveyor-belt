#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 300
# Engine cases: the test actions' queue (lib/testaction.sh): asks past the running limit wait in the queue and start
# in the order asked, each with main as it was at its ask; `testaction stop <id>` takes a queued one off. Their
# fixtures are testaction.test.sh's tasetup and tarec, and testactrun.test.sh's trsetup.
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"

# Bugs this guards (the owner, 2026-11-16: actions on many files at once): a Board ask for many files started a
# session for each at once; a queued ask never started when a running one ended, or started out of order; a stop of a
# queued ask started its session, or left it to start later. Each session here notes its pid in $STUB/ta-up and runs
# until $STUB/ta-end.<pid> or $STUB/ta-go is there.
t_taqueue() {
  tasetup; local ids=() i out
  cat > "$STUB/claude" <<'EOF'
#!/usr/bin/env bash
echo $$ >> "$STUB/ta-up"; cat > /dev/null
until [ -e "$STUB/ta-end.$$" ] || [ -e "$STUB/ta-go" ]; do sleep 0.1; done
EOF
  loop control tests claude m-tests > /dev/null || fail "control tests was refused"
  for i in 1 2 3 4 5; do
    out=$(loop testaction judge tests/x.test.sh 2>&1) && [[ $out =~ ^[0-9a-f]{12}$ ]] || fail "ask $i was not taken: $out"; ids+=("$out")
  done
  out=$(for i in "${ids[@]}"; do tarec "$i" .state; done | tr '\n' ' ')
  [ "$out" = 'running running running queued queued ' ] || fail "five asks are not three running and two queued, in the order asked: $out"
  wait_until "[ \"\$(grep -c . '$STUB/ta-up' 2>/dev/null)\" = 3 ]" || fail "the three running asks did not each start a session"
  # One session ends: the oldest queued ask starts, and the newer one waits.
  : > "$STUB/ta-end.$(head -n 1 "$STUB/ta-up")"
  wait_until "[ \"\$(tarec ${ids[3]} .state)\" = running ]" "cat '$ST/testactions/${ids[3]}.json'" || fail "the oldest queued ask did not start when a session ended"
  wait_until "[ \"\$(grep -c . '$STUB/ta-up')\" = 4 ]" || fail "the queued ask that started has no session"
  [ "$(tarec "${ids[0]}" .state)" = 'done' ] && [ "$(tarec "${ids[4]}" .state)" = queued ] || fail "the ended one is not done, or the newer queued ask did not wait: $(tarec "${ids[4]}" .state)"
  # A stop of the queued ask takes it off, unstarted: no session when the next one ends.
  out=$(loop testaction stop "${ids[4]}" 2>&1) && [ "$(tarec "${ids[4]}" '[.state, (.end | type), has("pid")] | tojson')" = '["stopped","string",false]' ] \
    || fail "the stop of a queued ask: $out $(cat "$ST/testactions/${ids[4]}.json")"
  : > "$STUB/ta-end.$(sed -n 2p "$STUB/ta-up")"
  wait_until "[ \"\$(tarec ${ids[1]} .state)\" = done ]" || fail "the second session did not end"
  : > "$STUB/ta-go"
  for i in "${ids[@]:0:4}"; do wait_until "[ \"\$(tarec $i .state)\" = done ]" "cat '$ST/testactions/$i.json'" || fail "the action $i did not end done"; done
  [ "$(grep -c . "$STUB/ta-up")" = 4 ] && [ "$(tarec "${ids[4]}" .state)" = stopped ] || fail "the stopped queued ask started a session: $(grep -c . "$STUB/ta-up") sessions"
}

# Bug this guards: a queued ask read main as it was when it started, not as it was at the ask, so a commit landed while
# it waited changed the file it judged or ran. Three running actions (sleeps) fill the queue; a run and a judge are
# asked, main moves on, the sleeps end; a later ask then starts all three: the two queued ones read the old commit,
# the later one the new.
t_taqueuedmain() {
  trsetup; local i p=() old id1 id2 id3 wt=$T/$CASE/cards/testactions
  mkdir -p "$ST/testactions" || fail "the actions' folder"
  for i in 1 2 3; do sleep 60 & p+=($!); echo "{\"id\":\"f$i\",\"state\":\"running\",\"asked\":$i,\"pid\":$!}" > "$ST/testactions/f$i.json"; done # sleep: a running action's process, until the case kills it
  loop control tests claude m-tests > /dev/null || fail "control tests was refused"
  old=$(git -C "$R" rev-parse HEAD)
  id1=$(loop testaction run tests/x.test.sh 2>&1) && id2=$(loop testaction judge tests/x.test.sh 2>&1) || fail "the asks were not taken: $id1 $id2"
  [ "$(tarec "$id1" '[.state, .commit] | tojson')" = "[\"queued\",\"$old\"]" ] && [ "$(tarec "$id2" '[.state, .commit] | tojson')" = "[\"queued\",\"$old\"]" ] \
    || fail "the asks are not queued with main's commit at the ask: $(cat "$ST/testactions/$id1.json" "$ST/testactions/$id2.json")"
  echo 'echo new' > "$R/tests/x.test.sh" && git -C "$R" commit -qam 'main moves on' || fail "main did not move on"
  kill "${p[@]}" 2>/dev/null; wait "${p[@]}" 2>/dev/null
  id3=$(loop testaction judge tests/x.test.sh 2>&1) || fail "the later ask was not taken: $id3"
  for i in "$id1" "$id2" "$id3"; do wait_until "[ -e '$wt/$i/tests/x.test.sh' ]" "cat '$ST/testactions/$i.json' '$ST/testactions/$i.err'" || fail "the action $i has no copy of main"; done
  [ "$(cat "$wt/$id1/tests/x.test.sh")" = 'echo ok' ] || fail "the queued run runs main as it was when it started, not at the ask"
  [ "$(cat "$wt/$id2/tests/x.test.sh")" = 'echo ok' ] || fail "the queued judge reads main as it was when it started, not at the ask"
  [ "$(cat "$wt/$id3/tests/x.test.sh")" = 'echo new' ] || fail "the later ask does not read main as it is at its ask"
  : > "$STUB/ta-go"; : > "$STUB/tr-go"
  for i in "$id1" "$id2" "$id3"; do wait_until "[ \"\$(tarec $i .state)\" = done ]" "cat '$ST/testactions/$i.json'" || fail "the action $i did not end done"; done
}
