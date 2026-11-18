#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 300
# Engine cases: the test actions (lib/testaction.sh): `testaction judge|explain <test file>` runs one session of the
# control record's Tests seat about one test file, and the snapshot lists them; `testissue` files an issue for one.
# The queue is in testactqueue.test.sh, the stop in testactstop.test.sh and the run by hand in testactrun.test.sh;
# they use tasetup and tarec here.
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
  # A test line that timed the file, written while files had a CPU budget (its slow note, which the judge is not
  # given: no file has a budget now, #349), and a flaky entry of a case of it.
  jq -cn '{card: "c1-5", issue: 5, step: "test", time: "2026-11-01T00:00:00Z", tokens: {claude: 0, codex: 0}, result: "ok", sha: "", reason: "",
    times: {"tests/x.test.sh": 41.5, "tests/other.test.sh": 2}, clocks: {"tests/x.test.sh": 44}, slow: [{file: "tests/x.test.sh", sec: 44, cpu: 41.5, budget: 8, changed: false}]}' >> "$ST/cards.jsonl"
  # Bug it catches (#130): a file timed in whole-suite runs alone was "not timed" to the judge, while the Tests page
  # showed its runs: the whole-suite runs ($SUITERUNS) are in its recorded times too.
  jq -cn '{time: "2026-11-03T00:00:00Z", how: "full", sha: "", files: {"tests/x.test.sh": {result: "ok", sec: 50, cpu: 45.5}, "tests/other.test.sh": {result: "ok", sec: 1, cpu: 1}}}' > "$ST/suiteruns.jsonl"
  jq -cn '{time: "2026-11-07T00:00:00Z", how: "release", sha: "0123456789abcdef", files: {"tests/x.test.sh": {result: "fail", sec: 9, cpu: 8}}}' >> "$ST/suiteruns.jsonl"
  echo '{"entries":[{"case":"tests/x.test.sh: one","source":"c2-6","time":"2026-11-02T00:00:00Z","card":"c2-6","issue":6}],"filed":[]}' > "$ST/flaky.json"
  # Its failed test steps (#188): one failed on main too, with the end of its output; one the card's own change caused;
  # and one of another file.
  { jq -cn '{card: "c3-8", issue: 8, step: "test", time: "2026-11-04T00:00:00Z", result: "fail", failures: {of: 1, files: [{file: "tests/x.test.sh", cases: [{name: "two"}]}], timeout: null},
      verdicts: [{case: "tests/x.test.sh: two", verdict: "main"}], tail: "ok one\nnot ok two: port 8080 in use"}'
    jq -cn '{card: "c4-9", issue: 9, step: "test", time: "2026-11-05T00:00:00Z", result: "fail", failures: {of: 1, files: [{file: "tests/x.test.sh", cases: [{name: "one"}]}], timeout: null},
      verdicts: [{case: "tests/x.test.sh: one", verdict: "card"}], tail: "not ok one"}'
    jq -cn '{card: "c5-10", issue: 10, step: "test", time: "2026-11-05T00:00:00Z", result: "fail", failures: {of: 1, files: [{file: "tests/other.test.sh", cases: [{name: "three"}]}], timeout: null},
      verdicts: [{case: "tests/other.test.sh: three", verdict: "flaky"}], tail: "not ok three"}'
    # and one that passed on re-run (a `test pass` line, its first run's failures in rerun): the flaky failure.
    jq -cn '{card: "c6-11", issue: 11, step: "test", time: "2026-11-06T00:00:00Z", result: "pass", rerun: {exit: 1, failures: {files: [{file: "tests/x.test.sh", cases: [{name: "four"}]}], timeout: null}},
      verdicts: [{case: "tests/x.test.sh: four", verdict: "flaky"}]}'; } >> "$ST/cards.jsonl"
  # No Tests seat: no session starts, and the command says why.
  out=$(loop testaction judge tests/x.test.sh 2>&1); [ $? = 2 ] && grep -q 'no Tests seat is set' <<<"$out" || fail "a judge with no Tests seat was not refused, saying why: $out"
  [ ! -e "$STUB/ta-args" ] && [ ! -d "$ST/testactions" ] || fail "a judge with no Tests seat started a session: $(cat "$STUB/ta-args" 2>&1)"
  loop control tests claude m-tests high > /dev/null || fail "control tests was refused"
  # Its hollow cases (#77): two HOLLOW lines that read, and one with no kind, skipped and counted.
  printf '%s\n' 'It runs the whole loop for one check.' 'HOLLOW: reads the pack | mock-echo | it checks the stub returns what the stub was given' \
    '- HOLLOW: `one` | no-assert | it asserts nothing' 'HOLLOW: two | it only prints' 'CAUSE: two | shared state | it binds the fixed port 8080' 'CAUSE: one | luck | no kind' \
    '- WAIT: two | polling | `tests/x.test.sh:12` | it polls the port every second' 'WAIT: one | nap | tests/x.test.sh:3 | no kind' 'VERDICT: split' > "$STUB/ta-last"
  id=$(loop testaction judge tests/x.test.sh 2>&1) && [[ $id =~ ^[0-9a-f]{12}$ ]] || fail "the judge did not start: $id"
  # While the session runs: its text so far is in the file, and its record says running.
  wait_until "grep -q 'first words' '$ST/testactions/$id.txt'" "cat '$ST/testactions/$id.txt' '$ST/testactions/$id.err'" || fail "the text written so far is not in the text file while the session runs"
  [ "$(tarec "$id" '[.state, .end, .action, .file, .limit] | tojson')" = '["running",null,"judge","tests/x.test.sh",900]' ] || fail "the record does not say running while the session runs: $(cat "$ST/testactions/$id.json")"
  grep -q -- '--model m-tests --effort high' "$STUB/ta-args" || fail "the session did not start on the Tests seat's CLI, model and effort: $(cat "$STUB/ta-args")"
  out=$(cat "$STUB"/ta-prompt.*)
  grep -qF 'Test file: tests/x.test.sh' <<<"$out" && grep -qF '"times":41.5' <<<"$out" && grep -qF '"clocks":44' <<<"$out" \
    && grep -qF '{"time":"2026-11-03T00:00:00Z","whole":true,"how":"full","cpu":45.5,"sec":50,"result":"ok"}' <<<"$out" && ! grep -qi 'budget' <<<"$out" && grep -qF 'c1-5 (#5)' <<<"$out" \
    && grep -qF 'tests/x.test.sh: one' <<<"$out" && ! grep -qF 'other.test.sh' <<<"$out" || fail "the prompt does not name the file, its recorded times (its card runs and whole-suite runs), the cards that ran it and its flaky entries alone: $out"
  # Bug it catches (#188): the judge was given no failure, so it could not say why the file fails. It is given each
  # recent failure of the file alone, newest first: its verdict, card, failing cases and the end of its output; a step
  # that passed on re-run too.
  [[ $out == *$'\n- 2026-11-06T00:00:00Z, card c6-11 (#11), verdict flaky, failing cases: four\n- 2026-11-05T00:00:00Z, card c4-9 (#9), verdict card, failing cases: one\n  The end of its output:\n    not ok one\n- 2026-11-04T00:00:00Z, card c3-8 (#8), verdict main, failing cases: two\n  The end of its output:\n    ok one\n    not ok two: port 8080 in use'* ]] \
    && ! grep -qF 'not ok three' <<<"$out" && grep -qF 'CAUSE: <case> | <kind> | <one-line reason>' <<<"$out" && grep -qF 'VERDICT: <keep | speed up | split | merge | delete | stabilise>' <<<"$out" \
    || fail "the prompt does not give the failures of the file alone, with their verdicts, cards, cases and output, and ask for CAUSE lines and stabilise: $out"
  # Bug it catches (#335): the judge told the owner the file's newest run passed, read from a card's run, when the
  # release suite had failed it since. Its newest run is the release suite's failed run (newer than every card line
  # above), named as the run it is.
  grep -qF 'Its newest run, from the card test steps, the whole-suite runs (the release suite'"'"'s too) and its runs on its own: the release suite'"'"'s run on 0123456789ab, 2026-11-07T00:00:00Z: failed. When you say how its newest run ended, say it of this run and name it.' <<<"$out" \
    || fail "the prompt does not name the newer failed release run as the file's newest run: $out"
  : > "$STUB/ta-go"
  wait_until "[ \"\$(tarec $id .state)\" != running ]" "cat '$ST/testactions/$id.json'" || fail "the record still says running after the session ended"
  [ "$(tarec "$id" '[.state, .cli, .model, .effort, .verdict, (.end | type), has("pid")] | tojson')" = '["done","claude","m-tests","high","split","string",false]' ] \
    || fail "the record of the ended session is not done with its end time, CLI, model, effort and verdict: $(cat "$ST/testactions/$id.json")"
  # Bug it catches (#77): the judge's hollow cases were lost in its text, or a HOLLOW line that does not read failed the
  # record; the prompt did not ask for them.
  [ "$(tarec "$id" '[.hollow, .hollowSkipped] | tojson')" = '[[{"case":"reads the pack","kind":"mock-echo","reason":"it checks the stub returns what the stub was given"},{"case":"`one`","kind":"no-assert","reason":"it asserts nothing"}],1]' ] \
    || fail "the record does not hold the two hollow cases and the one HOLLOW line skipped: $(cat "$ST/testactions/$id.json")"
  grep -qF 'HOLLOW: <case> | <kind> | <one-line reason>' "$STUB"/ta-prompt.* || fail "the prompt does not ask for the hollow cases"
  # Bug it catches (#188): the causes the judge named were lost in its text; a CAUSE line with no kind is left out.
  [ "$(tarec "$id" '.causes | tojson')" = '[{"case":"two","kind":"shared state","reason":"it binds the fixed port 8080"}]' ] \
    || fail "the record does not hold the one CAUSE line that reads: $(cat "$ST/testactions/$id.json")"
  # Bug it catches (#189): the waits of a file that Waits were not asked for, or lost in the judge's text; a WAIT line
  # with no kind is left out.
  grep -qF 'WAIT: <case> | <kind> | <file:line> | <one-line reason>' "$STUB"/ta-prompt.* || fail "the prompt does not ask for the waits"
  [ "$(tarec "$id" '.waits | tojson')" = '[{"case":"two","kind":"polling","at":"tests/x.test.sh:12","reason":"it polls the port every second"}]' ] \
    || fail "the record does not hold the one WAIT line that reads: $(cat "$ST/testactions/$id.json")"
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

