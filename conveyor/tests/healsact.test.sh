#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 120
# Engine cases: what the owner does with one entry of the self-heals list from the Board's Self-heals page: "Move up to
# harm" (`conveyor.sh heals harm <id>...`, healsharm(), lib/heals.sh) files its own follow-up card at once and takes it
# off the list; "Drop now" (`heals drop <id>...`, healsdiscard()) takes it off the list into the dropped record. And
# the count of sightings each entry keeps (healsagain(), lib/healslist.sh), which the page shows as "seen N×".
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"

# Two open entries of area:engine and one a batch card holds, on the list.
actlist() {
  jq -cn '{id: "h00000000a1", time: "2026-11-20T00:00:00Z", card: "c5", issue: 5, repo: "main", area: "area:engine", finding: "[P2] a.sh:1 a slow poll. Proof: a.sh:1", why: "the next turn picks it up", effect: "self-heals", from: "review", freed: [90]},
    {id: "h00000000a2", time: "2026-11-21T00:00:00Z", card: "c6", issue: 6, repo: "main", area: "area:engine", finding: "[P3] b.sh:2 a stale label", why: "the next poll corrects it", effect: "cleanup", from: "review"},
    {id: "h00000000a3", time: "2026-11-21T00:00:00Z", card: "c6", issue: 6, repo: "main", area: "area:engine", finding: "[P2] c.sh:3 a late redraw", why: "it heals", effect: "self-heals", from: "review", batched: 77}' >> "$ST/selfheals.jsonl"
}
actids() { jq -rs 'map(objects | .id) | join(" ")' "$1" 2>/dev/null; } # the ids of a list file, in file order

# Bugs: "Move up to harm" filed nothing, or filed the finding without the follow-up label, its level or its area, so
# it was not built as a harm follow-up; the entry stayed on the list (a batch card would fix it a second time) or was
# lost (no trace of why it left); a second ask filed it again; an entry a batch card holds was filed beside that card;
# its freed mark stayed, so a retry of the batch card that gave it back took it back to the list.
t_healsharm() {
  local out
  setup '[]'; actlist
  out=$(loop heals harm h00000000a1 2>&1) || fail "heals harm h00000000a1 failed: $out"
  [ "$(jq -c '[.title, (.labels | map(.name))]' "$STUB/filed")" = '["[P2] a.sh:1 a slow poll. Proof: a.sh:1",["conveyor-followup","bug","P2","area:engine"]]' ] \
    && jq -r .body "$STUB/filed" | grep -qxF 'Finding: [P2] a.sh:1 a slow poll. Proof: a.sh:1' \
    && jq -r .body "$STUB/filed" | grep -qxF 'Kind: harm (moved up from the self-heals list, where the judge had sorted it as self-heals: the next turn picks it up)' \
    && jq -r .body "$STUB/filed" | grep -qF '(list entry h00000000a1)' \
    || fail "heals harm h00000000a1 did not file the finding as a harm follow-up with its level and area: $(cat "$STUB/filed" 2>&1)"
  [ "$(actids "$ST/selfheals.jsonl")" = 'h00000000a2 h00000000a3' ] \
    && [ "$(jq -c '[.id, .dropped.why, .dropped.filed, has("freed")]' "$ST/healsdropped.jsonl")" = '["h00000000a1","harm",100101,false]' ] \
    || fail "the entry moved up to harm did not leave the list for the dropped record with the card it was filed as, its freed mark gone: $(cat "$ST/selfheals.jsonl" "$ST/healsdropped.jsonl" 2>&1)"
  out=$(loop heals harm h00000000a1 2>&1); rc=$?
  [ $rc = 2 ] && [ "$(wc -l < "$STUB/filed")" = 1 ] && grep -qF 'has no open entry h00000000a1' <<<"$out" \
    || fail "a second heals harm of the same entry filed again, or did not exit 2 naming it (exit $rc): $out"
  out=$(loop heals harm h00000000a2 h00000000a3 2>&1); rc=$?
  [ $rc = 2 ] && [ "$(wc -l < "$STUB/filed")" = 1 ] && [ "$(actids "$ST/selfheals.jsonl")" = 'h00000000a2 h00000000a3' ] \
    || fail "heals harm of an open entry beside one a batch card holds filed or changed something (exit $rc): $out"
  # A cleanup entry is filed with no type label, as followups() files a cleanup finding: no test can fail on main for it.
  out=$(loop heals harm h00000000a2 2>&1) && [ "$(sed -n 2p "$STUB/filed" | jq -c '.labels | map(.name)')" = '["conveyor-followup","area:engine"]' ] \
    || fail "the cleanup entry moved up to harm was not filed without the type label (a P3 in a pack of three priorities gets none): $out $(sed -n 2p "$STUB/filed" 2>&1)"
}

