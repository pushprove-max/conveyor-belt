#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 300
# Engine cases: a batch run again when main moved during its run reuses its last run's passes (rebatch(), batchkeep()),
# and is run again when what landed meanwhile shares a test file with it (sharedtests()); its run reuses no pass of a
# card whose change changed since its tests passed (batchkeep()).
# Its own file, with the fixture of batchreuse.test.sh (reusesetup): each case of the batch's reuse is a whole batch
# run, and together they were over the test step's CPU budget for one file.
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"

# The batch is formed again when main moved during its run (rebatch()): a product check fails, once, on its change on
# main as it moved, a red run, so it is run again there. s1, which both cards select, passed in the batch's last run
# with both in it, on their changes unchanged since, and every other case on its own card's change: the run again
# runs no case. Bug it catches: a batch run again ran the cases its last run had passed for the same cards.
t_batchreusemoved() {
  reusesetup "[$(issue 7 2026-01-01),$(issue 8 2026-01-02)]" 'b.txt s.test' 'x.txt x.test' 'y.txt y.test'
  echo 'grep -qx seven a.txt && grep -qx eight a.txt && [ ! -e "$STUB/moved" ] && { : > "$STUB/moved"; (cd "$R" && echo other > other.txt && git add other.txt && git commit -qm "another file"); }; :' >> "$STUB/test-cmd"
  printf '%s\n' '! git cat-file -e "$2:other.txt" 2>/dev/null || ! git show "$2:a.txt" | grep -qx eight || [ -e "$STUB/flaked" ] || { : > "$STUB/flaked"; echo "fails once"; exit 1; }' > "$STUB/once"
  tune --arg f "$STUB/once" '.checks += [$f]'
  out=$(loop run 2>&1) || fail "run exited non-zero: $out"
  c7=$(cardof 7); c8=$(cardof 8)
  grep -q "card $c7: a product check failed on its batch's change on main as it is now, a red run, so the batch is run again there: .*fails once" <<<"$out" \
    || fail "the batch was not run again on main as it moved: $out"
  [ "$(runs)" = "8 s1 y1 y2,7 s1 x1 x2,7 s1," ] || fail "the batch run again ran a case: $(runs): $out"
  # s1, which both cards' own passes and the batch's last run hold, counts once: five cases kept, not six. And x.test
  # and y.test, which the last run passed whole and each card's own pass names case by case, count once: not nine.
  grep -q "card $c7: its batch of 2 runs no case, each having passed on its cards' changes (5 kept)" <<<"$out" || fail "the batch run again did not say it runs no case, five kept: $out"
  [ "$(st 'select(.issue == 7 and .step == "test") | [.result, .selected.cases, .selected.kept] | tojson' | tail -n 1)" = '["pass",0,5]' ] \
    || fail "#7's last test line does not say no case ran and five passes were kept: $(st 'select(.issue == 7 and .step == "test")')"
  landedtogether "$c8 $c7" || fail "the two cards did not land as one batch: $(st 'select(.step == "landed")')"
  [ "$(cat "$R/other.txt")" = other ] && [ "$(sed -n '1p;$p' "$R/b.txt" | tr '\n' ' ')" = "seven eight " ] || fail "main does not hold both changes and the other file"
}

