# SPDX-License-Identifier: Apache-2.0
# The engine's needs-you items as open decisions in the owner's decision ledger (.claude/scripts/decision.sh), and the
# step an answer names, sourced by the loop (commands/run.sh). Two kinds: a card blocked with its work kept (needsask()),
# and a held issue of the nightly whole test (needsmain(), below); and the auto pass that answers them while auto is on
# (needsauto(), at the end), with the standing review-retry (needsretry()) and the landing of a card blocked by its
# review again (needsland()), and, when the host file names a webhook, one notice for each card that waits for the
# owner (needsnotify(), below). The loop runs them as one job (needsjob()).
# needsask() looks at the card records and the ledger once. The loop (`serve`) calls it every IDLE seconds, a job beside
# the cards.
#   - Each card blocked with a kept patch (an issue's card, not one stopped for the owner's yes) that has no decision yet
#     gets one, id `blocked-<card>`, once: its recommended option is NEEDSASK_RETRY, the others NEEDSASK_FRESH and
#     NEEDSASK_HELD. A card blocked by its review after review-retry gave its issue back (reviewretried(), lib/views.sh) is
#     asked as RRAGAIN (lib/standing.sh) says, with its kept patch and both block reasons, this one and the one
#     review-retry gave back: auto decide leaves that decision to the owner. While auto is on (full), needsland() lands
#     such a card first (below), unless it waits for the owner there too.
#   - An open decision whose card is no longer blocked with its kept patch (retried or shut by hand, or landed some other
#     way) is answered NEEDSASK_GONE: a closed decision names no step, so it is never taken later.
#   - A decision answered NEEDSASK_RETRY or NEEDSASK_FRESH whose card is still blocked has the step taken, as
#     `conveyor.sh retry <issue>` (with --fresh for the second) does; the card then leaves the blocked cards, so a
#     later pass takes no second step. NEEDSASK_HELD takes none. The retry is the owner's own (CONVEYOR_RETRYBY owner,
#     commands/retry.sh), which lets review-retry give the issue back once more and releases a held issue, only for an
#     answer decision.sh marked as the owner's (the Board's). Another answer (auto decide's, a Foreman's, or one that
#     names no one, to a question asked as RRAGAIN says too) is the engine's (decision): its retry leaves a held issue held.
#   - A decision answered RLCLOSED (lib/standing.sh) whose card is still blocked is reopened (rlreopen()): the retry by
#     review-land that closed it ended before it moved the card's lines (a restart stopped it), and needsland() tries
#     each card once, so the card would stay blocked with no one asked.
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
  heldlist l 2>/dev/null && w=$(jq -rRs --argjson l "$l" "$HELDIN"'heldnames($l) | join(", ")' <<<"$2" 2>/dev/null) || { printf %s "$2"; return 0; }
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
  local cs old rows='[]' c n k r r1 e id ans asked by opts q h mk lines
  local -A issue=()
  # The cards blocked now: a card's last closing line is a blocked one, so a card retried (its lines moved to the
  # retried file), shut or landed is not here. Not a card of a main-red fix (issue 0), nor one stopped for the owner's yes,
  # nor one blocked to be shut for a privacy hit (PRIVSHUT, privshut()): this job can read it before the shut, and nothing waits for the owner there.
  cs=$(stdb ask lines cards) && old=$(stdb ask lines retried) || { echo "conveyor: the card records could not be read; no blocked card was put to the owner" >&2; return 1; }
  [ ! -e "$led" ] || rows=$(CONVEYOR_MAIN=$MAIN bash "$dec" list) || { echo "conveyor: the decision ledger $led could not be read" >&2; return 1; }
  while IFS=$'\t' read -r c n k r r1; do
    [ -s "$ST/$k/$c.patch" ] && issue[$c]=$n || continue
    # r1: the block review-retry gave back, when this card came after that retry: both reasons are asked. The row is
    # joined with tabs, not @tsv: the reasons hold no tab or line break (gsub below), and @tsv doubles each backslash.
    h="Card $c (#$n) is blocked with its work kept:"
    [ -z "$r1" ] || { h="Card $c (#$n) $RRAGAIN, its work kept in $ST/$k/$c.patch:"; r="this block: $r; the block review-retry gave back: $r1"; }
    if jq -e --arg id "blocked-$c" 'any(.[]; .id == $id)' <<<"$rows" >/dev/null; then
      askkeep "blocked-$c" "$r" || echo "conveyor: the whole block reason of decision blocked-$c could not be kept in $ST/auto/asked" >&2
      continue
    fi
    # --reask: decision.sh refuses as a repeat a question like one answered in the last 24 hours (the issue's earlier
    # card, retried by hand): this card is a new one, and its id is the check that it is put once.
    opts=$(jq -cn --arg a "$NEEDSASK_RETRY" --arg b "$NEEDSASK_FRESH" --arg c "$NEEDSASK_HELD" '[$a, $b, $c]')
    # The two reasons after a review-retry are asked whole, not cut (askcut()): card.sh names a new P0 before the
    # finding whose fix did not hold, so a cut can drop that finding. auto decide holds such a question whatever it holds.
    if [ -n "$r1" ]; then askkeep "blocked-$c" "$r" && q=$r; else q=$(askcut "blocked-$c" "$r"); fi \
      || { echo "conveyor: decision blocked-$c was not put to the owner: the whole block reason could not be kept in $ST/auto/asked" >&2; continue; }
    e=$(CONVEYOR_MAIN=$MAIN bash "$dec" add "blocked-$c" "$h $q. What should the engine do with it?" \
      "$NEEDSASK_RETRY" "conveyor engine: card $c blocked" --options "$opts" --reask "a new card, $c, is blocked" 2>&1 >/dev/null) \
      && echo "conveyor: card $c (#$n) is blocked with its work kept: put to the owner as decision blocked-$c" >&2 \
      || echo "conveyor: decision blocked-$c could not be put to the owner: ${e//$'\n'/ }" >&2
  done < <(jq -rs --arg yes "$YES" --arg lintyes "$LINTYES" --arg priv "$PRIVSHUT" --arg rb "$REVIEWBLOCK" --slurpfile old <(printf '%s' "$old") "$REVIEWAGAIN"'retrylines($old) as $all
    | group_by(.card)[] | select(all(.step != "pushed"))
    | map(select(.step | IN("landed", "closed", "blocked"))) | last | select(. != null and .step == "blocked" and .issue > 0 and (.kept // "") != ""
      and ((.reason // "") | startswith($yes) or startswith($lintyes) or startswith($priv) | not))
    | [.card, .issue, .kept, ((.reason // "") | gsub("\\s+"; " ")),
       (if (.reason // "" | test($rb)) then reviewretried(.issue; $all).reason // "" | gsub("\\s+"; " ") else "" end)] | map(tostring) | join("\t")' <<<"$cs")
  [ -e "$led" ] || return 0
  rows=$(CONVEYOR_MAIN=$MAIN bash "$dec" list) || { echo "conveyor: the decision ledger $led could not be read" >&2; return 1; }
  # Split on the unit separator, not on a tab: read joins tabs, so an empty answer would move the asking time into it.
  # by: owner for an answer decision.sh marked as the owner's (answer --by owner: the Board's), else decision. Only the
  # owner's retry releases a held issue (again(), commands/retry.sh). Bugs: auto decide's answer released an issue the
  # owner held, and so did an answer that named no one to a question asked as RRAGAIN says (auto decide holds those,
  # but a Foreman can answer one).
  mk=${led%.jsonl}.answeredby.jsonl; [ -e "$mk" ] || mk=/dev/null
  lines=$(jq -r --slurpfile m "$mk" '[$m[] | select(.by == "owner") | .row] as $o
    | .[] | select(.id | startswith("blocked-")) | . as $r
    | [.id, (.answer // ""), .askedAt, (if any($o[]; . == $r) then "owner" else "decision" end)]
    | join("\u001f")' <<<"$rows") || { echo "conveyor: the decision ledger $led or $mk could not be read; no blocked decision is read in this pass" >&2; return 1; }
  while IFS=$'\x1f' read -r id ans asked by; do
    [ -n "$id" ] || continue # no decision: the one empty line of an empty list
    c=${id#blocked-}
    if [ -z "$ans" ] && [ -z "${issue[$c]:-}" ]; then
      CONVEYOR_MAIN=$MAIN bash "$dec" answer "$id" "$NEEDSASK_GONE" --asked-at "$asked" >/dev/null 2>&1 \
        && echo "conveyor: decision $id is closed: card $c is no longer blocked with its work kept" >&2
    elif [ -n "${issue[$c]:-}" ]; then
      case $ans in
        "$NEEDSASK_RETRY") echo "conveyor: decision $id is answered \"$ans\": retry ${issue[$c]}" >&2
          CONVEYOR_RETRYBY=$by bash "$HERE/conveyor.sh" retry "${issue[$c]}" < /dev/null ;;
        "$NEEDSASK_FRESH") echo "conveyor: decision $id is answered \"$ans\": retry ${issue[$c]} --fresh" >&2
          CONVEYOR_RETRYBY=$by bash "$HERE/conveyor.sh" retry "${issue[$c]}" --fresh < /dev/null ;;
        "$RLCLOSED") locked rlreopen "$id" "$c" "${issue[$c]}" ;;
      esac
    fi
  done <<<"$lines"
  return 0
}
# rlreopen <id> <card> <issue>, under the records' lock: decision <id>, closed RLCLOSED, is reopened when <card>'s last
# closing line is still a blocked one. The retry by review-land closes the decision and moves the card's lines under
# that same lock (again(), commands/retry.sh), so a card blocked here was not given back: that retry was stopped
# between the two. Bug guarded: a restart there left the card blocked with its decision closed, and no one was asked.
rlreopen() {
  local e
  stdb ask issue cards "$3" | jq -se --arg c "$2" 'map(select(.card == $c and (.step | IN("landed", "closed", "blocked")))) | last | .step == "blocked"' >/dev/null || return 0
  e=$(CONVEYOR_MAIN=$MAIN bash "$HERE/../.claude/scripts/decision.sh" reopen "$1" 2>&1 >/dev/null) \
    && echo "conveyor: decision $1 is open again: the retry by review-land that closed it did not give card $2 back" >&2 \
    || echo "conveyor: decision $1 could not be reopened: ${e//$'\n'/ }" >&2
}

# The second kind: an issue the nightly whole test filed for a test that fails on main (maintest(), lib/followups.sh;
# the record $MAINTEST names it in `filed`) that the control record holds and GitHub has open. needsmain() looks once, as
# needsask() does.
#   - Each such issue with no decision yet gets one, id `mainred-<issue>`, once: its recommended option is
#     NEEDSMAIN_RELEASE, the other NEEDSMAIN_HELD. One whose decision was answered NEEDSMAIN_GONE (the issue was closed,
#     or released by hand) is asked again, under the same id, once the issue is held and open again.
#   - An open decision whose issue is no longer held (released by hand), or is closed, is answered NEEDSMAIN_GONE.
#   - A decision answered NEEDSMAIN_RELEASE whose issue is still held and open has the step taken: the issue goes first in
#     the control record's `order`, then is released, as `control order` and `control release` do. An answer
#     decision.sh marked as the owner's (answer --by owner: the Board's) makes it the owner's release, dated in `released`
#     (foreman status: "you released it"); any other (`auto decide`'s, or one that names no one) makes it the engine's
#     (CONVEYOR_RELEASEBY decision), so the owner is never credited with auto's pick. The decision's id and
#     its asking number (MAINASKS) are then written to the file $ST/mainred-released, and that answer is read no more, so
#     a later hold of the issue is not released again by the old answer; the answer itself is left as the owner gave it.
#     The same decision asked again (reopened, or asked again as above) has a new asking number, so its answer is read,
#     in the asking's own second too.
#     NEEDSMAIN_HELD takes no step.
# Test seam: CONVEYOR_LEDGER (decision.sh's).
NEEDSMAIN_RELEASE='Release it, first in the order' NEEDSMAIN_HELD='Leave it held'
NEEDSMAIN_GONE='Closed: the issue is no longer held and open'
# MAINASKS, a jq def put before a filter: asks gives each mainred decision's ledger rows (the ledger only grows; each
# asking, decision.sh's add and reopen, writes one row with no answer, and each answer and correction one with its
# answer), in the order written, each with _k: the number of its asking (1 for the first). Two askings in one second
# have two numbers, where their askedAt, whole seconds, can be the same.
MAINASKS='def asks: [.[] | select(.id | type == "string" and startswith("mainred-"))] | group_by(.id)
  | map(reduce .[] as $r ({k: 0, a: []}; .k += (if $r.answeredAt == null then 1 else 0 end) | .a += [$r + {_k: .k}]) | .a); '
# mainstate <issue>: GitHub's state of the issue, OPEN or CLOSED; nothing for an issue it cannot read.
mainstate() { timeout 20 gh issue view "$1" --json state 2>/dev/null | jq -r '.state // ""' 2>/dev/null; }
# mainclose <id> <asked> <answer> <text>: a decision with no answer is answered <text>; one with <answer> has it replaced by <text>.
mainclose() { local dec=$HERE/../.claude/scripts/decision.sh
  if [ -n "$3" ]; then CONVEYOR_MAIN=$MAIN bash "$dec" answer "$1" "$4" --correct >/dev/null 2>&1
  else CONVEYOR_MAIN=$MAIN bash "$dec" answer "$1" "$4" --asked-at "$2" >/dev/null 2>&1; fi
}
needsmain() {
  local dec=$HERE/../.claude/scripts/decision.sh led=${CONVEYOR_LEDGER:-$MAIN/.claude/metrics/decisions.jsonl}
  local c rows='[]' mk lines n cases id ans asked opts e st q why by rb rest=()
  c=$(ctl) || { echo "conveyor: the control record could not be read; no held issue was put to the owner" >&2; return 1; }
  [ ! -e "$led" ] || rows=$(CONVEYOR_MAIN=$MAIN bash "$dec" list) || { echo "conveyor: the decision ledger $led could not be read" >&2; return 1; }
  # A short run (a run that skipped cases) files an issue too, but names no test that fails: left out.
  while IFS=$'\t' read -r n cases; do
    # A decision the engine closed as gone (NEEDSMAIN_GONE) is asked again: its issue is held and open again.
    if jq -e --arg id "mainred-$n" --arg gone "$NEEDSMAIN_GONE" 'any(.[]; .id == $id and .answer != $gone)' <<<"$rows" >/dev/null; then
      askkeep "mainred-$n" "$cases" || echo "conveyor: the whole list of tests of decision mainred-$n could not be kept in $ST/auto/asked" >&2
      continue
    fi
    [ "$(mainstate "$n")" = OPEN ] || continue
    why="a new issue, #$n, is held"; ! jq -e --arg id "mainred-$n" 'any(.[]; .id == $id)' <<<"$rows" >/dev/null || why="issue #$n is held and open again"
    opts=$(jq -cn --arg a "$NEEDSMAIN_RELEASE" --arg b "$NEEDSMAIN_HELD" '[$a, $b]')
    q=$(askcut "mainred-$n" "$cases") || { echo "conveyor: decision mainred-$n was not put to the owner: its whole list of tests could not be kept in $ST/auto/asked" >&2; continue; }
    e=$(CONVEYOR_MAIN=$MAIN bash "$dec" add "mainred-$n" "Issue #$n was filed by the nightly whole test for a test that fails on main ($q), and the engine holds it. What should the engine do with it?" \
      "$NEEDSMAIN_RELEASE" "conveyor engine: issue #$n held" --options "$opts" --reask "$why" 2>&1 >/dev/null) \
      && echo "conveyor: issue #$n, filed by the nightly whole test, is held: put to the owner as decision mainred-$n" >&2 \
      || echo "conveyor: decision mainred-$n could not be put to the owner: ${e//$'\n'/ }" >&2
  done < <(jq -r --slurpfile m <(cat "$MAINTEST" 2>/dev/null; true) '.held as $h | ($m | .[0] // {} | .filed // [])[]
    | select(.issue | IN($h[])) | select((.cases | length) > 0 and (.cases[0] | startswith("a short run") | not)) | [.issue, (.cases | join(", "))] | @tsv' <<<"$c")
  [ -e "$led" ] || return 0
  # A line that names the issue alone was written by an engine that did not keep which asking it released for. That
  # engine released the issue once, for the asking of mainred-<issue> that stood answered NEEDSMAIN_RELEASE when it
  # looked, and read no answer of that decision after. The line becomes a line of each asking ever answered so (a ledger
  # row of that asking with that answer: the ledger keeps every row, a corrected answer too), so no answer that engine
  # may have taken releases the issue again. No time is read to tell which one it took: the file's and the ledger's are
  # whole seconds, and the ledger can be written on another machine. When the decision's last asking is one of two or
  # more so answered, the records fit two histories that need different acts (that engine took an earlier one, and the
  # last one's answer is unread; or it took the last one), so that asking gets the line "ask <id> <asking number>" in
  # place of its own: its answer is not read, and the decision is put to the owner again (below). All such lines at
  # once: one rewrite.
  if grep -qx '[0-9][0-9]*' "$ST/mainred-released" 2>/dev/null; then
    { q=$(jq -rs --arg r "$NEEDSMAIN_RELEASE" --rawfile old "$ST/mainred-released" "$MAINASKS"'
           [$old | splits("\n") | select(test("^[0-9]+$")) | "mainred-" + .] as $ids
           | asks[] | select(.[0].id | IN($ids[])) | .[0].id as $id | last._k as $l
           | ([.[] | select(.answer == $r) | ._k] | unique) as $a | (($a | length) > 1 and ($l | IN($a[]))) as $two
           | ($a[] | select($two and . == $l | not) | "\($id) \(.)"), (select($two) | "ask \($id) \($l)")' "$led") \
      && { grep -vx '[0-9][0-9]*' "$ST/mainred-released"; sed '/^$/d' <<<"$q"; } > "$ST/mainred-released.new" \
      && mv -f "$ST/mainred-released.new" "$ST/mainred-released"; } \
      || { echo "conveyor: the old lines of $ST/mainred-released could not be rewritten; no mainred decision is read in this pass" >&2; return 1; }
  fi
  # decision.sh's read of the whole ledger, which fails on a row it does not take, then the rows read again by
  # MAINASKS, which numbers each asking.
  CONVEYOR_MAIN=$MAIN bash "$dec" list > /dev/null && rows=$(jq -cs "$MAINASKS"'asks' "$led") \
    || { echo "conveyor: the decision ledger $led could not be read" >&2; return 1; }
  # Each "ask <id> <asking number>" line: while that asking, answered, is still the decision's last (the line keeps its
  # answer from being read, below), the decision is asked again under its id, a new open asking whose answer is read
  # as any other, in the same second too. The owner's answers stay in the ledger, and the question names the latest. It
  # has no recommended option, so the auto pass (`auto decide`) leaves it to the owner. The line goes once the decision
  # has another asking (this one, or the owner's reopen); a line whose asking failed stays, for the next pass.
  if grep -q '^ask ' "$ST/mainred-released" 2>/dev/null; then
    e=''
    while read -r _ id asked; do
      st='' ans=''; IFS=$'\x1f' read -r st ans < <(jq -r --arg id "$id" '.[] | last | select(.id == $id and .answeredAt != null)
        | [._k, (.answer // "no answer" | gsub("[\r\n\u001f]+"; " "))] | map(tostring) | join("\u001f")' <<<"$rows")
      [ "$st" = "$asked" ] || continue
      n=${id#mainred-}; opts=$(jq -cn --arg a "$NEEDSMAIN_RELEASE" --arg b "$NEEDSMAIN_HELD" '[$a, $b]')
      if CONVEYOR_MAIN=$MAIN bash "$dec" add "$id" "An older engine released issue #$n once on an answer to this decision, and its records do not show which answer. Your latest answer was \"$ans\": the engine cannot tell whether it was acted on, so it takes no step until you answer. What should the engine do with the issue?" \
        none "conveyor engine: issue #$n held" --options "$opts" --reask "an older engine's records do not show which answer it acted on" > /dev/null; then
        echo "conveyor: decision $id is put to the owner again: an older engine's line in $ST/mainred-released does not show which of its answers was acted on" >&2
      else echo "conveyor: decision $id could not be put to the owner again" >&2; e+="ask $id $asked"$'\n'; fi
    done < <(grep '^ask ' "$ST/mainred-released")
    { grep -v '^ask ' "$ST/mainred-released"; printf %s "$e"; } > "$ST/mainred-released.new" && mv -f "$ST/mainred-released.new" "$ST/mainred-released" \
      || { echo "conveyor: $ST/mainred-released could not be rewritten" >&2; return 1; }
    rows=$(jq -cs "$MAINASKS"'asks' "$led") || { echo "conveyor: the decision ledger $led could not be read" >&2; return 1; }
  fi
  # The rows decision.sh marked as the owner's answers (answer --by owner, the Board's), from the mark file beside the
  # ledger. jq reads the file itself (--slurpfile): as one argument, a long history of marks passes the length an argument
  # may have (128 KiB on Linux), and no decision is read.
  mk=${led%.jsonl}.answeredby.jsonl; [ -e "$mk" ] || mk=/dev/null
  lines=$(jq -r --slurpfile m "$mk" '[$m[] | select(.by == "owner") | .row] as $o | .[] | last
    | (del(._k) as $r | if any($o[]; . == $r) then "owner" else "" end) as $by
    | [.id, (.answer // ""), .askedAt, ._k, $by] | map(tostring) | join("\u001f")' <<<"$rows") \
    || { echo "conveyor: the decision ledger $led or $mk could not be read; no mainred decision is read in this pass" >&2; return 1; }
  while IFS=$'\x1f' read -r id ans asked k by; do
    [ -n "$id" ] || continue # no decision: the one empty line of an empty list
    # An answer that names no step (leave it held, closed, done) is left as it is.
    [ -z "$ans" ] || [ "$ans" = "$NEEDSMAIN_RELEASE" ] || continue
    n=${id#mainred-}
    ! grep -qxF -e "$id $k" -e "ask $id $k" "$ST/mainred-released" 2>/dev/null || continue
    # The record as it stands now: an earlier release of this pass has moved `order`.
    c=$(ctl) || { echo "conveyor: the control record could not be read; decision $id waits" >&2; return 1; }
    if jq -e --argjson n "$n" '.held | index($n) | not' <<<"$c" >/dev/null; then st=CLOSED; else st=$(mainstate "$n"); fi
    case $st in
      CLOSED) mainclose "$id" "$asked" "$ans" "$NEEDSMAIN_GONE" && echo "conveyor: decision $id is closed: issue #$n is no longer held and open" >&2 ;;
      OPEN) [ "$ans" = "$NEEDSMAIN_RELEASE" ] || continue
        echo "conveyor: decision $id is answered \"$ans\": order $n first, release $n" >&2
        mapfile -t rest < <(jq -r --argjson n "$n" '.order[] | select(. != $n)' <<<"$c")
        # The owner's answer (its row marked owner) is the owner's release, dated; any other is the engine's.
        rb=decision; [ "$by" != owner ] || rb=''
        bash "$HERE/conveyor.sh" control order "$n" "${rest[@]}" > /dev/null < /dev/null && CONVEYOR_RELEASEBY=$rb bash "$HERE/conveyor.sh" control release "$n" > /dev/null < /dev/null \
          && echo "$id $k" >> "$ST/mainred-released" ;;
    esac
  done <<<"$lines"
  return 0
}

# The auto pass on the machine that has the record: while /conveyor-belt:auto is on or narrow in this state folder
# (commands/auto.sh, $ST/auto/mode.json), the engine decides as the Foreman's `auto decide` would, so auto goes on when the
# Foreman session is not running or the owner's machine is off. needsauto() runs `conveyor.sh auto decide` (its rules, its
# log, its lock) once when the ledger holds an open decision no pass has left for the owner as it stands (a new one,
# or one asked again or reopened under its id, in the same second too: a decided one is no longer open, and each pass
# writes the id and the count of ledger rows of each one it leaves to <log>.seen, whoever runs it; the ledger only
# grows), and fails when it did not run it. The open decisions and their counts come from one read of the ledger, so a
# count is never older than the row it goes with.
# Test seam: CONVEYOR_LEDGER (decision.sh's).
needsauto() {
  local led=${CONVEYOR_LEDGER:-$MAIN/.claude/metrics/decisions.jsonl} log row new=
  log=$(jq -re 'select(.scope == "full" or .scope == "narrow") | .log | strings' "$ST/auto/mode.json" 2>/dev/null) && [ -f "$log" ] && [ -e "$led" ] || return 1
  while IFS= read -r row; do grep -qxF -- "$row" "$log.seen" 2>/dev/null || { new=1; break; }; done \
    < <(jq -rs 'group_by(.id)[] | select(last.answeredAt == null) | "\(.[0].id | gsub("[\r\n]+"; " ")) \(length)"' "$led" 2>/dev/null)
  [ -n "$new" ] || return 1
  bash "$HERE/conveyor.sh" auto decide < /dev/null | sed 's/^/conveyor: /' >&2
}
# The standing kind review-retry (lib/standing.sh) while auto is on or narrow here: the Foreman's watcher takes it
# (foreman/watch-conveyor.sh reviewretry()), and needsretry() takes it too, so it goes on while the watcher is down. Each
# card blocked by its review (the reason the watcher reads: "the fix for [P1] ... did not hold after <n> rounds", with
# any notes after it in brackets; card.sh no longer writes it since issue 1670, so only a block already in the card records has it), and whose reason holds no word of the pack's auto.reserved and no item of the owner's
# profile (lib/standing.sh heldlist: that one waits for the owner), is given back with `conveyor.sh retry <issue>`, and
# the act is logged by `conveyor.sh auto act review-retry`, as the watcher logs it. The retry is marked as review-retry's
# (CONVEYOR_REVIEWRETRY, commands/retry.sh), and each issue is given back once: a later card of the issue, blocked by
# its review again (reviewretried(), REVIEWAGAIN, lib/views.sh), is not given back: needsland() lands it while auto is
# on (full), else needsask() puts it to the owner with both block reasons. Each card is tried once ($ST/auto/review-retry.cards): one whose retry failed stays blocked,
# and needsask() puts it to the owner. The watcher can give the card back between this read and this retry: `retry`
# then says so with status 3 (again(), commands/retry.sh), and that is no failure, and no second act to log.
needsretry() {
  local cs old c n out res rc
  jq -e 'select(.scope == "full" or .scope == "narrow")' "$ST/auto/mode.json" >/dev/null 2>&1 && standingon review-retry || return 0
  cs=$(stdb ask lines cards) && old=$(stdb ask lines retried) || { echo "conveyor: the card records could not be read; no card was given back by review-retry" >&2; return 0; }
  # A block reason that holds a word of the pack's auto.reserved (a finding tagged [security], say) or an item of the
  # owner's profile, as a whole word (HELDIN, lib/standing.sh), waits for the owner.
  heldlist res || { echo "conveyor: the pack's auto.reserved or the owner's profile could not be read; no card was given back by review-retry" >&2; return 0; }
  while IFS=$'\t' read -r c n; do
    ! grep -qxF -- "$c" "$ST/auto/review-retry.cards" 2>/dev/null || continue
    printf '%s\n' "$c" >> "$ST/auto/review-retry.cards" || continue
    out=$(CONVEYOR_REVIEWRETRY=$c bash "$HERE/conveyor.sh" retry "$n" < /dev/null 2>&1); rc=$?
    if [ "$rc" = 0 ]; then
      bash "$HERE/conveyor.sh" auto act review-retry "retried #$n: its card $c was blocked by its review" < /dev/null 2>&1 | sed 's/^/conveyor: /' >&2
    elif [ "$rc" = 3 ] && [[ $out == *"review-retry already gave back card $c of issue #$n;"* ]]; then :
    else echo "conveyor: the review-retry of #$n (card $c) failed, so it waits for the owner: ${out//$'\n'/ }" >&2; fi
  done < <(jq -rs --argjson r "$res" --arg rb "$REVIEWBLOCK" --slurpfile old <(printf '%s' "$old") "$REVIEWAGAIN"'retrylines($old) as $all
    | group_by(.card)[] | select(all(.step != "pushed")) | map(select(.step | IN("landed", "closed", "blocked"))) | last
    | select(. != null and .step == "blocked" and (.issue | numbers) > 0 and (.reason | strings | test($rb))
      and (.reason | heldin($r) | not)
      and reviewretried(.issue; $all) == null) | "\(.card)\t\(.issue)"' <<<"$cs")
}
# While auto is on (scope full, not narrow) with review-retry on, the owner's standing order for a card blocked by its
# review again after review-retry gave its issue back once (reviewretried(), lib/views.sh): land it, and make its
# finding a follow-up. needsland() gives such a card back with `conveyor.sh retry <issue>`, marked as review-land's
# (CONVEYOR_REVIEWLAND), which checks the same and more under the lock (landable(), commands/retry.sh: not at the
# follow-up depth cap, nor a card whose decision the owner answered), and logs the act with `conveyor.sh auto act
# review-retry` and in auto's log (rlput()). Its next card lands the kept patch on its kept review, through the card's
# own tests and landing, and files that review's findings as follow-ups (resumeplan(), afterreview(), lib/card.sh); a
# red test blocks it. Each issue is landed so once (reviewlanded()): a later review block of it goes to the owner. Not
# a block whose reason names a P0 or holds a word of the pack's auto.reserved or an item of the owner's profile
# (landable(), lib/views.sh): those wait for the owner, put to them by needsask(). Each card is tried once
# ($ST/auto/review-land.cards), as in needsretry().
needsland() {
  local cs old c n r out res
  jq -e 'select(.scope == "full")' "$ST/auto/mode.json" >/dev/null 2>&1 && standingon review-retry || return 0
  cs=$(stdb ask lines cards) && old=$(stdb ask lines retried) || { echo "conveyor: the card records could not be read; no card blocked by its review again was landed" >&2; return 0; }
  heldlist res || { echo "conveyor: the pack's auto.reserved or the owner's profile could not be read; no card blocked by its review again was landed" >&2; return 0; }
  while IFS=$'\t' read -r c n r; do
    ! grep -qxF -- "$c" "$ST/auto/review-land.cards" 2>/dev/null || continue
    printf '%s\n' "$c" >> "$ST/auto/review-land.cards" || continue
    if out=$(CONVEYOR_REVIEWLAND=1 bash "$HERE/conveyor.sh" retry "$n" < /dev/null 2>&1); then
      bash "$HERE/conveyor.sh" auto act review-retry "gave #$n back to land: its card $c was blocked by its review again after review-retry gave it back once; its next card lands the kept patch only once its tests pass, and then files the review's findings as follow-ups" < /dev/null 2>&1 | sed 's/^/conveyor: /' >&2
      rlput "$(printf '### %s review-land #%s: card %s given back to land\n- **Question:** Card %s (#%s) %s: %s\n- **Picked:** give it back. Its next card lands the kept patch only once its tests pass, and then files each finding of its review as a follow-up.\n- **Why:** the standing order of the owner while auto is on (the standing kind review-retry). A test that fails blocks that card, and nothing lands.\n- **Reversible:** yes, until that card lands. A change that lands stays on main until a later card changes it.\n' \
        "$(date +%H:%M)" "$n" "$c" "$c" "$n" "$RRAGAIN" "${r:0:600}")" || echo "conveyor: the step that gave #$n (card $c) back to land could not be written to auto's log" >&2
    else echo "conveyor: #$n (card $c, blocked by its review again) was not given back to land, so it waits for the owner: ${out//$'\n'/ }" >&2; fi
  done < <(jq -rs --argjson r "$res" --arg rb "$REVIEWBLOCK" --slurpfile old <(printf '%s' "$old") "$REVIEWAGAIN"'retrylines($old) as $all
    | group_by(.card)[] | select(all(.step != "pushed")) | map(select(.step | IN("landed", "closed", "blocked"))) | last
    | select(. != null and .step == "blocked" and (.issue | numbers) > 0 and (.kept // "") != "" and landable($r; $rb)
      and reviewretried(.issue; $all) != null and (reviewlanded(.issue; $all) | not)) | "\(.card)\t\(.issue)\t\(.reason | gsub("[\t\r\n]+"; " "))"' <<<"$cs")
}
# rlput <text>: an entry of needsland() at the end of "## Decisions" in auto's log (the mode's log, commands/auto.sh),
# where the owner reads what auto did for them: `auto status`, the band's count and the Foreman's account of it. Written
# under the lock auto decide holds while it rewrites that log ($ST/auto/decide.lock), to a new file, then renamed. Its
# "## Summary" is made again with the entry counted (autosum(), lib/standing.sh). Bug: it still said "(nothing yet)".
rlput() {
  local log lk rc=1
  log=$(jq -re '.log | strings' "$ST/auto/mode.json" 2>/dev/null) && [ -f "$log" ] || return 1
  { exec {lk}>>"$ST/auto/decide.lock"; } 2>/dev/null || return 1
  flock -w 120 "$lk" && P=$1 awk '/^## Waiting for the owner$/ && !done { printf "%s\n\n", ENVIRON["P"]; done = 1 } { print }' "$log" > "$log.$$.put" \
    && autosum "$log.$$.put" > "$log.$$.new" && mv "$log.$$.new" "$log" && rc=0
  rm -f "$log.$$.put" "$log.$$.new"; exec {lk}>&-
  return "$rc"
}
# needsnotify: one notice to a webhook for each card that waits for the owner, so an owner away from the Board and the
# Foreman learns of it. Off unless the host file's notify.webhookEnv names an environment variable that holds an https
# address (it is the one reader of that setting). A card is one that is blocked now and has an open decision
# blocked-<card>, or whose block reason blockhead() reads as a stop for the owner's yes. One POST of {"text": "Conveyor:
# card <card> (#<issue>) waits for the owner: <reason>"}, the reason being the block reason's first line cut to 200
# characters: no diff, no project name, no machine name. The card id goes into $ST/notify/sent, one a line, only after a
# 2xx answer, and a card in it is never sent again; a failed send is tried again the next pass. The address is given to
# curl on its standard input (curl --config -), never in its arguments, and no log line holds it.
needsnotify() {
  local dec=$HERE/../.claude/scripts/decision.sh led=${CONVEYOR_LEDGER:-$MAIN/.claude/metrics/decisions.jsonl}
  local var url cs rows='[]' open c n r o body code sent=$ST/notify/sent tmp
  var=$(jq -r '.notify.webhookEnv? // empty | strings' "$HOST" 2>/dev/null) || var=''
  [[ $var =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || return 0
  url=${!var:-}
  # No character a curl config line would read otherwise (a quote, a backslash, a space or a control character).
  [[ $url =~ ^https://[^[:space:][:cntrl:]\\\"]+$ ]] || return 0
  cs=$(stdb ask lines cards) || { echo "conveyor: the card records could not be read; no notice was sent" >&2; return 1; }
  [ ! -e "$led" ] || rows=$(CONVEYOR_MAIN=$MAIN bash "$dec" list) || { echo "conveyor: the decision ledger $led could not be read; no notice was sent" >&2; return 1; }
  open=$(jq -c '[.[] | select((.id | startswith("blocked-")) and (.answer // "") == "") | .id]' <<<"$rows") || return 1
  tmp=$(mktemp "${TMPDIR:-/tmp}/conveyor-notify.XXXXXX") || return 1
  while IFS=$'\t' read -r c n o r; do
    [ -n "$c" ] || continue
    grep -qxF -- "$c" "$sent" 2>/dev/null && continue
    [ "$o" = open ] || [[ $(blockhead "$r") == *'needs a yes' ]] || continue
    body=$(jq -cn --arg t "Conveyor: card $c (#$n) waits for the owner: $r" '{text: $t}')
    printf '%s' "$body" > "$tmp"
    code=$(printf 'url = "%s"\n' "$url" | curl -q --config - -sS -o /dev/null -w '%{http_code}' --max-time 10 --proto '=https' \
      -X POST -H 'Content-Type: application/json' --data-binary "@$tmp" 2>/dev/null) && code="HTTP $code" || code="curl exit $?"
    if [[ $code == "HTTP 2"?? ]]; then
      mkdir -p "$ST/notify" && echo "$c" >> "$sent" && echo "conveyor: card $c (#$n) waits for the owner: the notice was sent" >&2 \
        || echo "conveyor: the notice for card $c was sent, but $sent could not be written" >&2
    else echo "conveyor: the notice for card $c (#$n) was not sent ($code); it is tried again in the next pass" >&2; fi
  done < <(jq -rs --argjson open "$open" '
    group_by(.card)[] | select(all(.step != "pushed"))
    | map(select(.step | IN("landed", "closed", "blocked"))) | last | select(. != null and .step == "blocked")
    | ("blocked-" + .card) as $id
    | [.card, .issue, (if ($open | index($id)) != null then "open" else "-" end),
       ((.reason // "") | split("\n")[0] | gsub("\t"; " ") | .[0:200])] | map(tostring) | join("\t")' <<<"$cs")
  rm -f "$tmp"
}
# needsjob: the loop's job beside the cards: the standing review-retry and the landing of a second review block, the
# items put to the owner, the auto pass, and, when it ran, the steps its answers name at once (a second needsask and
# needsmain), not a turn later.
needsjob() { needsretry; needsland; needsask; needsmain; needsnotify || :; ! needsauto || { needsask; needsmain; }; }
