#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# The decisions ledger (decision.sh) is what the owner answers from, on the dashboard and in chat. It is append-only and
# folds to the latest snapshot; a reopened decision is asked afresh; and a question still open, or answered in the
# last 24 h, is not asked again under new wording.
set -euo pipefail
SOURCE=$(git rev-parse --show-toplevel)
DECIDE=$SOURCE/.claude/scripts/decision.sh
T=$(cd "$(mktemp -d /tmp/decision-ledger-test.XXXXXX)" && pwd -P)
trap 'rm -rf "$T"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }
mkdir -p "$T/home"
export HOME=$T/home CONVEYOR_RULING_LOG=$T/no-rulings.jsonl CONVEYOR_WORKSPACES=$T/ws CONVEYOR_SCRATCH=$T/scratch
# The parts below run side by side (part ( ... ) &), so the file takes its slowest part's time, not their sum. Each
# has a folder and a main checkout of its own ($T and $MAIN in it), so its own ledger: no part reads another's rows.
PARTS=()
started() { PARTS+=("$1:$!"); }
ledger() { # <part>
  T=$T/$1; MAIN=$T/main; L=$MAIN/.claude/metrics/decisions.jsonl
  mkdir -p "$MAIN/.claude/metrics"; git -C "$MAIN" init -q -b main
}
dec() { env CONVEYOR_MAIN="$MAIN" bash "$DECIDE" "$@"; }

( ledger fold
# --- the ledger is append-only and folds to the latest snapshot ---
Qtxt='Ship "it" <b>now</b>?'
dec add d1 "$Qtxt" 'wait a day' 'main-a' >/dev/null || fail "decision add failed"
dec add d2 'second?' 'no' 'issue #9' >/dev/null || fail "second add failed"
[ "$(wc -l < "$L")" -eq 2 ] || fail "each add appends exactly one line"
jq -e 'select(.id == "d1") | keys == ["answer","answeredAt","askedAt","id","proposedDefault","question","source"] and .answer == null and .answeredAt == null and .question == "Ship \"it\" <b>now</b>?" and (.askedAt | test("Z$"))' "$L" >/dev/null \
  || fail "add writes all seven fields with machine UTC time and the exact text"
asked=$(jq -r 'select(.id == "d2") | .askedAt' "$L")
dec answer d2 'yes' >/dev/null || fail "decision answer failed"
[ "$(wc -l < "$L")" -eq 3 ] || fail "answer appends a snapshot and rewrites nothing"
head -2 "$L" | jq -e -s 'all(.answer == null)' >/dev/null || fail "history before the answer is untouched"
dec list | jq -e --arg a "$asked" 'length == 2 and (.[] | select(.id == "d2") | .answer == "yes" and .askedAt == $a and .question == "second?" and .proposedDefault == "no" and .source == "issue #9" and .answeredAt != null)' >/dev/null \
  || fail "list folds to the latest snapshot and keeps the original metadata"
! dec add d1 'again' 'x' 'y' 2>/dev/null || fail "a duplicate add must fail"
! dec answer d2 'no' 2>/dev/null || fail "a second answer must fail"
! dec answer nope 'x' 2>/dev/null || fail "an unknown id must fail"
! dec add '' 'q' 'd' 's' 2>/dev/null || fail "an empty id must fail"
[ "$(wc -l < "$L")" -eq 3 ] || fail "refused writes append nothing"
# Two racing adds of one id: the lock lets exactly one through.
dec add race 'q' 'd' 's' >/dev/null 2>&1 & r1=$!
dec add race 'q' 'd' 's' >/dev/null 2>&1 & r2=$!
ok=0; wait $r1 && ok=$((ok + 1)); wait $r2 && ok=$((ok + 1))
[ "$ok" -eq 1 ] && [ "$(jq -s '[.[] | select(.id == "race")] | length' "$L")" -eq 1 ] || fail "concurrent duplicate adds must yield one record"
# Reopen: an Orca banner closed e2e-api-grant-2026-10-06 as "answered
# in chat". One appended snapshot puts it back on the card, asked afresh so a
# prompt that arrived before the reopen cannot close it again; history stays.
for m in m1 m2; do
  jq -cn --arg id "$m" '{id: $id, askedAt: "2026-10-01T00:00:00Z", question: "Grant \($id) API access?", proposedDefault: "not yet",
    source: "main", answeredAt: "2026-10-01T00:01:22Z", answer: "answered in chat (ruling-2)"}' >> "$L"
