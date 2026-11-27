#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 120
# Engine cases (issue 1683, slice 2): a push that its pre-push hook refused (kind check: it will not pass on a retry)
# gets a fix card made by the engine as a red main's is (redfix.sh pushred()), picked ahead of the queue and with the
# cap reached (redpick(), run.sh redfix()); its landing is pushed at once (push.sh pushturn(): pushfixowed()); and
# the owner's Needs you item for the block is there only while the owner has something to do, naming the fix card; a
# block origin no longer has gets no card; and a fix card's cases passing on main does not close it while its push
# check fails (card.sh cardbuild(), bugproof.sh bugproof(), followups.sh nochange()).
# The fixtures are pushflaky.test.sh's (pfix, pnow), pushtests.test.sh's (pushfix, pushnow, PUSHTURN, STUBPUSH),
# mainredproof.test.sh's (redsetup, redbuild, redcheck), mainredreplaced.test.sh's (replfix) and mainred.test.sh's (eng): the runner sources every case
# file before it runs a case.
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"

# pfix's landing c1 (issue 1) pushed through main's pre-push hook, which fails the check typecheck-web (no test file):
# the real push (pnow) holds it as a failed check. Sets base and l1.
blockedpush() {
  pfix; echo 'push-checks: FAILED typecheck-web' > "$STUB/hook-says"; pnow
  [ "$(st 'select(.step == "push") | "\(.kind) \(.check) \(.sha)"')" = "check typecheck-web $l1" ] \
    || fail "the hook's failed check was not recorded as one on c1's commit: $(st 'select(.step == "push")') $(cat "$T/$CASE/push.out")"
}