# Bugs: with rules.followupissues off, "Move up to harm" opened a GitHub issue anyway, or filed no card; a finding that
# names a pipeline file was queued with no hold, so the engine's own code changed with no yes from the owner, as
# followups() holds such a finding.
t_healsharmnoissue() {
  local out
  setup '[]'; actlist; pipeentry
  loop control rules followupissues=off > /dev/null || fail "control rules followupissues=off was refused"
  out=$(loop heals harm h00000000a1 h00000000a4 2>&1) || fail "heals harm h00000000a1 h00000000a4 with followupissues off failed: $out"
  [ ! -e "$STUB/filed" ] && [ "$(jq -c '[.cards[] | [.held, (.body | test("\nCost to every card: not assessed"))]]' "$ST/testactions/cards.json" 2>/dev/null)" = '[[null,false],[true,true]]' ] \
    && [ "$(jq -rs 'map(.dropped.filed) | join(" ")' "$ST/healsdropped.jsonl")" = "$(jq -r '.cards | map(.id) | join(" ")' "$ST/testactions/cards.json")" ] \
    || fail "heals harm h00000000a1 h00000000a4 with followupissues off opened a GitHub issue, filed no card with none, did not hold only the card of the finding on conveyor/lib/run.sh, or the dropped entries do not name them: $out $(cat "$STUB/filed" "$ST/testactions/cards.json" "$ST/healsdropped.jsonl" 2>&1)"
}

# An entry whose finding names conveyor/lib/run.sh, with conveyor/lib/ the pack's pipeline files.
pipeentry() {
  tune '.pipelineFiles = ["conveyor/lib/"]'
  jq -cn '{id: "h00000000a4", time: "2026-11-21T00:00:00Z", card: "c7", issue: 7, repo: "main", area: "area:engine", finding: "[P2] conveyor/lib/run.sh:680 a late retry. Proof: run.sh:680", why: "the next turn retries", effect: "self-heals", from: "review"}' >> "$ST/selfheals.jsonl"
}

# Bug: "Move up to harm" filed the follow-up of a finding on a pipeline file as an issue with no hold, so the loop
# could build a change to the engine's own code before the owner said yes (followups() holds such a finding). The issue
# is made with the built label, which the pick skips, until the hold is in the control record.
t_healsharmpipe() {
  local out
  setup '[]'; actlist; pipeentry
  out=$(loop heals harm h00000000a4 h00000000a1 2>&1) || fail "heals harm h00000000a4 h00000000a1 failed: $out"
  [ "$(loop control | jq -c .held)" = '[100101]' ] \
    && [ "$(jq -sc 'map([.number, (.labels | map(.name) | index("conveyor-built") != null), (.body | test("\nCost to every card: not assessed"))])' "$STUB/filed")" = '[[100101,false,true],[100102,false,false]]' ] \
    || fail "heals harm h00000000a4 h00000000a1 did not hold only #100101 (the finding on conveyor/lib/run.sh) with its cost line, or left the built label on it: $out $(loop control | jq -c .held) $(cat "$STUB/filed")"
}

