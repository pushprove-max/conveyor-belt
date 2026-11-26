#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 120
# Engine cases: an entry of the self-heals list that nobody fixed, filed in a batch card or saw again for
# rules.healsdays days (30 at first) leaves the list for the dropped record (healsexpire(), lib/heals.sh; issue 1561).
# Bug it catches: the list only grew, so findings nobody would fix piled up and the list stopped being read.
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"

# The clock of these cases: 2026-12-01T00:00:00Z. The entries are 31 days old (2026-10-31), 10 days old (2026-11-21).
HNOW=$(jq -rn '"2026-12-01T00:00:00Z" | fromdateiso8601')
# One list line: <id> <finding> [<jq object merged in>]
hline() { jq -cn --arg i "$1" --arg f "$2" '{id: $i, card: "c1-7", issue: 7, repo: "r", area: "area:engine", finding: $f, why: "w", effect: "self-heals", from: "review"} + ($ARGS.positional[0] | if . == "" then {} else fromjson end)' --args "${3:-}"; }
# healsexpire() or healsadd() as the loop runs them at HNOW.
hrun() { fx_in "export CONVEYOR_NOW=$HNOW; $1"; }
# The ids of a list file, one line, in file order.
hids() { jq -rs 'map(objects | .id) | join(" ")' "$1" 2>/dev/null; }

# The Done-when case: 31 days old with no sighting leaves; seen again 10 days ago stays (although it is 40 days old); no
# date stays and is dated now, so it leaves only 30 days after this run; one a batch card holds stays however old.
t_healsexpire() {
  local HNOW=$HNOW
  judging '[]'
  { hline h-old 'F-old' '{"time": "2026-10-31T00:00:00Z"}'
    hline h-seen 'F-seen' '{"time": "2026-10-22T00:00:00Z", "seen": "2026-11-21T00:00:00Z"}'
    hline h-none 'F-none'
    hline h-batch 'F-batch' '{"time": "2026-01-01T00:00:00Z", "batched": 100101}'; } > "$ST/selfheals.jsonl"
  hrun healsexpire
  [ "$RC" = 0 ] && [ "$(hids "$ST/selfheals.jsonl")" = 'h-seen h-none h-batch' ] \
    || fail "the 31-day-old entry did not leave the list alone (rc $RC): $(cat "$T/$CASE/run.out" "$ST/selfheals.jsonl" 2>&1)"
  [ "$(jq -rc '[.id, .dropped.time, .dropped.why, .finding] | tojson' "$ST/healsdropped.jsonl" 2>&1)" = '["h-old","2026-12-01T00:00:00Z","expired","F-old"]' ] \
    || fail "the entry that left is not kept in the dropped record with its date and why: $(cat "$ST/healsdropped.jsonl" 2>&1)"
  [ "$(jq -r 'select(.id == "h-none") | .seen' "$ST/selfheals.jsonl")" = 2026-12-01T00:00:00Z ] \
    || fail "the entry with no date was not dated at this run: $(cat "$ST/selfheals.jsonl")"
  # Thirty days on (2026-12-31), the entry that was dated by that run and nobody saw leaves, and the seen one too (70 days since its time, 40 since its sighting).
  HNOW=$((HNOW + 30 * 86400)); hrun healsexpire
  [ "$RC" = 0 ] && [ "$(hids "$ST/selfheals.jsonl")" = h-batch ] && [ "$(hids "$ST/healsdropped.jsonl")" = 'h-old h-seen h-none' ] \
    || fail "30 days on, the dated entries did not all leave (rc $RC): $(cat "$T/$CASE/run.out" "$ST/selfheals.jsonl" "$ST/healsdropped.jsonl" 2>&1)"
}

# A finding the judge matches to an entry again resets its days (healsadd() takes the existing entry), and one that
# comes back after it expired takes its line back from the dropped record: it is matched to it, not listed twice.
# Bug it catches: the entry's id names the card, so the same finding raised on a later card (another card, another
# issue) was a new entry: the old one kept its date and expired, and could not be taken back from the dropped record;
# and the finding's Proof names a line of code, so a Proof moved to another line made the finding another entry.
t_healsseen() {
  local HNOW=$HNOW id
  judging '[]'
  : > "$ST/selfheals.jsonl"
  hrun "healsadd c1-7 7 area:engine w 'F-keep Proof: a.sh:2' review self-heals"; [ "$RC" = 0 ] || fail "healsadd failed: $(cat "$T/$CASE/run.out")"
  id=$(cat "$T/$CASE/run.out")
  HNOW=$((HNOW + 25 * 86400)); hrun "healsadd c2-9 9 area:engine w 'F-keep Proof: a.sh:9' review self-heals"
  [ "$RC" = 0 ] && [ "$(cat "$T/$CASE/run.out")" = "$id" ] && [ "$(hids "$ST/selfheals.jsonl")" = "$id" ] \
    || fail "the same finding on a later card (c2-9), its Proof moved, was not matched to the entry it was found as (rc $RC; the id printed is the entry's own): $(cat "$T/$CASE/run.out" "$ST/selfheals.jsonl" 2>&1)"
  # A later review round of c2-9 lists the finding again: the entry c2-9 now holds, not a second entry.
  hrun "healsadd c2-9 9 area:engine w 'F-keep Proof: a.sh:9' review self-heals"
  [ "$RC" = 0 ] && [ "$(cat "$T/$CASE/run.out")" = "$id" ] && [ "$(hids "$ST/selfheals.jsonl")" = "$id" ] \
    || fail "the second listing of the finding by c2-9 (a later round) was not matched to the entry c2-9 holds now, so it listed a duplicate (rc $RC): $(cat "$T/$CASE/run.out" "$ST/selfheals.jsonl" 2>&1)"
  HNOW=$((HNOW + 25 * 86400)); hrun healsexpire
  [ "$RC" = 0 ] && [ "$(hids "$ST/selfheals.jsonl")" = "$id" ] && [ ! -s "$ST/healsdropped.jsonl" ] \
    || fail "an entry seen again 25 days after it was added left the list 50 days on (rc $RC): $(cat "$T/$CASE/run.out" "$ST/selfheals.jsonl" "$ST/healsdropped.jsonl" 2>&1)"
  HNOW=$((HNOW + 31 * 86400)); hrun healsexpire
  [ "$(hids "$ST/healsdropped.jsonl")" = "$id" ] && [ ! -s "$ST/selfheals.jsonl" ] || fail "the entry did not expire 31 days after it was seen: $(cat "$ST/selfheals.jsonl" "$ST/healsdropped.jsonl" 2>&1)"
  hrun 'healsadd c3-11 11 area:engine w F-keep review self-heals'
  [ "$RC" = 0 ] && [ "$(cat "$T/$CASE/run.out")" = "$id" ] && [ "$(hids "$ST/selfheals.jsonl")" = "$id" ] && [ ! -s "$ST/healsdropped.jsonl" ] && [ "$(jq -r .dropped "$ST/selfheals.jsonl")" = null ] \
    || fail "the finding that came back on a third card did not take its entry back from the dropped record, alone (rc $RC): $(cat "$T/$CASE/run.out" "$ST/selfheals.jsonl" "$ST/healsdropped.jsonl" 2>&1)"
}

