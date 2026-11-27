#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 120
# Engine cases: the release limit on the pick (rellimit(), lib/pick.sh). While a release run is under way, or a red one
# waits on an open fix card (its record's fixes, relfixes(), lib/fulltest.sh), pick() takes only that release's fix
# issues and fix cards, their review follow-ups and a main-red fix card; `release-run stop` (relstopwaiting()) ends it.
# Each case calls pick() as the loop's turn does, under the records' lock, or the turn's pick itself (turnpick(): the
# same-file check, then the pick). The record's fixes are never written ahead: the pick reads them itself.
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"

# rlrun <jq changes>: the record of release-prep 1.1.0, red, ended at 10:00, with the changes made to it (RUN).
rlrun() {
  RUN=$T/$CASE/cards/release/run.json
  mkdir -p "${RUN%/*}" && jq -n '{kind: "release", step: "release-prep", version: "1.1.0", since: "2026-11-19T09:00:00Z", ended: "2026-11-19T10:00:00Z",
    state: "failed", restarted: null, sha: "abc", pid: 1, reasons: []} | '"$1" > "$RUN" || fail "the fixture could not be made"
}
# rlfix <number> <OPEN|CLOSED>: a fix issue of release 1.1.0, filed after its run ended, as gh gives it.
rlfix() { issue "$1" 2026-11-19T11:00:00Z P1 | jq -c --arg s "$2" '.body = "Fix it.\n\nRelease fix: 1.1.0" | .state = $s'; }
# rlpick: one pick, as the loop's turn asks it, of the open issues of the stub; prints the number of the issue it took
# (0 for a card with no issue) and its card id, or nothing. A pick that fails fails the case. Its log lines are in $T/$CASE/run.out.
# RLPRE, when the case sets it: shell run first in the pick's shell (the loop's tunables, as IDLE).
rlpick() {
  fx_in "${RLPRE:-}"'cd "$R" && locked pick "" "" "$(jq -c "map(select(.state != \"CLOSED\"))" "$STUB/issues.json")"'
  [ "$RC" = 0 ] || fail "the pick failed (exit $RC): $(cat "$T/$CASE/run.out")"
  sed -n 's/^\(c[0-9]\{8\}T[0-9]\{6\}-[^ ]*\) \([0-9]*\) .*/\2 \1/p' "$T/$CASE/run.out"
}
# rlline <issue> <card> <step>: a line of the card records (a landed one with its commit, as the records' check needs).
rlline() { jq -cn --argjson n "$1" --arg c "$2" --arg s "$3" '{card: $c, issue: $n, step: $s, time: "2026-11-19T12:00:00Z", tokens: {claude: 0, codex: 0}, result: "ok", sha: "", reason: ""}
  + if $s == "landed" then {sha: "abc", product: false} else {} end' >> "$ST/cards.jsonl"; }

# Bug: while a red release waited on its fix issue #21, the pick took the oldest queued issue (#5), and the next one
# (#31, a review follow-up of #41, a card of no release), so the fix waited behind the queue. Also when the record had
# no fixes yet (only `serve` read them, in a job beside the pick), and when the landed fix #20's record, which names its
# follow-up #30, had gone to the ended list. #30 and #31 are review follow-ups as followups() files them (the follow-up
# label, and a body that starts "Follow-up to #<n> (Conveyor card "): a limit that let in no issue with that label
# would leave #30 out. The pick takes #30 (a follow-up goes first), then #21, then nothing. `release-run stop` ends the
# wait and the limit: the next pick takes #31, then #5, and the log says why at each change.
t_rellimitissues() {
  setup "$(jq -cs . <(issue 5 2026-01-01 P1) <(issue 31 2026-01-02 P1) <(rlfix 21 OPEN) <(issue 30 2026-11-19T12:00:00Z P1) <(rlfix 20 CLOSED))"
  mkdir -p "$ST/archive" && landed 20 '[30]' >> "$ST/archive/ended.jsonl"; landed 41 '[31]' >> "$ST/cards.jsonl"
  local got n out fu
  fx_in 'printf "%s\n" "$FOLLOWUP"'; fu=$(cat "$T/$CASE/run.out")
  jq -c --arg fu "$fu" 'map(if .number | IN(30, 31) then (if .number == 30 then 20 else 41 end) as $p
    | .labels += [{name: $fu}] | .body = "Follow-up to #\($p) (Conveyor card c0-\($p)). The last review of that card said NO-GO." else . end)' "$STUB/issues.json" > "$STUB/issues.new" \
    && mv "$STUB/issues.new" "$STUB/issues.json" || fail "the fixture could not be made"
  rlrun .
  for n in 30 21 ''; do
    got=$(rlpick) || exit 1; [ "${got%% *}" = "$n" ] || fail "release 1.1.0 waits on fix #21: the pick took '${got%% *}', not '$n': $(cat "$T/$CASE/run.out")"
  done
  out=$(loop release-run stop 2>&1) && grep -q 'no longer waits on its fix cards' <<<"$out" && jq -e '.state == "failed" and (.waitStopped | type) == "string"' "$RUN" > /dev/null \
    || fail "release-run stop did not end the wait on the fix cards: $out: $(cat "$RUN")"
  got=$(rlpick) || exit 1; [ "${got%% *}" = 31 ] || fail "with release 1.1.0's wait stopped, the pick took '${got%% *}', not #31: $(cat "$T/$CASE/run.out")"
  grep -q 'the release limit is off: release-prep 1.1.0 failed, and its wait on its fix cards was stopped' "$T/$CASE/run.out" || fail "the log did not say why the limit is off: $(cat "$T/$CASE/run.out")"
  got=$(rlpick) || exit 1; [ "${got%% *}" = 5 ] || fail "with release 1.1.0's wait stopped, the pick took '${got%% *}', not #5: $(cat "$T/$CASE/run.out")"
}

