#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 300
# Engine cases: a serve loop that restarts on new code adopts the cards in flight. (A loop takes up the cards whose
# process is gone, the machine or the loop stopped under them: revive.test.sh.)
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"
# The engine folder, as lib.sh sets it: named here too, so the release closure (tools/closure.sh) follows this file's paths.
SRC=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)

# Each case is on a main of its own: <issues json> on a pack pinned to $A, with $B installed too (coderepo,
# install.test.sh); adoptserve starts the loop on $A once the case's stubs are in place. The loop's live records are
# brought up to date once a second, as a pack's are by default (lib.sh's setup has five times a second): no case here
# reads them, and beside steps held for many seconds those updates were about a third of t_adopt's CPU.
adoptsetup() {
  setup "$1"; S=$ST; O=$T/$CASE/origin; for i in $(seq 10); do echo "$GO" > "$STUB/review.$i"; done
  coderepo; trap 'kill $pid 2>/dev/null; chmod -R u+w "$T/$CASE"' EXIT
  bash "$D/conveyor/conveyor.sh" install "$A" >/dev/null && bash "$D/conveyor/conveyor.sh" install "$B" >/dev/null || fail "the installs failed"
  tune --arg c "$A" '.plugin.commit = $c'; tune '.tunables += {idle: 1, poll: 1, pushRetry: 600, live: 1}'; loop control cap 4 >/dev/null
  add() { jq -c ". + [$(issue "$1" "$2")]" "$STUB/issues.json" > "$STUB/i.new" && mv "$STUB/i.new" "$STUB/issues.json"; } # <issue> <date>
  watchturns # here, not in adoptserve, so a case can add to the loop's sleep before the loop starts
}
adoptserve() {
  ( export CONVEYOR_MAIN=$R CONVEYOR_CARDS=$T/$CASE/cards
    exec bash "$V/$A/conveyor/conveyor.sh" serve > "$STUB/serve.out" 2>&1 ) & pid=$!
  till() { until eval "$1"; do kill -0 $pid 2>/dev/null || return 1; sleep 0.25; done; } # <condition>: until it holds; 1 if the loop ($pid) ended first
  cpid() { st "select(.issue == $1 and .step == \"worktree\") | .pid" | tail -n 1; }; card() { st "select(.issue == $1 and .step == \"picked\") | .card" | tail -n 1; }
  ends() { st "select(.issue == $1 and (.step | IN(\"landed\", \"closed\", \"blocked\"))) | .step" | tail -n 1; }
}

