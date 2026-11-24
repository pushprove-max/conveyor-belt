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
# LAUNCHER: the one command the start text gives for foreman.sh. Its path is the same in every version of the engine
# (it is not in a version folder, which a prune removes), and it runs foreman.sh of the project's current engine, found as
# shim.sh finds it: the pack's pin, or the commit of the project's engine record (a following pack), read at each run.
LAUNCHER=${XDG_DATA_HOME:-$HOME/.local/share}/conveyor/foreman.sh
# launcher: makes LAUNCHER when it is missing or differs from this engine's text, as the start runs it. The file is made
# beside its place and moved in, so a run of it never reads half of it. A pack with no plugin key (the plugin's own
# checkout) runs the checkout's own engine, as ask does. A text that could not be written whole (a full disk) is
# never moved in: the launcher there stays, and the failure is the return status, which context says in the start.
launcher() {
  local t bad="foreman: $LAUNCHER cannot be made new: the start's foreman.sh command may not run, or runs the launcher already there"
  t=$(mktemp "$LAUNCHER.XXXXXX" 2>/dev/null) || { mkdir -p "${LAUNCHER%/*}" && t=$(mktemp "$LAUNCHER.XXXXXX"); } || { echo "$bad" >&2; return 1; }
  cat > "$t" <<'EOF' || { rm -f "$t"; echo "$bad" >&2; return 1; }
#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Conveyor's Foreman command (written by the Foreman's start): runs foreman.sh of the engine this project runs.
set -uo pipefail
main=${CONVEYOR_MAIN:-}
[ -n "$main" ] || { main=$(git -C "${CLAUDE_PROJECT_DIR:-.}" rev-parse --path-format=absolute --git-common-dir 2>/dev/null) && main=${main%/.git}; } || main=
pack=$main/.conveyor/project.json
[ -n "$main" ] && [ -f "$pack" ] || { echo "foreman.sh: run it in a Conveyor project's checkout, or set CONVEYOR_MAIN" >&2; exit 1; }
if jq -e '.plugin == null' "$pack" > /dev/null 2>&1; then e=$main/conveyor/foreman/foreman.sh
else
  if jq -e .plugin.follow "$pack" > /dev/null 2>&1; then c=$(jq -er '.commit | select(type == "string" and test("^[0-9a-f]{40}$"))' "$main/.git/conveyor-engine.json" 2>/dev/null)
  else c=$(jq -er '.plugin.commit | select(type == "string" and test("^[0-9a-f]{40}$"))' "$pack" 2>/dev/null); fi
  [ -n "${c:-}" ] || { echo "foreman.sh: $main has no Conveyor engine commit; run /conveyor-belt:setup" >&2; exit 1; }
  e=${XDG_DATA_HOME:-$HOME/.local/share}/conveyor/versions/$c/conveyor/foreman/foreman.sh
fi
[ -f "$e" ] || { echo "foreman.sh: the project's engine $e is not installed; run /conveyor-belt:setup" >&2; exit 1; }
CONVEYOR_MAIN=$main exec bash "$e" "$@"
EOF
  if cmp -s "$t" "$LAUNCHER"; then rm -f "$t"; else chmod 755 "$t" && mv "$t" "$LAUNCHER" \
    || { rm -f "$t"; echo "$bad" >&2; return 1; }; fi
}
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
# repo_name [<checkout>]: the repository name of that checkout (default this one), from the address of the remote
# its pack names (.remote, default origin): the last part of git@host:owner/name.git or https://host/owner/name.
# Empty when there is none.
repo_name() {
  local m=${1:-$CONVEYOR_MAIN} r u
  r=$(jq -r '.remote // "origin" | strings' "$m/.conveyor/project.json" 2>/dev/null) && [ -n "$r" ] || r=origin
  u=$(git -C "$m" remote get-url -- "$r" 2>/dev/null) || return 0
  u=${u%/}; u=${u%.git}; u=${u##*[/:]}
  [[ $u =~ ^[A-Za-z0-9._-]+$ ]] && printf '%s' "$u"
  return 0
}
# plugin_home: 0 when one of the Foreman's projects (mine) is the plugin's own repository: a main checkout on this
# machine whose remote (the pack's .remote, default origin) is the repository this plugin's plugin.json names, owner
# and name alike (case aside). A record whose main is on another host (its belt runs there) is read from the checkout
# this runs for (ledger). There the Foreman files a plugin problem itself (stop.sh, context).
plugin_home() {
  local want repo main
  want=$(slug_of "$(jq -r '.repository | if type == "object" then .url else . end | strings' "$FHERE/../../.claude-plugin/plugin.json" 2>/dev/null)") \
    && [ -n "$want" ] || return 1
  while IFS=$'\t' read -r repo main; do
    [ -n "$main" ] && main=$(ledger "$repo" "$main") || continue
    [ "$(repo_slug "$main")" = "$want" ] && return 0
  done < <(mine 2>/dev/null)
  return 1
}
# slug_of <address>: "owner/name" of git@host:owner/name.git or https://host/owner/name, lower case; nonzero for none,
# as for a remote that is a folder on this machine (a path or file:// address), which names no hosted repository.
slug_of() { local s=${1%/} n; case $s in /* | .* | '~'* | file:*) return 1 ;; esac
  s=${s%.git}; s=${s//:/\/}; [[ $s == */*/* ]] || return 1; n=${s##*/}; s=${s%/*}; s="${s##*/}/$n"
  [[ ${s,,} =~ ^[a-z0-9._-]+/[a-z0-9._-]+$ ]] && printf '%s' "${s,,}"; }
