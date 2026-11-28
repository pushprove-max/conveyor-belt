#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 300
# Engine cases (#157): the records the engine's own writers write pass the record check (jq/check.jq), and a record
# that does not is set aside while the loop goes on. Bug caught: #147 added a list field to test lines (testrec()) but
# not to check.jq; the first card that wrote one stopped the loop and every snapshot, and no test had run check.jq
# on a line the real writers made.
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"

# recok (lib.sh) fails on each line the check refuses. The writers the cases here do not reach are checked by recok in
# the cases that already make their lines: the rebase line (port.test.sh t_rebase), the filed line and a landed line
# with leftover and followups (portfix.test.sh t_portfix, resume.test.sh t_resume), a land-branch card's picked line with branch
# (branch.test.sh t_branch) and a landed line with yesFrom (visibleinherit.test.sh t_inheritpart).
# Fails unless the records hold a line of each step named.
recsteps() { # <what wrote them> <step>...
  local s have; have=$(jq -r .step "$ST/cards.jsonl" | sort -u)
  for s in "${@:2}"; do grep -qxF "$s" <<<"$have" || fail "$1 wrote no $s line, so its fields went unchecked: $(tr '\n' ' ' <<<"$have")"; done
}

# A whole card of the loop, with a NO-GO review, a fix and the GO after it, its changed tests (the test line's list:
# the test file linked to its change, run alone) and its landing and push: each line it writes, with the fields each
# writer adds (picked's title and created, worktree's pid and account, a session's model, effort and usage, a review's
# counts and visible, the test line's list, selected and why, landed's diff and product, pushed's head), checks.
# The records start with a line of a field the check does not know: it is set aside, named with its line and field,
# and the loop still picks and lands the card (the loop did not stop for it).
t_recloop() {
  setup "[$(issue 7 2026-01-01)]"; echo "$NOGO" > "$STUB/review.1"; echo "$GO" > "$STUB/review.2"
  good='{"card":"c0-4","issue":4,"step":"picked","time":"2026-11-01T00:00:00Z","tokens":{"claude":0,"codex":0},"result":"ok","sha":"","reason":""}'
  printf '%s\n' "$good" "${good/\"reason\":\"\"/\"reason\":\"\",\"later\":1}" > "$ST/cards.jsonl"
  out=$(loop run --only 7 1 2>&1) || fail "the loop stopped on a line with a field the check does not know: $out"
  jq -se 'length == 1 and (.[0] | .line == 2 and .field == "later" and (.record | fromjson | .later == 1))' "$ST/quarantined.jsonl" > /dev/null \
    || fail "the line was not set aside with its line number and field: $(cat "$ST/quarantined.jsonl" 2>&1)"
  grep -qF '"later"' "$ST/cards.jsonl" && fail "the line set aside is still in the card records"
  [ "$(st 'select(.issue == 7 and .step == "picked") | .issue')" = 7 ] || fail "the loop did not pick #7 after the line was set aside: $out"
  loop health | jq -e '.quarantined == [{line: 2, field: "later", time: .quarantined[0].time}]' > /dev/null || fail "health does not name the line set aside: $(loop health)"
  recsteps "a card of the loop" picked worktree brief start build review fix test landed pushed
  [ "$(st 'select(.issue == 7 and .step == "test" and .before == null) | .list.mode')" = changed ] || fail "the test line has no list of the changed tests: $(st 'select(.step == "test")')"
  recok "$ST/cards.jsonl" "a card of the loop"
}

