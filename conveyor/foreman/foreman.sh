#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# foreman.sh setup | launch [--new] [<claude argument>...] | claim <session id> | ask <repo> <command> [<argument>...] | off | start | rules | words | live | filing | filed --
# Foreman mode (plan docs/plans/conveyor-plugin-2026-11-10.md, section 11b). The Foreman is a Claude session in a
# project's main checkout that watches that project's Conveyor (or its group's: lib.sh mine) and brings the owner
# what needs them: it files issues,
# clears blocked cards and takes every decision to the owner; it builds nothing itself. Its hooks are the plugin's own
# (hooks/hooks.json, run in every session through the shim): start and waiter.sh --start (asyncRewake, run as
# CONVEYOR_WAITER_START=1) at SessionStart; stop.sh state, stop.sh reply and
# waiter.sh (asyncRewake) at Stop; waiter.sh --check after each prompt and each tool call, which starts the waiter
# again when none runs; filing before a Bash call and filed after it, failed or not (each through filing-hook.sh,
# which ends at once, with no shim, for a command that files no issue). Each stands down in
# any session but the Foreman's (lib.sh foreman).
# setup (`conveyor.sh setup --foreman`, re-runnable; CONVEYOR_MAIN names the main checkout): checks the host file's
#   records, makes this project's Foreman's folder ($FD: `foreman` in its state folder, a group's in its first
#   project's) with an empty state.md when it has none, and writes $FD/settings.json, the launcher's settings: its
#   environment (CONVEYOR_FOREMAN=1, the folder, the 1-hour prompt cache; the launcher sets the main checkout it runs
#   in, as a group's Foreman may run in any of its projects). Written whole each run, so a second run leaves the same
#   file. Into the checkout it writes only env.CLAUDE_CODE_PROMPT_CACHE_TTL=1h in .claude/settings.local.json (other
#   keys kept; a file that is not a JSON object left as it is), so a claimed Foreman's session restarted there gets
#   the 1-hour cache; the claim says when its session runs with another. Another project's Foreman is set up by the
#   same command there.
# launch [--new] (`conveyor.sh foreman`): runs `claude` in the main checkout with those settings and
#   CONVEYOR_FOREMAN=1, resuming the marked session (`--resume <id>`) while its transcript exists; --new starts fresh.
# claim <session id> (/conveyor-belt:foreman, with the session's own id): makes that session the Foreman, one per
#   project or group (lib.sh claim), says so in one line, then gives the session what start gives it. off (/conveyor-belt:foreman
#   off): ends the role.
# words (UserPromptSubmit): the owner asks for the role in words, a prompt that is only "start your role" or "you are
#   the Foreman" (any case, a closing . or !): in a session in a project's main checkout (one with a pack,
#   .conveyor/project.json; never a worktree, as a card's), it claims the role as claim does, and tells the session to
#   reply with the claim's first line (and its line on a prompt cache time other than 1h). Any other prompt, or the
#   words anywhere else, does nothing.
# start (SessionStart): in the launcher's session (CONVEYOR_FOREMAN=1), at its first start, fresh or resumed, first
#   marks it the Foreman. A resumed session given a new id whose transcript is the Foreman session's takes the mark
#   over, unless it is a session that lost the role; so does the new session a /clear starts in the Foreman's own
#   Claude Code process (cleared_). Then, for the
#   Foreman session only, the Foreman's rules (with auto's rules and the standing kinds of routine
#   yes each record's pack turns on, asked of the record: `conveyor.sh auto standing`), then its saved state: the DONE items of state.md archived
#   (archive.py), a warning line when the project runs an old engine here (`conveyor.sh take stale`), a live summary
#   built fresh (never saved), then state.md, cut to its cap.
# start --rules-apart: the start without rules.md (see rules); the plugin's hook passes it. An engine from before the
#   rules hook ignores it and puts rules.md before the rest when the whole fits, or a Read line in its place when it does
#   not; a start without it here puts rules.md after the rest, cut to what the limit leaves.
# rules (SessionStart, a hook of its own): in the Foreman session only, this project's $FD/rules.md, under RULES_LIMIT, cut at
#   a whole line with a Read line when it is longer; any other session gets nothing. claim prints it in a session already running.
#   A session that was the Foreman and no longer is gets one line saying so, once, shown to the owner (systemMessage).
#   Any other new session (source startup) in a project's main checkout (inmain; never a worktree, as a card's, a
#   lane's or a reviewer's, nor a session with CONVEYOR_CARD or CONVEYOR_LANE set) takes the role by itself (auto):
#   when no session is marked, or the marked one is gone (running), it claims it and says so in one line; when a live
#   session holds it, it claims nothing and is told to ask the owner by the picker, as its first act, whether to take
#   it over ("Take over" runs the claim; "Leave it" leaves it a normal session, not asked again in it).
# live: the live summary, at most 1500 bytes of whole lines, apart from unavailable lines, which always print: for each of the Foreman's records (mine), its Conveyor snapshot (one read of it, not health and the cards: its time is on the first line; loop, state, in
#   flight, blocked, waiting on the owner's yes, after a card or before its build, push), and the open decisions of
#   each of those records' ledgers (.claude/metrics/decisions.jsonl in its main checkout, where its sessions' decision
#   hooks write; in this checkout for a record matched by its repository whose main is on another machine: lib.sh
#   ledger), newest first: a group's Foreman claimed in any of its checkouts sees every project's, and no other
#   project's. A source that cannot be read is one "unavailable" line saying why, which always prints: no stale or
#   guessed value.
# filing (PreToolUse, Bash) and filed (PostToolUse and PostToolUseFailure, Bash): an issue the Foreman files (a
#   command holding `issue create` or `issue new`: gh's, or the engine's gh-write) starts held, so nothing it files is
#   built before the owner's yes; the Foreman releases it (conveyor.sh control release) once the owner says yes.
#   filing, before the command runs, sets every record whose new issues start in the queue to start them held
#   (another project's too, as the command may file there) (conveyor.sh control start held), so an issue is held from its first sight, however long the command runs on;
#   when a record cannot be set, or the command is to run in the background, the command is refused. filed holds every
#   issue the command's output links (github.com/<owner>/<name>/issues/<n>) in the record whose main checkout's GitHub
#   repository is <name>, else the record named <name>, letter case aside (lib.sh record_of; filing needs no lookup,
#   as it sets every record), unless it was released or held already (conveyor.sh control adopt; control hold in a record whose engine has no adopt), so a
#   release given before filed runs stays, and tells the Foreman only those it holds; then it sets back to
#   the queue each record a filing set to held, once no other filing, of any Foreman, is in flight (SF, below), which
#   holds every open issue opened while it was held, a follow-up too (conveyor.sh control start queue filed), so an
#   issue the output does not link (`gh issue create ... | grep -oE '[0-9]+$'`) is held too, and one released already
#   stays released. The
#   research lane (lanes/research.sh) runs these two as well, with CONVEYOR_LANE=research and its own folder as $FD, so an issue it files starts held too.
set -uo pipefail
case ${1:-} in
  setup | launch | start | rules | words | live | filing | filed | off) ;;
  claim) [ $# = 2 ] && [[ $2 =~ ^[A-Za-z0-9-]+$ ]] || { echo "usage: foreman.sh claim <session id>" >&2; exit 2; } ;;
  ask) [ $# -ge 3 ] && [[ $2 =~ ^[A-Za-z0-9._-]+$ ]] || { echo "usage: foreman.sh ask <repo> <command> [<argument>...]" >&2; exit 2; } ;;
  *) echo "usage: foreman.sh setup | launch [--new] [<claude argument>...] | claim <session id> | ask <repo> <command> [<argument>...] | off | start | rules | words | live | filing | filed" >&2; exit 2 ;;
