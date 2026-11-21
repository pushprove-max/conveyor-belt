#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 120
# Engine cases: the snapshot's tests part (lib/testfiles.sh testspart()), a test file's "slow on purpose" mark, the
# times a card's run records (testlist.sh slowtests()), and `conveyor.sh test-settings`, which saves the mark and the
# project's test settings in the pack. No test file has a CPU budget (#349).
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"

# One passing card test line per run of <file>, a minute apart in order, each timing it at its CPU seconds and at one
# second more of clock time (times, clocks), appended to the card records.
tf_runs() { # <file> <CPU s>...
  jq -cn --arg f "$1" '$ARGS.positional | map(tonumber) | to_entries[] | {card: "c-\($f)-\(.key)", issue: 1, step: "test",
    time: "2026-11-10T12:\(.key | tostring | if length < 2 then "0" + . else . end):00Z", tokens: {claude: 0, codex: 0}, result: "pass",
    sha: "", reason: "", times: {($f): .value}, clocks: {($f): (.value + 1)}}' --args "${@:2}" >> "$ST/cards.jsonl"
}
# Each case's main holds setup's stub test file a.test.sh (filemode, lib.sh), so the part lists it; no card test line times it (only t_tfsuite's whole-suite runs).
# The engine's functions, as the script of <command> (conveyor/commands/) loads them, in a shell of the case's main
# ($R): <function> run there, with the 7 days from 2026-11-09. tf_in as the snapshot loads them (testspart), tf_card
# as the loop does a card's test step (slowtests, slowrec).
# shellcheck source=/dev/null # the command's libraries, by its . lines or its SNAPLIBS list (commands/snapshot.sh)
tf_as() { ( export CONVEYOR_MAIN=$R CONVEYOR_CARDS=$T/$CASE/cards; . "$SRC/conveyor.sh" state-dir > /dev/null \
  && eval "$(grep -e '^\. "\$HERE/lib/' -e '^SNAPLIBS=' "$SRC/commands/$1.sh")" \
  && for l in ${SNAPLIBS-}; do . "$HERE/lib/$l.sh" || exit 1; done && "${@:2}" ); } # <command> <function>...
tf_in() { tf_as snapshot "$@"; }
tf_card() { tf_as run "$@"; }

# The Tests page compares a file with its own usual time: merge.test.sh went from 25 to 72 CPU s in hours while one
# budget for all files showed nothing. a.test ran at 2, 4, 3 and 10 CPU s: now 10, the median of its 4 runs 3.5, and
# the change (10 - 3.5) / 3.5. Its last run's clock seconds (11) against its CPU seconds; it failed in two test steps
# (a failed file, a time-out in it); two flaky entries are its own (a.testx's is not); its last slow-test issue is #42.
# Bug caught: a part that took the median of the last run alone, or counted another file's failures or flaky entries.
# Each file's issue is the newest filed for it: a.test's from the slow-test record alone; b.test's #44 from the test
# rules' log (#43 in the slow-test record); c.test's #47 from the Board's File an issue (#46 in the test rules' log);
# d.test's #49 is no other file's. Bug caught: the issue came from the slow-test record alone, which nothing writes now,
# so a file the test rules (their log) or the Board's File an issue ($TAFILED) filed for had no issue, and no Close its
# issue as done.
t_tfpart() {
  setup '[]'; tf_runs a.test 2 4 3 10; tf_runs b.test 1
  { jq -cn '{card: "c-f1", issue: 2, step: "test", time: "2026-11-11T12:00:00Z", result: "fail", failures: {of: 2, files: [{file: "a.test", cases: []}, {file: "b.test", cases: []}], timeout: null}}'
    jq -cn '{card: "c-f2", issue: 2, step: "test", time: "2026-11-11T13:00:00Z", result: "fail", failures: {of: 1, files: [], timeout: {sec: 60, file: "a.test"}}}'
    jq -cn '{card: "c-f3", issue: 2, step: "test", time: "2026-11-11T14:00:00Z", result: "fail", failures: {of: 1, files: [{file: "b.test", cases: []}], timeout: null}}'; } >> "$ST/cards.jsonl"
  echo '{"entries": [{"case": "a.test: one", "source": "s", "time": "2026-11-10T00:00:00Z"}, {"case": "a.test", "source": "t", "time": "2026-11-10T00:00:00Z"},
    {"case": "a.testx: y", "source": "s", "time": "2026-11-10T00:00:00Z"}], "filed": []}' > "$ST/flaky.json"
  echo '{"filed": [{"file": "a.test", "issue": 41}, {"file": "a.test", "issue": 42}, {"file": "b.test", "issue": 43}]}' > "$ST/slow.json"
  printf '%s\n' '{"event": "filed", "file": "b.test", "issue": 44}' '{"event": "stopped", "file": "b.test", "guard": "perDay"}' '{"event": "filed", "file": "c.test", "issue": 46}' > "$ST/testrules.jsonl"
  mkdir -p "$ST/testactions" && printf '%s\n' '{"event": "filed", "file": "c.test", "issue": 47}' '{"event": "filed", "file": "d.test", "issue": 49}' > "$ST/testactions/filed.jsonl"
  got=$(tf_in testspart 2026-11-09) || fail "testspart failed: $got"
  [ "$(jq -c '.files[] | select(.file == "a.test") | {cpu, median, change, runs: [.runs[].cpu], newest: (.runs[0] | {card, time}), lastRun, timedRuns, failedSteps, flaky, issue}' <<<"$got")" \
    = '{"cpu":10,"median":3.5,"change":1.857,"runs":[10,3,4,2],"newest":{"card":"c-a.test-3","time":"2026-11-10T12:03:00Z"},"lastRun":{"sec":11,"cpu":10,"clockPerCpu":1.1,"time":"2026-11-10T12:03:00Z","whole":false},"timedRuns":4,"failedSteps":2,"flaky":2,"issue":42}' ] \
    || fail "a.test's figures: $(jq -c '.files[] | select(.file == "a.test")' <<<"$got")"
  [ "$(jq -cS '.files | map({key: .file, value: .issue}) | from_entries' <<<"$got")" = '{"a.test":42,"a.test.sh":null,"b.test":44,"c.test":47,"d.test":49}' ] \
    || fail "each file's issue, the newest filed for it in any record: $(jq -c '[.files[] | {file, issue}]' <<<"$got")"
}

