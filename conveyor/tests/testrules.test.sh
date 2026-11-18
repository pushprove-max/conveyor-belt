#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 300
# Engine cases: the test rules (lib/testrules.sh), which replace the "Slow test" filing (#519: it filed 37 issues in one
# burst, with one fixed limit, no cap and no preview). Each case calls the engine's functions, or `conveyor.sh
# testrules`, on card test lines written as the loop writes them; the gh stub (lib.sh) stands in for GitHub: what is
# filed is in $STUB/filed, an issue's state in $STUB/state.<n> and its closing time in $STUB/closedAt.<n>.
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"

# Now, for the engine (CONVEYOR_NOW): 2026-11-10 12:00 UTC; the day is UTC's.
TR_NOW=1794312000
# An engine function called in a case's main checkout, at TR_NOW or at <seconds> after it (tr_at).
tr_eng() { tr_at 0 "$@"; }
tr_at() { # <seconds after TR_NOW> <function> [<argument>...]
  ( export CONVEYOR_MAIN=$R CONVEYOR_CARDS=$T/$CASE/cards CONVEYOR_NOW=$((TR_NOW + $1)) TZ=UTC; shift
    . "$SRC/conveyor.sh" state-dir > /dev/null && eval "$(grep '^\. "\$HERE/lib/' "$SRC/commands/testrules.sh")" && "$@" )
}
# Card c0-<n>'s test line on day 2026-11-0<n>: its CPU seconds by file, and with clocks its clock seconds by file. A
# failed line (tr_fail) names its failed files.
tr_line() { # <n> <times json> [clocks json]
  jq -cn --argjson n "$1" --argjson x "$2" --argjson k "${3:-null}" '{card: "c0-\($n)", issue: $n, step: "test", time: "2026-11-0\($n)T00:00:00Z",
    tokens: {claude: 0, codex: 0}, result: "pass", sha: "", reason: "", times: $x} + if $k then {clocks: $k} else {} end' >> "$ST/cards.jsonl"
}
tr_fail() { # <n> <file>...
  local n=$1; shift
  jq -cn --argjson n "$n" '{card: "c0-\($n)", issue: $n, step: "test", time: "2026-11-0\($n)T00:00:00Z", tokens: {claude: 0, codex: 0},
    result: "fail", sha: "", reason: "exit 1", failures: {files: ($ARGS.positional | map({file: ., cases: []}))}}' --args "$@" >> "$ST/cards.jsonl"
}
# The pack's test.rules: the switch on, the guards a filter sets, and one usual rule "over": over 1.5 times its usual
# (the median of its runs before) in 2 card test runs in a row, with 3 on record.
TR_OVER='{"name": "over", "on": true, "measure": "usual", "limit": 1.5, "runs": 2, "minRuns": 3}'
tr_rules() { # [jq filter of test.rules]
  tune --argjson r "$TR_OVER" ".test.rules = ({on: true, list: [\$r]} | ${1:-.})"
}
# Card #1's test line with each of <files> at 2 CPU s: their usual before the runs of #2 and #3.
tr_base() { jq -cn '$ARGS.positional | map({key: ., value: 2}) | from_entries' --args "$@" | { read -r x; tr_line 1 "$x"; }; }
# Five files over their usual in cards #2 and #3: a pass that files them all would file five.
tr_five() { tr_base a.test b.test c.test d.test e.test; tr_line 2 '{"a.test": 9, "b.test": 9, "c.test": 9, "d.test": 9, "e.test": 9}'; tr_line 3 '{"a.test": 9, "b.test": 9, "c.test": 9, "d.test": 9, "e.test": 9}'; }
# An issue the rules filed for <file>, in the log: as of 2026-11-01.
tr_filed() { # <file> <issue>
  jq -cn --arg f "$1" --argjson n "$2" '{time: "2026-11-01T00:00:00Z", event: "filed", rule: "over", measure: "usual", file: $f, values: {}, cards: [], issue: $n}' >> "$ST/testrules.jsonl"
}
filedtitles() { jq -r .title "$STUB/filed" 2>/dev/null | sort | tr '\n' ' '; }

# The owner, 2026-11-14: one switch for all rules, off by default; off files nothing. Bug it catches: a rule that is on
# filed with the switch off, or a pack that names no switch had it on. a.test is over its usual in two card runs in a
# row, the rule "over" is on, and the pack names no test.rules.on: nothing is filed, nothing logged, and the list of
# the pass says the switch stopped it.
t_rulesoff() {
  setup '[]'; tr_rules 'del(.on)'
  tr_base a.test; tr_line 2 '{"a.test": 10}'; tr_line 3 '{"a.test": 11}'
  [ "$(tr_eng testrulesettings | jq -c '.on')" = false ] || fail "a pack with no test.rules.on has the switch on: $(tr_eng testrulesettings)"
  tr_eng testrulespass 2> /dev/null || fail "the pass failed"
  [ ! -s "$STUB/filed" ] || fail "the switch off still filed: $(cat "$STUB/filed")"
  [ ! -s "$ST/testrules.jsonl" ] || fail "the switch off still logged: $(cat "$ST/testrules.jsonl")"
  [ "$(jq -c '[.on, (.matches | map([.file, .guard]))]' "$ST/testrules.json")" = '[false,[["a.test","off"]]]' ] \
    || fail "the list does not say the switch stopped a.test: $(cat "$ST/testrules.json")"
}

