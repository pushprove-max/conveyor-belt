#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 300
# Engine cases: a serve loop that restarts on new code adopts the cards in flight. (A loop takes up the cards whose
# process is gone, the machine or the loop stopped under them: revive.test.sh.) Its cases call serveeng(), nojobs(),
# pushstub() and turn(), defined in serve.test.sh: the runner sources every area file.
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"
# The engine folder, as lib.sh sets it: named here too, so the release closure (tools/closure.sh) follows this file's paths.
SRC=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)

# Each case is on a main of its own: <issues json> on a pack pinned to $A, with $B installed too (coderepo,
# install.test.sh). The cases call the loop's own run() in a shell of their own (adoptrun), with no loop process to
# wait on: a restart's exec of the new loop runs the stub $STUB/adoptloop, which writes what it was handed to
# $STUB/new.*: its pid and arguments (args), CONVEYOR_ADOPT (adopt), CONVEYOR_KIDS (kids), and `held` (lock) when
# its fd 8 is the run file and the run lock is held (a new open of the file is refused it).
adoptsetup() {
  setup "$1"; mkdir -p "$T/$CASE/cards"; coderepo; kids=''; trap 'kill -KILL $kids 2>/dev/null; chmod -R u+w "$T/$CASE"' EXIT
  bash "$D/conveyor/conveyor.sh" install "$A" >/dev/null && bash "$D/conveyor/conveyor.sh" install "$B" >/dev/null || fail "the installs failed"
  tune --arg c "$A" '.plugin.commit = $c'; loop control cap 4 >/dev/null
  printf '%s\n' '#!/usr/bin/env bash' "printf '%s\n' \"\$\$ \$*\" > '$STUB/new.args'" \
    "printf '%s' \"\${CONVEYOR_ADOPT-unset}\" > '$STUB/new.adopt'; printf '%s' \"\${CONVEYOR_KIDS-unset}\" > '$STUB/new.kids'" \
    "[ /dev/fd/8 -ef '$ST/cards.jsonl.run' ] && ! flock -n '$ST/cards.jsonl.run' true && echo held > '$STUB/new.lock'" > "$STUB/adoptloop"
  chmod +x "$STUB/adoptloop"
}
# adoptrun <engine folder> <commands>: serveeng() of the commands, with no jobs beside the cards (nojobs) and the
# stub $STUB/adoptloop in place of the new loop a restart execs (run()'s exec "$BASH" <new conveyor.sh> serve).
adoptrun() { serveeng "$1" "nojobs; BASH=\$STUB/adoptloop; $2"; }
# $firstwait, in adoptrun(): the loop is ended with a KILL at the wait that ends its first turn with no pick (a turn
# that picks goes on to the next at once), and each card it starts is a stand-in that writes "<card> <issue> <its pid>" to
# $STUB/cardruns and runs until the case kills it (its pid in kids): a card that ended at once would be blocked as
# gone at the next turn.
firstwait='me=$BASHPID; cardrun() { echo "$1 $2 $BASHPID" >> "$STUB/cardruns"; standin; }; sleep() { [ "${FUNCNAME[1]:-}" != run ] || [ "$1" = 0.1 ] || { kill -KILL "$me"; exit 0; }; command sleep "$@"; }' # sleep: the engine's own, passed on as called
# A stand-in process for a card, its review or a push, that runs until the case kills it: called with &, or as the
# last command of a job, it keeps the job's own pid, so killing that pid ends it.
standin() { exec sleep 120; } # sleep: a stand-in that runs until it is killed
# adoptrec <card> <issue> <step> [extra json]: one line of the card records, as record() writes it.
adoptrec() {
  jq -cn --arg c "$1" --argjson i "$2" --arg s "$3" --argjson x "${4:-{\}}" \
    '{card:$c,issue:$i,step:$s,time:(now | todate),tokens:{claude:0,codex:0},result:"ok",sha:"",reason:""} * $x' >> "$ST/cards.jsonl"
}
# adoptcard <card> <issue> <pid> <step>: a card in flight in its <step>, its process <pid>.
adoptcard() {
  adoptrec "$1" "$2" picked; adoptrec "$1" "$2" worktree "$(jq -cn --argjson p "$3" --arg t "$(p_started "$3")" '{pid: $p, started: $t}')"
  adoptrec "$1" "$2" start "{\"of\": \"$4\"}"
}

