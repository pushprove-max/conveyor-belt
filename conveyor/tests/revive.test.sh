#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 300
# Engine cases: a loop takes up the cards whose process is gone (the machine or the loop stopped under them). (A serve
# loop that restarts on new code adopts the cards in flight: adopt.test.sh.)
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"
# The engine folder, as lib.sh sets it: named here too, so the release closure (tools/closure.sh) follows this file's paths.
SRC=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)

# The cards whose process was gone (run(): revive()). gonestop <pid>: it and every process under it, each stopped
# before the processes under it are looked for, so none starts another unseen; KILL then ends them all at once, as a
# power cut does.
gonestop() { local k; kill -STOP "$1" 2>/dev/null; echo "$1"; for k in $(pgrep -P "$1"); do gonestop "$k"; done; }
# gonecard <card> <issue> <pid> <started> [<step>]: the lines of a card that the machine stopped mid-build (or mid-step).
gonecard() {
  jq -cn --arg c "$1" --argjson n "$2" --argjson p "$3" --arg s "$4" --arg o "${5:-build}" '{card:$c,issue:$n,time:"2026-01-01T00:00:00Z",tokens:{claude:0,codex:0},result:"ok",sha:"",reason:""}
    | (. + {step:"picked"}), (. + {step:"worktree",pid:$p,started:$s}), (. + {step:"start",of:$o})' >> "$ST/cards.jsonl"
}

# The owner, 2026-11-14: a power cut left five cards open for good, each listed stuck, the restarted loop not picking
# them and `retry` refusing them ("has a card that is still open"); each was saved and given back by hand. Here #7's
# build is killed mid-session with the loop over it, as the machine stopping kills them, its change made and not
# staged: a tracked edit and a new file. Bugs: the next loop leaves the card open, blocks it without its change (or
# without the new file), or waits for someone to `retry` it. It blocks it with its change kept and picks #7 again from
# that work, with no one asked: the new card's session adds nothing, and the card lands with both files.
t_gonebuild() {
  local lp c1 c2 out
  setup "[$(issue 7 2026-01-01)]"; echo "$GO" > "$STUB/review.1"
  echo '[ -e "$STUB/built" ] || { echo two >> a.txt; echo new > u.txt; : > "$STUB/built"; exec sleep 600; }' > "$STUB/build" # sleep: a build the machine stops
  ( loop run > "$STUB/run1.out" 2>&1 ) & lp=$!
  wait_until '[ -e "$STUB/built" ]' || fail "#7's build did not start: $(cat "$STUB/run1.out")"
  # shellcheck disable=SC2046 # gonestop prints one pid a line
  kill -KILL $(gonestop $lp) 2>/dev/null; wait $lp 2>/dev/null
  c1=$(st 'select(.issue == 7 and .step == "picked") | .card')
  [ "$(st 'select(.issue == 7) | .step' | tail -n 1)" = start ] || fail "the killed card is not left open mid-build: $(st 'select(.issue == 7)')"
  out=$(loop run 2>&1) || fail "the next run exited non-zero: $out"
  grep -qF "card $c1 had an open record and its process was gone; it is blocked, its work kept, and issue #7 is given back" <<<"$out" \
    || fail "the run did not say it took up the card: $out"
  [ "$(jq -r --arg c "$c1" 'select(.card == $c and .step == "blocked") | [.reason, .kept, .retriedAt != null] | @tsv' "$ST/retried.jsonl")" \
    = "its process was gone: the machine or the loop stopped"$'\t'"kept/$c1"$'\t'true ] \
    || fail "the card was not blocked with its kept work and given back: $(jq -c --arg c "$c1" 'select(.card == $c)' "$ST/retried.jsonl" 2>&1) $(st 'select(.issue == 7)')"
  [ "$(git apply --numstat "$ST/kept/$c1/$c1.patch" | cut -f3 | sort | tr '\n' ' ')" = "a.txt u.txt " ] \
    || fail "the kept patch is not the worktree's change, its new file included: $(cat "$ST/kept/$c1/$c1.patch" 2>&1)"
  c2=$(st 'select(.issue == 7 and .step == "picked") | .card')
  [ -n "$c2" ] && [ "$c2" != "$c1" ] || fail "#7 was not picked again: $(st 'select(.issue == 7)')"
  [ "$(st 'select(.step == "worktree") | .reason')" = "resumed from the kept patch of card $c1: one session, then review" ] \
    || fail "the new card did not start from the kept work: $(st 'select(.step == "worktree")')"
  [ "$(st 'select(.step == "landed") | .card')" = "$c2" ] && [ "$(git -C "$R" show main:a.txt | tr '\n' ' ')$(git -C "$R" show main:u.txt)" = "one two new" ] \
    || fail "the new card did not land the kept work: $(st 'select(.issue == 7) | .step' | tr '\n' ' ') $(git -C "$R" show --stat main)"
}

