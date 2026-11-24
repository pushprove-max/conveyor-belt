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
