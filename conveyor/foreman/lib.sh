#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Foreman mode's shared reading (plan docs/plans/conveyor-plugin-2026-11-10.md, section 11b). Sourced, never run.
# The Foreman is the session in a project's main checkout that /conveyor-belt:foreman (or the launcher `conveyor.sh
# foreman`, or the owner's words: foreman.sh words) marks: it watches that project's Conveyor and brings the owner what needs them. There is one Foreman per
# project, never one for the machine: a Foreman watching several projects would mix their memory, rules, state and
# decisions in one context. The one exception is a group of linked projects (the host file's foreman.groups, lists
# of record names), whose work drives each other: they share one Foreman (mine, below). Nothing here names a project
# or a person: the Foreman's name is the host file's foreman.name (default "Foreman"), and its folder is `foreman` in
# its project's state folder (conveyor.sh state-dir of that checkout), for a group the first-named project's.
# FD: the Foreman's folder (CONVEYOR_FOREMAN_DIR, which the launcher and the settings setup writes both set).
# HOSTF: the host file. NAME: the Foreman's name. pending_put / pending_run: the one path of a wake (below).
FHERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
. "$FHERE/../lib/portable.sh" && require_bash 5.1 && p_tools || exit 1
ENGINE=$FHERE/../conveyor.sh
HOSTF=${XDG_CONFIG_HOME:-$HOME/.config}/conveyor/host.json
# The main checkout this runs for: the launcher's CONVEYOR_MAIN, else the checkout the session runs in, exported so
# the Foreman's folder and every watcher are this checkout's in a session started any way.
export CONVEYOR_MAIN=${CONVEYOR_MAIN:-$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null | sed 's|/\.git$||')}

