#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 300
# Engine cases: the flaky-test record (lib/flaky.sh): each case that failed and then passed when run again is kept, and
# a case that does so from three sources within seven days gets one issue.
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"

fl() { jq -r "$1" "$ST/flaky.json"; } # <jq filter> over the flaky-test record
flakyfiled() { [ -s "$STUB/filed" ] && jq -c "select(.labels | map(.name) | index(\"flaky-test\"))" "$STUB/filed" | wc -l || echo 0; }
# An entry of the record added at <seconds ago> by `flaky add`.
flakyat() { CONVEYOR_NOW=$(($(date +%s) - $1)) loop flaky add "${@:2}"; } # <seconds ago> <case> <source> <note>
# The test files the cases below name, on main: `flaky` drops an entry whose case is not in its file (t_flakyprune).
flakymain() { printf 'flaky\n' > "$R/b.test"; printf 'other\n' > "$R/c.test"; printf 'one\n' > "$R/x.test"; git -C "$R" add b.test c.test x.test && git -C "$R" commit -qm tests || fail "main's test files"; }

# The owner, 2026-11-13: all 20 failed test runs of a day passed on their next run, and nothing said which cases did
# that. A card whose run passed on re-run (its first run in <worktree>.first) adds one entry for each case that had not
# passed, by flakyrun(): the card, its issue and the time; one card alone files nothing. A card's run that does so is
# flakybatch.test.sh's.
t_flakyrerun() {
  setup '[]'
  local w=$T/$CASE/cards/c20260101T000000-repo-7 c=c20260101T000000-repo-7
  mkdir -p "${w%/*}"
  jq -cn '{exit: 1, failures: {files: [{file: "b.test", cases: [{name: "flaky"}]}, {file: "c.test", cases: [{name: "three"}]}]}}' > "$w.first"
  ( STATE=$ST/cards.jsonl; . "$SRC/lib/flaky.sh"; eval "$(sed -n '/^clock() {/p' "$SRC/lib/control.sh"; sed -n "/^NOTPASSED=/,/unique;'\$/p" "$SRC/lib/testrun.sh")"
    flakyrun "$w" ) || fail "flakyrun failed"
  [ "$(fl '[.entries[] | [.case, .source, .card, .issue] | join(" ")] | join("|")')" = "b.test: flaky $c $c 7|c.test: three $c $c 7" ] \
    || fail "not one entry for each case that passed on re-run, from the card: $(cat "$ST/flaky.json" 2>&1)"
  fl '.entries[] | .time | fromdate' > /dev/null || fail "an entry has no time: $(cat "$ST/flaky.json")"
  [ "$(flakyfiled)" = 0 ] || fail "one card's entries filed an issue: $(cat "$STUB/filed")"
}

# A card's files run side by side, so the time limit stops several at once: testfails() lists them all in stopped,
# and timeout names the one that ran out of time. Bug: b.test, only stopped beside c.test, got an entry as a case that
# failed and then passed, though run one at a time (#1594) it would not have begun. Only c.test gets one, and a.test,
# stopped by its own limit (ownLimit) though timeout names only the last, both from the first run alone (notpassed) and
# from a run again that passed them (passedagain).
t_flakyrunstopped() {
  setup '[]'
  local w=$T/$CASE/cards/c20260101T000000-repo-7 v=$T/$CASE/cards/c20260101T000000-repo-8
  mkdir -p "${w%/*}"
  jq -cn '{exit: 124, failures: {files: [], timeout: {sec: 1, file: "c.test"}, stopped: ["a.test", "b.test", "c.test"], ownLimit: ["a.test"]}}' | tee "$v.first" > "$w.first"
  ( STATE=$ST/cards.jsonl; . "$SRC/lib/flaky.sh"; eval "$(sed -n '/^clock() {/p' "$SRC/lib/control.sh"; sed -n "/^NOTPASSED=/,/unique;'\$/p" "$SRC/lib/testrun.sh")"
    flakyrun "$w" && flakyrun "$v" '{"passed":["a.test","b.test","c.test"],"okcases":[],"passcases":[]}' ) || fail "flakyrun failed"
  [ "$(fl '[.entries[] | [.case, .issue] | join(" ")] | join("|")')" = 'a.test 7|c.test 7|a.test 8|c.test 8' ] \
    || fail "with b.test only stopped beside c.test, which timed out, and a.test stopped by its own limit, the entries were not a.test's and c.test's alone, from the first run and the run again: $(cat "$ST/flaky.json" 2>&1)"
}

