#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 120
# Engine cases: the Board's Record CPU time on a Wall only test file (#190): cpuplan() (lib/testfiles.sh) says whether
# conveyor/tools/testtime.sh can wrap the pack's test command for the file, `conveyor.sh test-settings cpu-time <file>`
# saves that command, and a run of it records the file's CPU seconds (timed(), lib/testlist.sh); and Record test times
# (timesplan(), recordtimes(), lib/setup.sh): the plan in the snapshot's health and `test-settings record-times`. fx_in and
# fx_wt are in lib.sh.
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"
# A page of the repository says <text> (lines joined, spaces folded). Each case file that calls it defines its own, named after the file: the bug check puts only the card's test files on main's code, where a helper in lib.sh is missing, and the runner sources the case files into one shell, where one name cannot be defined twice.
pagesays_cputime() { tr '\n' ' ' < "$SRC/../$1" | tr -s ' ' | grep -qF -- "$2" || fail "$1 does not say \"$2\": $3"; } # <page> <text> <what the run showed>

# Bug it catches: a Wall only file had no way to record its CPU seconds, or the saved command still gave none. The test
# command runs one test file, w.test.sh, so the plan wraps it; test-settings cpu-time saves that command, and the
# pack's test.fileCommand wrapped too. Bug it catches too (E8 of #374's review): only test.command was saved, which no
# card runs (a file it names is a suite runner, on no card's list), so a card's run gave no CPU seconds. The card's
# run of its own test file x.test.sh, alone through the saved test.fileCommand, records x.test.sh with CPU seconds.
t_cputimesave() {
  setup '[]'; tune '.test.command = "bash w.test.sh" | del(.test.list) | .test.fileCommand = "bash"'
  fx_wt 'cp w.test.sh x.test.sh' w.test.sh 'i=0; while [ $i -lt 20000 ]; do i=$((i + 1)); done; echo done-w'
  fx_in 'p=$(cpuplan) && jq -e ".file == \"w.test.sh\" and .was == \"bash w.test.sh\"" <<<"$p" > /dev/null && testsettings cpu-time w.test.sh \
    && [ "$(jq -r .test.command "$R/.conveyor/project.json")" = "$(jq -r .command <<<"$p")" ] \
    && [ "$(jq -r .test.fileCommand "$R/.conveyor/project.json")" = "$(jq -r .fileCommand <<<"$p")" ] \
    && tests "$FXWT" && grep -q done-w "$FXWT.test" && timed "$FXWT"'
  [ "$RC" = 0 ] || fail "Record CPU time was not saved, or the card's run failed: $(cat "$T/$CASE/run.out" "$FXWT.test")"
  jq -e '."x.test.sh" | .cpu | numbers' < <(tail -n 1 "$T/$CASE/run.out") > /dev/null || fail "the card's run of the saved command gave x.test.sh no CPU seconds: $(cat "$T/$CASE/run.out")"
  # Its exit is the file's own: a failing file still fails the run.
  printf 'exit 3\n' > "$FXWT/x.test.sh"; printf 'fail\tx.test.sh\n' > "$FXWT.rerun"
  fx_in '! tests "$FXWT" test.fileCommand alone'
  [ "$RC" = 0 ] || fail "the wrapped command passed a failing test file"
}

# Bug it catches: Record CPU time saved a wrapper where it cannot time one file, so every file got the same time or
# none. With a test list, a command of more than one part, or one that names more than one test file, the plan says
# why, and test-settings cpu-time refuses and leaves the pack as it was.
t_cputimerefused() {
  local p before
  FXWT=; setup '[]'; printf 'exit 0\n' > "$R/a.test.sh"; printf 'exit 0\n' > "$R/b.test.sh"; git -C "$R" add a.test.sh b.test.sh && git -C "$R" commit -qm tests
  for p in '"bash a.test.sh"|args|given the test files of each card' '"bash a.test.sh; true"||not one plain command' \
    '"bash a.test.sh b.test.sh"||runs more than one test file' '"bash tests"|none|runs more than one test file'; do
    tune --argjson c "${p%%|*}" --arg l "$(cut -d'|' -f2 <<<"$p")" '.test.command = $c | if $l == "" then del(.test.list) else .test.list = $l end'
    before=$(cat "$R/.conveyor/project.json")
    fx_in 'cpuplan; ! testsettings cpu-time a.test.sh'
    [ "$RC" = 0 ] && grep -qF -- "${p##*|}" "$T/$CASE/run.out" || fail "the command ${p%%|*} was not refused with why: $(cat "$T/$CASE/run.out")"
    [ "$(cat "$R/.conveyor/project.json")" = "$before" ] || fail "a refused Record CPU time changed the pack (${p%%|*})"
  done
}

# One card test run of the case's records that recorded no test times (health's untimed counts it).
ct_untimed() { jq -cn '{card: "c0-1", issue: 1, step: "test", time: "2026-11-01T00:00:00Z", tokens: {claude: 0, codex: 0}, result: "pass", sha: "", reason: ""}' >> "$ST/cards.jsonl"; }

