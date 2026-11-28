#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 120
# Engine cases: the release hold (issue 1076; relhold(), holdtake(), releasewait(), lib/push.sh; land(),
# lib/claim.sh): while a release run is under way no card lands on main and nothing is pushed, and the cards that
# reach their land step wait for its end. The release cases' fixture is releaseboard.test.sh's runsetup
# (release.test.sh's cutsetup).
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"

# One engine call in the loop's shell (commands/run.sh's engine files), in main's checkout, its output in <file>.
rh_eng() { # <file> <commands>
  ( export CONVEYOR_MAIN=$R CONVEYOR_CARDS=$T/$CASE/cards; cd "$R" || exit 9
    . "$SRC/conveyor.sh" state-dir > /dev/null && eval "$(grep '^\. "\$HERE/lib/' "$SRC/commands/run.sh")" && names || exit 9
    eval "$2" ) > "$1" 2>&1
}
# The suite of runsetup until the case lets it go ($STUB/go): $STUB/insuite says it runs.
RHSUITE='touch "$STUB/insuite"; for i in $(seq 600); do [ -e "$STUB/go" ] && break; sleep 0.1; done' # sleep: the suite runs while the case lands and pushes
# Card c7-7's worktree on main as it is now, with a new file seven.txt staged: a card at its land step.
rh_card() {
  WT=$T/$CASE/cards/c7-7
  git -C "$R" worktree add -q --detach "$WT" main && echo seven > "$WT/seven.txt" && git -C "$WT" add -A || fail "the card's worktree could not be made"
}
# rh_land: c7-7 lands (land(), as card() calls it), its output and exit in $T/$CASE/land.out.
rh_land() { rh_eng "$T/$CASE/land.out" 'land c7-7 7 "$CARDS/c7-7" "seven (#7)"; echo "land: $?"'; }