# Bug (#334: two changes that each passed alone failed together on main): a batch whose run passed while main moved
# landed on that run, though what landed meanwhile touched a test file of the batch's change. #7 changes lib/mine.sh;
# during the batch's run main changes lib/other.sh, and lib/mine-other.test.sh tests both (sharedtests()): the batch
# is tested again on main as it is now, not landed on the run before; and that run keeps none of the passes of the run
# before (a batch formed again of the same cards would else reuse them, batchkeep(), and run no case): its case m1 runs
# again after main moved.
t_batchsharedmoved() {
  reusesetup "[$(issue 7 2026-01-01),$(issue 8 2026-01-02)]" 'x.txt x.test' 'y.txt y.test' \
    'lib/mine.sh lib/mine-other.test.sh' 'lib/other.sh lib/mine-other.test.sh' 'lib/mine-other.test.sh lib/mine-other.test.sh'
  echo 'lib/mine-other.test.sh m1' >> "$STUB/cases"
  mkdir -p "$R/lib"; echo mine > "$R/lib/mine.sh"; echo other > "$R/lib/other.sh"; echo case1 > "$R/lib/mine-other.test.sh"
  git -C "$R" add lib; git -C "$R" commit -qm "two sources and their shared test"
  echo 'case $PWD in *-7) echo seven >> lib/mine.sh ;; esac' >> "$STUB/build"
  # #8 changes after its own run, so the batch's run runs its cases (a run of none would not start the test command),
  # and only those: checked below.
  echo 'd=$(echo ../*-8); echo more >> "$d/y.txt"; git -C "$d" add -A' > "$STUB/held-then"
  # Main moves at the batch's run of y.test.sh, once its cases are on the run's line: a later file's run adds its
  # cases to the last line of $STUB/runs (reusesetup), which `moved` would be.
  echo '[ "${CONVEYOR_TEST_FILE:-}" = y.test.sh ] && grep -qx seven a.txt && grep -qx eight a.txt && [ ! -e "$STUB/moved" ] && { : > "$STUB/moved"; echo moved >> "$STUB/runs"; (cd "$R" && echo main >> lib/other.sh && git commit -qam "main changes the other source"); }; :' >> "$STUB/test-cmd"
  out=$(loop run 2>&1) || fail "run exited non-zero: $out"
  c7=$(cardof 7); c8=$(cardof 8)
  grep -q "card $c7: cards landed during its batch's run touch its test files too, so the batch is tested again: lib/mine-other.test.sh on main as it is now" <<<"$out" \
    || fail "the batch landed on its run though main's change shares a test file with it: $out"
  # A card whose change changed since its tests passed brings no pass (batchkeep()): the batch's first run (the line
  # before `moved`) runs y.test's two cases, as #8's y.txt changed after its own run, and not x.test's or m1, which #7
  # passed on its unchanged change.
  [ "$(grep -B1 -x moved "$STUB/runs" | head -n 1)" = "7 y1 y2" ] \
    || fail "the batch's first run did not run #8's changed cases alone: $(runs)"
  sed -n '/^moved$/,$p' "$STUB/runs" | grep -q ' m1\b' || fail "the shared test's case m1 did not run again after main moved: $(runs)"
  landedtogether "$c8 $c7" && [ "$(tail -n 1 "$R/lib/other.sh")" = main ] \
    && [ "$(tail -n 1 "$R/lib/mine.sh")" = seven ] || fail "both cards did not land as one batch on main as it moved: $(st 'select(.step == "landed")')"
  [ "$(cat "$R/y.txt" | tr '\n' ' ')" = "y more " ] || fail "main does not hold #8's change as it was tested: $(cat "$R/y.txt")"
}

