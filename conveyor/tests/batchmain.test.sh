#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 300
# Engine cases: batches whose main moves during their run, and cards stacked on the card whose batch takes them.
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"
# The engine folder, as lib.sh sets it: named here too, so the release closure (tools/closure.sh) follows this file's paths.
SRC=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)

# batchsetup, cardof and batchruns are batch.test.sh's: the runner loads every case file into one shell. A change to
# batch.test.sh runs this file too, through its link in .conveyor/test-links.json.

# What main gets during the batch's one run, for the cases below: $STUB/during is run once, in main's checkout, by the
# test run that holds #7's and #8's changes together (the batch's), as a card on other files landing meanwhile would.
during() { # <shell that commits to main>
  echo "$1" > "$STUB/during"
  echo '! { grep -qx seven a.txt && grep -qx eight a.txt; } || [ -e "$STUB/moved" ] || { : > "$STUB/moved"; (cd "$R" && . "$STUB/during"); }' >> "$STUB/test-cmd"
}

# A card of the batch whose change no longer applies to main as it moved leaves the batch; the others land on the run
# they passed. Main's line 10 of a.txt, the line #9 changes, changes during the batch's run: #8 and #7 land on that
# run, and #9 is fitted afterwards, as a waiting card is (one session, a review, its tests), and lands alone.
t_batchmovedleft() {
  batchsetup "[$(issue 7 2026-01-01),$(issue 8 2026-01-02),$(issue 9 2026-01-03)]"
  # The cards' tests are not main's a.txt's: card <n> writes s<n>.txt too, which the links give a.test.sh, and a.txt
  # is linked to none. A main that moved a.txt's test file would have the batch tested again (sharedtests(),
  # lib/claim.sh), not landed on the run it passed.
  linkset '{"s7.txt": ["a.test.sh"], "s8.txt": ["a.test.sh"], "s9.txt": ["a.test.sh"]}'
  cat > "$STUB/build" <<'EOF'
echo x > "s${PWD##*-}.txt"
if grep -q '^# Main moved: apply the same change\|^# Stacked: apply the same change' "$STUB/brief"; then sed -i 10s/.*/nine-ten/ a.txt
else case $PWD in *-7) sed -i 1s/.*/seven/ a.txt ;; *-8) echo eight >> a.txt ;; *) sed -i 10s/.*/nine/ a.txt ;; esac; fi
EOF
  during 'sed -i 10s/.*/ten/ a.txt; git commit -qam "line ten"'
  # #9, once out of the batch, looks at its claim each second, and so does #8 at its batch: which comes first decided
  # whether #9 found #8 still held (stacked on it, below) or gone (fitted onto main alone). The batch's landing waits
  # for #9's stack, or for #9 gone, at the limit reading taken just before it (card(): `reading fresh`), outside the lock
  # #9's claim takes; the engine stops that reading after 30 s, so a #9 that is never stacked fails below, not hangs.
  # shellcheck disable=SC2016 # run by the limit reading
  printf '%s\n' '[ ! -e "$STUB/moved" ] || [ -e "$STUB/stackseen" ] || while ls -d "$CONVEYOR_CARDS"/*-9 >/dev/null 2>&1 && ! ls "$CONVEYOR_CARDS"/*-9.batch >/dev/null 2>&1; do
  ! ls "$CONVEYOR_CARDS"/*-9.stack >/dev/null 2>&1 || { : > "$STUB/stackseen"; break; }; sleep 0.1; done; false' > "$STUB/limitcmd"
  # shellcheck disable=SC2016 # run by the limit reading
  local -x CONVEYOR_LIMIT_CMD='. "$STUB/limitcmd"'
  out=$(loop run 2>&1) || fail "run exited non-zero: $out"
  c7=$(cardof 7); c8=$(cardof 8); c9=$(cardof 9)
  grep -q "card $c7 tests a batch of 3: $c8 $c9 $c7" <<<"$out" && [ "$(batchruns)" = 1 ] || fail "#7 did not test one batch of three: $out"
  [ -e "$STUB/stackseen" ] || fail "the batch's landing did not wait at its limit reading for #9 to be stacked on #8: $out"
  [ "$(wc -l < "$STUB/tests")" = 5 ] || fail "not one run for the batch beside the three own runs, and one for #9 after its fit: $(wc -l < "$STUB/tests"): $out"
  [ "$(st 'select(.step == "landed") | .issue' | tr '\n' ' ')" = "8 7 9 " ] && [ "$(st 'select(.step == "landed" and .issue != 9) | .batch | join(" ")' | sort -u)" = "$c8 $c7" ] \
    && [ "$(st 'select(.step == "landed" and .issue == 9) | .batch')" = null ] || fail "#8 and #7 did not land as one batch before #9: $(st 'select(.step == "landed")')"
  [ "$(git -C "$R" log --reverse --format=%s HEAD~4..HEAD | tr '\n' ,)" = "line ten,feat(product): title 8 (#8),feat(product): title 7 (#7),feat(product): title 9 (#9)," ] \
    || fail "#8 and #7 did not land on main as it moved, #9 after them: $(git -C "$R" log --format=%s | tr '\n' ,)"
  [ "$(st "select(.issue == 9 and $NOMARK) | .step" | tr '\n' ' ')" = "picked worktree brief build review test fix review test landed " ] \
    || fail "steps of #9: $(st "select(.issue == 9) | .step" | tr '\n' ' ')"
  # Left out, #9 waits on #8, ordered first and held by the batch, and is stacked on it: its one session fits it onto
  # main with #8's change.
  st 'select(.issue == 9 and .step == "fix") | .reason' | grep -q "^stacked on card $c8, " || fail "#9 was not brought onto main after the batch landed: $(st 'select(.issue == 9 and .step == "fix") | .reason')"
  st '.reason' | grep -q 'rebase onto main conflicts' && fail "a card met a landing conflict: $(st '"\(.issue) \(.step) \(.reason)"' | tr '\n' ,)"
  [ "$(sed -n '1p;10p;$p' "$R/a.txt" | tr '\n' ' ')" = "seven nine-ten eight " ] && [ -z "$(ls "$T/$CASE/cards")" ] || fail "main does not hold the three changes: $(cat "$R/a.txt")"
}

# The product checks judge the batch's combined change on main as it is now before it lands on a run made elsewhere.
# The check refuses eight in a.txt beside flag-x, which main gets during the batch's run: the batch of #8 and #7 does
# not land on that run. That is a red run, handled as one is: the batch is run again on main as it is now and split,
# #7 lands alone, and #8, the card that breaks it, goes to its fix with the check named (not blocked by its own check
# once released). No commit on main ever holds eight beside flag-x.
t_batchmovedcheck() {
  batchsetup "[$(issue 7 2026-01-01),$(issue 8 2026-01-02)]"; echo 8 > "$STUB/ready"
  cat > "$STUB/build" <<'EOF'
if grep -q '^# The changed tests fail' "$STUB/brief"; then cp "$STUB/brief" "$STUB/fixbrief"; sed -i 's/^eight$/eight-fixed/' a.txt
else case $PWD in *-7) sed -i 1s/.*/seven/ a.txt ;; *) echo eight >> a.txt ;; esac; fi
EOF
  printf '%s\n' '! { git cat-file -e "$2:flag-x" 2>/dev/null && git show "$2:a.txt" | grep -qx eight; } || { echo "eight beside flag-x"; exit 1; }' > "$STUB/flags"
  tune --arg f "$STUB/flags" '.checks += [$f]'
  during ': > flag-x; git add flag-x; git commit -qm "flag-x"'
  out=$(loop run 2>&1)
  c7=$(cardof 7); c8=$(cardof 8)
  # Bug it catches: #8's pass on the result its batch gave it read `own` unset, so its card process died under set -u.
  ! grep -q 'unbound variable' <<<"$out" || fail "a card process died on an unset variable: $(grep 'unbound variable' <<<"$out")"
  grep -q "card $c7 tests a batch of 2: $c8 $c7" <<<"$out" || fail "#7 did not test a batch of #8 and itself: $out"
  grep -q "card $c7: a product check failed on its batch's change on main as it is now, a red run, so the batch is run again there: .*eight beside flag-x" <<<"$out" \
    || fail "the check did not judge the batch's change on main as it moved: $out"
  [ "$(st 'select(.step == "landed") | .batch' | sort -u)" = null ] && [ "$(st 'select(.step == "landed" and .issue == 7) | .issue')" = 7 ] \
    || fail "the batch the check refuses landed, or #7 never did: $(st 'select(.step == "landed")') $out"
  for s in $(git -C "$R" rev-list main); do
    ! { git -C "$R" cat-file -e "$s:flag-x" 2>/dev/null && git -C "$R" show "$s:a.txt" | grep -qx eight; } || fail "commit $s on main holds eight beside flag-x"
  done
  [ "$(batchruns)" = 4 ] || fail "the batch was not run again on main as it moved and split (its run, then the two again, then each): $(batchruns) batch runs: $out"
  [ -z "$(st 'select(.step == "blocked") | .step')" ] || fail "a card was blocked, not sent to its fix: $(st 'select(.step == "blocked")')"
  # #8, run again alone on main as it is now, fails the check there: a red run that goes to its fix round, where it was
  # blocked as a check failing on its own pass (card()).
  st 'select(.issue == 8 and .step == "test" and .result == "fail") | .tail' | grep -q "a product check failed on the change of $c8 on main as it is now" \
    || fail "#8's check failing on main as it is now was not a red test line sent to its fix: $(st 'select(.issue == 8) | "\(.step) \(.result) \(.reason)"' | tr '\n' ,)"
  st 'select(.issue == 8 and .step == "test" and .result == "fail") | .tail' | grep -q 'eight beside flag-x' || fail "#8's test line does not name the failing check: $(st '"\(.issue) \(.step) \(.result) \(.reason)"' | tr '\n' ,)"
  grep -q 'eight beside flag-x' "$STUB/fixbrief" || fail "#8's fix was not given the failing check"
  [ "$(sed -n '1p;$p' "$R/a.txt" | tr '\n' ' ')" = "seven eight-fixed " ] || fail "main does not hold #7's change and #8's fixed one: $(cat "$R/a.txt")"
}