# Bug (#1076): a card that finished while the Board's Release ran its suite landed and was pushed, so main moved
# under the suite and release was refused as "main moved". Here, during the suite, the card's landing and a push are
# refused and main stays where the suite runs; between release-prep's end and release's start (the jq that reads the
# commit release is told, wrapped here) the hold still stands; release goes out; then the card lands, fitted onto the
# release's main as card() fits it (STALE).
t_relhold() {
  local O RUN out j
  runsetup "$RHSUITE"; rh_card
  j=$(command -v jq) && printf '%s\n' '#!/usr/bin/env bash' \
    "if [ \"\$#\" = 3 ] && [ \"\$2\" = '.sha // \"\"' ] && [ \"\$3\" = '$RUN' ]; then flock -n -s '$ST/release.hold' true && echo free >> '$STUB/gap' || echo held >> '$STUB/gap'; fi" \
    "exec '$j' \"\$@\"" > "$STUB/jq" && chmod +x "$STUB/jq" || fail "the jq wrapper could not be made" # wraps the jq call that gives release the commit its suite passed on
  out=$(loop release-run 1.1.0 2>&1) || fail "release-run did not start the run: $out"
  wait_until '[ -e "$STUB/insuite" ]' "cat '$T/$CASE/cards/release/run.log'" || fail "the suite did not start"
  rh_land
  [ "$(cat "$T/$CASE/land.out")" = "a release run is under way, so no card lands on main until it ends; nothing was landed"$'\n'"land: 1" ] \
    && [ "$(git -C "$R" rev-parse main)" = "$O" ] || fail "the card landed during the release run's suite: $(cat "$T/$CASE/land.out")"
  rh_eng "$T/$CASE/push.out" 'push c7-7 7; echo "push: $?"'
  grep -q 'a release run is under way, so nothing is pushed until it ends' "$T/$CASE/push.out" && grep -qx 'push: 3' "$T/$CASE/push.out" \
    || fail "a push ran during the release run's suite: $(cat "$T/$CASE/push.out")"
  touch "$STUB/go"
  relwait "the run did not end" '.step == "release" and .ended != null'
  jq -e --arg o "$O" '.state == "released" and .moved == false and .sha == $o' "$RUN" > /dev/null \
    || fail "the release did not go out on the commit its suite passed: $(cat "$RUN") $(cat "$T/$CASE/cards/release/run.log")"
  [ "$(cat "$STUB/gap" 2>&1)" = held ] || fail "a card could land between release-prep and release: $(cat "$STUB/gap" 2>&1)"
  wait_until "flock -n -s '$ST/release.hold' true" || fail "the hold is still held once the run ended"
  rh_land
  [ "$(cat "$T/$CASE/land.out")" = "main moved since its checks and tests ran; nothing was landed"$'\n'"land: 1" ] || fail "the card did not find main moved by the release: $(cat "$T/$CASE/land.out")"
  git -C "$WT" diff --cached --binary > "$WT.p" && git -C "$WT" reset -q --hard main && git -C "$WT" apply --index "$WT.p" || fail "the card could not be fitted onto main"
  rh_land
  [ "$(cat "$T/$CASE/land.out")" = 'land: 0' ] && [ "$(git -C "$R" show main:seven.txt)" = seven ] \
    && git -C "$R" merge-base --is-ancestor "$(git -C "$T/$CASE/origin" rev-parse 'v1.1.0^{commit}')" main || fail "the card did not land on the release once it ended: $(cat "$T/$CASE/land.out")"
}
# Bug (#1076): `release-prep` run by hand let a card land while its suite ran (the hold is the run's own: no
# release-run holds it for it).
t_relholdprep() {
  local O RUN
  runsetup "$RHSUITE"; rh_card
  ( loop release-prep 1.1.0 > "$T/$CASE/prep.out" 2>&1 ) &
  wait_until '[ -e "$STUB/insuite" ]' "cat '$T/$CASE/prep.out'" || fail "the suite did not start"
  rh_land
  [ "$(tail -n 1 "$T/$CASE/land.out")" = 'land: 1' ] && [ "$(git -C "$R" rev-parse main)" = "$O" ] || fail "the card landed during release-prep's suite: $(cat "$T/$CASE/land.out")"
  touch "$STUB/go"; wait
  jq -e '.state == "passed"' "$RUN" > /dev/null || fail "release-prep did not pass: $(cat "$T/$CASE/prep.out")"
}
# Bug (#1076): a stopped release run kept the cards waiting at their land step. The stop ends the run, and the card
# that waits (releasewait()) goes on, and lands.
t_relholdstop() {
  local O RUN out
  runsetup 'touch "$STUB/insuite"; sleep 300'; rh_card # sleep: the suite runs until the stop ends it
  out=$(loop release-run prep 1.1.0 2>&1) || fail "release-run did not start the run: $out"
  wait_until '[ -e "$STUB/insuite" ]' "cat '$T/$CASE/cards/release/run.log'" || fail "the suite did not start"
  rh_eng "$T/$CASE/wait.out" 'releasewait c7-7 7 "$CARDS/c7-7"; echo waited' &
  wait_until "jq -e '.action | startswith(\"waiting for the release of 1.1.0\")' '$WT.live'" && [ -e "$WT.idle" ] \
    || fail "the card at its land step does not say it waits for the release: $(cat "$WT.live" 2>&1)"
  out=$(loop release-run stop 2>&1) || fail "the stop failed: $out"
  wait_until "grep -qx waited '$T/$CASE/wait.out'" || fail "the card still waits once the run is stopped: $(cat "$T/$CASE/wait.out")"
  [ ! -e "$WT.live" ] && [ ! -e "$WT.idle" ] || fail "the card's wait left its live record or idle mark"
  rh_land
  [ "$(cat "$T/$CASE/land.out")" = 'land: 0' ] && [ "$(git -C "$R" show main:seven.txt)" = seven ] || fail "the card did not land once the run was stopped: $(cat "$T/$CASE/land.out")"
}
# Bug (#1124): a second `release-run` while the first waited for its hold (a push under way) passed the lock's check,
# as the first's release-prep had not taken the lock yet: it wrote over the first's run.log and queued behind it, to
# run its suite once the first ended. It is refused, and the first's run.log is left as it is.
t_relholdtwice() {
  local O RUN out rc l log=$T/$CASE/cards/release/run.log
  runsetup true
  ( exec {l}>>"$ST/release.landing" && flock -s "$l" && touch "$STUB/pushing" && wait_until '[ -e "$STUB/pushgo" ]' ) & # the stand-in push runs until the case lets it go
  wait_until '[ -e "$STUB/pushing" ]' || fail "the stand-in push did not take its share of the hold"
  out=$(loop release-run prep 1.1.0 2>&1) || { touch "$STUB/pushgo"; fail "release-run did not start the run: $out"; }
  wait_until "grep -q 'a push runs: the run starts once it ends' '$log'" "cat '$log'" || { touch "$STUB/pushgo"; fail "the run did not wait for the push"; }
  out=$(loop release-run prep 1.1.0 2>&1); rc=$?
  [ $rc = 2 ] && grep -q 'release-prep or release is already running; this one is not started' <<<"$out" \
    || { touch "$STUB/pushgo"; fail "a second release-run was not refused while the first waited for a push (exit $rc): $out"; }
  grep -q 'a push runs: the run starts once it ends' "$log" || { touch "$STUB/pushgo"; fail "the second release-run wrote over the first's run.log: $(cat "$log")"; }
  touch "$STUB/pushgo"
  relwait "the run did not end" '.step == "release-prep" and .ended != null'
  jq -e '.state == "passed"' "$RUN" > /dev/null || fail "release-prep did not pass: $(cat "$RUN") $(cat "$log")"
}
# A release run's stand-in: it holds the hold until the case lets it go ($STUB/letgo).
rh_hold() {
  local h
  ( exec {h}>>"$ST/release.hold" && flock -x "$h" && touch "$STUB/held" && wait_until '[ -e "$STUB/letgo" ]' ) & # the stand-in run holds the hold until the case lets it go
  wait_until '[ -e "$STUB/held" ]' || fail "the stand-in run did not take the hold"
}
# Bug (#1076): a card that finished its tests while a release run was under way landed. The run's stand-in holds the
# hold until the case lets it go: the card waits at its land step, the Board saying so (the snapshot left out a live
# record written before the land step's start line), main stays, and the card lands after.
t_relholdcard() {
  local run s
  setup "[$(issue 7 2026-01-01)]"; echo "$GO" > "$STUB/review.1"; echo 'echo two >> a.txt' > "$STUB/build"
  rh_hold
  local m; m=$(git -C "$R" rev-parse main)
  loop run > "$STUB/log" 2>&1 & run=$! # loop: only a whole card shows card() waiting at its land step, then landing
  wait_until "grep -qs 'waiting for the release' '$T/$CASE/cards/'*-7.live" "cat '$STUB/log'" || { touch "$STUB/letgo"; fail "the card did not wait for the release at its land step"; }
  s=$(loop snapshot --fresh)
  [ "$(jq '[.belt[] | select(.issue == 7 and (.live.action // "" | startswith("waiting for the release")))] | length' <<<"$s")" = 1 ] \
    || { touch "$STUB/letgo"; fail "the Board does not show the card waiting for the release: $(jq -c '[.belt[] | {issue, result, last: (.x.log | last), live}]' <<<"$s")"; }
  [ "$(git -C "$R" rev-parse main)" = "$m" ] && [ -z "$(st 'select(.step == "landed") | .issue')" ] || { touch "$STUB/letgo"; fail "the card landed while the release run held main"; }
  touch "$STUB/letgo"
  wait "$run" || fail "run exited non-zero: $(cat "$STUB/log")"
  [ "$(st 'select(.step == "landed") | .issue')" = 7 ] && git -C "$R" show main:a.txt | grep -qx two || fail "the card did not land once the run ended: $(st '"\(.step) \(.reason)"' | tr '\n' ,)"
}
# Bug (#1076 review): the Board's push actions lost the release's refusal or raced it. Under a release run, a Board
# push that would push (issue 7's landing is unpushed: ftland(), fulltest.test.sh) is refused with the release's
# reason; with none, the push it starts goes out even when a release run begins before that push takes the push lock
# (held here by a stand-in for the loop's push until $STUB/pushgo): Push now and Push anyway said main was pushed,
# then their background push was refused. The stand-in run writes origin's main once it gets in: the push came first.
rh_boardpush() { # <the Board's push, as loop arguments...>
  local out pl h l
  setup "[$(issue 7 2026-01-01)]"; tune '.test.full = "true"'; ftland
  jq -cn --arg s "$(git -C "$R" rev-parse main)" '{time: "2026-01-01T00:00:00Z", id: "0123456789ab", kind: "run", push: false, sha: $s, state: "failed", exit: 1, cases: [], pushed: null}' >> "$ST/fulltest.jsonl"
  rh_hold
  out=$(loop "$@" 2>&1); [ $? = 2 ] && grep -q 'a release run is under way, so nothing is pushed until it ends' <<<"$out" \
    || { touch "$STUB/letgo"; fail "$* during a release run was not refused with its reason: $out"; }
  # Bug (#1435): a refused Push now wrote no result, so the push status kept the push before it.
  [ "$1" != push-now ] || loop health | jq -e '.pushLast | .by == "now" and .started == false and .why == "a release run is under way, so nothing is pushed until it ends"' > /dev/null \
    || { touch "$STUB/letgo"; fail "$* refused during a release run does not show as the last push, with its reason: $(loop health | jq -c .pushLast)"; }
  touch "$STUB/letgo"; wait_until "flock -n -x '$ST/release.hold' true" || fail "the stand-in run did not let the hold go"
  [ "$(ftorigin)" != "$(ftmain)" ] || fail "$* pushed during a release run"
  ( exec {pl}>>"$ST/pushed.lock" && flock -x "$pl" && touch "$STUB/pushlocked" && wait_until '[ -e "$STUB/pushgo" ]' ) & # the loop's stand-in push holds the push lock until the case lets it go
  wait_until '[ -e "$STUB/pushlocked" ]' || fail "the stand-in push did not take the push lock"
  out=$(loop "$@" 2>&1) || { touch "$STUB/pushgo"; fail "$* was refused with no release run under way: $out"; }
  ( exec {h}>>"$ST/release.hold" {l}>>"$ST/release.landing" && flock -x "$h" && touch "$STUB/relheld" && flock -x "$l" && ftorigin > "$STUB/relstart" ) &
  wait_until '[ -e "$STUB/relheld" ]' || { touch "$STUB/pushgo"; fail "the stand-in run did not take the hold"; }
  touch "$STUB/pushgo"
  wait_until '[ -s "$STUB/relstart" ]' "cat '$ST/pushnow.log' '$ST/fulltest.jsonl.log'" || fail "the stand-in run never got in"
  [ "$(cat "$STUB/relstart")" = "$(ftmain)" ] \
    || fail "the release run began before the push $* had started, and that push was refused: $(cat "$ST/pushnow.log" "$ST/fulltest.jsonl.log" 2>&1)"
}
t_relholdnow() { rh_boardpush push-now; }
t_relholdanyway() { rh_boardpush full-test anyway 0123456789ab; }
# Bug (#1125): Push landed's result (fullpush(), the run line's pushed) lost the release's refusal: push() writes no
# push line when a release run refuses it (exit 3), so the result fell back to "the push did not reach origin". Under
# the run's stand-in, the result is the release's reason, and nothing is pushed.
t_relholdfullpush() {
  setup "[$(issue 7 2026-01-01)]"; ftland
  rh_hold
  rh_eng "$T/$CASE/fullpush.out" 's=$(git rev-parse main); read -r c n <<<"$(fullowed "$s")"; fullpush "$s" "$c" "$n"'
  touch "$STUB/letgo"
  [ "$(cat "$T/$CASE/fullpush.out")" = '{"ok":false,"reason":"a release run is under way, so nothing is pushed until it ends"}' ] \
    || fail "Push landed's result under a release run does not give the release's reason: $(cat "$T/$CASE/fullpush.out")"
  [ "$(ftorigin)" != "$(ftmain)" ] || fail "Push landed pushed during a release run"
}
# Bug (R286): a release run waits for RELLANDING (a push under way) after it holds RELHOLD and before it writes its
# version to run.json (relstart()), so a card that reached its land step then said "waiting for the release of 1.8.0",
# the version of the last run, which had ended. The stand-in run holds the hold with run.json still the ended 1.8.0
# run's: the card's wait names no version. The wait runs in a process of its own and is polled: the live record it
# writes, as the Board reads it, is only there while the wait is under way.
t_relholdold() {
  local p
  setup '[]'; mkdir -p "$T/$CASE/cards/release"
  echo '{"kind":"release","step":"release","version":"1.8.0","since":"2026-11-20T10:00:00Z","ended":"2026-11-20T11:00:00Z","state":"released"}' > "$T/$CASE/cards/release/run.json"
  rh_hold
  rh_eng "$T/$CASE/wait.out" 'releasewait c7-7 7 "$CARDS/c7-7"; echo waited' & p=$!
  wait_until "jq -e '.action | startswith(\"waiting for the release\")' '$T/$CASE/cards/c7-7.live'" || { touch "$STUB/letgo"; fail "the card did not wait for the release"; }
  local a; a=$(jq -r .action "$T/$CASE/cards/c7-7.live"); touch "$STUB/letgo"; wait "$p" 2>/dev/null
  [ "$a" = 'waiting for the release: no card lands on main until it ends' ] \
    || fail "the card's wait, with run.json the ended run of 1.8.0 and a new run holding the release hold, says: $a"
}
# Bug (R286): a run killed before relend() leaves run.json with ended null, so the next run's wait for RELLANDING
# still named the dead run's version 1.8.0. A run whose process has ended counts as ended. Polled as t_relholdold is.
t_relholddead() {
  local p d a
  setup '[]'; mkdir -p "$T/$CASE/cards/release"
  ( : ) & d=$!; wait "$d" # d: the pid of a process that has ended, the killed run's
  echo "{\"kind\":\"release\",\"step\":\"release-prep\",\"version\":\"1.8.0\",\"since\":\"2026-11-20T10:00:00Z\",\"ended\":null,\"state\":\"running\",\"pid\":$d}" > "$T/$CASE/cards/release/run.json"
  rh_hold
  rh_eng "$T/$CASE/wait.out" 'releasewait c7-7 7 "$CARDS/c7-7"; echo waited' & p=$!
  wait_until "jq -e '.action | startswith(\"waiting for the release\")' '$T/$CASE/cards/c7-7.live'" || { touch "$STUB/letgo"; fail "the card did not wait for the release"; }
  a=$(jq -r .action "$T/$CASE/cards/c7-7.live"); touch "$STUB/letgo"; wait "$p" 2>/dev/null
  [ "$a" = 'waiting for the release: no card lands on main until it ends' ] \
    || fail "the card's wait, with run.json the run of 1.8.0 whose process $d has ended and a new run holding the release hold, says: $a"
}
# Bug (#1076 review): stop (halt(), lib/run.sh) left a card that waited for a release run, as its wait opened with a
# land start line, and the card landed once the run ended. Its follow-ups, filed before the hold refused its landing,
# were withdrawn: their filed line does not keep it either.
t_relholdhalt() {
  local p
  setup '[]'; mkdir -p "$T/$CASE/cards"
  rh_eng "$T/$CASE/filed.out" 'record c7-7 7 filed ok "{\"followups\":[]}"'
  rh_hold
  rh_eng "$T/$CASE/wait.out" 'releasewait c7-7 7 "$CARDS/c7-7"; echo waited' & p=$!
  wait_until "jq -e '.action | startswith(\"waiting for the release\")' '$T/$CASE/cards/c7-7.live'" || { touch "$STUB/letgo"; fail "the card did not wait for the release"; }
  rh_eng "$T/$CASE/halt.out" "echo '$p c7-7' | halt"
  touch "$STUB/letgo"
  [ "$(cat "$T/$CASE/halt.out")" = "$p c7-7" ] || fail "stop left the card that waited for the release: $(cat "$T/$CASE/halt.out")"
  wait "$p" 2>/dev/null; ! grep -q waited "$T/$CASE/wait.out" || fail "the card went on from its wait after the stop"
}