# Bug (O196): flakyrun() gave jq the run again's testfails() as one argument (--argjson); over 128 KiB (here 900 cases
# still failing, of 200-byte names) Linux refuses to start jq, and `|| return 0` recorded nothing. b.test's flaky
# passed in the run again: its entry is recorded; c.test's three did not pass, and has none.
t_flakyrunbig() {
  setup '[]'
  local w=$T/$CASE/cards/c20260101T000000-repo-7 l
  mkdir -p "${w%/*}"
  jq -cn '{exit: 1, failures: {files: [{file: "b.test", cases: [{name: "flaky"}]}, {file: "c.test", cases: [{name: "three"}]}]}}' > "$w.first"
  l=$(jq -cn '{passed: [], okcases: [], passcases: [{file: "b.test", cases: ["flaky"]}],
    files: [{file: "z.test", cases: [range(900) | {name: "case-\(.)-\("x" * 190)", line: "FAIL"}]}, {file: "c.test", cases: [{name: "three"}]}]}')
  [ ${#l} -gt 131072 ] || fail "the run again's result over 128 KiB was not made"
  ( STATE=$ST/cards.jsonl; . "$SRC/lib/flaky.sh"; eval "$(sed -n '/^clock() {/p' "$SRC/lib/control.sh"; sed -n "/^NOTPASSED=/,/unique;'\$/p" "$SRC/lib/testrun.sh")"
    flakyrun "$w" "$l" ) || fail "flakyrun failed"
  [ "$(fl '[.entries[] | .case] | join("|")')" = 'b.test: flaky' ] \
    || fail "with the run again's result over 128 KiB, the case that passed again was not the one entry: $(cat "$ST/flaky.json" 2>&1)"
}

# A main-red fix card and a land-branch card have no issue, and their ids end in -0. Bug: flakyrun() read the 0 as
# the card's issue, so the entry held issue 0 and the filed issue listed it as "issue #0".
t_flakyrunzero() {
  setup '[]'; flakymain
  local c=c20260101T000000-repo-0 b
  local w=$T/$CASE/cards/$c
  mkdir -p "${w%/*}"
  jq -cn '{exit: 1, failures: {files: [{file: "b.test", cases: [{name: "flaky"}]}]}}' > "$w.first"
  # shellcheck disable=SC2034 # STATE is read by the sourced lib/flaky.sh (FLAKY=${STATE%/*}/flaky.json)
  ( STATE=$ST/cards.jsonl; . "$SRC/lib/flaky.sh"; eval "$(sed -n '/^clock() {/p' "$SRC/lib/control.sh"; sed -n "/^NOTPASSED=/,/unique;'\$/p" "$SRC/lib/testrun.sh")"
    flakyrun "$w" ) || fail "flakyrun failed"
  [ "$(fl '.entries[] | [.card, .issue] | tojson')" = "[\"$c\",null]" ] || fail "the entry of a -0 card does not hold issue null: $(cat "$ST/flaky.json")"
  loop flaky add "b.test: flaky" two "second" > /dev/null && loop flaky add "b.test: flaky" three "third" > /dev/null || fail "flaky add failed"
  b=$(jq -r .body "$STUB/filed") && grep -q "^- .* $c$" <<<"$b" || fail "the filed body does not list the -0 card's entry: $b"
  ! grep -q 'issue #' <<<"$b" || fail "the filed body names an issue for a card that has none: $b"
}

# The cases kept off card runs (flakyoff(), called alone): a case whose last flaky issue is open, or that has none yet;
# never a case whose issue closed with no entry since, nor a case the card's list already names. A whole file is kept
# off only while an issue filed for it is open (g.test): never with no issue (d.test), nor a closed one (h.test), even
# with an entry newer than its closing (a full-suite rerun records one after the issue closes), nor a file the card's
# list names as failed (i.test, its issue open: the card's own failure must run it).
# Bug it catches: #1690 filed foreman-size.test.sh (a shell file, no cases) and said card steps keep it off, but they
# ran it whole, and its time-outs blocked #1734.
# A case whose entries aged out of the record (older than FLAKY_KEEP, dropped at the next write) stays off while its
# filed issue is open (#470): e.test: five has no entries left, only its open issue.
t_flakyoffissue() {
  setup '[]'
  local w=$T/$CASE/wt
  jq -cn '{entries: (["b.test: one", "b.test: two", "c.test: three", "d.test", "b.test: four", "g.test", "h.test", "i.test"]
      | map({case: ., source: "s", time: "2026-11-10T00:00:00Z"})), filed: [{case: "b.test: one", issue: 100101}, {case: "b.test: two", issue: 100102},
      {case: "e.test: five", issue: 100103}, {case: "g.test", issue: 100104}, {case: "h.test", issue: 100105}, {case: "i.test", issue: 100106}]}' > "$T/$CASE/flaky.json"
  echo OPEN > "$STUB/state.100101"; echo CLOSED > "$STUB/state.100102"; echo OPEN > "$STUB/state.100103"
  echo OPEN > "$STUB/state.100104"; echo CLOSED > "$STUB/state.100105"
  echo 2026-11-01T00:00:00Z > "$STUB/closedAt.100105"; echo OPEN > "$STUB/state.100106"
  printf 'fail\tb.test\tfour\npass\tc.test\nfail\ti.test\n' > "$w.rerun"
  ( eval "$(sed -n '/^flakyoff() {/,/^}/p' "$SRC/lib/flaky.sh")"; FLAKY=$T/$CASE/flaky.json flakyoff "$w" ) || fail "flakyoff failed"
  # Bug it catches (issue 469): the `ok` line alone could not be told from a case that passed in a run killed part-way,
  # so a change that selected a kept-off case ran it again. Each kept-off case has an `off` line too, its file listed
  # as passed or not (a change that selects c.test runs it again).
  [ "$(tr '\t\n' ':|' < "$w.rerun")" = "fail:b.test:four|pass:c.test|fail:i.test|ok:b.test:one|off:b.test:one|off:c.test:three|ok:e.test:five|off:e.test:five|pass:g.test|off:g.test|" ] || fail "the cases kept off: $(cat "$w.rerun")"
}