# The owner (2026-11-13): a batch landed only on the main its run was on, so each card on other files that landed
# during the run cost the batch one more run of 5 to 10 minutes, holding the shared files through each. Main gets a
# commit on another file during the batch's run: the changes still apply there, so the batch lands on that one run,
# each card its own commit on top of main as it is now, with no step beyond a card landing alone.
# Another card on other files lands while the product checks judge the batch's change on main as it moved: the batch
# is fitted onto main as it is then and the checks run there again, with no second batch run. Main gets other.txt
# during the batch's run and third.txt during the checks of the batch's change on it.
t_batchmovedagain() {
  batchsetup "[$(issue 7 2026-01-01),$(issue 8 2026-01-02)]"; echo 8 > "$STUB/ready"
  echo 'case $PWD in *-7) sed -i 1s/.*/seven/ a.txt ;; *) echo eight >> a.txt ;; esac' > "$STUB/build"
  printf '%s\n' '! git cat-file -e "$2:other.txt" 2>/dev/null || [ -e "$STUB/again" ] || ! git show "$2:a.txt" | grep -qx eight \
    || { : > "$STUB/again"; (cd "$R" && echo third > third.txt && git add third.txt && git commit -qm "a third file"); }' > "$STUB/flags"
  tune --arg f "$STUB/flags" '.checks += [$f]'
  during 'echo other > other.txt; git add other.txt; git commit -qm "another file"'
  out=$(loop run 2>&1) || fail "run exited non-zero: $out"
  c7=$(cardof 7); c8=$(cardof 8)
  [ -e "$STUB/moved" ] && [ -e "$STUB/again" ] || fail "main did not move during the batch's run and again during its checks: $out"
  [ "$(batchruns)" = 1 ] && [ "$(wc -l < "$STUB/tests")" = 3 ] || fail "the batch did not land on its one run: $(batchruns) batch runs, $(wc -l < "$STUB/tests") runs: $out"
  [ "$(git -C "$R" log --reverse --format=%s HEAD~4..HEAD | tr '\n' ,)" = "another file,a third file,feat(product): title 8 (#8),feat(product): title 7 (#7)," ] \
    || fail "main did not get one commit per card on top of both commits it got meanwhile: $(git -C "$R" log --format=%s | tr '\n' ,)"
  [ "$(st 'select(.step == "landed") | .batch | join(" ")' | sort -u)" = "$c8 $c7" ] || fail "the two cards did not land as one batch: $(st 'select(.step == "landed")')"
  for n in 7 8; do
    [ "$(st "select(.issue == $n and $NOMARK) | .step" | tr '\n' ' ')" = "picked worktree brief build review test landed " ] || fail "steps of #$n: $(st "select(.issue == $n) | .step" | tr '\n' ' ')"
  done
  [ "$(sed -n '1p;$p' "$R/a.txt" | tr '\n' ' ')" = "seven eight " ] && [ "$(cat "$R/other.txt")" = other ] || fail "main does not hold the two changes and the other file: $(cat "$R/a.txt")"
  [ "$(cat "$R/third.txt")" = third ] && [ -z "$(git -C "$R" status --porcelain)" ] && [ -z "$(ls "$T/$CASE/cards")" ] || fail "main is dirty, or a worktree or mark is left"
}

