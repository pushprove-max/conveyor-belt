#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 120
# Engine cases: release-prep runs each case its red suite failed alone and judges it as the full test does (issue
# 789, fulljudge()): one that passes every run alone is flaky and blocks nothing; one that fails alone blocks the
# release. Their fixture is alsetup, below, on releaseboard.test.sh's runsetup (release.test.sh's cutsetup).
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"

# alsetup <cases>: runsetup with a suite of the cases named, each failing in the whole run: flips (flaky) passes in a run
# alone, breaks fails there too. A run alone (CONVEYOR_TEST_RERUN set) runs only the case its list names to fail, and
# notes it in $STUB/alone; given a second argument, the first run alone prints a failed alone.test of one file and
# leaves one case passed and one failed in the worktree's case results, then writes the Release panel's state and counts,
# as the snapshot gives them then (a whole snapshot: what the panel reads while the release process runs), in
# $STUB/counts, and its rerun's pass, of, case, done, failed, files, whether its at is not before its since and whether
# its at is the live record's progress, later than the progress read before the case results were made, in $STUB/rerun.
# It polls, as only the real watch moves that progress, until the watch has seen the cases (a progress that stays the
# one the watch set at its start is a time that never advances); the whole run prints "the whole run". release-prep
# 1.1.0 then runs on O; its output is in $T/$CASE.out and its exit in rc.
alsetup() { # <flips | breaks | "flips breaks"> [snap]
  local w=$T/$CASE/cards/release/wt snap=
  # The snapshot step is a here-document, not quoted text, so each sleep in it can say why time must pass.
  [ -z "${2:-}" ] || snap=$(cat <<EOS
    if [ ! -s "\$STUB/counts" ]; then printf '%s\n' 'TESTRUN files=1' '-- FAIL alone.test'
      b=\$(jq -r .progress $w.live)
      sleep 1 # sleep: the watch stamps its progress to the second, so the stamp it sets next differs from b only after a second
      mkdir -p $w.testlog/cases/ok $w.testlog/cases/failed; : > $w.testlog/cases/ok/a; : > $w.testlog/cases/failed/b
      i=0; while [ "\$(jq -r .progress $w.live)" = "\$b" ] && [ \$i -lt 600 ]; do
        sleep 0.1 # sleep: the pause between two reads of the progress, which only the real watch moves
        i=\$((i + 1)); done
      s=\$(bash $SRC/conveyor.sh snapshot --fresh | jq -c '.suites[] | select(.kind == "release")'); a=\$(jq -r .progress $w.live)
      jq -c '[.state, .failed, .cases]' <<<"\$s" > "\$STUB/counts"
      jq -c --arg b "\$b" --arg a "\$a" '.rerun | [.round, .of, .case, .done, .failed, .files, .at >= .since, (.at == \$a and \$a > \$b)]' <<<"\$s" > "\$STUB/rerun"; fi
EOS
)
  runsetup "$(printf '%s\n' '[ -n "${CONVEYOR_TEST_RERUN:-}" ] || echo "the whole run"' "for c in $1; do" \
    '  if [ -n "${CONVEYOR_TEST_RERUN:-}" ]; then awk -F "\t" -v c="$c" '\''$1 == "fail" && $NF == c { f = 1 } END { exit !f }'\'' "$CONVEYOR_TEST_RERUN" || continue; echo "$c" >> "$STUB/alone"' \
    "$snap" '  fi' \
    '  if [ "$c" = breaks ] || [ -z "${CONVEYOR_TEST_RERUN:-}" ]; then echo "FAIL [$c]: off"; bad=1; fi' \
    'done; [ -z "${bad:-}" ]')"
  loop release-prep 1.1.0 > "$T/$CASE.out" 2>&1; rc=$?
}

