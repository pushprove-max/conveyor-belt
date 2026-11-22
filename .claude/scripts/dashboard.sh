#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# dashboard.sh [--install|--uninstall|--restart|--loop|--publish|--update|--history|--work|--older|--donewhen|--shot|--excerpts|--bench] -- the collector of the Conveyor dashboard (the
# strip-down to Conveyor). It writes one file, data.js in dashboard/ of the state folder (`conveyor.sh state-dir`)
# (`window.DASH = {...};`), which the static page in .claude/dashboard/ reads, through the page server's /events as it
# changes, or every 15 s when that stream is not open, and beside it limit.json, the usage limit alone, which the
# plugin's pane in Claude Code reads. No model call, ever.
# No argument collects once; --loop collects every 60 s, serves the page (dashboard_server.py), runs the live Conveyor
# feed (dashboard_stream.py) and is what --install runs as a user service; between cycles it also runs
# sync-install.sh when it is beside this script (a release folder has none), which reinstalls the main checkout's
# packages when they no longer match its lockfiles, and --update, which brings the main checkout forward to
# origin/main and restarts the service on new code.
# The live feed: Conveyor's part comes from one long-lived `conveyor.sh watch` per record, which
# dashboard_stream.py keeps in stream.json and publishes with --publish: data.js built again at once from that and
# the other parts as the last cycle read them (cache/part-*.json), so a card's step is on the page in seconds while
# the usage limit, the decisions and the lanes keep the 60 s cycle. A cycle reads Conveyor itself (the one ssh
# command below) only when stream.json is not fresh: the feed is not running.
#
# What it reads, each read only:
#   conveyor  `conveyor.sh snapshot` for every record conveyor/host.json names, in one ssh command to that host
#             (to host.json's `ssh` target), or in one command here on one machine (hostof), with each record's
#             GitHub address, the time of its last push that worked.
#   decisions the open decisions (decision.sh list) of each record's ledger, the file the host file's records[].ledger
#             names on this machine, each with its record's repo; a record that names none has none. An answer that is recorded is done: there is no main session to
#             send it to any more, so nothing waits on its message.
#   limit     the account's usage limit and list-price cost (dashboard_limit.py), with its own cache under cache/, and
#             every Claude account's usage, this machine's and (over ssh, at most once a TTL) the Conveyor host's;
#             on one machine they are the same accounts, read once.
#   lanes     each record's Fast lane worktree and Research lane worktree on this machine: the folders the host
#             file's records[].lanes.fast.worktree and records[].lanes.research.worktree name.
#   foremen   each Foreman of this machine (foremen()): a project's, or a group's of the host file's foreman.groups.
#
# The data contract, {updatedAt, panels} with one part per panel of the page, is in dashboard_panels.sh, beside the jq
# program that cuts the parts (PANELS_JQ).
# Test seams: CONVEYOR_DASHBOARD_DIR, CONVEYOR_MAIN, CONVEYOR_WORKSPACES, CONVEYOR_SCRATCH, CONVEYOR_HOST_OS,
# XDG_CONFIG_HOME (where the host file is).
# Standalone (plan A9): the Board sources no support script of the project's (paths.sh, host-services.sh,
# peer-runtime.sh, .githooks/lib-workspaces.sh), so it runs from the release-1 files alone. The few values it took from
# them are resolved below, each by the same rule as its twin there.
set -uo pipefail
export GIT_OPTIONAL_LOCKS=0  # sampling never writes a worktree's index
HERE=$(cd "$(dirname "$0")" && pwd)
# The Mac's GNU tools (stat -c, date -d, xargs -d) lead PATH, ahead of a login shell's /usr/bin; --install writes this
# PATH into the job. Twin of paths.sh's Mac PATH repair.
if [ "$(uname -s)" = Darwin ]; then
  # Prepended even when already on PATH: one behind /usr/bin would leave Bash 3.2 and the BSD tools first.
  for d in /opt/homebrew/bin /opt/homebrew/opt/*/libexec/gnubin; do [ ! -d "$d" ] || PATH=$d:$PATH; done
  export PATH
fi
# The page server's Python: the Board's own virtualenv, which `conveyor.sh setup` fills from requirements.txt and
# `conveyor.sh doctor` checks (the same path in conveyor.sh's BOARD_VENV).
BOARD_PY=${XDG_DATA_HOME:-$HOME/.local/share}/conveyor/board-venv/bin/python3
# This machine's host file (plan section 6): the Conveyor host, its ssh target and its checkout, read by conveyor().
HOST_FILE=${XDG_CONFIG_HOME:-$HOME/.config}/conveyor/host.json
# This machine's primary checkout: CONVEYOR_MAIN, which a Board installed outside any checkout is given (--install
# keeps it in the job); else this script's git common dir, so a worktree's copy and main's read the same checkout
# (twin of paths.sh's PP_MAIN). Never the host file's `main`: that is the Conveyor host's checkout, on another machine
# when the Board runs on the Mac.
if [ -n "${CONVEYOR_MAIN:-}" ]; then PP_MAIN=$CONVEYOR_MAIN
else
  PP_MAIN=$(git -C "$HERE" rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || PP_MAIN=''
  case $PP_MAIN in
    */.git) PP_MAIN=${PP_MAIN%/.git} ;;
    *) echo "dashboard: cannot resolve the primary checkout from $HERE (git common dir: ${PP_MAIN:-none}); set CONVEYOR_MAIN" >&2; exit 1 ;;
  esac