# The age is the Rules setting rules.healsdays: 10 days drops the 11-day-old entry but keeps one of 9 days; a value out of 1 to 3650 is refused and nothing changes.
t_healsdays() {
  local out
  judging '[]'
  { hline h-11 F-11 '{"time": "2026-11-20T00:00:00Z"}'; hline h-9 F-9 '{"time": "2026-11-22T00:00:00Z"}'; } > "$ST/selfheals.jsonl"
  for v in 0 3651 x 1.5 -3; do
    out=$(loop control rules "healsdays=$v" 2>&1) && fail "control rules healsdays=$v was accepted: $out"
  done
  fx_in 'ctl | jq -r .rules.healsdays'; [ "$(cat "$T/$CASE/run.out")" = 30 ] || fail "a refused value changed the rule: $(cat "$T/$CASE/run.out")"
  out=$(loop control rules healsdays=10 2>&1) || fail "control rules healsdays=10 failed: $out"
  hrun healsexpire
  [ "$RC" = 0 ] && [ "$(hids "$ST/selfheals.jsonl")" = h-9 ] && [ "$(hids "$ST/healsdropped.jsonl")" = h-11 ] \
    || fail "with healsdays=10 the 11-day-old entry did not leave and the 9-day-old one stay (rc $RC): $(cat "$T/$CASE/run.out" "$ST/selfheals.jsonl" "$ST/healsdropped.jsonl" 2>&1)"
}

# A finding whose Proof says it was seen in real logs is ruled harm and goes to no list, yet it is the finding of an
# entry of the list seen again: the entry's days start over, and it is of the card that saw it. The entry was listed with
# a Proof that names code, and a line was added above the code since (a.txt:2 is a.txt:3), so the finding is told by its
# words alone, without its Proof or its line number. Bugs it catches: such a sighting took the harm path of judged(), which
# skips healsput(), so the entry expired 30 days after it was listed although the logs showed it again; and healsseen()
# compared the whole line, Proof and line number too, so the logs' wording was never the listed finding.
t_healslogseen() {
  local listed='[P2] a.txt:2 a slot stays over its cap. Proof: a.txt:2' seen='[P2] a.txt:3 a slot stays over its cap. Proof: seen in the logs of card c5 at 10:02'
  judging '[]'
  : > "$ST/selfheals.jsonl"
  hrun "healsadd c4 4 area:engine w '$listed' review self-heals"; [ "$RC" = 0 ] || fail "healsadd failed: $(cat "$T/$CASE/run.out")"
  jq -c '.time = "2026-01-01T00:00:00Z"' "$ST/selfheals.jsonl" > "$ST/selfheals.new" && mv -f "$ST/selfheals.new" "$ST/selfheals.jsonl" || fail "the entry could not be dated back"
  printf '%s\n' "$seen" 'USER-VISIBLE: no' 'VERDICT: NO-GO' > "$STUB/review"
  printf '%s\n' 'F1 ACCEPT: self-heals: the slot frees at the next turn. Cost to every card: none' > "$STUB/judge.1"
  JUDGEWRAP="export CONVEYOR_NOW=$HNOW" judgeone 7 "$STUB/review" fix
  grep -qxF "$seen" <(jr 7) || fail "the finding seen in the logs is not left as a harm finding of the review: $(jr 7)"
  [ "$(jq -cs 'map([.time, .seen, .card, .issue])' "$ST/selfheals.jsonl")" = '[["2026-01-01T00:00:00Z","2026-12-01T00:00:00Z","c7",7]]' ] \
    || fail "the entry was not seen again, by the card that saw it, when the judge ruled its finding harm for the logs: $(cat "$ST/selfheals.jsonl")"
}

# A finding seen in the logs after its entry expired leaves the entry in the dropped record: the finding is ruled harm,
# so the card's review files it as a follow-up, and an entry on the list too would let a batch card fix it a second time.
# Bug it catches: the sighting took the entry back to the list, so one finding was both a follow-up and a listed entry;
# and the same finding listed live at another line (a.txt:3, 10 days before the other expired) took the sighting alone,
# so the expired entry of a.txt:2 never noted it.
t_healslogdropped() {
  local listed='[P2] a.txt:2 a slot stays over its cap. Proof: a.txt:2' seen='[P2] a.txt:2 a slot stays over its cap. Proof: seen in the logs of card c5 at 10:02' HNOW=$HNOW id live
  judging '[]'
  : > "$ST/selfheals.jsonl"
  HNOW=$((HNOW - 31 * 86400)); hrun "healsadd c4 4 area:engine w '$listed' review self-heals"; [ "$RC" = 0 ] || fail "healsadd failed: $(cat "$T/$CASE/run.out")"
  id=$(cat "$T/$CASE/run.out")
  HNOW=$((HNOW + 21 * 86400)); hrun "healsadd c4 4 area:engine w '[P2] a.txt:3 a slot stays over its cap. Proof: a.txt:3' review self-heals"; [ "$RC" = 0 ] || fail "healsadd failed: $(cat "$T/$CASE/run.out")"
  live=$(cat "$T/$CASE/run.out"); HNOW=$((HNOW + 10 * 86400)); hrun healsexpire
  [ "$id" != "$live" ] && [ "$(hids "$ST/healsdropped.jsonl")" = "$id" ] && [ "$(hids "$ST/selfheals.jsonl")" = "$live" ] \
    || fail "the entry of a.txt:2 did not expire alone beside the live entry of a.txt:3 ($id, $live): $(cat "$ST/selfheals.jsonl" "$ST/healsdropped.jsonl" 2>&1)"
  printf '%s\n' "$seen" 'USER-VISIBLE: no' 'VERDICT: NO-GO' > "$STUB/review"
  printf '%s\n' 'F1 ACCEPT: self-heals: the slot frees at the next turn. Cost to every card: none' > "$STUB/judge.1"
  JUDGEWRAP="export CONVEYOR_NOW=$HNOW" judgeone 7 "$STUB/review" fix
  [ "$(hids "$ST/selfheals.jsonl")" = "$live" ] && [ "$(hids "$ST/healsdropped.jsonl")" = "$id" ] \
    || fail "a finding ruled harm for the logs took its expired entry back to the list: $(cat "$ST/selfheals.jsonl" "$ST/healsdropped.jsonl" 2>&1)"
  [ "$(jq -c '[.seen, .dropped.why]' "$ST/healsdropped.jsonl")" = '["2026-12-01T00:00:00Z","expired"]' ] \
    || fail "the finding seen in the logs after its entry expired is not matched to the dropped record (its seen is the sighting): $(cat "$ST/healsdropped.jsonl")"
  [ "$(jq -c '[.seen, .card]' "$ST/selfheals.jsonl")" = '[null,"c4"]' ] \
    || fail "the sighting of [P2] a.txt:2 in the logs also reset the days of the live entry of a.txt:3 (its seen and card changed): $(cat "$ST/selfheals.jsonl")"
}