# Bug it catches: the Health part gave no way to record test times for a runner whose report setup knows, or the action
# did not set the pack's test.report. The plan is in the snapshot's health while the last runs recorded no times, and
# null once a run records them; `test-settings record-times` saves the report the plan names.
t_timesplanreport() {
  local p
  setup '[]'; tune '.test.command = "node --test" | del(.test.report)'; ct_untimed
  p=$(loop snapshot --fresh | jq -c '.health.timesPlan | {kind, runner: .report.runner, format: .report.format}')
  [ "$p" = '{"kind":"report","runner":"node --test","format":"junit"}' ] || fail "the snapshot's health gives no report plan for node --test: $p"
  loop test-settings record-times > "$T/$CASE/rt.out" 2>&1 || fail "record-times failed: $(cat "$T/$CASE/rt.out")"
  [ "$(jq -c '.test.report | {runner, format}' "$R/.conveyor/project.json")" = '{"runner":"node --test","format":"junit"}' ] \
    || fail "record-times did not set the pack's test.report: $(jq -c .test "$R/.conveyor/project.json")"
  jq -cn '{card: "c0-2", issue: 2, step: "test", time: "2026-11-02T00:00:00Z", tokens: {claude: 0, codex: 0}, result: "pass", sha: "", reason: "", times: {"a.test": 1}}' >> "$ST/cards.jsonl"
  # The pack names no report again, so the plan would apply: only the recorded times keep it out of the health.
  tune 'del(.test.report)'
  [ "$(loop snapshot --fresh | jq -c .health.timesPlan.kind)" = null ] || fail "the snapshot's health still has a plan after a run recorded times"
}

# Bug it catches: a test command that runs one test file got no wrap from the action, so its cards still recorded no
# times. The plan is cpuplan()'s, and record-times saves that command (and test.fileCommand's) as cpu-time does.
t_timesplanwrap() {
  local p
  setup '[]'; tune '.test.command = "bash w.test.sh" | del(.test.list) | del(.test.report) | .test.fileCommand = "bash"'; ct_untimed
  printf 'exit 0\n' > "$R/w.test.sh"; git -C "$R" add w.test.sh && git -C "$R" commit -qm w || fail "main's test file"
  # The plan as the Tests page reads it, from the snapshot's health: a Health part that drops a wrap plan fails here.
  p=$(loop snapshot --fresh | jq -c .health.timesPlan)
  [ "$(jq -r '[.kind, .file, .was] | join(" ")' <<<"$p")" = "wrap w.test.sh bash w.test.sh" ] || fail "the snapshot's health has no wrap plan for a one-file command: $p"
  loop test-settings record-times > "$T/$CASE/rt.out" 2>&1 || fail "record-times failed: $(cat "$T/$CASE/rt.out")"
  [ "$(jq -r .test.command "$R/.conveyor/project.json")" = "$(jq -r .command <<<"$p")" ] \
    && [[ $(jq -r .test.command "$R/.conveyor/project.json") == *CONVEYOR_TEST_TIME* ]] || fail "record-times did not save the wrapped command: $(jq -c .test "$R/.conveyor/project.json")"
}

# Bug it catches: a test command that runs a script of the project had its script changed or nothing filed. The plan
# is a held card (no GitHub issue, picked only once released) whose body holds timinghint()'s wrap steps; the pack stays
# as it was, and a second action does not file the same card again.
t_timesplancard() {
  local before p wrap
  setup '[]'; tune '.test.command = "bash run-all.sh" | del(.test.list) | del(.test.report)'; ct_untimed
  printf 'for f in *.test.sh; do bash "$f"; done\n' > "$R/run-all.sh"; git -C "$R" add run-all.sh && git -C "$R" commit -qm s || fail "main's script"
  before=$(cat "$R/.conveyor/project.json")
  # The command that wraps one file's run (timinghint()): the body must hold it as a line, not only its words.
  # shellcheck disable=SC2016 # the line as the body prints it, $f and $out unexpanded
  wrap='./testtime.sh "$f" -- <the file'\''s command> > "$out" 2>&1; rc=$?; cat "$out"; grep '\''^TESTRUN sec'\'' "$out" >> "$CONVEYOR_TEST_LOG/<its log>"'
  # The plan as the Tests page reads it, from the snapshot's health: a Health part that drops a card plan fails here.
  p=$(loop snapshot --fresh | jq -c .health.timesPlan)
  jq -e --arg w "$wrap" '.kind == "card" and .file == "run-all.sh" and (.body | split("\n") | any(sub("^\\s+"; "") == $w))' <<<"$p" > /dev/null \
    || fail "the snapshot's health has no card plan with the wrap command for a script: $p"
  loop test-settings record-times > "$T/$CASE/rt.out" 2>&1 || fail "record-times failed: $(cat "$T/$CASE/rt.out")"
  jq -e --arg w "$wrap" '.cards | length == 1 and (.[0] | .held == true and .card == null and .file == "run-all.sh" and (.body | split("\n") | any(sub("^\\s+"; "") == $w)))' \
    "$ST/testactions/cards.json" > /dev/null || fail "no held card with the wrap command: $(cat "$ST/testactions/cards.json" "$T/$CASE/rt.out")"
  [ "$(cat "$R/.conveyor/project.json")" = "$before" ] || fail "record-times changed the pack for a script"
  # Bug (#1436): the guide said every test-settings command but history-start changes the pack; the run above filed a card and left it as it was.
  pagesays_cputime conveyor/README.md '`record-times` when its plan is a held card, which files the card and leaves the pack as it is' "record-times filed a held card and left the pack as it was"
  loop test-settings record-times > "$T/$CASE/rt.out" 2>&1 && fail "a second record-times filed the card again"
  [ "$(jq '.cards | length' "$ST/testactions/cards.json")" = 1 ] || fail "a second record-times filed a second card: $(cat "$T/$CASE/rt.out")"
}