# The owner (2026-11-17): a card that changed the holder's files slept on it for hours, through the holder's fixes.
# #7 holds a.txt and changes its line 20; #8 appends a line, which does not apply with #7's change, so #8 is told to
# wait on #7. It is stacked instead: one session brings its change onto main plus #7's change (the session finds
# #7's line there), it is reviewed again and tests there while #7 holds a.txt, and #7's batch takes it after #7: one
# batch run, main gets #7's commit then #8's. Bug it catches too: the batch put #8, ready first, before #7, and #8's
# change, made on #7's, does not apply on main alone, so #8 left the batch.
t_stackbatch() {
  batchsetup "[$(issue 7 2026-01-01),$(issue 8 2026-01-02)]"; : > "$STUB/overlap"; echo 8 > "$STUB/ready"
  cat > "$STUB/build" <<'EOF'
if grep -q '^# Stacked: apply the same change' "$STUB/brief"; then tail -n 1 a.txt > "$STUB/stackline"; echo eight >> a.txt
else case $PWD in *-7) sed -i 20s/.*/seven/ a.txt ;; *) echo eight >> a.txt ;; esac; fi
EOF
  out=$(loop run 2>&1) || fail "run exited non-zero: $out"
  c7=$(cardof 7); c8=$(cardof 8)
  grep -q "card $c8 is stacked on card $c7" <<<"$out" && [ "$(cat "$STUB/stackline" 2>/dev/null)" = seven ] \
    || fail "#8 was not stacked onto main plus #7's change: $(cat "$STUB/stackline" 2>/dev/null): $out"
  st 'select(.issue == 8 and .step == "fix") | .reason' | grep -qF "stacked on card $c7" && [ "$(st 'select(.issue == 8 and .step == "review") | .result' | wc -l)" = 2 ] \
    || fail "#8's stack session is not on its record, or #8 was not reviewed again after it: $(st 'select(.issue == 8) | "\(.step) \(.result) \(.reason)"' | tr '\n' ,)"
  grep -q "card $c7 tests a batch of 2: $c7 $c8" <<<"$out" && [ "$(batchruns)" = 1 ] || fail "#7 did not test one batch of itself, then #8: $out"
  [ "$(st 'select(.step == "landed") | "\(.issue) \(.batch | join(" "))"' | tr '\n' ,)" = "7 $c7 $c8,8 $c7 $c8," ] \
    && [ "$(git -C "$R" log --reverse --format=%s HEAD~2..HEAD | tr '\n' ,)" = "feat(product): title 7 (#7),feat(product): title 8 (#8)," ] \
    || fail "#7 and #8 did not land as one batch, #7 first: $(st 'select(.step == "landed")')"
  [ "$(tail -n 2 "$R/a.txt" | tr '\n' ' ')" = "seven eight " ] && [ -z "$(ls "$T/$CASE/cards")" ] || fail "main does not hold both changes, or a mark is left: $(cat "$R/a.txt"; ls "$T/$CASE/cards")"
}