# An audit's finding that moved to another line after its entry expired takes its entry back with the line it has now,
# although a later review saw the finding before it expired (which made that card the entry's card).
# Bug it catches: the entry came back with its old line (a.sh:1), so the sort counted the audit's finding (a.sh:2) as
# not listed, and the audit, with that one finding, stayed open.
t_healssortmoved() {
  local a b HNOW=$HNOW
  judging '[]'
  : > "$ST/selfheals.jsonl"
  HNOW=$((HNOW - 45 * 86400)); hrun "healsadd '#23' 23 area:engine w '[P2] a.sh:1 the wait is one turn longer' sort self-heals"; [ "$RC" = 0 ] || fail "healsadd failed: $(cat "$T/$CASE/run.out")"
  a=$(cat "$T/$CASE/run.out")
  HNOW=$((HNOW + 14 * 86400)); hrun "healsseen c5-5 5 '[P2] a.sh:1 the wait is one turn longer'"; [ "$RC" = 0 ] || fail "healsseen failed: $(cat "$T/$CASE/run.out")"
  [ "$(jq -r .card "$ST/selfheals.jsonl")" = c5-5 ] || fail "the later review did not become the entry's card (the case sets up nothing without it): $(cat "$ST/selfheals.jsonl")"
  HNOW=$((HNOW + 31 * 86400)); hrun healsexpire
  [ "$(hids "$ST/healsdropped.jsonl")" = "$a" ] && [ ! -s "$ST/selfheals.jsonl" ] || fail "the entry did not expire: $(cat "$ST/selfheals.jsonl" "$ST/healsdropped.jsonl" 2>&1)"
  hrun "healsadd '#23' 23 area:engine w '[P2] a.sh:2 the wait is one turn longer' sort self-heals"; [ "$RC" = 0 ] || fail "healsadd failed: $(cat "$T/$CASE/run.out")"
  b=$(cat "$T/$CASE/run.out")
  [ "$a" = "$b" ] && [ "$(hids "$ST/selfheals.jsonl")" = "$a" ] && [ ! -s "$ST/healsdropped.jsonl" ] \
    && [ "$(jq -r .finding "$ST/selfheals.jsonl")" = '[P2] a.sh:2 the wait is one turn longer' ] \
    || fail "the audit's finding, moved to a.sh:2, did not take its expired entry back with that line ($a, $b): $(cat "$ST/selfheals.jsonl" "$ST/healsdropped.jsonl" 2>&1)"
}

# A finding the sort sends to the list again takes its expired entry back, and when the sort then leaves the finding in its
# issue (GitHub refused the close: healsdrop()), the entry goes back to the dropped record as it expired, not erased.
# Bug it catches: healsdrop() removed the live copy and the dropped record no longer held the entry, so a failed close
# lost it from both files.
t_healsdropback() {
  local f='[P3] a.txt:5 a stale label' id
  judging '[]'
  : > "$ST/selfheals.jsonl"
  HNOW=$((HNOW - 31 * 86400)); hrun "healsadd c4 7 area:engine w '$f' sort cleanup"; [ "$RC" = 0 ] || fail "healsadd failed: $(cat "$T/$CASE/run.out")"
  id=$(cat "$T/$CASE/run.out"); HNOW=$((HNOW + 31 * 86400)); hrun healsexpire
  [ "$(hids "$ST/healsdropped.jsonl")" = "$id" ] || fail "the entry did not expire: $(cat "$ST/selfheals.jsonl" "$ST/healsdropped.jsonl" 2>&1)"
  hrun "healsadd c4 7 area:engine w '$f' sort cleanup"
  [ "$RC" = 0 ] && [ "$(hids "$ST/selfheals.jsonl")" = "$id" ] && [ ! -s "$ST/healsdropped.jsonl" ] \
    || fail "the sort's finding did not take its expired entry back (rc $RC): $(cat "$T/$CASE/run.out" "$ST/selfheals.jsonl" "$ST/healsdropped.jsonl" 2>&1)"
  hrun "healsdrop $id"
  [ "$RC" = 0 ] && [ ! -s "$ST/selfheals.jsonl" ] && [ "$(jq -rc '[.id, .dropped.why, .dropped.time, .expired] | tojson' "$ST/healsdropped.jsonl" 2>&1)" = "[\"$id\",\"expired\",\"2026-12-01T00:00:00Z\",null]" ] \
    || fail "the entry the sort took back and then dropped is not in the dropped record as it expired (rc $RC): $(cat "$T/$CASE/run.out" "$ST/selfheals.jsonl" "$ST/healsdropped.jsonl" 2>&1)"
}

# The same for the sort of the queued follow-ups: a card whose finding the judge rules harm, and that an entry names too,
# is seen again. Bug it catches: healsapply() let a harm ruling go by with no word to the list. The sort runs at the
# real time, so the entry is dated back, and its sighting is any date after that.
t_healssortseen() {
  local f='[P2] a.txt:1 a slow poll until the next turn. Proof: a.txt:1'
  judging '[]'; rm -f "$ST/healssort.jsonl"
  fubody "$f" > "$T/$CASE/b1"
  fx_in 'tcadd "" "finding 1" "$(cat "$T/$CASE/b1")" "" "Review follow-up of #3" "[\"conveyor-followup\",\"bug\",\"area:engine\"]" 3 || exit 1'
  [ "$RC" = 0 ] || fail "the queued follow-up card could not be made: $(cat "$T/$CASE/run.out")"
  : > "$ST/selfheals.jsonl"
  hrun "healsadd c5 5 area:engine w '$f' review self-heals"; [ "$RC" = 0 ] || fail "healsadd failed: $(cat "$T/$CASE/run.out")"
  jq -c '.time = "2026-01-01T00:00:00Z"' "$ST/selfheals.jsonl" > "$ST/selfheals.new" && mv -f "$ST/selfheals.new" "$ST/selfheals.jsonl" || fail "the entry could not be dated back"
  printf '%s\n' 'F1 HARM: the poll is wrong again, as before.' > "$STUB/judge.1"
  out=$(loop heals sort 2>&1) || fail "heals sort failed: $out"
  [ "$(jq -cs 'map([.time, (.seen // "" | . > "2026-06")])' "$ST/selfheals.jsonl")" = '[["2026-01-01T00:00:00Z",true]]' ] \
    || fail "the entry was not seen again when the sort ruled the same finding of a queued card harm: $(cat "$ST/selfheals.jsonl")"
}