# A file that meets a rule's limit in its runs in a row gets one issue; one run short gets none. Bug it catches (#459):
# one slow run, the machine's load, filed an issue. a.test is over in #2 and #3; b.test only in #3. The issue names
# the rule, the measured values and the cards, and has no Done-when line (no run count or time target). The log has
# one line for it.
t_rulesrun() {
  setup '[]'; tr_rules
  tr_base a.test b.test; tr_line 2 '{"a.test": 10, "b.test": 2}'; tr_line 3 '{"a.test": 11, "b.test": 12}'
  tr_eng testrulespass 2> /dev/null || fail "the pass failed"
  [ "$(filedtitles)" = "Test rule over: a.test " ] || fail "not one issue, for a.test alone: $(filedtitles)"
  [ "$(jq -c '[.labels[].name]' "$STUB/filed")" = '["bug","P2"]' ] || fail "the labels: $(jq -c .labels "$STUB/filed")"
  jq -r .body "$STUB/filed" | grep -qF 'The test rule `over` (usual) matched the test file `a.test`: 2 card test runs in a row at 10, 11 CPU s, each over 1.5 times its usual of 2 CPU s.' \
    || fail "the body does not name the rule and the values: $(jq -r .body "$STUB/filed")"
  jq -r .body "$STUB/filed" | grep -qF 'The cards of those figures: c0-2, c0-3.' || fail "the body does not name the cards: $(jq -r .body "$STUB/filed")"
  ! jq -r .body "$STUB/filed" | grep -qi 'done when' || fail "the issue has a Done-when line: $(jq -r .body "$STUB/filed")"
  [ "$(jq -c '[.event, .rule, .file, .values, .cards, .issue, (.time | length > 0)]' "$ST/testrules.jsonl")" = '["filed","over","a.test",{"cpu":[10,11],"usual":2},["c0-2","c0-3"],100101,true]' ] \
    || fail "the log does not have one line for the issue filed: $(cat "$ST/testrules.jsonl")"
}

# Each measure matches a file that meets its limit and not one that does not (testrulesmatches(), the rules' order):
# budget (#349): no test file has a CPU budget, so a rule of it matches nothing, though a.test ran at 10 and 11 CPU s,
# over the old 8 CPU s budget of test.fileBudget, which the pack still holds; usual: u1.test at 4 after three runs at 2 (limit 1.5 times
# its usual), u2.test at 2 then 4; clock: k1.test 12 s for 3 CPU s (over 2 times), k2.test 4 s for 1 CPU s but under
# the 5 s minClock; flaky: f1.test's case kept off twice in the last 7 days, f2.test's once in them and once 10 days
# before; failed: x1.test failed in two test steps in the last 7 days, x2.test in one. A rule that is off matches
# nothing.
t_rulesmeasures() {
  setup '[]'
  tune '.test.fileBudget = 8 | .test.rules = {list: [{name: "over", on: true, measure: "budget", limit: 1, runs: 2, minRuns: 2},
    {name: "usual", on: true, measure: "usual", limit: 1.5, runs: 2, minRuns: 4},
    {name: "clock", on: true, measure: "clock", limit: 2, runs: 1, minRuns: 1, minClock: 5},
    {name: "flaky", on: true, measure: "flaky", limit: 2, runs: 1, minRuns: 0, days: 7},
    {name: "failed", on: true, measure: "failed", limit: 2, runs: 1, minRuns: 0, days: 7},
    {name: "off", on: false, measure: "clock", limit: 0, runs: 1, minRuns: 0}]}'
  tr_line 1 '{"a.test": 10, "b.test": 7, "u1.test": 2, "u2.test": 2}'; tr_line 2 '{"a.test": 11, "b.test": 12, "u1.test": 2, "u2.test": 2}'
  tr_line 3 '{"u1.test": 2, "u2.test": 2}'; tr_line 4 '{"u1.test": 4, "u2.test": 2}'
  tr_line 5 '{"u1.test": 4, "u2.test": 4, "k1.test": 3, "k2.test": 1}' '{"u1.test": 4, "u2.test": 4, "k1.test": 12, "k2.test": 4}'
  tr_fail 6 x1.test x2.test; tr_fail 7 x1.test
  jq -cn '{entries: [{case: "f1.test: one", source: "c0-3", card: "c0-3", time: "2026-11-08T00:00:00Z"}, {case: "f1.test: one", source: "c0-4", card: "c0-4", time: "2026-11-09T00:00:00Z"},
    {case: "f2.test: two", source: "c0-3", card: "c0-3", time: "2026-10-31T00:00:00Z"}, {case: "f2.test: two", source: "c0-4", card: "c0-4", time: "2026-11-09T00:00:00Z"}], filed: []}' > "$ST/flaky.json"
  got=$(tr_eng testrulesmatches "$TR_NOW" "$(tr_eng testrulesettings)" | jq -c 'map([.rule, .file, .values])') || fail "the matches could not be read"
  [ "$got" = '[["usual","u1.test",{"cpu":[4,4],"usual":2}],["clock","k1.test",{"sec":[12],"cpu":[3]}],["flaky","f1.test",{"count":2,"days":7}],["failed","x1.test",{"count":2,"days":7}]]' ] \
    || fail "each measure does not match the file that meets it, and it alone: $got"
}

