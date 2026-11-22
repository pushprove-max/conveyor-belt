#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 300
# Engine cases: the same-file rule.
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"
# The engine folder, as lib.sh sets it: named here too, so the release closure (tools/closure.sh) follows this file's paths.
SRC=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
# The cases call the engine's functions on card worktrees made here, with no loop run: claim() in the case's own shell
# (sfclaim, as readyfirst.test.sh's t_readyclaim loads it), and settle(), land(), urgent() and pick() in the engine
# shell (fx_in, lib.sh).

# sfcard <issue> <change>: card c<issue>-<issue>'s worktree on main, <change> made in it and staged, its picked line
# in the card records.
sfcard() {
  CARDS=$T/$CASE/cards; mkdir -p "$CARDS"
  git -C "$R" worktree add -q --detach "$CARDS/c$1-$1" main && (cd "$CARDS/c$1-$1" && eval "$2") && git -C "$CARDS/c$1-$1" add -A \
    || fail "the change of card $1 could not be staged"
  landed "$1" | jq -c --arg c "c$1-$1" '.card = $c | .step = "picked"' >> "$ST/cards.jsonl"
}
# claim() and what it calls (lib/claim.sh), with stdb() (lib/records.sh), in the case's shell. cl <issue>: that card's
# claim, under this shell's pid (alive), printing what it waits on ({"on": ...}), nothing when it holds its files.
sfclaim() {
  eval "$(sed -n '/^claim() {/,/^}/p; /^together() {/,/^}/p; /^ready() {/,/^}/p; /^fits() {/,/^}/p; /^merge3() {/,/^}/p; /^cardpatch() {/p; /^tested() {/,/} # <worktree>$/p; /^testedhere() {/p; /^readysince() {/,/^}/p; /^bpid() {/,/^}/p; /^turnq() {/,/^}/p' "$SRC/lib/claim.sh")"
  packget() { printf -v "$2" 1; } # for turnq(): the test pack's landBatch, batches off
  eval "$(sed -n '/^stdb() {/,/^}/p' "$SRC/lib/records.sh")"
  # shellcheck disable=SC2034 # read by stdb(): its answers, and the folder state.py is in
  declare -gA ASKED_K=() ASKED_V=() && HERE=$SRC
  ctl() { cat "$ST/control.json"; }
  # Defined here, in the case's shell, not at the top of this file: the runner sources every case file into one shell,
  # and a top-level order() would replace deps.test.sh's.
  cl() { (cd "$R" && STATE=$ST/cards.jsonl BRANCH=main claim "c$1-$1" "$CARDS/c$1-$1" $$); } # <issue>
  order() { jq -c --argjson o "$1" '.order = $o' "$ST/control.json" > "$STUB/c" && mv "$STUB/c" "$ST/control.json"; } # <order json>
}
# gone <issue> [<change>]: card <issue> landed: its change (or <change>, made in main's checkout, as a session fitted
# it there) committed on main, its landed line written, its claim gone with it.
gone() {
  if [ -n "${2:-}" ]; then (cd "$R" && eval "$2") && git -C "$R" add -A; else git -C "$CARDS/c$1-$1" diff --cached --binary | git -C "$R" apply --index; fi \
    && git -C "$R" commit -qm "title $1 (#$1)" || fail "the change of card $1 could not land"
  landed "$1" | jq -c --arg c "c$1-$1" '.card = $c' >> "$ST/cards.jsonl"; rm -f "$CARDS/c$1-$1.claim" "$CARDS/c$1-$1.cpatch"
}
# sfsettle <issue>: settle() of card <issue> at its landing step, as card() calls it, in the engine shell (fx_in), with
# card()'s caught set to $SFCAUGHT; run.out ends with "settle: <its exit>". Each look of a wait sleeps the live
# record's seconds: here sleep() counts the looks (SLEPT) and calls atlook() at each instead, to do what the case needs
# done during the wait (the holder lands); a wait of over 10 looks ends the call (exit 8).
atlook() { :; }
# sfsleep: what sleep() does in sfsettle's engine shell (sleep() calls it, so its caller's caller is settle()).
sfsleep() {
  [ "${FUNCNAME[2]}" = settle ] || { command sleep "$@"; return; } # sleep: a sleep outside settle() is the real one
  SLEPT=$((SLEPT + 1)); [ "$SLEPT" -le 10 ] || exit 8; atlook
}
sfsettle() {
  # shellcheck disable=SC2034 # read by the commands fx_in runs
  SFN=$1
  fx_in 'cd "$R" || exit 9; caught=${SFCAUGHT:-} waitsec=0 behind="[]" parsecheck="" SLEPT=0
    sleep() { sfsleep "$@"; }
    settle "c$SFN-$SFN" "$SFN" "$CARDS/c$SFN-$SFN" "Build the issue." land "$(issue "$SFN" 2026-01-01)"; echo "settle: $?"'
}
sfout() { tail -n 1 "$T/$CASE/run.out"; }

