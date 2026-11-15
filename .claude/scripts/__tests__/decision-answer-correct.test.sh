#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Self-test for decision.sh answer --correct.
# Run: bash .claude/scripts/run-shell-tests.sh .claude/scripts/__tests__/decision-answer-correct.test.sh
#
# Why each case matters: a mis-recorded answer is what main acts on, so --correct must replace it in one
# step, and the old answer must survive with who changed it and when, or the record of what the owner first said
# is lost. A plain answer to an answered decision must still refuse: that refusal is what stops a second
# picker or hook from silently overwriting the owner's answer. --correct on an open decision is no correction.
set -uo pipefail
ROOT=$(git rev-parse --show-toplevel)
DECIDE=$ROOT/.claude/scripts/decision.sh
BOX=$(mktemp -d "${TMPDIR:-/tmp}/decision-correct-test.XXXXXX")
trap 'rm -rf "$BOX"' EXIT
PASS=0 FAIL=0
check() { # name expected actual
  if [ "$2" = "$3" ]; then PASS=$((PASS + 1)); echo "ok   $1"
  else FAIL=$((FAIL + 1)); echo "FAIL $1 (expected [$2], got [$3])"; fi
}
mkdir -p "$BOX/.claude/metrics"
L=$BOX/.claude/metrics/decisions.jsonl
{ echo '{"id":"d-done","question":"Ship it?","proposedDefault":"yes","source":"t","askedAt":"2026-10-15T10:00:00Z","answeredAt":"2026-10-15T10:05:00Z","answer":"no"}'
  echo '{"id":"d-open","question":"Merge it?","proposedDefault":"yes","source":"t","askedAt":"2026-10-15T10:00:00Z","answeredAt":null,"answer":null}'; } > "$L"
decide() { CONVEYOR_MAIN=$BOX USER=term_main bash "$DECIDE" "$@"; }
latest() { jq -cs --arg id "$1" 'map(select(.id == $id)) | last' "$L"; }

decide answer d-done yes >/dev/null 2>"$BOX/err"
check "a plain answer to an answered decision still refuses" "1 1" "$? $(grep -c 'already answered' "$BOX/err")"
check "and changes nothing" '"no"' "$(latest d-done | jq -c .answer)"

decide answer d-done yes --correct >/dev/null 2>"$BOX/err"
check "--correct replaces the answer" "0 \"yes\"" "$? $(latest d-done | jq -c .answer)"
check "the old answer stays in history with who and when" '["no","term_main",true]' \
  "$(latest d-done | jq -c '[.history[0].answer, .history[0].who, (.history[0].at | test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T"))]')"
check "the decision keeps when the owner answered it" '"2026-10-15T10:05:00Z"' "$(latest d-done | jq -c .answeredAt)"
decide answer d-done maybe --correct >/dev/null 2>&1
check "a second correction keeps both earlier answers, oldest first" '["no","yes"]' "$(latest d-done | jq -c '[.history[].answer]')"

decide answer d-open yes --correct >/dev/null 2>"$BOX/err"
check "--correct on an open decision refuses: there is nothing to correct" "1 1 null" \
  "$? $(grep -c 'not answered yet' "$BOX/err") $(latest d-open | jq -c .answer)"

# The plan author reads the owner's earlier answers before asking again. Bug caught: a question they already answered was
# written into a plan because nothing showed the author the log at that point.
RL=$BOX/rulings.jsonl
{ echo '{"id":"r-old","utc":"2026-10-01T10:00:00Z","et":"2026-10-01 06:00 ET","source":"ask","question":"Keep the GRIP limit?","answer":"yes"}'
  echo '{"id":"r-void","utc":"2026-10-02T10:00:00Z","et":"e","source":"ask","question":"grip again?","answer":"no","void":true}'
  echo '{"id":"r-typed","utc":"2026-10-04T10:00:00Z","et":"e","source":"prompt","answer":"grip it"}'
  echo '{"id":"r-other","utc":"2026-10-05T10:00:00Z","et":"e","source":"ask","question":"Ship it?","answer":"no"}'
  echo 'half a row{'
  echo '{"id":"r-new","utc":"2026-10-06T10:00:00Z","et":"2026-10-06 06:00 ET","source":"ask","question":"Which limit?","answer":"the grip one"}'
  jq -cn '{id:"r-lines",utc:"2026-10-07T10:00:00Z",et:"e",source:"ask",question:"Odd (answer)?",answer:"first\nsecond\nthird"}'; } > "$RL"
