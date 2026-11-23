#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 120
# Engine cases: the test history's start (the control record's testsFrom, `conveyor.sh test-settings history-start`,
# histstart() and HISTFROM in lib/testfiles.sh): the snapshot's tests part and the facts the Tests judge is given count
# only the runs, failures and flaky entries on or after it, and delete nothing.
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"
# A page of the repository says <text> (lines joined, spaces folded). Each case file that calls it defines its own, named after the file: the bug check puts only the card's test files on main's code, where a helper in lib.sh is missing, and the runner sources the case files into one shell, where one name cannot be defined twice.
pagesays_testhistory() { tr '\n' ' ' < "$SRC/../$1" | tr -s ' ' | grep -qF -- "$2" || fail "$1 does not say \"$2\": $3"; } # <page> <text> <what the run showed>

# The start is the exact time of one run (h.test's first run after it), so a filter that keeps only what is after it
# (not on or after it) drops that run.
TH_START=2026-11-20T12:00:00Z
# The engine's functions as the script of <command> loads them, run in a shell of the case's main ($R).
# shellcheck source=/dev/null # the command's libraries, by its . lines or its SNAPLIBS list (commands/snapshot.sh)
th_as() { ( export CONVEYOR_MAIN=$R CONVEYOR_CARDS=$T/$CASE/cards; . "$SRC/conveyor.sh" state-dir > /dev/null \
  && eval "$(grep -e '^\. "\$HERE/lib/' -e '^SNAPLIBS=' "$SRC/commands/$1.sh")" \
  && for l in ${SNAPLIBS-}; do . "$HERE/lib/$l.sh" || exit 1; done && "${@:2}" ); } # <command> <function>...
# Two files. h.test has history on both sides of $TH_START. Before it: two passing runs at 900 CPU s, a failed step, a
# release-suite run, a flaky entry, a test-speed survey time (700 CPU s) and a card that timed it in one step and
# carried that time in its next one, which is after the start. After it: six passing card runs (10, 10, 10, 10, 16, 16
# CPU s; one of the 10 s in a step that carried it from the step before), a failed step, a suite run and a flaky entry.
# Both failed steps are of cards that landed. g.test has history before the start only: a card run, a failed step, a
# flaky entry and a run on its own. A card line is {card, step: test} at <time>.
th_fixture() {
  setup '[]'; tune '.test.slower = {share: 0.5, runs: 2, minRuns: 4}'
  local t i=0 sha
  sha=$(git -C "$R" rev-parse HEAD)
  for t in 2026-11-10T12:00:00Z 2026-11-10T12:01:00Z 2026-11-20T12:00:00Z 2026-11-20T12:01:00Z 2026-11-20T12:02:00Z 2026-11-20T12:03:00Z; do
    jq -cn --arg t "$t" --argjson c "$(jq -cn --argjson i "$i" '[900, 900, 10, 10, 16, 16][$i]')" '{card: "c-run-\($t)", issue: 1, step: "test", time: $t, result: "pass",
      times: {"h.test": $c}, clocks: {"h.test": ($c + 1)}}' >> "$ST/cards.jsonl"
    i=$((i + 1))
  done
  for t in 2026-11-11T00:00:00Z 2026-11-21T00:00:00Z; do
    jq -cn --arg t "$t" '{card: "c-fail-\($t)", issue: 2, step: "test", time: $t, result: "fail", failures: {of: 1, files: [{file: "h.test", cases: [{name: "one"}]}], timeout: null},
      verdicts: [{case: "h.test: one", verdict: "main"}], tail: "not ok one"}' >> "$ST/cards.jsonl"
  done
  # A card that landed with a failed test step, for each failed step of h.test: the commit changed no test file, so
  # the fix went into the code (caught).
  for t in 2026-11-11T00:00:00Z 2026-11-21T00:00:00Z; do
    jq -cn --arg t "$t" --arg s "$sha" '{card: "c-fail-\($t)", issue: 2, step: "landed", time: $t, result: "ok", sha: $s}' >> "$ST/cards.jsonl"
  done
  # A step that timed h.test at 900 before the start, and the next one, after it, that carried it; and the pair after the start at 10.
  # The card changed h.test, so both its lines also hold its time in timed (the later one carries it, as slowtests() writes it).
  jq -cn '{card: "c-old", issue: 3, step: "test", time: "2026-11-10T13:00:00Z", result: "pass", times: {"h.test": 900}, timed: [{file: "h.test", sec: 901, cpu: 900}]}' >> "$ST/cards.jsonl"
  jq -cn '{card: "c-old", issue: 3, step: "test", time: "2026-11-20T12:00:10Z", result: "pass", times: {"h.test": 900}, timed: [{file: "h.test", sec: 901, cpu: 900}], carried: ["h.test"]}' >> "$ST/cards.jsonl"
  jq -cn '{card: "c-new", issue: 4, step: "test", time: "2026-11-20T12:00:30Z", result: "pass", times: {"h.test": 10}}' >> "$ST/cards.jsonl"
  jq -cn '{card: "c-new", issue: 4, step: "test", time: "2026-11-20T12:00:40Z", result: "pass", times: {"h.test": 10}, carried: ["h.test"]}' >> "$ST/cards.jsonl"
  jq -cn '{card: "c-g", issue: 5, step: "test", time: "2026-11-10T14:00:00Z", result: "pass", times: {"g.test": 5}}' >> "$ST/cards.jsonl"
  jq -cn '{card: "c-g-fail", issue: 6, step: "test", time: "2026-11-11T01:00:00Z", result: "fail", failures: {of: 1, files: [{file: "g.test", cases: [{name: "one"}]}], timeout: null},
    verdicts: [{case: "g.test: one", verdict: "main"}], tail: "not ok one"}' >> "$ST/cards.jsonl"
  jq -cn '{time: "2026-11-12T00:00:00Z", how: "release", sha: "", files: {"h.test": {result: "ok", sec: 1, cpu: 800}}}' > "$ST/suiteruns.jsonl"
  jq -cn '{time: "2026-11-22T00:00:00Z", how: "release", sha: "", files: {"h.test": {result: "ok", sec: 1, cpu: 30}}}' >> "$ST/suiteruns.jsonl"
  echo '{"entries":[{"case":"h.test: one","source":"c-a","time":"2026-11-09T00:00:00Z"},{"case":"h.test: one","source":"c-b","time":"2026-11-21T00:00:00Z"},
    {"case":"g.test: one","source":"c-c","time":"2026-11-09T00:00:00Z"}],"filed":[]}' > "$ST/flaky.json"
  mkdir -p "$ST/testactions" && jq -cn '{id: "0000000000aa", action: "run", file: "g.test", commit: "fedcba9876543210", start: "2026-11-13T00:00:00Z", end: "2026-11-13T00:01:00Z", state: "done", result: "pass"}' > "$ST/testactions/0000000000aa.json"
  # The test-speed survey's time of h.test, dated by the commit that saved it.
  mkdir -p "$R/.conveyor" && echo '{"files": {"h.test": {"sec": 701, "cpu": 700}}}' > "$R/.conveyor/test-times.json" \
    && git -C "$R" add -f .conveyor/test-times.json && GIT_COMMITTER_DATE=2026-11-12T12:00:00Z git -C "$R" commit -qm times || fail "the saved survey times"
}
th_row() { jq -c --arg f h.test '.files[] | select(.file == $f)' <<<"$1"; }
# The figures of h.test's row the start changes: its newest CPU, median, change, usual, slower flag, runs on record, failed steps and
# flaky entries, and the times of its runs and failures.
th_figs() { jq -c '[.cpu, .median, .change, .usual, .slower, .runsOnRecord, .failedSteps, .flaky, .caught, [.runs[].time], [.failures[].time]]' <<<"$(th_row "$1")"; }