# Bug (#1791): a writer and the check learn a new field in separate commits, and a valid line written between them
# was set aside for good: nothing tested $QUARANTINE again, so health said "needs you" after the check caught up and
# the history lost the step. Now the check puts back each set-aside record it accepts, at its time place, and keeps
# the one it still refuses, which health still names.
# Bug (#1791, review): the put-back dropped a record with no time (the record check then had nothing to set aside); it
# put back a Test line of a card whose lines `retry` had moved to the retried file, so that card looked open again;
# and `cards` answered from the copy it took before the put-back, so it left out the record it had just put back.
# Bug (#1791, review 2): the cards whose lines left went to jq as one argument, so once the ended list's map passed
# the kernel's limit for one argument (128 KiB on Linux), jq could not start and nothing was put back.
qrec() { echo "{\"card\":\"c0-$1\",\"issue\":$1,\"step\":\"picked\",\"time\":\"2026-11-01T0$1:00:00Z\",\"tokens\":{\"claude\":0,\"codex\":0},\"result\":\"ok\",\"sha\":\"\",\"reason\":\"\"${2:-}}"; }
t_recputback() {
  local out err r5
  setup '[]'
  printf '%s\n' "$(qrec 1)" '{"card":"c","issue":7,"step":"landed"}' "$(qrec 3)" > "$ST/cards.jsonl"
  r5=$(qrec 5); echo "${r5/picked/blocked}" > "$ST/retried.jsonl"
  mkdir -p "$ST/archive" && awk 'BEGIN { for (i = 0; i < 4000; i++) printf "{\"card\":\"c20261101T000000-conveyor-belt-%d\",\"issue\":%d,\"step\":\"landed\"}\n", i, i }' > "$ST/archive/ended.jsonl"
  jq -cn --arg ok "$(qrec 2)" --arg bad "$(qrec 4 ',"later":1')" --arg gone "$r5" '{line: 2, field: "rerun", time: "2026-11-02T00:00:00Z", record: $ok},
    {line: 3, field: "later", time: "2026-11-02T00:00:00Z", record: $bad}, {line: 5, field: "rerun", time: "2026-11-02T00:00:00Z", record: $gone}' > "$ST/quarantined.jsonl"
  out=$(loop cards 2> "$STUB/cards.err") || fail "cards failed with a set-aside record the check accepts: $(cat "$STUB/cards.err")"; err=$(cat "$STUB/cards.err")
  jq -e '.cards | any(.card == "c0-2")' <<<"$out" > /dev/null || fail "cards left out the record its own check put back: $out"
  [ "$(jq -r .card "$ST/cards.jsonl" | tr '\n' ' ')" = 'c0-1 c0-2 c0-3 ' ] || fail "the accepted record is not back in the records at its time place: $(cat "$ST/cards.jsonl")"
  grep -qF 'a set-aside record of card c0-2 passes the record check now' <<<"$err" || fail "the check did not name the record it put back: $err"
  grep -qF "card c0-5 passes the record check now, but the card's lines have left" <<<"$err" || fail "the check did not name the record it kept for its card's move: $err"
  [ "$(jq -sc 'map(.record | fromjson | .card)' "$ST/quarantined.jsonl")" = '["c0-4","c0-5","c"]' ] \
    || fail "the quarantine does not hold the refused record, the moved card's record and the line with no time: $(cat "$ST/quarantined.jsonl")"
  loop health 2> /dev/null | jq -e '.quarantined | map(.line) == [3, 5, 2]' > /dev/null || fail "health does not name only the records still set aside: $(loop health 2>&1)"
}

# Bug (#1791, review 2): the snapshot put the record back after snapcopy() had read the pushes, so a push line put back
# was in the card rows but not in the day's push count.
t_recputbacksnap() {
  local now r out
  setup '[]'; now=$(date -u +%FT%TZ)
  r="{\"card\":\"cP\",\"issue\":9,\"step\":\"picked\",\"time\":\"$now\",\"tokens\":{\"claude\":0,\"codex\":0},\"result\":\"ok\",\"sha\":\"\",\"reason\":\"\"}"
  echo "$r" > "$ST/cards.jsonl"
  r=${r/picked/pushed}; jq -cn --arg ok "${r%\}},\"head\":\"cP\"}" '{line: 2, field: "head", time: "2026-11-02T00:00:00Z", record: $ok}' > "$ST/quarantined.jsonl"
  out=$(loop snapshot --fresh 2> "$T/$CASE/snap.err" | jq -c '.metrics.today.pushes.ok') && [ "$out" = 1 ] \
    || fail "the snapshot's push count of today is $out, not 1, with the push line it put back: $(cat "$T/$CASE/snap.err")"
  [ "$(jq -r .step "$ST/cards.jsonl" | tr '\n' ' ')" = 'picked pushed ' ] || fail "the push line is not back in the records: $(cat "$ST/cards.jsonl")"
}

# flocking <pid> <fd>: a process under <pid> waits on, or holds, `flock <fd>`.
flocking() {
  ps -A -ww -o pid=,ppid=,args= | awk -v r="$1" -v fd="$2" '{ p[NR] = $1; pp[NR] = $2; $1 = $2 = ""; a[NR] = $0 }
    END { t[r] = 1; do { n = 0; for (i = 1; i <= NR; i++) if ((pp[i] in t) && !(p[i] in t)) { t[p[i]] = 1; n = 1 } } while (n)
      for (i = 1; i <= NR; i++) if ((p[i] in t) && a[i] ~ ("^ *flock " fd " *$")) f = 1; exit !f }'
}