# Bugs: new code lands with cards in review and the loop waits for them before it restarts, so free slots sit idle;
# the restarted loop forgets those cards (does not count them, drops their claims, never pushes their landings), or
# starts them again on the new code in place of their own processes (they switch at their next step: t_switchcode); it restarts beside a push still running and starts a second one, or waits for the push
# of a card that landed during that push; a forged adoption takes the run lock beside a running loop.
t_adopt() {
  adoptsetup "[$(issue 5 2025-12-31), $(issue 6 2026-01-01), $(issue 7 2026-01-02), $(issue 8 2026-01-03)]"
  linkset '{"a.txt": ["a.test.sh"], "f7.txt": ["a.test.sh"]}' # #7's test step runs the stub, held below
  # Each card changes a file of its own, but #9 changes #7's. The reviews of #5, #8 and #9, and the tests of #7 (past its
  # claim on f7.txt, at its landing step), are held until $STUB/go.<issue>.
  echo 'n=${PWD##*-}; [ "$n" != 9 ] || n=7; echo two >> "f$n.txt"' > "$STUB/build"
  echo 'n=${PWD##*-}; case $n in 5|8|9): > "$STUB/reviewing.$n"; while [ -d "$STUB" ]; do [ -e "$STUB/go.$n" ] && break; sleep 0.5; done ;; esac' > "$STUB/review-cmd"
  echo 'case $PWD in *-7) : > "$STUB/testing.7"; while [ -d "$STUB" ]; do [ -e "$STUB/go.7" ] && break; sleep 0.5; done ;; esac' >> "$STUB/test-cmd"
  # The first push is held until $STUB/pushgo, the second until $STUB/pushgo2; every push says when it starts and ends.
  cat > "$R/.git/hooks/pre-push" <<'EOF2'
#!/usr/bin/env bash
read -r ref sha rest; echo "start $sha" >> "$STUB/pushlog"
g=$(grep -c ^start "$STUB/pushlog"); g=$([ "$g" = 1 ] && echo pushgo || echo pushgo$g)
[ "$g" = pushgo ] || [ "$g" = pushgo2 ] && while [ -d "$STUB" ]; do [ -e "$STUB/$g" ] && break; sleep 0.5; done
echo "end $sha" >> "$STUB/pushlog"
EOF2
  chmod +x "$R/.git/hooks/pre-push"
  # At the first landing, main's pre-commit hook (a descendant of the loop) forges an adoption, its own pid written in
  # loop.json as the loop's: it must be refused, not start a second loop beside the running one.
  printf '%s\n' '#!/usr/bin/env bash' '[ -e "$STUB/forged" ] && exit 0' \
    "s=\$(bash '$SRC/conveyor.sh' state-dir) && cp \"\$s/loop.json\" \"\$STUB/loop.json\" || exit 1" \
    "out=\$(env -u GIT_INDEX_FILE timeout 5 bash -c 'printf \"{\\\"pid\\\":%s}\\n\" \$\$ > \"\$1/loop.json\"; CONVEYOR_ADOPT=\" \" exec bash \"\$2\" serve' bash \"\$s\" '$SRC/conveyor.sh' 2>&1 < /dev/null)" \
    "echo \"exit \$? \$out\" > \"\$STUB/forged\"; mv \"\$STUB/loop.json\" \"\$s/loop.json\"" \
    > "$R/.git/hooks/pre-commit"; chmod +x "$R/.git/hooks/pre-commit"
  adoptserve
  till '[ -e "$STUB/reviewing.5" ] && [ -e "$STUB/testing.7" ] && [ -e "$STUB/reviewing.8" ] && grep -q ^start "$STUB/pushlog" 2>/dev/null' \
    || fail "#6 did not land and push, or #5 and #8 did not reach review, or #7 its tests: $(cat "$STUB/serve.out")"
  grep -q '^exit 1 .*already running' "$STUB/forged" || fail "a hook under the loop forged an adoption and was not refused: $(cat "$STUB/forged" 2>&1)"
  # New code lands during the push, and #9 and #10 are queued: nothing restarts or is picked while the push runs.
  tune --arg c "$B" '.plugin.commit = $c'; add 9 2026-01-04; add 10 2026-01-05
  till 'grep -q "pins another Conveyor commit than this loop.s $A" "$STUB/serve.out"' || fail "the loop did not see the new pin: $(cat "$STUB/serve.out")"
  turns 2 # a whole turn of the loop after it saw the pin
  ! grep -q restarting "$STUB/serve.out" && [ -z "$(st 'select(.issue == 9)')" ] || fail "the loop restarted or picked during its push: $(cat "$STUB/serve.out")"
  # #5 lands while the push runs. The push ends: the loop restarts at once, without a push for #5 (that one is held,
  # and the new loop makes it), with #7 still in its tests and #8 in review, and picks #9 into the one free slot of cap 3; #10
  # stays queued, as the adopted cards count against the cap. #9's review is held meanwhile: past it, #9 waits on #7
  # (below), and a card that only waits leaves its slot free (idle()), so #10 would then be picked by right.
  : > "$STUB/go.5"; till '[ "$(ends 5)" = landed ]' || fail "#5 did not land during the push: $(cat "$STUB/serve.out")"
  loop control cap 3 >/dev/null; : > "$STUB/pushgo"
  till 'grep -q restarting "$STUB/serve.out"' || fail "the loop waited for a push of #5 before it restarted: $(cat "$STUB/pushlog" "$STUB/serve.out")"
  : > "$STUB/pushgo2"
  till '[ -n "$(card 9)" ] && [ -e "$STUB/reviewing.9" ]' || fail "the restarted loop did not pick #9 into the free slot: $(cat "$STUB/serve.out")"
  turns 2; [ -z "$(card 10)" ] || fail "the restarted loop picked #10 past cap 3 beside the adopted #7 and #8: $(cat "$STUB/serve.out")"
  # That said, #10 leaves the queue: building and landing it would prove nothing more.
  jq -c 'map(select(.number != 10))' "$STUB/issues.json" > "$STUB/i.new" && mv "$STUB/i.new" "$STUB/issues.json"
  grep -q "restarting on the new code; 2 cards in flight carry on on $A" "$STUB/serve.out" && [ -z "$(ends 7)$(ends 8)" ] \
    || fail "the loop waited for its cards before it restarted, or did not say so: $(cat "$STUB/serve.out")"
  kill -0 $pid 2>/dev/null && ps -o args= -p $pid | grep -qF "$V/$B/conveyor/conveyor.sh serve" || fail "the loop is not running $B in its own process: $(ps -o args= -p $pid)"
  for i in 7 8; do ps -o args= -p "$(cpid $i)" | grep -qF "$V/$A/conveyor/conveyor.sh" || fail "card #$i does not carry on on $A: $(ps -o args= -p "$(cpid $i)")"; done
  out=$(loop serve 2>&1) && fail "a second serve ran beside the restarted loop"; grep -q 'already running' <<<"$out" || fail "second serve: $out"
  out=$(CONVEYOR_ADOPT=' ' CONVEYOR_MAIN=$R CONVEYOR_CARDS=$T/$CASE/cards timeout 20 bash "$SRC/conveyor.sh" serve 8>>"$STUB/other.run" 2>&1) \
    && fail "a serve with a forged adoption ran beside the restarted loop"; grep -q 'already running' <<<"$out" || fail "forged adoption: $out"
  # The adopted #7 still holds its file: #9 is reviewed, then waits on it to land. Health and the Board see both
  # adopted cards as on the belt.
  : > "$STUB/go.9"
  till 'grep -q "card $(card 9) waits on card $(card 7)" "$STUB/serve.out"' && [ -n "$(st 'select(.issue == 9 and .step == "review")')" ] \
    || fail "#9 did not wait on the adopted #7's claim after its review: $(cat "$STUB/serve.out")"
  h=$(loop health); [ "$(jq -c --arg a "$(card 7)" --arg b "$(card 8)" '[.loop, (.stuck | map(select(.card == $a or .card == $b)) | length)]' <<<"$h")" = '[true,0]' ] \
    || fail "health does not see the adopted cards as running: $(jq -c '[.loop, .stuck]' <<<"$h")"
  [ "$(loop cards | jq -c '[.open, ([.cards[] | select(.result == "") | .issue] | sort)]')" = '[3,[7,8,9]]' ] || fail "the Board does not show the adopted cards: $(loop cards)"
  # #7 lands, in the process it started in (with $B's code from its land step: t_switchcode), then #8 and #9; the new loop pushes them all, one push at a time.
  : > "$STUB/go.8"; : > "$STUB/go.7"
  till '[ "$(ends 7)" = landed ] && [ "$(ends 8)" = landed ] && [ "$(ends 9)" = landed ] && [ "$(git -C "$O" rev-parse main)" = "$(git -C "$R" rev-parse main)" ]' \
    || fail "the cards did not all land and push through the new loop: $(st '"\(.issue) \(.step)"' | tr '\n' ,) $(cat "$STUB/serve.out")"
  [ "$(awk '{ print $1 }' "$STUB/pushlog" | uniq -c | awk '$1 != 1' | wc -l)" = 0 ] || fail "a push started beside another: $(cat "$STUB/pushlog")"
  till '[ "$(st '"'"'select(.step == "pushed") | .issue'"'"' | sort -n | tr "\n" " ")" = "5 6 7 8 9 " ]' || fail "the landings were not all marked pushed: $(st 'select(.step == "pushed")')"
  loop check && [ "$(loop cards | jq -c '[.landed, .open]')" = '[5,0]' ] || fail "the records after the restart: $(loop cards)"
  kill $pid; wait $pid 2>/dev/null; return 0
}

