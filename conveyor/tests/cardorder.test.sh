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

# Bug it catches: a card's place in `order` was its own id alone, so ordering an umbrella issue did not move its split
# parts: a part waited behind every older card. With `order` [9], ten older cards, then P (a split part of #9, parent
# 9) and Q (a follow-up of #20, whose umbrella is #9), the picks are P, Q, then the oldest unordered card.
t_cardorderumb() {
  setup "$(jq -cs . <(issue 9 2026-01-01) <(issue 20 2026-01-01 | jq -c '.umbrella = 9'))"; mkdir -p "$ST/testactions"
  local p=c20261101T000100-x-0 q=c20261101T000101-x-0
  jq -cn --arg p "$p" --arg q "$q" '{cards: ([range(10) | {file: null, title: "old \(.)", body: "Do it.", time: "2026-11-01T00:00:0\(.)Z", id: "c20261101T00000\(.)-x-0", card: null}]
    + [{file: null, title: "p", body: "Do p.", time: "2026-11-01T00:01:00Z", id: $p, card: null, parent: 9},
       {file: null, title: "q", body: "Do q.", time: "2026-11-01T00:01:01Z", id: $q, card: null, parent: 20}])}' > "$ST/testactions/cards.json"
  # The umbrella stays open and held while its parts are built.
  loop control hold 9 > /dev/null && loop control order 9 > /dev/null || fail "control hold 9 or control order 9 was refused"
  [ "$(loop control | jq -c .order)" = '[9]' ] || fail "control order 9 did not store [9]: $(loop control | jq -c .order)"
  fx_in 'for i in 1 2 3; do p=$(locked pick "" "" "$(cat "$STUB/issues.json")") || exit 1; echo "pick $i: $p"; done'
  [ "$RC" = 0 ] && [ "$(grep '^pick ' "$T/$CASE/run.out")" = "pick 1: $p 0 false"$'\n'"pick 2: $q 0 false"$'\n''pick 3: c20261101T000000-x-0 0 false' ] \
    || fail "with order [9], the split part $p of #9 and the follow-up $q of #20 (umbrella #9) were not picked first, before the ten older cards: $(cat "$T/$CASE/run.out")"
}

# Bug it catches: an ordered issue went after every ordered card, or the unordered cards went before an ordered one:
# `order` [5, C] must start #5, then C, then the older unordered cards A and B.
t_cardordermix() {
  setup "$(jq -cs . <(issue 5 2026-01-01 P1))"; mkdir -p "$ST/testactions"
  local a=c20261101T000000-x-0 b=c20261101T000001-x-0 c=c20261101T000002-x-0
  jq -cn --arg a "$a" --arg b "$b" --arg c "$c" '{cards: [
    {file: null, title: "a", body: "Do a.", time: "2026-11-01T00:00:00Z", id: $a, card: null},
    {file: null, title: "b", body: "Do b.", time: "2026-11-01T00:00:01Z", id: $b, card: null},
    {file: null, title: "c", body: "Do c.", time: "2026-11-01T00:00:02Z", id: $c, card: null}]}' > "$ST/testactions/cards.json"
  loop control order 5 "$c" > /dev/null || fail "control order 5 $c was refused"
  fx_in 'for i in 1 2 3 4; do p=$(locked pick "" "" "$(cat "$STUB/issues.json")") || exit 1; echo "pick $i: $p"; done'
  [ "$RC" = 0 ] && [[ $(grep '^pick ' "$T/$CASE/run.out") == "pick 1: c"*"-5 5 false"$'\n'"pick 2: $c 0 false"$'\n'"pick 3: $a 0 false"$'\n'"pick 4: $b 0 false" ]] \
    || fail "with order [5, $c], the picks were not #5, $c, $a, $b: $(cat "$T/$CASE/run.out")"
}

# Bug it catches: the order [C, 5] read as "an ordered issue goes first": card C is placed before #5, so it starts first.
t_cardordermixc() {
  setup "$(jq -cs . <(issue 5 2026-01-01 P1))"; mkdir -p "$ST/testactions"
  local c=c20261101T000002-x-0
  jq -cn --arg c "$c" '{cards: [{file: null, title: "c", body: "Do c.", time: "2026-11-01T00:00:02Z", id: $c, card: null}]}' > "$ST/testactions/cards.json"
  loop control order "$c" 5 > /dev/null || fail "control order $c 5 was refused"
  fx_in 'locked pick "" "" "$(cat "$STUB/issues.json")"'
  [ "$RC" = 0 ] && [ "$(grep -v '^conveyor:' "$T/$CASE/run.out")" = "$c 0 false" ] || fail "with order [$c, 5], the pick was not $c: $(cat "$T/$CASE/run.out")"
}

# Bug it catches: pick() took the first ready issue's place from the order it read before adopt() took the closed
# issues out of it, and testpick() compared that old place with the new order's. With order [2, 3, 5, C] and #2 and #3
# closed, adopt() in the same pick saves [5, C]: the old place of #5 (2) let C (1 in the new order) start before #5.
t_cardorderadopt() {
  setup "$(jq -cs . <(issue 5 2026-01-01 P1))"; mkdir -p "$ST/testactions"
  local c=c20261101T000002-x-0
  jq -cn --arg c "$c" '{cards: [{file: null, title: "c", body: "Do c.", time: "2026-11-01T00:00:02Z", id: $c, card: null}]}' > "$ST/testactions/cards.json"
  loop control order 2 3 5 "$c" > /dev/null || fail "control order 2 3 5 $c was refused"
  fx_in 'locked pick "" "" "$(cat "$STUB/issues.json")"'
  [ "$(loop control | jq -c .order)" = "[5,\"$c\"]" ] || fail "the pick's adopt() did not take the closed #2 and #3 out of the order: $(loop control | jq -c .order)"
  [ "$RC" = 0 ] && [[ $(grep -v '^conveyor:' "$T/$CASE/run.out") == c*-5\ 5\ false ]] || fail "with order [2, 3, 5, $c] and #2 and #3 closed, the pick was not #5: $(cat "$T/$CASE/run.out")"
}

# Bug it catches: a card that more than one pin matches took the place of its own id, not the first place of any of
# them. With order [9, 5, P], P a split part of the held umbrella #9 and #5 ready, P is placed at 0 by #9, so it starts
# before #5; a rule that took P's id first would place it at 2 and start #5.
t_cardorderfirst() {
  setup "$(jq -cs . <(issue 9 2026-01-01) <(issue 5 2026-01-01 P1))"; mkdir -p "$ST/testactions"
  local p=c20261101T000100-x-0
  jq -cn --arg p "$p" '{cards: [{file: null, title: "p", body: "Do p.", time: "2026-11-01T00:01:00Z", id: $p, card: null, parent: 9}]}' > "$ST/testactions/cards.json"
  loop control hold 9 > /dev/null && loop control order 9 5 "$p" > /dev/null || fail "control hold 9 or control order 9 5 $p was refused"
  fx_in 'locked pick "" "" "$(cat "$STUB/issues.json")"'
  [ "$RC" = 0 ] && [ "$(grep -v '^conveyor:' "$T/$CASE/run.out")" = "$p 0 false" ] || fail "with order [9, 5, $p], #9 held and $p a part of #9, the pick was not $p: $(cat "$T/$CASE/run.out")"
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
