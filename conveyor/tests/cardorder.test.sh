#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 120
# Engine cases: card ids in the control record's order (`control order`, lib/control.sh), and the pick of the cards with
# no GitHub issue by them (testpick(), lib/testaction.sh).
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"

# Bugs it catches: testpick() took the cards with no issue oldest first and never read `order`, so a card the owner put
# first waited behind every older one; or an ordered card went past a hold; or the pinned cards went first but in record
# order, not in the order's. Four ready-or-held cards, A oldest: issue 12, D (held), C and B are in the order, in that
# order. The picks are C then B (pinned, by their place, though B is older), then A, unpinned; D, held, never.
# Bug it catches too: the control record check took an order of issue numbers or of card ids, and refused one that
# holds both, so an issue and a card could not be pinned together.
t_cardorder() {
  setup '[]'; mkdir -p "$ST/testactions"
  local out a=c20261101T000000-x-0 b=c20261101T000001-x-0 c=c20261101T000002-x-0 d=c20261101T000003-x-0
  jq -cn --arg a "$a" --arg b "$b" --arg c "$c" --arg d "$d" '{cards: [
    {file: null, title: "a", body: "Do a.", time: "2026-11-01T00:00:00Z", id: $a, card: null},
    {file: null, title: "b", body: "Do b.", time: "2026-11-01T00:00:01Z", id: $b, card: null},
    {file: null, title: "c", body: "Do c.", time: "2026-11-01T00:00:02Z", id: $c, card: null},
    {file: null, title: "d", body: "Do d.", time: "2026-11-01T00:00:03Z", id: $d, card: null, held: true}]}' > "$ST/testactions/cards.json"
  out=$(loop control order 12 "$d" "$c" "$b" 2>&1) || fail "control order 12 $d $c $b was refused: $out"
  [ "$(loop control | jq -c .order)" = "[12,\"$d\",\"$c\",\"$b\"]" ] || fail "control order 12 $d $c $b did not store the issue and the three card ids: $(loop control | jq -c .order)"
  fx_in 'for i in 1 2 3 4; do p=$(locked pick "" "" "[]") || exit 1; echo "pick $i: $p"; done'
  # The pick lines alone: the first pick also logs once why the release limit is off (rellimit(), lib/pick.sh).
  [ "$RC" = 0 ] && [ "$(grep '^pick ' "$T/$CASE/run.out")" = "pick 1: $c 0 false"$'\n'"pick 2: $b 0 false"$'\n'"pick 3: $a 0 false"$'\n''pick 4: ' ] \
    || fail "with order [12, $d (held), $c, $b], the picks were not $c, $b, $a and then none: $(cat "$T/$CASE/run.out")"
  # Bug it catches: `control unpin` took issue numbers alone, so a pinned card id could not be taken out by itself.
  out=$(loop control unpin "$b" 2>&1) && [ "$(loop control | jq -c .order)" = "[12,\"$d\",\"$c\"]" ] || fail "control unpin $b did not leave the order [12, $d, $c]: $out $(loop control | jq -c .order)"
}

# Bug it catches: `control order` took a word that is neither an issue number nor a card id, or stored part of the list
# before it refused. `control order 12 cfoo` is refused naming cfoo, and the record keeps its order as it was.
t_cardorderbad() {
  setup '[]'
  loop control order 7 > /dev/null || fail "control order 7 was refused"
  local before out rc=0; before=$(cat "$ST/control.json")
  out=$(loop control order 12 cfoo 2>&1) || rc=$?
  [ "$rc" != 0 ] && [[ $out == *'"cfoo" is not an issue number or a card id'* ]] || fail "control order 12 cfoo was not refused naming cfoo (exit $rc): $out"
  [ "$(cat "$ST/control.json")" = "$before" ] || fail "control order 12 cfoo changed the control record: $(cat "$ST/control.json")"
}