esac
# A hook's input, and the session it names.
case $1 in start | rules | words | filing | filed) IN=$(cat); SID=$(jq -r '.session_id // empty | strings' <<<"$IN" 2>/dev/null) ;; esac
# words: every prompt of every session comes here, so any other prompt ends before anything is read; the rest runs in
# the session's own folder (the hook input's cwd), whose main checkout is the one claimed.
if [ "$1" = words ]; then
  case $(jq -r '.prompt // "" | strings | ascii_downcase | gsub("^\\s+|[\\s.!]+$"; "") | gsub("\\s+"; " ")' <<<"$IN" 2>/dev/null) in
    'start your role' | 'you are the foreman') ;;
    *) exit 0 ;;
  esac
  [[ $SID =~ ^[A-Za-z0-9-]+$ ]] || exit 0
  WD=$(jq -r '.cwd // empty | strings' <<<"$IN" 2>/dev/null)
  [ -z "$WD" ] || cd "$WD" || exit 0
fi
# The Bash call a filing or filed hook is for: a filing in flight is that call's, and only that call's filed ends it.
case $1 in filing | filed) TID=$(jq -r '.tool_use_id // empty | strings' <<<"$IN" 2>/dev/null) ;; esac
[ "$1" != setup ] || unset CONVEYOR_FOREMAN_DIR # the state folder decides the folder setup writes, never a session's
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh" || exit 1
# filing and filed are the Foreman's, and the research lane's (CONVEYOR_LANE=research): any other session's pass,
# but for filed of a call with a filing in flight ($SF/in, below), which ends it though the role has moved on.
SF=${HOSTF%/*}/filing
case $1 in
  filing | filed) [ "${CONVEYOR_LANE:-}" = research ] || foreman "$SID" \
    || { [ "$1" = filed ] && [ -n "$SID" ] && grep -qxF "$SID"$'\t'"$FD"$'\t'"$TID" "$SF/in" 2>/dev/null; } || exit 0 ;;
esac
MAIN=${CONVEYOR_MAIN:-$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null | sed 's|/\.git$||')}
CAP=5000 LIVE_CAP=1500 CTX_LIMIT=9000 RULES_LIMIT=9000
# --rules-apart: the start's caller sends rules.md by the rules hook, so the start leaves it out (context).
RULES_APART=; [ "$1" = start ] && [ "${2:-}" = --rules-apart ] && RULES_APART=1

setup() {
  local n pin
  n=$(mine | cut -f1 | paste -sd' ' -) && [ -n "$n" ] || return 1
  pin=$(jq -r '.plugin.commit // .plugin.follow // empty' "$MAIN/.conveyor/project.json" 2>/dev/null) && [[ $pin =~ ^([0-9a-f]{40}|main)$ ]] \
    || { echo "foreman: the pack of $MAIN pins no Conveyor commit and follows no main; run /conveyor-belt:setup first" >&2; return 1; }
  mkdir -p "$FD" || return 1
  [ -e "$FD/state.md" ] || { printf '# %s: saved state\n' "$NAME" > "$FD/state.md" && echo "foreman: wrote the state file $FD/state.md"; } || return 1
  jq -n --arg fd "$FD" \
    '{env: {CONVEYOR_FOREMAN: "1", CONVEYOR_FOREMAN_DIR: $fd, CLAUDE_CODE_PROMPT_CACHE_TTL: "1h"}}' > "$FD/settings.json.new" \
    && mv "$FD/settings.json.new" "$FD/settings.json" || return 1
  # A Foreman claimed in an ordinary session gets the 1-hour cache from the main checkout's local settings, every other
  # key kept; a file that is not a JSON object is not ours to rewrite.
  local sl=$MAIN/.claude/settings.local.json
  if [ ! -e "$sl" ] || jq -e 'type == "object"' "$sl" > /dev/null 2>&1; then
    mkdir -p "$MAIN/.claude" && { if [ -e "$sl" ]; then cat "$sl"; else echo '{}'; fi; } \
      | jq '.env = ((.env | objects) // {}) + {CLAUDE_CODE_PROMPT_CACHE_TTL: "1h"}' > "$sl.new" && mv "$sl.new" "$sl" \
      || { rm -f "$sl.new"; echo "foreman: the 1-hour prompt cache could not be set in $sl" >&2; return 1; }
    echo "foreman: set the 1-hour prompt cache (env.CLAUDE_CODE_PROMPT_CACHE_TTL) in $sl"
  else
    echo "foreman: $sl is not a JSON object, so it is left as it is; a Foreman claimed in a session here keeps that session's prompt cache time" >&2
  fi
  echo "foreman: wrote the launcher's settings $FD/settings.json, for $NAME, watching $(wc -w <<<"$n") record(s) of $HOSTF, this project's own or its group's ($n), and no other; start it with /conveyor-belt:foreman in a Claude Code session in this checkout (or conveyor foreman); another project gets its own Foreman by this setup there"
}

launch() {
  local new= id enc f
  shift
  [ "${1:-}" != --new ] || { new=1; shift; }
  [ -f "$FD/settings.json" ] || { echo "foreman: Foreman mode is not set up here; run /conveyor-belt:setup --foreman" >&2; return 1; }
  cd "$MAIN" || return 1
  # The launch file names this launch: the session's first start marks it, however it was opened (start).
  mkdir -p "$FD" && echo "$$" > "$FD/launch" || return 1
  export CONVEYOR_FOREMAN=1 CONVEYOR_FOREMAN_DIR=$FD CONVEYOR_MAIN=$MAIN CLAUDE_CODE_PROMPT_CACHE_TTL=1h CONVEYOR_FOREMAN_LAUNCH=$$
  # Reopen the marked session's own conversation while its transcript (Claude Code's, under the main checkout's
  # project folder) is still there; else, or with --new, a fresh session, which its start marks. Claude Code names
  # the folder for the path, every other character a dash, cut past 200 characters to those and a dash and a hash.
  id=$(marked) enc=${MAIN//[^A-Za-z0-9]/-}
  [ ${#enc} -le 200 ] || enc="${enc:0:200}-*"
  [ -z "$new" ] && [ -n "$id" ] && for f in "${CLAUDE_CONFIG_DIR:-$HOME/.claude}"/projects/$enc/"$id.jsonl"; do
    [ ! -f "$f" ] || exec claude --settings "$FD/settings.json" --resume "$id" "$@"
  done
  exec claude --settings "$FD/settings.json" "$@"
}

# why <exit code> <stderr file>: the last 200 bytes of what the source said, else what its exit means.
why() {
  local said; said=$(tr -s '[:space:]' ' ' < "$2" 2>/dev/null | tail -c 200 | sed 's/^ //; s/ $//')
  [ -n "$said" ] && { printf '%s' "$said"; return; }
  [ "$1" = 124 ] && echo "no answer in time" || echo "exit $1"
}
BELT='def one: tostring | gsub("\\s+"; " ") | .[0:160];
  # A card by its issue, a main-red fix card (issue 0) by its name, "Main is red (<commit>)".
  def ref: (.name | strings) // "#\(.issue)";
  if type == "object" and (.health | type == "object" and (.loop | type == "boolean") and ([.blocked, .waiting] | all(type == "array")))
    and (.belt | type == "array")
  then . else error("not a snapshot") end
  | .health as $h | .belt as $b
  | "Conveyor \($repo) (snapshot as of \(.snapshotAt // "an unknown time")): loop \(if $h.loop then "running" else "not running" end), state \($h.state // "unknown")\(if $h.reason then ": " + ($h.reason | one) else "" end)",
    "\($repo) in flight: \([$b[] | select(.landed | not) | "\(ref) \(.step)"] | if length == 0 then "none" else join(", ") end)",
    (if ($h.blocked | length) == 0 then "\($repo) blocked: none" else $h.blocked[] | "\($repo) blocked: \(ref) since \(.since): \(.reason | one)" end),
    (($h.before | arrays | map(objects)) // []) as $before
    | (if ($h.waiting | length) + ($before | length) == 0 then "\($repo) waiting on the owner'"'"'s yes: none"
       else ($h.waiting[] | "\($repo) waiting on the owner'"'"'s yes: \(ref) since \(.since)"),
         ($before[] | "\($repo) waiting on the owner'"'"'s yes before its build: #\(.issue) since \(.since): \(.title | one)") end),
    (if $h.pushError then "\($repo) push failing since \($h.pushFailingSince): \($h.pushError.reason | one)" else "\($repo) push errors: none" end)'
OPEN='def one: tostring | gsub("\\s+"; " ") | .[0:160];
  group_by(.id) | map(last) | map(select(.answeredAt == null)) | sort_by(.askedAt) | reverse
  | if length == 0 then "\($repo) open decisions: none" else "\($repo) open decisions (\(length), newest first):", (.[] | "- \(.id): \(.question | one)") end'

live() {
  local tmp i line used=0 need=0 cutting= cut="[live summary cut at $LIVE_CAP bytes]" lines=() must=() recs repo main rc out led
  tmp=$(mktemp -d) || { echo "# Live summary unavailable: no temp folder"; return 0; }
  lines+=("# Live summary (built at startup from Conveyor's snapshot and the decision ledger; never saved)")
  recs=$(mine 2>"$tmp/recs.err") || { must+=("${#lines[@]}"); lines+=("Conveyor: unavailable: $(why 1 "$tmp/recs.err")"); }
  i=0
  while IFS=$'\t' read -r repo main; do
    [ -n "$repo" ] || continue
    i=$((i + 1))
    ( { ASK_LIMIT=10 ask "$repo" "$main" snapshot; } > "$tmp/$i.out" 2> "$tmp/$i.err"; echo $? > "$tmp/$i.rc" ) &
  done <<<"$recs"
  wait
  i=0
  while IFS=$'\t' read -r repo main; do
    [ -n "$repo" ] || continue
    i=$((i + 1)); rc=$(cat "$tmp/$i.rc")
    if [ "$rc" = 0 ] && out=$(jq -r --arg repo "$repo" "$BELT" "$tmp/$i.out" 2>"$tmp/$i.err"); then mapfile -t -O "${#lines[@]}" lines <<<"$out"
    else [ "$rc" != 0 ] || rc=1; must+=("${#lines[@]}"); lines+=("Conveyor $repo: unavailable: $(why "$rc" "$tmp/$i.err")"); fi
  done <<<"$recs"
  while IFS=$'\t' read -r repo main; do
    [ -n "$repo" ] || continue
    # A main on another host (lib.sh mine) is read from this checkout's ledger when it is that record's (lib.sh
    # ledger); any other has its ledger there: not read here, which is not "none".
    if ! led=$(ledger "$repo" "$main"); then must+=("${#lines[@]}"); lines+=("$repo open decisions: unavailable: its main checkout $main is not on this machine")
    elif [ ! -e "$led/.claude/metrics/decisions.jsonl" ]; then lines+=("$repo open decisions: none (no ledger)")
    elif out=$(jq -rs --arg repo "$repo" "$OPEN" "$led/.claude/metrics/decisions.jsonl" 2>"$tmp/dec.err"); then mapfile -t -O "${#lines[@]}" lines <<<"$out"
    else must+=("${#lines[@]}"); lines+=("$repo open decisions: unavailable: $(why 1 "$tmp/dec.err")"); fi
  done <<<"$recs"
  rm -rf "$tmp"
  # The cap counts bytes. An "unavailable" line always prints, by reserve, so other lines never hide a failure; any
  # other line that does not fit drops the rest of those with the cut line, which fits by reserve.
  local LC_ALL=C
  for i in "${must[@]}"; do need=$((need + ${#lines[i]} + 1)); done
  for i in "${!lines[@]}"; do
    line=${lines[i]}
    if [[ " ${must[*]} " == *" $i "* ]]; then echo "$line"; used=$((used + ${#line} + 1)); need=$((need - ${#line} - 1)); continue; fi
    [ -z "$cutting" ] || continue
    if [ $((used + ${#line} + 1 + ${#cut} + 1 + need)) -gt "$LIVE_CAP" ]; then echo "$cut"; cutting=1; continue; fi
    echo "$line"; used=$((used + ${#line} + 1))
  done
}

# start writes the session to $FD/started when it ends, marked or not, so the waiter's SessionStart hook beside it
# (waiter.sh --start) reads the mark only once this hook's claim has ended, and ends at once in a session not marked.
start() {
  local rc
  start_; rc=$?
  [ -z "$SID" ] || { mkdir -p "$FD" && printf '%s\n' "$SID" > "$FD/started.$$" && mv -f "$FD/started.$$" "$FD/started"; } 2>/dev/null
  return "$rc"
}
start_() {
  local src t launched=
  src=$(jq -r '.source // empty | strings' <<<"$IN" 2>/dev/null)
  # The launcher's first start (its launch file, consumed here) marks its session, fresh or opened by --resume or
  # --continue; a /clear, a compaction or a /resume later in that session, after a claim elsewhere or off, does not.
  [ -n "${CONVEYOR_FOREMAN_LAUNCH:-}" ] && [ "$(cat "$FD/launch" 2>/dev/null)" = "$CONVEYOR_FOREMAN_LAUNCH" ] \
    && rm -f "$FD/launch" && launched=1
  if [ "${CONVEYOR_FOREMAN:-}" = 1 ] && [ -n "$SID" ] && { [ "$src" = startup ] || [ -n "$launched" ]; }; then claim "$SID" || return 1
  elif { [ "$src" = resume ] || [ "$src" = fork ]; } && [ -n "$SID" ]; then
    t=$(jq -r '.transcript_path // empty | strings' <<<"$IN" 2>/dev/null)
    locked adopt_ "$SID" "$t" || return 1
  elif [ "$src" = clear ] && [ -n "$SID" ]; then locked cleared_ "$SID" || return 1
  fi
  if foreman "$SID"; then context; return 0; fi
  if [ -n "$SID" ] && grep -qxF -- "$SID" "$FD/former" 2>/dev/null; then
    # Plain stdout at SessionStart reaches only Claude: systemMessage shows the owner the line too.
    jq -cn --arg m "This session is no longer the Foreman: the role moved to another session or was turned off. /conveyor-belt:foreman makes it the Foreman again." \
      '{systemMessage: $m, hookSpecificOutput: {hookEventName: "SessionStart", additionalContext: ("# " + $m)}}' || return 1
    locked told "$SID"; return
  fi
  [ "$src" = startup ] && [[ $SID =~ ^[A-Za-z0-9-]+$ ]] && [ -z "${CONVEYOR_CARD:-}" ] && [ -z "${CONVEYOR_LANE:-}" ] && inmain || return 0
  auto
}
# inmain: 0 when this runs in a project's main checkout (one with a pack, .conveyor/project.json), never a worktree
# (a card's, a lane's).
inmain() {
  local top
  top=$(git rev-parse --show-toplevel 2>/dev/null) && top=$(cd "$top" && pwd -P) && [ "$top" = "$(cd "$MAIN" 2>/dev/null && pwd -P)" ] \
    && [ -f "$MAIN/.conveyor/project.json" ]
}
# The marked Foreman is gone when no running Claude process holds its session id (Claude Code's sessions/<pid>.json
# naming it, that pid running), or when its transcript (projects/*/<id>.jsonl) has not been written for GONE seconds:
# 24 hours, as its waiter wakes a live Foreman at least every 23 (waiter.sh).
CC=${CLAUDE_CONFIG_DIR:-$HOME/.claude} GONE=86400
# holders <session id>: "<pid> <started, epoch seconds>" for each running Claude process holding it.
holders() {
  local f pid st
  for f in "$CC"/sessions/*.json; do
    grep -qF -- "\"$1\"" "$f" 2>/dev/null || continue
    read -r pid st < <(jq -r --arg s "$1" 'select(.sessionId == $s and (.pid | type == "number" and . > 0))
      | "\(.pid) \((.startedAt | numbers / 1000 | floor) // "")"' "$f" 2>/dev/null) || continue
    kill -0 "$pid" 2>/dev/null && [[ $(ps -o stat= -p "$pid" 2>/dev/null) != *Z* ]] && printf '%s %s\n' "$pid" "$st"
  done
}
# written <session id>: when its transcript was last written (epoch seconds), empty with none.
written() {
  local f t n=0
  for f in "$CC"/projects/*/"$1.jsonl"; do
    t=$(p_stat "$f" | cut -d' ' -f2); [ "${t:-0}" -le "$n" ] || n=$t
  done
  [ "$n" = 0 ] || printf '%s' "$n"
}
running() { # <session id>: 0 when it is not gone
  local w
  [ -n "$(holders "$1")" ] || return 1
  w=$(written "$1"); [ -z "$w" ] || [ $(( $(date +%s) - w )) -le "$GONE" ]
}
# auto_ <session id> (under claim.lock): prints the marked session when it is live; else claims the role for this one.
auto_() {
  local m; m=$(marked)
  if [ -n "$m" ] && [ "$m" != "$1" ] && running "$m"; then printf '%s\n' "$m"; return 0; fi
  claim_ "$1"
}
# named: the Foreman's name in brackets, only when the host file gives it one other than "Foreman" (lib.sh's default),
# so a start line never reads "the Foreman (Foreman)".
named() { [ "$NAME" = Foreman ] || printf ' (%s)' "$NAME"; }
# auto: a new session in the main checkout takes the role, or is told to ask the owner whether to take it over.
auto() {
  local m out st w at cmd p
  if ! m=$(locked auto_ "$SID"); then
    jq -cn --arg m "foreman: this session could not take the Foreman role at its start ($MARK); /conveyor-belt:foreman tries again." \
      '{systemMessage: $m, hookSpecificOutput: {hookEventName: "SessionStart", additionalContext: ("# " + $m)}}'
    return 1
  fi
  if [ -z "$m" ]; then
    out="This session is now the Foreman$(named): no live session held the role, so it took it at its start; its watchers start at once, with no turn needed."
    out+=$'\n\n'$(context)
    jq -cn --arg m "${out%%$'\n'*}" --arg c "$out" '{systemMessage: $m, hookSpecificOutput: {hookEventName: "SessionStart", additionalContext: $c}}'
    return
  fi
  st=$(holders "$m" | awk '$2 != "" { print $2; exit }')
  if [ -n "$st" ]; then st=$(p_date "@$st" '+%Y-%m-%d %H:%M %Z')
  else read -r _ at 2>/dev/null < "$MARK"; st=$(p_date "${at:-now}" '+%Y-%m-%d %H:%M %Z' 2>/dev/null) || st=unknown; fi
  w=$(written "$m"); if [ -n "$w" ]; then w=$(p_date "@$w" '+%Y-%m-%d %H:%M %Z'); else w=unknown; fi
  p=$(mine 2>/dev/null | cut -f1 | paste -sd' ' - | sed 's/ /, /g'); p=${p:-this project}
  printf -v cmd '%q/shim.sh conveyor/foreman/foreman.sh claim %q' "${CLAUDE_PLUGIN_ROOT:-$(cd "$FHERE/../.." && pwd -P)}" "$SID"
  out="# Foreman: another live session holds the role, so this session did not take it. As your first act, before anything else, ask the owner by the picker (AskUserQuestion), with this question and two options, \"Take over\" and \"Leave it\":
Session ${m:0:8} (started $st, last active $w) is the Foreman of $p. Make this session the Foreman instead?
- On \"Take over\": run \`$cmd\`. Its first line says this session is now the Foreman (the other session's watchers stop): reply with that one line, and with the line on the prompt cache time when there is one, and from then on work by the rest of its output as the Foreman. When it fails, show its message and stop.
- On \"Leave it\": this session stays a normal session; do not ask again in it.
Then go on with what the owner asked, if anything."
  jq -cn --arg c "$out" '{hookSpecificOutput: {hookEventName: "SessionStart", additionalContext: $c}}'
}
# adopt_ <session id> <transcript> (under claim.lock, so an off or a claim made meanwhile is never undone): a resume
# or a fork (--fork-session, source fork) that gave the session a new id takes the mark when its transcript holds the
# Foreman session's entries, copied (forkedFrom). A session that held the role and lost it (former) gets it back only
# by a claim. The marked session itself reopened in a new Claude process moves the process record to that process
# only when the recorded process no longer runs it; any other session opened in the recorded process (a /resume
# there) ends the record, so a /clear after it never takes the role (cleared_).
adopt_() {
  local m rec=
  m=$(marked)
  if [ -n "$m" ] && [ "$m" = "$1" ]; then
    { read -r rec < "$FD/claude.pid"; } 2>/dev/null
    # The record stays with a running process that still holds the marked session, so a second process that reopens
    # it (and may end first) never takes the record from the Foreman.
    [ -n "$rec" ] && kill -0 "$rec" 2>/dev/null \
      && jq -e --arg m "$m" --argjson p "$rec" '.pid == $p and .sessionId == $m' "$CC/sessions/$rec.json" >/dev/null 2>&1 || claude_rec
    return 0
  fi
  if [ -n "$m" ] && [ -f "$2" ] && ! awk -v s="$1" '$1 == s { f = 1 } END { exit !f }' "$FD/former" 2>/dev/null \
    && jq -en --arg m "$m" 'first(inputs | select(.sessionId == $m or .forkedFrom.sessionId? == $m)) | true' "$2" >/dev/null 2>&1; then
    claim_ "$1"; return
  fi
  { read -r rec < "$FD/claude.pid"; } 2>/dev/null
  [ -z "$rec" ] || [ "$rec" != "$(cc_pid)" ] || rm -f "$FD/claude.pid"
  return 0
}
# cleared_ <session id> (under claim.lock, as adopt_): a /clear (source clear) gives the session a new id in the same
# Claude Code process; the new one takes the mark when that process (cc_pid) holds the marked Foreman: its
# sessions/<pid>.json still names the marked session, or, as Claude Code writes it before this hook runs, names the
# new one while the process is the one recorded at the mark ($FD/claude.pid). A /clear in any other process, or after
# off, changes nothing.
cleared_() {
  local m p rec=
  m=$(marked); [ -n "$m" ] && [ "$m" != "$1" ] || return 0
  p=$(cc_pid) && [ -n "$p" ] || return 0
  { read -r rec < "$FD/claude.pid"; } 2>/dev/null
  jq -e --arg m "$m" --arg n "$1" --arg rec "$rec" --argjson p "$p" \
    '.pid == $p and (.sessionId == $m or (.sessionId == $n and $rec == ($p | tostring)))' "$CC/sessions/$p.json" >/dev/null 2>&1 || return 0
  claim_ "$1"
}