# Main's checkout with a project's test-*.mjs files and a hook test x.test.sh (one case, one), all committed, and,
# with <saved> given, the survey's saved times of src/test-a.mjs in .conveyor/test-times.json, committed at a known time.
tf_patfiles() { # [saved]
  mkdir -p "$R/src" "$R/scripts" "$R/.claude/hooks"
  printf "import test from 'node:test';\ntest('a', () => {});\n" > "$R/src/test-a.mjs"; cp "$R/src/test-a.mjs" "$R/scripts/test-b.mjs"
  printf 't_one() {\n  :\n}\n' > "$R/.claude/hooks/x.test.sh"
  # The fixture's .gitignore holds .conveyor; a host project commits its test-times.json.
  [ -z "${1:-}" ] || { echo '{"files": {"src/test-a.mjs": {"sec": 7.5, "cpu": 6.25}}}' > "$R/.conveyor/test-times.json" && git -C "$R" add -f .conveyor/test-times.json; } \
    || fail "the saved times"
  git -C "$R" add src scripts .claude/hooks && GIT_COMMITTER_DATE=2026-11-12T00:00:00Z git -C "$R" commit -qm tests || fail "main's test files"
}
# Bug it catches (#1036): the Tests page listed only *.test.* files, so a project whose tests.patterns name its tests
# test-*.mjs saw none of them. Both test-*.mjs files are listed, beside the *.test.* files; an .mjs file's cases are
# not counted (null, not an empty list that reads as no case), while the shell file's are; the survey's saved times
# of src/test-a.mjs are its newest run, marked survey (it was said "a card" on the Board), after its five card runs
# (two days before), and the oldest card run, which the survey's run pushed out of runs, is in testolder()'s olderRuns
# (it was dropped from the Timeline).
t_tfpatterns() {
  setup '[]'; tune '.tests.patterns = ["test-*.mjs"]'; tf_patfiles saved; tf_runs src/test-a.mjs 1 2 3 4 5
  got=$(tf_in testspart 2026-11-09) || fail "testspart failed: $got"
  [ "$(jq -c '[.files[].file] | sort' <<<"$got")" = '[".claude/hooks/x.test.sh","a.test.sh","scripts/test-b.mjs","src/test-a.mjs"]' ] \
    || fail "the files the patterns match and the *.test.* files: $(jq -c '[.files[].file]' <<<"$got")"
  [ "$(jq -c '[.files[] | {file, cases}] | sort_by(.file)' <<<"$got")" \
    = '[{"file":".claude/hooks/x.test.sh","cases":["one"]},{"file":"a.test.sh","cases":[]},{"file":"scripts/test-b.mjs","cases":null},{"file":"src/test-a.mjs","cases":null}]' ] \
    || fail "each file's cases: $(jq -c '[.files[] | {file, cases}]' <<<"$got")"
  [ "$(jq -c '.files[] | select(.file == "src/test-a.mjs") | {cpu, survey: .runs[0], cards: [.runs[1:][].cpu], timedRuns, last: .lastRun.survey}' <<<"$got")" \
    = '{"cpu":6.25,"survey":{"cpu":6.25,"sec":7.5,"card":null,"time":"2026-11-12T00:00:00Z","whole":false,"survey":true},"cards":[5,4,3,2],"timedRuns":6,"last":true}' ] \
    || fail "the saved times of src/test-a.mjs: $(jq -c '.files[] | select(.file == "src/test-a.mjs")' <<<"$got")"
  got=$(tf_as history testolder src/test-a.mjs | jq -c '[.olderRuns[] | [.cpu, .card]]')
  [ "$got" = '[[1,"c-src/test-a.mjs-0"]]' ] || fail "the older runs of src/test-a.mjs: $got"
}
# With no tests.patterns in the pack the list is the *.test.* files, as before #1036: not the schema's default
# patterns, which name test-*.mjs too. Bugs it catches: a list that took the default patterns when the pack sets none;
# and a survey time saved for src/test-a.mjs (the survey reads the default patterns) that added it to the list.
t_tfnopatterns() {
  setup '[]'; tf_patfiles saved
  got=$(tf_in testspart 2026-11-09) || fail "testspart failed: $got"
  [ "$(jq -c '[.files[].file] | sort' <<<"$got")" = '[".claude/hooks/x.test.sh","a.test.sh"]' ] \
    || fail "the *.test.* files alone: $(jq -c '[.files[].file]' <<<"$got")"
}
# Bugs it catches (#1048): testowners and testedits read the *.test.* files alone, not those the pack's tests.patterns
# match. So a case the runner run.test.sh names as its own, defined in src/test-c.mjs, which names that runner, counted
# for the runner alone; and a card's change to src/test-a.mjs was missing from its testedits.
t_tfpatfind() {
  setup '[]'; tune '.tests.patterns = ["test-*.mjs"]'; mkdir -p "$R/src"
  printf '// runs through run.test.sh\nrone() {}\n' > "$R/src/test-c.mjs"; tf_patfiles
  got=$(tf_in eval 'testowners && jq -cn --argjson d "$defs" --argjson r "$refs" "[\$d.rone, \$r[\"src/test-c.mjs\"]]"') || fail "testowners failed: $got"
  [ "$got" = '[["src/test-c.mjs"],["run.test.sh"]]' ] || fail "the case's file and the runner it names: $got"
  W=$T/$CASE/cards/c-1; git -C "$R" worktree add -q --detach "$W" || fail "the card's worktree"
  echo "import test from 'node:test';" > "$W/src/test-a.mjs"; git -C "$W" add -A || fail "the card's change"
  got=$(tf_card eval 'testedits "$W"' | jq -c 'map([.file, .casesDeleted])') || fail "testedits failed: $got"
  [ "$got" = '[["src/test-a.mjs",1]]' ] || fail "the test-*.mjs file the card changed, its test('a') case deleted: $got"
}
# The case reader (TESTEDIT_TABLE's case patterns) counts each language's cases: a card that deletes the whole file
# deletes them all. Bug it catches (#1049): pytest and Go files had no row, so their cases were not read (read false),
# and a JavaScript test( or it( call with a name from a variable or a template with ${...} counted as a case.
# node:test: two cases (a t.test subtest and test(name) from a variable are not); Jest: two it( cases and a test.only,
# not the describe; pytest: a def test_ and an async def test (not the helper); Go: TestOne and Test_two (not the
# helper, nor Testing, which go test does not run); an .rb file is still listed, with no case count.
t_tfcases() {
  setup '[]'; tune '.tests.patterns = ["*.test.*", "test_*.py", "*_test.go"]'
  printf '%s\n' "import test from 'node:test';" "test('a', async (t) => {" "  await t.test('sub', () => {});" '});' \
    "test(\"b\", () => {});" 'for (const name of names) test(name, () => {});' 'test(`c ${n}`, () => {});' > "$R/node.test.mjs"
  printf '%s\n' "describe('d', () => {" "  it('x', () => { expect(1).toBe(1); });" '  it(`y`, () => {});' "  test.only('z', () => {});" '});' > "$R/jest.test.js"
  printf '%s\n' 'import pytest' 'def helper():' '    pass' 'def test_one():' '    assert helper() is None' 'async def test_two():' '    pass' > "$R/test_a.py"
  printf '%s\n' 'package a' 'func helper() {}' 'func TestOne(t *testing.T) {' '	t.Fatal("x")' '}' 'func Test_two(t *testing.T) {}' 'func Testing() {}' > "$R/a_test.go"
  echo "it 'works' do end" > "$R/a.test.rb"
  git -C "$R" add -A && git -C "$R" commit -qm tests || fail "main's test files"
  W=$T/$CASE/cards/c-1; git -C "$R" worktree add -q --detach "$W" || fail "the card's worktree"
  git -C "$W" rm -q node.test.mjs jest.test.js test_a.py a_test.go a.test.rb || fail "the card's change"
  got=$(tf_card eval 'testedits "$W"' | jq -c 'map([.file, .read, .casesDeleted]) | sort') || fail "testedits failed: $got"
  [ "$got" = '[["a.test.rb",false,null],["a_test.go",true,2],["jest.test.js",true,3],["node.test.mjs",true,2],["test_a.py",true,2]]' ] \
    || fail "each file's cases: $got"
}
# A Python or Go assertion whose message alone changes is no changed expected value; one whose expected value changes
# is. Bug it catches (#1049): these assertions were read whole, the message as part of the expected value, so a
# reworded unittest, bare assert, t.Errorf or require message showed as a changed expected value on the Board.
t_tfeditmsg() {
  local got
  got=$( . "$SRC/lib/testfiles.sh"
    ed() { printf '%s\0%s' "$2" "$3" | jq -Rsc --arg f "$1" "$TESTEDIT_TABLE$TESTEDIT_JQ" | jq -c '[.file, .removedAsserts, .changedExpected]'; }
    ed u.py "        self.assertEqual(b, [0, 2], 'a change: %s' % b)" "        self.assertEqual(b, [0, 2], 'no change: %s' % b)"
    ed v.py "        self.assertEqual(b, [0, 2], 'm')" "        self.assertEqual(b, [0, 3], 'm')"
    ed t.py "        self.assertTrue(ok, 'on')" "        self.assertTrue(ok, 'it is on')"
    ed a.py "    assert f() == 3, 'three'" "    assert f() == 3, 'it is three'"
    ed b.py "    assert f() == 3, 'three'" "    assert f() == 4, 'three'"
    ed e.go '	t.Errorf("got %v", got)' '	t.Errorf("have %v", got)'
    ed r.go '	require.Equal(t, 3, got, "m")' '	require.Equal(t, 3, got, "n")'
    ed s.go '	assert.Equal(t, 3, got, "m")' '	assert.Equal(t, 4, got, "m")' ) || fail "the reader failed: $got"
  [ "$(jq -sc . <<<"$got")" = '[["u.py",0,0],["v.py",0,1],["t.py",0,0],["a.py",0,0],["b.py",0,1],["e.go",0,0],["r.go",0,0],["s.go",0,1]]' ] \
    || fail "each edit's removed assertions and changed expected values: $got"
}
# A file no pattern lists but card runs keep on the page keeps its survey time too. Bug it catches (#1044): the part
# dropped the survey run of an unlisted file, so its newest run was a card's, while testolder() counted the survey and
# gave as older the oldest card run, which the part's runs already held: the Timeline showed that run twice.
t_tfunlistedsurvey() {
  setup '[]'; tf_patfiles saved; tf_runs src/test-a.mjs 1 2 3 4 5
  got=$(tf_in testspart 2026-11-09) || fail "testspart failed: $got"
  [ "$(jq -c '.files[] | select(.file == "src/test-a.mjs") | {survey: .runs[0].survey, cards: [.runs[1:][].card], timedRuns}' <<<"$got")" \
    = '{"survey":true,"cards":["c-src/test-a.mjs-4","c-src/test-a.mjs-3","c-src/test-a.mjs-2","c-src/test-a.mjs-1"],"timedRuns":6}' ] \
    || fail "the runs of src/test-a.mjs: $(jq -c '.files[] | select(.file == "src/test-a.mjs")' <<<"$got")"
  got=$(tf_as history testolder src/test-a.mjs | jq -c '[.olderRuns[].card]')
  [ "$got" = '["c-src/test-a.mjs-0"]' ] || fail "the older runs of src/test-a.mjs: $got"
}