# The sort never edits an audit issue's body, so a finding it moved to the list is still in the body; healslisted()
# keeps it from going to the judge again, and healsbrief() keeps it out of the issue's card. Bug it catches: both
# read the live list alone, so after the entries expired the brief put them back into the card's scope and the next
# sort sent the same unchanged findings to the judge again.
t_healsexpiresort() {
  local HNOW=$HNOW id f='[P2] a.sh:1 the wait is one turn longer'
  judging '[]'
  : > "$ST/selfheals.jsonl"
  hrun "healsadd c9-7 7 area:engine w '$f' sort self-heals"; [ "$RC" = 0 ] || fail "healsadd failed: $(cat "$T/$CASE/run.out")"
  id=$(cat "$T/$CASE/run.out")
  HNOW=$((HNOW + 31 * 86400)); hrun healsexpire
  [ "$(hids "$ST/healsdropped.jsonl")" = "$id" ] && [ ! -s "$ST/selfheals.jsonl" ] || fail "the sort's entry did not expire: $(cat "$ST/selfheals.jsonl" "$ST/healsdropped.jsonl" 2>&1)"
  hrun 'healslisted; healsbrief 7'
  grep -qxF "$(jq -cn --arg f "$f" '{issue: 7, finding: $f}')" "$T/$CASE/run.out" && grep -qxF -- "- $f (list entry $id, expired)" "$T/$CASE/run.out" \
    || fail "the expired entry's finding is not kept from the next sort, or the issue's brief does not hold it out of the card's scope: $(cat "$T/$CASE/run.out")"
}

# An entry a batch card held and shut() gave back (healsfree()) counts its days from the give-back, not from its time: it
# stays 29 days on, where the retry of that card takes it again (healstake()), and one no card took in 31 days leaves the
# list like any other. Bugs it catches: the entries expired at once because their time was old, so the card was given back
# with no scope; and an entry marked freed never expired, so a shut batch card's findings stayed on the list for good.
t_healsexpirefreed() {
  local HNOW=$HNOW
  judging '[]'
  { hline h-a F-a '{"time": "2026-10-01T00:00:00Z", "batched": 100101}'; hline h-b F-b '{"time": "2026-10-01T00:00:00Z", "batched": 100102}'; } > "$ST/selfheals.jsonl"
  hrun 'healsfree "" 100101'; [ "$RC" = 0 ] || fail "healsfree failed: $(cat "$T/$CASE/run.out")"
  hrun 'healsfree "" 100102'; [ "$RC" = 0 ] || fail "healsfree failed: $(cat "$T/$CASE/run.out")"
  HNOW=$((HNOW + 29 * 86400)); hrun healsexpire
  [ "$RC" = 0 ] && [ "$(hids "$ST/selfheals.jsonl")" = 'h-a h-b' ] && [ ! -s "$ST/healsdropped.jsonl" ] \
    || fail "the entries a shut batch card gave back expired before 30 days from the give-back (rc $RC): $(cat "$T/$CASE/run.out" "$ST/selfheals.jsonl" "$ST/healsdropped.jsonl" 2>&1)"
  hrun 'healstake "" 100101'
  [ "$RC" = 0 ] && [ "$(jq -cs 'map(.batched)' "$ST/selfheals.jsonl")" = '[100101,null]' ] \
    || fail "the retry of the batch card did not take its entry again (rc $RC): $(cat "$T/$CASE/run.out" "$ST/selfheals.jsonl" 2>&1)"
  HNOW=$((HNOW + 2 * 86400)); hrun healsexpire
  [ "$RC" = 0 ] && [ "$(hids "$ST/selfheals.jsonl")" = h-a ] && [ "$(hids "$ST/healsdropped.jsonl")" = h-b ] \
    || fail "31 days after the give-back, the entry no card took did not leave, or the one a card holds did (rc $RC): $(cat "$T/$CASE/run.out" "$ST/selfheals.jsonl" "$ST/healsdropped.jsonl" 2>&1)"
}

# The record lines of a blocked card: <card> <issue> [<jq object merged into its picked line>]
hblocked() {
  local x=${3:-}; [ -n "$x" ] || x='{}'
  jq -cn --arg c "$1" --argjson n "$2" --argjson x "$x" '{card: $c, issue: $n, step: "picked", time: "2026-11-01T00:00:00Z", tokens: {claude: 0, codex: 0}, result: "ok", sha: "", reason: "", repo: "main"}
    | (. + $x), (.step = "blocked" | .result = "blocked" | .reason = "build: it failed")' >> "$ST/cards.jsonl"
}

# Bug it catches (issue 1769): healsids() read TACARDS, which only lib/testaction.sh sets, so a shut() without that file
# printed "unbound variable" and a batch card with no GitHub issue kept the entry it holds by its Tests page id.
# shut() is called with the libraries commands/shut.sh loads for every target: `shut <card id>` of a card with no issue
# also loads lib/testaction.sh, so the command alone cannot show that healsids() needs no variable of it.
t_healsshutnoissue() {
  local c=c20261101T000000-main-0
  judging '[]'
  hblocked "$c" 0 '{"noIssue": "Self-heals batch: area:engine"}'
  mkdir -p "$ST/testactions"
  jq -cn --arg c "$c" '{cards: [{id: "abcabcabcabc", card: $c}]}' > "$ST/testactions/cards.json"
  hline h-a F-a '{"batched": "abcabcabcabc"}' > "$ST/selfheals.jsonl"
  ( export CONVEYOR_MAIN=$R CONVEYOR_CARDS=$T/$CASE/cards
    . "$SRC/conveyor.sh" state-dir > /dev/null && eval "$(grep '^\. "\$HERE/lib/' "$SRC/commands/shut.sh")" && names || exit 9
    locked shut "$c" ) > "$T/$CASE/run.out" 2>&1; RC=$?
  [ "$RC" = 0 ] && [ "$(jq -c '[.batched, .freed]' "$ST/selfheals.jsonl")" = '[null,["abcabcabcabc"]]' ] \
    || fail "shut of the batch card with no GitHub issue did not give back the entry it holds by its Tests page id (rc $RC): $(cat "$T/$CASE/run.out" "$ST/selfheals.jsonl" 2>&1)"
  ! grep -q 'unbound variable' "$T/$CASE/run.out" || fail "shut $c read an unset variable: $(cat "$T/$CASE/run.out")"
}