# The same mid-test. The test command has two files: a.test passes, and b.test, on the first run only, hangs until the
# machine stops it. Bugs: the card picked again from the kept work runs a.test again (what the cut run had passed is
# lost with its worktree), or is not told it passed. Its run is given `pass a.test` and runs b.test alone, as any run
# again after a run cut short does. The build is the same edit each time, so the change tested is the same.
t_gonetest() {
  local lp c1 out
  setup "[$(issue 7 2026-01-01)]"; echo "$GO" > "$STUB/review.1"; echo "$GO" > "$STUB/review.2"
  echo 'grep -qx two a.txt || echo two >> a.txt' > "$STUB/build"
  cat > "$STUB/test-cmd" <<'EOF'
RR=${CONVEYOR_TEST_RERUN:-/dev/null}; n=$(( $(cat "$STUB/n" 2>/dev/null || echo 0) + 1 )); echo "$n" > "$STUB/n"; cp "$RR" "$STUB/rerun.$n"
for f in a.test b.test; do
  ! grep -qxF "pass	$f" "$RR" || continue
  echo "== $f"; echo "== $f" >> "$CONVEYOR_TEST_LOG/run.log"; echo "$n $f" >> "$STUB/ran"
  [ "$f" = a.test ] || [ -e "$STUB/tested" ] || { : > "$STUB/tested"; exec sleep 600; } # sleep: a test the machine stops
  echo "ok $f"; echo "-- ok $f" >> "$CONVEYOR_TEST_LOG/run.log"
done
EOF
  ( loop run > "$STUB/run1.out" 2>&1 ) & lp=$!
  wait_until '[ -e "$STUB/tested" ]' || fail "#7's test run did not reach b.test: $(cat "$STUB/run1.out")"
  # shellcheck disable=SC2046 # gonestop prints one pid a line
  kill -KILL $(gonestop $lp) 2>/dev/null; wait $lp 2>/dev/null
  c1=$(st 'select(.issue == 7 and .step == "picked") | .card')
  [ "$(st 'select(.issue == 7) | .of // .step' | tail -n 1)" = test ] || fail "the killed card is not left open mid-test: $(st 'select(.issue == 7)')"
  out=$(loop run 2>&1) || fail "the next run exited non-zero: $out"
  grep -qF "card $c1 had an open record and its process was gone; it is blocked, its work kept, and issue #7 is given back" <<<"$out" \
    || fail "the run did not say it took up the card: $out"
  [ "$(st 'select(.step == "worktree") | .reason')" = "resumed from the kept patch of card $c1: one session, then review" ] \
    || fail "the new card did not start from the kept work: $(st 'select(.step == "worktree")')"
  [ "$(grep $'^pass\t' "$STUB/rerun.2" | tr '\t\n' ':|')" = "pass:a.test|" ] \
    || fail "the new card's run was not told what the cut run had passed: $(cat "$STUB/rerun.2" 2>&1)"
  [ "$(sed -n 's/^2 //p' "$STUB/ran" | tr '\n' ' ')" = "b.test " ] || fail "the new card's run did not run b.test alone: $(cat "$STUB/ran")"
  [ "$(st 'select(.step == "landed") | .issue')" = 7 ] || fail "the new card did not land: $(st 'select(.issue == 7) | .step' | tr '\n' ' ')"
}