# Bugs: a second restart says the cards it adopts again run the code of the loop before it; a card killed while
# adopted stays open for good and `retry` refuses it, or its review goes on in a worktree taken away (also when it is
# killed at a restart), or a process under it that ignores TERM holds the loop for good, or one it starts on TERM
# before it ends outlives it unseen.
t_adoptkill() {
  adoptsetup "[$(issue 8 2026-01-03)]"
  # Each card changes a file of its own; the reviews of #8 and #9 are held until $STUB/go.<issue>. The first review of
  # #8 starts a process that ignores TERM, and on TERM starts another that ignores it too (its pid in $STUB/spawned),
  # then ends. That it does is checked here, so a spawned file that is missing later means no TERM came.
  echo 'echo two >> "f${PWD##*-}.txt"' > "$STUB/build"
  cat > "$STUB/deaf.sh" <<'EOF2'
deaf() { trap '' TERM; echo "$BASHPID" > "$STUB/spawned"; while :; do sleep 1; done; } # sleep: a stand-in that goes on until it is killed
trap 'deaf & exit' TERM; : > "$STUB/deafup"
while :; do sleep 1; done # sleep: a stand-in that goes on until TERM
EOF2
  bash "$STUB/deaf.sh" & k=$!; until [ -e "$STUB/deafup" ] || ! kill -0 $k 2>/dev/null; do sleep 0.1; done; kill -TERM $k
  wait $k; until [ -s "$STUB/spawned" ]; do sleep 0.1; done # the one it started on TERM writes its pid as it starts
  [ -s "$STUB/spawned" ] && kill -0 "$(cat "$STUB/spawned")" 2>/dev/null || fail "the process that ignores TERM did not start another on TERM"
  kill -KILL "$(cat "$STUB/spawned")"; rm "$STUB/spawned" "$STUB/deafup"
  echo 'n=${PWD##*-}; [ "$n" != 8 ] || [ -e "$STUB/deaf" ] || { : > "$STUB/deaf"; bash "$STUB/deaf.sh" >/dev/null 2>&1 & }; : > "$STUB/reviewing.$n"; while [ -d "$STUB" ]; do [ -e "$STUB/go.$n" ] && break; sleep 0.5; done' > "$STUB/review-cmd"
  # Once $STUB/kill8 names #8's process, the first look under it after the loop on $B has seen the pin move kills it
  # first, so that look finds nothing under it: the restart's own, or the list of the turn that restarts.
  cat > "$STUB/pgrep" <<EOF2
#!/usr/bin/env bash
k=\$(cat "$STUB/kill8" 2>/dev/null) && [ "\$*" = "-P \$k" ] && grep -q "than this loop.s $B" "$STUB/serve.out" && rm "$STUB/kill8" && kill -KILL "\$k"
exec $(command -v pgrep) "\$@"
EOF2
  chmod +x "$STUB/pgrep"; adoptserve
  # #8 in review is adopted by the loop the pin's move to $B restarts, which picks #9 on $B.
  till '[ -e "$STUB/reviewing.8" ]' || fail "#8 did not reach review: $(cat "$STUB/serve.out")"
  tune --arg c "$B" '.plugin.commit = $c'; add 9 2026-01-04
  till '[ -e "$STUB/reviewing.9" ]' && grep -q "restarting on the new code; 1 cards in flight carry on on $A" "$STUB/serve.out" \
    || fail "the loop on $B did not adopt #8 and start #9: $(cat "$STUB/serve.out")"
  # The pin moves back to $A before they end: a second restart, which adopts both again and says each code they run.
  # #8's own process is killed at that restart, its review still held, as the old loop looks under it for the last
  # time (the stub pgrep, above): the review, and a process under it that ignores TERM (with any it starts on TERM),
  # are ended before its worktree goes, the card is blocked with the reason, and `retry` takes it.
  tree() { local k; echo "$1"; for k in $(pgrep -P "$1"); do tree "$k"; done; }
  till '[ -e "$STUB/deafup" ]' || fail "#8's review did not start its process that ignores TERM: $(cat "$STUB/serve.out")"
  k=$(tree "$(cpid 8)" | tail -n +2); [ -n "$k" ] || fail "#8 runs no review to outlive it"
  cpid 8 > "$STUB/kill8"; tune --arg c "$A" '.plugin.commit = $c'
  till '[ "$(grep -c restarting "$STUB/serve.out")" = 2 ]' && [ ! -e "$STUB/kill8" ] || fail "#8 was not killed at the second restart: $(cat "$STUB/serve.out")"
  grep -q "restarting on the new code; 2 cards in flight carry on on $(printf "%s\n" "$A" "$B" | sort | paste -sd" " - | sed "s/ /, /g")$" "$STUB/serve.out" \
    || fail "the second restart did not say #8 runs $A and #9 runs $B: $(cat "$STUB/serve.out")"
  till 'ps -o args= -p $pid | grep -qF "$V/$A/conveyor/conveyor.sh serve"' || fail "the loop did not restart on $A: $(ps -o args= -p $pid)"
  till '[ "$(ends 8)" = blocked ]' || fail "a card killed while adopted was not recorded blocked: $(st 'select(.issue == 8)')"
  # Its line says where it was and what ended it: the review step, and the KILL it was sent above.
  [[ "$(st 'select(.issue == 8 and .step == "blocked") | .reason')" =~ ^"its process ended without a result in its review step".*"; signal KILL killed it (exit status 137)"$ ]] \
    || fail "reason: $(st 'select(.issue == 8 and .step == "blocked") | .reason')"
  # The loop stops then kills, so it sends no TERM: had it sent one, the process that ignores TERM would have started
  # another (checked above), which would have written $STUB/spawned and could outlive the card unseen.
  [ ! -e "$STUB/spawned" ] || fail "the loop sent TERM to #8's processes, and one started another: $(ps -o pid=,args= -p "$(cat "$STUB/spawned")")"
  for i in $k; do ! kill -0 "$i" 2>/dev/null || fail "the review of the killed #8 runs on after its worktree went: $(ps -o pid=,args= -p "$i")"; done
  : > "$STUB/go.8"; : > "$STUB/go.9"
  loop retry 8 >/dev/null || fail "retry refused the card killed while adopted"
  till '[ "$(ends 8)" = landed ] && [ "$(ends 9)" = landed ]' || fail "the retried #8 and the adopted #9 did not land: $(st '"\(.issue) \(.step)"' | tr '\n' ,)"
  kill $pid; wait $pid 2>/dev/null; return 0
}

