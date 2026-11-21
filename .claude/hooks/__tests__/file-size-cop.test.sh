#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Self-test for file-size-cop.sh.
#
# Files grow by Edit and MultiEdit, one hunk at a time, so those payloads must be measured too, not only a whole-file Write.
#
# It also pins the narrowing: only the caps the rules STATE are enforced --
# 500 for a .ts, 400 for a .tsx. The universal 800-line block for every file
# type came from no rule, and it refused a long markdown reference on a number
# nobody chose while letting a .tsx past its stated 400 with a warning.
#
# It also pins where the hook DECLINES to answer: a replace_all edit applies its
# swap an unknown number of times, so the resulting size is not computable from
# the payload and the hook stays silent rather than reporting a number it made
# up.
set -u

HOOK="$(cd "$(dirname "$0")/.." && pwd)/file-size-cop.sh"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
PASS=0 FAIL=0

. "$(dirname "${BASH_SOURCE[0]}")/lib/said.sh" # a FAIL line names the hook's last input
check() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); echo "ok   $1"; else FAIL=$((FAIL+1)); echo "FAIL $1 (expected $2, got $3)$(said)"; fi }
run()     { bash "$HOOK" >/dev/null 2>&1 <<<"$1"; echo $?; }
run_err() { bash "$HOOK" 2>&1 >/dev/null <<<"$1"; }

lines() { seq 1 "$1" | sed 's/^/const x/;s/$/ = 1;/'; }

BIG="$TMP/big.ts"; lines 490 > "$BIG"          # near the stated 500-line .ts cap
SMALL="$TMP/small.ts"; lines 100 > "$SMALL"
TSX="$TMP/panel.tsx"; lines 390 > "$TSX"       # near the stated 400-line .tsx cap
HUGE="$TMP/huge.ts"; lines 900 > "$HUGE"       # ALREADY past the cap
MD="$TMP/reference.md"; lines 790 > "$MD"      # long, and no rule caps it

write() { jq -cn --arg fp "$1" --arg s "$2" '{tool_name:"Write", tool_input:{file_path:$fp, content:$s}}'; }
edit()  { jq -cn --arg fp "$1" --arg o "$2" --arg n "$3" '{tool_name:"Edit", tool_input:{file_path:$fp, old_string:$o, new_string:$n}}'; }
multi() { jq -cn --arg fp "$1" --argjson e "$2" '{tool_name:"MultiEdit", tool_input:{file_path:$fp, edits:$e}}'; }
edit_all() { jq -cn --arg fp "$1" --arg o "$2" --arg n "$3" '{tool_name:"Edit", tool_input:{file_path:$fp, old_string:$o, new_string:$n, replace_all:true}}'; }

# --- Write: the payload IS the file, exactly as before ------------------------
check "a 550-line .ts Write blocks"              2 "$(run "$(write "$TMP/new.ts" "$(lines 550)")")"
check "a 410-line .tsx Write blocks"             2 "$(run "$(write "$TMP/new.tsx" "$(lines 410)")")"
check "a Write under the cap passes"             0 "$(run "$(write "$TMP/new.ts" "$(lines 100)")")"
# A file exactly at the cap, trailing newline included, is not one over.
check "a 500-line .ts Write with a trailing newline passes" 0 \
  "$(run "$(write "$TMP/new.ts" "$(lines 500)"$'\n')")"
check "a 501-line .ts Write blocks"              2 "$(run "$(write "$TMP/new.ts" "$(lines 501)"$'\n')")"
check "the block names the cap and its rule"     0 \
  "$(run_err "$(write "$TMP/new.ts" "$(lines 550)")" | grep -q 'cap is 500.*backend.md' && echo 0 || echo 1)"
check "a 450-line .ts Write is SILENT"           "" "$(run_err "$(write "$TMP/new.ts" "$(lines 450)")")"
check "a 390-line .tsx Write is SILENT"          "" "$(run_err "$(write "$TMP/new.tsx" "$(lines 390)")")"

# --- the universal 800-line rule is gone --------------------------------------
# No rule states it. A long markdown reference, a generated fixture and a shell
# script were all refused on a number nobody chose.
check "a 900-line markdown Write passes"         0 "$(run "$(write "$TMP/doc.md" "$(lines 900)")")"
check "a 900-line markdown Write is SILENT"      "" "$(run_err "$(write "$TMP/doc.md" "$(lines 900)")")"
check "a 900-line JSON fixture passes"           0 "$(run "$(write "$TMP/fixture.json" "$(lines 900)")")"
check "a 900-line Python file passes"            0 "$(run "$(write "$TMP/tool.py" "$(lines 900)")")"
check "an Edit growing a markdown file past 800 passes" 0 \
  "$(run "$(edit "$MD" "const x1 = 1;" "$(lines 20)")")"

