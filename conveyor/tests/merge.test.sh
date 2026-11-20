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

# Bug: two cards that changed different parts of one file waited one behind the other whenever their changes did not
# apply together plainly, though they merge three-way with no conflict (together(), through merge3() and fits()). c7
# changes l4 and c8 l6: both hold a.txt at once, and c8 waits on no card. No link gives a.txt a test file: each card's
# test is its own (seven.test.sh, eight.test.sh).
# Bug too (the owner, 2026-11-13: 24 rebuild sessions in a day): a card whose change no longer applied plainly to a main
# that moved (here, by c7's landing) went to a rebuild session, a new review and its tests again, though main changed
# other lines of the file. c8's change fits onto that main (fits(): its three-way merge leaves the card's own lines),
# with both lines, and its tests' pass stands on it (testedhere()): it lands with no session and no second run.
t_mergetogether() {
  setup '[]'; fx_wt "sed -i 's/^l4\$/seven/' a.txt; echo x > seven.test.sh" a.txt "$(seq 9 | sed 's/^/l/')" # main's a.txt as nine() makes it
  claims "sed -i 's/^l6\$/eight/' a.txt; echo x > eight.test.sh"
  [ "$(tr '\n' ' ' < "$T/$CASE/claims")" = '[true,["a.txt","seven.test.sh"]] [true,["a.txt","eight.test.sh"]] ' ] && [ ! -s "$T/$CASE/run.out" ] \
    || fail "c8 waited on c7, whose change merges with its own: $(cat "$T/$CASE/claims" "$T/$CASE/run.out")"
  # c7 lands; c8's change, its tests passed (tested()), is fitted onto main in its worktree, where it no longer applies plainly.
  sed -i 's/^l4$/seven/' "$R/a.txt"; echo x > "$R/seven.test.sh"; git -C "$R" add -A; git -C "$R" commit -qm "c7 lands"
  fx_in 'cd "'"$W8"'" && git diff --cached --binary --no-renames > "$PWD.patch" && id=$(cardpatch "$PWD") && echo "{}" > "$PWD.ready" && tested "$PWD" \
    && git reset -q --hard main && ! git apply --check --cached "$PWD.patch" 2>/dev/null && fits "$PWD.patch" "$id" && testedhere "$PWD"'
  [ "$RC" = 0 ] || fail "c8's change, which merges three-way with c7's, did not fit onto main on the tests it passed: $(cat "$T/$CASE/run.out")"
  [ "$(git -C "$W8" show :a.txt | grep -cx 'seven\|eight')" = 2 ] && [ -z "$(git -C "$R" status --porcelain)" ] \
    || fail "the fitted change does not hold both lines, or main's checkout is dirty: $(git -C "$W8" show :a.txt | tr '\n' ' ')"
}

# The same landing as a card sees it (t_mergetogether): #8 changes l6, and while its tests run main takes l4 as c7's
# landing makes it, so #8's change no longer applies plainly. #8 lands on its first test pass, the second test step
# reused, with one review and one test run, no session to bring it onto main, both lines in main and its checkout clean.
t_mergetogethercard() {
  setup "[$(issue 8 2026-01-02)]"; for i in 1 2; do echo "$GO" > "$STUB/review.$i"; done; nine; linkset '{}'
  echo "sed -i 's/^l6\$/eight/' a.txt; echo x > eight.test.sh" > "$STUB/build"
  echo '[ -e "$STUB/moved" ] || { : > "$STUB/moved"; sed -i "s/^l4\$/seven/" "$R/a.txt"; echo x > "$R/seven.test.sh"; git -C "$R" add -A; git -C "$R" commit -qm "c7 lands"; }' >> "$STUB/test-cmd"
  # loop: the card's steps and its test records (the second test step reused, no rebase or fix) are written only by a card run
  out=$(loop run 2>&1) || fail "run exited non-zero: $out"
  [ "$(st "select(.issue == 8 and $NOMARK) | .step" | tr '\n' ' ')" = "picked worktree brief build review test test landed " ] \
    && [ "$(st 'select(.issue == 8 and .step == "test") | .reused // false' | tr '\n' ' ')" = "false true " ] \
    || fail "#8, merged onto a main that moved, did not land on the tests it passed: $(st "select(.issue == 8) | \"\(.step) \(.reused)\"" | tr '\n' ,)"
  [ "$(grep -cx 'seven\|eight' "$R/a.txt")" = 2 ] && [ "$(wc -l < "$STUB/reviews")" = 1 ] && [ "$(wc -l < "$STUB/tests")" = 1 ] \
    && [ -z "$(git -C "$R" status --porcelain)" ] || fail "#8 was reviewed or tested again, or main lacks a line or is dirty: $(cat "$R/a.txt")"
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