# claim <session id> (/conveyor-belt:foreman): this session becomes the Foreman; its watchers start at its next stop.
# A session that was not the Foreman before also gets the Board opened in the browser (board_open, as a fresh start
# opens it; boardAutoOpen false turns it off), once: a claim by the Foreman's own session opens no second tab, and a
# resume, /clear or compact never comes here. When the Board is not running, one line says so and the Board is started
# from this checkout (conveyor.sh board), then opened; the claim stands.
claim_cmd() {
  local was
  was=$(marked)
  claim "$2" || { echo "foreman: this session could not be made the Foreman ($MARK)"; return 1; }
  echo "This session is now the Foreman$(named): its watchers start at the end of this turn."
  # A claimed session keeps the cache time it started with; setup's settings.local.json gives a restarted one 1h.
  [ -z "${CLAUDE_CODE_PROMPT_CACHE_TTL:-}" ] || [ "$CLAUDE_CODE_PROMPT_CACHE_TTL" = 1h ] \
    || echo "The Foreman runs with the prompt cache time $CLAUDE_CODE_PROMPT_CACHE_TTL, not 1h: a restart of this session takes the 1-hour cache from $MAIN/.claude/settings.local.json, which /conveyor-belt:setup --foreman writes."
  [ "$was" = "$2" ] || { . "$FHERE/../../.claude/hooks/lib/board-open.sh" && board_open "$MAIN"; }
  echo; context
}
off() {
  claim '' || { echo "foreman: Foreman mode could not be turned off ($MARK)"; return 1; }
  echo "Foreman mode is off: no session is the Foreman, and its watchers have stopped."
}