# Bugs: a restart with no card in flight is not what it was: on the pin, in the same process, holding the lock,
# picking; after the restart, a ready issue with a free slot waits more than one turn to be picked.
t_adoptidle() {
  local k
  adoptsetup '[]'
  # The loop's waits (TURNS) when #11 is made ready, and when it is picked: the turn running then may be past its
  # pick, so the next one picks it, with one wait between. The pick is counted by the loop's first wait after its
  # picked record, in the loop's own process: its build starts later, after its worktree and brief, while the loop
  # takes more turns, and those turns are not the pick's.
  sleep() { case ${FUNCNAME[1]:-} in run) [ "$1" = 0.1 ] || { [ -e "$STUB/pickedat" ] || ! jq -e 'select(.issue == 11 and .step == "picked")' "$ST/cards.jsonl" >/dev/null 2>&1 || wc -l < "$TURNS" > "$STUB/pickedat"; echo "${CONVEYOR_MAIN:-}" >> "$TURNS"; } ;; esac; command sleep "$@"; } # sleep: the engine's own, passed on as called
  export -f sleep; adoptserve; turns 1; tune --arg c "$B" '.plugin.commit = $c'
  till 'grep -q "restarting on the new code; 0 cards in flight carry on on $A" "$STUB/serve.out"' || fail "the idle loop did not restart: $(cat "$STUB/serve.out")"
  k=$(wc -l < "$TURNS"); add 11 2026-01-06; till '[ "$(ends 11)" = landed ]' || fail "the loop restarted with no card in flight did not pick: $(cat "$STUB/serve.out")"
  [ "$(cat "$STUB/pickedat")" -le $((k + 1)) ] || fail "#11 was picked $(( $(cat "$STUB/pickedat") - k )) waits after it was ready, past one turn: $(cat "$STUB/serve.out")"
  kill -0 $pid 2>/dev/null && ps -o args= -p $pid | grep -qF "$V/$B/conveyor/conveyor.sh serve" || fail "the idle restart is not on $B in its own process"
  out=$(loop serve 2>&1) && fail "a second serve ran beside the loop restarted idle"
  kill $pid; wait $pid 2>/dev/null; return 0
}