# The engine's runner names a failed or flaky case as its own (run.test.sh: rone), while the times name the case file
# that ran it (cases/r.test.sh, which defines t_rone): the case counts for its case file. Another file's case (rtwo, in
# cases/q.test.sh) does not, and a step that failed two of its cases counts once. A case file names the runner it runs
# through; solo.test.sh, which runs alone, and o.test.sh, another runner's case file, define a case rone too and get
# none of it; solo.test.sh's own flaky rone is its alone. Bugs caught: every engine case file showed no failed step and no flaky entry, as the records' file names
# did not match; a runner's `setup` failure counted for both tests/setup.test.sh and foreman/foreman.test.sh.
# The Tests page lists every test file of main's checkout. c.test.sh ran on a card; w.test.sh, wholeOnly in the pack,
# ran only in a whole-suite run, whose files the run's output names (testlist.sh suiterec(): its `TESTRUN sec` and `-- FAIL` lines);
# n.test.sh never ran. Bug caught: the part was made from card test lines alone, so a whole-only file
# (conveyor/conveyor.test.sh) and a file never run were missing, and no whole-suite run reached the page.
t_tfrunner() {
  setup '[]'; mkdir -p "$R/cases"; tune '.test.files = {"w.test.sh": {wholeOnly: true}}'
  printf '# run.test.sh\nt_rone() {\n  :\n}\nrhelp() {\n  :\n}\nt_r_help() { :; }\n# <<EOF\nt_rthree() {\n  cat <<'"'"'X'"'"' > f\nt_rfix() {\nX\n}\n' > "$R/cases/r.test.sh"; printf '# run.test.sh\nt_rtwo() {\n  :\n}\n' > "$R/cases/q.test.sh"
  # printf, not a heredoc: a fixture line starting t_ here would be a case the runner selects in this file (#370).
  printf '%s\n' "printf 'a <<EOF\\n' \"\$(cat <<<\"x\")\"" "echo \"b <<'EOF'\" \$'c <<\\'EOF\\'' > \"\$f\" <<Y" \
    't_rfive() {' Y 't_rfour() {' '  :' '}' >> "$R/cases/r.test.sh"
  printf 't_rone() {\n  :\n}\n' > "$R/cases/solo.test.sh"; printf '# other.test.sh\nt_rone() {\n  :\n}\n' > "$R/cases/o.test.sh"
  touch "$R/c.test.sh" "$R/w.test.sh" "$R/n.test.sh" "$R/zz.test.sh"
  git -C "$R" add cases c.test.sh w.test.sh n.test.sh zz.test.sh && git -C "$R" commit -qm tests || fail "main's test files"
  tf_runs cases/r.test.sh 2 3; tf_runs cases/q.test.sh 1; tf_runs cases/solo.test.sh 0.5; tf_runs cases/o.test.sh 0.4; tf_runs c.test.sh 2
  printf 'TESTRUN sec\tw.test.sh\t48\t30.5\n-- FAIL w.test.sh\n' > "$T/$CASE/suite.test"
  CONVEYOR_NOW=1794700800 tf_as full-test suiterec "$T/$CASE/suite" full 0123abcd || fail "suiterec failed"
  { jq -cn '{card: "c-f1", issue: 2, step: "test", time: "2026-11-11T12:00:00Z", result: "fail", failures: {of: 1, files: [{file: "run.test.sh", cases: [{name: "rone", line: 3}, {name: "rthree", line: 4}]}], timeout: null},
      verdicts: [{case: "run.test.sh: rone", verdict: "card"}, {case: "run.test.sh: rthree", verdict: "main"}], tail: ("x" * 1600 + "END")}'
    jq -cn '{card: "c-f2", issue: 2, step: "test", time: "2026-11-11T13:00:00Z", result: "fail", failures: {of: 1, files: [{file: "run.test.sh", cases: [{name: "rtwo", line: 3}]}], timeout: null},
      verdicts: [{case: "run.test.sh: rtwo", verdict: "card"}]}'
    # c.test.sh failed in 6 steps: the oldest has no tail, past the newest TESTKEEP (5). The newest passed on re-run
    # (card(): a `test pass` line, its first run's failures and output's end in rerun, firstrun()), with no tail of its own.
    jq -cn 'range(5) | {card: "c-g\(.)", issue: 3, step: "test", time: "2026-11-12T0\(.):00:00Z", result: "fail", failures: {of: 1, files: [{file: "c.test.sh", cases: [{name: "one"}]}], timeout: null},
      verdicts: [{case: "c.test.sh: one", verdict: "card"}], tail: "t\(.)"}'
    jq -cn '{card: "c-g5", issue: 3, step: "test", time: "2026-11-12T05:00:00Z", result: "pass", reason: "passed on re-run: c.test.sh: one",
      rerun: {exit: 1, failures: {files: [{file: "c.test.sh", cases: [{name: "one"}]}], timeout: null}, tail: "not ok one"}, verdicts: [{case: "c.test.sh: one", verdict: "flaky"}]}'
    # A step that failed again in another file (zz.test.sh) after n.test.sh's case and w.test.sh's time-out of its
    # first run passed on the run again; its tail is the run again's, its first run's in rerun.
    jq -cn '{card: "c-h1", issue: 4, step: "test", time: "2026-11-13T00:00:00Z", result: "fail", failures: {of: 1, files: [{file: "zz.test.sh", cases: [{name: "x"}]}], timeout: null},
      tail: "again", rerun: {exit: 1, failures: {files: [{file: "n.test.sh", cases: [{name: "two"}]}, {file: "zz.test.sh", cases: [{name: "x"}]}], timeout: {sec: 60, file: "w.test.sh"}}, tail: "first"},
      verdicts: [{case: "n.test.sh: two", verdict: "flaky"}, {case: "w.test.sh", verdict: "flaky"}, {case: "zz.test.sh: x", verdict: "card"}]}'; } >> "$ST/cards.jsonl"
  echo '{"entries": [{"case": "run.test.sh: rone", "source": "s", "time": "2026-11-10T00:00:00Z"}, {"case": "run.test.sh: rtwo", "source": "s", "time": "2026-11-10T00:00:00Z"},
    {"case": "cases/solo.test.sh: rone", "source": "s", "time": "2026-11-10T00:00:00Z"}], "filed": []}' > "$ST/flaky.json"
  got=$(tf_in testspart 2026-11-09) || fail "testspart failed: $got"
  [ "$(jq -c '[.files[] | select(.file | startswith("cases/")) | {file, failedSteps, flaky}]' <<<"$got")" = '[{"file":"cases/r.test.sh","failedSteps":1,"flaky":1},{"file":"cases/q.test.sh","failedSteps":1,"flaky":1},{"file":"cases/solo.test.sh","failedSteps":0,"flaky":1},{"file":"cases/o.test.sh","failedSteps":0,"flaky":0}]' ] \
    || fail "the runner's cases: $(jq -c '[.files[] | {file, failedSteps, flaky}]' <<<"$got")"
  # Bug it catches (#272): the Board's search found no file by a case it defines (capwaittests in capwait.test.sh),
  # as the part named a file's cases only in its failures. Each file has the cases it defines: q.test.sh's rtwo is not
  # r.test.sh's; r.test.sh's helpers rhelp and t_r_help (a name the runner does not select) and the case rfix its
  # heredoc writes are no cases (the search showed them as cases); a comment's <<EOF starts no heredoc, so rthree is
  # found; a quoted <<EOF is text (#370: it hid every later case), so rfour is found and the real <<Y after it still
  # hides rfive; and c.test.sh, which defines none (its failed case one is not defined there), has [].
  [ "$(jq -c '[.files[] | select(.file | IN("cases/r.test.sh", "cases/q.test.sh", "c.test.sh")) | {file, cases}]' <<<"$got")" \
    = '[{"file":"cases/r.test.sh","cases":["rfour","rone","rthree"]},{"file":"c.test.sh","cases":[]},{"file":"cases/q.test.sh","cases":["rtwo"]}]' ] \
    || fail "each file's own cases: $(jq -c '[.files[] | {file, cases}]' <<<"$got")"
  # Bug it catches (#188): "Fails often" counted every failed step, also those the card's own change caused (the test
  # did its job). Each failure carries the verdict of the cases that count for the file (main before flaky before
  # card; a line's other verdicts are not the file's), its cases, its card and the end of its output.
  [ "$(jq -c '[.files[] | select(.file | IN("cases/r.test.sh", "cases/q.test.sh")) | {file, f: [.failures[] | {card, verdict, cases, tail: (.tail | if . then [length, .[-3:]] else . end)}]}]' <<<"$got")" \
    = '[{"file":"cases/r.test.sh","f":[{"card":"c-f1","verdict":"main","cases":["rone","rthree"],"tail":[1500,"END"]}]},{"file":"cases/q.test.sh","f":[{"card":"c-f2","verdict":"card","cases":["rtwo"],"tail":null}]}]' ] \
    || fail "the failures of the runner's case files: $(jq -c '[.files[] | select(.file | startswith("cases/")) | {file, failures}]' <<<"$got")"
  # Bug it catches (#188): a step that passed on re-run (the flaky failure) was left out, as it is a `test pass` line;
  # and (#228) it had no output, as its tail is its first run's, in rerun.
  [ "$(jq -c '.files[] | select(.file == "c.test.sh") | [.failedSteps, [.failures[] | [.card, .verdict, .tail]]]' <<<"$got")" \
    = '[6,[["c-g5","flaky","not ok one"],["c-g4","card","t4"],["c-g3","card","t3"],["c-g2","card","t2"],["c-g1","card","t1"],["c-g0","card",null]]]' ] \
    || fail "c.test.sh's failures, newest first, a tail on the newest 5 alone: $(jq -c '.files[] | select(.file == "c.test.sh") | .failures' <<<"$got")"
  # Bug it catches (#227): on a step that failed again in another file, the cases that passed on the run again (in
  # rerun alone) were left out, so their files showed no failure. And (#228): those files had the run again's output,
  # which does not show their failure, in place of the first run's; a file that failed again keeps the run again's.
  [ "$(jq -c '[.files[] | select(.file | IN("n.test.sh", "w.test.sh", "zz.test.sh")) | {file, failedSteps, f: [.failures[] | [.card, .verdict, .cases, .tail]]}]' <<<"$got")" \
    = '[{"file":"w.test.sh","failedSteps":1,"f":[["c-h1","flaky",[],"first"]]},{"file":"n.test.sh","failedSteps":1,"f":[["c-h1","flaky",["two"],"first"]]},{"file":"zz.test.sh","failedSteps":1,"f":[["c-h1","card",["x"],"again"]]}]' ] \
    || fail "the first run's failures of a step that failed again: $(jq -c '[.files[] | select(.file | IN("n.test.sh", "w.test.sh", "zz.test.sh")) | {file, failures}]' <<<"$got")"
  got=$(jq -c '[.files[] | select(.file | IN("w.test.sh", "c.test.sh", "n.test.sh")) | {file, cpu, wholeOnly, runs: [.runs[] | {card, whole, result, sec, cpu}], last: (.lastRun | if . then {time, whole} else . end)}]' <<<"$got")
  [ "$got" = '[{"file":"w.test.sh","cpu":30.5,"wholeOnly":true,"runs":[{"card":null,"whole":true,"result":"fail","sec":48,"cpu":30.5}],"last":{"time":"2026-11-15T00:00:00Z","whole":true}},'\
'{"file":"c.test.sh","cpu":2,"wholeOnly":false,"runs":[{"card":"c-c.test.sh-0","whole":false,"result":null,"sec":3,"cpu":2}],"last":{"time":"2026-11-10T12:00:00Z","whole":false}},'\
'{"file":"n.test.sh","cpu":null,"wholeOnly":false,"runs":[],"last":null}]' ] || fail "the three files: $got"
}

