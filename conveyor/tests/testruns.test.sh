#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 300
# Engine cases: a card's test runs (its dependency links, the fix round, the failed run's line, the timeout) and its
# commit trailers.
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"
# The engine folder, as lib.sh sets it: named here too, so the release closure (tools/closure.sh) follows this file's paths.
SRC=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)

# Bugs: a card lands a change that breaks tests, because nothing ran them: its worktree has no dependencies (a link
# whose parent folder the worktree does not have, as cache/ is main's alone, failed); a dependency link is staged and
# lands (main's ignore rule has a trailing slash, which no link matches); the brief names folders the pack does not
# link, rather than the pack's linkFromMain, or does not say the loop runs the changed tests.
t_tests() {
  local w
  setup "[$(issue 7 2026-01-01)]"; w=$T/$CASE/cards/c7
  mkdir -p "$R/node_modules/dep" "$R/web/node_modules/wdep" "$R/infra" "$R/cache/deps/cdep"; echo '{}' | tee "$R/package.json" "$R/web/package.json" > "$R/infra/package.json"
  tune '.linkFromMain += ["cache/deps"]'
  printf 'conveyor/\n.conveyor/\nnode_modules/\ncache/\n' > "$R/.gitignore"; git -C "$R" add -A; git -C "$R" commit -qm deps
  # The card's worktree as card() makes it, its links made by deps() and its brief's header by header(), as card()
  # calls them; then the card's change staged as card() stages it (git add -A).
  git -C "$R" worktree add -q --detach "$w" refs/heads/main || fail "the card's worktree"
  fx_in 'deps "'"$w"'" && header'
  [ "$RC" = 0 ] || fail "the dependencies could not be linked (exit $RC): $(cat "$T/$CASE/run.out")"
  [ -L "$w/node_modules" ] && [ -d "$w/node_modules/dep" ] && [ -L "$w/web/node_modules" ] && [ -d "$w/web/node_modules/wdep" ] && [ ! -e "$w/infra/node_modules" ] \
    && [ -L "$w/cache/deps" ] && [ -d "$w/cache/deps/cdep" ] || fail "the worktree does not have main's dependency links: $(ls -la "$w" "$w/web" "$w/cache" 2>&1 | tr '\n' ' ')"
  echo two >> "$w/a.txt"; git -C "$w" add -A
  [ "$(git -C "$w" diff --cached --name-only | tr '\n' ' ')" = "a.txt " ] || fail "a dependency link was staged: $(git -C "$w" diff --cached --name-only | tr '\n' ' ')"
  # Bug: the brief names folders the pack does not link, rather than the pack's linkFromMain.
  grep -qF 'linked from the main checkout: node_modules, infra/node_modules, packages/sample-node/node_modules, web/node_modules, cache/deps.' "$T/$CASE/run.out" \
    && grep -q 'the loop runs the changed tests itself' "$T/$CASE/run.out" || fail "the brief does not say the dependencies are there and the loop runs the tests: $(cat "$T/$CASE/run.out")"
}