# switchrun: N, a commit after $B, installed: its redbrief() (lib/card.sh, called as the land step
# begins) writes the commit the card runs to $STUB/newcode, the card's settings file to $STUB/settings, and to
# $STUB/prompt card()'s sprompt (made before the switch, as the copies other functions are handed are) as session()
# and review() send it (newtexts(), lib/session.sh); its card rules (rules/card-core.md) end with a line of its own.
# #5 then started on $A, the pin moved to N while #5 is in its test step, and #5 let go on to its end.
switchrun() {
  adoptsetup "[$(issue 5 2026-01-01)]"; linkset '{"a.txt": ["a.test.sh"], "f5.txt": ["a.test.sh"]}' # #5's test step runs the stub
  printf '%s\n' 'eval "old$(declare -f redbrief)"; redbrief() { echo "$RAN" >> "$STUB/newcode"; cp "$wt.settings" "$STUB/settings"; local p=$sprompt; newtexts p; printf %s "$p" > "$STUB/prompt"; oldredbrief "$@"; }' >> "$D/conveyor/lib/card.sh"
  echo 'A rule of commit N.' >> "$D/conveyor/rules/card-core.md"
  git -C "$D" commit -qam N && N=$(git -C "$D" rev-parse HEAD) && git -C "$D" push -q origin main \
    && bash "$D/conveyor/conveyor.sh" install "$N" >/dev/null || fail "the new commit was not installed"
  echo 'echo two >> f5.txt' > "$STUB/build"
  echo 'case $PWD in *-5) : > "$STUB/testing"; while [ -d "$STUB" ]; do [ -e "$STUB/go" ] && break; sleep 0.5; done ;; esac' >> "$STUB/test-cmd"
  adoptserve
  till '[ -e "$STUB/testing" ]' || fail "#5 did not reach its test step: $(cat "$STUB/serve.out")"
  tune --arg c "$N" '.plugin.commit = $c'
  till '[ "$(jq -r .commit "$S/loop.json" 2>/dev/null)" = "$N" ]' || fail "the loop did not restart on $N: $(cat "$STUB/serve.out")"
  : > "$STUB/go"; till '[ "$(ends 5)" = landed ]' || fail "#5 did not land: $(st 'select(.issue == 5) | .step' | tr '\n' ' ') $(cat "$STUB/serve.out")"
}

