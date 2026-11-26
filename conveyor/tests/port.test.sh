#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 300
# Engine cases: landing conflicts and ports (the retry of a blocked card is in resume.test.sh, kept work in kept.test.sh).
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"
# The engine folder, as lib.sh sets it: named here too, so the release closure (tools/closure.sh) follows this file's paths.
SRC=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
# A line of a build stub: the session that ports a card after its landing conflict moves main's a.txt again, so the
# card's landing conflicts once more and it blocks for the owner (a case that goes on to `retry` it).
AGAIN='if grep -q "^# Landing conflict" "$STUB/brief"; then echo TWO > "$R/a.txt"; git -C "$R" commit -qam again; fi'
# NOGO with its P1 made a P2, for the same reason as PORTNOGO (lib.sh).
export PORTNOGO2=${NOGO/\[P1\]/[P2]}

# Bugs: a card that passed its review is thrown away when another change landed on its lines first; the
# rebuild starts from the card's stale tree; its result lands unreviewed, or over the other change; a card is rebuilt
# and ported more than once; a card with no conflict runs an extra session. Each kind is a case of its own on a main of
# its own (rebase, rebasetwice, rebaseempty), so they run side by side; a card with no conflict is keptunread's card
# built from nothing. What the rebuild is handed, and the review after it, are rebasebig's, with no card run; so are
# rebasetwice's and rebaseempty's, which call landconflict() (lib/cardland.sh) on a conflict made by hand (conflicted,
# lib.sh).
t_rebase() {
  rebasesetup 7
  echo 'printf "ONE\ntwo\n" > a.txt' > "$STUB/rebuild"; echo 'ONE other' > "$STUB/move"
  # loop: only a whole card run shows the landing conflict, the rebuild, its review and the landing on the other commit
  loop run 1 >/dev/null || fail "run exited non-zero"
  [ "$(st '.step' | tr '\n' ' ')" = "picked worktree deps brief start build start review start test start start start rebase start review start test start landed pushed issue " ] && [ "$(st 'select(.step == "start" and .waitFor == "cap") | .of')" = rebase ] || fail "steps of a card that conflicts at landing (one wait for room, caphold(), before its rebuild): $(st '"\(.step) \(.of) \(.waitFor) \(.reason)"' | tr '\n' ',')"
  [ "$(wc -l < "$STUB/sessions")" = 2 ] && [ "$(wc -l < "$STUB/reviews")" = 2 ] || fail "$(wc -l < "$STUB/sessions") sessions and $(wc -l < "$STUB/reviews") reviews, not 2 and 2"
  [ "$(cat "$STUB/started-from")" = ONE ] || fail "the rebuild did not start from main as it stands: $(cat "$STUB/started-from")"
  [ "$(st 'select(.step == "landed") | .sha')" = "$(git -C "$R" rev-parse HEAD)" ] && [ "$(git -C "$R" log -1 --format=%s HEAD~1)" = other ] || fail "the card did not land on top of the other commit"
  [ "$(tr '\n' ' ' < "$R/a.txt")" = "ONE two " ] && [ -z "$(git -C "$R" status --porcelain)" ] && [ -z "$(ls "$T/$CASE/cards")" ] || fail "the landed tree does not hold both changes, main is dirty, or the worktree is left"
  [ "$(st 'select(.step == "rebase") | [.result, .tokens.claude, (.reason | startswith("rebase onto main conflicts: "))] | tojson')" = '["ok",35,true]' ] || fail "rebase line: $(st 'select(.step == "rebase")')"
  recok "$ST/cards.jsonl" "a card rebuilt after a landing conflict (its rebase line)"
  [ "$(loop cards | jq -c '.cards[0] | [.step, .reviews, (.steps | map(.step) | join(" "))]')" = '["landed",2,"build review test rebase review test"]' ] || fail "dashboard row: $(loop cards)"
}

