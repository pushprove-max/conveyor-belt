#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 120
# Engine cases: a red release run's fix cards (relfixes(), lib/fulltest.sh, issue 758): the issues that carry
# `Release fix: <version>` are recorded in the run's record, and release-prep starts again by itself once they have
# all landed, are in the commit release-prep tests and no card is open; so does a release-prep that waits on its notes
# card (t_relnoteslanded). Each case but t_relfixesserve calls relfixes() as the loop's job does. t_relfixesland's,
# t_relfixespr's and t_relnoteslanded's fixture is release.test.sh's relsetup, as their release-prep runs.
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"

# fixred: the record of a red release-prep of 1.1.0 that ended at 10:00 (RUN); fixcall: relfixes(), with the loop's
# libraries loaded; fixissue <number> <created hour> <OPEN|CLOSED> <body>: one issue as gh issue list gives it.
fixred() {
  RUN=$T/$CASE/cards/release/run.json
  mkdir -p "${RUN%/*}" && jq -cn '{kind: "release", step: "release-prep", version: "1.1.0", since: "2026-11-19T09:00:00Z", ended: "2026-11-19T10:00:00Z",
    state: "failed", sha: "abc", done: 2, failed: 1, cases: [], moved: false, reused: null, reasons: [], pid: 1, red: null, anyway: null, allowed: null}' > "$RUN" \
    || fail "the fixture could not be made"
}
fixcall() {
  ( export CONVEYOR_MAIN=$R CONVEYOR_CARDS=$T/$CASE/cards; . "$SRC/conveyor.sh" state-dir > /dev/null && eval "$(grep '^\. "\$HERE/lib/' "$SRC/commands/run.sh")" && names \
    && cd "$R" && relfixes ) > "$T/$CASE.fix" 2>&1 || fail "relfixes failed: $(cat "$T/$CASE.fix")"
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
# release, release-prep tests the head of conveyor/landing, which holds the fix: release-prep 1.1.0 runs there.
t_relfixespr() {
  relsetup ''
  fixred; tune '.push.landAs = "pr" | .push.prMerge = "button"'
  fixissue 20 11 CLOSED 'Release fix: 1.1.0' | jq -s . > "$STUB/fixes.json"
  printf '%s\n' '[ "$1 $2" != "issue list" ] || cat "$STUB/fixes.json"' >> "$STUB/gh"
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
