#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 300
# Engine cases: the test actions (lib/testaction.sh): `testaction judge|explain <test file>` runs one session of the
# control record's Tests seat about one test file, `testaction run <test file>` runs one test file on a test slot,
# `testaction stop <id>` ends one, and the snapshot lists them.
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"

# The helpers are named ta*: every case file is sourced into one shell, so a name another file uses would replace its.
# The setup of a test-action case: main holds the test file tests/x.test.sh, and claude is a Tests session that keeps
# its arguments ($STUB/ta-args) and prompt ($STUB/ta-prompt.<pid>), writes its first words, tries to file an issue
# and to write a file of the repo it runs in (each try's exit status in $STUB/ta-tries), waits for $STUB/ta-go, then
# writes $STUB/ta-last (when there is one) and ends.
tasetup() {
  setup "[$(issue 7 2026-01-01)]"
  mkdir -p "$R/tests" && echo 'echo ok' > "$R/tests/x.test.sh" && git -C "$R" add tests && git -C "$R" commit -qm 'a test file' || fail "the test file could not be committed"
  cat > "$STUB/claude" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$STUB/ta-args"; cat > "$STUB/ta-prompt.$$"
echo '{"type":"assistant","message":{"content":[{"type":"text","text":"first words"}]}}'
gh issue create --title t --body b > /dev/null 2>&1; echo "gh $?" >> "$STUB/ta-tries"
{ echo changed >> a.txt; } 2>/dev/null; echo "write $?" >> "$STUB/ta-tries"
until [ -e "$STUB/ta-go" ]; do sleep 0.1; done
[ ! -f "$STUB/ta-last" ] || jq -cn --rawfile t "$STUB/ta-last" '{type: "assistant", message: {content: [{type: "text", text: $t}]}}'
echo '{"type":"result","is_error":false,"result":"end"}'
EOF
  chmod +x "$STUB/claude"
}
tarec() { jq -r "$2" "$ST/testactions/$1.json" 2>/dev/null; } # <id> <jq filter>: of the action's record