# Bug: after a GO on the review of a port whose earlier loop ended on a NO-GO, a test fix and the
# GO after it landed the card with nothing filed: the earlier loop's findings were lost.
# Bugs of the card blocked here, a last review's NO-GO whose landing conflicts, and conflicts again after its port: its
# three follow-ups were not withdrawn as not planned each time, their findings kept. Of the retried card, whose kept
# patch no longer applies to main (resumeport takes it up with no card run): its port session was not told the
# patch's file and the commit it was built on, or to change nothing else (its one review's prompt is resumeport's,
# with no card run).
t_portfix() {
  setup "[$(issue 8 2026-01-01)]"; for i in 1 2 3; do moved "${i/3/}" "$PORTNOGO" | p1at2 "$i" > "$STUB/review.$i"; done; echo "$GO" > "$STUB/review.4"
  steps() { st "select(.issue == $1) | \"\(.step) \(.result) \(.reason)\"" | tr '\n' ,; }
  echo 'cp "$STUB/brief" "$STUB/brief.$(wc -l < "$STUB/sessions")"; echo two >> a.txt; '"$AGAIN" > "$STUB/build"; echo 'ONE other' > "$STUB/move"
  # loop: only a whole card run shows a last review's NO-GO, a landing conflict and the retry that ports it
  loop run >/dev/null; st 'select(.step == "blocked") | .reason' | grep -q '^rebase onto main conflicts' || fail "#8 was not blocked on its landing conflict: $(steps 8)"
  [ "$(tr '\n' ' ' < "$STUB/closed")" = "100101 100102 100103 100104 100105 100106 " ] && [ "$(grep -c -- '^--reason not planned --comment .*withdrawn.* #8 ' "$STUB/close-comments")" = 6 ] \
    || fail "the withdrawn follow-ups were not closed as not planned, each naming #8: $(cat "$STUB/closed" "$STUB/close-comments" 2>&1)"
  local k old s
  k=$(st 'select(.issue == 8 and .step == "blocked") | "\($ENV.ST)/\(.kept)"'); old=$(st 'select(.issue == 8 and .step == "blocked") | .card')
  [ "$(sed -n 2p "$k/$old.withdrawn")" = '#100102 [P2] b.txt:22 no mark here' ] && [ -s "$k/$old.patch" ] || fail "the withdrawn findings or the patch are not in the kept folder: $(ls "$k")"
  echo "$GO" > "$STUB/review.5"; echo "$GO" > "$STUB/review.6"
  # The third run fails, and its run again too (tests()), so the test fix starts. It exits 1, so filecmd()
  # (lib/testrun.sh) reports a.test.sh failed, the one file test.fileCommand is given: a failure it reported in another file would be a run of files it was not given
  # (session.sh watch()), which stops the run and blocks the card before any test fix.
  echo 'echo x >> "$STUB/tests"; case $(wc -l < "$STUB/tests") in 3|4) exit 1 ;; esac' > "$STUB/test-cmd"
  s=$(($(wc -l < "$STUB/sessions") + 1))
  # The bug is after the resume, in the port's test fix, its second GO and the landing that files the earlier loop's findings.
  # loop: only the card's own steps show the port's brief, its review, test fix, second GO and landing
  loop retry 8 >/dev/null && loop run >/dev/null || fail "run of the retried #8 exited non-zero"
  [ "$(cat "$k/$old.base")" != "$(git -C "$R" rev-parse HEAD)" ] && grep -q "^# This card brings the change of blocked card $old onto main$" "$STUB/brief.$s" \
    && grep -q "The patch is the file $k/$old.patch, built on commit $(cat "$k/$old.base")\. Bring that change onto main as it is now.* resolve the conflicts" "$STUB/brief.$s" \
    && grep -q 'Change nothing else: that change finished its review loop' "$STUB/brief.$s" && ! grep -q 'from nothing\.\? *$\|Build the issue' "$STUB/brief.$s" \
    || fail "the port session of a finished loop was not told the patch and the commit it was built on, or to change nothing else: $(tail -n 6 "$STUB/brief.$s")"
  [ "$(st 'select(.issue == 8 and '"$NOMARK"') | "\(.step) \(.result)"' | tr '\n' ,)" = "picked ok,worktree ok,brief ok,build ok,review GO,test fail,fix ok,review GO,test pass,landed ok," ] \
    && [ "$(st 'select(.issue == 8 and .step == "landed") | .leftover')" = true ] \
    && [ "$(tail -n 3 "$STUB/filed" | jq -r .title | tr '\n' '|')" = '[P2] a.txt:1 wrong word|[P2] b.txt:22 no mark here|[P2] c.txt:3 a nit|' ] \
    || fail "a test fix after the port's GO lost the earlier loop's findings: $(steps 8)"
  [ "$(st 'select(.issue == 8 and .step == "filed") | .followups | length')" = 3 ] || fail "no filed line names the three follow-ups: $(steps 8)"
  recok "$ST/cards.jsonl" "a card that landed on a NO-GO (its filed line, and its landed line with leftover and followups)"
}

