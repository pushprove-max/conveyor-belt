#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 300
# Engine cases: the archive of finished cards' lines and the landed list, as their readers read them: allrecs() and
# archrows() (the all-time totals), landedall() (the pick and adopted()), the ended list (the pick, the Tests page's
# pick and its history, umbrellas(), reopened(), retry, the main-red pick and slicetake()); and the archive run that
# moves the lines there (archiverun(), lib/archive.sh).
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"

# archline <card> <issue> <step> <time> [<dollars>]: one line of the card records; with dollars, a build step that
# cost them at $20 per million output tokens.
archline() {
  jq -cn --arg c "$1" --argjson n "$2" --arg s "$3" --arg t "$4" --argjson o "$(jq -n --argjson d "${5:-0}" '$d * 50000 | round')" --arg repo "${R##*/}" \
    '{card:$c,issue:$n,step:$s,time:$t,tokens:{claude:$o,codex:0},result:"ok",sha:(if $s == "landed" then "ab" * 20 else "" end),reason:"",repo:$repo}
     + if $s == "build" then {model:"claude-opus-5-5",usage:{input:0,write:0,write1h:0,read:0,output:$o}} elif $s == "landed" then {product:true} else {} end'
}
# The cost of the build lines on stdin, as spent() prices a card's steps (SPENTSTEPS, stepsusd()), in whole cents:
# stepsusd prints a float (7.0), and the cases compare the amount, not its form.
ARCHCOST='jq -cs "$SPENTSTEPS" | stepsusd | jq ". * 100 | round"'

# Bugs: allrecs() leaves out an archive month, a gzip member after a file's first, or the live records; prints a month
# out of order (by the files' times, not their names), or the live lines before the archive; with no archive folder,
# prints anything but what recs() prints; or a cost total over it is not the total of the same lines all live.
t_allrecs() {
  setup '[]'; mkdir -p "$ST/archive"
  { archline cA 1 picked 2026-09-01T00:00:00Z; archline cA 1 build 2026-09-01T00:10:00Z 1; archline cA 1 landed 2026-09-01T00:20:00Z; } > "$T/$CASE/sep"
  { archline cB 2 picked 2026-10-01T00:00:00Z; archline cB 2 build 2026-10-01T00:10:00Z 2; archline cB 2 landed 2026-10-01T00:20:00Z; } > "$T/$CASE/oct"
  { archline cC 3 picked 2026-11-01T00:00:00Z; archline cC 3 build 2026-11-01T00:10:00Z 4; } > "$ST/cards.jsonl"
  # Each month in two gzip members, as two archive runs append them; October's file written first, so it is the older file.
  for m in oct sep; do
    f=$ST/archive/cards-2026-$([ $m = sep ] && echo 09 || echo 10).jsonl.gz
    head -n 1 "$T/$CASE/$m" | gzip -c > "$f" && tail -n +2 "$T/$CASE/$m" | gzip -c >> "$f" || fail "the archive fixture could not be written"
  done
  touch -t 200001010000 "$ST/archive/cards-2026-10.jsonl.gz"
  fx_in "allrecs; echo cost; allrecs | $ARCHCOST"
  [ "$(cat "$T/$CASE/run.out")" = "$(cat "$T/$CASE/sep" "$T/$CASE/oct" "$ST/cards.jsonl"; echo cost; echo 700)" ] \
    || fail "allrecs did not print September's lines, October's, then the live ones, or their cost is not \$7: $(cat "$T/$CASE/run.out")"
  # The same lines all live, no archive folder: allrecs prints what recs prints, and the cost total is the same.
  rm -rf "$ST/archive"; cat "$T/$CASE/sep" "$T/$CASE/oct" "$ST/cards.jsonl" > "$T/$CASE/all" && mv "$T/$CASE/all" "$ST/cards.jsonl"
  fx_in "[ \"\$(allrecs)\" = \"\$(recs)\" ] || echo differs; allrecs | $ARCHCOST"
  [ "$(cat "$T/$CASE/run.out")" = 700 ] || fail "with no archive, allrecs is not recs, or the cost total over it is not \$7: $(cat "$T/$CASE/run.out")"
}

