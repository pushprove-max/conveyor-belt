#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 300
# Engine cases: the pack's path-to-area map (labels.areaPaths, lib/areas.sh). An entry of the self-heals list takes the
# area of the file its finding names, and its issue's area label only when it names none; every filing path files with
# an area label; the one pass (`heals areas`) gives what has no area one; a pack with no map works as before.
# Issue 1693: 331 of 469 entries of a project's self-heals list had no area, as only the issue's label was read.
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"

# The map of these cases: lib/ is the engine, lib/tests/ (longer, so it wins) the tests, docs/ the docs, else plugin.
AMAP='{"paths": {"lib/": "area:engine", "lib/tests/": "area:tests", "docs/": "area:docs"}, "other": "area:plugin"}'
amap() { setup "${1:-[]}"; tune --argjson m "$AMAP" '.labels.areaPaths = $m'; } # [issues json]: a case's main whose pack has the map
# One judge decision marked for its list (healsput(), lib/review.sh, as judged() writes it), in $STUB/said.
said() { jq -cn --arg f "$1" '{d: [{n: 1, accept: true, heals: true, effect: "self-heals", reason: "it heals", finding: $f}]}' > "$STUB/said"; } # <finding>
area() { jq -c --arg c "$1" 'select(.card == $c) | .area' "$ST/selfheals.jsonl"; } # <card>: its entry's area
labels() { sed -n "${1}p" "$STUB/filed" | jq -c '[.labels[].name]'; } # <n>: the labels of the nth issue filed
# Main's lib/tests/x.test.sh, which defines the case t_one (a case named alone, `one`, is of that file).
mainfile() { mkdir -p "$R/lib/tests" && echo 't_one() { :; }' > "$R/lib/tests/x.test.sh" && git -C "$R" add lib && git -C "$R" commit -qm x || fail "main's lib/tests/x.test.sh"; }