# Bug it catches (#447): a batch run again on main as it moved for its shared test files (rebatch() exit 4) wrote no mark that the card's shared
# test files ran there for the change it holds (<worktree>.sharedran), so when another card landed on those files
# before it did, its test step ran them a third time. cardtest() is called as card() calls it, on card c7 of #7, with
# the steps around the runs stubbed: its batch's run again passes; then main moves onto a shared test file
# (sharedtests()), and its own tests do not run again.
# Bug it catches too: only the card was marked, so the other card c8, unmarked, had the batch run a third time when
# main moved onto a file its batch passes (.bpass) held. c8's mark is its change's after that run.
# And: a run again for a product check's red run (rebatch() exit 3, not 4 for the shared files) keeps the cards'
# passes, so it may run no shared file; it marked every card, and the next landing on a shared file was not run again
# (exit 5).
# And: a run again for the shared files marked every card of the batch, so c9, whose change shared no file with main's
# (not among rebatch()'s sharers), had used up its run again, and main's next change to a file it shares landed unrun.
t_batchrerunshared() {
  setup "[$(issue 7 2026-01-01)]"; fx_wt 'echo seven >> a.txt' b.txt base
  git -C "$R" worktree add -q --detach "$T/$CASE/cards/c8" main && echo eight > "$T/$CASE/cards/c8/c.txt" && git -C "$T/$CASE/cards/c8" add -A || fail "c8's change"
  fx_in 'cardpatch "$CARDS/c8" > "$T/$CASE/patch8" || exit 3
    c=c7 n=7 wt=$FXWT issue="{}" sprompt="" br="" parsecheck="" tmain="" away="" apart="" me=$$ cmsg=x mates=(c7 c8 c9)
    lintgate() { return 0; }; checks() { :; }; treecheck() { :; }; testedhere() { return 0; }; sharedtests() { return 1; }; landedsince() { :; }
    gather() { return 1; }; rebatch() { return 3; }; batch() { return 0; }; turntake() { :; }; tests() { echo own >> "$T/$CASE/own"; return 0; }
    cardtest; [ "$rc" = 0 ] || exit 3; [ ! -e "$wt.sharedran" ] && [ ! -e "$CARDS/c8.sharedran" ] || exit 5
    mates=(c7 c8 c9); rebatch() { sharers=(c7 c8); sharedown=(s.test.sh s.test.sh); return 4; }
    batch() { printf "%s\n" "{\"units\": [\"s.test.sh\"]}" | tee "$wt.bpass" > "$CARDS/c8.bpass"; }; cardtest; [ "$rc" = 0 ] || exit 3; cardpatch "$wt" > "$T/$CASE/patch" || exit 3
    [ ! -e "$CARDS/c9.sharedran" ] || exit 6
    mates=(); sharedtests() { echo s.test.sh; }; cardtest; [ "$rc" = 0 ] || exit 4'
  [ "$RC" = 0 ] && [ -s "$T/$CASE/patch" ] && cmp -s "$T/$CASE/patch" "$FXWT.sharedran" && [ ! -e "$T/$CASE/own" ] \
    || fail "a batch run again on main as it moved did not mark its shared run, or its tests ran again, or c9, sharing no file, was marked (exit $RC): $(cat "$T/$CASE/run.out")"
  [ -s "$T/$CASE/patch8" ] && cmp -s "$T/$CASE/patch8" "$T/$CASE/cards/c8.sharedran" || fail "the batch's other card c8 was not marked after the batch's run again"
}

# c8, on main as it was (old), changes lib/claim.sh, which the test map (map.json) gives lib/a.test.sh; lib/opt.test.sh
# is lib/speed.sh's. Main then runs <main's change> (old to new). W holds new with c8's change, as rebatch() and
# stalepass() have the batch's worktree. run.out holds what sharedtests() prints for <asked> (c8, or c7: W itself) asked
# with W, and its exit. With <lone> 1, c8 is asked as card() asks it: alone, its change moved onto main as it is now;
# with own, it is asked with W for its own change's files alone (rebatch()'s sharers).
mateshared() { # <main's change: commands run in main> [<asked>] [<lone>: 1 or own]
  setup '[]'; tune '.test.map = "map.json"'; mkdir -p "$R/lib" "$T/$CASE/cards"
  echo '{"lib/claim.sh": ["lib/a.test.sh"], "lib/speed.sh": ["lib/opt.test.sh"]}' > "$R/map.json"
  for f in claim.sh speed.sh a.test.sh opt.test.sh; do echo x > "$R/lib/$f"; done
  git -C "$R" add map.json lib && git -C "$R" commit -qm base || fail "main's files"
  git -C "$R" worktree add -q --detach "$T/$CASE/cards/c8" main && echo y >> "$T/$CASE/cards/c8/lib/claim.sh" && git -C "$T/$CASE/cards/c8" add -A || fail "c8's change"
  fx_in 'cd "$R" || exit 9; old=$(git rev-parse HEAD); '"$1"' && git commit -qam moved || exit 9
    W=$CARDS/c7; git worktree add -q --detach "$W" main && git -C "$CARDS/c8" diff --cached --binary | git -C "$W" apply --index || exit 9
    if [ "'"${3:-}"'" != 1 ]; then sharedtests "$CARDS/'"${2:-c8}"'" "$old" "$(git rev-parse HEAD)" "$W" '"${3:-}"'
    else git -C "$CARDS/c8" diff --cached --binary > "$CARDS/p8" && git -C "$CARDS/c8" reset -q --hard "$(git rev-parse HEAD)" && git -C "$CARDS/c8" apply --index "$CARDS/p8" || exit 9
      sharedtests "$CARDS/c8" "$old"; fi; echo "exit $?"'
}

