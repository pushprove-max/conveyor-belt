#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# PreToolUse hook (Edit|Write|MultiEdit): block a Write, and warn on an Edit,
# that takes a .ts file past 500 lines or a .tsx file past 400 -- the caps the rules state
# (`.claude/rules/backend.md`, `.claude/rules/frontend.md`, AGENT_STARTUP.md).
#
# ONLY THOSE TWO CAPS. There used to be a universal 800-line block for every
# file type. No rule states it, so a 900-line markdown reference or a generated
# fixture was refused on a number nobody chose, while a .tsx sailed past its
# stated 400 with a warning nothing enforced. The stated caps are enforced and
# the invented one is gone.
#
# WHY IT SEES EDITS NOW. It was registered on `Write` alone until 2026-08-31 and
# read only tool_input.content, so it could only judge a file written whole --
# which is not how a file gets long. Files grow by Edit and MultiEdit, one hunk
# at a time, and every one of those passed unmeasured.
#
# HOW AN EDIT IS MEASURED. A Write states the whole file, so its line count is
# exact. An Edit does not, so the count is the file ON DISK plus, per edit, the
# lines the new text adds over the old text it replaces. That is exact for the
# ordinary edit and needs no guessing.
#
# WHERE IT DECLINES TO GUESS, deliberately, rather than shipping a check that
# lies: a `replace_all` edit applies its swap an unknown number of times, and a
# file not yet on disk has no baseline. In either case the payload is not
# measurable and the hook exits silently. A wrong number here would be worse
# than no number: it would either block a legitimate write or, reported as
# fact, be believed.
# THE PAYLOAD SHAPE COMES FROM THE SHARED EXTRACTOR. This hook used to
# keep its own jq over `.tool_input.edits`, a second definition of how the three
# tools spell a change, beside the one in lib/edit-payload.sh. A second
# definition is how eleven guards went blind to MultiEdit for a month: the July
# fold reached some hooks and not their siblings. The shape it needs -- whether
# a whole file was stated, and each edit's net line count -- now lives in the
# helper as hook_edit_size, so the next tool shape is added there once.
INPUT=$(cat)
. "${BASH_SOURCE[0]%/*}/lib/hook-fire-log.sh" 2>/dev/null && hook_fire_log_arm "$INPUT"
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=lib/edit-payload.sh
. "$HERE/lib/edit-payload.sh" 2>/dev/null
hook_payload_loaded 2>/dev/null || {
  echo "BLOCKED: .claude/hooks/lib/edit-payload.sh did not load, so the file-size cap screened nothing. Restore it: git checkout .claude/hooks/lib/edit-payload.sh" >&2
  exit 2
}

# AN EDIT IS JUDGED ON CROSSING THE LINE, NOT ON STANDING BEYOND IT. A Write
# states a whole file, so its baseline is zero and any oversized result is the
# writer's doing. An edit to a file that is ALREADY too long is usually the
# repair, and warning on every one of those -- or worse, blocking them -- turns
# a long file into a file nobody can shorten. So a threshold fires only when
# this change takes the file across it.
#
# One record per PATH, so a MultiEdit that touches two files is judged per file
# rather than summed against the payload-level path.
while IFS=$'\t' read -r P64 KIND N; do
  [ -n "${P64:-}" ] && [ -n "${KIND:-}" ] || continue
  FILE_PATH=$(printf '%s' "$P64" | base64 -d 2>/dev/null) || continue
  case "$FILE_PATH" in
    */.claude/rules/orchestration.md)
      # The card is capped in BYTES: main loads it on every unit. A Write
      # is its content's bytes; an edit is the disk size plus each record's new
      # bytes less its old. A replace_all never reaches here (hook_edit_size
      # prints nothing for it), so it is declined as for the line caps.
      # 9000 is the twin of the limit in .claude/hooks/__tests__/startup-size.test.sh.
      CARD_LIMIT=9000
      NEW=0; OLD=0
      while IFS=: read -r _p _n _o; do
        [ "$_p" = "$P64" ] || continue
        NEW=$((NEW + $(printf '%s' "$_n" | base64 -d 2>/dev/null | wc -c | tr -d ' ')))
        OLD=$((OLD + $(printf '%s' "$_o" | base64 -d 2>/dev/null | wc -c | tr -d ' ')))
      done <<< "$(hook_edit_triples "$INPUT" | tr '\t' ':')"
      if [ "$KIND" = write ]; then
        DISK=0; [ -f "$FILE_PATH" ] && DISK=$(wc -c < "$FILE_PATH" | tr -d ' ')
        PROJECTED=$NEW
      else
        [ -f "$FILE_PATH" ] || continue
        DISK=$(wc -c < "$FILE_PATH" | tr -d ' '); PROJECTED=$((DISK + NEW - OLD))
      fi
      if [ "$PROJECTED" -ge "$CARD_LIMIT" ] && [ "$DISK" -lt "$CARD_LIMIT" ]; then
        echo "BLOCKED: this change leaves $FILE_PATH at ${PROJECTED} bytes; the card limit is ${CARD_LIMIT}. The card holds what main does on every unit; move the rest to .claude/orchestration-reference.md with a pointer." >&2
        exit 2
      fi
      continue ;;
    *.tsx) CAP=400; RULE='.claude/rules/frontend.md' ;;
    *.ts)  CAP=500; RULE='.claude/rules/backend.md' ;;
    *) continue ;;
  esac
  if [ "$KIND" = write ]; then
    BASELINE=0; LINE_COUNT=$N; VERB="Write to"
  else
    # An edit describes a change to a file it cannot see, so the count is the
    # file ON DISK plus what this call adds. A file not yet on disk has no
    # baseline, and this hook does not guess.
    [ -f "$FILE_PATH" ] || continue
    BASELINE=$(wc -l < "$FILE_PATH" | tr -d ' ')
    LINE_COUNT=$((BASELINE + N)); VERB="Edit to"
  fi
  if [ "$LINE_COUNT" -gt "$CAP" ] && [ "$BASELINE" -le "$CAP" ]; then
    # A feature that grows an existing file past its cap goes ahead; the
    # shrink is its own follow-up unit, not a refactor folded into the feature.
    if [ "$KIND" != write ]; then
      HOOK_FIRE_ADVISE=1
      echo "OVER CAP: $VERB $FILE_PATH leaves a ${LINE_COUNT}-line file; the cap is ${CAP} ($RULE). Allowed in a feature unit: do NOT fold it here; list it under 'Over cap' in the evidence and main files the shrink as a follow-up unit." >&2
      continue
    fi
    echo "BLOCKED: $VERB $FILE_PATH would leave a ${LINE_COUNT}-line file; the cap is ${CAP} ($RULE). Split it, or move what you are adding to the file it belongs in." >&2
    exit 2
  fi
done <<< "$(hook_edit_size "$INPUT")"

exit 0
