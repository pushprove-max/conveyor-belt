# SPDX-License-Identifier: Apache-2.0
# `pick --dry` writes nothing, so it makes no state folder either; its paths are read from where it was called.
# `install`, `install-service`, `board`, `setup` and `doctor` make none either: they run before a project has one,
# install-service and board for the project they were called from. (Setup's label creation goes through gh_write, which makes the
# folder's privacy/ for its record of what it checked.) `state-dir` names the folder and makes nothing: the review gate
# asks it on a machine Conveyor may not run on. `testmap` and `take stale` only read, for /units, which writes nothing, and the Foreman's start; `testmap build` and `stop` write only beside the pack
# (lib/testmap.sh). `lint` reads the tree of the worktree it was called in (CALLED) and makes no state folder: it changes
# neither that worktree nor its index, though `git add -A` on its index's copy puts the new files' objects in the repository.
# `size --list` reads the worktree it was called in too, and makes no state folder either; nor does `precheck`, which a build session runs
# where it may write only in its worktree and the temporary folders.
# `lane research` makes only the lane's own folder in it. CALLED is the folder it was called from.
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
{ [[ ${1:-} =~ ^(pick|install|install-service|board|setup|doctor|state-dir|machine|testmap|lint|size|precheck)$ ]] || [[ "${1:-}:${2:-}" =~ ^(lane:research|take:stale)$ ]] || { mkdir -p "${STATE%/*}" && keepcards && mkdir -p "$CARDS" && : >> "$STATE" && : >> "$RETRIED"; }; } && cd "$MAIN" || exit 1