# Bug: "Move up to harm" read the list, filed the card and moved the entry with no lock held across the three, so a
# "Drop now" or a second "Move up to harm" of the same entry that came while the card was being filed acted on an
# entry already filed: dropped as the owner's (the harm card lost from the record) or filed twice. Both run inside gh's
# issue create ($STUB/create-cmd), the point between the list's read and its write, under `timeout 3`: a real process
# given time, as only a wait shows that they wait for the list's lock and do not get in first.
t_healsharmlock() {
  local out
  setup '[]'; actlist
  # shellcheck disable=SC2016 # expanded when gh sources it
  printf '%s\n' 'rm -f "$STUB/create-cmd"' \
    "timeout 3 env CONVEYOR_MAIN='$R' CONVEYOR_CARDS='$T/$CASE/cards' bash '$SRC/conveyor.sh' heals drop h00000000a1 > '$STUB/drop-out' 2>&1 & d=\$!" \
    "timeout 3 env CONVEYOR_MAIN='$R' CONVEYOR_CARDS='$T/$CASE/cards' bash '$SRC/conveyor.sh' heals harm h00000000a1 > '$STUB/harm-out' 2>&1; echo \$? > '$STUB/harm-rc'" \
    "wait \$d; echo \$? > '$STUB/drop-rc'" > "$STUB/create-cmd"
  out=$(loop heals harm h00000000a1 2>&1) || fail "heals harm h00000000a1 failed: $out"
  [ "$(cat "$STUB/drop-rc" "$STUB/harm-rc" 2>&1 | tr '\n' ' ')" = '124 124 ' ] \
    || fail "a heals drop and a heals harm of h00000000a1 asked while its card was being filed did not wait for it (exit $(cat "$STUB/drop-rc" "$STUB/harm-rc" 2>&1 | tr '\n' ' ')): $(cat "$STUB/drop-out" "$STUB/harm-out" 2>&1)"
  [ "$(wc -l < "$STUB/filed")" = 1 ] && [ "$(jq -sc 'map([.id, .dropped.why])' "$ST/healsdropped.jsonl")" = '[["h00000000a1","harm"]]' ] \
    || fail "a heals drop or heals harm of h00000000a1 asked while its card was being filed filed it again or dropped it: $(cat "$STUB/filed" "$ST/healsdropped.jsonl" 2>&1)"
}