# Bug (#1791, review 2): two checks at once shared the put-back's files ($STATE.qkeep among them). What must stay true:
# a refused record stays in $QUARANTINE, whatever another check does. The other writer: a second `conveyor.sh check`,
# whose first pass removed and wrote those files with no lock. The first check is held at the weak point (it has split
# the set-aside records under the records' lock and waits for $STATE.checked.lock, which this test holds); the second
# then runs its first pass, made to fail by an ended list it cannot read, and waits for the same lock. The first then
# put back the accepted record and removed $QUARANTINE, as its list of those to keep was gone. Real processes, as only
# two checks at once show it.
t_recputbackrace() {
  local d=$T/$CASE a b
  setup '[]'
  printf '%s\n' "$(qrec 1)" "$(qrec 3)" > "$ST/cards.jsonl"
  jq -cn --arg ok "$(qrec 2)" --arg bad "$(qrec 4 ',"later":1')" '{line: 2, field: "rerun", time: "2026-11-02T00:00:00Z", record: $ok},
    {line: 3, field: "later", time: "2026-11-02T00:00:00Z", record: $bad}' > "$ST/quarantined.jsonl"
  ( flock 9 && : > "$d/held" && wait_until '[ -e "$d/go" ]' ) 9>>"$ST/cards.jsonl.checked.lock" &
  wait_until '[ -e "$d/held" ]' || fail "the test never took the lock on the checked file"
  (loop check > "$d/a.out" 2>&1; echo $? > "$d/a.rc") & a=$!
  wait_until "[ -s '$d/a.rc' ] || flocking $a 5" || { : > "$d/go"; wait; fail "the first check never waited for the checked file's lock"; }
  [ ! -s "$d/a.rc" ] || { : > "$d/go"; wait; fail "the first check ended while the checked file's lock was held: $(cat "$d/a.out")"; }
  mkdir -p "$ST/archive/ended.jsonl"
  (loop check > "$d/b.out" 2>&1; echo $? > "$d/b.rc") & b=$!
  wait_until "[ -s '$d/b.rc' ] || flocking $b 5" || { : > "$d/go"; wait; fail "the second check never waited for the checked file's lock"; }
  rmdir "$ST/archive/ended.jsonl"; : > "$d/go"; wait
  [ "$(cat "$d/a.rc")" = 0 ] || fail "the first check failed (exit $(cat "$d/a.rc")): $(cat "$d/a.out")"
  [ "$(jq -r .card "$ST/cards.jsonl" | tr '\n' ' ')" = 'c0-1 c0-2 c0-3 ' ] || fail "the accepted record is not back in the records at its time place: $(cat "$ST/cards.jsonl")"
  [ "$(jq -sc 'map(.record | fromjson | .card)' "$ST/quarantined.jsonl" 2>&1)" = '["c0-4"]' ] \
    || fail "the refused record is not kept in the quarantine after a second check ran beside the put-back: $(cat "$ST/quarantined.jsonl" 2>&1); second check: $(cat "$d/b.out")"
}

# Bug (#1791, review 2): the put-back's first pass wrote three files even when every set-aside record was still
# refused. With the state folder made read-only after a first check, a second check that has nothing to put back must
# still pass, with no complaint that it cannot test the records.
t_recputbackread() {
  local out rc
  setup '[]'
  printf '%s\n' "$(qrec 1)" > "$ST/cards.jsonl"
  jq -cn --arg bad "$(qrec 4 ',"later":1')" '{line: 2, field: "later", time: "2026-11-02T00:00:00Z", record: $bad}' > "$ST/quarantined.jsonl"
  out=$(loop check 2>&1) || fail "the first check failed: $out"
  chmod a-w "$ST"; out=$(loop check 2>&1); rc=$?; chmod u+w "$ST"
  [ $rc = 0 ] && [ -z "$out" ] || fail "a check with nothing to put back, in a read-only state folder, failed or wrote something (exit $rc): $out"
}