# Bug it catches: the batch's own card c7, its worktree W lent to the batch (W.lent: old, its change W.bpatch, to
# lib/speed.sh), was asked on what W holds: c8's change to lib/claim.sh, so main's change to lib/a.test.sh counted as
# c7's, and rebatch() marked c7's change as run again (sharers) though no file of it ran again.
t_matesharedlent() {
  mateshared 'echo y >> lib/speed.sh && git diff --binary --no-renames > "$CARDS/c7.bpatch" && echo x > lib/speed.sh && echo "$old" > "$CARDS/c7.lent" && echo z >> lib/a.test.sh' c7
  [ "$RC" = 0 ] && [ "$(cat "$T/$CASE/run.out")" = 'exit 1' ] \
    || fail "main's change to lib/a.test.sh, which only c8's change selects, was shared with c7's lent worktree: exit $RC, $(cat "$T/$CASE/run.out")"
}

# Bug it catches: a card of a batch was asked on its own worktree, whose test map is main's before the run, so main's
# change to the map, giving lib/claim.sh lib/opt.test.sh too, selected no test of it: the batch landed with no run again.
t_matesharedmap() {
  mateshared 'echo '"'"'{"lib/claim.sh": ["lib/a.test.sh", "lib/opt.test.sh"], "lib/speed.sh": ["lib/opt.test.sh"]}'"'"' > map.json'
  [ "$RC" = 0 ] && grep -qx 'lib/opt.test.sh' "$T/$CASE/run.out" && grep -qx 'exit 0' "$T/$CASE/run.out" \
    || fail "c8's change did not share lib/opt.test.sh with main's new test map: exit $RC, $(cat "$T/$CASE/run.out")"
}

# Bug it catches: c8's batch passes (.bpass units) held lib/opt.test.sh, which the batch ran for c7, so main's change
# to that file alone counted as shared with c8 and ran the batch again. Of .bpass, c8's own units (by) count.
t_matesharedbpass() {
  mateshared 'echo z >> lib/opt.test.sh && printf "%s\n" "{\"units\": [\"lib/a.test.sh\", \"lib/opt.test.sh\"], \"by\": {\"c7\": [\"lib/opt.test.sh\"], \"c8\": [\"lib/a.test.sh\"]}}" > "$CARDS/c8.bpass"'
  [ "$RC" = 0 ] && [ "$(cat "$T/$CASE/run.out")" = 'exit 1' ] \
    || fail "main's change to c7's lib/opt.test.sh was shared with c8 through the batch's passes: exit $RC, $(cat "$T/$CASE/run.out")"
}