# Bugs: the port's landing conflicts too (its session moves main again) and something lands, or a second port runs:
# it blocks for the owner. A NO-GO on the one review of a port (a finished loop stopped only by a landing conflict)
# lands with follow-ups as if it were a last review, instead of being fixed and going round the loop as any card's.
t_port() {
  setup "[$(issue 8 2026-01-01)]"; for i in 1 2 3; do moved "${i/3/}" "$PORTNOGO" | p1at2 "$i" > "$STUB/review.$i"; done; echo "$GO" > "$STUB/review.4"
  steps() { st "select(.issue == $1) | \"\(.step) \(.result) \(.reason)\"" | tr '\n' ,; }
  echo "echo two >> a.txt; $AGAIN" > "$STUB/build"; echo 'ONE other' > "$STUB/move"
  # loop: only a whole card run shows a finished loop stopped by a landing conflict, then the port's own review
  loop run >/dev/null || fail "run of #8 exited non-zero"
  [ "$(st 'select(.issue == 8 and '"$NOMARK"') | "\(.step) \(.result)"' | tr '\n' ,)" = "picked ok,worktree ok,brief ok,build ok,review NO-GO,fix ok,review NO-GO,fix ok,review NO-GO,test pass,rebase ok,review GO,test pass,blocked blocked," ] \
    && st 'select(.issue == 8 and .step == "blocked") | .reason' | grep -q '^rebase onto main conflicts: ' && [ "$(wc -l < "$STUB/sessions")" = 4 ] \
    && [ "$(git -C "$R" log -1 --format=%s)" = again ] || fail "a conflict after the port did not block for the owner: $(steps 8)"
  echo "$NOGO" > "$STUB/review.5"; echo "$GO" > "$STUB/review.6"; f=$(wc -l < "$STUB/filed")
  # resumeplan only gives the port its finished loop's GO (fin); what is proved is card()'s handling of a NO-GO on that
  # one review (fixed and reviewed again, nothing filed).
  # loop: only the card's review loop shows a NO-GO on the port's one review fixed and reviewed again
  loop retry 8 >/dev/null && loop run >/dev/null || fail "run of the retried #8 exited non-zero"
  [ "$(st 'select(.issue == 8 and '"$NOMARK"') | "\(.step) \(.result)"' | tr '\n' ,)" = "picked ok,worktree ok,brief ok,build ok,review NO-GO,fix ok,review GO,test pass,landed ok," ] \
    && [ "$(wc -l < "$STUB/filed")" = "$f" ] && [ "$(st 'select(.issue == 8 and .step == "landed") | has("leftover")')" = false ] && [ "$(tr '\n' ' ' < "$R/a.txt")" = "TWO two two " ] \
    || fail "a NO-GO on the port's review was not fixed and reviewed again before landing: $(steps 8)"
  loop check || fail "the records do not check"
}

