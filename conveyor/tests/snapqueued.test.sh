#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 300
# Engine cases: the snapshot's queue.cards, the cards with no GitHub issue that wait to be picked (TCQUEUE,
# lib/snapshot.sh). Their records are written here as followups(), splitcards() and cardnew() write them.
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"
# The engine folder, as lib.sh sets it: named here too, so the release closure (tools/closure.sh) follows watch.py.
SRC=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)

# Bug it catches (#1714): the snapshot held no queued card with no GitHub issue, so the Board showed none of them. Each
# is listed in the record's order with its kind, level and filing time; a held one says so, one that waits names what it
# waits on (an open issue, a parent card not landed), and one a Never build label skips names the label. The first
# listed card that nothing keeps back is the one pick takes. A record that is missing or does not read gives null,
# never an empty list, which would say no card waits.
t_sqcards() {
  setup '[{"number":7,"title":"Open","body":"","labels":[],"createdAt":"2026-11-01T00:00:00Z"}]'
  local out p=c20261101T000000-sample-3
  [ "$(loop snapshot --fresh | jq -c .queue.cards)" = null ] || fail "with no record of the cards with no GitHub issue, queue.cards is not null"
  loop control rules area:infra=off > /dev/null || fail "control rules area:infra=off was refused"
  mkdir -p "$ST/testactions"
  jq -cn --arg p "$p" '{cards: [
    {id: "c20261102T000001-sample-0", card: null, title: "Held one", time: "2026-11-02T00:00:01Z", body: "b", held: true, label: "Foreman order"},
    {id: "c20261102T000002-sample-0", card: null, title: "Waits on a card", time: "2026-11-02T00:00:02Z", body: "b\nDepends on: \($p)", label: "Review follow-up of #3", labels: ["P1"]},
    {id: "c20261102T000003-sample-0", card: null, title: "Waits on an issue", time: "2026-11-02T00:00:03Z", body: "Depends on: #7", label: "Split part of #2"},
    {id: "c20261102T000004-sample-0", card: null, title: "Skipped", time: "2026-11-02T00:00:04Z", body: "b", label: "Docs sweep: area:infra", labels: ["area:infra"]},
    {id: "c20261102T000005-sample-0", card: null, title: "Ready", time: "2026-11-02T00:00:05Z", body: "b", file: "f.test.sh"}]}' > "$ST/testactions/cards.json"
  out=$(loop snapshot --fresh) || fail "no snapshot"
  [ "$(jq -c '.queue.cards | map([.title, .kind, .held, .waitsFor, .rule])' <<<"$out")" = '[["Held one","Foreman order",true,[],null],["Waits on a card","Review follow-up of #3",false,[3],null],["Waits on an issue","Split part of #2",false,[7],null],["Skipped","Docs sweep: area:infra",false,[],"area:infra"],["Ready","Tests page",false,[],null]]' ] \
    || fail "queue.cards does not say what each waiting card is: $(jq -c .queue.cards <<<"$out")"
  [ "$(jq -c '.queue.cards[1] | [.card, .priority, .created]' <<<"$out")" = '["c20261102T000002-sample-0","P1","2026-11-02T00:00:02Z"]' ] \
    || fail "queue.cards does not give a card's id, level and filing time: $(jq -c '.queue.cards[1]' <<<"$out")"
  # #1813: the Foreman's wake for a card waiting on a red main names a held card by its test file, read here.
  [ "$(jq -c '.queue.cards | map(.file)' <<<"$out")" = '[null,null,null,null,"f.test.sh"]' ] \
    || fail "queue.cards does not give a Tests page card's test file (and null for the others): $(jq -c '.queue.cards | map(.file)' <<<"$out")"
  fx_in 'locked pick "" "" "$(cat "$STUB/issues.json")"'
  [ "$(cat "$T/$CASE/run.out")" = 'c20261102T000005-sample-0 0 false' ] || fail "pick did not take the one card queue.cards shows as ready: $(cat "$T/$CASE/run.out")"
  [ "$(loop snapshot --fresh | jq -c '.queue.cards | map(.title)')" = '["Held one","Waits on a card","Waits on an issue","Skipped"]' ] \
    || fail "a card pick took is still listed as waiting: $(loop snapshot --fresh | jq -c .queue.cards)"
  echo 'not json' > "$ST/testactions/cards.json"
  [ "$(loop snapshot --fresh | jq -c .queue.cards)" = null ] || fail "with a record that does not read, queue.cards is not null"
}