# Bug it catches: a batch run's pass of lib/opt.test.sh, a test main linked to another card's change during the run, was
# given to c8 too (batchpass(): no card's own selection had it), so main's next change to that file made c8 a sharer
# (rebatch()), and the run again used up c8's: its own change (lib/claim.sh) selects lib/a.test.sh alone. Asked for its
# own change's files, c8 shares none.
t_matesharedown() {
  mateshared 'echo z >> lib/opt.test.sh && printf "%s\n" "{\"units\": [\"lib/opt.test.sh\"], \"by\": {\"c7\": [\"lib/opt.test.sh\"], \"c8\": [\"lib/opt.test.sh\"]}}" > "$CARDS/c8.bpass"' c8 own
  [ "$RC" = 0 ] && [ "$(cat "$T/$CASE/run.out")" = 'exit 1' ] \
    || fail "main's change to lib/opt.test.sh, which c8's own change does not select, was shared with c8's own change through a batch pass: exit $RC, $(cat "$T/$CASE/run.out")"
}

# Bug it catches: as t_matesharedbpass, with c8 asked as its own test step asks (card(): no batch worktree), which
# read every unit of .bpass: c8 ran its tests again for c7's file. Of .bpass, c8's own units (by) count there too.
t_matesharedbpasslone() {
  mateshared 'echo z >> lib/opt.test.sh && printf "%s\n" "{\"units\": [\"lib/a.test.sh\", \"lib/opt.test.sh\"], \"by\": {\"c7\": [\"lib/opt.test.sh\"], \"c8\": [\"lib/a.test.sh\"]}}" > "$CARDS/c8.bpass"' c8 1
  [ "$RC" = 0 ] && [ "$(cat "$T/$CASE/run.out")" = 'exit 1' ] \
    || fail "main's change to c7's lib/opt.test.sh was shared with c8 alone through the batch's passes: exit $RC, $(cat "$T/$CASE/run.out")"
}

# Bug it catches: the batch's run again for the shared files split, the card c7 passing and c8 failing, and c8 was
# marked as run again from c7's pass, so its next run again was skipped (exit 3); so was c7 when it was apart from that
# run, its change not applied there (exit 4). markshared() is called as card() calls it after batch(): mates the cards
# that passed, the card among them or not.
t_marksharedpassed() {
  setup '[]'; fx_wt 'echo seven >> a.txt' b.txt base
  git -C "$R" worktree add -q --detach "$T/$CASE/cards/c8" main && echo eight > "$T/$CASE/cards/c8/c.txt" && git -C "$T/$CASE/cards/c8" add -A || fail "c8's change"
  fx_in 'printf "%s\n" "{\"units\": [\"s.test.sh\\tt_s\"]}" | tee "$FXWT.bpass" > "$CARDS/c8.bpass"
    sharers=(c7 c8); sharedown=(s.test.sh s.test.sh); mates=(c7 c9); apart=""; markshared c7 "$FXWT"; [ -s "$FXWT.sharedran" ] && [ ! -e "$CARDS/c8.sharedran" ] || exit 3
    rm -f "$FXWT.sharedran"; mates=(c8); apart=1; markshared c7 "$FXWT"; [ ! -e "$FXWT.sharedran" ] && [ -s "$CARDS/c8.sharedran" ] || exit 4'
  [ "$RC" = 0 ] || fail "a card that did not pass the run again was marked as run again, or one that passed was not (exit $RC): $(cat "$T/$CASE/run.out")"
}

# Bug it catches: the run again for the shared files ran only the test file c8's change edits (testrun.sh listcmd()
# selects a card's own test files alone), not c7's shared p.test.sh, and c7 was marked as run again all the same: the
# next main change to p.test.sh landed unrun. Only c8, whose shared m.test.sh ran, is marked.
t_marksharedunrun() {
  setup '[]'; fx_wt 'echo seven >> a.txt' b.txt base
  git -C "$R" worktree add -q --detach "$T/$CASE/cards/c8" main && echo eight > "$T/$CASE/cards/c8/c.txt" && git -C "$T/$CASE/cards/c8" add -A || fail "c8's change"
  fx_in 'printf "%s\n" "{\"units\": [\"m.test.sh\\tt_m\"]}" | tee "$FXWT.bpass" > "$CARDS/c8.bpass"
    sharers=(c7 c8); sharedown=(p.test.sh m.test.sh); mates=(c7 c8); apart=""; markshared c7 "$FXWT"; [ ! -e "$FXWT.sharedran" ] && [ -s "$CARDS/c8.sharedran" ] || exit 3'
  [ "$RC" = 0 ] || fail "a card whose shared test file did not run in the run again was marked as run again, or one whose file ran was not (exit $RC): $(cat "$T/$CASE/run.out")"
}