# records: every record of the host file, "<repo> TAB <main>" one per line; a host file with no records has one, the
# main checkout this runs for, named for its folder. Nonzero, with the reason, when the records are not understood.
# The Board and doctor read every record; a Foreman watches only its own (mine), and reads every record only to
# hold an issue it files wherever it lands (foreman.sh filing and filed).
records() {
  jq -er --arg m "$CONVEYOR_MAIN" '(.records // [{repo: ($m | split("/") | last), main: $m}])
    | select(type == "array" and length > 0 and all(type == "object" and (.repo | type == "string" and test("^[A-Za-z0-9._-]+$"))
        and (.main | type == "string" and test("^/[A-Za-z0-9._/-]+$"))) and (map(.repo) | unique | length) == length)
    | .[] | "\(.repo)\t\(.main)"' "$HOSTF" 2>/dev/null || { echo "the records of $HOSTF are not understood" >&2; return 1; }
}
# repo_name: this checkout's repository name, from the address of the remote its pack names (.remote, default
# origin): the last part of git@host:owner/name.git or https://host/owner/name. Empty when there is none.
repo_name() {
  local r u
  r=$(jq -r '.remote // "origin" | strings' "$CONVEYOR_MAIN/.conveyor/project.json" 2>/dev/null) && [ -n "$r" ] || r=origin
  u=$(git -C "$CONVEYOR_MAIN" remote get-url -- "$r" 2>/dev/null) || return 0
  u=${u%/}; u=${u%.git}; u=${u##*[/:]}
  [[ $u =~ ^[A-Za-z0-9._-]+$ ]] && printf '%s' "$u"
  return 0
}
# ledger <repo> <main>: the checkout whose decision ledger (.claude/metrics/decisions.jsonl) a record's open decisions
# are read from: its main when that is on this machine; else, for the record mine matched by this checkout's
# repository (repo_name), the checkout this runs for, where the Foreman writes and answers them. Nonzero for any
# other record whose main is not on this machine: its ledger is not here.
ledger() {
  if [ -d "$2" ]; then printf '%s' "$2"
  elif [ -n "$1" ] && [ "$1" = "$(repo_name)" ] && [ -d "$CONVEYOR_MAIN" ]; then printf '%s' "$CONVEYOR_MAIN"
  else return 1; fi
}
# mine: the records this checkout's Foreman watches, as records prints them: its own record (the one whose main is
# this checkout; else the one named for this checkout's repository (repo_name), whose main is then on the host the
# Foreman asks (ask), as when the owner runs the Foreman on their own machine and the belt on another; a checkout no
# record names either way is its own, named for its folder), or, when a list of the host file's
# foreman.groups names that record, every record that list names, in its order; a name no record has is passed
# over. foreman.groups is lists of names with no name in two lists, or twice in one: a project in two groups would
# have two Foremen, so such groups are not understood. Paths are compared with their links resolved, so a record that
# names its checkout by a link is still this checkout's.
mine() {
  local recs repo main real
  recs=$(records) || return 1
  recs=$(while IFS=$'\t' read -r repo main; do
    real=$(cd "$main" 2>/dev/null && pwd -P) || real=$main
    printf '%s\t%s\t%s\n' "$repo" "$main" "$real"
  done <<<"$recs")
  real=$(cd "$CONVEYOR_MAIN" 2>/dev/null && pwd -P) || real=$CONVEYOR_MAIN
  jq -er --arg m "$CONVEYOR_MAIN" --arg p "$real" --arg n "$(repo_name)" --arg recs "$recs" '
    [$recs | split("\n")[] | select(. != "") | split("\t") | {repo: .[0], main: .[1], real: .[2]}] as $r
    | (.foreman.groups // []) as $gs
    | select($gs | type == "array" and all(type == "array" and all(type == "string")) and ([.[][]] | length == (unique | length)))
    | (first($r[] | select(.main == $m or .real == $p)) // first($r[] | select($n != "" and .repo == $n))
        // {repo: ($m | split("/") | last), main: $m, none: true}) as $own
    | if $own.none then [$own]
      else (first($gs[] | select(any(.[]; . == $own.repo))) // [$own.repo]) as $g
        | [$g[] as $n | $r[] | select(.repo == $n)] end
    | .[] | "\(.repo)\t\(.main)"' "$HOSTF" 2>/dev/null \
    || { echo "the Foreman's records in $HOSTF are not understood (foreman.groups must name each project once at most)" >&2; return 1; }
}
FD=${CONVEYOR_FOREMAN_DIR:-}
if [ -z "$FD" ]; then
  # The folder of the first project mine names (this checkout's own, but for a group); this checkout's when mine
  # cannot be read, where no claim is made (claim_), or when that project's main is not on this machine (a record
  # matched by its repository, its belt on another host): the Foreman's folder is always on the machine it runs on.
  FM=$(mine 2>/dev/null) && FM=${FM%%$'\n'*} && FM=${FM#*$'\t'} && [ -d "$FM" ] || FM=$CONVEYOR_MAIN
  FD=$(CONVEYOR_MAIN=$FM bash "$ENGINE" state-dir)/foreman || exit 1
fi
NAME=$(jq -r '.foreman.name // empty | strings' "$HOSTF" 2>/dev/null); NAME=${NAME:-Foreman}
# The Foreman is marked by session, one per project (or group): its folder FD holds session, "<session id> <time
# claimed>" (empty once turned off), so a session continued or resumed any way stays the Foreman, and a claim in
# another session of the same project (or of a project of its group) moves the role; a claim in another project
# moves nothing here. foreman <session id> (the hook input's session_id): 0 when
# that session is the marked one, or, while no session was ever marked, when the launcher set CONVEYOR_FOREMAN=1
# (the launcher's start marks its own session at once). Every hook stands down in any other session.
MARK=$FD/session
marked() { local s=; read -r s _ 2>/dev/null < "$MARK"; printf '%s' "$s"; }
foreman() {
  [ -n "${1:-}" ] && [ "$1" = "$(marked)" ] && return 0
  [ ! -e "$MARK" ] && [ "${CONVEYOR_FOREMAN:-}" = 1 ]
}
# locked <command> [<argument>...]: runs it holding claim.lock, so two changes of the mark or of former never mix.
locked() { mkdir -p "$FD" && ( flock -w 30 9 || exit 1; "$@" ) 9>>"$FD/claim.lock"; }
# former: the sessions that held the role and lost it, one a line: "<id>" until it is told so at its next start, then
# "<id> told". Only a claim takes a session off it, so a former Foreman never takes the role back by a resume.
# forget <session id>: takes it off former. told <session id>: marks it told.
forget() { touch "$FD/former" && awk -v s="$1" '$1 != s' "$FD/former" > "$FD/former.new" && mv "$FD/former.new" "$FD/former"; }
told() { awk -v s="$1" '{ print ($0 == s ? s " told" : $0) }' "$FD/former" > "$FD/former.new" && mv "$FD/former.new" "$FD/former"; }
# claim <session id>: marks that session the Foreman; an empty id turns the role off. The session that held it is
# listed in former and its waiter is stopped now, so its watchers exit before the new Foreman's waiter starts: two
# Foremen never run the same watchers. Refused while mine is (groups not understood): which folder is the
# Foreman's cannot be told then, and a mark in the wrong one would make a second Foreman.
claim() { locked claim_ "${1:-}"; }
claim_() {
  local old pid sid w3=''
  mine > /dev/null || return 1
  old=$(marked)
  [ -z "$old" ] || [ "$old" = "$1" ] || { forget "$old" && printf '%s\n' "$old" >> "$FD/former"; } || return 1
  forget "${1:-}" || return 1
  if [ -n "$1" ]; then printf '%s %s\n' "$1" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$MARK.new"; else : > "$MARK.new"; fi
  mv "$MARK.new" "$MARK" || return 1
  # A waiter writes waiter.pid, then checks the mark (waiter.sh): one that wrote it after this read sees the new mark.
  # The session is the fourth field, or the third in a waiter.pid of an older engine's waiter (no session's process).
  { read -r pid _ w3 sid < "$FD/waiter.pid"; } 2>/dev/null || return 0
  [ -n "$sid" ] || [[ $w3 =~ ^[0-9]+$ ]] || sid=$w3
  [ "$sid" != "$1" ] || return 0
  flock -n "$FD/waiter.lock" true 2>/dev/null && return 0 # no waiter alive
  kill -TERM "$pid" 2>/dev/null; flock -w 10 "$FD/waiter.lock" true \
    || { echo "foreman: the previous Foreman's waiter (pid $pid) did not stop" >&2; return 1; }
}

# waiter_state: the Foreman's waiter now, one line. "listening" while the pid waiter.pid names runs waiter.sh; else,
# from the last line of waiter.log (waiter.sh log), "starting again" for a minute after it was written, then
# "down: <why the waiter ended>". A waiter killed with no chance to write leaves another line last, which says nothing
# of when it ended: the first read that finds it so writes its end line then, so the minute counts from that read.
waiter_state() {
  local pid='' line t
  { read -r pid _ < "$FD/waiter.pid"; } 2>/dev/null
  if [[ $pid =~ ^[0-9]+$ ]] && ps -o args= -p "$pid" 2>/dev/null | grep -q '/conveyor/foreman/waiter\.sh'; then echo listening; return; fi
  line=$(tail -n 1 "$FD/waiter.log" 2>/dev/null)
  [ -n "$line" ] || { echo 'down: no waiter has run yet; the end of the next turn starts one'; return; }
  case ${line#* * } in
    'ended: '*) ;;
    *) printf '%s %s ended: it was killed with no time to say why (its last line: %s)\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "${pid:--}" "${line#* * }" >> "$FD/waiter.log" ;;
  esac 2>/dev/null
  line=$(tail -n 1 "$FD/waiter.log" 2>/dev/null)
  t=$(p_stat "$FD/waiter.log" | cut -d' ' -f2)
  [ $(( $(date +%s) - ${t:-0} )) -gt 60 ] || { echo 'starting again'; return; }
  echo "down: ${line#* * ended: }"
}

# ask <repo> <main> <command> [<argument>...]: one Conveyor command (snapshot, health, control ...) of a record, by
# the commit its own pack pins (or its current engine, for a pack that follows the plugin's main), run over ssh at
# the host file's ssh target when it names one, else on this machine.
# CONVEYOR_FOREMAN_ASK, when set, runs in its place with CONVEYOR_REPO, CONVEYOR_MAIN and CONVEYOR_CMD (the command
# and its arguments, space-separated) set (the tests' seam).
ask() {
  local cmd target
  if [ -n "${CONVEYOR_FOREMAN_ASK:-}" ]; then CONVEYOR_REPO=$1 CONVEYOR_MAIN=$2 CONVEYOR_CMD="${*:3}" bash -c "$CONVEYOR_FOREMAN_ASK" < /dev/null; return; fi
  # A pin names a version folder, so only a full commit id may (as the shim requires): anything else could name a
  # path outside versions/. A pack that follows the plugin's main runs that machine's current engine (as the shim). A
  # pack with no plugin key (the plugin's own checkout) runs the engine of the checkout itself, as its loop does.
  printf -v cmd 'cd %q && if jq -e ".plugin == null" .conveyor/project.json >/dev/null 2>&1; then e=$PWD/conveyor/conveyor.sh; else p=$(if jq -e .plugin.follow .conveyor/project.json >/dev/null 2>&1; then jq -er %q .git/conveyor-engine.json; else jq -er %q .conveyor/project.json; fi) && e=${XDG_DATA_HOME:-$HOME/.local/share}/conveyor/versions/$p/conveyor/conveyor.sh; fi && CONVEYOR_MAIN=%q bash "$e"' \
    "$2" '.commit | select(type == "string" and test("^[0-9a-f]{40}$"))' '.plugin.commit | select(type == "string" and test("^[0-9a-f]{40}$"))' "$2"
  printf -v cmd '%s%s' "$cmd" "$(printf ' %q' "${@:3}")"
  target=$(jq -er '.ssh | select(type == "string" and test("^[A-Za-z0-9][A-Za-z0-9._@-]*$"))' "$HOSTF" 2>/dev/null) || target=''
  if [ -n "$target" ]; then
    timeout -k 2 "${ASK_LIMIT:-45}" ssh -o BatchMode=yes -o ConnectTimeout=5 "$target" "$cmd" < /dev/null
  else timeout -k 2 "${ASK_LIMIT:-45}" bash -c "$cmd" < /dev/null; fi
}

# The pending items (a watcher's wake, owed to the session). $FD/pending holds one file per wake, written as
# <name>.tmp and renamed into place, so a reader sees a whole file or none. A watcher puts its wake here BEFORE it
# records the item as seen: a kill between the two repeats the item, never loses it. The waiter (waiter.sh) relays
# them and removes exactly what it relayed.
PENDING=$FD/pending
pending_put() { # stdin becomes one pending wake; nonzero when not written
  local f
  mkdir -p "$PENDING" && f=$(mktemp "$PENDING/.put.XXXXXX") && cat > "$f" \
    && mv "$f" "$PENDING/$(date -u +%Y%m%dT%H%M%SZ)-$$-${f##*.put.}.wake"
}
# pending_run <ack file>: prints every pending wake whole, oldest first, and lists each printed file in <ack file>.
# 0 when it printed anything.
pending_run() {
  local f n=0
  for f in "$PENDING"/*.wake; do
    [ -f "$f" ] || continue
    cat "$f" && printf '%s\n' "$f" >> "$1" && n=$((n + 1))
  done
  [ "$n" -gt 0 ]
}
