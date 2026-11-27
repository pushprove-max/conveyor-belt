#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 300
# Engine cases: a card does not start its test step's runs while main is red (cardland.sh mainredhold(), claim.sh settle(),
# mainred.sh redhere() and redholdwait()): with a main-red entry for main's commit whose fix card is not landed, it waits
# for main to change; once main is at a commit with no such entry, it runs them. Only a card of a loop with no limit on its
# picks waits (run.sh cardrun(): LOOPFIX), as only that loop is sure to start the fix card.
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"

# Card c7's test step as card() calls cardtest() for it, in a loop with no limit on its picks (LOOPFIX), with every step around its own run stubbed: tests() only writes a
# line to $T/$CASE/own, gather() (the batch) one to $T/$CASE/gather, settle() ends its wait at once unless the case sets
# REALSETTLE, and the wait for main (redholdwait()) runs for real.
# redholdsetup makes main and the worktree. <commands> run first (they file the main-red entry, set c7's ready file or
# claim, change a stub); then cardtest() is called <times> times, each printing its go and how many times the tests ran
# so far. Prints through fx_in's run.out.
redholdsetup() { setup "[$(issue 7 2026-01-01)]"; fx_wt 'echo seven >> a.txt' b.txt base; }
redholdcard() { # <commands> <times>; after redholdsetup
  fx_in 'cd "$R"; LOOPFIX=1 c=c7 n=7 wt=$FXWT issue="{}" sprompt="" br="" parsecheck="" tmain="" away="" apart="" me=$$ cmsg=x mates=() mainsec=0 waitsec=0 behind="[]" LIVE=0.2
    lintgate() { return 0; }; checks() { :; }; treecheck() { :; }; testedhere() { return 1; }
    gather() { echo x >> "$T/$CASE/gather"; return 1; }; turntake() { :; }; tests() { echo own >> "$T/$CASE/own"; return 0; }
    [ -n "${REALSETTLE:-}" ] || settle() { return 0; }; s=$(git rev-parse "refs/heads/$BRANCH"); '"$1"'
    for i in $(seq '"$2"'); do go=end; cardtest; echo "pass $i: go=$go tests run $(cat "$T/$CASE/own" 2>/dev/null | wc -l)"; done'
}
# The main-red record with two entries, as it is when a fix card of an older commit is still open as a newer commit goes
# red: card c7's entry for <older commit>, and card cnew's for <main's commit>.
redtwo() { # <main's commit>
  jq -cn --arg s "$1" '{reds: [{sha: "old", cases: [{case: "a.test: one"}], card: "c7"}, {sha: $s, cases: [{case: "a.test: two"}], card: "cnew"}]}' > "$MAINRED"
}
# Two passes of c7's test step in the background, with <commands> first;
# once its live record says it waits for main, no test or batch has run; then main moves to a commit the record holds no
# entry for, <what to do once main has moved> runs, and the case waits for the passes.
# Background: the wait is a loop of the card's own, so only its live record shows that the card stands in it.
redholdwaits() { # <commands> [<a command of this shell: what to do once main has moved>]
  local first
  ( redholdcard "$1" 2 ) & first=$!
  wait_until "grep -qs 'waiting for main to change: a.test: one fail on main at' '$T/$CASE/cards/c7.live' || grep -qs '^pass' '$T/$CASE/run.out'" 'cat "$T/$CASE/run.out"' \
    || fail "the card did not wait for main to change with main red at its commit: $(cat "$T/$CASE/run.out" 2>/dev/null)"
  [ ! -e "$T/$CASE/own" ] && [ ! -e "$T/$CASE/gather" ] || fail "the card's tests or a batch ran while main was red at its commit: $(cat "$T/$CASE/run.out" 2>/dev/null)"
  git -C "$R" commit -q --allow-empty -m "main moves" || fail "main could not move"
  ${2:-:}
  wait "$first"
}