# Bug: between the release-prep and the release of one `release-run`, the record says release-prep passed and ended,
# and release has not written its start, but the run still holds the release hold (relhold(), lib/push.sh): a free
# turn read the limit as off and took the queued #7. The hold is taken here as relhold() takes it. While it is held, the
# pick takes nothing and the log says why; once the run lets it go, the pick takes #7.
t_rellimitheld() {
  setup "[$(issue 7 2026-01-01)]"
  rlrun '.state = "passed"'
  local hold h got
  fx_in 'printf "%s\n" "$RELHOLD"'; hold=$(cat "$T/$CASE/run.out")
  { exec {h}>>"$hold"; } && flock -x "$h" || fail "the release hold $hold could not be taken"
  got=$(rlpick) || exit 1
  [ -z "$got" ] && grep -q 'the release limit is on: a release run holds the release hold (release-prep 1.1.0 passed' "$T/$CASE/run.out" \
    || fail "with release-prep 1.1.0 passed and its release-run's hold held, the pick took '$got', or the log did not say why: $(cat "$T/$CASE/run.out")"
  exec {h}>&-
  got=$(rlpick) || exit 1; [ "${got%% *}" = 7 ] || fail "with the release hold let go, the pick did not take #7: $(cat "$T/$CASE/run.out")"
}

# Bug: the record's fixes (the last `relfixes record`) named #21 and #22 open; the owner then took the line
# `Release fix: 1.1.0` out of #21. #22 kept the limit on, and the record's old list still let #21 start first. The
# record is read within IDLE, so it is not read again: the pick takes #22, then nothing.
t_rellimitunfix() {
  setup "$(jq -cs . <(issue 5 2026-01-01 P1) <(rlfix 21 OPEN | jq -c '.body = "Fix it."') <(rlfix 22 OPEN))"
  rlrun ".fixes = [{issue: 21, state: \"open\"}, {issue: 22, state: \"open\"}] | .fixesRead = $(date +%s)"
  local got n RLPRE='IDLE=3600; '
  for n in 22 ''; do
    got=$(rlpick) || exit 1; [ "${got%% *}" = "$n" ] || fail "#21 no longer says Release fix: 1.1.0, and #22 does: the pick took '${got%% *}', not '$n': $(cat "$T/$CASE/run.out")"
  done
}