# The newest run the judge is told of (testfacts(), called as the session's start calls it).
tanewest() { ( export CONVEYOR_MAIN=$R CONVEYOR_CARDS=$T/$CASE/cards; . "$SRC/conveyor.sh" state-dir > /dev/null && eval "$(grep '^\. "\$HERE/lib/' "$SRC/commands/testaction.sh")" && testfacts tests/x.test.sh | jq -c .newest ); }
# Bugs it catches (#335): a card's test step where this file and another failed and this one alone passed when run
# again was told to the judge as a failed run of this file; and a run of the file on its own (Run this file now), newer
# than every card and suite run, was not read at all.
t_tanewest() {
  tasetup; local out
  jq -cn '{card: "c7-12", issue: 12, step: "test", time: "2026-11-08T00:00:00Z", result: "fail", failures: {of: 1, files: [{file: "tests/other.test.sh", cases: [{name: "b"}]}], timeout: null},
    rerun: {exit: 1, failures: {files: [{file: "tests/x.test.sh", cases: [{name: "a"}]}, {file: "tests/other.test.sh", cases: [{name: "b"}]}], timeout: null}}}' >> "$ST/cards.jsonl"
  out=$(tanewest)
  [ "$out" = '{"time":"2026-11-08T00:00:00Z","run":"the test step of card c7-12 (#12)","result":"failed, then passed when run again"}' ] \
    || fail "the newest run is not the card's step, where the file passed when run again: $out"
  mkdir -p "$ST/testactions" && jq -cn '{id: "0000000000bb", action: "run", file: "tests/x.test.sh", commit: "fedcba9876543210", start: "2026-11-09T00:00:00Z", end: "2026-11-09T00:01:00Z", state: "done", result: "fail"}' > "$ST/testactions/0000000000bb.json"
  out=$(tanewest)
  [ "$out" = '{"time":"2026-11-09T00:01:00Z","run":"its run on its own from the Tests page (test action 0000000000bb) on fedcba987654","result":"failed"}' ] \
    || fail "the newest run is not the file's run on its own: $out"
  # Bug: a step the machine held (result held, card.sh) with a time for the file was told as passed.
  jq -cn '{card: "c8-13", issue: 13, step: "test", time: "2026-11-10T00:00:00Z", result: "held", times: {"tests/x.test.sh": 1},
    failures: {files: [{file: "tests/x.test.sh", cases: [{name: "a"}]}], timeout: null}}' >> "$ST/cards.jsonl"
  out=$(tanewest)
  [ "$out" = '{"time":"2026-11-10T00:00:00Z","run":"the test step of card c8-13 (#13)","result":"failed (the card was held: the machine was at fault)"}' ] \
    || fail "a held step that failed the file is not told as failed and held: $out"
  # Bug: a run again that timed out in another file before it reached this one was told as this file passing on it.
  jq -cn '{card: "c9-14", issue: 14, step: "test", time: "2026-11-11T00:00:00Z", result: "fail",
    failures: {files: [{file: "tests/other.test.sh", cases: []}], timeout: {sec: 600, file: "tests/other.test.sh"}},
    rerun: {exit: 1, failures: {files: [{file: "tests/other.test.sh", cases: [{name: "b"}]}, {file: "tests/x.test.sh", cases: [{name: "a"}]}], timeout: null}}}' >> "$ST/cards.jsonl"
  out=$(tanewest)
  [ "$out" = '{"time":"2026-11-11T00:00:00Z","run":"the test step of card c9-14 (#14)","result":"failed, and its run again timed out in tests/other.test.sh before it was known to pass"}' ] \
    || fail "a run again that timed out before the file ran is told as the file passing on it: $out"
}
# Bugs it catches (#341): a card's step that kept the file as passed and did not run it, its time of the file carried
# from the card's earlier step (carried, carriedrec()), was told to the judge as a pass at its own time and as a run of
# it, not marked carried; once it was not, the earlier step that ran it, failed in another file (a failed step saves no times), was not
# told at all, leaving an older release-suite failure as the newest run; and dropping the carrying line lost the only
# times of that run and its card from the card list.
t_tacarried() {
  tasetup; local out
  jq -cn '{time: "2026-11-08T00:00:00Z", how: "release", sha: "0123456789abcdef", files: {"tests/x.test.sh": {result: "fail", sec: 1, cpu: 1}}}' >> "$ST/suiteruns.jsonl"
  jq -cn '{card: "c7-12", issue: 12, step: "test", time: "2026-11-09T00:00:00Z", result: "fail", failures: {of: 1, files: [{file: "tests/y.test.sh", cases: [{name: "b"}]}], timeout: null}}' >> "$ST/cards.jsonl"
  jq -cn '{card: "c7-12", issue: 12, step: "test", time: "2026-11-10T00:00:00Z", result: "pass", times: {"tests/x.test.sh": 1, "tests/y.test.sh": 2},
    clocks: {"tests/x.test.sh": 1, "tests/y.test.sh": 2}, carried: ["tests/x.test.sh"]}' >> "$ST/cards.jsonl"
  out=$( export CONVEYOR_MAIN=$R CONVEYOR_CARDS=$T/$CASE/cards; . "$SRC/conveyor.sh" state-dir > /dev/null && eval "$(grep '^\. "\$HERE/lib/' "$SRC/commands/testaction.sh")" \
    && testfacts tests/x.test.sh | jq -c '[.newest, (.runs | map([.card // "suite", .carried // false, .times // .sec])), .cards]')
  [ "$out" = '[{"time":"2026-11-09T00:00:00Z","run":"the test step of card c7-12 (#12)","result":"passed"},[["suite",false,1],["c7-12",true,1]],[{"card":"c7-12","issue":12}]]' ] \
    || fail "the newest run is not the failed step that passed the file, or the carried times are lost or not marked as carried: $out"
}
# Bug it catches (#342): a passing release-suite run and a failing run of the file on its own that ended in the same
# second (times are to the second) were told to the judge as one of them, the suite's pass, picked by its place in
# the list: both are named, with how each ended, and that which ran last is not known.
t_tasamesecond() {
  tasetup; local out
  jq -cn '{time: "2026-11-09T00:01:00Z", how: "release", sha: "0123456789abcdef", files: {"tests/x.test.sh": {result: "ok", sec: 1, cpu: 1}}}' >> "$ST/suiteruns.jsonl"
  mkdir -p "$ST/testactions" && jq -cn '{id: "0000000000bb", action: "run", file: "tests/x.test.sh", commit: "fedcba9876543210", start: "2026-11-09T00:00:00Z", end: "2026-11-09T00:01:00Z", state: "done", result: "fail"}' > "$ST/testactions/0000000000bb.json"
  out=$(tanewest)
  [ "$out" = '{"time":"2026-11-09T00:01:00Z","run":"its run on its own from the Tests page (test action 0000000000bb) on fedcba987654 and the release suite'"'"'s run on 0123456789ab, which ended in the same second, so which of them ran last is not known","result":"failed on its run on its own from the Tests page (test action 0000000000bb) on fedcba987654; passed on the release suite'"'"'s run on 0123456789ab"}' ] \
    || fail "two runs that ended in the same second are not both named, with how each ended: $out"
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

# Bug this guards (#188): a judge had no verdict for a file whose failures have a cause in the test, so it said keep;
# its stabilise verdict, as a model writes it (marked bold, in capitals), read as "no verdict".
t_taverdict() {
  local f=$T/taverdict.txt out
  printf '%s\n' 'Two cases share a port.' 'CAUSE: two | shared state | the fixed port' '**VERDICT: Stabilise**' > "$f"
  out=$(STATE=$T/taverdict/state . "$SRC/lib/testaction.sh" && taverdict "$f") && [ "$out" = '"stabilise"' ] || fail "a stabilise verdict does not read: $out"
  printf '%s\n' 'VERDICT: stable' > "$f"
  out=$(STATE=$T/taverdict/state . "$SRC/lib/testaction.sh" && taverdict "$f") && [ "$out" = '"no verdict"' ] || fail "a word that is no verdict reads as one: $out"
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
