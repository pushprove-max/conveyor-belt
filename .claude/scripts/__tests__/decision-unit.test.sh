#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Self-test for the ledger's optional `unit` field.
# Run: bash .claude/scripts/run-shell-tests.sh .claude/scripts/__tests__/decision-unit.test.sh
#
# Why each case matters: every checkout reads the shared ledger through its own decision.sh, and one row an older
# copy does not know fails the whole read ("malformed ledger"), which stops the Foreman's picker rows and the
# Builder's question gate. So the reader that accepts `unit` must ship before any writer adds one (ring N-1). A
# junk unit must still fail the read: the field names a worktree, and a path or a number there is corruption.
set -uo pipefail
ROOT=$(git rev-parse --show-toplevel)
DECIDE=$ROOT/.claude/scripts/decision.sh
TOP=$(mktemp -d "${TMPDIR:-/tmp}/decision-unit-test.XXXXXX")
trap 'rm -rf "$TOP"' EXIT
PASS=0 FAIL=0
check() { # name expected actual
  if [ "$2" = "$3" ]; then PASS=$((PASS + 1)); echo "ok   $1"
  else FAIL=$((FAIL + 1)); echo "FAIL $1 (expected [$2], got [$3])"; fi
}
row() { # id unit-json-or-empty
  local u=${2:+,\"unit\":$2}
  echo "{\"id\":\"$1\",\"question\":\"Q $1?\",\"proposedDefault\":\"yes\",\"source\":\"t\",\"askedAt\":\"2026-11-01T10:00:00Z\",\"answeredAt\":null,\"answer\":null$u}"
}
decide() { CONVEYOR_MAIN=$BOX bash "$DECIDE" "$@"; }
last() { jq -sr --arg id "$1" '[.[] | select(.id == $id)] | last | .unit // "none"' "$L"; }
# The parts below run side by side, so the file takes its slowest part's time, not their sum. Each has a main
# checkout of its own ($BOX), so its own ledger ($L). Each part's checks are printed and counted in the parts' order
# once all have ended.
PARTS=()
part() { BOX=$TOP/$1; L=$BOX/.claude/metrics/decisions.jsonl; mkdir -p "$BOX/.claude/metrics"; } # <name>
started() { PARTS+=("$1:$!"); } # <name>, after the part's ( ... ) > "$TOP/out.<name>" 2>&1 &

( part read
{ row d-plain; row d-unit '"units-redesign-42"'; } > "$L"
out=$(decide list 2>"$BOX/err"); rc=$?
check "the ledger accepts a row carrying a unit and refuses a junk one: a unit row reads" "0 1" \
  "$rc $(grep -c 'd-unit' <<<"$out")"

for junk in '"../etc"' '5' '""' '"-lead"'; do
  { row d-plain; row d-junk "$junk"; } > "$L"
  decide list >/dev/null 2>"$BOX/err"; rc=$?
  check "the ledger accepts a row carrying a unit and refuses a junk one: unit $junk fails the read" "1 1" \
    "$rc $(grep -c 'malformed ledger' "$BOX/err")"
done
) > "$TOP/out.read" 2>&1 & started read

# The writer: the unit a decision blocks is recorded on the row, so the units mod never guesses it
# from the id; every later copy of the row keeps it.
( part writer
: > "$L"
decide add a1 'Ship the band redesign now?' yes main --unit units-redesign-42 >/dev/null 2>&1
u1=$(last a1)
decide answer a1 no >/dev/null 2>&1; u2=$(last a1)
decide reopen a1 >/dev/null 2>&1; u3=$(last a1)
decide add a2 'Rename the dashboard column?' yes main >/dev/null 2>&1
check "add --unit records the unit, and answer and reopen keep it" \
  "units-redesign-42 units-redesign-42 units-redesign-42 none" "$u1 $u2 $u3 $(last a2)"
) > "$TOP/out.writer" 2>&1 & started writer

# Bug caught: a path, a space or an empty value written as the unit corrupts the shared ledger for every reader.
( part badunit
: > "$L"
for bad in 'a b' '' '../x' no-value; do
  if [ "$bad" = no-value ]; then decide add b1 'Merge it?' yes main --unit >/dev/null 2>"$BOX/err"; rc=$?
  else decide add b1 'Merge it?' yes main --unit "$bad" >/dev/null 2>"$BOX/err"; rc=$?; fi
  check "add refuses a unit that is not a unit name: [$bad]" "1 1 0" "$rc $(grep -c usage "$BOX/err") $(wc -l < "$L" | tr -d ' ')"
done
) > "$TOP/out.badunit" 2>&1 & started badunit

# Bug caught: --reask accepted only as the last flag, so the plan re-ask `--reask '<facts>' --unit <unit>` was refused.
( part order
for order in reask-first unit-first; do
  : > "$L"
  if [ $order = reask-first ]; then decide add plan-u 'Q?' d main --reask 'judge P1' --unit u >/dev/null 2>&1; rc=$?
  else decide add plan-u 'Q?' d main --unit u --reask 'judge P1' >/dev/null 2>&1; rc=$?; fi
  check "add takes --reask and --unit in either order: $order" "0 1 u true" \
    "$rc $(wc -l < "$L" | tr -d ' ') $(last plan-u) $(jq -sr 'last | .source | endswith("re-ask: judge P1")' "$L")"
done
) > "$TOP/out.order" 2>&1 & started order

# An answer is recorded and nothing else. Units, Builder panes and the answer follower are gone, so there is
# no one to deliver to. The old seam (CONVEYOR_ANSWER_WORKER) still points at a recorder here, so delivery coming
# back through it would show up.
# recorders: the part's answer-worker and send-to-pane recorders (AWLOG, STLOG); every case that uses them runs
# against these, never a real pane; an answer sends main nothing.
recorders() {
  AWLOG=$BOX/aw.log
  printf '#!/usr/bin/env bash\nprintf "%%s|%%s\\n" "$1" "$2" >> "%s"\n' "$AWLOG" > "$BOX/aw.sh"
  STLOG=$BOX/stp.log
  printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$*" >> "%s"\nexit "${STP_RC:-0}"\n' "$STLOG" > "$BOX/stp.sh"
  export CONVEYOR_SEND_TO_PANE=$BOX/stp.sh
}
adecide() { CONVEYOR_ANSWER_WORKER=$BOX/aw.sh CONVEYOR_MAIN=$BOX bash "$DECIDE" "$@"; }

( part records; recorders
# Bug caught: an answer to a row with a unit or a term_ handle ran the deleted answer-worker.sh and printed
# "not delivered: ... exited 127".
: > "$L"; : > "$AWLOG"
adecide add aw-1 'Q one?' yes 'worker term_ab12-cd34 asked' --unit units-redesign-42 >/dev/null 2>&1
adecide answer aw-1 go >"$BOX/out1" 2>"$BOX/err1"; rc=$?
check "answer_records_only: a row with a unit and a term_ handle: exit 0, the answer recorded, nothing on stderr, no delivery" \
  "0 go 0 0 0" \
  "$rc $(jq -sr '[.[] | select(.id == "aw-1")] | last | .answer' "$L") $(wc -c < "$BOX/err1" | tr -d ' ') $(grep -ciE 'deliver|pending|kept' "$BOX/out1") $(wc -c < "$AWLOG" | tr -d ' ')"
# Bug caught: --correct exited before the delivery block, so a correction was never delivered either; now
# neither is, and it says nothing about delivery.
adecide answer aw-1 stop --correct >"$BOX/out2" 2>"$BOX/err2"; rc=$?
check "answer_correct_records_only: exit 0, the corrected answer recorded with the old one in history, nothing on stderr, no delivery" \
  "0 stop go 0 0 0" \
  "$rc $(jq -sr '[.[] | select(.id == "aw-1")] | last | "\(.answer) \(.history[0].answer)"' "$L") $(wc -c < "$BOX/err2" | tr -d ' ') $(grep -ciE 'deliver|pending|kept' "$BOX/out2") $(wc -c < "$AWLOG" | tr -d ' ')"

# Bug caught: an answer still woke main's pane with a decision_gate.
: > "$L"; : > "$STLOG"
adecide add wk-1 'Q wake?' yes main >/dev/null 2>&1
adecide answer wk-1 'go ahead' >/dev/null 2>"$BOX/err-wk"; rc=$?
check "answer_sends_main_nothing: exit 0, the answer recorded, no send to main and no wake line on stderr" "0 1 0 0" \
  "$rc $(jq -sr '[.[] | select(.id == "wk-1" and .answer == "go ahead")] | length' "$L") $(grep -c . "$STLOG") $(grep -c 'main wake' "$BOX/err-wk")"
) > "$TOP/out.records" 2>&1 & started records

# A live unit is a worktree on sample-owner/<unit> of main's checkout.
( part live; recorders
git -C "$BOX" init -q -b main && git -C "$BOX" -c user.name=t -c user.email=t@t commit -q --allow-empty -m base
for u in live-unit live; do git -C "$BOX" worktree add -q -b "sample-owner/$u" "$BOX/wt-$u"; done
: > "$L"
# Each ask's unit is read from its own id alone, so the six are added side by side (the ledger's lock takes them in turn).
adecide add plan-live-unit 'Plan q?' yes main >/dev/null 2>"$BOX/note1" &
adecide add live-unit-r1-question 'R q?' yes main >/dev/null 2>/dev/null &
adecide add review-stop-live-x 'Stop q?' yes main >/dev/null 2>/dev/null &
adecide add live-unitless 'Word q?' yes main >/dev/null 2>/dev/null &
adecide add unrelated-ask 'Other q?' yes main >/dev/null 2>/dev/null &
adecide add plan-live-unit-2 'Explicit q?' yes main --unit explicit >/dev/null 2>/dev/null &
wait
# Bug caught: an ask that names its unit only in the id carried no unit, so the answer had nowhere to go.
check "id_named_ask_records_unit: the longest live unit an id names is recorded, with a stderr note; a word that only continues a unit name falls back to the shorter unit; an id naming none records none; --unit wins" \
  "live-unit live-unit live live none explicit 1" \
  "$(last plan-live-unit) $(last live-unit-r1-question) $(last review-stop-live-x) $(last live-unitless) $(last unrelated-ask) $(last plan-live-unit-2) $(grep -c '^decision.sh: recorded --unit live-unit from the id$' "$BOX/note1")"
) > "$TOP/out.live" 2>&1 & started live

# Each part's checks, in the parts' order; a part that ended before its last line fails.
for p in "${PARTS[@]}"; do
  wait "${p#*:}"; rc=$?
  cat "$TOP/out.${p%%:*}"
  PASS=$((PASS + $(grep -c '^ok ' "$TOP/out.${p%%:*}"))) FAIL=$((FAIL + $(grep -c '^FAIL ' "$TOP/out.${p%%:*}")))
  [ "$rc" -eq 0 ] || check "the part ${p%%:*} ran to its end" 0 "$rc"
done
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