# Bug (#1693): a review of a card whose issue has no area label wrote its finding to the list with no area, though
# the finding names its file; and the issue's label won over the file. Through healsput(), as a review writes them.
t_areaentry() {
  amap; said '[P2] lib/tests/x.test.sh:3 a slow wait. Proof: lib/tests/x.test.sh:3'
  fx_in 'healsput c1-7 7 "" "$STUB/said"'
  [ "$RC" = 0 ] && [ "$(area c1-7)" = '"area:tests"' ] \
    || fail "healsput c1-7 7 '' of the finding '[P2] lib/tests/x.test.sh:3 ...' wrote area $(area c1-7), not area:tests (exit $RC): $(cat "$T/$CASE/run.out")"
  said '[P2] `lib/a.sh`: a late line'
  fx_in 'healsput c2-8 8 area:board "$STUB/said"'
  [ "$(area c2-8)" = '"area:engine"' ] || fail "healsput c2-8 8 area:board of the finding '[P2] \`lib/a.sh\`: ...' wrote area $(area c2-8), not its file's area:engine"
}
# Bug (review of #1693): a finding listed again kept the null area of its entry, listed before the pack had the map.
# Through healsput(), as a review lists it again: an entry with no area takes its file's; one with an area keeps it.
t_areaagain() {
  amap
  for x in 'h00000000001|null|[P2] lib/a.sh:1 a late line' 'h00000000002|"area:board"|[P2] lib/b.sh:1 a slow poll'; do
    IFS='|' read -r i a f <<<"$x"
    jq -cn --arg i "$i" --argjson a "$a" --arg f "$f" '{id: $i, time: "2026-11-20T00:00:00Z", card: "c0", issue: 5, area: $a, finding: $f, why: "w", effect: "self-heals", from: "review"}' >> "$ST/selfheals.jsonl"
  done
  said '[P2] lib/a.sh:1 a late line'; fx_in 'healsput c1-7 7 "" "$STUB/said"'
  said '[P2] lib/b.sh:1 a slow poll'; fx_in 'healsput c2-8 8 "" "$STUB/said"'
  [ "$(jq -c '[.id, .card, .area]' "$ST/selfheals.jsonl" | paste -sd' ' -)" = '["h00000000001","c1-7","area:engine"] ["h00000000002","c2-8","area:board"]' ] \
    || fail "healsput of '[P2] lib/a.sh:1 a late line' (entry of no area) and '[P2] lib/b.sh:1 a slow poll' (entry of area:board) again left the list: $(cat "$ST/selfheals.jsonl") ($(cat "$T/$CASE/run.out"))"
}
# A finding that names no file keeps its issue's area label; with no label too, it has no area (the Board shows it
# under No area, never hidden).
t_areaentrynofile() {
  # Two findings: one finding listed again moves its entry to the later card (healsagain(), lib/healslist.sh).
  amap; said '[P2] the wait is long'; fx_in 'healsput c1-7 7 area:board "$STUB/said"'
  said '[P2] the poll is slow'; fx_in 'healsput c2-8 8 "" "$STUB/said"'
  [ "$(area c1-7)" = '"area:board"' ] && [ "$(area c2-8)" = null ] \
    || fail "healsput of the findings '[P2] the wait is long' (issue label area:board) and '[P2] the poll is slow' (no label), no file in either, wrote areas $(area c1-7) and $(area c2-8), not area:board and null"
}
# A pack with no map works as before: the issue's label, else none, also for a finding that names a file; a filing has
# no area label of its own; doctor says the map is missing; the one pass changes nothing.
t_areanomap() {
  # Two findings: one finding listed again moves its entry to the later card (healsagain(), lib/healslist.sh).
  setup '[]'; mainfile
  said '[P2] lib/a.sh:1 a late line'; fx_in 'healsput c1-7 7 area:board "$STUB/said"'
  said '[P2] lib/b.sh:1 a slow poll'; fx_in 'healsput c2-8 8 "" "$STUB/said"; testissue lib/tests/x.test.sh "Speed up x" "Measured."'
  [ "$(area c1-7)" = '"area:board"' ] && [ "$(area c2-8)" = null ] \
    || fail "with no map, healsput of '[P2] lib/a.sh:1 ...' (issue label area:board) and '[P2] lib/b.sh:1 ...' (no label) wrote areas $(area c1-7) and $(area c2-8), not area:board and null"
  [ "$(labels 1 | jq 'map(select(startswith("area:"))) | length')" = 0 ] || fail "with no map, testissue lib/tests/x.test.sh filed the labels $(labels 1)"
  fx_in 'areadoctor "$PACK"'
  grep -q '^warning: the pack sets no labels.areaPaths' "$T/$CASE/run.out" || fail "areadoctor of a pack with no map said: $(cat "$T/$CASE/run.out")"
  cp "$ST/selfheals.jsonl" "$STUB/before"
  fx_in 'healsareas'
  [ "$RC" = 2 ] && cmp -s "$ST/selfheals.jsonl" "$STUB/before" || fail "healsareas with no map exited $RC or changed the list: $(cat "$T/$CASE/run.out")"
}
# Bug it catches: doctor warns that the map is missing when the pack has one.
t_areadoctor() {
  amap; fx_in 'areadoctor "$PACK"'
  [ "$RC" = 0 ] && ! grep -q 'areaPaths' "$T/$CASE/run.out" || fail "areadoctor of a pack with the map $AMAP said: $(cat "$T/$CASE/run.out")"
}