# One pass of c7's test step, with <commands> first, that must run its tests at once: it fails, naming <what it checks>,
# when the card waits for main (its live record) or does not run its tests once. Background: a card that waits does so
# for good, so the case ends on the pass or the live record, whichever comes first, not on its time limit.
redholdnow() { # <commands> <what it checks>; after redholdsetup
  local first
  ( redholdcard "$1" 1 ) & first=$!
  wait_until "grep -qs '^pass 1' '$T/$CASE/run.out' || [ -e '$FXWT.live' ]" 'cat "$T/$CASE/run.out"' || fail "$2: the card did not end its pass: $(cat "$T/$CASE/run.out" 2>/dev/null)"
  [ "$(cat "$T/$CASE/run.out")" = 'pass 1: go= tests run 1' ] || fail "$2: the card did not run its tests at once: $(cat "$T/$CASE/run.out") $(cat "$FXWT.live" 2>&1)"
  wait "$first" || : # fx_in's own status is that of a read of a file a fix card leaves; the pass above is what is checked
}

# Bug it catches (#1592): a card's Test step started with main red at its commit, the run failed on main's own failure
# and was run again on main, 25 of 34 failed runs in a day. With the entry for main's commit and its fix card open, the
# card's tests do not run: it waits (its live record says for main to change), and once main moves past that commit
# its next pass runs them. Main moves to a commit the record holds no entry for, and the card does not stay held there
# (a card that reaches its test step there starts its tests). Run in the background: the wait is polled as it runs.
t_mainredholdwait() {
  redholdsetup
  redholdwaits 'mainred c1 "a.test: one" a.test "$s"; echo "{\"issue\":7}" > "$wt.ready"'
  [ "$(grep '^pass' "$T/$CASE/run.out")" = "$(printf '%s\n' 'pass 1: go=again tests run 0' 'pass 2: go= tests run 1')" ] \
    || fail "once main moved the card did not go on to run its tests on its next pass: $(cat "$T/$CASE/run.out")"
}

# Bug it catches: a card whose tests passed on the change it holds (testedhere()) skipped the wait, and went on to form a
# batch (gather()), whose run on main would fail on main's own failure. It waits as any card: redholdwaits() fails when
# gather() was asked while main was red (the card's worktree is at main's commit then, so gather() is asked for it). Its
# ready file holds the pass, so it stays: the card keeps its pass and its place in batching.
t_mainredholdbatch() {
  redholdsetup
  redholdwaits 'mainred c1 "a.test: one" a.test "$s"; testedhere() { return 0; }; echo "{\"issue\":7,\"tested\":true}" > "$wt.ready"'
  [ "$(grep '^pass' "$T/$CASE/run.out")" = "$(printf '%s\n' 'pass 1: go=again tests run 0' 'pass 2: go= tests run 0')" ] \
    || fail "the card with its pass did not wait for main and then go on: $(cat "$T/$CASE/run.out")"
  jq -e '.tested == true' "$FXWT.ready" >/dev/null 2>&1 || fail "the card lost the ready file that holds its pass while it waited: $(cat "$FXWT.ready" 2>&1)"
}

# Bug it catches: the wait taken for any card: with no main-red entry, the Test step starts as before, running its tests
# at once and waiting for nothing.
t_mainredholdnone() {
  redholdsetup
  redholdcard : 1
  [ "$(cat "$T/$CASE/run.out")" = 'pass 1: go= tests run 1' ] && [ ! -e "$T/$CASE/cards/c7.live" ] \
    || fail "with no main-red entry the card's tests did not run at once: $(cat "$T/$CASE/run.out")"
}

# Bug it catches: a main-red fix card (c7 here, named by its entry of an older commit) waited on the entry of another fix
# card for main's commit. The newer entry's card cannot take the slot beyond the card cap while c7 holds it, and both
# waited for good.
t_mainredholdfix() {
  redholdsetup
  redholdnow 'redtwo "$s"; n=0' "a fix card waited on another fix card's entry"
}

# Bug it catches (E6): every card of issue 0 went on at once, as a main-red fix card does, and with it a Tests page card
# and a land-branch card (issue 0 too, no entry names them), whose tests then failed on main's own failure. Only a card
# an entry names is exempt: this card has issue 0 and a branch, and waits for main to change as any card does.
t_mainredholdzero() {
  redholdsetup
  redholdwaits 'mainred c1 "a.test: one" a.test "$s"; n=0 br=feature'
  [ "$(grep '^pass' "$T/$CASE/run.out")" = "$(printf '%s\n' 'pass 1: go=again tests run 0' 'pass 2: go= tests run 1')" ] \
    || fail "a card of issue 0 that no entry names did not wait for main and then go on: $(cat "$T/$CASE/run.out")"
}

