#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 300
# Engine cases: what the owner does to a card with no GitHub issue before the loop picks it (testcardact(),
# lib/testcardact.sh): `control hold <card id>`, `control release` with card ids and issue numbers together, and `shut
# <card id>`. Their fixture is testcards.test.sh's tcsetup and tcask: two queued cards, f.test.sh's first.
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"

# The helpers are named tk*: every case file is sourced into one shell, so a name another file uses would replace its.
# tkcards: two queued cards, f.test.sh's (its id in $TKF) and g.test.sh's ($TKG).
tkcards() {
  tcsetup; tcask f.test.sh 'Optimize the test file f.test.sh' 'Make it cheaper.'; tcask g.test.sh 'Optimize the test file g.test.sh' 'Make it cheaper.'
  TKF=$(jq -r '.cards[] | select(.file == "f.test.sh") | .id' "$ST/testactions/cards.json"); TKG=$(jq -r '.cards[] | select(.file == "g.test.sh") | .id' "$ST/testactions/cards.json")
  [[ $TKF =~ -0$ ]] && [[ $TKG =~ -0$ ]] || fail "the two queued cards have no card ids: $(cat "$ST/testactions/cards.json")"
}
tkheld() { jq -c '[.cards[] | [.file, (.held // false)]]' "$ST/testactions/cards.json"; } # which queued cards are held

# Bug it catches (#1579): a queued card with no GitHub issue could not be held, so the owner could not stop it from
# being built from a stale brief. The older card f is held: the pick takes g and then nothing; released, the next pick
# takes f. A card the pick has taken is no longer waiting: holding it is refused.
t_tchold() {
  tkcards; local out
  out=$(loop control hold "$TKF" 2>&1) && [ "$out" = "conveyor: card $TKF is held: it is not picked until \`control release $TKF\`" ] || fail "control hold $TKF failed: $out"
  [ "$(tkheld)" = '[["f.test.sh",true],["g.test.sh",false]]' ] || fail "control hold $TKF did not hold only f.test.sh's card: $(tkheld)"
  fx_in 'for i in 1 2; do p=$(locked pick "" "" "[]") || exit 1; echo "pick $i: $p"; done'
  [ "$RC" = 0 ] && grep -qxF "pick 1: $TKG 0 false" "$T/$CASE/run.out" && grep -qx 'pick 2: ' "$T/$CASE/run.out" \
    || fail "after control hold $TKF, the pick took the held card, or not the other: $(cat "$T/$CASE/run.out")"
  loop control release "$TKF" > /dev/null || fail "control release $TKF failed"
  fx_in 'locked pick "" "" "[]"'
  [ "$RC" = 0 ] && [ "$(cat "$T/$CASE/run.out")" = "$TKF 0 false" ] || fail "after control release $TKF, the pick did not take it: $(cat "$T/$CASE/run.out")"
  if out=$(loop control hold "$TKG" 2>&1); then fail "control hold $TKG of a card the pick took was accepted: $out"; fi
  [[ $out == *"$TKG is not a card with no GitHub issue that is waiting to be picked"*"; nothing changed" ]] || fail "the refusal of control hold $TKG does not name the card: $out"
}

# Bug it catches (#1579): `shut <card id>` of a queued card with no GitHub issue said there was no open or blocked card,
# so the card was still picked. It is taken off the record, the other card stays, and the pick never takes it.
t_tcshut() {
  tkcards; local out
  out=$(loop shut "$TKF" 2>&1) && [ "$out" = "conveyor: card $TKF was shut before it was picked; it is taken off the record and never picked" ] || fail "shut $TKF failed: $out"
  [ "$(jq -c '[.cards[].file]' "$ST/testactions/cards.json")" = '["g.test.sh"]' ] || fail "shut $TKF did not take only its card off the record: $(cat "$ST/testactions/cards.json")"
  fx_in 'for i in 1 2; do p=$(locked pick "" "" "[]") || exit 1; echo "pick $i: $p"; done'
  [ "$RC" = 0 ] && grep -qxF "pick 1: $TKG 0 false" "$T/$CASE/run.out" && grep -qx 'pick 2: ' "$T/$CASE/run.out" \
    || fail "after shut $TKF, the pick took it, or not the other card: $(cat "$T/$CASE/run.out")"
  if out=$(loop shut "$TKF" 2>&1); then fail "shut $TKF of a card no longer on the record was accepted: $out"; fi
}

