#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 300
# Engine cases: the Tests page's cards with no GitHub issue (#1330, #1346). With the control record's rules.testissues
# off (the Rules tab's Cards with no GitHub issue: Tests page actions On), `testissue` files no issue and queues a card
# (testcard(), lib/testaction.sh), which the loop picks ahead of the queue (testpick()) and the Board shows by its test
# file and title. The card is held to the check of its action (lib/speedproof.sh), is held for a Foreman session until
# released, waits on a card it depends on, is retried once when it blocks, and lands naming and closing no issue.
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
# a Foreman session (`foreman.sh ask <project> testissue`, which sets CONVEYOR_FOREMAN=1) filed a GitHub issue, or
# started a card the owner had not said yes to (#1346: a card the Foreman starts is held until the owner's yes). It
# queues a held card with no issue, which says how to release it; the pick passes over it until `control release
# <card id>`, and then takes it as that card id.
t_tcheld() {
  tcsetup; local out id
  loop control start held > /dev/null 2>&1 || fail "start held was refused"
  tcask f.test.sh 'Optimize the test file f.test.sh' 'Make it cheaper.'
  out=$(CONVEYOR_FOREMAN=1 loop testissue g.test.sh 'Optimize the test file g.test.sh' 'Make it cheaper.' 2> "$STUB/ti.err") \
    || fail "testissue g.test.sh 'Optimize the test file g.test.sh' with the rule off for a Foreman session failed: $out $(cat "$STUB/ti.err")"
  id=$(jq -r '.cards[] | select(.file == "g.test.sh") | .id' "$ST/testactions/cards.json")
  [ "$out" = 'Card queued with no GitHub issue: Optimize the test file g.test.sh' ] && [ ! -e "$STUB/filed" ] \
    && [ "$(jq -c '[.cards[] | [.file, (.held // false)]]' "$ST/testactions/cards.json")" = '[["f.test.sh",false],["g.test.sh",true]]' ] \
    && grep -qF "card $id is held, as it was asked for a Foreman session: release it (conveyor.sh control release $id)" "$STUB/ti.err" \
    || fail "testissue g.test.sh with the rule off for a Foreman session did not queue a held card with no issue and say how to release it: $out $(cat "$STUB/ti.err") $(cat "$STUB/filed" 2>&1) $(cat "$ST/testactions/cards.json")"
  fx_in 'for i in 1 2; do p=$(locked pick "" "" "[]") || exit 1; echo "pick $i: $p"; done'
  [ "$RC" = 0 ] && grep -qE '^pick 1: c[0-9T]+-.*-0 0 false$' "$T/$CASE/run.out" && grep -qx 'pick 2: ' "$T/$CASE/run.out" \
    && [ "$(st 'select(.step == "picked") | .testFile')" = f.test.sh ] || fail "the pick took the held card $id, or not the other: $(cat "$T/$CASE/run.out")"
  out=$(loop control release "$id" 2>&1) && [ "$out" = "conveyor: card $id is released: it is picked in its turn" ] || fail "control release $id failed: $out"
  fx_in 'locked pick "" "" "[]"'
  [ "$RC" = 0 ] && [ "$(cat "$T/$CASE/run.out")" = "$id 0 false" ] || fail "after control release $id, the pick did not take it as card $id: $(cat "$T/$CASE/run.out")"
  if out=$(loop control release "$id" 2>&1); then fail "control release $id of a card no longer held was taken: $out"; fi
}

# #1346 D6, depends-on by card id. Bugs it catches: a card with no GitHub issue whose body says "Depends on: <card id>"
# was picked before that card landed. The older entry b waits on a; a is picked first as its own card id, b only once
# a's card has landed.
t_tcdeps() {
  setup '[]'; mkdir -p "$ST/testactions"; local a=c20261101T000000-main-0
  jq -cn --arg a "$a" '{cards: [{file: "b.test.sh", title: "b", body: "Do b.\nDepends on: \($a)", time: "2026-11-01T00:00:00Z", id: "c20261101T000001-x-0", card: null},
    {file: "a.test.sh", title: "a", body: "Do a.", time: "2026-11-01T00:00:01Z", id: $a, card: null}]}' > "$ST/testactions/cards.json"
  fx_in 'for i in 1 2; do p=$(locked pick "" "" "[]") || exit 1; echo "pick $i: $p"; done'
  [ "$RC" = 0 ] && [ "$(cat "$T/$CASE/run.out")" = "pick 1: $a 0 false"$'\n''pick 2: ' ] || fail "b, which depends on $a, was picked before $a landed, or $a was not picked as its id: $(cat "$T/$CASE/run.out")"
  fx_in 'append "$(line '"$a"' 0 landed ok "{\"sha\":\"abc\",\"product\":false}")" && locked pick "" "" "[]"'
  [ "$RC" = 0 ] && [ "$(cat "$T/$CASE/run.out")" = 'c20261101T000001-x-0 0 false' ] || fail "b was not picked once $a landed: $(cat "$T/$CASE/run.out")"
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

# #1346 D4. Bugs it catches: a card with no GitHub issue that blocked went straight to the owner, or was retried with
# its work lost (resumeplan() read no kept patch of issue 0), or was retried again and again. Its build changes
# f.test.sh and fails each time: the first card is retried once, with no one asked, and the second starts from its
# kept patch (the first build had nothing staged, the second has f.test.sh); that one stays blocked, and Needs you
# shows it with its reason.
t_tcblock() {
  tcsetup; local c1 c2 out
  echo 'git diff --cached --name-only >> "$STUB/resumed-with"; echo x >> f.test.sh; exit 3' > "$STUB/build"
  tcask f.test.sh 'Optimize the test file f.test.sh' 'Make it cheaper.'
  # loop: only a whole card run shows that the pick after a block gives the card back and the next card takes up its patch.
  loop run > /dev/null 2> "$STUB/run.err"
  # The first card's lines moved out to the retried lines as it was given back; the second's stay.
  c1=$(jq -r 'select(.step == "blocked") | .card' "$ST/retried.jsonl" 2>/dev/null); c2=$(st 'select(.step == "blocked") | .card')
  [ -n "$c1" ] && [ "$(wc -l <<<"$c1")" = 1 ] && [ -n "$c2" ] && [ "$(wc -l <<<"$c2")" = 1 ] && [ "$c1" != "$c2" ] \
    || fail "the card with no issue was not blocked exactly twice, as two cards: retried $(cat "$ST/retried.jsonl" 2>&1) now $(st 'select(.step | IN("picked", "blocked")) | [.card, .step, .reason] | @json') $(cat "$STUB/run.err")"
  [ "$(jq -c --arg c "$c1" 'select(.card == $c and .step == "blocked") | .retriedWhy' "$ST/retried.jsonl")" = "\"retried once with its kept work: a card with no GitHub issue is tried again once before it goes to the owner\"" ] \
    || fail "card $c1's blocked line was not given back with why: $(cat "$ST/retried.jsonl" 2>&1)"
  st "select(.card == \"$c2\" and .step == \"worktree\") | .reason" | grep -q "^resumed from the kept patch of card $c1:" && [ "$(cat "$STUB/resumed-with")" = f.test.sh ] \
    || fail "card $c2 did not start from the kept patch of $c1: $(st "select(.card == \"$c2\" and .step == \"worktree\")") $(cat "$STUB/resumed-with")"
  out=$(loop snapshot --fresh) || fail "no snapshot"
  [ "$(jq -c '[.needsYou.blocked[] | select(.issue == 0) | [.card, (.reason | startswith("build:"))]]' <<<"$out")" = "[[\"$c2\",true]]" ] \
    || fail "Needs you does not show card $c2, blocked the second time, alone with its reason: $(jq -c '.needsYou.blocked' <<<"$out")"
  fx_in 'locked pick "" "" "[]"'
  [ "$RC" = 0 ] && [ ! -s "$T/$CASE/run.out" ] || fail "card $c2, blocked the second time, was retried again: $(cat "$T/$CASE/run.out")"
}

