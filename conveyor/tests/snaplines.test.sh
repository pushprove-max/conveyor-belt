#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 120
# Engine cases: the running summaries of the card records and the retried file that health, the slow-test list and
# the Tests part read in place of every line (lib/records.sh linesum, HEALTHLINE, TESTLINE), and the cards priced at
# the last snapshot (dashboard_limit.py cardlines), with their metrics, run sums and waits (cardruns.py).
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"
# The engine folder, as lib.sh sets it: named here too, so the release closure (tools/closure.sh) follows this file's paths.
SRC=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)

# A line of the records: <card> <issue> <step> <result> <minute of 2026-11-17T10> [extra json]. Every case file is
# sourced into one shell (conveyor.test.sh), so the helpers carry the file's name.
snaplines_line() {
  jq -cn --arg c "$1" --argjson i "$2" --arg s "$3" --arg r "$4" --arg t "2026-11-17T10:$5:00Z" --argjson x "${6:-{\}}" \
    '{card: $c, issue: $i, step: $s, time: $t, tokens: {claude: 1, codex: 0}, result: $r, sha: "", reason: "", repo: "r"} * $x'
}

# Bug: health, the slow-test list, the Tests part, the pricing and the final assembly read every line of the records,
# or priced and measured every card, on each snapshot (most of the snapshot's growth with the history). Read from
# summaries kept beside the records, brought up to date with the lines appended since (a card priced again only when
# its line changed, an issue's metrics made again only when its cards changed), a field one of
# them reads but the summary left out, a line it left out, or a card's price kept from before it changed, changes what the snapshot
# shows: here the whole snapshot from the summaries is compared with the one read from scratch. The records hold each
# field those readers read: a dead worktree (gone), a failed test step with its cases, verdicts and output, a run
# again, test times and clocks, a refused full run, a review's COVERED-BY line, a speed proof, a landed line with its
# follow-ups and test edits, a failed push, a main-red card, a blocked one, issues that wait on each other (cycles) and
# a slow file whose issue lands in the appended lines (the slow-test list).
t_snaplinessame() {
  local a b h s='a.test.sh' f m='del(.health.diskFreeKb, .health.machineNow, .health.pressure, .health.cores, .testSlots)'
  export TZ=UTC CONVEYOR_NOW=1794918000
  setup "$(jq -cs . <(issue 2 2026-11-01) <(issue 7 2026-11-01 | jq -c '.body = "Depends on: #8"') <(issue 8 2026-11-01 | jq -c '.body = "Depends on: #7"'))"
  f=$(jq -cn --arg s "$s" '{of: 1, files: [{file: $s, cases: [{line: "", name: "one"}]}], timeout: null}')
  # c1's landed commit is in main and not pushed (unpushed, and the failed push after it).
  echo one > "$R/one.txt" && git -C "$R" add one.txt && git -C "$R" commit -qm one && h=$(git -C "$R" rev-parse HEAD) || fail "the fixture's commit failed"
  {
    snaplines_line c1 1 picked ok 00 '{"title": "one"}'
    snaplines_line c1 1 worktree ok 01 '{"pid": 999999999, "started": "x"}'
    snaplines_line c1 1 review NO-GO 02 '{"reason": "P1 a finding\nCOVERED-BY: b.test.sh: it still runs the case\nmore"}'
    snaplines_line c1 1 test fail 03 "$(jq -cn --arg s "$s" --argjson f "$f" '{failures: $f, verdicts: [{case: "\($s): one", verdict: "card"}], tail: "boom", times: {($s): 1.5}}')"
    snaplines_line c1 1 test pass 04 "$(jq -cn --arg s "$s" --argjson f "$f" '{times: {($s): 1.2}, clocks: {"b.test.sh": 2}, rerun: {exit: 1, failures: $f, tail: "first run"}, wait: 1, run: 3}')"
    snaplines_line c1 1 bugproof ok 05 "$(jq -cn --arg s "$s" '{speed: {file: $s, before: 2, after: 1, fix: "sped up", into: []}}')"
    snaplines_line c1 1 landed ok 06 "$(jq -cn --arg s "$s" --arg h "$h" '{sha: $h, product: false, followups: [9],
      testedits: [{file: $s, read: true, removedAsserts: 1, changedExpected: 0, skipsAdded: 0, timeoutsRaised: 0, casesDeleted: 0}]}')"
    snaplines_line c1 1 push fail 07 "$(jq -cn --arg h "$h" '{sha: $h, kind: "transport", check: null, reason: "no network"}')"
    snaplines_line c2 2 picked ok 08 '{"title": "two"}'
    snaplines_line c2 2 worktree ok 09 '{"pid": 999999998, "started": "y"}'
    snaplines_line c2 2 test pass 10 '{"refused": "refused full run: too many files", "selected": {"files": 2, "filesOf": null, "cases": null, "casesOf": null}}'
    snaplines_line c3 0 picked ok 11 '{"mainRed": "abcdef0123456789", "title": "red"}'
    snaplines_line c3 0 blocked blocked 12 '{"reason": "build: failed"}'
  } > "$ST/cards.jsonl"
  { snaplines_line c0 2 picked ok 00 '{"title": "two"}'; snaplines_line c0 2 blocked blocked 01 '{"reason": "brief: failed"}'; } > "$ST/retried.jsonl"
  jq -cn --arg s "$s" '{filed: [{file: $s, issue: 2, cpu: 9}, {file: "b.test.sh", issue: 1, cpu: 9}]}' > "$ST/slow.json"
  a=$(loop snapshot) || fail "the first snapshot exited non-zero"
  [ "$(jq -c '.slowOff | map(.file)' <<<"$a")" = "[\"$s\"]" ] || fail "the slow file of an issue no card has landed is not kept off: $(jq -c .slowOff <<<"$a")"
  [ -s "$ST/cards.jsonl.health" ] && [ -s "$ST/cards.jsonl.tests" ] && [ -s "$ST/retried.jsonl.health" ] && [ -s "$ST/retried.jsonl.tests" ] && [ -s "$ST/cards.jsonl.priced" ] && [ -s "$ST/cards.jsonl.cardruns" ] \
    || fail "the first snapshot kept no summary of the records: $(ls "$ST")"
  # Lines appended since: c2 tested and landed (its slow file comes back), a new card, and c3 reviewed.
  {
    snaplines_line c2 2 test pass 13 "$(jq -cn --arg s "$s" '{times: {($s): 0.5}}')"
    snaplines_line c2 2 landed ok 14 '{"sha": "1123456789012345678901234567890123456789", "product": false}'
    snaplines_line c4 4 picked ok 15 '{"title": "four"}'
    snaplines_line c4 4 worktree ok 16 '{"pid": 999999997, "started": "z"}'
    snaplines_line c3 0 review GO 17 '{"reason": "COVERED-BY: a.test.sh: the case", "model": "claude-opus-5-5", "usage": {"input": 1000000, "write": 0, "read": 0, "output": 0}}'
  } >> "$ST/cards.jsonl"
  a=$(loop snapshot) || fail "the snapshot from the summaries exited non-zero"
  [ "$(head -n 1 "$ST/cards.jsonl.health" | cut -d' ' -f1)" = "$(wc -c < "$ST/cards.jsonl")" ] || fail "the health summary was not brought up to the records' end"
  rm -f "$ST"/*.jsonl.health "$ST"/*.jsonl.tests "$ST"/*.jsonl.rows "$ST"/*.jsonl.priced "$ST"/*.jsonl.cardruns
  b=$(loop snapshot) || fail "the snapshot read from scratch exited non-zero"
  # What the fields the summaries keep give, as the lines say it (a summary that left one out would give it in both
  # snapshots alike): the dead worktree, the landed commit not pushed and the push that failed, the refused run, the
  # cycle, the main-red card's name and blocked reason, the slow file back on card steps, and of the test file its
  # newest time, the failure the landed commit left the file as it was in (caught), each failed run (newest first:
  # the run again's first run, then the failed step) with its verdict, cases and output, and the landed test edits.
  jq -e --arg s "$s" --arg h "$h" '(.health.stuck | map(.card) | index("c4")) != null and (.health.unpushed | map(.sha)) == [$h] and .health.pushError.reason == "no network"
      and (.health.refused | map(.card)) == ["c2"] and .health.cycles == [[7, 8]] and .slowOff == []
      and (.health.blocked | map([.card, .reason, .name])) == [["c3", "build: failed", "Main is red (abcdef012345)"]]
      and (.tests.files[] | select(.file == $s) | [.cpu, .caught, [.failures[] | [.verdict, .cases, .tail]]]) == [0.5, 1, [[null, ["one"], "first run"], ["card", ["one"], "boom"]]]
      and (.tests.edits | map(.file)) == [$s]' <<<"$a" > /dev/null \
    || fail "the snapshot does not show what the records say: $(jq -c --arg s "$s" '{stuck: .health.stuck, unpushed: .health.unpushed, pushError: .health.pushError, refused: .health.refused,
      cycles: .health.cycles, blocked: .health.blocked, slowOff, file: (.tests.files[] | select(.file == $s) | {cpu, caught, failures}), edits: .tests.edits}' <<<"$a")"
  # The machine's own readings (free disk, load, pressure, cores, test slots) are read anew by each snapshot.
  [ "$(jq -c "$m" <<<"$a")" = "$(jq -c "$m" <<<"$b")" ] || fail "the snapshot from the summaries differs from the one read from scratch: $(diff <(jq -S "$m" <<<"$a") <(jq -S "$m" <<<"$b") | head -n 20)"
}

# Bug: a summary read on from its offset in a file `retry` rewrote (its lines moved out of the card records): past
# the end of a shorter file, or, grown past the offset again, from the middle of a line, with the moved card's lines
# kept. Each summary (health's, the Tests part's) is read again from the start, and the lines appended to a file
# that was not rewritten are the only ones read. linesum() is called as health and testspart call it.
t_snaplinesshort() {
  local D=$T/$CASE n
  mkdir -p "$D" || fail "the case's folder could not be made"
  eval "$(sed -n '/^linesum() {/,/^}/p' "$SRC/lib/records.sh"; sed -n "/^HEALTHLINE='/,/'$/p" "$SRC/lib/views.sh"; sed -n "/^TESTLINE='/,/'$/p" "$SRC/lib/testfiles.sh")"
  declare -F linesum > /dev/null && [ -n "$HEALTHLINE" ] && [ -n "$TESTLINE" ] || fail "linesum or its filters were not found in the engine"
  # Each run of a filter: the lines it was given, in $D/read.
  jq() { if [ "$1" = -cR ]; then tee "$D/read" | command jq "$@"; else command jq "$@"; fi; }
  for n in HEALTHLINE TESTLINE; do
    { for c in 1 2 3; do snaplines_line "c$c" "$c" picked ok 0$c; snaplines_line "c$c" "$c" test pass 1$c '{"times": {"a.test.sh": 1}}'; done; } > "$D/rec"
    rm -f "$D/rec.sum"
    linesum "$D/rec" "$D/rec.sum" "$D/out" "${!n}" || fail "$n: the first summary failed"
    [ "$(wc -l < "$D/read")" = 6 ] || fail "$n: the first summary did not read the whole file"
    # Appended to: only the new line is read.
    snaplines_line c3 3 landed ok 20 >> "$D/rec"
    linesum "$D/rec" "$D/rec.sum" "$D/out" "${!n}" || fail "$n: the summary of the grown file failed"
    [ "$(wc -l < "$D/read")" = 1 ] || fail "$n: the summary of a grown file read $(wc -l < "$D/read") lines, not the one appended"
    # Rewritten shorter (c1 moved out): read from the start, c1 gone.
    grep -v '"card":"c1"' "$D/rec" > "$D/short" && mv "$D/short" "$D/rec"
    linesum "$D/rec" "$D/rec.sum" "$D/out" "${!n}" || fail "$n: the summary of the shorter file failed"
    [ "$(wc -l < "$D/read")" = 5 ] && ! grep -q '"c1"' "$D/out" || fail "$n: the summary of a file rewritten shorter was not read from the start: $(cat "$D/out")"
    # Rewritten again (c2 moved out) and grown past the offset since: read from the start again.
    grep -v '"card":"c2"' "$D/rec" > "$D/short" && mv "$D/short" "$D/rec"
    for c in 4 5 6; do snaplines_line "c$c" "$c" test pass 3$c '{"times": {"a.test.sh": 2}}' >> "$D/rec"; done
    [ "$(wc -c < "$D/rec")" -gt "$(head -n 1 "$D/rec.sum" | cut -d' ' -f1)" ] || fail "the fixture is wrong: the rewritten file is not longer than the summary's offset"
    linesum "$D/rec" "$D/rec.sum" "$D/out" "${!n}" || fail "$n: the summary of the rewritten, grown file failed"
    [ "$(wc -l < "$D/read")" = 6 ] && ! grep -q '"c2"' "$D/out" || fail "$n: the summary of a file rewritten and grown past its offset was not read from the start: $(cat "$D/out")"
    # What it holds is what the filter makes of the whole file.
    [ "$(cat "$D/out")" = "$(command jq -cR "${!n}" "$D/rec")" ] && [ "$(tail -n +2 "$D/rec.sum")" = "$(cat "$D/out")" ] \
      || fail "$n: the summary differs from the filter's reading of the whole file"
  done
  unset -f jq
}

# Bug: the snapshot priced every card of the history again on each run (dashboard_limit.py cards), and grew with the
# card count. A card whose line is as it was is taken from the summary of the last call: here a kept price changed
# by hand (99) shows that it was not priced again, and the cards whose line changed are. The summary is not used, and
# every card is priced anew, when the pack's prices change or its body is not the one its first line names.
t_snaplinesprice() {
  local D=$T/$CASE b
  mkdir -p "$D" || fail "the case's folder could not be made"
  snaplines_card() { jq -cn --arg c "$1" --argjson n "$2" '{card: $c, models: {}, steps: [range($n) | {step: "build", time: "2026-11-17T10:0\(.):00Z", model: "claude-opus-5-5",
    usage: {input: 1000000, write: 0, read: 0, output: 0}}]}'; }
  snaplines_price() { # <prices json>: the part on stdout, the cards in $D/priced (one array; cardlines writes one a line)
    jq -cn --argjson p "$1" '{prices: $p, since: "2026-11-01T00:00:00Z"}' | python3 "$SRC/../.claude/scripts/dashboard_limit.py" cardlines "$D/all" "$D/kept" "$D/lines" \
      && jq -cs . "$D/lines" > "$D/priced"
  }
  # The kept price of card a set to 99, with the summary's first line made right for its new body.
  snaplines_tamper() {
    python3 -c 'import hashlib, json, sys
p = sys.argv[1]; head, body = open(p, "rb").read().split(b"\n", 1)
def one(l):
    f = l.split(b"\t"); c = json.loads(f[1])
    if c["card"] == "a": c["usd"] = 99; f[1] = json.dumps(c, separators=(",", ":")).encode()
    return b"\t".join(f)
body = b"".join(one(l) + b"\n" for l in body.split(b"\n")[:-1])
open(p, "wb").write(head.split()[0] + b" " + hashlib.sha256(body).hexdigest().encode() + b"\n" + body)' "$D/kept"
  }
  { snaplines_card a 1; snaplines_card b 1; } > "$D/all"
  snaplines_price '{}' > /dev/null && [ -s "$D/kept" ] || fail "the first pricing failed or kept no summary"
  # What the stdin form prices of the same cards, as the snapshot priced them before.
  [ "$(jq -c '.cards' < <(jq -cs '{cards: ., prices: {}, since: "2026-11-01T00:00:00Z"}' "$D/all" | python3 "$SRC/../.claude/scripts/dashboard_limit.py" cards))" = "$(jq -c . "$D/priced")" ] \
    || fail "the cards priced from their lines differ from the same cards priced whole: $(cat "$D/priced")"
  snaplines_tamper
  # b grows a step and c is new: both are priced; a is kept, and seen counts every step.
  { snaplines_card a 1; snaplines_card b 2; snaplines_card c 1; } > "$D/all"
  b=$(snaplines_price '{}') || fail "the second pricing failed"
  [ "$(jq -c 'map([.card, .usd])' "$D/priced")" = "$(jq -cs '{cards: ., prices: {}}' "$D/all" | python3 "$SRC/../.claude/scripts/dashboard_limit.py" cards | jq -c '.cards | .[0].usd = 99 | map([.card, .usd])')" ] \
    && [ "$(jq -c '.seen[0].sessions' <<<"$b")" = 4 ] || fail "only the changed cards were not priced again: $(jq -c 'map([.card, .usd])' "$D/priced") $(jq -c .seen <<<"$b")"
  # Other prices: every card priced anew.
  snaplines_price '{"claude-opus-5-5": {"input": 1, "output": 1, "cacheRead": 1}}' > /dev/null && [ "$(jq -c 'map(.usd) == [1, 2, 1]' "$D/priced")" = true ] \
    || fail "a kept price was used under other prices: $(jq -c 'map(.usd)' "$D/priced")"
  # A body that is not the one its first line names: not used.
  snaplines_price '{}' > /dev/null && snaplines_tamper && printf 'x' >> "$D/kept" && snaplines_price '{}' > /dev/null && [ "$(jq -c '.[0].usd != 99' "$D/priced")" = true ] \
    || fail "a summary whose body is not the one it names was used: $(jq -c 'map(.usd)' "$D/priced")"
}

# Bug: the snapshot's final assembly made every card's metrics (cardm), its runs' sums (runSteps) and its waits again
# on each run, and grew with the card count. cardruns.py makes again only the issues whose figures can have changed:
# their cards' lines, now (a card still blocked waits to now) or the samples in a card's queue time. Each result is
# what CARDRUNS gives run on every card; a kept card set by hand to "kept" shows which cards were not made again.
t_snaplinesruns() {
  local D=$T/$CASE CARDRUNS
  mkdir -p "$D" || fail "the case's folder could not be made"
  eval "$(sed -n "/^CARDRUNS='/,/'$/p" "$SRC/lib/snapshot.sh")"
  [ -n "$CARDRUNS" ] && printf '%s\n%s\n' "$(cat "$SRC/jq/metrics.jq")" "$CARDRUNS" > "$D/p.jq" || fail "CARDRUNS was not found in the engine"
  # <card> <issue> <picked minute> <end minute> [x extra]: a landed card as the snapshot's priced cards hold it.
  snaplines_runcard() {
    jq -cn --arg c "$1" --argjson i "$2" --arg p "2026-11-17T10:$3:00Z" --arg e "2026-11-17T10:$4:00Z" --argjson x "${5:-{\}}" \
      '{card: $c, issue: $i, step: "landed", startedAt: $p, usd: 1, reviews: [], reason: "build: failed", steps: [{step: "build", time: $p, result: "ok", usd: 1}],
        x: ({endAt: $e, log: [{step: "picked", time: $p}], tokens: {claude: 1, codex: 0}, followups: []} * $x)}'
  }
  snaplines_runs() { python3 "$SRC/cardruns.py" "$D/cards" "$D/kept" "$D/out" "$D/p.jq" "$D/smp" "$1" 60 'Needs your yes'; }
  # What CARDRUNS gives run on every card, in the form cardruns.py writes.
  snaplines_whole() {
    jq -cs --argjson now "$1" --argjson every 60 --arg yes 'Needs your yes' --slurpfile smp "$D/smp" -f "$D/p.jq" "$D/cards" \
      | jq -cs '[range(0; length; 3) as $i | .[$i]], [range(1; length; 3) as $i | .[$i][]] + [range(2; length; 3) as $i | .[$i][]]'
  }
  # The cards not made again: each kept card's metrics set to "kept", the summary's first line made right for its body.
  snaplines_keep() {
    python3 -c 'import hashlib, json, sys
p = sys.argv[1]; head, body = open(p, "rb").read().split(b"\n", 1)
def one(l):
    f = l.split(b"\t"); c = json.loads(f[1]); c["metrics"] = "kept"; f[1] = json.dumps(c, separators=(",", ":")).encode()
    return b"\t".join(f)
body = b"".join(one(l) + b"\n" for l in body.split(b"\n")[:-1])
open(p, "wb").write(head.split()[0] + b" " + hashlib.sha256(body).hexdigest().encode() + b"\n" + body)' "$D/kept"
  }
  snaplines_made() { jq -c '[.[] | select(.metrics != "kept") | .card]' < <(head -n 1 "$D/out"); }
  # a0 and a are two runs of issue 1 (a0 blocked, retried); b is blocked, waiting to now; c's queue time, 10:15 to
  # its pick at 10:20, holds a full sample.
  {
    snaplines_runcard a0 1 40 45 '{"retried": true, "retriedAt": "2026-11-17T10:50:00Z"}' | jq -c '.step = "blocked" | .startedAt = "2026-11-17T09:40:00Z" | .x.endAt = "2026-11-17T09:45:00Z"'
    snaplines_runcard a 1 00 05
    snaplines_runcard b 2 10 12 | jq -c '.step = "blocked"'
    snaplines_runcard c 3 20 25 '{"log": [{"step": "picked", "time": "2026-11-17T10:20:00Z", "created": "2026-11-17T10:15:00Z"}]}'
  } > "$D/cards" || fail "the fixture's cards could not be made"
  echo '{"time": "2026-11-17T10:16:00Z", "slots": 1, "cap": 1}' > "$D/smp"
  snaplines_runs 1794913200 && [ "$(jq -c . "$D/out")" = "$(snaplines_whole 1794913200)" ] \
    || fail "the first call differs from CARDRUNS run on every card: $(diff <(jq -c . "$D/out") <(snaplines_whole 1794913200) | head -n 5)"
  [ "$(jq -c '[.[] | [.card, .metrics.runs]]' < <(head -n 1 "$D/out"))" = '[["a0",1],["a",2],["b",1],["c",1]]' ] && [ "$(sed -n 2p "$D/out" | jq length)" = 2 ] \
    || fail "the fixture does not hold two runs of issue 1 and two waits: $(cat "$D/out")"
  # From the summary, at a later now: the same as from scratch.
  snaplines_runs 1794916800 && [ "$(jq -c . "$D/out")" = "$(snaplines_whole 1794916800)" ] \
    || fail "a call from the summary differs from CARDRUNS run on every card: $(diff <(jq -c . "$D/out") <(snaplines_whole 1794916800) | head -n 5)"
  snaplines_keep && snaplines_runs 1794916800 && [ "$(snaplines_made)" = '[]' ] || fail "cards that did not change were made again: $(snaplines_made)"
  snaplines_keep && snaplines_runs 1794920400 && [ "$(snaplines_made)" = '["b"]' ] || fail "a new now made other than the blocked card again: $(snaplines_made)"
  snaplines_keep && echo '{"time": "2026-11-17T10:17:00Z", "slots": 1, "cap": 1}' >> "$D/smp" && echo '{"time": "2026-11-17T11:00:00Z", "slots": 1, "cap": 1}' >> "$D/smp" \
    && snaplines_runs 1794920400 && [ "$(snaplines_made)" = '["c"]' ] || fail "a sample in c's queue time made other than c again: $(snaplines_made)"
  snaplines_keep && sed -i '/"card":"a",/s/"usd":1,/"usd":2,/' "$D/cards" \
    && snaplines_runs 1794920400 && [ "$(snaplines_made)" = '["a0","a"]' ] || fail "a changed card made other than its issue's cards again: $(snaplines_made)"
  # A card name in two issues: every card is made again, as one issue.
  snaplines_keep && snaplines_runcard c 4 30 35 >> "$D/cards" && snaplines_runs 1794920400 && [ "$(snaplines_made)" = '["a0","a","b","c","c"]' ] \
    && [ "$(jq -c . "$D/out")" = "$(snaplines_whole 1794920400)" ] || fail "a card name in two issues was not made again whole: $(snaplines_made)"
}