# Done when 1. Bug it catches: a push held by a failed check got no fix card, so with the belt full (the cap reached)
# the next card picked was a queued issue, or none, and the owner had to order the fix. The real push files the block;
# #5 is queued and the loop's own card of #7 fills its one slot (cap 1). The loop's turn (turnask(), then turnpick())
# runs as run() runs it, with cardrun() stubbed to say what it was given, as the card's run is not under test: the card
# it starts is the block's fix card, of issue 0, titled after the check, in the slot beyond the cap; not #5. A turn
# that stopped asking redfix() at the cap starts nothing. Its brief names the check, the landing and the hook's output.
t_pushblockpick() {
  local l1 out c
  blockedpush
  jq -cs . <(issue 5 2026-01-05 P1) > "$STUB/issues.json"
  jq -cn '{card: "c20260101T000000-x-7", issue: 7, step: "picked", time: "2026-11-18T10:01:00Z", tokens: {claude: 0, codex: 0}, result: "ok", sha: "", reason: ""}' >> "$ST/cards.jsonl"
  fx_in 'cd "$R" && declare -A shuts=() mine=([1]="c20260101T000000-x-7 7") ranon=()
    cap=1 building=1 now=running inuse=1 running=1 sampled=$SECONDS old= nopack= nocli= mhold= guard= waits= issues= ctl=$(ctl) left=-1 started=0 pct= serve= pusher= picked=
    cardrun() { echo "started $1 $2"; }
    turnask >/dev/null 2>&1; echo "red $red"; turnpick || :; wait'
  out=$(cat "$T/$CASE/run.out"); c=$(tail -n 1 <<<"$out"); c=${c#started }; c=${c%% *}
  [ "$(head -n 1 <<<"$out")" = "red $l1" ] && [[ $(tail -n 1 <<<"$out") =~ ^started\ c[0-9]{8}T[0-9]{6}-.*-0\ 0$ ]] \
    || fail "with the belt full (cap 1, #7 on it) and #5 queued, the loop's turn did not start the push block's fix card (turnask, turnpick; exit $RC): $out"
  [ "$(st "select(.card == \"$c\" and .step == \"picked\") | [.title, .mainRed, .beyond] | join(\"|\")")" = "Push blocked: typecheck-web fails on main|$l1|main is red" ] \
    && [ -z "$(st 'select(.issue == 5) | .card')" ] || fail "the fix card's picked line does not name the check, main's commit and the slot beyond the cap, or #5 was picked: $(st 'select(.step == "picked")')"
  fx_in "redissue $c"
  jq -e '.title == "Push blocked: typecheck-web fails on main" and (.body | contains("failed its check typecheck-web") and contains("The push was for card c1 (#1)")
    and contains("push-checks: FAILED typecheck-web") and contains("Done when: the check typecheck-web passes on main."))' "$T/$CASE/run.out" >/dev/null \
    || fail "the fix card's brief (redissue $c) does not name the check, the landing and the hook's output: $(cat "$T/$CASE/run.out")"
  # The same check failing again while that card is open makes no second card.
  fx_in "pushred $(printf 'b%.0s' {1..40}) typecheck-web c2 2 && jq -c '[.reds[] | .card]' \"\$MAINRED\""
  [ "$(cat "$T/$CASE/run.out")" = "[\"$c\"]" ] || fail "a second failure of typecheck-web while its fix card $c is open made another entry: $(cat "$T/$CASE/run.out")"
}

# Done when 2. Bug it catches: the fix card's landing waited for the rule Push after a combined test run (set for 5
# landings, 3 landed), so the landings the block held stayed unpushed after their fix was in. c2's push failed its check
# (pushred(), as the push files it), the fix card cf was picked (redpick()) and lands l3: the next turn (pushturn())
# pushes it. Before cf lands, the same turn holds the push for the rule: only the fix card's landing goes past it.
t_pushblockland() {
  local l1 l2 l3 c
  pushfix false
  loop control rules push=on pushbatch=on pushbatchwhen=5 > /dev/null || fail "control rules push=on pushbatch=on pushbatchwhen=5 failed"
  fx_in "cd \"\$R\" && pushred $l2 typecheck-web c2 2 && locked redpick"
  c=$(cat "$T/$CASE/run.out"); c=${c%% *}
  [[ $c =~ -0$ ]] || fail "the push block's fix card was not picked (pushred $l2 typecheck-web c2 2, then redpick): $(cat "$T/$CASE/run.out")"
  pushnow "$STUBPUSH$PUSHTURN"
  [ ! -e "$STUB/pushcalls" ] && [ "$(cat "$T/$CASE/push.out")" = 'the rule Push after a combined test run holds the push until its run is due (pushbatchwhen)' ] || fail "before the fix card landed, the turn did not hold the push for the rule: $(cat "$STUB/pushcalls" "$T/$CASE/push.out" 2>&1)"
  echo good > "$R/lib/cart.js" && git -C "$R" commit -qam fix && l3=$(git -C "$R" rev-parse HEAD) || fail "the fix could not be committed"
  fx_in "append \"\$(line $c 0 landed ok '{\"sha\":\"$l3\",\"product\":true}')\""; [ "$RC" = 0 ] || fail "the fix card's landed line could not be written: $(cat "$T/$CASE/run.out")"
  pushnow "$STUBPUSH$PUSHTURN"
  [ "$(cat "$STUB/pushcalls" 2>&1)" = "$c 0" ] && [ "$(cat "$T/$CASE/push.out")" = null ] \
    || fail "the landed fix card $c of the push block was not pushed at the next turn: $(cat "$STUB/pushcalls" "$T/$CASE/push.out" 2>&1)"
}

# Done when 3. Bug it catches: Needs you said "push blocked" with nothing for the owner to do while the engine's fix
# card was queued, on the belt or landed and waiting for its push (the review of the first try: the item came back in
# that last gap), and did not name the fix card once it did need the owner. Health names the fix card and where it
# is (pushError.fix); the snapshot's Needs you has no push item while the card is on the belt, nor once it has landed
# with the rule Push when a card lands on (the loop pushes it); blocked, or landed with that rule off (the owner must
# push: the second review's finding), the item names it. Third review, E8: with no loop running, the fix card not
# picked yet needs the owner too (nothing picks it or pushes main), so health's needsYou is true and Needs you has the
# block. Health reads a loop as running while the loop's run lock is held: the case holds it, as a running loop does.
t_pushblockneeds() {
  local l1 c s l3 lk
  blockedpush
  loop control rules push=on > /dev/null || fail "control rules push=on failed"
  [ "$(loop health | jq -c '[.loop, (.pushError.fix | [.card, .state, .needsYou])]')" = '[false,[null,"queued",true]]' ] \
    || fail "with no loop running and the fix card not picked, health does not say the owner must act: $(loop health | jq -c '{loop, pushError}')"
  s=$(loop snapshot --fresh 2>/dev/null)
  [ "$(jq -c '[.needsYou.blocked[] | select(.push) | [.fix.state, (.reason | contains("Its fix card is not picked yet, and no loop is running"))]]' <<<"$s")" = '[["queued",true]]' ] \
    || fail "with no loop running and the fix card not picked, Needs you does not list the push block: $(jq -c .needsYou.blocked <<<"$s")"
  exec {lk}>>"$ST/cards.jsonl.run" && flock -n "$lk" || fail "the loop's run lock could not be taken"
  [ "$(loop health | jq -c '[.loop, (.pushError.fix | [.card, .state, .needsYou])]')" = '[true,[null,"queued",false]]' ] \
    || fail "with a loop running, health says the owner must act on the queued fix card: $(loop health | jq -c '{loop, pushError}')"
  # Review finding E12: a paused loop runs but picks no card (pick(), lib/pick.sh), so the queued fix card needs the
  # owner to resume it, and Needs you says so.
  loop control pause > /dev/null || fail "control pause failed"
  [ "$(loop health | jq -c '[.loop, .state, (.pushError.fix | [.state, .needsYou])]')" = '[true,"paused",["queued",true]]' ] \
    || fail "with the loop running but paused and the fix card not picked, health does not say the owner must act: $(loop health | jq -c '{loop, state, pushError}')"
  s=$(loop snapshot --fresh 2>/dev/null)
  [ "$(jq -c '[.needsYou.blocked[] | select(.push) | .reason | contains("the loop is paused, so it picks no card: resume the loop")]' <<<"$s")" = '[true]' ] \
    || fail "with the loop paused and the fix card not picked, Needs you does not list the push block saying resume: $(jq -c .needsYou.blocked <<<"$s")"
  loop control resume > /dev/null || fail "control resume failed"
  fx_in 'cd "$R" && locked redpick'; c=$(cat "$T/$CASE/run.out"); c=${c%% *}
  [[ $c =~ -0$ ]] || fail "the push block's fix card was not picked: $(cat "$T/$CASE/run.out")"
  [ "$(loop health | jq -c '.pushError.fix | [.card, .state, .needsYou]')" = "[\"$c\",\"picked\",false]" ] || fail "health does not name the fix card on the belt: $(loop health | jq -c .pushError)"
  s=$(loop snapshot --fresh 2>/dev/null)
  [ "$(jq -c '[.needsYou.blocked[] | select(.push)]' <<<"$s")" = '[]' ] || fail "with fix card $c on the belt, Needs you lists the push block: $(jq -c .needsYou.blocked <<<"$s")"
  fx_in "append \"\$(line $c 0 blocked fail '{\"reason\":\"build: no change\"}')\""; [ "$RC" = 0 ] || fail "the fix card's blocked line could not be written: $(cat "$T/$CASE/run.out")"
  s=$(loop snapshot --fresh 2>/dev/null)
  [ "$(jq -c '[.needsYou.blocked[] | select(.push) | [.fix.card, .fix.state, (.reason | contains("Its fix card \($c) is blocked"))]]' --arg c "$c" <<<"$s")" = "[[\"$c\",\"blocked\",true]]" ] \
    || fail "with fix card $c blocked, Needs you does not list the push block naming it: $(jq -c .needsYou.blocked <<<"$s")"
  echo fixed > "$R/fixed.txt" && git -C "$R" add fixed.txt && git -C "$R" commit -qm fix && l3=$(git -C "$R" rev-parse HEAD) || fail "the fix could not be committed"
  fx_in "append \"\$(line $c 0 landed ok '{\"sha\":\"$l3\",\"product\":true}')\""; [ "$RC" = 0 ] || fail "the fix card's landed line could not be written: $(cat "$T/$CASE/run.out")"
  s=$(loop snapshot --fresh 2>/dev/null)
  [ "$(jq -c '[.needsYou.blocked[] | select(.push)]' <<<"$s")" = '[]' ] || fail "with fix card $c landed and push=on, Needs you lists the push block: $(jq -c .needsYou.blocked <<<"$s")"
  loop control rules push=off > /dev/null || fail "control rules push=off failed"
  # Fourth review: with the rule off and the loop stopped too, the item said "start the loop", which a started loop
  # does not answer (owed(), lib/push.sh): the run lock is let go, and the item must still say Push now.
  exec {lk}>&-
  s=$(loop snapshot --fresh 2>/dev/null)
  [ "$(jq -c '[.needsYou.blocked[] | select(.push) | [.fix.card, .fix.state, (.reason | contains("Its fix card \($c) landed") and contains("Push now") and (contains("start the loop") | not))]]' --arg c "$c" <<<"$s")" = "[[\"$c\",\"landed\",true]]" ] \
    || fail "with fix card $c landed, push=off and no loop running, Needs you does not list the push block naming it with Push now: $(jq -c .needsYou.blocked <<<"$s")"
}

# Second review, E2. Bug it catches: a push block's queued fix card was picked though origin already held the blocked
# commit (pushed by hand once main was fixed), a card for a block that no longer was. The real push files the block;
# the commit is pushed to origin past the hook; redpick() picks nothing and drops the entry.
t_pushblockgone() {
  local l1
  blockedpush
  git -C "$R" push -q --no-verify origin "$l1:refs/heads/main" || fail "the blocked commit could not be pushed by hand"
  fx_in 'cd "$R" && locked redpick && jq -c .reds "$MAINRED"'
  [ "$RC" = 0 ] && [ "$(cat "$T/$CASE/run.out")" = '[]' ] && [ -z "$(st 'select(.step == "picked" and .issue == 0)')" ] \
    || fail "with the blocked commit $l1 at origin, redpick picked its fix card or kept its entry (exit $RC): $(cat "$T/$CASE/run.out")"
}

# Review finding E10. Bug it catches: a queued fix card's entry whose commit was then pushed by hand still stood for its
# check, so pushred() made no entry for a later commit the same check blocked, and redpick() dropped the old one: no
# fix card at all. c1's push is blocked (A, queued), A is pushed by hand, B lands and its real push fails the same check:
# the pick takes B's fix card.
t_pushblockmoved() {
  local l1 l2 c
  blockedpush
  git -C "$R" push -q --no-verify origin "$l1:refs/heads/main" || fail "the blocked commit could not be pushed by hand"
  echo b > "$R/b.txt" && git -C "$R" add b.txt && git -C "$R" commit -qm c2 && l2=$(git -C "$R" rev-parse HEAD) || fail "B could not be committed"
  jq -cn --arg s "$l2" '{card: "c2", issue: 2, step: "landed", time: "2026-11-18T10:05:00Z", tokens: {claude: 0, codex: 0}, result: "ok", sha: $s, reason: "", product: false}' >> "$ST/cards.jsonl"
  pnow
  fx_in 'cd "$R" && locked redpick'; c=$(cat "$T/$CASE/run.out"); c=${c%% *}
  [[ $c =~ -0$ ]] && [ "$(st "select(.card == \"$c\" and .step == \"picked\") | .mainRed")" = "$l2" ] \
    || fail "with A ($l1) pushed by hand and B ($l2) blocked by typecheck-web, redpick did not pick B's fix card: $(cat "$T/$CASE/run.out" "$ST/mainred.json" "$T/$CASE/push.out")"
}

# Review follow-up of #1683, finding 2. Bug it catches: a blocked fix card of A's push block stood for its check after A
# was pushed by hand (pushred() did not ask origin of a card with records), so B's block of the same check got no entry,
# and no fix card. c1's push is blocked (A), its fix card is picked and blocks, A is pushed by hand, B lands and its
# real push fails the same check: the pick takes B's fix card.
t_pushblockblockedmoved() {
  local l1 l2 ca c
  blockedpush
  fx_in 'cd "$R" && locked redpick'; ca=$(cat "$T/$CASE/run.out"); ca=${ca%% *}
  [[ $ca =~ -0$ ]] || fail "A's fix card was not picked (redpick): $(cat "$T/$CASE/run.out")"
  jq -cn --arg c "$ca" '{card: $c, issue: 0, step: "blocked", time: "2026-11-18T10:03:00Z", tokens: {claude: 0, codex: 0}, result: "failed", sha: "", reason: "tests failed"}' >> "$ST/cards.jsonl"
  git -C "$R" push -q --no-verify origin "$l1:refs/heads/main" || fail "the blocked commit could not be pushed by hand"
  echo b > "$R/b.txt" && git -C "$R" add b.txt && git -C "$R" commit -qm c2 && l2=$(git -C "$R" rev-parse HEAD) || fail "B could not be committed"
  jq -cn --arg s "$l2" '{card: "c2", issue: 2, step: "landed", time: "2026-11-18T10:05:00Z", tokens: {claude: 0, codex: 0}, result: "ok", sha: $s, reason: "", product: false}' >> "$ST/cards.jsonl"
  pnow
  fx_in 'cd "$R" && locked redpick'; c=$(cat "$T/$CASE/run.out"); c=${c%% *}
  [[ $c =~ -0$ ]] && [ "$c" != "$ca" ] && [ "$(st "select(.card == \"$c\" and .step == \"picked\") | .mainRed")" = "$l2" ] \
    || fail "with A ($l1) pushed by hand, its fix card $ca blocked, and B ($l2) blocked by typecheck-web, redpick did not pick B's fix card: $(cat "$T/$CASE/run.out" "$ST/mainred.json" "$T/$CASE/push.out")"
}

# Review follow-up of #1683, finding 1. Bug it catches: a push block at a commit whose main-red fix card had blocked was
# added to that card's entry, which kept the blocked card, so redpick() made no fix card for the block until a person
# retried it. Main is red at c1's commit, its fix card cx blocked; the push of that commit fails typecheck-web
# (pushred(), as the push files it): the entry is given a new fix card, named in the record.
t_pushblockblockedred() {
  local l1 c
  pfix
  jq -cn --arg s "$l1" '{reds: [{sha: $s, cases: [{case: "lib/a.test.sh: adds", file: "lib/a.test.sh", by: "c9", files: ["lib/a.test.sh"], last: ""}], card: "cx"}]}' > "$ST/mainred.json"
  jq -cn '{card: "cx", issue: 0, step: "picked", time: "2026-11-18T10:01:00Z", tokens: {claude: 0, codex: 0}, result: "ok", sha: "", reason: "", mainRed: "x"}, {card: "cx", issue: 0, step: "blocked", time: "2026-11-18T10:02:00Z", tokens: {claude: 0, codex: 0}, result: "failed", sha: "", reason: "tests failed"}' >> "$ST/cards.jsonl"
  fx_in "cd \"\$R\" && pushred $l1 typecheck-web c1 1 && locked redpick"; c=$(cat "$T/$CASE/run.out"); c=${c%% *}
  [[ $c =~ -0$ ]] && [ "$(jq -r .reds[0].card "$ST/mainred.json")" = "$c" ] && [ "$(jq -r .reds[0].push.check "$ST/mainred.json")" = typecheck-web ] \
    || fail "with main red at $l1 and its fix card cx blocked, pushred $l1 typecheck-web c1 1 then redpick did not give the entry a new fix card: $(cat "$T/$CASE/run.out" "$ST/mainred.json")"
}

# Second review, E1: a main-red entry with cases and a push block (pushred() on a commit main is red at). Its cases pass
# on main (redsetup's ok.txt), its push check does not.
pushredcases() {
  redsetup $'one\nc.test'
  jq -c '.reds[0].push = {check: "typecheck-web", card: "c1", issue: 1}' "$ST/mainred.json" > "$STUB/red.new" && mv "$STUB/red.new" "$ST/mainred.json" \
    || fail "the push block could not be added to the entry"
}
# Bug it catches: cardbuild() closed the fix card before its build (redgreen(): its cases pass on main) while the push
# check it was made for still failed. The build session starts, and the card is not closed.
t_pushredbuild() {
  local out
  pushredcases; out=$(redbuild)
  [ "$(wc -l < "$STUB/sessions" 2>/dev/null)" = 1 ] && [ -z "$(st 'select(.step == "closed")')" ] \
    || fail "cardbuild on fix card cfix (cases pass on main, push block typecheck-web) closed it, or started no build session: $out: $(st '"\(.step) \(.reason)"' | tr '\n' ,)"
}
# Bug it catches: nochange() ran the cases of a fix card with no change again on main, found them passing and closed it
# as not needed while the push check still failed. It is blocked, as any card with no change.
t_pushrednochange() {
  local out
  pushredcases
  jq -c '.reds[0].card = "cfix"' "$ST/mainred.json" > "$STUB/red.new" && mv "$STUB/red.new" "$ST/mainred.json" \
    && git -C "$R" worktree add -q --detach "$T/$CASE/cards/cfix" HEAD || fail "the fix card's worktree could not be made"
  out=$(eng 'nochange cfix 0 "$CONVEYOR_CARDS/cfix" brief' 2>&1)
  [ -z "$(st 'select(.card == "cfix" and .step == "closed")')" ] && [ -n "$(st 'select(.card == "cfix" and .step == "blocked")')" ] \
    || fail "nochange on fix card cfix (no change; cases pass on main, push block typecheck-web) closed it, or did not block it: $out: $(st 'select(.card == "cfix") | "\(.step) \(.reason)"' | tr '\n' ,)"
}
# Bug it catches: bugproof() proved the fix card's change by its cases (redproof()), which pass on main without it, so
# exit 3 closed the card as already done while the push check still failed. It is checked as any bug card.
t_pushredproof() {
  local got
  pushredcases; got=$(redcheck changed)
  [ "$(head -n 1 <<<"$got")" != "exit 3" ] && [[ $got != *"closes as already done"* ]] \
    || fail "bugproof on fix card cfix (cases pass on main, push block typecheck-web) closed it as already done: $got"
}

# A push block that joins fix card cfix's entry while its cases run. The callers read `.push == null` before the cases
# run (cardbuild(), nochange()), and the other writer, the real pushred() (under the main-red record's lock, as the
# push files it), adds the block at the weak point: after the cases ran and the closer (redclosed(), redreplaced())
# began, just before it takes the main-red record's lock (flock, wrapped, when the closer itself calls it). So the close
# sees the block only if it reads `.push` under that lock: a closer that read it before the lock would close the card.
# What must stay true: a fix card whose entry holds a push block does not close, and the entry keeps the block and
# names the card (redpick() skips a card with lines; a closed one would leave the block with no fix).
PUSHJOIN='flock() { case ${FUNCNAME[1]} in redclosed | redreplaced) pushred "$(jq -r .reds[0].sha "$MAINRED")" typecheck-web c1 1 > /dev/null 2>&1 ;; esac; command flock "$@"; }'
pushjoinkept() { # <the call that was checked>
  [ -z "$(st 'select(.card == "cfix" and .step == "closed")')" ] && [ -n "$(st 'select(.card == "cfix" and .step == "blocked")')" ] \
    && [ "$(jq -r '.reds[0] | "\(.card) \(.push.check)"' "$ST/mainred.json")" = "cfix typecheck-web" ] \
    || fail "$1, with a push block of typecheck-web joining cfix's entry while its cases ran, closed cfix, did not block it, or the entry lost the block or the card: $(st 'select(.card == "cfix") | "\(.step) \(.reason)"' | tr '\n' ,) $(cat "$ST/mainred.json")"
}
# Bug it catches: cardbuild() read no push block, redgreen() found the cases passing, and greenclose() closed the card
# as already done (redclosed() checked only for new cases) after pushred() added the block. It is blocked, naming why.
t_pushredjoinbuild() {
  local out
  redsetup $'one\nc.test'
  jq -c '.reds[0].card = "cfix"' "$ST/mainred.json" > "$STUB/red.new" && mv "$STUB/red.new" "$ST/mainred.json" \
    && git -C "$R" worktree add -q --detach "$T/$CASE/cards/cfix" HEAD || fail "the fix card's worktree could not be made"
  out=$(eng "$PUSHJOIN"'
    session() { echo x >> "$STUB/sessions"; return 1; }
    c=cfix n=0 br="" mode="" wt=$CONVEYOR_CARDS/cfix sprompt=brief sf="" waitsec=4 mainsec=0 go=end; issue=$(redissue cfix) && cardbuild' 2>&1)
  pushjoinkept "cardbuild on cfix (cases pass on main): $out"
  [[ $(st 'select(.card == "cfix" and .step == "blocked") | .reason') == *'a push block joined its entry'* ]] \
    || fail "cardbuild on cfix: the blocked reason does not say a push block joined its entry: $(st 'select(.card == "cfix") | .reason')"
}
# Bug it catches: nochange() read no push block, redproof() found the cases passing (exit 3), and the card closed as not
# needed after pushred() added the block.
t_pushredjoinnochange() {
  local out
  redsetup $'one\nc.test'
  jq -c '.reds[0].card = "cfix"' "$ST/mainred.json" > "$STUB/red.new" && mv "$STUB/red.new" "$ST/mainred.json" \
    && git -C "$R" worktree add -q --detach "$T/$CASE/cards/cfix" HEAD || fail "the fix card's worktree could not be made"
  out=$(eng "$PUSHJOIN"'; nochange cfix 0 "$CONVEYOR_CARDS/cfix" brief' 2>&1)
  pushjoinkept "nochange on cfix (no change; cases pass on main): $out"
}
# Bug it catches: nochange() read no push block, the cases still failed on main, and redreplaced() closed the card as
# replaced by cnew1 and cnew2 (they hold its cases, not the push check) after pushred() added the block. The fixture is
# mainredreplaced.test.sh's replfix().
t_pushredjoinreplaced() {
  local out
  replfix '[{"sha": "new1", "cases": [{"case": "a.test: one", "file": "a.test"}], "card": "cnew1"},
    {"sha": "new2", "cases": [{"case": "c.test", "file": "c.test"}], "card": "cnew2"}]' \
    '[{"card": "cnew1", "step": "picked"}, {"card": "cnew2", "step": "picked"}]'
  out=$(eng "$PUSHJOIN"'; nochange cfix 0 "$CONVEYOR_CARDS/cfix" brief' 2>&1)
  pushjoinkept "nochange on cfix (no change; cases fail on main, held by cnew1 and cnew2 on the belt): $out"
}