# repo_slug <checkout>: slug_of the remote its pack names (.remote, default origin); nonzero when there is none.
repo_slug() {
  local r u
  r=$(jq -r '.remote // "origin" | strings' "$1/.conveyor/project.json" 2>/dev/null) && [ -n "$r" ] || r=origin
  u=$(git -C "$1" remote get-url -- "$r" 2>/dev/null) && slug_of "$u"
}
# host_slug <main>: repo_slug of a main checkout on the host file's ssh target (the host ask runs commands on);
# nonzero when the host file names none, or the host does not answer within 10 s.
host_slug() {
  local t c u
  t=$(host_ssh) && [ -n "$t" ] || return 1
  printf -v c 'cd %q || exit 1; r=$(jq -r %q .conveyor/project.json 2>/dev/null); git remote get-url -- "${r:-origin}"' "$1" '.remote // "origin" | strings'
  u=$(timeout -k 2 10 ssh -o BatchMode=yes -o ConnectTimeout=5 "$t" "$c" < /dev/null 2>/dev/null) && slug_of "$u"
}
# record_of <owner/name> <records>: the record, "<repo> TAB <main>" as records prints them, that holds an issue of the
# GitHub repository <owner/name>: the first whose main checkout has that repository, owner and name (repo_slug of a
# checkout on this machine, a worktree of it, as the checkout a hook runs in may be, sharing its remotes; else
# host_slug, read on the host its belt runs on); else the one named <name> (so a record whose main cannot be read either way is
# still found by its name), unless its main has another repository (another owner's of that name, or another name):
# that is another project. Letter case aside, as GitHub prints a repository's name in its own case. Empty when none is.
record_of() {
  local rec main s n=${1,,} other=()
  while IFS=$'\t' read -r rec main; do
    [ -n "$main" ] || continue
    # A folder here with no checkout in it (as an empty folder at a path of the belt's host is) is read on the host.
    s=''; [ ! -e "$main/.git" ] || s=$(repo_slug "$main"); [ -n "$s" ] || s=$(host_slug "$main") || continue
    [ "$s" != "$n" ] || { printf '%s\t%s\n' "$rec" "$main"; return 0; }
    other+=("$rec")
  done <<<"$2"
  awk -F'\t' -v r="${n#*/}" -v o="$(printf '%s\n' "${other[@]}")" 'BEGIN { k = split(o, x, "\n"); for (i = 1; i <= k; i++) skip[x[i]] = 1 }
    tolower($1) == r && !($1 in skip) { print; exit }' <<<"$2"
}
# The filing hooks' shared state (foreman.sh filing and filed), in the folder of filings SF, for the Bash call TID.
# ends: under the shared lock, each filing's end left in $SF/ended takes its line from $SF/in.
ends() {
  local f ins
  for f in "$SF"/ended/*; do
    [ -f "$f" ] || continue
    ins=$(F=$(cat "$f") awk '!d && $0 == ENVIRON["F"] { d = 1; next } 1' "$SF/in" 2>/dev/null) && printf '%s' "${ins:+$ins$'\n'}" > "$SF/in" && rm -f "$f"
  done
}
# mark <repo> <main>: before a command that may file an issue runs, marks the record (control filing on), so its loop
# holds every issue opened from now on from its first sight, a follow-up too (adopted(), lib/control.sh), which it
# otherwise passes over: else it could pick a follow-up the command filed before filed holds it. The record is listed
# in $SF/marked, where unmark finds it. Prints why when it is not marked. An engine before the mark (the record's pin)
# refuses it as a usage error (2): its loop reads no mark and passes over a follow-up, so that is not marked either.
mark() {
  local c
  c=$(ask "$1" "$2" control filing on 2>&1) || { [ $? = 2 ] && [[ $c == *'usage: conveyor.sh control'* ]] && c="its engine has no control filing; update the engine it runs"; printf '%s\n' "${c##*$'\n'}"; return 1; }
  grep -qxF -- "$1" "$SF/marked" 2>/dev/null || printf '%s\n' "$1" >> "$SF/marked"
}
# unmark: under the shared lock, once no filing is in flight (queue_again, foreman.sh), takes each listed mark off
# (control filing off, which holds what was opened since it was set, a follow-up too). A record in $SF/held is passed
# over: its Queue (control start queue filed) takes the mark off too. Prints each record whose mark stays, still listed.
unmark() {
  local repo main c left=()
  while read -r repo; do
    [ -n "$repo" ] && ! grep -qxF -- "$repo" "$SF/held" 2>/dev/null || continue
    main=$(awk -F'\t' -v r="$repo" '$1 == r { print $2; exit }' <<<"$(records 2>/dev/null)")
    [ -n "$main" ] && { c=$(ask "$repo" "$main" control filing off 2>&1) || { [ $? = 2 ] && [[ $c == *'usage: conveyor.sh control'* ]]; }; } || left+=("$repo")
  done < <(cat "$SF/marked" 2>/dev/null)
  if [ ${#left[@]} = 0 ]; then rm -f "$SF/marked"; else printf '%s\n' "${left[@]}" > "$SF/marked"; printf '%s\n' "${left[@]}"; fi
}
# kept_file: this filing's list of the records that started new issues held before it began (the owner's Held): the
# UTC time it began on its first line, a record a line after. No filing ends that Held, so no Queue of filed's holds
# what the command files there, and once its mark is off (unmark) the loop's own hold passes over a follow-up (adopted(), lib/control.sh).
kept_file() { printf '%s/kept-%s' "$SF" "${TID//[^A-Za-z0-9_-]/_}"; }
# kept_put <record>...: writes the list, timed now, before the command runs: what it files is created on or after it.
kept_put() { { jq -rn '(($ENV.CONVEYOR_NOW // "" | tonumber?) // now) | todate' && printf '%s\n' "$@"; } > "$(kept_file)"; }
# kept_hold <records, as records prints them>: in each record of the list, every open issue opened since the filing
# began is held (control adopt since); prints a line for each record where it was not. The list is removed.
kept_hold() {
  local k t repo main c kr=()
  k=$(kept_file)
  if [ -s "$k" ]; then
    { IFS= read -r t; mapfile -t kr; } < "$k"
    for repo in "${kr[@]}"; do
      main=$(awk -F'\t' -v r="$repo" '$1 == r { print $2; exit }' <<<"$1")
      c='no record of that name'; [ -n "$main" ] && c=$(ask "$repo" "$main" control adopt since "$t" 2>&1) || printf '%s\n' "the issues filed in $repo since $t (${c##*$'\n'})"
    done
  fi
  rm -f "$k"
}
# ledger <repo> <main>: the checkout whose decision ledger (.claude/metrics/decisions.jsonl) a record's open decisions
# are read from: its main when that is a checkout on this machine (it has .git: an empty folder at a path of the
# belt's host is none); else, for the record mine matched by this checkout's repository (repo_name), the checkout
# this runs for, where the Foreman writes and answers them. Nonzero for any other record whose main is not on this
# machine: its ledger is not here.
ledger() {
  if [ -e "$2/.git" ]; then printf '%s' "$2"
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
# await_start <session id>: waits, at most 10 s, until the session's start hook (foreman.sh start), which runs beside the
# caller, has ended: that hook writes the session to $FD/started, read only when written in the 5 s before this began or
# since, so an earlier start of the session never ends the wait.
await_start() {
  local _
  for _ in $(seq 50); do
    [ "$(cat "$FD/started" 2>/dev/null)" = "$1" ] && p_newer "$FD/started" $((SECONDS + 5)) && break
    sleep 0.2 # sleep: the poll of the file the session's start hook writes
  done
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
# Foremen never run the same watchers. A claim by the session that holds the role replaces its Stop hook's waiter
# (below). Refused while mine is (groups not understood): which folder is the
# Foreman's cannot be told then, and a mark in the wrong one would make a second Foreman.
claim() { locked claim_ "${1:-}"; }
# cc_pid: the Claude Code process this command runs under: the nearest of its ancestors with a sessions/<pid>.json
# (Claude Code's file for a running session); prints nothing when there is none.
cc_pid() {
  local p=$PPID cc=${CLAUDE_CONFIG_DIR:-$HOME/.claude}
  while [ "${p:-0}" -gt 1 ] && [ ! -f "$cc/sessions/$p.json" ]; do p=$(ps -o ppid= -p "$p" 2>/dev/null | tr -d ' '); done
  [ "${p:-0}" -gt 1 ] && printf '%s' "$p"
}
# claude_rec: records the Claude process of the marked session in $FD/claude.pid (empty when none is found).
claude_rec() { { cc_pid > "$FD/claude.pid.new" || : ; } && mv "$FD/claude.pid.new" "$FD/claude.pid"; }
claim_() {
  local old pid sid w3=''
  mine > /dev/null || return 1
  old=$(marked)
  [ -z "$old" ] || [ "$old" = "$1" ] || { forget "$old" && printf '%s\n' "$old" >> "$FD/former"; } || return 1
  forget "${1:-}" || return 1
  if [ -n "$1" ]; then printf '%s %s\n' "$1" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$MARK.new"; else : > "$MARK.new"; fi
  mv "$MARK.new" "$MARK" || return 1
  # The Claude process of the session just marked, so a /clear in it keeps the role (foreman.sh cleared_).
  claude_rec || return 1
  # A waiter writes waiter.pid, then checks the mark (waiter.sh): one that wrote it after this read sees the new mark.
  # The session is the fourth field, or the third in a waiter.pid of an older engine's waiter (no session's process).
  { read -r pid _ w3 sid < "$FD/waiter.pid"; } 2>/dev/null || return 0
  [ -n "$sid" ] || [[ $w3 =~ ^[0-9]+$ ]] || sid=$w3
  # The session's own waiter is left running, but for its Stop hook's (no --held): that hook may be one the session
  # no longer reads, in the same process (Claude Code's /restart, issue 594), which nothing outside it can tell. So it
  # is replaced by a waiter that listens until the next stop; its wakes stay pending for that stop.
  if [ "$sid" = "$1" ]; then
    [[ $pid =~ ^[0-9]+$ ]] && ps -o args= -p "$pid" 2>/dev/null | grep -q '/conveyor/foreman/waiter\.sh *$' || return 0
  fi
  flock -n "$FD/waiter.lock" true 2>/dev/null && return 0 # no waiter alive
  kill -TERM "$pid" 2>/dev/null; flock -w 10 "$FD/waiter.lock" true \
    || { echo "foreman: the previous Foreman's waiter (pid $pid) did not stop" >&2; return 1; }
  # Not on claim.lock (fd 9): the waiter it starts runs on, and would hold that lock from every later claim.
  [ "$sid" != "$1" ] || jq -cn --arg s "$1" '{session_id: $s}' \
    | bash "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/waiter.sh" --check > /dev/null 2>&1 9>&-
  return 0
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

# healsdef: prints the jq def healsline, the Foreman status's self-heals line (watch-conveyor.sh STATUS), of a
# snapshot's selfheals (snapshot.sh): its count, and when the sort of the queued follow-ups ran; none when the list is
# empty and no sort ran. The list is no one's work now (an area's batch card, filed from the Board, fixes it), so the
# line is never a "needs you".
healsdef() {
  printf '%s' 'def healsline: ([.areas[]?.count | numbers] | add // 0) as $n | select($n > 0 or .sorted != null)
  | "self-heals list: \($n) finding(s) for the batch cards of their areas, filed from the Board (nothing to act on now)"
    + (if .sorted then "; the sort of the queued follow-ups ran at \(.sorted.time) and moved \(.sorted.moved) of \(.sorted.items)"
         + (if .sorted.failed then " (its judge failed: \(.sorted.failed))" else "" end)
       else "; the sort of the queued follow-ups has not run" end);'
}

# status_tail: the last two lines of the Foreman's status, read from this machine's Foreman folder: the watcher's last
# poll (conveyor-polls.log) and the waiter (waiter_state).
status_tail() {
  local t1 took rest
  if read -r _ t1 took rest < <(tail -n 1 "$FD/conveyor-polls.log" 2>/dev/null); [ -n "${rest:-}" ]; then
    echo "watcher: last poll ended $t1, took ${took%s} s ($rest)"
  else echo "watcher: no poll logged yet"; fi
  echo "waiter: $(waiter_state)"
}

# ask <repo> <main> <command> [<argument>...]: one Conveyor command (snapshot, health, control ...) of a record, by
# the commit its own pack pins (or its current engine, for a pack that follows the plugin's main), run over ssh at
# the host file's ssh target when it names one, else on this machine. testissue runs with the Foreman's mark,
# CONVEYOR_FOREMAN=1, so it holds the issue it files: the engine on the host, or of another project of the group,
# cannot see this machine's mark file. ask adds the mark to no other command: a session one starts (a card's) would
# claim the role. CONVEYOR_REVIEWRETRY, when set (reviewretry(), watch-conveyor.sh: the card), goes to the command too: the
# host's `retry` marks its retry as review-retry's (commands/retry.sh). `retry` runs with CONVEYOR_RETRYBY=foreman, so
# the host does not take a Foreman's retry (a standing rule's, fixed-block) for the owner's own. A command run on this
# machine still inherits the Foreman session's own environment, mark included.
# The command reads nothing, unless ASK_IN names a file: the command then reads that file (`auto rulings`).
# CONVEYOR_FOREMAN_ASK, when set, runs in its place with CONVEYOR_REPO, CONVEYOR_MAIN and CONVEYOR_CMD (the command
# and its arguments, space-separated) set (the tests' seam).
host_ssh() { # the host file's ssh target, empty when it names none (or one that is not a plain host name)
  jq -er '.ssh | select(type == "string" and test("^[A-Za-z0-9][A-Za-z0-9._@-]*$"))' "$HOSTF" 2>/dev/null || :
}
ask() {
  local cmd fm=
  [ "$3" != testissue ] || fm='CONVEYOR_FOREMAN=1 '
  [ -z "${CONVEYOR_REVIEWRETRY:-}" ] || fm+="CONVEYOR_REVIEWRETRY=$(printf %q "$CONVEYOR_REVIEWRETRY") "
  [ "$3" != retry ] || fm+='CONVEYOR_RETRYBY=foreman '
  if [ -n "${CONVEYOR_FOREMAN_ASK:-}" ]; then CONVEYOR_REPO=$1 CONVEYOR_MAIN=$2 CONVEYOR_CMD="${*:3}" bash -c "$CONVEYOR_FOREMAN_ASK" < "${ASK_IN:-/dev/null}"; return; fi
  # A pin names a version folder, so only a full commit id may (as the shim requires): anything else could name a
  # path outside versions/. A pack that follows the plugin's main runs that machine's current engine (as the shim). A
  # pack with no plugin key (the plugin's own checkout) runs the engine of the checkout itself, as its loop does.
  printf -v cmd 'cd %q && if jq -e ".plugin == null" .conveyor/project.json >/dev/null 2>&1; then e=$PWD/conveyor/conveyor.sh; else p=$(if jq -e .plugin.follow .conveyor/project.json >/dev/null 2>&1; then jq -er %q .git/conveyor-engine.json; else jq -er %q .conveyor/project.json; fi) && e=${XDG_DATA_HOME:-$HOME/.local/share}/conveyor/versions/$p/conveyor/conveyor.sh; fi && %sCONVEYOR_MAIN=%q bash "$e"' \
    "$2" '.commit | select(type == "string" and test("^[0-9a-f]{40}$"))' '.plugin.commit | select(type == "string" and test("^[0-9a-f]{40}$"))' "$fm" "$2"
  printf -v cmd '%s%s' "$cmd" "$(printf ' %q' "${@:3}")"
  case $3 in card | testissue) askfiling "$1" "$cmd" ;; *) askrun "$cmd" ;; esac
}
askrun() { # <command>: run where the record is, stopped at the ask limit (exit 124, or 137 once killed)
  local target
  target=$(host_ssh)
  if [ -n "$target" ]; then
    timeout -k 2 "${ASK_LIMIT:-45}" ssh -o BatchMode=yes -o ConnectTimeout=5 "$target" "$1" < "${ASK_IN:-/dev/null}"
  else timeout -k 2 "${ASK_LIMIT:-45}" bash -c "$1" < "${ASK_IN:-/dev/null}"; fi
}
# A filing ask (card, testissue) prints its issue's link as soon as the issue is made, before it holds it in the record
# (cardnew(), testissue(), lib/testaction.sh), and ends 0 once it has printed it. Its limit is the ask limit and GHWAIT
# more, gh_write()'s own limit on gh (lib/issues.sh): stopped while gh waits on GitHub, the issue could be made with no
# link printed. Failed after the link (stopped at its limit, or the ssh connection lost: 255), the issue is made: the
# ask prints the link, says the hold may not be in, and ends 0, so the Foreman does not file it again. Stopped, or the
# connection lost, before the link, it says to look for the issue before it is filed again.
GHWAIT=60
askfiling() { # <repo> <command>
  local out rc u how lim=$((${ASK_LIMIT:-45} + GHWAIT))
  out=$(ASK_LIMIT=$lim askrun "$2"); rc=$?
  [ -z "$out" ] || printf '%s\n' "$out"
  [ "$rc" != 0 ] || return 0
  case $rc in 124 | 137) how="was stopped at its $lim-second limit" ;; 255) how='lost its connection to the host' ;; *) how="ended $rc" ;; esac
  u=$(grep -oE '[^[:space:]]*/issues/[0-9]+' <<<"$out" | tail -n 1)
  if [ -n "$u" ]; then
    echo "foreman: the filing $how after it filed $u: do not file it again. Its hold may not be in: hold it (foreman.sh ask $1 control hold ${u##*/}) unless the owner has said yes, and take its built label off" >&2
    return 0
  fi
  case $rc in 124 | 137 | 255) echo "foreman: the filing $how before it printed an issue link: look for the issue in $1 before you file it again" >&2 ;; esac
  return "$rc"
}