# Bug it catches: the record of the Tests page's cards kept only its newest 200 cards, so a card the Tests page had
# said was queued was dropped before the loop picked it. The record holds one card not picked yet, the oldest, and 203
# picked ones; a new card drops only the oldest picked one past the newest 200 whose work is on main, c1 (landed).
# Bug caught (R141): the trim dropped c2, blocked, so `retry c2` moved its lines out and the pick had no entry to
# start it again from: it left Needs you with no new card. Kept: not landed.
# Bug caught (R136): the trim dropped c3, landed after deleting its test file (its bugproof speed fix "deleted"), the
# only source of that file's removed mark, so the Tests page showed the deleted file again. Kept.
t_tctrim() {
  setup '[]'; mkdir -p "$ST/testactions"
  jq -cn '{cards: ([{file: "p.test.sh", title: "Optimize the test file p.test.sh", body: "b", time: "2026-11-01T00:00:00Z", card: null}]
    + [range(1; 204) | {file: "d.test.sh", title: "t", body: "b", time: "2026-11-01T00:00:00Z", card: "c\(.)"}])}' > "$ST/testactions/cards.json"
  fx_in 'append "$(line c1 0 landed ok)" && append "$(line c2 0 blocked blocked "{\"reason\":\"build: it failed\"}")" \
    && append "$(line c3 0 bugproof ok "{\"speed\":{\"fix\":\"deleted\"}}")" && append "$(line c3 0 landed ok)" \
    && testcard n.test.sh "Optimize the test file n.test.sh" "Make it cheaper."'
  [ "$RC" = 0 ] || fail "testcard n.test.sh failed: $(cat "$T/$CASE/run.out")"
  [ "$(jq -c '[(.cards | length), .cards[0].file, .cards[1].card, .cards[2].card, .cards[3].card, .cards[-2].card, .cards[-1].file, .cards[-1].card]' "$ST/testactions/cards.json")" = '[204,"p.test.sh","c2","c3","c4","c203","n.test.sh",null]' ] \
    || fail "testcard n.test.sh with a card not picked and 203 picked ones (c1 landed, c2 blocked, c3 landed deleting its file) did not keep each card not picked, c2 and c3, and drop only c1: $(jq -c '[.cards[] | [.file, .card]] | .[:5] + .[-3:]' "$ST/testactions/cards.json")"
}

