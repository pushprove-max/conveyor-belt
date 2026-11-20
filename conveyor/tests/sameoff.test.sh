#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 300
# Engine cases: the same-file rule, for a wait on a card `retry` gave back and a wait at a claim as health shows it.
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"
# The engine folder, as lib.sh sets it: named here too, so the release closure (tools/closure.sh) follows this file's paths.
SRC=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)

# sameoffsetup <waiter> <holder>: those two issues and the belt's cap 1; card c3-<waiter> on the belt waits at its
# landing claim on card c4-<holder> (its live record names it), which blocked and `retry` gave back.
sameoffsetup() {
  setup "[$(issue "$1" 2026-01-03),$(issue "$2" 2026-01-04)]"; CARDS=$T/$CASE/cards; mkdir -p "$CARDS"
  loop control cap 1 >/dev/null || fail "cap 1 was refused"
  { landed "$1" | jq -c --arg c "c3-$1" '.card = $c | .step = "picked"'
    landed "$2" | jq -c --arg c "c4-$2" '.card = $c | .step = "picked"'
    landed "$2" | jq -c --arg c "c4-$2" '.card = $c | .step = "blocked" | .result = "blocked" | .reason = "review 1: review failed (exit 124)"'; } >> "$ST/cards.jsonl"
  loop retry "$2" >/dev/null || fail "retry of #$2 exited non-zero"
  jq -cn --arg on "c4-$2" '{step: "land", waits: {on: $on, paths: ["a.txt"]}}' > "$CARDS/c3-$1.live"
}

# The belt full (cap 1) with #11, which waits at its landing claim on card c4-12; c4-12 blocked and `retry` gave #12
# back. Bug: #11 held the only slot, waiting on a card that was never picked. The loop's next turn picks #12 past the
# cap: urgent() names it, and the pick run() makes for it (ONLY=<urgent> pick retried) takes it.
t_sameoffretry() {
  sameoffsetup 11 12
  fx_in 'u=$(urgent); echo "urgent: $u"; ONLY=$u locked fresh pick retried "" "$(asked)"'
  [ "$RC" = 0 ] && [ "$(head -n 1 "$T/$CASE/run.out")" = "urgent: [12]" ] && [ "$(sed -n 2p "$T/$CASE/run.out" | cut -d' ' -f2)" = 12 ] \
    && [ -n "$(st 'select(.issue == 12 and .step == "picked" and .card != "c4-12")')" ] || fail "the retried holder #12 was not picked past the cap: $(cat "$T/$CASE/run.out")"
}

# The belt full (cap 1) with #15, which waited on card c4-16 once and went on to its tests when its claim went: its
# live record names no card now. `retry` gives #16 back. Bug: #16 was picked past the cap, a builder for nobody.
# urgent() names no card, so run() picks nothing beyond the cap.
t_sameoffcap() {
  sameoffsetup 15 16
  echo '{"step": "test"}' > "$CARDS/c3-15.live"
  fx_in 'echo "urgent: $(urgent)"'
  [ "$RC" = 0 ] && [ "$(cat "$T/$CASE/run.out")" = "urgent: " ] || fail "the retried #16 is to be picked past the cap while nobody waits on it: $(cat "$T/$CASE/run.out")"
}

# As t_sameoffretry, in a run with --only 13: the run builds only what it lists, so the retried #14 #13 waits on is
# not picked past the cap (urgent() names it only when the --only list, if any, has its issue).
t_sameoffonly() {
  sameoffsetup 13 14
  fx_in 'echo "all: $(urgent)"; ONLY="[13]"; echo "only: $(urgent)"'
  [ "$RC" = 0 ] && [ "$(cat "$T/$CASE/run.out")" = $'all: [14]\nonly: ' ] || fail "run --only 13 is to pick the retried #14: $(cat "$T/$CASE/run.out")"
}