# context: the start's text, under CTX_LIMIT bytes (Claude Code keeps a hook's output over 10,000 characters out of the
# context and gives the session a short preview only). It is made in three parts: the fixed text with its warnings, the
# rest (auto's rules, the standing kinds, the live summary) and the saved state. This project's rules.md is not part of
# it when the start is called with --rules-apart (the plugin's hooks.json does): the SessionStart hook `rules` sends it in
# an output of its own. A call without it (a claim in a running session, which no SessionStart follows, or a plugin from
# before the rules hook) gets rules.md after the rest, cut to what the limit leaves. When the whole is over the limit,
# state.md is swapped for one line that tells the Foreman to Read the file.
context() {
  local head mid st
  launcher
  FQ=$(printf %q "$LAUNCHER")
  head=$(context_head) mid=$(context_mid) st=$(context_state)
  if [ "$(printf '%s\n%s\n%s\n' "$head" "$mid" "$st" | wc -c)" -gt "$CTX_LIMIT" ]; then st=$(context_state_warn; context_read "$FD/state.md"); fi
  printf '%s\n' "$head"
  printf '%s\n' "$mid"
  [ -z "$st" ] || printf '%s\n' "$st"
  [ -n "$RULES_APART" ] || rules_text "$((CTX_LIMIT - $(printf '%s\n%s\n%s\n' "$head" "$mid" "$st" | wc -c)))"
}