# Bug: "Move up to harm" of a finding on a pipeline file asked for its hold (`control hold`, the records' lock) with the
# list's lock still held, while `retry` of a shut batch card takes the records' lock and then the list's (healstake(),
# lib/followups.sh): each waited for the other. The retry of #90 (h00000000a1 is freed by it) starts inside gh's issue
# create ($STUB/create-cmd), between the list's read and its write, under `timeout 5`: a real process, as only a wait
# shows the two do not deadlock. The create waits (polls, at most 5 s) until the retry holds the records' lock: retry
# takes it once, in `locked again`, and keeps it until it has the list's lock, so the hold is asked behind it. The
# retry's own output goes to /dev/null: the promotion reads gh's output to its end, so an open pipe would stall it.
# The wait's result is kept in $STUB/retry-locked and checked: gh files the issue even when the wait gives up, so a
# retry that started late (after the promotion had ended) would otherwise pass without the two ever meeting.
t_healsharmretry() {
  local out
  setup '[]'; actlist; pipeentry
  landed 90 | jq -c '.card = "c90" | (.step = "picked"), (.step = "blocked" | .result = "blocked" | .reason = "build: it failed")' >> "$ST/cards.jsonl"
  # shellcheck disable=SC2016 # expanded when gh sources it
  printf '%s\n' 'rm -f "$STUB/create-cmd"' \
    "(timeout 5 env CONVEYOR_MAIN='$R' CONVEYOR_CARDS='$T/$CASE/cards' bash '$SRC/conveyor.sh' retry 90 > '$STUB/retry-out' 2>&1; echo \$? > '$STUB/retry-rc') 9>&- > /dev/null 2>&1 &" \
    ". '$SRC/tests/wait.sh'; WAIT_CEILING=5 wait_until \"! flock -n '$ST/cards.jsonl' true\"; echo \$? > '$STUB/retry-locked'" > "$STUB/create-cmd"
  out=$(timeout 20 env CONVEYOR_MAIN="$R" CONVEYOR_CARDS="$T/$CASE/cards" bash "$SRC/conveyor.sh" heals harm h00000000a4 2>&1) || fail "heals harm h00000000a4 failed: $out"
  wait_until '[ -s "$STUB/retry-rc" ]' # the retry's exit, written as it ends
  [ "$(cat "$STUB/retry-locked" 2>&1)" = 0 ] || fail "heals harm h00000000a4: gh's issue create never saw the retry 90 hold the records' lock (wait exit $(cat "$STUB/retry-locked" 2>&1)), so the two did not meet: $out $(cat "$STUB/retry-out" 2>&1)"
  [ "$(cat "$STUB/retry-rc" 2>&1)" = 0 ] && [ "$(loop control | jq -c .held)" = '[100101]' ] \
    && [ "$(jq -rs 'map(select(.id == "h00000000a1") | .batched) | join(" ")' "$ST/selfheals.jsonl")" = 90 ] \
    || fail "heals harm h00000000a4 (a pipeline finding, so it asks control hold) and a retry 90 that holds the records' lock waited for each other, or one did not do its work (retry exit $(cat "$STUB/retry-rc" 2>&1)): $out $(cat "$STUB/retry-out" 2>&1) held $(loop control | jq -c .held) $(cat "$ST/selfheals.jsonl")"
}