# A card waiting on a card `retry` gave back (not on the belt) for 25 minutes (past STUCK, within waitLimitMin), and
# one waiting as long on a card on the belt. Card c1-7 blocked and was given back, as in t_sameoff.
t_sameoffstuck() {
  setup "[$(issue 7 2026-01-01)]"; mkdir -p "$T/$CASE/cards"
  landed 7 | jq -c '.card = "c1-7" | .step = "picked"' >> "$ST/cards.jsonl"
  landed 7 | jq -c '.card = "c1-7" | .step = "blocked" | .result = "blocked" | .reason = "review 1: review failed (exit 124)"' >> "$ST/cards.jsonl"
  loop retry 7 >/dev/null || fail "retry of #7 exited non-zero"
  now=$(jq -rn 'now | todate'); ago=$(jq -rn 'now - 1500 | todate')
  for c in c2-9:c1-7 c3-10:c2-9; do
    k=${c%%:*}; n=${k#*-}
    jq -cn --arg c "$k" --argjson n "$n" --arg t "$now" '{card:$c,issue:$n,step:"picked",time:$t,tokens:{claude:0,codex:0},result:"ok",sha:"",reason:"",title:"t",created:$t},
      {card:$c,issue:$n,step:"start",time:$t,tokens:{claude:0,codex:0},result:"ok",sha:"",reason:"",of:"land"}' >> "$ST/cards.jsonl"
    jq -cn --arg on "${c#*:}" --arg at "$ago" --arg t "$now" '{step: "land", at: $at, last: $t, turns: 0, waits: {on: $on, paths: ["a.txt"]},
      action: "waiting on card \($on), which changes the same files: a.txt"}' > "$T/$CASE/cards/$k.live"
  done
  s=$(loop snapshot --fresh) || fail "snapshot failed"
  [ "$(jq -c '[.belt[] | select(.card | IN("c2-9", "c3-10")) | [.card, .step, .waitsOn.issue, .waitsOn.state]]' <<<"$s")" = '[["c2-9","waiting",7,"queued"],["c3-10","waiting",9,"brief"]]' ] \
    || fail "a waiting card's step is not waiting, or does not say what it waits on: $(jq -c '[.belt[] | {card, step, waitsOn}]' <<<"$s")"
  [ "$(loop health | jq -c '[.stuck[] | [.card, .step, .waitsOn]]')" = '[["c2-9","waiting",{"card":"c1-7","issue":7,"state":"queued"}]]' ] \
    || fail "a long wait on a card not on the belt is not stuck, or one on a card on the belt is: $(loop health | jq -c .stuck)"
  # A waiter whose own output is stale is stuck as waiting, never as the landing it waits to begin.
  jq -cn --arg t "$ago" '{card:"c3-10",issue:10,step:"start",time:$t,tokens:{claude:0,codex:0},result:"ok",sha:"",reason:"",of:"land"}' >> "$ST/cards.jsonl"
  jq -c --arg t "$ago" '.last = $t' "$T/$CASE/cards/c3-10.live" > "$T/$CASE/cards/c3-10.live.new" && mv "$T/$CASE/cards/c3-10.live.new" "$T/$CASE/cards/c3-10.live"
  [ "$(loop health | jq -c '[.stuck[] | select(.card == "c3-10") | [.step, .waitsOn]]')" = '[["waiting",{"card":"c2-9","issue":9,"state":"land"}]]' ] \
    || fail "a stale waiter is stuck in another step: $(loop health | jq -c .stuck)"
}

