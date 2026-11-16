# SPDX-License-Identifier: Apache-2.0
# The state folders other than ST that an older engine may have written this checkout's card records to, each that
# holds card records, one a line: the checkout's own conveyor/state when the host file names another state folder for
# it, and /conveyor/state, where an engine whose project path came out empty wrote (`//conveyor`). This belt reads
# neither: retry names one that holds a card of the issue it is asked for, and doctor names each.
strays() {
  local s
  for s in "$MAIN/conveyor/state" /conveyor/state; do
    [ -s "$s/cards.jsonl" ] && [ "$(realpath -m -- "$s")" != "$(realpath -m -- "$ST")" ] && printf '%s\n' "$s"
  done
  return 0
}
# Under the lock: every line of the issue's blocked card (of each, when it was blocked more than once) moves from the
# card records to the retried file, so the issue has no card and pick takes it again. A card that ended closed because
# its issue was closed while it was blocked (shut()) counts as blocked. Nothing changes when the issue
# has no card, or a card of it is still open (in flight, or stopped mid-card), has landed (or was pushed) or has closed it,
# or a blocked card's process is still alive. The records are
# rewritten in place, never replaced: the lock is held on the file itself, and a writer waiting for it must find
# the same file when its turn comes.
# A main-red fix card (issue 0, redpick()) is given back by its card id: its lines move out the same way, and the loop
# picks its main commit's entry again, a new card built from nothing.
retry() { # <issue, or the card id of a main-red fix card> [fresh: an issue's next card builds from nothing]
  local n=$1 ends l what k='.issue == $n' a p f
  check || return 1
  # No issue is #0: every main-red fix card is of issue 0, so a retry of it would give back each of them. Said: how to
  # name one, and the blocked ones by card id beside the name they are shown by.
  if [[ $1 =~ ^0+$ ]]; then
    l=$(stdb ask issue cards 0) || return 1
    l=$(jq -rs 'map(select(.step != "push")) | [group_by(.card)[] | select(any(.step == "picked" and (.mainRed | type) == "string") and last.step == "blocked")
      | "\(.[0].card) (Main is red (\(map(.mainRed | strings) | first | .[0:12])))"] | if . == [] then "none is blocked now" else "blocked now: " + join(", ") end' <<<"$l") || return 1
    echo "conveyor: no issue is #0. A main-red fix card, shown as \"Main is red (<commit>)\", has no issue: retry it by its card id, \`conveyor.sh retry <card id>\` ($l); nothing changed" >&2
    return 1
  fi
  if [[ $1 =~ ^[0-9]+$ ]]; then
    what="issue #$1"; a=(--argjson n "$1"); l=$(stdb ask issue cards "$1") || return 1
  else
    what="card $1"; k='.card == $n'; a=(--arg n "$1"); l=$(stdb ask card "$1") || return 1
    [ -z "$l" ] || jq -se 'any(.step == "picked" and .mainRed)' <<<"$l" >/dev/null \
      || { echo "conveyor: card $1 is no main-red fix card: retry takes a card's issue number; nothing changed" >&2; return 1; }
  fi
  # A card with a pushed line has landed, whatever line follows it and whatever their times: its commit is on main.
  ends=$(jq -rs "${a[@]}" --arg shut "$SHUT" "map(select($k))"' | group_by(.card)
    | map(if any(.step == "pushed") then "landed" else map(select(.step | IN("landed", "closed", "blocked"))) | . as $e
        | [range(length) as $i | $e[$i] | select(.step != "blocked" or ($e[$i + 1:] | all(.step == "blocked")))] | last
        | if . == null then "open" elif .step == "closed" and .reason == $shut then "blocked" else .step end end)
    | if length == 0 then "none" elif index("open") then "open" elif index("landed") or index("closed") then "landed" else "blocked" end' <<<"$l") || return 1
  case $ends in
    none) [ "$k" = '.issue == $n' ] || { echo "conveyor: $what has no card; nothing to retry" >&2; return 1; }
      # The state folder read is named, and any other folder (strays) that holds a card of the issue: two commands that
      # disagree on a card have read two folders.
      p=$(strays | while IFS= read -r f; do jq -Rne --argjson n "$n" 'any(inputs | fromjson? | objects; .issue == $n)' "$f/cards.jsonl" >/dev/null 2>&1 && printf ' %s' "$f"; done)
      echo "conveyor: $what has no card in the state folder $ST; nothing to retry.${p:+ A card of it is in another state folder, which an older engine wrote to and this belt does not read:$p (doctor names it).} If the issue is held, release it with \`conveyor.sh control release $n\`, which starts a new card" >&2
      return 1 ;;
    open) echo "conveyor: $what has a card that is still open; nothing changed" >&2; return 1 ;;
    landed) echo "conveyor: $what has a card that landed, or that closed it as already fixed; nothing changed" >&2; return 1 ;;
  esac
  # A blocked card's process can still be ending (stopped by TERM, say): it writes a second blocked line and keeps its
  # change as a patch from its worktree. Its lines moved out and its worktree taken before that, its change was lost
  # (#585). The card's process is the pid (with its start time) of its last worktree line.
  ends=$(jq -rs 'group_by(.card)[] | map(select(.step == "worktree" and (.pid | type) == "number")) | last | select(.)
      | "\(.pid)\t\(.started // "")"' <<<"$l" | while IFS=$'\t' read -r p t; do ! p_alive "$p" "$t" || printf ' %s' "$p"; done) || return 1
  [ -z "$ends" ] || { echo "conveyor: $what has a blocked card whose process is still ending (pid$ends); nothing changed: retry once it has ended" >&2; return 1; }
  # fresh (`retry <issue> --fresh`): the kept work of every blocked card of the issue, this one's and those of earlier
  # retries (prior() reads them all), moves to a dated folder under the state folder, not deleted: its kept folder and
  # a review left beside its worktree. With none of it left, the next card builds from nothing. Done before the lines
  # move out: a move that fails leaves the card blocked.
  if [ -n "${2:-}" ]; then
    local c f d moved=''
    d=$ST/kept-dropped/$(date -u +%Y%m%dT%H%M%SZ)-$n
    ends=$({ printf '%s\n' "$l"; stdb ask issue retried "$n"; } | jq -r 'select(.step == "blocked") | .card' | sort -u) || return 1
    for c in $ends; do
      for f in "$ST/kept/$c" "$CARDS/$c.review"; do
        [ -e "$f" ] || continue
        mkdir -p "$d" && mv "$f" "$d/" || { echo "conveyor: $f could not be moved to $d; $what is still blocked" >&2; return 1; }
        moved=1
      done
    done
  fi
  # The blocked line carries when the owner gave the card back (retriedAt): the wait ends there, not at the next pick.
  MOVETAG='if .step == "blocked" and .retriedAt == null then . + {retriedAt: $at} else . end' moveout "$k" "${a[@]}" || return 1
  echo "conveyor: $what can be picked again; its old lines are in $RETRIED"
  [ "$k" = '.issue == $n' ] || return 0
  [ -z "${2:-}" ] || { echo "conveyor: its next card builds from nothing; $([ -n "$moved" ] && echo "its kept work is in $d" || echo "it had no kept work")"; return 0; }
  p=$(prior "$n"); ends=$(jq -r 'select(.kept != "") | "\(.kept)/\(.card).patch"' <<<"$p")
  [ -n "$ends" ] && [ -s "$ends" ] || return 0
  # A patch stopped for the owner's yes: what card() does with it, by the issue as it is now (keptway()), and by the
  # check card() makes after it: with the rule "visible changes need the owner's yes" off, nothing waits for the yes;
  # on, a yes with a condition has the kept patch reviewed against it with no build.
  if names 2>/dev/null && yeskept "$p" && l=$(gh issue view "$n" --json number,title,body,labels,milestone 2>/dev/null); then
    what=$(keptway "$l" "${ends%.patch}.body")
    if ! yesrule; then [ "$what" != wait ] && [ "$what" != land ] || what=off
    elif [ "$what" = land ] && conditional "$l"; then what=held
    fi
    case $what in
      held) echo "conveyor: its next card reviews the kept patch $ends against $OWNER's yes as the issue now gives it, with no build: the patch lands only after that review"; return 0 ;;
      off) echo "conveyor: its next card lands from the kept patch $ends, with no build and no review while it still applies to main: the rule \"visible changes need the owner's yes\" is off, and the issue is the one its review read"; return 0 ;;
      land) echo "conveyor: its next card lands from the kept patch $ends, with no build and no review while it still applies to main: an approval line has come since its review, and the issue is the one that review read"; return 0 ;;
      wait) echo "conveyor: its next card stops again for $OWNER's yes on the kept patch $ends: the issue is the one its review read, with no approval line since"; return 0 ;;
      review) echo "conveyor: its next card starts from the kept patch $ends, with one session, then a review against the issue as it is now: the issue changed since that patch was reviewed"; return 0 ;;
      build) echo "conveyor: its next card is built from nothing: the issue's section of what customers or staff will see changed since the kept patch $ends was reviewed"; return 0 ;;
    esac
  fi
  echo "conveyor: its next card starts from the kept patch $ends: applied if it still applies to main, brought onto main by a session if not"
}
# Under the lock, at a turn of the loop that found a blocked card's issue closed: a blocked card whose issue is closed
# (among the issue numbers given), for whatever reason, is done waiting on the owner. It ends with a closed line whose
# reason is SHUT, as a card that found its issue already fixed ends closed, so it leaves the blocked and waiting lists
# and pick does not take the issue again from an open list asked before it closed. Its kept work stays where it is:
# Once the issue is opened again, a turn of the loop gives it back as `retry` does (reopened()), the new card starting
# from that work.
# A main-red fix card (issue 0, redpick()), which has no issue to close, is shut by its card id: its main commit then
# starts no card again, and `retry <card id>` gives it back.
SHUT='the issue was closed by hand while the card was blocked'
shut() { # <closed issue numbers, a json array, or the card id of a main-red fix card>
  local closed=$1 c n l t='.[0].issue | IN($closed[])' found=''
  check || return 1
  [[ $1 == '['* ]] || { closed=$(jq -cn --arg c "$1" '$c'); t='.[0].card == $closed and any(.[]; .step == "picked" and .mainRed)'; }
  while read -r c n; do
    l=$(line "$c" "$n" closed ok "$(jq -cn --arg r "$SHUT" '{reason: $r}')") && append "$l" || return 1
    found=1
    if [ "$n" = 0 ]; then echo "conveyor: card $c was shut while it was blocked; the card is closed, and \`retry $c\` takes it again"
    else echo "conveyor: issue #$n was closed while card $c was blocked; the card is closed, its kept work where it was, and the issue is picked again once it is open"; fi
  done < <(jq -rs --argjson closed "$closed" 'map(select(.step != "push")) | group_by(.card)[]
    | select((map(select(.step | IN("landed", "closed", "blocked", "pushed"))) | . as $e
        | [range(length) as $i | $e[$i] | select(.step != "pushed" and (.step != "blocked" or ($e[$i + 1:] | all(.step == "blocked"))))] | last | .step) == "blocked"
      and ('"$t"'))
    | "\(.[0].card) \(.[0].issue)"' < <(stdb ask lines cards))
  [[ $1 == '['* ]] || [ -n "$found" ] || { echo "conveyor: card $1 is no blocked main-red fix card; nothing changed" >&2; return 1; }
}
# At a turn of the loop, outside the lock: an issue of the open list given whose newest card was shut (above) is given
# back with `retry` (under the lock) once GitHub says the issue itself is open: a stale open list alone gives nothing
# back. Its lines move to the retried file and its next card starts from the kept work. An issue with a card that
# landed, was pushed or closed it as already fixed is not asked: its work is on main, and retry refuses it. retry
# also leaves a card whose process is still ending; a later turn gives it back once that process has ended.
reopened() { # <open issues, a json list>
  local n t
  while read -r n; do
    t=$(timeout 20 gh issue view "$n" --json closed 2>/dev/null | jq -r '.closed' 2>/dev/null) || t=''
    [ "$t" != false ] || { locked retry "$n"; stdbkeeps; } || true
  done < <(jq -rs --arg shut "$SHUT" --argjson open "$1" 'map(select(.step != "push")) | group_by(.issue)[]
    | select((.[0].issue | IN($open[].number)) and all(.step != "landed" and .step != "pushed" and (.step != "closed" or .reason == $shut)))
    | group_by(.card) | max_by(.[0].time) | select(any(.step == "closed" and .reason == $shut)) | .[0].issue' < <(turncards) 2>/dev/null)
}
# At a turn of the loop, outside the lock: an issue of the open list given whose newest card stopped for the owner's
# yes is given back with `retry` (under the lock) once its body, as the list has it, holds more approval lines than
# the body that card's review read (the .body file it kept: keptway()): a line added after the stop. The next card
# then takes up the kept patch as `retry` would have it. A card that kept no body is left for `retry`.
approved() { # <open issues, a json list>
  local n c k
  [ -n "${YES:-}" ] || return 0
  while read -r n c k; do
    jq -en --argjson open "$1" --argjson n "$n" --slurpfile was "$ST/$k/$c.body" "$SEE"'
      ($open | map(select(.number == $n)) | first) as $now | $now != null and ($was[0] | type) == "object"
      and ($now | approvals) > ($was[0] | approvals)' >/dev/null 2>&1 || continue
    { locked retry "$n"; stdbkeeps; } || true
  done < <(jq -rs --arg yes "$YES" --argjson open "$1" 'map(select(.step != "push")) | group_by(.issue)[]
    | select((.[0].issue | IN($open[].number)) and all(.step != "landed" and .step != "pushed" and .step != "closed"))
    | group_by(.card) | max_by(.[0].time) | map(select(.step == "blocked")) | last | select(. != null)
    | select((.reason | startswith($yes)) and (.kept // "") != "") | "\(.issue) \(.card) \(.kept)"' < <(turncards) 2>/dev/null)
}
# At a turn of the loop, outside the lock: an issue of the open list given whose newest card was blocked by a session
# or review that never began its work (nostart(): its spent names the seat, CLI, model and account it ran on) is given
# back with `retry` (under the lock) once a check session starts (startcheck()) on its seat's CLI and model as set now
# (startnow(): a model changed since is the one checked), a login made since, say. Once
# only (startonce()). The checks start API_PAUSE after the block at the soonest, and at most once every API_PAUSE
# ($ST/startcheck holds when the last ones ran), one for each CLI, model and account.
startagain() { # <open issues, a json list>
  local n s last ok
  declare -A tried=()
  last=$(cat "$ST/startcheck" 2>/dev/null); [[ $last =~ ^[0-9]+$ ]] || last=0
  jq -en --argjson l "$last" --argjson p "$API_PAUSE" '$l + $p <= now' >/dev/null 2>&1 || return 0
  while IFS=$'\t' read -r n s; do
    startonce "$n" && s=$(startnow "$s") || continue
    [ -n "${tried[$s]+1}" ] || { echo "$EPOCHSECONDS" > "$ST/startcheck"; if startcheck "$s"; then tried[$s]=1; else tried[$s]=''; fi; }
    ok=${tried[$s]}; [ -n "$ok" ] || continue
    echo "conveyor: a check session on $(jq -r '"\(.cli) \(.model)"' <<<"$s") started: issue #$n, whose card was blocked before its session began its work, is put back"
    { locked retry "$n"; stdbkeeps; } || true
  done < <(jq -rs --argjson open "$1" --argjson p "$API_PAUSE" 'map(select(.step != "push")) | group_by(.issue)[]
    | select((.[0].issue | IN($open[].number)) and all(.step != "landed" and .step != "pushed" and .step != "closed"))
    | group_by(.card) | max_by(.[0].time) | map(select(.step == "blocked")) | last | select(. != null)
    | select((.spent.start | type) == "object" and (try (.time | fromdate) catch now) + $p <= now) | "\(.issue)\t\(.spent.start | tojson)"' < <(turncards) 2>/dev/null)
}
# Under the lock, at `control resume` (the Board's Resume too), as a sign-in failure paused the loop (signinpause()):
# each issue whose newest card was blocked by a session whose sign-in failed (nostart(): its spent's start has signin) is given back with
# `retry`, once (startonce()). What retry says goes to stderr: control prints the record alone.
signinback() {
  local n
  while read -r n; do ! startonce "$n" || retry "$n" >&2 || true; done < <(stdb ask lines cards | jq -rs 'map(select(.step != "push")) | group_by(.issue)[]
    | select(all(.step != "landed" and .step != "pushed" and .step != "closed"))
    | group_by(.card) | max_by(.[0].time) | map(select(.step == "blocked")) | last | select(.spent.start.signin? == true) | .issue' 2>/dev/null)
}
# Under the lock: the lines the jq test picks (asked of each record, with the jq arguments given) move from the card
# records to the retried file; MOVETAG, when set, is a jq filter each moved line goes through ($at: now).
moveout() { # <jq test> <jq arguments>...
  local t=$1; shift
  # The records as the state database (state.py) holds them, read once; both files are written through it.
  stdb ask -o "$STATE.all" lines cards \
    && { if [ -n "${MOVETAG:-}" ]; then jq -c "$@" --arg at "$(date -u +%FT%TZ)" "select($t) | $MOVETAG" "$STATE.all"; else jq -Rr "$@" "select(fromjson | $t)" "$STATE.all"; fi; } > "$STATE.moved" \
    && jq -Rr "$@" "select(fromjson | $t | not)" "$STATE.all" > "$STATE.rest" \
    || { rm -f "$STATE.all" "$STATE.moved" "$STATE.rest"; echo "conveyor: cannot read the card records; nothing changed" >&2; return 1; }
  rm -f "$STATE.all"
  # Both files change under the one lock a snapshot's copy takes (snapcopy), so it never holds a moved line twice.
  ( flock 5 || exit 1; stdb append retried < "$STATE.moved" || exit 1; stdb rewrite cards < "$STATE.rest" || exit 2 ) 5>>"$STATE.checked.lock"
  case $? in 0) ;; 1) rm -f "$STATE.moved" "$STATE.rest"; echo "conveyor: cannot write $RETRIED; the card records are unchanged" >&2; return 1 ;; *) false ;; esac || { echo "conveyor: the card records were not rewritten whole; what they held is in $STATE.rest, and the moved lines are in $RETRIED" >&2; return 1; }
  rm -f "$STATE.moved" "$STATE.rest"
}

# The kept work of the issue's blocked cards that `retry` gave back, as {card, kept, reason, review}: the last card
# that holds a kept patch (card is "" when none does), and the last kept review, which may be a later card's.
# Nothing when there is neither. Not simply the last blocked card: a retry that blocks before it takes up the kept
# work (its worktree could not be made, its dependencies not linked) keeps nothing, and the work is still there.
# A review that block() could not move into the kept folder is still beside the card's worktree, whether or not the
# line names a folder: it is read there, before the kept folder, since it is there only when the move failed.
prior() { # <issue>
  local l k c patch='' rev=''
  while IFS= read -r l; do
    k=$(jq -r .kept <<<"$l"); c=$(jq -r .card <<<"$l")
    [ -z "$k" ] || [ ! -f "$k/$c.patch" ] || [ ! -s "$k/$c.patch" ] || patch=$l
    if [ -f "$CARDS/$c.review" ] && [ -s "$CARDS/$c.review" ]; then rev=$CARDS/$c.review
    elif [ -n "$k" ] && [ -f "$k/$c.review" ] && [ -s "$k/$c.review" ]; then rev=$k/$c.review; fi
  done < <(jq -c --argjson n "$1" --arg st "$ST" 'select(.issue == $n and .step == "blocked") | {card, kept: (.kept // "" | if . == "" then . else $st + "/" + . end), reason}' < <(stdb ask issue retried "$1" 2>/dev/null) 2>/dev/null)
  [ -n "$patch$rev" ] || return 0
  jq -cn --argjson p "${patch:-null}" --arg r "$rev" '{card: ($p.card // ""), kept: ($p.kept // ""), reason: ($p.reason // ""), review: $r}'
}
# Whether the kept patch of prior() ($1) is one card() would land with no build and no review: its card stopped for
# the owner's yes after a review of that patch (the kept review is that card's own) that gave a verdict and said
# whether the change is visible.
yeskept() { # <prior json>
  local from was rev
  from=$(jq -r .card <<<"$1"); was=$(jq -r .reason <<<"$1"); rev=$(jq -r .review <<<"$1")
  [ -n "$from" ] && [[ $was == "$YES"* ]] && { [ "$rev" = "$(jq -r .kept <<<"$1")/$from.review" ] || [ "$rev" = "$CARDS/$from.review" ]; } \
    && [ -s "$rev" ] && [ "$(verdict "$rev")" != none ] && [ -n "$(visible "$rev" any)" ]
}
# How the next card takes up such a kept patch, from the issue as it is now ($1, its json) and the issue as the
# review of that patch read it (the .body file its card kept when it stopped for the yes, $2). Approval lines aside:
# land: the body is the one the review read and an approval line has come since; wait: nothing has changed, and the
# card stops again for the yes (no build and no review); review: the body changed, or cannot be compared, with the
# same section of what customers or staff will see, so the patch is built on and reviewed against the issue as it
# is now; build: that section changed, so the issue asks for another change and the card is built from nothing.
keptway() { # <issue json> <kept body file>
  local was
  was=$(jq -ce 'objects' "$2" 2>/dev/null) || { echo review; return 0; }
  jq -rn --argjson now "$1" --argjson was "$was" "$SEE"'
    def asks: [.body // "" | splits("\r?\n") | select(startswith("Visible change approved:") | not) | sub("\\s+\\z"; "") | select(. != "")];
    if ($now | section) != ($was | section) then "build" elif ($now | asks) != ($was | asks) then "review"
    elif ($now | approvals) > ($was | approvals) then "land" else "wait" end'
}
# The approval lines an issue saying nothing visible changes had when its last card stopped for the owner's yes,
# as the .approvals file of its newest blocked card that kept one says; nothing when none did.
yesbase() { # <issue>
  local f v=''
  while IFS= read -r f; do [ ! -s "$f" ] || v=$(head -n 1 "$f"); done \
    < <(jq -r --argjson n "$1" --arg st "$ST" 'select(.issue == $n and .step == "blocked" and (.kept // "") != "") | "\($st)/\(.kept)/\(.card).approvals"' < <(stdb ask issue retried "$1" 2>/dev/null) 2>/dev/null)
  printf '%s' "$v"
}
# What the brief of a retried issue's card carries: the findings of the review now beside the worktree (the
# blocked card's last one, put there by card()) and the finding of every follow-up withdrawn for the issue.
# Every finding is carried, none cut: when they are too many for a brief (a prompt must not grow without bound), the
# brief holds the first of them, whole lines, and names the file beside the worktree that holds them all.
# The withdrawn follow-ups are read from two places, each once (by issue number): the .withdrawn files of the issue's
# blocked cards, and GitHub, for an issue that `retry` gave back: withdrawn() below. The files alone miss a follow-up
# withdrawn before they were written (withdrawn and closed as "completed") or on another machine.
# When GitHub does not answer, the brief says the list may be short and where to look.
carried() { # <issue> <worktree>
  local f w k g='' miss='' all head max=60000 old
  f=$(grep -Ev "$NOTFINDING" "$2.review" 2>/dev/null)
  old=$(stdb ask issue retried "$1" 2>/dev/null)
  w=$(jq -r --argjson n "$1" --arg st "$ST" 'select(.issue == $n and .step == "blocked" and (.kept // "") != "") | "\($st)/\(.kept)/\(.card).withdrawn"' <<<"$old" 2>/dev/null \
    | while IFS= read -r k; do cat "$k" 2>/dev/null; done)
  if jq -es --argjson n "$1" 'any(.issue == $n)' <<<"$old" >/dev/null 2>&1; then
    g=$(withdrawn "$1") || { g=''; miss=$'\n## The withdrawn follow-ups of this issue could not be read from GitHub\nThe list here may be short. Look for them yourself before you change anything: the closed issues labelled '"$FOLLOWUP"$' whose body starts "Follow-up to #'"$1"$' (", each with a `Finding:` line.\n'; }
    w=$(printf '%s\n%s\n' "$w" "$g" | awk 'NF && !seen[$1]++')
  fi
  [ -n "$f$w$miss" ] || return 0
  all=$(printf '# Findings carried over from the blocked cards of this issue\nThe change for this issue must not have these problems. Nothing else holds them now: fix each one, or leave it fixed.\n'
    [ -z "$f" ] || printf '\n## The last review of the blocked card\n%s\n' "$f"
    [ -z "$w" ] || printf '\n## Follow-ups that were filed for a finding and withdrawn when the card did not land\n%s\n' "$w"
    printf '%s' "$miss")
  [ ${#all} -gt $max ] || { printf '%s\n' "$all"; return 0; }
  head=${all:0:max}; head=${head%$'\n'*}
  if printf '%s\n' "$all" > "$2.carried"; then
    printf '%s\n\n## The list above is cut short: it is too long for this brief\nAll of it, %s lines, is in the file %s. Read that whole file, in parts, before you change anything: every finding in it counts, not only the ones above.\n' "$head" "$(wc -l < "$2.carried")" "$2.carried"
  else
    printf '%s\n\n## The list above is cut short: it is too long for this brief\nThe whole list could not be written to %s. The rest is in the .review and .withdrawn files of the blocked cards of this issue, in the folders under %s: read them before you change anything.\n' "$head" "$2.carried" "$ST/kept"
  fi
}

# The follow-ups withdrawn for an issue, as GitHub holds them, one line each: `#<follow-up> <its finding>`. Such a
# follow-up is closed, labelled conveyor-followup, its body starts "Follow-up to #<issue> (" (followups() wrote it)
# and no card of its own landed it or closed it as already fixed (a card shut() closed fixed nothing): nothing fixed its finding, however it was closed
# (a withdrawn follow-up once closed as "completed"). Exit 1 when GitHub or the card records do not answer.
withdrawn() { # <issue>
  local out cards
  out=$(timeout 60 gh issue list --state closed --limit 1000 --json number,title,body --label "$FOLLOWUP" --search "\"Follow-up to #$1\" in:body" 2>/dev/null) || return 1
  cards=$(stdb ask lines cards 2>/dev/null) || return 1
  jq -r --argjson n "$1" --arg shut "$SHUT" --slurpfile cards <(printf '%s\n' "$cards") '($cards | map(select((.step == "landed" or .step == "closed" and .reason != $shut)) | .issue)) as $done
    | sort_by(.number)[] | select((.body // "" | startswith("Follow-up to #\($n) (")) and (.number | IN($done[]) | not))
    | "#\(.number) \((.body | capture("(^|\n)Finding: (?<f>[^\n]*[^[:space:]])").f) // .title)"' <<<"$out" 2>/dev/null
}

# Test files: the one place that says which paths are the project's tests. A path one of the pack's tests.patterns
# matches (TESTRX, made by names(); the schema's default when the pack sets none) is a test file. Of the paths on stdin
# (one a line; with -z, each ended by a NUL), prints those that are test files; with -v, those that are not. Every
# line is read, so a pipe into it never ends early. TESTRX is the one names() made last, as PRODUCT is (a pack a card
# changed counts from the loop's next turn); with none made yet, names() makes it here. Fails when the pack cannot be
# read.
testpaths() { # [-v] [-z]
  [ -n "${TESTRX:-}" ] || names || { cat > /dev/null; return 1; }
  grep -E "$@" -e "$TESTRX" || :
}
# Product code: the one place that says which paths count. A file under one of the pack's productPaths
# (PRODUCT, made by names()) is product code, its tests (testpaths()) aside. Both product() and the visible-change check
# ask this of a list of paths (one per line, on stdin); every line is read, so a pipe into it never ends early.
productpaths() { [ "$(testpaths -v | grep -Ec "$PRODUCT")" != 0 ]; }
# Did this commit change product code (tests aside)?
product() { git show --name-only --format= "$1" 2>/dev/null | productpaths; }

ghok() { if [ -n "$GITHUB" ]; then [ "$(cat "$GITHUB/gh" 2>/dev/null)" = true ]; else timeout 20 gh auth status >/dev/null 2>&1; fi; }
# Every JSON and GraphQL string escape (\uXXXX, \u{X...}, \n, \/ ...) decoded, again on each result until nothing is
# left to decode; one line per decoding that changed the text. A high and low surrogate \uXXXX pair decodes as the one
# character it names, as JSON parsers read it; any other code point that is not a character decodes as U+FFFD.
UNESCAPE='def hex: ascii_downcase | explode | reduce .[] as $d (0; . * 16 + (if $d >= 97 then $d - 87 else $d - 48 end));
  def ch: if . > 1114111 or (. >= 55296 and . < 57344) then "\ufffd" else [.] | implode end;
  def dec: gsub("\\\\(?:u\\{(?<b>[0-9A-Fa-f]+)\\}|u(?<p>[dD][89abAB][0-9A-Fa-f]{2})\\\\u(?<q>[dD][c-fC-F][0-9A-Fa-f]{2})|u(?<h>[0-9A-Fa-f]{4})|(?<c>[^u]))";
    if .b then .b | hex | ch elif .p then (.p | hex) as $p | .q | hex | 65536 + ($p - 55296) * 1024 + . - 56320 | ch
    elif .h then .h | hex | ch else .c as $c | {n: "\n", t: "\t", r: "\r", b: "\b", f: "\f"}[$c] // $c end);
  def go: dec as $d | if $d == . then empty else $d, ($d | go) end; go'
# Every GitHub write the engine and the Board make (`gh-write`) goes through here (plan section 8, P5): a test fails on
# a gh write anywhere else. The state and cards folders are written as <state> and <cards>, and kept work as
# <state>/kept, never as absolute paths. The text (every argument, and every file gh would read: --body-file, -F,
# --input, or api's -F/--field <key>=@<file>, in each of their forms: -F <x>, -F<x>, -F=<x>, -wF <x>, --field=<x>,
# --input=<x>; - is standard input; and all of it again with its string escapes decoded) is checked by
# privacy/check.sh, with the terms file the host file names (terms; ~/ is the user's home); a file that cannot be read
# posts nothing. The terms file is optional: with no host file, or one that names none, the check runs with no word
# list. With the pack's
# privacy.mode public, a hit, or a terms file named and not readable (or a host file that does not read, which may
# name one), posts nothing: the text is kept in <state>/privacy/, the
# reason goes to stderr, and it returns 3. With private, a hit is a warning on the engine's own stderr (LOGFD, which a
# caller's redirection does not hide), and the text is posted.
# The argument after one of GHVALUE (a gh option that takes the next argument as its value) is that value, never a
# flag. GHVALUE holds the options that take a value in every gh write command; ghvalue adds those whose name
# is a switch in another command (pr review's --comment, -c, -a; pr merge's -m). A switch named as a value option would
# hide a real -F after it from the check, so an option goes in only for the commands where gh says it takes a value.
# A group of short options is read as gh reads it: letter by letter, the first F or value option takes the rest of
# the group (an = first is dropped), or the next argument when the group ends with it (-cb <text>, -wF <file>).
GHVALUE='--body --title --label --reason --assignee --milestone --project --repo --template --base --head
  --reviewer --add-label --remove-label --add-assignee --remove-assignee --add-project --remove-project --add-reviewer
  --remove-reviewer --method --raw-field --header --jq --subject --duplicate-of -b -t -l -R -T -B -H -X -q'
GHVALUE=${GHVALUE//$'\n'/ }
# The command is the first two arguments that are not options; an option before it (--repo o/r issue close) is skipped
# with its value, so the command's own value options still apply.
ghcmd() { # <gh arguments>: the command's two names, space-separated
  local a skip='' w=()
  for a; do
    if [ -n "$skip" ]; then skip=''
    elif [[ $a == -* ]]; then [[ " $GHVALUE " != *" $a "* ]] || skip=1
    else w+=("$a"); [ ${#w[@]} -lt 2 ] || break; fi
  done
  printf '%s %s' "${w[0]:-}" "${w[1]:-}"
}
ghvalue() { # <gh arguments>: the value options of this command, space-separated
  local more=''
  case "$(ghcmd "$@")" in
    "issue close") more='--comment -c -r' ;;
    "issue reopen"|"pr close"|"pr reopen") more='--comment -c' ;;
    "issue create"|"issue new") more='-a -m -p' ;;
    "pr create"|"pr new") more='-a -m -p -r' ;;
    "issue edit"|"pr edit") more='-m' ;;
    "pr merge") more='--author-email -A' ;;
    "label create"|"label edit") more='--color --description --name -c -d -n' ;;
    "api "*) more='--preview -f -p' ;;
  esac
  printf ' %s %s ' "$GHVALUE" "$more"
}
# The terms file the host file names (terms; ~/ is the user's home), when it can be read; nothing otherwise.
termsfile() {
  local t
  t=$(jq -r '.terms // empty' "$HOST" 2>/dev/null); [[ $t != "~/"* ]] || t=$HOME/${t#"~/"}
  [ -r "$t" ] && [ ! -d "$t" ] && printf '%s' "$t"
}
# Whether the host file may name a terms file: 1 only when there is no host file or it is an object with no terms.
termsnamed() { [ -e "$HOST" ] && ! jq -e 'type == "object" and (.terms // "") == ""' "$HOST" >/dev/null 2>&1; }
gh_write() { # <gh arguments>
  local a st d h mode terms hits rc pre src v fld i c w want='' n=0 args=() val cmd ended=''
  val=$(ghvalue "$@"); cmd=$(ghcmd "$@")
  st=${STATE%/*}; d=$st/privacy; h=$d/$(date -u +%Y%m%dT%H%M%SZ)-$$-$RANDOM.txt
  mkdir -p "$d" && : > "$h" && packget privacy.mode mode || { echo "conveyor: privacy: the check could not be made; nothing posted" >&2; return 3; }
  for a; do
    pre='' src='' v='' fld=''; n=$((n + 1)); w=${ended:-$want}; want=''
    case $w in # what the argument before left this one to be
      src) src=$a ;;
      F) v=$a ;;
      field) v=$a fld=1 ;;
      text) ;; # literal text, though it starts with -F or --body-file=
      *) if [ "$a" = -- ]; then ended=text # as gh reads it: every argument after -- is literal text, not an option
         elif [[ $a == --body-file || $a == --input ]]; then want=src
         elif [ "$a" = --field ]; then want=field
         elif [[ $a == --body-file=* || $a == --input=* ]]; then pre=${a%%=*}=; src=${a#*=}
         elif [[ $a == --field=* ]]; then pre=--field=; v=${a#--field=} fld=1
         elif [[ $a == --* ]]; then [[ $val != *" $a "* ]] || want=text
         elif [[ $a =~ ^-[[:alpha:]] ]]; then
           for ((i = 1; i < ${#a}; i++)); do
             c=${a:i:1}; [[ $c == [[:alpha:]] ]] || break
             if [ "$c" = F ]; then
               pre=${a:0:i+1}; v=${a:i+1}; [[ $v != =* ]] || { pre+='='; v=${v#=}; }
               [ "$pre" != "$a" ] || want=F; break
             elif [[ $val == *" -$c "* ]]; then [ $((i + 1)) != ${#a} ] || want=text; break; fi
           done
         fi ;;
    esac
    if [ -n "$v" ]; then # -F's value: a file to gh issue/pr; to api, <key>=@<file> reads one
      if [[ $cmd != "api "* ]] && [ -z "$fld" ]; then src=$v
      elif [[ $v == *=@* ]]; then pre=$pre${v%%=@*}=@; src=${v#*=@}; else pre=''; fi
    fi
    if [ -n "$src" ]; then
      if [ "$src" = - ]; then a=$(cat; echo .); else a=$(cat -- "$src" && echo .); fi \
        || { echo "conveyor: privacy: $src cannot be read; nothing posted" >&2; rm -f "$h".body.*; return 3; }
      a=${a%.}; a=${a//"$CARDS"/<cards>}; a=${a//"$st"/<state>}
      printf '%s' "$a" > "$h.body.$n" || return 3; args+=("$pre$h.body.$n")
    else a=${a//"$CARDS"/<cards>}; a=${a//"$st"/<state>}; args+=("$a"); fi
    printf '%s\n' "$a" >> "$h"
  done
  # GitHub decodes escapes in what it posts: JSON's in api's --input, then GraphQL's in a query, so "\/home" and
  # "\\u002fhome" post /home. The raw text alone misses that: each decoding, until none is left, is checked as well.
  jq -Rrs "$UNESCAPE" "$h" > "$h.body.dec" && cat "$h.body.dec" >> "$h" \
    || { echo "conveyor: privacy: the check could not be made; nothing posted" >&2; rm -f "$h".body.*; return 3; }
  terms=$(termsfile)
  if [ "$mode" = public ] && [ -z "$terms" ] && termsnamed; then hits="the host file's terms file cannot be read"
  else hits=$("$HERE/privacy/check.sh" ${terms:+--terms "$terms"} "$h"); [ $? -le 1 ] || hits="the privacy check failed"; hits=${hits//"$h:"/line }; fi
  hits=${hits//$'\n'/; }
  if [ -n "$hits" ] && [ "$mode" = public ]; then
    rm -f "$h".body.*; echo "conveyor: privacy: nothing posted; the text is kept at <state>/privacy/${h##*/}: $hits" >&2; return 3
  fi
  [ -z "$hits" ] || echo "conveyor: privacy warning (the pack's privacy.mode is private, so it was posted): gh ${args[*]:0:3}: $hits" >&"$LOGFD"
  timeout 60 gh "${args[@]}"; rc=$?
  rm -f "$h" "$h".body.*; return $rc
}
# github <folder> -- the GitHub reads of a snapshot, each written whole into the folder for `watch`: issues (the
# open issues with the snapshot's fields; no file when gh did not list them, so the queue is not read, as it would not
# be), labelled, and gh (true or false). It also keeps the host's report of its CLIs and their models (hostclis()).
github() {
  local d=$1 i
  if i=$(openissues "$FIELDS" 2>/dev/null); then printf '%s\n' "$i" > "$d/issues.new" && mv -f "$d/issues.new" "$d/issues"
  else rm -f "$d/issues"; fi
  labelled > "$d/labelled.new" && mv -f "$d/labelled.new" "$d/labelled"
  { ghok && echo true || echo false; } > "$d/gh.new" && mv -f "$d/gh.new" "$d/gh"
  # On this slower timer too, never in a snapshot the feed builds: the CLIs' models, read again once the host's report
  # is CLI_TTL old (a snapshot with no feed reads them itself, as it reads GitHub).
  hostclis due >/dev/null 2>&1 || :
}

# Every open issue, with the fields asked for.
# When each open awaiting-deploy issue last got that label: {"<number>": <time>}, from one GraphQL question (the issue
# list does not say when a label was added). {} when GitHub does not answer: the snapshot then gives since as null.
labelled() {
  [ -z "$GITHUB" ] || { cat "$GITHUB/labelled" 2>/dev/null || echo '{}'; return 0; }
  gh api graphql -F owner='{owner}' -F repo='{repo}' -f label="$BUILT" -f query='query($owner: String!, $repo: String!, $label: String!) {
    repository(owner: $owner, name: $repo) { issues(labels: [$label], states: OPEN, first: 100) { nodes { number
      timelineItems(itemTypes: [LABELED_EVENT], last: 100) { nodes { ... on LabeledEvent { createdAt label { name } } } } } } } }' 2>/dev/null \
    | jq -ce --arg l "$BUILT" '[.data.repository.issues.nodes[] | {key: (.number | tostring), value: ([.timelineItems.nodes[] | select(.label.name == $l) | .createdAt] | max)}
        | select(.value)] | from_entries' 2>/dev/null || echo '{}'
}

openissues() { # <json fields> [gh issue list arguments]
  local out f=$1 lim=1000; shift
  [ -z "$GITHUB" ] || { [ -s "$GITHUB/issues" ] && cat "$GITHUB/issues"; return; }  # the snapshot's fields, as `github` kept them
  while :; do # a full page means there may be more: ask again for ten times as many until the answer is short
    out=$(gh issue list --state open --limit "$lim" --json "$f" "$@") || { echo "conveyor: gh issue list failed" >&2; return 1; }
    [ "$(jq length <<<"$out")" -ge "$lim" ] || break; lim=$((lim * 10))
  done
  farstates "$out"
}
# The open issues given, each whose `Depends on:` lines name an issue of another repository (owner/repo#N, farneeds
# in DEPS) with far: {"owner/repo#N": {open}}, its state asked with `gh issue view --repo`. One that cannot be read (no
# access, not found, gh failing) is {open: true, error: what gh said}: the issue waits, and Needs you names it.
farstates() { # <open issues json>
  local refs r out st e s='{}'
  refs=$(jq -r "$DEPS"'[.[] | farneeds[]] | unique[]' <<<"$1") || return 1
  [ -n "$refs" ] || { printf '%s\n' "$1"; return; }
  e=$(mktemp) || return 1
  while IFS= read -r r; do
    # stdout alone is the answer: gh may write a notice to stderr even when it answers.
    if out=$(timeout 30 gh issue view "${r##*#}" --repo "${r%#*}" --json state 2>"$e") && st=$(jq -er '.state | strings' <<<"$out" 2>/dev/null); then
      s=$(jq -c --arg r "$r" --arg st "$st" '.[$r] = {open: ($st | IN("CLOSED", "MERGED") | not)}' <<<"$s")
    else
      out=$(tr '\n' ' ' < "$e"); s=$(jq -c --arg r "$r" --arg e "${out:0:300}" '.[$r] = {open: true, error: ($e | if test("^\\s*$") then "gh gave no answer" else sub("\\s+$"; "") end)}' <<<"$s")
    fi || { rm -f "$e"; return 1; }
  done <<<"$refs"
  rm -f "$e"
  jq -c --argjson s "$s" "$DEPS"'map(([farneeds[] | {key: ., value: $s[.]}] | from_entries) as $f | if $f == {} then . else .far = $f end)' <<<"$1"
}
# The open issues as a pick reads them, asked of GitHub now and kept in ISSUES for the minute's sample.
asked() {
  local i; i=$(openissues "$FIELDS") || return 1
  { printf '%s\n' "$i" > "$ISSUES.new" && mv -f "$ISSUES.new" "$ISSUES"; } 2>/dev/null
  printf '%s\n' "$i"
}