# Bug: the release's only open fix, #21, has a GitHub sub-issue, #22, with no `Release fix:` line of its own. upnext()
# never takes a parent, and the limit did not let its part in: the queue held, and nothing fixed the release. The pick
# takes #22, then nothing.
t_rellimitparts() {
  setup "$(jq -cs . <(issue 5 2026-01-01 P1) <(rlfix 21 OPEN | jq -c '.parts = [{number: 22}]') <(issue 22 2026-11-19T11:30:00Z P1 | jq -c '.umbrella = 21'))"
  rlrun .
  local got n
  for n in 22 ''; do
    got=$(rlpick) || exit 1; [ "${got%% *}" = "$n" ] || fail "release 1.1.0 waits on fix #21, whose sub-issue is #22: the pick took '${got%% *}', not '$n': $(cat "$T/$CASE/run.out")"
  done
}

# Bug: the same, for cards with no GitHub issue (rules.releaseissues false): a review follow-up of another card (the
# oldest queued card) was taken ahead of the release's open fix card, and so was an ordinary card (no follow-up label)
# whose Depends on: names the release's landed fix card. The pick takes the fix card, then the review follow-up of the
# release's landed fix card (its Depends on: names that card), then nothing: neither of those cards nor #5.
t_rellimitcards() {
  setup "[$(issue 5 2026-01-01 P1)]"
  local x1=c20261119T090000-p-0 y1=c20261119T100100-p-0 z=c20261119T100000-p-0 a=c20261119T110000-p-0 x2=c20261119T110100-p-0 b=c20261119T110200-p-0 o=c20261119T110300-p-0 fu got n
  fx_in 'printf "%s\n" "$FOLLOWUP"'; fu=$(cat "$T/$CASE/run.out")
  mkdir -p "$ST/testactions" && jq -n --arg x1 "$x1" --arg y1 "$y1" --arg z "$z" --arg a "$a" --arg x2 "$x2" --arg b "$b" --arg o "$o" --arg fu "$fu" \
    'def e($id; $t; $body; $l): {file: null, label: $t, labels: $l, parent: null, title: $t, body: $body, time: "2026-11-19T11:00:00Z", id: $id, card: null, held: false};
    {cards: [e($a; "follow-up of another card"; "Fix it.\nDepends on: \($z)"; [$fu]), e($o; "ordinary card"; "Do it.\nDepends on: \($y1)"; []),
      e($x2; "fix b"; "Fix b.\n\nRelease fix: 1.1.0"; []), e($b; "follow-up of fix a"; "Fix it.\nDepends on: \($y1)"; [$fu]),
      (e($x1; "fix a"; "Fix a.\n\nRelease fix: 1.1.0"; []) | .card = $y1)]}' > "$ST/testactions/cards.json" \
    || fail "the fixture could not be made"
  rlline 0 "$z" picked; rlline 0 "$z" landed; rlline 0 "$y1" picked; rlline 0 "$y1" landed
  rlrun .
  for n in "0 $x2" "0 $b" ''; do
    got=$(rlpick) || exit 1; [ "$got" = "$n" ] || fail "release 1.1.0 waits on fix card $x2: the pick took '$got', not '$n': $(cat "$T/$CASE/run.out")"
  done
}