# Bug it catches (#1579): `control hold` and `control release` with a card id and an issue number together refused the
# whole list, so `control release 1575 <card id>` released nothing. Both are acted on. A list with one argument that
# does not fit (a card id not on the record, or neither an issue number nor a card id) is refused naming it, with the
# card ids before it left as they were.
t_tcmix() {
  tkcards; local out nosuch=c20260101T000000-x-0
  out=$(loop control hold 7 "$TKF" 2>&1) || fail "control hold 7 $TKF failed: $out"
  [ "$(loop control | jq -c .held)" = '[7]' ] && [ "$(tkheld)" = '[["f.test.sh",true],["g.test.sh",false]]' ] \
    || fail "control hold 7 $TKF did not hold issue 7 and the card: $(loop control | jq -c .held) $(tkheld)"
  if out=$(loop control hold "$TKG" 8 "$nosuch" 2>&1); then fail "control hold $TKG 8 $nosuch, with a card id that is on no record, was accepted: $out"; fi
  [[ $out == *"$nosuch is not a card with no GitHub issue that is waiting to be picked"*"; nothing changed" ]] && [ "$(loop control | jq -c .held)" = '[7]' ] \
    && [ "$(tkheld)" = '[["f.test.sh",true],["g.test.sh",false]]' ] || fail "control hold $TKG 8 $nosuch did not refuse naming $nosuch and change nothing: $out $(loop control | jq -c .held) $(tkheld)"
  if out=$(loop control release "$TKF" seven 2>&1); then fail "control release $TKF seven, with an argument that is no issue number, was accepted: $out"; fi
  [[ $out == *'"seven" is neither an issue number nor a card id'* ]] && [ "$(tkheld)" = '[["f.test.sh",true],["g.test.sh",false]]' ] \
    || fail "control release $TKF seven did not refuse naming seven and change nothing: $out $(tkheld)"
  loop control release 7 "$TKF" > /dev/null || fail "control release 7 $TKF failed"
  [ "$(loop control | jq -c .held)" = '[]' ] && [ "$(tkheld)" = '[["f.test.sh",false],["g.test.sh",false]]' ] \
    || fail "control release 7 $TKF did not release both: $(loop control | jq -c .held) $(tkheld)"
}