# Bug (#789, D1): a case that failed only in the release's suite run (it passes alone, as cases that fail only inside
# another file's run did) blocked the release, a fix card and a release-prep more each time.
t_relaloneflaky() {
  local O RUN rc
  alsetup flips
  [ $rc = 0 ] || fail "release-prep failed on a case that passes alone: $(cat "$T/$CASE.out")"
  [ "$(sort "$STUB/alone" | uniq -c | awk '{print $1, $2}')" = "3 flips" ] || fail "flips was not run alone three times: $(cat "$STUB/alone" 2>&1)"
  [ "$(jq -c '[.entries[] | [.case, .source]]' "$ST/flaky.json" 2>&1)" = "[[\"flips\",\"release 1.1.0 ${O:0:12}\"]]" ] \
    || fail "the case is not on the flaky-test record with the release as its source: $(cat "$ST/flaky.json" 2>&1)"
  jq -e '.state == "passed" and .failed == 0 and .cases == [] and ([.alone[] | [.case, .verdict, (.runs | join(","))]] == [["flips", "flaky", "passed,passed,passed"]])' "$RUN" > /dev/null \
    || fail "the record does not pass the suite and name the case judged flaky: $(cat "$RUN")"
  grep -q "statuses/$O -f state=success .*judged flaky: flips" "$STUB/gh-calls" || fail "the posted status does not pass and name the flaky case: $(cat "$STUB/gh-calls")"
}
# Bug (#789, D2): a case that fails alone too must still block the release, its runs alone kept with it.
t_relalonefail() {
  local O RUN rc
  alsetup breaks snap
  [ $rc = 1 ] && grep -q "statuses/$O -f state=failure" "$STUB/gh-calls" || fail "release-prep did not fail on a case that fails alone: $(cat "$T/$CASE.out")"
  jq -e '.state == "failed" and .cases == ["breaks"] and ([.alone[] | [.case, .verdict, (.runs | join(","))]] == [["breaks", "failed", "failed,failed,failed"]])' "$RUN" > /dev/null \
    || fail "the record does not carry the case's runs alone: $(cat "$RUN")"
  [ ! -s "$ST/flaky.json" ] || [ "$(jq '.entries | length' "$ST/flaky.json")" = 0 ] || fail "a case that fails alone went on the flaky-test record: $(cat "$ST/flaky.json")"
  # Bug (#789 review): each run alone cleared the suite's output and progress, so the failed release pointed to the
  # last run alone's output, and the Release panel's count went back to that run's while they ran.
  local w=$T/$CASE/cards/release/wt
  grep -q "its output is in $w.test" "$T/$CASE.out" && grep -q '^the whole run$' "$w.test" || fail "the failed release does not point to the suite's own output: $(cat "$w.test" 2>&1)"
  [ "$(cat "$STUB/counts" 2>&1)" = '["running",1,["breaks"]]' ] || fail "the snapshot did not show the suite's counts while the case ran alone: $(cat "$STUB/counts" 2>&1)"
  jq -e 'has("counts") | not' "$RUN" > /dev/null || fail "the ended record kept the counts of the runs alone: $(cat "$RUN")"
  # Bug (#1240): while the failed cases ran again, the record and the Board's release row kept the suite's counts with
  # no sign of the rerun: which pass, how far it was, when it last moved. The run alone printed a failed alone.test.
  [ "$(cat "$STUB/rerun" 2>&1)" = '[1,3,"breaks",2,1,{"done":1,"of":1,"failed":["alone.test"]},true,true]' ] \
    || fail "the snapshot's release entry did not show the rerun's pass and progress while breaks ran alone: $(cat "$STUB/rerun" 2>&1)"
  jq -e '.rerun == null' "$RUN" > /dev/null || fail "the ended record still names a rerun under way: $(cat "$RUN")"
}
# Bug (#789, D3): with a flaky case beside one that fails alone, the flaky one must not pass the run, nor be said to block it.
t_relalonemixed() {
  local O RUN rc
  alsetup 'flips breaks'
  [ $rc = 1 ] || fail "release-prep passed with a case that fails alone: $(cat "$T/$CASE.out")"
  jq -e '.state == "failed" and ([.alone[] | [.case, .verdict]] == [["breaks", "failed"], ["flips", "flaky"]])' "$RUN" > /dev/null \
    || fail "the record does not judge flips flaky and breaks the one that blocks: $(cat "$RUN")"
  [ "$(jq -c '[.entries[].case]' "$ST/flaky.json" 2>&1)" = '["flips"]' ] || fail "only flips should be on the flaky-test record: $(cat "$ST/flaky.json" 2>&1)"
}
# Bug (#1247): a run alone was named in the release record while the pass before's logs were still in the worktree (the
# run clears them only as it starts), and the last one was still named as release-prep put the suite's logs back, so
# the snapshot showed one pass's counts as another's progress. fulljudge() runs with its run alone stubbed: each pass
# writes its own logs; each write of the record notes the pass it names and the logs then in the worktree.
t_relalonepass() {
  local w=$T/$CASE/wt got
  mkdir -p "$T/$CASE"; got=$( RELRUN=$T/$CASE/run.json; echo '{"rerun":null}' > "$RELRUN"
    eval "$(sed -n '/^fulljudge() {/,/^}/p' "$SRC/lib/fulltest.sh")"; eval "$(sed -n 's/^relrec() {/relrec0() {/p' "$SRC/commands/release-prep.sh")"
    relrec() { relrec0 "$@"; echo "$(jq -c '.rerun.round' "$RELRUN") $(cat "$w.test" 2>/dev/null)/$(cat "$w.testlog/l" 2>/dev/null)" >> "$T/$CASE/seen"; }
    fullalone() { local p; p=p$(jq '.rerun.round' "$RELRUN"); mkdir -p "$1.testlog"; echo "$p" > "$1.testlog/l"; echo "$p" > "$1.test"; echo passed; }
    flaky() { :; }
    FULL_ALONE=3 fulljudge "$w" 0123456789abcdef 'bash t' '{"files":[{"file":"a.test","cases":[{"name":"x","line":"x failed"}]}]}' 'release 1.1.0' > /dev/null
    paste -sd, "$T/$CASE/seen" )
  [ "$got" = 'null /,1 /,null p1/p1,2 /,null p2/p2,3 /,null p3/p3' ] \
    || fail "fulljudge on a release's failed case x named a pass beside another pass's logs, or left one named (round logs.test/testlog, each write): $got"
}