# Bug: two cards in flight that change the same file both went on to land, and the second met "rebase onto main
# conflicts". The second, #8, waits at its landing claim while #7 holds a.txt, its live record naming #7 and the file,
# and says it waits once however many looks the wait takes. Once #7 has landed (during the second look) #8's patch no
# longer applies (both changed the same lines): one session, told main moved and given the card's patch, brings it
# onto main, and settle() returns 2, so it is reviewed again there.
t_samefile() {
  setup '[]'; sfclaim; sfcard 7 'echo seven >> a.txt'; sfcard 8 'echo eight >> a.txt'
  [ -z "$(cl 7)" ] || fail "#7 waited with no other claim"
  echo 'if grep -q "^# Main moved: apply the same change" "$STUB/brief"; then cp "$STUB/brief" "$STUB/caught"; printf "one\nseven\neight\n" > a.txt; fi' > "$STUB/build"
  atlook() { [ "$SLEPT" != 1 ] || cp "$CARDS/c8-8.live" "$STUB/waitlive"; [ "$SLEPT" != 2 ] || gone 7; }
  sfsettle 8
  [ "$(sfout)" = "settle: 2" ] || fail "#8 was not to be reviewed again after its wait: $(cat "$T/$CASE/run.out")"
  [ "$(jq -r .step "$STUB/waitlive" 2>/dev/null)" = land ] && [ "$(jq -r .action "$STUB/waitlive")" = "waiting on card c7-7, which changes the same files: a.txt" ] \
    && [ "$(jq -c .waits "$STUB/waitlive")" = '{"on":"c7-7","paths":["a.txt"]}' ] || fail "#8 was not shown waiting on #7 to land, with the file: $(cat "$STUB/waitlive" 2>/dev/null)"
  [ "$(grep -c 'waits on card' "$T/$CASE/run.out")" = 1 ] && grep -qx 'conveyor: card c8-8 waits on card c7-7, which changes the same files: a.txt' "$T/$CASE/run.out" \
    || fail "settle() did not say #8 waits, once: $(cat "$T/$CASE/run.out")"
  grep -q '^The file .*\.patch, made against commit [0-9a-f]*\.$' "$STUB/caught" 2>/dev/null || fail "the session after the wait was not told main moved, with the card's patch"
  [ "$(st 'select(.issue == 8) | [.step, .of // empty] | join(" ")' | tr '\n' ,)" = "picked,start land,start fix,fix," ] \
    && st 'select(.issue == 8 and .step == "fix") | .reason' | grep -q '^main moved since the card' || fail "steps of #8: $(st 'select(.issue == 8) | "\(.step) \(.of // "") \(.reason)"' | tr '\n' ,)"
  [ "$(tr '\n' ' ' < "$CARDS/c8-8/a.txt")" = "one seven eight " ] && [ "$(git -C "$CARDS/c8-8" rev-parse HEAD)" = "$(git -C "$R" rev-parse main)" ] \
    || fail "#8's change was not brought onto main with #7's"
}

# Bug: among cards waiting on a file with no holder, the older pick always went first, so an ordered card waited
# behind any older one. #6 holds a.txt and is ordered, so no card goes past it; once it lands, the ordered #9 and #8
# go before the older #7 that is not ordered, and #9, earlier in the order list, before #8.
t_samequeue() {
  setup '[]'; sfclaim; for n in 6 7 8 9; do sfcard $n "echo $n >> a.txt"; done
  [ -z "$(cl 6)" ] || fail "#6 waited with no other claim"; order '[6, 9, 8]'
  for n in 7 8 9; do w=$(cl $n) && [ "$(jq -r .on <<<"$w")" = c6-6 ] || fail "#$n went past the ordered holder #6: $w"; done
  gone 6
  w=$(cl 7) && [ "$(jq -r .on <<<"$w")" = c9-9 ] || fail "the older #7, not ordered, did not wait on the ordered #9 first: $w"
  w=$(cl 8) && [ "$(jq -r .on <<<"$w")" = c9-9 ] || fail "the ordered #8 did not wait on #9, earlier in the order list: $w"
  w=$(cl 9) && [ -z "$w" ] && [ "$(jq .held "$CARDS/c9-9.claim")" = true ] || fail "#9, first in the order list, did not claim a.txt: $w"
  gone 9 'echo 9 >> a.txt'
  w=$(cl 7) && [ "$(jq -r .on <<<"$w")" = c8-8 ] || fail "the older #7 did not wait on the ordered #8: $w"
  w=$(cl 8) && [ -z "$w" ] && [ "$(jq .held "$CARDS/c8-8.claim")" = true ] || fail "the ordered #8 did not claim a.txt before the older #7: $w"
}

# Bug: once the ordered #9 went past #7 on a.txt, both held it, and the Board told #8 it was waiting on #7 (the
# earlier claim) though the ordered #9 goes first. #8's wait must name #9.
t_sameboard() {
  setup '[]'; sfclaim; for n in 7 8 9; do sfcard $n "echo $n >> a.txt"; done
  [ -z "$(cl 7)" ] || fail "#7 waited with no other claim"; order '[9]'
  w=$(cl 9) && [ -z "$w" ] && [ "$(jq -c '[.held, .passed]' "$CARDS/c7-7.claim")" = '[true,true]' ] || fail "the ordered #9 did not go past #7: $w $(cat "$CARDS/c7-7.claim")"
  w=$(cl 8) && [ "$(jq -r .on <<<"$w")" = c9-9 ] || fail "#8 was not shown waiting on the ordered #9: $w"
}

# Bug: a card the owner ordered first sat built behind an older card that was not ordered and held the same file.
# The ordered #8 claims a.txt while #7 holds it and goes on; #7, marked passed, waits on #8 at its next claim.
t_samepast() {
  setup '[]'; sfclaim; sfcard 7 'echo seven >> a.txt'; sfcard 8 'echo eight >> a.txt'
  [ -z "$(cl 7)" ] || fail "#7 waited with no other claim"; order '[8]'
  w=$(cl 8) && [ -z "$w" ] && [ "$(jq .held "$CARDS/c8-8.claim")" = true ] || fail "the ordered #8 waited on #7: $w"
  w=$(cl 7) && [ "$(jq -c . <<<"$w")" = '{"on":"c8-8","paths":["a.txt"]}' ] && [ "$(jq -c '[.held, .passed]' "$CARDS/c7-7.claim")" = '[false,true]' ] \
    || fail "#7 did not wait on the ordered #8 at its next claim, marked passed: $w $(cat "$CARDS/c7-7.claim")"
}

# Bug: a card the ordered #8 went past landed without another review when its patch still applied to main after #8
# landed, so nobody reviewed it against #8's change. #7, passed (as claim() marks it: t_samepast), changes a.txt's
# first line and main's #8 its last: settle() fits its patch as it is and returns 2, so it is reviewed again.
t_samepastclean() {
  setup '[]'; seq 20 | sed 1s/1/one/ > "$R/a.txt"; git -C "$R" commit -qam "a longer a.txt"
  sfcard 7 'sed -i 1s/one/seven/ a.txt'; sfcard 8 'echo eight >> a.txt'
  echo "{\"pid\":$$,\"paths\":[\"a.txt\"],\"held\":true,\"passed\":true}" > "$CARDS/c7-7.claim"; gone 8
  sfsettle 7
  [ "$(sfout)" = "settle: 2" ] || fail "#7, passed by the ordered #8, was not to be reviewed again though its patch applied: $(cat "$T/$CASE/run.out")"
  [ "$(sed -n '1p;$p' "$CARDS/c7-7/a.txt" | tr '\n' ' ')" = "seven eight " ] && [ ! -e "$STUB/sessions" ] && [ "$(jq .was "$CARDS/c7-7.claim")" = true ] \
    || fail "#7's patch was not applied on main as it is, with no session: $(cat "$CARDS/c7-7.claim")"
}

# Bug: a card the ordered #8 went past landed without another review when #8 had landed and let go of a.txt before
# #7's next claim, so #7 found nobody to wait on. Its claim says it was passed (was), for settle() to review it again.
t_samepastgone() {
  setup '[]'; sfclaim; sfcard 7 'echo seven >> a.txt'; sfcard 8 'echo eight >> a.txt'
  [ -z "$(cl 7)" ] || fail "#7 waited with no other claim"; order '[8]'
  [ -z "$(cl 8)" ] || fail "the ordered #8 waited on #7"
  gone 8
  w=$(cl 7) && [ -z "$w" ] && [ "$(jq -c '[.held, .was]' "$CARDS/c7-7.claim")" = '[true,true]' ] \
    || fail "#7, passed by #8 that has landed since, is not to be reviewed again: $w $(cat "$CARDS/c7-7.claim")"
}

# Bug: a card read that no ordered card had gone past it, then, before its locked landing, the ordered #8 went past it
# and landed a change on other lines of the same file; #7's patch still applied, so it landed without another review.
# land() reads the mark again under the lock: #7, passed while at its landing step, lands nothing.
t_samepastland() {
  setup '[]'; sfcard 7 'echo seven >> a.txt'
  echo "{\"pid\":$$,\"paths\":[\"a.txt\"],\"held\":true,\"was\":false,\"passed\":true}" > "$CARDS/c7-7.claim"
  m=$(git -C "$R" rev-parse main)
  fx_in 'cd "$R" && land c7-7 7 "$CARDS/c7-7" "title 7 (#7)"; echo "land: $?"'
  [ "$(cat "$T/$CASE/run.out")" = "an ordered or ready card went past it since its claim; nothing was landed"$'\n'"land: 1" ] \
    && [ "$(git -C "$R" rev-parse main)" = "$m" ] || fail "#7 landed though an ordered card went past it: $(cat "$T/$CASE/run.out")"
}

# The owner (2026-11-12): "how do we avoid having so many cards waiting". Cards that share a file and changed
# different functions of it do not overlap: their changes apply together, so #8 claims a.txt while #7 holds it,
# neither waiting nor going past the other.
t_sameapply() {
  setup '[]'; { printf '%s\n' 'first() {' '  echo one' '}'; seq 10; printf '%s\n' 'last() {' '  echo two' '}'; } > "$R/a.txt"; git -C "$R" commit -qam "a.txt of two functions"
  sfclaim; sfcard 7 'sed -i "s/echo one/echo seven/" a.txt'; sfcard 8 'sed -i "s/echo two/echo eight/" a.txt'
  [ -z "$(cl 7)" ] || fail "#7 waited with no other claim"
  w=$(cl 8) && [ -z "$w" ] && [ "$(jq -sc 'map([.held, .paths, .passed])' "$CARDS/c7-7.claim" "$CARDS/c8-8.claim")" = '[[true,["a.txt"],null],[true,["a.txt"],null]]' ] \
    || fail "#8 waited on #7, or went past it, though their changes apply together: $w $(cat "$CARDS"/*.claim)"
}

# Bug: cards with no file in common are held to one at a time. #8 on b.txt claims while #7 holds a.txt.
t_apart() {
  setup '[]'; sfclaim; sfcard 7 'echo seven >> a.txt'; sfcard 8 'echo eight > b.txt'
  [ -z "$(cl 7)" ] || fail "#7 waited with no other claim"
  w=$(cl 8) && [ -z "$w" ] && [ "$(jq -sc 'map(.held)' "$CARDS/c7-7.claim" "$CARDS/c8-8.claim")" = '[true,true]' ] || fail "#8 waited on #7, with no file in common: $w"
}

# Bug: an older card that claimed a file after a younger card had claimed it went past its claim too, both past
# their claim on the same file. The older #7 waits at its claim on the younger #8 that holds a.txt. #8 then lands while
# #7 waits, and #7's tests had run on its change before (card()'s caught): settle() puts that change back as it was, on
# its own commit, for the landing's rebuild session to bring onto main, and returns 0.
t_sameorder() {
  setup '[]'; sfclaim; sfcard 7 'echo seven >> a.txt'; sfcard 8 'echo eight >> a.txt'
  [ -z "$(cl 8)" ] || fail "#8 waited with no other claim"
  w=$(cl 7) && [ "$(jq -c . <<<"$w")" = '{"on":"c8-8","paths":["a.txt"]}' ] || fail "the older #7 went past the younger #8's claim: $w"
  old=$(git -C "$CARDS/c7-7" rev-parse HEAD)
  atlook() { [ "$SLEPT" != 1 ] || gone 8; }
  SFCAUGHT=1 sfsettle 7
  [ "$(sfout)" = "settle: 0" ] && grep -qx 'conveyor: card c7-7 waits on card c8-8, which changes the same files: a.txt' "$T/$CASE/run.out" \
    || fail "#7 did not wait on #8, or did not go on to land: $(cat "$T/$CASE/run.out")"
  [ "$(git -C "$CARDS/c7-7" rev-parse HEAD)" = "$old" ] && [ "$(git -C "$CARDS/c7-7" diff --cached HEAD | grep -c '^+seven')" = 1 ] \
    && [ ! -e "$STUB/sessions" ] || fail "#7's change, its tests run on it, was not put back as it was for the landing's rebuild"
  # Its landing then meets the conflict with #8's change and lands nothing: that message is what starts card()'s one
  # rebuild, which brings #7 onto main and reviews it again there (port.test.sh t_rebase).
  m=$(git -C "$R" rev-parse main)
  fx_in 'cd "$R" && land c7-7 7 "$CARDS/c7-7" "title 7 (#7)"; echo "land: $?"'
  grep -q '^rebase onto main conflicts: ' "$T/$CASE/run.out" && [ "$(sfout)" = "land: 1" ] && [ "$(git -C "$R" rev-parse main)" = "$m" ] \
    || fail "#7, put back as it was, did not meet the conflict at landing for its rebuild: $(cat "$T/$CASE/run.out")"
}

# Bug: an older card holding x.txt whose fix added a.txt, while a younger card held a.txt, ignored the younger holder:
# both were past their claim on a.txt. #7 claimed x.txt alone, then #8 a.txt; #7's fix adds a.txt, and at its next
# claim #7 waits on #8 for a.txt, and once #8 lands it is brought onto main and reviewed again.
t_samelast() {
  setup '[]'; sfclaim; sfcard 7 'echo seven > x.txt'; sfcard 8 'echo eight >> a.txt'
  [ -z "$(cl 7)" ] && [ -z "$(cl 8)" ] || fail "#7 on x.txt and #8 on a.txt did not both claim"
  echo seven >> "$CARDS/c7-7/a.txt"; git -C "$CARDS/c7-7" add -A
  w=$(cl 7) && [ "$(jq -c . <<<"$w")" = '{"on":"c8-8","paths":["a.txt"]}' ] && [ "$(jq .held "$CARDS/c7-7.claim")" = false ] \
    || fail "#7, its fix adding a.txt, did not wait on #8 holding it: $w $(cat "$CARDS/c7-7.claim")"
  # #8 lands during the wait: #7's patch no longer applies, one session told main moved brings it onto main, and
  # settle() returns 2, so it is reviewed again there.
  echo 'if grep -q "^# Main moved: apply the same change" "$STUB/brief"; then printf "one\neight\nseven\n" > a.txt; echo seven > x.txt; fi' > "$STUB/build"
  atlook() { [ "$SLEPT" != 1 ] || gone 8; }
  sfsettle 7
  [ "$(sfout)" = "settle: 2" ] || fail "#7 was not to be reviewed again after #8 landed: $(cat "$T/$CASE/run.out")"
  st 'select(.issue == 7 and .step == "fix") | .reason' | grep -q '^main moved since the card' && [ "$(tr '\n' ' ' < "$CARDS/c7-7/a.txt")" = "one eight seven " ] \
    && [ "$(cat "$CARDS/c7-7/x.txt")" = seven ] && [ "$(git -C "$CARDS/c7-7" rev-parse HEAD)" = "$(git -C "$R" rev-parse main)" ] \
    || fail "no session brought #7 onto main with #8's change: $(st 'select(.issue == 7)' | tr '\n' ' ')"
}

# Bug: a card whose overlapping card landed before it claimed anything saw no claim, skipped the move onto main, and
# met "rebase onto main conflicts" at landing. At its landing claim #8 waits on nobody, its patch no longer applies to
# main, and one session brings it there; settle() returns 2, so it is reviewed again.
t_samelate() {
  setup '[]'; sfcard 7 'echo seven >> a.txt'; sfcard 8 'echo eight >> a.txt'; gone 7
  echo 'if grep -q "^# Main moved: apply the same change" "$STUB/brief"; then printf "one\nseven\neight\n" > a.txt; fi' > "$STUB/build"
  sfsettle 8
  [ "$(sfout)" = "settle: 2" ] && ! grep -q 'waits on card' "$T/$CASE/run.out" || fail "#8 was not brought onto main to be reviewed again: $(cat "$T/$CASE/run.out")"
  st 'select(.issue == 8 and .step == "fix") | .reason' | grep -q '^main moved since the card' && [ "$(tr '\n' ' ' < "$CARDS/c8-8/a.txt")" = "one seven eight " ] \
    || fail "no session brought #8 onto main: $(st 'select(.issue == 8)' | tr '\n' ' ')"
}

# Bug: a card that blocked while it held a file, and was given back by `retry`, kept every card that shares the file
# waiting on it, each holding a builder slot (8 of 10 slots for 70 minutes). A card that is not on the belt holds no
# file: card c1-7, its claim on a.txt standing and its process alive, makes #8 wait only while it is on the belt.
t_sameoff() {
  setup '[]'; sfclaim; sfcard 8 'echo two >> a.txt'
  landed 7 | jq -c '.card = "c1-7" | .step = "picked"' >> "$ST/cards.jsonl"
  echo "{\"pid\":$$,\"paths\":[\"a.txt\"],\"held\":true}" > "$CARDS/c1-7.claim"
  w=$(cl 8) && [ "$(jq -r .on <<<"$w")" = c1-7 ] || fail "#8 did not wait on c1-7 while it was on the belt: $w"
  landed 7 | jq -c '.card = "c1-7" | .step = "blocked" | .result = "blocked" | .reason = "review 1: review failed (exit 124)"' >> "$ST/cards.jsonl"
  w=$(cl 8) && [ -z "$w" ] || fail "#8 waited on the blocked c1-7: $w"
  loop retry 7 >/dev/null || fail "retry of #7 exited non-zero"
  [ -e "$CARDS/c1-7.claim" ] && w=$(cl 8) && [ -z "$w" ] && [ "$(jq .held "$CARDS/c8-8.claim")" = true ] || fail "#8 waited on c1-7, given back by retry: $w"
}