# Bug it catches (#1579): a hold, a release or a shut that does not take the picker's lock (testpick(), lib/testaction.sh)
# can write the record from a read the pick has made stale, so a card held or shut is picked all the same, or the pick's
# own write puts it back. Here this shell holds that lock, as a pick in its middle does: each of the three commands waits for
# it (a `timeout` ends it with 124, with the record as it was) and, with the lock let go, acts.
# timeout: a command that took no lock would finish at once, so its end at the limit is what shows it waited.
t_tclock() {
  tkcards; local lk cmd i pids=() before
  loop control hold "$TKG" > /dev/null && loop control release "$TKG" > /dev/null && loop control hold "$TKG" > /dev/null || fail "control hold $TKG, before the lock was taken, failed"
  before=$(cat "$ST/testactions/cards.json")
  exec {lk}>>"$ST/testactions/cards.json.lock"; flock "$lk" || fail "this shell could not take the lock of the record"
  i=0; for cmd in "control hold $TKF" "control release $TKG" "shut $TKF"; do
    ( timeout 3 env CONVEYOR_MAIN=$R CONVEYOR_CARDS=$T/$CASE/cards bash "$SRC/conveyor.sh" $cmd > "$T/$CASE/lock.$i.out" 2>&1; echo $? > "$T/$CASE/lock.$i.rc" ) &
    pids+=($!); i=$((i + 1))
  done
  wait "${pids[@]}"
  [ "$(cat "$ST/testactions/cards.json")" = "$before" ] || { exec {lk}>&-; fail "a command wrote the record while this shell held its lock: $(cat "$ST/testactions/cards.json")"; }
  exec {lk}>&-
  [ "$(cat "$T/$CASE/lock.0.rc" "$T/$CASE/lock.1.rc" "$T/$CASE/lock.2.rc" | tr '\n' ' ')" = '124 124 124 ' ] \
    || fail "control hold $TKF, control release $TKG and shut $TKF did not each wait for the lock: rc $(cat "$T/$CASE/lock."*.rc | tr '\n' ' ') out $(cat "$T/$CASE/lock."*.out)"
  loop control hold "$TKF" > /dev/null && loop control release "$TKG" > /dev/null && loop shut "$TKF" > /dev/null || fail "the three commands did not act once the lock was let go"
  [ "$(jq -c '[.cards[] | [.file, (.held // false)]]' "$ST/testactions/cards.json")" = '[["g.test.sh",false]]' ] || fail "the record is not as the three commands leave it: $(cat "$ST/testactions/cards.json")"
}