# Bugs: the Board's batch sheet filed every entry of the area, not only the entries it kept, so one the owner left out
# left the list; an entry added from another area was not filed; its title, its level or File held was not kept (the
# card queued with the pack's last priority); an id that is not an open entry was filed anyway or let the others file;
# a named entry whose card is in flight (c9) was filed, or left the list unsaid; File held made the issue with no built
# label, so the picker could take it before its hold was saved; a level the sheet never offers (P0, P1) was taken.
t_healsbatchsheet() {
  local out rc p
  setup '[]'; actlist
  jq -cn '{id: "h00000000a5", time: "2026-11-21T00:00:00Z", card: "c8", issue: 8, repo: "main", area: "area:board", finding: "[P2] d.js:4 a late tile", why: "the next poll redraws it", effect: "self-heals", from: "review"},
    {id: "h00000000a6", time: "2026-11-21T00:00:00Z", card: "c9", issue: 9, repo: "main", area: "area:board", finding: "[P2] e.js:5 a late chip", why: "it heals", effect: "self-heals", from: "review"}' >> "$ST/selfheals.jsonl"
  landed 9 | jq -c '.card = "c9" | .step = "picked"' >> "$ST/cards.jsonl"
  out=$(loop heals batch area:engine h00000000a1 h00000000a3 2>&1); rc=$?
  [ $rc = 2 ] && [ ! -e "$STUB/filed" ] && grep -qF 'has no open entry h00000000a3' <<<"$out" \
    || fail "heals batch area:engine h00000000a1 h00000000a3 (a3 held by a batch card) filed something, or did not exit 2 naming a3 (exit $rc): $out"
  for p in P0 P1; do
    out=$(loop heals batch area:engine --prio "$p" h00000000a1 2>&1); rc=$?
    [ $rc = 2 ] && [ ! -e "$STUB/filed" ] || fail "heals batch area:engine --prio $p h00000000a1 filed a card, or did not exit 2 (exit $rc): $out"
  done
  # stub: the create's arguments, as the label the issue was made with is taken off it later
  echo 'printf "%s\n" "$*" >> "$STUB/create-args"' > "$STUB/create-cmd"
  out=$(loop heals batch area:engine --held --prio P3 --title 'Self-heals batch: engine (2 entries)' h00000000a1 h00000000a5 h00000000a6 2>&1) \
    && grep -qF '; 1 wait for their card to land or close and stay on the list' <<<"$out" \
    || fail "heals batch area:engine --held --prio P3 --title ... h00000000a1 h00000000a5 h00000000a6 failed, or did not say that a6 waits: $out"
  # awaiting-deploy: the fixture pack's built label, which the picker skips
  head -n 1 "$STUB/create-args" | grep -qF -- '--label awaiting-deploy --body' \
    || fail "heals batch area:engine --held ... made its issue with no built label (awaiting-deploy), so the picker could take it before the hold: $(head -c 300 "$STUB/create-args")"
  rm -f "$STUB/create-cmd"
  [ "$(jq -c '[.title, (.labels | map(.name))]' "$STUB/filed")" = '["Self-heals batch: engine (2 entries)",["bug","area:engine"]]' ] \
    && jq -r .body "$STUB/filed" | grep -qF 'list entry h00000000a5' && ! jq -r .body "$STUB/filed" | grep -qF 'list entry h00000000a2' \
    && [ "$(loop control | jq -c .held)" = '[100101]' ] \
    || fail "heals batch area:engine --held --prio P3 --title ... h00000000a1 h00000000a5 did not file only a1 and a5 under its title, with no priority label (P3 of three), held and the built label off: $out $(cat "$STUB/filed") $(loop control | jq -c .held)"
  [ "$(jq -rs 'map(objects | "\(.id)=\(.batched)") | join(" ")' "$ST/selfheals.jsonl")" = 'h00000000a1=100101 h00000000a2=null h00000000a3=77 h00000000a5=100101 h00000000a6=null' ] \
    || fail "after heals batch ... h00000000a1 h00000000a5, the entries kept are not marked with the card, or a2, left out, or a6, waiting, left the list: $(cat "$ST/selfheals.jsonl")"
  out=$(loop heals batch area:engine --prio P2 h00000000a2 2>&1) && [ "$(sed -n 2p "$STUB/filed" | jq -c '[.title, (.labels | map(.name))]')" = '["Self-heals batch: 1 finding of area:engine",["P2","area:engine"]]' ] \
    && [ "$(loop control | jq -c .held)" = '[100101]' ] \
    || fail "heals batch area:engine --prio P2 h00000000a2 did not file the cleanup entry queued, with the P2 label: $out $(sed -n 2p "$STUB/filed" 2>&1) $(loop control | jq -c .held)"
}

# Bug: File and queue filed an ordinary issue, so a project whose new issues start held (`control start held`) held
# it at its first sight (adopted(), lib/control.sh) though the owner asked to queue it. The real picker's adopt reads
# the open issues with the filed one (list-filed) and must pick it.
t_healsbatchqueue() {
  local out p
  setup '[]'; actlist
  loop control start held > /dev/null || fail "control start held was refused"
  touch "$STUB/list-filed"
  out=$(loop heals batch area:engine --queue --prio P2 h00000000a1 2>&1) || fail "heals batch area:engine --queue --prio P2 h00000000a1 failed: $out"
  jq -s '.' "$STUB/filed" > "$STUB/open.json"
  p=$(loop pick --dry --issues "$STUB/open.json" --state "$ST" 2>&1)
  [ "$p" = 100101 ] && [ "$(loop control | jq -c '[.held, (.startSeen | index(100101) != null)]')" = '[[],true]' ] \
    || fail "after heals batch area:engine --queue ... with new issues held, #100101 was held or not picked (pick: $p): $out $(loop control)"
}