# "Slower than its usual", with the pack's own share (0.5), runs in a row (2) and least runs on record (4), so the
# defaults (0.25, 3, 5) would name another set. s.test: 10, 10, then 16 and 16, over its usual of 10 by more than half
# twice: named. o.test: one run short (10 then 16 at the end). f.test: 3 runs on record, too few. h.test: 14 twice,
# over 10 by 40%, under the share. Bug caught: a usual that is the median of every run, the slow runs among them,
# hides a file whose slow runs are half its record (merge.test.sh's 72 CPU s runs).
# A runner that starts other test files whole (wholeOnly in the pack) is never slower than usual: its CPU is the sum
# of its case files', each timed on its own. r.test (wholeOnly) and c.test ran at 10, 10, 900 and 900 CPU s, far over
# their usual: c.test is slower, r.test not. Bug caught: conveyor/conveyor.test.sh showed as slower than usual
# forever, as no change can pass. Bug caught too (#349): a file over the pack's old test.fileBudget, still in it, is
# flagged over budget: no file or total of the part names a budget.
t_tfslower() {
  setup '[]'; tune '.test.fileBudget = 8 | .test.slower = {share: 0.5, runs: 2, minRuns: 4} | .test.files = {"r.test": {wholeOnly: true}}'
  tf_runs s.test 10 10 16 16; tf_runs o.test 10 10 10 16; tf_runs f.test 10 16 16; tf_runs h.test 10 10 14 14
  tf_runs r.test 10 10 900 900; tf_runs c.test 10 10 900 900
  got=$(tf_in testspart 2026-11-09) || fail "testspart failed: $got"
  [ "$(jq -cS '[.slower, .totals.slower, (.files | map({key: .file, value: .slower}) | from_entries)]' <<<"$got")" \
    = '[["c.test","s.test"],2,{"a.test.sh":false,"c.test":true,"f.test":false,"h.test":false,"o.test":false,"r.test":false,"s.test":true}]' ] || fail "the files slower than usual: $(jq -c '[.slower, .files]' <<<"$got")"
  [ "$(jq -c '[(.files[] | select(.file == "s.test") | .usual), (.files[] | select(.file == "f.test") | .usual)]' <<<"$got")" = '[10,null]' ] || fail "the usual times: $got"
  [ "$(jq -c '[(.totals | keys), any(.files[]; has("budget") or has("budgetFrom") or has("over")), (.settings | has("fileBudget"))]' <<<"$got")" \
    = '[["files","slower","steps"],false,false]' ] || fail "the part names a CPU budget: $(jq -c '[.totals, .settings, .files]' <<<"$got")"
}

# A project with no recorded file time still has the part (the page shows its step totals, never an error): main's
# one test file (a.test.sh), no file counted in the totals, and the steps of the 7 days, their slot wait and run seconds added up; a step before the 7 days, and one that
# reused a pass (it ran nothing), are not counted. Bug caught: a project with no test line at all had no part (the
# search for test lines found none and failed the part).
t_tfempty() {
  setup '[]'
  got=$(tf_in testspart 2026-11-09) || fail "testspart failed with no test line: $got"
  [ "$(jq -c '[(.files | map(.file)), .totals.steps]' <<<"$got")" = '[["a.test.sh"],{"count":0,"waitSec":0,"runSec":0}]' ] || fail "the part with no test line: $got"
  # #190: with no whole-suite run and no test.report, the part says none of either (null), never a made-up figure.
  [ "$(jq -c '[.suite, .settings.report]' <<<"$got")" = '[null,null]' ] || fail "the suite and report with none on record: $got"
  { jq -cn '{card: "c-1", issue: 1, step: "test", time: "2026-11-12T12:00:00Z", result: "pass", wait: 3, run: 7}'
    jq -cn '{card: "c-2", issue: 2, step: "test", time: "2026-11-12T13:00:00Z", result: "fail", wait: 1.5, run: 2}'
    jq -cn '{card: "c-3", issue: 3, step: "test", time: "2026-11-12T14:00:00Z", result: "pass", reused: true}'
    jq -cn '{card: "c-0", issue: 4, step: "test", time: "2026-11-01T12:00:00Z", result: "pass", wait: 100, run: 100}'; } >> "$ST/cards.jsonl"
  got=$(tf_in testspart 2026-11-09) || fail "testspart failed: $got"
  [ "$(jq -c '[(.files | map(.file)), .slower, .totals]' <<<"$got")" = '[["a.test.sh"],[],{"files":0,"slower":0,"steps":{"count":2,"waitSec":4.5,"runSec":9}}]' ] \
    || fail "the part with no file time: $got"
}