# Bug: a card waiting at its claim for a same-file card was reported stuck after STUCK seconds with no new step, its
# live record brought up to date every poll; waiting is normal. A card waiting there 25 minutes on a live holder (past
# STUCK, within the limit on all its waits, waitLimitMin: tests/health.test.sh) is not
# stuck and shows as waiting on that card; a silent card with no wait is stuck, as before, and so is one whose only
# fresh wait record is from another step; and once the holder's process is gone the wait never ends, so the waiter is
# stuck too.
t_waitclaim() {
  setup "[$(issue 7 2026-01-01),$(issue 8 2026-01-02),$(issue 9 2026-01-03),$(issue 10 2026-01-04)]"; mkdir -p "$T/$CASE/cards"
  sleep 300 & holder=$!; sleep 300 & waiter=$! # sleep: stand-ins for two cards' processes, alive
  now=$(jq -rn 'now | todate'); ago25=$(jq -rn 'now - 1500 | todate'); ago20=$(jq -rn 'now - 1200 | todate')
  line() { # <card> <issue> <step> <time> <extra json>
    jq -cn --arg c "$1" --argjson n "$2" --arg s "$3" --arg t "$4" --argjson x "$5" \
      '{card:$c,issue:$n,step:$s,time:$t,tokens:{claude:0,codex:0},result:"ok",sha:"",reason:""} + $x' >> "$ST/cards.jsonl"
  }
  for c in "c1-7,7,$holder,$now" "c2-8,8,$waiter,$ago25" "c3-9,9,$waiter,$ago20" "c4-10,10,$waiter,$ago25"; do
    IFS=, read -r k n p t <<<"$c"
    line "$k" "$n" picked "$t" '{"title":"t","created":"2026-01-01T00:00:00Z"}'
    line "$k" "$n" worktree "$t" "$(jq -cn --argjson p "$p" --arg s "$(. "$SRC/lib/portable.sh"; p_started "$p")" '{pid:$p,started:$s}')"
  done
  line c1-7 7 start "$now" '{"of":"review"}'; line c2-8 8 start "$ago25" '{"of":"land"}'; line c3-9 9 start "$ago20" '{"of":"build"}'
  line c4-10 10 start "$ago25" '{"of":"build"}'
  for k in c2-8 c4-10; do # c4-10's fresh wait record is from a step it is not running: no output from its build.
    jq -cn --arg at "$ago25" --arg t "$now" '{step: "land", at: $at, last: $t, turns: 0, waits: {on: "c1-7", paths: ["a.txt"]},
      action: "waiting on card c1-7, which changes the same files: a.txt"}' > "$T/$CASE/cards/$k.live"
  done
  h=$(loop health) || fail "health failed: $h"
  [ "$(jq -c '[.stuck[].card] | sort' <<<"$h")" = '["c3-9","c4-10"]' ] \
    || fail "a card waiting at its claim on a live holder is stuck, or a silent card is not: $(jq -c .stuck <<<"$h")"
  [ "$(jq -c --arg a "$ago25" '.waitingOnCard == [{card: "c2-8", issue: 8, since: $a, waitsOn: {card: "c1-7", issue: 7, state: "review"}}]' <<<"$h")" = true ] \
    || fail "health does not show the card waiting on its holder: $(jq -c .waitingOnCard <<<"$h")"
  s=$(loop snapshot --fresh) || fail "snapshot failed"
  [ "$(jq -c '[.belt[] | select(.card == "c2-8") | [.step, .waitsOn.card, .waitsOn.issue]]' <<<"$s")" = '[["waiting","c1-7",7]]' ] \
    || fail "the Board does not show the card waiting on its holder: $(jq -c '[.belt[] | {card, step, waitsOn}]' <<<"$s")"
  # The holder's process is gone: the wait never ends, so the waiter is stuck, as waiting since its wait began.
  kill $holder; wait $holder 2>/dev/null
  h=$(loop health) || fail "health failed: $h"
  [ "$(jq -c '[.stuck[] | [.card, .step]] | sort | map(select(.[0] != "c4-10"))' <<<"$h")" = '[["c1-7","review"],["c2-8","waiting"],["c3-9","build"]]' ] \
    && [ "$(jq -r '.stuck[] | select(.card == "c2-8") | .since' <<<"$h")" = "$ago25" ] \
    || fail "a card waiting on a holder whose process is gone is not stuck since its wait began: $(jq -c .stuck <<<"$h")"
  kill $waiter; wait $waiter 2>/dev/null; :
}