rulings() { CONVEYOR_RULING_LOG=$RL decide rulings "$@"; }
rulings >/dev/null 2>&1; rc=$?
CONVEYOR_RULING_LOG=$BOX/none decide rulings grip >/dev/null 2>&1; rc="$rc $?"
check "rulings_digest_by_term: real picks only, by id, newest first, any case, a term as plain text; no term or no log is exit 1, never an empty digest" \
  'r-new 2026-10-06 06:00 ET: Which limit? -> the grip one|r-old 2026-10-01 06:00 ET: Keep the GRIP limit? -> yes|nomatch=0 |1 1' \
  "$(rulings GrIp | paste -sd'|' -)|nomatch=$(rulings '(no match'; echo "$? ")|$rc"
check "rulings_digest_answer_newlines: an answer with newlines stays one line, read as spaces" \
  "r-lines e: Odd (answer)? -> first second third" "$(rulings odd)"

# growth_answer_without_id_warns: catches a growth answer typed without its ruling id recording silently, so the
# Builder's checker later read it as no grant and nobody knew why. The answer is still recorded: the warning never refuses.
{ echo '{"id":"g-open","question":"Unit u: may it grow foo +2?","proposedDefault":"yes","source":"t","askedAt":"2026-10-15T10:00:00Z","answeredAt":null,"answer":null}'
  echo '{"id":"g-open2","question":"Unit u: may it grow foo +2?","proposedDefault":"yes","source":"t","askedAt":"2026-10-15T10:00:00Z","answeredAt":null,"answer":null}'
  echo '{"id":"o-open","question":"Merge it now?","proposedDefault":"yes","source":"t","askedAt":"2026-10-15T10:00:00Z","answeredAt":null,"answer":null}'; } >> "$L"
decide answer g-open "Yes" >/dev/null 2>"$BOX/err"
check "growth_answer_without_id_warns: a growth answer with no id warns and is still recorded" "0 1 \"Yes\"" \
  "$? $(grep -c 'warning: g-open asks to grow a test count' "$BOX/err") $(latest g-open | jq -c .answer)"
# A made-up ruling id, put together at run time: written out, its shape is a hit of conveyor/privacy/check.sh.
RID=$(printf 'r-%08d-%06d-p-000001' 0 0)
decide answer g-open2 "Yes ($RID)" >/dev/null 2>"$BOX/err"
check "growth_answer_with_id_is_silent: an answer holding the ruling id warns of nothing" "0 0" "$? $(grep -c warning "$BOX/err")"
decide answer o-open "Yes" >/dev/null 2>"$BOX/err"
check "other_answer_is_silent: an answer to a question that grows nothing warns of nothing" "0 0" "$? $(grep -c warning "$BOX/err")"

# --- digest: the owner's day, made by script from the ledger and the ruling log ---
RLD=$BOX/rl-digest.jsonl
gdecide() { CONVEYOR_RULING_LOG=$RLD decide "$@"; }
r() { jq -cn --arg id "$1" --arg q "$2" --arg at "$3" --arg ans "$4" '{id: $id, question: $q, proposedDefault: "yes", source: "t", askedAt: $at,
  answeredAt: (if $ans == "" then null else $at end), answer: (if $ans == "" then null else $ans end)}'; }
{ r o1 'Open one?' 2026-11-07T14:00:00Z ''; r o0 'Open zero?' 2026-11-06T10:00:00Z ''
  r e1 'Edge one?' 2026-11-07T04:59:59Z yes; r e2 'Edge two?' 2026-11-07T05:00:00Z yes; } > "$L"
{ echo '{"id":"r-p1","source":"ask","utc":"2026-11-07T15:30:00Z","question":"Pick a\ncolor?","answer":"Blue"}'
  echo '{"id":"r-p2","source":"ask","utc":"2026-11-07T15:31:00Z","question":"Open one?","answer":"yes"}'
  echo '{"id":"r-p3","source":"ask","utc":"2026-11-07T15:32:00Z","question":"Void?","answer":"x","void":true}'
  echo '{"id":"r-p4","source":"prompt","utc":"2026-11-07T15:33:00Z","question":null,"answer":"typed"}'
  echo 'not json'; } > "$RLD"
# Bug caught: open asks buried under the day's answers, or an answer filed under the UTC day instead of the owner's ET day.
check "digest_open_first_then_answered: open asks oldest first, then the ET day's answers" \
  "# The owner's decisions, 2026-11-07 (ET)|## Open (2)|- o0, asked 2026-11-06 05:00 ET: Open zero? (default: yes)|- o1, asked 2026-11-07 09:00 ET: Open one? (default: yes)|## Answered 2026-11-07 (1)|- 00:00 e2: Edge two? -> yes" \
  "$(gdecide digest 2026-11-07 2>&1 | head -6 | paste -sd'|' -)"
check "digest_open_first_then_answered: 04:59:59Z is the day before in ET" "## Answered 2026-11-06 (1)|- 23:59 e1: Edge one? -> yes" \
  "$(gdecide digest 2026-11-06 2>&1 | sed -n '5,6p' | paste -sd'|' -)"