# `flaky add` (the nightly whole test: a case that failed in the full run and passed alone) adds one entry with its
# source and note; a call with no case name adds none.
t_flakyadd() {
  setup '[]'; flakymain
  loop flaky add "x.test: one" nightly "failed in the full run, passed alone" > /dev/null || fail "flaky add failed"
  [ "$(fl '.entries | map([.case, .source, .note] | join("|")) | join(",")')" = "x.test: one|nightly|failed in the full run, passed alone" ] \
    || fail "the entry is not the one added: $(cat "$ST/flaky.json")"
  loop flaky add "" nightly "no case" 2> "$STUB/err"; [ $? = 2 ] || fail "flaky add with an empty case name did not refuse"
  loop flaky add 2> /dev/null; [ $? = 2 ] || fail "flaky add with no case did not refuse"
  grep -q 'usage: conveyor.sh flaky add <case> <source> <note>' "$STUB/err" || fail "the refusal does not give the usage: $(cat "$STUB/err")"
  [ "$(fl '.entries | length')" = 1 ] || fail "a refused call added an entry: $(cat "$ST/flaky.json")"
}

# The third entry of a case from a third source within seven days files exactly one issue, with its title, labels and
# body; while it is open a fourth files nothing, and once it is closed the next files again. An entry older than seven
# days does not count, and one older than 30 days is dropped. The Board's line has each case's count and its issue.
t_flakyfile() {
  setup '[]'; flakymain
  tune '.labels.nonProductAreas += ["area:engine"]'
  local k="b.test: flaky" day=86400 b
  flakyat $((40 * day)) "$k" old "forty days ago" > /dev/null && flakyat $((9 * day)) "$k" week "nine days ago" > /dev/null \
    && flakyat $((2 * day)) "$k" one "first" > /dev/null && flakyat $day "$k" two "second" > /dev/null || fail "flaky add failed"
  [ "$(fl '[.entries[].source] | join(" ")')" = "week one two" ] || fail "an entry older than 30 days was kept: $(cat "$ST/flaky.json")"
  [ "$(flakyfiled)" = 0 ] || fail "two sources in seven days and one older filed an issue: $(cat "$STUB/filed")"
  loop flaky add "$k" three "third" > /dev/null || fail "flaky add failed"
  [ "$(flakyfiled)" = 1 ] || fail "the third source in seven days did not file exactly one issue: $(cat "$STUB/filed" 2>&1)"
  [ "$(jq -r .title "$STUB/filed")" = "Flaky test: b.test: flaky fails at random" ] || fail "the title: $(jq -r .title "$STUB/filed")"
  [ "$(jq -c '[.labels[].name]' "$STUB/filed")" = '["bug","P2","area:engine","flaky-test"]' ] || fail "the labels: $(jq -c .labels "$STUB/filed")"
  grep -qx 'label create -- flaky-test' "$STUB/labels" || fail "the flaky-test label was not made: $(cat "$STUB/labels" 2>&1)"
  b=$(jq -r .body "$STUB/filed")
  for s in one:first two:second three:third; do grep -q "^- .* ${s%%:*}: ${s#*:}$" <<<"$b" || fail "the body does not list the entry of $s: $b"; done
  ! grep -q '^- .* \(week\|old\):' <<<"$b" || fail "the body lists an entry older than seven days: $b"
  grep -q 'Make the test reliable, or remove it\.' <<<"$b" && grep -qx 'Done when: the case passes alone and in the whole test\.' <<<"$b" \
    || fail "the body does not ask for the test to be made reliable or removed, with its Done when: $b"
  ! grep -q 'Follow-up to' <<<"$b" || fail "the issue reads as a review follow-up: $b"
  # The body says what the record now does to card runs (flakyoff()), not that the case must still pass on them.
  grep -q 'card test steps are told to keep the case off' <<<"$b" && ! grep -q 'still has to pass' <<<"$b" \
    || fail "the body does not say the case is kept off card test steps: $b"
  [ "$(fl '.filed | tojson')" = '[{"case":"b.test: flaky","issue":100101}]' ] || fail "the issue filed is not kept: $(cat "$ST/flaky.json")"
  echo OPEN > "$STUB/state.100101"
  loop flaky add "$k" four "fourth" > /dev/null || fail "flaky add failed"
  [ "$(flakyfiled)" = 1 ] || fail "a fourth entry filed again while the issue was open: $(cat "$STUB/filed")"
  loop flaky add "c.test: other" one "x" > /dev/null || fail "flaky add failed"
  b=$(loop snapshot --fresh | jq -c '.flaky')
  [ "$b" = '[{"case":"b.test: flaky","count":4,"issue":100101,"files":["b.test"]},{"case":"c.test: other","count":1,"issue":null,"files":["c.test"]}]' ] || fail "the snapshot's flaky cases: $b"
  echo CLOSED > "$STUB/state.100101"
  loop flaky add "$k" five "fifth" > /dev/null || fail "flaky add failed"
  [ "$(flakyfiled)" = 2 ] || fail "an entry after the issue was closed filed none: $(cat "$STUB/filed")"
}

