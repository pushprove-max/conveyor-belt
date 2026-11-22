#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 300
# Engine cases: the Tests page's cards with no GitHub issue (#1330). With the control record's rule Tests page issues
# off (rules.testissues), `testissue` files no issue and queues a card (testcard(), lib/testaction.sh), which the loop
# picks ahead of the queue (testpick()) and the Board shows by its test file and title. The card is held to the check
# of its action (lib/speedproof.sh) and lands naming and closing no issue.
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"

# The helpers are named tc*: every case file is sourced into one shell, so a name another file uses would replace its.
# A case folder with no open issue and the rule off. Main holds f.test.sh (`echo slow`, its median on record 10 CPU s)
# and g.test.sh (`echo other`), pushed. Each run under cards/mainrun/ runs the file test.fileCommand names
# (CONVEYOR_TEST_FILE), names its cases one and two as passed, and times it at the CPU seconds $STUB/cpu-<file> holds
# (1 with none). A run with no case selected (the split check's start-up run, speedproof.sh splitstart()) gives no
# CPU seconds, so the pack's test.splitAllowance, 1, counts.
tcsetup() {
  setup '[]'
  local c; for c in 9 10 11; do
    jq -cn --argjson c "$c" '{time: "2026-11-01T00:00:00Z", how: "full", sha: "abc", files: {"f.test.sh": {result: "ok", sec: $c, cpu: $c}}}' >> "$ST/suiteruns.jsonl"
  done
  echo 'echo slow' > "$R/f.test.sh"; echo 'echo other' > "$R/g.test.sh"
  git -C "$R" add f.test.sh g.test.sh && git -C "$R" commit -qm 'two tests' && git -C "$R" push -q origin main || fail "main's files"
  cat > "$STUB/mainrun-cmd" <<'EOF'
f=${CONVEYOR_TEST_FILE:-}; [ -n "$f" ] || exit 0
! awk -F '\t' -v f="$f" '$1 == "fail" && $2 == f && $3 != "" { e = 1 } END { exit !e }' "${CONVEYOR_TEST_RERUN:-/dev/null}" || exit 0
printf '== %s\nok one\nok two\n' "$f"
printf '== %s\n-- ok %s\nTESTRUN sec\t%s\t1\t%s\n' "$f" "$f" "$f" "$(cat "$STUB/cpu-$f" 2>/dev/null || echo 1)" >> "$CONVEYOR_TEST_LOG/r"
EOF
  loop control rules testissues=off > /dev/null || fail "control rules testissues=off was refused"
  [ "$(loop control | jq -c .rules.testissues)" = false ] || fail "control rules testissues=off did not set the rule off: $(loop control | jq -c .rules)"
}
# `testissue <file> <title> <body>` as the Board's Tests page sends it; its output in $TCOUT, and nothing filed.
tcask() {
  TCOUT=$(loop testissue "$1" "$2" "$3" 2>&1) || fail "testissue $1 \"$2\" with the rule off failed: $TCOUT"
  [ "$TCOUT" = "Card queued with no GitHub issue: $2" ] || fail "testissue $1 \"$2\" with the rule off does not say its card is queued: $TCOUT"
  [ ! -e "$STUB/filed" ] || fail "testissue $1 \"$2\" with the rule off filed a GitHub issue: $(cat "$STUB/filed")"
}