# Bug it catches (#190): the Board could not say what a whole-only file costs, nor name the runner of a Wall only file.
# The part gives the newest whole-suite run's CPU seconds summed over its files (a file with no CPU seconds adds
# nothing; an older run is not used), and the pack's test.report.
t_tfsuite() {
  setup '[]'; tune '.test.report = {runner: "vitest", format: "jest-json", path: "report.json"}'
  { jq -cn '{time: "2026-11-10T00:00:00Z", how: "full", sha: "abc", files: {"a.test.sh": {result: "ok", sec: 9, cpu: 99}}}'
    jq -cn '{time: "2026-11-12T00:00:00Z", how: "full", sha: "abd", files: {"a.test.sh": {result: "ok", sec: 9, cpu: 6.25}, "b.test.sh": {result: "ok", sec: 3, cpu: 2}, "c.test.ts": {result: "ok", sec: 4, cpu: null}}}'
  } >> "$ST/suiteruns.jsonl"
  got=$(tf_in testspart 2026-11-09) || fail "testspart failed: $got"
  [ "$(jq -c '[.suite, .settings.report]' <<<"$got")" = '[{"time":"2026-11-12T00:00:00Z","cpu":8.25},{"runner":"vitest","format":"jest-json","path":"report.json"}]' ] \
    || fail "the suite's CPU seconds or the report: $(jq -c '[.suite, .settings.report]' <<<"$got")"
  # The Record CPU time plan (cpuplan()) reaches the Board in the part: its file and command, or why not.
  jq -e '.settings.cpuTime | (.why | strings) or (.file and .command)' <<<"$got" > /dev/null || fail "the part has no Record CPU time plan: $(jq -c .settings <<<"$got")"
}

# Bug it catches (#189): a file with no run on record showed "Never run" with no reason, and a file that Waits had no
# waits to name. Each file never run says why when the engine can tell: lone.test.sh and a.test.sh, which the pack's
# tests.patterns do not match; other/o.test.mjs, which the test command's folder (tests) does not hold; tests/bad.test.sh, which
# does not parse (bash -n); tests/skip.test.mjs, skipped by its describe.skip. tests/fine.test.sh says nothing, nor
# does tests/ran.test.sh, which ran. The waits are its newest judge's WAIT lines: an older judge's are not shown. The
# parse is kept by the file's content: a second look reads it from the record, not from bash -n.
t_tfnever() {
  setup '[]'; tune '.tests.patterns = ["tests/", "other/"] | .test.command = "node --test tests"'
  mkdir -p "$R/tests" "$R/other"; echo 'echo one' > "$R/lone.test.sh"; echo 'it("o", () => {});' > "$R/other/o.test.mjs"
  echo 'if then fi' > "$R/tests/bad.test.sh"; echo "describe.skip('x', () => { it('y', () => {}); });" > "$R/tests/skip.test.mjs"
  echo 'echo fine' > "$R/tests/fine.test.sh"; echo 'echo ran' > "$R/tests/ran.test.sh"
  git -C "$R" add -A && git -C "$R" commit -qm 'tests' || fail "main's files"
  tf_runs tests/ran.test.sh 1
  mkdir -p "$ST/testactions"
  jq -cn '{id: "000000000001", action: "judge", state: "done", file: "tests/ran.test.sh", end: "2026-11-10T00:00:00Z", waits: [{case: "old", kind: "sleep", at: "tests/ran.test.sh:1", reason: "older"}]}' > "$ST/testactions/000000000001.json"
  jq -cn '{id: "000000000002", action: "judge", state: "done", file: "tests/ran.test.sh", end: "2026-11-11T00:00:00Z", waits: [{case: "one", kind: "polling", at: "tests/ran.test.sh:1", reason: "it polls"}]}' > "$ST/testactions/000000000002.json"
  got=$(tf_in testspart 2026-11-09) || fail "testspart failed: $got"
  [ "$(jq -c '[.files[] | {file, neverRun}] | sort_by(.file)' <<<"$got")" = '[{"file":"a.test.sh","neverRun":{"kind":"patterns","reason":"the pack'"'"'s tests.patterns do not match it"}},'\
'{"file":"lone.test.sh","neverRun":{"kind":"patterns","reason":"the pack'"'"'s tests.patterns do not match it"}},'\
'{"file":"other/o.test.mjs","neverRun":{"kind":"patterns","reason":"the test command (node --test tests) runs tests, which does not match it"}},'\
'{"file":"tests/bad.test.sh","neverRun":{"kind":"load","reason":"loading it fails: tests/bad.test.sh: line 1: syntax error near unexpected token `then'"'"'"}},'\
'{"file":"tests/fine.test.sh","neverRun":null},{"file":"tests/ran.test.sh","neverRun":null},{"file":"tests/skip.test.mjs","neverRun":{"kind":"skipped","reason":"it is skipped: describe.skip"}}]' ] \
    || fail "why each file never ran: $(jq -c '[.files[] | {file, neverRun}]' <<<"$got")"
  [ "$(jq -c '[.files[] | select(.waits != null) | {file, waits}]' <<<"$got")" = '[{"file":"tests/ran.test.sh","waits":[{"case":"one","kind":"polling","at":"tests/ran.test.sh:1","reason":"it polls"}]}]' ] \
    || fail "the waits are not the newest judge's: $(jq -c '[.files[] | {file, waits}]' <<<"$got")"
  jq -c 'map_values("kept: " + .)' "$ST/testactions/neverloads" > "$ST/nl" && mv "$ST/nl" "$ST/testactions/neverloads" || fail "the parse record: $(cat "$ST/testactions/neverloads" 2>&1)"
  got=$(tf_in neverwhy '["tests/bad.test.sh"]') && [ "$(jq -r '.["tests/bad.test.sh"].reason' <<<"$got")" = 'loading it fails: kept: tests/bad.test.sh: line 1: syntax error near unexpected token `then'"'"'' ] \
    || fail "a file whose content was parsed before is parsed again: $got"
}

# #349: no test file has a CPU budget. The pack still holds the old test.fileBudget of 5 and budgets of single files:
# a.test's 20, b.test's 2. A card's run times each file (testlist.sh slowtests()) and its test line (testlist.sh slowrec()) records each
# file's CPU and clock seconds, which the part reads, and holds no slow note. Bugs caught: a file over the old budget
# flagged on the test line, or in the part; a file's times not recorded. m.test, marked slow on purpose, keeps its
# mark in the part (a CPU test rule never files it: testrules.test.sh).
t_tfnobudget() {
  setup '[]'; tune '.test.fileBudget = 5 | .test.files = {"a.test": {budget: 20}, "b.test": {budget: 2}, "m.test": {slowOnPurpose: "it starts the whole loop"}}'
  mkdir -p "$R.testlog" && printf 'TESTRUN sec\t%s\t%s\t%s\n' a.test 11 10 b.test 4 3 c.test 7 6 m.test 60 50 > "$R.testlog/r.log"
  tf_card slowtests "$R" || fail "slowtests failed"
  [ ! -e "$R.slow" ] || fail "the run wrote a slow note: $(cat "$R.slow")"
  got=$(tf_card slowrec "$R")
  [ "$got" = '{"times":{"a.test":10,"b.test":3,"c.test":6,"m.test":50},"clocks":{"a.test":11,"b.test":4,"c.test":7,"m.test":60}}' ] || fail "the test line's times: $got"
  jq -c '{card: "c-1", issue: 1, step: "test", time: "2026-11-10T12:00:00Z", result: "pass"} + .' <<<"$got" >> "$ST/cards.jsonl"
  got=$(tf_in testspart 2026-11-09) || fail "testspart failed: $got"
  [ "$(jq -c '.files[] | select(.file == "a.test") | .lastRun' <<<"$got")" = '{"sec":11,"cpu":10,"clockPerCpu":1.1,"time":"2026-11-10T12:00:00Z","whole":false}' ] \
    || fail "a.test in the part: $(jq -c '.files[] | select(.file == "a.test")' <<<"$got")"
  [ "$(jq -c '[any(.files[]; has("budget") or has("over")), (.totals | has("overBudget")), (.files[] | select(.file == "m.test") | .slowOnPurpose)]' <<<"$got")" = '[false,false,"it starts the whole loop"]' ] \
    || fail "the part names a CPU budget, or lost m.test's mark: $got"
}