# Once the case's filed issue is closed (its fix landed), only the entries made after it closed count toward a new
# issue, and only they are listed. Bug it catches (#440): one entry after the close filed a new issue that counted
# and listed the three entries from before the fix.
t_flakyclosed() {
  setup '[]'; flakymain
  local k="b.test: flaky" hour=3600 b
  flakyat $((72 * hour)) "$k" one "first" > /dev/null && flakyat $((48 * hour)) "$k" two "second" > /dev/null \
    && flakyat $((24 * hour)) "$k" three "third" > /dev/null || fail "flaky add failed"
  [ "$(flakyfiled)" = 1 ] || fail "three sources did not file the first issue: $(cat "$STUB/filed" 2>&1)"
  echo CLOSED > "$STUB/state.100101"; jq -rn "now - 12 * $hour | todate" > "$STUB/closedAt.100101"
  flakyat $((6 * hour)) "$k" four "fourth" > /dev/null || fail "flaky add failed"
  [ "$(flakyfiled)" = 1 ] || fail "one entry after the close filed an issue, counting the entries from before it: $(cat "$STUB/filed")"
  flakyat $((3 * hour)) "$k" five "fifth" > /dev/null && loop flaky add "$k" six "sixth" > /dev/null || fail "flaky add failed"
  [ "$(flakyfiled)" = 2 ] || fail "three sources after the close did not file one issue: $(cat "$STUB/filed")"
  b=$(jq -rs '.[-1].body' "$STUB/filed")
  [ "$(grep -c '^- ' <<<"$b")" = 3 ] && for s in four:fourth five:fifth six:sixth; do grep -q "^- .* ${s%%:*}: ${s#*:}$" <<<"$b" || fail "the new issue does not list the entry of $s: $b"; done \
    || fail "the new issue does not list exactly the three entries after the close: $b"
}