# Bug it catches (issue 1769): `shut <issue>` of any card, with a list that holds a batched entry, printed
# "TACARDS: unbound variable" once for each such list.
t_healsshutissue() {
  local out
  judging '[]'
  hblocked c20261101T000000-main-7 7
  hline h-a F-a '{"batched": 100101}' > "$ST/selfheals.jsonl"
  out=$(loop shut 7 2>&1 > /dev/null) || fail "shut 7 failed: $out"
  [[ $out != *'unbound variable'* ]] || fail "shut 7 read an unset variable: $out"
  [ "$(st 'select(.issue == 7 and .step == "closed") | .card')" = c20261101T000000-main-7 ] && [ "$(jq -c .batched "$ST/selfheals.jsonl")" = 100101 ] \
    || fail "shut 7 did not close its card, or gave back the entry another card holds: $out $(cat "$ST/cards.jsonl" "$ST/selfheals.jsonl")"
}

# The loop's turn expires the list when it can pick no card. Bug it catches: expiry ran inside healsonce(), which turnask()
# calls only when a build slot is free or an urgent card is ready, so a loop with every slot full never expired one.
# The turn is called whole (turnask()), as t_turnaskbig does (redcap.test.sh): a call of healsexpire() alone cannot show the skip.
t_healsexpireturn() {
  judging '[]'
  hline h-old F-old '{"time": "2026-10-31T00:00:00Z"}' > "$ST/selfheals.jsonl"
  hrun 'declare -A shuts=() mine=(); cap=1 building=1 now=running inuse=1 running=1 sampled=$SECONDS old= nopack= nocli= mhold= guard= waits= issues= ctl=$(ctl)
    turnask >/dev/null 2>&1'
  [ "$(hids "$ST/healsdropped.jsonl")" = h-old ] && [ ! -s "$ST/selfheals.jsonl" ] \
    || fail "a turn with every build slot full did not expire the 31-day-old entry (rc $RC): $(cat "$T/$CASE/run.out" "$ST/selfheals.jsonl" "$ST/healsdropped.jsonl" 2>&1)"
}

# The commands of t_healsexpirelock, in the engine shell: healsexpire() runs until its write (cmp, the call after both
# reads), a writer then asks for the list's lock (healsadd() with flock -n, so a held lock is seen, not waited for) and
# the expiry goes on. $d is the case's folder. The waits are for the files the two shell functions touch (wait_until).
lockrace() {
  local ex
  export CONVEYOR_NOW=$HNOW WAIT_CEILING=30
  cmp() { : > "$d/paused"; wait_until '[ -e "$d/go" ]' || return 1; command cmp "$@"; }
  healsexpire & ex=$!
  wait_until '[ -e "$d/paused" ]' || { echo "healsexpire did not reach its write"; exit 1; }
  ( flock() { command flock -n "$@" || { : > "$d/blocked"; return 1; }; }; healsadd c4-12 12 area:engine w F-keep review self-heals ); echo "add $?"
  : > "$d/go"; wait $ex; echo "expire $?"
}
# An entry seen again while its expiry runs is not lost. The weak point: healsexpire() has read the list and not yet
# written it, and a sighting (healsadd(), the real caller) comes in. What must stay true: the two take the list's lock in
# turn, so the sighting comes after the expiry, takes the entry back from the dropped record and sees it now. Bug it
# catches: with no shared lock the sighting writes the list in between, and the expiry's write then drops the entry with
# its sighting. A poll of the paused expiry is the only way to hold it at that point: a direct call has no point to pause.
t_healsexpirelock() {
  local HNOW=$HNOW d=$T/$CASE id
  judging '[]'
  : > "$ST/selfheals.jsonl"
  HNOW=$((HNOW - 31 * 86400)); hrun 'healsadd c1-7 7 area:engine w F-keep review self-heals'; [ "$RC" = 0 ] || fail "healsadd failed: $(cat "$d/run.out")"
  id=$(cat "$d/run.out"); HNOW=$((HNOW + 31 * 86400))
  rm -f "$d/paused" "$d/go" "$d/blocked"
  fx_in lockrace
  [ "$(cat "$d/run.out")" = $'add 1\nexpire 0' ] && [ -e "$d/blocked" ] && [ "$(hids "$ST/healsdropped.jsonl")" = "$id" ] && [ ! -s "$ST/selfheals.jsonl" ] \
    || fail "a sighting while the expiry ran did not find the list's lock held, or the expiry did not finish (rc $RC): $(cat "$d/run.out" "$ST/selfheals.jsonl" "$ST/healsdropped.jsonl" 2>&1)"
  hrun 'healsadd c4-12 12 area:engine w F-keep review self-heals'
  [ "$RC" = 0 ] && [ "$(cat "$d/run.out")" = "$id" ] && [ "$(jq -cs 'map([.id, .seen])' "$ST/selfheals.jsonl")" = "$(jq -cn --arg i "$id" '[[$i, "2026-12-01T00:00:00Z"]]')" ] && [ ! -s "$ST/healsdropped.jsonl" ] \
    || fail "the sighting after the expiry did not take the entry back, seen now (rc $RC): $(cat "$d/run.out" "$ST/selfheals.jsonl" "$ST/healsdropped.jsonl" 2>&1)"
}

# The snapshot gives the Board the entries that expired, the latest first, apart from the list's own. Bug it catches:
# the snapshot read the live lists alone, so the Board could not show what expired.
t_healsexpiresnap() {
  local out
  judging '[]'
  hline h-live F-live '{"time": "2026-11-20T00:00:00Z"}' > "$ST/selfheals.jsonl"
  { hline h-1 F-1 '{"dropped": {"time": "2026-11-10T00:00:00Z", "why": "expired"}}'; hline h-2 F-2 '{"dropped": {"time": "2026-11-12T00:00:00Z", "why": "expired"}}'; } > "$ST/healsdropped.jsonl"
  out=$(loop snapshot --fresh) || fail "snapshot exited non-zero"
  [ "$(jq -c '.selfheals | [(.entries | map(.id)), (.dropped | map([.id, .dropped.why]))]' <<<"$out")" = '[["h-live"],[["h-2","expired"],["h-1","expired"]]]' ] \
    || fail "the snapshot does not give the expired entries, the latest first, apart from the list: $(jq -c '.selfheals' <<<"$out")"
}