# archcard <card> <issue> <time> <dollars>: a landed and pushed card's lines (its push's head named for the card).
archcard() {
  archline "$1" "$2" picked "$3"; archline "$1" "$2" build "$3" "$4"; archline "$1" "$2" landed "$3"
  archline "$1" "$2" pushed "$3" | jq -c --arg h "$1" '.head = $h'
}
# Bugs: the snapshot read the live records alone, so a card whose lines went to the archive dropped out of its landed
# count, its cost list, the week's pushes and the history the Board reads: the all-time totals (archrows(),
# lib/snapshot.sh); or a later snapshot reused the archive's kept rows and pushes after an archive run appended a gzip
# member to a month's file.
t_archrows() {
  local now f q='[.landedCount, ([.landed[].card] | sort), .landedUsd, .cost.today, .metrics.week.pushes.ok]' out
  setup '[]'; mkdir -p "$ST/archive"; now=$(date -u +%FT%TZ); f=$ST/archive/cards-${now:0:7}.jsonl.gz
  archcard cA 1 "$now" 1 | gzip -c > "$f"
  archcard cB 2 "$now" 2 > "$ST/cards.jsonl"
  out=$(loop snapshot --fresh | jq -c "$q") && [ "$out" = '[2,["cA","cB"],3,3,2]' ] \
    || fail "the snapshot did not count the archived card's landing, cost and push beside the live one's: $out"
  # A later archive run appends a member to the same month's file: the next snapshot reads it, not the kept rows.
  archcard cC 3 "$now" 4 | gzip -c >> "$f"
  out=$(loop snapshot --fresh | jq -c "$q") && [ "$out" = '[3,["cA","cB","cC"],7,7,3]' ] \
    || fail "the second snapshot left out the archive's new gzip member (cC): $out"
  out=$(loop history | jq -c '[.cost.cards[].card] | sort') && [ "$out" = '["cA","cB","cC"]' ] \
    || fail "the history's cost list left out an archived card: $out"
}

# Bugs: an issue whose card landed and whose lines left the live records (it is only in landed.tsv) is picked again, by
# the pick or a dry pick of a state folder that holds the list; or adopted() keeps it pinned in order as not landed.
t_landedtsv() {
  local d=$T/$CASE/frozen out
  setup "$(jq -cs . <(issue 4 2026-01-01 P1) <(issue 5 2026-02-01 P1))"
  printf 'c9-4\t4\t%s\t2026-09-01T00:00:00Z\n' "$(printf 'ab%.0s' {1..20})" > "$T/$CASE/landed.tsv"
  # A dry pick of another folder reads that folder's landed list, not the state folder's (which has none here).
  mkdir -p "$d" && cp "$ST/control.json" "$T/$CASE/landed.tsv" "$d/" && : > "$d/cards.jsonl"
  out=$(loop pick --dry --issues "$STUB/issues.json" --state "$d") && [ "$out" = 5 ] || fail "the dry pick took '$out', not 5: #4 is landed in its folder's landed.tsv"
  cp "$T/$CASE/landed.tsv" "$ST/landed.tsv"
  out=$(pickfn upnext "$(cat "$STUB/issues.json")" | jq -c 'map(.number)') && [ "$out" = '[5]' ] || fail "the pick's list is $out, not [5]: #4 is landed in landed.tsv"
  fx_in 'adopted "$(ctl | jq -c ".order = [4, 5]")" "$(cat "$STUB/issues.json")" | jq -c .order'
  [ "$(cat "$T/$CASE/run.out")" = '[5]' ] || fail "adopted() kept #4, landed in landed.tsv, in order: $(cat "$T/$CASE/run.out")"
}