# Bugs (#449): a card in its test step when Conveyor takes a new commit lands on the code it started with (on
# 2026-11-18 a fix to how cards test missed the three cards running when it landed), or its passed test step runs
# again after the switch, or its log does not say it switched; its next session runs the old install's hooks
# (its settings file) or the old rules (its prompt, a copy made before the switch too); prune() removes the install it
# switched to while it runs; a later restart says, and hands on, the commit it started on in place of the one it runs.
t_switchcode() {
  switchrun
  grep -qF "conveyor: card $(card 5): Conveyor took commit $N; the card goes on with the new code from its land step, and no passed step runs again" "$STUB/serve.out" \
    || fail "#5 did not say it switched at its land step: $(cat "$STUB/serve.out")"
  [ "$(sort -u "$STUB/newcode" 2>&1)" = "$N" ] || fail "#5's land step did not run $N's code: $(cat "$STUB/newcode" 2>&1)"
  [ "$(st 'select(.issue == 5 and .step == "start") | .of' | grep -c '^test$')" = 1 ] && [ "$(st 'select(.issue == 5 and .step == "test") | .result' | tr '\n' ' ')" = 'pass ' ] \
    || fail "#5's passed test step ran again: $(st 'select(.issue == 5) | .of // .step' | tr '\n' ' ')"
  grep -qF "$V/$N" "$STUB/settings" && ! grep -qF "$V/$A" "$STUB/settings" || fail "#5's settings after the switch do not run $N's hooks: $(cat "$STUB/settings" 2>&1)"
  grep -qxF 'A rule of commit N.' "$STUB/prompt" && [ "$(grep -c '^# Rules$' "$STUB/prompt")" = 1 ] || fail "#5's prompt after the switch does not carry $N's rules alone: $(cat "$STUB/prompt" 2>&1)"
  # The lines of #5 up to its land step, as prune() reads a card in flight (inflight(), lib/install.sh).
  jq -c 'select(.issue == 5 and .step != "landed")' "$ST/cards.jsonl" > "$STUB/inflight.jsonl"
  ( . "$SRC/lib/install.sh" && inflight "$STUB/inflight.jsonl" ) | grep -qxF "$N" || fail "prune() would remove $N's install while #5 runs on it: $(cat "$STUB/inflight.jsonl")"
  # The commit a loop that restarts names for #5 and hands its next loop (cardcode(), lib/run.sh), the store read as
  # its lines: not $A, which #5 left.
  t=$(stdb() { cat "$STUB/inflight.jsonl"; }; eval "$(sed -n '/^cardcode() {/,/^}/p' "$SRC/lib/run.sh")"; cardcode "$(card 5)" "$A")
  [ "$t" = "$N" ] || fail "a restart would say #5 runs $t, not $N"
  kill $pid; wait $pid 2>/dev/null; return 0
}