# context_read <file>: the line that stands for a file part that did not fit; nothing for a file with no text.
context_read() {
  [ -s "$1" ] || return 0
  printf '\n# %s did not fit in this start (Claude Code cuts a start over 10,000 characters): Read %s now, before you act.' "$1" "$1"
}

context_head() {
  local err n plug home='' s=$FD/state.md
  # A plugin problem: in the plugin's own repository (plugin_home) the Foreman files it there itself, as any issue it
  # files, and its line names the issue (stop.sh refuses one that does not); elsewhere the owner files it.
  plug="# A suspected defect in Conveyor itself always needs the owner (only they can fix or file it in the plugin's repository): say it on its own line, \"Plugin problem (for the conveyor-belt repo): <what you saw>, card <card>, evidence <path>\"; it is noted in $FD/plugin-bugs.md."
  if plugin_home; then
    home=1
    plug="# A suspected defect in Conveyor itself: this project is the plugin's own repository, so file it here at once, as any issue you file (it starts held until the owner says yes), and say it on its own line with the issue's number, \"Plugin problem (for the conveyor-belt repo): <what you saw>, card <card>, evidence <path>, filed as #<n>\"; it is noted in $FD/plugin-bugs.md."
  fi
  cat <<EOF
# Foreman mode: you are $NAME, the Foreman of this project. You file issues as cards, watch Conveyor, clear blocked cards and take every decision to the owner; you never answer for the owner, and you build no code yourself: the cards do.
# You are the Foreman of $(mine 2>/dev/null | cut -f1 | paste -sd' ' - | sed 's/ /, /g; s/^$/this project/') only: every other project has its own Foreman. Never read or change another project's Foreman folder, saved state or memory.
# Filing: file issues only in your own projects; an issue you file starts held (the filing hooks hold it in Conveyor, in its record); release it (conveyor.sh control release <issue>, in that record) only once the owner has said yes to it. File an issue about a test file with $FQ ask <project> testissue <test file> <title> <body>: it runs where the record is, as the Foreman, so the issue starts held there too.
# Questions to the owner go only by the picker (AskUserQuestion), never as a question in your reply.
# The pack not committed (git status --porcelain -- .conveyor/project.json prints a line in a project's main checkout): there, run conveyor.sh setup pack-commit, and when it prints an ask: line, ask the owner by the picker "Commit the Conveyor pack (.conveyor/project.json) on <default branch> now?" (yes / no), with the change it printed; on yes run conveyor.sh setup pack-commit yes, on no conveyor.sh setup pack-commit no, and say what it printed. Never list a git command for the owner to run.
# A release's suite: before you run conveyor.sh release-run prep <version> or release-run <version>, ask the owner by the picker "Run the test files one by one or in parallel?" with two options, "One by one" (slower, the least load) and "In parallel (<n> at once)" (faster, more load on the build machine, the belt slower meanwhile), and pass the answer last in the command: --serial for one by one, --parallel for in parallel. <n> is the number $FQ ask <project> release-run atonce prints for the release's project: the most test files its parallel suite runs at once, where it runs; when it prints no number, the option is "In parallel".
# A wake (a watcher's message) gets a reply that says only what needs the owner; when nothing does, reply with the one word Idle.
# A wake that a card has waited (or is still waiting) for main to change, or on another card: do not only report it. Find why it waits: read the waited-on card's log (<card>.out, .err and .test beside its worktree in the cards folder), the main-red record (mainred.json in the folder conveyor.sh state-dir prints) and the test log (<card>.testlog). Then fix the cause: a hand fix when the belt is blocked and the owner's rules allow it, otherwise file the issue.
$plug
# Check status with conveyor.sh foreman status, not your own snapshot reads. A wake already names what changed: a landed card's commit, a blocked card's reason, a suite run's result and failed cases.
# Run a command that ends in under 2 minutes in the foreground; put several checks into one command; start a background command only for a long run.
# Read an image (a screenshot, a GIF frame) only when the owner asks or a check needs to see it.
# To be woken when an issue lands, append its number to $FD/await-<project>.txt, <project> being the one it is in (append only; never rewrite it).
# Your saved state is $s: keep it current, under $CAP bytes; mark a finished item "- DONE" and it is archived at the next start.
EOF
  # There, each noted plugin problem that names no issue (no "filed as #<n>"), so an older one is not lost, with the
  # line that marks it filed: in the form, its own text (between its card and its evidence) with the note's card and
  # evidence fields after it, unless the text already ends with them (a note saved from a line in the form), which
  # stop.sh matches exactly.
  if [ -n "$home" ] && n=$(grep '^- ' "$FD/plugin-bugs.md" 2>/dev/null | grep -viE ' filed as #[1-9][0-9]*[[:space:]]*\.? · evidence: ') && [ -n "$n" ]; then
    echo "# WARNING: plugin problems noted in $FD/plugin-bugs.md with no issue number yet: for each one, first search this repository's issues, open and closed, for one that already reports it (the owner may have filed it); file it now only when none does. Then say the line under it with that issue's number, word for word, so the entry is marked filed."
    local l t f re='^- [^ ]* · card ([^ ]*) · (.*) · evidence: (.*)$'
    while IFS= read -r l; do
      t=$l
      if [[ $l =~ $re ]]; then
        t=${BASH_REMATCH[2]} f=", card ${BASH_REMATCH[1]}, evidence ${BASH_REMATCH[3]}"
        [[ $t == *"$f" ]] || t+=$f
      fi
      printf '%s\n  Plugin problem (for the conveyor-belt repo): %s, filed as #<n>\n' "$l" "$t"
    done <<<"$n"
  fi
  # An empty state.md still runs archive: only archive reports a late write kept beside it.
  [ ! -e "$s" ] || err=$(python3 -I "$FHERE/archive.py" "$s" 2>&1) \
    || echo "# WARNING: the DONE items of $s were not archived: ${err##*$'\n'}"
}