# Bug (#1791, review): what is set aside can change while the put-back waits for the records' lock (a quarantine()
# under that lock): a put-back that wrote $QUARANTINE from its read before the lock lost what was added. Another
# process holds the records' lock and adds an entry once the check's flock is seen waiting under it: a real process,
# as only two processes at once show what the waiting one reads. The entry added is put back too, and with none left,
# $QUARANTINE is removed.
t_recputbacklock() {
  local d=$T/$CASE
  setup '[]'
  printf '%s\n' "$(qrec 1)" "$(qrec 3)" > "$ST/cards.jsonl"
  jq -cn --arg ok "$(qrec 2)" '{line: 2, field: "rerun", time: "2026-11-02T00:00:00Z", record: $ok}' > "$ST/quarantined.jsonl"
  ( flock 9 && : > "$d/held" && wait_until '[ -e "$d/go" ]' && jq -cn --arg ok "$(qrec 4)" '{line: 3, field: "rerun", time: "2026-11-02T00:00:00Z", record: $ok}' >> "$ST/quarantined.jsonl" ) 9>>"$ST/cards.jsonl" &
  wait_until '[ -e "$d/held" ]' || fail "the other process never took the records' lock"
  (loop check > "$d/check.out" 2>&1; echo $? > "$d/check.rc") &
  # The check's flock on the records' lock, under the check, or the check's end.
  wait_until "[ -s '$d/check.rc' ] || flocking $! 9"
  [ ! -s "$d/check.rc" ] || { : > "$d/go"; wait; fail "the check ended while another process held the records' lock: $(cat "$d/check.out")"; }
  : > "$d/go"; wait
  [ "$(cat "$d/check.rc")" = 0 ] || fail "the check failed (exit $(cat "$d/check.rc")): $(cat "$d/check.out")"
  [ "$(jq -r .card "$ST/cards.jsonl" | tr '\n' ' ')" = 'c0-1 c0-2 c0-3 c0-4 ' ] || fail "the records do not hold both records put back, at their time place: $(cat "$ST/cards.jsonl")"
  [ ! -e "$ST/quarantined.jsonl" ] || fail "the quarantine file is left with nothing set aside: $(cat "$ST/quarantined.jsonl")"
}

# A card whose build session fails after changing a file: its blocked line, with its kept patch, the files it changed,
# the end of what the session said and what it spent, checks.
t_recblocked() {
  setup "[$(issue 7 2026-01-01)]"; echo 'echo two >> a.txt; echo "FAIL schema mismatch" >&2; exit 3' > "$STUB/build"
  loop run --only 7 1 > /dev/null 2>&1
  [ "$(st 'select(.issue == 7 and .step == "blocked") | [.kept != "", (.paths | length), (.tail | length > 0)] | tojson')" = '[true,1,true]' ] \
    || fail "the blocked line has no kept patch, files or tail, so they went unchecked: $(st 'select(.step == "blocked")')"
  recok "$ST/cards.jsonl" "a blocked card"
}

# A card whose first test run fails b.test's flaky, as does the run again, and main's run of it passes: its failed test
# line (card.sh's fail record) with its failures, the end of the run's output, each case's verdict and main's run,
# then its passing run after the fix, checks. Bug it catches: no case above wrote a failed test line, so a field only
# that writer adds (failures, tail, verdicts, mainRun) went unchecked.
t_recfailed() {
  rerunsetup '1 fail flaky' '2 fail flaky'; rerunfiles
  loop run 1 > "$STUB/run.out" 2>&1 || fail "run exited non-zero: $(cat "$STUB/run.out")"
  [ "$(st 'select(.step == "test" and .result == "fail") | [(.failures.files | length > 0), (.tail | length > 0), .verdicts[0].verdict, (.mainRun.sha | length > 0)] | tojson')" = '[true,true,"card",true]' ] \
    || fail "the failed test line has no failures, tail, verdicts or main's run, so they went unchecked: $(st 'select(.step == "test")')"
  recok "$ST/cards.jsonl" "a card whose test run failed"
}