# Every append and every pick holds one flock on the state file itself, so lines never interleave.
# LOCKHELD tells what runs under it that the lock is held (check(), views.sh): a second flock on the file would wait for ever.
# shellcheck disable=SC2034 # read by check() in lib/views.sh
locked() { ( flock 9 && LOCKHELD=1 && "$@" ) 9>>"$STATE"; }
# The longest a pick, or a snapshot's hold of new issues (adopt), may hold that lock, in seconds: every card's record
# writes wait on it, and one jq that did not end there stopped the whole belt, with no word, until it was stopped by hand.
LOCKLIMIT=120
# locked, for <step>'s work, to LOCKLIMIT seconds. Past it, the work and every process under it are stopped (each
# one holds the lock's file open, and the lock is free only when all of them have ended), the log says which step ran
# out of time, and the status is 124: the step failed, as when it fails on its own. The watch has no stdout (a caller
# that reads the work's output reads to its end) and no lock: neither this one (fd 9) nor the loop's run lock (fd 8),
# which a sleep it leaves behind would hold after the loop is killed.
# shellcheck disable=SC2034 # LOCKHELD: read by check() in lib/views.sh
lockedfor() { # <step> <command> [args]
  local step=$1; shift
  ( flock 9 || exit 1
    LOCKHELD=1; "$@" & p=$!
    ( exec > /dev/null 9>&- 8>&-; s=''; trap 'kill "$s" 2>/dev/null; exit 0' TERM; sleep "$LOCKLIMIT" 2> /dev/null & s=$!; wait "$s" || exit 0; trap '' TERM
      echo "conveyor: $step ran out of time: it held the card records' lock for over $LOCKLIMIT s; it is stopped and the lock is free" >&2
      # shellcheck disable=SC2046 # the pids freeze() (lib/run.sh, loaded by the pick and the snapshot) prints, one word each
      kill -KILL $(freeze "$p") 2>/dev/null; exit 3 ) & k=$!
    wait "$p"; rc=$?; kill "$k" 2>/dev/null; wait "$k"; [ $? != 3 ] || exit 124; exit "$rc" ) 9>>"$STATE"
}
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
    v=$(python3 -S "$HERE/state.py" "${STATE%/*}" "$@" && echo .) || { rc=$?; unset 'ASKED_K[$q]' 'ASKED_V[$q]'; printf '%s' "$v" 2>/dev/null; return "$rc"; }
    ASKED_K[$q]=$k ASKED_V[$q]=${v%.}
  fi
  # A reader may stop before the end (a jq given a bad --argjson stops before it reads its input). The service runs
  # with SIGPIPE ignored, so printf then says "write error: Broken pipe", and the loop's log fills with it: say nothing.
  printf '%s' "${ASKED_V[$q]}" 2>/dev/null
}
# The answers the loop's turn and the cards it starts read: kept in this shell (stdb, above).
stdbkeeps() { { stdb ask lines cards; stdb ask lines retried; stdb ask lines declined; stdb ask tail limit 400; } >/dev/null 2>&1; return 0; }
# The card records as the loop's turn kept them (stdbkeeps, run()): read once a turn and passed on to the turn's own
# readers (run(), reopened(), approved(), overlap(), checkheld(), stuckcard() with turn; only the loop calls them), as one reading for the whole turn. The
# loop keeps them again after each line it writes in the turn, so those readers see the loop's own lines. Asked anew
# when none are kept. A reader that stops early gets no "Broken pipe" line in the log (stdb, above).
turncards() { if [ -n "${ASKED_K[lines cards ]:-}" ]; then printf '%s' "${ASKED_V[lines cards ]}" 2>/dev/null; else stdb ask lines cards; fi; }
# What the readers read (READ, READ_OLD): the state database's whole lines of the card records and of the retried
# lines, or the copy a snapshot or another folder gave in their place. A dry pick (DRYPICK, drypick()) reads the
# files themselves even when its folder is the state folder: the helper would write the database there.
recs() { if [ "$READ" = "$STATE" ] && [ -z "${DRYPICK:-}" ]; then stdb ask lines cards; else cat -- "$READ"; fi; }
olds() { if [ "$READ_OLD" = "$RETRIED" ] && [ -z "${DRYPICK:-}" ]; then stdb ask lines retried; else cat -- "$READ_OLD"; fi; }
# The findings the judge ruled OUTSIDE on the cards of an issue (and on a card), from their review lines: the
# judge.outside ones, and the judge.selfheals ones marked outside (an OUTSIDE ruling whose effect sends it to the
# self-heals list), the last 50, each with its effect and reason, as the judge is given them (judged(): a repeat of one
# gets its ruling again). OUTSIDEDEF is the jq function that reads them from a review line (outlines); the replay reads them with it too.
# It prints no closing blank line, as a command substitution drops it: judged() adds it.
OUTSIDEDEF='def outlines: (.judge.outside[]?, (.judge.selfheals[]? | select(.outside == true))) | objects | select(.finding != null)
  | "- \(.finding) (ruled OUTSIDE: \(if .effect then "\(.effect): " else "" end)\(.reason))";'