# D1. Bugs it catches: with the rule off, an Optimize, a Split or a Fix the failures action filed a GitHub issue all the
# same; its card was never picked; or the belt showed it as "#0", with no title or test file. Each is queued with no
# issue, picked ahead of the queue as a card of issue 0, and on the belt as "Tests page: <file>" with the action's title;
# what stands in for its issue is labelled as the issue would be, so card() holds it to its action's check.
t_tcqueue() {
  tcsetup; local out c f t
  tcask f.test.sh 'Optimize the test file f.test.sh' 'Make it cheaper.'
  tcask g.test.sh 'Split the test file g.test.sh' 'Split it in two.'
  tcask f.test.sh 'Fix the failures of the test file f.test.sh' 'Make it pass every time.'
  fx_in 'for i in 1 2 3 4; do p=$(locked pick "" "" "[]") || exit 1; echo "pick $i: $p"; done'
  [ "$RC" = 0 ] || fail "the picks failed: $(cat "$T/$CASE/run.out")"
  [ "$(grep -cE '^pick [123]: c[0-9T]+-.*-0 0 false$' "$T/$CASE/run.out")" = 3 ] && grep -qx 'pick 4: ' "$T/$CASE/run.out" \
    || fail "the three cards were not each picked once as cards of issue 0: $(cat "$T/$CASE/run.out")"
  [ "$(st 'select(.step == "picked") | [.issue, .title, .testFile] | @json' | jq -sc .)" = '[[0,"Optimize the test file f.test.sh","f.test.sh"],[0,"Split the test file g.test.sh","g.test.sh"],[0,"Fix the failures of the test file f.test.sh","f.test.sh"]]' ] \
    || fail "the picked lines do not name each card's title and test file, oldest first: $(st 'select(.step == "picked")')"
  out=$(loop snapshot --fresh) || fail "no snapshot"
  while IFS=$'\t' read -r c f t; do
    [ "$(jq -c --arg c "$c" '.belt[] | select(.card == $c) | [.issue, .name, .title]' <<<"$out")" = "$(jq -cn --arg f "$f" --arg t "$t" '[0, "Tests page: \($f)", $t]')" ] \
      || fail "the belt does not show card $c of \"$t\" by its test file and title: $(jq -c .belt <<<"$out")"
    fx_in 'i=$(testcardissue '"$c"') && jq -c "[.number, .title, .body, (.labels | map(.name))]" <<<"$i"; speedfile "$i" "$OPTIMIZE" || speedfile "$i" "$SPLIT" || speedfile "$i" "$FIXFAILS"'
    [ "$(sed -n 2p "$T/$CASE/run.out")" = "$f" ] && [ "$(head -n 1 "$T/$CASE/run.out" | jq -c '[.[0], .[1], (.[3])]')" = "$(jq -cn --arg t "$t" '[0, $t, ["bug", "P2"]]')" ] \
      || fail "the issue that stands in for card $c of \"$t\" is not labelled as its issue would be, or does not name its file $f: $(cat "$T/$CASE/run.out")"
  done < <(st 'select(.step == "picked") | [.card, .testFile, .title] | @tsv')
}