# D1, landing. Bugs it catches: a card with no issue landed under "Closes #0", or its landing or push asked GitHub to
# close an issue; or the Tests page lost its result, as its Optimize history was read from GitHub filings only, so
# f.test.sh, which it deleted, stayed in the table. The Optimize card deletes f.test.sh and its review names the test
# of each case.
# #1346 D5, and File on GitHub. Bugs it catches: the commit left out the words the card came from; a closing keyword
# in them ("Fixes #12") went into the commit, so the push closed #12; the card's trailers went in above a body line
# that starts "Conveyor card ", not above its card line; the Board lost the card's body once it landed; and File on
# GitHub (`cardissue`) filed no issue, or not its title and body, left it open for the belt to build again, or filed
# a second one when asked again.
t_tcland() {
  tcsetup; local c msg out sha body=$'Make it cheaper. Fixes #12.\nConveyor card words in the body.'
  echo 'rm f.test.sh; echo "Bug-Proof: g.test.sh" > "$PWD.trailers"' > "$STUB/build"; printf '%s\n' 'COVERED-BY: g.test.sh: one' 'COVERED-BY: g.test.sh: two' "$GO" > "$STUB/review.1"
  tcask f.test.sh 'Optimize the test file f.test.sh' "$body"
  # loop: only a whole card shows that it is picked, built, checked, reviewed, landed and pushed with no issue.
  loop run > /dev/null || fail "run exited non-zero: $(st 'select(.step | IN("blocked", "landed"))')"
  c=$(st 'select(.step == "landed") | .card')
  [ -n "$c" ] && [ "$(st 'select(.step == "landed") | .issue')" = 0 ] || fail "the Optimize card with no issue did not land: $(st 'select(.step | IN("picked", "blocked", "landed"))')"
  # Its picked line, with its test file, is a whole record: the record check set none aside.
  [ "$(st 'select(.step == "picked") | [.card, .testFile] | @tsv')" = "$c"$'\t'f.test.sh ] && [ ! -s "$ST/quarantined.jsonl" ] \
    || fail "card $c's picked line does not name its test file, or a line was set aside: $(st 'select(.step == "picked")') $(cat "$ST/quarantined.jsonl" 2>&1)"
  sha=$(st 'select(.step == "landed") | .sha'); msg=$(git -C "$R" log -1 --format=%B "$sha")
  [ "$msg" = "fix(product): Optimize the test file f.test.sh"$'\n\nMake it cheaper. Fixes issue 12.\nConveyor card words in the body.\n\nBug-Proof: g.test.sh\n'"Conveyor card $c" ] \
    || fail "the landed commit of card $c does not carry its title, its body with no issue to close, its trailer and its card id last: $msg"
  [ ! -e "$STUB/closed" ] && [ ! -e "$STUB/filed" ] && [ -z "$(st 'select(.step == "issue")')" ] \
    || fail "card $c of no issue filed or closed an issue: $(cat "$STUB/filed" "$STUB/closed" 2>&1) $(st 'select(.step == "issue")')"
  out=$(loop snapshot --fresh) || fail "no snapshot"
  [ "$(jq -c '.tests.files[] | select(.file == "f.test.sh") | [.removed, (.optimize | map([.issue, .card, .name, .state, .fix, .into]))]' <<<"$out")" = "[true,[[null,\"$c\",\"No issue\",\"landed\",\"deleted\",[\"g.test.sh\"]]]]" ] \
    || fail "the Tests page does not show f.test.sh as removed by card $c of no issue: $(jq -c '.tests.files[] | select(.file == "f.test.sh") | {removed, optimize}' <<<"$out")"
  [ "$(jq -c --arg c "$c" '.landed[] | select(.card == $c) | [.title, .body, .filed, (.track.steps | length), .step]' <<<"$out")" = "$(jq -cn --arg b "$body" '["Optimize the test file f.test.sh", $b, null, 6, "landed"]')" ] \
    || fail "Landed today lost the record of card $c of no issue (title, body, steps, result): $(jq -c '.landed' <<<"$out")"
  out=$(loop cardissue "$c" 2>&1) && [ "$out" = https://github.com/o/r/issues/100101 ] \
    && [ "$(jq -c '[.title, .body]' "$STUB/filed")" = "$(jq -cn --arg b "$body" '["Optimize the test file f.test.sh", $b]')" ] \
    || fail "cardissue $c did not file an issue with its title and body: $out $(cat "$STUB/filed" 2>&1)"
  # Bug it catches (R129): the issue was made with no built label and closed after, so a pick in between built the landed work again.
  [ "$(jq -c '.labels | map(.name)' "$STUB/filed")" = '["awaiting-deploy"]' ] \
    || fail "cardissue $c did not make the issue with the built label: $(cat "$STUB/filed")"
  [ "$(cat "$STUB/closed")" = 100101 ] && grep -qF "Conveyor card $c landed this as commit $sha" "$STUB/close-comments" \
    || fail "cardissue $c did not close #100101 naming the commit $sha: $(cat "$STUB/closed" "$STUB/close-comments" 2>&1)"
  out=$(loop cardissue "$c" 2>/dev/null) && [ "$out" = https://github.com/o/r/issues/100101 ] && [ "$(wc -l < "$STUB/filed")" = 1 ] \
    || fail "a second cardissue $c filed again, or did not print #100101: $out $(cat "$STUB/filed")"
  [ "$(loop snapshot --fresh | jq -c --arg c "$c" '.landed[] | select(.card == $c) | [.filed, .filedUrl]')" = '[100101,"https://github.com/o/r/issues/100101"]' ] \
    || fail "Landed today does not link #100101, filed from card $c"
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

# Bug it catches: with the pack's privacy.mode public, a card with no issue whose body quotes test output (a Fix the
# failures card's log tail) landed a commit message holding a home path, and the push sent it to the remote with no
# privacy check. cardsubject() masks the flagged words in the message; with privacy.mode private it keeps them.
t_tcprivmsg() {
  setup '[]'
  local hx=/hom"e"/x # a home path, put together so this file holds none itself (the privacy check runs over it)
  local issue; issue=$(jq -cn --arg b "The end of the output: cd $hx/repo failed" '{number: 0, title: "Fix the failures of the test file f.test.sh", body: $b, labels: []}')
  tune '.privacy.mode = "public"'
  fx_in "cardsubject c0-0 '$issue'"
  [ "$RC" = 0 ] && [ "$(cat "$T/$CASE/run.out")" = $'feat(product): Fix the failures of the test file f.test.sh\n\nThe end of the output: cd <home path> failed\n\nConveyor card c0-0' ] \
    || fail "cardsubject c0-0 '$issue' with privacy.mode public did not mask the home path (exit $RC): $(cat "$T/$CASE/run.out")"
  tune '.privacy.mode = "private"'
  fx_in "cardsubject c0-0 '$issue'"
  [ "$RC" = 0 ] && grep -qF "cd $hx/repo failed" "$T/$CASE/run.out" \
    || fail "cardsubject c0-0 '$issue' with privacy.mode private changed the body (exit $RC): $(cat "$T/$CASE/run.out")"
}

# Bug it catches (#1385): with privacy.mode public, the commit message of a card with no issue whose body holds a whole
# private key masked its BEGIN line alone (the words the privacy check flags), so the key's body and END line landed.
# The whole key, BEGIN to END, is one <token>; the lines around it stay.
t_tcprivkey() {
  setup '[]'
  local k="PRIVATE"" KEY" # put together so this file holds no key header itself (the privacy check runs over it)
  local issue; issue=$(jq -cn --arg b "$(printf '%s\n' 'The end of the output:' "-----BEGIN RSA $k-----" 'MIIBOgIBAAJBAKj34GkxFhD90vcNLYLInFEX6Ppy1tPf9Cnzj4p4WGeKLs1Pt8Qu' 'KUpRKfFLfRYC9AIKjbJTWit+CqvjWYzvQwECAwEAAQ==' "-----END RSA $k-----" 'and then it stopped')" \
    '{number: 0, title: "Fix the failures of the test file f.test.sh", body: $b, labels: []}')
  tune '.privacy.mode = "public"'
  fx_in "cardsubject c0-0 '$issue'"
  [ "$RC" = 0 ] && [ "$(cat "$T/$CASE/run.out")" = $'feat(product): Fix the failures of the test file f.test.sh\n\nThe end of the output:\n<token>\nand then it stopped\n\nConveyor card c0-0' ] \
    || fail "cardsubject c0-0 '$issue' with privacy.mode public left a line of the key body or its END line (exit $RC): $(cat "$T/$CASE/run.out")"
}

# #1347: the other four kinds of card with no GitHub issue, each with its switch of the Rules tab's Cards with no GitHub
# issue group (rules.foremanissues, followupissues, releaseissues, splitissues, each false = On). The helpers are named ni*.
# nisetup <rule>: a case with the open issue #7 and the rule <rule> off. nipick: the pick, as the loop takes it, with
# nothing else open; its output is "<card id> 0 false", or nothing.
nicards() { echo "$ST/testactions/cards.json"; } # the record of the cards with no GitHub issue
nisetup() {
  setup "[$(issue 7 2026-01-01)]"
  loop control rules "$1=off" > /dev/null || fail "control rules $1=off was refused"
  [ "$(loop control | jq -c --arg r "$1" '.rules[$r]')" = false ] || fail "control rules $1=off did not set the rule off: $(loop control | jq -c .rules)"
}
nipick() { fx_in "${1:+ONLY='$1' }"'locked pick "" "" "[]"'; [ "$RC" = 0 ] || fail "the pick failed: $(cat "$T/$CASE/run.out")"; cat "$T/$CASE/run.out"; } # [<--only list, json>]
# nibelt <card id> <name> <title>: the belt shows the card of issue 0 by that name and title.
nibelt() {
  [ "$(loop snapshot --fresh | jq -c --arg c "$1" '.belt[] | select(.card == $c) | [.issue, .name, .title]')" = "$(jq -cn --arg n "$2" --arg t "$3" '[0, $n, $t]')" ] \
    || fail "the belt does not show card $1 as \"$2\" with the title \"$3\": $(loop snapshot --fresh | jq -c .belt)"
}

# D1 (the Foreman's order, the rule On). Bugs it catches: `foreman.sh ask <project> card` filed a GitHub issue with the
# rule on; its card was not held until the owner's yes (a card the Foreman starts is held, as its issue would be); it
# was never picked, or the belt showed it with no name or title.
t_nifore() {
  nisetup foremanissues; local out id
  out=$(loop card 'Add a Rules row' 'Make it so.' 2> "$STUB/c.err") || fail "card 'Add a Rules row' with foremanissues off failed: $out $(cat "$STUB/c.err")"
  id=$(jq -r '.cards[0].id' "$(nicards)")
  [ "$out" = 'Card queued with no GitHub issue: Add a Rules row' ] && [ ! -e "$STUB/filed" ] && grep -qF "card $id is held" "$STUB/c.err" \
    || fail "card 'Add a Rules row' with foremanissues off did not queue a held card with no issue: $out $(cat "$STUB/c.err") $(cat "$STUB/filed" 2>&1)"
  [ -z "$(nipick)" ] || fail "the pick took the held Foreman order $id"
  loop control release "$id" > /dev/null || fail "control release $id failed"
  [ "$(nipick)" = "$id 0 false" ] || fail "after control release $id, the pick did not take it: $(cat "$T/$CASE/run.out")"
  nibelt "$id" 'Foreman order' 'Add a Rules row'
}

# D1 (the release fix card, the rule On). Bug it catches: the fix card of a red test file filed an issue with the rule
# on, or lost its `Release fix: <version>` line, which relfixes() reads to find it.
t_nirelease() {
  nisetup releaseissues; local out id
  out=$(loop card --release 1.1.0 'Fix a.test.sh' 'Make it pass.' 2> "$STUB/c.err") || fail "card --release 1.1.0 with releaseissues off failed: $out $(cat "$STUB/c.err")"
  id=$(jq -r '.cards[0].id' "$(nicards)")
  [ "$out" = 'Card queued with no GitHub issue: Fix a.test.sh' ] && [ ! -e "$STUB/filed" ] && [ "$(jq -r '.cards[0].body' "$(nicards)")" = $'Make it pass.\n\nRelease fix: 1.1.0' ] \
    || fail "card --release 1.1.0 with releaseissues off did not queue a card with no issue and the Release fix line: $out $(cat "$STUB/filed" 2>&1) $(cat "$(nicards)")"
  loop control release "$id" > /dev/null || fail "control release $id failed"
  [ "$(nipick)" = "$id 0 false" ] || fail "the pick did not take the release fix card $id: $(cat "$T/$CASE/run.out")"
  nibelt "$id" 'Release fix' 'Fix a.test.sh'
}

# D2 (every switch Off, its default). Bugs it catches: `card` with its rule off filed no issue, or filed one the owner's
# yes had not been asked for (a Foreman's issue starts held), or a release fix issue with no `Release fix:` line (relfixes()
# would not find it); a follow-up of a review filed no issue with its rule off.
t_nioff() {
  setup "[$(issue 7 2026-01-01)]"; local out n
  # Bug caught (#1347): with foremanissues on, a Foreman order filed a bug-labelled issue with no `## Cause` section, which the Foreman's filing hook refuses for any other fix issue.
  if loop card 'Fix the empty Board' 'The Board shows no cards.' > "$STUB/c.out" 2> "$STUB/c.err"; then fail "card with foremanissues on filed a fix issue with no Cause section: $(cat "$STUB/c.out" "$STUB/filed")"; fi
  [ ! -e "$STUB/filed" ] || fail "card with no Cause section filed an issue all the same: $(cat "$STUB/filed")"
  out=$(loop card 'Add a Rules row' $'Make it so.\n## Cause\nNo row exists.' 2> "$STUB/c.err") || fail "card with the default rules failed: $out $(cat "$STUB/c.err")"
  n=${out##*/}
  [ "$(jq -rs 'map(.title) | join("|")' "$STUB/filed")" = 'Add a Rules row' ] && [ "$(loop control | jq -c --argjson n "$n" '.held | index($n) != null')" = true ] && [ ! -e "$(nicards)" ] \
    || fail "card with foremanissues on did not file its issue #$n held, or started a card: $out $(cat "$STUB/filed" 2>&1) $(loop control | jq -c .held)"
  # Bug caught (#1347): with releaseissues on the card command filed a bug-labelled fix issue with no `## Cause` section, which the Foreman's filing hook refuses for any other fix issue.
  if loop card --release 1.1.0 'Fix a.test.sh' 'Make it pass.' > "$STUB/c.out" 2> "$STUB/c.err"; then fail "card --release with releaseissues on filed a fix issue with no Cause section: $(cat "$STUB/c.out" "$STUB/filed")"; fi
  [ "$(jq -rs 'length' "$STUB/filed")" = 1 ] || fail "card --release with no Cause section filed an issue all the same: $(cat "$STUB/filed")"
  out=$(loop card --release 1.1.0 'Fix a.test.sh' $'Make it pass.\n## Cause\nA stale file.' 2> "$STUB/c.err") || fail "card --release with the default rules failed: $out $(cat "$STUB/c.err")"
  [ "$(jq -rs 'last | .body' "$STUB/filed")" = $'Make it pass.\n## Cause\nA stale file.\n\nRelease fix: 1.1.0' ] && [ ! -e "$(nicards)" ] \
    || fail "card --release with releaseissues on did not file an issue with the Release fix line: $(cat "$STUB/filed") $(cat "$(nicards)" 2>&1)"
  printf '%s\n' '[P2] a.txt:1 the word is wrong. Proof: a.txt line 1 reads "one"' 'VERDICT: NO-GO' > "$STUB/r.review"
  fx_in 'followups c1-7 "$(jq -c ".[0]" "$STUB/issues.json")" "$STUB/r.review"'
  [ "$RC" = 0 ] && [ "$(jq -rs 'last | .title' "$STUB/filed")" = '[P2] a.txt:1 the word is wrong. Proof: a.txt line 1 reads "one"' ] && [ ! -e "$(nicards)" ] \
    || fail "a follow-up with followupissues on did not file its issue: $(cat "$T/$CASE/run.out") $(cat "$STUB/filed")"
}

# D1 (the review follow-up, the rule On) and the withdrawal. Bugs it catches: a follow-up filed an issue with the rule
# on; its card did not name its parent; it was not on the belt with its finding as its title; one withdrawn after its
# card failed to land (unfile()) stayed in the record, so the belt would build a finding the card's next build carries; the
# card was picked before its parent card landed, as an issue's follow-up waits for its parent's landed line.
t_nifollow() {
  nisetup followupissues; local id
  printf '%s\n' '[P2] a.txt:1 the word is wrong. Proof: a.txt line 1 reads "one"' 'VERDICT: NO-GO' > "$STUB/r.review"
  fx_in 'followups c20261101T000000-main-7 "$(jq -c ".[0]" "$STUB/issues.json")" "$STUB/r.review"'
  id=$(jq -r '.cards[0].id' "$(nicards)")
  [ "$RC" = 0 ] && [ "$(cat "$T/$CASE/run.out")" = '[]' ] && [ ! -e "$STUB/filed" ] && jq -e '.cards[0].body | startswith("Follow-up to #7 (Conveyor card c20261101T000000-main-7).") and contains("Follow-up depth: 1")' "$(nicards)" > /dev/null \
    || fail "a follow-up with followupissues off filed an issue, or its card does not name its parent #7: $(cat "$T/$CASE/run.out") $(cat "$STUB/filed" 2>&1) $(cat "$(nicards)" 2>&1)"
  # Bug caught: the follow-up card was picked before its parent card landed (an issue's follow-up waits for that landed line).
  [ -z "$(nipick)" ] || fail "the pick took the follow-up card $id before its parent card landed: $(cat "$T/$CASE/run.out")"
  jq -e '.cards[0].body | endswith("\nDepends on: c20261101T000000-main-7")' "$(nicards)" > /dev/null || fail "the follow-up card $id does not depend on its parent card: $(cat "$(nicards)")"
  fx_in 'append "$(line c20261101T000000-main-7 7 landed ok "{\"sha\":\"abc\",\"product\":false}")"'
  [ "$(nipick)" = "$id 0 false" ] || fail "after its parent card landed, the pick did not take the follow-up card $id: $(cat "$T/$CASE/run.out")"
  nibelt "$id" 'Review follow-up of #7' '[P2] a.txt:1 the word is wrong. Proof: a.txt line 1 reads "one"'
  # The card was not picked yet in a second run: a card that failed to land takes its follow-ups back out of the record.
  fx_in 'followups c20261101T000000-main-7 "$(jq -c ".[0]" "$STUB/issues.json")" "$STUB/r.review" > /dev/null; unfile 7 "$STUB/r.review"'
  [ "$RC" = 0 ] && [ "$(jq -c '[.cards[] | .card != null]' "$(nicards)")" = '[true]' ] && grep -qE '^c[0-9T]+-.*-0 \[P2\] a.txt:1' "$STUB/r.withdrawn" \
    || fail "a withdrawn follow-up card stayed in the record, or its finding was not kept for the next build: $(cat "$(nicards)") $(cat "$STUB/r.withdrawn" 2>&1) $(cat "$T/$CASE/run.out")"
}

# D1 (the split parts, the rule On). Bugs it catches: the parts of a split filed issues with the rule on; the second part
# did not wait for the first (its Depends on line names the first's card id); the parts did not start held when the
# umbrella is held; the umbrella stayed open after each part landed (umbrellas() read only parts that are issues); the
# split check filed the parts as issues whatever the switch said (it goes through splitcheck(), as the card does, so it
# fails if splitcheck() always calls splitfile()).
t_nisplit() {
  local a b
  slices on "$SPLIT2" "[$(big 7)]"
  loop control rules splitissues=off > /dev/null && loop control hold 7 > /dev/null || fail "control rules splitissues=off, or control hold 7, failed"
  fx_in 'splitcheck c1-7 7'
  a=$(jq -r '.cards[0].id' "$(nicards)"); b=$(jq -r '.cards[1].id' "$(nicards)")
  [ "$RC" = 1 ] && [ ! -e "$STUB/filed" ] && [ "$(st 'select(.step == "split") | .split | [.cards == ["'"$a"'", "'"$b"'"], .filed, .held] | @json')" = '[true,[],true]' ] \
    && [ "$(jq -c '[.cards[] | [.title, (.held // false)]]' "$(nicards)")" = '[["part one",true],["part two",true]]' ] && jq -e --arg a "$a" '.cards[1].body | test("(^|\n)Depends on: " + $a + "(\n|$)")' "$(nicards)" > /dev/null \
    || fail "splitcheck with splitissues off did not make the parts held cards with no issue, the second depending on the first (exit $RC): $(cat "$T/$CASE/run.out") $(cat "$STUB/filed" 2>&1) $(cat "$(nicards)")"
  loop control release "$a" > /dev/null && loop control release "$b" > /dev/null || fail "control release of the parts $a and $b failed"
  [ "$(nipick)" = "$a 0 false" ] || fail "the pick did not take the first part $a only: $(cat "$T/$CASE/run.out")"
  nibelt "$a" 'Split part of #7' 'part one'
  [ -z "$(nipick)" ] || fail "the second part $b was picked before the first landed"
  # The umbrella: its split line (the one splitcheck wrote) names the cards; it closes once each has landed, not before.
  fx_in 'append "$(line '"$a"' 0 landed ok "{\"sha\":\"abc\",\"product\":false}")"; umbrellas "$(asked)"'
  [ ! -e "$STUB/closed" ] || fail "the umbrella #7 was closed with its second part $b not landed: $(cat "$STUB/closed") $(cat "$T/$CASE/run.out")"
  fx_in 'append "$(line '"$b"' 0 landed ok "{\"sha\":\"abd\",\"product\":false}")"; umbrellas "$(asked)"'
  [ "$(cat "$STUB/closed" 2>/dev/null)" = 7 ] || fail "the umbrella #7 was not closed once each part card landed: $(cat "$STUB/closed" 2>&1) $(cat "$T/$CASE/run.out")"
}

# Bugs it catches: a part whose card ended closed because main already does it (ALREADY-DONE) kept its umbrella open and
# its dependent part queued, as only a landed line counted; a part shut by hand is not done, so it must still hold both.
t_nidone() {
  nisetup splitissues; local a b
  fx_in 'splitcards c1-7 "$(jq -c ".[0]" "$STUB/issues.json")" '"'"'[{"title":"First part","doneWhen":["a"],"covers":[1],"dependsOn":[]},{"title":"Second part","doneWhen":["b"],"covers":[2],"dependsOn":[1]}]'"'"' 1'
  a=$(jq -r '.cards[0].id' "$(nicards)"); b=$(jq -r '.cards[1].id' "$(nicards)")
  [ "$(nipick)" = "$a 0 false" ] || fail "the pick did not take the first part $a: $(cat "$T/$CASE/run.out")"
  fx_in 'append "$(line c1-7 7 split split "{\"split\":{\"mode\":\"on\",\"hash\":\"h\",\"size\":{\"areas\":1,\"chars\":10,\"doneWhen\":3,\"files\":1},\"verdict\":\"split\",\"why\":\"w\",\"cards\":[\"'"$a"'\",\"'"$b"'\"],\"filed\":[]}}")"
    append "$(line '"$a"' 0 closed ok "$(jq -cn --arg r "$OWNSHUT" "{reason: \$r}")")"; umbrellas "$(asked)"'
  [ -z "$(nipick)" ] && [ ! -e "$STUB/closed" ] || fail "a part shut by the owner counted as done: its dependent part was picked, or the umbrella closed: $(cat "$STUB/closed" 2>&1) $(cat "$T/$CASE/run.out")"
  fx_in 'append "$(line '"$a"' 0 closed ok "{\"reason\":\"ALREADY-DONE: src/app.sh:1 does it\"}")"'
  [ "$(nipick)" = "$b 0 false" ] || fail "the part $b did not start once the card of the part before it ended already done on main: $(cat "$T/$CASE/run.out")"
  fx_in 'append "$(line '"$b"' 0 landed ok "{\"sha\":\"abd\",\"product\":false}")"; umbrellas "$(asked)"'
  [ "$(cat "$STUB/closed" 2>/dev/null)" = 7 ] || fail "the umbrella #7 stayed open though one part is already done on main and the other landed: $(cat "$STUB/closed" 2>&1) $(cat "$T/$CASE/run.out")"
}

# Bug it catches: with the Follow-ups rule off (rules.followups false) a review follow-up card and a split part were still
# picked, as the rule was read only for issues (jq/upnext.jq). The rule On again, both are picked in their turn.
t_nirule() {
  nisetup followupissues; local id
  printf '%s\n' '[P2] a.txt:1 the word is wrong. Proof: a.txt line 1 reads "one"' 'VERDICT: NO-GO' > "$STUB/r.review"
  loop control rules splitissues=off > /dev/null || fail "control rules splitissues=off failed"
  fx_in 'followups c20261101T000000-main-7 "$(jq -c ".[0]" "$STUB/issues.json")" "$STUB/r.review" > /dev/null
    splitcards c20261101T000000-main-7 "$(jq -c ".[0]" "$STUB/issues.json")" '"'"'[{"title":"First part","doneWhen":["a"],"covers":[1],"dependsOn":[]}]'"'"' 1 > /dev/null
    append "$(line c20261101T000000-main-7 7 landed ok "{\"sha\":\"abc\",\"product\":false}")"'
  id=$(jq -r '.cards[0].id' "$(nicards)")
  loop control rules followups=off > /dev/null || fail "control rules followups=off failed"
  [ -z "$(nipick)" ] || fail "with the Follow-ups rule off, the pick took a follow-up card or a split part: $(cat "$T/$CASE/run.out") $(cat "$(nicards)")"
  loop control rules followups=on > /dev/null || fail "control rules followups=on failed"
  [ "$(nipick)" = "$id 0 false" ] || fail "with the Follow-ups rule on, the pick did not take the follow-up card $id: $(cat "$T/$CASE/run.out")"
}

# Bugs it catches: a Foreman order or release fix card with a `Depends on: #7` line was picked while #7 was open (testpick()
# read card ids only, as upnext() reads the issues too); a card whose issue's card landed (not yet pushed) waited anyway;
# a split part with an area label the owner set to never build was picked, as upnext() holds an issue with that label.
t_nihold() {
  nisetup foremanissues; local id part
  loop card 'Add a Rules row' $'Make it so.\n\nDepends on: #7' > /dev/null 2>&1 || fail "card with a Depends on line failed"
  id=$(jq -r '.cards[0].id' "$(nicards)")
  loop control release "$id" > /dev/null || fail "control release $id failed"
  fx_in 'locked testpick "$(jq -c . "$STUB/issues.json")"'
  [ "$RC" = 0 ] && [ ! -s "$T/$CASE/run.out" ] || fail "the pick took the Foreman order $id (Depends on: #7) while #7 is open: $(cat "$T/$CASE/run.out")"
  fx_in 'append "$(line c20261101T000000-main-7 7 landed ok "{\"sha\":\"abc\",\"product\":false}")"; locked testpick "$(jq -c . "$STUB/issues.json")"'
  [ "$(cat "$T/$CASE/run.out")" = "$id 0 false" ] || fail "the pick did not take the Foreman order $id once the card of #7 landed: $(cat "$T/$CASE/run.out")"
  fx_in 'tcadd "" "A part" "Body." "" "Split part of #7" "[\"area:engine\",\"bug\"]" 7'
  part=$(jq -r '.cards[-1].id' "$(nicards)")
  loop control rules area:engine=off > /dev/null || fail "control rules area:engine=off failed"
  fx_in 'locked testpick "[]"'
  [ "$RC" = 0 ] && [ ! -s "$T/$CASE/run.out" ] || fail "the pick took the part $part with area:engine set to never build: $(cat "$T/$CASE/run.out")"
  loop control rules area:engine=on > /dev/null || fail "control rules area:engine=on failed"
  fx_in 'locked testpick "[]"'
  [ "$(cat "$T/$CASE/run.out")" = "$part 0 false" ] || fail "with area:engine built again, the pick did not take the part $part: $(cat "$T/$CASE/run.out")"
}

# Bug it catches: a Foreman order or release fix card with `Depends on: other/repo#600` was picked while that issue of another
# repository was open (testpick() dropped the reference, as needs does; upnext() holds an issue for it, farstates()). Its body over 128 KiB catches a pick that gives the far states to jq as an argument (Argument list too long).
t_nifar() {
  nisetup foremanissues; local id
  loop card 'Add a Rules row' $'Make it so.\n\nDepends on: other/repo#600' > /dev/null 2>&1 || fail "card with a far Depends on line failed"
  id=$(jq -r '.cards[0].id' "$(nicards)"); { jq '.cards[0].body += "\n" + "x" * 140000' "$(nicards)" > "$STUB/c.json" && mv -f "$STUB/c.json" "$(nicards)"; } || fail "the body of $id could not be made over 128 KiB"
  loop control release "$id" > /dev/null || fail "control release $id failed"
  echo OPEN > "$STUB/repo.other_repo.600"
  fx_in 'locked testpick "[]"'
  [ "$RC" = 0 ] && [ ! -s "$T/$CASE/run.out" ] || fail "the pick took the Foreman order $id (Depends on: other/repo#600) while that issue is open: $(cat "$T/$CASE/run.out")"
  echo CLOSED > "$STUB/repo.other_repo.600"
  fx_in 'locked testpick "[]"'
  [ "$(cat "$T/$CASE/run.out")" = "$id 0 false" ] || fail "the pick did not take the Foreman order $id once other/repo#600 closed: $(cat "$T/$CASE/run.out")"
}

# Bug it catches: a run limited to an issue (run --only 7) left the review follow-ups and the split parts of that issue
# queued, as the pick took no card with no issue under --only. It takes the cards that follow up the issues it names, and
# no other card with no issue (a Foreman order has no parent).
t_nionly() {
  nisetup followupissues; local id f
  printf '%s\n' '[P2] a.txt:1 the word is wrong. Proof: a.txt line 1 reads "one"' 'VERDICT: NO-GO' > "$STUB/r.review"
  loop control rules foremanissues=off > /dev/null || fail "control rules foremanissues=off failed"
  loop card 'Add a Rules row' 'Make it so.' > /dev/null 2>&1 || fail "card 'Add a Rules row' failed"
  fx_in 'followups c20261101T000000-main-7 "$(jq -c ".[0]" "$STUB/issues.json")" "$STUB/r.review" > /dev/null; append "$(line c20261101T000000-main-7 7 landed ok "{\"sha\":\"abc\",\"product\":false}")"'
  f=$(jq -r '.cards[1].id' "$(nicards)"); id=$(jq -r '.cards[0].id' "$(nicards)"); loop control release "$id" > /dev/null || fail "control release $id failed"
  [ -z "$(nipick '[9]')" ] || fail "a run limited to #9 took a card that follows up #7 or a Foreman order: $(cat "$T/$CASE/run.out")"
  [ "$(nipick '[7]')" = "$f 0 false" ] || fail "a run limited to #7 did not take the follow-up card $f of #7, or took the Foreman order $id: $(cat "$T/$CASE/run.out") $(cat "$(nicards)")"
  [ -z "$(nipick '[7]')" ] || fail "a run limited to #7 took the Foreman order $id: $(cat "$T/$CASE/run.out")"
  [ "$(nipick)" = "$id 0 false" ] || fail "a run with no limit did not take the Foreman order $id: $(cat "$T/$CASE/run.out")"
}

# Bug it catches: a review follow-up card with no GitHub issue lost its parent's area label (the follow-up issue keeps it), so an
# area the owner set to never build after the parent started (rules area:engine=off) still built it.
t_niarea() {
  setup "[$(issue 7 2026-01-01 area:engine)]"
  loop control rules followupissues=off > /dev/null || fail "control rules followupissues=off failed"
  printf '%s\n' '[P2] a.txt:1 the word is wrong. Proof: a.txt line 1 reads "one"' 'VERDICT: NO-GO' > "$STUB/r.review"
  fx_in 'followups c20261101T000000-main-7 "$(jq -c ".[0]" "$STUB/issues.json")" "$STUB/r.review" > /dev/null; append "$(line c20261101T000000-main-7 7 landed ok "{\"sha\":\"abc\",\"product\":false}")"'
  jq -e '.cards[0].labels | index("area:engine") != null' "$(nicards)" > /dev/null || fail "the follow-up card of #7 (area:engine) lost its parent's area label: $(cat "$(nicards)")"
  loop control rules area:engine=off > /dev/null || fail "control rules area:engine=off failed"
  [ -z "$(nipick)" ] || fail "the pick took the follow-up card with area:engine set to never build: $(cat "$T/$CASE/run.out")"
}

# Bug it catches: a run limited to an umbrella (run --only 7) skipped the review follow-up with no GitHub issue of one of its parts
# (#8, a GitHub sub-issue), though upnext() builds the parts: the card's parent is 8, and testpick() compared it with [7] alone.
t_nipart() {
  setup "[$(issue 7 2026-01-01 | jq -c '.parts = [{ref: "#8", number: 8}]'), $(issue 8 2026-01-01)]"
  local id
  fx_in 'tcadd "" "Finding" "Body." "" "Review follow-up of #8" "[\"follow-up\"]" 8 > /dev/null'
  id=$(jq -r '.cards[0].id' "$(nicards)")
  fx_in "ONLY='[9]' "'locked testpick "$(jq -c . "$STUB/issues.json")"'
  [ -z "$(cat "$T/$CASE/run.out")" ] || fail "a run limited to #9 took the follow-up card $id of #8: $(cat "$T/$CASE/run.out")"
  fx_in "ONLY='[7]' "'locked testpick "$(jq -c . "$STUB/issues.json")"'
  [ "$(cat "$T/$CASE/run.out")" = "$id 0 false" ] || fail "a run limited to #7 did not take the follow-up card $id of its part #8: $(cat "$T/$CASE/run.out")"
}

# Bug caught (R120): run --only 7, #7 closed, skipped the follow-up card of its closed part #8: --only grew from open
# issues' parts alone. Bug caught: the parts were read at the run's start alone, so #8, open then and closed by its push,
# was lost. turnask() (run()'s variables it reads set here) reads them again (the gh stub's $STUB/subs) at each turn.
t_nipartclosed() {
  setup "[$(issue 9 2026-01-01)]"
  local id
  echo '7 8 OPEN' > "$STUB/subs"
  fx_in 'tcadd "" "Finding" "Body." "" "Review follow-up of #8" "[\"follow-up\"]" 8 > /dev/null'
  id=$(jq -r '.cards[0].id' "$(nicards)")
  fx_in "ONLY='[7]' ONLYNAMED='[7]'; "'declare -A shuts=() mine=(); cap=1 building=0 now=running inuse=0 running=0 sampled=$SECONDS old= nopack= nocli= mhold= guard= waits= issues= ctl=null
    turnask >/dev/null 2>&1; echo "$ONLY"; echo "7 8 CLOSED" > "$STUB/subs"; turnask >/dev/null 2>&1; echo "$ONLY" && locked testpick "$(jq -c . "$STUB/issues.json")"'
  [ "$(cat "$T/$CASE/run.out")" = $'[7]\n[7,8]\n'"$id 0 false" ] \
    || fail "a run limited to the closed #7, its part #8 open and then closed, did not give [7] and then [7,8] and take the follow-up card $id of #8: $(cat "$T/$CASE/run.out")"
}
# Bug caught: onlyparts() put #7's open part #8 in ONLY at the run's start, so once the owner moved #8 to another
# parent (#5) the pick still took it. An open part is taken by its parent as the pick reads it (umbrella): ONLY stays
# [7], #8 under #5 is not taken, and under #7 (closed, so it has no parts list) it is; so is the follow-up card of #8
# (testpick()), only under #7. Bug caught: closed #8 (open part #9) put in ONLY stayed once moved under #5; read again, it goes.
t_nipartmoved() {
  setup "[$(issue 9 2026-01-01)]"
  local id
  echo '7 8 OPEN' > "$STUB/subs"; issue 9 2026-01-01 | jq -c '[. + {umbrella: 8}]' > "$STUB/sub.json"
  issue 8 2026-01-01 | jq -c '[. + {umbrella: 5}]' > "$STUB/moved.json" && issue 8 2026-01-01 | jq -c '[. + {umbrella: 7}]' > "$STUB/under.json"
  fx_in 'tcadd "" "Finding" "Body." "" "Review follow-up of #8" "[\"follow-up\"]" 8 > /dev/null'
  id=$(jq -r '.cards[0].id' "$(nicards)")
  fx_in 'ONLY=$(onlyparts "[7]") && echo "$ONLY" && upnext "$(cat "$STUB/moved.json")" | jq -c "[.[].number]" && upnext "$(cat "$STUB/under.json")" | jq -c "[.[].number]" \
    && echo "moved: $(locked testpick "$(cat "$STUB/moved.json")")" && echo "under: $(locked testpick "$(cat "$STUB/under.json")")" \
    && echo "7 8 CLOSED" > "$STUB/subs" && ONLY=$(onlyparts "[7]") && upnext "$(cat "$STUB/sub.json")" | jq -c "[.[].number]" \
    && echo "5 8 CLOSED" > "$STUB/subs" && ONLY=$(onlyparts "[7]") && echo "$ONLY" && upnext "$(cat "$STUB/sub.json")" | jq -c "[.[].number]"'
  [ "$(cat "$T/$CASE/run.out")" = $'[7]\n[]\n[8]\nmoved: \nunder: '"$id 0 false"$'\n[9]\n[7]\n[]' ] \
    || fail "with ONLY [7] and its open part #8 moved under #5, then under #7, and then #8 closed (its part #9) under #7 and moved under #5, onlyparts, the pick and testpick did not give [7], [] and [8], the card $id only under #7, then [9], [7] and []: $(cat "$T/$CASE/run.out")"
}

# Bug it catches: a review follow-up of a split part (a card of issue 0) was filed as a follow-up of "#0": a run limited to the
# umbrella (run --only 7) never took it, and its brief never reached the umbrella's visible-change yes (inherit() looks the
# number up). A follow-up of a part follows up the part's own parent, so it names that issue, and so does its follow-up in turn.
t_nichain() {
  local P='Visible change approved: yes, 2026-01-02; condition: only for admins' part f
  setup "[$(issue 7 2026-01-01 | jq -c --arg l "$P" '.body += "\n\n" + $l')]"
  loop control rules followupissues=off > /dev/null || fail "control rules followupissues=off failed"
  printf '%s\n' '[P2] a.txt:1 the word is wrong. Proof: a.txt line 1 reads "one"' 'VERDICT: NO-GO' > "$STUB/r.review"
  fx_in 'tcadd "" "Part one" "Follow-up of #7: slice 1 of 2. Conveyor card c20261101T000000-main-7 split #7." "" "Split part of #7" "[\"follow-up\"]" 7 > /dev/null'
  part=$(nipick '[7]'); part=${part%% *}
  [ -n "$part" ] || fail "a run limited to #7 did not take its split part: $(cat "$(nicards)")"
  fx_in 'followups "'"$part"'" "$(testcardissue "'"$part"'")" "$STUB/r.review" > /dev/null; append "$(line "'"$part"'" 0 landed ok "{\"sha\":\"abc\",\"product\":false}")"'
  [ "$(jq -r '.cards[1].parent' "$(nicards)")" = 7 ] && jq -r '.cards[1].body' "$(nicards)" | head -n 1 | grep -q "^Follow-up to #7 (Conveyor card $part)"     || fail "the follow-up of split part $part does not follow up #7: $(cat "$(nicards)")"
  f=$(jq -r '.cards[1].id' "$(nicards)")
  [ "$(nipick '[7]')" = "$f 0 false" ] || fail "a run limited to #7 did not take the follow-up card $f of its split part: $(cat "$T/$CASE/run.out")"
  fx_in 'inherit "$(jq -c "{body: .cards[1].body}" "'"$(nicards)"'")"'
  [ "$(jq -r .from "$T/$CASE/run.out")" = 7 ] && jq -e --arg l "$P" '.line == $l' "$T/$CASE/run.out" > /dev/null \
    || fail "the follow-up of split part $part did not reach the yes of #7: $(cat "$T/$CASE/run.out")"
}

# Bug it catches: a review follow-up card with no GitHub issue lost its parent's visible-change yes (card() read an inherited
# yes only for a card with an issue number), so a change that is part of the parent's approved one stopped for the owner's yes
# again, and the review was never given the parent's approval line or its condition. A split part reads its parent the same way.
t_niyes() {
  local P='Visible change approved: yes, 2026-01-02; condition: only for admins'
  setup "[$(issue 7 2026-01-01 | jq -c --arg l "$P" '.body += "\n\n" + $l')]"
  loop control rules followupissues=off > /dev/null || fail "control rules followupissues=off failed"
  echo 'echo two >> a.txt; mkdir -p web; echo pay >> web/pay.ts' > "$STUB/build"
  sed -i 's|^cat > /dev/null; echo x|cat > "$STUB/asked"; echo x|' "$STUB/codex"
  mkdir -p "$ST"
  { jq -cn '{card:"c20261101T000000-main-7",issue:7,step:"review",time:"2026-11-01T00:00:00Z",tokens:{claude:0,codex:0},result:"GO",sha:"",reason:"",visible:"yes: admins see a Pay button"}'
    landed 7 | jq -c '.card = "c20261101T000000-main-7"'; } > "$ST/cards.jsonl"
  # A [cleanup] finding: its card is no bug card, so the build need not add a test file.
  printf '%s\n' '[P2][cleanup] a.txt:1 the word is wrong. Proof: a.txt line 1 reads "one"' 'VERDICT: NO-GO' > "$STUB/r.review"
  fx_in 'followups c20261101T000000-main-7 "$(jq -c ".[0]" "$STUB/issues.json")" "$STUB/r.review" > /dev/null'
  printf '%s\n' 'INHERITED: part' 'USER-VISIBLE: yes: admins see the Pay button in red' 'VERDICT: GO' > "$STUB/review.1"
  # loop: only a card's own run reads the inherited yes (card()), gives it to its review and lands on it
  loop run > "$STUB/run1.out" || fail "run exited non-zero: $(st 'select(.step | IN("blocked", "landed"))')"
  [ "$(st 'select(.step == "landed") | [.issue, .yesFrom] | @json' | tail -n 1)" = '[0,7]' ] && grep -q 'yes is inherited' "$STUB/run1.out" \
    || fail "the follow-up card of no issue did not land on its parent's yes: $(st 'select(.step | IN("picked", "blocked", "landed")) | [.step, .issue, .result, .reason[0:300]] | @json' | tail -n 4)"
  grep -qx "$P" "$STUB/asked" && grep -q '^# The yes of #7$' "$STUB/asked" && grep -q 'That yes gives a condition' "$STUB/asked" \
    || fail "the review of the follow-up card of no issue lacks the parent's yes or its condition: $(cat "$STUB/asked")"
}

# Bug it catches (R130): a card given back by `retry` (picked, blocked, its lines gone, its card id kept) was picked again
# with no check of its `Depends on: other/repo#600`, as that issue of another repository was asked only for a card not picked
# yet, so it started while #600 was open again. It waits while #600 is open and is picked once #600 is closed. A landed card
# is not asked about (E1): the pick asked for every unheld card and held the records lock while it did.
t_nifarretry() {
  nisetup foremanissues; local id out new
  loop card 'Add a Rules row' $'Make it so.\n\nDepends on: other/repo#600' > /dev/null 2>&1 || fail "card with a far Depends on line failed"
  id=$(jq -r '.cards[0].id' "$(nicards)")
  loop control release "$id" > /dev/null || fail "control release $id failed"
  echo CLOSED > "$STUB/repo.other_repo.600"
  fx_in 'locked testpick "[]"; append "$(line "'"$id"'" 0 blocked ok "{\"reason\":\"build: it failed\"}")"'
  [ "$(head -n 1 "$T/$CASE/run.out")" = "$id 0 false" ] || fail "the pick did not take the Foreman order $id once other/repo#600 was closed: $(cat "$T/$CASE/run.out")"
  out=$(loop retry "$id" 2>&1) && [ -z "$(st "select(.card == \"$id\")")" ] || fail "retry $id did not give back the blocked card: $out"
  echo OPEN > "$STUB/repo.other_repo.600"
  fx_in 'locked testpick "[]"'
  [ "$RC" = 0 ] && [ ! -s "$T/$CASE/run.out" ] || fail "the pick took the retried card $id (Depends on: other/repo#600) while that issue is open: $(cat "$T/$CASE/run.out")"
  echo CLOSED > "$STUB/repo.other_repo.600"
  fx_in 'locked testpick "[]"'
  # A card given back is taken again under a new card id.
  [[ $(cat "$T/$CASE/run.out") =~ ^c[0-9]{8}T[0-9]{6}-[A-Za-z0-9._-]+-0\ 0\ false$ ]] || fail "the pick did not take the retried card $id once other/repo#600 closed: $(cat "$T/$CASE/run.out")"
  # A card that landed is never picked again, so a pick asks GitHub nothing about its other/repo#600 (each ask holds the records lock for up to 30 seconds).
  new=$(awk '{print $1}' "$T/$CASE/run.out")
  fx_in 'append "$(line "'"$new"'" 0 landed ok "{\"sha\":\"abc\",\"product\":false}")"'
  rm -f "$STUB/far-viewed"
  fx_in 'locked testpick "[]"'
  [ "$RC" = 0 ] && [ ! -s "$STUB/far-viewed" ] || fail "the pick asked GitHub about the landed card's other/repo#600: $(cat "$STUB/far-viewed" 2>/dev/null)"
}