# The Board saves the test settings through these commands: each saves its value in main's pack, and the next snapshot
# shows it (its tests part's settings). c.test gets its mark and then has it cleared: it leaves the pack. Bug caught:
# a value written somewhere the snapshot does not read, or a clear that left the file's entry. No test file has a CPU
# budget (#349): the old budget commands (budget, file-budget, file-budget-clear) are usage errors and change nothing.
# The snapshot holds this part whole (testrules.test.sh reads it there), so the part is read here. Each setting is
# saved by testsettings(), the function `conveyor.sh test-settings` calls; one is saved through the command itself.
# A bad value is refused with why, and the pack is left byte for byte as it was. Bug caught: a mark with no reason
# (blank, or more than one line) saved, which the test rules (testrulespass()) then honour, hiding a slow file for
# no stated reason.
tf_refused() { # the refusals, each checked: in a shell with testsettings() loaded (tf_as test-settings)
  local a out
  for a in 'slow-issues yes' 'slow-mark gone.test x' 'slow-mark ../a.test x'; do
    # shellcheck disable=SC2086 # each is the command's words
    out=$(testsettings $a 2>&1) && fail "test-settings $a was taken"
    [[ $out == *"nothing changed"* ]] || fail "test-settings $a did not say why: $out"
  done
  for a in 'budget 12' 'file-budget a.test 20' 'file-budget-clear a.test'; do
    # shellcheck disable=SC2086 # each is the command's words
    testsettings $a > /dev/null 2>&1; [ $? = 2 ] || fail "the budget command test-settings $a was not a usage error"
  done
  for a in '' '   ' $'one\ntwo'; do
    out=$(testsettings slow-mark a.test "$a" 2>&1) && fail "the mark with the reason '$a' was taken"
    [[ $out == *"reason"* ]] || fail "the refused mark did not say why: $out"
  done
}
tf_saved() { # the settings saved: in a shell with testsettings() loaded (tf_as test-settings)
  local a
  for a in 'slow-issues true' 'slow-mark c.test x' 'slow-mark-clear c.test'; do
    # shellcheck disable=SC2086 # each is the command's words
    testsettings $a > /dev/null || fail "test-settings $a failed"
  done
}
t_tfsettings() {
  local before
  setup '[]'
  touch "$R/a.test" "$R/b.test" "$R/c.test" && git -C "$R" add a.test b.test c.test && git -C "$R" commit -qm tests || fail "main's tests"
  before=$(cat "$R/.conveyor/project.json")
  tf_as test-settings tf_refused || fail "a bad value was taken"
  loop test-settings slow-mark a.test > /dev/null 2>&1; [ $? = 2 ] || fail "a mark with no reason given was not a usage error"
  [ "$(cat "$R/.conveyor/project.json")" = "$before" ] || fail "a refused value changed the pack"
  tf_as test-settings tf_saved || fail "a setting was not saved"
  loop test-settings slow-mark b.test '  starts a loop of its own  ' || fail "the mark of b.test failed"
  got=$(tf_in testspart 2026-11-09 | jq -c '.settings | {slowIssues, files}')
  [ "$got" = '{"slowIssues":true,"files":{"b.test":{"slowOnPurpose":"starts a loop of its own"}}}' ] \
    || fail "the part's settings: $got"
}

# The Tests page shows what each Optimize did (#74). The Board filed #70, #71 and #72 for a.test (main has it) and #73
# for gone.test (main no longer has it). a.test ran at 10, 9, 4 and 3 CPU s; #70's card proved it faster (10 to 4) and
# landed between the 9 and the 4, so its median since is 3.5 over 2 runs; #71 has no card; #72's card is blocked; #73's
# card deleted gone.test and landed, its last review naming b.test and c.test on its COVERED-BY lines, and #74's was
# closed without landing. Bug caught: the part named one issue a file and no state, so the page could not show what an
# Optimize did, nor a file it removed; and a deleted file lost the tests that cover its cases.
t_tfoptimize() {
  setup '[]'
  touch "$R/a.test" && git -C "$R" add a.test && git -C "$R" commit -qm tests || fail "main's tests"
  tf_runs a.test 10 9 4 3
  mkdir -p "$ST/testactions" && jq -cn '[70, 71, 72, 74] | to_entries[] | {time: "2026-11-0\(.key + 1)T00:00:00Z", event: "filed", file: "a.test", issue: .value},
    {time: "2026-11-05T00:00:00Z", event: "filed", file: "gone.test", issue: 73}' > "$ST/testactions/filed.jsonl"
  jq -cn '{card: "c-70", issue: 70, step: "picked", time: "2026-11-10T11:00:00Z"},
    {card: "c-70", issue: 70, step: "bugproof", result: "ok", time: "2026-11-10T11:30:00Z", speed: {file: "a.test", before: 10, after: 4, fix: "sped up", into: []}},
    {card: "c-70", issue: 70, step: "landed", result: "ok", sha: "abc1234", time: "2026-11-10T12:01:30Z"},
    {card: "c-72", issue: 72, step: "picked", time: "2026-11-10T13:00:00Z"},
    {card: "c-72", issue: 72, step: "blocked", reason: "build: the file is not faster", time: "2026-11-10T13:30:00Z"},
    {card: "c-73", issue: 73, step: "bugproof", result: "ok", time: "2026-11-06T00:00:00Z", speed: {file: "gone.test", before: 6, after: null, fix: "deleted", into: []}},
    {card: "c-73", issue: 73, step: "review", result: "NO-GO", time: "2026-11-06T00:20:00Z", reason: "COVERED-BY: old.test: t_one\n[P1] x:1 no"},
    {card: "c-73", issue: 73, step: "review", result: "GO", time: "2026-11-06T00:30:00Z", reason: "COVERED-BY: b.test: t_one\nCOVERED-BY: c.test: t_two\nCOVERED-BY: b.test: t_three\nVERDICT: GO"},
    {card: "c-73", issue: 73, step: "landed", result: "ok", sha: "def5678", time: "2026-11-06T01:00:00Z"},
    {card: "c-74", issue: 74, step: "picked", time: "2026-11-10T14:00:00Z"},
    {card: "c-74", issue: 74, step: "closed", reason: "already done", time: "2026-11-10T14:10:00Z"}' >> "$ST/cards.jsonl"
  # a.test's mutation checks (#79): two done before #70 landed (12:01:30), one done after it and a failed one after
  # that; and the asked list, where a.test is second.
  mkdir -p "$ST/testactions/mutations" && printf '%s\n' s.test a.test > "$ST/testactions/mutations/asked"
  jq -cn '["09T00:00", "done", 1], ["10T12:00", "done", 2], ["10T12:30", "done", 4], ["10T13:00", "failed", 0] | {id: .[0], file: "a.test",
      at: "2026-11-\(.[0]):00Z", state: .[1], killed: .[2], mutants: [range(4)], survived: [], tried: 4}' \
    | while read -r l; do printf '%s\n' "$l" > "$ST/testactions/mutations/$(jq -r '.id | gsub(":"; "")' <<<"$l").json"; done
  got=$(tf_in testspart 2026-11-09) || fail "testspart failed: $got"
  # Bug caught: an Optimize history that could not show the mutants caught before and after it landed, or a row that
  # could not show its place in the queue the Board's Mutation check puts it in.
  [ "$(jq -c '.files[] | select(.file == "a.test") | [.mutationPlace, (.optimize[] | select(.issue == 70 or .issue == 71) | [.issue, .mutantsBefore, .mutantsAfter])]' <<<"$got")" \
    = '[2,[71,null,null],[70,{"at":"2026-11-10T12:00:00Z","killed":2,"of":4},{"at":"2026-11-10T12:30:00Z","killed":4,"of":4}]]' ] \
    || fail "a.test's place in the asked list, or its mutants before and after #70: $(jq -c '.files[] | select(.file == "a.test") | [.mutationPlace, .optimize]' <<<"$got")"
  [ "$(jq -c '.files[] | select(.file == "a.test") | [.removed, (.optimize[] | [.issue, .state, .reason, .sha, .fix, .before, .after, .since, .sinceRuns])]' <<<"$got")" \
    = '[false,[74,"closed",null,null,null,null,null,null,0],[72,"blocked","build: the file is not faster",null,null,null,null,null,0],[71,"open",null,null,null,null,null,null,0],[70,"landed",null,"abc1234","sped up",10,4,3.5,2]]' ] \
    || fail "a.test's Optimize issues: $(jq -c '.files[] | select(.file == "a.test") | .optimize' <<<"$got")"
  [ "$(jq -c '[(.files[] | select(.file == "gone.test") | [.removed, .optimize[0].fix, .optimize[0].landed, .optimize[0].into]), .totals.files]' <<<"$got")" \
    = '[[true,"deleted","2026-11-06T01:00:00Z",["b.test","c.test"]],1]' ] \
    || fail "gone.test, deleted: $(jq -c '[(.files[] | select(.file == "gone.test")), .totals]' <<<"$got")"
}