# A card's test line when its change narrows the run (test.list args): its list is the changed tests, how many and by
# what. Written as card.sh writes a passing first run: testrec(), firstrun() and testlist.sh slowrec() of the run tests() made,
# through record(). Each call moves into main's checkout first, where the engine's load leaves the loop (lib/records.sh)
# and engine_once does not: speedproof() and closed() run git there with no -C.
t_reclist() {
  local wt=$T/$CASE/cards/c7
  setup '[]'
  mkdir -p "$R/lib" && echo x > "$R/lib/cartsum.js" && echo x > "$R/lib/cartsum.test.js" && git -C "$R" add -A && git -C "$R" commit -qm files || fail "main's files"
  printf '%s\n' 'echo "$*" > "$STUB/got"' > "$STUB/list-cmd"
  tune '.test.list = "args" | .test.command = "bash \"$STUB/list-cmd\""'
  git -C "$R" worktree add -q --detach "$wt" && echo y >> "$wt/lib/cartsum.js" && git -C "$wt" add -A || fail "the card's change could not be staged"
  wt=$wt engine_once 'cd "$CONVEYOR_MAIN" && tests "$wt" || exit 1
    record c7 7 test pass "$(jq -cn --argjson x "$(testrec "$wt" 0 1)" --argjson r "$(firstrun "$wt" pass)" --argjson s "$(slowrec "$wt")" "\$x + \$r + \$s")"' \
    > "$T/$CASE/run.out" 2>&1 || fail "the test step failed: $(cat "$T/$CASE/run.out")"
  [ "$(st 'select(.step == "test") | .list | tojson')" = '{"mode":"changed","files":1,"by":"name"}' ] || fail "the test line has no list of the changed tests: $(cat "$ST/cards.jsonl")"
  recok "$ST/cards.jsonl" "a card's narrowed test run"
}

# The writers no card above reaches, each called as the engine calls it, on one card whose change speeds up f.test.sh:
# its test line, whose list is its own changed test file (testrec()), the speed-up check's bugproof line with its speed
# (speedproof.sh speedproof(): 10 CPU s on record, 4 now), a push its pre-push hook refuses (push(): kind check, naming the check) and
# the closed line of a card main already fixes (closed()).
t_recother() {
  local wt=$T/$CASE/cards/c7 c
  setup '[]'
  echo slow > "$R/f.test.sh" && git -C "$R" add f.test.sh && git -C "$R" commit -qm 'a slow test' || fail "main's file"
  for c in 9 10 11; do
    jq -cn --argjson c "$c" '{time: "2026-11-01T00:00:00Z", how: "full", sha: "abc", files: {"f.test.sh": {result: "ok", sec: $c, cpu: $c}}}' >> "$ST/suiteruns.jsonl"
  done
  echo 'printf "TESTRUN sec\tf.test.sh\t1\t4\n" > "$CONVEYOR_TEST_LOG/r"' > "$STUB/mainrun-cmd"
  printf '%s\n' '#!/usr/bin/env bash' 'echo "push-checks: FAILED fast-checks" >&2; exit 1' > "$R/.git/hooks/pre-push" && chmod +x "$R/.git/hooks/pre-push"
  git -C "$R" worktree add -q --detach "$wt" && echo fast > "$wt/f.test.sh" && git -C "$wt" add -A || fail "the card's change could not be staged"
  wt=$wt engine_once 'cd "$CONVEYOR_MAIN" && tests "$wt" || exit 1
    record c7 7 test pass "$(jq -cn --argjson x "$(testrec "$wt" 0 1)" --argjson r "$(firstrun "$wt" pass)" --argjson s "$(slowrec "$wt")" "\$x + \$r + \$s")"
    speedproof c7 "$wt" "{\"number\":7}" f.test.sh || exit 1
    push c7 7; closed c7 7 "$wt" "ALREADY-DONE: f.test.sh is fast"' > "$T/$CASE/run.out" 2>&1 || fail "a writer failed: $(cat "$T/$CASE/run.out")"
  recsteps "the other writers" test bugproof push closed
  [ "$(st 'select(.step == "test") | .list | tojson')" = '{"mode":"changed","files":1,"by":"own"}' ] || fail "the test line's list is not the card's own test file: $(st 'select(.step == "test")')"
  [ "$(st 'select(.step == "bugproof") | .speed | tojson')" = '{"file":"f.test.sh","before":10,"after":4,"fix":"sped up","into":[]}' ] \
    || fail "the bugproof line has no speed with both CPU numbers: $(st 'select(.step == "bugproof")')"
  [ "$(st 'select(.step == "push") | [.result, .kind, .check] | join(" ")')" = 'fail check fast-checks' ] || fail "the push line has no kind and check: $(st 'select(.step == "push")')"
  recok "$ST/cards.jsonl" "the other writers"
}