# Bug: the same-file check judged the oldest queued issue, #5, found no clash and stopped; the release limit then
# dropped #5 and the pick started fix #21 unchecked beside #1's card on the belt. And when the check judged #21 and
# `release-run stop` ended the wait while the model answered, the pick read the limit again and started #5, which the
# check never judged. The turn's pick (turnpick(), as run() runs it, cardrun() stubbed to say what it was given: the
# card's run is not under test) judges #21; the stop comes in the model's answer, NONE; the turn starts nothing. The
# next turn judges #5, then starts it.
t_rellimitturn() {
  setup "$(jq -cs . <(issue 1 2026-01-01 P1) <(issue 5 2026-01-02 P1) <(rlfix 21 OPEN))"
  rlline 1 c1-1 picked
  rlrun .
  export CONVEYOR_OVERLAP_CMD='p=$(cat); n=$(sed -n "/^# The queued issue$/{n;p;q}" <<<"$p" | grep -oE "^#[0-9]+"); echo "$n" >> "$STUB/judged"
    [ "$n" != "#21" ] || bash "'"$SRC"'/conveyor.sh" release-run stop >> "$STUB/stop.out" 2>&1; echo NONE'
  fx_in 'cd "$R" && declare -A mine=() ranon=(); cardrun() { echo "started $2"; }
    asking=1 urgent= red= building=1 cap=3 left=-1 pct= running=0 serve=1 pusher= started=0 ctl=$(ctl) issues=$(cat "$STUB/issues.json")
    for t in 1 2; do waits= picked=; turnpick || :; wait; echo "turn $t: waits=$waits"; done'
  [ "$(tr '\n' ' ' < "$STUB/judged" 2>/dev/null)" = '#21 #5 ' ] && jq -e '(.waitStopped | type) == "string"' "$RUN" > /dev/null \
    || fail "with release 1.1.0 waiting on #21, #1 on the belt and the wait stopped during the check, the checks (exit $RC) judged '$(cat "$STUB/judged" 2>/dev/null)', not #21 then #5, or the stop failed: $(cat "$STUB/stop.out" "$T/$CASE/run.out")"
  [ "$(grep -E '^(started|turn) ' "$T/$CASE/run.out" | tr '\n' ' ')" = 'turn 1: waits=1 started 5 turn 2: waits= ' ] && [ -z "$(st 'select(.issue == 21) | .card')" ] \
    || fail "after the limit changed during the check of #21, the turn did not start nothing, then #5 once checked: $(cat "$T/$CASE/run.out")"
}

# Bug: while release-prep ran, the pick took the queued #7. A main-red fix card is still taken; then nothing, and the
# log says the run is under way. So did the dry pick (`pick --dry`): it printed #7 while the pick took none. And once
# the suite passed, release-prep wrote its end before it made the coverage map (coverage: "running"), and the pick took
# #7 while the map was made. Once the release is out, the dry pick and the next pick take #7.
t_rellimitred() {
  setup "[$(issue 7 2026-01-01)]"
  local s got
  ( exec -a "bash conveyor.sh release-run 1.1.0" sleep 60 ) & FAKE=$! # sleep: the stand-in run under way, ended at the case's end
  rlrun '.ended = null | .state = "running" | .pid = '"$FAKE"
  s=$(git -C "$R" rev-parse HEAD)
  fx_in 'cd "$R" && mainred c1 "a.test: one" a.test '"$s"
  got=$(rlpick) || exit 1; [ "${got%% *}" = 0 ] && [ "$(st "select(.card == \"${got#* }\") | .title")" = "Main is red: a.test: one" ] \
    || fail "with release-prep 1.1.0 running, the main-red fix card was not picked: $(cat "$T/$CASE/run.out")"
  got=$(rlpick) || exit 1; [ -z "$got" ] && grep -q 'the release limit is on: release-prep 1.1.0 is under way' "$T/$CASE/run.out" \
    || fail "with release-prep 1.1.0 running, the pick took '$got', or the log did not say why: $(cat "$T/$CASE/run.out")"
  got=$(loop pick --dry --issues "$STUB/issues.json" --state "$ST" 2>&1) && [ -z "$got" ] \
    || fail "with release-prep 1.1.0 running, the dry pick failed or printed '$got', not nothing"
  rlrun '.state = "passed" | .ended = "2026-11-19T11:00:00Z" | .coverage = "running" | .pid = '"$FAKE"
  got=$(rlpick) || exit 1; [ -z "$got" ] || fail "with release-prep 1.1.0 making its coverage map, the pick took '$got': $(cat "$T/$CASE/run.out")"
  rlrun '.step = "release" | .state = "passed" | .ended = "2026-11-19T11:00:00Z" | .pid = '"$FAKE"
  got=$(loop pick --dry --issues "$STUB/issues.json" --state "$ST" 2>&1) && [ "$got" = 7 ] || fail "with release 1.1.0 out, the dry pick printed '$got', not 7"
  got=$(rlpick) || exit 1; kill "$FAKE" 2>/dev/null
  [ "${got%% *}" = 7 ] || fail "with release 1.1.0 out, the pick did not take #7: $(cat "$T/$CASE/run.out")"
}

# Bug: a release record that does not read held the queue. The pick takes #5, and the log says the limit is off and why.
t_rellimitunread() {
  setup "[$(issue 5 2026-01-01 P1)]"
  mkdir -p "$T/$CASE/cards/release" && echo 'not json' > "$T/$CASE/cards/release/run.json"
  local got; got=$(rlpick) || exit 1
  [ "${got%% *}" = 5 ] && grep -q 'the release limit is off: the release record .* could not be read' "$T/$CASE/run.out" \
    || fail "with a release record that does not read, the pick did not take #5, or the log did not say why: $(cat "$T/$CASE/run.out")"
}

# rlcards <card>...: the Tests page's cards (testactions/cards.json), in that order, each given as
# "<id>|<title>|<body, \n for a new line>|<card or ''>|<time>".
rlcards() {
  mkdir -p "$ST/testactions" && printf '%s\n' "$@" | jq -Rn '{cards: [inputs | split("|") | {file: null, label: .[1], labels: [], parent: null, title: .[1],
    body: (.[2] | gsub("\\\\n"; "\n")), time: .[4], id: .[0], card: (if .[3] == "" then null else .[3] end), held: false}]}' > "$ST/testactions/cards.json" \
    || fail "the fixture could not be made"
}

