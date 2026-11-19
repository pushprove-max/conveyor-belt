#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 300
# Engine cases: a serve loop that restarts on new code adopts the cards in flight; a loop takes up the cards whose
# process is gone (the machine or the loop stopped under them).
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

# The cards whose process was gone (run(): revive()). gonestop <pid>: it and every process under it, each stopped
# before the processes under it are looked for, so none starts another unseen; KILL then ends them all at once, as a
# power cut does.
gonestop() { local k; kill -STOP "$1" 2>/dev/null; echo "$1"; for k in $(pgrep -P "$1"); do gonestop "$k"; done; }
# gonecard <card> <issue> <pid> <started> [<step>]: the lines of a card that the machine stopped mid-build (or mid-step).
gonecard() {
  jq -cn --arg c "$1" --argjson n "$2" --argjson p "$3" --arg s "$4" --arg o "${5:-build}" '{card:$c,issue:$n,time:"2026-01-01T00:00:00Z",tokens:{claude:0,codex:0},result:"ok",sha:"",reason:""}
    | (. + {step:"picked"}), (. + {step:"worktree",pid:$p,started:$s}), (. + {step:"start",of:$o})' >> "$ST/cards.jsonl"
}

# switchrun [<sed script>]: N, a commit after $B, installed: its redbrief() (lib/card.sh, called as the land step
# begins) writes the commit the card runs to $STUB/newcode, the card's settings file to $STUB/settings, and to
# $STUB/prompt card()'s sprompt (made before the switch, as the copies other functions are handed are) as session()
# and review() send it (newtexts(), lib/session.sh); its card rules (rules/card-core.md) end with a line of its own; <sed script>, run on
# its lib/card.sh, changes it more. #5 then started on $A, the pin moved to N while #5 is in its test step, and #5 let
# go on to its end.
switchrun() {
  adoptsetup "[$(issue 5 2026-01-01)]"; linkset '{"a.txt": ["a.test.sh"], "f5.txt": ["a.test.sh"]}' # #5's test step runs the stub
  printf '%s\n' 'eval "old$(declare -f redbrief)"; redbrief() { echo "$RAN" >> "$STUB/newcode"; cp "$wt.settings" "$STUB/settings"; local p=$sprompt; newtexts p; printf %s "$p" > "$STUB/prompt"; oldredbrief "$@"; }' >> "$D/conveyor/lib/card.sh"
  echo 'A rule of commit N.' >> "$D/conveyor/rules/card-core.md"
  [ -z "${1:-}" ] || sed -i "$1" "$D/conveyor/lib/card.sh"
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
  switchrun "s/^STEPFILES=.*/STEPFILES=2/"
  grep -qF "conveyor: card $(card 5): Conveyor took commit $N; the card goes on with its old code, commit $A: the new code cannot read the step files that the old code saved (form 1; the new code reads form 2)" "$STUB/serve.out" \
    || fail "#5 did not say why it kept its old code: $(cat "$STUB/serve.out")"
  [ ! -e "$STUB/newcode" ] || fail "#5 ran $N's code: $(cat "$STUB/newcode")"
  kill $pid; wait $pid 2>/dev/null; return 0
}

# Bug (#449 review): a card switches while it runs in a function the new code changes, so the rest of that function
# runs its old body beside the new code's other functions (a fix inside card() never reaches it); or its log does not
# say why it stays on its old code.
t_switchbusy() {
  switchrun '/^card() {/a :'
  grep -qF "conveyor: card $(card 5): Conveyor took commit $N; the card goes on with its old code, commit $A: the new code changes card(), which the card is running in" "$STUB/serve.out" \
    || fail "#5 did not say why it kept its old code: $(cat "$STUB/serve.out")"
  [ ! -e "$STUB/newcode" ] || fail "#5 ran $N's code: $(cat "$STUB/newcode")"
  kill $pid; wait $pid 2>/dev/null; return 0
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
  local -x WHOLESUITE=true # The old fixture: it tests test.command itself, the whole-suite run's log ($CONVEYOR_TEST_LOG) and its rerun list.
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