# Two entries of one finding on the dropped record (two cards listed it before an entry was its finding; their ids tell
# them apart): a finding that comes back takes one of them back, with its own id, and the other stays on the record.
# Bug it catches: the finding took the last row, printed the first row's id and erased every row of the finding from the
# record, so the id it reported was on no list.
t_healsdropdup() {
  judging '[]'
  : > "$ST/selfheals.jsonl"
  { hline h-1 F-dup '{"repo": "main", "time": "2026-09-01T00:00:00Z", "dropped": {"time": "2026-10-01T00:00:00Z", "why": "expired"}}'
    hline h-2 F-dup '{"repo": "main", "card": "c2-9", "issue": 9, "time": "2026-09-02T00:00:00Z", "dropped": {"time": "2026-10-02T00:00:00Z", "why": "expired"}}'; } > "$ST/healsdropped.jsonl"
  hrun 'healsadd c3-11 11 area:engine w F-dup review self-heals'
  [ "$RC" = 0 ] && [ "$(cat "$T/$CASE/run.out")" = h-1 ] && [ "$(hids "$ST/selfheals.jsonl")" = h-1 ] && [ "$(hids "$ST/healsdropped.jsonl")" = h-2 ] \
    || fail "the finding listed by two cards did not take back one entry, the id it printed, and leave the other dropped (rc $RC): $(cat "$T/$CASE/run.out" "$ST/selfheals.jsonl" "$ST/healsdropped.jsonl" 2>&1)"
}

# The finding seen again on a card still in flight is of that card: the batch card of its area waits for it, as for any
# entry whose card has not landed (healsbatch(), lib/heals.sh). Bug it catches: the entry kept the card and issue it was
# found on, which had ended, so a batch card was filed for a finding that the card in flight was fixing.
t_healsseenbatch() {
  local out rc
  judging '[]'; rm -f "$ST/healssort.jsonl" "$STUB/filed"
  : > "$ST/selfheals.jsonl"
  hrun 'healsadd c5 5 area:engine w F-keep review self-heals'; [ "$RC" = 0 ] || fail "healsadd failed: $(cat "$T/$CASE/run.out")"
  hrun 'healsadd c7 7 area:engine w F-keep review self-heals'; [ "$RC" = 0 ] || fail "healsadd failed: $(cat "$T/$CASE/run.out")"
  landed 7 | jq -c '.card = "c7" | .step = "picked"' >> "$ST/cards.jsonl" # c7 is in flight
  out=$(loop heals batch area:engine 2>&1); rc=$?
  [ "$rc" = 2 ] && [ ! -e "$STUB/filed" ] && grep -qF '(1 wait for theirs to land or close)' <<<"$out" \
    || fail "a batch card was filed for a finding that card c7, still in flight, saw again, or the ask did not exit 2 naming the entry that waits ($rc): $out $(cat "$ST/selfheals.jsonl")"
}

# A repeat review of one finding is matched to its entry although the reviewer marked it another way: an id mark ([E1])
# and a kind or level mark are not the finding, and a line number follows any path, one with no extension too
# (.github/CODEOWNERS:2). Bug it catches: the match kept [E1] and the digits of CODEOWNERS:2, so the finding was a second
# entry beside the first, and only the first one's days were reset.
t_healskeymarks() {
  local id
  judging '[]'
  : > "$ST/selfheals.jsonl"
  hrun "healsadd c1-7 7 area:engine w '[P1] .github/CODEOWNERS:2 a rule is skipped. Proof: p' review self-heals"; [ "$RC" = 0 ] || fail "healsadd failed: $(cat "$T/$CASE/run.out")"
  id=$(cat "$T/$CASE/run.out")
  hrun "healsadd c2-9 9 area:engine w '[P1][E1] .github/CODEOWNERS:9 a rule is skipped. Proof: q' review self-heals"
  [ "$RC" = 0 ] && [ "$(cat "$T/$CASE/run.out")" = "$id" ] && [ "$(hids "$ST/selfheals.jsonl")" = "$id" ] \
    || fail "[P1][E1] .github/CODEOWNERS:9 was not matched to the entry of [P1] .github/CODEOWNERS:2 (rc $RC): $(cat "$T/$CASE/run.out" "$ST/selfheals.jsonl" 2>&1)"
}

# A finding a sort listed, that expired, and that a later card's review lists is that entry again, on the list alone.
# Bug it catches: the match asked the same source of both, so the review's finding was no match for the sort's expired
# entry and got a second id, and the finding stood twice, in the dropped record and on the list.
t_healssortreview() {
  judging '[]'
  : > "$ST/selfheals.jsonl"
  hline h-s F-sort '{"repo": "main", "from": "sort", "time": "2026-09-01T00:00:00Z", "dropped": {"time": "2026-10-01T00:00:00Z", "why": "expired"}}' > "$ST/healsdropped.jsonl"
  hrun 'healsadd c3-11 11 area:engine w F-sort review self-heals'
  [ "$RC" = 0 ] && [ "$(cat "$T/$CASE/run.out")" = h-s ] && [ "$(hids "$ST/selfheals.jsonl")" = h-s ] && [ ! -s "$ST/healsdropped.jsonl" ] \
    || fail "a review's finding was not matched to the expired entry a sort listed (rc $RC): $(cat "$T/$CASE/run.out" "$ST/selfheals.jsonl" "$ST/healsdropped.jsonl" 2>&1)"
}

# A later card that lists one of two findings of an earlier card (they differ in their line numbers only) changes that one entry.
# Bug it catches: both entries matched the listing and both took its finding text, so two findings became one and the
# other finding was lost from the list; and the exact entry was told by its whole text, Proof too, so a listing with a
# Proof the entry lacks picked the first entry.
t_healsonerow() {
  local a b
  judging '[]'
  : > "$ST/selfheals.jsonl"
  hrun "healsadd c6-6 6 area:board w '[P3] d.js:0 an old redraw' review self-heals"; [ "$RC" = 0 ] || fail "healsadd failed: $(cat "$T/$CASE/run.out")"
  a=$(cat "$T/$CASE/run.out")
  hrun "healsadd c6-6 6 area:board w '[P3] d.js:1 an old redraw' review self-heals"; [ "$RC" = 0 ] || fail "healsadd failed: $(cat "$T/$CASE/run.out")"
  b=$(cat "$T/$CASE/run.out")
  hrun "healsadd c7-8 8 area:board w '[P3] d.js:1 an old redraw. Proof: d.js:1' review self-heals"
  [ "$RC" = 0 ] && [ "$(cat "$T/$CASE/run.out")" = "$b" ] && [ "$(hids "$ST/selfheals.jsonl")" = "$a $b" ] \
    && [ "$(jq -sc 'map([.card, .finding])' "$ST/selfheals.jsonl")" = '[["c6-6","[P3] d.js:0 an old redraw"],["c7-8","[P3] d.js:1 an old redraw. Proof: d.js:1"]]' ] \
    || fail "a listing of [P3] d.js:1 an old redraw (with a Proof) by c7-8 changed the entry of [P3] d.js:0 an old redraw too (rc $RC): $(cat "$T/$CASE/run.out" "$ST/selfheals.jsonl" 2>&1)"
}