# Bug it catches (#1579 follow-up): a pick (testpick(), lib/testaction.sh) that does not take the lock hold, release and
# shut take. The real pick is paused after it read the record (at farstates(), its next step). There this shell asks
# for that lock (the one t_tclock shows hold, release and shut wait for) with `flock -n`, which does not wait: it must
# be refused, as the pick holds it. With no lock in the pick it is given, at once and on any runner, and the case fails
# there; a hold timed against a limit could instead read the record late, after the pick's write, and pass. Then
# `control hold` of the card the pick is about to take runs, the pick goes on, and the hold, once it has the lock,
# refuses that card. The pause and the hold's end are waited for as files, as each is in another process.
t_tcpicklock() {
  tkcards; local d=$T/$CASE p rc lk
  ( fx_in 'eval "$(declare -f farstates | sed "1s/^farstates /tkfar0 /")"
    farstates() { if [ "${FUNCNAME[1]}" = testpick ]; then : > "'"$d"'/paused"; until [ -e "'"$d"'/go" ]; do sleep 0.1; done; fi; tkfar0 "$@"; } # sleep: the paused pick waits for the case to let it go
    locked pick "" "" "[]"'; echo "$RC" > "$d/pick.rc" ) & p=$!
  wait_until "[ -e '$d/paused' ]" || fail "the pick did not reach its read of the record"
  exec {lk}>>"$ST/testactions/cards.json.lock"
  if flock -n "$lk"; then exec {lk}>&-; : > "$d/go"; wait "$p"; fail "the lock of the record was free while the pick held its read of the record: hold, release and shut do not wait for the pick"; fi
  exec {lk}>&-
  ( loop control hold "$TKF" > "$d/hold.out" 2>&1; echo $? > "$d/hold.rc" ) &
  : > "$d/go"; wait "$p"
  wait_until "[ -s '$d/hold.rc' ]" || fail "control hold $TKF did not end once the pick let go of the lock: $(cat "$d/hold.out")"
  rc=$(cat "$d/hold.rc")
  [ "$(cat "$d/pick.rc")" = 0 ] && [ "$(cat "$d/run.out")" = "$TKF 0 false" ] || fail "the paused pick did not take $TKF: $(cat "$d/run.out")"
  [ "$rc" = 2 ] && [[ $(cat "$d/hold.out") == *"$TKF is not a card with no GitHub issue that is waiting to be picked"* ]] \
    || fail "control hold $TKF, run while the pick held the record, ended $rc, not 2 with a refusal of the card the pick took:$(cat "$d/hold.out")"
  [ "$(jq -c --arg c "$TKF" '[.cards[] | select(.id == $c) | [.card != null, (.held // false)]]' "$ST/testactions/cards.json")" = '[[true,false]]' ] \
    || fail "after the pick and control hold $TKF, its entry is not picked and unheld: $(cat "$ST/testactions/cards.json")"
}

# Bug it catches (#1579): `control hold` and `control release` of card ids only returned before the wake `control` sends
# (wakeloop(), lib/control.sh), so a loop asleep on its idle timer picked the released card only when the timer ended.
# The stand-in loop counts each URG it is sent; the wait is a poll, as the signal arrives from another process.
t_tcwake() {
  tkcards
  bash -c 'trap "echo urg >> \"\$0.urg\"" URG; : > "$0.ready"; sleep 60 & s=$!; while kill -0 "$s" 2>/dev/null; do wait "$s"; done' "$STUB/loop" & e=$! # sleep: the stand-in loop's own wait
  wait_until '[ -e "$STUB/loop.ready" ]' || fail "the stand-in loop did not start"
  jq -cn --argjson p "$e" --arg t "$(p_started "$e")" '{pid: $p, started: $t}' > "$ST/loop.json"
  loop control hold "$TKF" > /dev/null || fail "control hold $TKF failed"
  WAIT_CEILING=10 wait_until '[ "$(wc -l < "$STUB/loop.urg" 2>/dev/null)" = 1 ]' || fail "control hold $TKF did not wake the loop loop.json names: $(cat "$ST/loop.json")"
  loop control release "$TKF" > /dev/null || fail "control release $TKF failed"
  WAIT_CEILING=10 wait_until '[ "$(wc -l < "$STUB/loop.urg" 2>/dev/null)" = 2 ]' || fail "control release $TKF did not wake the loop loop.json names: $(cat "$ST/loop.json")"
  kill "$e" 2>/dev/null; wait "$e" 2>/dev/null; return 0
}

# Bug it catches (#1579): a shut queued card leaves what another record still assigns to it. (1) A batch card of the
# self-heals list holds its entries (batched): shut must give them back, or no later batch takes them. (2) A card that
# is a part of a split issue is what that issue waits for: shut refuses it, naming the issue, and changes nothing.
t_tcshutheld() {
  tkcards; local out
  jq -cn --arg c "$TKF" '{id: "h000000001", time: "2026-11-01T00:00:00Z", card: "c5", issue: 5, repo: "r", area: "area:engine", finding: "[P2] a.sh:1 a slow poll", why: "it heals", effect: "self-heals", from: "review", batched: $c}' >> "$ST/selfheals.jsonl"
  jq -cn --arg c "$TKG" '{card: "c20261101T000000-r-60", issue: 60, step: "split", result: "ok", time: "2026-11-01T00:00:00Z", split: {cards: [$c]}}' >> "$ST/cards.jsonl"
  if out=$(loop shut "$TKG" 2>&1); then fail "shut $TKG, a part of the split of issue 60, was accepted: $out"; fi
  [[ $out == *"$TKG is a part of the split of issue #60"*"nothing changed" ]] && [ "$(jq -c '[.cards[].file]' "$ST/testactions/cards.json")" = '["f.test.sh","g.test.sh"]' ] \
    || fail "shut $TKG did not refuse naming issue #60 and change nothing: $out $(cat "$ST/testactions/cards.json")"
  out=$(loop shut "$TKF" 2>&1) || fail "shut $TKF failed: $out"
  [ "$(jq -c '[.batched, .freed]' "$ST/selfheals.jsonl")" = "$(jq -cn --arg c "$TKF" '[null, [$c]]')" ] \
    || fail "shut $TKF did not give its self-heals entry back to the list: $(cat "$ST/selfheals.jsonl")"
}