# `flaky off` (the Board's Keep a case off, an action that files no issue) adds its entry and files none, though it is
# the case's third source within seven days. Bug it catches: the Board ran `flaky add`, which filed an issue then.
t_flakyoffadd() {
  setup '[]'; flakymain
  local k="b.test: flaky" day=86400
  flakyat $((2 * day)) "$k" one "first" > /dev/null && flakyat $day "$k" two "second" > /dev/null || fail "flaky add failed"
  loop flaky off "$k" "Board user" "kept off" > /dev/null || fail "flaky off failed"
  [ "$(fl '[.entries[] | .source] | join(",")')" = "one,two,Board user" ] || fail "flaky off did not add its entry: $(cat "$ST/flaky.json")"
  [ "$(flakyfiled)" = 0 ] || fail "flaky off filed an issue: $(cat "$STUB/filed")"
}

# The engine's runner names a flaky case as its own (run.test.sh: rone), so the snapshot's flaky case names the case
# file that defines it and runs through that runner (cases/r.test.sh) too: the Board's Tests page shows Put back on
# that file's row. Bug it catches: Put back matched a case by the row's file name alone and never showed a runner's case.
t_flakysnapfiles() {
  setup '[]'; mkdir -p "$R/cases"
  printf '# run.test.sh\nt_rone() {\n  :\n}\n' > "$R/cases/r.test.sh"
  git -C "$R" add cases && git -C "$R" commit -qm cases || fail "main's case file"
  loop flaky off "run.test.sh: rone" "Board user" "kept off" > /dev/null || fail "flaky off failed"
  b=$(loop snapshot --fresh | jq -c '[.flaky[] | {case, files}]')
  [ "$b" = '[{"case":"run.test.sh: rone","files":["run.test.sh","cases/r.test.sh"]}]' ] || fail "the snapshot's flaky case does not name its case file: $b"
}

# Three entries from one source are one source: nothing is filed.
t_flakysame() {
  setup '[]'; flakymain
  local i; for i in 1 2 3; do loop flaky add "b.test: flaky" nightly "run $i" > /dev/null || fail "flaky add failed"; done
  [ "$(fl '.entries | length')" = 3 ] || fail "not three entries: $(cat "$ST/flaky.json")"
  [ "$(flakyfiled)" = 0 ] || fail "three entries from one source filed an issue: $(cat "$STUB/filed")"
}

# Bug it catches: again() counted the entries (or their times) of a file, so one full test run that found two cases
# of it flaky made the file "flaky again" and reopened the issue of its fix, though it failed once: fulljudge() (lib/fulltest.sh) writes each case with its own `flaky` call, so the run's entries have one source
# and times seconds apart. The entries go in through the real writer, `flaky add`, an hour apart: one source is one
# failure; a second source (a card) is the second, and issue 5 is the one to reopen.
t_flakyagainsources() {
  setup '[]'
  printf 'x\ny\n' > "$R/b.test"; git -C "$R" add b.test && git -C "$R" commit -qm tests || fail "main's test file"
  printf '{"entries": [], "filed": [{"case": "b.test: x", "issue": 5, "time": "2020-01-01T00:00:00Z"}]}\n' > "$ST/flaky.json"
  flakyat 7200 "b.test: x" "full test c0ffee" "first" > /dev/null && flakyat 3600 "b.test: y" "full test c0ffee" "second" > /dev/null \
    || fail "flaky add failed: $(cat "$ST/flaky.json")"
  cp "$ST/flaky.json" "$T/$CASE/one.json"
  flakyat 60 "b.test: x" "card c1" "third" > /dev/null || fail "flaky add failed: $(cat "$ST/flaky.json")"
  cp "$ST/flaky.json" "$T/$CASE/two.json"
  fx_in 'for r in one two; do echo "$r: $(jq -c --slurpfile defs <(echo "{}") --slurpfile refs <(echo "{}") "$OWNERS$FLAKYAGAIN"'"'"'again("b.test"; now; 7)'"'"' "$T/$CASE/$r.json")"; done'
  grep -qxF 'one: null' "$T/$CASE/run.out" && grep -qxF 'two: 5' "$T/$CASE/run.out" \
    || fail "again(): two cases of one full test run were not one failure, or a second source did not reopen issue 5: $(cat "$T/$CASE/run.out") from $(cat "$T/$CASE/one.json")"
}