# The Tests page's Caught column (#75): a test file that failed on a card whose landed commit left it as it was caught
# a bug (the fix went into the code); one whose landed commit changed it was changed to pass. f.test failed on c-1
# (landed: it changed code.sh alone), on c-2 (landed: it changed f.test), on c-3 (blocked, never landed) and on c-4
# (its landed commit is not in main's checkout); it ran on two cards that passed too: 6 runs on record. Bug caught: a
# page that showed no test file catching anything, or counted a test edited to pass, or an unlanded card, as a catch.
# The cheap check for hollow tests (#77): in a .test.ts of main, a case with no assertion and a case whose only
# assertion is toBeDefined are hollow; a case with a real expect(x).toBe(2) is not, and neither is a one-line case
# whose assertion follows its name on the same line, or a case that calls a variable named before (before.click())
# ahead of its assertion. Bugs it catches: a case that passes without proving anything
# showed on the Tests page as any other; a case that asserts was flagged.
t_tfcaught() {
  setup '[]'
  printf '%s\n' "import { describe, it, expect } from 'vitest';" "describe('sum', () => {" "  it('loads', async () => {" '    await load();' '  });' \
    "  it('has a value', () => {" '    expect(get()).toBeDefined();' '  });' "  it(\"adds\", () => {" '    before.click();' '    const x = add(1, 1);' '    expect(x).toBe(2);' '  });' \
    "  test('one line', () => expect(add(0, 1)).toBe(1));" '});' > "$R/sum.test.ts"
  touch "$R/f.test" "$R/code.sh" && git -C "$R" add f.test code.sh sum.test.ts && git -C "$R" commit -qm base || fail "main's files"
  echo fix > "$R/code.sh" && git -C "$R" commit -qam "fix the code" && s1=$(git -C "$R" rev-parse HEAD) || fail "the code fix"
  echo edit > "$R/f.test" && git -C "$R" commit -qam "edit the test" && s2=$(git -C "$R" rev-parse HEAD) || fail "the test edit"
  tf_runs f.test 1 1
  jq -cn --arg s1 "$s1" --arg s2 "$s2" '["c-1", "c-2", "c-3", "c-4"] | to_entries[] | .value as $c
      | {card: $c, issue: (.key + 1), step: "test", time: "2026-11-11T1\(.key):00:00Z", result: "fail", times: {"f.test": 1},
         failures: {of: 1, files: [{file: "f.test", cases: []}], timeout: null}},
        ({card: $c, issue: (.key + 1), time: "2026-11-11T1\(.key):30:00Z"} + ({"c-1": {step: "landed", result: "ok", sha: $s1},
          "c-2": {step: "landed", result: "ok", sha: $s2}, "c-3": {step: "blocked", reason: "no"},
          "c-4": {step: "landed", result: "ok", sha: ("0" * 40)}}[$c]))' >> "$ST/cards.jsonl"
  got=$(tf_in testspart 2026-11-09) || fail "testspart failed: $got"
  [ "$(jq -c '.files[] | select(.file == "f.test") | {caught, changedToPass, runsOnRecord, failedSteps}' <<<"$got")" = '{"caught":1,"changedToPass":1,"runsOnRecord":6,"failedSteps":4}' ] \
    || fail "f.test's catches: $(jq -c '.files[] | select(.file == "f.test")' <<<"$got")"
  [ "$(jq -c '.files[] | select(.file == "sum.test.ts") | .hollow | map([.case, .kind])' <<<"$got")" = '[["loads","no-assert"],["has a value","defined-only"]]' ] \
    || fail "the hollow cases of sum.test.ts: $(jq -c '.files[] | select(.file == "sum.test.ts") | .hollow' <<<"$got")"
}

# A card that weakens a test file main had, to get green, shows on the Tests page (#76). One card, landed by land():
# in a.test.mjs it removes one expect( line, changes toBe(3) to toBe(4), adds it.skip and raises a timeout; in
# s.test.sh it deletes a case (t_two, with its assertion) and raises the file's timeout; it edits a.test.rb, a kind
# the table does not read (still listed, with no counts); it changes true to false in bool.test.mjs, the message alone in msg.test.mjs and the
# expected value on its own line in multi.test.mjs; in re.test.mjs it changes 7 to 8 in a regular expression with a
# comma and removes the assertion after one with an unclosed \( in its regular expression; it deletes gone.test.sh;
# and it adds new.test.mjs. Bug caught: a landed line with no testedits, a count read wrong (a changed assertion taken
# for a removed one, a boolean, multiline or regular expression expected value missed, a regular expression's comma
# or bracket read as code, a changed message taken for a changed expected value, a skip or a deleted case
# missed), a deleted test file left out, a new test file counted as an edit of one main had, or an unread kind left
# out; and a Tests part with no list of them, or one that grows with every card that lands.
# #217: runs holds a file's newest five runs alone, so the sixth took the first off the Board's Timeline, which lists
# every event of a file: `conveyor.sh history test <file>` (testolder()) gives the runs before them, newest first, as
# runs has them, and those of that file alone.
t_tfolderruns() {
  setup '[]'; tf_runs e.test 1 2 3 4 5 6 7; tf_runs other.test 9 9 9 9 9 9 9
  got=$(tf_in testspart 2026-11-09 | jq -c '.files[] | select(.file == "e.test") | [.runs[].cpu]')
  [ "$got" = '[7,6,5,4,3]' ] || fail "e.test's runs: $got"
  got=$(loop history test e.test | jq -c '[.file, (.olderRuns | map([.cpu, .card])), .olderEdits]') || fail "history test exited non-zero"
  [ "$got" = '["e.test",[[2,"c-e.test-1"],[1,"c-e.test-0"]],[]]' ] || fail "e.test's older runs: $got"
}

# #251: the Tests part carried every older run (olderRuns) and test edit (olderEdits) of each file, so data.js grew
# with each test run until /units, which caps it, stopped reading it. Bug caught: a part that grows with the runs on
# record: one built from 80 runs of a file is the size of one built from 40 (the second 40 are the first again, so
# the newest five are of the same size).
t_tfpartsize() {
  local one two
  setup '[]'
  # shellcheck disable=SC2046 # 40 words, one a run
  tf_runs e.test $(printf '3 %.0s' {1..40})
  one=$(tf_in testspart 2026-11-09) || fail "the part of 40 runs"
  # shellcheck disable=SC2046
  tf_runs e.test $(printf '3 %.0s' {1..40})
  two=$(tf_in testspart 2026-11-09) || fail "the part of 80 runs"
  [ "$(jq -c '.files[] | select(.file == "e.test") | [.runsOnRecord, (.runs | length), has("olderRuns"), has("olderEdits")]' <<<"$two")" = '[80,5,false,false]' ] \
    || fail "the part of 80 runs: $(jq -c '.files[] | select(.file == "e.test")' <<<"$two" | cut -c1-600)"
  [ "${#two}" = "${#one}" ] || fail "the part grew with the runs on record: ${#one} bytes for 40 runs, ${#two} for 80"
}