# Bug it catches: the runs from before the start (a slower machine) stayed in a file's figures: they lifted its median
# and usual, so a file that is slower now than its runs since the start showed as not slower, and its failed steps and
# flaky entries from then still counted. With the start set, a file's CPU, median, change, usual, slower flag, runs,
# failed steps, flaky entries and landed failures come from the runs on or after it alone (the run at the start's exact
# time too, the survey time and a carried time of a run before it not), a file with no run since has no row, and the
# totals follow.
t_thstart() {
  local got pack; th_fixture; pack=$(cat "$R/.conveyor/project.json")
  loop test-settings history-start "$TH_START" || fail "the start $TH_START was not saved"
  # Bug (#1436): the guide said test-settings changes the pack and nothing else, then named history-start as an
  # exception; the run shows history-start changes the control record and leaves the pack as it was.
  [ "$(jq -r .testsFrom "$ST/control.json")" = "$TH_START" ] && [ "$(cat "$R/.conveyor/project.json")" = "$pack" ] \
    || fail "history-start did not change the control record alone: $(jq -c .testsFrom "$ST/control.json" 2>&1)"
  pagesays_testhistory conveyor/README.md 'except `history-start`, which changes the control record' "history-start saved to the control record, not the pack"
  ! tr '\n' ' ' < "$SRC/README.md" | tr -s ' ' | grep -qF 'and nothing else. Each' || fail "conveyor/README.md still says test-settings changes the pack and nothing else"
  got=$(th_as snapshot testspart 2026-11-09) || fail "testspart failed with the start $TH_START: $got"
  [ "$(th_figs "$got")" = '[30,10,2,10,true,7,1,1,1,["2026-11-22T00:00:00Z","2026-11-20T12:03:00Z","2026-11-20T12:02:00Z","2026-11-20T12:01:00Z","2026-11-20T12:00:40Z"],["2026-11-21T00:00:00Z"]]' ] \
    || fail "h.test's figures with the start $TH_START are not those of its runs on or after it: $(th_figs "$got")"
  [ "$(jq -c '[.files[] | select(.file == "g.test")] | length' <<<"$got")" = 0 ] || fail "g.test, run only before the start $TH_START, has a row: $(jq -c '.files[] | select(.file == "g.test")' <<<"$got")"
  [ "$(jq -c '.totals.slower' <<<"$got")" = 1 ] || fail "the totals with the start $TH_START do not count h.test slower: $(jq -c .totals <<<"$got")"
  # Bug it catches: the snapshot did not carry the start, so the Board's Test settings could not show it.
  [ "$(jq -r '.settings.historyStart' <<<"$got")" = "$TH_START" ] || fail "the snapshot's settings.historyStart is not the start $TH_START: $(jq -c .settings <<<"$got")"
}
# Bug it catches: a tracked test file whose runs are all before the start had a row with no runs, so the Board said
# Never run and offered Delete it, though it ran. Its row says everRun; a tracked file that never ran does not.
t_theverrun() {
  local got; th_fixture
  tune '.tests.patterns = ["*.test"]'
  touch "$R/g.test" "$R/n.test" && git -C "$R" add g.test n.test && git -C "$R" commit -qm tests || fail "the tracked test files"
  loop test-settings history-start "$TH_START" || fail "the start $TH_START was not saved"
  got=$(th_as snapshot testspart 2026-11-09) || fail "testspart failed with the start $TH_START: $got"
  [ "$(jq -c '[.files[] | select(.file | IN("g.test", "n.test")) | [.file, .runsOnRecord, .everRun]]' <<<"$got")" = '[["g.test",0,true],["n.test",0,false]]' ] \
    || fail "g.test, run only before the start $TH_START, is not everRun, or n.test, never run, is: $(jq -c '[.files[] | {file, runsOnRecord, everRun}]' <<<"$got")"
}
# Bug it catches (O239): `history test` (testolder(), the Timeline's older runs) read every run with no start filter,
# so the Timeline brought back the runs before the start the Tests page leaves out, and c-old's carried 900 s too.
t_tholder() {
  local got; th_fixture
  loop test-settings history-start "$TH_START" || fail "the start $TH_START was not saved"
  got=$(loop history test h.test | jq -c '[.olderRuns[] | [.time, .card]]') || fail "history test h.test failed: $got"
  jq -e --arg s "$TH_START" 'length > 0 and all(.[]; .[0] >= $s and .[1] != "c-old")' <<<"$got" > /dev/null \
    || fail "history test h.test with the start $TH_START gives older runs before it, or c-old's carried time: $got"
}
# Bug it catches (O241): the landed commits of cards with a failed test step went to jq as one argument; 3,300 of them
# (41 bytes each) pass Linux's 128 KiB limit, jq did not start, and h.test's two caught failures read as none.
t_thmanylanded() {
  local got; th_fixture
  jq -cn 'range(3300) | ("c-many-\(.)" as $c | {card: $c, issue: 9, step: "test", time: "2026-11-15T00:00:00Z", result: "fail",
      failures: {of: 1, files: [{file: "z.test", cases: []}], timeout: null}}, {card: $c, issue: 9, step: "landed", time: "2026-11-15T00:00:01Z", result: "ok",
      sha: ("f" + ("000000000000000000000000000000000000000" + (. | tostring))[-39:])})' >> "$ST/cards.jsonl" || fail "the fixture could not be made"
  got=$(th_as snapshot testspart 2026-11-09) || fail "testspart failed with 3300 landed failed cards: $got"
  [ "$(th_row "$got" | jq -c .caught)" = 2 ] || fail "with 3300 landed failed cards, h.test's caught failures are not 2: $(th_row "$got" | jq -c '{caught, changedToPass}')"
}
# Bug it catches: with no start set the filter dropped runs (a missing setting read as a date): every run counts, as
# before the setting existed: the 900 s runs, the survey time and the carried time are in the median (30), usual
# (700) and run count (13), and both failed steps, flaky entries and landed failures count.
t_thnostart() {
  local got; th_fixture
  got=$(th_as snapshot testspart 2026-11-09) || fail "testspart failed with no start: $got"
  [ "$(th_figs "$got" | jq -c '.[:9]')" = '[30,30,0,700,false,13,2,2,2]' ] \
    || fail "with no start set, h.test's figures are not those of all its runs: $(th_figs "$got")"
  [ "$(jq -c '.settings.historyStart' <<<"$got")" = null ] || fail "with no start set, settings.historyStart is not null: $(jq -c .settings <<<"$got")"
}
# Bug it catches: the figures' slot wait and run time of the card Test steps, and the whole-suite run, still counted
# what ran before the start (the Tests page said it did not). With the start set, the steps' wait and run are those of
# the steps on or after it, and the suite is the newest suite run on or after it, none when every one is before it.
t_thsteps() {
  local got; th_fixture
  jq -cn '{card: "c-wr", issue: 7, step: "test", time: "2026-11-10T15:00:00Z", result: "pass", wait: 100, run: 200}' >> "$ST/cards.jsonl"
  jq -cn '{card: "c-wr", issue: 7, step: "test", time: "2026-11-21T15:00:00Z", result: "pass", wait: 1, run: 2}' >> "$ST/cards.jsonl"
  loop test-settings history-start "$TH_START" || fail "the start $TH_START was not saved"
  got=$(th_as snapshot testspart 2026-11-09) || fail "testspart failed with the start $TH_START: $got"
  [ "$(jq -c '[.totals.steps.waitSec, .totals.steps.runSec]' <<<"$got")" = '[1,2]' ] \
    || fail "the card steps' wait and run with the start $TH_START do not leave out the step before it: $(jq -c .totals.steps <<<"$got")"
  loop test-settings history-start 2026-11-23T00:00:00Z || fail "the start 2026-11-23T00:00:00Z was not saved"
  got=$(th_as snapshot testspart 2026-11-09) || fail "testspart failed with the start after every suite run: $got"
  [ "$(jq -c .suite <<<"$got")" = null ] || fail "the suite with every suite run before the start is not none: $(jq -c .suite <<<"$got")"
  loop test-settings history-start clear || fail "the start was not cleared"
  got=$(th_as snapshot testspart 2026-11-09) || fail "testspart failed with no start: $got"
  [ "$(jq -c '[.totals.steps.waitSec, .totals.steps.runSec, .suite.time]' <<<"$got")" = '[101,202,"2026-11-22T00:00:00Z"]' ] \
    || fail "with no start, the card steps' wait and run and the newest suite run are not all counted: $(jq -c '[.totals.steps, .suite]' <<<"$got")"
}
# Bug it catches: the judge was given the runs and failures from before the start, so it judged a file by history the
# Tests page no longer showed. With the start set, its runs, newest run, failures and flaky entries are all on or after it.
# A carried time is dated by the step that ran the file (c-new's 12:00:30), not by the later step that carried it (12:00:40).
t_thfacts() {
  local got want have; th_fixture
  loop test-settings history-start "$TH_START" || fail "the start $TH_START was not saved"
  got=$(th_as testaction testfacts h.test) || fail "testfacts failed with the start $TH_START: $got"
  # The want list is [run times, carried run times, failure times, flaky times, newest run time]: c-new's carried run
  # is at 12:00:30, the time of the step that ran the file.
  want='[["2026-11-20T12:00:00Z","2026-11-20T12:00:30Z","2026-11-20T12:00:30Z","2026-11-20T12:01:00Z","2026-11-20T12:02:00Z","2026-11-20T12:03:00Z","2026-11-22T00:00:00Z"],["2026-11-20T12:00:30Z"],["2026-11-21T00:00:00Z"],["2026-11-21T00:00:00Z"],"2026-11-22T00:00:00Z"]'
  have=$(jq -c '[[.runs[].time], [.runs[] | select(.carried) | .time], [.failures[].time], [.flaky[].time], .newest.time]' <<<"$got")
  [ "$have" = "$want" ] \
    || fail "the facts for h.test with the start $TH_START do not have the expected times (want $want, have $have): $got"
  # g.test has only a card run, a failed step, a flaky entry and a run on its own (which would be its newest run) from before the start.
  got=$(th_as testaction testfacts g.test) || fail "testfacts g.test failed with the start $TH_START: $got"
  [ "$(jq -c '[.runs, .cards, .failures, .flaky, .newest]' <<<"$got")" = '[[],[],[],[],null]' ] \
    || fail "the facts for g.test, whose runs are all before the start $TH_START, are not empty: $got"
  loop test-settings history-start clear || fail "the start was not cleared"
  got=$(th_as testaction testfacts h.test) || fail "testfacts failed with no start: $got"
  [ "$(jq -c '[(.runs | length), (.failures | length), (.flaky | length)]' <<<"$got")" = '[13,2,2]' ] \
    || fail "the facts for h.test with no start do not hold every run, failure and flaky entry: $got"
  got=$(th_as testaction testfacts g.test) || fail "testfacts g.test failed with no start: $got"
  [ "$(jq -c '[(.runs | length), (.failures | length), (.flaky | length), .newest.time]' <<<"$got")" = '[1,1,1,"2026-11-13T00:01:00Z"]' ] \
    || fail "the facts for g.test with no start do not hold its run, failure, flaky entry and run on its own: $got"
}
# Bug it catches: a start that deleted the history (so moving it back could not bring the runs back). Using the
# setting leaves the card records, the whole-suite runs and the flaky record as they were, and clearing it counts every run again.
t_thkept() {
  local before after got; th_fixture
  before=$(cksum "$ST/cards.jsonl" "$ST/suiteruns.jsonl" "$ST/flaky.json" "$ST"/testactions/*.json)
  loop test-settings history-start "$TH_START" || fail "the start $TH_START was not saved"
  th_as snapshot testspart 2026-11-09 > /dev/null || fail "testspart failed with the start $TH_START"
  th_as testaction testfacts h.test > /dev/null || fail "testfacts failed with the start $TH_START"
  after=$(cksum "$ST/cards.jsonl" "$ST/suiteruns.jsonl" "$ST/flaky.json" "$ST"/testactions/*.json)
  [ "$before" = "$after" ] || fail "using the start $TH_START changed the card records, suite runs or flaky record: $before / $after"
  grep -q '2026-11-10T12:00:00Z' "$ST/cards.jsonl" || fail "a run from before the start $TH_START is gone from the card records"
  loop test-settings history-start clear || fail "the start was not cleared"
  got=$(th_as snapshot testspart 2026-11-09) || fail "testspart failed after the start was cleared: $got"
  [ "$(th_row "$got" | jq -c .runsOnRecord)" = 13 ] || fail "the runs from before the start do not count again once it is cleared: $(th_figs "$got")"
}
# Bug it catches: a bad time saved in the control record (which then stands unread, so nothing is picked), or a
# setting that changed the record when refused. Set and clear go through the control record; each refusal changes nothing.
t_thsetting() {
  local before a
  setup '[]'
  before=$(loop control)
  loop test-settings history-start "$TH_START" > /dev/null || fail "the start $TH_START was not saved"
  [ "$(loop control | jq -c .testsFrom)" = "\"$TH_START\"" ] || fail "the control record does not hold the start $TH_START: $(loop control)"
  loop test-settings history-start clear > /dev/null || fail "the start was not cleared"
  [ "$(loop control)" = "$before" ] || fail "clearing the start did not put the control record back: $(loop control)"
  for a in 2026-11-15 yesterday 2026-13-45T00:00:00Z '2026-11-15T00:00:00Z extra'; do
    loop test-settings history-start "$a" > /dev/null 2>&1; [ $? = 2 ] || fail "the start \"$a\" was not refused"
    [ "$(loop control)" = "$before" ] || fail "the refused start \"$a\" changed the control record: $(loop control)"
  done
  loop test-settings history-start > /dev/null 2>&1; [ $? = 2 ] || fail "test-settings history-start with no value was not a usage error"
}
# Bug it catches: the test rules (which file the slow-test issues) read every run on record, so a file whose runs before
# the start made its usual look fast was still filed, and a carried time of a run before the start counted as a run
# after it. r.test: runs at 10, 10 and 20 CPU s before the start (the 20 s one in a step the card's next step
# carries), then, after it, 10 (at the start's exact time), the carried 20 and 20. The rule matches when its last 2
# of at least 3 runs are over 1.5 times the usual before them: with every run it matches; with the start only 2 runs
# count (the carried 20 is not one), so it does not.
t_thrules() {
  local n=1 t x r
  setup '[]'; tune '.test.rules = {on: true, list: [{name: "over", on: true, measure: "usual", limit: 1.5, runs: 2, minRuns: 3}]}'
  for x in "2026-11-01T00:00:00Z 10" "2026-11-02T00:00:00Z 10" "2026-11-10T00:00:00Z 20" "$TH_START 10" "2026-11-20T12:05:00Z 20 carried" "2026-11-20T12:10:00Z 20"; do
    read -r t r x <<<"$x"
    jq -cn --arg t "$t" --argjson r "$r" --argjson n "$n" --arg c "${x:-}" '{card: "c-r\(if $c == "" then $n else 3 end)", issue: $n, step: "test", time: $t, result: "pass", times: {"r.test": $r}}
      + (if $c == "" then {} else {carried: ["r.test"]} end)' >> "$ST/cards.jsonl"
    n=$((n + 1))
  done
  r=$(th_as testrules testrulesmatches 1794312000 "$(th_as testrules testrulesettings)") || fail "the rules' matches could not be read with no start"
  [ "$(jq -c 'map([.rule, .file, .values.cpu])' <<<"$r")" = '[["over","r.test",[20,20]]]' ] \
    || fail "with no start set, the rule does not match r.test (runs 10, 10, 20, 10, 20, 20): $r"
  loop test-settings history-start "$TH_START" || fail "the start $TH_START was not saved"
  r=$(th_as testrules testrulesmatches 1794312000 "$(th_as testrules testrulesettings)") || fail "the rules' matches could not be read with the start $TH_START"
  [ "$r" = '[]' ] || fail "with the start $TH_START, the rule counts a run before it, or the carried time of one: $r"
}
# Bug it catches: a time of a run before the start came back as one after it when its file was kept as passed through
# two failed steps. A failed step saves no times, so the card's step that timed q.test (900 CPU s, before the start,
# in a step that failed) is told only by the failed steps that carry it: two of them after the start, then a step that
# passed and carried the 900 (from the run before) with its timed entry. The time must be dated by the step before
# the first failed step that carried it, not by the second failed step: with the start set, that step's facts hold no time
# of q.test; with no start, they hold it.
t_thretry() {
  local got
  setup '[]'
  jq -cn '{card: "c-q", issue: 1, step: "test", time: "2026-11-10T00:00:00Z", result: "fail", failures: {of: 1, files: [{file: "other.test", cases: [{name: "one"}]}], timeout: null}}' >> "$ST/cards.jsonl"
  jq -cn '{card: "c-q", issue: 1, step: "test", time: "2026-11-20T12:05:00Z", result: "fail", carried: ["q.test"], failures: {of: 1, files: [{file: "other.test", cases: [{name: "one"}]}], timeout: null}}' >> "$ST/cards.jsonl"
  jq -cn '{card: "c-q", issue: 1, step: "test", time: "2026-11-20T12:10:00Z", result: "fail", carried: ["q.test"], failures: {of: 1, files: [{file: "other.test", cases: [{name: "one"}]}], timeout: null}}' >> "$ST/cards.jsonl"
  jq -cn '{card: "c-q", issue: 1, step: "test", time: "2026-11-20T12:15:00Z", result: "pass", times: {"q.test": 900}, clocks: {"q.test": 901}, timed: [{file: "q.test", sec: 901, cpu: 900}], carried: ["q.test"]}' >> "$ST/cards.jsonl"
  got=$(th_as testaction testfacts q.test) || fail "testfacts q.test failed with no start: $got"
  [ "$(jq -c '[.runs[] | select(.times != null or .timed != null) | .times]' <<<"$got")" = '[900]' ] \
    || fail "with no start set, the facts for q.test do not hold its 900 s time: $got"
  loop test-settings history-start "$TH_START" || fail "the start $TH_START was not saved"
  got=$(th_as testaction testfacts q.test) || fail "testfacts q.test failed with the start $TH_START: $got"
  [ "$(jq -c '[.runs[] | select(.times != null or .clocks != null or .timed != null)]' <<<"$got")" = '[]' ] \
    || fail "the facts for q.test with the start $TH_START hold the time of a run before it (kept as passed through two failed steps): $got"
}
# Bug it catches: a new time was dropped when a retry carried it. r.test was timed (900 CPU s) in a step before the start;
# a failed step after it kept r.test as passed; the next failed step, also after it, ran r.test again (saving no times)
# and failed another test; the step after that passed and carried the new time (10). The carried time is that of the
# step that ran r.test last (the second failed step), not of the first step that timed it, so with the start set it counts.
t_thretrynew() {
  local got
  setup '[]'
  jq -cn '{card: "c-r", issue: 1, step: "test", time: "2026-11-10T00:00:00Z", result: "pass", times: {"r.test": 900}, timed: [{file: "r.test", sec: 901, cpu: 900}]}' >> "$ST/cards.jsonl"
  jq -cn '{card: "c-r", issue: 1, step: "test", time: "2026-11-20T12:05:00Z", result: "fail", carried: ["r.test"], failures: {of: 1, files: [{file: "other.test", cases: [{name: "one"}]}], timeout: null}}' >> "$ST/cards.jsonl"
  jq -cn '{card: "c-r", issue: 1, step: "test", time: "2026-11-20T12:10:00Z", result: "fail", failures: {of: 1, files: [{file: "other.test", cases: [{name: "one"}]}], timeout: null}}' >> "$ST/cards.jsonl"
  jq -cn '{card: "c-r", issue: 1, step: "test", time: "2026-11-20T12:15:00Z", result: "pass", times: {"r.test": 10}, timed: [{file: "r.test", sec: 11, cpu: 10}], carried: ["r.test"]}' >> "$ST/cards.jsonl"
  loop test-settings history-start "$TH_START" || fail "the start $TH_START was not saved"
  got=$(th_as testaction testfacts r.test) || fail "testfacts r.test failed with the start $TH_START: $got"
  [ "$(jq -c '[.runs[] | select(.times != null or .timed != null) | [.time, .times, .timed.cpu]]' <<<"$got")" = '[["2026-11-20T12:10:00Z",10,10]]' ] \
    || fail "the facts for r.test with the start $TH_START drop the new time a retry carried, keep the 900 s one before it, or date it by the step that carried it (12:15) and not the step that ran it (12:10): $got"
}

# Bug it guards (#1461 B-R390): a survey time counts for each file the Tests page has a row for (testspart() $rows:
# listed, a card or whole-suite run, a Board filing, a Tests page card), and no case had a file whose only record was
# a whole-suite run or a filing, so dropping either source from $rows failed nothing. src/s.mjs and src/f.mjs match no
# pattern (none is set: *.test.* files alone); the survey saved a time of each; a release suite ran src/s.mjs, and the
# Board filed an issue for src/f.mjs. Each row holds the survey run, beside the suite run for src/s.mjs.
t_thsurveyrows() {
  setup '[]'; mkdir -p "$R/src" "$ST/testactions" && echo x > "$R/src/s.mjs" && echo x > "$R/src/f.mjs" \
    && echo '{"files": {"src/s.mjs": {"sec": 7.5, "cpu": 6.25}, "src/f.mjs": {"sec": 3, "cpu": 2}}}' > "$R/.conveyor/test-times.json" \
    && git -C "$R" add src && git -C "$R" add -f .conveyor/test-times.json && GIT_COMMITTER_DATE=2026-11-12T00:00:00Z git -C "$R" commit -qm tests \
    && jq -cn '{time: "2026-11-11T00:00:00Z", how: "release", sha: "", files: {"src/s.mjs": {result: "ok", sec: 9, cpu: 8}}}' > "$ST/suiteruns.jsonl" \
    && jq -cn '{event: "filed", file: "src/f.mjs", issue: 12, time: "2026-11-11T00:00:00Z"}' > "$ST/testactions/filed.jsonl" || fail "the fixture"
  got=$(th_as snapshot testspart 2026-11-09) || fail "testspart failed: $got"
  [ "$(jq -c '[.files[] | select(.file | startswith("src/")) | {file, runs: [.runs[] | [.cpu, (.survey // false), .whole]]}] | sort_by(.file)' <<<"$got")" \
    = '[{"file":"src/f.mjs","runs":[[2,true,false]]},{"file":"src/s.mjs","runs":[[6.25,true,false],[8,false,true]]}]' ] \
    || fail "the survey time of a file only a suite run or a filing puts on the page is not on its row: $(jq -c '[.files[] | select(.file | startswith("src/"))]' <<<"$got")"
}

# Bug it catches: a carried time was dated by a step that ran only some cases of the file, so a whole-file time from
# before the start came back. p.test passed whole (900 CPU s) before the start; after it, a fix's step ran one case of
# it (its line names it partial, with no time of it); then a step that ran another shared file again carried p.test's
# 900 s from the runs before (testlist.sh timed(): <worktree>.oldtimes). That time is the first step's, so with the
# start set no reader counts it: the partial step is not its source. q.test, of another card, is the same after the
# start: passed whole (30 CPU s) at 12:01, one case of it ran in a failed step (testlist.sh carriedrec() names it
# partial on a failed line too), then a passing step carried its 30 s. That time stays, dated 12:01, not by the
# failed step.
th_partfixture() {
  setup '[]'
  jq -cn '{card: "c-p", issue: 1, step: "test", time: "2026-11-10T00:00:00Z", result: "pass", times: {"p.test": 900}, clocks: {"p.test": 901}, timed: [{file: "p.test", sec: 901, cpu: 900}]}' >> "$ST/cards.jsonl"
  jq -cn '{card: "c-p", issue: 1, step: "test", time: "2026-11-20T12:05:00Z", result: "pass", partial: ["p.test"]}' >> "$ST/cards.jsonl"
  jq -cn '{card: "c-p", issue: 1, step: "test", time: "2026-11-20T12:10:00Z", result: "pass", times: {"p.test": 900, "s.test": 4}, clocks: {"p.test": 901, "s.test": 5}, timed: [{file: "p.test", sec: 901, cpu: 900}], carried: ["p.test"]}' >> "$ST/cards.jsonl"
  jq -cn '{card: "c-q", issue: 2, step: "test", time: "2026-11-20T12:01:00Z", result: "pass", times: {"q.test": 30}, clocks: {"q.test": 31}}' >> "$ST/cards.jsonl"
  jq -cn '{card: "c-q", issue: 2, step: "test", time: "2026-11-20T12:05:00Z", result: "fail", partial: ["q.test"], failures: {of: 1, files: [{file: "r.test", cases: [{name: "one"}]}], timeout: null}}' >> "$ST/cards.jsonl"
  jq -cn '{card: "c-q", issue: 2, step: "test", time: "2026-11-20T12:10:00Z", result: "pass", times: {"q.test": 30, "r.test": 2}, clocks: {"q.test": 31, "r.test": 3}, carried: ["q.test"]}' >> "$ST/cards.jsonl"
  loop test-settings history-start "$TH_START" || fail "the start $TH_START was not saved"
}
# The Tests page (testspart(): startlines()).
t_thpartpage() {
  local got; th_partfixture
  got=$(th_as snapshot testspart 2026-11-09) || fail "testspart failed with the start $TH_START: $got"
  [ "$(jq -c '[.files[] | select(.file == "p.test") | .runs[] | .cpu]' <<<"$got")" = '[]' ] \
    || fail "with the start $TH_START, the Tests page keeps p.test's 900 s from before it, carried after a step that ran one case of it: $(jq -c '.files[] | select(.file == "p.test")' <<<"$got")"
}
# The Tests judge's facts (testfacts()).
t_thpartfacts() {
  local got; th_partfixture
  got=$(th_as testaction testfacts p.test) || fail "testfacts p.test failed with the start $TH_START: $got"
  [ "$(jq -c '[.runs[] | select(.times != null or .timed != null) | .time]' <<<"$got")" = '[]' ] \
    || fail "with the start $TH_START, the facts for p.test keep its 900 s from before it, dated by a later step that ran one case of it: $got"
  got=$(th_as testaction testfacts q.test) || fail "testfacts q.test failed with the start $TH_START: $got"
  [ "$(jq -c '[.runs[] | select(.carried == true) | .time]' <<<"$got")" = '["2026-11-20T12:01:00Z"]' ] \
    || fail "with the start $TH_START, the facts for q.test do not date its carried 30 s by the step that ran it whole (12:01), not the failed step that ran one case of it (12:05): $got"
}