# rules (SessionStart, beside start): the Foreman session's project (or group) rules, $FD/rules.md, as an output of their
# own, so they never share the start's limit. It waits until start has ended, as the waiter does (await_start), so a
# session that start made the Foreman is seen as one. A session that is not the Foreman gets nothing.
rules() {
  [ -z "$SID" ] || await_start "$SID"
  foreman "$SID" || return 0
  rules_text "$RULES_LIMIT"
}

# rules_text <limit>: rules.md in at most <limit> bytes: whole, or cut at a whole line with a line that names the file
# and says to Read the rest. Nothing for a missing or empty file.
rules_text() {
  local r=$FD/rules.md n head
  [ -s "$r" ] || return 0
  head="# $r (this project's Foreman rules)"
  n=$(p_stat "$r" | cut -d' ' -f1)
  echo; echo "$head"
  if [ $((${#head} + 3 + n)) -le "$1" ]; then cat "$r"; return 0; fi
  LC_ALL=C awk -v cap=$(($1 - ${#head} - 300)) '{ used += length($0) + 1; if (used > cap) exit; print }' "$r"
  echo "[cut to fit $1 bytes, $n in the file; Read the rest from $r]"
}

context_mid() {
  local err repo main
  # Auto's rules while it is on (`conveyor.sh auto rules`): the mode is this machine's, set by /conveyor-belt:auto here.
  if err=$(bash "$FHERE/../conveyor.sh" auto rules 2>/dev/null); then [ -z "$err" ] || { echo; printf '%s\n' "$err"; }
  else echo "# WARNING: auto's rules could not be read (conveyor.sh auto rules failed)."; fi
  # The standing kinds of routine yes each record's pack turns on, with their limits (`conveyor.sh auto standing`,
  # lib/standing.sh), asked of the record as the live summary asks it (ask: over ssh when the host file names a host),
  # so a kind the Board turns on or off in the host's pack counts here; one warning line for a record whose kinds
  # cannot be read, so none of its kinds is taken. The rules' commands run by `foreman.sh ask <repo>` (ask_cmd), from
  # this machine, so they reach the record on its host, not the host's engine path here.
  while IFS=$'\t' read -r repo main; do
    [ -n "$repo" ] || continue
    if err=$(ASK_LIMIT=10 ask "$repo" "$main" auto standing "CONVEYOR_MAIN=$(printf %q "$CONVEYOR_MAIN") $FQ ask $repo" 2>/dev/null); then [ -z "$err" ] || { echo; echo "# $repo"; printf '%s\n' "$err"; }
    else echo "# WARNING: the standing kinds of routine yes of $repo could not be read (conveyor.sh auto standing failed), so take none without asking."; fi
  done < <(mine 2>/dev/null)
  # The project runs an old engine here, and why (`conveyor.sh take stale`, from this install: no remote is read).
  err=$(bash "$FHERE/../conveyor.sh" take stale 2>/dev/null) && [ -n "$err" ] && echo "# WARNING: $err"
  echo
  live
}

# context_state_warn: the warning for a saved state over its cap; nothing for one that fits. A start that swaps the
# state for a Read line keeps it.
context_state_warn() {
  local n
  [ -s "$FD/state.md" ] || return 0
  n=$(p_stat "$FD/state.md" | cut -d' ' -f1)
  [ "$n" -le "$CAP" ] || echo "# WARNING: $FD/state.md is $n bytes, over its $CAP-byte cap: trim it."
}

context_state() {
  local s=$FD/state.md n
  [ -s "$s" ] || return 0
  echo
  echo "# $s (your saved state; keep it current)"
  n=$(context_state_warn)
  if [ -z "$n" ]; then cat "$s"; return 0; fi
  echo "$n"
  n=$(p_stat "$s" | cut -d' ' -f1)
  # Whole lines up to the cap, then a line naming the file.
  LC_ALL=C awk -v cap=$((CAP - 200)) '{ used += length($0) + 1; if (used > cap) exit; print }' "$s"
  echo "[cut to fit $CAP of $n bytes; Read the rest from $s]"
}

# files <hook input>: 0 when its command files an issue, by gh or by the engine's gh-write; quotes and backslashes
# are dropped first, so `gh issue 'create'` is seen too; a subcommand or command group made by an expansion
# (`gh issue "$sub"`, `gh issue $(echo create)`, `gh "$noun" "$sub"`) cannot be read, so it counts as filing; flags
# before either, each with its value (`gh issue --repo "$repo" view 7`, `gh -R example/alpha issue create`), are passed
# over whole, so a value made by an expansion is not taken for the subcommand; a short flag with its value attached
# (`gh issue -Rexample/alpha "$sub"`) takes no word after it. `gh api` on a repository's issues endpoint
# (`gh api repos/example/alpha/issues -f title=example`) or a GraphQL createIssue files one too, and so may a `gh api`
# whose request is read from a file or made by an expansion (`-F query=@file`, `--input file`, `-f query="$q"`): it
# cannot be read, so it counts as filing. Any other HTTP client (curl, wget, a script) files one on the same endpoints,
# and whether it writes cannot be read (a script POSTs whenever it sends a body), so a command that names a
# repository's issues list or the GraphQL endpoint (`curl https://api.github.com/repos/example/alpha/issues`,
# `.../graphql`) counts as filing; one issue (`.../issues/7`) does not. \uXXXX, \xXX and %XX escapes are decoded first,
# so `\u0069ssues` is seen too. A curl or wget whose request is read from a file (`curl --config file`, `wget -i file`)
# or that writes with an expansion in it cannot be read, so it counts as filing. A read taken for filing only holds new
# issues until `filed` starts them in the queue again.
# Its limit, accepted: it reads the command as written, in the forms above. It does not try to see through deliberate
# shell indirection beyond them (a command run through eval or a script, a gh or gh-write named through a variable,
# other quoting tricks), which is out of scope: it checks agents' own commands and is not a security boundary.
# The program is files.jq, which the plugin's hook lines (filing-hook.sh) read too, so a command that files no issue
# ends there, before the shim looks for the engine.
files() { jq -e -f "$FHERE/files.jq" <<<"$1" >/dev/null 2>&1; }
# Every Foreman of the host file, and every lane's filer, files against the same records, so what filing set held is
# kept in one list for all ($SF/held, beside the host file), and each filing in flight adds a line to $SF/in (the
# session filing, a tab, the folder of the Foreman or filer filing, whole, a tab, and the Bash call's id; one line per
# filing, so one Foreman's two at once are two, and a call's filed ends its own filing and no other): a filing that
# finds a record held by another's still in flight has set nothing, and only the last filing to end starts them in the
# queue again (queue_again). When the shared lock is not had, the command is refused.
filing() {
  local in recs repo main c bad=() sl
  in=$IN
  files "$in" || return 0
  # A command run in the background has its filed hook as soon as it starts: the records would start new issues in
  # the queue again before it files any, and its output links none, so nothing it files would be held.
  ! jq -e '.tool_input.run_in_background == true' <<<"$in" >/dev/null 2>&1 \
    || { deny "Not run: a command that files an issue runs in the background, so the issues it files would not be held. Run it again in the foreground."; return 0; }
  mkdir -p "$SF" && exec {sl}>>"$SF/lock" && flock -w 300 "$sl" && touch "$SF/held" && printf '%s\t%s\t%s\n' "$SID" "$FD" "$TID" >> "$SF/in" \
    || { deny "Not run: the filing lock ($SF/lock) was not had, so new issues could not be set to start held, and an issue you file could be built before the owner's yes. Try again; if it fails again, tell the owner."; return 0; }
  # Every record, not only the Foreman's own: the command may file in another project (`gh issue create -R`), and
  # that issue must be held from its first sight too.
  recs=$(records 2>&1) || { bad+=("every record (${recs##*$'\n'})"); recs=''; }
  while IFS=$'\t' read -r repo main; do
    [ -n "$repo" ] || continue
    grep -qxF "$repo" "$SF/held" && continue
    c=$(ask "$repo" "$main" control 2>&1 | tail -n 1)
    [ "$(jq -r '.start // empty' <<<"$c" 2>/dev/null)" != held ] || continue
    if [ "$(jq -r '.start // empty' <<<"$c" 2>/dev/null)" = queue ] && c=$(ask "$repo" "$main" control start held 2>&1); then
      printf '%s\n' "$repo" >> "$SF/held"
    else bad+=("$repo (${c##*$'\n'})"); fi
  done <<<"$recs"
  exec {sl}>&-
  [ ${#bad[@]} != 0 ] || return 0
  queue_again > /dev/null # the command does not run; only the refusal is printed
  deny "Not run: new issues could not be set to start held in ${bad[*]}, so an issue you file there could be built before the owner's yes. Try again; if it fails again, tell the owner."
}
deny() { jq -cn --arg r "$1" '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: $r}}'; }
# queue_again: this filing's line is taken from $SF/in; when no other filing is in flight, every record a filing set to start
# new issues held starts them in the queue again; those that cannot stay listed in $SF/held, and are printed. The
# research lane's filer (lanes/research-file) files holding filing.lock in its folder (lanes/research-filer in the state folder, beside the lane's own and the Foreman's
# lanes/), and relies on new issues starting held until its issue is held, whoever set them held: the Foreman's and the
# lane's hooks start them in the queue again only once it is not filing (the filer, whose folder that is, holds the
# lock already). When the lock is not had, every record stays held.
# This filing's end is left in $SF/ended, a file each, whole once moved there; whoever next holds the shared lock takes
# its line from $SF/in (ends): a lock not had (another filing holding it long) never leaves the filing in flight for ever.
queue_again() {
  local repo main c left=() fl lk sl e
  e=$(mktemp "$SF/end.XXXXXX") && printf '%s\t%s\t%s\n' "$SID" "$FD" "$TID" > "$e" && mkdir -p "$SF/ended" && mv "$e" "$SF/ended/"
  if exec {sl}>>"$SF/lock" && flock -w 300 "$sl"; then
    ends
    exec {sl}>&-
  fi
  [ -s "$SF/held" ] || return 0
  fl=$(cd "$FD/.." && pwd -P)
  if [ "${CONVEYOR_LANE:-}" = research ]; then fl+=/research-filer; else fl+=/lanes/research-filer; fi
  # The filer's lock before the shared one, as the filer takes them, so neither waits on the other.
  [ "$FD" -ef "$fl" ] || { mkdir -p "$fl" && exec {lk}>>"$fl/filing.lock" && flock -w 300 "$lk"; } || { cat "$SF/held"; return 0; }
  exec {sl}>>"$SF/lock" && flock -w 300 "$sl" || { cat "$SF/held"; return 0; }
  ends
  # Another filing in flight may have found them held and set nothing: it starts them in the queue again at its end.
  [ ! -s "$SF/in" ] || return 0
  while read -r repo; do
    main=$(awk -F'\t' -v r="$repo" '$1 == r { print $2; exit }' <<<"$(records 2>/dev/null)")
    # An engine before `control start queue filed` refuses it as a usage error (2): set Queue as it can.
    [ -n "$main" ] && { c=$(ask "$repo" "$main" control start queue filed 2>&1) \
      || { [ $? = 2 ] && [[ $c == *'usage: conveyor.sh control'* ]] && ask "$repo" "$main" control start queue > /dev/null 2>&1; }; } || left+=("$repo")
  done < "$SF/held"
  if [ ${#left[@]} = 0 ]; then : > "$SF/held"; else printf '%s\n' "${left[@]}" | tee "$SF/held"; fi
}

# ends: under the shared lock, each filing's end left in $SF/ended takes its line from $SF/in.
ends() {
  local f ins
  for f in "$SF"/ended/*; do
    [ -f "$f" ] || continue
    ins=$(F=$(cat "$f") awk '!d && $0 == ENVIRON["F"] { d = 1; next } 1' "$SF/in" 2>/dev/null) && printf '%s' "${ins:+$ins$'\n'}" > "$SF/in" && rm -f "$f"
  done
}

filed() {
  local in ev recs gh repo main c rc h r n nums left said=() freed=() bad=()
  in=$IN
  files "$in" || return 0
  ev=$(jq -r '.hook_event_name // "PostToolUse"' <<<"$in")
  recs=$(records 2>&1) || { bad+=("any issue you filed (${recs##*$'\n'})"); recs=''; }
  # Every issue linked, as "<name> <n>", each once.
  n=$(jq -r '[.tool_response, .error] | map(select(. != null) | if type == "object" then [.stdout, .stderr] | map(strings) | join("\n") else tostring end) | join("\n")' <<<"$in" 2>/dev/null \
    | grep -oE 'github\.com/[^/[:space:]]+/[^/[:space:]]+/issues/[1-9][0-9]*' | awk -F/ '{ print $3, $5 }' | sort -u)
  while read -r gh nums; do
    [ -n "$gh" ] && [ -n "$recs" ] || continue
    nums=$(awk -v r="$gh" '$1 == r { print $2 }' <<<"$n" | paste -sd' ' -)
    # The record is found by its main checkout's GitHub repository, else by its name: a record (or the folder a host
    # file with no records names it for) may be named apart from its repository.
    repo='' main=''; IFS=$'\t' read -r repo main < <(record_of "$gh" "$recs")
    if [ -z "$main" ]; then bad+=("${nums// /, } of $gh: no record of $HOSTF is for $gh; it looked at $(awk -F'\t' '{ printf "%s%s (main %s)", (NR > 1 ? ", " : ""), $1, $2 }' <<<"$recs"), and none has a main checkout on this machine whose remote (origin, or its pack's remote) is $gh, nor is named $gh. Set the \"main\" of its record in $HOSTF to its main checkout on this machine, or run conveyor.sh setup in that checkout")
    else
      c=$(ask "$repo" "$main" control adopt $nums 2>&1); rc=$?
      # An engine before `control adopt` (a record's pack pins its own) refuses it as a usage error (2): hold them.
      [ "$rc" != 2 ] || [[ $c != *'usage: conveyor.sh control'* ]] || { c=$(ask "$repo" "$main" control hold $nums 2>&1); rc=$?; }
      if [ "$rc" = 0 ]; then
        # The record printed last tells which it holds; one not held was released already, and stays so.
        h=$(jq -er '.held | arrays' <<<"${c##*$'\n'}" >/dev/null 2>&1 \
          && jq -r '.held as $h | $ARGS.positional[] | select(tonumber | IN($h[]))' --args $nums <<<"${c##*$'\n'}" | paste -sd' ' -) || h=$nums
        r=$(printf '%s\n' $nums | grep -vxF -f <(printf '%s\n' $h) | paste -sd' ' -)
        [ -z "$h" ] || said+=("$repo: ${h// /, }"); [ -z "$r" ] || freed+=("$repo: ${r// /, }")
      else bad+=("${nums// /, } of $repo (${c##*$'\n'})"); fi
    fi
  done < <(awk '{ print $1 }' <<<"$n" | uniq)
  # Only once every issue is held do the records start new issues in the queue again.
  left=$(queue_again | paste -sd' ' -)
  if [ ${#bad[@]} != 0 ] || [ -n "$left" ]; then
    jq -cn --arg r "${bad[*]:+Not held in Conveyor: ${bad[*]}. Hold each issue you filed (conveyor.sh control hold <issue>, in its record) unless the owner has said yes to it. }${left:+New issues of $left still start held: set them back (conveyor.sh control start queue, in each) unless the owner set them held.}" '{decision: "block", reason: $r}'
  elif [ ${#said[@]} != 0 ] || [ ${#freed[@]} != 0 ]; then
    jq -cn --arg e "$ev" --arg c "${said[*]:+Held in Conveyor (${said[*]}): not built until you release it (conveyor.sh control release <issue>, in its record), which you do only once the owner has said yes to it. }${freed[*]:+Not held, as released already (${freed[*]}).}" \
      '{hookSpecificOutput: {hookEventName: $e, additionalContext: $c}}'
  fi
}

# words: in a project's main checkout, the claim, its reply the claim's first line and its cache-time line if any (a
# prompt hook's additionalContext).
words() {
  local out ttl n
  inmain || return 0
  if out=$(claim_cmd claim "$SID" 2>&1); then
    # The claim's line on a cache time other than 1h is part of the reply, so the owner sees it.
    ttl=$(grep -m1 '^The Foreman runs with the prompt cache time ' <<<"$out") && n='these two lines' || n='this one line'
    out="The owner asked, in words, for this session to be the Foreman, and it now is. Reply with only $n: ${out%%$'\n'*}${ttl:+$'\n'$ttl}"$'\n'"From this turn on, work by the rest of this as the Foreman."$'\n\n'"${out#*$'\n'}"
  else out="The owner asked, in words, for this session to be the Foreman, and the claim failed. Show the owner this and stop: $out"; fi
  jq -cn --arg c "$out" '{hookSpecificOutput: {hookEventName: "UserPromptSubmit", additionalContext: $c}}'
}

# ask <repo> <command> [<argument>...]: one engine command of that record of this Foreman's (mine), run where the
# record is (lib.sh ask: over ssh when the host file names a host); the standing kinds' rules name it (context).
ask_cmd() {
  local repo main
  main=$(mine | awk -F'\t' -v r="$2" '$1 == r { print $2; exit }') && [ -n "$main" ] \
    || { echo "foreman: ask: $2 is not a record of this Foreman" >&2; return 1; }
  # `foreman status` over ssh ends with the watcher and waiter of the host's Foreman folder, where no Foreman runs: those
  # two lines are replaced with this Foreman's own.
  if [ "$3 ${4:-}" = "foreman status" ]; then
    local out rc
    out=$(ask "$2" "$main" "${@:3}"); rc=$?
    [ "$rc" != 0 ] || out=$(grep -v '^\(watcher\|waiter\): ' <<<"$out"; status_tail)
    [ -z "$out" ] || printf '%s\n' "$out"
    return "$rc"
  fi
  ask "$2" "$main" "${@:3}"
}

if [ "$1" = claim ]; then claim_cmd "$@"; elif [ "$1" = ask ]; then ask_cmd "$@"; else "$1" "$@"; fi