# The time <days> days ago, as a card line holds it.
ago() { jq -rn --argjson d "$1" 'now - $d * 86400 | todate'; }
# The live lines' cards, in order, one each, as one line.
livecards() { jq -r .card "$ST/cards.jsonl" | uniq | paste -sd' ' -; }
# The checksum of each file of the state folder, sorted.
stsums() { (cd "$ST" && find . -type f -exec cksum {} + | sort); }
# landcard <card> <issue> <time> [<sha>]: a card's lines that landed (its commit sha, when given), were pushed and,
# with an issue, had it closed: a finished card.
landcard() {
  archline "$1" "$2" picked "$3"; archline "$1" "$2" landed "$3" | jq -c --arg s "${4:-}" 'if $s == "" then . else .sha = $s end'
  archline "$1" "$2" pushed "$3"; [ "$2" = 0 ] || archline "$1" "$2" issue "$3"
}
# Bugs: the archive run moves a card still in flight, or one finished less than ARCHIVE_DAYS ago; moves a landed card
# not pushed yet (cU: the push, and the rule Push after a combined test run, read live landings alone) or one whose
# issue the push has not closed yet (cV: with Land as pr, the merge closes it from its pushed line); leaves a landed,
# closed (shut) or blocked-then-shut card live; moves a card whose lines are in the retried file alone (cY: given
# back by `retry` after its shut, whose kept work prior() finds there for its issue's next card); puts the moved
# lines in no month's file, or the retried lines of a moved card
# nowhere; leaves a landed card out of landed.tsv (or puts a closed one in it), or a moved card's end lines out of
# the ended list; leaves state.db's cards table holding the old lines after the rewrite (it is read here with no call
# that would sync it from the file); runs again within the hour; changes a file's bytes when it has nothing to move;
# or the loop's turn does not run it, or picks an issue whose landed or shut card it archived.
t_archmove() {
  local old m out sums tl ts
  setup "$(jq -cs . <(issue 4 2026-01-01 P1) <(issue 6 2026-01-02 P1) <(issue 10 2026-01-03 P1))"
  old=$(ago 3) tl=$(ago 3.002) ts=$(ago 3.001); m=${tl:0:7}
  { landcard cL 4 "$tl"
    archline cS 6 blocked "$ts"; archline cS 6 closed "$ts" | jq -c '.reason = "shut by the owner"'
    archline cC 7 picked "$old"; archline cC 7 closed "$old"; } > "$T/$CASE/moved"
  # cN is finished as cL is (landed, pushed, its issue closed): only its age keeps it live.
  { landcard cN 8 "$(ago 1)"; archline cF 9 picked "$(ago 5)"; archline cF 9 build "$(ago 5)"
    archline cU 0 picked "$old"; archline cU 0 landed "$old"; archline cV 5 picked "$old"; archline cV 5 landed "$old"; archline cV 5 pushed "$old"; } > "$T/$CASE/kept"
  cat "$T/$CASE/moved" "$T/$CASE/kept" > "$ST/cards.jsonl"
  { archline cL 4 blocked "$tl"; archline cZ 3 blocked "$(ago 4)"; archline cY 3 blocked "$tl"; archline cY 3 closed "$tl" | jq -c '.reason = "shut by the owner"'; } > "$ST/retried.jsonl"
  fx_in archiverun
  [ "$(livecards)" = 'cN cF cU cV' ] || fail "the live records hold cards '$(livecards)', not the 1-day cN, the in-flight cF, cU not pushed and cV with its issue not closed: $(cat "$T/$CASE/run.out")"
  [ "$(gzip -dc "$ST/archive/cards-$m.jsonl.gz")" = "$(cat "$T/$CASE/moved")" ] \
    || fail "cards-$m.jsonl.gz does not hold the 3-day cards' lines: $(gzip -dc "$ST/archive/cards-$m.jsonl.gz" | jq -r .card | paste -sd' ' -)"
  [ "$(jq -r .card "$ST/retried.jsonl" | uniq | paste -sd' ' -)" = 'cZ cY' ] && [ "$(gzip -dc "$ST/archive/retried-$m.jsonl.gz" | jq -r .card | uniq | paste -sd' ' -)" = cL ] \
    || fail "cL's retried line did not go to retried-$m.jsonl.gz, or cZ's or the given-back card cY's left the live retried lines: $(jq -r .card "$ST/retried.jsonl" | paste -sd' ' -)"
  [ "$(cat "$ST/landed.tsv")" = "$(printf 'cL\t4\t%s\t%s' "$(printf 'ab%.0s' {1..20})" "$tl")" ] || fail "landed.tsv holds '$(cat "$ST/landed.tsv")', not cL's landing alone"
  [ "$(jq -r '"\(.card) \(.step)"' "$ST/archive/ended.jsonl" | paste -sd, -)" = 'cL picked,cL landed,cL pushed,cS blocked,cS closed,cC picked,cC closed' ] \
    || fail "the ended list does not hold the moved cards' end lines: $(cat "$ST/archive/ended.jsonl")"
  out=$(python3 -c 'import sqlite3, sys; [print(r[0]) for r in sqlite3.connect(sys.argv[1]).execute("SELECT line FROM cards ORDER BY n")]' "$ST/state.db")
  [ "$out" = "$(cat "$ST/cards.jsonl")" ] || fail "state.db's cards table is not the live cards.jsonl after the run: $out"
  # Within the hour: an old finished card added since stays live.
  landcard cX 10 "$old" >> "$ST/cards.jsonl"
  fx_in archiverun
  [ "$(livecards)" = 'cN cF cU cV cX' ] || fail "a second run within the hour moved cards: the live records hold '$(livecards)'"
  # Over an hour later with nothing to move (cX taken out again): every file's bytes are the same.
  cp "$T/$CASE/kept" "$ST/cards.jsonl" && touch -t 200001010000 "$ST/archive/last"
  sums=$(stsums)
  fx_in archiverun
  [ "$(stsums)" = "$sums" ] || fail "a run with nothing to move changed a file: $(diff <(echo "$sums") <(stsums))"
  # The loop's own turn runs it before the pick: cX, landed 3 days ago, is archived and its open issue not picked.
  landcard cX 10 "$old" >> "$ST/cards.jsonl"; touch -t 200001010000 "$ST/archive/last"
  # loop: only the loop's turn joins the archive run to the pick that reads the landed and ended lists after it
  out=$(loop run 2>&1) || fail "the run exited non-zero: $out"
  # The turn can also end cF, in flight with no process (unstick()): only cX's lines are asked of here.
  ! grep -q '"card":"cX"' "$ST/cards.jsonl" && grep -q "^cX	10	" "$ST/landed.tsv" || fail "the loop's turn did not archive cX: live '$(livecards)'; $out"
  [ -z "$(st 'select(.step == "picked" and (.issue | IN(4, 6, 10))) | .card')" ] || fail "the loop picked #4, #6 or #10, whose cards landed or were shut and were archived: $out"
}