# A merge at landing. #7 (its issue has a `## Done when`) changes l4; during its review main changes l4 too, so at its
# landing claim one session brings #7 onto main (settle()). That session writes a.txt as the merged lines and then
# runs <its own edit> on it; its reply has no D<n> line. Each session's reply is $STUB/reply.<its number>.
mergedw() { # <the merge session's own edit>
  setup "[$(issue 7 2026-01-01 | jq -c '.body = "body of 7\n\n## Done when\n- l4 is seven"')]"; for i in 1 2; do echo "$GO" > "$STUB/review.$i"; done; nine
  cat > "$STUB/claude" <<'EOF'
#!/usr/bin/env bash
cat > "$STUB/brief"; echo "$*" >> "$STUB/sessions"; cp "$STUB/brief" "$STUB/brief.$(wc -l < "$STUB/sessions")"; . "$STUB/build"
jq -cn --rawfile r "$STUB/reply.$(wc -l < "$STUB/sessions")" '{type: "result", is_error: false, result: $r, usage: {input_tokens: 10, cache_creation_input_tokens: 20, cache_read_input_tokens: 999, output_tokens: 5}}'
EOF
  { echo "if grep -q '^# Main moved: apply the same change' \"\$STUB/brief\"; then printf '%s\n' l1 l2 l3 main4 seven l5 l6 l7 l8 l9 > a.txt; $1"
    echo "else sed -i 's/^l4\$/seven/' a.txt; fi"; } > "$STUB/build"
  echo '[ -e "$STUB/moved" ] || { : > "$STUB/moved"; sed -i "s/^l4\$/main4/" "$R/a.txt"; git -C "$R" commit -qam "main moves"; }' > "$STUB/review-cmd"
  printf 'Built.\n\n## Done when\nD1 met: a.txt:4 holds seven\n' > "$STUB/reply.1"; echo 'Merged.' > "$STUB/reply.2"
  printf 'Fixed.\n\n## Done when\nD1 met: a.txt:5 holds seven\n' > "$STUB/reply.3"
  out=$(loop run 2>&1) || fail "run exited non-zero: $out"
  grep -q '^# Main moved: apply the same change' "$STUB/brief.2" || fail "#7 was not brought onto main by a session at its landing claim: $(st '"\(.step) \(.reason)"' | tr '\n' ,)"
}

# Bug (#407 blocked, #305 lost 10.5 minutes): the merge session's reply went through the Done-when check, and a merge
# reply leaves out the D<n> lines, so the card was sent to a fix session and blocked. A merge that changed only the
# conflict is not checked: no Done-when fix session, and #7 is reviewed, tested and lands as merged.
t_mergedwconflict() {
  mergedw :
  [ "$(wc -l < "$STUB/sessions")" = 2 ] && [ -z "$(st 'select(.step == "blocked") | .reason')" ] \
    || fail "the merge that changed only the conflict was given the Done-when check: $(st '"\(.step) \(.reason) \(.doneWhen)"' | tr '\n' ,)"
  [ "$(st "select(.issue == 7 and $NOMARK) | .step" | tr '\n' ' ')" = "picked worktree brief build review fix review test landed " ] \
    && [ "$(st 'select(.step == "fix") | .doneWhen')" = null ] || fail "steps of #7: $(st "select(.issue == 7) | \"\(.step) \(.doneWhen)\"" | tr '\n' ,)"
  [ "$(grep -cx 'main4\|seven\|l8' "$R/a.txt")" = 3 ] || fail "main does not hold the merge: $(cat "$R/a.txt")"
}

# A merge session that also changes a line outside the conflict (l8) is checked as any fix session: its reply with no
# D<n> line is sent to one Done-when fix session, and #7 then goes through review and test before it lands.
t_mergedwoutside() {
  mergedw "sed -i 's/^l8\$/eight/' a.txt"
  [ "$(wc -l < "$STUB/sessions")" = 3 ] && grep -q '^# The Done-when check failed' "$STUB/brief.3" \
    || fail "the merge that changed a line outside the conflict was not given the Done-when check: $(st '"\(.step) \(.reason) \(.doneWhen)"' | tr '\n' ,)"
  [ "$(st "select(.issue == 7 and $NOMARK) | .step" | tr '\n' ' ')" = "picked worktree brief build review fix fix review test landed " ] \
    && [ "$(st 'select(.step == "fix") | .doneWhen.failed | length' | tr '\n' ' ')" = "1 0 " ] && [ "$(wc -l < "$STUB/reviews")" = 2 ] && [ "$(wc -l < "$STUB/tests")" = 1 ] \
    || fail "#7 did not go through its Done-when fix, review and test: $(st "select(.issue == 7) | \"\(.step) \(.doneWhen)\"" | tr '\n' ,)"
  grep -qx eight "$R/a.txt" || fail "main does not hold the session's change: $(cat "$R/a.txt")"
}