# Bug (#449): a card switches to new code that reads another form of step files than its old code saved, or does not
# say why it stays on its old code.
t_switchkeep() {
  local out; out=$(switchtry "s/^STEPFILES=.*/STEPFILES=2/")
  grep -qxF "conveyor: card c-5: Conveyor took commit new2; the card goes on with its old code, commit old1: the new code cannot read the step files that the old code saved (form 1; the new code reads form 2)" <<<"$out" \
    || fail "c-5 did not say why it kept its old code: $out"
  grep -qx 'none of the new code loaded' <<<"$out" || fail "c-5 loaded new2's code: $out"
}

# switchtry <sed script>: what switchcode() (lib/card.sh) says, called from a function named card() as began() is, in
# a shell that loaded this engine as `serve` does (serveeng, serve.test.sh), for card c-5 at its land step; it runs
# commit old1 (this engine folder, as an install's own), and loop.json says the loop runs commit new2 from a copy of
# it, its lib/card.sh changed by <sed script> and given a function newmark() of its own. card()'s texts (issue..vrule)
# are set, so new code that changes nothing the card runs in is switched to. Then whether newmark() was loaded. The
# switch itself, in a card the loop runs: t_switchcode.
switchtry() {
  local new=$T/$CASE/new
  setup '[]'; mkdir -p "$new" && cp -a "$SRC/." "$new/" && sed -i "$1" "$new/lib/card.sh" && echo 'newmark() { :; }' >> "$new/lib/card.sh" \
    || fail "no copy of the engine to switch to"
  serveeng "$SRC" "OWN=1 RAN=old1; jq -n --argjson p \$\$ --arg d '$new' '{pid: \$p, commit: \"new2\", checkout: \$d}' > \"\$SAYS\" || exit 1
    issue='{\"number\":5,\"title\":\"five\",\"body\":\"\"}' hdr=h rules=r vrule=on; card() { switchcode c-5 land; }; card; declare -F newmark >/dev/null || echo 'none of the new code loaded'" 2>&1
}