# Bug it catches (E7): a run limited by --only (ONLY) started no fix card (pick.sh; run.sh redfix()) and its loop lets no
# second one start, yet its card waited on main's open entry for a fix that never came. In that run it starts its tests.
t_mainredholdonly() {
  redholdsetup
  redholdnow 'mainred c1 "a.test: one" a.test "$s"; ONLY="[7]"' "a card of a run limited by --only waited for a fix card that run cannot start"
}

# Bug it catches: a card waited on an entry whose fix card landed, a red main that no longer is one.
t_mainredholdlanded() {
  redholdsetup
  redholdnow 'mainred c1 "a.test: one" a.test "$s"; jq -c ".reds[0].card = \"cfix\"" "$MAINRED" > "$MAINRED.new" && mv "$MAINRED.new" "$MAINRED"; append "$(line cfix 0 landed ok "{}")"' \
    "the card waited on an entry whose fix card landed"
}

# Bug it catches: a card that has given way GIVEWAY times kept its claim (giveway() refused to give it up), so it ran its
# tests on red main, and they failed there on main's cases. It now gives its files way for the wait (giveway() red), so
# the fix card of main's commit that needs them is not held up, and waits for main as any card does. Its claim, with
# gave at 3 and settle() stubbed, is away after the wait: nothing claimed it again.
t_mainredholdclaim() {
  redholdsetup
  redholdwaits 'mainred c1 "a.test: one" a.test "$s"; echo "{\"pid\":$$,\"paths\":[\"a.txt\"],\"held\":true,\"gave\":3}" > "$wt.claim"'
  [ "$(jq -c '[.held, .away]' "$FXWT.claim" 2>&1)" = '[false,true]' ] \
    || fail "a card that had given way 3 times kept its claim while it waited for main: $(cat "$FXWT.claim" 2>&1)"
}

# Bug it catches: a card that had given way GIVEWAY times, whose tests then failed only on cases that fail on main too,
# waited for main to change in cardfailed() with its claim held, as giveway() refused it: the main-red fix card that
# needs the same files waited at its claim, and nothing freed either. cardfailed() runs its main route, each step
# around the wait stubbed: mainwaited() prints the claim as the wait starts, and settle() stops the card.
t_mainredfailclaim() {
  # shellcheck disable=SC2034 # FXWT is read by fx_in, a fix card's worktree; this case has none
  local FXWT=$T/$CASE/none
  setup '[]'
  # shellcheck disable=SC2016 # expanded by fx_in's eval
  fx_in 'c=c7 n=7 wt=$T/$CASE/c7 rc=1 own="" sec=1 mainsec=0 br="" sprompt="" issue=""
    echo "{\"pid\":$$,\"paths\":[\"a.txt\"],\"held\":true,\"gave\":3}" > "$wt.claim"
    depsmissing() { :; }; voidrun() { return 1; }; testfails() { :; }; testroute() { echo main; }
    verdicts() { echo "{\"mainRun\":{\"sha\":\"abc\"},\"verdicts\":[{\"case\":\"a.test: one\",\"verdict\":\"main\"}]}"; }
    record() { :; }; failline() { :; }; testrulespass() { :; }; began() { :; }; unmate() { :; }; redbrief() { :; }; settle() { return 1; }
    mainwaited() { echo "waits with claim $(jq -c "[.held, .away]" "$wt.claim")"; }
    cardfailed || :'
  grep -qx 'waits with claim \[false,true\]' "$T/$CASE/run.out" \
    || fail "cardfailed of a card at the give-way limit whose failed case fails on main waited with its claim held: $(tr '\n' '|' < "$T/$CASE/run.out")"
}