# retryable <record> <jq path to its blocked list>: "<card> TAB <issue>" for each card the standing kind review-retry
# (lib/standing.sh) gives back: blocked by its review (card.sh: "the fix for [P1] ... did not hold after <n> rounds",
# as the Board's reviewWhy reads it, with any notes block() adds after it in brackets, lib/push.sh), with an issue,
# whose reason holds no word of `conveyor.sh auto reserved` (case-insensitive), and not reported yet. Not a card that
# came after a review-retry of its issue (health's reviewRetried, lib/views.sh): review-retry gives an issue back once, and the second
# block waits for the owner, who has it in Needs you (lib/needsask.sh needsask), or the engine lands it while auto is on
# (needsland()). None unless the
# kind is on in the pack now, as `conveyor.sh auto standing` on the record's host reads it: a kept snapshot's standing
# can be from before the owner turned it off, and health has none. Called by watch-conveyor.sh with its $repo, $main,
# $errf and $SEEN.
retryable() {
  local c st res held
  c=$(jq -r "$2"' | arrays | .[] | objects | select((.issue | numbers) > 0 and .reviewRetried != true and (.reason | strings
    | test("\\Athe fix for \\[P[0-3]\\][\\s\\S]* did not hold after [0-9]+ rounds?( \\[[\\s\\S]*\\])?\\z"))) | "\(.card)\t\(.issue)"' <<<"$1" 2>/dev/null \
    | awk -F'\t' -v p="$repo/blocked:" 'FILENAME == ARGV[1] { s[$0]; next } !((p $1) in s)' "$SEEN" -)
  [ -n "$c" ] && st=$(ask "$repo" "$main" auto standing 2>>"${errf:-/dev/null}") && grep -q '^- review-retry:' <<<"$st" || return 0
  # A reason that holds a word of auto.reserved or an item of the owner's profile waits for the owner (needsretry()
  # leaves it too): the words are read from the record's host; none read, none retried.
  res=$(ask "$repo" "$main" auto reserved 2>>"${errf:-/dev/null}") && jq -e arrays >/dev/null 2>&1 <<<"$res" || return 0
  held=$(jq -r --argjson r "$res" "$2"' | arrays | .[] | objects | select((.reason | strings | ascii_downcase) as $t
    | any($r[]; . as $w | $t | contains($w | ascii_downcase))) | .card' <<<"$1" 2>/dev/null) || return 0
  c=$(awk -F'\t' 'FILENAME == ARGV[1] { s[$0]; next } !($1 in s)' <(printf '%s\n' "$held") - <<<"$c")
  [ -z "$c" ] || printf '%s\n' "$c"
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
# pending_fresh: before a stop relays the pending wakes, each blocked card a wake names (its "<repo>: <ref> is blocked
# since" or "has been blocked for" line, or its "not yet reported: blocked <ref>" line) that its record no longer holds
# blocked as the line says, as `conveyor.sh health` reads it now (retried, landed or shut since the watcher put the
# wake, or retried and blocked again: a line whose since, or whose reason, is not health's), is
# taken out, its ref with it from the blocked parts of the wake's first line; a wake left with no other line is
# removed. A record whose health does not read, or gives no blocked list, keeps its lines.
pending_fresh() {
  local f repos repo main now='{}' h n t
  repos=$(cat "$PENDING"/*.wake 2>/dev/null | sed -nE 's/^([A-Za-z0-9._-]+): (.+ is blocked since |.+ has been blocked for |not yet reported: blocked ).*/\1/p' | sort -u)
  [ -n "$repos" ] || return 0
  while IFS= read -r repo; do
    # mine first: a checkout no record names is watched as its own, named for its folder, and is in no record.
    main=$({ mine; records; } 2>/dev/null | awk -F'\t' -v r="$repo" '$1 == r { print $2; exit }')
    [ -n "$main" ] && h=$(ASK_LIMIT=10 ask "$repo" "$main" health 2>/dev/null) \
      && n=$(jq -ce --arg r "$repo" --argjson h "$h" '($h | objects | .blocked | arrays) as $b
        | .[$r] = [$b[] | objects | {ref: ((.name | strings) // "#\(.issue)"), since, why: (.reason | tostring | gsub("\\s+"; " ") | .[0:240])}]' <<<"$now" 2>/dev/null) \
      && now=$n
  done <<<"$repos"
  [ "$now" != '{}' ] || return 0
  for f in "$PENDING"/*.wake; do
    [ -f "$f" ] || continue
    t=$(jq -Rrs --argjson now "$now" "$FRESH" "$f" 2>/dev/null) || continue
    if [ -z "$t" ]; then rm -f "$f"; elif [ "$t" != "$(cat "$f")" ]; then printf '%s\n' "$t" > "$f.tmp" && mv -f "$f.tmp" "$f"; fi
  done
}
# The wake (raw text) without the blocked cards $now (each repo's blocked cards, of the repos read: ref, since and the
# reason as the watcher's line gives it) no longer holds. A line's reason is health's whole, but for the time of an
# older snapshot the watcher may put after it (watch-conveyor.sh $asof) and the note of a review-retry that failed
# after that (reviewretry): an old reason with a note that the new one has not is another block. A line whose
# review-retry worked but was not logged (its note "was retried (review-retry), but the act was not logged") is no
# block's line: the card was retried, and the line reports that its act is not in the log, which no later read undoes.
FRESH='def card: [capture("^(?<r>[A-Za-z0-9._-]+): (?<ref>.+?) is blocked since (?<t>[0-9T:-]+Z): (?<why>.*)$"),
    capture("^(?<r>[A-Za-z0-9._-]+): (?<ref>.+?) has been blocked for [0-9hm]+ \\(since (?<t>[0-9T:-]+Z)\\): (?<why>.*)$"),
    capture("^(?<r>[A-Za-z0-9._-]+): not yet reported: blocked (?<ref>.+)$")] | first
  | select(. != null and (.why == null or (.why | test("; #[0-9]+ was retried \\(review-retry\\), but the act was not logged: ") | not))) | . as $c
  | select($now[$c.r] != null and (any($now[$c.r][]; . as $i | $i.ref == $c.ref and ($c.t == null or $i.since == $c.t)
      and ($c.why == null or ($c.why | sub("; the review-retry of #[0-9]+ failed: [\\s\\S]*$"; "")
        | sub(" \\(as of [0-9]{2}:[0-9]{2}Z\\)$"; "")) == $i.why)) | not));
  split("\n") | (if .[-1] == "" then .[:-1] else . end) as $l
  | [$l[1:][] | card] as $g
  | if $g == [] then $l | join("\n")
    else [$l[1:][] | select([card] == [])] as $keep
      | if $keep == [] then ""
        else ($l[0] | if startswith("Conveyor: ") then "Conveyor: " + (ltrimstr("Conveyor: ") | split(" | ") | map(index(": ") as $i
            | if $i == null then . else .[:$i] as $r | (.[$i + 2:] | split("; ") | map(index(": ") as $j
                | if $j != null and (.[:$j] | IN("blocked", "still blocked")) then .[:$j] as $k
                  | (reduce ($g[] | select(.r == $r) | .ref) as $x (" \(.[$j + 2:]) "; split(" \($x) ") | join(" ")) | ltrimstr(" ") | rtrimstr(" "))
                  | if . == "" then empty else "\($k): \(.)" end
                else . end)) as $s | if $s == [] then empty else "\($r): \($s | join("; "))" end end) | join(" | "))
          else . end) as $h | [$h] + $keep | join("\n") end end'
# stop_key <transcript>: the uuid of the transcript's last assistant entry (the reply that stops), which names one stop:
# every Stop hook of that stop reads the same, a later stop of the session a newer one. Empty with none.
stop_key() {
  [ -f "${1:-}" ] || return 0
  grep -F '"type":"assistant"' "$1" | jq -r 'select(.type == "assistant") | .uuid // empty | strings' 2>/dev/null | tail -n 1
}
# Stops a hook refused (stop.sh), one stop_key a line, the last 20: the waiter reads it to know whether the stop at
# which it relayed a wake ended a turn.
REFUSED=$FD/refused-stops
refused_put() { # <key>
  [ -n "${1:-}" ] || return 0
  { mkdir -p "$FD" && printf '%s\n' "$1" >> "$REFUSED" && tail -n 20 "$REFUSED" > "$REFUSED.$$" && mv -f "$REFUSED.$$" "$REFUSED"; } 2>/dev/null
}
# stdin_file <command>: the file the command's first `< file` redirect names, as the shell reads the name, printed; 1 when
# there is none. A `<` inside quotes (a title) is no redirect, nor is `<<`, `<<<`, `<(`, `<&` or `<>`. The name is any run
# of unquoted, quoted and backslash-escaped parts (`./'fix notes.md'`, `fix\ notes.md`), and ends at an unquoted space
# or one of `<>|;&(`.
stdin_file() {
  local s=$1 n=${#1} i=0 c d q='' w='' st=scan # st: scan (no redirect yet), gap (after `<`), word (the name is being read)
  while ((i < n)); do
    c=${s:i:1}
    i=$((i + 1))
    if [ "$q" = "'" ]; then # a single quote keeps every character as it is
      if [ "$c" = "'" ]; then q=; elif [ $st = word ]; then w+=$c; fi
      continue
    fi
    if [ "$c" = '\' ]; then # unquoted: keeps the next character; in double quotes: only before $ ` " \ (as bash does)
      d=${s:i:1}
      i=$((i + 1))
      [ "$d" != $'\n' ] || continue # a backslash and newline is a line continuation: bash removes both
      if [ $st = word ]; then
        if [ "$q" = '"' ]; then case $d in '$' | '`' | '"' | '\') ;; *) w+=$c ;; esac; fi
        w+=$d
      fi
      continue
    fi
    if [ "$q" = '"' ]; then
      if [ "$c" = '"' ]; then q=; elif [ $st = word ]; then w+=$c; fi
      continue
    fi
    case $c in "'" | '"')
      q=$c
      [ $st != gap ] || st=word
      continue
      ;;
    esac
    case $st in
      scan)
        [ "$c" = '<' ] || continue
        d=${s:i:1}
        while [ "$d" = '<' ]; do # `<<` and `<<<` read no file
          i=$((i + 1))
          d=${s:i:1}
          c='<<'
        done
        case $c$d in '<&' | '<>' | '<(' | '<<'*) ;; *) st=gap ;; esac
        continue
        ;;
      gap)
        case $c in [[:space:]]) continue ;; esac
        st=word
        ;;
    esac
    case $c in
      [[:space:]] | '<' | '>' | '|' | ';' | '&' | '(')
        [ -z "$w" ] || break
        st=scan
        ;;
      *) w+=$c ;;
    esac
  done
  [ -n "$w" ] || return 1
  printf '%s\n' "$w"
}