# Bug (#449 review): a card switches while it runs in a function the new code changes, so the rest of that function
# runs its old body beside the new code's other functions (a fix inside card() never reaches it); or its log does not
# say why it stays on its old code.
t_switchbusy() {
  local out; out=$(switchtry '/^card() {/a :')
  grep -qxF "conveyor: card c-5: Conveyor took commit new2; the card goes on with its old code, commit old1: the new code changes card(), which the card is running in" <<<"$out" \
    || fail "c-5 did not say why it kept its old code: $out"
  grep -qx 'none of the new code loaded' <<<"$out" || fail "c-5 loaded new2's code: $out"
}

# Bug: the loop that a restart starts adopts a card that has landed and not pushed yet; the card's process ends while
# the last line of the card records is still being written (a long line reaches the file in more than one write),
# the whole read of the records fails, and the loop writes `blocked` ("its process ended without a result") for the
# landed card, which then stays in Needs you after its push goes out.
t_landedrestart() {
  setup '[]'; S=$ST; O=$T/$CASE/origin; mkdir -p "$S"
  echo x > "$R/n.txt"; git -C "$R" add -A; git -C "$R" commit -qm next; sha=$(git -C "$R" rev-parse HEAD)
  rec() { # <card> <issue> <step> [extra json]
    jq -cn --arg c "$1" --argjson i "$2" --arg s "$3" --argjson x "${4:-{\}}" \
      '{card:$c,issue:$i,step:$s,time:(now | todate),tokens:{claude:0,codex:0},result:"ok",sha:"",reason:""} * $x'
  }
  { rec c1-14 14 picked; rec c1-14 14 landed "{\"sha\":\"$sha\",\"product\":false}"; } >> "$S/cards.jsonl"
  # Another card's line, half written.
  l=$(rec c2-15 15 picked); printf '%s' "${l:0:40}" >> "$S/cards.jsonl"
  # The landed card's process, adopted from the loop before the restart, has ended.
  sleep 0 & dead=$!; wait $dead # sleep: a stand-in for a card's process that has ended
  # Its exit file: only the loop's look at a card of its own that has ended takes it away, so a run that skipped the
  # adoption (and so had no adopted card to look at) leaves it, and the case fails.
  mkdir -p "$T/$CASE/cards"; echo 0 > "$T/$CASE/cards/c1-14.exit"
  # One `run` given the adopted card (CONVEYOR_ADOPT, with the run lock on fd 8), with the push rule off: no line of
  # its own is written after the half-written one. Its first turn sees to the adopted card, and it ends: the look at
  # an adopted card is run()'s own, in its turn, so the case runs the loop, in the foreground.
  pushrule() { jq --argjson p "$1" '.rules.push = $p' "$S/control.json" > "$STUB/c.new" && mv "$STUB/c.new" "$S/control.json"; } # <true | false>
  pushrule false
  out=$(CONVEYOR_ADOPT="$dead c1-14 14 $(git -C "$SRC" rev-parse HEAD)" loop run 8>>"$S/cards.jsonl.run" 2>&1) || fail "the run that adopted the landed card failed: $out"
  [ ! -e "$T/$CASE/cards/c1-14.exit" ] || fail "the run did not look at the adopted card: its exit file is still there: $out"
  ! grep -q '"step":"blocked"' "$S/cards.jsonl" || fail "the loop blocked the adopted card that had landed: $out"
  # Once the line is whole, the landed card's push is the next loop's, as for any landing.
  printf '%s\n' "${l:40}" >> "$S/cards.jsonl"; pushrule true
  out=$(loop run 2>&1) || fail "the run that pushes the landed card failed: $out"
  [ "$(git -C "$O" rev-parse main)" = "$sha" ] && [ -n "$(st 'select(.card == "c1-14" and .step == "pushed")')" ] && [ -z "$(st 'select(.step == "blocked")')" ] && loop check \
    || fail "the landed card's push did not go out, or it was blocked: $(st '"\(.card) \(.step)"' | tr '\n' ,) $out"
  # The loop's push holds its run lock and can end a while after the run: the case waits for that lock before it ends.
  wait_until "flock -n '$ST/cards.jsonl.run' true" || fail "a push of the loop still holds the loop's run lock"
}