# Bug: a batch that did not land left its card's claim keeping the whole batch's change (gather()). #8, out of the
# batch and waiting on #7, was stacked (stackto()) onto main plus that change, #8's own change in it already: it went
# to a session to fit a change that was there, gave way for it, and #9 went past it. unmate() makes the change #7's
# claim keeps #7's own again, and takes the batch's marks away; with no batch it leaves that change as it is.
t_unmatecpatch() {
  setup '[]'; seq 20 > "$R/a.txt"; git -C "$R" commit -qam "a longer a.txt"
  local CARDS=$T/$CASE/cards wt mates
  mkdir -p "$CARDS"; wt=$CARDS/c7-7; git -C "$R" worktree add -q "$wt" -b card-7 main
  echo seven >> "$wt/a.txt"; git -C "$wt" add -A
  echo 'the batch of #7 and #8' > "$wt.cpatch"; : > "$CARDS/c8-8.batch"
  eval "$(sed -n '/^unbatch() {/p; /^unmate() {/,/^}/p' "$SRC/lib/claim.sh")"
  mates=(c8-8 c7-7); unmate
  git -C "$wt" diff --cached --binary --no-renames | cmp -s - "$wt.cpatch" && [ ! -e "$CARDS/c8-8.batch" ] && [ ${#mates[@]} = 0 ] \
    || fail "#7's claim still keeps the batch's change, or a batch mark is left: $(cat "$wt.cpatch"; ls "$CARDS")"
  echo 'as its claim kept it' > "$wt.cpatch"; unmate
  [ "$(cat "$wt.cpatch")" = 'as its claim kept it' ] || fail "with no batch, unmate() changed the change #7's claim keeps: $(cat "$wt.cpatch")"
}
