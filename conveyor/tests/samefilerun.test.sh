#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 300
# Engine cases: the same-file rule, through the real loop.
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"
# The engine folder, as lib.sh sets it: named here too, so the release closure (tools/closure.sh) follows this file's paths.
SRC=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)

# The three cases below but t_samepastshared, which calls the engine's functions on t_samepastrun's landing, run cards
# through the real loop (loop run): the direct checks in samefile.test.sh and
# sameoff.test.sh show claim(), settle(), land() and urgent() each on its own, but only card() and run() join them (a
# fix round to the next claim, a pass at the landing step to another review, a wait on the belt to the pick past the
# cap), and only a run shows that join.
# Each acts at a hook in the step it waits for (settle()'s sleep, the reading before land(), a session), never polls.

# Bug it catches: the fix round's change was not what the card claimed next (card(): the fix, then settle() at its
# landing step), so a card whose fix added a file another card holds went on past that holder. #7 builds x.txt; its
# first review is a NO-GO and its fix adds a.txt, which card c1-8 holds (a stand-in: its claim under this shell's pid,
# alive). At its landing claim #7 waits on c1-8, naming it. At the first look of that wait (settle()'s sleep, the
# hook) c1-8 lands a change to b.txt and lets go of a.txt, and #7 goes on and lands.
t_samefixclaim() {
  setup "[$(issue 7 2026-01-01)]"; mkdir -p "$T/$CASE/cards"
  printf '%s\n' '[P1] x.txt:1 a.txt needs the line too' 'USER-VISIBLE: no' 'VERDICT: NO-GO' > "$STUB/review.1"; echo "$GO" > "$STUB/review.2"
  echo 'if [ -e x.txt ]; then echo seven >> a.txt; else echo seven > x.txt; fi' > "$STUB/build"
  landed 8 | jq -c '.card = "c1-8" | .step = "picked"' >> "$ST/cards.jsonl"; landed 8 | jq -c '.card = "c1-8"' > "$STUB/landed8"
  echo "{\"pid\":$$,\"paths\":[\"a.txt\"],\"held\":true}" > "$T/$CASE/cards/c1-8.claim"
  out=$(sleep() {
      if [ "${FUNCNAME[1]:-}" = settle ] && [ ! -e "$STUB/released" ]; then
        : > "$STUB/released"; local w; w=$(echo "$CONVEYOR_CARDS"/*-7)
        cp "$w.live" "$STUB/waitlive"; jq -c . "$w.claim" > "$STUB/waitclaim"; git -C "$w" diff --cached --name-only | tr '\n' ' ' > "$STUB/waitpaths"
        echo eight > "$R/b.txt" && git -C "$R" add b.txt && git -C "$R" commit -qm "title 8 (#8)" && cat "$STUB/landed8" >> "$ST/cards.jsonl" && rm -f "$CONVEYOR_CARDS/c1-8.claim"
      fi
      command sleep "$@"; } # sleep: the engine's own sleep, passed on as it was called
    export -f sleep; loop run 2>&1) || fail "run exited non-zero: $out" # loop: only card() takes the fix round's change to the landing claim, settle()'s wait and land()
  c7=$(st 'select(.issue == 7 and .step == "picked") | .card')
  [ "$(st 'select(.issue == 7 and (.step | IN("review", "fix"))) | "\(.step) \(.result)"' | tr '\n' ,)" = "review NO-GO,fix ok,review GO," ] \
    || fail "#7 was not reviewed, fixed and reviewed again: $(st 'select(.issue == 7) | "\(.step) \(.result) \(.reason)"' | tr '\n' ,)"
  [ "$(cat "$STUB/waitpaths" 2>/dev/null)" = "a.txt x.txt " ] && [ "$(jq -c .held "$STUB/waitclaim")" = false ] \
    || fail "#7 did not claim the file its fix added, or held it while c1-8 did: $(cat "$STUB/waitpaths" "$STUB/waitclaim" 2>/dev/null)"
  [ "$(jq -c '[.step, .waits, .action]' "$STUB/waitlive")" = '["land",{"on":"c1-8","paths":["a.txt"]},"waiting on card c1-8, which changes the same files: a.txt"]' ] \
    && grep -qxF "conveyor: card $c7 waits on card c1-8, which changes the same files: a.txt" <<<"$out" \
    || fail "#7 was not shown waiting on c1-8 for a.txt: $(cat "$STUB/waitlive") $out"
  [ "$(st 'select(.step == "landed") | .issue' | tr '\n' ' ')" = "8 7 " ] && [ "$(tail -n 1 "$R/a.txt")" = seven ] && [ "$(cat "$R/x.txt" "$R/b.txt" | tr '\n' ' ')" = "seven eight " ] \
    || fail "#7 did not go on and land once c1-8 let go: $(st '"\(.issue) \(.step) \(.result) \(.reason)"' | tr '\n' ,)"
}

# Bug it catches: a card that read no pass before its locked landing (card(): the passed check, then land()) landed
# though the ordered #8 went past it and landed just before, so nobody reviewed it against #8's change. #7 adds a case
# at the end of the test file a.test.sh. The weekly limit reading #7 asks for at its landing step, outside the lock and
# before land(), is the hook: there #8, first in the order list, claims a.test.sh with the engine's claim() and lands
# its own case at the end. The two additions conflict in a three-way merge, so claim() finds that they do not apply
# together (together(), on #7's claimed change) and #8 goes past #7; yet they are compatible: the landing fit merges
# the test file keeping both sides (unionfit()). land() then lands nothing, and #7 is fitted onto #8's commit and
# reviewed again there before it lands.
t_samepastrun() {
  setup "[$(issue 7 2026-01-01)]"; for i in 1 2; do echo "$GO" > "$STUB/review.$i"; done
  echo case1 > "$R/a.test.sh"; git -C "$R" add a.test.sh; git -C "$R" commit -qm "a test file"; m0=$(git -C "$R" rev-parse main)
  echo 'echo case7 >> a.test.sh' > "$STUB/build"; echo 'git rev-parse HEAD >> "$STUB/reviewheads"' > "$STUB/review-cmd"
  w8=$T/$CASE/c8-8; git -C "$R" worktree add -q --detach "$w8" main && echo case8 >> "$w8/a.test.sh" && git -C "$w8" add -A || fail "#8's change could not be staged"
  landed 8 | jq -c '.card = "c8-8" | .step = "picked"' > "$STUB/picked8"; landed 8 | jq -c '.card = "c8-8"' > "$STUB/landed8"
  { printf 'W=%q SRC=%q\n' "$w8" "$SRC"; cat <<'EOF'; } > "$STUB/limit"
if [ ! -e "$STUB/past" ] && jq -se 'map(select(.issue == 7)) | last | .step == "start" and .of == "land"' "$ST/cards.jsonl" >/dev/null 2>&1; then
  : > "$STUB/past"; cat "$STUB/picked8" >> "$ST/cards.jsonl"; jq -c '.order = [8]' "$ST/control.json" > "$STUB/c.new" && mv "$STUB/c.new" "$ST/control.json"
  ( . "$SRC/conveyor.sh" state-dir > /dev/null && eval "$(grep '^\. "\$HERE/lib/' "$SRC/commands/run.sh")" && names && cd "$R" && locked claim c8-8 "$W" $$; echo "claim: $?" ) > "$STUB/claim8" 2>&1
  jq -c .passed "$CONVEYOR_CARDS"/*-7.claim > "$STUB/past7"
  git -C "$W" diff --cached --binary | git -C "$R" apply --index && git -C "$R" commit -qm "title 8 (#8)" && cat "$STUB/landed8" >> "$ST/cards.jsonl"
fi
false
EOF
  out=$(CONVEYOR_LIMIT_CMD=". \"$STUB/limit\"" loop run 2>&1) || fail "run exited non-zero: $out" # loop: the order of the steps, a second review on #8's commit before the landing and no rebuild session, is card()'s alone
  [ "$(cat "$STUB/claim8" 2>/dev/null)" = "claim: 0" ] && [ "$(cat "$STUB/past7")" = true ] \
    || fail "the ordered #8 did not go past #7 at #7's landing step: $(cat "$STUB/claim8" "$STUB/past7" 2>/dev/null)"
  m8=$(git -C "$R" rev-parse main~1)
  [ "$(git -C "$R" log -1 --format=%s "$m8")" = "title 8 (#8)" ] && [ "$(git -C "$R" rev-parse main~2)" = "$m0" ] \
    && [ "$(tr '\n' ' ' < "$STUB/reviewheads")" = "$m0 $m8 " ] && [ "$(st 'select(.step == "review") | "\(.issue) \(.result)"' | tr '\n' ,)" = "7 GO,7 GO," ] \
    || fail "#7 was not reviewed again on #8's commit before it landed: $(cat "$STUB/reviewheads") $(st '"\(.issue) \(.step) \(.result) \(.reason)"' | tr '\n' ,)"
  [ "$(st 'select(.step == "landed") | .issue' | tr '\n' ' ')" = "8 7 " ] && [ "$(tr '\n' ' ' < "$R/a.test.sh")" = "case1 case8 case7 " ] \
    || fail "#7 did not land on #8's change: $(st '"\(.issue) \(.step) \(.result) \(.reason)"' | tr '\n' ,)"
  # The pass path, not the rebuild: a land() that tried the fit before reading the pass would meet the conflict and
  # rebuild #7 on #8's tip, a second session that appends case7 again and ends the same way as the lines above.
  [ "$(wc -l < "$STUB/sessions")" = 1 ] && [ -z "$(st 'select(.issue == 7 and (.step == "rebase" or .of == "rebase")) | .step')" ] \
    || fail "#7 was rebuilt in place of being fitted onto #8's commit as passed: $(cat "$STUB/sessions") $(st '"\(.issue) \(.step) \(.of // "")"' | tr '\n' ,)"
}

# What card() reads of #7 at its landing, once fitted onto #8's commit (t_samepastrun's turn, with no card): #7's tests
# passed on m0 (tested(), its list based there); #8 lands its case at the end of a.test.sh. settle() fits #7 onto #8's
# commit with the union merge and no session. Bug it catches: a card whose tests ran before #8 landed its case in the
# same test file landed on that pass, so a.test.sh never ran with both cases: the merged change is not the one that
# passed (testedhere() fails), a.test.sh is shared with #8 (sharedtests()), #8 is the card landed since (landedsince()),
# and the run again lists a.test.sh to run whole, not as passed (unshare()).
t_samepastshared() {
  setup "[$(issue 7 2026-01-01)]"; fx_wt 'echo case7 >> a.test.sh' a.test.sh case1; m0=$(git -C "$R" rev-parse main)
  echo '{"issue":7}' > "$FXWT.ready"; printf 'base\t%s\npass\ta.test.sh\n' "$m0" > "$FXWT.rerun"
  fx_in 'tested "$FXWT"'; [ "$RC" = 0 ] || fail "#7's pass could not be recorded: $(cat "$T/$CASE/run.out")"
  echo case8 >> "$R/a.test.sh"; git -C "$R" commit -qam "title 8 (#8)" || fail "#8 could not land"
  landed 8 | jq -c --arg s "$(git -C "$R" rev-parse main)" '.card = "c8-8" | .sha = $s' >> "$ST/cards.jsonl"
  fx_in 'cd "$R" || exit 9; caught="" waitsec=0 behind="[]" parsecheck=""
    session() { echo session >> "$STUB/sessions"; return 1; }
    settle c7 7 "$FXWT" "Build the issue." land "$(issue 7 2026-01-01)"; echo "settle: $?"
    if testedhere "$FXWT"; then echo "testedhere: 0"; else echo "testedhere: 1"; fi
    t=$(sharedtests "$FXWT" "'"$m0"'"); echo "sharedtests: $t"; echo "landedsince: $(landedsince "$FXWT" "'"$m0"'")"
    unshare "$FXWT" "$t" && grep -v "^base" "$FXWT.rerun" | sort | tr "\t\n" ":,"'
  [ ! -e "$STUB/sessions" ] && [ "$(git -C "$FXWT" rev-parse HEAD)" = "$(git -C "$R" rev-parse main)" ] \
    && [ "$(tr '\n' ' ' < "$FXWT/a.test.sh")" = "case1 case8 case7 " ] \
    || fail "#7 was not fitted onto #8's commit keeping both cases, with no session: $(cat "$T/$CASE/run.out")"
  [ "$(sed 1d "$T/$CASE/run.out" | tr '\n' '|')" = "testedhere: 1|sharedtests: a.test.sh|landedsince: c8-8|fail:a.test.sh,shared:a.test.sh," ] \
    || fail "card() would land #7 on its pass from before #8's case, or not run a.test.sh whole again: $(cat "$T/$CASE/run.out")"
}

# Bug it catches: the turn's pick past the cap (run(): urgent(), then `pick retried` with ONLY) did not take a card
# that `retry` gave back while a card on the belt waited on it, or took one --only leaves out, or one nobody waits on
# now. The cap is 1, the run is `run --only 11,12,16`, and three cards of another loop are on the belt (stand-ins:
# their picked line and live record): c3-13 comes to wait on card c4-12, c3-15 waits on c4-14, and c3-17 once waited
# on c4-16 and went on (its live record names no card). `retry` gave back #12, #14 and #16 before the run. The run
# picks #11, the oldest; its build session makes c3-13 wait on c4-12, then waits for #12's build (a pipe, 100 s at
# most): #12 is picked past the cap while #11 holds the only slot. #14 (not in --only) is never picked; #16 only once
# #11 and #12 have ended their builds. #16's build makes no change, so its card blocks with no review, test or landing: its pick
# is all the case reads of it.
t_sameoffrun() {
  setup "[$(issue 11 2026-01-01),$(issue 12 2026-01-02),$(issue 14 2026-01-03),$(issue 16 2026-01-04)]"; mkdir -p "$T/$CASE/cards"
  for i in 1 2; do echo "$GO" > "$STUB/review.$i"; done; tune '.tunables.poll = 1'; loop control cap 1 >/dev/null || fail "cap 1 was refused"
  for n in 12 14 16; do
    { landed $n | jq -c --arg c "c4-$n" '.card = $c | .step = "picked"'
      landed $n | jq -c --arg c "c4-$n" '.card = $c | .step = "blocked" | .result = "blocked" | .reason = "review 1: review failed (exit 124)"'
      landed $((n + 1)) | jq -c --arg c "c3-$((n + 1))" '.card = $c | .step = "picked"'; } >> "$ST/cards.jsonl"
    loop retry $n >/dev/null || fail "retry of #$n exited non-zero"
  done
  jq -cn '{step: "land", waits: {on: "c4-14", paths: ["a.txt"]}}' > "$T/$CASE/cards/c3-15.live"; echo '{"step": "test"}' > "$T/$CASE/cards/c3-17.live"
  mkfifo "$STUB/built12" || fail "the pipe could not be made"
  { printf 'C=%q\n' "$T/$CASE/cards"; cat <<'EOF'; } > "$STUB/build"
case $PWD in
  *-11) exec {L}<> "$STUB/built12"; jq -cn '{step: "land", waits: {on: "c4-12", paths: ["a.txt"]}}' > "$C/c3-13.live"
    read -r -t 100 l <&"$L" && : > "$STUB/heard12"; exec {L}<&-; echo eleven > b.txt ;;
  *-12) echo go 1<> "$STUB/built12"; echo twelve > c.txt ;;
  *) : ;;
esac
EOF
  out=$(loop run --only 11,12,16 2>&1) || fail "run exited non-zero: $out" # loop: the pick past the cap is run()'s turn, with a card on the belt waiting on the retried one
  [ -e "$STUB/heard12" ] || fail "the retried #12 was not picked while #11 held the only slot: $(st '"\(.issue) \(.step)"' | tr '\n' ,)"
  [ -z "$(st 'select(.issue == 14 and .step == "picked")')" ] || fail "run --only 11,12,16 picked the retried #14: $(st '"\(.issue) \(.step)"' | tr '\n' ,)"
  # The picked, build and landed lines in their order: #16 is picked last, only once #11 and #12 have both ended their
  # builds (a card in its review or tests holds no build slot), and #11 and #12 land; #16, built to no change, blocks
  # and never lands.
  [ "$(jq -rs '[.[] | select((.issue | IN(11, 12, 16)) and (.step | IN("picked", "build", "landed"))) | "\(.issue) \(.step)"] as $l
      | ($l | index("16 picked")) as $q | [($l | map(select(endswith(" picked"))) | join(",")),
        ($q != null and ([$l | index("11 build", "12 build")] | all(. != null and . < $q))), ($l | map(select(IN("11 landed", "12 landed"))) | length)] | @json' "$ST/cards.jsonl")" \
    = '["11 picked,12 picked,16 picked",true,2]' ] \
    || fail "#16, waited on by nobody now, was picked past the cap (before #11 and #12 had ended their builds), or #11 or #12 did not land: $(st '"\(.issue) \(.step)"' | tr '\n' ,)"
}