# Bugs: a card whose tests pass after their one fix round does not land; a card landing on its last review's NO-GO
# skips its tests, or files the follow-ups before they have passed; a failed run names a file the test itself logged
# (`-- FAIL widget.test.ts`) beside the one the runner ran; the build session is not given the card's settings file,
# or that file is left once the card has landed; the card's briefs folder (CONVEYOR_BRIEFS, where its sessions keep
# long command output: tools/outbrief.sh) is left once the card has landed (#1238 review: tidy() kept it).
t_testsland() {
  local p
  setup "[$(issue 7 2026-01-01)]"
  for i in 1 2 3 4; do moved "$i" "${NOGO/\[P1\]/[P2]}" > "$STUB/review.$i"; done
  # The build adds a line and keeps the settings file it is given, as it is while the session runs; each later session
  # changes the card, so each review after it reads a new change. The first run fails, and its run again too (tests());
  # the run after the test fix passes, marking whether it came before any follow-up was filed.
  cat > "$STUB/build" <<'EOS'
if [ "$(wc -l < "$STUB/sessions")" = 1 ]; then echo two >> a.txt; a=("$@"); for i in "${!a[@]}"; do [ "${a[i]}" != --settings ] || cp "${a[i+1]}" "$STUB/settings"; done
  echo "$CONVEYOR_BRIEFS" > "$STUB/briefs"; : > "$CONVEYOR_BRIEFS/outbrief.kept"
else wc -l < "$STUB/sessions" > fixed.txt; fi
EOS
  echo 'echo x >> "$STUB/tests"; [ "$(wc -l < "$STUB/tests")" -gt 2 ] || { echo "FAIL widget.test.ts"; exit 1; }; [ -e "$STUB/filed" ] || : > "$STUB/tested-first"' > "$STUB/test-cmd"
  # A whole card: that its test step, after the last review's NO-GO and the test fix, goes on to file and land is
  # card()'s own order of steps, which no function of it makes alone.
  rulecard 7
  [ "$(st '.step' | tr '\n' ' ')" = "picked worktree deps brief start build start review start fix start review start fix start review start test start fix start review start test start filed start landed " ] \
    || fail "steps of a card landing on a last NO-GO after its test fix: $(st '"\(.step) \(.reason)"' | tr '\n' ,)"
  [ "$(st 'select(.step == "test") | .result' | tr '\n' ' ')" = "fail pass " ] && [ -e "$STUB/tested-first" ] \
    && [ "$(st 'select(.step == "landed") | [.sha, (.followups | length)] | tojson')" = "[\"$(git -C "$R" rev-parse main)\",1]" ] \
    || fail "the card did not land with its follow-up after its tests passed, or filed it first: $(st 'select(.step == "test" or .step == "landed")')"
  [ "$(st 'select(.step == "test" and .result == "fail") | .failures.files | map(.file) | join(" ")')" = a.test.sh ] \
    || fail "the failed test step does not name a.test.sh alone: $(st 'select(.step == "test" and .result == "fail") | .failures | tojson')"
  p=$T/$CASE/cards/$(st '.card' | head -n 1).settings
  [ "$(sed -n '1s/.*--settings \([^ ]*\) .*/\1/p' "$STUB/sessions")" = "$p" ] && [ -s "$STUB/settings" ] && [ ! -e "$p" ] \
    || fail "the build session was not given the card's settings file, or it was left once the card landed: $(head -n 1 "$STUB/sessions")"
  [ "$(cat "$STUB/briefs" 2>/dev/null)" = "${p%.settings}.briefs" ] && [ ! -e "${p%.settings}.briefs" ] \
    || fail "the build session was not given the card's briefs folder, or it was left once the card landed: '$(cat "$STUB/briefs" 2>/dev/null)', $(ls -A "$T/$CASE/cards")"
  recok "$ST/cards.jsonl" "a card that landed after its test fix"
}