# Bugs: one run moves more than ARCHIVE_BATCH cards (holding the lock past its limit on a long history), or not the
# oldest first (the cards' ids run newest first here, so an order by card id moves the newest); a run that left cards
# to move is not run again at the next turn within the hour; or the run is stopped at the lock's limit (it then notes
# 1 left, not the count).
t_archbatch() {
  local n left live first
  setup '[]'
  jq -cn --arg repo "${R##*/}" --argjson t0 "$(jq -n 'now - 10 * 86400 | floor')" 'range(5000) as $i | ($t0 - $i | todate) as $t | "c\(10000 + $i)" as $c
    | {card: $c, issue: 0, step: "picked", time: $t, tokens: {claude: 0, codex: 0}, result: "ok", sha: "", reason: "", repo: $repo},
      {card: $c, issue: 0, step: "closed", time: $t, tokens: {claude: 0, codex: 0}, result: "ok", sha: "", reason: "", repo: $repo}' > "$ST/cards.jsonl"
  for n in 1 2 3; do
    fx_in archiverun
    left=$(cat "$ST/archive/last"); live=$((5000 - n * 2000)); [ "$live" -ge 0 ] || live=0; first=$((10000 + live))
    [ "$left" = "$live" ] && [ "$(wc -l < "$ST/cards.jsonl")" = $((2 * live)) ] && ! grep -q 'ran out of time' "$T/$CASE/run.out" \
      || fail "run $n left $left cards to move and $(wc -l < "$ST/cards.jsonl") live lines, not $live and $((2 * live)): $(cat "$T/$CASE/run.out")"
    [ "$(gzip -dc "$ST"/archive/cards-*.jsonl.gz | jq -r .card | sort -u | sed -n '1p;$p' | paste -sd' ' -) $(gzip -dc "$ST"/archive/cards-*.jsonl.gz | jq -r .card | sort -u | wc -l)" = "c$first c14999 $((5000 - live))" ] \
      || fail "after run $n the archive does not hold the oldest cards alone, c$first to c14999"
  done
}

