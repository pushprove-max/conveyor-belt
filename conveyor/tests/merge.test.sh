#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 300
# Engine cases: the three-way merge at landing and at the same-file claim, and documentation files at the claim.
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"
# The engine folder, as lib.sh sets it: named here too, so the release closure (tools/closure.sh) follows this file's paths.
SRC=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)

# Main's a.txt as nine lines, l1 to l9: a change to l4 and one to l6 leave l5 between them, so neither applies plainly
# on the other (each one's context holds the other's line) and they merge three-way with no conflict.
nine() { seq 9 | sed 's/^/l/' > "$R/a.txt"; git -C "$R" commit -qam "a.txt of nine lines"; }

# A second card, c8, beside c7 (fx_wt): its worktree on main as it is now ($W8), with <change> made in it and staged.
# Then, in a shell of the engine (fx_in), c7 and then c8 claim their files (claim(), each as this shell's live pid):
# what each claim holds, [held, paths], goes to $T/$CASE/claims, one a line, and run.out gets what c8's claim()
# printed: nothing when it waits on no card.
claims() { # <c8's change>
  W8=$T/$CASE/cards/c8; rulewt c8 "$1"
  # claim() waits only on cards picked and not ended: both picked, c7 first.
  mkdir -p "$ST"; for n in 7 8; do jq -cn --argjson n $n '{card: "c\($n)", issue: $n, step: "picked", time: "2026-11-01T00:00:00Z", result: "ok"}'; done >> "$ST/cards.jsonl"
  fx_in 'claim c7 "$FXWT" $$ >/dev/null && claim c8 "'"$W8"'" $$ && for c in c7 c8; do jq -c "[.held, .paths]" "$CARDS/$c.claim"; done > "$T/$CASE/claims"'
  [ "$RC" = 0 ] || fail "the claims failed: $(cat "$T/$CASE/run.out")"
}