outsideruled() { # <card> <issue>
  local l
  l=$({ recs; olds; } 2>/dev/null | jq -rR --arg c "$1" --argjson n "$2" --arg repo "$REPO" "$OUTSIDEDEF"'fromjson? | objects | select(.step == "review" and (.card == $c or (.issue == $n and $n != 0 and .repo == $repo)))
    | outlines' 2>/dev/null | awk '!seen[$0]++' | tail -n 50)
  [ -z "$l" ] || printf '# Findings ruled OUTSIDE on the cards of this issue\n%s' "$l"
}
# Whether a judged review's fields (judged()) hold a ruling: a finding the judge declined or ruled OUTSIDE (judge.declined,
# judge.outside, or judge.selfheals marked outside). card() keeps the tree the first such review read (ftree), so the judge of a later
# review can tell lines a fix round changed after a ruling (it may take also one from before a later ruling: it then rules from the code).
judgeruled() { # <the review's fields>
  jq -e '.judge | objects | ((.declined // []) + (.outside // []) + [(.selfheals // [])[] | select(.outside == true)]) | length > 0' <<<"$1" >/dev/null 2>&1
}
# What a reader needs of each line of a records file of whole lines (a copy: READ, READ_OLD, or what recs or olds
# gave), written to <to>: the output of <filter> (jq -R: it is given each line's text) for each line, in the file's
# order, from a running summary of the file kept beside the history (<kept>), as snaprows keeps the rows: a line
# `<offset> <sum> <key>` (offset: how many of the file's bytes the summary has read; sum: their cksum; key: the filter,
# quoted to one line), then the filter's lines. Only the lines past the offset are read. The summary is made anew from
# the whole file when it is missing, has another key, or its bytes are no longer the file's first bytes: `retry`
# rewrote the file, shorter, or grown past the offset again since. Health, the Tests part and the slow-test list read
# every line of the records whole on each snapshot, and grew with the history. A file not grown since costs two
# programs (cksum and cat), and an empty file none (its output is empty; the summary is left as it is): the snapshot
# is read again and again (t_snapexec counts its programs). The snapshot's copy of the card records (READ, with its
# lineage and size in READG: snapcopy(), lib/snapshot.sh) is not read to sum it: its first bytes are the summary's
# while the lineage, kept in place of the sum, is the same, and only the bytes up to that size are read. That summary
# is kept in <kept>.copy, apart from the one of a reader of the records with no lineage (`conveyor.sh health`, `history
# test`): each wrote over the other's, and the snapshot after such a reader read the whole copy again.
linesum() { # <records file> <kept> <to> <filter>
  local k r cs size h o s n=0 g=''
  if [ -f "$1" ] && [ ! -s "$1" ]; then : > "$3"; return; fi
  printf -v k '%q' "$4"
  [ -z "${READG:-}" ] || [ "$1" != "$READ" ] || g=${READG% *} size=${READG#* }
  if [[ $g == g* ]]; then cs=$g; set -- "$1" "$2.copy" "$3" "$4"; else g=''; r=$(cksum < "$1") && cs=${r%% *} size=${r##* }; fi
  [[ $size =~ ^[0-9]+$ ]] || return 1
  # One open of the summary, its line and the rest read from it: a reader running beside this one may put a newer
  # summary in its place meanwhile.
  { read -r o s h && [ "$h" = "$k" ] && [[ $o =~ ^[0-9]+$ ]] && [ "$o" -le "$size" ] \
      && if [ -n "$g" ] || [ "$o" = "$size" ]; then [ "$s" = "$cs" ]; else [ "$(head -c "$o" "$1" | cksum)" = "$s $o" ]; fi \
      && cat > "$3" && n=$o; } 2>/dev/null < "$2"
  [ "$n" -gt 0 ] || : > "$3" || return 1
  [ "$n" -lt "$size" ] || return 0
  # Only the bytes cksum summed: a line appended since is read at the next call.
  tail -c +$((n + 1)) "$1" | head -c $((size - n)) | jq -cR "$4" >> "$3" || return 1
  { printf '%s %s %s\n' "$size" "$cs" "$k" && cat "$3"; } > "$2.$$" 2>/dev/null && mv -f "$2.$$" "$2" || rm -f "$2.$$"
}
append() { printf '%s\n' "$1" | stdb append cards; }
# The pick a card's own lines hold (the newest), for a line written outside card(), which holds none: a card stopped
# (stopped(), lib/session.sh) or blocked by the loop when its process was gone or stuck (block(), lib/push.sh). Sets
# PICK and PICKCARD, which the caller declares local; a card with no pick leaves them as they were.
heldpick() { # <card>
  local p
  p=$(stdb ask card "$1" 2>/dev/null | jq -cs '[.[] | objects | .pick | objects] | last // empty' 2>/dev/null)
  [ -z "$p" ] || { PICK=$p; PICKCARD=$1; }
}
# One step = one line, of no fixed size (a tail can hold many long lines), appended under the lock (locked, above),
# so another writer's line never lands inside it.
line() { # <card> <issue> <step> <result> [extra json]
  # The extra fields come on stdin, not as an argument: a tail of long lines can be more than one argument can hold.
  # A line of the card whose pick card() holds (PICK, PICKCARD: modelpick(), lib/modelpick.sh) carries it.
  local x=${5:-} p=null; [ -n "$x" ] || x='{}'
  [ -z "${PICK:-}" ] || [ "${PICKCARD:-}" != "$1" ] || p=$PICK
  printf '%s' "$x" | jq -c --arg c "$1" --argjson i "$2" --arg s "$3" --arg r "$4" --arg repo "$REPO" --argjson p "$p" \
    '. as $x | {card:$c,issue:$i,step:$s,time:(now|todate),tokens:{claude:0,codex:0},result:$r,sha:"",reason:"",repo:$repo} * $x | .reason |= .[0:1500]
     | if $p != null then .pick = $p else . end
     | if has("tail") then .tail |= '"($TAIL)"' else . end'
}
# A line's tail (a blocked line's output, the findings of a NO-GO review or of a GO with an OUTSIDE line): its last 60 lines, each whole, so no line loses what it says and identical lines stay
# identical (the Board folds them).
TAIL='split("\n") | .[-60:] | join("\n")'
# A build, fix or rebase line written with no price to read (no usage: its output held none, or the session's fields
# were lost and the line written bare; or unread) keeps that session's output, which clean() removes as the card
# ends, beside the card's kept work: $ST/kept/<card>/<card>.<step>.out (-2, -3 and so on for a later one), so the
# cause can be read. A step run again after a stall or the model API's refusal (lib/session.sh session1(),
# apitries()) wrote a new output over the try before; each try with no price to read left its own first (outfirst()),
# and these are kept first, in try order: the line's unread can be that try's (BOTHTRIES, APIFOLD).
UNPRICED='(.usage | type) != "object" or (.unread | type) == "string"'
# The output of a try with no price to read, before the next try writes over it: <worktree>.out.first for the first,
# then <worktree>.out.first-2 and so on, as outkeep() reads them.
outfirst() { # <worktree>
  local f=$1.out.first n=1
  while [ -e "$f" ]; do n=$((n + 1)); f=$1.out.first-$n; done
  cp "$1.out" "$f" 2>/dev/null || :
}
unpricedleft() { # <worktree>: an earlier try with no price left its output (outfirst()); a try refused on stderr alone leaves an empty one
  local x
  for x in "$1".out.first "$1".out.first-*; do [ ! -s "$x" ] || return 0; done
  return 1
}
outkeep() { # <card> <step> <the line>
  local d=$ST/kept/$1 f n=1 o i=1 u=''
  case $2 in build | fix | rebase) ;; *) return 0 ;; esac
  # Each <card>.out.first* is a try with no price to read, kept whatever the line says: a line stopped() writes in a
  # later try's wait reads that later try alone when it wrote output, or else the tries' fold ($wt.spent), either of
  # which can have a price.
  ! jq -e "$UNPRICED" <<<"$3" >/dev/null 2>&1 || u=1
  o=$CARDS/$1.out.first
  while :; do
    if [ -s "$o" ] && { [ -n "$u" ] || [ "$o" != "$CARDS/$1.out" ]; }; then
      f=$d/$1.$2.out; while [ -e "$f" ]; do n=$((n + 1)); f=$d/$1.$2-$n.out; done
      # An earlier try's output is removed only once it is kept: one that could not be (a full disk) is the only copy.
      if mkdir -p "$d" 2>/dev/null && cp "$o" "$f" 2>/dev/null; then [ "$o" = "$CARDS/$1.out" ] || rm -f "$o"
      else echo "conveyor: card $1: its $2 line has no price to read, and its output could not be kept in $d$([ "$o" = "$CARDS/$1.out" ] || echo "; it is left at $o")" >&2; fi
    elif [ "$o" != "$CARDS/$1.out" ]; then rm -f "$o"
    fi
    [ "$o" != "$CARDS/$1.out" ] || break
    i=$((i + 1)); o=$CARDS/$1.out.first-$i; [ -e "$o" ] || o=$CARDS/$1.out
  done
}
# A step's line is always written: one whose extra fields are not one JSON object is written without them,
# and says so (unread, with the start of what they were), so the card goes on. A line that cannot be written at all
# (twice, a second apart) ends the card as blocked (block keeps its change as a patch and removes its worktree), so
# a card is never left open with its worktree behind; then this process stops. A build, fix or rebase line with no
# price to read keeps its session's output (outkeep).
record() { # <card> <issue> <step> <result> [extra json]
  local l
  l=$(line "$@" 2>/dev/null) || l=$(line "$1" "$2" "$3" "$4" "$(jq -cn --arg x "${5:0:300}" '{unread: ("the fields of this line were not one JSON object, so they were left out: " + $x)}')" 2>/dev/null) || l=''
  [ -n "$l" ] && { locked append "$l" || { sleep 1; locked append "$l"; }; } && { outkeep "$1" "$3" "$l"; return 0; }
  echo "conveyor: cannot record $1 $3" >&2
  [ "$3" = blocked ] || [ ! -d "$CARDS/$1" ] || block "$1" "$2" "$CARDS/$1" "conveyor: the engine could not write the $3 line of this card to the card records"
  exit 1
}
# The dollars of steps at list price (dashboard_limit.py work, the Board's price table with the pack's prices over it):
# steps [{step, model, usage, tokens, ...}] as a JSON array on stdin; null when one of them has no price, or the price
# could not be read. spent() and replayusd() (lib/replay.sh) price with it.
stepsusd() {
  local pp u; packget prices pp 2>/dev/null && [ -n "$pp" ] || pp='{}'
  u=$(jq -c --argjson p "$pp" '{steps: ., live: null, prices: $p}' 2>/dev/null | python3 "$HERE/../.claude/scripts/dashboard_limit.py" work 2>/dev/null \
    | jq -c 'if .state == "known" then .usd else null end' 2>/dev/null) || u=''
  printf '%s\n' "${u:-null}"
}
# What a card and the cards of its issue spent: {card, issue}, each the dollars at list price of the sessions and reviews
# their step lines hold (stepsusd), a failed one a blocked line keeps (spent) too, and each judge call a review line (or
# that failed session) holds in its judge, a step of its own as the Board's trial cost prices it (swe_cost(),
# bench/swe.sh): a judge with no sec (judgecall() writes it once a call ran) ran no call and costs nothing. The issue's
# are from the card records and the retried lines of the issue (this repository's). A total is null when one of its steps
# has no price or its lines could not be read, and the issue's is null for issue 0, which has no cards beside the card's
# own: no limit is checked on a null total (usdstop(), below). Both are rounded to the cent.
SPENTSTEPS='[.[] | objects | (if .step | IN("seats", "build", "review", "fix", "rebase") then . elif .step == "blocked" and (.spent | type) == "object" then .spent else empty end)
  | ., (.judge | objects | select(has("sec")) | {step: "judge", model, usage, tokens})]'