# The guards of one file, and the log. Bug it catches: a file got a second issue while one filed for it was open, or
# right after one closed, or when GitHub did not say its state; or a CPU rule filed a file marked slow on purpose. Each
# file is over its usual in #2 and #3: o.test's issue #201 is open; q.test's #202 closed 2 days ago (quietDays 14);
# u.test's #203 cannot be read; c.test's #204 closed 30 days ago; p.test is marked slow on purpose. Only c.test is
# filed, and the log has one line for it and one for each match a guard stopped, with the guard.
t_rulesguards() {
  setup '[]'; tr_rules; tune '.test.files = {"p.test": {slowOnPurpose: "runs the loop end to end"}}'
  tr_base c.test o.test p.test q.test u.test
  tr_line 2 '{"c.test": 9, "o.test": 9, "p.test": 9, "q.test": 9, "u.test": 9}'; tr_line 3 '{"c.test": 9, "o.test": 9, "p.test": 9, "q.test": 9, "u.test": 9}'
  tr_filed o.test 201; tr_filed q.test 202; tr_filed u.test 203; tr_filed c.test 204
  echo OPEN > "$STUB/state.201"; echo 2026-11-08T12:00:00Z > "$STUB/closedAt.202"; echo UNKNOWN > "$STUB/state.203"; echo 2026-10-11T12:00:00Z > "$STUB/closedAt.204"
  tr_eng testrulespass 2> /dev/null || fail "the pass failed"
  [ "$(filedtitles)" = "Test rule over: c.test " ] || fail "not one issue, for c.test alone: $(filedtitles)"
  got=$(tail -n +5 "$ST/testrules.jsonl" | jq -sc 'map([.event, .file, (.issue // .guard)])')
  [ "$got" = '[["filed","c.test",100101],["stopped","o.test","open"],["stopped","p.test","slowOnPurpose"],["stopped","q.test","quietDays"],["stopped","u.test","open"]]' ] \
    || fail "the log does not have one line for the issue filed and each match stopped: $got"
  tail -n 1 "$ST/testrules.jsonl" | jq -e '.why == "the state of #203, filed for the file, could not be read"' > /dev/null || fail "the unread state is not said: $(tail -n 1 "$ST/testrules.jsonl")"
}

# The cap of a day. Bug it catches (#519: 37 issues in one burst): a pass filed every match. With the burst guard off,
# a cap of 3 and five files over their usual: 3 are filed and 2 wait (perDay); the next day's pass, with the 3 open,
# files the 2.
t_rulescap() {
  setup '[]'; tr_rules '.burst = false | .perDay = 3'; tr_five
  tr_eng testrulespass 2> /dev/null || fail "the first pass failed"
  [ "$(filedtitles)" = "Test rule over: a.test Test rule over: b.test Test rule over: c.test " ] || fail "the first day did not file 3: $(filedtitles)"
  [ "$(jq -c '[.matches[] | select(.result == "stopped") | [.file, .guard]]' "$ST/testrules.json")" = '[["d.test","perDay"],["e.test","perDay"]]' ] \
    || fail "the 2 past the cap do not wait for the cap: $(cat "$ST/testrules.json")"
  echo OPEN > "$STUB/state"
  tr_at 86400 testrulespass 2> /dev/null || fail "the next day's pass failed"
  [ "$(wc -l < "$STUB/filed")" = 5 ] && [ "$(jq -r .title "$STUB/filed" | tail -n 2 | tr '\n' ' ')" = "Test rule over: d.test Test rule over: e.test " ] \
    || fail "the next day's pass did not file the 2 that waited: $(filedtitles)"
}