# Bugs: the rebuild of a card whose diff is larger than a prompt may be fails at once with "Prompt is too long",
# and the card is blocked; or it is not handed the issue, the conflict message and the file that holds the card's
# patch. The prompt of the rebuild, and of a port (rebaseprompt(), lib/card.sh, on the card's prompt as card() makes
# it), names the patch file and the commit it was made against, and holds none of the card's diff of 3 MB.
# Bug: a NO-GO on the review after the rebuild got a fix round. That review is a last review (afterreview(),
# lib/card.sh): its NO-GO lands the card with its finding filed, where the same NO-GO with no rebuild is fixed. The
# NO-GO holds a P0: one of new P2 findings alone ends the loop with no rebuild too (loopstop(): new-p2).
t_rebasebig() {
  local cm='rebase onto main conflicts: CONFLICT (content): Merge conflict in a.txt'
  setup "[$(issue 11 2026-01-01)]"
  fx_in 'wt=$CARDS/c1-11; mkdir -p "$CARDS" && { printf "%s\n" "diff --git a/big.txt b/big.txt" "--- /dev/null" "+++ b/big.txt"; awk "BEGIN { while (i++ < 140000) print \"+a line of a large file\" }"; } > "$wt.patch" || exit 3
    issue=$(gh issue view 11 --json number,title,body,labels,milestone) && hdr=$(header on) && b=$(brief c1-11 "$issue" "$hdr") || exit 3
    p=$(cardprompt c1-11 "$hdr" "the card rules" "$b")
    rebaseprompt "$p" "$wt" "$cm" 0123abc > "$T/$CASE/rebuild" && rebaseprompt "$p" "$wt" "$cm" 0123abc port > "$T/$CASE/port" || exit 3
    printf "%s\n" "$NOGO3" > "$wt.review"; res=NO-GO fin="" finrev="" finend="{}" pass=1 rounds=0 tfix="" lfix="" mode="" privfix="" p1fix=""
    for rebased in 1 ""; do afterreview; echo "$after $stop"; done > "$T/$CASE/after"'
  [ "$RC" = 0 ] || fail "the rebuild's prompt or the decision after its review could not be made (exit $RC): $(cat "$T/$CASE/run.out")"
  local f; for f in rebuild port; do
    [ "$(wc -c < "$T/$CASE/cards/c1-11.patch")" -gt 3000000 ] && [ "$(wc -c < "$T/$CASE/$f")" -lt 100000 ] && ! grep -q 'a line of a large file' "$T/$CASE/$f" \
      || fail "the $f prompt of a card with a 3 MB diff holds the patch itself, so it grows with the diff: $(wc -c < "$T/$CASE/$f") bytes"
    grep -q '^# Issue #11: title 11$' "$T/$CASE/$f" && grep -q '^# Landing conflict' "$T/$CASE/$f" \
      && [ "$(grep -A1 -x '## The conflict message' "$T/$CASE/$f" | tail -n 1)" = "$cm" ] && grep -qxF "The file $T/$CASE/cards/c1-11.patch, made against commit 0123abc." "$T/$CASE/$f" \
      || fail "the $f session is not handed the issue, the conflict message and the file that holds the card's patch with its commit: $(tail -n 8 "$T/$CASE/$f")"
  done
  grep -qx 'One review of this port alone follows: change nothing else.' "$T/$CASE/port" && ! grep -q 'One review of this port' "$T/$CASE/rebuild" \
    || fail "only the port's session is told that one review of the port alone follows: $(tail -n 8 "$T/$CASE/port")"
  [ "$(tr '\n' , < "$T/$CASE/after")" = "last rebased,fix ," ] || fail "a NO-GO on the review after the rebuild is not a last review that lands with its finding filed: $(tr '\n' , < "$T/$CASE/after")"
  # A last review's NO-GO, its three follow-ups filed, whose landing conflicts: landconflict() ports it (no rebuild)
  # and withdraws them; the port's own last NO-GO files three more, its landing conflicts again, and the card blocks
  # with those withdrawn too.
  # last=1 as afterreview() (lib/card.sh) sets it on a last NO-GO: landconflict() rebuilds a card without it.
  conflicted 11 'printf "%s\n" "$PORTNOGO2" > "$wt.review"; res=NO-GO last=1
    for u in "[100101,100102,100103]" "[100104,100105,100106]"; do ups=$u; land1; go=end; landconflict; outcome; done'
  [ "$OUTCOME" = '{"go":"next","rebased":"","ported":"1","parsecheck":"1","kept":"","pass":0}
{"go":"end","rebased":"","ported":"1","parsecheck":"1","kept":"","pass":0}' ] \
    || fail "a finished loop whose landing conflicted was not ported, then blocked when the port conflicted: $OUTCOME"
  [ "$(tr '\n' ' ' < "$STUB/closed")" = "100101 100102 100103 100104 100105 100106 " ] && st 'select(.issue == 11 and .step == "blocked") | .reason' | grep -q '^rebase onto main conflicts: ' \
    || fail "the follow-ups of a conflicting landing were not withdrawn at the port and at the block after it: $(cat "$STUB/closed" 2>&1) $(st 'select(.issue == 11 and .step == "blocked")')"
}

# Bug: a card whose review loop had finished (a last NO-GO, its follow-ups filed) blocked for the owner when its
# landing met a conflict, and sat there until the owner ran `retry`. It is ported in the card with no owner action:
# one session, one review of that port alone, the tests and the landing, which files the loop's findings again; the
# Board shows the port as a step, not a block. A conflict after that port blocks for the owner (t_port).
# Bug: a card that files a last NO-GO's follow-ups had no <worktree>.ready, so its test pass was stored nowhere and it
# ran its tests again each time it came to the test step (the owner: passes are reused). Its pass is kept, keyed to
# its staged change: the port, a different change, runs its tests again; main moving on another file during the
# port's tests then fits it onto main with the same change, which reuses the port's pass and starts no run. It lands
# alone, with the earlier loop's findings filed.
t_autoport() {
  setup "[$(issue 8 2026-01-01)]"; for i in 1 2 3; do moved "${i/3/}" "$PORTNOGO" | p1at2 "$i" > "$STUB/review.$i"; done; echo "$GO" > "$STUB/review.4"
  steps() { st "select(.issue == $1 and $NOMARK) | \"\(.step) \(.result)\"" | tr '\n' ,; }
  echo 'echo two >> a.txt' > "$STUB/build"; echo 'ONE other' > "$STUB/move"
  echo '[ "$(wc -l < "$STUB/tests")" != 2 ] || { echo b > "$R/b.txt"; git -C "$R" add b.txt; git -C "$R" commit -qm "main adds b.txt"; }' >> "$STUB/test-cmd"
  echo '[ ! -e "$PWD.port" ] || { cp "$PWD.port" "$STUB/port"; cp "$PWD.ready" "$STUB/readyatport"; echo "$PWD" > "$STUB/portwt"; }' > "$STUB/review-cmd"
  # Each review's prompt is kept, as $STUB/prompt.<n>.
  sed -i 's|^cat > /dev/null; echo x >> "$STUB/reviews";|echo x >> "$STUB/reviews"; cat > "$STUB/prompt.$(wc -l < "$STUB/reviews")";|' "$STUB/codex"
  # loop: only a whole card run shows the port's tests, the move on main and the auto-port that reuses its pass
  loop run >/dev/null || fail "run of #8 exited non-zero"
  [ "$(steps 8)" = "picked ok,worktree ok,brief ok,build ok,review NO-GO,fix ok,review NO-GO,fix ok,review NO-GO,test pass,rebase ok,review GO,test pass,test pass,landed ok," ] \
    && [ "$(wc -l < "$STUB/sessions")" = 4 ] && [ "$(wc -l < "$STUB/reviews")" = 4 ] \
    || fail "a finished loop whose landing conflicted was not ported by one session, reviewed once, tested and landed: $(steps 8)"
  [ "$(jq -c '[.tested, .alone, (.patch | length > 0)]' "$STUB/readyatport" 2>/dev/null)" = '[true,true,true]' ] \
    || fail "the card with a last NO-GO did not store its test pass, marked alone, keyed to its staged change: $(cat "$STUB/readyatport" 2>&1)"
  [ "$(wc -l < "$STUB/tests")" = 2 ] && [ "$(st 'select(.issue == 8 and .step == "test") | .reused' | tr '\n' ,)" = "null,null,true," ] \
    && [ "$(st 'select(.issue == 8 and .step == "landed") | .batch')" = null ] \
    || fail "the port, a different staged change, did not run its tests, its fit onto the moved main with the same change ran them again, or it did not land alone: $(wc -l < "$STUB/tests") runs, $(steps 8) $(st 'select(.issue == 8 and .step == "landed")')"
  [ "$(cat "$R/b.txt")" = b ] && [ "$(git -C "$R" log -1 --format=%P | wc -w)" = 1 ] && [ "$(git -C "$R" log -2 --format=%s | tail -n 1)" = "main adds b.txt" ] \
    || fail "#8 did not land alone on the main that moved: $(git -C "$R" log --oneline | head -3)"
  st 'select(.issue == 8 and .step == "rebase") | .reason' | grep -q '^rebase onto main conflicts: ' || fail "the port's step does not name the conflict"
  # Bug (#1385): nothing marked the port, so a retry counted the reviews before it as its rounds (t_resumeport3).
  [ "$(st 'select(.issue == 8 and .step == "rebase") | .port')" = true ] && recok "$ST/cards.jsonl" "an automatic port" \
    || fail "the port's rebase line does not mark it as the port: $(st 'select(.issue == 8 and .step == "rebase")')"
  # The .port file and the instructions of the port's review are made inside card() (no function makes them), so only
  # this run shows that review is told it reviews a port alone and handed the kept patch against the ported change.
  # Bug: the port's review was given the instructions of any other review (no PORTREVIEW, no .port file named).
  # Bug: a prompt that names another file (such as <worktree>.patch.port) in place of <worktree>.port, the file the
  # engine writes, sends the review to a file that is not there: the line must name that exact path.
  grep -qx -- '+ ONE' "$STUB/port" && grep -qx -- ' +two' "$STUB/port" || fail "the review after the port was not handed the kept patch against the port: $(cat "$STUB/port" 2>&1)"
  grep -qx '# This review is of a port alone' "$STUB/prompt.4" && grep -qxF "The difference is the file $(cat "$STUB/portwt" 2>&1).port." "$STUB/prompt.4" \
    && ! grep -q '^# This review is of a port alone' "$STUB/prompt.3" \
    || fail "the port's review, and it alone, was not told it reviews the port and handed the .port file: $(grep -n 'port' "$STUB/prompt.4" 2>&1 | tail -n 4)"
  [ "$(tr '\n' ' ' < "$STUB/closed")" = "100101 100102 100103 " ] && [ "$(st 'select(.issue == 8 and .step == "landed") | [.leftover, .followups] | tojson')" = '[true,[100104,100105,100106]]' ] \
    && [ "$(tr '\n' ' ' < "$R/a.txt")" = "ONE two " ] || fail "the port did not withdraw the follow-ups and file the loop's findings again at its landing: $(st 'select(.issue == 8 and .step == "landed")')"
  # Bug: the filed line after the port's GO said the loop ended on that GO, not on review 3's max-reviews whose
  # findings it files.
  [ "$(st 'select(.issue == 8 and .step == "filed") | [.stop, .pass, .rounds] | tojson' | tr '\n' ' ')" = '["max-reviews",3,0] ["max-reviews",3,0] ' ] \
    || fail "a filed line does not say why the loop whose findings it files ended: $(st 'select(.issue == 8 and .step == "filed") | tojson')"
  [ "$(loop cards | jq -c '.cards[0] | [.step, (.steps | map(.step) | join(" "))]')" = '["landed","build review fix review fix review test rebase review test test"]' ] \
    && [ -z "$(st 'select(.step == "blocked")')" ] && [ ! -s "$ST/retried.jsonl" ] || fail "the port is not a step of the card's row, or it blocked or was retried: $(loop cards | jq -c '.cards[0]')"
}

# The rebuild conflicts too (main moves again during it), and so does the one port after it: blocked with the
# conflict message, nothing landed: landconflict() on each of the three conflicts, as card() calls it after each land().
t_rebasetwice() {
  rebasesetup 8
  echo 'echo again > a.txt; echo "THREE$(wc -l < "$STUB/sessions")" > "$R/a.txt"; git -C "$R" commit -qam third' > "$STUB/rebuild"
  conflicted 8 'for i in 1 2 3; do land1; go=end; landconflict; outcome; done'
  [ "$OUTCOME" = '{"go":"next","rebased":"1","ported":"","parsecheck":"1","kept":"","pass":1}
{"go":"next","rebased":"","ported":"1","parsecheck":"1","kept":"","pass":0}
{"go":"end","rebased":"","ported":"1","parsecheck":"1","kept":"","pass":0}' ] \
    || fail "a card that conflicts three times was not rebuilt, then ported, then blocked: $OUTCOME"
  [ "$(st 'select(.issue == 8 and '"$NOMARK"') | "\(.step) \(.result)"' | tr '\n' ,)" = "rebase ok,rebase ok,blocked blocked," ] \
    && st 'select(.issue == 8 and .step == "blocked") | .reason' | grep -q '^rebase onto main conflicts: ' || fail "a conflict after the port did not block with the conflict message: $(st 'select(.issue == 8)')"
  [ "$(git -C "$R" log -1 --format=%s)" = third ] && [ -z "$(git -C "$R" status --porcelain)" ] && [ -z "$(ls "$T/$CASE/cards")" ] || fail "a conflict after the port landed something, left main dirty or left the worktree"
  [ "$(wc -l < "$STUB/sessions")" = 2 ] || fail "a card that conflicts three times was rebuilt or ported more than once: $(wc -l < "$STUB/sessions") sessions"
}

# Bug: a rebuild session that ends well but leaves no change blocks the card with nothing kept: the
# reviewed change is deleted with the worktree, and retry builds from nothing. landconflict() rebuilds, and the next
# pass of the review loop finds no change (emptychange(), then nochange(), as cardreview() calls them).
t_rebaseempty() {
  rebasesetup 12
  echo ':' > "$STUB/rebuild"
  conflicted 12 'land1; go=end; landconflict; outcome; ! emptychange "$c" "$n" "$wt" "$br" || nochange "$c" "$n" "$wt" "$sprompt"'
  [ "$OUTCOME" = '{"go":"next","rebased":"1","ported":"","parsecheck":"1","kept":"","pass":1}' ] || fail "a card whose landing conflicted after a GO was not rebuilt: $OUTCOME"
  [ "$(st 'select(.issue == 12 and '"$NOMARK"') | "\(.step) \(.result)"' | tr '\n' ,)" = "rebase ok,blocked blocked," ] \
    || fail "a rebuild that leaves no change: $(st 'select(.issue == 12) | "\(.step) \(.result) \(.reason)"' | tr '\n' ,)"
  local k c; k=$(st 'select(.issue == 12 and .step == "blocked") | "\($ENV.ST)/\(.kept)"'); c=$(st 'select(.issue == 12 and .step == "blocked") | .card')
  [ -n "$k" ] && grep -qx '+two' "$k/$c.patch" && [ "$(cat "$k/$c.base")" = "$(git -C "$R" rev-parse HEAD~1)" ] || fail "a rebuild that left no change did not keep the reviewed change as the card's patch (kept: $k)"
  grep -qF "builds the next card from the kept work (1 file, 1 KB; the reviewed change from before the rebuild, which left no change of its own)." "$STUB/comments" \
    && [ "$(tail -n 1 "$STUB/comments")" = "<sub>Card $c · \`<state>/kept/${k##*/}/$c.patch\` · built on $(head -c 7 "$k/$c.base")</sub>" ] || fail "the block comment does not name the reviewed patch: $(tail -n 3 "$STUB/comments")"
  [ -z "$(ls "$T/$CASE/cards")" ] || fail "a rebuild that left no change left files beside the cards: $(ls "$T/$CASE/cards")"
}

# Bug: the earlier loop's review was put back in place of the port's own before the yes was
# checked, so a port whose visible change goes beyond its parent's yes landed on the earlier review's INHERITED: part.
# The yes check (visgate(), lib/card.sh) of follow-up #100101, whose parent #7 has the owner's yes (inherit()), on
# the port's product change: the port's own review, which says the change goes beyond that yes, stops the card for
# the owner; the earlier loop's review, which says it is part of the yes, would land it on that yes.
t_portyes() {
  local P='Visible change approved: Dana, 2026-01-02; condition: only for admins' Y="visible to customers or staff: needs Dana's yes: "
  setup "$(jq -cs . <(issue 7 2026-01-01 | jq -c --arg l "$P" '.body += "\n\n" + $l') <(issue 100101 2026-01-02 conveyor-followup P1 | jq -c '.body = "Follow-up to #7 (Conveyor card c0-7). Its last review said NO-GO.\nFinding: x\nFollow-up depth: 1"'))"
  { kline c0-7 7 review GO '{"visible":"yes: admins see a Pay button"}'; landed 7 '[100101]'; } > "$ST/cards.jsonl"
  printf '%s\n' 'INHERITED: beyond: guests see it too' 'USER-VISIBLE: yes: guests see a Pay button' 'VERDICT: GO' > "$STUB/review.port"
  printf '%s\n' '[P1] a.txt:1 wrong word' 'INHERITED: part' 'USER-VISIBLE: yes: admins see the Pay button in red' 'VERDICT: NO-GO' > "$STUB/review.earlier"
  fx_in 'cd "$R" || exit 3; n=100101 c=c9 wt=$CARDS/c9 ph="" pf=""
    git worktree add -q --detach "$wt" "refs/heads/$BRANCH" && (cd "$wt" && echo two >> a.txt && mkdir -p web && echo pay >> web/pay.ts && git add -A) || exit 3
    issue=$(gh issue view "$n" --json number,title,body,labels,milestone) || exit 3
    vrule=on seen=none nyes=0 sect="" ybase="" heldto="" vmode="" yfile=""; visplan; inh=$(inherit "$issue"); [ -n "$inh" ] || exit 3
    for r in port earlier; do
      cp "$STUB/review.$r" "$wt.review" && vis=$(visible "$wt.review" "$vmode") && yesfrom="" err="" || exit 3
      visgate >/dev/null; jq -cn --arg r "$r" --arg rc $? --arg e "$err" --arg y "$yesfrom" "{review: \$r, rc: \$rc, err: \$e, yesfrom: \$y}"
    done > "$T/$CASE/gate"'
  [ "$RC" = 0 ] || fail "the yes check could not be called on #100101's port (exit $RC): $(cat "$T/$CASE/run.out")"
  [ "$(jq -sc '.[0]' "$T/$CASE/gate")" = "$(jq -cn --arg e "${Y}guests see a Pay button (it goes beyond the yes of #7: guests see it too)" '{review: "port", rc: "1", err: $e, yesfrom: ""}')" ] \
    || fail "a port whose visible change goes beyond its parent's yes does not stop for the owner: $(cat "$T/$CASE/gate")"
  [ "$(jq -sc '.[1]' "$T/$CASE/gate")" = '{"review":"earlier","rc":"0","err":"","yesfrom":"7"}' ] \
    || fail "the earlier loop's review, the one that must not stand for the port's, does not land on the yes of #7: $(cat "$T/$CASE/gate")"
}