# Bugs: a failing test run blocks the card with no fix round, or gets more than one; the fix session is not handed the
# issue and the last 200 lines of the test output; a card whose tests fail twice lands, files the follow-ups of its
# last review's NO-GO, leaves main dirty or leaves its worktree; its blocked line's reason is not the one sentence, or
# its tail is not the last 60 lines of the output, each line whole: a cap on a line's length loses what it says after
# the cut, and makes lines that differ only there fold as identical on the Board. Lines that long, 60 of them, are
# more than one command argument can hold: the line is written all the same, its sentence and its output.
t_testsfix() {
  local head out
  setup "[$(issue 7 2026-01-01)]"
  for i in 1 2 3 4; do moved "$i" "${NOGO/\[P1\]/[P2]}" > "$STUB/review.$i"; done
  echo 'echo x >> "$STUB/tests"; seq 300 | sed "s/^/out line /"; for i in $(seq 59); do printf "FAIL %03000d\n" 0; done; echo "FAIL gadget.test.ts: expected 2"; printf "%s\n" "== gadget.test.ts" "-- FAIL gadget.test.ts" >> "$CONVEYOR_TEST_LOG/run.log"; exit 1' > "$STUB/test-cmd"
  head=$(git -C "$R" rev-parse HEAD)
  # A whole card: the one fix round, and the block after it, are card()'s test step, which only the card's own run
  # takes after its reviews.
  rulecard 7
  [ "$(st '.step' | tr '\n' ' ')" = "picked worktree deps brief start build start review start fix start review start fix start review start test start fix start review start test blocked " ] \
    || fail "steps of a NO-GO card whose tests fail twice: $(st '"\(.step) \(.reason)"' | tr '\n' ,)"
  [ "$(wc -l < "$STUB/sessions") $(wc -l < "$STUB/reviews") $(wc -l < "$STUB/tests")" = "4 4 4" ] \
    || fail "sessions, reviews and test runs are $(wc -l < "$STUB/sessions") $(wc -l < "$STUB/reviews") $(wc -l < "$STUB/tests"), not 4 4 4"
  # The test-fix session's brief: the issue, and the end of the output (the last 200 lines hold no more than 140 of
  # the 300 `out line` lines). Bug: a cut of 100 lines kept these lines all the same; the part after the
  # heading is counted, and ends with the output's last line (the run's LINKED note).
  out=$(sed '1,/^# The changed tests fail (exit 1): fix that and nothing else\. The end of the test output:$/d' "$STUB/brief")
  grep -q '^# The changed tests fail' "$STUB/brief" && grep -qx 'FAIL gadget.test.ts: expected 2' <<<"$out" && grep -qx 'out line 300' <<<"$out" \
    && ! grep -qx 'out line 160' <<<"$out" && [ "$(grep -c '' <<<"$out")" = 200 ] && [[ "$(tail -n 1 <<<"$out")" == "conveyor: the change adds or changes no test file"* ]] \
    && grep -q '^# Issue #7:' "$STUB/brief" || fail "the fix session was not handed the issue and the last 200 lines of the test output: $(grep -c '' <<<"$out") lines, the last $(tail -n 1 <<<"$out" | cut -c1-200)"
  [ "$(st 'select(.step == "blocked") | .reason')" = "the changed tests failed again after their one fix round (exit 1); nothing landed." ] \
    || fail "the blocked reason is not the one sentence: $(st 'select(.step == "blocked") | .reason')"
  # After the stub's lines come the run's own: a.test.sh's end (`-- FAIL a.test.sh`: filecmd()) and the note of the
  # linked files it ran (LINKED).
  [ "$(st 'select(.step == "blocked") | .tail | split("\n") | [length, (.[0] | length), .[-3], .[-2], (.[-1] | startswith("conveyor: the change adds or changes no test file")), (.[-5] == .[-4] and (.[-4] | startswith("FAIL 000") and length == 3005))] | join("|")')" = "60|3005|FAIL gadget.test.ts: expected 2|-- FAIL a.test.sh|true|true" ] \
    || fail "the blocked line's tail is not the last 60 lines of the test output: $(st 'select(.step == "blocked") | .tail' | cut -c1-400)"
  recok "$ST/cards.jsonl" "a card whose tests failed twice"
  [ "$(git -C "$R" rev-parse HEAD)" = "$head" ] && [ -z "$(git -C "$R" status --porcelain)" ] && [ -z "$(ls "$T/$CASE/cards")" ] && [ ! -s "$STUB/filed" ] \
    || fail "a card whose tests failed twice landed, left main dirty, left its worktree or filed a follow-up"
  grep -q 'FAIL gadget' "$(st 'select(.step == "blocked") | "\($ENV.ST)/\(.kept)"')"/*.test || fail "the test output was not kept"
}

# Bug: a failed test run's line held the last characters of its output as its reason: cut mid-word, a run of `ok`
# names and cleanup warnings, a note on exit 124 whatever the exit was, and the failing test named nowhere. The owner
# could not tell from the Board what failed. The line names the failing files and cases, each with its first FAIL
# line; a run that timed out says so and names the file still running; the output is the line's tail, lines whole.
# Bugs: a file that failed with no `FAIL [case]:` line (a node or TAP test, or one that died) was not listed at all;
# and a `== ` line a test printed passed for the runner's, so its cases went to a file that never ran and the count
# grew. Which files ran and failed is read from the runner's log, which no test's output reaches.
# Bug: a failing file that printed the `== ` line of a file that had passed gave it its failing case, so the Board
# named a passing file as failed. Files run in the log's order: a `== ` line that goes back is a test's own, and a
# FAIL line a passing file prints is no failure.
# shellcheck disable=SC2034 # the case's local f is unused; the case moved here unchanged from rules.test.sh
t_testfails() {
  local w=$T/$CASE/cards/c0-7 f
  setup "$(jq -cs . <(issue 7 2026-01-01))"; mkdir -p "$w.1.testlog" "$w.2.testlog" "$ST"
  # ran <run> <file> <ok | FAIL | - (still running when the clock stopped the run)> <its lines>...: one file of the run,
  # its output and the runner's log (run.log) as filecmd() writes them: `== <file>` as it begins, `-- <end> <file>`
  # as it ends.
  ran() {
    { echo "== $2" | tee -a "$w.$1.testlog/run.log"; printf '%s\n' "${@:4}"; [ "$3" = - ] || echo "-- $3 $2" | tee -a "$w.$1.testlog/run.log"; } >> "$w.$1.test"
  }
  # Run 1, of four files: two fail, one case each, one with a line over 200 characters and a second FAIL line, after a
  # `== ` line of its own that is no file of the run; the other after the `== ` line of a file that passed, earlier.
  # A passing file prints a FAIL line of its own.
  echo 'TESTRUN files=4' > "$w.1.testlog/run.log"
  ran 1 tests/a.test.sh ok 'ok alpha'
  ran 1 conveyor/conveyor.test.sh FAIL 'ok lane' '== diagnostic' "FAIL [views]: the snapshot lacks $(printf 'word %.0s' $(seq 60))end" 'FAIL [views]: a second line' 'conveyor: left 2 stubs running'
  ran 1 tests/b.test.sh FAIL '== tests/a.test.sh' 'FAIL [beta]: expected 2, got 3' 'ok gamma'
  ran 1 tests/c.test.sh ok 'FAIL [own]: words a passing test prints' 'ok delta'
  # Run 2, of four files, out of time (2 s) in its third: a TAP file fails (its TODO case does not), a file fails
  # naming no case, and z.test.sh never began.
  echo 'TESTRUN files=4' > "$w.2.testlog/run.log"
  ran 2 tests/d.test.mjs FAIL 'not ok 1 - rejects invalid input' 'ok 2 - fine' 'not ok 3 - later # TODO'
  ran 2 tests/e.test.sh FAIL 'e.test.sh: line 3: syntax error'
  ran 2 tests/slow.test.sh - 'ok one'
  # The failure parser on each, with the run's exit and the step's timeout, as card()'s test step calls it.
  fx_in 'TEST_TIMEOUT=2; testfails "'"$w"'.1.test" 1 > "'"$w"'.1.fails" && testfails "'"$w"'.2.test" 124 > "'"$w"'.2.fails"'
  [ "$RC" = 0 ] || fail "the failure parser failed (exit $RC): $(cat "$T/$CASE/run.out")"
  f() { jq -r "$2" "$w.$1.fails"; }
  [ "$(f 1 '[.of, .timeout, (.files | map([.file, (.cases | map(.name) | join(","))] | join(":")) | join(" "))] | tojson')" \
    = '[4,null,"conveyor/conveyor.test.sh:views tests/b.test.sh:beta"]' ] || fail "the failing files and cases are not exactly the two that failed: $(f 1 'tojson')"
  [ "$(f 1 '.files[1].cases[0].line')" = "FAIL [beta]: expected 2, got 3" ] || fail "a case's line is not its first FAIL line: $(f 1 'tojson')"
  [ "$(f 1 '.files[0].cases[0].line | [(length <= 200 and length > 190), startswith("FAIL [views]: the snapshot lacks word"), endswith(" word")] | tojson')" = '[true,true,true]' ] \
    || fail "a long first line is not cut to 200 characters at a word: $(f 1 '.files[0].cases[0].line')"
  f 1 '{of, files, timeout} | tojson' | grep -q 'ok \|alpha\|left 2 stubs\|second line\|diagnostic\|own' && fail "a passing file, an ok line, a warning, a later FAIL line or a test's own == line is among the failures: $(f 1 'tojson')"
  [ "$(f 2 '[.of, .timeout] | tojson')" = '[4,{"sec":2,"file":"tests/slow.test.sh"}]' ] || fail "a run that timed out does not say so and name the file still running, of the files selected: $(f 2 'tojson')"
  [ "$(f 2 '.files | tojson')" = '[{"file":"tests/d.test.mjs","cases":[{"name":"rejects invalid input","line":"not ok 1 - rejects invalid input"}]},{"file":"tests/e.test.sh","cases":[]}]' ] \
    || fail "a file that failed with a TAP line, or with no case line at all, is not listed: $(f 2 '.files | tojson')"
  # Each failed run's line as card()'s test step makes it (failline(): no verdicts of a run on main, no carried part).
  fx_in 'failline "'"$w"'.1" 1 2 "$(<"'"$w"'.1.fails")" "{\"verdicts\":[]}" "{}" > "'"$w"'.1.line" && failline "'"$w"'.2" 124 2 "$(<"'"$w"'.2.fails")" "{\"verdicts\":[]}" "{}" > "'"$w"'.2.line"'
  [ "$RC" = 0 ] || fail "the failed test lines could not be made (exit $RC): $(cat "$T/$CASE/run.out")"
  # The exit is said as it was: a note on 124 beside an exit 1 reads as a timeout that never happened. A run that
  # timed out says so with the file still running; its failures are the parser's, with their cases; the tail is the
  # output, a line a line.
  [ "$(jq -r .reason "$w.1.line")" = "exit 1" ] || fail "the reason of a run that exited 1: $(jq -r .reason "$w.1.line")"
  # Bug: a tail of more than the output's last 60 lines makes a failed run's line, on the Board, as long as its output.
  # Run 3 printed 70 lines and no runner's log.
  seq -f 'line %g' 70 > "$w.3.test"
  fx_in 'failline "'"$w"'.3" 1 2 null "{\"verdicts\":[]}" "{}"'
  [ "$RC" = 0 ] && [ "$(jq -c '.tail | split("\n") | [length, .[0], .[-1]]' "$T/$CASE/run.out")" = '[60,"line 11","line 70"]' ] \
    || fail "the line of a run with a long output does not keep its last 60 lines alone (exit $RC): $(head -c 300 "$T/$CASE/run.out")"
  [ "$(jq -r .reason "$w.2.line")" = "exit 124: timed out after 2s in tests/slow.test.sh" ] || fail "the reason of a run that timed out: $(jq -r .reason "$w.2.line")"
  [ "$(jq -c .failures "$w.2.line")" = "$(f 2 'del(.passed, .okcases, .passcases) | tojson')" ] && [ "$(jq -c '.failures.files[0].cases' "$w.2.line")" = '[{"name":"rejects invalid input","line":"not ok 1 - rejects invalid input"}]' ] \
    || fail "the timed-out line's failures are not the parser's, with their cases: $(jq -c .failures "$w.2.line")"
  [ "$(jq -r '.tail | split("\n") | [.[0], .[1], .[-2], .[-1]] | join("|")' "$w.2.line")" = "== tests/d.test.mjs|not ok 1 - rejects invalid input|== tests/slow.test.sh|ok one" ] \
    || fail "the timed-out line's tail is not the output, a line a line: $(jq -r .tail "$w.2.line")"
  # The Board reads them from the card's steps: the two failed lines, then the blocked line.
  { landed 7 | jq -c '.step = "picked" | .sha = "" | .title = "title 7" | del(.product)'
    for i in 1 2; do
      jq -c --arg t "2026-11-01T00:0$i:00Z" '{card: "c0-7", issue: 7, step: "test", time: $t, tokens: {claude: 0, codex: 0}, result: "fail", sha: ""} + .' "$w.$i.line"
    done
    landed 7 | jq -c '.step = "blocked" | .result = "blocked" | .sha = "" | .time = "2026-11-01T00:05:00Z" | .reason = "the changed tests failed again after their one fix round (exit 124); nothing landed." | del(.product)'
  } >> "$ST/cards.jsonl"
  recok "$ST/cards.jsonl" "the failed test lines"
  [ "$(loop snapshot --fresh | jq -c '.needsYou.blocked[0].track.records | map(select(.name == "tests failed") | [.why, (.failures.files | length), .failures.timeout.file, (.output | test("FAIL \\[beta\\]|not ok 1 "))])')" \
    = '[["exit 1",2,null,true],["exit 124: timed out after 2s in tests/slow.test.sh",2,"tests/slow.test.sh",true]]' ] \
    || fail "the card's steps lack a failed run's failures or output: $(loop snapshot --fresh | jq -c '.needsYou.blocked[0].track.records')"
}

# Bugs: a host's commit-msg hook refuses every card that needs a line only the builder can write, because the card
# cannot put one in Conveyor's message; a line not of the trailer shape, or a Co-Authored-By, is kept; the review
# does not see the trailers; a pack rule's trailer is missing and the card does not owe it; a pack with no
# commit.trailers asks for a trailer; a path git quotes (café/) escapes the rule; a rule whose when is not a valid ERE
# silently requires nothing.
t_trailers() {
  local d=$T/$CASE/cards
  setup '[]'
  # The staged changes the trailers are read on: each a worktree of main, its trailers file beside it.
  rulewt 10 'touch a-guard.test.ts'
  rulewt 7 'echo two >> a.txt; printf "%s\n" "Mutation-verified: broke X, test went red" "not a trailer line" "Co-Authored-By: someone" "-x: no token" > "$PWD.trailers"'
  rulewt 8 'touch b-guard.test.ts'
  rulewt 9 'mkdir -p café; touch café/c-guard.test.ts'
  # The trailer filter, the brief's section and donewhen.sh owing() as card() calls them: first with no pack rule, then with the
  # pack's rule for an added guard-class test, then with a rule whose when grep cannot read.
  fx_in 'owing "$d/10" > "$d/owe.10" && trailerbrief "$d/10" > "$d/brief.10" && trailers "$d/7" > "$d/kept.7" && trailerview "$d/7" > "$d/view.7" || exit 1
    tune '"'"'.commit.trailers = [{"when": "(conformance|guard|parity|coverage)[^/]*\\.test\\.(ts|tsx)$", "token": "Mutation-verified", "ask": "Say what you broke and how the test went red."}]'"'"'
    owing "$d/8" > "$d/owe.8" && trailerbrief "$d/8" > "$d/brief.8" && owing "$d/9" > "$d/owe.9" || exit 2
    echo "Mutation-verified: removed the check, the test went red" > "$d/9.trailers"; owing "$d/9" > "$d/owe.9.written" || exit 2
    tune '"'"'.commit.trailers = [{"when": "[", "token": "Mutation-verified", "ask": "Say what you broke."}]'"'"'
    ! owing "$d/8" || exit 3'
  [ "$RC" = 0 ] || fail "the trailers could not be read as asked (exit $RC: 1 with no rule, 2 with the rule, 3 an invalid when was taken): $(cat "$T/$CASE/run.out")"
  # No pack rule: a change adding a guard test owes nothing; the brief names the trailers file.
  [ ! -s "$d/owe.10" ] || fail "a pack with no commit.trailers asked for a trailer: $(cat "$d/owe.10")"
  grep -qF "$d/10.trailers, one a line" "$d/brief.10" || fail "the build prompt does not name the trailers file: $(cat "$d/brief.10")"
  # The kept lines: only the trailer; a line not of the shape and a Co-Authored-By are dropped, and the review sees the kept one.
  [ "$(cat "$d/kept.7")" = 'Mutation-verified: broke X, test went red' ] || fail "the kept trailers are not the one trailer: $(cat "$d/kept.7")"
  grep -qx 'Mutation-verified: broke X, test went red' "$d/view.7" && ! grep -q 'not a trailer line\|Co-Authored-By\|no token' "$d/view.7" || fail "the review is not shown the kept trailers alone: $(cat "$d/view.7")"
  # The pack's rule: an added guard test with no trailer owes it, and the prompt carries the rule.
  [ "$(cat "$d/owe.8")" = '{"token":"Mutation-verified","ask":"Say what you broke and how the test went red.","paths":["b-guard.test.ts"]}' ] \
    || fail "a change missing a required trailer does not owe it: $(cat "$d/owe.8")"
  grep -q 'adds a file whose path matches the extended regular expression `(conformance|guard|parity|coverage)' "$d/brief.8" || fail "the prompt does not carry the pack's rule: $(cat "$d/brief.8")"
  # A path git quotes owes it whole, and owes nothing once the trailer is written.
  [ "$(jq -c .paths "$d/owe.9")" = '["café/c-guard.test.ts"]' ] && [ ! -s "$d/owe.9.written" ] \
    || fail "a path git quotes escaped the rule, or its written trailer was not counted: $(cat "$d/owe.9" "$d/owe.9.written")"
  # Bugs: the trailer the one fix session writes, asked for it, is not reviewed again; or it is lost from the commit
  # when the tests delete the trailers file. A whole card: that the fix goes back to review, and that the commit takes
  # the trailers as they were reviewed and not as the tests leave them, is card()'s own order of steps.
  tune '.commit.trailers = [{"when": "(conformance|guard|parity|coverage)[^/]*\\.test\\.(ts|tsx)$", "token": "Mutation-verified", "ask": "Say what you broke and how the test went red."}]'
  echo "[$(issue 9 2026-01-01)]" > "$STUB/issues.json"; for i in 1 2; do echo "$GO" > "$STUB/review.$i"; done
  sed -i 's|^cat > /dev/null; echo x|cat > "$STUB/asked"; echo x|' "$STUB/codex"
  printf '%s\n' 'mkdir -p café; touch café/c-guard.test.ts' '[ "$(wc -l < "$STUB/sessions")" -lt 2 ] || echo "Mutation-verified: removed the check, the test went red" > "$PWD.trailers"' > "$STUB/build"
  echo 'rm -f "$PWD.trailers"' >> "$STUB/test-cmd"
  rulecard 9
  [ "$(st '.step' | tr '\n' ' ')" = "picked worktree deps brief start build start review start fix start review start test start landed " ] \
    && [ "$(wc -l < "$STUB/sessions") $(wc -l < "$STUB/reviews")" = "2 2" ] && grep -qx 'Mutation-verified: removed the check, the test went red' "$STUB/asked" \
    || fail "the trailer the fix session wrote was not reviewed again: $(st '"\(.step) \(.reason)"' | tr '\n' ,)"
  # The whole message, so the trailer is checked in its place: after Closes, before the Conveyor card line.
  [ "$(git -C "$R" log -1 --format=%B main)" = "feat(product): title 9 (#9)"$'\n\n'"Closes #9"$'\n'"Mutation-verified: removed the check, the test went red"$'\n'"Conveyor card $(st 'select(.step == "landed") | .card')" ] \
    || fail "the trailer the fix session wrote did not land after Closes, though the tests deleted its file: $(git -C "$R" log -1 --format=%B main)"
}

# Bug: a required trailer still missing after the one fix session that asked for it does not stop the card, so it
# commits without the trailer, or it gets no such session. A whole card: that the block comes after that one fix
# session, before the tests and the commit, is card()'s own order of steps.
t_trailermissing() {
  local head
  setup "[$(issue 8 2026-01-01)]"
  tune '.commit.trailers = [{"when": "(conformance|guard|parity|coverage)[^/]*\\.test\\.(ts|tsx)$", "token": "Mutation-verified", "ask": "Say what you broke and how the test went red."}]'
  echo "$GO" > "$STUB/review.1"; echo 'touch b-guard.test.ts' > "$STUB/build"; head=$(git -C "$R" rev-parse main)
  rulecard 8
  [ "$(st '.step' | tr '\n' ' ')" = "picked worktree deps brief start build start review start fix blocked " ] && [ "$(wc -l < "$STUB/sessions")" = 2 ] \
    && grep -q 'Say what you broke and how the test went red. It adds b-guard.test.ts.' "$STUB/brief" \
    || fail "a card missing a required trailer did not get one fix session asking for it, then stop: $(st '"\(.step) \(.reason)"' | tr '\n' ,)"
  st 'select(.step == "blocked") | .reason' | grep -qF 'missing after its one fix session; nothing landed: Mutation-verified (it adds b-guard.test.ts)' \
    && [ "$(git -C "$R" rev-parse main)" = "$head" ] || fail "a card missing a required trailer was not blocked with the reason, or landed: $(st '"\(.step) \(.reason)"' | tr '\n' ,)"
}

# Bug: a path holding a newline escaped the pack's trailer rule: read a line a name, neither half matches the rule's
# when, so the card owed no trailer and committed without one. owing() (lib/donewhen.sh) reads the added names whole.
t_trailerpath() {
  local W=$T/$CASE/w out rc
  mkdir -p "$W" && git -C "$W" init -q && touch "$W/$(printf 'e-guard\n.test.ts')" && git -C "$W" add -A || fail "the worktree"
  # shellcheck disable=SC2034 # STATE is read by the sourced lib/testrun.sh
  out=$( (STATE=$T/$CASE/cards.jsonl; . "$SRC/lib/testrun.sh" || exit 3
    packget() { case $1 in commit.trailers) printf -v "$2" '%s' '[{"when": "(conformance|guard|parity|coverage)[^/]*\\.test\\.(ts|tsx)$", "token": "Mutation-verified", "ask": "Say what you broke."}]' ;;
      *) printf -v "$2" '%s' '[]' ;; esac; }
    owing "$W") 2>&1); rc=$?
  [ $rc = 0 ] && [ "$out" = '{"token":"Mutation-verified","ask":"Say what you broke.","paths":["e-guard\n.test.ts"]}' ] \
    || fail "a path holding a newline escaped the pack's rule: exit $rc, $out"
}

# Bug: Needs You lacks the running file, the timeout or the output of a card's timed-out last test run. t_testfails uses
# fixture runs; a card run joins exit, log and output. Each run prints a failure, then reads a pipe no one writes.
t_testtimeout() {
  setup "[$(issue 7 2026-01-01)]"; tune '.tunables.testTimeout = 1'; mkfifo "$STUB/never"; echo "$GO" | tee "$STUB/review.1" > "$STUB/review.2"
  echo 'echo x >> "$STUB/tests"; echo "FAIL [slow]: no answer yet"; read -r < "$STUB/never"' > "$STUB/test-cmd"; rulecard 7
  [ "$(st 'select(.step == "blocked") | .reason' | head -n 1)" = "the changed tests failed again after their one fix round (exit 124); nothing landed." ] \
    || fail "the card was not blocked after its timed-out test runs: $(st '"\(.step) \(.reason)"' | tr '\n' ,)"
  [ "$(loop snapshot --fresh | jq -c '.needsYou.blocked[0].track.records | map(select(.name == "tests failed")) | last | [.why, .failures.timeout.file, (.output | contains("FAIL [slow]: no answer yet"))]')" \
    = '["exit 124: timed out after 1s in a.test.sh","a.test.sh",true]' ] || fail "Needs You does not show the timed-out run: $(loop snapshot --fresh | jq -c '.needsYou.blocked[0].track.records')"
}