# Fix card cfix of the entry for main's commit lands (the entry then holds main red no more), run from a case's stubs.
redclose() { jq -c '.reds[0].card = "cfix"' "$MAINRED" > "$MAINRED.new" && mv "$MAINRED.new" "$MAINRED"; append "$(line cfix 0 landed ok "{}")"; }
# The stubs around settle()'s own tests for a card at its claim, run in fx_in's shell: it waits on card c8 until the case frees it
# with $T/$CASE/free; its own tests write a line to $T/$CASE/own.
redsettlestubs() {
  claim() { [ -e "$T/$CASE/free" ] || echo "{\"on\":\"c8\",\"paths\":[\"a.txt\"]}"; }; stackto() { return 1; }; turnfree() { :; }; began() { :; }; capowed() { :; }
  checks() { return 0; }; tests() { echo own >> "$T/$CASE/own"; return 0; }; record() { :; }; testrulespass() { :; }
  testrec() { echo "{}"; }; firstrun() { echo "{}"; }; slowrec() { echo "{}"; }; slowtests() { :; }
}

# Bug it catches (E10, E11): main moved past the red commit while the card waited at its claim for a card that changes the
# same lines (the repair landed on other files), and settle() ran the card's own tests on its worktree, still on the red
# commit, before the fit onto main: they failed on the old failure. The entry for that commit is in the record still, its fix
# card landed, so the card waits out the claim with no run, is fitted onto main, and keeps its ready file (it has no pass to
# keep: a run after the fit marks that file, and a batch takes only a card that holds one). Real settle(), the real git.
t_mainredholdbase() {
  local first
  redholdsetup
  tune '.landBatch = 8'
  # shellcheck disable=SC2016 # run by fx_in's eval
  ( fx_in 'cd "$R"; LOOPFIX=1 LIVE=0.1 waitsec=0 mainsec=0 parsecheck="" behind="[]"; s=$(git rev-parse "refs/heads/$BRANCH")
      mainred c1 "a.test: one" a.test "$s"; redclose; git commit -q --allow-empty -m "the repair lands"
      echo "{\"issue\":7}" > "$FXWT.ready"; redsettlestubs
      settle c7 7 "$FXWT" prompt land "{}"; echo "settle $? at $(git -C "$FXWT" rev-parse HEAD) of main $(git rev-parse "refs/heads/$BRANCH")"' ) & first=$!
  wait_until "[ -e '$FXWT.idle' ] || [ -e '$T/$CASE/own' ]" 'cat "$T/$CASE/run.out"' || fail "the card's wait did not start: $(cat "$T/$CASE/run.out" 2>/dev/null)"
  [ ! -e "$T/$CASE/own" ] || fail "a card waiting at its claim ran its tests on its worktree, which is on the red commit, after main moved past it"
  : > "$T/$CASE/free"
  wait "$first"
  [ ! -e "$T/$CASE/own" ] && grep -Eq '^settle 0 at ([0-9a-f]+) of main \1$' "$T/$CASE/run.out" \
    || fail "the card was not fitted onto main with no test run once its claim was free: $(cat "$T/$CASE/run.out" 2>/dev/null)"
  jq -e '.issue == 7' "$FXWT.ready" >/dev/null 2>&1 || fail "the card lost its ready file while it waited at its claim: $(cat "$FXWT.ready" 2>&1)"
}

# What the card does once main has moved, in t_mainredholdstale: it waits on card c8's claim (settle() writes its live
# record, then <worktree>.idle at the end of a look that found nothing to run); its tests have not run yet; c8 lets go.
redstalewait() {
  wait_until "grep -qs 'waiting on card c8' '$T/$CASE/cards/c7.live' && [ -e '$FXWT.idle' ]" 'cat "$T/$CASE/run.out"' \
    || fail "the card did not wait on the claim of card c8 once main moved: $(cat "$T/$CASE/run.out" 2>/dev/null)"
  [ ! -e "$T/$CASE/own" ] || fail "the card ran its tests, on the worktree of the red commit, while it waited on a claim after main moved: $(cat "$T/$CASE/own")"
  : > "$T/$CASE/free"
}

# Bug it catches (E8, E11): main moved while the card waited, and the card went on to settle() for its claim with its
# worktree still on the red commit and its ready file untested. With batches on, settle() ran the card's own tests there
# (main is no longer red at its commit, so redhere() let them): they failed on the old failure, before the fit onto main.
# Taking the ready file away to stop that run left the card's pass after the wait unmarked (tested() marks a file that
# exists), so no batch took the card. It waits out card c8's claim with no run, is fitted onto main, and its tests run there
# and mark its ready file. Real settle() and mainredhold(), the real git; the claim of c8 stands until the case frees it.
t_mainredholdstale() {
  local -x REALSETTLE=1 # read by redholdcard(): the real settle(), not its stub
  redholdsetup
  tune '.landBatch = 8'
  redholdwaits 'mainred c1 "a.test: one" a.test "$s"; echo "{\"issue\":7}" > "$wt.ready"
      claim() { [ -e "$T/$CASE/free" ] || echo "{\"on\":\"c8\",\"paths\":[\"a.txt\"]}"; }; stackto() { return 1; }; turnfree() { :; }; began() { :; }; capowed() { :; }
      lintwait() { return 0; }; record() { :; }; testrulespass() { :; }; testrec() { echo "{}"; }; firstrun() { echo "{}"; }; slowrec() { echo "{}"; }; slowtests() { :; }
      tests() { git -C "$wt" rev-parse HEAD >> "$T/$CASE/own"; return 0; }' redstalewait
  [ "$(grep '^pass' "$T/$CASE/run.out")" = "$(printf '%s\n' 'pass 1: go=again tests run 0' 'pass 2: go= tests run 1')" ] \
    || fail "once main moved and the claim was free the card did not run its tests once: $(cat "$T/$CASE/run.out")"
  [ "$(cat "$T/$CASE/own")" = "$(git -C "$R" rev-parse HEAD)" ] \
    || fail "the card's tests did not run on main as it is now: $(cat "$T/$CASE/own"), main: $(git -C "$R" rev-parse HEAD)"
  jq -e '.tested == true' "$FXWT.ready" >/dev/null 2>&1 \
    || fail "the card's ready file was lost while it waited, so its pass after the wait was not marked and no batch takes it: $(cat "$FXWT.ready" 2>&1)"
}

# Bug it catches (E9): `land-branch`, which runs no loop and may be landing the very repair of main, waited for main to
# change as any card does, and so would a card of a run of a number of cards (`run 1`) once its picks are spent: no fix card
# starts, and the wait never ends. cardrun() marks (LOOPFIX) only a card of a loop with no limit on its picks; without the
# mark the card runs its tests at once, with the entry for main's commit open.
t_mainredholdnoloop() {
  redholdsetup
  redholdnow 'mainred c1 "a.test: one" a.test "$s"; unset LOOPFIX' "a card that no loop with no limit on its picks runs waited for main"
}

# What a card sees in LOOPFIX when the loop's pick turn (turnpick(), with run()'s variables as t_locklimit sets them for a
# turn with room below the cap) starts it with <picks left> in run()'s `left`; the real cardrun(), card() only says.
redpickmark() { # <picks left>
  setup "[$(issue 7 2026-01-01)]"
  fx_in 'mkdir -p "$CARDS"; card() { echo "loopfix=${LOOPFIX:-none}"; }
    asking=1 urgent="" red="" building=0 cap=3 left='"$1"' pct="" running=0 serve=1 pusher="" started=0 waits="" ctl=$(ctl) issues=$(cat "$STUB/issues.json")
    declare -A mine=(); turnpick; wait'
}
# Bug it catches (E9): the mark never reached a card, or reached each card of a run of a number of cards: with no limit
# on its picks the loop starts a fix card whenever main is red, so its cards wait for it.
t_mainredholdunlimited() {
  redpickmark -1
  [ "$(cat "$T/$CASE/run.out")" = 'loopfix=1' ] || fail "a card of a loop with no limit on its picks was not marked: $(cat "$T/$CASE/run.out")"
}
# Bug it catches (E9): a card of `run 1` waited for a fix card its loop cannot pick once its one pick is spent.
t_mainredholdlimited() {
  redpickmark 1
  [ "$(cat "$T/$CASE/run.out")" = 'loopfix=none' ] || fail "a card of a loop with a limit on its picks was marked: $(cat "$T/$CASE/run.out")"
}