# Bug: the loop's background read (relfixes()) had just written no fixes for the red release (fixesRead, within the
# loop's IDLE seconds), so a fix card (`conveyor.sh card --release`) and a fix issue filed after that read left the limit
# off until the next read: the pick took the older card of no release, then #5. The pick reads them now: it takes the
# fix card, then #21, then nothing.
t_rellimitfresh() {
  setup "$(jq -cs . <(issue 5 2026-01-01 P1) <(rlfix 21 OPEN))"
  rlcards 'c20261119T100000-p-0|another card|Do it.||2026-11-19T09:30:00Z' 'c20261119T110000-p-0|fix a|Fix a.\n\nRelease fix: 1.1.0||2026-11-19T11:00:00Z'
  rlrun ".fixes = [] | .fixesRead = $(date +%s)"
  local got n RLPRE='IDLE=3600; '
  for n in '0 c20261119T110000-p-0' 21 ''; do
    got=$(rlpick) || exit 1; [ "$(if [ "${n%% *}" = 0 ]; then echo "$got"; else echo "${got%% *}"; fi)" = "$n" ] \
      || fail "release 1.1.0's fixes were read with none open just before fix card c20261119T110000-p-0 and #21 were filed: the pick took '$got', not '$n': $(cat "$T/$CASE/run.out")"
  done
}

# Bug: the landing of the release's only fix card (no GitHub issue) had gone to the ended list, so the fix list read it
# as open again: the limit held #5 for ever, as the pick never took the landed card again. The pick takes #5, and the
# record's fixes say the card landed.
t_rellimitarchived() {
  setup "[$(issue 5 2026-01-01 P1)]"
  rlcards 'c20261119T110000-p-0|fix a|Release fix: 1.1.0|c20261119T110100-p-0|2026-11-19T11:00:00Z'
  mkdir -p "$ST/archive" && jq -cn '{card: "c20261119T110100-p-0", issue: 0, step: "landed", time: "2026-11-19T12:00:00Z", tokens: {claude: 0, codex: 0},
    result: "ok", sha: "abc", reason: "", product: false}' >> "$ST/archive/ended.jsonl"
  rlrun .
  local got; got=$(rlpick) || exit 1
  [ "${got%% *}" = 5 ] && jq -e '.fixes == [{issue: null, card: "c20261119T110000-p-0", ids: ["c20261119T110000-p-0", "c20261119T110100-p-0"], state: "landed"}]' "$RUN" > /dev/null \
    || fail "with release 1.1.0's only fix card landed and its lines in the ended list, the pick took '$got', not #5, or the fixes are wrong: $(cat "$RUN" "$T/$CASE/run.out")"
}