# The burst guard (on by default). Bug it catches (#519): one pass that matched 37 files filed 37 issues. With a cap of
# 3 and five matches, the pass files none, logs each as stopped by it, and the snapshot has one line in Needs you, and
# the pass's list.
t_rulesburst() {
  setup '[]'; tr_rules '.perDay = 3'; tr_five
  tr_eng testrulespass 2> /dev/null || fail "the pass failed"
  [ ! -s "$STUB/filed" ] || fail "a pass over the cap filed: $(filedtitles)"
  [ "$(jq -sc 'map(.guard) | unique' "$ST/testrules.jsonl")" = '["burst"]' ] && [ "$(wc -l < "$ST/testrules.jsonl")" = 5 ] || fail "the log: $(cat "$ST/testrules.jsonl")"
  # The log too, newest first, for the Board's Tests page (#521).
  got=$(CONVEYOR_NOW=$TR_NOW loop snapshot | jq -c '[.needsYou.testRules, (.tests.rules.last.matches | map([.file, .guard])), (.tests.rules.log | map(.file))]')
  [ "$got" = '[{"time":"2026-11-10T12:00:00Z","matched":5,"cap":3},[["a.test","burst"],["b.test","burst"],["c.test","burst"],["d.test","burst"],["e.test","burst"]],["e.test","d.test","c.test","b.test","a.test"]]' ] \
    || fail "the snapshot does not hold one Needs you line, the list and the log: $got"
}

# The preview lists each match with its result and files nothing, the switch on or off. Bug it catches: a preview that
# filed, or wrote the log, would be no preview. a.test would be filed; o.test's issue #201 is open.
t_rulespreview() {
  setup '[]'; tr_rules; tr_base a.test o.test; tr_line 2 '{"a.test": 10, "o.test": 9}'; tr_line 3 '{"a.test": 11, "o.test": 9}'; tr_filed o.test 201; echo OPEN > "$STUB/state.201"
  got=$(loop testrules preview) || fail "the preview failed: $got"
  [ "$got" = 'over: a.test: 2 card test runs in a row at 10, 11 CPU s, each over 1.5 times its usual of 2 CPU s: would file
over: o.test: 2 card test runs in a row at 9, 9 CPU s, each over 1.5 times its usual of 2 CPU s: stopped by open: #201, filed for the file, is open' ] \
    || fail "the preview does not list each match with its result: $got"
  got=$(tr_eng eval 'testrules off && testrules preview') || fail "the preview with the switch off failed: $got"
  [ "$(cut -d: -f2,4- <<<"$got" | tr '\n' '|')" = ' a.test: stopped by off: the switch is off| o.test: stopped by off: the switch is off|' ] \
    || fail "the preview with the switch off: $got"
  [ ! -s "$STUB/filed" ] && [ "$(wc -l < "$ST/testrules.jsonl")" = 1 ] && [ ! -e "$ST/testrules.json" ] || fail "the preview filed or wrote: $(ls "$ST")"
}

# The commands that set the rules check each value and save only a good one. Bug it catches: a bad value saved to the
# pack, which then failed its check and held every command that reads it.
tr_good() { testrules add over usual 1 2 2 && testrules set over on true && testrules on && testrules guard perDay 2 && testrules guard burst false && testrules add flaky flaky 2 1 0 7; }
tr_bad() { # each refused, and the pack as it was
  local n=0; cp "$PACK" "$STUB/pack.was"
  testrules guard perDay 0 || n=$((n + 1)); testrules add over usual 1 2 2 || n=$((n + 1)); testrules add x usual 1 2 2 7 || n=$((n + 1))
  testrules set none on true || n=$((n + 1)); testrules set over measure speed || n=$((n + 1))
  # No test file has a CPU budget (#349): a new rule of the measure budget is refused.
  testrules add x budget 1 2 2 || n=$((n + 1)); testrules set over measure budget || n=$((n + 1))
  [ $n = 7 ] && cmp -s "$PACK" "$STUB/pack.was"
}
t_rulescmds() {
  setup '[]'
  tr_eng tr_good || fail "a good value was refused"
  [ "$(jq -c .test.rules "$R/.conveyor/project.json")" = '{"list":[{"name":"over","on":true,"measure":"usual","limit":1,"runs":2,"minRuns":2},{"name":"flaky","on":false,"measure":"flaky","limit":2,"runs":1,"minRuns":0,"days":7}],"on":true,"perDay":2,"burst":false}' ] \
    || fail "the pack: $(jq -c .test.rules "$R/.conveyor/project.json")"
  tr_eng tr_bad 2> /dev/null || fail "a bad value was taken, or changed the pack: $(jq -c .test.rules "$R/.conveyor/project.json")"
  loop testrules remove flaky && [ "$(jq -c '[.test.rules.list[].name]' "$R/.conveyor/project.json")" = '["over"]' ] || fail "the rule was not removed"
}