# A card of the loop's own whose process a signal ends mid-test, the loop still running. Bugs (#390: two cards ended
# with nothing anywhere saying why): its blocked line says only that it ended, or the machine or the loop stopped,
# with no step or signal, and its kept error output says nothing; its test run outlives it in a worktree that is gone.
# The run is a batch's, its own change set aside (<worktree>.bpatch) and another card's alone in its worktree, as a
# split does. Bug: the other card's change is kept as its work and its own is lost with its .bpatch.
t_killedtest() {
  local lp c tp r
  setup "[$(issue 7 2026-01-01)]"; echo "$GO" > "$STUB/review.1"; echo 'echo two >> a.txt' > "$STUB/build"
  # A turn a second, not the pack's 30 s: `turns 2` below waits out two of the loop's waits with the card running.
  tune '.tunables.poll = 1'
  echo 'git add -A && git diff --cached --binary --no-renames > "$PWD.bpatch" && git rev-parse HEAD > "$PWD.lent" && git reset -q --hard && echo eight > m.txt && git add -A
    echo $$ > "$STUB/testpid"; exec sleep 600' > "$STUB/test-cmd" # sleep: a test run under way when the card is killed
  watchturns; ( loop run > "$STUB/run.out" 2>&1 ) & lp=$!
  wait_until '[ -s "$STUB/testpid" ]' || fail "#7's test run did not start: $(cat "$STUB/run.out")"
  tp=$(cat "$STUB/testpid"); turns 2 # the loop has looked under the card since its test run began
  kill -TERM "$(st 'select(.issue == 7 and .step == "worktree") | .pid')"
  wait_until '[ "$(st "select(.issue == 7) | .step" | tail -n 1)" = blocked ]' || { kill -KILL "$tp"; fail "the killed card was not blocked: $(st 'select(.issue == 7)') $(cat "$STUB/run.out")"; }
  kill $lp 2>/dev/null; wait $lp 2>/dev/null
  ! kill -0 "$tp" 2>/dev/null || { kill -KILL "$tp"; fail "the killed card's test run ran on after it was blocked"; }
  c=$(st 'select(.issue == 7 and .step == "picked") | .card'); r=$(st 'select(.issue == 7 and .step == "blocked") | .reason')
  [[ $r =~ ^"its process ended without a result in its test step".*"; signal TERM killed it (exit status 143)"$ ]] || fail "the blocked line does not name the step and the signal: $r"
  grep -qxF "conveyor: card $c: $r" "$ST/kept/$c/$c.err" || fail "the kept error output does not say why: $(cat "$ST/kept/$c/$c.err" 2>&1)"
  [ "$(git apply --numstat "$ST/kept/$c/$c.patch" | cut -f3 | tr '\n' ' ')" = "a.txt " ] \
    || fail "the kept patch is not the card's own change: $(cat "$ST/kept/$c/$c.patch" 2>&1)"
}