# Bug (#1693): the Foreman's testissue, and its card with no GitHub issue, had no area label.
t_areatestissue() {
  amap; mainfile; fx_in 'testissue lib/tests/x.test.sh "Speed up x" "Measured."'
  [ "$RC" = 0 ] && labels 1 | jq -e 'index("area:tests")' > /dev/null || fail "testissue lib/tests/x.test.sh filed the labels $(labels 1) (exit $RC): $(cat "$T/$CASE/run.out")"
}
t_areatestcard() {
  amap; mainfile; loop control rules testissues=off > /dev/null || fail "control rules testissues=off was refused"
  fx_in 'testissue lib/tests/x.test.sh "Speed up x" "Measured."'
  [ "$(jq -c '.cards[0].labels' "$ST/testactions/cards.json")" = '["bug","P2","area:tests"]' ] \
    || fail "testissue lib/tests/x.test.sh with testissues off made a card with the labels $(jq -c '.cards[0].labels' "$ST/testactions/cards.json" 2>&1)"
}
# The Foreman's card: the area of the file its body ($STUB/body) names.
cardbody() { printf '%s\n' 'Fix `docs/a.md`.' '' '## Cause' 'It is old.' > "$STUB/body"; }
t_areacard() {
  amap; cardbody; fx_in 'cardnew "Fix the page" "$(cat "$STUB/body")"'
  [ "$RC" = 0 ] && labels 1 | jq -e 'index("area:docs")' > /dev/null || fail "cardnew of a body naming \`docs/a.md\` filed the labels $(labels 1) (exit $RC): $(cat "$T/$CASE/run.out")"
}
t_areacardnoissue() {
  amap; cardbody; loop control rules foremanissues=off > /dev/null || fail "control rules foremanissues=off was refused"
  fx_in 'cardnew "Fix the page" "$(cat "$STUB/body")"'
  [ "$(jq -c '.cards[0].labels' "$ST/testactions/cards.json")" = '["bug","P2","area:docs"]' ] \
    || fail "cardnew of a body naming \`docs/a.md\` with foremanissues off made a card with the labels $(jq -c '.cards[0].labels' "$ST/testactions/cards.json" 2>&1)"
}
# A follow-up takes its parent's area; a parent with none gives it the area of its finding's file.
fuarea() { # <parent's labels json> <the area it must have>
  amap "[$(issue 7 2026-01-01)]"
  printf '%s\n' '[P2] lib/a.sh:1 the word is wrong' 'VERDICT: NO-GO' > "$STUB/r.review"
  jq -cn --argjson l "$1" '{number: 7, title: "t", body: "b", labels: $l, milestone: null}' > "$STUB/parent.json"
  fx_in 'followups c1-7 "$(cat "$STUB/parent.json")" "$STUB/r.review"'
  [ "$RC" = 0 ] && [ "$(labels 1 | jq -c 'map(select(startswith("area:")))')" = "[\"$2\"]" ] \
    || fail "followups of '[P2] lib/a.sh:1 ...' under a parent labelled $1 filed the labels $(labels 1), not one area $2 (exit $RC): $(cat "$T/$CASE/run.out")"
}
t_areafollowup() { fuarea '[]' area:engine; }
t_areafollowupparent() { fuarea '[{"name": "area:board"}]' area:board; }
# A flaky test's issue (flakyfile(), through flaky() as its third source files it): the area of its case's file (with
# no map, area:engine when nonProductAreas names it, as before). Bug (review of #1693): the full test names a case
# alone (`one`), which the map gave its other area, not that of lib/tests/x.test.sh, which defines it. Bug (review of
# #1693): main's table of cases to files (lib/tests/big.test.sh's 6000 cases) over Linux's 128 KiB limit of one
# argument made jq fail, and the case got the map's other area.
t_areaflaky() {
  amap; mkdir -p "$R/lib/tests" && printf 't_c%025d() { :; }\n' $(seq 6000) > "$R/lib/tests/big.test.sh"; mainfile
  fx_in 'for s in a b c; do flaky "$s" "[{\"case\": \"one\"}]" || exit 1; done'
  [ "$RC" = 0 ] && [ "$(labels 1)" = '["bug","P2","area:tests","flaky-test"]' ] \
    || fail "flaky of the case one (t_one of lib/tests/x.test.sh) from three sources filed the labels $(labels 1) (exit $RC): $(cat "$T/$CASE/run.out")"
}
# A push's flaky issue (flakypush()): the area of its first file.
t_areaflakypush() {
  amap; mainfile; fx_in 'flakypush 0123456789abcdef "lib/tests/x.test.sh failed" lib/tests/x.test.sh'
  [ "$(labels 1)" = '["bug","P2","area:tests","flaky-test"]' ] \
    || fail "flakypush of lib/tests/x.test.sh filed the labels $(labels 1) (exit $RC): $(cat "$T/$CASE/run.out")"
}
# A main-red fix card stands in for an issue with the area of its first case's file.
t_areamainred() {
  amap
  fx_in 'jq -cn '\''{reds: [{sha: "abc", card: "cred", cases: [{case: "lib/tests/x.test.sh: t_one", files: ["lib/tests/x.test.sh"], by: "c1", last: ""}]}]}'\'' > "$MAINRED" && redissue cred | jq -c "[.labels[].name]"'
  grep -qxF '["bug","P0","area:tests"]' "$T/$CASE/run.out" || fail "redissue of a case of lib/tests/x.test.sh gave the labels: $(cat "$T/$CASE/run.out")"
}
# The full test suite's fix card of a case (fullfix(), lib/fulltest.sh): the area of the case's file; a case
# `<file>: <case>` that no file defines, <file>. Bug (review of #1693): a runner's case (`lib/run.test.sh: one`, as
# `conveyor/conveyor.test.sh: slotcaseterm`) took the runner's area, not that of lib/tests/x.test.sh, which defines it.
t_areafullfix() {
  amap; mainfile; fx_in 'fullfix "lib/run.test.sh: one" "It fails." && fullfix "docs/y.test.sh: two" "It fails."'
  [ "$(labels 1)" = '["bug","P1","area:tests"]' ] && [ "$(labels 2)" = '["bug","P1","area:docs"]' ] \
    || fail "fullfix of 'lib/run.test.sh: one' (t_one of lib/tests/x.test.sh) and of 'docs/y.test.sh: two' filed the labels $(labels 1) and $(labels 2): $(cat "$T/$CASE/run.out")"
}
# A release fix (`card --release`, cardnew()): the area of the file its body names.
t_areacardrelease() {
  amap; cardbody; fx_in 'cardnew --release 1.2.0 "Fix the page" "$(cat "$STUB/body")"'
  [ "$RC" = 0 ] && labels 1 | jq -e 'index("area:docs")' > /dev/null || fail "cardnew --release 1.2.0 of a body naming \`docs/a.md\` filed the labels $(labels 1) (exit $RC): $(cat "$T/$CASE/run.out")"
}
# A batch card of the entries with no area (`heals batch -`): the area of its first finding's file, else other.
t_areabatch() {
  amap
  jq -cn '{id: "h00000000a1", time: "2026-11-20T00:00:00Z", card: "c5", issue: 5, repo: "r", area: null, finding: "[P2] a slow poll", why: "it heals", effect: "self-heals", from: "review"}' >> "$ST/selfheals.jsonl"
  out=$(loop heals batch - 2>&1) || fail "heals batch - failed: $out"
  labels 1 | jq -e 'index("area:plugin")' > /dev/null || fail "heals batch - of an entry naming no file filed the labels $(labels 1), not the map's other area:plugin"
}
# A split part of a parent with no area label: the area of the first file it builds again.
t_areasplit() {
  amap "[$(issue 7 2026-01-01 bug)]"
  issue 7 2026-01-01 bug > "$STUB/parent.json" && echo '[{"title": "s1", "doneWhen": ["a"], "files": ["docs/a.md"], "dependsOn": []}]' > "$STUB/slices.json"
  fx_in 'splitfile c1-7 "$(cat "$STUB/parent.json")" "$(cat "$STUB/slices.json")" 0'
  [ "$RC" = 0 ] && labels 1 | jq -e 'index("area:docs")' > /dev/null || fail "splitfile of a slice of docs/a.md under a parent with no area filed the labels $(labels 1) (exit $RC): $(cat "$T/$CASE/run.out")"
}
# Bug (review of #1693): a split part whose Done-when names its file plain (lib/a.sh, no backticks, no line) got the
# map's other area, as only file:line and backticked paths were read. Through splitcards(), a part with no GitHub issue.
t_areasplitplain() {
  amap "[$(issue 7 2026-01-01 bug)]"
  issue 7 2026-01-01 bug > "$STUB/parent.json" && echo '[{"title": "s1", "doneWhen": ["lib/a.sh says why."], "covers": [1], "dependsOn": []}]' > "$STUB/slices.json"
  fx_in 'splitcards c1-7 "$(cat "$STUB/parent.json")" "$(cat "$STUB/slices.json")" 0'
  [ "$RC" = 0 ] && jq -e '.cards[0].labels | index("area:engine")' "$ST/testactions/cards.json" > /dev/null \
    || fail "splitcards of a slice whose Done-when is 'lib/a.sh says why.' made a card with the labels $(jq -c '.cards[0].labels' "$ST/testactions/cards.json" 2>&1) (exit $RC): $(cat "$T/$CASE/run.out")"
}