# Bugs: the archive run holds the records' lock with no limit (locked, not lockedfor): a run stalled under the lock
# holds every card's next line until it ends. Here its first step under the lock stalls: the run must stop at the
# limit, say so, change no record, and leave the next turn to run it again.
t_archlimit() {
  local t
  setup '[]'
  landcard cA 0 "$(ago 3)" > "$ST/cards.jsonl"; cp "$ST/cards.jsonl" "$T/$CASE/was"
  t=$SECONDS
  fx_in 'LOCKLIMIT=1; archsplit() { sleep 60; }; archiverun' # sleep: the stall under the lock that the limit must stop; no check waits on it
  [ $((SECONDS - t)) -lt 30 ] && grep -qF 'conveyor: the archive run ran out of time' "$T/$CASE/run.out" && [ "$(cat "$ST/archive/last")" = 1 ] \
    && cmp -s "$ST/cards.jsonl" "$T/$CASE/was" && [ ! -e "$ST/landed.tsv" ] \
    || fail "a stalled archive run was not stopped at the lock's limit with the records unchanged, after $((SECONDS - t)) s: $(cat "$T/$CASE/run.out")"
}

# Bugs: a line appended between the run's read and its lock (a card's next step, a late line of a card the run moves)
# is lost when the run writes the records it read; or the run moves nothing when the records only grew.
t_archappend() {
  setup '[]'
  { landcard cA 1 "$(ago 3)"; archline cF 2 picked "$(ago 3)"; } > "$ST/cards.jsonl"
  { archline cF 2 build "$(ago 0)"; archline cA 1 issue "$(ago 0)"; } > "$T/$CASE/new"
  # The lines go in through the real writer at the weak point: after the run's read, before it takes the lock.
  fx_in 'eval "real_$(declare -f lockedfor)"; lockedfor() { while read -r l; do locked append "$l"; done < "$T/$CASE/new"; real_lockedfor "$@"; }; archiverun'
  [ "$(livecards)" = 'cF cA' ] && [ "$(tail -n 2 "$ST/cards.jsonl")" = "$(cat "$T/$CASE/new")" ] && [ "$(wc -l < "$ST/cards.jsonl")" = 3 ] \
    || fail "the lines appended after the read are not all live after the write: $(cat "$ST/cards.jsonl") $(cat "$T/$CASE/run.out")"
  [ "$(gzip -dc "$ST"/archive/cards-*.jsonl.gz | jq -r .step | paste -sd' ' -)" = 'picked landed pushed issue' ] || fail "the run did not move cA's four read lines: $(cat "$T/$CASE/run.out")"
}