spent() { # <card> <issue>
  local c i='' l
  c=$(stdb ask card "$1" 2>/dev/null) && c=$(jq -cs "$SPENTSTEPS" <<<"$c" 2>/dev/null | stepsusd) || c=null
  if [[ ${2:-0} =~ ^[1-9][0-9]*$ ]]; then
    l=$({ stdb ask issue cards "$2" && stdb ask issue retried "$2"; } 2>/dev/null) && i=$(jq -cs --arg repo "$REPO" "map(objects | select(.repo == \$repo)) | $SPENTSTEPS" <<<"$l" 2>/dev/null | stepsusd)
  fi
  jq -cn --argjson c "$c" --argjson i "${i:-null}" 'def cent: if . == null then null else (. * 100 | round) / 100 end; {card: ($c | cent), issue: ($i | cent)}'
}
# The dollar limits of a card and of its issue: the rules cardusd and issueusd of the control record (whole dollars,
# 0 for off), which this is the one place to read. A session (session(), lib/session.sh) whose card (named by its
# worktree) or issue (SEATCARD, set by card()) has spent the limit or more (spent(): the step lines at list price) does
# not start: this prints why, the issue's limit first, and fails, and the caller blocks the card, which keeps its patch. A
# running session is never ended, so a card can pass a limit by one step. A total with no price (a step whose model has
# none) is not checked: the session starts and the loop log says so. Issue 0 has no issue limit.
usdstop() { # <worktree>
  local c=${1##*/} n=${SEATCARD:-0} cl il s
  [[ $n =~ ^[0-9]+$ ]] || n=0
  ctlread 2>/dev/null && read -r cl il <<<"$(jq -r '[.rules.cardusd // 0, .rules.issueusd // 0] | @tsv' <<<"$CTL_V" 2>/dev/null)" && [[ $cl =~ ^[0-9]+$ && $il =~ ^[0-9]+$ ]] || return 0
  [ "$n" != 0 ] || il=0
  [ "$cl" != 0 ] || [ "$il" != 0 ] || return 0
  s=$(spent "$c" "$n") || return 0
  jq -er --argjson cl "$cl" --argjson il "$il" --argjson n "$n" '
    def usd: (. * 100 | round) as $c | "$\($c / 100 | floor)" + (if $c % 100 == 0 then "" else ".\($c % 100 | if . < 10 then "0\(.)" else "\(.)" end)" end);
    if $il > 0 and .issue != null and .issue >= $il then "stopped at the dollar limit of issue #\($n): its cards spent \(.issue | usd) of $\($il)"
    elif $cl > 0 and .card != null and .card >= $cl then "stopped at the dollar limit of the card: it spent \(.card | usd) of $\($cl)"
    else empty end' <<<"$s" 2>/dev/null && return 1
  jq -e --argjson cl "$cl" --argjson il "$il" '($cl > 0 and .card == null) or ($il > 0 and .issue == null)' <<<"$s" >/dev/null 2>&1 \
    && echo "conveyor: card $c: its dollar limits were not checked: the cost of one of its steps, or of its issue's, is not known" >&2
  return 0
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
# The field a closed line adds: called in card(), {waitSec}, the seconds the card waited on other cards, for main to
# change and for the machine hold or the repair lane (card()'s waitsec and mainsec), as on its landed and blocked lines, for the drift watch (bench/drift.sh), which
# would leave a closed card out of the mean wait without it; outside card(), {}.
waited() { if [ -n "${waitsec+x}" ]; then echo "{\"waitSec\":$((waitsec + ${mainsec:-0}))}"; else echo '{}'; fi; }
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
# The two forms a blocked line's reason starts with when the card stops for the owner's yes (block(), lib/card.sh):
# YES, to a visible change, and LINTYES, to a change of lint policy (lintpolicy(), lib/lint.sh) and no visible change.
# Set by names() (lib/prompts.sh), and by the snapshot's reader of the card records (recordsnow(), commands/snapshot.sh),
# which runs before the pack is read.
# shellcheck disable=SC2034 # YES and LINTYES are read in lib/card.sh, lib/issues.sh, lib/views.sh and commands/snapshot.sh
yesforms() { # <owner>
  YES="visible to customers or staff: needs $1's yes: "
  LINTYES="lint policy: needs $1's yes: "
}
# One loop and host sample (README.md), appended to SAMPLES; only the loop writes there. Kept to 14 days of
# minutes. A reading the host does not give is null.
# wait, while the loop runs or the weekly limit guard pauses it and an issue waits: {"<issue>": <cause>} for the issues
# of the line (upnext's whole list, less those a rule other than the guard leaves out, that wait for the owner's yes
# before their build or that are stuck) up to and with the first one the pick would take. Each issue before that one
# waits on its own cause: "held" (the control record holds it), "guard" (the weekly limit guard holds its seats) or a
# dependency, "overlap" when this loop's same-file check added its Depends on: line (overlap(), OVL_SEEN; after a
# restart it reads "Depends on"), else "Depends on". The one the pick would take waits on "guard" while the guard
# pauses the loop (state "paused by guard"), else on "machine hold" while the machine hold stands (a fault of the
# machine, not a red main: machineheld(), lib/mainred.sh), else on "cap" while every slot is taken or the machine
# holds it back (room(), ROOMF); with none of these it waits on nothing and is not named. A red main holds no pick
# back: a card that waits for main's fix leaves its slot (mainwait()). The metrics add these up per card (waitWhy,
# jq/metrics.jq).
sample() { # <slots in use> <cap> <loop state> [the machine hold, while one stands]
  local load mem disk queued='' issues line='' w='' ovl room k full
  # queued: the issues a pick would take now, the control record's holds and rules applied (upnext's filter, on its
  # whole list); null when GitHub does not list them. Asked here, out of the loop's turn (run() starts this apart),
  # one asking at a time.
  exec 6>>"$SAMPLES.lock" && flock -n 6 || return 0
  issues=$({ p_newer "$ISSUES" "$SAMPLE" && cat "$ISSUES" || openissues "$FIELDS"; } 2>/dev/null) && line=$(upnext "$issues" '' all 2>/dev/null) \
    && queued=$(jq -e 'map(select((.hold | not) and .rule == null and (.waits == [] or .forced) and (.before | not))) | length' <<<"$line" 2>/dev/null) || { queued=''; line=''; }
  if [ -n "$line" ] && { [ "$3" = running ] || [ "$3" = "paused by guard" ]; }; then
    ovl=$(for k in "${!OVL_SEEN[@]}"; do [[ ! $k =~ ^[0-9]+$ ]] || echo "$k"; done | jq -cs .) || ovl='[]'
    room=$(jq -r '.issue | numbers' "$ROOMF" 2>/dev/null) || room=''
    full=false; [[ ${2:-} =~ ^[0-9]+$ && $1 =~ ^[0-9]+$ ]] && [ "$2" -gt 0 ] && [ "$1" -ge "$2" ] && full=true
    w=$(jq -c --argjson ovl "$ovl" --arg room "$room" --arg st "$3" --arg mhold "${4:-}" --argjson full "$full" '
      def why: if .hold then "held" elif .rule == "the weekly limit guard" then "guard"
        elif .waits != [] and (.forced | not) then (if .number | IN($ovl[]) then "overlap" else "Depends on" end) else null end;
      [.[] | select((.rule == null or .rule == "the weekly limit guard") and (.stuck | not) and (.before | not))] as $l
      | ([range($l | length) | select($l[.] | why == null)] | first) as $i
      | [$l[:(if $i == null then ($l | length) else $i + 1 end)][]
        | {key: (.number | tostring), value: (why // (if $st == "paused by guard" then "guard" elif $mhold != "" then "machine hold" elif $full or (.number | tostring) == $room then "cap" else null end))}
        | select(.value != null)] | from_entries | select(. != {})' <<<"$line" 2>/dev/null) || w=''
  fi
  load=$(p_load); mem=$(p_mem)
  disk=$(diskfree) || disk=''
  jq -cn --argjson s "$1" --argjson c "${2:-null}" --arg st "$3" --arg l "$load" --arg m "$mem" --arg d "$disk" --arg q "$queued" --argjson w "${w:-null}" '
    def n: tonumber? // null;
    {time: (now | todate), slots: $s, cap: $c, state: $st, queued: ($q | n), load: ($l | n), memUsedKb: ($m | split(" ")[0] | n), memTotalKb: ($m | split(" ")[1] // "" | n),
     diskFreeKb: ($d | n)} + (if $w == null then {} else {wait: $w} end)' 2>/dev/null | stdb append samples 2>/dev/null || return 0
  stdb keep samples 30000 20160 2>/dev/null || return 0
}
