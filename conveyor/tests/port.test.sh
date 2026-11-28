#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 300
# Engine cases: landing conflicts and ports (the retry of a blocked card is in resume.test.sh, kept work in kept.test.sh).
# Each case that runs whole cards and ports one is a file of its own (portauto.test.sh, portagain.test.sh,
# portfix.test.sh): the Test step runs a file's cases one after another, so here they added up past its time limit on a
# busy machine.
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"
# The engine folder, as lib.sh sets it: named here too, so the release closure (tools/closure.sh) follows this file's paths.
SRC=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
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
  [ "$(st '.step' | tr '\n' ' ')" = "picked worktree deps brief start build start test start review start test start start start rebase start review start test start landed pushed issue " ] && [ "$(st 'select(.step == "start" and .waitFor == "cap") | .of')" = rebase ] || fail "steps of a card that conflicts at landing (one wait for room, caphold(), before its rebuild): $(st '"\(.step) \(.of) \(.waitFor) \(.reason)"' | tr '\n' ',')"
  [ "$(wc -l < "$STUB/sessions")" = 2 ] && [ "$(wc -l < "$STUB/reviews")" = 2 ] || fail "$(wc -l < "$STUB/sessions") sessions and $(wc -l < "$STUB/reviews") reviews, not 2 and 2"
  [ "$(cat "$STUB/started-from")" = ONE ] || fail "the rebuild did not start from main as it stands: $(cat "$STUB/started-from")"
  [ "$(st 'select(.step == "landed") | .sha')" = "$(git -C "$R" rev-parse HEAD)" ] && [ "$(git -C "$R" log -1 --format=%s HEAD~1)" = other ] || fail "the card did not land on top of the other commit"
  [ "$(tr '\n' ' ' < "$R/a.txt")" = "ONE two " ] && [ -z "$(git -C "$R" status --porcelain)" ] && [ -z "$(ls "$T/$CASE/cards")" ] || fail "the landed tree does not hold both changes, main is dirty, or the worktree is left"
  [ "$(st 'select(.step == "rebase") | [.result, .tokens.claude, (.reason | startswith("rebase onto main conflicts: "))] | tojson')" = '["ok",35,true]' ] || fail "rebase line: $(st 'select(.step == "rebase")')"
  recok "$ST/cards.jsonl" "a card rebuilt after a landing conflict (its rebase line)"
  [ "$(loop cards | jq -c '.cards[0] | [.step, .reviews, (.steps | map(.step) | join(" "))]')" = '["landed",2,"build test review test rebase review test"]' ] || fail "dashboard row: $(loop cards)"
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

# Bug: a NO-GO on the one review of a port (its earlier loop ended on a last NO-GO of P2s, whose follow-ups the
# landing conflict withdrew) dropped that loop's review, so the GO after the fix of the port's own finding landed the
# card with those P2s filed nowhere. afterreview() (lib/card.sh) as card() calls it on the port's two reviews: the NO-GO
# gets its fix round, and the GO is a last review that carries the earlier loop's findings and why it ended.
t_portnogo() {
  local e='{"stop":"max-reviews","pass":3,"rounds":0}'
  setup "[$(issue 12 2026-01-01)]"
  fx_in 'wt=$CARDS/c1-12; mkdir -p "$CARDS" && issue=$(gh issue view 12 --json number,title,body,labels,milestone) || exit 3
    fin=NO-GO finrev=$PORTNOGO finend=$e earlier="" earlyend="" pass=0 rounds=0 rebased="" tfix="" lfix="" mode="" privfix="" p1fix=""
    for r in "$NOGO" "$GO"; do printf "%s\n" "$r" > "$wt.review"; res=$(verdict "$wt.review") pass=$((pass + 1)); afterreview
      jq -cn --arg a "$after" --arg s "$stop" --argjson e "${earlyend:-null}" --arg r "$earlier" "{after: \$a, stop: \$s, earlyend: \$e, earlier: (\$r | test(\"c.txt:3 a nit\"))}"; done > "$T/$CASE/after"'
  [ "$RC" = 0 ] || fail "afterreview() on the port's reviews could not be called (exit $RC): $(cat "$T/$CASE/run.out")"
  [ "$(tr '\n' , < "$T/$CASE/after")" = "{\"after\":\"fix\",\"stop\":\"\",\"earlyend\":$e,\"earlier\":true},{\"after\":\"last\",\"stop\":\"go\",\"earlyend\":$e,\"earlier\":true}," ] \
    || fail "a GO after the fix of a NO-GO on the port's review (earlier loop's review: $PORTNOGO) does not land with that loop's last NO-GO and why it ended: $(tr '\n' , < "$T/$CASE/after")"
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