# Bug: with rules.followupissues off, File held started the batch card with no GitHub issue unheld (healsbatch() did
# not pass --held to tcput(), lib/heals.sh), so the loop built a card the owner filed held; or File and queue held it.
t_healsbatchheldnoissue() {
  local out
  setup '[]'; actlist
  loop control rules followupissues=off > /dev/null || fail "control rules followupissues=off was refused"
  out=$(loop heals batch area:engine --held h00000000a1 2>&1) && out+=$(loop heals batch area:engine --queue h00000000a2 2>&1) \
    || fail "heals batch area:engine --held h00000000a1, then --queue h00000000a2, with followupissues off failed: $out"
  [ ! -e "$STUB/filed" ] && [ "$(jq -c '[.cards[] | [.label, .held]]' "$ST/testactions/cards.json" 2>&1)" = '[["Self-heals batch: area:engine",true],["Self-heals batch: area:engine",null]]' ] \
    || fail "heals batch area:engine --held h00000000a1 with followupissues off did not start its card held with no GitHub issue, or --queue h00000000a2 started its card held: $out $(cat "$STUB/filed" "$ST/testactions/cards.json" 2>&1)"
}

# Bug: a docs sweep from the Board's sheet filed every entry of its area, also the one the owner left out, which left
# the docs list unfixed.
t_healsdocssheet() {
  local out
  setup '[]'
  jq -cn '{id: "d00000000d1", time: "2026-11-21T00:00:00Z", card: "c5", issue: 5, repo: "main", area: "area:docs", finding: "[P3] docs/a.md:1 omits a", why: "drift", effect: "docs drift", from: "review"},
    {id: "d00000000d2", time: "2026-11-21T00:00:00Z", card: "c6", issue: 6, repo: "main", area: "area:docs", finding: "[P3] docs/b.md:2 omits b", why: "drift", effect: "docs drift", from: "review"}' > "$ST/docsdrift.jsonl"
  out=$(loop heals docs area:docs --queue --title 'Docs sweep: docs (1 entry)' d00000000d2 2>&1) || fail "heals docs area:docs --queue --title ... d00000000d2 failed: $out"
  [ "$(jq -r .title "$STUB/filed")" = 'Docs sweep: docs (1 entry)' ] && jq -r .body "$STUB/filed" | grep -qF 'list entry d00000000d2' \
    && ! jq -r .body "$STUB/filed" | grep -qF 'list entry d00000000d1' \
    && [ "$(jq -rs 'map("\(.id)=\(.batched)") | join(" ")' "$ST/docsdrift.jsonl")" = 'd00000000d1=null d00000000d2=100101' ] \
    || fail "heals docs area:docs ... d00000000d2 did not file d2 alone, or a1 left the docs list: $out $(cat "$STUB/filed" "$ST/docsdrift.jsonl")"
}

# Bugs: "Drop now" erased the entry (no trace of it), left it on the list, or dropped some entries of an ask that named
# one it could not drop; a dropped finding a review lists again stayed dropped, so it was lost.
t_healsdrop() {
  local out
  setup '[]'; actlist
  out=$(loop heals drop h00000000a1 h-none 2>&1); rc=$?
  [ $rc = 2 ] && [ "$(actids "$ST/selfheals.jsonl")" = 'h00000000a1 h00000000a2 h00000000a3' ] && [ ! -s "$ST/healsdropped.jsonl" ] \
    || fail "heals drop of an entry the list does not have beside one it has dropped something, or did not exit 2 (exit $rc): $out"
  out=$(loop heals drop h00000000a1 2>&1) || fail "heals drop h00000000a1 failed: $out"
  [ "$(actids "$ST/selfheals.jsonl")" = 'h00000000a2 h00000000a3' ] && [ "$(jq -c '[.id, .dropped.why, .finding]' "$ST/healsdropped.jsonl")" = '["h00000000a1","dropped","[P2] a.sh:1 a slow poll. Proof: a.sh:1"]' ] \
    || fail "the entry dropped now did not leave the list for the dropped record: $(cat "$ST/selfheals.jsonl" "$ST/healsdropped.jsonl" 2>&1)"
  fx_in "healsadd c9 9 area:engine 'it heals' '[P2] a.sh:1 a slow poll. Proof: a.sh:1' review self-heals" > /dev/null
  [ "$(actids "$ST/selfheals.jsonl")" = 'h00000000a2 h00000000a3 h00000000a1' ] && [ ! -s "$ST/healsdropped.jsonl" ] \
    || fail "the dropped finding a review listed again did not take its entry back to the list: $(cat "$ST/selfheals.jsonl" "$ST/healsdropped.jsonl" 2>&1)"
}