# --- THE DEFECT: an Edit that pushes a file past the cap ----------------------
# An Edit is measured as the file will be after the edit (790 on disk, one line replaced by 20 = 809), not by its payload alone.
ADD20=$(lines 20)
# A feature growing an existing file past its cap goes ahead with a warning;
# the shrink is a follow-up unit, never a refactor folded into the feature.
check "an Edit that grows a .ts past its cap passes" 0 "$(run "$(edit "$BIG" "const x1 = 1;" "$ADD20")")"
check "a MultiEdit that grows a .ts past its cap passes" 0 \
  "$(run "$(multi "$BIG" "$(jq -cn --arg n "$ADD20" '[{old_string:"const x1 = 1;", new_string:"const x1 = 2;"},{old_string:"const x2 = 1;", new_string:$n}]')")")"
check "the warning reports the RESULTING line count and the follow-up" 0 \
  "$(run_err "$(edit "$BIG" "const x1 = 1;" "$ADD20")" | grep -q '509-line.*follow-up unit' && echo 0 || echo 1)"

# --- an edit that does not grow the file, or shrinks it, passes ---------------
check "a same-size Edit passes"                  0 "$(run "$(edit "$BIG" "const x1 = 1;" "const x1 = 2;")")"
check "a same-size Edit is SILENT"               "" "$(run_err "$(edit "$BIG" "const x1 = 1;" "const x1 = 2;")")"
check "an Edit that SHRINKS a big file passes"   0 \
  "$(run "$(edit "$BIG" "$(lines 50)" "const x1 = 1;")")"
check "an Edit on a small file passes"           0 "$(run "$(edit "$SMALL" "const x1 = 1;" "$ADD20")")"
check "an Edit that crosses the .tsx cap passes"  0 "$(run "$(edit "$TSX" "const x1 = 1;" "$ADD20")")"
check "the .tsx warning cites the frontend rule" 0 \
  "$(run_err "$(edit "$TSX" "const x1 = 1;" "$ADD20")" | grep -q 'cap is 400.*frontend.md' && echo 0 || echo 1)"

# An edit to a file ALREADY past a threshold is usually the repair. Warning on
# every one of those -- or blocking them -- turns a long file into a file nobody
# can shorten, so a threshold fires only on the change that CROSSES it.
check "an Edit inside an already-long file is SILENT" "" \
  "$(run_err "$(edit "$BIG" "const x1 = 1;" "const x1 = 2;
const x1b = 3;")")"
check "an Edit inside an already-oversized file passes" 0 \
  "$(run "$(edit "$TMP/huge.ts" "const x1 = 1;" "const x1 = 2;
const x1b = 3;")")"

# --- where it declines to answer, deliberately -------------------------------
# A number the hook cannot compute must not be reported as fact.
check "a replace_all Edit is SILENT rather than guessing" "" \
  "$(run_err "$(edit_all "$BIG" "const x1 = 1;" "$ADD20")")"
check "a replace_all Edit passes"                0 "$(run "$(edit_all "$BIG" "const x1 = 1;" "$ADD20")")"
check "a replace_all edit inside a MultiEdit is SILENT" "" \
  "$(run_err "$(multi "$BIG" "$(jq -cn --arg n "$ADD20" '[{old_string:"const x1 = 1;", new_string:$n, replace_all:true}]')")")"
check "an Edit to a file not on disk passes"     0 "$(run "$(edit "$TMP/absent.ts" "a" "$ADD20")")"

# --- a tripwire never wedges an unrelated call -------------------------------
check "a Bash payload passes"                    0 "$(run "$(jq -cn '{tool_name:"Bash",tool_input:{command:"ls"}}')")"
check "malformed JSON passes rather than wedging" 0 "$(run 'not json')"