done
cp "$L" "$T/before-reopen"; n=$(wc -l < "$L"); before=$(date -u +%Y-%m-%dT%H:%M:%SZ)
dec reopen m1 >/dev/null || fail "decision reopen failed"
[ "$(wc -l < "$L")" -eq $((n + 1)) ] && head -n "$n" "$L" | cmp -s - "$T/before-reopen" || fail "reopen appends one snapshot and rewrites no history"
tail -1 "$L" | jq -e --arg b "$before" 'keys == ["answer","answeredAt","askedAt","id","proposedDefault","question","source"]
    and .id == "m1" and .question == "Grant m1 API access?" and .proposedDefault == "not yet" and .source == "main"
    and .answer == null and .answeredAt == null and .askedAt >= $b' >/dev/null \
  || fail "reopen keeps id, question, default and source, clears the answer and refreshes askedAt: $(tail -1 "$L")"
dec list | jq -e '.[] | select(.id == "m1") | .answeredAt == null and .answer == null' >/dev/null || fail "list folds the reopened row as open"
n=$(wc -l < "$L")
! dec reopen m1 2>/dev/null || fail "reopening an open decision must fail"
! dec reopen nope 2>/dev/null || fail "reopening an unknown id must fail"
! dec reopen 2>/dev/null || fail "reopen with no id must fail"
! dec reopen m2 extra 2>/dev/null || fail "reopen with extra arguments must fail"
! env CONVEYOR_MAIN="$T/no-main" bash "$DECIDE" reopen m2 2>/dev/null || fail "reopen with no ledger must fail"
[ ! -e "$T/no-main/.claude/metrics/decisions.jsonl" ] || fail "reopen must not create a ledger"
[ "$(wc -l < "$L")" -eq "$n" ] || fail "a refused reopen appends nothing"
# Two racing reopens of one answered decision: the lock lets exactly one through.
dec reopen m2 >/dev/null 2>&1 & r1=$!
dec reopen m2 >/dev/null 2>&1 & r2=$!
ok=0; wait $r1 && ok=$((ok + 1)); wait $r2 && ok=$((ok + 1))
[ "$ok" -eq 1 ] && [ "$(wc -l < "$L")" -eq $((n + 1)) ] || fail "concurrent reopens must append one snapshot"
dec answer m1 'grant it' >/dev/null && dec answer m2 'not yet' >/dev/null || fail "a reopened decision must take a later answer"
dec list | jq -e '.[] | select(.id == "m1") | .answer == "grant it"' >/dev/null || fail "the later answer is the folded one"
dec list | jq -e '[.[] | select(.answeredAt == null) | .id] == ["d1","race"]' >/dev/null || fail "an answered reopened decision is no longer open"
) & started fold