# The one pass (#1693, item 3): each entry of both lists with no area gets its finding's file's area, and one with an
# area or no file is left as it is; each open issue with no area label gets one, and one with a label is left.
t_areapass() {
  setup '[]'
  jq -cn '[{number: 7, body: "[P2] lib/tests/x.test.sh:4 slow", labels: []}, {number: 8, body: "lib/a.sh:1", labels: [{name: "area:board"}]}, {number: 9, body: "no file", labels: [{name: "bug"}]},
    {number: 10, body: "It ran 00:05 to 07:35 UTC in `lib/a.sh`.", labels: []}]
    | map(. + {title: "t", milestone: null, createdAt: "2026-01-01"})' > "$STUB/issues.json"
  tune --argjson m "$AMAP" '.labels.areaPaths = $m'
  for x in 'e1|null|[P2] lib/a.sh:1 a' 'e2|"area:board"|[P2] lib/a.sh:2 b' 'e3|null|[P2] no file'; do
    IFS='|' read -r c a f <<<"$x"
    jq -cn --arg c "$c" --argjson a "$a" --arg f "$f" '{id: "h\($c)", time: "2026-11-20T00:00:00Z", card: $c, issue: 5, area: $a, finding: $f, effect: "self-heals"}' >> "$ST/selfheals.jsonl"
  done
  jq -cn '{id: "dd1", card: "d1", issue: 5, area: null, finding: "[P3] docs/x.md:1 omits it", effect: "docs drift"}' > "$ST/docsdrift.jsonl"
  fx_in 'gh_write() { printf "%s\n" "$*" >> "$STUB/writes"; }; healsareas'
  [ "$RC" = 0 ] || fail "healsareas failed (exit $RC): $(cat "$T/$CASE/run.out")"
  [ "$(jq -c '[.card, .area]' "$ST/selfheals.jsonl" | paste -sd' ' -)" = '["e1","area:engine"] ["e2","area:board"] ["e3",null]' ] \
    && [ "$(jq -c .area "$ST/docsdrift.jsonl")" = '"area:docs"' ] \
    || fail "healsareas left the lists: $(cat "$ST/selfheals.jsonl" "$ST/docsdrift.jsonl")"
  [ "$(grep '^issue edit' "$STUB/writes" | sort | paste -sd'|' -)" = 'issue edit 10 --add-label area:engine|issue edit 7 --add-label area:tests|issue edit 9 --add-label area:plugin' ] \
    && grep -qx 'label create -- area:docs' "$STUB/writes" || fail "healsareas wrote to GitHub: $(cat "$STUB/writes" 2>&1)"
}
# Bug (review of #1693): a map's label GitHub would not make was let pass, and each issue edit that names it failed or
# was missed. Now the pass stops before it labels any issue.
t_areapasslabel() {
  amap '[{"number": 7, "body": "lib/a.sh:1", "labels": [], "title": "t", "milestone": null, "createdAt": "2026-01-01"}]'
  fx_in 'gh_write() { printf "%s\n" "$*" >> "$STUB/writes"; [ "$*" != "label create -- area:docs" ]; }; healsareas'
  [ "$RC" = 1 ] && ! grep -q '^issue edit' "$STUB/writes" && grep -q 'the label area:docs could not be made' "$T/$CASE/run.out" \
    || fail "healsareas whose label create -- area:docs failed exited $RC, wrote $(paste -sd'|' "$STUB/writes" 2>&1) and said: $(cat "$T/$CASE/run.out")"
}