# The same for a card whose shell stopped on an error (#390: `own: unbound variable`, exit 1, no signal), from
# cardgone() alone. Bugs: its line names no step, action or exit status; it names the action of an earlier step that
# the live file still holds; a card with no exit status written (an older loop's) is said to have one.
t_cardgone() {
  local CARDS=$T/$CASE/cards out
  mkdir -p "$CARDS"
  out=$( eval "$(sed -n '/^cardstep() {/,/^}/p;/^cardgone() {/,/^}/p' "$SRC/lib/run.sh")"; cg() { cardgone "$1" "$(cardstep "$1")"; }
    stdb() { printf '%s\n' '{"card":"c-7","step":"review"}' '{"card":"c-7","step":"start","of":"fix"}' '{"card":"c-8","step":"land"}'; }
    echo '{"step":"fix","action":"reading a.txt"}' > "$CARDS/c-7.live"; echo 1 > "$CARDS/c-7.exit"; cg c-7
    echo '{"step":"build","action":"reading b.txt"}' > "$CARDS/c-7.live"; rm "$CARDS/c-7.exit"; cg c-7 )
  [ "$out" = "its process ended without a result in its fix step (last action: reading a.txt); it exited with status 1
its process ended without a result in its fix step; its exit status is not known" ] || fail "cardgone said: $out"
}

# Bugs: the loop takes up a card whose process still runs (a card of another process: a land-branch, or a loop's that
# outlived it), or misses a card whose worktree is gone too. #7's process runs: its lines, its worktree and a new
# file there are left as they are, and its issue is not picked. #8's process is gone and so is its worktree: it is
# blocked with nothing kept, and its issue is picked again and built from the start.
t_gonealive() {
  local alive ended s out c w=c20260101T000000-t-7
  setup "[$(issue 7 2026-01-01), $(issue 8 2026-01-02)]"; echo "$GO" > "$STUB/review.1"
  sleep 600 & alive=$!; sleep 0 & ended=$!; wait $ended # sleep: stand-ins for two cards' processes, one alive and one ended
  s=$(p_started $alive)
  gonecard $w 7 $alive "$s"; gonecard c20260101T000000-t-8 8 $ended "$s"
  git -C "$R" worktree add -q --detach "$T/$CASE/cards/$w" && echo mine > "$T/$CASE/cards/$w/u.txt" || fail "no worktree for #7"
  out=$(loop run 2>&1) || { kill $alive; fail "run exited non-zero: $out"; }
  kill $alive; wait $alive 2>/dev/null
  [ "$(st "select(.card == \"$w\") | .step" | tr '\n' ' ')" = "picked worktree start " ] && [ "$(cat "$T/$CASE/cards/$w/u.txt")" = mine ] \
    && [ -z "$(st "select(.issue == 7 and .card != \"$w\")")" ] && ! grep -qF "$w" <<<"$out" \
    || fail "the card whose process runs was touched or its issue picked: $(st 'select(.issue == 7)') $out"
  [ "$(jq -r 'select(.card == "c20260101T000000-t-8" and .step == "blocked") | [.reason, .kept] | @tsv' "$ST/retried.jsonl")" \
    = "its process was gone: the machine or the loop stopped"$'\t' ] || fail "#8 was not blocked with nothing kept and given back: $(st 'select(.issue == 8)')"
  c=$(st 'select(.issue == 8 and .step == "landed") | .card')
  [ -n "$c" ] && [ "$(st "select(.card == \"$c\" and .step == \"worktree\") | .reason")" = "" ] || fail "#8 was not built again from the start: $(st 'select(.issue == 8)') $out"
}

# wtchange <card>: a worktree for the card, with a change (a tracked edit, not staged): the work a block must keep.
wtchange() { git -C "$R" worktree add -q --detach "$T/$CASE/cards/$1" && echo two >> "$T/$CASE/cards/$1/a.txt" || fail "no worktree for $1"; }

# Bug (#466): a card whose process is gone, with no loop running to block it, was open for good: `retry` refused it
# ("still open") and nothing on the owner's side freed it. retry ends it as a block does, its change kept, then gives
# the issue back, and the next card of #7 is built from that kept work.
t_retrygone() {
  local ended out c=c20260101T000000-t-7 c2
  setup "[$(issue 7 2026-01-01)]"; echo "$GO" > "$STUB/review.1"; echo : > "$STUB/build"
  sleep 0 & ended=$!; wait $ended # sleep: a stand-in for the card's process, ended
  gonecard $c 7 $ended "$(date)" review; wtchange $c
  out=$(loop retry 7 2>&1) || fail "retry of #7, its card's process gone, exited non-zero: $out"
  grep -qF "card $c was open with its process gone; it is blocked, its work kept" <<<"$out" && grep -qF 'issue #7 can be picked again' <<<"$out" \
    || fail "retry did not say it ended the card and gave #7 back: $out"
  [ "$(jq -r --arg c "$c" 'select(.card == $c and .step == "blocked") | [.reason, .kept] | @tsv' "$ST/retried.jsonl")" = "its process was gone: the machine or the loop stopped"$'\t'"kept/$c" ] \
    && [ "$(git apply --numstat "$ST/kept/$c/$c.patch" | cut -f3)" = a.txt ] || fail "the card was not blocked with its work kept: $(cat "$ST/retried.jsonl" 2>&1)"
  out=$(loop run 1 2>&1) || fail "the run after the retry exited non-zero: $out"
  c2=$(st 'select(.issue == 7 and .step == "picked") | .card')
  [ -n "$c2" ] && [ "$(st 'select(.step == "worktree") | .reason')" = "resumed from the kept patch of card $c: one session, then review" ] \
    && [ "$(st 'select(.step == "landed") | .card')" = "$c2" ] || fail "#7 was not picked again from the kept work: $(st 'select(.issue == 7) | .step' | tr '\n' ' ') $out"
}

# Bug (#466): retry and shut refused a card alive with no process of its step, as one with a session running. Here
# three cards' processes run (stand-ins): #7 is in its build with a live record (its session runs), #8 is past its
# build line with no live record and nothing written for longer than stuck and reviewPause, and #9 too, its issue
# closed. retry 7 still refuses #7 and leaves it as it is; retry 8 ends #8 and everything under it, blocks it naming
# its review step, with its work kept, and gives #8 back; shut 9 ends #9 the same way and closes the card.
t_retrystuck() {
  local p7 p8 p9 out c7=c20260101T000000-t-7 c8=c20260101T000000-t-8 c9=c20260101T000000-t-9 why
  setup "[$(issue 7 2026-01-01), $(issue 8 2026-01-02)]"; tune '.tunables.stuck = 1 | .tunables.reviewPause = 0'
  sleep 600 & p7=$!; sleep 600 & p8=$!; sleep 600 & p9=$! # sleep: stand-ins for three cards' processes that run
  gonecard $c7 7 $p7 "$(p_started $p7)"; gonecard $c8 8 $p8 "$(p_started $p8)"; gonecard $c9 9 $p9 "$(p_started $p9)"
  jq -c 'if .step == "start" and (.card | endswith("-7") | not) then .step = "build" | del(.of) else . end' "$ST/cards.jsonl" > "$STUB/c.new" && mv "$STUB/c.new" "$ST/cards.jsonl"
  wtchange $c7; wtchange $c8; wtchange $c9; echo '{"step":"build","at":"2026-01-01T00:00:00Z","last":null,"turns":0}' > "$T/$CASE/cards/$c7.live"
  touch -t 202601010000 "$T/$CASE/cards/$c8" "$T/$CASE/cards/$c9"
  out=$(loop retry 7 2>&1) && fail "retry took #7, whose session runs: $out"
  grep -qF 'issue #7 has a card that is still open; nothing changed' <<<"$out" && kill -0 $p7 && [ "$(st "select(.card == \"$c7\") | .step" | tr '\n' ' ')" = "picked worktree start " ] \
    && [ -d "$T/$CASE/cards/$c7" ] || fail "retry touched #7, whose session runs: $out $(st "select(.card == \"$c7\")")"
  out=$(loop retry 8 2>&1) || fail "retry of #8 exited non-zero: $out"
  why="review: no process of this step ran for 1s (the pack's stuck and reviewPause), so the engine stopped the card"
  ! kill -0 $p8 2>/dev/null && [ "$(jq -r --arg c "$c8" 'select(.card == $c and .step == "blocked") | [.reason, .kept] | @tsv' "$ST/retried.jsonl")" = "$why"$'\t'"kept/$c8" ] \
    && grep -qF 'issue #8 can be picked again' <<<"$out" || fail "retry did not end #8, block it naming its step with its work kept, and give it back: $out $(cat "$ST/retried.jsonl" 2>&1)"
  out=$(loop shut 9 2>&1) || fail "shut of #9 exited non-zero: $out"
  ! kill -0 $p9 2>/dev/null && [ "$(st "select(.card == \"$c9\") | [.step, .reason] | @tsv" | tail -n 2)" = "blocked	$why"$'\n'"closed	the issue was closed by hand while the card was blocked" ] \
    && [ -s "$ST/kept/$c9/$c9.patch" ] || fail "shut did not end #9, block it with its work kept, and close it: $out $(st "select(.card == \"$c9\")")"
  kill $p7; wait $p7 $p8 $p9 2>/dev/null; return 0
}

# The same mid-batch: a card testing a batch holds the batch's changes in its worktree (batch(), rebatch()), its own
# only in <worktree>.bpatch. #7 is stopped running #8's change alone (its own change taken out, as a split does).
# Bug: its worktree is kept as it stands, #8's change saved as #7's work and #7's own lost with its .bpatch. Its own
# change, the new file too, is put back and kept, none of #8's, and #7 lands it.
t_gonebatch() {
  local ended out c=c20260101T000000-t-7 wt
  setup "[$(issue 7 2026-01-01)]"; echo "$GO" > "$STUB/review.1"; echo : > "$STUB/build"
  sleep 0 & ended=$!; wait $ended # sleep: a stand-in for the card's process, ended
  gonecard $c 7 $ended "$(date)" test
  wt=$T/$CASE/cards/$c
  git -C "$R" worktree add -q --detach "$wt" && echo two >> "$wt/a.txt" && echo new > "$wt/u.txt" && git -C "$wt" add -A \
    && git -C "$wt" diff --cached --binary --no-renames > "$wt.bpatch" && git -C "$wt" rev-parse HEAD > "$wt.lent" \
    && git -C "$wt" reset -q --hard && echo eight > "$wt/m.txt" && git -C "$wt" add -A || fail "no mid-batch worktree for #7"
  out=$(loop run 2>&1) || fail "the run exited non-zero: $out"
  grep -qF "card $c had an open record and its process was gone; it is blocked, its work kept, and issue #7 is given back" <<<"$out" \
    || fail "the run did not take up the card: $out"
  [ "$(git apply --numstat "$ST/kept/$c/$c.patch" | cut -f3 | sort | tr '\n' ' ')" = "a.txt u.txt " ] \
    || fail "the kept patch is not the card's own change: $(cat "$ST/kept/$c/$c.patch" 2>&1)"
  [ "$(st 'select(.step == "landed") | .issue')" = 7 ] && [ "$(git -C "$R" show main:a.txt | tr '\n' ' ')$(git -C "$R" show main:u.txt)" = "one two new" ] \
    && ! git -C "$R" cat-file -e main:m.txt 2>/dev/null || fail "#7 did not land its own change alone: $(st 'select(.issue == 7) | .step' | tr '\n' ' ') $(git -C "$R" show --stat main)"
}