# A finding listed again after its entry expired takes that entry back, although a live entry of the same card names the
# same finding at another line.
# Bug it catches: the live entry (a.txt:3) matched first and took the listing of a.txt:2, so the expired entry of a.txt:2
# stayed in the dropped record and its finding stood twice; and the listing's Proof (here another from the entry's) made
# the exact entry no match, so the live entry of a.txt:3 took it.
t_healsexactdropped() {
  local id live HNOW=$HNOW
  judging '[]'
  : > "$ST/selfheals.jsonl"
  HNOW=$((HNOW - 31 * 86400)); hrun "healsadd c4 4 area:engine w '[P2] a.txt:2 a slot stays over its cap. Proof: p' review self-heals"; [ "$RC" = 0 ] || fail "healsadd failed: $(cat "$T/$CASE/run.out")"
  id=$(cat "$T/$CASE/run.out")
  HNOW=$((HNOW + 21 * 86400)); hrun "healsadd c4 4 area:engine w '[P2] a.txt:3 a slot stays over its cap. Proof: p' review self-heals"; [ "$RC" = 0 ] || fail "healsadd failed: $(cat "$T/$CASE/run.out")"
  live=$(cat "$T/$CASE/run.out"); HNOW=$((HNOW + 10 * 86400)); hrun healsexpire
  [ "$(hids "$ST/healsdropped.jsonl")" = "$id" ] || fail "the case did not set up an expired entry of a.txt:2 beside a live one of a.txt:3: $(cat "$ST/selfheals.jsonl" "$ST/healsdropped.jsonl" 2>&1)"
  hrun "healsadd c9-9 9 area:engine w '[P2] a.txt:2 a slot stays over its cap. Proof: a.txt:2' review self-heals"
  [ "$RC" = 0 ] && [ "$(cat "$T/$CASE/run.out")" = "$id" ] && [ "$(hids "$ST/selfheals.jsonl")" = "$live $id" ] && [ ! -s "$ST/healsdropped.jsonl" ] \
    && [ "$(jq -r 'select(.id == "'"$live"'") | .finding' "$ST/selfheals.jsonl")" = '[P2] a.txt:3 a slot stays over its cap. Proof: p' ] \
    || fail "[P2] a.txt:2 listed by c9-9 did not take its expired entry back beside the live entry of a.txt:3 (rc $RC): $(cat "$T/$CASE/run.out" "$ST/selfheals.jsonl" "$ST/healsdropped.jsonl" 2>&1)"
}

# The same listing with another level mark still takes the expired entry of its own line.
# Bug it catches: the exact match kept the level mark, so a finding re-ranked from [P2] to [P3] fell to the loose match,
# which took the live entry of a.txt:3 and left the expired entry of a.txt:2 in the record.
t_healsexactmarks() {
  local id live HNOW=$HNOW
  judging '[]'
  : > "$ST/selfheals.jsonl"
  HNOW=$((HNOW - 31 * 86400)); hrun "healsadd c4 4 area:engine w '[P2] a.txt:2 a slot stays over its cap. Proof: p' review self-heals"; [ "$RC" = 0 ] || fail "healsadd failed: $(cat "$T/$CASE/run.out")"
  id=$(cat "$T/$CASE/run.out")
  HNOW=$((HNOW + 21 * 86400)); hrun "healsadd c4 4 area:engine w '[P2] a.txt:3 a slot stays over its cap. Proof: p' review self-heals"; [ "$RC" = 0 ] || fail "healsadd failed: $(cat "$T/$CASE/run.out")"
  live=$(cat "$T/$CASE/run.out"); HNOW=$((HNOW + 10 * 86400)); hrun healsexpire
  [ "$(hids "$ST/healsdropped.jsonl")" = "$id" ] || fail "the case did not set up an expired entry of a.txt:2 beside a live one of a.txt:3: $(cat "$ST/selfheals.jsonl" "$ST/healsdropped.jsonl" 2>&1)"
  hrun "healsadd c9-9 9 area:engine w '[P3] a.txt:2 a slot stays over its cap. Proof: p' review self-heals"
  [ "$RC" = 0 ] && [ "$(cat "$T/$CASE/run.out")" = "$id" ] && [ "$(hids "$ST/selfheals.jsonl")" = "$live $id" ] && [ ! -s "$ST/healsdropped.jsonl" ] \
    && [ "$(jq -r 'select(.id == "'"$live"'") | .finding' "$ST/selfheals.jsonl")" = '[P2] a.txt:3 a slot stays over its cap. Proof: p' ] \
    || fail "[P3] a.txt:2 listed by c9-9 did not take the expired entry of [P2] a.txt:2 back beside the live entry of a.txt:3 (rc $RC): $(cat "$T/$CASE/run.out" "$ST/selfheals.jsonl" "$ST/healsdropped.jsonl" 2>&1)"
}

# An audit that lists a finding again after its entry expired, with the finding at another line, takes that entry back.
# Bug it catches: a sort has one card (#23) for all its listings, so the same-card rule asked for equal finding text, the
# moved finding got a second id and the old entry stayed in the dropped record, so the audit stayed open.
t_healssortsamecard() {
  local a b HNOW=$HNOW
  judging '[]'
  : > "$ST/selfheals.jsonl"
  HNOW=$((HNOW - 45 * 86400)); hrun "healsadd '#23' 23 area:engine w '[P2] a.sh:1 the wait is one turn longer' sort self-heals"; [ "$RC" = 0 ] || fail "healsadd failed: $(cat "$T/$CASE/run.out")"
  a=$(cat "$T/$CASE/run.out")
  HNOW=$((HNOW + 45 * 86400)); hrun healsexpire
  [ "$(hids "$ST/healsdropped.jsonl")" = "$a" ] || fail "the entry did not expire: $(cat "$ST/selfheals.jsonl" "$ST/healsdropped.jsonl" 2>&1)"
  hrun "healsadd '#23' 23 area:engine w '[P2] a.sh:2 the wait is one turn longer' sort self-heals"
  b=$(cat "$T/$CASE/run.out")
  [ "$RC" = 0 ] && [ "$a" = "$b" ] && [ "$(hids "$ST/selfheals.jsonl")" = "$a" ] && [ ! -s "$ST/healsdropped.jsonl" ] \
    && [ "$(jq -r .finding "$ST/selfheals.jsonl")" = '[P2] a.sh:2 the wait is one turn longer' ] \
    || fail "the audit's finding, moved to a.sh:2, did not take its expired entry back by the same card (rc $RC; $a, $b): $(cat "$ST/selfheals.jsonl" "$ST/healsdropped.jsonl" 2>&1)"
}