# Bug: an entry moved up to harm that a review listed again keeps that move only in its expired mark, and "Drop now"
# (healsgone()) and the expiry (healsexpiry()) erased the mark with its filed card, so the Board's harm tile stopped
# counting the move. An expired mark that is no move up to harm still goes.
t_healsdropharm() {
  local out mark='{"time": "2026-11-22T00:00:00Z", "why": "harm", "filed": 811}'
  setup '[]'
  jq -cn --argjson m "$mark" '{id: "h00000000b1", time: "2026-11-20T00:00:00Z", card: "c5", issue: 5, repo: "main", area: "area:engine", finding: "F-b1", why: "w", effect: "self-heals", from: "review", expired: $m},
    {id: "h00000000b2", time: "2026-11-20T00:00:00Z", card: "c5", issue: 5, repo: "main", area: "area:engine", finding: "F-b2", why: "w", effect: "self-heals", from: "review", expired: {time: "2026-11-21T00:00:00Z", why: "expired"}},
    {id: "h00000000b3", time: "2000-01-01T00:00:00Z", card: "c5", issue: 5, repo: "main", area: "area:engine", finding: "F-b3", why: "w", effect: "self-heals", from: "review", expired: $m}' > "$ST/selfheals.jsonl"
  out=$(loop heals drop h00000000b1 h00000000b2 2>&1) || fail "heals drop h00000000b1 h00000000b2 failed: $out"
  fx_in healsexpire > /dev/null
  [ "$(jq -sc 'map([.id, .dropped.why, .expired])' "$ST/healsdropped.jsonl")" = "$(jq -cn --argjson m "$mark" '[["h00000000b1", "dropped", $m], ["h00000000b2", "dropped", null], ["h00000000b3", "expired", $m]]')" ] \
    || fail "heals drop h00000000b1 h00000000b2 and healsexpire (h00000000b3, listed in 2000) did not keep the move up to harm (expired why harm) and drop the other expired mark: $(cat "$ST/selfheals.jsonl" "$ST/healsdropped.jsonl" 2>&1)"
}

# Bug: an entry kept no count of its sightings, so the Self-heals page could not say how often a finding came back.
# Each sighting counts one: a listing again, and a sighting of an entry that already expired, in the dropped record.
t_healssightings() {
  setup '[]'; : > "$ST/selfheals.jsonl"
  fx_in "healsadd c1 1 area:engine w 'F-one Proof: a.sh:2' review self-heals" > /dev/null
  [ "$(jq -c .sightings "$ST/selfheals.jsonl")" = null ] || fail "a new entry counts a sighting: $(cat "$ST/selfheals.jsonl")"
  fx_in "healsadd c2 2 area:engine w 'F-one Proof: a.sh:2' review self-heals" > /dev/null
  fx_in "healsadd c3 3 area:engine w 'F-one Proof: a.sh:2' review self-heals" > /dev/null
  [ "$(jq -c .sightings "$ST/selfheals.jsonl")" = 2 ] || fail "two listings again did not count two sightings: $(cat "$ST/selfheals.jsonl")"
  jq -c '. + {dropped: {time: "2026-11-01T00:00:00Z", why: "expired"}}' "$ST/selfheals.jsonl" > "$ST/healsdropped.jsonl"; : > "$ST/selfheals.jsonl"
  fx_in "healsseen c4 4 'F-one Proof: a.sh:2'" > /dev/null
  [ "$(jq -c .sightings "$ST/healsdropped.jsonl")" = 3 ] || fail "a sighting of an expired entry did not count: $(cat "$ST/healsdropped.jsonl")"
}
