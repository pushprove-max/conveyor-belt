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
tacommit() { GIT_AUTHOR_DATE=$1 GIT_COMMITTER_DATE=$1 git -C "$R" commit -qam "$2"; } # <time> <subject>: main's changes, made at <time>

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
    && ! grep -qF 'not ok three' <<<"$out" && grep -qF 'CAUSE: <case> | <kind> | <one-line reason>' <<<"$out" && grep -qF 'VERDICT: <keep | speed up | split | merge | delete | stabilise | indirect>' <<<"$out" \
    && grep -qF 'DIRECT: <what it protects> | <the direct check that would replace it> | <the cases that must keep passing, comma-separated>' <<<"$out" \
    || fail "the prompt does not give the failures of the file alone, with their verdicts, cards, cases and output, and ask for CAUSE and DIRECT lines, stabilise and indirect: $out"
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
  out=$(loop snapshot --fresh | jq -c '.modelSettings.builder.allowed as $b | .testActions | [.seat, .limit, [.actions[] | [.id, .state, .verdict, (.text | test("^first words\n(.|\n)*VERDICT: split\n$")), .textCut]],
    (.allowed == $b and (.allowed.claude | index("m") != null))]')
  [ "$out" = "[{\"cli\":\"claude\",\"model\":\"m-tests\",\"effort\":\"high\"},900,[[\"$id\",\"done\",\"split\",true,false]],true]" ] || fail "the snapshot does not list the seat, the action with its state and text, and the pack's models by CLI: $out"
  # shellcheck source=/dev/null # the snapshot's libraries, by the list snapshot.sh names (SNAPLIBS)
  out=$( export CONVEYOR_MAIN=$R CONVEYOR_CARDS=$T/$CASE/cards; . "$SRC/conveyor.sh" state-dir > /dev/null && eval "$(grep '^SNAPLIBS=' "$SRC/commands/snapshot.sh")" && for l in $SNAPLIBS; do . "$HERE/lib/$l.sh" || exit 1; done && TATEXT_MAX=7 testacts | jq -c '.[0] | [.text, .textCut]')
  [ "$out" = '["split\n\n",true]' ] || fail "a text over TATEXT_MAX is not its end alone, marked cut: $out"
  # Bug it catches: an action older than the newest TATEXT_SHOWN was listed with text null, so after a reload the
  # Board's View and Copy of that result had no text. Past the newest, only a file's newest judge with a verdict is
  # listed (the issue preview's verdict), with its text; an older explain is left out.
  jq -cn '{id: "0000000000aa", action: "explain", file: "tests/x.test.sh", start: "2020-01-01T00:00:00Z", end: "2020-01-01T00:01:00Z", state: "done"}' > "$ST/testactions/0000000000aa.json"
  echo old > "$ST/testactions/0000000000aa.txt"
  # shellcheck source=/dev/null # the snapshot's libraries, by the list snapshot.sh names (SNAPLIBS)
  out=$( export CONVEYOR_MAIN=$R CONVEYOR_CARDS=$T/$CASE/cards; . "$SRC/conveyor.sh" state-dir > /dev/null && eval "$(grep '^SNAPLIBS=' "$SRC/commands/snapshot.sh")" && for l in $SNAPLIBS; do . "$HERE/lib/$l.sh" || exit 1; done && TATEXT_SHOWN=0 testacts | jq -c '[.[] | [.id, (.text | type)]]')
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
# from the card's earlier step (carried, testlist.sh carriedrec()), was told to the judge as a pass at its own time and as a run of
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
# Bug it catches (#1461 B-R336): a step that ran some cases of the file has no time of it (a runner times no file it
# ran in part; testlist.sh partran()), so its line names the file partial; without it that passing step was not told,
# and an older release-suite failure stood as the newest run.
t_tapartial() {
  tasetup; local out
  jq -cn '{time: "2026-11-08T00:00:00Z", how: "release", sha: "0123456789abcdef", files: {"tests/x.test.sh": {result: "fail", sec: 1, cpu: 1}}}' >> "$ST/suiteruns.jsonl"
  jq -cn '{card: "c7-12", issue: 12, step: "test", time: "2026-11-10T00:00:00Z", result: "pass", times: {"tests/y.test.sh": 2}, clocks: {"tests/y.test.sh": 2}, partial: ["tests/x.test.sh"]}' >> "$ST/cards.jsonl"
  out=$( export CONVEYOR_MAIN=$R CONVEYOR_CARDS=$T/$CASE/cards; . "$SRC/conveyor.sh" state-dir > /dev/null && eval "$(grep '^\. "\$HERE/lib/' "$SRC/commands/testaction.sh")" \
    && testfacts tests/x.test.sh | jq -c '[.newest, (.runs | map(.card // "suite"))]')
  [ "$out" = '[{"time":"2026-11-10T00:00:00Z","run":"the test step of card c7-12 (#12)","result":"passed"},["suite"]]' ] \
    || fail "testfacts tests/x.test.sh, its only card step naming it partial: the newest run is not that step, or the step is given a time of it: $out"
  # Bug it catches: a later step that ran a case of the file too but gave no result (killed after the runner named the
  # case, before it ended: cardfailed()'s no-result line, its partial part and no failures), was told as a pass of it.
  # It is no run of it with a result: the passing step stays the newest.
  jq -cn '{card: "c8-13", issue: 13, step: "test", time: "2026-11-11T00:00:00Z", result: "fail", reason: "no result: exit 143: the run was killed by a signal", partial: ["tests/x.test.sh"]}' >> "$ST/cards.jsonl"
  out=$(tanewest)
  [ "$out" = '{"time":"2026-11-10T00:00:00Z","run":"the test step of card c7-12 (#12)","result":"passed"}' ] \
    || fail "testfacts tests/x.test.sh, a no-result step (11-11) that names it partial: the newest run is not the passing step of 11-10: $out"
  # Bug it catches (#1461 follow-up): a step that named x partial and timed out in another file (y, on both attempts)
  # was dropped, but a file past its own limit leaves the others to run to their end (testrun.sh filecmd()), so the
  # cases of x that step ran had passed: it is the newest run of x, not the older 11-10 step.
  jq -cn '{card: "c9-14", issue: 14, step: "test", time: "2026-11-12T00:00:00Z", result: "fail", partial: ["tests/x.test.sh"],
    failures: {files: [], timeout: {sec: 600, file: "tests/y.test.sh"}, stopped: ["tests/y.test.sh"]},
    rerun: {failures: {files: [], timeout: {sec: 600, file: "tests/y.test.sh"}, stopped: ["tests/y.test.sh"]}}}' >> "$ST/cards.jsonl"
  out=$(tanewest)
  [ "$out" = '{"time":"2026-11-12T00:00:00Z","run":"the test step of card c9-14 (#14)","result":"passed"}' ] \
    || fail "testfacts tests/x.test.sh, a step (11-12) naming it partial whose timeout names tests/y.test.sh on both attempts: the newest run is not that step's pass: $out"
  # Bug it catches (E1): when x timed out too on both attempts, before y did, the timeout named y alone (the last file
  # open) and that step was told as a pass of x. Its last attempt's stopped names x: it is no pass, and 11-12 stays newest.
  jq -cn '{card: "c10-15", issue: 15, step: "test", time: "2026-11-13T00:00:00Z", result: "fail", partial: ["tests/x.test.sh"],
    failures: {files: [], timeout: {sec: 600, file: "tests/y.test.sh"}, stopped: ["tests/x.test.sh", "tests/y.test.sh"]},
    rerun: {failures: {files: [], timeout: {sec: 600, file: "tests/y.test.sh"}, stopped: ["tests/x.test.sh", "tests/y.test.sh"]}}}' >> "$ST/cards.jsonl"
  out=$(tanewest)
  [ "$out" = '{"time":"2026-11-12T00:00:00Z","run":"the test step of card c9-14 (#14)","result":"passed"}' ] \
    || fail "testfacts tests/x.test.sh, a step (11-13) naming it partial whose stopped names it and tests/y.test.sh on both attempts: the newest run is not the 11-12 pass: $out"
  # Bug it catches (E2): x stopped on the first attempt (w failed, x and y past their limits), and on the run again w
  # used up the run's limit, so x never ran again. Only the first attempt's stopped names x: it is no pass of x.
  jq -cn '{card: "c11-16", issue: 16, step: "test", time: "2026-11-14T00:00:00Z", result: "fail", partial: ["tests/x.test.sh"],
    failures: {files: [], timeout: {sec: 600, file: "tests/w.test.sh"}, stopped: ["tests/w.test.sh"]},
    rerun: {failures: {files: [{file: "tests/w.test.sh", cases: []}], timeout: {sec: 600, file: "tests/y.test.sh"}, stopped: ["tests/x.test.sh", "tests/y.test.sh"]}}}' >> "$ST/cards.jsonl"
  out=$(tanewest)
  [ "$out" = '{"time":"2026-11-12T00:00:00Z","run":"the test step of card c9-14 (#14)","result":"passed"}' ] \
    || fail "testfacts tests/x.test.sh, a step (11-14) naming it partial whose first attempt's stopped names it and whose run again timed out in tests/w.test.sh: the newest run is not the 11-12 pass: $out"
  # Bug it catches: the same first attempt, but a run again that did not time out ran each file it chose, x too, to its
  # end; w failed and x did not, so that step is the newest run of x and passed it.
  jq -cn '{card: "c12-17", issue: 17, step: "test", time: "2026-11-15T00:00:00Z", result: "fail", partial: ["tests/x.test.sh"],
    failures: {files: [{file: "tests/w.test.sh", cases: []}], timeout: null},
    rerun: {failures: {files: [{file: "tests/w.test.sh", cases: []}], timeout: {sec: 600, file: "tests/y.test.sh"}, stopped: ["tests/x.test.sh", "tests/y.test.sh"]}}}' >> "$ST/cards.jsonl"
  out=$(tanewest)
  [ "$out" = '{"time":"2026-11-15T00:00:00Z","run":"the test step of card c12-17 (#17)","result":"passed"}' ] \
    || fail "testfacts tests/x.test.sh, a step (11-15) naming it partial whose first attempt's stopped names it and whose run again ended with tests/w.test.sh failed: the newest run is not that step's pass: $out"
}
# Bug it catches (O238): a carried line's times were dated to the later step that carried them, so a card step that ran
# the file before a release suite failed it was listed after that suite in runs, which are oldest first. The file
# passes in c7-12's failed step at T1, fails in the release suite at T2 and is carried by the fix step at T3: T1 first.
t_tacarrieddate() {
  tasetup; local out
  jq -cn '{card: "c7-12", issue: 12, step: "test", time: "2026-11-09T00:00:00Z", result: "fail", failures: {of: 1, files: [{file: "tests/y.test.sh", cases: [{name: "b"}]}], timeout: null}}' >> "$ST/cards.jsonl"
  jq -cn '{time: "2026-11-09T12:00:00Z", how: "release", sha: "0123456789abcdef", files: {"tests/x.test.sh": {result: "fail", sec: 1, cpu: 1}}}' >> "$ST/suiteruns.jsonl"
  jq -cn '{card: "c7-12", issue: 12, step: "test", time: "2026-11-10T00:00:00Z", result: "pass", times: {"tests/x.test.sh": 1}, carried: ["tests/x.test.sh"]}' >> "$ST/cards.jsonl"
  out=$( export CONVEYOR_MAIN=$R CONVEYOR_CARDS=$T/$CASE/cards; . "$SRC/conveyor.sh" state-dir > /dev/null && eval "$(grep '^\. "\$HERE/lib/' "$SRC/commands/testaction.sh")" \
    && testfacts tests/x.test.sh | jq -c '.runs | map([.card // "suite", .time])')
  [ "$out" = '[["c7-12","2026-11-09T00:00:00Z"],["suite","2026-11-09T12:00:00Z"]]' ] \
    || fail "testfacts tests/x.test.sh did not date the carried times to the step that ran the file, before the release suite: $out"
}
# Bug it catches (#1036): the Tests page showed the time the test-speed survey saved in .conveyor/test-times.json as
# the file's newest run, but Judge and Explain were given only the card runs, so they judged a time the page did not
# show. The survey's time is one of the runs, marked survey, dated by the commit that wrote it.
t_tasurvey() {
  tasetup; local out
  jq -cn '{card: "c7-12", issue: 12, step: "test", time: "2026-11-08T00:00:00Z", result: "pass", times: {"tests/x.test.sh": 1}}' >> "$ST/cards.jsonl"
  mkdir -p "$R/.conveyor" && echo '{"files": {"tests/x.test.sh": {"sec": 7.5, "cpu": 6.25}}}' > "$R/.conveyor/test-times.json" \
    && git -C "$R" add -f .conveyor/test-times.json && GIT_COMMITTER_DATE=2026-11-12T00:00:00Z git -C "$R" commit -qm times || fail "the saved times"
  out=$( export CONVEYOR_MAIN=$R CONVEYOR_CARDS=$T/$CASE/cards; . "$SRC/conveyor.sh" state-dir > /dev/null && eval "$(grep '^\. "\$HERE/lib/' "$SRC/commands/testaction.sh")" \
    && testfacts tests/x.test.sh | jq -c '.runs')
  [ "$out" = '[{"card":"c7-12","issue":12,"time":"2026-11-08T00:00:00Z","times":1},{"time":"2026-11-12T00:00:00Z","survey":true,"cpu":6.25,"sec":7.5}]' ] \
    || fail "the survey's saved time is not one of the runs Judge and Explain are given: $out"
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
  # #1330 D2: the rule Tests page issues is on unless the owner turns it off, and on, the action files its issue (below).
  [ "$(loop control | jq -c .rules.testissues)" = true ] || fail "the rule Tests page issues is not on by default: $(loop control | jq -c .rules)"
  out=$(loop testissue tests/x.test.sh "Speed up tests/x.test.sh" "Measured: 12 CPU s.") || fail "testissue failed: $out"
  [ "$out" = https://github.com/o/r/issues/100101 ] || fail "testissue does not print the issue's address: $out"
  [ "$(jq -c '[.title, (.labels | map(.name))]' "$STUB/filed")" = '["Speed up tests/x.test.sh",["bug","P2"]]' ] || fail "the issue filed: $(cat "$STUB/filed")"
  [ "$(jq -c '[.event, .file, .issue]' "$ST/testactions/filed.jsonl")" = '["filed","tests/x.test.sh",100101]' ] || fail "the issue is not kept for the file: $(cat "$ST/testactions/filed.jsonl" 2>&1)"
  loop testissue tests/gone.test.sh t b 2> /dev/null; [ $? = 2 ] && [ "$(wc -l < "$STUB/filed")" = 1 ] || fail "testissue of a file main lacks did not refuse"
  # The Board's filing, with new issues starting in the queue, leaves the issue queued (#961: the owner pressed the button).
  [ "$(loop control | jq -c '[.start, .held]')" = '["queue",[]]' ] || fail "an issue the owner filed with new issues in the queue was held: $(loop control)"
}
# Bug this guards (#961): an issue a Foreman session filed through testissue was not held, as the Foreman's filing
# hooks never see it, so it was built before the owner's yes. Both of the Foreman's marks: the session the mark file
# names, and the launcher's CONVEYOR_FOREMAN=1.
t_taissuefm() {
  tasetup; local out
  mkdir -p "$ST/foreman" && echo "fm-1 2026-11-20T00:00:00Z" > "$ST/foreman/session"
  out=$(CLAUDE_CODE_SESSION_ID=fm-1 loop testissue tests/x.test.sh "Speed up tests/x.test.sh" "Measured: 12 CPU s." 2> "$STUB/ti.err") || fail "testissue failed: $out"
  [ "$out" = https://github.com/o/r/issues/100101 ] || fail "testissue does not print the issue's address alone: $out"
  [ "$(loop control | jq -c .held)" = '[100101]' ] || fail "the issue the marked Foreman session filed is not held: $(loop control)"
  grep -q '#100101 is held, as it was filed for a Foreman session' "$STUB/ti.err" || fail "testissue did not say it held the issue: $(cat "$STUB/ti.err")"
  loop control release 100101 > /dev/null || fail "the release was refused"
  CONVEYOR_FOREMAN=1 loop testissue tests/x.test.sh t b > /dev/null 2>&1 || fail "testissue with CONVEYOR_FOREMAN=1 failed"
  [ "$(loop control | jq -c .held)" = "[$(jq -s '.[-1].issue' "$ST/testactions/filed.jsonl")]" ] || fail "the issue filed with CONVEYOR_FOREMAN=1 is not held: $(loop control)"
}
# Bug this guards (#961): with New issues start in set to Held, an issue filed from the Tests page was queued and
# picked at once.
t_taissueheld() {
  tasetup
  loop control start held > /dev/null 2>&1 || fail "start held was refused"
  loop testissue tests/x.test.sh "Speed up tests/x.test.sh" "Measured: 12 CPU s." > /dev/null 2> "$STUB/ti.err" || fail "testissue failed: $(cat "$STUB/ti.err")"
  [ "$(loop control | jq -c .held)" = '[100101]' ] || fail "the issue filed while new issues start held is not held: $(loop control)"
  grep -q '#100101 is held, as new issues start held' "$STUB/ti.err" || fail "testissue did not say it held the issue: $(cat "$STUB/ti.err")"
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

# Bug this guards (#778): a judge found a file that checks what it protects through a proxy (it runs the suite again),
# and its record had no verdict for it and no part to rewrite, so the Tests page could not offer the direct check. The
# record's fields (tajudged(), as the end of tarun() writes them) hold the verdict indirect and each DIRECT line that
# reads, its cases split; a DIRECT line with no case is left out. Bug this guards too (#827): a | inside a DIRECT
# line's check text made the rest of the check its case list, so a rewrite card was blocked on cases that never
# existed; the cases are the text after the last |, and the check keeps its own |.
t_tadirect() {
  local f=$T/tadirect.txt out
  mkdir -p "$T/tadirect/wt" && printf 't_%s() { :; }\n' relfiles relpins case1 case2 > "$T/tadirect/wt/f.test.sh"
  printf '%s\n' 'It runs the whole suite again from a copy.' \
    '- DIRECT: the install holds the right files | compare the installed list with the manifest | `relfiles`, relpins' \
    'DIRECT: a | run x | y, which z | case1, case2' \
    'DIRECT: the loop lands | no cases named |' '**VERDICT: Indirect**' > "$f"
  out=$(export STATE=$T/tadirect/state && . "$SRC/lib/testaction.sh" && . "$SRC/lib/testfiles.sh" && . "$SRC/lib/testrun.sh" && tajudged "$f" "$T/tadirect/wt" f.test.sh | jq -c '{verdict, direct}') \
    && [ "$out" = '{"verdict":"indirect","direct":[{"protects":"the install holds the right files","check":"compare the installed list with the manifest","cases":["relfiles","relpins"]},{"protects":"a","check":"run x | y, which z","cases":["case1","case2"]}]}' ] \
    || fail "the record of an indirect judge does not hold its verdict and DIRECT lines: $out"
}

# Bug this guards (#827): a judge named on a DIRECT line of views.test.sh cases that snapshot.test.sh defines, and the
# rewrite card was blocked for dropping cases the file never had. Read as tarun() reads it, with the judged file at the
# judge's commit, the record keeps the line with only the cases the file defines and lists the other as dropped. The
# file's cases are read from its case start lines (testfiles.sh's table), so a case that only calls snapfixlive does
# not hold a case of that name, as a scan of the whole file would.
t_tadirectin() {
  local d=$T/tadirectin out
  mkdir -p "$d/wt" && printf '%s\n' 't_relfiles() { :; }' 't_relpins() { snapfixlive; }' > "$d/wt/f.test.sh"
  printf '%s\n' 'DIRECT: the install holds the right files | compare the list | relfiles, snapfixlive, relpins' 'VERDICT: indirect' > "$d/t.txt"
  out=$(export STATE=$d/state && . "$SRC/lib/testaction.sh" && . "$SRC/lib/testfiles.sh" && . "$SRC/lib/testrun.sh" && tajudged "$d/t.txt" "$d/wt" f.test.sh | jq -c .direct) \
    && [ "$out" = '[{"protects":"the install holds the right files","check":"compare the list","cases":["relfiles","relpins"],"dropped":["snapfixlive"]}]' ] \
    || fail "the record keeps a case another test file defines: $out"
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

# Bug it catches (#344): the snapshot gave the test actions, each with up to TATEXT_MAX of its text, to jq as one
# argument, which Linux refuses over 128 KiB ("Argument list too long"), so the Board stopped refreshing. Ten ended
# actions with 16,000 bytes of text each (about 160 KB): the snapshot lists every one with its text.
t_tabigtexts() {
  local i id out
  setup '[]'; mkdir -p "$ST/testactions"
  for i in 0 1 2 3 4 5 6 7 8 9; do
    id=00000000000$i
    jq -cn --arg id "$id" --arg s "2026-01-01T00:0$i:00Z" '{id: $id, action: "explain", file: "tests/x.test.sh", start: $s, end: $s, state: "done"}' > "$ST/testactions/$id.json"
    head -c 16000 /dev/zero | tr '\0' x > "$ST/testactions/$id.txt"
  done
  out=$(loop snapshot --fresh 2>&1 | jq -c '[.testActions.actions[] | .text | length] | [length, unique]' 2>&1)
  [ "$out" = '[10,[16000]]' ] || fail "the snapshot does not list the ten actions with their texts: ${out:0:300}"
}

# The setup of an explain case: main maps src/a.sh to tests/x.test.sh and shares tests/lib.sh with every test (the
# pack's test.map, in lines of areas), and a card, c9-14, landed a commit that changed the test file, src/a.sh and
# src/b.sh, after which the file ran 10 times slower; c8-13 landed before it, between the last fast run and c9-14's
# slow one, a commit that added <n> lines to the test file; c1-5 landed before its first run, so its change is not
# around the rise. <lines> are added to the test file by c9-14. Each commit is made at the time its card landed.
taslowed() { # <n> <lines of the test file's change>
  tasetup; local sha old i
  mkdir -p "$R/src" && echo 'a=1' > "$R/src/a.sh" && echo 'b=1' > "$R/src/b.sh" && echo 'h=1' > "$R/tests/lib.sh" \
    && printf '%s\n' '{"area": "core", "tests": "all"}' '{"area": "core", "file": "tests/lib.sh"}' '{"area": "a", "file": "src/a.sh"}' '{"area": "a", "test": "tests/x.test.sh"}' > "$R/map.json" \
    && git -C "$R" add src tests map.json && tacommit 2026-11-01T01:00:00Z 'the sources' || fail "the sources could not be committed"
  tune '.test.map = "map.json"'
  for i in $(seq 1 "$1"); do echo "echo old line $i" >> "$R/tests/x.test.sh"; done
  tacommit 2026-11-02T12:00:00Z 'Log more' && old=$(git -C "$R" rev-parse HEAD) || fail "the older card's change could not be committed"
  shift
  printf '%s\n' "$@" >> "$R/tests/x.test.sh" && echo 'retry 9 # a=2' > "$R/src/a.sh" && echo 'b=2 # not mapped' > "$R/src/b.sh" \
    && tacommit 2026-11-03T01:00:00Z 'Wait for the port' && sha=$(git -C "$R" rev-parse HEAD) || fail "the card's change could not be committed"
  jq -cn --arg s "$sha" --arg m "$old" --arg o "$(git -C "$R" rev-parse HEAD~2)" '{card: "c1-5", issue: 5, step: "test", time: "2026-11-01T00:00:00Z", result: "pass", times: {"tests/x.test.sh": 1}},
    {card: "c1-5", issue: 5, step: "landed", time: "2026-11-01T01:00:00Z", sha: $o},
    {card: "c2-6", issue: 6, step: "test", time: "2026-11-02T00:00:00Z", result: "pass", times: {"tests/x.test.sh": 1.2}},
    {card: "c8-13", issue: 13, step: "landed", time: "2026-11-02T12:00:00Z", sha: $m},
    {card: "c9-14", issue: 14, step: "test", time: "2026-11-03T00:00:00Z", result: "pass", times: {"tests/x.test.sh": 10}},
    {card: "c9-14", issue: 14, step: "landed", time: "2026-11-03T01:00:00Z", sha: $s},
    {card: "c10-15", issue: 15, step: "test", time: "2026-11-04T00:00:00Z", result: "pass", times: {"tests/x.test.sh": 10.5}}' >> "$ST/cards.jsonl"
  TASHA=$sha
}
# Bug it catches (#767): the explain session has no git, and its facts named the card it blamed but held none of its
# change, so it could not say what in it made the file slower. The prompt holds the card's commit, subject, changed
# files and its diff of the test file and the mapped source, not of a file the map does not link; not the change of a
# card that landed before the rise; the change of the card of the slow run comes before an older one's; and the
# session keeps Read, Grep and Glob alone.
t_taexplainchange() {
  taslowed 2 'nc -l 8080 & wait'; local id out
  loop control tests claude m-tests high > /dev/null || fail "control tests was refused"
  # Asked as the Board asks it, with --time: a zone of 5 hours west of UTC with no daylight time, named EST (a POSIX TZ,
  # so no zone database is needed), while this machine is in UTC, and the 12-hour Time setting.
  id=$(TZ=UTC loop testaction explain --time EST5 12-hour tests/x.test.sh 2>&1) && [[ $id =~ ^[0-9a-f]{12}$ ]] || fail "the explain did not start: $id"
  [ "$(tarec "$id" '[.zone, .hours] | tojson')" = '["EST5","12-hour"]' ] || fail "the record does not keep the zone and Time of the ask: $(cat "$ST/testactions/$id.json")"
  # Polled: the prompt is built in the queue's start of the session (tastart()), which runs apart from the ask, and the
  # stub session writes it only once it runs; what the session is given is what only a started session shows.
  wait_until "grep -q 'first words' '$ST/testactions/$id.txt'" "cat '$ST/testactions/$id.err'" || fail "the session did not start"
  : > "$STUB/ta-go"; out=$(cat "$STUB"/ta-prompt.*)
  grep -qF "Card c9-14 (#14), landed as commit $TASHA at 2026-11-02 8:00:00 PM EST: Wait for the port" <<<"$out" && grep -qF 'tests/x.test.sh (+1, -0)' <<<"$out" \
    && grep -qF 'src/b.sh (+1, -1)' <<<"$out" && grep -qF '+nc -l 8080 & wait' <<<"$out" && grep -qF '+retry 9 # a=2' <<<"$out" \
    && ! grep -qF '+b=2 # not mapped' <<<"$out" && ! grep -qF 'Card c1-5' <<<"$out" \
    && grep -qF 'from its last run at its usual time (1.2 s at 2026-11-01 7:00:00 PM EST) to its first slower run (10 s at 2026-11-02 7:00:00 PM EST, the test step of card c9-14)' <<<"$out" \
    || fail "the prompt does not hold the change of the card that landed at the rise (its commit, files and diff of the test file and its mapped source) alone: $out"
  # Bug it catches (#770): the facts gave each time in UTC, then in the build machine's zone, while the Board shows the
  # zone of its browser and its clock.
  grep -qF '{"card":"c2-6","issue":6,"time":"2026-11-01 7:00:00 PM EST","times":1.2}' <<<"$out" && ! grep -qF '2026-11-02T00:00:00Z' <<<"$out" \
    && ! grep -qF ' UTC' <<<"$out" || fail "the prompt's runs are not in the zone and clock the Board sent: $out"
  grep -qF 'Weigh every commit in that window: do not blame a card only because its run was the first slower one.' <<<"$out" \
    || fail "the explain prompt does not ask the session to weigh every commit in the window: $out"
  grep -qF '+echo old line 2' <<<"$out" && [ "$(grep -oE '^Card c(9-14|8-13) ' <<<"$out" | tr -d '\n')" = 'Card c9-14 Card c8-13 ' ] \
    || fail "the change of the card of the slow run does not come first, before the older card's: $out"
  grep -q -- '--tools Read,Grep,Glob --setting-sources' "$STUB/ta-args" || fail "the explain session is not kept to Read, Grep and Glob: $(cat "$STUB/ta-args")"
}
# Bug it catches (#767): a big change filled the session's prompt with no end. Its diffs keep to TACHANGEMAX
# characters, cut at a whole line, and the facts say which lines and files of the diff are left out. The older card's
# 40-line diff, given first, took the whole limit and left out all of the diff of the card of the slow run (E1).
t_taexplaincut() {
  local out
  taslowed 40 'nc -l 8080 & wait'
  # shellcheck disable=SC2034 # TACHANGEMAX is read by tachanges()
  out=$( export CONVEYOR_MAIN=$R CONVEYOR_CARDS=$T/$CASE/cards; . "$SRC/conveyor.sh" state-dir > /dev/null && eval "$(grep '^\. "\$HERE/lib/' "$SRC/commands/testaction.sh")" \
    && TACHANGEMAX=1000 && tachanges tests/x.test.sh "$(testfacts tests/x.test.sh)" "$R")
  grep -qF '+retry 9 # a=2' <<<"$out" && grep -qF '+nc -l 8080 & wait' <<<"$out" \
    || fail "the diff of the card of the slow run is not given whole before an older card's: $out"
  grep -qF '+echo old line 1' <<<"$out" && ! grep -qF '+echo old line 40' <<<"$out" && [ "$(grep -c '^\[Left out' <<<"$out")" = 1 ] \
    && sed -n '/^Card c8-13 /,$p' <<<"$out" | grep -qE '^\[Left out: lines [0-9]+ to [0-9]+ of its [0-9]+ lines of diff, of the files tests/x.test.sh; the diffs of these facts keep to 1000 characters\.\]$' \
    || fail "the older card's diff over the limit is not cut at it, saying which lines and files are left out: $out"
  # 1000 characters and the newline that ends the last line kept of each of the two diffs (a diff has no empty line).
  [ "$(awk '/^Its diff:$/ { d = 1; next } /^\[Left out|^Card / { d = 0 } d && $0 != "" { c += length($0) + 1 } END { print c + 0 }' <<<"$out")" -le 1002 ] \
    || fail "the diffs kept are over the limit: $out"
  # Bug it catches (E2): when a whole-suite run marks the rise, the facts said the card of that run came first, though
  # that run has no card (and the line naming the rise came out empty). The same fixture, its slow run of c9-14 read as
  # one of the full suite, names the rise and says all the cards come oldest first.
  out=$( export CONVEYOR_MAIN=$R CONVEYOR_CARDS=$T/$CASE/cards; . "$SRC/conveyor.sh" state-dir > /dev/null && eval "$(grep '^\. "\$HERE/lib/' "$SRC/commands/testaction.sh")" \
    && tachanges tests/x.test.sh "$(testfacts tests/x.test.sh | jq -c '.runs |= map(if .card == "c9-14" then del(.card, .issue) + {whole: true} else . end)')" "$R" | head -n 1)
  grep -qF ', a whole-suite run). The commits made in that window' <<<"$out" && grep -qF '), all of them oldest first, each with' <<<"$out" && ! grep -qF 'that commit first' <<<"$out" \
    || fail "the facts of a rise marked by a whole-suite run do not say all the cards come oldest first: $out"
}
# Bug it catches (#770): the explain facts named only the cards whose runs or landings fell around the rise, so the
# session blamed the card of the first slow run while a commit to the shared test helper in the window was not in
# them. Three more commits in the window (c2-6's fast run to c9-14's slow one): c11-16's to tests/lib.sh (shared
# with every test by the map), c12-17's to src/b.sh (linked to no test) and one by hand to the test file, with no card.
t_taexplainwindow() {
  local out h fix
  taslowed 2 'nc -l 8080 & wait'
  echo 'h=2 # one fixture a file' > "$R/tests/lib.sh" && tacommit 2026-11-02T13:00:00Z 'Share the fixture' && h=$(git -C "$R" rev-parse HEAD) \
    && echo 'b=3' > "$R/src/b.sh" && tacommit 2026-11-02T14:00:00Z 'Tidy b' \
    && echo 'echo by hand' >> "$R/tests/x.test.sh" && tacommit 2026-11-02T15:00:00Z 'A line by hand' && fix=$(git -C "$R" rev-parse HEAD) \
    || fail "the commits in the window could not be made"
  jq -cn --arg h "$h" --arg b "$(git -C "$R" rev-parse HEAD~1)" '{card: "c11-16", issue: 16, step: "landed", time: "2026-11-02T13:00:00Z", sha: $h},
    {card: "c12-17", issue: 17, step: "landed", time: "2026-11-02T14:00:00Z", sha: $b}' >> "$ST/cards.jsonl"
  # tachanges() alone, in a zone 5 hours west of UTC with no daylight time (a POSIX TZ: no zone database is needed),
  # on a clock of <$1> (empty: none given) and the facts changed by the jq filter <$2>.
  tawin() { ( export CONVEYOR_MAIN=$R CONVEYOR_CARDS=$T/$CASE/cards TZ=EST5
    . "$SRC/conveyor.sh" state-dir > /dev/null && eval "$(grep '^\. "\$HERE/lib/' "$SRC/commands/testaction.sh")" \
    && tachanges tests/x.test.sh "$(testfacts tests/x.test.sh | jq -c "$2")" "$R" ${1:+"$1"} ); }
  out=$(tawin '' .)
  grep -qF 'The window of the rise in its time: from its last run at its usual time (1.2 s at 2026-11-01 7:00:00 PM EST) to its first slower run (10 s at 2026-11-02 7:00:00 PM EST, the test step of card c9-14)' <<<"$out" \
    || fail "the facts do not name the window of the rise, in the machine's zone on a 12-hour clock: $out"
  [ "$(grep -oE '^(Card c[0-9-]+|Commit [0-9a-f]+)' <<<"$out" | tr '\n' ' ')" = "Card c9-14 Card c8-13 Card c11-16 Commit $fix " ] \
    && grep -qF "Card c11-16 (#16), landed as commit $h at 2026-11-02 8:00:00 AM EST: Share the fixture" <<<"$out" && grep -qF '+h=2 # one fixture a file' <<<"$out" \
    && grep -qF "Commit $fix at 2026-11-02 10:00:00 AM EST, landed by no card on record: A line by hand" <<<"$out" \
    && ! grep -qF 'c12-17' <<<"$out" && ! grep -qF '+b=3' <<<"$out" \
    || fail "the facts do not list the commits in the window that changed the test file or the shared helper, with their cards, and only those: $out"
  out=$(tawin 24-hour .)
  grep -qF '(1.2 s at 2026-11-01 19:00:00 EST)' <<<"$out" && grep -qF "landed as commit $h at 2026-11-02 08:00:00 EST" <<<"$out" \
    || fail "the facts' times do not follow a 24-hour Time setting: $out"
  # The window moved past every commit in it, its slow run of a card that never landed: none is in it, and it says so.
  out=$(tawin '' '.runs |= map(if .card == "c2-6" then .time = "2026-11-02T16:00:00Z" elif .card == "c9-14" then .card = "c99-99" else . end)')
  grep -qF 'oldest first, each with its card and its diff of those files: none: no commit that changed one of these files was made in that window.' <<<"$out" \
    && ! grep -qE '^(Card|Commit) ' <<<"$out" || fail "the facts of a window with no commit in it do not say so: $out"
}

# Bug this guards (R128): an issue filed for a Foreman session (new issues start in the queue) was open and unheld
# until testissue held it, so a pick that listed the open issues in between took it before the owner's yes. The pick
# is run, as the loop would run it, just before the hold, on the issues filed so far (as the owner's issues, which the
# loop does not hold for being from outside); it must take none, and the issue is held with no built label left once
# the hold is in.
t_taissuerace() {
  tasetup
  # A function stands in for `locked` to run the pick at the moment the hold is asked for; the real one does the rest.
  fx_in 'export CONVEYOR_FOREMAN=1; eval "$(declare -f locked | sed "1s/^locked/reallocked/")"
    locked() { if [ "$1 $2" = "control hold" ]; then reallocked pick "" "" "$(jq -cs "map(. + {authorAssociation: \"OWNER\"})" "$STUB/filed")" > "$STUB/between" 2>&1; fi; reallocked "$@"; }
    testissue tests/x.test.sh "Speed up tests/x.test.sh" "Measured: 12 CPU s."'
  [ "$RC" = 0 ] && [ -e "$STUB/between" ] || fail "testissue for a Foreman session did not file and reach the hold (exit $RC): $(cat "$T/$CASE/run.out")"
  [ ! -s "$STUB/between" ] || fail "a pick between the issue's filing and its hold took the Foreman's issue: $(cat "$STUB/between")"
  [ "$(loop control | jq -c .held)" = '[100101]' ] || fail "the Foreman's issue is not held: $(loop control)"
  [ "$(jq -c '.labels | map(.name)' "$STUB/filed")" = '["bug","P2"]' ] || fail "the built label was not taken off the held issue: $(cat "$STUB/filed")"
}
# Bug it catches (O237): `conveyor.sh card` (cardnew(), a Foreman order) made its issue with no built label and held it
# only after, so a pick in that moment could take the order before the owner's yes. The same pick as above runs there.
t_cardnewrace() {
  tasetup
  fx_in 'eval "$(declare -f locked | sed "1s/^locked/reallocked/")"
    locked() { if [ "$1 $2" = "control hold" ]; then reallocked pick "" "" "$(jq -cs "map(. + {authorAssociation: \"OWNER\"})" "$STUB/filed")" > "$STUB/between" 2>&1; fi; reallocked "$@"; }
    cardnew "Add a Rules row" "$(printf "Make it so.\n## Cause\nNo row exists.")"'
  [ "$RC" = 0 ] && [ -e "$STUB/between" ] || fail "card 'Add a Rules row' did not file and reach the hold (exit $RC): $(cat "$T/$CASE/run.out")"
  [ ! -s "$STUB/between" ] || fail "a pick between the filing of card 'Add a Rules row' and its hold took it: $(cat "$STUB/between")"
  [ "$(loop control | jq -c .held)" = '[100101]' ] || fail "the issue of card 'Add a Rules row' is not held: $(loop control)"
  [ "$(jq -c '.labels | map(.name)' "$STUB/filed")" = '["bug","P2"]' ] || fail "the built label was not taken off the held issue of card 'Add a Rules row': $(cat "$STUB/filed")"
}
# The Foreman's filing ask over these (#1637) is in askfiling.test.sh.
# Bug these catch (#1637): gh stopped at gh_write()'s time limit (exit 124) can have had the issue made on GitHub with
# its answer lost; `card` and `testissue` said only "could not be filed", so the Foreman filed it again.
t_cardghstop() {
  tasetup
  echo 'exit 124' > "$STUB/create-cmd" # stands for gh_write()'s timeout, which ends gh with 124
  fx_in 'cardnew "Add a Rules row" "$(printf "Make it so.\n## Cause\nNo row exists.")"'
  [ "$RC" = 1 ] && grep -qF 'look for it in GitHub before you file it again' "$T/$CASE/run.out" \
    || fail "card 'Add a Rules row' with gh stopped at its limit does not say the issue may be filed (exit $RC): $(cat "$T/$CASE/run.out")"
}
t_taissueghstop() {
  tasetup
  echo 'exit 124' > "$STUB/create-cmd" # stands for gh_write()'s timeout, which ends gh with 124
  fx_in 'testissue tests/x.test.sh "Speed up tests/x.test.sh" "Measured: 12 CPU s."'
  [ "$RC" = 1 ] && grep -qF 'look for it in GitHub before you file it again' "$T/$CASE/run.out" \
    || fail "testissue tests/x.test.sh with gh stopped at its limit does not say the issue may be filed (exit $RC): $(cat "$T/$CASE/run.out")"
}
