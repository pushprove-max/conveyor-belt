# SPDX-License-Identifier: Apache-2.0
# `pick --dry` writes nothing, so it makes no state folder either; its paths are read from where it was called.
# `install`, `install-service`, `board`, `setup` and `doctor` make none either: they run before a project has one,
# install-service and board for the project they were called from. (Setup's label creation goes through gh_write, which makes the
# folder's privacy/ for its record of what it checked.) `state-dir` names the folder and makes nothing: the review gate
# asks it on a machine Conveyor may not run on. `testmap` and `take stale` only read, for /units, which writes nothing, and the Foreman's start; `testmap build` and `stop` write only beside the pack
# (lib/testmap.sh). `lane research`
# makes only the lane's own folder in it. CALLED is the folder it was called from.
CALLED=$PWD
# Keeps the cards folder's name, and takes the name kept. One command at a time (the flock) keeps the name it chose
# when no name is kept, and a file that holds no name (an empty one, say) is no name kept: it is replaced, whole,
# never left for a command after a project is added beside to choose another folder by. So two commands that chose
# at one time, on each side of a project being added, both take the name of the one that kept its first, and
# neither writes to a folder the other does not read.
keepcards() {
  [ -z "${CONVEYOR_CARDS:-}" ] || return 0
  local kept
  ( flock 9 && { keptcards "$CARDSNAME" >/dev/null || { printf '%s\n' "${CARDS##*/}" > "$CARDSNAME.$$" && mv -f "$CARDSNAME.$$" "$CARDSNAME"; }; } ) 9>>"$CARDSNAME" \
    && kept=$(keptcards "$CARDSNAME") && CARDS=$(dirname "$MAIN")/$kept
}
{ [[ ${1:-} =~ ^(pick|install|install-service|board|setup|doctor|state-dir|machine|testmap)$ ]] || [[ "${1:-}:${2:-}" =~ ^(lane:research|take:stale)$ ]] || { mkdir -p "${STATE%/*}" && keepcards && mkdir -p "$CARDS" && : >> "$STATE" && : >> "$RETRIED"; }; } && cd "$MAIN" || exit 1