# D2 (the rule on) is in testaction.test.sh t_taissue. Bugs it catches: with the rule off, the Board's action was
# refused on a project whose new issues start held, though the owner asked for the card on the Board; or one asked for
# a Foreman session (`foreman.sh ask <project> testissue`, which sets CONVEYOR_FOREMAN=1) started a card the owner had
# not said yes to, or was refused, so the Foreman could not file the held issue docs/foreman.md promises: it files the
# issue and holds it, as with the rule on, and queues no card.
t_tcheld() {
  tcsetup; local out
  loop control start held > /dev/null 2>&1 || fail "start held was refused"
  tcask f.test.sh 'Optimize the test file f.test.sh' 'Make it cheaper.'
  out=$(CONVEYOR_FOREMAN=1 loop testissue g.test.sh 'Optimize the test file g.test.sh' 'Make it cheaper.' 2> "$STUB/ti.err") \
    || fail "testissue g.test.sh 'Optimize the test file g.test.sh' with the rule off for a Foreman session failed: $out $(cat "$STUB/ti.err")"
  [ "$out" = https://github.com/o/r/issues/100101 ] && [ "$(jq -c '[.title, (.labels | map(.name))]' "$STUB/filed")" = '["Optimize the test file g.test.sh",["bug","P2"]]' ] \
    || fail "testissue g.test.sh with the rule off for a Foreman session did not file its issue: $out $(cat "$STUB/filed" 2>&1)"
  [ "$(loop control | jq -c .held)" = '[100101]' ] && grep -qF '#100101 is held, as it was filed for a Foreman session' "$STUB/ti.err" \
    || fail "testissue g.test.sh with the rule off for a Foreman session did not hold #100101 and say so: $(loop control | jq -c .held) $(cat "$STUB/ti.err")"
  [ "$(jq -c '[.cards[].file]' "$ST/testactions/cards.json")" = '["f.test.sh"]' ] \
    || fail "testissue g.test.sh for a Foreman session queued a card with no issue: $(cat "$ST/testactions/cards.json")"
}

# Bugs it catches: Needs you's Retry and Close of a blocked Tests page card, which send its card id as for a main-red
# fix card, were refused (retry and shut took a card of issue 0 only as a main-red fix card or a branch's), so the card
# stayed in Needs you; `retry 0` named no blocked Tests page card; and a card given back was not picked again, as its
# entry still named it. Close (shut) ends it
# closed and its action starts no card; Retry then gives it back, and the next pick takes the same action as a new
# card of issue 0, by its title and test file.
t_tcretry() {
  setup '[]'; local c c2 out
  mkdir -p "$ST/testactions"
  jq -cn '{cards: [{file: "f.test.sh", title: "Split the test file f.test.sh", body: "Split it.", time: "2026-11-01T00:00:00Z", card: null}]}' > "$ST/testactions/cards.json"
  fx_in 'c=$(locked pick "" "" "[]") && c=${c%% *} && echo "$c" && append "$(line "$c" 0 blocked ok "{\"reason\":\"build: it failed\"}")"'
  c=$(head -n 1 "$T/$CASE/run.out")
  [ "$RC" = 0 ] && [[ $c == c*-0 ]] || fail "the Tests page card was not picked and blocked: $(cat "$T/$CASE/run.out")"
  # `retry 0` names it among the blocked cards of no issue, by the name the Board shows it by.
  out=$(loop retry 0 2>&1); grep -qF "blocked now: $c (Tests page: f.test.sh)" <<<"$out" || fail "retry 0 does not name the blocked Tests page card $c: $out"
  out=$(loop shut "$c" 2>&1) && [ "$(st "select(.card == \"$c\") | .step" | tail -n 1)" = closed ] \
    || fail "shut $c did not close the blocked Tests page card by its card id: $out"
  fx_in 'locked pick "" "" "[]"'
  [ "$RC" = 0 ] && [ ! -s "$T/$CASE/run.out" ] || fail "after shut $c, the next pick took its action again: $(cat "$T/$CASE/run.out")"
  out=$(loop retry "$c" 2>&1) && [ -z "$(st "select(.card == \"$c\")")" ] || fail "retry $c did not give back the shut Tests page card by its card id: $out"
  fx_in 'locked pick "" "" "[]"'
  c2=$(cut -d ' ' -f 1 "$T/$CASE/run.out")
  [ "$RC" = 0 ] && [[ $c2 == c*-0 && $c2 != "$c" ]] && [ "$(st "select(.card == \"$c2\" and .step == \"picked\") | [.issue, .title, .testFile] | @json")" = '[0,"Split the test file f.test.sh","f.test.sh"]' ] \
    || fail "after retry $c, the next pick did not take the Split action again as a new card: $(cat "$T/$CASE/run.out") $(st 'select(.step == "picked")')"
}

# Bug it catches: the record of the Tests page's cards kept only its newest 200 cards, so a card the Tests page had
# said was queued was dropped before the loop picked it. The record holds one card not picked yet, the oldest, and 201
# picked ones; a new card drops only the oldest picked one.
t_tctrim() {
  setup '[]'; mkdir -p "$ST/testactions"
  jq -cn '{cards: ([{file: "p.test.sh", title: "Optimize the test file p.test.sh", body: "b", time: "2026-11-01T00:00:00Z", card: null}]
    + [range(1; 202) | {file: "d.test.sh", title: "t", body: "b", time: "2026-11-01T00:00:00Z", card: "c\(.)"}])}' > "$ST/testactions/cards.json"
  fx_in 'testcard n.test.sh "Optimize the test file n.test.sh" "Make it cheaper."'
  [ "$RC" = 0 ] || fail "testcard n.test.sh failed: $(cat "$T/$CASE/run.out")"
  [ "$(jq -c '[(.cards | length), .cards[0].file, .cards[1].card, .cards[-2].card, .cards[-1].file, .cards[-1].card]' "$ST/testactions/cards.json")" = '[202,"p.test.sh","c2","c201","n.test.sh",null]' ] \
    || fail "testcard n.test.sh with a card not picked and 201 picked ones did not keep each card not picked and drop only the oldest picked: $(jq -c '[.cards[] | [.file, .card]] | .[:3] + .[-3:]' "$ST/testactions/cards.json")"
}

# D1, landing. Bugs it catches: a card with no issue landed under "Closes #0", or its landing or push asked GitHub to
# close an issue; or the Tests page lost its result, as its Optimize history was read from GitHub filings only, so
# f.test.sh, which it deleted, stayed in the table. The Optimize card deletes f.test.sh and its review names the test
# of each case.
t_tcland() {
  tcsetup; local c msg out
  echo 'rm f.test.sh' > "$STUB/build"; printf '%s\n' 'COVERED-BY: g.test.sh: one' 'COVERED-BY: g.test.sh: two' "$GO" > "$STUB/review.1"
  tcask f.test.sh 'Optimize the test file f.test.sh' 'Make it cheaper.'
  # loop: only a whole card shows that it is picked, built, checked, reviewed, landed and pushed with no issue.
  loop run > /dev/null || fail "run exited non-zero: $(st 'select(.step | IN("blocked", "landed"))')"
  c=$(st 'select(.step == "landed") | .card')
  [ -n "$c" ] && [ "$(st 'select(.step == "landed") | .issue')" = 0 ] || fail "the Optimize card with no issue did not land: $(st 'select(.step | IN("picked", "blocked", "landed"))')"
  # Its picked line, with its test file, is a whole record: the record check set none aside.
  [ "$(st 'select(.step == "picked") | [.card, .testFile] | @tsv')" = "$c"$'\t'f.test.sh ] && [ ! -s "$ST/quarantined.jsonl" ] \
    || fail "card $c's picked line does not name its test file, or a line was set aside: $(st 'select(.step == "picked")') $(cat "$ST/quarantined.jsonl" 2>&1)"
  msg=$(git -C "$R" log -1 --format=%B "$(st 'select(.step == "landed") | .sha')")
  [ "$(head -n 1 <<<"$msg")" = 'fix(product): Optimize the test file f.test.sh' ] && ! grep -qE 'Closes|#0' <<<"$msg" && grep -qx "Conveyor card $c" <<<"$msg" \
    || fail "the landed commit of card $c names or closes an issue: $msg"
  [ ! -e "$STUB/closed" ] && [ ! -e "$STUB/filed" ] && [ -z "$(st 'select(.step == "issue")')" ] \
    || fail "card $c of no issue filed or closed an issue: $(cat "$STUB/filed" "$STUB/closed" 2>&1) $(st 'select(.step == "issue")')"
  out=$(loop snapshot --fresh) || fail "no snapshot"
  [ "$(jq -c '.tests.files[] | select(.file == "f.test.sh") | [.removed, (.optimize | map([.issue, .card, .name, .state, .fix, .into]))]' <<<"$out")" = "[true,[[null,\"$c\",\"No issue\",\"landed\",\"deleted\",[\"g.test.sh\"]]]]" ] \
    || fail "the Tests page does not show f.test.sh as removed by card $c of no issue: $(jq -c '.tests.files[] | select(.file == "f.test.sh") | {removed, optimize}' <<<"$out")"
}

# D3. Bug it catches: a Split card with no issue was held to no check (its title is no Optimize issue's), so a split
# that costs more than it may landed. Its files take 8 + 8 CPU s against the 10 on record plus 1 for each file: the
# card is blocked by the Optimize check before any review, its blocked line carrying the check's version, as an
# issue's card is.
t_tcsplit() {
  tcsetup
  echo 8 > "$STUB/cpu-f1.test.sh"; echo 8 > "$STUB/cpu-f2.test.sh"
  echo 'rm f.test.sh; echo one > f1.test.sh; echo two > f2.test.sh' > "$STUB/build"
  tcask f.test.sh 'Split the test file f.test.sh' 'Split this test file into two or more test files.'
  # loop: only a whole card shows that card() picks the Optimize check for a Split card of no issue and blocks on it.
  loop run > /dev/null || fail "run exited non-zero"
  [[ $(st 'select(.step == "blocked") | .reason') == 'build: the split does not fit: the files take 16 CPU s summed, 4 over the 12 CPU s a split of f.test.sh may take: '* ]] \
    && [ -n "$(st 'select(.step == "blocked") | .speedcheck // empty')" ] && [ -z "$(st 'select(.step == "review")')" ] \
    || fail "a Split card of no issue over its allowance was not blocked by the split check before review: $(st 'select(.step | IN("review", "blocked", "landed"))')"
  [ ! -e "$STUB/filed" ] || fail "the blocked Split card filed an issue: $(cat "$STUB/filed")"
}