# Bug it catches (#1048): a runner's case files were looked for in the *.test.* files alone, so the case run.mjs names
# as its own, defined in src/test-a.mjs (the pack's tests.patterns), which names run.mjs, was dropped as gone.
t_flakypatterns() {
  setup '[]'; tune '.tests.patterns = ["test-*.mjs"]'; mkdir -p "$R/src" "$ST"
  printf "// through run.mjs\ntest('one', () => {});\n" > "$R/src/test-a.mjs"; echo "// runs src/" > "$R/run.mjs"
  git -C "$R" add src run.mjs && git -C "$R" commit -qm tests || fail "main's test files"
  jq -cn '{entries: [{case: "run.mjs: one", source: "s", time: (now - 86400 | todate)}], filed: []}' > "$ST/flaky.json"
  loop flaky off "run.mjs: one" "Board user" "kept off" > /dev/null 2> "$STUB/err" || fail "flaky off failed: $(cat "$STUB/err")"
  [ "$(fl '[.entries[].case] | join("|")')" = "run.mjs: one|run.mjs: one" ] || fail "the case was dropped: $(cat "$STUB/err" "$ST/flaky.json")"
}

# `conveyor.sh flaky` drops, as it reads the record, each case gone from main: renamed in its file, no longer in a
# runner's case files, or its file gone; its open issue is closed with the reason. A case still in its file (its name
# quoted there as 'it\'s kept' too), one in a file named from a subfolder (pkg/s.test as s.test) and a runner's case
# still in its case file stay. Bug it catches:
# the record kept a renamed case's entries under each old name, and a removed file's, so they named cases that no
# longer ran.
t_flakyprune() {
  setup '[]'; mkdir -p "$R/cases" "$R/pkg" "$ST"
  printf "test('new name', () => {})\ntest('kept', () => {})\ntest('it\\\\'s kept', () => {})\n" > "$R/b.test.mjs"; printf '# runs cases/\n' > "$R/r.test.sh"
  printf '# r.test.sh\nt_rcase() {\n  :\n}\n' > "$R/cases/c.test.sh"; printf "test('sub', () => {})\n" > "$R/pkg/s.test"
  git -C "$R" add -A && git -C "$R" commit -qm tests || fail "main's test files"
  jq -cn --arg q "b.test.mjs: it's kept" '{entries: (["b.test.mjs: old name", "b.test.mjs: kept", $q, "gone.test.mjs: x", "r.test.sh: rcase", "r.test.sh: rgone", "s.test: sub"]
    | map({case: ., source: "s", time: (now - 86400 | todate)})), filed: [{case: "b.test.mjs: old name", issue: 100101}, {case: "gone.test.mjs: x", issue: 100102}]}' > "$ST/flaky.json"
  echo OPEN > "$STUB/state.100101"; echo CLOSED > "$STUB/state.100102"
  loop flaky off "b.test.mjs: kept" "Board user" "kept off" > /dev/null 2> "$STUB/err" || fail "flaky off failed: $(cat "$STUB/err")"
  [ "$(fl '[.entries[].case] | join("|")')" = "b.test.mjs: kept|b.test.mjs: it's kept|r.test.sh: rcase|s.test: sub|b.test.mjs: kept" ] || fail "the entries kept: $(cat "$ST/flaky.json")"
  [ "$(fl '.filed | length')" = 0 ] || fail "a dropped case's filed issue was kept: $(cat "$ST/flaky.json")"
  [ "$(cat "$STUB/closed" 2>&1)" = 100101 ] || fail "not exactly the open issue of the renamed case was closed: $(cat "$STUB/closed" 2>&1)"
  grep -q 'b.test.mjs: old name.*no longer in b.test.mjs' "$STUB/close-comments" || fail "the closing comment does not give the reason: $(cat "$STUB/close-comments" 2>&1)"
  grep -q 'b.test.mjs: old name: dropped .* 1 entries and #100101: the case "old name" is no longer in b.test.mjs' "$STUB/err" \
    && grep -q "gone.test.mjs: x: dropped .*: its file gone.test.mjs is not in main's checkout$" "$STUB/err" \
    && grep -q 'r.test.sh: rgone: dropped .*: the case "rgone" is no longer in r.test.sh' "$STUB/err" || fail "a dropped case was not said with its reason: $(cat "$STUB/err")"
}
