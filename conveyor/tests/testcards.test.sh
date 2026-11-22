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