fi
# The worktrees folder whose sessions count in this project's cost (limit): CONVEYOR_WORKSPACES, else the parent of
# main's linked worktree Fast-lane, else of its first linked worktree; empty when there is none or two Fast-lane
# folders disagree. The lanes are not read from it: lanes() reads each record's from the host file. Twin of
# pp_workspaces_dir in .githooks/lib-workspaces.sh: a change to one is made to both.
workspaces_dir() {
  if [ -n "${CONVEYOR_WORKSPACES:-}" ]; then printf '%s\n' "$CONVEYOR_WORKSPACES"; return 0; fi
  local line wt first='' lane='' main=1
  while IFS= read -r -d '' line; do
    case $line in "worktree "*) wt=${line#worktree } ;; *) continue ;; esac
    if [ -n "$main" ]; then main=''; continue; fi
    [ -n "$first" ] || first=${wt%/*}
    if [ "${wt##*/}" = Fast-lane ]; then
      [ -z "$lane" ] || [ "$lane" = "${wt%/*}" ] || return 1
      lane=${wt%/*}
    fi
  done < <(git -C "$PP_MAIN" worktree list --porcelain -z 2>/dev/null)
  wt=${lane:-$first}
  [ -n "$wt" ] || return 1
  printf '%s\n' "$wt"
}
PP_WORKSPACES=$(workspaces_dir) || PP_WORKSPACES=''
# The scratch folder dashboard_limit.py counts closing review copies in: one per primary checkout, so one project's
# closing-review spend is its own; a project may set its own.
PP_SCRATCH=${CONVEYOR_SCRATCH:-${TMPDIR:-/tmp}/conveyor/scratch/$(printf '%s' "$PP_MAIN" | tr -c 'A-Za-z0-9' '-')}
# CONVEYOR_HOST_OS drives either branch in a test (twin of host-services.sh's hs_os).
host_os() { printf '%s' "${CONVEYOR_HOST_OS:-$(uname -s)}"; }
# The & is escaped: from Bash 5.2 a bare & in the replacement is the match.
xml() { local s=${1//&/\&amp;}; s=${s//</\&lt;}; printf '%s' "${s//>/\&gt;}"; }
# The cycle runs this script again as "$HERE/$NAME.sh"; the mark tells tools/closure.sh what that load reaches.
NAME=dashboard # closure: load
# The Board's folder: dashboard/ in the state folder of the primary checkout, as `conveyor.sh state-dir` names it
# (the engine beside this Board's files). A state folder that cannot be named (a host file that cannot be read)
# stops the Board, as it stops the engine.
OUT=${CONVEYOR_DASHBOARD_DIR:-}
if [ -z "$OUT" ]; then
  OUT=$(CONVEYOR_MAIN=$PP_MAIN bash "${HERE%/*/*}/conveyor/conveyor.sh" state-dir) && [ -n "$OUT" ] \
    || { echo "dashboard: the state folder cannot be named; set CONVEYOR_DASHBOARD_DIR" >&2; exit 1; }
  OUT=$OUT/dashboard
fi
CACHE=$OUT/cache
# Each Claude account's usage reads and 429 deadline (dashboard_limit.py fetch and accounts): the machine's one folder,
# which the engine's guard and the Foreman's watcher use too, so no reader asks inside a wait another one was given.
ACCTS=${XDG_CACHE_HOME:-$HOME/.cache}/conveyor/accounts
# The Board's files the job runs and the page it copies: a Board in a git checkout takes the primary checkout's when
# that checkout carries the Board (a worktree's copy goes when the worktree does); a release install, a git clone or
# not, whose project carries no Board, and one outside any checkout, take their own.
if git -C "$HERE" rev-parse --git-dir >/dev/null 2>&1 && [ -d "$PP_MAIN/.claude/dashboard" ]; then BOARD=$PP_MAIN/.claude
else BOARD=${HERE%/*}; fi
VIEW_SRC=$BOARD/dashboard
TTL=300          # the usage read: asked again once its copy is this old, so a 60 s collection stays under its rate limit
CYCLE_LIMIT=900  # --loop kills a cycle running longer (a hung read)
SSH_LIMIT=60     # the one ssh command; a snapshot lists GitHub's open issues, which takes seconds
ACTIVE=600       # a lane's session whose record moved in this many seconds is working (whole minutes: find -mmin)
HISTORY_TTL=60   # --history with no live feed (so no ledger key) gives the copy it built while it is this young
PORT=${CONVEYOR_DASHBOARD_PORT:-8790}
RUN='' PUB='' SRV='' ALV='' STM='' LCK=''
# The heartbeat, the page server and the live feed end with the loop, or the page would read a stopped collector as
# alive. A build's lock of data.js goes with it.
trap 'rm -rf "${RUN:-}" "${PUB:-}" ${LCK:+"$LCK"}; for p in "$SRV" "$ALV" "$STM"; do [ -z "$p" ] || kill "$p" 2>/dev/null; done' EXIT
trap 'exit 143' TERM

iso() { date -u -d "@$1" +%Y-%m-%dT%H:%M:%SZ; }

# cached <key> <cmd>... -- the command's JSON, re-read once the copy is TTL old. Only a read that works and parses
# as JSON replaces the copy; a failed one keeps it. $RUN/st-<key> says which the caller got: fresh, stale (the last
# good copy) or not-measured (no copy: nothing is printed), and $RUN/why-<key> the reason. A failed read writes
# $CACHE/<key>.retry ("<retry-at epoch> <reason>"): until then the command is not run, so a 429 is not hit again
# every cycle. Retry-at is the `retry after <n> s` the command's stderr names, else the TTL. A shorter named wait is
# kept as named: dashboard_limit.py fetch names what is left of a 429 wait another reader of the account was given,
# and raised to the TTL it kept the first collect after that wait from asking.
cached() {
  local key=$1 f=$CACHE/$1 tmp=$RUN/cache-$1 err=$RUN/err-$1 m=$CACHE/$1.retry at='' why='' rc=0 n st=''
  shift
  [ ! -s "$m" ] || read -r at why < "$m" || true
  if [ -s "$f" ] && [ $((NOW - $(stat -c %Y "$f"))) -lt $TTL ]; then st=fresh
  elif [[ $at =~ ^[0-9]+$ ]] && [ "$at" -gt "$NOW" ]; then :
  elif { "$@" > "$tmp" 2>"$err"; rc=$?; [ $rc -eq 0 ] && jq -e . "$tmp" >/dev/null 2>&1; }; then
    mv -f "$tmp" "$f" && rm -f "$m" && st=fresh
  else
    why=$(tail -n 1 "$err" | cut -c1-120)
    [ -n "$why" ] || { [ $rc -eq 0 ] && why='malformed response' || why='read failed'; }
    n=$(grep -oE 'retry after [0-9]+ s' "$err" | tail -n 1 | grep -oE '[0-9]+') || n=0
    n=$((10#${n:-0}))  # a leading zero must not read as octal
    [ "$n" -gt 0 ] || n=$TTL
    printf '%s %s\n' $((NOW + n)) "$why" > "$RUN/retry-$key" && mv -f "$RUN/retry-$key" "$m"
  fi
  [ -n "$st" ] || { [ -s "$f" ] && st=stale || st=not-measured; }
  printf '%s' "$st" > "$RUN/st-$key"; printf '%s' "$why" > "$RUN/why-$key"
  [ ! -s "$f" ] || cat "$f"
}

# Conveyor's snapshot, read where conveyor/host.json says Conveyor runs (hostof): one fixed command each cycle, over
# ssh to the build machine, or here on one machine. For
# every record, in order, three lines: `conveyor.sh snapshot`, the checkout's origin address (empty when it names
# none) and the time its last push that worked was recorded (0 when there is none). Then a marker line, so an answer
# cut short is no answer. The answer is one object: {host, local (true on one machine), reachable, error, records}; a record is {repo, snap, steered (it is the record on host.json's main: the
# one the Board steers through POST /control), repoUrl, lastPushAt, readAt (the snapshot's snapshotAt: when the build
# of the kept snapshot it printed began; null when it does not say)}. reachable is false when ssh itself did not get through (its exit 255, or
# the time limit) and true when the host answered, whatever it said; records is null, with the reason in error, unless
# every record answered with a snapshot: never an earlier answer, and never a part of the records.
# hostof -- what the one command of a read needs of the host file, as hostfile.sh (its one reader, which says the
# rules) gives it: host (the machine Conveyor runs on), main (the checkout of the record the Board steers), engine (the
# checkout whose conveyor.sh runs), target (host.json's own `ssh`; empty on one machine, where every read runs here)
# and recs (its records, [{repo, main}]); remote is 1 when the file names a build machine, even one it does not say
# all of. 1, with why naming the field that is wrong, when it does not say them.
hostof() {
  local r rc=0
  host='' main='' engine='' target='' recs='' why='' remote=''
  r=$(bash "$HERE/hostfile.sh" "$PP_MAIN") || rc=$?
  { IFS= read -r -d '' host; IFS= read -r -d '' main; IFS= read -r -d '' engine; IFS= read -r -d '' target
    IFS= read -r -d '' recs; IFS= read -r -d '' why; IFS= read -r -d '' remote; } < <(jq -j '(.host // ""), "\u0000", (.main // ""), "\u0000",
      (.engine // ""), "\u0000", (.target // ""), "\u0000", (.records | if . == null then "" else tojson end), "\u0000",
      (.error // ""), "\u0000", (if .local == false then "1" else "" end), "\u0000"' <<<"$r" 2>/dev/null)
  [ "$rc" = 0 ] || { why=${why:-the host file could not be read}; return 1; }
}
# onhost <command> -- runs one read's command where Conveyor runs: over ssh to target, or here when there is none,
# under the same time limit. The keepalive ends a host that stops answering mid-command; the time limit one that
# stalls before its command starts.
onhost() {
  if [ -n "$target" ]; then
    timeout -k 2 "$SSH_LIMIT" ssh -o BatchMode=yes -o ConnectTimeout=5 -o ServerAliveInterval=15 -o ServerAliveCountMax=4 "$target" "$1"
  else timeout -k 2 "$SSH_LIMIT" bash -c "$1"; fi
}

# --check, for doctor (conveyor/lib/setup.sh): whether the Board reads the project where the host file says Conveyor
# runs (hostof), by the read every panel takes: the snapshot of every record (conveyor). Prints where, or why it
# cannot, and then fails. On one machine the Board's own copy of Conveyor must have its conveyor.sh.
check() {
  local host main engine target recs why remote out
  hostof || { echo "$why"; return 1; }
  [ -n "$target" ] || [ -f "$engine/conveyor/conveyor.sh" ] || { echo "the Board's copy of Conveyor at $engine has no conveyor/conveyor.sh"; return 1; }
  RUN=$(mktemp -d) || return 1
  out=$(conveyor)
  jq -e '.records | arrays' >/dev/null 2>&1 <<<"$out" || { jq -r '.error // "the Board read no snapshot"' <<<"$out" 2>/dev/null || echo "the Board read no snapshot"; return 1; }
  if [ -n "$target" ]; then echo "on the build machine $host, over ssh to $target"; else echo "on this machine ($host)"; fi
}

conveyor() {
  local host main engine target recs why remote cmd out rc=0 one=false read=0
  hostof || read=1
  [ -n "$remote" ] || one=true
  fail() { jq -cn --arg h "${host:-}" --argjson r "$1" --arg e "$2" --argjson l "$one" '{host: (if $h == "" then null else $h end), local: $l, reachable: $r, error: $e, records: null}'; }
  [ "$read" = 0 ] || { fail null "$why"; return 0; }
  cmd=$(jq -r --arg e "$engine/conveyor/conveyor.sh" 'map((.main | @sh) as $m | "CONVEYOR_MAIN=\($m) bash \($e | @sh) snapshot && { git -C \($m) remote get-url origin 2>/dev/null || echo; } && { stat -c %Y \"$(CONVEYOR_MAIN=\($m) bash \($e | @sh) state-dir)\"/pushed 2>/dev/null || echo 0; }") | join(" && ")
    + " && echo @@end"' <<<"$recs")
  out=$(onhost "$cmd" 2>"$RUN/err-conveyor") || rc=$?
  case $rc in
    0) ;;
    255|124|137) fail false "$host did not answer: $(tail -n 1 "$RUN/err-conveyor" | tr -d '\r' | cut -c1-160 | grep . || echo "no answer in $SSH_LIMIT s")"; return 0 ;;
    *) fail true "$host answered, but its Conveyor gave no snapshot: $(tail -n 1 "$RUN/err-conveyor" | tr -d '\r' | cut -c1-200 | grep . || echo "exit $rc")"; return 0 ;;
  esac
  jq -ecRs --arg h "$host" --arg m "$main" --argjson recs "$recs" --argjson one "$one" '
    def need(f): if f then . else error("shape") end;
    split("\n") as $l | ($recs | length) as $n
    | need(($l | index("@@end")) == 3 * $n)
    | {host: $h, local: $one, reachable: true, error: null,
       records: [range(0; $n) as $i | ($l[3 * $i] | fromjson) as $s
         | $s | need(type == "object" and ([.needsYou.waiting, .needsYou.blocked, .belt, .landed] | all(type == "array"))
             and ([.queue, .health, .cost] | all(type == "object")))
         | {repo: $recs[$i].repo, snap: $s, steered: ($recs[$i].main == $m),
            repoUrl: ($l[3 * $i + 1] | (capture("github\\.com[:/](?<p>[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+?)(\\.git)?$") | "https://github.com/\(.p)") // null),
            lastPushAt: ($l[3 * $i + 2] | tonumber? // 0 | if . > 0 then todate else null end),
            readAt: (($s.snapshotAt | strings) // null)}]}' <<<"$out" 2>/dev/null \
    || fail true "$host answered, but not with the snapshot of every record"
}

# What waits on the owner outside the cards: the open decisions of each project's ledger, the file the host file's
# records[].ledger names on this machine (never the Board's own checkout), each with its record's repo. A record that
# names no ledger has no decisions; a named ledger that does not read is a warning naming its record, beside the
# decisions of the ledgers that did. Also writes the owner's daily page (/digest.txt behind the login), one page a
# ledger, then the picker answers no ledger holds (empty with no ledger named); a run in which any named ledger failed
# keeps the last good page.
decisions() {
  local cfg=$HOST_FILE recs repo led got err='' errs=() leds=() named=0 nread=0 pages=true open=$RUN/decisions-open.jsonl
  [ -e "$cfg" ] || cfg=$PP_MAIN/conveyor/host.json
  recs='[]'
  if [ -e "$cfg" ]; then
    recs=$(jq -ec '[.records // [] | .[] | select(has("ledger")) | [(.repo | tostring), (.ledger | tostring)]]' "$cfg" 2>/dev/null) \
      || { jq -cn '{decisions: null, error: "conveyor/host.json records are not understood"}'; return 0; }
  fi
  : > "$OUT/.digest.txt.$$"; : > "$open"
  # NUL between fields: a path reaches decision.sh exactly as the host file has it (@tsv would double a backslash).
  # Each ledger's open decisions go to a file, never an argument: a long question would exceed the argument limit.
  while IFS= read -r -d '' repo && IFS= read -r -d '' led; do
    named=$((named + 1))
    if [ ! -e "$led" ]; then errs+=("no ledger for $repo at $led"); continue; fi
    if got=$(CONVEYOR_MAIN=$PP_MAIN CONVEYOR_LEDGER=$led bash "$HERE/decision.sh" list 2>"$RUN/err-decisions") \
        && got=$(jq -ce --arg r "$repo" 'arrays | map(select(.answeredAt == null) | {repo: $r, id, askedAt, question, options: (.options // null), proposedDefault: (.proposedDefault // null), source: (.source // null)})' <<<"$got" 2>/dev/null); then
      printf '%s\n' "$got" >> "$open"; nread=$((nread + 1)); leds+=("$led")
      { printf '# %s\n' "$repo" && CONVEYOR_MAIN=$PP_MAIN CONVEYOR_LEDGER=$led bash "$HERE/decision.sh" digest --no-picks 2>/dev/null && echo; } >> "$OUT/.digest.txt.$$" || pages=false
    else
      got=$(head -n 1 "$RUN/err-decisions" 2>/dev/null | cut -c1-200); errs+=("$repo: ${got:-the decision ledger could not be read}")
    fi
  done < <(jq -j '.[] | .[0], "\u0000", .[1], "\u0000"' <<<"$recs")
  # Picker answers name no project: one section after the projects, of those no read ledger holds a row for.
  [ "$nread" -eq 0 ] || { printf '# Picker answers no project ledger holds\n' && CONVEYOR_MAIN=$PP_MAIN bash "$HERE/decision.sh" digest --picks "${leds[@]}" 2>/dev/null; } >> "$OUT/.digest.txt.$$" || pages=false
  # The page is replaced only when every named ledger read: a page missing a project is a failed run. With no ledger
  # named, every one read and the page is empty: a removed ledger's decisions leave the page with it.
  if [ "${#errs[@]}" -eq 0 ] && $pages; then mv -f "$OUT/.digest.txt.$$" "$OUT/digest.txt"; else rm -f "$OUT/.digest.txt.$$"; fi
  [ "${#errs[@]}" -eq 0 ] || { err=$(printf '%s; ' "${errs[@]}"); err=${err%; }; }
  jq -cs --argjson none "$([ "$nread" -eq 0 ] && [ "$named" -gt 0 ] && echo true || echo false)" --arg e "$err" \
    '{decisions: (if $none then null else add // [] end), error: (if $e == "" then null else $e end)}' "$open"
}

# The usage limit and list-price cost. The usage read is Claude's own quota reading, the statusline's source, never a
# model call; dashboard_limit.py owns the math and keeps the only percent history there is, in cache/. The reading is
# one account's: after a switch the cached one and its retry deadline are dropped, so neither the other
# account's figure nor its 429 holds off this collect's read; each account's own 429 deadline, kept by
# dashboard_limit.py per account, still does. Prints {limit, error}.
# The Claude accounts of the Conveyor host (its host file's accounts and its own default login), each with its own
# usage, as the host's dashboard_limit.py reads them; over ssh to host.json's target, as conveyor() checks the host file.
# Prints the list.
hostaccounts() {
  local host main engine target recs why remote
  hostof && [ -n "$target" ] || { echo "no Conveyor host is named" >&2; return 1; }
  timeout -k 2 "$SSH_LIMIT" ssh -o BatchMode=yes -o ConnectTimeout=5 -o ServerAliveInterval=15 -o ServerAliveCountMax=4 \
    "$target" "python3 $(jq -rn --arg p "$main" '$p | @sh')/.claude/scripts/dashboard_limit.py accounts \"\${XDG_CACHE_HOME:-\$HOME/.cache}/conveyor/accounts\"" | jq -ce 'arrays'
}
# Every Claude account the Board can read, each with its own usage: this machine's (dashboard_limit.py accounts, the
# account in use from claude-usage, which limit() has just read) and the
# Conveyor host's (hostaccounts, asked at most once a TTL: cached). Prints {here, host: {name, accounts, error}}. The
# emails are for the page alone.
accounts() {
  local here acc st host main engine target recs why remote
  # The account in use is shown from limit()'s reading, never read a second time (a second read kept it refused, 429).
  here=$(python3 "$HERE/dashboard_limit.py" accounts "$ACCTS" "$CACHE/claude-usage" 2>/dev/null | jq -ce 'arrays') || here=null
  # On one machine (the host file names no build machine: hostof) the Conveyor host is this machine: its accounts are
  # the ones just read, listed once, as the host's (no name: the page says "this machine"), so each shows what the
  # cards use it for.
  hostof
  if [ -z "$remote" ]; then
    jq -cn --argjson h "$here" '{here: [], host: {name: null, accounts: $h,
      error: (if $h == null then "the accounts on this machine were not read" else null end)}}'
    return 0
  fi
  acc=$(cached host-accounts hostaccounts) || acc=''
  st=$(cat "$RUN/st-host-accounts")
  jq -cn --argjson h "$here" --argjson a "${acc:-null}" --arg st "$st" --rawfile why "$RUN/why-host-accounts" --arg n "$host" \
    '{here: $h, host: {name: (if $n == "" then null else $n end), accounts: $a,
      error: (if $st == "fresh" then null elif $st == "stale" then "the accounts on the host were not read again (\($why)); showing the last read" else "the accounts on the host were not read: \($why)" end)}}'
}
limit() {
  local st have now_in_use out acc cx=${CODEX_HOME:-$HOME/.codex}/sessions
  have=$(jq -r '.account.folder // empty' "$CACHE/claude-usage" 2>/dev/null)
  now_in_use=$(python3 "$HERE/dashboard_limit.py" account | jq -r .folder)
  # A reading of another account goes, with the retry deadline. A deadline beside no reading of an account goes too:
  # it cannot be told whose it is (a 429 of the account switched from would hold the read of the one in use back).
  if [ -z "$have" ]; then rm -f "$CACHE/claude-usage.retry"
  elif [ "$have" != "$now_in_use" ]; then rm -f "$CACHE/claude-usage" "$CACHE/claude-usage.retry"; fi
  # With the cache folder, fetch honours and keeps the account's own 429 deadline, which outlives the switch above.
  cached claude-usage python3 "$HERE/dashboard_limit.py" fetch "$now_in_use" "$ACCTS" > /dev/null
  st=$(cat "$RUN/st-claude-usage")
  acc=$(accounts) || acc=null
  # The pack's model prices, added models and aliases win over the built-in table here too (use_prices); a pack that
  # does not read has none.
  if out=$(PP_SCRATCH=$PP_SCRATCH PP_PRICES=$(jq -c '.prices // {}' "$PP_MAIN/.conveyor/project.json" 2>/dev/null) python3 "$HERE/dashboard_limit.py" build "$st" "$CACHE/claude-usage" "$NOW" "$CACHE" "$HOME/.claude/projects" "$cx" "$PP_MAIN" ${PP_WORKSPACES:+"$PP_WORKSPACES"} 2>"$RUN/err-limit") \
      && jq -e 'objects' >/dev/null 2>&1 <<<"$out"; then
    jq -c --arg st "$st" --rawfile why "$RUN/why-claude-usage" --argjson acc "$acc" 'del(.history) | (.codex | objects) |= del(.history)
      | {limit: (. + {reading: $st}), error: (if $st == "fresh" then null elif $st == "stale" then "the usage read failed (\($why)); showing the last reading" else "the usage limit was not read: \($why)" end), accounts: $acc}' <<<"$out"
  else jq -cn --arg e "$(tail -n 1 "$RUN/err-limit" | cut -c1-200)" --argjson acc "$acc" '{limit: null, error: ("the usage limit could not be built" + (if $e == "" then "" else ": " + $e end)), accounts: $acc}'; fi
}

# latest_cwd <record> -- the folder a Claude session's record says it works in now: the cwd of the last of its lines
# that carry one, each such line read, so one long message cannot hide it.
latest_cwd() { grep -F '"cwd":' "$1" 2>/dev/null | jq -rR 'fromjson? | .cwd? | strings | select(test("\n") | not)' 2>/dev/null | tail -n 1; }

# One lane's worktree on this machine: {present, branch, ahead, subject, first, dirty, run}. ahead is the commits it
# has that main does not, subject the newest of them and first the oldest (the title Conveyor gives a card of a
# branch that names no issue); dirty counts its files with an uncommitted change, new files too. run is the newest Claude
# session in the folder (begun there, or working there now): when it began, when its record last moved, whether
# that was in the last ACTIVE seconds, and how its first prompt opens. A folder that is not there is {present: false}.
lane() { # <worktree>
  local d=$1 br ahead=null subj='' first='' dirty=null f g c cwd run=null
  [ -e "$d/.git" ] || { echo '{"present":false}'; return 0; }
  br=$(git -C "$d" symbolic-ref -q --short HEAD 2>/dev/null) || br=''
  if ahead=$(git -C "$d" rev-list --count main..HEAD 2>/dev/null); then
    [ "$ahead" = 0 ] || { subj=$(git -C "$d" log -1 --format=%s 2>/dev/null); first=$(git -C "$d" log --reverse --format=%s main..HEAD 2>/dev/null | head -n 1); }
  else ahead=null; fi
  dirty=$(git -C "$d" status --porcelain --untracked-files=all 2>/dev/null | grep -c .) || dirty=${dirty:-0}
  [[ $dirty =~ ^[0-9]+$ ]] || dirty=null
  # The newest record in the folder's ~/.claude/projects entry (Claude Code's folder naming; twin of pp_session_log).
  f=$(ls -t "$HOME/.claude/projects/$(sed 's/[^a-zA-Z0-9]/-/g' <<<"$d")"/*.jsonl 2>/dev/null | head -1)
  # Claude Code files a session under the folder it began in, and each record carries the folder it works in now
  # (cwd): a session begun in the main checkout or in a folder of the lane, working in the lane, is filed elsewhere.
  # A newer record that moved in the last ACTIVE seconds, whose latest cwd is the lane or a folder in it, is the run;
  # a session filed under the lane whose latest cwd has left it is not. The records that moved in the last ACTIVE
  # seconds, each with its latest cwd, are LANE_ACTIVE, which lanes() lists once a cycle.
  cwd=''
  if [ -n "$f" ]; then
    g=''
    while IFS=$'\t' read -r g c; do [ "$g" != "$f" ] || { cwd=$c; break; }; done <<<"$LANE_ACTIVE"
    [ "$g" = "$f" ] || cwd=$(latest_cwd "$f")
  fi
  case $cwd in ''|"$d"|"$d"/*) ;; *) f='' ;; esac
  while IFS=$'\t' read -r g c; do
    [ -n "$g" ] || continue
    [ -z "$f" ] || [ "$g" -nt "$f" ] || continue
    case $c in "$d"|"$d"/*) f=$g ;; esac
  done <<<"$LANE_ACTIVE"
  # The record is read in whole lines, however long, up to its first timestamp and first prompt and no further.
  [ -z "$f" ] || run=$(jq -cRn --argjson last "$(stat -c %Y "$f")" --argjson now "$NOW" --argjson active "$ACTIVE" '
      def prompt: select(.type == "user" and .isSidechain != true) | .message.content
        | if type == "string" then . else (arrays | map(select(.type == "text") | .text) | join(" ")) end | strings | select(length > 0);
      (label $done | foreach ((inputs | fromjson? | objects), null) as $o ({s: null, t: null};
         if $o then .s //= ([$o.timestamp | strings][0]) | .t //= ([$o | prompt][0]) else . end;
         if $o == null or (.s and .t) then ., break $done else empty end)) as $r
      | {startedAt: $r.s, lastAt: ($last | todate), active: ($now - $last < $active),
         topic: ($r.t | if . then gsub("\\s+"; " ") | .[0:160] else null end)}' "$f" 2>/dev/null) || run=null
  jq -cn --arg b "$br" --argjson a "$ahead" --arg s "$subj" --arg f "$first" --argjson d "$dirty" --argjson run "${run:-null}" \
    'def n: if . == "" then null else . end; {present: true, branch: ($b | n), ahead: $a, subject: ($s | n), first: ($f | n), dirty: $d, run: $run}'
}
# The lanes of every record of the host file, in its order: {records: [{repo, fast, research}]}. A lane is read from
# the folder the record's lanes.fast.worktree or lanes.research.worktree names on this machine (a path starting ~/
# is under the home folder), and is null when the record names none: a lane is the owner's own worktree, wherever
# `conveyor.sh lane fast create` or `lane research create` made it, and each writes its folder into the host file.
lanes() {
  local cfg=$HOST_FILE recs='[]' repo f r out='[]' LANE_ACTIVE='' g
  [ -e "$cfg" ] || cfg=$PP_MAIN/conveyor/host.json
  if [ -e "$cfg" ]; then
    recs=$(jq -ec 'def w: . // "" | if type == "string" then . else error("worktree") end;
        [.records // [] | .[] | [(.repo | tostring), (.lanes.fast.worktree | w), (.lanes.research.worktree | w)]]' "$cfg" 2>/dev/null) \
      || { jq -cn '{error: "conveyor/host.json records are not understood"}'; return 0; }
  fi
  # The Claude records that moved in the last ACTIVE seconds, each with its latest cwd, one "<record><tab><cwd>" a
  # line: listed and read once a cycle, not once a lane.
  while IFS= read -r g; do
    LANE_ACTIVE+=$g$'\t'$(latest_cwd "$g")$'\n'
  done < <(find "$HOME/.claude/projects" -mindepth 2 -maxdepth 2 -name '*.jsonl' -mmin -$((ACTIVE / 60)) 2>/dev/null)
  while IFS= read -r -d '' repo && IFS= read -r -d '' f && IFS= read -r -d '' r; do
    [[ $f != "~/"* ]] || f=$HOME/${f#"~/"}
    [[ $r != "~/"* ]] || r=$HOME/${r#"~/"}
    f=$([ -z "$f" ] && echo null || lane "$f") && r=$([ -z "$r" ] && echo null || lane "$r") \
      && out=$(jq -c --arg repo "$repo" --argjson f "$f" --argjson r "$r" '. + [{repo: $repo, fast: $f, research: $r}]' <<<"$out") || return 1
  done < <(jq -j '.[] | .[] | ., "\u0000"' <<<"$recs")
  jq -c '{records: .}' <<<"$out"
}

# The Foremen of this machine, one a project or one a group (conveyor/foreman/lib.sh mine: a list of the host file's
# foreman.groups is one Foreman over the records it names; groups that name a project twice are not understood, and
# then each project has its own): {foremen: [{projects, group, held, since, lastWakeAt, waiting, pluginBugs,
# pluginBugsFile, pluginBugsUrl, pluginNotes}], error}; pluginBugs: how many plugin problems it noted (plugin-bugs.md,
# conveyor/foreman/stop.sh), pluginBugsFile: that file, pluginBugsUrl: its copy in the Board's folder
# (plugin-bugs/<first project>.txt, which the page server serves, as a browser opens no file:// link from an https
# page), pluginNotes: each note as {at, card, text, line} (stop.sh's "- <at> · card <card> · <text>"; at and card null
# for a line in no such form; line: the whole line, which the page's Dismiss names to POST /plugin-dismiss); all three
# null when it noted none. A Foreman's
# folder is foreman/ in the state folder of its first project (lib.sh's FD), which is the host file's stateDir for the
# host file's own checkout and that checkout's conveyor/state for any other (conveyor.sh's ST); the host file's own
# checkout is the one its main leads to, links followed, as the engine compares them. held: a session holds
# the role (the folder's session mark names one), since when it claimed it; lastWakeAt: when a wake was last relayed
# to it (last-wake.txt); waiting: the wakes owed to it and not relayed yet (pending/), the first line of each. A
# project whose folder holds no mark has no Foreman: held false, and the page says so. When the host file names an
# ssh target and a Foreman's first record's main is not on this machine (the belt runs on the host), the Foreman runs
# in a checkout here whose remote is that repository (lib.sh's mine and FD), so its folder is read there
# (checkout_of); with no such checkout, under main as before. A main that is also a path here (the same path on both
# machines) is read here as it is. With an ssh target, the loop on the host notes a model with no
# built-in price in the host's folder (noprice(), conveyor/lib/control.sh), which this machine does not read: each such
# note the snapshot of one of the Foreman's projects gives (priceNotes, in <conveyor part>) is added to the folder read
# here, under the lock the loop takes. Once a model: price-notes.txt in the folder lists the models added, so a note
# dismissed or filed here does not come back; and none for a model a note in the file already names.
# checkout_of <repo> [<ledger>]: the main checkout on this machine whose remote the pack names (.remote, default
# origin) has that repository's name as the last part of its address (lib.sh's repo_name), looked for in the
# checkout holding the record's ledger, then in the folders beside the Board's own checkout. Nonzero when none has.
checkout_of() {
  local c r u cs=()
  [ -z "${2:-}" ] || { c=$(git -C "$(dirname -- "$2")" rev-parse --path-format=absolute --git-common-dir 2>/dev/null) && cs+=("${c%/.git}"); }
  for c in "${PP_MAIN%/*}"/*/; do cs+=("${c%/}"); done
  for c in "${cs[@]}"; do
    [ -d "$c/.git" ] || continue
    r=$(jq -r '.remote // "origin" | strings' "$c/.conveyor/project.json" 2>/dev/null) && [ -n "$r" ] || r=origin
    u=$(git -C "$c" remote get-url -- "$r" 2>/dev/null) || continue
    u=${u%/}; u=${u%.git}; u=${u##*[/:]}
    [ "$u" != "$1" ] || { printf '%s' "$c"; return 0; }
  done
  return 1
}
foremen() { # <conveyor part>
  local cfg=$HOST_FILE rows projects main hm sd ssh led here dir sid since wake f out='[]' waiting host engine target recs why remote bugs url away
  # The copies are made again each read: a Foreman whose notes are gone has none left.
  rm -rf "$OUT/plugin-bugs"
  [ -e "$cfg" ] || cfg=$PP_MAIN/conveyor/host.json
  [ -e "$cfg" ] || { echo '{"foremen":[],"error":null}'; return 0; }
  # The host's main and its ssh target as hostof reads them (a host file it cannot read names neither).
  hostof || main=''
  rows=$(jq -ec --arg hm "$main" --arg ssh "$target" '(.records // []) as $r | (.foreman.groups // []) as $g
      | select(($r | type == "array" and all(type == "object" and (.repo | type == "string") and (.main | type == "string")))
          and ($g | type == "array" and all(type == "array" and all(type == "string"))))
      | (if ([$g[][]] | length == (unique | length)) then $g else [] end) as $g
      | (if $hm == "" then null else $hm end) as $hm | (.stateDir | if type == "string" and . != "" then . else null end) as $sd
      | ($ssh != "") as $ssh
      | [$r[].repo] as $at
      | [$r[] | .repo as $n | (first($g[] | select(index($n))) // [$n]) | map(select(. as $x | $at | index($x)))]
      | unique_by(.[0]) | sort_by(.[0] as $n | $at | index($n))
      | map(. as $p | first($r[] | select(.repo == $p[0])) as $f
          | {projects: $p, main: $f.main, hm: ($hm // ""), sd: ($sd // ""), ssh: (if $ssh then "1" else "" end),
             led: ($f.ledger | strings // "")})' "$cfg" 2>/dev/null) \
    || { jq -cn '{foremen: null, error: "conveyor/host.json records are not understood"}'; return 0; }
  while IFS= read -r -d '' projects && IFS= read -r -d '' main && IFS= read -r -d '' hm && IFS= read -r -d '' sd \
    && IFS= read -r -d '' ssh && IFS= read -r -d '' led; do
    # With ssh, the belt runs on the host, whether or not its main is also a path here (the same path on both): the
    # Foreman is here, and a main not on this machine is the host's, so the Foreman runs in a checkout matched by its remote.
    away=''
    if [ -n "$ssh" ] && [ -d "$main" ]; then
      away=1
    elif [ -n "$ssh" ]; then
      [[ $led != "~/"* ]] || led=$HOME/${led#"~/"}
      here=$(checkout_of "$(jq -r '.[0]' <<<"$projects")" "$led") && main=$here && away=1
    fi
    dir=$main/conveyor/state
    [ -z "$sd" ] || { [ "$main" != "$hm" ] && [ "$(cd "$main" 2>/dev/null && pwd -P)" != "$(cd "$hm" 2>/dev/null && pwd -P || echo "$hm")" ]; } || dir=$sd
    dir=$dir/foreman
    # The host's notes for models with no built-in price; only a note of noprice()'s form, one line, is added.
    [ -z "$away" ] || ( mkdir -p "$dir" && { flock -w 30 9 || exit 1
      while IFS= read -r l; do
        m=${l#*" · No built-in price for "}; m=${m%%": "*}
        ! grep -qxF -- "$m" "$dir/price-notes.txt" 2>/dev/null || continue
        grep -qF -- " · No built-in price for $m: " "$dir/plugin-bugs.md" 2>/dev/null \
          || { [ -s "$dir/plugin-bugs.md" ] || printf '# Plugin problems the Foreman noted (for the conveyor-belt repo)\n\n'; printf '%s\n' "$l"; } >> "$dir/plugin-bugs.md" || continue
        printf '%s\n' "$m" >> "$dir/price-notes.txt"
      done < <(jq -r --argjson p "$projects" '.records | arrays | .[] | objects | select(.repo | IN($p[])) | .snap.priceNotes | arrays | .[] | strings
          | select((contains("\n") or contains("\r") | not) and test("^- [^ ]+ · card - · No built-in price for (claude|gpt)-[A-Za-z0-9._\\[\\]-]+: "))' "$1" 2>/dev/null); } 9>>"$dir/noprice.lock" ) \
      || echo "dashboard: the notes for models with no built-in price could not be added to $dir/plugin-bugs.md" >&2
    sid='' since=''; { read -r sid since < "$dir/session"; } 2>/dev/null || true
    [[ $since =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:]{8}Z$ ]] || since=''
    wake=$(stat -c %Y "$dir/last-wake.txt" 2>/dev/null) && wake=$(iso "$wake") || wake=''
    waiting=$(for f in "$dir"/pending/*.wake; do [ ! -f "$f" ] || head -n 1 "$f" | cut -c1-200; done | jq -Rc . | jq -cs .) || waiting='[]'
    bugs=$(grep -c '^- ' "$dir/plugin-bugs.md" 2>/dev/null) || bugs=0
    notes=$({ grep '^- ' "$dir/plugin-bugs.md" 2>/dev/null || true; } | jq -Rc '(capture("^- (?<at>[^ ]+) · card (?<card>[^ ]+) · (?<text>.*)$")
      // {at: null, card: null, text: ltrimstr("- ")}) + {line: .}' | jq -cs .) || notes='[]'
    url=$(jq -r '.[0]' <<<"$projects"); url=plugin-bugs/${url//[^A-Za-z0-9._-]/_}.txt
    [ "$bugs" -eq 0 ] || { mkdir -p "$OUT/plugin-bugs" && cp -- "$dir/plugin-bugs.md" "$OUT/$url" && chmod 644 "$OUT/$url"; } || url=''
    out=$(jq -c --argjson p "$projects" --arg sid "$sid" --arg s "$since" --arg w "$wake" --argjson q "${waiting:-[]}" \
      --argjson nb "${bugs:-0}" --arg fb "$dir/plugin-bugs.md" --arg u "$url" --argjson nt "${notes:-[]}" \
      'def n: if . == "" then null else . end; . + [{projects: $p, group: ($p | length > 1), held: ($sid != ""), since: ($s | n), lastWakeAt: ($w | n), waiting: $q,
        pluginBugs: $nb, pluginBugsFile: (if $nb > 0 then $fb else null end), pluginBugsUrl: (if $nb > 0 then $u | n else null end),
        pluginNotes: (if $nb > 0 then $nt else null end)}]' <<<"$out") || return 1
  done < <(jq -j '.[] | (.projects | tojson), "\u0000", .main, "\u0000", .hm, "\u0000", .sd, "\u0000", .ssh, "\u0000", .led, "\u0000"' <<<"$rows")
  jq -c '{foremen: ., error: null}' <<<"$out"
}

# The data contract, the jq program that cuts the page's parts (PANELS_JQ) and the builds of data.js.
. "$HERE/dashboard_panels.sh" || exit 1

# publish_lock -- one build of data.js at a time: the cycle's and the feed's (--publish). A lock older than a minute
# is a build that was killed, and is taken over. The lock goes with this process (the EXIT trap) or with publish.
publish_lock() {
  local i
  for i in $(seq 100); do
    mkdir "$OUT/.publish.lock" 2>/dev/null && { LCK=$OUT/.publish.lock; return 0; }
    [ $(( $(date +%s) - $(stat -c %Y "$OUT/.publish.lock" 2>/dev/null || date +%s) )) -lt 60 ] || rmdir "$OUT/.publish.lock" 2>/dev/null
    sleep 0.1
  done
  echo "dashboard: another build of data.js holds $OUT/.publish.lock" >&2; return 1
}

# --history: the Landed, Metrics, Cost and Declined parts as data.js has them, but built from every entry: each
# record's `conveyor.sh history` (the lists whole, of which its snapshot holds the newest) laid into its record. The
# page server gives it at GET /history, which the page asks for while one of those panels is shown, never with the
# live feed. Printed as {updatedAt, panels}, and kept in cache/history.json, with the ledger key it was built for in
# cache/history.key. The ledger key is cut from the live feed's records, with no host read
# (ledger_key). While the live feed's key is the kept one, the kept copy is printed; the page server's POST /control
# drops the kept copy and key, so the next ask builds again. With no key (no live feed, or a record with no
# historySum) the copy is printed while it is under HISTORY_TTL seconds old. The rest of each record is the live
# feed's (with none running, read as a cycle reads it), the other parts those the last cycle kept. A host that gives no
# history of every record prints nothing: exit 1. The page server reads the same key and copy itself (kept_history).
# ledger_key <conveyor.json>: each record's repo, snapshot historySum (the cksum of its history less the Metrics cards'
# wait and run times, so any other change to an entry changes it, and the clock alone does not) and day, as one line;
# nothing and 1 when a record has no historySum.
ledger_key() {
  jq -ce '[.records[] | {repo, h: .snap.historySum, day: .snap.day}] | select(all(.[]; .h | type == "string"))' "$1"
}
history() {
  local host main engine target recs why remote cmd f=$CACHE/history.json k=$CACHE/history.key at key='' live=''
  RUN=$(mktemp -d "$OUT/.run.XXXXXX") || return 1
  stream_conv > "$RUN/conveyor.json" && live=1 && key=$(ledger_key "$RUN/conveyor.json") || key=''
  if [ -n "$key" ]; then  # the key before the copy: the copy is written before its key, and dropped after it
    [ "$(cat "$k" 2>/dev/null)" = "$key" ] && jq -ce 'objects' "$f" 2>/dev/null && return 0
  else
    at=$(stat -c %Y "$f" 2>/dev/null) && [ $(( $(date +%s) - at )) -lt $HISTORY_TTL ] && jq -ce 'objects' "$f" 2>/dev/null && return 0
  fi
  NOW=$(date +%s)
  hostof || { echo "dashboard: no history: $why" >&2; return 1; }
  cmd=$(jq -r --arg e "$engine/conveyor/conveyor.sh" 'map("CONVEYOR_MAIN=\(.main | @sh) bash \($e | @sh) history") | join(" && ") + " && echo @@end"' <<<"$recs")
  onhost "$cmd" > "$RUN/history" 2>"$RUN/err-history" \
    || { echo "dashboard: $host gave no history: $(tail -n 1 "$RUN/err-history" | tr -d '\r' | cut -c1-200)" >&2; return 1; }
  { [ -n "$live" ] || conveyor > "$RUN/conveyor.json"; } && kept_parts || return 1
  jq -c --argjson recs "$recs" --rawfile h "$RUN/history" '($h | split("\n")) as $l | ($recs | length) as $n
    | if ($l | index("@@end")) != $n or (.records | type) != "array" then error("no history of every record") else . end
    | ([range(0; $n) as $i | {key: $recs[$i].repo, value: ($l[$i] | fromjson | objects)}] | from_entries) as $x
    | .records |= map($x[.repo] as $o | if $o == null then . else .snap |= (.landed = $o.landed | .metrics.cards = $o.metrics.cards
        | .cost.cards = $o.cost.cards | .cost.unpriced = $o.cost.unpriced | .declinedRest = $o.declinedRest) end)' \
    "$RUN/conveyor.json" > "$RUN/conveyor.whole" 2>"$RUN/err-history" && mv -f "$RUN/conveyor.whole" "$RUN/conveyor.json" \
    || { echo "dashboard: $host gave no history of every record" >&2; return 1; }
  panels | jq -c '{updatedAt, panels: (.panels | {landed, metrics, cost, declined})}' > "$RUN/out" && [ -s "$RUN/out" ] \
    && mv -f "$RUN/out" "$f" || return 1
  # The key of the copy now kept; none with no key, so a later live feed's key never matches a copy built without it.
  if [ -n "$key" ]; then printf '%s\n' "$key" > "$RUN/key" && mv -f "$RUN/key" "$k"; else rm -f "$k"; fi
  cat "$f"
}

# --work: the Health panel's Work now, what keeps the Conveyor host busy now: `conveyor.sh work --json` of the first
# record, which reads every record's cards, in one command to the host (hostof, onhost), as one {host, groups, other}:
# every record's busy cards (its groups), the heaviest first, and the busy processes no record's card owns. Each
# command is cut to 200 characters. The page server gives it at GET /work, which the page asks for when the owner
# opens Work now or reads it again; never kept.
work() {
  local host main engine target recs why remote cmd
  hostof || { echo "dashboard: no work reading: $why" >&2; return 1; }
  cmd=$(jq -er --arg e "$engine/conveyor/conveyor.sh" 'first(.[] | .main | @sh | "CONVEYOR_MAIN=\(.) bash \($e | @sh) work --json")' <<<"$recs") \
    || { echo "dashboard: no work reading: the host file names no record" >&2; return 1; }
  RUN=$(mktemp -d "$OUT/.run.XXXXXX") || return 1
  onhost "$cmd" > "$RUN/work" 2>"$RUN/err-work" \
    || { echo "dashboard: $host gave no work reading: $(tail -n 1 "$RUN/err-work" | tr -d '\r' | cut -c1-200)" >&2; return 1; }
  jq -ce --arg h "$host" '{host: $h, groups: (.groups | sort_by(-.cpu) | map(.processes |= map(.command |= .[:200]))),
       other: (.other | map(.command |= .[:200]))}' "$RUN/work" 2>"$RUN/err-work" \
    || { echo "dashboard: $host gave no work reading" >&2; return 1; }
}

# --older <repo> <test file>: the older runs and test edits of one test file of a record, which the snapshot leaves
# out: its `conveyor.sh history test <file>` and its origin's address, in one command to the host (hostof, onhost), as
# {file, olderRuns, olderEdits}, each run tagged with its card's issue and that issue's url as the Tests part's runs
# are. The page server gives it at GET /older, which the Tests page asks for when a file's Timeline is opened; never
# kept.
older() {
  local host main engine target recs why remote cmd
  hostof || { echo "dashboard: no older runs: $why" >&2; return 1; }
  cmd=$(jq -er --arg r "$1" --arg f "$2" --arg e "$engine/conveyor/conveyor.sh" 'first(.[] | select(.repo == $r) | .main | @sh)
      | "CONVEYOR_MAIN=\(.) bash \($e | @sh) history test \($f | @sh) && { git -C \(.) remote get-url origin 2>/dev/null || echo; }"' <<<"$recs") \
    || { echo "dashboard: no older runs: the host file names no record $1" >&2; return 1; }
  RUN=$(mktemp -d "$OUT/.run.XXXXXX") || return 1
  onhost "$cmd" > "$RUN/older" 2>"$RUN/err-older" \
    || { echo "dashboard: $host gave no older runs: $(tail -n 1 "$RUN/err-older" | tr -d '\r' | cut -c1-200)" >&2; return 1; }
  jq -ceRs --arg r "$1" 'split("\n") as $l | ($l[1] | (capture("github\\.com[:/](?<p>[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+?)(\\.git)?$") | "https://github.com/\(.p)") // null) as $u
    | $l[0] | fromjson | objects | select((.olderRuns | type) == "array" and (.olderEdits | type) == "array")
    | .olderRuns |= map(objects | (.issue = ([.card | strings | capture("-(?<n>[1-9][0-9]{0,8})$").n | tonumber][0] // null))
        | . + {repo: $r, url: (if $u != null and .issue != null then "\($u)/issues/\(.issue)" else null end)})' "$RUN/older" 2>"$RUN/err-older" \
    || { echo "dashboard: $host gave no older runs" >&2; return 1; }
}

# --donewhen <repo> <card id>: a card's last Done-when check of a record, item by item, which the snapshot leaves out:
# its `conveyor.sh history donewhen <card id>`, in one command to the host (hostof, onhost), as {card, items: [{n, text,
# builder, reviewer}]}. The page server gives it at GET /donewhen, which the Board asks for when a card's Done-when line
# is opened; never kept.
donewhen() {
  local host main engine target recs why remote cmd
  hostof || { echo "dashboard: no Done-when detail: $why" >&2; return 1; }
  cmd=$(jq -er --arg r "$1" --arg c "$2" --arg e "$engine/conveyor/conveyor.sh" 'first(.[] | select(.repo == $r) | .main | @sh)
      | "CONVEYOR_MAIN=\(.) bash \($e | @sh) history donewhen \($c | @sh)"' <<<"$recs") \
    || { echo "dashboard: no Done-when detail: the host file names no record $1" >&2; return 1; }
  RUN=$(mktemp -d "$OUT/.run.XXXXXX") || return 1
  onhost "$cmd" > "$RUN/donewhen" 2>"$RUN/err-donewhen" \
    || { echo "dashboard: $host gave no Done-when detail: $(tail -n 1 "$RUN/err-donewhen" | tr -d '\r' | cut -c1-200)" >&2; return 1; }
  jq -ce 'objects | select(.items | type == "array")' "$RUN/donewhen" 2>"$RUN/err-donewhen" \
    || { echo "dashboard: $host gave no Done-when detail" >&2; return 1; }
}

# --shot <repo> <card> <file>: one screenshot a card waiting for the owner's yes kept, in its kept folder on the host
# (shots/ of kept/<card> in the record's state folder: keepshots(), conveyor/lib/push.sh), as base64 on one ssh
# command. The page server (GET /shot) checks the card and file are of the shapes the snapshot names.
shot() {
  local host main engine target recs why remote cmd
  hostof || { echo "dashboard: no screenshot: $why" >&2; return 1; }
  cmd=$(jq -er --arg r "$1" --arg c "$2" --arg f "$3" --arg e "$engine/conveyor/conveyor.sh" 'first(.[] | select(.repo == $r) | .main | @sh)
      | "f=\"$(CONVEYOR_MAIN=\(.) bash \($e | @sh) state-dir)\"/kept/\($c | @sh)/shots/\($f | @sh) && [ -f \"$f\" ] && base64 < \"$f\""' <<<"$recs") \
    || { echo "dashboard: no screenshot: the host file names no record $1" >&2; return 1; }
  RUN=$(mktemp -d "$OUT/.run.XXXXXX") || return 1
  onhost "$cmd" 2>"$RUN/err-shot" || { echo "dashboard: $host gave no screenshot $3 of card $2: $(tail -n 1 "$RUN/err-shot" | tr -d '\r' | cut -c1-200)" >&2; return 1; }
}

# --excerpts <repo> <card id>: the lines a card's review findings cite, as each review kept them from the tree it read,
# which the snapshot leaves out: its `conveyor.sh history excerpts <card id>`, in one command to the host (hostof,
# onhost), as {card, excerpts: [{review, at, side, from, lines}]}. The page server gives it at GET /excerpts, which the
# Board asks for when a finding's place is opened; never kept.
excerpts() {
  local host main engine target recs why remote cmd
  hostof || { echo "dashboard: no reviewed lines: $why" >&2; return 1; }
  cmd=$(jq -er --arg r "$1" --arg c "$2" --arg e "$engine/conveyor/conveyor.sh" 'first(.[] | select(.repo == $r) | .main | @sh)
      | "CONVEYOR_MAIN=\(.) bash \($e | @sh) history excerpts \($c | @sh)"' <<<"$recs") \
    || { echo "dashboard: no reviewed lines: the host file names no record $1" >&2; return 1; }
  RUN=$(mktemp -d "$OUT/.run.XXXXXX") || return 1
  onhost "$cmd" > "$RUN/excerpts" 2>"$RUN/err-excerpts" \
    || { echo "dashboard: $host gave no reviewed lines: $(tail -n 1 "$RUN/err-excerpts" | tr -d '\r' | cut -c1-200)" >&2; return 1; }
  jq -ce 'objects | select(.excerpts | type == "array")' "$RUN/excerpts" 2>"$RUN/err-excerpts" \
    || { echo "dashboard: $host gave no reviewed lines" >&2; return 1; }
}

# --bench <repo> [<run>]: the Benchmarks tab's history (every run with each arm's figures, and the arms) or, with a
# run's id, that run's tasks by arm, which the snapshot leaves out: the record's `conveyor.sh bench swe history` or
# `bench swe show <run>`, in one command to the host (hostof, onhost). The page server gives it at GET /bench, which
# the tab asks for when it is shown and when a run is opened; never kept.
bench() {
  local host main engine target recs why remote cmd
  hostof || { echo "dashboard: no benchmarks: $why" >&2; return 1; }
  cmd=$(jq -er --arg r "$1" --arg run "$2" --arg e "$engine/conveyor/conveyor.sh" 'first(.[] | select(.repo == $r) | .main | @sh)
      | "CONVEYOR_MAIN=\(.) bash \($e | @sh) bench swe \(if $run == "" then "history" else "show \($run | @sh)" end)"' <<<"$recs") \
    || { echo "dashboard: no benchmarks: the host file names no record $1" >&2; return 1; }
  RUN=$(mktemp -d "$OUT/.run.XXXXXX") || return 1
  onhost "$cmd" > "$RUN/bench" 2>"$RUN/err-bench" \
    || { echo "dashboard: $host gave no benchmarks: $(tail -n 1 "$RUN/err-bench" | tr -d '\r' | cut -c1-200)" >&2; return 1; }
  jq -ce 'objects' "$RUN/bench" 2>/dev/null || { echo "dashboard: $host gave no benchmarks" >&2; return 1; }
}

# view_files -- the page's files, relative to .claude/dashboard: the page, its core, its tab icon and one file per panel.
view_files() { (cd "$VIEW_SRC" && find . -type f \( -name '*.html' -o -name '*.css' -o -name '*.js' -o -name '*.svg' \) | sed 's|^\./||' | LC_ALL=C sort); }
# copy_view -- copy each page file from the primary checkout into $OUT, skipping one that is already the same. Each
# --loop cycle runs it too, so a landed page change is served without a reinstall. The checksum of the installed page
# files, alive.js's `view`, is worked out here, when a file was copied or the list of files changed, into $OUT/.view
# (the list in $OUT/.view-files): alive reads that, not every page file each 15 s.
copy_view() {
  local f list moved=''
  list=$(view_files)
  while IFS= read -r f; do
    [ -n "$f" ] || continue  # no page files: the one empty line <<< gives
    cmp -s "$VIEW_SRC/$f" "$OUT/$f" && continue
    { mkdir -p "$(dirname "$OUT/$f")" && cp "$VIEW_SRC/$f" "$OUT/$f.new.$$" && mv -f "$OUT/$f.new.$$" "$OUT/$f"; } 2>/dev/null \
      || { rm -f "$OUT/$f.new.$$"; echo "dashboard: could not copy $VIEW_SRC/$f into $OUT" >&2; return 1; }
    moved=1
  done <<<"$list"
  [ -z "$moved" ] && [ -s "$OUT/.view" ] && [ "$list" = "$(cat "$OUT/.view-files" 2>/dev/null)" ] && return 0
  rm -f "$OUT/.view"  # a checksum that may be wrong is none, until the new one is in
  { printf '%s\n' "$list" > "$OUT/.view-files" \
    && (cd "$OUT" && xargs -d '\n' cat <<<"$list" 2>/dev/null) | cksum | cut -d' ' -f1 > "$OUT/.view.$$" \
    && mv -f "$OUT/.view.$$" "$OUT/.view"; } 2>/dev/null \
    || { rm -f "$OUT/.view.$$"; echo "dashboard: could not write the page's checksum into $OUT" >&2; return 1; }
}

# The user service and the page server's certificate.
. "$HERE/dashboard_service.sh" || exit 1

# alive -- the --loop heartbeat, $OUT/alive.js: the time now and the cycle stamps the loop left in $OUT/.cycle. The
# page tells a slow cycle (fresh heartbeat, old data.js) from a stopped collector (no heartbeat) by it. `view` is a
# checksum of the installed page files, as copy_view last worked it out ($OUT/.view; null before it has, which the
# page does not compare): a page left open reloads when it changes. No page file is read here.
alive() {
  local at age=null view=null  # snapshotAgeSec: how old the published data.js is, null before the first
  at=$(stat -c %Y "$OUT/data.js" 2>/dev/null) && age=$(( $(date +%s) - at ))
  view=$(cat "$OUT/.view" 2>/dev/null) && [[ $view =~ ^[0-9]+$ ]] && view="\"$view\"" || view=null
  printf 'window.DASH_ALIVE = {"at":"%s","view":%s,"snapshotAgeSec":%s,%s};\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    "$view" "$age" \
    "$(cat "$OUT/.cycle" 2>/dev/null || echo '"cycleStartedAt":null,"lastCycleSec":null')" > "$OUT/.alive.js.$BASHPID" \
    && mv -f "$OUT/.alive.js.$BASHPID" "$OUT/alive.js"
}
# cycle <start-epoch> <seconds|null> -- stamp the cycle for alive.js; written whole, so alive never reads half.
cycle() {
  printf '"cycleStartedAt":"%s","lastCycleSec":%s' "$(iso "$1")" "$2" > "$OUT/.cycle.tmp" && mv -f "$OUT/.cycle.tmp" "$OUT/.cycle"
  alive
}

case "${1:-}" in
  --install) install || { echo "dashboard: install FAILED" >&2; exit 1; }
             echo "dashboard installed; open $OUT/index.html, or https://<this host>.local:$PORT/ from the LAN"; exit 0 ;;
  --uninstall) uninstall; echo "dashboard uninstalled"; exit 0 ;;
  --restart) restart; exit $? ;;
  --update) mkdir -p "$OUT" || exit 1
            update || exit 1 ;;
  --loop) mkdir -p "$OUT" || exit 1
          rm -f "$OUT/.cycle"
          # Every 15 s while this loop lives; a cycle's start and end also write it at once.
          { while kill -0 $$ 2>/dev/null; do alive; sleep 15; done; } & ALV=$!
          last=null
          while :; do
            # Restarted here if it stopped. Its stderr stays in the log: "no certificate" must be seen. Before each
            # start, a certificate that is missing, empty or does not load is made again (cert): the server would
            # exit at once on it, every cycle.
            [ -n "$SRV" ] && kill -0 "$SRV" 2>/dev/null \
              || { cert; "$BOARD_PY" "$HERE/dashboard_server.py" "$PORT" "$OUT" >/dev/null & SRV=$!; }
            # The live feed, restarted here too; its stderr (a stream that keeps failing) stays in the log. The temp
            # files a feed that ended mid-write left are removed first: no feed writes them now.
            [ -n "$STM" ] && kill -0 "$STM" 2>/dev/null \
              || { rm -f "$OUT"/.stream.json.*; python3 "$HERE/dashboard_stream.py" "$OUT" "$PP_MAIN" >/dev/null & STM=$!; }
            copy_view || echo "dashboard: page refresh FAILED; the page keeps the last copy" >&2
            t0=$(date +%s); cycle "$t0" "$last"
            # The cycle is this script run once more, so a hung read can be killed from outside. TERM first,
            # KILL 10 s later; a KILLed cycle runs no exit trap, so its temporary files are cleared here.
            timeout -k 10 "$CYCLE_LIMIT" "$BASH" "$HERE/$NAME.sh"; rc=$?
            if [ "$rc" = 124 ] || [ "$rc" = 137 ]; then
              echo "$(date +%FT%T) dashboard: cycle killed after $CYCLE_LIMIT s; data.js keeps the last snapshot" >&2
              rm -rf "$OUT"/.run.* "$OUT"/.data.js.*
            fi
            last=$(( $(date +%s) - t0 )); cycle "$t0" "$last"
            [ "$last" -le 60 ] || echo "$(date +%FT%T) dashboard: cycle took $last s" >&2
            # The shared installs follow main's lockfiles here, between cycles, where sync-install.sh is installed (a
            # release folder has none). A wait repeats every cycle, so only a changed line is logged.
            si=''; [ ! -e "$HERE/sync-install.sh" ] || si=$(timeout -k 10 "$CYCLE_LIMIT" "$BASH" "$HERE/sync-install.sh" 2>&1)
            [ -z "$si" ] || [ "$si" = "${si_last-}" ] || echo "$si" | sed "s/^/$(date +%FT%T) /" >&2
            si_last=$si
            timeout -k 10 "$CYCLE_LIMIT" "$BASH" "$HERE/$NAME.sh" --update
            sleep 60 & wait $!; done ;;  # a foreground sleep would hold off the TERM trap that stops the server
  --publish) mkdir -p "$CACHE" || exit 1
             republish || { echo "dashboard: publishing the live feed FAILED; data.js keeps the last snapshot" >&2; exit 1; } ;;
  --history) mkdir -p "$CACHE" || exit 1
             history || exit 1 ;;
  --work) mkdir -p "$OUT" || exit 1
          work || exit 1 ;;
  --bench) [ $# = 2 ] || [ $# = 3 ] || { echo "usage: dashboard.sh --bench <repo> [<run>]" >&2; exit 2; }
           mkdir -p "$OUT" || exit 1
           bench "$2" "${3:-}" || exit 1 ;;
  --older) [ $# = 3 ] || { echo "usage: dashboard.sh --older <repo> <test file>" >&2; exit 2; }
           mkdir -p "$OUT" || exit 1
           older "$2" "$3" || exit 1 ;;
  --donewhen) [ $# = 3 ] || { echo "usage: dashboard.sh --donewhen <repo> <card id>" >&2; exit 2; }
              mkdir -p "$OUT" || exit 1
              donewhen "$2" "$3" || exit 1 ;;
  --shot) [ $# = 4 ] || { echo "usage: dashboard.sh --shot <repo> <card> <file>" >&2; exit 2; }
          mkdir -p "$OUT" || exit 1
          shot "$2" "$3" "$4" || exit 1 ;;
  --excerpts) [ $# = 3 ] || { echo "usage: dashboard.sh --excerpts <repo> <card id>" >&2; exit 2; }
              mkdir -p "$OUT" || exit 1
              excerpts "$2" "$3" || exit 1 ;;
  --check) check || exit 1 ;;
  "") mkdir -p "$OUT" || exit 1
      render || { echo "dashboard: collection FAILED; data.js keeps the last snapshot" >&2; exit 1; } ;;
  *) echo "usage: dashboard.sh [--install|--uninstall|--restart|--loop|--publish|--update|--history|--work|--older <repo> <test file>|--donewhen <repo> <card id>|--shot <repo> <card> <file>|--excerpts <repo> <card id>|--bench <repo> [<run>]|--check]" >&2; exit 2 ;;
esac