# --- one shared definition of the payload's shape ---------------------
# The hook used to keep its own jq over `.tool_input.edits`, beside the one in
# lib/edit-payload.sh. A second definition is how eleven guards went blind to
# MultiEdit for a month, so the shape moved into the helper. The cases below run it: a broken helper blocks the
# hook, and a two-file MultiEdit is measured file by file.
# Without this, the helper going missing turns the cap into a silent no-op.
# The hook and helper are copied into $TMP first: tests run in parallel, and a
# chmod on the real helper blinds every hook test running at the same moment.
mkdir -p "$TMP/hooks/lib"
cp "$HOOK" "$TMP/hooks/"; cp "$(dirname "$HOOK")/lib/edit-payload.sh" "$TMP/hooks/lib/"
REAL_HOOK=$HOOK HOOK="$TMP/hooks/file-size-cop.sh"
chmod 000 "$TMP/hooks/lib/edit-payload.sh" 2>/dev/null
LOADFAIL=$(run "$(write "$SMALL" "$(lines 10)")")
LOADMSG=$(run_err "$(write "$SMALL" "$(lines 10)")")
chmod 644 "$TMP/hooks/lib/edit-payload.sh"
HOOK=$REAL_HOOK
check "an unreadable helper BLOCKS instead of passing" 2 "$LOADFAIL"
check "and it says which file to restore" 0 \
  "$(grep -qF 'git checkout .claude/hooks/lib/edit-payload.sh' <<<"$LOADMSG" && echo 0 || echo 1)"
check "the real helper was never touched" 0 "$([ -r "$(dirname "$HOOK")/lib/edit-payload.sh" ] && echo 0 || echo 1)"

# ONE BATCH, TWO FILES, JUDGED SEPARATELY. The old private extractor summed
# every edit against the payload-level path, so a small file's growth was
# charged to whichever file tool_input named.
TWO=$(jq -cn --arg big "$BIG" --arg small "$SMALL" --arg n "$ADD20" \
  '{tool_name:"MultiEdit",tool_input:{file_path:$small,edits:[
     {file_path:$small,old_string:"const x1 = 1;",new_string:$n},
     {file_path:$big,old_string:"const x1 = 1;",new_string:$n}]}}')
check "a two-file batch passes with a warning on the file that crosses" 0 "$(run "$TWO")"
check "and the warning names THAT file" 0 \
  "$(grep -qF "$BIG" <<<"$(run_err "$TWO")" && echo 0 || echo 1)"

# --- the orchestration card is capped in BYTES -------------------------
# main loads the card on every unit, so a worker growing it past 9000 bytes is
# refused at the edit, not found at the merge. The path is matched by its tail.
CARDDIR="$TMP/.claude/rules"; mkdir -p "$CARDDIR"; CARD="$CARDDIR/orchestration.md"
card_of() { head -c "$1" /dev/zero | tr '\0' 'a' > "$CARD"; }
PAD30=$(head -c 30 /dev/zero | tr '\0' 'a'); PAD20=$(head -c 20 /dev/zero | tr '\0' 'a')
# Bug caught: the cap counts characters or lines, not bytes; or compares at <=
# so exactly 9000 slips; or judges an edit by its new text alone, not disk + net.
# One check a hook call, so a FAIL line names the payload of the call that failed.
card_of 8990
check "card_edit_over_limit_blocks: 8990 + 29 = 9019 bytes" 2 "$(run "$(edit "$CARD" "a" "$PAD30")")"
check "card_edit_over_limit_blocks: 8990 + 10 = 9000 bytes" 2 \
  "$(run "$(edit "$CARD" "a" "$(head -c 10 /dev/zero | tr '\0' 'a')a")")"
check "card_edit_over_limit_blocks: 5 chars, 10 bytes: 8990 - 1 + 10 = 8999 passes" 0 "$(run "$(edit "$CARD" "a" "ééééé")")"
check "card_edit_over_limit_blocks: 8990 - 2 + 10 = 8998 passes" 0 "$(run "$(edit "$CARD" "aa" "ééééé")")"
check "card_edit_over_limit_blocks: 8990 + 10 = 9000 bytes, 8995 as characters" 2 "$(run "$(edit "$CARD" "" "ééééé")")"
check "card_edit_over_limit_blocks: a 9000-byte Write" 2 "$(run "$(write "$CARD" "$(head -c 9000 /dev/zero | tr '\0' 'a')")")"
# Bug caught: blocking a trim of an already-oversize card, a swap that nets
# smaller, or a replace_all whose count is unknown (the cop declines those).
card_of 9500
check "card_edit_under_limit_passes: a trim of a 9500-byte card" 0 "$(run "$(edit "$CARD" "$PAD30" "$PAD20")")"
card_of 8990
check "card_edit_under_limit_passes: a swap that nets smaller" 0 "$(run "$(edit "$CARD" "$PAD30" "$PAD20")")"
check "card_edit_under_limit_passes: a replace_all" 0 "$(run "$(edit_all "$CARD" "a" "$PAD30")")"
check "card_edit_under_limit_passes: an 8000-byte Write" 0 "$(run "$(write "$CARD" "$(head -c 8000 /dev/zero | tr '\0' 'a')")")"

echo
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