# --- a question still open, or answered in the last 24 h, is not asked again ---
# Main re-asked three decisions under new wording, so the owner
# answered each twice. The questions are the ledger's real text (main extracted
# them); only the PROD, STAGING and spacing variants are made up
# here. The repeated "both" question sits exactly on the half-the-words line,
# so a change to the rule that loses it fails here. The repeat names the earlier
# decision and its answer so main uses it; a changed proposal, another
# environment and an unrelated question still go through.
seed() { # id question answeredAt answer ("" = still open)
  jq -cn --arg id "$1" --arg q "$2" --arg at "$3" --arg a "$4" \
    '{id: $id, askedAt: "2026-10-03T07:00:00Z", question: $q, proposedDefault: "none", source: "fixture",
      answeredAt: (if $at == "" then null else $at end), answer: (if $a == "" then null else $a end)}' >> "$L"
}
try() { rc=0; dec add "$@" > "$T/dec.out" 2> "$T/dec.err" || rc=$?; echo "$rc"; }
lines() { wc -l < "$L" | tr -d ' '; }
TOOL1='Tooling-class review: orchestration.md:557 says one review round; routing.json gives tooling zero reviewers. Which wins?'
TOOL2='Tooling changes: the written rule says one outside review round, but the reviewer settings give them none. Which should win going forward?'
DET1="If the background ID detector cannot start on a guest's phone: 1) show the existing camera-cannot-run stop screen, or 2) run detection on the main thread (needs a new knob with a hard-fail option)?"
DET2="If the new background ID detector can't start on a guest's phone, what should happen?"
SHADOW1='Set DEV ai.documentOcr.method to both (AI stays the reader that decides; Textract reads every same image as a shadow), then compare the two on live phone captures of your passport plus a few non-US ones?'
SHADOW2="Set DEV's document reader to \"both\", so Textract reads every ID photo in the background next to the AI reader, which keeps deciding every verdict?"
ORDER="Textract first, then the AI reader only when Textract's read does not pass (MRZ check digits fail or required fields missing). Our pipeline rule says every fallback must be a plan setting with a 'no fallback, hard fail' option. Build it that way?"
seeds() {
  seed tooling-review-conflict "$TOOL1" "" ""
  seed capture-worker-fail "$DET1" "$(date -u -d '-23 hours' +%Y-%m-%dT%H:%M:%SZ)" "existing camera-cannot-run screen"
  seed dev-ocr-both-shadow "$SHADOW1" "" ""
  seed lambda-memory 'Raise the capture Lambda memory to 2 GB?' "$(date -u -d '-25 hours' +%Y-%m-%dT%H:%M:%SZ)" "yes"
}

