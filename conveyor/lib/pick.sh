# SPDX-License-Identifier: Apache-2.0
# Under the lock: the next qualifying issue that has no card yet: a follow-up (label conveyor-followup) before any
# other issue, then highest priority first, then oldest. An issue with any card is skipped: an open one is in
# flight or stopped mid-card, a blocked one waits on the owner, who gives it back with `retry`. An issue named in the
# retried file is a retried one: `pick retried` takes only those, and the answer says whether the pick is one
# ("<card> <issue> <true|false>"), because a retried card does not count toward a run's max-cards. A run limited by --only also takes the follow-ups
# filed from the issues it lists, and theirs: the landed lines name them, and a chain is at most MAX_DEPTH long.
# A follow-up Conveyor filed (its body opens "Follow-up to #N (Conveyor card ...") is taken only once a landed line
# names it. It is filed before its parent lands, and until that landed line is written (or if the parent never
# lands and the follow-up could not be withdrawn) main does not hold the change it is to be built on. Any other
# open conveyor-followup issue, one given the label by hand, has no parent to wait for and is taken like the rest.
# No label but awaiting-deploy holds an issue back (no skip list); it holds every issue back, a follow-up
# too: its code is on main already.
# upnext() is that order as a list, every qualifying issue with no card: pick takes its first, the snapshot shows its
# first ten.
# The control record comes on top of all that. Each such issue gets hold (the record holds it) and rule (the
# rule that excludes it: an area label never built, "follow-ups", or its priority; null for none); those are left out
# of the list unless it is asked for whole (`all`, the snapshot's). The issues of the order list come first, in its
# order, then the order above. pick takes nothing at all unless the loop is running (state, above): it is handed the
# reading's percent and the open issues, both asked for before the lock (each may wait on the network, and every
# card's line waits on the lock), and reads the record itself under the lock.
# Dependencies (DEPS above) come on top of that too: each issue gets waits (the open issues it depends on, and
# the open follow-ups filed from them and from theirs, less those whose newest card landed, push on or off) and,
# in the whole list, stuck (it waits, through the chain, on an issue in a cycle: nothing will ever clear it). An issue
# that waits is left out of the list unless it is asked for whole, like a held one. A dependency that is open and not
# landed is waited for whatever keeps it off the belt (held, a label, blocked, building, waiting for a yes). That is the dependency guard of the
# control record, on unless `control dep-guard off`: only then does an issue `control force` names (forced) go into the
# list while it waits; nothing else (a release, the order list, a retry) lets one through.
# Approve before build (SEE above): an issue whose section names a change and that has no approval line gets
# before (unless the control record's rule "visible changes need the owner's yes" is off), and is left out of the list unless it is asked for whole, like a held one.
# A run limited by --only that finds nothing to pick hears `wait` when an issue of its list is held, waits or
# waits for approval before its build, and is not excluded or stuck: the run goes on polling for
# it instead of ending (a held one is neither landed, closed nor blocked: it is built once released).
# The monthly test-speed survey's card (lib/survey.sh) measures while the machine is quiet: its issue (titled
# "Test-speed survey, ...") gets the rule "the survey hour" outside the pack's test.surveyHour, local time
# (CONVEYOR_NOW when set), so it is picked only in that hour, on whichever day the loop has room for it then.
upnext() { # <open issues json> [retried] [all] [the control record, when the caller has read it]
  local c=${4:-} sh cards old; [ -n "$c" ] || c=$(ctl) || return 1
  packget test.surveyHour sh || return 1
  # Read first, one after the other: a read that fails stops the pick (a process substitution's failure is not
  # passed back, and jq would read no cards at all, so every issue with a card would be picked again).
  cards=$(recs) && old=$(olds) || return 1
  jq -c --slurpfile cards <(printf '%s' "$cards") --slurpfile retried <(printf '%s' "$old") --arg mode "${2:-}" --arg built "$BUILT" --argjson only "${ONLY:-null}" --argjson sh "$sh" \
    --argjson ctl "$c" --arg all "${3:-}" --arg fu "$FOLLOWUP" --argjson prio "$PRIOS" --arg area "$AREA" --argjson np "$NONPRODUCT" \
    "$DEPS$SEE$LEVEL$(<"$HERE/jq/upnext.jq")" <<<"$1"
}
# One Conveyor per machine (docs/setup.md, Run): the machine's settings are the host file's, over every project's loop.
# cap is the most cards building, reviewing or testing at once on this machine across every project (each project's
# own cap, its control record's, is its most at once on top); mode "pause" pauses every project (room()). Unset, each
# sets nothing: only the projects' own caps apply. Cards already running are never stopped by either.
# MACH holds, under MACH/lock, one file per project loop that asked (MACH/slots/<project>.json, a folder of their own,
# so no project's name takes the machine loop's own file, MACH/loop.json): {pid, started, running, wants, last}: its cards
# running at its last turn (or since, one more for each card granted), whether a card of it waits for a slot, and its
# place in the round-robin (last: the machine's count of slots granted when it last got one; MACH/seq is that count).
# A file whose loop is gone counts for nothing once no card of it runs (run: its project's run lock, which they hold). RUNNING is the loop's count of its cards running at this turn, set by
# run() before a pick; a pick outside a loop (none) never asks. A card a card on the belt waits on (urgent()), and a
# main-red fix (redfix()), go past their project's cap, never past the machine's.
MACH=${HOST%/*}/machine; MSLOT=$MACH/slots/$RTAG.json; RUNNING=''
ROOMF=${STATE%/*}/room.json # the card held back by the machine, while one is: {issue, reason, since}
# A host file that is there and does not read as one object is {unread: true}: the machine's cap and pause are
# not known, so no new card starts until it reads (roomed()). No host file (nohost(): a link that leads nowhere is
# a host file that does not read) sets nothing.
mhost() {
  ! nohost || return 0
  local h; h=$(jq -cs 'if length != 1 or (.[0] | type) != "object" then {unread: true} else .[0]
    | {cap: (.cap | if type == "number" and . >= 1 then floor else null end), paused: (.mode == "pause")}
    | select(.cap != null or .paused) end' "$HOST" 2>/dev/null) && echo "$h" || echo '{"unread":true}' # jq prints for no input, then fails
}
# <running> <wants> [<last>]: this loop's slot file, written under the machine lock; last is kept unless given.
slotput() {
  local l=${3:-}; [ -n "$l" ] || l=$(jq -r '.last // 0' "$MSLOT" 2>/dev/null) || l=0
  jq -cn --argjson p "$$" --arg t "$(p_started $$)" --argjson r "$1" --argjson w "$2" --argjson l "${l:-0}" --arg u "$STATE.run" \
    '{pid: $p, started: $t, running: $r, wants: $w, last: $l, run: $u}' > "$MSLOT.new" && mv -f "$MSLOT.new" "$MSLOT"
}
mlocked() { mkdir -p "$MACH/slots" && ( flock -w 30 4 || exit 1; "$@" ) 4>>"$MACH/lock"; }
# The loop's turn: its cards running now, and no card waiting for a slot when it does not ask for one (asking empty).
slotturn() { # <running> [asking]
  ! nohost || { rm -f "$MSLOT" "$ROOMF"; return 0; }
  [ -n "${2:-}" ] || rm -f "$ROOMF"
  mlocked slotput "$1" "$([ -n "${2:-}" ] && jq -r '.wants // false' "$MSLOT" 2>/dev/null || echo false)"
}
# The machine's yes to one more card of this project, for <issue>: 0 and its slot taken, or 1 with why on stdout
# (kept in ROOMF for health and the Board). The order: the machine paused, the cap, then the turn: among the
# projects with a card waiting for a slot, the one that got its last slot longest ago goes first. No host file holds
# nothing back.
room() { # <issue>
  local h; [ -n "$RUNNING" ] && ! nohost || { rm -f "$ROOMF"; return 0; }
  h=$(mhost); [ -n "$h" ] || h='{"cap":null,"paused":false}'
  # The machine's lock not taken: no gate was read, so no card starts.
  local why; why=$(mlocked roomed "$h") || why=${why:-"waiting for a machine slot: the machine's lock could not be taken"}
  if [ -z "$why" ]; then rm -f "$ROOMF"; return 0; fi
  jq -cn --argjson n "$1" --arg r "$why" --slurpfile o <(cat "$ROOMF" 2>/dev/null) \
    '{issue: $n, reason: $r, since: (($o[0] // {}) | if .issue == $n then .since else null end // (now | todate))}' > "$ROOMF.new" 2>/dev/null && mv -f "$ROOMF.new" "$ROOMF"
  echo "$why"; return 1
}
roomed() { # <machine settings>; under the machine lock: prints why not, else takes the slot
  local h=$1 r why='' used s p t mine f c
  if [ "$(jq -r .unread <<<"$h")" = true ]; then why="waiting for a machine slot: the host file could not be read, so the machine's cap and pause are not known"
  elif [ "$(jq -r .paused <<<"$h")" = true ]; then why="the machine's Conveyor is paused (the host file's mode)"
  fi
  c=$(jq -r .cap <<<"$h")
  if [ -z "$why" ] && [ "$c" != null ]; then
    # The other loops alive: "<running> <wants> <last> <name>" each. A loop gone whose cards still run (each holds its
    # project's run lock, run() says why) keeps its slots until they end, and no card of it waits.
    s=$(for f in "$MACH"/slots/*.json; do
      [ -f "$f" ] && [ "$f" != "$MSLOT" ] || continue
      # Split on \037, not a tab: read joins tabs around an empty field, and a file a killed loop's last write left
      # with no start time ("started": "") gave its run lock as empty, so its cards still running were not counted.
      IFS=$'\037' read -r p t r w l u <<<"$(jq -r '[.pid, .started, .running, .wants, .last, .run] | map(if . == null then "" else tostring end) | join("\u001f")' "$f" 2>/dev/null)" || continue
      [ -n "$p" ] || continue
      p_alive "$p" "$t" || { w=false; [ -n "$u" ] && [ -e "$u" ] && ! ( flock -n 5 ) 5>>"$u"; } 2>/dev/null || continue
      f=${f##*/}; echo "$r $w $l ${f%.json}"
    done)
    used=$(( RUNNING + $(awk '{s += $1} END {print s + 0}' <<<"$s") ))
    mine=$(jq -r '.last // 0' "$MSLOT" 2>/dev/null) || mine=0; mine=${mine:-0}; t=${MSLOT##*/}; t=${t%.json}
    if [ "$used" -ge "$c" ]; then why="waiting for a machine slot: $used of the machine cap $c in use"
    else
      p=$(awk -v m="$mine" -v t="$t" '$2 == "true" && ($3 < m || ($3 == m && $4 < t)) {print $4; exit}' < <(sort -n -k3 <<<"$s"))
      [ -z "$p" ] || why="waiting for a machine slot: $p got its last slot before this project and goes first"
    fi
  fi
  if [ -n "$why" ]; then slotput "$RUNNING" true; echo "$why"; return 0; fi
  s=$(( $(cat "$MACH/seq" 2>/dev/null || echo 0) + 1 )); echo "$s" > "$MACH/seq"
  slotput "$((RUNNING + 1))" false "$s"
}
pick() { # [retried or ""] [the weekly limit reading's percent] [the open issues, as asked() gives them] [acctkey of the record the reading was taken for]
  local issues=${3:-} n card l again c u m f
  check && c=$(ctl) || return 1
  [ -z "$issues" ] || adopt "$issues" || return 1
  [ "$(state "$c" "${2:-}")" = running ] || return 0
  # The accounts changed since the loop read the record: its reading is another account's; the next turn reads again.
  [ -z "${4:-}" ] || [ "$(acctkey "$c")" = "$4" ] || { echo wait; return 0; }
  # No list: the loop asked for none, the record not saying running a moment ago. It asks at its next turn.
  [ -n "$issues" ] || { echo wait; return 0; }
  # The fix card of a red main commit (redpick(), lib/testrun.sh) goes ahead of the queue, as its P0 issue did; it counts
  # toward max-cards (not in `pick retried`), and a run limited by --only takes none. One that cannot be picked leaves
  # the queue to go on.
  if [ -z "${1:-}" ] && [ -z "$ONLY" ] && [ -s "${MAINRED:-}" ] && n=$(redpick) && [ -n "$n" ]; then echo "$n"; return 0; fi
  # A pick for the slot beyond the project's cap (BEYOND, set by run(): redfix()) takes a main-red fix card or nothing.
  [ -z "${BEYOND:-}" ] || return 0
  u=$(upnext "$issues" "${1:-}" | jq -r '.[] | "\(.number) \(.again)"') || return 1
  # The first issue whose fields for its picked line read as JSON: one that does not is named in the log and skipped,
  # and the next one is taken on this same pick, so it holds back no other ready issue.
  n=''
  while read -r m; do
    [ -n "$m" ] || continue
    f=$(jq -c --argjson n "${m% *}" 'map(select(.number == $n))[0] | {title: (.title // "")[0:200], created: (.createdAt // "" | tostring)}' <<<"$issues" 2>/dev/null) \
      && { n=$m; break; }
    echo "conveyor: the pick step could not read the title and created time of #${m% *} as JSON; #${m% *} is skipped, and the next ready issue is picked" >&2
  done <<<"$u"
  # The machine's yes (room()): a card it holds back waits, and the loop asks again at its next turn.
  [ -z "$n" ] || room "${n% *}" >/dev/null || { echo wait; return 0; }
  if [ -z "$n" ]; then
    [ -z "$RUNNING" ] || slotturn "$RUNNING" # nothing to pick: no card of it waits for a slot
    [ -n "$ONLY" ] && upnext "$issues" "${1:-}" all | jq -e 'any(.[]; .rule == null and (.stuck | not) and (.hold or .waits != [] or .before))' >/dev/null && echo wait
    return 0
  fi
  again=${n#* }; n=${n% *}
  # A card id is its second, its project and its issue. One retried within the second its blocked card was picked in waits for
  # the next: the two would share a kept folder, and the patch kept there is what the new card starts from.
  while card="c$(date -u +%Y%m%dT%H%M%S)-$CTAG-$n"; stdb ask lines retried | grep -F "\"card\":\"$card\"" >/dev/null; do sleep 1; done
  l=$(line "$card" "$n" picked ok "$f") && append "$l" && echo "$card $n $again"
}

# `pick --dry` (plan section 13, A7: the shadow-comparison contract): the issue pick would take now, from frozen inputs:
# an open-issues file as asked() gives it and a state folder (its card records, retried file, control record and weekly
# limit readings; a file it lacks is read as the loop starts it, empty). The guard is applied to the folder's newest
# reading as the loop applies it (lastpct): one older than LIMIT_OLD is no reading, else the dry pick would hold an
# issue the loop then picks; no new reading is asked for. It writes nothing, there or anywhere: no lock, no check mark, no hold of adopt() saved (the
# record is read with them) and no card. Prints the issue number, or nothing when pick would take none.
drypick() { # <open issues file> <state folder>
  # shellcheck disable=SC2034 # DRYPICK is read by recs(), olds() and lastread() in lib/records.sh
  local issues c bad w DRYPICK=1
  issues=$(jq -ce 'arrays' "$1") || { echo "conveyor: $1 is not a list of open issues" >&2; return 1; }
  READ=$2/$(basename "$STATE"); READ_OLD=$2/$(basename "$RETRIED"); CONTROL=$2/control.json; LIMIT=$2/$(basename "$LIMIT")
  [ -e "$READ" ] || READ=/dev/null; [ -e "$READ_OLD" ] || READ_OLD=/dev/null
  # Only the records' whole lines are read (check() says why), straight from the file: a copy would be a write.
  # A line the check refuses is left out, as the loop sets it aside (check(), views.sh) before it picks.
  w=$(($(wc -l < "$READ"))) || return 1
  bad=$(head -n "$w" "$READ" | jq -Rrn -f "$HERE/jq/check.jq") || return 1
  c=$(ctl) && c=$(adopted "$c" "$issues") && [ -n "$c" ] || return 1
  [ "$(state "$c" "$(guardread "$c" | jq -r '.pct // empty')")" = running ] || return 0
  READ=<(head -n "$w" "$READ" | awk -F'\t' 'NR == FNR { b[$1]; next } !(FNR in b)' <(printf '%s\n' "$bad") -) upnext "$issues" '' '' "$c" | jq -r '.[0].number // empty'
}

# The same-file check before a pick (docs/commands.md, Issues), run by the loop outside the records' lock, as a model
# call takes seconds and every card's line waits on that lock. Cards on the belt that change the same lines of a file
# clash when the second lands, and that card goes back to a fix session; holding every card that might share a file
# waits far longer. So the issue pick would take now (upnext's first) is read beside the cards on the belt (a card of
# an issue with a picked line and no landed, closed or blocked one) by one short judgement: the builder's CLI on the
# last model the pack's models.allowed lists for that CLI (the pack lists them best first: the seed is the first; none
# listed, the builder's own) at low effort, with no tools, OVERLAP_TIMEOUT at most. Only when it answers that the issue
# and card #N clearly change the same part of the same file does the issue get `Depends on: #N` (depends(), the Board's
# "Depends on…", which refuses a cycle) and a one-line comment naming the file and the card; the open issues the pick
# reads then hold that line, so it takes the next issue, and this one waits on the card as any dependency does. A
# call that fails, times out or answers anything else, or a dependency that cannot be written, leaves the issue to be
# picked as it is. An issue is judged once against the same cards on the belt (OVL_SEEN), so a pick the machine holds
# back is not asked again at every turn; one that got a dependency is never judged again by this loop, so the
# owner's × on the Board is not undone. CONVEYOR_OVERLAP_CMD runs in place of the CLI, the prompt on its stdin and the
# answer on its stdout (the tests' seam).
OVERLAP_TIMEOUT=90
declare -gA OVL_SEEN=()
OVERLAP='A queued issue is about to be built while other cards are being built (the cards on the belt). Two cards that
change the same lines of a file clash when the second one lands. Decide whether the queued issue must wait for one of
the cards on the belt.
Answer DEPENDS only when the queued issue and that card clearly change the same part of the same file: both name the
same function, the same test file or the same panel, for example. Sharing an area, a folder, or a file many changes
touch such as README.md is not enough. When in doubt, answer NONE.
Answer with exactly one line and nothing else, one of:
DEPENDS #<the number of the card'"'"'s issue>: <the file both change>
NONE'
overlap() { # <open issues json> <retried or ""> <the control record>: sets OVL to the open issues, with the lines it added
  local all n belt ans d f
  OVL=$1
  [ -n "$1" ] && all=$(turncards 2>/dev/null) && [ -n "$all" ] || return 0
  belt=$(jq -cs '[group_by(.card)[] | select(.[0].issue != 0 and any(.step == "picked") and all(.step | IN("landed", "closed", "blocked") | not)) | .[0].issue] | unique' <<<"$all" 2>/dev/null) || return 0
  [ "$belt" != '[]' ] || return 0
  while n=$(READ=<(printf '%s\n' "$all") upnext "$OVL" "$2" '' "$3" 2>/dev/null | jq -r '.[0].number // empty') && [ -n "$n" ]; do
    [ -z "${OVL_SEEN[$n]+1}" ] && [ -z "${OVL_SEEN[$n $belt]+1}" ] || return 0
    OVL_SEEN[$n $belt]=1
    ans=$(overlapcall "$n" "$belt" "$OVL" "$3") || { echo "conveyor: the same-file check of #$n failed ($ans); it is picked without it" >&2; return 0; }
    [ "$ans" != NONE ] || return 0
    d=${ans%%$'\t'*}; f=${ans#*$'\t'}
    ans=$(depends "$n" add "$d" 2>&1) || { echo "conveyor: #$n changes $f as #$d does, and the dependency could not be added ($ans); it is picked without it" >&2; return 0; }
    OVL_SEEN[$n]=1
    gh_write issue comment "$n" --body "Conveyor: this issue now waits on #$d, which is being built and changes the same part of $f. If that is wrong, remove it with the Board's Depends on… ×." >/dev/null 2>&1 \
      || echo "conveyor: #$n now waits on #$d; no comment could be added to it" >&2
    OVL=$(jq -c --argjson n "$n" --arg l "Depends on: #$d" 'map(if .number == $n then .body = ((.body // "") + "\n" + $l) else . end)' <<<"$OVL") || return 0
  done
}
# One answer from a model with no tools: the builder's CLI on the last model the pack's models.allowed lists for that
# CLI (none listed, the builder's own), at <effort>, <seconds> at most, run in <folder> (a scratch folder the caller
# removes), the answer left in <folder>/answer. Returns the CLI's exit (124: the timeout); when no CLI could be
# started, 1 with why on stdout (nothing else is printed there).
askmodel() { # <folder> <seconds> <effort> <the control record, or ""> <prompt>
  local d=$1 p=$5 s a agent model acct rc
  s=$(seat builder "$4") && jqget "$s" agent agent model model && modelsallowed a \
    || { echo "no builder model"; return 1; }
  model=$(jq -r --arg g "$agent" --arg m "$model" "$OKMODELS"'okmodels("builder")[$g] // [] | last // $m' <<<"$a") || model=''
  case $agent in
    claude) acct=$(acctenv "$(ctlacct "$4")") || { echo "$acct"; return 1; }
      (cd "$d" && proxyenv && acctrun "$acct" && exec timeout --kill-after=10 "$2" claude -p --model "$model" --effort "$3" --tools "" \
        --setting-sources "" --strict-mcp-config --no-session-persistence --output-format text <<<"$p" > "$d/answer" 2> "$d/err" 8>&- 9>&-); rc=$? ;;
    codex) model=$(codexmodel "$model") || { echo "$model"; return 1; }
      (cd "$d" && codexargs && exec timeout --kill-after=10 "$2" codex exec --skip-git-repo-check -s read-only "${CODEX_PX[@]}" -m "$model" -c "model_reasoning_effort=\"$3\"" \
        -o "$d/answer" - <<<"$p" > "$d/err" 2>&1 8>&- 9>&-); rc=$? ;;
    opencode) (REVIEW_TIMEOUT=$2 ocrun "$d" "$model" "$3" <<<"$p" > "$d/events" 2>/dev/null 8>&- 9>&-); rc=$?
      [ $rc != 0 ] || jq -Rrn "$OPENCODEANSWER" "$d/events" > "$d/answer" 2>/dev/null || rc=1 ;;
    *) rc=1 ;;
  esac
  # Its login failed and the proxy is the builder's fallback: asked again at once through the proxy.
  ! loginfallback "$rc" "$agent" "$d/answer" "$d/err" || { PROXY_NOW=1 askmodel "$@"; return; }
  return $rc
}
# One same-file judgement (overlap()): prints "<card's issue>\t<file>" or NONE, else why not and fails.
overlapcall() { # <issue> <the belt's issues, a JSON array> <open issues json> <the control record>
  local p d rc s a
  p=$OVERLAP$'\n\n'$(jq -r --argjson n "$1" --argjson b "$2" 'def show: "#\(.number) \(.title // "")\n\((.body // "")[0:4000])\n";
    "# The queued issue\n" + (map(select(.number == $n)) | map(show) | join("")) + "\n# The cards on the belt\n" + (map(select(.number | IN($b[]))) | map(show) | join("\n"))' <<<"$3") \
    || { echo "the issues could not be read"; return 1; }
  d=$(mktemp -d) || { echo "no scratch folder"; return 1; }
  if [ -n "${CONVEYOR_OVERLAP_CMD:-}" ]; then
    (cd "$d" && exec timeout --kill-after=10 "$OVERLAP_TIMEOUT" bash -c "$CONVEYOR_OVERLAP_CMD" <<<"$p" > "$d/answer" 2>/dev/null 8>&- 9>&-); rc=$?
  else
    s=$(askmodel "$d" "$OVERLAP_TIMEOUT" low "$4" "$p"); rc=$?
    [ -z "$s" ] || { rm -rf "$d"; echo "$s"; return 1; }
  fi
  # Exactly one line (backticks and spaces around it dropped): NONE, or DEPENDS on a card of the belt and one file.
  a=$(jq -Rrsn --argjson b "$2" 'input | split("\n") | map(gsub("^[[:space:]`*]+|[[:space:]`*]+$"; "") | select(. != ""))
      | select(length == 1) | .[0] | if . == "NONE" then . else capture("^DEPENDS #(?<n>[0-9]+):[[:space:]]*(?<f>[^[:space:]].{0,199})$")
      | select(.n | tonumber | IN($b[])) | "\(.n)\t\(.f)" end' "$d/answer" 2>/dev/null)
  rm -rf "$d"
  [ "$rc" = 0 ] || { echo "exit $rc; 124 is the ${OVERLAP_TIMEOUT}s timeout"; return 1; }
  [ -n "$a" ] || { echo "the answer was not NONE or one DEPENDS line naming a card on the belt"; return 1; }
  printf '%s\n' "$a"
}