# Every append and every pick holds one flock on the state file itself, so lines never interleave.
# LOCKHELD tells what runs under it that the lock is held (check(), views.sh): a second flock on the file would wait for ever.
# shellcheck disable=SC2034 # read by check() in lib/views.sh
locked() { ( flock 9 && LOCKHELD=1 && "$@" ) 9>>"$STATE"; }
# The state database (state.py): the only reader and writer of the history files (the card records, the retried
# lines, the declined list, the samples and the limit readings). Every line is appended, and every rewrite written,
# through it, to its table and its file both; every reader asks it, but check() (views.sh), which checks the card
# records file's own bytes.
# -S: it imports the standard library alone, and the site start-up was a fifth of each call's time.
#
# The answer to one question (`ask <question> <arg>...`, no -o) is kept in the shell that asked (ASKED_V, by the
# question) while the files of the tables it reads are unchanged since (ASKED_K: p_filekey of each, or that it is not
# there, read before the database was asked): each append and rewrite goes to the file too, and the database takes its
# lines from the files alone, so unchanged files get the same answer. A file that changed is asked again; an answer
# that failed is kept no more. A subshell finds what its shell kept: the loop keeps what its turn and its cards read
# most (stdbkeeps, run()), a card its issue's retried lines (card()), and a waiting card the card records before each
# look (settle()), so their readers, in subshells, ask the database once between two writes, not once each.
declare -A ASKED_K=() ASKED_V=()
stdb() {
  local q k='' t v rc
  if [ "${1:-}" = ask ] && [ $# -ge 2 ] && [ "$2" != -o ] && [[ " $* " != *" -- "* ]]; then
    case $2 in lines|issue|tail) t=${3:-} ;; pushes) t='cards retried' ;; samples|limit) t=$2 ;; *) t=cards ;; esac
    for t in $t; do
      [[ $t =~ ^(cards|retried|declined|samples|limit)$ ]] || { k=''; break; }
      k+=$(p_filekey "${STATE%/*}/$t.jsonl" || echo "none ${STATE%/*}/$t.jsonl")$'\n'
    done
  fi
  [ -n "$k" ] || { python3 -S "$HERE/state.py" "${STATE%/*}" "$@"; return; }
  printf -v q '%q ' "${@:2}"
  # A table whose file is not there, or empty, holds no line (the database takes its lines from the file): its lines,
  # an issue's, its tail, its readings and its samples are none, asked of no database, and no older answer is kept.
  if [[ $k == 0\ * || $k == none\ * ]]; then
    case $2:$# in lines:3|limit:3|samples:2) unset 'ASKED_K[$q]' 'ASKED_V[$q]'; return 0 ;;
      issue:4|tail:4) [[ $4 =~ ^[0-9]+$ ]] && { unset 'ASKED_K[$q]' 'ASKED_V[$q]'; return 0; } ;; esac
  fi
  if [ "$k" != "${ASKED_K[$q]:-}" ]; then
    v=$(python3 -S "$HERE/state.py" "${STATE%/*}" "$@" && echo .) || { rc=$?; unset 'ASKED_K[$q]' 'ASKED_V[$q]'; printf '%s' "$v"; return "$rc"; }
    ASKED_K[$q]=$k ASKED_V[$q]=${v%.}
  fi
  printf '%s' "${ASKED_V[$q]}"
}
# The answers the loop's turn and the cards it starts read: kept in this shell (stdb, above).
stdbkeeps() { { stdb ask lines cards; stdb ask lines retried; stdb ask lines declined; stdb ask tail limit 400; } >/dev/null 2>&1; return 0; }
# The card records as the loop's turn kept them (stdbkeeps, run()): read once a turn and passed on to the turn's own
# readers (run(), reopened(), approved(), overlap(), checkheld(); only the loop calls them), as one reading for the whole turn. The
# loop keeps them again after each line it writes in the turn, so those readers see the loop's own lines. Asked anew
# when none are kept.
turncards() { if [ -n "${ASKED_K[lines cards ]:-}" ]; then printf '%s' "${ASKED_V[lines cards ]}"; else stdb ask lines cards; fi; }
# What the readers read (READ, READ_OLD): the state database's whole lines of the card records and of the retried
# lines, or the copy a snapshot or another folder gave in their place. A dry pick (DRYPICK, drypick()) reads the
# files themselves even when its folder is the state folder: the helper would write the database there.
recs() { if [ "$READ" = "$STATE" ] && [ -z "${DRYPICK:-}" ]; then stdb ask lines cards; else cat -- "$READ"; fi; }
olds() { if [ "$READ_OLD" = "$RETRIED" ] && [ -z "${DRYPICK:-}" ]; then stdb ask lines retried; else cat -- "$READ_OLD"; fi; }
# What a reader needs of each line of a records file of whole lines (a copy: READ, READ_OLD, or what recs or olds
# gave), written to <to>: the output of <filter> (jq -R: it is given each line's text) for each line, in the file's
# order, from a running summary of the file kept beside the history (<kept>), as snaprows keeps the rows: a line
# `<offset> <sum> <key>` (offset: how many of the file's bytes the summary has read; sum: their cksum; key: the filter,
# quoted to one line), then the filter's lines. Only the lines past the offset are read. The summary is made anew from
# the whole file when it is missing, has another key, or its bytes are no longer the file's first bytes: `retry`
# rewrote the file, shorter, or grown past the offset again since. Health, the Tests part and the slow-test list read
# every line of the records whole on each snapshot, and grew with the history. A file not grown since costs two
# programs (cksum and cat): the snapshot is read again and again (t_snapexec counts its programs).
linesum() { # <records file> <kept> <to> <filter>
  local k r cs size h o s n=0
  printf -v k '%q' "$4"
  r=$(cksum < "$1") && cs=${r%% *} size=${r##* } && [[ $size =~ ^[0-9]+$ ]] || return 1
  # One open of the summary, its line and the rest read from it: a reader running beside this one may put a newer
  # summary in its place meanwhile.
  { read -r o s h && [ "$h" = "$k" ] && [[ $o =~ ^[0-9]+$ ]] && [ "$o" -le "$size" ] \
      && if [ "$o" = "$size" ]; then [ "$s" = "$cs" ]; else [ "$(head -c "$o" "$1" | cksum)" = "$s $o" ]; fi \
      && cat > "$3" && n=$o; } 2>/dev/null < "$2"
  [ "$n" -gt 0 ] || : > "$3" || return 1
  [ "$n" -lt "$size" ] || return 0
  # Only the bytes cksum summed: a line appended since is read at the next call.
  tail -c +$((n + 1)) "$1" | head -c $((size - n)) | jq -cR "$4" >> "$3" || return 1
  { printf '%s %s %s\n' "$size" "$cs" "$k" && cat "$3"; } > "$2.$$" 2>/dev/null && mv -f "$2.$$" "$2" || rm -f "$2.$$"
}
append() { printf '%s\n' "$1" | stdb append cards; }
# One step = one line, of no fixed size (a tail can hold many long lines), appended under the lock (locked, above),
# so another writer's line never lands inside it.
line() { # <card> <issue> <step> <result> [extra json]
  # The extra fields come on stdin, not as an argument: a tail of long lines can be more than one argument can hold.
  local x=${5:-}; [ -n "$x" ] || x='{}'
  printf '%s' "$x" | jq -c --arg c "$1" --argjson i "$2" --arg s "$3" --arg r "$4" --arg repo "$REPO" \
    '. as $x | {card:$c,issue:$i,step:$s,time:(now|todate),tokens:{claude:0,codex:0},result:$r,sha:"",reason:"",repo:$repo} * $x | .reason |= .[0:1500]
     | if has("tail") then .tail |= '"($TAIL)"' else . end'
}
# A line's tail (a blocked line's output, a NO-GO review's findings): its last 60 lines, each whole, so no line loses what it says and identical lines stay
# identical (the Board folds them).
TAIL='split("\n") | .[-60:] | join("\n")'
# A step's line is always written: one whose extra fields are not one JSON object is written without them,
# and says so (unread, with the start of what they were), so the card goes on. A line that cannot be written at all
# (twice, a second apart) ends the card as blocked (block keeps its change as a patch and removes its worktree), so
# a card is never left open with its worktree behind; then this process stops.
record() { # <card> <issue> <step> <result> [extra json]
  local l
  l=$(line "$@" 2>/dev/null) || l=$(line "$1" "$2" "$3" "$4" "$(jq -cn --arg x "${5:0:300}" '{unread: ("the fields of this line were not one JSON object, so they were left out: " + $x)}')" 2>/dev/null) || l=''
  [ -n "$l" ] && { locked append "$l" || { sleep 1; locked append "$l"; }; } && return 0
  echo "conveyor: cannot record $1 $3" >&2
  [ "$3" = blocked ] || [ ! -d "$CARDS/$1" ] || block "$1" "$2" "$CARDS/$1" "conveyor: the engine could not write the $3 line of this card to the card records"
  exit 1
}

# The measurements (README.md). The newest weekly limit reading's percent, from the readings file
# only (nothing is asked here): nothing when none is younger than LIMIT_OLD. Each is the account's in use (ACCT): a
# line names its account, and one that names none is the default login's.
lastread() {
  { if [ "$LIMIT" = "${STATE%/*}/limit.jsonl" ] && [ -z "${DRYPICK:-}" ]; then stdb ask tail limit 400; else tail -n 400 "$LIMIT"; fi; } 2>/dev/null | jq -cRn --arg a "$ACCT" --argjson old "$LIMIT_OLD" '[inputs | fromjson? | objects | select((.account // "") == $a)]
    | last // empty | select((.pct | type == "number") and now - (.time | fromdate) <= $old) | {time, pct}' 2>/dev/null
}
lastpct() { lastread | jq -r .pct; }
# The fields a closing line (landed, closed, blocked) adds: {limit} when there is a reading, else {}.
ending() { local p; p=$(lastpct); if [ -n "$p" ]; then echo "{\"limit\":$p}"; else echo '{}'; fi; }
# The size of a worktree's staged change, {files, added, removed}; a binary file is a file with no lines.
diffsize() { # <worktree>
  git -C "$1" diff --cached --numstat --no-renames 2>/dev/null \
    | awk -F'\t' '{f++; if ($1 != "-") a += $1; if ($2 != "-") r += $2} END {printf "{\"files\":%d,\"added\":%d,\"removed\":%d}\n", f, a, r}'
}
# The tests of a run, from the summary lines the runners print (scripts/test-changed.sh): files selected (root and
# web), and the tests, passed, failed (cancelled ones too) and skipped (todo too). A count no line gives is null, and
# so are all four when a half that ran gave no totals (its "totals unavailable", or no totals line at all): a sum of
# the other half alone would read as the whole run.
testcounts() { # <test output file>
  sed 's/\x1b\[[0-9;]*m//g' "$1" 2>/dev/null | awk '
    function n(v) { return v == "" ? "null" : v + 0 }
    /^test-changed: [0-9]+ (root )?test file\(s\) selected/ { files += $2; sf = 1; if ($2 > 0) rsel = 1 }
    /^test-changed: [0-9]+ web test file\(s\) selected/ { files += $2; sf = 1; if ($2 > 0) wsel = 1 }
    /^test-changed: [a-z]+ totals unavailable/ || /^test-changed: web totals: .*Tests unavailable/ { gone = 1 }
    /^test-changed: root totals: tests / { rseen = 1 }
    /^test-changed: web totals: .*; Tests[[:space:]]+[0-9]/ { wseen = 1 }
    /^test-changed: root totals: tests / { l = $0; gsub(/,/, "", l); k = split(l, w, /[[:space:]]+/)
      for (i = 1; i < k; i++) { v = w[i + 1]; if (v !~ /^[0-9]+$/) continue
        if (w[i] == "tests") t += v; else if (w[i] == "pass") p += v; else if (w[i] == "fail" || w[i] == "cancelled") f += v; else if (w[i] == "skipped" || w[i] == "todo") s += v }
      seen = 1 }
    /^test-changed: web totals: .*; Tests[[:space:]]+[0-9]/ { l = $0; sub(/.*; Tests[[:space:]]+/, "", l)
      if (match(l, /\(([0-9]+)\)/)) t += substr(l, RSTART + 1, RLENGTH - 2)
      k = split(l, w, /[[:space:]]*\|[[:space:]]*/)
      for (i = 1; i <= k; i++) { split(w[i], x, /[[:space:]]+/)
        if (x[2] ~ /^passed/) p += x[1]; else if (x[2] ~ /^failed/) f += x[1]; else if (x[2] ~ /^(skipped|todo)/) s += x[1] }
      seen = 1 }
    END { if (!seen || gone || (rsel && !rseen) || (wsel && !wseen)) t = p = f = s = ""; else { t += 0; p += 0; f += 0; s += 0 }
      printf "{\"files\":%s,\"total\":%s,\"passed\":%s,\"failed\":%s,\"skipped\":%s}\n", (sf ? files + 0 : "null"), n(t), n(p), n(f), n(s) }'
}
# One loop and host sample (README.md), appended to SAMPLES; only the loop writes there. Kept to 14 days of
# minutes. A reading the host does not give is null.
sample() { # <slots in use> <cap> <loop state>
  local load mem disk queued='' issues
  # queued: the issues a pick would take now, the control record's holds and rules applied (upnext); null when GitHub
  # does not list them. Asked here, out of the loop's turn (run() starts this apart), one asking at a time.
  exec 6>>"$SAMPLES.lock" && flock -n 6 || return 0
  issues=$({ p_newer "$ISSUES" "$SAMPLE" && cat "$ISSUES" || openissues "$FIELDS"; } 2>/dev/null) && queued=$(upnext "$issues" 2>/dev/null | jq -e length 2>/dev/null) || queued=''
  load=$(p_load); mem=$(p_mem)
  disk=$(df -Pk "$CARDS" 2>/dev/null | awk 'NR == 2 {print $4}')
  jq -cn --argjson s "$1" --argjson c "${2:-null}" --arg st "$3" --arg l "$load" --arg m "$mem" --arg d "$disk" --arg q "$queued" '
    def n: tonumber? // null;
    {time: (now | todate), slots: $s, cap: $c, state: $st, queued: ($q | n), load: ($l | n), memUsedKb: ($m | split(" ")[0] | n), memTotalKb: ($m | split(" ")[1] // "" | n),
     diskFreeKb: ($d | n)}' 2>/dev/null | stdb append samples 2>/dev/null || return 0
  stdb keep samples 30000 20160 2>/dev/null || return 0
}
