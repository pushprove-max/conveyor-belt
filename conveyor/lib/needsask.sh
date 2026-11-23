# SPDX-License-Identifier: Apache-2.0
# The engine's needs-you items as open decisions in the owner's decision ledger (.claude/scripts/decision.sh), and the
# step an answer names, sourced by the loop (commands/run.sh). Two kinds: a card blocked with its work kept (needsask()),
# and a held issue of the nightly whole test (needsmain(), below); and the auto pass that answers them while auto is on
# (needsauto(), at the end), with the standing review-retry (needsretry()). The loop runs them as one job (needsjob()).
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
# askcut <id> <text>: the text's first 300 characters, as the question of decision <id> to the owner gives it. auto
# decide holds a question that holds a word of the pack's auto.reserved or an item of the owner's profile (lib/standing.sh
# heldlist), so each such word or item of a longer text is named after the cut, where the cut would hide it; with the
# list unread, the whole text. The list can grow after the question is put (the owner's profile reaches a host later), so
# the whole text of a question that may be cut (300 characters or more) is kept first in $ST/auto/asked/<id>.txt
# (askkeep), where auto decide reads it; it fails, and gives no question, when that file cannot be written.
askcut() {
  local l w
  askkeep "$1" "$2" || return 1
  [ ${#2} -gt 300 ] || { printf %s "$2"; return 0; }
  heldlist l 2>/dev/null && w=$(jq -rRs --argjson l "$l" 'ascii_downcase as $t
    | [$l[] | select(. as $w | $t | contains($w | ascii_downcase))] | join(", ")' <<<"$2" 2>/dev/null) || { printf %s "$2"; return 0; }
  printf %s "${2:0:300}${w:+ (it names: $w)}"
}
# askkeep <id> <text>: a text of 300 characters or more kept whole in $ST/auto/asked/<id>.txt. auto decide holds such a
# question while that file is not there, as its text cannot show whether it was cut, so one of exactly 300 is kept too.
# needsask() and needsmain() also run it for a decision already in the ledger, each pass before auto decide: one put by an
# engine that kept no whole text (before this file was kept) gets it there, so an item the profile holds past the cut
# still holds the decision. Written to a new file, then renamed: auto decide may read the file at the same time, and must
# never read it empty or in part.
askkeep() {
  local f=$ST/auto/asked/$1.txt
  [ ${#2} -ge 300 ] || return 0
  mkdir -p "$ST/auto/asked" && printf %s "$2" > "$f.$$.new" && mv "$f.$$.new" "$f" || { rm -f "$f.$$.new"; return 1; }
}
needsask() {
  local dec=$HERE/../.claude/scripts/decision.sh led=${CONVEYOR_LEDGER:-$MAIN/.claude/metrics/decisions.jsonl}
  local cs rows='[]' c n k r e id ans asked opts q
  local -A issue=()
  # The cards blocked now: a card's last closing line is a blocked one, so a card retried (its lines moved to the
  # retried file), shut or landed is not here. Not a card of a main-red fix (issue 0), nor one stopped for the owner's yes.
  cs=$(stdb ask lines cards) || { echo "conveyor: the card records could not be read; no blocked card was put to the owner" >&2; return 1; }
  [ ! -e "$led" ] || rows=$(CONVEYOR_MAIN=$MAIN bash "$dec" list) || { echo "conveyor: the decision ledger $led could not be read" >&2; return 1; }
  while IFS=$'\t' read -r c n k r; do
    [ -s "$ST/$k/$c.patch" ] && issue[$c]=$n || continue
    if jq -e --arg id "blocked-$c" 'any(.[]; .id == $id)' <<<"$rows" >/dev/null; then
      askkeep "blocked-$c" "$r" || echo "conveyor: the whole block reason of decision blocked-$c could not be kept in $ST/auto/asked" >&2
      continue
    fi
    # --reask: decision.sh refuses as a repeat a question like one answered in the last 24 hours (the issue's earlier
    # card, retried by hand): this card is a new one, and its id is the check that it is put once.
    opts=$(jq -cn --arg a "$NEEDSASK_RETRY" --arg b "$NEEDSASK_FRESH" --arg c "$NEEDSASK_HELD" '[$a, $b, $c]')
    q=$(askcut "blocked-$c" "$r") || { echo "conveyor: decision blocked-$c was not put to the owner: the whole block reason could not be kept in $ST/auto/asked" >&2; continue; }
    e=$(CONVEYOR_MAIN=$MAIN bash "$dec" add "blocked-$c" "Card $c (#$n) is blocked with its work kept: $q. What should the engine do with it?" \
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

# The second kind: an issue the nightly whole test filed for a test that fails on main (maintest(), lib/followups.sh;
# the record $MAINTEST names it in `filed`) that the control record holds and GitHub has open. needsmain() looks once, as
# needsask() does.
#   - Each such issue with no decision yet gets one, id `mainred-<issue>`, once: its recommended option is
#     NEEDSMAIN_RELEASE, the other NEEDSMAIN_HELD.
#   - An open decision whose issue is no longer held (released by hand), or is closed, is answered NEEDSMAIN_GONE.
#   - A decision answered NEEDSMAIN_RELEASE whose issue is still held and open has the step taken: the issue goes first in
#     the control record's `order`, then is released, as `control order` and `control release` do. The issue is then
#     written to the file $ST/mainred-released, and the answer is read no more, so a later hold of the issue is not
#     released again by the old answer; the answer itself is left as the owner gave it. NEEDSMAIN_HELD takes no step.
# Test seam: CONVEYOR_LEDGER (decision.sh's).
NEEDSMAIN_RELEASE='Release it, first in the order' NEEDSMAIN_HELD='Leave it held'
NEEDSMAIN_GONE='Closed: the issue is no longer held and open'
# mainstate <issue>: GitHub's state of the issue, OPEN or CLOSED; nothing for an issue it cannot read.
mainstate() { timeout 20 gh issue view "$1" --json state 2>/dev/null | jq -r '.state // ""' 2>/dev/null; }
# mainclose <id> <asked> <answer> <text>: a decision with no answer is answered <text>; one with <answer> has it replaced by <text>.
mainclose() { local dec=$HERE/../.claude/scripts/decision.sh
  if [ -n "$3" ]; then CONVEYOR_MAIN=$MAIN bash "$dec" answer "$1" "$4" --correct >/dev/null 2>&1
  else CONVEYOR_MAIN=$MAIN bash "$dec" answer "$1" "$4" --asked-at "$2" >/dev/null 2>&1; fi
}
needsmain() {
  local dec=$HERE/../.claude/scripts/decision.sh led=${CONVEYOR_LEDGER:-$MAIN/.claude/metrics/decisions.jsonl}
  local c rows='[]' n cases id ans asked opts e st q rest=()
  c=$(ctl) || { echo "conveyor: the control record could not be read; no held issue was put to the owner" >&2; return 1; }
  [ ! -e "$led" ] || rows=$(CONVEYOR_MAIN=$MAIN bash "$dec" list) || { echo "conveyor: the decision ledger $led could not be read" >&2; return 1; }
  # A short run (a run that skipped cases) files an issue too, but names no test that fails: left out.
  while IFS=$'\t' read -r n cases; do
    if jq -e --arg id "mainred-$n" 'any(.[]; .id == $id)' <<<"$rows" >/dev/null; then
      askkeep "mainred-$n" "$cases" || echo "conveyor: the whole list of tests of decision mainred-$n could not be kept in $ST/auto/asked" >&2
      continue
    fi
    [ "$(mainstate "$n")" = OPEN ] || continue
    opts=$(jq -cn --arg a "$NEEDSMAIN_RELEASE" --arg b "$NEEDSMAIN_HELD" '[$a, $b]')
    q=$(askcut "mainred-$n" "$cases") || { echo "conveyor: decision mainred-$n was not put to the owner: its whole list of tests could not be kept in $ST/auto/asked" >&2; continue; }
    e=$(CONVEYOR_MAIN=$MAIN bash "$dec" add "mainred-$n" "Issue #$n was filed by the nightly whole test for a test that fails on main ($q), and the engine holds it. What should the engine do with it?" \
      "$NEEDSMAIN_RELEASE" "conveyor engine: issue #$n held" --options "$opts" --reask "a new issue, #$n, is held" 2>&1 >/dev/null) \
      && echo "conveyor: issue #$n, filed by the nightly whole test, is held: put to the owner as decision mainred-$n" >&2 \
      || echo "conveyor: decision mainred-$n could not be put to the owner: ${e//$'\n'/ }" >&2
  done < <(jq -r --slurpfile m <(cat "$MAINTEST" 2>/dev/null; true) '.held as $h | ($m | .[0] // {} | .filed // [])[]
    | select(.issue | IN($h[])) | select((.cases | length) > 0 and (.cases[0] | startswith("a short run") | not)) | [.issue, (.cases | join(", "))] | @tsv' <<<"$c")
  [ -e "$led" ] || return 0
  rows=$(CONVEYOR_MAIN=$MAIN bash "$dec" list) || { echo "conveyor: the decision ledger $led could not be read" >&2; return 1; }
  while IFS=$'\x1f' read -r id ans asked; do
    # An answer that names no step (leave it held, closed, done) is left as it is.
    [ -z "$ans" ] || [ "$ans" = "$NEEDSMAIN_RELEASE" ] || continue
    n=${id#mainred-}
    ! grep -qx "$n" "$ST/mainred-released" 2>/dev/null || continue
    # The record as it stands now: an earlier release of this pass has moved `order`.
    c=$(ctl) || { echo "conveyor: the control record could not be read; decision $id waits" >&2; return 1; }
    if jq -e --argjson n "$n" '.held | index($n) | not' <<<"$c" >/dev/null; then st=CLOSED; else st=$(mainstate "$n"); fi
    case $st in
      CLOSED) mainclose "$id" "$asked" "$ans" "$NEEDSMAIN_GONE" && echo "conveyor: decision $id is closed: issue #$n is no longer held and open" >&2 ;;
      OPEN) [ "$ans" = "$NEEDSMAIN_RELEASE" ] || continue
        echo "conveyor: decision $id is answered \"$ans\": order $n first, release $n" >&2
        mapfile -t rest < <(jq -r --argjson n "$n" '.order[] | select(. != $n)' <<<"$c")
        bash "$HERE/conveyor.sh" control order "$n" "${rest[@]}" > /dev/null < /dev/null && bash "$HERE/conveyor.sh" control release "$n" > /dev/null < /dev/null \
          && echo "$n" >> "$ST/mainred-released" ;;
    esac
  done < <(jq -r '.[] | select(.id | startswith("mainred-")) | [.id, (.answer // ""), .askedAt] | join("\u001f")' <<<"$rows")
  return 0
}

# The auto pass on the machine that has the record: while /conveyor-belt:auto is on or narrow in this state folder
# (commands/auto.sh, $ST/auto/mode.json), the engine decides as the Foreman's `auto decide` would, so auto goes on when the
# Foreman session is not running or the owner's machine is off. needsauto() runs `conveyor.sh auto decide` (its rules, its
# log, its lock) once when the ledger holds an open decision its log does not list yet (a new one: a decided one is no
# longer open, and each one left is listed under "Waiting for the owner"), and fails when it did not run it.
# Test seam: CONVEYOR_LEDGER (decision.sh's).
needsauto() {
  local dec=$HERE/../.claude/scripts/decision.sh led=${CONVEYOR_LEDGER:-$MAIN/.claude/metrics/decisions.jsonl} log id new=
  log=$(jq -re 'select(.scope == "full" or .scope == "narrow") | .log | strings' "$ST/auto/mode.json" 2>/dev/null) && [ -f "$log" ] && [ -e "$led" ] || return 1
  while IFS= read -r id; do grep -qF -- "- $id: " "$log" || { new=1; break; }; done \
    < <(CONVEYOR_MAIN=$MAIN bash "$dec" list 2>/dev/null | jq -r '.[] | select(.answeredAt == null) | .id | gsub("[\r\n]+"; " ")' 2>/dev/null)
  [ -n "$new" ] || return 1
  bash "$HERE/conveyor.sh" auto decide < /dev/null | sed 's/^/conveyor: /' >&2
}
# The standing kind review-retry (lib/standing.sh) while auto is on or narrow here: the Foreman's watcher takes it
# (foreman/watch-conveyor.sh reviewretry()), and needsretry() takes it too, so it goes on while the watcher is down. Each
# card blocked by its review (the reason the watcher reads: "the fix for [P1] ... did not hold after <n> rounds", with
# any notes after it in brackets), and whose reason holds no word of the pack's auto.reserved and no item of the owner's
# profile (lib/standing.sh heldlist: that one waits for the owner), is given back with `conveyor.sh retry <issue>`, and
# the act is logged by `conveyor.sh auto act review-retry`, as the watcher logs it. Each card is tried once ($ST/auto/review-retry.cards): one whose retry
# failed stays blocked, and needsask() puts it to the owner.
needsretry() {
  local cs c n out res
  jq -e 'select(.scope == "full" or .scope == "narrow")' "$ST/auto/mode.json" >/dev/null 2>&1 && standingon review-retry || return 0
  cs=$(stdb ask lines cards) || { echo "conveyor: the card records could not be read; no card was given back by review-retry" >&2; return 0; }
  # A block reason that holds a word of the pack's auto.reserved (a finding tagged [security], say) or an item of the
  # owner's profile waits for the owner.
  heldlist res || { echo "conveyor: the pack's auto.reserved or the owner's profile could not be read; no card was given back by review-retry" >&2; return 0; }
  while IFS=$'\t' read -r c n; do
    ! grep -qxF -- "$c" "$ST/auto/review-retry.cards" 2>/dev/null || continue
    printf '%s\n' "$c" >> "$ST/auto/review-retry.cards" || continue
    if out=$(bash "$HERE/conveyor.sh" retry "$n" < /dev/null 2>&1); then
      bash "$HERE/conveyor.sh" auto act review-retry "retried #$n: its card $c was blocked by its review" < /dev/null 2>&1 | sed 's/^/conveyor: /' >&2
    else echo "conveyor: the review-retry of #$n (card $c) failed, so it waits for the owner: ${out//$'\n'/ }" >&2; fi
  done < <(jq -rs --argjson r "$res" 'group_by(.card)[] | select(all(.step != "pushed")) | map(select(.step | IN("landed", "closed", "blocked"))) | last
    | select(. != null and .step == "blocked" and (.issue | numbers) > 0 and (.reason | strings
      | test("\\Athe fix for \\[P[0-3]\\][\\s\\S]* did not hold after [0-9]+ rounds?( \\[[\\s\\S]*\\])?\\z"))
      and ((.reason | ascii_downcase) as $t | all($r[]; . as $w | $t | contains($w | ascii_downcase) | not))) | "\(.card)\t\(.issue)"' <<<"$cs")
}
# needsjob: the loop's job beside the cards: the standing review-retry, the items put to the owner, the auto pass, and,
# when it ran, the steps its answers name at once (a second needsask and needsmain), not a turn later.
needsjob() { needsretry; needsask; needsmain; ! needsauto || { needsask; needsmain; }; }