# Two findings of one audit that differ in their number (R1, R4) are two findings, although one wording is at two lines.
# Bug it catches: the match dropped the audit number and the line numbers, so R4, new, took the expired entry of R1 and
# R1 stayed missing, and the audit stayed open.
t_healssortrnumber() {
  local a b HNOW=$HNOW
  judging '[]'
  : > "$ST/selfheals.jsonl"
  HNOW=$((HNOW - 45 * 86400)); hrun "healsadd '#23' 23 area:engine w 'R1 [P2] \`a.sh:1\`: the wait is one turn longer - How: x' sort self-heals"; [ "$RC" = 0 ] || fail "healsadd failed: $(cat "$T/$CASE/run.out")"
  a=$(cat "$T/$CASE/run.out")
  HNOW=$((HNOW + 45 * 86400)); hrun healsexpire
  [ "$(hids "$ST/healsdropped.jsonl")" = "$a" ] || fail "the entry did not expire: $(cat "$ST/selfheals.jsonl" "$ST/healsdropped.jsonl" 2>&1)"
  hrun "healsadd '#23' 23 area:engine w 'R4 [P2] \`a.sh:2\`: the wait is one turn longer - How: x' sort self-heals"
  b=$(cat "$T/$CASE/run.out")
  [ "$RC" = 0 ] && [ "$a" != "$b" ] && [ "$(hids "$ST/selfheals.jsonl")" = "$b" ] && [ "$(hids "$ST/healsdropped.jsonl")" = "$a" ] \
    || fail "R4 at a.sh:2 took the expired entry of R1 at a.sh:1 (rc $RC; $a, $b): $(cat "$T/$CASE/run.out" "$ST/selfheals.jsonl" "$ST/healsdropped.jsonl" 2>&1)"
  # A review lists R1's finding at a.sh:1 in its own wording (no backticks, no colon after the place): the expired R1 takes
  # it, not the live R4 at a.sh:2. Bug it catches: lkey kept the colon after the audit's place, so the line-exact tier missed
  # R1 and the line-blind one took the first live entry, R4.
  hrun 'healsadd c3-11 11 area:engine w "[P2] a.sh:1 the wait is one turn longer. Proof: a.sh:1" review self-heals'
  [ "$RC" = 0 ] && [ "$(cat "$T/$CASE/run.out")" = "$a" ] && [ "$(hids "$ST/selfheals.jsonl")" = "$b $a" ] && [ ! -s "$ST/healsdropped.jsonl" ] \
    && [ "$(jq -r 'select(.id == "'"$b"'") | .card' "$ST/selfheals.jsonl")" = '#23' ] \
    || fail "a review's [P2] a.sh:1 finding did not take the expired R1 at a.sh:1 back beside the live R4 at a.sh:2 (rc $RC; $a, $b): $(cat "$T/$CASE/run.out" "$ST/selfheals.jsonl" "$ST/healsdropped.jsonl" 2>&1)"
}

# A review lists a finding an audit's sort stored (with the audit's number, backticks and How) after that entry expired.
# Bug it catches: the match kept R1, the backticks, the colon after the place and the How text, so the same file and
# finding in a review's wording was no match and the finding stood twice.
t_healssortauditkey() {
  judging '[]'
  : > "$ST/selfheals.jsonl"
  hline h-r1 'R1 [P2] `a.sh:1`: the wait is one turn longer - How: the turn waits.' '{"repo": "main", "from": "sort", "issue": 23, "card": "#23", "time": "2026-09-01T00:00:00Z", "dropped": {"time": "2026-10-01T00:00:00Z", "why": "expired"}}' > "$ST/healsdropped.jsonl"
  hrun 'healsadd c3-11 11 area:engine w "[P2] a.sh:1 the wait is one turn longer. Proof: a.sh:1" review self-heals'
  [ "$RC" = 0 ] && [ "$(cat "$T/$CASE/run.out")" = h-r1 ] && [ "$(hids "$ST/selfheals.jsonl")" = h-r1 ] && [ ! -s "$ST/healsdropped.jsonl" ] \
    || fail "a review's [P2] a.sh:1 finding was not matched to the expired entry of the audit's R1 (rc $RC): $(cat "$T/$CASE/run.out" "$ST/selfheals.jsonl" "$ST/healsdropped.jsonl" 2>&1)"
  # healsitems() (lib/heals.sh) tells the sort which findings of issue 23 it has stored by this text: the review's wording must not replace it.
  hrun healslisted
  [ "$(jq -r .finding "$T/$CASE/run.out")" = 'R1 [P2] `a.sh:1`: the wait is one turn longer - How: the turn waits.' ] \
    || fail "a review that took the audit's R1 back from the record replaced the text the sort stored for it: $(cat "$ST/selfheals.jsonl")"
}

# The retry of a shut batch card after its entry expired takes the entry back from the dropped record, held by the card.
# Bug it catches: healstake() read the live list alone and found nothing, so the retried card kept the finding in its scope
# while a later review listed it again with no batched value, and `heals batch` filed it for a second card.
t_healsretryexpired() {
  judging '[]'
  : > "$ST/selfheals.jsonl"
  hline h-a F-a '{"repo": "main", "freed": [100101], "time": "2026-09-01T00:00:00Z", "dropped": {"time": "2026-10-01T00:00:00Z", "why": "expired"}}' > "$ST/healsdropped.jsonl"
  hrun 'healstake "" 100101'
  [ "$RC" = 0 ] && [ "$(jq -cs 'map([.id, .batched])' "$ST/selfheals.jsonl")" = '[["h-a",100101]]' ] && [ ! -s "$ST/healsdropped.jsonl" ] \
    || fail "the retry did not take its expired entry back, held by its card (rc $RC): $(cat "$T/$CASE/run.out" "$ST/selfheals.jsonl" "$ST/healsdropped.jsonl" 2>&1)"
}

# The turn never waits for a list that a writer holds (healsbatch() holds it across its GitHub calls): expiry checks
# nothing and succeeds, and the next turn expires the entry. Bug it catches: expiry waited for the lock, so one slow
# `gh issue create` stalled the loop's pick.
# A direct call: a held lock is the whole condition, and fd 8 of the case's shell holds it.
t_healsexpirebusy() {
  judging '[]'
  hline h-old F-old '{"time": "2026-10-31T00:00:00Z"}' > "$ST/selfheals.jsonl"
  hrun 'exec 8>>"$SELFHEALS.lock"; flock 8; healsexpire'
  [ "$RC" = 0 ] && [ "$(hids "$ST/selfheals.jsonl")" = h-old ] && [ ! -s "$ST/healsdropped.jsonl" ] \
    || fail "expiry with the list's lock held by a writer did not leave at once with nothing changed (rc $RC): $(cat "$T/$CASE/run.out" "$ST/selfheals.jsonl" "$ST/healsdropped.jsonl" 2>&1)"
  hrun healsexpire
  [ "$RC" = 0 ] && [ "$(hids "$ST/healsdropped.jsonl")" = h-old ] || fail "the next turn did not expire the entry (rc $RC): $(cat "$T/$CASE/run.out" "$ST/selfheals.jsonl" 2>&1)"
}
