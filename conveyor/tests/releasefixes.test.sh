#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 120
# Engine cases: a red release run's fix cards (relfixes(), lib/fulltest.sh, issue 758): the issues that carry
# `Release fix: <version>` are recorded in the run's record, and release-prep starts again by itself once they have
# all landed, are in the commit release-prep tests and no card is open; so does a release-prep that waits on its notes
# card (t_relnoteslanded). Each case but t_relfixesserve, t_relstoprestarted (relstopwaiting()) and t_engineonce
# (fixcall's engine_once) calls relfixes() as
# the loop's job does. t_relfixesland's,
# t_relfixespr's and t_relnoteslanded's fixture is release.test.sh's relsetup, as their release-prep runs.
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"

# fixred: the record of a red release-prep of 1.1.0 that ended at 10:00 (RUN); fixcall: relfixes(), with the loop's
# libraries loaded once per case and pack (engine_once, lib.sh); fixissue <number> <created hour> <OPEN|CLOSED> <body>: one issue as gh issue list gives it.
fixred() {
  RUN=$T/$CASE/cards/release/run.json
  mkdir -p "${RUN%/*}" && jq -cn '{kind: "release", step: "release-prep", version: "1.1.0", since: "2026-11-19T09:00:00Z", ended: "2026-11-19T10:00:00Z",
    state: "failed", sha: "abc", done: 2, failed: 1, cases: [], moved: false, reused: null, reasons: [], pid: 1, red: null, anyway: null, allowed: null}' > "$RUN" \
    || fail "the fixture could not be made"
}
fixcall() {
  engine_once 'cd "$CONVEYOR_MAIN" && relfixes' > "$T/$CASE.fix" 2>&1 || fail "relfixes failed: $(cat "$T/$CASE.fix")"
}
fixissue() { jq -cn --argjson n "$1" --arg h "$2" --arg s "$3" --arg b "$4" '{number: $n, title: "fix \($n)", body: $b, createdAt: "2026-11-19T\($h):00:00Z", state: $s}'; }
fixrec() { jq -e "$2" "$RUN" > /dev/null || fail "$1: $(cat "$RUN")"; } # <what> <jq test of the record>
cardline() { jq -cn --argjson n "$1" --arg c "$2" --arg s "$3" '{card: $c, issue: $n, step: $s, time: "2026-11-19T12:00:00Z", tokens: {claude: 0, codex: 0}, result: "ok", sha: "", reason: ""}' >> "$ST/cards.jsonl"; }

