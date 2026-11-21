# SPDX-License-Identifier: Apache-2.0
# The engine's needs-you items as open decisions in the owner's decision ledger (.claude/scripts/decision.sh), and the
# step an answer names, sourced by the loop (commands/run.sh). One kind so far: a card blocked with its work kept.
# needsask() looks at the card records and the ledger once. The loop (`serve`) calls it every IDLE seconds, a job beside
# the cards.
#   - Each card blocked with a kept patch (an issue's card, not one stopped for the owner's yes) that has no decision yet
#     gets one, id `blocked-<card>`, once: its recommended option is NEEDSASK_RETRY, the others NEEDSASK_FRESH and
#     NEEDSASK_HELD.
#   - An open decision whose card is no longer blocked with its kept patch (retried or shut by hand, or landed some other
#     way) is answered NEEDSASK_GONE: a closed decision names no step, so it is never taken later.
#   - A decision answered NEEDSASK_RETRY or NEEDSASK_FRESH whose card is still blocked has the step taken, as
#     `conveyor.sh retry <issue>` (with --fresh for the second) does; the card then leaves the blocked cards, so a
#     later pass takes no second step. NEEDSASK_HELD takes none.
# Test seam: CONVEYOR_LEDGER (decision.sh's).
NEEDSASK_RETRY='Retry keeping the work' NEEDSASK_FRESH='Fresh retry' NEEDSASK_HELD='Leave it held'
NEEDSASK_GONE='Closed: the card is no longer blocked with its work kept'
needsask() {
  local dec=$HERE/../.claude/scripts/decision.sh led=${CONVEYOR_LEDGER:-$MAIN/.claude/metrics/decisions.jsonl}
  local cs rows='[]' c n k r e id ans asked opts
  local -A issue=()
  # The cards blocked now: a card's last closing line is a blocked one, so a card retried (its lines moved to the
  # retried file), shut or landed is not here. Not a card of a main-red fix (issue 0), nor one stopped for the owner's yes.
  cs=$(stdb ask lines cards) || { echo "conveyor: the card records could not be read; no blocked card was put to the owner" >&2; return 1; }
  [ ! -e "$led" ] || rows=$(CONVEYOR_MAIN=$MAIN bash "$dec" list) || { echo "conveyor: the decision ledger $led could not be read" >&2; return 1; }
  while IFS=$'\t' read -r c n k r; do
    [ -s "$ST/$k/$c.patch" ] && issue[$c]=$n || continue
    ! jq -e --arg id "blocked-$c" 'any(.[]; .id == $id)' <<<"$rows" >/dev/null || continue
    # --reask: decision.sh refuses as a repeat a question like one answered in the last 24 hours (the issue's earlier
    # card, retried by hand): this card is a new one, and its id is the check that it is put once.
    opts=$(jq -cn --arg a "$NEEDSASK_RETRY" --arg b "$NEEDSASK_FRESH" --arg c "$NEEDSASK_HELD" '[$a, $b, $c]')
    e=$(CONVEYOR_MAIN=$MAIN bash "$dec" add "blocked-$c" "Card $c (#$n) is blocked with its work kept: ${r:0:300}. What should the engine do with it?" \
      "$NEEDSASK_RETRY" "conveyor engine: card $c blocked" --options "$opts" --reask "a new card, $c, is blocked" 2>&1 >/dev/null) \
      && echo "conveyor: card $c (#$n) is blocked with its work kept: put to the owner as decision blocked-$c" >&2 \
      || echo "conveyor: decision blocked-$c could not be put to the owner: ${e//$'\n'/ }" >&2
  done < <(jq -rs --arg yes "$YES" --arg lintyes "$LINTYES" 'group_by(.card)[] | select(all(.step != "pushed"))
    | map(select(.step | IN("landed", "closed", "blocked"))) | last | select(. != null and .step == "blocked" and .issue > 0 and (.kept // "") != ""
      and ((.reason // "") | startswith($yes) or startswith($lintyes) | not)) | [.card, .issue, .kept, ((.reason // "") | gsub("\\s+"; " "))] | @tsv' <<<"$cs")
  [ -e "$led" ] || return 0
  rows=$(CONVEYOR_MAIN=$MAIN bash "$dec" list) || { echo "conveyor: the decision ledger $led could not be read" >&2; return 1; }
  # Split on the unit separator, not on a tab: read joins tabs, so an empty answer would move the asking time into it.
  while IFS=$'\x1f' read -r id ans asked; do
    c=${id#blocked-}
    if [ -z "$ans" ] && [ -z "${issue[$c]:-}" ]; then
      CONVEYOR_MAIN=$MAIN bash "$dec" answer "$id" "$NEEDSASK_GONE" --asked-at "$asked" >/dev/null 2>&1 \
        && echo "conveyor: decision $id is closed: card $c is no longer blocked with its work kept" >&2
    elif [ -n "${issue[$c]:-}" ]; then
      case $ans in
        "$NEEDSASK_RETRY") echo "conveyor: decision $id is answered \"$ans\": retry ${issue[$c]}" >&2
          bash "$HERE/conveyor.sh" retry "${issue[$c]}" < /dev/null ;;
        "$NEEDSASK_FRESH") echo "conveyor: decision $id is answered \"$ans\": retry ${issue[$c]} --fresh" >&2
          bash "$HERE/conveyor.sh" retry "${issue[$c]}" --fresh < /dev/null ;;
      esac
    fi
  done < <(jq -r '.[] | select(.id | startswith("blocked-")) | [.id, (.answer // ""), .askedAt] | join("\u001f")' <<<"$rows")
  return 0
}