# Bugs: once a card's lines go to the archive, a reader that asks whether a card or an issue ended no longer finds
# it: the pick takes #21 again, whose card the owner shut (cO); the Tests page's pick starts its landed card cT again
# (its entry's card has no live lines, read as given back), and its review follow-up waits for good on its parent
# card, landed and archived; umbrellas() leaves the parent #10 open, as its part #11 landed and was archived while
# #12 is still open; reopened() and retry no longer give back #23, whose card was shut when its issue was closed
# by hand and which is open again; the next main-red pick (redpick()) starts a new fix card for the red commit whose
# fix card cM the owner shut (read as given back), and redopen() and redlive() read cM as open; the land-branch command (slicetake()) takes over cT's entry,
# though cT is done (its landed commit is main's); and the Tests page (testlines()) loses cT's test run from its history.
t_archreaders() {
  local h p=c20260101T000000-main-22 old
  setup "[$(issue 10 2026-11-01), $(issue 11 2026-11-02), $(issue 12 2026-11-03), $(issue 21 2026-11-04), $(issue 23 2026-11-05)]"
  printf '10 11\n10 12\n' > "$STUB/subs"; h=$(git -C "$R" rev-parse HEAD); old=$(ago 3)
  { landcard cP11 11 "$old" "$h"; archline cO 21 picked "$old"; archline cO 21 closed "$old" | jq -c '.reason = "shut by the owner"'
    archline cR 23 picked "$old"; archline cR 23 closed "$old" | jq -c '.reason = "the issue was closed by hand while the card was blocked"'
    landcard cT 0 "$old" "$h" | jq -c 'if .step == "picked" then .testFile = "t.test.sh" else . end'; landcard "$p" 22 "$old"
    archline cT 0 test "$old" | jq -c '.times = {"t.test.sh": 3}'
    archline cM 0 picked "$old" | jq -c --arg h "$h" '.mainRed = $h'; archline cM 0 closed "$old" | jq -c '.reason = "shut by the owner"'
    archline cP12 12 picked "$(ago 0)"; archline cP12 12 landed "$(ago 0)" | jq -c --arg s "$h" '.sha = $s'; } > "$ST/cards.jsonl"
  jq -cn --arg h "$h" '{reds: [{sha: $h, cases: [{case: "x.test.sh: t_x", file: "x.test.sh"}], card: "cM"}]}' > "$ST/mainred.json"
  mkdir -p "$ST/testactions" && jq -cn --arg p "$p" '{cards: [{file: "t.test.sh", title: "t", body: "Do t.", time: "2026-11-01T00:00:00Z", id: "cT", card: "cT"},
    {title: "follow", body: "Depends on: \($p)\nDo it.", time: "2026-11-01T00:00:01Z", id: "cQ", card: null, label: "Review follow-up"}]}' > "$ST/testactions/cards.json"
  fx_in 'archiverun > /dev/null; echo "pick $(upnext "$(asked)" | jq -c "map(.number)")"; echo "test $(locked testpick "$(asked)")"
    umbrellas "$(asked)"; reopened "$(asked)" > /dev/null 2>&1; echo "again $(upnext "$(asked)" | jq -c "map(.number)")"
    slicetake cT cNew; echo "slice $?"; echo "red [$(locked redpick)]"; redopen cM; echo "redopen $?"; redlive cM; echo "redlive $?"; echo "runs $(testlines | jq -sc "[.[] | select(.times != null) | .card]")"'
  # cQ's line is the picked line of the follow-up the Tests page's pick takes after the run (checked below).
  [ "$(livecards)" = 'cP12 cQ' ] || fail "the archive run did not move the finished cards: live '$(livecards)'"
  grep -qx 'pick \[\]' "$T/$CASE/run.out" || fail "the pick took an issue whose card landed or was shut and was archived: $(cat "$T/$CASE/run.out")"
  grep -qx 'test c[^ ]* 0 false' "$T/$CASE/run.out" && [ "$(jq -c '[.cards[] | [.id, (.card != null), (.was // [])]]' "$ST/testactions/cards.json")" = '[["cT",true,[]],["cQ",true,[]]]' ] \
    || fail "the Tests page's pick did not take the follow-up of the archived parent, or took the archived card cT again: $(cat "$T/$CASE/run.out") $(cat "$ST/testactions/cards.json")"
  [ "$(cat "$STUB/closed" 2>/dev/null)" = 10 ] || fail "umbrellas() did not close #10, whose part #11 landed and was archived: $(cat "$STUB/closed" 2>&1) $(cat "$T/$CASE/run.out")"
  grep -qx 'again \[23\]' "$T/$CASE/run.out" && ! grep -q '"cR"' "$ST/archive/ended.jsonl" && grep -q '"card":"cR","issue":23,"step":"closed"' "$ST/retried.jsonl" \
    || fail "reopened() did not give back #23, its archived shut card's lines moving from the ended list to the retried file: $(cat "$T/$CASE/run.out")"
  grep -qx 'slice 1' "$T/$CASE/run.out" && grep -qF 'slice cT is done already, as card cT' "$T/$CASE/run.out" \
    || fail "slicetake cT cNew did not refuse the archived done slice cT: $(cat "$T/$CASE/run.out")"
  grep -qx 'red \[\]' "$T/$CASE/run.out" && [ "$(jq -r '.reds[0].card' "$ST/mainred.json")" = cM ] \
    || fail "redpick started a fix card for the red commit whose shut fix card cM was archived: $(cat "$T/$CASE/run.out") $(cat "$ST/mainred.json")"
  # redopen() and redlive() read cM, shut and archived, as ended: main red for its cases no longer holds cards back.
  grep -qx 'redopen 1' "$T/$CASE/run.out" && grep -qx 'redlive 1' "$T/$CASE/run.out" \
    || fail "redopen cM or redlive cM read the archived shut card cM as open: $(cat "$T/$CASE/run.out")"
  grep -qx 'runs \["cT"\]' "$T/$CASE/run.out" || fail "testlines lost the test run of cT, archived: $(cat "$T/$CASE/run.out")"
}