t_tfedits() {
  setup '[]'
  printf '%s\n' "it('a', () => {" '  expect(f()).toBe(3);' '  expect(g()).toBe(1);' '});' "it('b', () => {" '  expect(h()).toBe(2);' '}, { timeout: 1000 });' > "$R/a.test.mjs"
  printf '%s\n' "test('b', () => { assert.equal(on(), true, 'it is on'); });" > "$R/bool.test.mjs"
  printf '%s\n' "test('m', () => { assert.equal(n(), 2, 'two'); });" > "$R/msg.test.mjs"
  printf '%s\n' "test('l', () => {" '  assert.deepEqual(list(),' '    [1, 2]);' '});' > "$R/multi.test.mjs"
  printf '%s\n' "test('r', () => {" '  assert.match(cost(), /no price \(1 today, 2 in 7 days\)/);' '  assert.match(open(), /a \( b/);' '  assert.equal(n(), 1);' '});' > "$R/re.test.mjs"
  printf '%s\n' 't_gone() {' '  [ "$(z)" = 3 ] || fail "z"' '}' > "$R/gone.test.sh"
  printf '%s\n' '# timeout: 120' 't_one() {' '  [ "$(x)" = 1 ] || fail "x"' '}' 't_two() {' '  [ "$(y)" = 2 ] || fail "y"' '}' > "$R/s.test.sh"
  echo x > "$R/a.test.rb"
  git -C "$R" add a.test.mjs s.test.sh a.test.rb bool.test.mjs msg.test.mjs multi.test.mjs re.test.mjs gone.test.sh && git -C "$R" commit -qm tests || fail "main's test files"
  W=$T/$CASE/cards/c-1; git -C "$R" worktree add -q --detach "$W" || fail "the card's worktree"
  printf '%s\n' "it('a', () => {" '  expect(f()).toBe(4);' '});' "it.skip('b', () => {" '  expect(h()).toBe(2);' '}, { timeout: 5000 });' > "$W/a.test.mjs"
  printf '%s\n' '# timeout: 300' 't_one() {' '  [ "$(x)" = 1 ] || fail "x"' '}' > "$W/s.test.sh"
  echo y > "$W/a.test.rb"; echo "it('n', () => { expect(1).toBe(1); });" > "$W/new.test.mjs"
  printf '%s\n' "test('b', () => { assert.equal(on(), false, 'it is on'); });" > "$W/bool.test.mjs"
  printf '%s\n' "test('m', () => { assert.equal(n(), 2, 'it is two'); });" > "$W/msg.test.mjs"
  printf '%s\n' "test('l', () => {" '  assert.deepEqual(list(),' '    [1, 3]);' '});' > "$W/multi.test.mjs"
  printf '%s\n' "test('r', () => {" '  assert.match(cost(), /no price \(1 today, 2 in 8 days\)/);' '  assert.match(open(), /a \( b/);' '});' > "$W/re.test.mjs"
  git -C "$W" rm -q gone.test.sh || fail "gone.test.sh not deleted"
  git -C "$W" add -A && tf_card eval 'names && land c-1 7 "$W" "weaken the tests"' || fail "the card did not land"
  got=$(st 'select(.step == "landed") | .testedits | map([.file, .read, .removedAsserts, .changedExpected, .skipsAdded, .timeoutsRaised, .casesDeleted])' | jq -c .)
  [ "$got" = '[["a.test.mjs",true,1,1,1,1,0],["a.test.rb",false,null,null,null,null,null],["bool.test.mjs",true,0,1,0,0,0],["gone.test.sh",true,1,0,0,0,1],["msg.test.mjs",true,0,0,0,0,0],["multi.test.mjs",true,0,1,0,0,0],["re.test.mjs",true,1,1,0,0,0],["s.test.sh",true,1,0,0,1,1]]' ] \
    || fail "the landed line's testedits: $got"
  loop check >/dev/null || fail "the landed line with testedits does not check"
  # Five later cards edit a.test.mjs: the part's edits keep a file's newest five alone (the list stays small).
  for i in 2 3 4 5 6; do
    jq -cn --argjson i "$i" '{card: "c-\($i)", issue: $i, step: "landed", time: "2099-01-01T0\($i):00:00Z", tokens: {claude: 0, codex: 0}, result: "ok", sha: "s", reason: "",
      product: false, testedits: [{file: "a.test.mjs", read: true, removedAsserts: 0, changedExpected: 0, skipsAdded: 0, timeoutsRaised: 0, casesDeleted: 0}]}' >> "$ST/cards.jsonl"
  done
  part=$(tf_in testspart 2026-11-09)
  got=$(jq -c '.edits | map([.card, .issue, .file])' <<<"$part")
  [ "$got" = '[["c-6",6,"a.test.mjs"],["c-5",5,"a.test.mjs"],["c-4",4,"a.test.mjs"],["c-3",3,"a.test.mjs"],["c-2",2,"a.test.mjs"],["c-1",7,"a.test.rb"],["c-1",7,"bool.test.mjs"],["c-1",7,"gone.test.sh"],["c-1",7,"msg.test.mjs"],["c-1",7,"multi.test.mjs"],["c-1",7,"re.test.mjs"],["c-1",7,"s.test.sh"]]' ] \
    || fail "the Tests part's edits, newest first, a file's newest five: $got"
  # #217: the sixth edit pushed the first out of edits, and so off the Board's Timeline, which lists every event of a
  # file: testolder() gives the edits of a file before its newest five, newest first.
  got=$(for f in a.test.mjs bool.test.mjs; do tf_as history testolder "$f"; done | jq -sc 'map([.file, (.olderEdits | map([.card, .issue, .removedAsserts]))])')
  [ "$got" = '[["a.test.mjs",[["c-1",7,1]]],["bool.test.mjs",[]]]' ] || fail "each file's older edits: $got"
}

# Bug it catches (#780): a test file that checks through a proxy (it starts another test file or the suite runner, or
# polls a real process) looked like any other on the Tests page. runs.test.sh starts plain.test.sh by bash, by its path
# under timeout inside "$( )", the pack's test.command with a variable set before it, the same on the line a backslash
# goes on to (line 6), plain.test.sh after a quoted value with a space, and node --test on a line a backslash joins to
# one with quotes inside "$( )" (line 9); polls.test.sh calls wait_until, the pack's
# other poll helper (poll_for) after if !, and wait_until in a function defined on its line, with a " // " in its
# quoted argument that is no comment. Each is marked with the line its command is on, and the comment
# beside it, on the line or right above, as its why. plain.test.sh is not marked: it names a test file only as text
# (echo, cat, a command quoted as an argument), calls a helper whose name starts with wait_until and defines poll_for;
# a comment that names wait_until is not read.
# Bug it catches (#824): plain.test.sh also calls .conveyor/test-changed.sh (here the pack's test.full) with --check,
# --map, --checks, --funcs and --parts, which exit before they run a test file, and is still not marked; runs.test.sh starts it with --file (line 10).
t_tfproxy() {
  setup '[]'; tune '.test.command = "bash run-all.sh" | .test.full = "bash .conveyor/test-changed.sh" | .test.pollHelpers = ["wait_until", "poll_for"]'
  mkdir -p "$R/tests"
  printf '%s\n' '# a whole run of it is what the exit status shows' 'bash tests/plain.test.sh' \
    'x="$(timeout 30 ./tests/plain.test.sh)" || exit 1' 'CONVEYOR_X=1 bash run-all.sh --quick' \
    "(cd t && A='a b' \\" '  exec timeout --kill-after=30 60 bash run-all.sh --quick) > out &' \
    "B=1 C='p q' timeout 9 bash \"\$T/plain.test.sh\" > o" "out=\$(eval \"\$(grep '^\\. \"x' \"f\")\" \\" \
    '  && node --test t/a.test.js)' 'bash .conveyor/test-changed.sh --file tests/plain.test.sh' > "$R/tests/runs.test.sh"
  printf '%s\n' '# wait_until in a comment is no poll' 'start &' "wait_until '[ -e done ]' || fail 'not done' # the server writes done once it is up" \
    'if ! poll_for x; then exit 1; fi' "up() { wait_until \"jq -e '.of // \\\"\\\"' f\" 'cat log'; }" > "$R/tests/polls.test.sh"
  printf '%s\n' 'echo "bash tests/runs.test.sh"' 'cat tests/runs.test.sh' 'wait_until_ready x' 'poll_for() { :; }' \
    "check 'cd t && bash all.test.sh' \"x; wait_until y\"" '(cd t && bash .conveyor/test-changed.sh --check) | grep -q map' \
    'bash .conveyor/test-changed.sh --map > m' 'bash .conveyor/test-changed.sh --checks' \
    'bash .conveyor/test-changed.sh --funcs lib/a.sh; ./.conveyor/test-changed.sh --parts t/a.test.sh' > "$R/tests/plain.test.sh"
  git -C "$R" add -A && git -C "$R" commit -qm 'tests' || fail "main's files"
  got=$(tf_in testspart 2026-11-09 | jq -c '[.files[] | select(.file | startswith("tests/")) | {file, proxy}]') || fail "testspart failed: $got"
  [ "$got" = '[{"file":"tests/plain.test.sh","proxy":[]},'\
'{"file":"tests/polls.test.sh","proxy":[{"line":3,"kind":"polls","text":"wait_until '"'"'[ -e done ]'"'"' || fail '"'"'not done'"'"'","why":"the server writes done once it is up"},'\
'{"line":4,"kind":"polls","text":"if ! poll_for x; then exit 1; fi","why":null},'\
'{"line":5,"kind":"polls","text":"up() { wait_until \"jq -e '"'"'.of // \\\"\\\"'"'"' f\" '"'"'cat log'"'"'; }","why":null}]},'\
'{"file":"tests/runs.test.sh","proxy":[{"line":2,"kind":"runs","text":"bash tests/plain.test.sh","why":"a whole run of it is what the exit status shows"},'\
'{"line":3,"kind":"runs","text":"x=\"$(timeout 30 ./tests/plain.test.sh)\" || exit 1","why":null},'\
'{"line":4,"kind":"runs","text":"CONVEYOR_X=1 bash run-all.sh --quick","why":null},'\
'{"line":6,"kind":"runs","text":"exec timeout --kill-after=30 60 bash run-all.sh --quick) > out &","why":null},'\
'{"line":7,"kind":"runs","text":"B=1 C='"'"'p q'"'"' timeout 9 bash \"$T/plain.test.sh\" > o","why":null},'\
'{"line":9,"kind":"runs","text":"&& node --test t/a.test.js)","why":null},'\
'{"line":10,"kind":"runs","text":"bash .conveyor/test-changed.sh --file tests/plain.test.sh","why":null}]}]' ] || fail "the proxy checks: $got"
}