# rebatch() called on cards c7 and c8 (each adds a file of its own, <n>.txt, its tests' passes the case t_<n> of
# <n>.test.sh in its .ready), the .sharedran of those <marked> its change's, after another card landed on main. sharedtests() is stubbed:
# s.test.sh is shared with each card of <shares> asked alone, and with the batch asked whole when one card shares it.
# run.out holds rebatch's exit, the batch's cards after it and the cards it found sharing a file (sharers); with
# <passed> 1, then the units each card selects (by) of a batch run that passes those cases and t_new, a case main
# added to 7.test.sh during the run (batchpass()). A card of <by a pass> shares it through a batch pass alone: asked
# for its own change's files (sharedtests() own), it shares none.
rebatchmarked() { # <shares: the cards' numbers, e.g. "7 8"> <marked: numbers> [<passed>] [<by a pass: numbers>]
  local n
  setup '[]'; mkdir -p "$T/$CASE/cards"; for n in $1; do : > "$T/$CASE/s$n"; done; for n in ${4:-}; do : > "$T/$CASE/p$n"; done
  for n in 7 8; do git -C "$R" worktree add -q --detach "$T/$CASE/cards/c$n" main && echo "$n" > "$T/$CASE/cards/c$n/$n.txt" && git -C "$T/$CASE/cards/c$n" add -A \
    && git -C "$T/$CASE/cards/c$n" diff --cached --binary --no-renames > "$T/$CASE/cards/c$n.bpatch" || fail "the change of card $n"; done
  fx_in 'cd "$R" || exit 9; W=$CARDS/c7
    for n in 7 8; do jq -cn --arg p "$(cardpatch "$CARDS/c$n")" --arg u "$n.test.sh" "{tested: true, patch: \$p, units: [\$u + \"\\tt_$n\"]}" > "$CARDS/c$n.ready" || exit 9; done
    for n in '"$2"'; do cardpatch "$CARDS/c$n" > "$CARDS/c$n.sharedran" || exit 9; done
    echo other > other.txt && git add other.txt && git commit -qm "another card" || exit 9
    lintbatch() { return 0; }; checks() { :; }
    sharedtests() { if [ $# = 2 ]; then ls "$T/$CASE"/s[78] >/dev/null 2>&1 || return 1; elif [ ! -e "$T/$CASE/s${1##*/c}" ]; then return 1
      elif [ "${5:-}" = own ] && [ -e "$T/$CASE/p${1##*/c}" ]; then return 1; fi; echo s.test.sh; }
    mates=(c7 c8); rebatch c7 "$W"; echo "rebatch: $? mates=${mates[*]} sharers=${sharers[*]}"
    [ -z "'"${3:-}"'" ] || { batchpass c7 "$W" "[\"7.test.sh\\tt_7\", \"7.test.sh\\tt_new\", \"8.test.sh\\tt_8\"]" 3 c7 c8; echo "by: $(jq -c .by "$W.bpass")"; }'
}

# Bug it catches (#447): after that run again, main moved before the batch landed (land() STALE), and rebatch() found
# the new landing on a shared test file and ran the batch a third time, though .sharedran marked the card's change.
# Main moved onto a file shared with the card's change, not c8's: the batch lands on its run (exit 0, both cards), not
# run again (exit 4).
t_rebatchsharedran() {
  rebatchmarked 7 7
  grep -qx 'rebatch: 0 mates=c7 c8 sharers=' "$T/$CASE/run.out" \
    || fail "a batch whose shared files already ran again for the card's change was not landed on its run: $(cat "$T/$CASE/run.out")"
}

# Bug it catches: the card's .sharedran let the whole batch land on its run, though main moved onto a test file c8's
# change shares too, which never ran again with it (c8 has no mark). The batch is run again there for its shared
# files (exit 4, both cards), for c8 (sharers): c7's own run again was used.
t_rebatchmateshared() {
  rebatchmarked '7 8' 7
  grep -qx 'rebatch: 4 mates=c7 c8 sharers=c8' "$T/$CASE/run.out" \
    || fail "a batch whose other card shares a test file with main's new change was landed with no run again: $(cat "$T/$CASE/run.out")"
}

# Bug it catches: the card c7 unmarked, the batch was asked whole, so c8's mark (its run again after main's first move)
# did not count: main moved onto a file c8 alone shares, and the batch ran a third time (exit 4). c7 shares none: the
# batch lands on its run (exit 0).
t_rebatchmatemark() {
  rebatchmarked 8 8
  grep -qx 'rebatch: 0 mates=c7 c8 sharers=' "$T/$CASE/run.out" \
    || fail "a batch whose other card's shared files ran again for its change was run again with the card unmarked: $(cat "$T/$CASE/run.out")"
}

# Bug it catches: the batch was run again for a file only the card c7's change shares with main's (c7 unmarked, c8
# sharing none), and every card of it was marked as run again, c8 too: main's next change to a file c8 shares then
# landed with no run of it (rebatch() and stalepass() kept c8's pass). Only c7 is a sharer (exit 4).
# Bug it catches too: rebatch() dropped both cards' passes, so the run again, passing, gave each card each file (by):
# a later change to c7's 7.test.sh alone counted as shared with c8 and used up c8's run again. Each keeps its own.
# And: t_new, a case main added to c7's 7.test.sh during the run, was in neither card's cases, so it went to both, with
# the same result. It is c7's, whose cases are in its file.
t_rebatchsharers() {
  rebatchmarked 7 '' 1
  grep -qx 'rebatch: 4 mates=c7 c8 sharers=c7' "$T/$CASE/run.out" \
    || fail "a batch run again for c7's shared file did not name c7 alone as sharing one: $(cat "$T/$CASE/run.out")"
  grep -qx 'by: {"c7":\["7.test.sh\\tt_7","7.test.sh\\tt_new"\],"c8":\["8.test.sh\\tt_8"\]}' "$T/$CASE/run.out" \
    || fail "the run again's passes did not give each card its own file: $(cat "$T/$CASE/run.out")"
}

# Bug it catches: c8 shared s.test.sh only through a batch pass (a test main linked to c7's change during an earlier
# run, given to both cards), and was a sharer, so the run again used up its own: main's next change to a file c8's
# change selects landed unrun. The batch still runs again for the file (exit 4), with c7 alone a sharer.
t_rebatchpassonly() {
  rebatchmarked '7 8' '' '' 8
  grep -qx 'rebatch: 4 mates=c7 c8 sharers=c7' "$T/$CASE/run.out" \
    || fail "a card sharing a test file through a batch pass alone was named a sharer: $(cat "$T/$CASE/run.out")"
}

# Bug it catches: as t_rebatchpassonly, with c7, whose change selects s.test.sh, marked (its one run again used): c8's
# pass alone still ran the batch again (exit 4) with no sharer, so no card was marked, and each later move of main onto
# s.test.sh ran it again. The batch lands on its run (exit 0).
t_rebatchpassmarked() {
  rebatchmarked '7 8' 7 '' 8
  grep -qx 'rebatch: 0 mates=c7 c8 sharers=' "$T/$CASE/run.out" \
    || fail "a batch whose only unmarked share was another card's batch pass was run again: $(cat "$T/$CASE/run.out")"
}