# Bug (review of #434): inconflicts() read only the `@@` lines of the diff, so a merge session that resolved the conflict
# and also changed the file's mode (`chmod a+x`) was taken to have changed only the conflict and skipped the check.
t_mergedwmode() {
  eval "$(sed -n '/^inconflicts() {/,/^}/p' "$SRC/lib/claim.sh")"
  local w=$T/$CASE/w mt
  mkdir -p "$w" && git -C "$w" init -q && printf '%s\n' l1 '<<<<<<< ours' main4 ======= seven '>>>>>>> theirs' l5 > "$w/a.txt"
  git -C "$w" add -A && mt=$(git -C "$w" write-tree) && printf '%s\n' l1 main4 seven l5 > "$w/a.txt" && git -C "$w" add -A
  inconflicts "$w" "$mt" a.txt || fail "a merge that changed only the conflict was taken to change more"
  chmod a+x "$w/a.txt"; git -C "$w" add -A
  ! inconflicts "$w" "$mt" a.txt || fail "a merge that also changed the file's mode was taken to change only the conflict"
}

# A clash in a README alone at landing. #7 changes l4 of a.txt and README.md's one line; main rewrites that line while
# #7 is in <hook> (review-cmd: its review; test-cmd: its tests). One session merges README.md (settle()'s, at its
# landing claim, or the landing rebuild), writing a.txt as #7 had it, and then runs <its own edit>.
readme() { # <review-cmd|test-cmd> <the merge session's own edit>
  setup "[$(issue 7 2026-01-01)]"; for i in 1 2; do echo "$GO" > "$STUB/review.$i"; done; nine
  echo title > "$R/README.md"; git -C "$R" add README.md; git -C "$R" commit -qm "a README"
  { echo "if grep -q '^# \(Landing conflict\|Main moved\)' \"\$STUB/brief\"; then sed -i 's/^l4\$/seven/' a.txt; printf '%s\n' main seven > README.md; $2"
    echo "else sed -i 's/^l4\$/seven/' a.txt; echo seven > README.md; fi"; } > "$STUB/build"
  echo '[ -e "$STUB/moved" ] || { : > "$STUB/moved"; echo main > "$R/README.md"; git -C "$R" commit -qam "main moves"; }' >> "$STUB/$1"
  out=$(loop run 2>&1) || fail "run exited non-zero: $out"
  [ "$(st 'select(.step == "landed") | .issue')" = 7 ] && [ "$(tr '\n' ' ' < "$R/README.md")" = "main seven " ] && grep -qx seven "$R/a.txt" \
    || fail "#7 did not land merged: $(st '"\(.step) \(.reason)"' | tr '\n' ,)"
}

# Bug (#436: two of a day's 11 landing clashes shared only a README, and cost 40.5 minutes): a clash in a README alone
# after the card's tests passed sent it, after the rebuild session merged the README, to a new review and a new test
# run. Its change outside documentation is the one reviewed and tested: it lands on that review and that run.
t_mergereadme() {
  readme test-cmd :
  [ "$(st "select(.issue == 7 and $NOMARK) | .step" | tr '\n' ' ')" = "picked worktree brief build review test rebase test landed " ] \
    && [ "$(st 'select(.step == "test") | .reused // false' | tr '\n' ' ')" = "false true " ] \
    && [ "$(wc -l < "$STUB/reviews")" = 1 ] && [ "$(wc -l < "$STUB/tests")" = 1 ] \
    || fail "#7 was reviewed or tested again after a clash in README.md alone: $(st "select(.issue == 7) | \"\(.step) \(.reused)\"" | tr '\n' ,)"
}

# The review and the test pass stand only for the same change: a rebuild session that also changes a line of code (l8)
# sends #7 to a new review and a new test run.
t_mergereadmecode() {
  readme test-cmd "sed -i 's/^l8\$/eight/' a.txt"
  [ "$(wc -l < "$STUB/reviews")" = 2 ] && [ "$(wc -l < "$STUB/tests")" = 2 ] && grep -qx eight "$R/a.txt" \
    || fail "#7's changed code was not reviewed and tested again: $(st "select(.issue == 7) | \"\(.step) \(.reused)\"" | tr '\n' ,)"
}

# The same at the landing claim (settle()): a clash in a README alone during the review is merged by one session, and
# the card goes on to its tests with no second review.
t_mergereadmewait() {
  readme review-cmd :
  [ "$(st "select(.issue == 7 and $NOMARK) | .step" | tr '\n' ' ')" = "picked worktree brief build review fix test landed " ] \
    && [ "$(wc -l < "$STUB/reviews")" = 1 ] && [ "$(wc -l < "$STUB/tests")" = 1 ] \
    || fail "#7 was reviewed again after its landing claim merged README.md alone: $(st "select(.issue == 7) | \"\(.step) \(.reused)\"" | tr '\n' ,)"
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