( ledger repeat; seeds
n=$(lines)
[ "$(try tooling-review-2026-10-03 "$TOOL2" none main)" = 3 ] || fail "a reworded open question must be refused as a duplicate (exit 3)"
grep -qF 'tooling-review-conflict' "$T/dec.err" && grep -qiF 'open' "$T/dec.err" || fail "the refusal must name the open decision it repeats: $(cat "$T/dec.err")"
[ "$(try detector-2026-10-04 "$DET2" none main)" = 3 ] || fail "a question answered 23 h ago must be refused"
grep -qF 'existing camera-cannot-run screen' "$T/dec.err" || fail "the refusal must carry the earlier answer: $(cat "$T/dec.err")"
[ "$(try dev-reader-2026-10-04 "$SHADOW2" none main)" = 3 ] || fail "the repeated DEV both/shadow question must be refused"
[ "$(try shadow-again "  set dev's DOCUMENT reader to both,   so textract reads every ID photo in the background next to the ai reader, which keeps deciding every verdict " none main)" = 3 ] \
  || fail "case, punctuation and spacing must not make a repeat new"
# "thirteenth", "13th" and "13" are one number: the same round asked twice, spelt two ways, is a repeat. Each pair on
# a ledger of its own.
k=0
for p in 'Run a thirteenth round of the release audit?|Should we run round 13 of the release audit?' \
         'Run round 13 of the release audit?|Should we run the 13th round of the release audit?'; do
  k=$((k + 1)); rc=0
  CONVEYOR_LEDGER=$T/rounds-$k.jsonl dec add first "${p%%|*}" none main >/dev/null 2>&1 || fail "the first spelling was not added: $p"
  CONVEYOR_LEDGER=$T/rounds-$k.jsonl dec add retry "${p#*|}" none main >/dev/null 2>&1 || rc=$?
  [ "$rc" = 3 ] || fail "equivalent number spellings returned $rc, expected 3: $p"
done
[ "$(lines)" -eq "$n" ] || fail "a refused repeat appends nothing"
[ "$(try reader-order-2026-10-04 "$ORDER" none main)" = 0 ] || fail "a changed proposal (reader order) is a new decision: $(cat "$T/dec.err")"
[ "$(try prod-reader "${SHADOW2/DEV/PROD}" none main)" = 0 ] \
  || fail "the same question for another environment is a new decision: $(cat "$T/dec.err")"
[ "$(try region 'Which AWS region hosts the new bucket?' none main)" = 0 ] || fail "an unrelated question is added: $(cat "$T/dec.err")"
[ "$(try lambda-memory-2 'Raise the capture Lambda memory to 2 GB?' none main)" = 0 ] || fail "a question answered over 24 h ago may be asked again"
) & started repeat

# The same rows, and the unrelated question the part above adds as region.
( ledger reask; seeds; seed region 'Which AWS region hosts the new bucket?' "" ""
# New facts: main may re-ask with the reason logged; the reason is required.
[ "$(try tooling-reask "$TOOL2" none main --reask '')" = 1 ] || fail "a blank --reask reason must be refused"
# A deliberate re-ask of an existing id puts the decision back in front
# of the owner as a fresh open snapshot, the reason logged; history is never rewritten.
cp "$L" "$T/before-reask"; n=$(lines)
[ "$(try tooling-review-conflict "$TOOL1" none main --reask 'the reviewer count changed')" = 0 ] \
  || fail "--reask on an existing id must append a fresh snapshot: $(cat "$T/dec.err")"
[ "$(lines)" -eq $((n + 1)) ] && head -n "$n" "$L" | cmp -s - "$T/before-reask" || fail "an existing-id re-ask appends one row and rewrites no history"
dec list | jq -e --arg q "$TOOL1" '[.[] | select(.id == "tooling-review-conflict")] | length == 1 and (.[0] | .answeredAt == null
    and .question == $q and .askedAt != "2026-10-03T07:00:00Z" and (.source | contains("re-ask: the reviewer count changed")))' >/dev/null \
  || fail "the re-asked id folds to one open snapshot, asked afresh, with the reason in its source"
n=$(lines)
[ "$(try tooling-reask "$TOOL2" none main --reask 'routing.json now gives tooling one reviewer')" = 0 ] || fail "--reask with a reason must be added: $(cat "$T/dec.err")"
[ "$(lines)" -eq $((n + 1)) ] || fail "a re-ask appends exactly one row"
jq -e -s '[.[] | select(.id == "tooling-reask")][0] | .source | contains("main") and contains("routing.json now gives tooling one reviewer")' "$L" >/dev/null \
  || fail "the re-ask reason is logged in the decision's source"
[ "$(try tooling-third "$TOOL1" none main)" = 3 ] || fail "an ordinary ask after the re-ask is still deduplicated"
dec answer tooling-review-conflict 'written rule wins' >/dev/null && dec answer tooling-reask 'routing.json wins' >/dev/null || fail "answering the fixtures failed"
[ "$(try tooling-fourth "$TOOL2" none main)" = 3 ] && grep -qF 'routing.json wins' "$T/dec.err" \
  || fail "a repeat names the NEWEST matching answer, the re-ask's: $(cat "$T/dec.err")"
[ "$(try staging-reader "${SHADOW2/DEV/STAGING}" none main)" = 0 ] \
  || fail "staging is another environment too: $(cat "$T/dec.err")"
[ "$(try region "$SHADOW2" none main)" = 3 ] || fail "a reused id asking an open question is that question's repeat, not an id collision"
# Two different ids racing one new question: the lock lets exactly one in.
dec add rq1 'Rotate the webhook signing key this week?' d s >/dev/null 2>&1 & r1=$!
dec add rq2 'Rotate the webhook signing key this week?' d s >/dev/null 2>&1 & r2=$!
ok=0; wait $r1 && ok=$((ok + 1)); wait $r2 && ok=$((ok + 1))
[ "$ok" -eq 1 ] && [ "$(jq -s '[.[] | select(.question == "Rotate the webhook signing key this week?")] | length' "$L")" -eq 1 ] \
  || fail "two ids racing one question must yield one record"
) & started reask