# The engine's functions the cases call, from lib/claim.sh: together(), fits(), merge3(), cardpatch(), tested(),
# testedhere(), docsonly() and inconflicts(), run in this shell.
claimfns() { eval "$(sed -n '/^together() {/,/^}/p; /^fits() {/,/^}/p; /^merge3() {/,/^}/p; /^docsonly() {/,/^}/p
  /^inconflicts() {/,/^}/p; /^cardpatch() {/p; /^tested() {/{N;p;}; /^testedhere() {/p' "$SRC/lib/claim.sh")"; }

# A main of its own, $r on branch main, its a.txt nine lines (as nine() makes it), with the cards' worktrees under
# $CARDS: none of the case's setup is needed by the functions above.
mainrepo() { # [<file> <content>]...
  r=$T/$CASE/r; CARDS=$T/$CASE/cards; export BRANCH=main; claimfns; mkdir -p "$CARDS" && git init -q -b main "$r" && seq 9 | sed 's/^/l/' > "$r/a.txt" || fail "no main"
  while [ $# -gt 1 ]; do printf '%s\n' "$2" > "$r/$1"; shift 2; done
  git -C "$r" add -A && git -C "$r" commit -qm base || fail "main's files"
}
# Card c<n>'s worktree on main, $CARDS/c<n>-<n>, with <change> made in it and staged.
cardwt() { # <n> <change>
  git -C "$r" worktree add -q "$CARDS/c$1-$1" -b "card-$1" main && (cd "$CARDS/c$1-$1" && eval "$2") && git -C "$CARDS/c$1-$1" add -A || fail "card $1's change"
}

# Bug: two cards that changed different parts of one file waited one behind the other whenever their changes did not
# apply together plainly, though they merge three-way with no conflict (together(), through merge3() and fits()). c7
# changes l4 and c8 l6, and main moves l1 and l9, so neither change applies to it plainly: c8 overlaps c7 on no file
# (together() names c7). Each card's test is its own (seven.test.sh, eight.test.sh).
# Bug too (the owner, 2026-11-13: 24 rebuild sessions in a day): a card whose change no longer applied plainly to a main
# that moved (here, by c7's landing) went to a rebuild session, a new review and its tests again, though main changed
# other lines of the file. c8's change fits onto that main (fits(): its three-way merge leaves the card's own lines),
# with both lines, and its tests' pass stands on it (testedhere()): it lands with no session and no second run.
t_mergetogether() {
  local r a id w8
  mainrepo; cardwt 7 "sed -i 's/^l4\$/seven/' a.txt; echo x > seven.test.sh"; cardwt 8 "sed -i 's/^l6\$/eight/' a.txt; echo x > eight.test.sh"
  w8=$CARDS/c8-8; git -C "$CARDS/c7-7" diff --cached --binary --no-renames > "$CARDS/c7-7.cpatch"; git -C "$w8" diff --cached --binary --no-renames > "$w8.patch"
  id=$(cardpatch "$w8" ':(exclude)*.md'); echo '{}' > "$w8.ready"; tested "$w8"
  sed -i 's/^l1$/main1/; s/^l9$/main9/' "$r/a.txt"; git -C "$r" commit -qam "main moves"
  ! (cd "$r" && git apply --check --cached "$CARDS/c7-7.cpatch" 2>/dev/null) && ! (cd "$r" && git apply --check --cached "$w8.patch" 2>/dev/null) \
    || fail "a card's change still applies to main plainly"
  a=$(cd "$r" && together "$w8.patch" '["a.txt","eight.test.sh"]' '[{"card":"c7-7","paths":["a.txt","seven.test.sh"]}]' "$id") || fail "together() failed"
  [ "$a" = '["c7-7"]' ] || fail "c8 overlaps c7, whose change merges with its own: $a"
  # c7 lands; c8's worktree is reset to that main, where its change no longer applies plainly, and fitted onto it.
  sed -i 's/^l4$/seven/' "$r/a.txt"; echo x > "$r/seven.test.sh"; git -C "$r" add -A; git -C "$r" commit -qm "c7 lands"
  git -C "$w8" reset -q --hard main && ! (cd "$w8" && git apply --check --cached "$w8.patch" 2>/dev/null) || fail "c8's change applies plainly to the main c7 landed on"
  (cd "$w8" && fits "$w8.patch" "$id" 2>/dev/null) || fail "c8's change, which merges three-way with c7's, did not fit onto main"
  testedhere "$w8" || fail "c8's tests' pass does not stand on its change fitted onto main"
  [ "$(git -C "$w8" show :a.txt | grep -cx 'seven\|eight')" = 2 ] && [ -z "$(git -C "$r" status --porcelain)" ] \
    || fail "the fitted change does not hold both lines, or main's checkout is dirty: $(git -C "$w8" show :a.txt | tr '\n' ' ')"
}

# Bug (2026-11-13: three of six finished cards waited on another over README.md alone, one for 55 minutes): a
# documentation file shared by two cards made one wait for the other. c7 and c8 both rewrite README.md's one line, a
# conflict: neither waits, both holding their claims at once with no file named (claim() leaves out *.md). Once c7
# landed, c8's change does not fit onto main (ready(), through fits(): the conflict stays), so a session brings it
# there, as any conflict at landing.
t_mergedocs() {
  setup '[]'; fx_wt 'echo seven > README.md' README.md title
  claims 'echo eight > README.md'
  [ "$(tr '\n' ' ' < "$T/$CASE/claims")" = '[true,[]] [true,[]] ' ] && [ ! -s "$T/$CASE/run.out" ] \
    || fail "c8 waited on c7 over README.md alone: $(cat "$T/$CASE/claims" "$T/$CASE/run.out")"
  # Bug (#1435): with both claims naming no file, the check above passes whatever together() makes of a clash in
  # README.md alone. Given README.md as the file they share, it leaves *.md out of both changes, so c7 goes together
  # with c8 (named: no overlap); one that kept README.md in would find the clash and name none.
  fx_in 'cd "$R" && together "'"$W8"'.cpatch" "[\"README.md\"]" "[{\"card\":\"c7\",\"paths\":[\"README.md\"]}]" "$(cardpatch "'"$W8"'" ":(exclude)*.md")"'
  [ "$RC" = 0 ] && [ "$(cat "$T/$CASE/run.out")" = '["c7"]' ] || fail "together() took c7, whose change clashes with c8's in README.md alone, as an overlap: $(cat "$T/$CASE/run.out")"
  echo seven > "$R/README.md"; git -C "$R" commit -qam "c7 lands"
  fx_in 'cd "$R" && ready "'"$W8"'"'
  [ "$RC" = 1 ] || fail "c8's change, which conflicts with c7's in README.md, was taken to fit onto main with no session: $(cat "$T/$CASE/run.out")"
}

# A three-way merge of a change main holds already is clean, and leaves no change: that is not the card's change. Two
# cards that make the same change, l4 to seven and a new b.txt, overlap (their merge would land the second as nothing),
# and once main holds that change the card is not ready. Bug too: git apply --cached --3way wrote the merged b.txt
# into the work tree, main's checkout, which then refused the landing of b.txt. The cards' change merges as the same
# change onto a main that changed l6 alone: ready.
t_mergesame() {
  setup '[]'; nine; CARDS=$T/$CASE/cards; mkdir -p "$CARDS"
  for n in 7 8; do
    git -C "$R" worktree add -q "$CARDS/c$n-$n" -b "card-$n" main
    sed -i 's/^l4$/seven/' "$CARDS/c$n-$n/a.txt"; echo bee > "$CARDS/c$n-$n/b.txt"; git -C "$CARDS/c$n-$n" add -A
  done
  git -C "$CARDS/c7-7" diff --cached --binary --no-renames > "$CARDS/c7-7.cpatch"; git -C "$CARDS/c8-8" diff --cached --binary --no-renames > "$CARDS/c8-8.cpatch.new"
  # ready() and together() as the engine has them, and what they call, run from main's checkout.
  eval "$(sed -n '/^together() {/,/^}/p; /^ready() {/,/^}/p; /^fits() {/,/^}/p; /^merge3() {/,/^}/p; /^cardpatch() {/p' "$SRC/lib/claim.sh")"
  sed -i 's/^l6$/main6/' "$R/a.txt"; git -C "$R" commit -qam "main changes l6" # the cards' change no longer applies plainly
  (cd "$R" && BRANCH=main ready "$CARDS/c7-7") || fail "a change that merges three-way onto main as the same change is not ready"
  a=$(cd "$R" && BRANCH=main together "$CARDS/c8-8.cpatch.new" '["a.txt","b.txt"]' '[{"card":"c7-7","paths":["a.txt","b.txt"]}]' "$(cardpatch "$CARDS/c8-8" ':(exclude)*.md')") \
    || fail "together() failed"
  [ "$a" = '[]' ] || fail "two cards that make the same change were taken to merge together: $a"
  [ ! -e "$R/b.txt" ] && [ -z "$(git -C "$R" status --porcelain)" ] || fail "the three-way merge wrote into main's checkout: $(git -C "$R" status --porcelain)"
  sed -i 's/^l4$/seven/' "$R/a.txt"; echo bee > "$R/b.txt"; git -C "$R" add -A; git -C "$R" commit -qm "main makes the cards' change"
  ! (cd "$R" && BRANCH=main ready "$CARDS/c7-7") || fail "a change main holds already was taken as merged onto it"
}

# A merge at landing, as settle() checks it. A card's change and main both changed l4 of a.txt: $mt is their three-way
# merge with its conflict markers, a tree, and the merge session's resolution, main4 and then seven, is staged in $w.
mergedw() {
  claimfns; w=$T/$CASE/w
  mkdir -p "$w" && git -C "$w" init -q && printf '%s\n' l1 l2 l3 '<<<<<<< ours' main4 ======= seven '>>>>>>> theirs' l5 l6 l7 l8 l9 > "$w/a.txt" \
    && git -C "$w" add -A && mt=$(git -C "$w" write-tree) && printf '%s\n' l1 l2 l3 main4 seven l5 l6 l7 l8 l9 > "$w/a.txt" && git -C "$w" add -A \
    || fail "the merge's fixture"
}

# Bug (#407 blocked, #305 lost 10.5 minutes): the merge session's reply went through the Done-when check, and a merge
# reply leaves out the D<n> lines, so the card was sent to a fix session and blocked. A merge that changed only the
# conflict is not checked (inconflicts() holds).
t_mergedwconflict() {
  local w mt; mergedw
  inconflicts "$w" "$mt" a.txt || fail "a merge that changed only the conflict was taken to change more, so it gets the Done-when check"
}

# A merge session that also changes a line outside the conflict (l8) is checked as any fix session (inconflicts() fails).
t_mergedwoutside() {
  local w mt; mergedw
  sed -i 's/^l8$/eight/' "$w/a.txt"; git -C "$w" add -A
  ! inconflicts "$w" "$mt" a.txt || fail "a merge that also changed l8, outside the conflict, was taken to change only the conflict"
}

# Bug (review of #434): inconflicts() read only the `@@` lines of the diff, so a merge session that resolved the conflict
# and also changed the file's mode (`chmod a+x`) was taken to have changed only the conflict and skipped the check.
t_mergedwmode() {
  local w mt; mergedw
  chmod a+x "$w/a.txt"; git -C "$w" add -A
  ! inconflicts "$w" "$mt" a.txt || fail "a merge that also changed the file's mode was taken to change only the conflict"
}

# A clash in a README alone at landing. Card c7 changes l4 of a.txt and README.md's one line, and its tests pass on
# that change (tested()); main then rewrites README.md's line, so the change no longer applies. Sets r (main), w7 (its
# worktree) and docs (its change outside *.md, the id settle() and the landing rebuild keep).
readme() {
  mainrepo README.md title; cardwt 7 "sed -i 's/^l4\$/seven/' a.txt; echo seven > README.md"
  w7=$CARDS/c7-7; git -C "$w7" diff --cached --binary --no-renames > "$w7.patch"; echo '{}' > "$w7.ready"; tested "$w7"
  docs=$(cardpatch "$w7" ':(exclude)*.md'); [ -n "$docs" ] && testedhere "$w7" || fail "c7's tests did not pass on its change: $docs"
  echo main > "$r/README.md"; git -C "$r" commit -qam "main moves"
  ! (cd "$r" && git apply --check --cached "$w7.patch" 2>/dev/null) || fail "c7's change still applies to main"
}
# The session that brings c7 onto main: its worktree reset to main, a.txt as c7 had it, README.md merged, then <its own edit>.
rebuild() { # <the session's own edit>
  git -C "$w7" reset -q --hard main && (cd "$w7" && sed -i 's/^l4$/seven/' a.txt && printf '%s\n' main seven > README.md && eval "$1") \
    && git -C "$w7" add -A || fail "the rebuild"
}

# Bug (#436: two of a day's 11 landing clashes shared only a README, and cost 40.5 minutes): a clash in a README alone
# after the card's tests passed sent it, after the rebuild session merged the README, to a new review and a new test
# run. Its change outside documentation is the one reviewed and tested: the same id after the rebuild, so the review
# and the test pass stand (kept and docpass in card.sh, dp in settle()).
t_mergereadme() {
  local r w7 docs; readme; rebuild :
  [ "$(cardpatch "$w7" ':(exclude)*.md')" = "$docs" ] || fail "a rebuild that merged README.md alone changed the card's change outside documentation"
}

# The review and the test pass stand only for the same change: a rebuild session that also changes a line of code (l8)
# leaves another id outside documentation, and the tests' pass does not stand on it.
t_mergereadmecode() {
  local r w7 docs; readme; rebuild "sed -i 's/^l8\$/eight/' a.txt"
  [ "$(cardpatch "$w7" ':(exclude)*.md')" != "$docs" ] || fail "a rebuild that changed l8 kept the id the review and the tests passed on"
  ! testedhere "$w7" || fail "the tests' pass stands on a change of code they did not run on"
}

# The same at the landing claim (settle()): a clash in a README alone is one in documentation alone (docsonly()), so the
# session's merge keeps the review; once main changes l4 too, the clash is in code, and docsonly() fails.
t_mergereadmewait() {
  local r w7 docs; readme
  (cd "$r" && docsonly "$w7.patch" "$docs") || fail "a clash in README.md alone was taken as one in code"
  sed -i 's/^l4$/main4/' "$r/a.txt"; git -C "$r" commit -qam "main changes l4"
  ! (cd "$r" && docsonly "$w7.patch" "$docs") || fail "a clash in a.txt too was taken as one in documentation alone"
}

# The fast resolver (the owner, 2026-11-18, #381): a card's change and main both changed l4 of a.txt. One judge call
# (a stub here, its answer <answer>) merges the conflict before any fitting session. Sets w (the worktree), onto (main's
# commit), mt (the merge with its markers) and rc (fastfit's exit).
fastcase() { # <answer>, as the judge writes it
  eval "$(sed -n '/^inconflicts() {/,/^}/p; /^FASTFIT_ASK=/p; /^fastfit() {/,/^}/p' "$SRC/lib/claim.sh")"
  HERE=$SRC; FASTANSWER=$1; w=$T/$CASE/w
  judgeon() { [ -z "${FASTOFF:-}" ]; }
  judgecall() { : > "$T/$CASE/called"; printf '%s\n' "$3" > "$T/$CASE/asked"; printf '%s\n' "$FASTANSWER" > "$1.judge"; }
  mkdir -p "$w" && git -C "$w" init -q && seq 9 | sed 's/^/l/' > "$w/a.txt" && git -C "$w" add -A && git -C "$w" commit -qm base
  sed -i 's/^l4$/seven/' "$w/a.txt" && git -C "$w" diff --binary > "$w.patch" && git -C "$w" checkout -q -- a.txt
  sed -i 's/^l4$/main4/' "$w/a.txt" && git -C "$w" commit -qam "main moves" && onto=$(git -C "$w" rev-parse HEAD)
  ! git -C "$w" apply --3way --index "$w.patch" >/dev/null 2>&1 || fail "the case's change did not conflict with main"
  git -C "$w" add -A && mt=$(git -C "$w" write-tree) && git -C "$w" reset -q --hard "$onto"
  fastfit "$w" a.txt "$onto" "$mt"; rc=$?
}

# A good answer: both lines are kept, the change is staged on main's commit, no marker is left, and the judge was given
# the conflict with its base.
t_fastfit() {
  fastcase '{"1": "main4\nseven"}'
  [ $rc = 0 ] || fail "the fast resolver did not fit a conflict its answer merged"
  [ "$(git -C "$w" rev-parse HEAD)" = "$onto" ] && [ "$(git -C "$w" show :a.txt | sed -n 4,5p | tr '\n' ' ')" = "main4 seven " ] \
    || fail "the merged change is not staged on main: $(git -C "$w" show :a.txt 2>&1 | tr '\n' ' ')"
  ! grep -qE '^(<{7}|={7}|>{7})' "$w/a.txt" || fail "a conflict marker was left: $(cat "$w/a.txt")"
  grep -qx '||||||| base' "$T/$CASE/asked" && grep -qx 'l4' "$T/$CASE/asked" || fail "the judge was not shown the base of the conflict: $(cat "$T/$CASE/asked")"
}

# An answer that leaves a marker, gives no text for the conflict, or is no JSON: no fit, and the worktree is main again
# for the session.
t_fastfitbad() {
  local a
  for a in '{"1": "main4\n=======\nseven"}' '{"2": "x"}' 'I could not merge it.'; do
    fastcase "$a"
    [ $rc != 0 ] || fail "the fast resolver fitted with the answer: $a"
    [ "$(git -C "$w" rev-parse HEAD)" = "$onto" ] && [ -z "$(git -C "$w" status --porcelain)" ] \
      || fail "the worktree was not put back on main after the answer $a: $(git -C "$w" status --porcelain | tr '\n' ' ')"
    rm -rf "$w" "$w.patch" "$w.judge"
  done
}

# With the judge off in the control record, the fast resolver asks nothing: the session fits the card, as before.
t_fastfitoff() {
  FASTOFF=1 fastcase '{"1": "main4\nseven"}'
  [ $rc != 0 ] && [ ! -e "$T/$CASE/called" ] || fail "the fast resolver ran with the judge off"
}