# Bug: `release-run stop` refused a red release whose fix #21 was filed but not yet read into its record: "no release
# run is under way". The stop ends the wait, and the pick takes #5.
t_rellimitstop() {
  setup "$(jq -cs . <(issue 5 2026-01-01 P1) <(rlfix 21 OPEN))"
  rlrun .
  local out got
  out=$(loop release-run stop 2>&1) && jq -e '.state == "failed" and (.waitStopped | type) == "string" and (.fixes == null)' "$RUN" > /dev/null \
    || fail "release-run stop did not stop red release 1.1.0 before its fixes were read: $out: $(cat "$RUN")"
  got=$(rlpick) || exit 1; [ "${got%% *}" = 5 ] || fail "with release 1.1.0 stopped, the pick did not take #5: $(cat "$T/$CASE/run.out")"
}

# Bug (#1711): while release 1.1.0 waited on its fix #21, the pick left #5 alone, but the snapshot listed #5 as queued
# with no reason, so the Board, /units and `foreman status` did not say why it was not built. The snapshot gives #5
# release "1.1.0" in order and next (#21, the release's own fix, none), and `foreman status` says it waits for the
# release. Once `release-run stop` ends the wait, no issue has release, and the status no longer says so.
t_rellimitsnap() {
  setup "$(jq -cs . <(issue 5 2026-01-01 P1) <(rlfix 21 OPEN))"
  rlrun .
  local snap=$T/$CASE/snap.json got out state
  mkdir -p "$T/$CASE/xdg/conveyor" && jq -n --arg m "$R" '{records: [{repo: "alpha", main: $m}]}' > "$T/$CASE/xdg/conveyor/host.json" || fail "the host file could not be written"
  for state in waiting stopped; do
    if [ "$state" = stopped ]; then out=$(loop release-run stop 2>&1) || fail "release-run stop failed: $out"; fi
    loop snapshot --fresh > "$snap" || fail "the snapshot failed with release 1.1.0 $state"
    got=$(jq -c '[.queue.order, .queue.next] | map(map([.issue, .release]) | sort)' "$snap")
    out=$(XDG_CONFIG_HOME=$T/$CASE/xdg CONVEYOR_FOREMAN_DIR=$T/$CASE/foreman CONVEYOR_FOREMAN_ASK="cat $snap" CONVEYOR_MAIN=$R bash "$SRC/foreman/watch-conveyor.sh" --status 2>&1)
    if [ "$state" = waiting ]; then
      [ "$got" = '[[[5,"1.1.0"],[21,null]],[[5,"1.1.0"],[21,null]]]' ] || fail "release 1.1.0 waits on fix #21: the snapshot's queue (order, next) does not say #5 alone waits for it: $got"
      grep -qxF 'waits for release 1.1.0: #5' <<<"$out" || fail "release 1.1.0 waits on fix #21: foreman status (watch-conveyor.sh --status on the snapshot) does not say #5 waits for it: $out"
    else
      [ "$got" = '[[[5,null],[21,null]],[[5,null],[21,null]]]' ] || fail "release 1.1.0's wait stopped: the snapshot's queue (order, next) still says an issue waits for it: $got"
      ! grep -qF 'waits for release' <<<"$out" || fail "release 1.1.0's wait stopped: foreman status (watch-conveyor.sh --status on the snapshot) still says an issue waits for it: $out"
    fi
  done
}