( ledger options
# A decision may carry the 2 to 4 answers the owner can click; the row is unchanged without them, they survive
# answer, --correct and reopen.
[ "$(try region 'Which AWS region hosts the new bucket?' none main)" = 0 ] || fail "a row with no options is added: $(cat "$T/dec.err")"
n=$(lines)
[ "$(try opt-ship 'Ship the opt batch to the dock?' Yes main --options '["Yes","No"]')" = 0 ] \
  || fail "add_options_stored_and_listed: $(cat "$T/dec.err")"
dec list | jq -e '.[] | select(.id == "opt-ship") | .options == ["Yes","No"]' >/dev/null \
  || fail "add_options_stored_and_listed: the listed row carries its options"
dec list | jq -e '[.[] | select(.id == "region")] | all(has("options") | not)' >/dev/null \
  || fail "add_options_stored_and_listed: a row added without options gains no options key"
dec answer opt-ship Yes >/dev/null && dec answer opt-ship No --correct >/dev/null && dec reopen opt-ship >/dev/null \
  && dec list | jq -e '.[] | select(.id == "opt-ship") | .options == ["Yes","No"] and .answer == null' >/dev/null \
  || fail "add_options_stored_and_listed: options survive answer, --correct and reopen"
[ "$(try opt-reask 'Ship the opt batch to the dock?' Yes main --options '["Yes","No"]' --reask 'the dock moved')" = 0 ] \
  && dec list | jq -e '.[] | select(.id == "opt-reask") | .options == ["Yes","No"] and (.source | endswith("re-ask: the dock moved"))' >/dev/null \
  || fail "add_options_stored_and_listed: --options goes before --reask: $(cat "$T/dec.err")"
n=$(lines)
for bad in '["Only"]' '["a","b","c","d","e"]' '["Yes",""]' '["Yes",5]' '{"a":1}' 'Yes,No' \
  "[\"Yes\",\"$(head -c 501 /dev/zero | tr '\0' a)\"]" "[\"Yes\",\"two
lines\"]"; do
  [ "$(try opt-bad 'Is the opt bad case refused today?' Yes main --options "$bad")" = 1 ] \
    || fail "add_options_count_refused: [$bad] was not refused"
done
[ "$(lines)" = "$n" ] || fail "add_options_count_refused: a refused --options appended a row"
[ "$(try opt-bad 'Is the opt bad case refused today?' Yes main --options)" = 1 ] \
  || fail "add_options_count_refused: --options with no value"
# An answered decision, which a reopen would put back but for the malformed line below.
seed answered-once 'Empty the old capture bucket?' 2026-10-03T08:00:00Z yes
printf '{"id":"broken"\n' >> "$L"
! dec list >/dev/null 2>&1 || fail "a malformed ledger line must fail list"
! dec add d9 'q' 'd' 's' 2>/dev/null || fail "a malformed ledger must refuse new writes"
n=$(wc -l < "$L")
! dec reopen answered-once 2>/dev/null || fail "a malformed ledger must refuse a reopen"
[ "$(wc -l < "$L")" -eq "$n" ] || fail "a reopen refused on a malformed ledger appends nothing"
) & started options

bad=()
for p in "${PARTS[@]}"; do wait "${p#*:}" || bad+=("${p%%:*}"); done
[ ${#bad[@]} -eq 0 ] || fail "these parts failed (their FAIL lines are above): ${bad[*]}"
echo "PASS: decision-ledger"