# Bug it catches: the Board placed a card in Next up by its own id alone, so a split part of an ordered umbrella showed
# behind older cards while pick took it first. queue.cards gives each card its pins: its id and cards given back, its
# parent issue #20 and its umbrella #9 (#20 is a GitHub sub-issue of #9).
t_sqpins() {
  setup '[{"number":9,"title":"U","body":"","labels":[],"createdAt":"2026-11-01T00:00:00Z"},
    {"number":20,"title":"P","body":"","labels":[],"createdAt":"2026-11-01T00:00:00Z"}]'
  echo '9 20' > "$STUB/subs"; mkdir -p "$ST/testactions"
  jq -cn '{cards: [{id: "c20261102T000001-sample-0", card: null, title: "a", time: "2026-11-02T00:00:01Z", body: "b", was: ["c20261101T000001-sample-0"]},
    {id: "c20261102T000002-sample-0", card: null, title: "b", time: "2026-11-02T00:00:02Z", body: "b", parent: 20}]}' > "$ST/testactions/cards.json"
  local out; out=$(loop snapshot --fresh) || fail "no snapshot"
  [ "$(jq -c '.queue.cards | map(.pins)' <<<"$out")" = '[["c20261101T000001-sample-0","c20261102T000001-sample-0"],[9,20,"c20261102T000002-sample-0"]]' ] \
    || fail "queue.cards does not give each card its pins (id, was, parent, umbrellas): $(jq -c '.queue.cards | map(.pins)' <<<"$out")"
}

# Bugs it catches (#1714): a card still shown as waiting for an issue of another repository after it closed, when no
# open issue names that one (its state was read only from the open issues); the state not kept in the stream's GitHub
# folder, or a change of it not seen by the stream; and, with the open issues not listed, a card that waits on one shown
# as ready.
t_sqfar() {
  setup '[]'
  mkdir -p "$ST/testactions" "$T/$CASE/gh"
  jq -cn '{cards: [{id: "c20261102T000001-sample-0", card: null, title: "Far", time: "2026-11-02T00:00:01Z", body: "Depends on: other/repo#600\nDepends on: #7", label: "Foreman order"}]}' > "$ST/testactions/cards.json"
  waits() { loop snapshot --fresh | jq -c '.queue.cards[0].waitsFor'; }
  echo OPEN > "$STUB/repo.other_repo.600"
  [ "$(waits)" = '["other/repo#600"]' ] || fail "with other/repo#600 open and #7 closed, the card does not wait on other/repo#600 alone: $(waits)"
  echo CLOSED > "$STUB/repo.other_repo.600"
  [ "$(waits)" = '[]' ] || fail "with other/repo#600 closed, named by no open issue, the card still waits: $(waits)"
  loop github "$T/$CASE/gh" || fail "conveyor.sh github failed"
  [ "$(jq -c . "$T/$CASE/gh/cardfar")" = '{"other/repo#600":{"open":false}}' ] || fail "the GitHub folder does not keep the state of other/repo#600: $(ls "$T/$CASE/gh"; cat "$T/$CASE/gh/cardfar")"
  python3 -I -c 'import sys, types; sys.path.insert(0, sys.argv[1]); import watch
sys.exit(0 if watch.Stream.github_files(types.SimpleNamespace(github=sys.argv[2])).get("cardfar") else 1)' "$SRC" "$T/$CASE/gh" \
    || fail "the stream does not look at cardfar, so a change of it sends no snapshot"
  echo 'exit 1' > "$STUB/list-cmd" # the gh stub sources it before it lists the open issues
  [ "$(loop snapshot --fresh | jq -c '[.queue.order, .queue.cards[0].waitsFor]')" = '[null,[7]]' ] \
    || fail "with the open issues not listed, the card that depends on #7 is not shown as waiting on it: $(loop snapshot --fresh | jq -c .queue)"
}