# Bugs: new code lands with cards in review and the loop waits for them before it restarts, so free slots sit idle;
# the restarted loop forgets those cards (does not count them, drops their claims, never pushes their landings), or
# starts them again on the new code in place of their own processes (they switch at their next step: t_switchcode); it
# restarts beside a push still running and starts a second one, or waits for the push of a card that landed during
# that push; a forged adoption takes the run lock beside a running loop.
t_adopt() {
  local out p7 p8 c9 rc me args turns
  adoptsetup "[$(issue 9 2026-01-04), $(issue 10 2026-01-05)]"
  # #7 and #8 in flight, adopted from the loop before: #7 past its claim on f7.txt, #8 in review. #6 has landed, its
  # push not made. The pin moves to $B.
  standin & p7=$!; standin & p8=$!; kids="$p7 $p8"
  adoptcard c-7 7 "$p7" land; adoptcard c-8 8 "$p8" review
  jq -cn --argjson p "$p7" '{pid: $p, paths: ["f7.txt"], held: true}' > "$T/$CASE/cards/c-7.claim"
  echo 6 > "$R/f6.txt"; git -C "$R" add f6.txt && git -C "$R" commit -qm 6 || fail "#6 did not land"
  adoptrec c-6 6 picked; adoptrec c-6 6 landed "$(jq -cn --arg s "$(git -C "$R" rev-parse HEAD)" '{sha: $s, product: false}')"
  # The loop on $A, at cap 2 (its two cards fill it, so it picks nothing): its first turn starts #6's push (a stand-in
  # that runs until it is killed) and the pin moves to $B as that turn ends; its second turn, with the push still
  # running, does not restart, and #5 lands as it ends (the owed push is now #5's, never tried); that turn's end ends
  # the push, and the third turn restarts: at once, with both cards still running, and with no push of #5 and no
  # second push of #6. The new loop on $B, in the same process with the run
  # lock, is handed both cards and the commit each runs.
  loop control cap 2 >/dev/null || fail "cap 2 was refused"
  # The wait that ends a turn is a job of the loop's (sleep "$t" &), so the turns are counted in a file.
  turns='sleep() { [ "${FUNCNAME[1]:-}" = run ] && [ "$1" != 0.1 ] || { command sleep "$@"; return; }; echo >> "$STUB/turns"; case $(wc -l < "$STUB/turns") in 1) tune --arg c "$B" ".plugin.commit = \$c" ;; 2) echo "pusher ${pusher:-none}" > "$STUB/turn2"; echo 5 > "$R/f5.txt"; git -C "$R" add f5.txt && git -C "$R" commit -qm 5 && adoptrec c-5 5 picked && adoptrec c-5 5 landed "{\"sha\": \"$(git -C "$R" rev-parse HEAD)\", \"product\": false}"; kill -KILL "$pusher" ;; *) kill -KILL "$me" ;; esac; }' # sleep: the engine's own, passed on as called
  out=$(CONVEYOR_ADOPT="$p7 c-7 7 $A"$'\n'"$p8 c-8 8 $A" adoptrun "$V/$A/conveyor" 'me=$BASHPID; echo $me > "$STUB/me"; push() { echo "$*" >> "$STUB/pushcalls"; standin; }; '"$turns"'; run "" serve' 8>>"$ST/cards.jsonl.run" 2>&1)
  # Its line also says what ends the cards all the same (#1332: a restart of the machine's service ended them, under
  # a line that said they carry on).
  grep -qxF "conveyor: restarting on the new code; 2 cards in flight carry on on $A; a stop of this loop or of the machine's Conveyor, or a restart of its service, ends them" <<<"$out" \
    || fail "the loop did not restart with its 2 cards once the push ended, or did not say so and what ends them: $out"
  [[ "$(cat "$STUB/turn2" 2>&1)" =~ ^pusher\ [0-9]+$ ]] || fail "the loop restarted while #6's push ran, or started no push: $(cat "$STUB/turn2" 2>&1) $out"
  read -r me args < "$STUB/new.args"; [ "$me" = "$(cat "$STUB/me")" ] && [ "$args" = "$V/$B/conveyor/conveyor.sh serve" ] && [ "$(cat "$STUB/new.lock" 2>&1)" = held ] \
    || fail "the loop did not restart on $B in its own process, holding the run lock: $(cat "$STUB/new.args" "$STUB/new.lock" 2>&1)"
  [ "$(sort "$STUB/new.adopt")" = "$(printf '%s\n' "$p7 c-7 7 $A" "$p8 c-8 8 $A" | sort)" ] || fail "the new loop was not handed both cards on $A: $(cat "$STUB/new.adopt")"
  kill -0 "$p7" && kill -0 "$p8" && [ "$(cut -d' ' -f1,2 "$STUB/pushcalls" 2>&1)" = 'c-6 6' ] && [ -z "$(st 'select(.step | IN("push", "pushed"))')" ] \
    || fail "the restart ended its cards, or waited for #5's push or pushed again: $(cat "$STUB/pushcalls" 2>&1)"
  # The new loop, cap 3, given the restart's list: the adopted cards count against the cap, so it picks #9 into the
  # one free slot and leaves #10 queued. The owed push, #5's (#6's commit is under it), is a stub's that does nothing
  # (the push decision: below).
  loop control cap 3 >/dev/null || fail "cap 3 was refused"
  CONVEYOR_ADOPT=$(cat "$STUB/new.adopt") adoptrun "$V/$B/conveyor" "$firstwait; push() { :; }; run '' serve" 8>>"$ST/cards.jsonl.run" > "$STUB/run.out" 2>&1; rc=$?
  kids+=" $(awk '{ print $3 }' "$STUB/cardruns" 2>/dev/null)"
  [ "$rc" = 137 ] && [ "$(st 'select(.step == "picked" and .issue >= 9) | .issue' | paste -sd' ')" = 9 ] && [ "$(awk '{ print $2 }' "$STUB/cardruns")" = 9 ] \
    || fail "the new loop did not pick #9 alone beside the adopted #7 and #8 at cap 3 ($rc): $(st 'select(.step == "picked") | .issue' | paste -sd' ') $(cat "$STUB/run.out")"
  # The adopted #7 keeps its claim: #9, which changes f7.txt too, waits on it.
  c9=$(st 'select(.issue == 9 and .step == "picked") | .card')
  git -C "$R" worktree add -q --detach "$T/$CASE/cards/$c9" && echo two >> "$T/$CASE/cards/$c9/f7.txt" && git -C "$T/$CASE/cards/$c9" add f7.txt || fail "no worktree for #9"
  out=$(serveeng "$SRC" "locked claim '$c9' \"\$CARDS/$c9\" $$" 2>&1)
  [ "$out" = '{"on":"c-7","paths":["f7.txt"]}' ] || fail "#9 does not wait on the adopted #7's claim on f7.txt: $out"
  # A forged adoption beside a running loop (one holds the run lock, fd 9 here): refused, with fd 8 on another file,
  # and with fd 8 opened anew on the run file (the variable alone never passes the lock).
  # The lock checks need the run lock free, and the new loop's card #9 (a stand-in that is no child of this shell, so
  # wait cannot wait on it) holds it on its fd 8 until the kernel closes that fd as it dies: a direct check cannot
  # make that happen sooner, so the case polls the lock.
  kill -KILL $kids 2>/dev/null; wait "$p7" "$p8" 2>/dev/null; wait_until "flock -n '$ST/cards.jsonl.run' true" || fail "a stand-in of the new loop's card still holds the run lock"
  out=$( { flock -n 9 || exit 9; CONVEYOR_ADOPT=' ' serveeng "$SRC" run 8>>"$STUB/other.run" 9>&- 2>&1; } 9>>"$ST/cards.jsonl.run"); rc=$?
  [ "$rc" = 1 ] && grep -q 'already running' <<<"$out" || fail "an adoption with fd 8 on another file was not refused ($rc): $out"
  out=$( { flock -n 9 || exit 9; CONVEYOR_ADOPT=' ' serveeng "$SRC" run 8>>"$ST/cards.jsonl.run" 9>&- 2>&1; } 9>>"$ST/cards.jsonl.run"); rc=$?
  [ "$rc" = 1 ] && grep -q 'already running' <<<"$out" || fail "an adoption with fd 8 opened anew on the run file was not refused ($rc): $out"
  # One push at a time: none starts while a push runs (pusher, its record in $PUSHING) or once the restart is due
  # (new); the new loop's first push decision makes the owed one, #5's (#6's commit is under it).
  # R109 of #1389: the push job killed, its record stays for health to show it stale (it was deleted, so a killed push
  # was not shown at all).
  out=$(serveeng "$SRC" 'pushstub; standin & pusher=$!; pproc=$pusher pushing "$(git rev-parse HEAD)" push; pushturn; echo T >> "$STUB/pushcalls"
    k=$pusher; kill "$pusher"; wait "$pusher"; pushended; [ -z "$pusher" ] || echo "the ended push is still named"
    [ "$(loop health | jq -c "[.pushing.pid, .pushing.stale]")" = "[$k,true]" ] || echo "health does not show the killed push stale: $(loop health | jq -c .pushing)"
    new=$STUB/adoptloop; pushturn; echo T >> "$STUB/pushcalls"; new=""; turn' 2>&1)
  [ -z "$out" ] && [ "$(cut -d' ' -f1,2 "$STUB/pushcalls" | paste -sd,)" = 'T,T,c-5 5' ] \
    || fail "a push started beside another or with the restart due, or the new loop did not push #5: $out $(cat "$STUB/pushcalls")"
}

# Bugs: a second restart says the cards it adopts again run the code of the loop before it; a card killed while
# adopted stays open for good and `retry` refuses it, or its review goes on in a worktree taken away (also when it is
# killed at a restart), or a process under it that ignores TERM holds the loop for good, or one it starts on TERM
# before it ends outlives it unseen.
t_adoptkill() {
  local out k p8 p9 deaf
  adoptsetup '[]'
  # A review that ignores TERM, and on TERM starts another that ignores it too (its pid in $STUB/spawned), then ends.
  # That it does is checked here, so a spawned file that is missing later means no TERM came. What is under test is
  # which signals the loop sends to a real process tree and what those processes then do, which no function call
  # shows: so these are real processes, and the case polls for each one's mark file, as each starts in its own time.
  cat > "$STUB/deaf.sh" <<'EOF2'
deaf() { trap '' TERM; echo "$BASHPID" > "$STUB/spawned"; while :; do sleep 1; done; } # sleep: a stand-in that goes on until it is killed
trap 'deaf & exit' TERM; : > "$STUB/deafup"
while :; do sleep 1; done # sleep: a stand-in that goes on until TERM
EOF2
  bash "$STUB/deaf.sh" & k=$!; until [ -e "$STUB/deafup" ] || ! kill -0 $k 2>/dev/null; do sleep 0.1; done; kill -TERM $k
  wait $k; until [ -s "$STUB/spawned" ]; do sleep 0.1; done # the one it started on TERM writes its pid as it starts
  [ -s "$STUB/spawned" ] && kill -0 "$(cat "$STUB/spawned")" 2>/dev/null || fail "the process that ignores TERM did not start another on TERM"
  kill -KILL "$(cat "$STUB/spawned")"; rm "$STUB/spawned" "$STUB/deafup"
  # #8 in review, that review under it, started on $A; #9 started on $B. The loop on $B restarts on $A, the pin's move back.
  bash -c 'bash "$1" & wait' bash "$STUB/deaf.sh" & p8=$!; standin & p9=$!; kids="$p8 $p9"
  # The poll: the review must have set its TERM trap before the loop looks at it (a real process: above).
  until [ -e "$STUB/deafup" ] || ! kill -0 $p8 2>/dev/null; do sleep 0.1; done; deaf=$(pgrep -P "$p8"); kids+=" $deaf"
  [ -n "$deaf" ] || fail "#8 runs no review to outlive it"
  adoptcard c-8 8 "$p8" review; adoptcard c-9 9 "$p9" build; tune --arg c "$A" '.plugin.commit = $c'
  out=$(CONVEYOR_ADOPT="$p8 c-8 8 $A"$'\n'"$p9 c-9 9 $B" adoptrun "$V/$B/conveyor" 'run "" serve' 8>>"$ST/cards.jsonl.run" 2>&1)
  grep -qxF "conveyor: restarting on the new code; 2 cards in flight carry on on $(printf '%s\n' "$A" "$B" | sort | paste -sd' ' - | sed 's/ /, /g'); a stop of this loop or of the machine's Conveyor, or a restart of its service, ends them" <<<"$out" \
    || fail "the second restart did not say #8 runs $A and #9 runs $B: $out"
  [ "$(sort "$STUB/new.adopt")" = "$(printf '%s\n' "$p8 c-8 8 $A" "$p9 c-9 9 $B" | sort)" ] && grep -q "^$p8 $deaf " "$STUB/new.kids" \
    || fail "the new loop was not handed each card's own commit, or #8's review: $(cat "$STUB/new.adopt" "$STUB/new.kids")"
  # #8's process is killed (exit 137, as cardrun() writes it) with its review still running. The new loop, given the
  # restart's lists, ends the review with a KILL alone, blocks the card with the reason, and `retry` takes it. #9 is
  # left out of its list: it runs on, and a `run` ends only once no card of its own runs.
  kill -KILL "$p8"; wait "$p8" 2>/dev/null; echo 137 > "$T/$CASE/cards/c-8.exit"
  out=$(CONVEYOR_ADOPT=$(grep "^$p8 " "$STUB/new.adopt") CONVEYOR_KIDS=$(cat "$STUB/new.kids") adoptrun "$SRC" run 8>>"$ST/cards.jsonl.run" 2>&1) \
    || fail "the run that adopted the killed #8 failed: $out"
  [[ "$(st 'select(.card == "c-8" and .step == "blocked") | .reason')" =~ ^"its process ended without a result in its review step".*"; signal KILL killed it (exit status 137)"$ ]] \
    || fail "a card killed while adopted was not blocked with the reason: $(st 'select(.card == "c-8") | .step' | paste -sd' ') $out"
  # The loop stops then kills, so it sends no TERM: had it sent one, the review that ignores TERM would have started
  # another (checked above), which would have written $STUB/spawned and could outlive the card unseen.
  [ ! -e "$STUB/spawned" ] || fail "the loop sent TERM to #8's review, and it started another: $(ps -o pid=,args= -p "$(cat "$STUB/spawned")")"
  ! kill -0 "$deaf" 2>/dev/null || fail "the review of the killed #8 runs on after its worktree went: $(ps -o pid=,args= -p "$deaf")"
  [ -z "$(st 'select(.card == "c-9" and .step == "blocked")')" ] || fail "#9, still running, was blocked"
  loop retry 8 >/dev/null || fail "retry refused the card killed while adopted"
}

# Bugs: a restart with no card in flight is not what it was: on the pin, in the same process, holding the lock;
# a second serve runs beside the restarted loop; after the restart, a ready issue with a free slot waits more than one
# turn to be picked.
t_adoptidle() {
  local out rc me args
  adoptsetup "[$(issue 11 2026-01-06)]"; tune --arg c "$B" '.plugin.commit = $c'
  out=$(adoptrun "$V/$A/conveyor" 'echo $BASHPID > "$STUB/me"; run "" serve' 2>&1)
  grep -qxF "conveyor: restarting on the new code; 0 cards in flight carry on on $A" <<<"$out" || fail "the idle loop did not restart: $out"
  read -r me args < "$STUB/new.args"; [ "$me" = "$(cat "$STUB/me")" ] && [ "$args" = "$V/$B/conveyor/conveyor.sh serve" ] && [ "$(cat "$STUB/new.lock" 2>&1)" = held ] && [ ! -s "$STUB/new.adopt" ] \
    && [ -z "$(st 'select(.step == "picked")')" ] || fail "the idle restart is not on $B in its own process, holding the lock, with no card: $(cat "$STUB/new.args" "$STUB/new.lock" "$STUB/new.adopt" 2>&1)"
  # A serve beside the restarted loop (it holds the run lock, fd 9 here) is refused.
  out=$( { flock -n 9 || exit 9; adoptrun "$V/$B/conveyor" 'run "" serve' 9>&- 2>&1; } 9>>"$ST/cards.jsonl.run"); rc=$?
  [ "$rc" = 1 ] && grep -q 'already running' <<<"$out" || fail "a second serve ran beside the loop restarted idle ($rc): $out"
  # The new loop, as the restart hands it on: its first turn picks #11.
  CONVEYOR_ADOPT=$(cat "$STUB/new.adopt") adoptrun "$V/$B/conveyor" "$firstwait; run '' serve" 8>>"$ST/cards.jsonl.run" > "$STUB/run.out" 2>&1; rc=$?
  kids=$(awk '{ print $3 }' "$STUB/cardruns" 2>/dev/null)
  [ "$rc" = 137 ] && [ "$(st 'select(.step == "picked") | .issue')" = 11 ] && [ "$(awk '{ print $2 }' "$STUB/cardruns")" = 11 ] \
    || fail "the loop restarted with no card in flight did not pick #11 in its first turn ($rc): $(cat "$STUB/run.out")"
}

# switchtry <sed script>: card c-5 of issue 5 run by the engine's own card() in a shell that loaded this engine as
# `serve` does (serveeng, serve.test.sh), on commit old1 (this engine folder, as an install's own). Its test step (the
# stub $STUB/test-cmd) writes loop.json as it passes, saying the loop runs commit new2: installed as a copy of this
# engine, its lib/card.sh changed by <sed script> and given a function newmark() of its own, its card rules
# (rules/card-core.md) ending with a line of their own. So the card meets the new commit as its land step begins
# (switchcode(), lib/card.sh, from began()). new2's redbrief(), the first function the land step calls after began(),
# saves what the card has then: the card records ($STUB/cards.land), its settings file ($STUB/settings) and its
# prompt as a session would be given it (card()'s sprompt, through newtexts(), lib/session.sh: $STUB/prompt). Then
# whether newmark() was loaded and the commit the shell runs (ran). Sets the caller's out to what that shell printed.
switchtry() {
  local new
  setup "[$(issue 5 2026-01-01)]"; export XDG_DATA_HOME=$T/$CASE/data; V=$XDG_DATA_HOME/conveyor/versions; new=$V/new2/conveyor
  echo "$GO" > "$STUB/review.1"
  printf '%s\n' 'echo x >> "$STUB/tests"; cp "$STUB/says" "$(cat "$STUB/sayspath")"' > "$STUB/test-cmd"
  printf '%s\n' 'cp "$STATE" "$STUB/cards.land"; cp "$CARDS/$1.settings" "$STUB/settings"; newtexts sprompt; printf "%s\n" "$sprompt" > "$STUB/prompt"' > "$STUB/landsave"
  mkdir -p "$new" && cp -a "$SRC/." "$new/" && sed -i -e "$1" -e "/^redbrief() {/r $STUB/landsave" "$new/lib/card.sh" && echo 'newmark() { :; }' >> "$new/lib/card.sh" \
    && echo 'A rule of commit new2.' >> "$new/rules/card-core.md" || fail "no copy of the engine to switch to"
  adoptrec c-5 5 picked
  out=$(serveeng "$SRC" "OWN=1 RAN=old1; jq -n --argjson p \$\$ --arg d '$new' '{pid: \$p, commit: \"new2\", checkout: \$d}' > \"\$STUB/says\" && echo \"\$SAYS\" > \"\$STUB/sayspath\" || exit 1
    cd \"\$R\" && card c-5 5; declare -F newmark >/dev/null || echo 'none of the new code loaded'; echo \"ran \$RAN\"" 2>&1)
}

# Bugs (#449): a card in its land step when Conveyor takes a new commit lands on the code it started with (on
# 2026-11-18 a fix to how cards test missed the three cards running when it landed), or its passed test step runs
# again after the switch, or its log does not say it switched; its next session runs the old install's hooks
# (its settings file) or the old rules (its prompt, a copy made before the switch too); prune() removes the install it
# switched to while it runs; a later restart says, and hands on, the commit it started on in place of the one it runs.
t_switchcode() {
  local out t; switchtry ''
  grep -qxF "conveyor: card c-5: Conveyor took commit new2; the card goes on with the new code from its land step, and no passed step runs again" <<<"$out" \
    || fail "c-5 did not say it switched at its land step: $out"
  ! grep -qx 'none of the new code loaded' <<<"$out" && grep -qx 'ran new2' <<<"$out" || fail "c-5's land step did not run new2's code: $out"
  # Its steps: the test step ran once, and the land step, the one start line that names new2, went on to the landing.
  [ "$(st 'select(.step == "start") | "\(.of) \(.engine // "")"' | paste -sd,)" = 'build ,review ,test ,land new2' ] && [ "$(wc -l < "$STUB/tests")" = 1 ] \
    && [ "$(st '.step' | tail -n 1)" = landed ] || fail "c-5's steps after the switch: $(st '"\(.step) \(.of // "") \(.engine // "")"' | paste -sd,) ($(wc -l < "$STUB/tests") test runs)"
  grep -qF "$V/new2" "$STUB/settings" && ! grep -qF "${SRC%/*}" "$STUB/settings" \
    || fail "c-5's settings after the switch do not run new2's hooks: $(cat "$STUB/settings" 2>&1)"
  grep -qxF 'A rule of commit new2.' "$STUB/prompt" && [ "$(grep -c '^# Rules$' "$STUB/prompt")" = 1 ] || fail "c-5's prompt after the switch does not carry new2's rules alone: $(cat "$STUB/prompt" 2>&1)"
  # The lines of c-5 up to its land step, as prune() reads a card in flight (inflight(), lib/install.sh).
  ( . "$SRC/lib/install.sh" && inflight "$STUB/cards.land" ) | grep -qxF new2 || fail "prune() would remove new2's install while c-5 runs on it: $(cat "$STUB/cards.land")"
  # The commit a loop that restarts names for c-5 and hands its next loop (cardcode(), lib/run.sh), the store read as
  # its lines: not old1, which c-5 left.
  t=$(stdb() { cat "$STUB/cards.land"; }; eval "$(sed -n '/^cardcode() {/,/^}/p' "$SRC/lib/run.sh")"; cardcode c-5 old1)
  [ "$t" = new2 ] || fail "a restart would say c-5 runs $t, not new2"
}

# Bug (#449): a card switches to new code that reads another form of step files than its old code saved, or does not
# say why it stays on its old code.
t_switchkeep() {
  local out; switchtry "s/^STEPFILES=.*/STEPFILES=2/"
  grep -qxF "conveyor: card c-5: Conveyor took commit new2; the card goes on with its old code, commit old1: the new code cannot read the step files that the old code saved (form 1; the new code reads form 2)" <<<"$out" \
    || fail "c-5 did not say why it kept its old code: $out"
  grep -qx 'none of the new code loaded' <<<"$out" || fail "c-5 loaded new2's code: $out"
}

# Bug (#449 review): a card switches while it runs in a function the new code changes, so the rest of that function
# runs its old body beside the new code's other functions (a fix inside card() never reaches it); or its log does not
# say why it stays on its old code.
t_switchbusy() {
  local out; switchtry '/^card() {/a :'
  grep -qxF "conveyor: card c-5: Conveyor took commit new2; the card goes on with its old code, commit old1: the new code changes card(), which the card is running in" <<<"$out" \
    || fail "c-5 did not say why it kept its old code: $out"
  grep -qx 'none of the new code loaded' <<<"$out" || fail "c-5 loaded new2's code: $out"
}

# Bug: the loop that a restart starts adopts a card that has landed and not pushed yet; the card's process ends while
# the last line of the card records is still being written (a long line reaches the file in more than one write),
# the whole read of the records fails, and the loop writes `blocked` ("its process ended without a result") for the
# landed card, which then stays in Needs you after its push goes out.
t_landedrestart() {
  local out l dead sha
  setup '[]'; mkdir -p "$ST" "$T/$CASE/cards"
  echo x > "$R/n.txt"; git -C "$R" add -A; git -C "$R" commit -qm next; sha=$(git -C "$R" rev-parse HEAD)
  adoptrec c1-14 14 picked; adoptrec c1-14 14 landed "{\"sha\":\"$sha\",\"product\":false}"
  # Another card's line, half written.
  l=$(jq -cn '{card:"c2-15",issue:15,step:"picked",time:(now | todate),tokens:{claude:0,codex:0},result:"ok",sha:"",reason:""}'); printf '%s' "${l:0:40}" >> "$ST/cards.jsonl"
  # The landed card's process, adopted from the loop before the restart, has ended.
  sleep 0 & dead=$!; wait $dead # sleep: a stand-in for a card's process that has ended
  # Its exit file: only the loop's look at a card of its own that has ended takes it away, so a run that skipped the
  # adoption (and so had no adopted card to look at) leaves it, and the case fails.
  echo 0 > "$T/$CASE/cards/c1-14.exit"
  # One `run` given the adopted card (CONVEYOR_ADOPT, with the run lock on fd 8), with the push rule off: no line of
  # its own is written after the half-written one. Its first turn sees to the adopted card, and it ends.
  pushrule() { jq --argjson p "$1" '.rules.push = $p' "$ST/control.json" > "$STUB/c.new" && mv "$STUB/c.new" "$ST/control.json"; } # <true | false>
  pushrule false
  out=$(CONVEYOR_ADOPT="$dead c1-14 14 $(git -C "$SRC" rev-parse HEAD)" serveeng "$SRC" 'nojobs; run' 8>>"$ST/cards.jsonl.run" 2>&1) || fail "the run that adopted the landed card failed: $out"
  [ ! -e "$T/$CASE/cards/c1-14.exit" ] || fail "the run did not look at the adopted card: its exit file is still there: $out"
  ! grep -q '"step":"blocked"' "$ST/cards.jsonl" || fail "the loop blocked the adopted card that had landed: $out"
  # Once the line is whole, the landed card's push is the next loop's first push decision, as for any landing.
  printf '%s\n' "${l:40}" >> "$ST/cards.jsonl"; pushrule true
  out=$(serveeng "$SRC" 'pushstub; turn' 2>&1)
  [ -z "$out" ] && [ "$(cut -d' ' -f1,2 "$STUB/pushcalls")" = 'c1-14 14' ] && [ -z "$(st 'select(.step == "blocked")')" ] && loop check \
    || fail "the landed card's push was not made, or it was blocked: $(cat "$STUB/pushcalls") $out"
}