# Bugs: with Land as pr, the archive run moves a landed and pushed card whose commit the pull request still holds
# (origin's default branch, as last fetched, does not): Merge PR idle (idleone(), lib/push.sh) then finds no live
# landing and never merges, and the run before the merge (pushtests()) leaves its test files out; or it keeps one whose
# commit origin's default branch holds (its pull request merged).
t_archpr() {
  local a b
  setup '[]'; tune '.push.landAs = "pr"'
  git -C "$R" commit -q --allow-empty -m merged && a=$(git -C "$R" rev-parse HEAD) && git -C "$R" update-ref refs/remotes/origin/main "$a" \
    && git -C "$R" commit -q --allow-empty -m held && b=$(git -C "$R" rev-parse HEAD) || fail "the fixture's commits could not be made"
  { landcard cM 0 "$(ago 3)" "$a"; landcard cH 0 "$(ago 3)" "$b"; } > "$ST/cards.jsonl"
  fx_in archiverun
  [ "$(livecards)" = cH ] || fail "with Land as pr the live records hold '$(livecards)', not cH alone, whose commit the pull request holds: $(cat "$T/$CASE/run.out")"
}

# Bugs: the snapshot reads the archive files as they are when it reads them, not as they were with its copy of the
# records: an archive run between the two moves a card into the archive the copy holds too, and the Board counts its
# landing twice. The run is made to act at that point through the snapshot itself: between its copy and its read of
# the archive (archrows()).
t_archsnap() {
  setup '[]'
  # The snapshot's landed list holds today's landings alone: cA landed seconds ago, and the run, with ARCHIVE_DAYS 0,
  # moves it (a run within seconds of midnight would date it yesterday).
  landcard cA 0 "$(ago 0.0001)" > "$ST/cards.jsonl"
  fx_in 'ARCHIVE_DAYS=0; . "$SRC/lib/snapshot.sh" && . "$SRC/lib/setup.sh" || exit 9; eval "real_$(declare -f archrows)"; archrows() { archiverun >&2; real_archrows "$@"; }
    snapshot | jq -c "[.landedCount, [.landed[].card]]"'
  [ -z "$(livecards)" ] && [ "$(tail -n 1 "$T/$CASE/run.out")" = '[1,["cA"]]' ] \
    || fail "the snapshot counted cA, moved to the archive after its copy, other than once: live '$(livecards)'; $(cat "$T/$CASE/run.out")"
}