# Bugs this guards: a judge started with no Tests seat (on a seat the owner never chose); a session given no times of
# the file, so it judged blind; text that reached the Board only once the session ended; a record that did not say the
# session ran, how it ended, or on which CLI, model and effort; a judge's verdict lost; a session that filed an issue
# or changed the repo it reads; a snapshot that did not list the seat or the action.
t_tajudge() {
  tasetup; local id out
  # A test line that timed the file, over its budget, and a flaky entry of a case of it.
  jq -cn '{card: "c1-5", issue: 5, step: "test", time: "2026-11-01T00:00:00Z", tokens: {claude: 0, codex: 0}, result: "ok", sha: "", reason: "",
    times: {"tests/x.test.sh": 41.5, "tests/other.test.sh": 2}, slow: [{file: "tests/x.test.sh", sec: 44, cpu: 41.5, budget: 8, changed: false}]}' >> "$ST/cards.jsonl"
  echo '{"entries":[{"case":"tests/x.test.sh: one","source":"c2-6","time":"2026-11-02T00:00:00Z","card":"c2-6","issue":6}],"filed":[]}' > "$ST/flaky.json"
  # No Tests seat: no session starts, and the command says why.
  out=$(loop testaction judge tests/x.test.sh 2>&1); [ $? = 2 ] && grep -q 'no Tests seat is set' <<<"$out" || fail "a judge with no Tests seat was not refused, saying why: $out"
  [ ! -e "$STUB/ta-args" ] && [ ! -d "$ST/testactions" ] || fail "a judge with no Tests seat started a session: $(cat "$STUB/ta-args" 2>&1)"
  loop control tests claude m-tests high > /dev/null || fail "control tests was refused"
  # Its hollow cases (#77): two HOLLOW lines that read, and one with no kind, skipped and counted.
  printf '%s\n' 'It runs the whole loop for one check.' 'HOLLOW: reads the pack | mock-echo | it checks the stub returns what the stub was given' \
    '- HOLLOW: `one` | no-assert | it asserts nothing' 'HOLLOW: two | it only prints' 'VERDICT: split' > "$STUB/ta-last"
  id=$(loop testaction judge tests/x.test.sh 2>&1) && [[ $id =~ ^[0-9a-f]{12}$ ]] || fail "the judge did not start: $id"
  # While the session runs: its text so far is in the file, and its record says running.
  wait_until "grep -q 'first words' '$ST/testactions/$id.txt'" "cat '$ST/testactions/$id.txt' '$ST/testactions/$id.err'" || fail "the text written so far is not in the text file while the session runs"
  [ "$(tarec "$id" '[.state, .end, .action, .file, .limit] | tojson')" = '["running",null,"judge","tests/x.test.sh",900]' ] || fail "the record does not say running while the session runs: $(cat "$ST/testactions/$id.json")"
  grep -q -- '--model m-tests --effort high' "$STUB/ta-args" || fail "the session did not start on the Tests seat's CLI, model and effort: $(cat "$STUB/ta-args")"
  out=$(cat "$STUB"/ta-prompt.*)
  grep -qF 'Test file: tests/x.test.sh' <<<"$out" && grep -qF '"times":41.5' <<<"$out" && grep -qF '"budget":8' <<<"$out" && grep -qF 'c1-5 (#5)' <<<"$out" \
    && grep -qF 'tests/x.test.sh: one' <<<"$out" && ! grep -qF 'other.test.sh' <<<"$out" || fail "the prompt does not name the file, its recorded times, the cards that ran it and its flaky entries alone: $out"
  : > "$STUB/ta-go"
  wait_until "[ \"\$(tarec $id .state)\" != running ]" "cat '$ST/testactions/$id.json'" || fail "the record still says running after the session ended"
  [ "$(tarec "$id" '[.state, .cli, .model, .effort, .verdict, (.end | type), has("pid")] | tojson')" = '["done","claude","m-tests","high","split","string",false]' ] \
    || fail "the record of the ended session is not done with its end time, CLI, model, effort and verdict: $(cat "$ST/testactions/$id.json")"
  # Bug it catches (#77): the judge's hollow cases were lost in its text, or a HOLLOW line that does not read failed the
  # record; the prompt did not ask for them.
  [ "$(tarec "$id" '[.hollow, .hollowSkipped] | tojson')" = '[[{"case":"reads the pack","kind":"mock-echo","reason":"it checks the stub returns what the stub was given"},{"case":"`one`","kind":"no-assert","reason":"it asserts nothing"}],1]' ] \
    || fail "the record does not hold the two hollow cases and the one HOLLOW line skipped: $(cat "$ST/testactions/$id.json")"
  grep -qF 'HOLLOW: <case> | <kind> | <one-line reason>' "$STUB"/ta-prompt.* || fail "the prompt does not ask for the hollow cases"
  grep -q 'first words' "$ST/testactions/$id.txt" && grep -q 'VERDICT: split' "$ST/testactions/$id.txt" || fail "the text file did not grow to the session's whole text: $(cat "$ST/testactions/$id.txt")"
  # It tried to file an issue and to write a file of the repo: both failed, and the repo is as it was.
  [ "$(cat "$STUB/ta-tries")" = $'gh 1\nwrite 1' ] && [ ! -e "$STUB/filed" ] || fail "the session filed an issue or wrote a file: $(cat "$STUB/ta-tries" "$STUB/filed" 2>&1)"
  [ "$(cat "$R/a.txt")" = one ] && [ -z "$(git -C "$R" status --porcelain)" ] || fail "the repo changed: $(git -C "$R" status --porcelain)"
  [ ! -e "$T/$CASE/cards/testactions/$id" ] && [ "$(git -C "$R" worktree list | wc -l)" = 1 ] || fail "the copy the session read was left: $(git -C "$R" worktree list)"
  # The Board shows the action's text from the snapshot (#521): there, whole, and its end alone when it is too long.
  # Bug it catches (#594): the Tests model offered no model for Claude Code, which lists none on the host; the
  # snapshot gives the pack's models by CLI (the builder's, as modelSettings has them) for the Board to offer.
  out=$(loop snapshot | jq -c '.modelSettings.builder.allowed as $b | .testActions | [.seat, .limit, [.actions[] | [.id, .state, .verdict, (.text | test("^first words\n(.|\n)*VERDICT: split\n$")), .textCut]],
    (.allowed == $b and (.allowed.claude | index("m") != null))]')
  [ "$out" = "[{\"cli\":\"claude\",\"model\":\"m-tests\",\"effort\":\"high\"},900,[[\"$id\",\"done\",\"split\",true,false]],true]" ] || fail "the snapshot does not list the seat, the action with its state and text, and the pack's models by CLI: $out"
  out=$( export CONVEYOR_MAIN=$R CONVEYOR_CARDS=$T/$CASE/cards; . "$SRC/conveyor.sh" state-dir > /dev/null && eval "$(grep '^\. "\$HERE/lib/' "$SRC/commands/snapshot.sh")" && TATEXT_MAX=7 testacts | jq -c '.[0] | [.text, .textCut]')
  [ "$out" = '["split\n\n",true]' ] || fail "a text over TATEXT_MAX is not its end alone, marked cut: $out"
  # Bug it catches: an action older than the newest TATEXT_SHOWN was listed with text null, so after a reload the
  # Board's View and Copy of that result had no text. Past the newest, only a file's newest judge with a verdict is
  # listed (the issue preview's verdict), with its text; an older explain is left out.
  jq -cn '{id: "0000000000aa", action: "explain", file: "tests/x.test.sh", start: "2020-01-01T00:00:00Z", end: "2020-01-01T00:01:00Z", state: "done"}' > "$ST/testactions/0000000000aa.json"
  echo old > "$ST/testactions/0000000000aa.txt"
  out=$( export CONVEYOR_MAIN=$R CONVEYOR_CARDS=$T/$CASE/cards; . "$SRC/conveyor.sh" state-dir > /dev/null && eval "$(grep '^\. "\$HERE/lib/' "$SRC/commands/snapshot.sh")" && TATEXT_SHOWN=0 testacts | jq -c '[.[] | [.id, (.text | type)]]')
  [ "$out" = "[[\"$id\",\"string\"]]" ] || fail "past the newest, not the judge alone with its text: $out"
}

# The Board's File an issue (`testissue`) files the issue with the pack's type and last priority and keeps it for the
# file, and refuses a file main lacks. Bug it catches: an issue the Board filed was kept nowhere, so its file's row had
# no Close its issue as done.
t_taissue() {
  tasetup; local out
  out=$(loop testissue tests/x.test.sh "Speed up tests/x.test.sh" "Measured: 12 CPU s.") || fail "testissue failed: $out"
  [ "$out" = https://github.com/o/r/issues/100101 ] || fail "testissue does not print the issue's address: $out"
  [ "$(jq -c '[.title, (.labels | map(.name))]' "$STUB/filed")" = '["Speed up tests/x.test.sh",["bug","P2"]]' ] || fail "the issue filed: $(cat "$STUB/filed")"
  [ "$(jq -c '[.event, .file, .issue]' "$ST/testactions/filed.jsonl")" = '["filed","tests/x.test.sh",100101]' ] || fail "the issue is not kept for the file: $(cat "$ST/testactions/filed.jsonl" 2>&1)"
  loop testissue tests/gone.test.sh t b 2> /dev/null; [ $? = 2 ] && [ "$(wc -l < "$STUB/filed")" = 1 ] || fail "testissue of a file main lacks did not refuse"
}

# Bug this guards: a Tests seat set to a model its CLI does not list (the Board's Other…) ran on another model; a
# judge whose text ends with no verdict had a verdict made up for it.
t_taother() {
  tasetup; local id
  cat > "$STUB/codex" <<'EOF'
#!/usr/bin/env bash
[ "$1 ${2:-}" != "debug models" ] || { echo '{"models":[{"slug":"gpt-a","visibility":"list"}]}'; exit 0; }
printf '%s\n' "$*" >> "$STUB/ta-args"; cat > /dev/null
echo '{"type":"item.completed","item":{"type":"agent_message","text":"Its setup is slow; nothing more to say."}}'
EOF
  loop control tests codex custom-9 > /dev/null || fail "control tests with a model the CLI does not list was refused"
  id=$(loop testaction judge tests/x.test.sh 2>&1) && [[ $id =~ ^[0-9a-f]{12}$ ]] || fail "the judge did not start: $id"
  wait_until "[ \"\$(tarec $id .state)\" = done ]" "cat '$ST/testactions/$id.json' '$ST/testactions/$id.err'" || fail "the session did not end done"
  grep -q -- '-m custom-9 ' "$STUB/ta-args" || fail "the session did not start with the model the CLI does not list: $(cat "$STUB/ta-args")"
  [ "$(tarec "$id" '[.cli, .model, .effort, .verdict] | tojson')" = '["codex","custom-9","medium","no verdict"]' ] || fail "the record of a judge with no verdict line: $(cat "$ST/testactions/$id.json")"
  grep -q 'Its setup is slow' "$ST/testactions/$id.txt" || fail "a Codex session's text is not in the text file: $(cat "$ST/testactions/$id.txt")"
}

# Bug this guards: a stop ended every running action, or none; a stopped one's record still said running.
t_tastop() {
  tasetup; local a b out
  loop control tests claude m-tests > /dev/null || fail "control tests was refused"
  a=$(loop testaction judge tests/x.test.sh 2>&1) && b=$(loop testaction explain tests/x.test.sh 2>&1) || fail "the two actions did not start: $a $b"
  wait_until "[ \"\$(grep -c . '$STUB/ta-tries' 2>/dev/null)\" = 4 ]" || fail "the two sessions did not both run"
  out=$(loop testaction stop "$a" 2>&1) || fail "the stop failed: $out"
  [ "$(tarec "$a" '[.state, (.end | type)] | tojson')" = '["stopped","string"]' ] || fail "the stopped action's record does not say stopped: $(cat "$ST/testactions/$a.json")"
  [ "$(tarec "$b" .state)" = running ] && kill -0 "$(tarec "$b" .pid)" 2>/dev/null || fail "the stop of one action stopped the other: $(cat "$ST/testactions/$b.json")"
  # Of the two sessions (each stub's pid ends its prompt file's name), the stopped one's has ended and the other's runs.
  out=$(for p in "$STUB"/ta-prompt.*; do kill -0 "${p##*.}" 2>/dev/null && echo up || echo gone; done | sort | tr '\n' ' ')
  [ "$out" = 'gone up ' ] || fail "the stop did not end that one session alone: $out"
  out=$(loop snapshot | jq -c '[.testActions.actions[] | [.id, .state]] | sort')
  [ "$out" = "$(jq -cn --arg a "$a" --arg b "$b" '[[$a, "stopped"], [$b, "running"]] | sort')" ] || fail "the snapshot does not list each action with its state: $out"
  out=$(loop testaction stop "$a" 2>&1); [ $? = 2 ] || fail "a stop of an action that is not running was not refused: $out"
  : > "$STUB/ta-go"
  wait_until "[ \"\$(tarec $b .state)\" = done ]" "cat '$ST/testactions/$b.json'" || fail "the action that was not stopped did not end done"
  [ "$(tarec "$b" .verdict)" = null ] || fail "an explain has a verdict: $(cat "$ST/testactions/$b.json")"
}

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

# Bug this guards: a session that never ended held its action running for ever.
t_tatimeout() {
  tasetup; local id
  tune '.tunables.testActionTimeout = 1'
  loop control tests claude m-tests > /dev/null || fail "control tests was refused"
  id=$(loop testaction explain tests/x.test.sh 2>&1) && [[ $id =~ ^[0-9a-f]{12}$ ]] || fail "the action did not start: $id"
  wait_until "[ \"\$(tarec $id .state)\" != running ]" "cat '$ST/testactions/$id.json'" || fail "the action that passed its time limit did not end"
  [ "$(tarec "$id" '[.state, .limit] | tojson')" = '["timed out",1]' ] || fail "the record of an action past its time limit does not say timed out: $(cat "$ST/testactions/$id.json")"
}

# The setup of a run by hand (testaction run, issue 517): tasetup's main, and a pool of the case's own of one slot
# ($T/$CASE/slots, the host file's testSlotsDir, written before setup), so the slot the run takes can be seen. The
# test command keeps the list it is given ($STUB/tr-list), its own pid ($STUB/tr-pid) and whether slot 1 is held
# while it runs ($STUB/tr-held); writes its words; times tests/x.test.sh in its log at 3.5 s and 2.25 CPU s; waits
# for $STUB/tr-go; and exits with $STUB/tr-rc, 0 when there is none.
trsetup() {
  export XDG_CONFIG_HOME=$T/$CASE/config
  mkdir -p "$XDG_CONFIG_HOME/conveyor" && echo "{\"testSlots\": 1, \"testSlotsDir\": \"$T/$CASE/slots\"}" > "$XDG_CONFIG_HOME/conveyor/host.json" \
    || fail "the host file was not written"
  tasetup
  cat > "$STUB/test-cmd" <<'EOF'
cat "$CONVEYOR_TEST_RERUN" > "$STUB/tr-list"; echo $$ > "$STUB/tr-pid"
if flock -n "$STUB/../slots/1" true; then echo free; else echo held; fi > "$STUB/tr-held"
echo "running tests/x.test.sh"
printf 'TESTRUN sec\ttests/x.test.sh\t3.5\t2.25\n' > "$CONVEYOR_TEST_LOG/r.log"
until [ -e "$STUB/tr-go" ]; do sleep 0.1; done
exit "$(cat "$STUB/tr-rc" 2>/dev/null || echo 0)"
EOF
}
trfree() { flock -n "$T/$CASE/slots/1" true; } # the pool's one slot is free

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

# Bugs this guards (issue 517): the owner could not time one test file without a card. A run by hand ran more than the
# file, or ran it with no test slot, beside the cards' runs; its record did not say how it went or how long it took;
# its slot stayed taken; its time was lost to the next card that changed the file, which had no before.
t_tarun() {
  trsetup; local id got w=$T/$CASE/wt
  id=$(loop testaction run tests/x.test.sh 2>&1) && [[ $id =~ ^[0-9a-f]{12}$ ]] || fail "the run did not start: $id"
  wait_until '[ -s "$STUB/tr-held" ]' "cat '$ST/testactions/$id.err'" || fail "the test command did not start"
  [ "$(cat "$STUB/tr-list")" = $'fail\ttests/x.test.sh' ] || fail "the command was not told to run that file alone: $(cat "$STUB/tr-list")"
  [ "$(cat "$STUB/tr-held")" = held ] && ! trfree || fail "the run does not hold the test slot while it runs"
  # limit (issue 571): the test run's time limit (testTimeout, 3600 in the test pack), not a session's (testActionTimeout).
  [ "$(tarec "$id" '[.state, .action, .file, .result, .end, (.load | type), .limit] | tojson')" = '["running","run","tests/x.test.sh",null,null,"number",3600]' ] \
    || fail "the record does not say running, with the machine's load and the test run's time limit: $(cat "$ST/testactions/$id.json")"
  wait_until "grep -q 'running tests/x.test.sh' '$ST/testactions/$id.txt'" || fail "the output is not in the text file while it runs"
  : > "$STUB/tr-go"
  wait_until "[ \"\$(tarec $id .state)\" != running ]" "cat '$ST/testactions/$id.json' '$ST/testactions/$id.err'" || fail "the record still says running after the run ended"
  [ "$(tarec "$id" '[.state, .result, .sec, .cpu, (.wait | type), (.end | type), has("pid")] | tojson')" = '["done","pass",3.5,2.25,"number","string",false]' ] \
    || fail "the record of the ended run has not its result, clock and CPU seconds and slot wait: $(cat "$ST/testactions/$id.json")"
  trfree || fail "the slot is still held once the run ended"
  grep -q 'running tests/x.test.sh' "$ST/testactions/$id.txt" && [ ! -L "$ST/testactions/$id.txt" ] || fail "the output was not kept: $(ls -l "$ST/testactions")"
  [ ! -e "$T/$CASE/cards/testactions/$id" ] && [ "$(git -C "$R" worktree list | wc -l)" = 1 ] || fail "the copy of main it ran in was left: $(git -C "$R" worktree list)"
  # A later card whose change modifies the file, over a 1 CPU s budget, gets the run's time as its before.
  tune '.test.fileBudget = 1'
  git -C "$R" worktree add -q --detach "$w" && echo more >> "$w/tests/x.test.sh" && git -C "$w" add tests && mkdir -p "$w.testlog" \
    && printf 'TESTRUN sec\ttests/x.test.sh\t9\t9\n' > "$w.testlog/r.log" || fail "the later card's worktree"
  got=$( ( export CONVEYOR_MAIN=$R CONVEYOR_CARDS=$T/$CASE/cards; . "$SRC/conveyor.sh" state-dir > /dev/null && eval "$(grep '^\. "\$HERE/lib/' "$SRC/commands/run.sh")" && slowtests "$w" && jq -c 'map({file, before, from})' "$w.slow" ) )
  [ "$got" = "[{\"file\":\"tests/x.test.sh\",\"before\":2.25,\"from\":\"run by hand, $(tarec "$id" '.end[:10]')\"}]" ] || fail "the later card's before is not the run by hand's: $got"
}

# Bug this guards (issue 517): a file that fails run by hand lost its output, or its record said it passed.
t_tarunfail() {
  trsetup; local id
  echo 3 > "$STUB/tr-rc"; : > "$STUB/tr-go"
  id=$(loop testaction run tests/x.test.sh 2>&1) && [[ $id =~ ^[0-9a-f]{12}$ ]] || fail "the run did not start: $id"
  wait_until "[ \"\$(tarec $id .state)\" != running ]" "cat '$ST/testactions/$id.json' '$ST/testactions/$id.err'" || fail "the failing run did not end"
  [ "$(tarec "$id" '[.state, .result, .cpu] | tojson')" = '["done","fail",2.25]' ] || fail "the record of a failing file does not say fail: $(cat "$ST/testactions/$id.json")"
  grep -q 'running tests/x.test.sh' "$ST/testactions/$id.txt" || fail "the failing file's output was not kept: $(cat "$ST/testactions/$id.txt")"
}

# Bug this guards (issue 517): a stopped run went on, or kept its test slot from every card.
t_tarunstop() {
  trsetup; local id out
  id=$(loop testaction run tests/x.test.sh 2>&1) && [[ $id =~ ^[0-9a-f]{12}$ ]] || fail "the run did not start: $id"
  wait_until '[ -s "$STUB/tr-held" ]' "cat '$ST/testactions/$id.err'" || fail "the test command did not start"
  out=$(loop testaction stop "$id" 2>&1) || fail "the stop failed: $out"
  [ "$(tarec "$id" '[.state, .result, (.end | type)] | tojson')" = '["stopped",null,"string"]' ] || fail "the stopped run's record does not say stopped: $(cat "$ST/testactions/$id.json")"
  ! kill -0 "$(cat "$STUB/tr-pid")" 2>/dev/null || fail "the test command still runs after the stop"
  trfree || fail "the stopped run still holds the test slot"
}

# Bug this guards (issue 42): a stopped run's record said stopped while a process of it still held its test slot. Its
# processes were looked for once, then ended: a child started after the look (watch()'s timer) was never ended. Here a
# process starts children all the time, each holding the lock it took, as the run's processes hold its slot: once
# taend() returns, the lock is free.
t_taendall() {
  local p f=$T/$CASE/slot
  mkdir -p "$T/$CASE" || fail "the case's folder"
  ( exec 7>>"$f"; flock 7; while :; do sleep 5 & sleep 0.01; done ) & p=$! # sleep: children started all the time, each holding the lock
  wait_until "! flock -n '$f' true" || fail "the process did not take the lock"
  # shellcheck disable=SC2034 # STATE is read by the sourced lib/testaction.sh (TESTACTS=${STATE%/*}/testactions)
  ( STATE=$T/$CASE/cards.jsonl; . "$SRC/lib/testaction.sh" && taend "$p" ) || fail "taend() could not be run"
  flock -n "$f" true || fail "a child started while the processes were looked for still runs, holding the lock"
}

# Bug this guards (issue 517): a run by hand of a path that is not a test file of main (a source file, a file main has
# not, a path out of the repo, a helper main has in a __tests__ folder) ran something, or took a slot.
t_tarunrefused() {
  trsetup; local p out
  mkdir -p "$R/tests/__tests__/lib" && echo 'helper() { :; }' > "$R/tests/__tests__/lib/helper.sh" && git -C "$R" add tests \
    && git -C "$R" commit -qm 'a test helper' || fail "the helper could not be committed"
  for p in a.txt tests/none.test.sh tests/../tests/x.test.sh "$R/tests/x.test.sh" tests/__tests__/lib/helper.sh; do
    out=$(loop testaction run "$p" 2>&1); [ $? = 2 ] && grep -q 'is not a test file' <<<"$out" || fail "the run of $p was not refused: $out"
  done
  [ ! -e "$STUB/tr-held" ] && [ -z "$(ls "$ST/testactions" 2>/dev/null)" ] && { [ ! -e "$T/$CASE/slots/1" ] || trfree; } || fail "a refused run ran, or took the slot: $(ls "$ST/testactions" 2>&1)"
}