# Bug caught: a picker answer with no ledger row (asked outside decision.sh) missing from the owner's day, or a junk,
# void or typed-prompt line listed as one.
check "digest_includes_picker_answers_without_row: only the picker answer no row holds, newline-free" \
  "## Other picker answers 2026-11-07 (1)|- 10:30 r-p1: Pick a color? -> Blue" "$(gdecide digest 2026-11-07 2>&1 | sed -n '7,$p' | paste -sd'|' -)"
# Bug caught: the Board wrote each project's page with the whole ruling log's picker answers, so a picker answer named
# no project yet showed under every project's heading, and one another project's ledger held showed as "other".
L2=$BOX/other-ledger.jsonl; r q2 'Pick a color?' 2026-11-07T14:00:00Z Blue > "$L2"
check "digest_no_picks_is_the_ledger_alone: Open and Answered only" "0 1" \
  "$(gdecide digest 2026-11-07 --no-picks 2>&1 | grep -c picker) $(gdecide digest 2026-11-07 --no-picks 2>&1 | grep -c '^## Open (2)$')"
check "digest_picks_of_every_ledger: only the picker section, without the answers any named ledger holds" \
  "## Other picker answers 2026-11-07 (1)|- 10:30 r-p1: Pick a color? -> Blue|## Other picker answers 2026-11-07 (0)|- none" \
  "$(gdecide digest 2026-11-07 --picks "$L" 2>&1 | paste -sd'|' -)|$(gdecide digest 2026-11-07 --picks "$L" "$L2" 2>&1 | paste -sd'|' -)"
gdecide digest 2026-11-07 --picks >/dev/null 2>&1; got="$? "; gdecide digest --no-picks x >/dev/null 2>&1; got+="$? "
gdecide digest --picks "$BOX/nowhere.jsonl" >/dev/null 2>&1; got+=$?
check "digest_picks_needs_a_readable_ledger: no ledger is a usage error, an unreadable one a failure" "2 2 1" "$got"
# Bug caught: a corrected answer shown as if the owner had said it first, hiding what they said before.
: > "$L"; : > "$RLD"
gdecide add c1 'Corrected thing?' yes main >/dev/null 2>&1; gdecide answer c1 a >/dev/null 2>&1
gdecide answer c1 b --correct >/dev/null 2>&1; gdecide answer c1 c --correct >/dev/null 2>&1
check "digest_marks_corrected_answer: the latest answer with every earlier one, oldest first" "1" \
  "$(gdecide digest 2>&1 | grep -c '^- [0-9][0-9]:[0-9][0-9] c1: Corrected thing? -> c (corrected; earlier: a; b)$')"
# Bug caught: a bad date read as some other day, or an empty day printing headings with nothing under them.
: > "$L"; got=""
for d in 2026-13-01 yesterday '2026-11-07 2026-11-08'; do read -ra A <<<"$d"; gdecide digest "${A[@]}" >/dev/null 2>&1; got+="$? "; done
check "digest_empty_day_and_bad_date: bad dates exit 2; an empty day reads - none under each heading" "2 2 2 0 3" \
  "$got$(gdecide digest 2026-11-07 >"$BOX/dg" 2>&1; echo $?) $(grep -cx -- '- none' "$BOX/dg")"
# Bug caught (pass 1): the ledger and the picker rows passed to jq as arguments, so at real sizes (1.07 MB and 1.41 MB
# on 11-07, past the host's argument limit) jq never started and /digest.txt went stale. The size is in long rows, not
# many: 300 rows of 6000 bytes are each file's 1.8 MB, past both the Mac's 1 MiB and Linux's 128 KiB argument, in a
# tenth of the rows to read. The bytes are in each row's default and answer, not its question: the digest matches
# every question word by word (a regex over each), which cost about 2 s at this size and is not what this case tests.
jq -cn 'range(300) as $i | {id: "big\($i)", question: "Q\($i)?", proposedDefault: ("x" * 6000), source: "t",
  askedAt: "2026-11-07T14:00:00Z", answeredAt: null, answer: null}' > "$L"
jq -cn 'range(300) as $i | {id: "r-b\($i)", source: "ask", utc: "2026-11-07T15:00:00Z", question: "P\($i)?", answer: ("y" * 6000)}' > "$RLD"
check "digest_reads_real_sized_ledger_and_log: every open ask and picker answer of a 1.8 MB ledger and log" "0 300 300 1" \
  "$(gdecide digest 2026-11-07 >"$BOX/dg" 2>&1; echo $?) $(grep -c '^- big' "$BOX/dg") $(grep -c '^- 10:00 r-b' "$BOX/dg") $(($(wc -c < "$L") > 1800000 && $(wc -c < "$RLD") > 1800000))"

echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