# Bug (#758): after a red release run, nothing started the suite again once its fix cards had landed: the owner had to
# tell the Foreman. With one of two fixes landed, nothing starts; with both landed but one's commit not yet at origin
# (its push owed: release-prep tests origin's head), nothing starts; pushed, but a card open, nothing starts; with no
# card open, release-prep 1.1.0 runs, its record saying it started for the fixes. Each hold is the only one in its
# step. An issue filed before the run ended (#18, an earlier run's fix) and one of another version (#22, 1.1.01) are
# not its fixes.
t_relfixesland() {
  relsetup ''
  fixred
  { fixissue 18 08 CLOSED 'Release fix: 1.1.0'; fixissue 20 11 OPEN $'Fix a.test.\n\nRelease fix: 1.1.0'
    fixissue 21 11 OPEN $'Release fix: 1.1.0\r\nDepends on: #20'; fixissue 22 11 OPEN 'Release fix: 1.1.01'; } | jq -s . > "$STUB/fixes.json"
  printf '%s\n' '[ "$1 $2" != "issue list" ] || cat "$STUB/fixes.json"' >> "$STUB/gh"
  landed 20 | jq -c --arg s "$O" '.sha = $s' >> "$ST/cards.jsonl"
  fixcall
  fixrec "one fix of two landed: not recorded as such, or a run started" '.state == "failed" and .restarted == null and .fixes == [{issue: 20, state: "landed"}, {issue: 21, state: "open"}]'
  [ ! -e "${RUN%/*}/run.log" ] || fail "a run started with a fix still open: $(cat "${RUN%/*}/run.log")"
  landed 21 | jq -c --arg s "$(git -C "$R" rev-parse HEAD)" '.sha = $s' >> "$ST/cards.jsonl"
  fixcall
  fixrec "both fixes landed, one not yet pushed: a run started" '.state == "failed" and .restarted == null and (.fixes | map(.state)) == ["landed", "landed"]'
  [ ! -e "${RUN%/*}/run.log" ] || fail "a run started before a fix's commit was at origin: $(cat "${RUN%/*}/run.log")"
  git -C "$R" push -q origin main || fail "the fixture could not be pushed"
  cardline 23 c1-23 picked
  fixcall
  fixrec "both fixes landed and pushed, a card open: a run started" '.state == "failed" and .restarted == null'
  [ ! -e "${RUN%/*}/run.log" ] || fail "a run started while a card is open: $(cat "${RUN%/*}/run.log")"
  cardline 23 c1-23 landed
  fixcall
  grep -q 'release-prep 1.1.0 is running' "$T/$CASE.fix" || fail "release-run prep 1.1.0 did not start: $(cat "$T/$CASE.fix")"
  wait_until "jq -e '.since != \"2026-11-19T09:00:00Z\" and .ended != null' '$RUN' > /dev/null" || fail "the run did not end: $(cat "$RUN")"
  fixrec "the run is not release-prep 1.1.0 started for the fixes, or did not pass: $(cat "${RUN%/*}/run.log")" '.step == "release-prep" and .version == "1.1.0" and .state == "passed" and .by == "fixes landed"'
  [ -e "$STUB/full-at" ] || fail "the run did not run the suite"
}
# #1347 D6. Bug it catches: a fix card with no GitHub issue (rules.releaseissues off: `card --release`, a card of the
# record that the Tests page's cards use) was not read as a fix of the red run, so the suite never started again when it
# landed. Open, it is recorded as the fix, by its card id, and no run starts; landed and pushed, release-prep 1.1.0 runs.
t_relfixescard() {
  relsetup ''
  fixred
  # stub: relfixes() reads the issues through `gh issue list`, which the release fixture's gh does not answer; none is filed.
  printf '%s\n' '[ "$1 $2" != "issue list" ] || echo "[]"' >> "$STUB/gh"
  loop control rules releaseissues=off > /dev/null && loop card --release 1.1.0 'Fix a.test.sh' 'Make it pass.' > /dev/null 2>&1 || fail "the fix card with no issue was not started"
  local id; id=$(jq -r '.cards[0].id' "$ST/testactions/cards.json")
  fixcall
  fixrec "the open fix card $id with no issue is not recorded as the fix, or a run started" '.state == "failed" and .restarted == null and .fixes == [{issue: null, card: "'"$id"'", ids: ["'"$id"'"], state: "open"}]'
  [ ! -e "${RUN%/*}/run.log" ] || fail "a run started with the fix card $id still open: $(cat "${RUN%/*}/run.log")"
  git -C "$R" push -q origin main || fail "the fixture could not be pushed"
  jq -cn --arg c "$id" --arg s "$(git -C "$R" rev-parse HEAD)" '{card: $c, issue: 0, step: "landed", time: "2026-11-19T12:00:00Z", tokens: {claude: 0, codex: 0}, result: "ok", sha: $s, reason: ""}' >> "$ST/cards.jsonl"
  fixcall
  grep -q 'release-prep 1.1.0 is running' "$T/$CASE.fix" || fail "release-run prep 1.1.0 did not start when the fix card $id with no issue landed: $(cat "$T/$CASE.fix") $(cat "$RUN")"
  # wait_until: release-run prep runs as a process of its own after relfixes() returns; only its record shows that it ended and passed.
  wait_until "jq -e '.since != \"2026-11-19T09:00:00Z\" and .ended != null' '$RUN' > /dev/null" || fail "the run did not end: $(cat "$RUN")"
  fixrec "the run is not release-prep 1.1.0 started for the fix card, or did not pass" '.step == "release-prep" and .version == "1.1.0" and .state == "passed" and .by == "fixes landed"'
}
# R90. Bug it catches: `release` runs the suite when its commit has no passing status, and a failure there leaves step
# release, state failed, which relfixes() did not read, so Release fix cards for it never started the run again. With
# every fix card landed (and pushed) the run starts again as release-prep 1.1.0.
t_relfixesrelease() {
  relsetup ''
  fixred
  jq -c '.step = "release"' "$RUN" > "$RUN.new" && mv "$RUN.new" "$RUN" || fail "the fixture could not be made"
  # stub: relfixes() reads the issues through `gh issue list`, which the release fixture's gh does not answer; none is filed.
  printf '%s\n' '[ "$1 $2" != "issue list" ] || echo "[]"' >> "$STUB/gh"
  loop control rules releaseissues=off > /dev/null && loop card --release 1.1.0 'Fix a.test.sh' 'Make it pass.' > /dev/null 2>&1 || fail "the fix card was not started"
  local id; id=$(jq -r '.cards[0].id' "$ST/testactions/cards.json")
  git -C "$R" push -q origin main || fail "the fixture could not be pushed"
  jq -cn --arg c "$id" --arg s "$(git -C "$R" rev-parse HEAD)" '{card: $c, issue: 0, step: "landed", time: "2026-11-19T12:00:00Z", tokens: {claude: 0, codex: 0}, result: "ok", sha: $s, reason: ""}' >> "$ST/cards.jsonl"
  fixcall
  grep -q 'release-prep 1.1.0 is running' "$T/$CASE.fix" || fail "a failed release run with its fix card $id landed did not start release-prep 1.1.0: $(cat "$T/$CASE.fix") $(cat "$RUN")"
  # wait_until: release-run prep runs as a process of its own after relfixes() returns; only its record shows that it ended and passed.
  wait_until "jq -e '.since != \"2026-11-19T09:00:00Z\" and .ended != null' '$RUN' > /dev/null" || fail "the run did not end: $(cat "$RUN")"
  fixrec "the run is not release-prep 1.1.0 started for the fix card" '.step == "release-prep" and .version == "1.1.0" and .by == "fixes landed"'
}
# #1365. Bug it catches: a release run that started a notes card (relnotescard(), commands/release-prep.sh) waited on it
# for ever, or started again before it landed, or in another mode or with no release after it. The run was release-run
# 1.1.0 --serial on a head with no notes (so then release, mode serial: the run itself records both) and the control
# record's suite-mode is parallel: while the card is open nothing starts; once it has landed on origin's head (N, O and
# the card's commit of docs/releases/1.1.0.md), release-prep starts again in serial mode, runs the suite on N, and
# release follows its pass (it refuses here, main lacking N, but it runs).
t_relnoteslanded() {
  relsetup '' nonotes
  local id n=$T/$CASE/notes N
  RUN=$T/$CASE/cards/release/run.json
  relmodel $'# 1.1.0\n\nCards can wait. [#5]\n\n## Cards\n\n- You can hold a card. [#5]'
  loop control suite-mode parallel > /dev/null && loop release-run 1.1.0 --serial > /dev/null 2>&1 || fail "release-run 1.1.0 --serial did not start"
  # wait_until: release-run runs release-prep as a process of its own; only its record shows that it ended, and the
  # process (its pid) holds the release lock, which relfixes() needs, until it exits.
  wait_until "jq -e '.ended != null' '$RUN' > /dev/null && ! kill -0 \$(jq -r .pid '$RUN') 2>/dev/null" || fail "the first run did not end: $(cat "$RUN")"
  id=$(jq -r '.notes.card // ""' "$RUN")
  [ -n "$id" ] && jq -e --arg c "$id" '.cards | map(select(.id == $c)) | length == 1' "$ST/testactions/cards.json" > /dev/null \
    || fail "release-run 1.1.0 --serial on a head with no notes did not wait on a notes card it started: $(cat "$RUN" "${RUN%/*}/run.log")"
  fixcall
  fixrec "the open notes card $id is not recorded as the run's one fix, or a run started" '.state == "waiting" and .restarted == null and .fixes == [{issue: null, card: "'"$id"'", ids: ["'"$id"'"], state: "open"}]'
  [ ! -e "$STUB/full-at" ] || fail "the suite ran with the notes card $id still open"
  git clone -q "$T/$CASE/origin" "$n" && mkdir -p "$n/docs/releases" && cp "$ST/release/1.1.0.md" "$n/docs/releases/" && git -C "$n" add docs \
    && git -C "$n" commit -q -m "docs: Release notes 1.1.0" && git -C "$n" push -q origin main && N=$(git -C "$n" rev-parse HEAD) \
    || fail "the fixture could not be made"
  jq -cn --arg c "$id" --arg s "$N" '{card: $c, issue: 0, step: "landed", time: "2026-11-19T12:00:00Z", tokens: {claude: 0, codex: 0}, result: "ok", sha: $s, reason: ""}' >> "$ST/cards.jsonl"
  fixcall
  grep -q 'release-prep 1.1.0 is running, then release 1.1.0 once its suite passes' "$T/$CASE.fix" \
    || fail "release-run 1.1.0 did not start when the notes card $id landed: $(cat "$T/$CASE.fix") $(cat "$RUN")"
  # wait_until: release-run runs as a process of its own after relfixes() returns; only its record shows that release ran.
  wait_until "jq -e '.step == \"release\" and .ended != null' '$RUN' > /dev/null" || fail "release did not run after the suite: $(cat "$RUN") $(cat "${RUN%/*}/run.log")"
  fixrec "the suite did not run in the first run's serial mode on $N, started for the notes card" '.version == "1.1.0" and .mode == "serial" and .sha == "'"$N"'" and .by == "notes landed"'
  [ "$(cat "$STUB/full-at" 2>&1)" = "$N" ] || fail "the suite did not run on origin's head $N, which holds the notes: $(cat "$STUB/full-at" 2>&1)"
}
# #1347. Bug it catches: the Board's File on GitHub on a landed release fix card (cardissue()) copies its `Release fix:`
# line into a new issue that it closes at once; relfixes() read that issue as a second fix, closed with no landed card of
# its own, so the suite never started again after the fix landed.
t_relfixesfiled() {
  relsetup ''
  fixred
  fixissue 21 12 CLOSED $'Make it pass.\n\nRelease fix: 1.1.0' | jq -s . > "$STUB/fixes.json"
  printf '%s\n' '[ "$1 $2" != "issue list" ] || cat "$STUB/fixes.json"' >> "$STUB/gh" # stub: relfixes() reads the issues through `gh issue list`, which the release fixture's gh does not answer; none is filed.
  local id=c20261119T110000-main-0
  mkdir -p "$ST/testactions" && jq -cn --arg c "$id" '{cards: [{file: null, title: "Fix a.test.sh", body: "Make it pass.\n\nRelease fix: 1.1.0", time: "2026-11-19T11:00:00Z", id: $c, card: $c,
    filed: 21, filedUrl: "https://example.com/o/r/issues/21"}]}' > "$ST/testactions/cards.json" || fail "the card record could not be made"
  git -C "$R" push -q origin main || fail "the fixture could not be pushed"
  jq -cn --arg c "$id" --arg s "$(git -C "$R" rev-parse HEAD)" '{card: $c, issue: 0, step: "landed", time: "2026-11-19T12:00:00Z", tokens: {claude: 0, codex: 0}, result: "ok", sha: $s, reason: ""}' >> "$ST/cards.jsonl"
  fixcall
  grep -q 'release-prep 1.1.0 is running' "$T/$CASE.fix" || fail "release-run prep 1.1.0 did not start though the fix card $id landed and its issue #21 was filed from it: $(cat "$T/$CASE.fix") $(cat "$RUN")"
  # wait_until: release-run prep runs as a process of its own after relfixes() returns; only its record shows that it ended.
  wait_until "jq -e '.since != \"2026-11-19T09:00:00Z\" and .ended != null' '$RUN' > /dev/null" || fail "the run did not end: $(cat "$RUN")"
}
# #1347. Bug it catches: a release fix card with no GitHub issue that was given back (retried: its entry's was holds the first card,
# card the new one) and then shut by the owner showed as open, as relfixes() looked for the closed line of the oldest card, not of
# the current one; the Release panel never showed the closed fix that holds the run.
t_relfixesretried() {
  setup '[]'
  fixred
  mkdir -p "$ST/testactions" && jq -cn '{cards: [{file: null, title: "Fix a.test.sh", body: "Make it pass.\n\nRelease fix: 1.1.0", time: "2026-11-19T11:00:00Z",
    id: "c20261119T110000-main-0", card: "c20261119T113000-main-0", was: ["c20261119T110000-main-0"]}]}' > "$ST/testactions/cards.json" || fail "the card record could not be made"
  cardline 0 c20261119T110000-main-0 blocked
  cardline 0 c20261119T113000-main-0 closed
  fixcall
  fixrec "the retried fix card, shut after its retry, is not recorded as closed, or a run started" '.state == "failed" and .restarted == null and (.fixes | map(.state) == ["closed"])'
}
# Bug (#758): a fix closed with no landed card fixed nothing, so the suite must not start; the record names that fix.
# Landed fix #20's commit is main's head, at origin, so the closed fix is the only hold.
t_relfixesclosed() {
  setup "$( { fixissue 20 11 OPEN 'Release fix: 1.1.0'; fixissue 21 11 CLOSED 'Release fix: 1.1.0'; } | jq -s .)"
  fixred; landed 20 | jq -c --arg s "$(git -C "$R" rev-parse HEAD)" '.sha = $s' >> "$ST/cards.jsonl"
  fixcall
  fixrec "a fix closed with no landed card is not named, or a run started" '.state == "failed" and .restarted == null and .fixes == [{issue: 20, state: "landed"}, {issue: 21, state: "closed"}]'
  [ ! -e "${RUN%/*}/run.log" ] || fail "a run started over a fix closed with no landed card: $(cat "${RUN%/*}/run.log")"
}
# Bugs it catches (follow-up of #1461): the release lock held a moment (by a `release-run stop` that read the wait just
# before) refused the release-run relfixes() starts a waiting run with, and the record kept its restarted mark: the run
# never started, every stop skipped it, and it held every other version (relother(), lib/fulltest.sh) for ever. The
# mark is taken off, and a stop then ends the wait.
t_relnotesrefused() {
  setup '[]'
  local id=c20261119T110000-main-0 out rc f
  RUN=$T/$CASE/cards/release/run.json
  mkdir -p "${RUN%/*}" "$ST/testactions" && git -C "$R" push -q origin main \
    && jq -cn --arg c "$id" '{kind: "release", step: "release-prep", version: "1.1.0", since: "2026-11-19T09:00:00Z", ended: "2026-11-19T10:00:00Z",
      state: "waiting", sha: null, reasons: [], pid: 1, notes: {card: $c, then: "prep", mode: null, machine: null}}' > "$RUN" \
    && jq -cn --arg c "$id" '{cards: [{file: null, title: "Release notes 1.1.0: add docs/releases/1.1.0.md", body: "", time: "2026-11-19T10:00:00Z", id: $c, label: "Release notes"}]}' > "$ST/testactions/cards.json" \
    && jq -cn --arg c "$id" --arg s "$(git -C "$R" rev-parse HEAD)" '{card: $c, issue: 0, step: "landed", time: "2026-11-19T12:00:00Z", tokens: {claude: 0, codex: 0}, result: "ok", sha: $s, reason: ""}' >> "$ST/cards.jsonl" \
    && f=$(command -v flock) || fail "the fixture could not be made"
  # A flock that finds the lock held at a try (-n) once the record is marked restarted: the stop's moment, made certain.
  printf '%s\n' '#!/usr/bin/env bash' "[ \"\$1\" != -n ] || ! jq -e '.restarted | strings' '$RUN' > /dev/null 2>&1 || exit 1" "exec $f \"\$@\"" > "$STUB/flock" \
    && chmod +x "$STUB/flock" || fail "the flock stand-in could not be made"
  ( export CONVEYOR_MAIN=$R CONVEYOR_CARDS=$T/$CASE/cards; . "$SRC/conveyor.sh" state-dir > /dev/null && eval "$(grep '^\. "\$HERE/lib/' "$SRC/commands/run.sh")" && names \
    && cd "$R" && relfixes ) > "$T/$CASE.fix" 2>&1; rc=$?
  [ $rc != 0 ] && grep -q 'already running; this one is not started' "$T/$CASE.fix" || fail "relfixes(), its release-run refused at the lock, did not fail as refused (rc $rc): $(cat "$T/$CASE.fix")"
  fixrec "the restart refused at the lock left the record marked restarted, or not waiting on notes card $id" '.state == "waiting" and .restarted == null and .notes.card == "'"$id"'"'
  rm -f "$STUB/flock" || fail "the flock stand-in could not be removed"
  out=$(loop release-run stop 2>&1) || fail "release-run stop of the waiting run, its mark taken off, failed: $out"
  fixrec "release-run stop did not end the wait the refused restart left" '.state == "stopped" and .reasons == ["stopped by the owner"]'
}
# Bug (#758): a red run with no fix filed yet has, by "all its fixes landed", nothing that could have fixed it: no run.
t_relfixesnone() {
  setup '[]'
  fixred
  fixcall
  fixrec "a red run with no fixes: not recorded as none, or a run started" '.state == "failed" and .restarted == null and .fixes == []'
  [ ! -e "${RUN%/*}/run.log" ] || fail "a run started with no fix cards: $(cat "${RUN%/*}/run.log")"
}
# Bug (#758): with Land as pr, a fix's push goes to conveyor/landing; with Merge PR button, release-prep still tests
# origin's main, so a retry there would test the red commit again, without the fix: nothing starts. With Merge PR
# release, release-prep tests the head of conveyor/landing while a pull request from it is open (relhead(), #1533),
# and that head holds the fix: release-prep 1.1.0 runs there.
t_relfixespr() {
  relsetup ''
  fixred; tune '.push.landAs = "pr" | .push.prMerge = "button"'
  fixissue 20 11 CLOSED 'Release fix: 1.1.0' | jq -s . > "$STUB/fixes.json"
  local prs='[ "$1 $2" != "pr list" ] || echo "[{\"number\":9,\"url\":\"https://example.com/pr/9\",\"isCrossRepository\":false}]"'
  # stub: relfixes() reads the issues through `gh issue list`, and relhead() the open pull request from conveyor/landing through `gh pr list` (landingprs()): #9 is open, as the push of Land as pr opened it
  printf '%s\n' '[ "$1 $2" != "issue list" ] || cat "$STUB/fixes.json"' "$prs" >> "$STUB/gh"
  # The push of Land as pr, and its record as the loop writes it (lib/push.sh), which atorigin() takes as at origin.
  git -C "$R" push -q origin "HEAD:refs/heads/conveyor/landing" && echo "$(git -C "$R" rev-parse HEAD) origin conveyor/landing" > "$ST/pushed" \
    || fail "the fixture could not be pushed"
  landed 20 | jq -c --arg s "$(git -C "$R" rev-parse HEAD)" '.sha = $s' >> "$ST/cards.jsonl"
  fixcall
  fixrec "a fix in the open pull request, Merge PR button: a run started" '.state == "failed" and .restarted == null and .fixes == [{issue: 20, state: "landed"}]'
  [ ! -e "${RUN%/*}/run.log" ] || fail "a run started on origin's main without the fix: $(cat "${RUN%/*}/run.log")"
  tune '.push.prMerge = "release"'
  fixcall
  grep -q 'release-prep 1.1.0 is running' "$T/$CASE.fix" || fail "release-run prep 1.1.0 did not start with Merge PR release: $(cat "$T/$CASE.fix")"
  wait_until "jq -e '.since != \"2026-11-19T09:00:00Z\" and .ended != null' '$RUN' > /dev/null" || fail "the run did not end: $(cat "$RUN")"
  [ "$(cat "$STUB/full-at" 2>/dev/null)" = "$(git -C "$R" rev-parse HEAD)" ] || fail "the suite did not run on conveyor/landing's head: $(cat "${RUN%/*}/run.log")"
}
# Bug (#758): the cases above call relfixes() themselves, so a loop that never runs it starts no release-prep, and
# nothing above sees that. This one runs the real `serve` loop and polls the record, as only the loop's own turn
# shows that it runs relfixes(): the red run's record gets its fixes with no other call.
t_relfixesserve() {
  setup "[$(fixissue 20 11 CLOSED 'Release fix: 1.1.0')]"; tune '.tunables.idle = 1 | .tunables.poll = 1'
  fixred
  loop serve > "$STUB/serve.out" 2>&1 & fxpid=$!; trap 'kill $fxpid 2>/dev/null' EXIT
  wait_until "jq -e '.fixes == [{issue: 20, state: \"closed\"}]' '$RUN' > /dev/null" "cat '$STUB/serve.out'" \
    || fail "the serve loop did not record the red run's fixes: $(cat "$RUN")"
  kill $fxpid; wait $fxpid 2>/dev/null; return 0
}
# #1369. Bug it catches: a release-prep that waits on its notes card (state waiting) has ended, so `release-run stop` said
# "no release run is under way" and the card, once landed, started the suite and the release the owner meant to stop. Stop
# marks the waiting record stopped: relfixes() then starts nothing when the card lands, and a second stop is refused.
t_relnotesstop() {
  relsetup '' nonotes
  local id n=$T/$CASE/notes N out
  RUN=$T/$CASE/cards/release/run.json
  relmodel $'# 1.1.0\n\nCards can wait. [#5]\n\n## Cards\n\n- You can hold a card. [#5]'
  loop release-run 1.1.0 > /dev/null 2>&1 || fail "release-run 1.1.0 did not start"
  # wait_until: release-run runs release-prep as a process of its own; its record shows the end, and the process holds the release lock until it exits.
  wait_until "jq -e '.ended != null' '$RUN' > /dev/null && ! kill -0 \$(jq -r .pid '$RUN') 2>/dev/null" || fail "the run did not end: $(cat "$RUN")"
  id=$(jq -r '.notes.card // ""' "$RUN"); [ -n "$id" ] || fail "the run did not wait on a notes card: $(cat "$RUN")"
  out=$(loop release-run stop 2>&1) || fail "release-run stop of a run that waits on notes card $id failed: $out"
  fixrec "the stop did not mark the waiting run stopped" '.state == "stopped" and .ended != null and .reasons == ["stopped by the owner"]'
  # Bug it catches too: starting the stopped release again queued a second notes card for the same file; it waits on the first.
  loop release-run 1.1.0 > /dev/null 2>&1 || fail "release-run 1.1.0 did not start again after its stop"
  # wait_until: the stopped record also has an end, so the new run is told by its state waiting.
  wait_until "jq -e '.state == \"waiting\" and .ended != null' '$RUN' > /dev/null && ! kill -0 \$(jq -r .pid '$RUN') 2>/dev/null" || fail "the run did not end the second time: $(cat "$RUN")"
  [ "$(jq -r '.notes.card' "$RUN")" = "$id" ] && jq -e '.cards | length == 1' "$ST/testactions/cards.json" > /dev/null \
    || fail "the run after the stop did not wait on the first notes card $id: $(cat "$RUN") $(cat "$ST/testactions/cards.json")"
  loop release-run stop > /dev/null 2>&1 || fail "the second release-run stop failed"
  git clone -q "$T/$CASE/origin" "$n" && mkdir -p "$n/docs/releases" && cp "$ST/release/1.1.0.md" "$n/docs/releases/" && git -C "$n" add docs \
    && git -C "$n" commit -q -m "docs: Release notes 1.1.0" && git -C "$n" push -q origin main && N=$(git -C "$n" rev-parse HEAD) \
    || fail "the fixture could not be made"
  jq -cn --arg c "$id" --arg s "$N" '{card: $c, issue: 0, step: "landed", time: "2026-11-19T12:00:00Z", tokens: {claude: 0, codex: 0}, result: "ok", sha: $s, reason: ""}' >> "$ST/cards.jsonl"
  fixcall
  fixrec "the run started again after its stop, when notes card $id landed" '.state == "stopped" and .restarted == null'
  [ ! -e "$STUB/full-at" ] || fail "the suite ran after the stop, when notes card $id landed"
  out=$(loop release-run stop 2>&1); [ $? = 2 ] && grep -q 'no release run is under way' <<<"$out" || fail "a second stop was not refused: $out"
}
# R255. Bug it catches: relstopwaiting() read a waiting record, then took the release lock; when relfixes() started the
# run again before that (its record's restarted set), the stop's write left the record as it was, yet the stop said
# the run no longer waits and exited 0. flock is wrapped to set restarted as the stop takes the lock: the stop fails,
# says it stopped nothing, and the record keeps restarted, still waiting.
t_relstoprestarted() {
  setup '[]'; RUN=$T/$CASE/cards/release/run.json
  mkdir -p "${RUN%/*}" && jq -cn '{kind: "release", step: "release-prep", version: "1.1.0", since: "2026-11-19T09:00:00Z", ended: "2026-11-19T10:00:00Z",
    state: "waiting", restarted: null, reasons: [], notes: {card: "c-1", then: "prep", mode: null, machine: null}}' > "$RUN" || fail "the fixture could not be made"
  fx_in 'RELRUN=$CARDS/release/run.json; flock() { jq -c ".restarted = \"2026-11-19T11:00:00Z\"" "$RELRUN" > "$RELRUN.x" && mv "$RELRUN.x" "$RELRUN"; command flock "$@"; }; relstopwaiting'
  [ "$RC" = 1 ] && grep -q 'no longer waits on notes card c-1 (it started again, or another run began); nothing stopped' "$T/$CASE/run.out" \
    || fail "the stop of a run started again as it took the lock did not fail saying it stopped nothing ($RC): $(cat "$T/$CASE/run.out")"
  fixrec "the stop changed the record of the run started again" '.state == "waiting" and .restarted == "2026-11-19T11:00:00Z" and .reasons == []'
}
# Bug it catches: relfixes() read the red record, then the issues (gh issue list, up to 60 s), and only then took the
# release lock; a `release-run stop` in that time set waitStopped and said the run no longer waits, yet the locked
# check did not look at waitStopped, so relfixes() set restarted and started release-prep. The gh stub's issue list
# runs the real stop at that point (list-cmd); the only fix has landed and is pushed, so without the stop it would start.
t_relfixesstopped() {
  setup "$(fixissue 20 11 CLOSED 'Release fix: 1.1.0' | jq -s .)"
  fixred; landed 20 | jq -c --arg s "$(git -C "$R" rev-parse HEAD)" '.sha = $s' >> "$ST/cards.jsonl"
  printf 'CONVEYOR_MAIN=%q CONVEYOR_CARDS=%q bash %q release-run stop > "$STUB/stop.out" 2>&1; echo $? > "$STUB/stop.rc"\n' \
    "$R" "$T/$CASE/cards" "$SRC/conveyor.sh" > "$STUB/list-cmd"
  fixcall
  [ "$(cat "$STUB/stop.rc" 2>/dev/null)" = 0 ] || fail "release-run stop, run as relfixes() read the issues, did not stop the red run's wait: $(cat "$STUB/stop.out" 2>/dev/null)"
  fixrec "relfixes() marked the red run restarted after release-run stop ended its wait, as it read the issues" '.state == "failed" and .waitStopped != null and .restarted == null'
  ! grep -q 'starts again' "$T/$CASE.fix" || fail "relfixes() started release-prep 1.1.0 after release-run stop reported success: $(cat "$T/$CASE.fix")"
  [ ! -e "${RUN%/*}/run.log" ] || fail "a run started after release-run stop ended the wait: $(cat "${RUN%/*}/run.log")"
}
# engine_once (lib.sh), which fixcall runs relfixes() in. Bugs it catches: a load per call (each fixcall paid a whole
# engine load again), whether it starts conveyor.sh again or only sources the libraries of commands/run.sh again; a
# call after a pack change run in the load of the pack before (the engine reads the pack as it loads); a call run with
# the first caller's environment or folder (a variable one call set, such as CONVEYOR_NOW, seen by the next, which did
# not set it); a call without the case's test slot or trace descriptor (CONVEYOR_TEST_SLOT, BASH_XTRACEFD: its tests()
# waited for another slot, and the coverage log lost its lines). The loads are counted by a scratch engine folder
# whose conveyor.sh notes each start and then sources the real one, and whose commands/run.sh (the real one, with the
# other commands linked) has one more library line that notes each time the libraries are sourced.
t_engineonce() {
  local e=$T/$CASE/engine-src out rc c f sl tf=${COVERAGE_LOG:-}
  setup '[]'
  mkdir -p "$e/commands" "$R/sub" && for f in "$SRC"/commands/*; do ln -s "$f" "$e/commands/${f##*/}" || break; done \
    && rm "$e/commands/run.sh" && printf '. "$HERE/lib/portable.sh" && echo lib >> %q\n' "$T/$CASE/libs" | cat "$SRC/commands/run.sh" - > "$e/commands/run.sh" \
    && printf 'echo load >> %q\n. %q "$@"\n' "$T/$CASE/loads" "$SRC/conveyor.sh" > "$e/conveyor.sh" || fail "the scratch engine could not be made"
  local SRC=$e
  # The case's own slot and trace descriptors, as the runner and a coverage run give them; the coverage log's own when
  # it traces this case.
  exec {sl}>> "$T/$CASE/slot" || fail "the slot file could not be opened"
  [ -n "${BASH_XTRACEFD:-}" ] && [ -n "$tf" ] || { tf=$T/$CASE/trace; exec {BASH_XTRACEFD}>> "$tf"; } || fail "the trace file could not be opened"
  printf -v c 'echo "${X-unset} $PWD"; [ /dev/fd/%s -ef %q ] || echo "no slot"; [ /dev/fd/"$BASH_XTRACEFD" -ef %q ] || echo "no trace"' "$sl" "$T/$CASE/slot" "$tf"
  out=$(X=one CONVEYOR_TEST_SLOT=$sl.t engine_once "$c") && [ "$out" = "one $T/$CASE" ] \
    || fail "the first call (X=one, in $T/$CASE, slot descriptor $sl, trace descriptor $BASH_XTRACEFD) printed: $out"
  out=$(cd "$R/sub" && engine_once 'echo "${X-unset} $PWD"; echo err >&2; exit 3' 2>&1); rc=$?
  [ "$rc" = 3 ] && [ "$out" = "unset $R/sub"$'\n'err ] || fail "the second call (no X, in $R/sub, exit 3) ended $rc and printed: $out"
  [ "$(cat "$T/$CASE/loads" "$T/$CASE/libs" | tr '\n' ' ')" = 'load lib ' ] \
    || fail "two calls on one pack started conveyor.sh $(grep -c . "$T/$CASE/loads") times and sourced the libraries $(grep -c . "$T/$CASE/libs") times"
  tune '.tunables.idle = 7'
  out=$(engine_once 'packget tunables.idle i && echo "$i"') && [ "$out" = 7 ] || fail "the call after the pack set tunables.idle to 7 read: $out"
  [ "$(cat "$T/$CASE/loads" "$T/$CASE/libs" | tr '\n' ' ')" = 'load load lib lib ' ] \
    || fail "the call after a pack change started conveyor.sh $(grep -c . "$T/$CASE/loads") times and sourced the libraries $(grep -c . "$T/$CASE/libs") times in all, not twice each"
}
