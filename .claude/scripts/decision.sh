#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# decision.sh add <id> <question> <proposedDefault> <source> [--options '<JSON array>'] [--reask <what is new>] [--unit <unit>]
#           | answer <id> <answer> [--asked-at <askedAt> | --correct]
#           | reopen <id> | list | rulings <term>... | growth <unit> <ruling-id> <subject> +<n>...
#           | digest [<YYYY-MM-DD>] [--no-picks | --picks <ledger>...]
# digest: the owner's day's page; dashboard.sh writes it beside data.js.
# answer and answer --correct record the answer in the ledger and do nothing else: no answer is delivered to any pane
# or session. The Foreman session and the dashboard read answers from the ledger.
# add with no --unit records the live unit its id names (Decision 44).
# growth <unit> <ruling-id> <subject> +<n>...: main records a test-count raise under the owner's grant (Decision 34). It
# appends an answered row, `Unit <unit>: may it grow <subject> +<n>, ...?` answered `Yes (<ruling-id>)`, the row
# new-test-count.sh's growth() ties a plan's `Subject growth:` line to. Refused, nothing written, from any checkout that
# is not main's, so a Builder cannot grant itself a raise. An `answer` to a question that asks to grow a subject by +<n>
# warns on stderr when the answer holds no ruling id; it never refuses.
# rulings <term>...: the owner's earlier picker answers from the ruling log, for a plan author to read before it writes
# a question. Void rows are left out; a term is plain text matched in any case on the question or the answer;
# newest first, one line each, `<id> <et>: <question> -> <answer>`. Exit 0 with nothing printed when no row matches.
# The decisions ledger, .claude/metrics/decisions.jsonl in the primary checkout:
# append-only, one complete snapshot per line, the latest line per id wins.
# The dashboard's Needs you card shows the unanswered ones with their default;
# the page never adds, reopens or applies one, and answers only through
# dashboard_server.py's /answer, which runs `answer --asked-at`. Every read-validate-append holds
# the ledger's lock, so a duplicate id or a double answer cannot race in.
# --options: the 2 to 4 answers the card offers as buttons, each one
# the server's /answer would accept; a row without
# them shows its default alone. "Printable" is Python's str.isprintable(), the
# server's test: no \p{C} or \p{Z} character but the ASCII space;
# ask-records-decision.sh holds the same pattern.
#
# A question the owner still has open, or answered in the last 24 hours, is not added
# again: add exits 3 naming the earlier decision and its answer, prints that
# decision's snapshot, and appends nothing. --reask with the new facts, logged in
# the source, adds it anyway; a --reask of an existing id appends a fresh open
# snapshot. Exit 1 is every other failure. ask-records-decision.sh refuses no
# picker on 3: it asks an open decision it repeats afresh with --reask, else adds
# the picker's row with --reask.
# --unit: the unit the decision holds, stored as the row's `unit`; the units mod reads it, never the id. Every
# row add appends carries it when given; answer and reopen copy the whole row.
# CONVEYOR_LEDGER: the ledger file itself, in place of the checkout's; the Board names each project's ledger by it,
# as the host file's records[].ledger gives it.
# Test seams: CONVEYOR_MAIN; XDG_CONFIG_HOME (where the host file is); CONVEYOR_RULING_LOG.
set -uo pipefail
DIGEST_USAGE='digest [<YYYY-MM-DD>] [--no-picks | --picks <ledger>...]'
USAGE="usage: decision.sh add <id> <question> <proposedDefault> <source> [--options '<JSON array>'] [--reask <what is new>] [--unit <unit>] | answer <id> <answer> [--asked-at <askedAt> | --correct] | reopen <id> | list | rulings <term>... | growth <unit> <ruling-id> <subject> +<n>... | $DIGEST_USAGE
answer (and --correct) records the answer in the ledger only; it is delivered to no pane or session."
case ${1:-} in
  --help|-h) printf '%s\nexample: decision.sh add push-sample-project-abc123 "Push 3 commits?" "yes" "main, 2026-10-19"\n' "$USAGE"; exit 0 ;;
esac
# The Mac's Homebrew flock and GNU tools lead PATH, ahead of a login shell's /usr/bin, so a direct run finds them as the
# Board's does. Twin of dashboard.sh's Mac PATH repair.
if [ "$(uname -s)" = Darwin ]; then
  for d in /opt/homebrew/bin /opt/homebrew/opt/*/libexec/gnubin; do [ ! -d "$d" ] || PATH=$d:$PATH; done
  export PATH
fi
# This machine's primary checkout, by dashboard.sh's rule: CONVEYOR_MAIN (the project's main checkout, also named by
# the decision-log hooks when the plugin runs from its own install), else this script's git common dir (twin of
# paths.sh's PP_MAIN); never the host file's `main`, which is the Conveyor host's checkout. It moves with the Board,
# which sources no support script of the project's, so it sources no paths.sh.
if [ -n "${CONVEYOR_MAIN:-}" ]; then PP_MAIN=$CONVEYOR_MAIN
else
  PP_MAIN=$(git -C "$(dirname "$0")" rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || PP_MAIN=''
  case $PP_MAIN in
    */.git) PP_MAIN=${PP_MAIN%/.git} ;;
    *) echo "decision: cannot resolve the primary checkout from $(dirname "$0") (git common dir: ${PP_MAIN:-none}); set CONVEYOR_MAIN" >&2; exit 1 ;;
  esac
fi
L=${CONVEYOR_LEDGER:-$PP_MAIN/.claude/metrics/decisions.jsonl}
RULINGS=${CONVEYOR_RULING_LOG:-$HOME/.claude/rulings/conveyor.jsonl}
die() { echo "decision: $*" >&2; exit 1; }
usage() { die "$USAGE"; }

# lock <-s|-x> -- held on the ledger itself until the script exits.
lock() { [ -r "$L" ] && exec 9<"$L" || die "no ledger at $L"; flock "$1" 9 || die "could not lock $L"; }

# The ledger's one fence: every reader that gates on a row reads through fold.
# A row is one line holding a complete snapshot; a blank line is no row.
BAD_LINES='split("\n") | to_entries | map(select(.value | test("\\S")) | select((.value | try fromjson catch null)
  | type == "object"
    and (keys - ["history","options","unit"] == ["answer","answeredAt","askedAt","id","proposedDefault","question","source"])
    and ((.history // []) | type == "array")
    and ((has("options") | not) or (.options | type == "array" and all(.[]; type == "string")))
    and ((has("unit") | not) or (.unit | type == "string" and test("^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$")))
    and (.id | type == "string" and length > 0)
    and all(.askedAt, .proposedDefault, .question, .source; type == "string")
    and (.answer | type) == (.answeredAt | type) and (.answer | type | . == "string" or . == "null")
  | not) | .key + 1 | tostring) | join(", ")'

# The latest snapshot per id, in asking order. One malformed line fails the
# whole read, naming the line: a corrupt ledger is never an empty one.
fold() {
  local bad
  bad=$(jq -Rrs "$BAD_LINES" "$L" 2>/dev/null) || die "malformed ledger $L"
  [ -z "$bad" ] || die "malformed ledger $L (line $bad)"
  jq -cs '[to_entries[] | .value + {_i: .key}] | group_by(.id) | map(last + {_i: first._i}) | sort_by(._i) | map(del(._i))' "$L" 2>/dev/null \
    || die "malformed ledger $L"
}

append() { printf '%s\n' "$1" >> "$L" || die "could not append to $L"; printf '%s\n' "$1"; }
now() { date -u +%Y-%m-%dT%H:%M:%SZ; }

# Same question: equal once case, punctuation and spacing are dropped, or a
# reworded one whose content words (stop words out, plural/-ing/-ed endings
# off) are at least half, and at least three, already in the earlier question,
# naming no other environment and no other number or ordinal ("round 13",
# "fourteenth round": each round is its own decision). "thirteenth",
# "13th" and "13" are one number; cardinal words ("one more round") are not
# numbers. Measured on the 2026-10-03/04 repeats: 0.57,
# 0.57 and 0.78 matched; the changed reader order scored 0.36 and stays a new
# decision (decision-ledger.test.sh). A ceiling: a paraphrase sharing under
# half its words gets through; a new decision reusing most of an open one's
# words is refused and goes through --reask.
SAME_Q='
def stop: ["a","an","the","to","of","in","on","at","for","by","with","and","or","but","so","if","it","its",
  "is","are","be","been","was","were","do","does","did","should","shall","would","could","can","will","may",
  "must","we","i","you","they","them","their","this","that","these","those","there","here","what","which",
  "who","how","when","where","why","now","then","than","as","from","into","up","out","any","all","some","new",
  "happen","going","forward","instead","get","keep","yes","no","not","just","also","only","our","my","your",
  "about","s","t","plus"];
def stem: if length > 5 and endswith("ing") then .[:-3] elif length > 4 and endswith("ed") then .[:-2]
  elif length > 3 and endswith("s") and (endswith("ss") | not) then .[:-1] else . end;
def flat: ascii_downcase | [scan("[a-z0-9]+")] | join(" ");
def toks: ascii_downcase | gsub("can[’'"'"']?t\\b"; "cannot") | gsub("[’'"'"']"; "") | [scan("[a-z0-9]+")];
def words: toks | map(select(. as $w | stop | index($w) | not) | stem) | unique;
def envs: ascii_downcase | [scan("[a-z0-9]+")] | map(select(IN("dev", "prod", "production", "staging")) | if . == "production" then "prod" else . end) | unique;
def nums: ["first", "second", "third", "fourth", "fifth", "sixth", "seventh", "eighth", "ninth", "tenth",
  "eleventh", "twelfth", "thirteenth", "fourteenth", "fifteenth", "sixteenth", "seventeenth", "eighteenth",
  "nineteenth", "twentieth"] as $ord
  | toks | map(if test("^[0-9]+(st|nd|rd|th)?$") then sub("(st|nd|rd|th)$"; "") | tonumber
    else . as $w | $ord | index($w) // empty | . + 1 end) | unique;
def recent: .answeredAt == null or .answeredAt >= (now - 86400 | strftime("%Y-%m-%dT%H:%M:%SZ"));
def same_q($new): . as $old | ($new | flat) == ($old | flat) or (
  ($new | words) as $n | ($old | words) as $o | ([$n[] | select(. as $w | $o | index($w))] | length) as $k
  | $k >= 3 and $k * 2 >= ($n | length)
    and (($new | envs) as $a | ($old | envs) as $b | $a == $b or $a == [] or $b == [])
    and (($new | nums) as $a | ($old | nums) as $b | $a == $b or $a == [] or $b == []));'

# dup <cur> <id> <question> -- the newest earlier decision this question
# repeats, or nothing: still open, or answered in the last 24 hours. Only when
# none does is the same id asking something else a write failure (exit 1).
# A push ask id (push-<repo>-<sha12>; a picker header "Push ..." is not one) repeats only its own id (each push names its commits, so a new tip is a new decision); a near-text
# repeat is let through only when both rows hold a unit and the units differ (a picker ask holds none, so it is still
# refused); an exact repeat counts across units.
dup() {
  local d
  if [[ $2 =~ ^push-.+-[0-9a-f]{12}$ ]]; then
    d=$(jq -c --arg id "$2" "$SAME_Q"'[.[] | select(recent and .id == $id)] | last // empty' <<<"$1")
  else
    d=$(jq -c --arg q "$3" --arg u "${unit:-}" "$SAME_Q"'[.[] | select(recent and ((.question | flat) == ($q | flat)
      or (((.unit // "") == "" or $u == "" or (.unit // "") == $u) and (.question | same_q($q)))))] | last // empty' <<<"$1")
  fi
  [ -n "$d" ] && { printf '%s\n' "$d"; return; }
  ! jq -e --arg id "$2" 'any(.[]; .id == $id)' <<<"$1" >/dev/null || die "decision $2 already exists"
}

# refuse <snapshot> [note] -- exit 3: the question is already the owner's, with their answer.
refuse() {
  jq -r --arg note "${2:-}" '"decision: this repeats \(.id), asked \(.askedAt): "
    + (if .answeredAt == null then "still open, no answer yet" else "answered \"\(.answer)\" at \(.answeredAt)" end)
    + ". Use that decision; re-ask only with new facts (decision.sh add ... --reask \"<what is new>\")."
    + (if $note == "" then "" else " " + $note end)' <<<"$1" >&2
  printf '%s\n' "$1"
  exit 3
}

# gate <cur> <id> <question> -- refuse a repeat (exit 3), or the id asking something else (exit 1).
gate() {
  local d
  d=$(dup "$1" "$2" "$3") || exit 1
  [ -n "$d" ] || return 0
  refuse "$d"
}

bad() { echo "decision: $*" >&2; exit 2; }

case "${1:-}" in
  add)
    reask="" opts="" unit=""
    [ $# -ge 5 ] || usage
    id=$2 q=$3 dflt=$4 src=$5; shift 5
    while [ $# -gt 0 ]; do
      case $1 in
        --options) [ $# -ge 2 ] && [ -n "$2" ] || usage; opts=$2; shift 2 ;;
        --reask) [ $# -ge 2 ] || usage; reask=$2; shift 2
          [ -n "${reask//[[:space:]]/}" ] || die "--reask needs the new facts" ;;
        # The ledger reader's pattern (BAD_LINES): a unit that fails it would make every read fail.
        --unit) [ $# -ge 2 ] && [[ $2 =~ ^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$ ]] || usage; unit=$2; shift 2 ;;
        *) usage ;;
      esac
    done
    [ -z "$opts" ] || {
      jq -e 'type == "array" and length >= 2 and length <= 4
          and all(.[]; type == "string" and length >= 1 and length <= 500 and test("^(?:[^\\p{C}\\p{Z}]| )+$"))' \
        <<<"$opts" >/dev/null 2>&1 || die "--options takes a JSON array of 2 to 4 answers, each 1 to 500 printable characters"
      opts=$(jq -c . <<<"$opts")
    }
    [ -n "$id" ] || die "an id is required"
    # Decision 44: an id that names a live unit (a worktree on <owner>/<unit>) records it, the longest match
    # winning: [plan-|review-stop-]<unit> then end or -<letter>.
    if [ -z "$unit" ]; then
      stem=${id#plan-}; [ "$stem" != "$id" ] || stem=${id#review-stop-}
      while read -r b; do
        u=${b#refs/heads/*/}
        [ "$u" != "$b" ] && [[ $u =~ ^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$ ]] || continue
        case $stem in "$u"|"$u"-[a-z]*) [ "${#u}" -le "${#unit}" ] || unit=$u ;; esac
      done < <(git -C "$PP_MAIN" worktree list --porcelain 2>/dev/null | sed -n 's/^branch //p')
      [ -z "$unit" ] || echo "decision.sh: recorded --unit $unit from the id" >&2
    fi
    # The first ask on a fresh checkout starts the ledger; answer and list still refuse a missing one.
    [ -e "$L" ] || { mkdir -p "${L%/*}" && : >> "$L"; } || die "could not create $L"
    lock -x
    cur=$(fold) || exit 1
    [ -n "$reask" ] || gate "$cur" "$id" "$q"
    append "$(jq -cn --arg id "$id" --arg q "$q" --arg d "$dflt" --arg s "$src${reask:+; re-ask: $reask}" --arg at "$(now)" --argjson o "${opts:-null}" --arg u "$unit" \
      '{id: $id, askedAt: $at, question: $q, proposedDefault: $d, source: $s, answeredAt: null, answer: null}
       + (if $o == null then {} else {options: $o} end) + (if $u == "" then {} else {unit: $u} end)')" ;;
  answer)
    # --asked-at: answer only the snapshot the caller read. A hook that read
    # its open rows before a reopen must not close the reopened ask.
    # ponytail: whole-second stamps; a reopen in the ask's own second passes.
    asked="" correct=0
    [ $# -ge 3 ] || usage
    i=4
    while [ $i -le $# ]; do
      case ${!i} in
        --asked-at) j=$((i + 1)); [ $j -le $# ] && [ $correct = 0 ] || usage; asked=${!j}; i=$((i + 2)) ;;
        --correct) [ -z "$asked" ] || usage; correct=1; i=$((i + 1)) ;;
        *) usage ;;
      esac
    done
    [ -n "$3" ] || die "an answer is required"
    lock -x
    cur=$(fold) || exit 1
    prev=$(jq -c --arg id "$2" '.[] | select(.id == $id)' <<<"$cur")
    [ -n "$prev" ] || die "unknown decision $2"
    # --correct: a mis-recorded answer is replaced; the old one stays in history with who and when.
    if [ $correct = 1 ]; then
      jq -e '.answeredAt != null' <<<"$prev" >/dev/null || die "decision $2 is not answered yet; answer it without --correct"
      append "$(jq -c --arg a "$3" --arg at "$(now)" --arg who "${USER:-unknown}" \
        '.history = ((.history // []) + [{who: $who, at: $at, answer: .answer}]) | .answer = $a' <<<"$prev")"
      exit $?
    fi
    jq -e '.answeredAt == null' <<<"$prev" >/dev/null || die "decision $2 is already answered (to fix a wrong answer: answer $2 <answer> --correct)"
    [ -z "$asked" ] || jq -e --arg a "$asked" '.askedAt == $a' <<<"$prev" >/dev/null \
      || die "decision $2 was reopened after this answer read it"
    # A growth grant is read by its ruling id; an answer without one grants nothing, so say so now, never refuse.
    ! jq -e --arg a "$3" '(.question | test("\\bgrow\\b.*[+][0-9]"; "i")) and ($a | test("r-[0-9]{8}-[0-9]{6}-[0-9a-z]+-[0-9a-z]+") | not)' <<<"$prev" >/dev/null \
      || echo "decision: warning: $2 asks to grow a test count and the answer holds no ruling id (r-YYYYMMDD-HHMMSS-...), so new-test-count.sh will read it as no grant" >&2
    append "$(jq -c --arg a "$3" --arg at "$(now)" '.answeredAt = $at | .answer = $a' <<<"$prev")" ;;
  reopen)
    # reopen <id>: the owner's answer was not theirs (an Orca banner closed a
    # chat ask). The fresh askedAt keeps a prompt that arrived before the
    # reopen from closing it again; the wrong answer stays in the history.
    [ $# -eq 2 ] || usage
    lock -x
    cur=$(fold) || exit 1
    prev=$(jq -c --arg id "$2" '.[] | select(.id == $id)' <<<"$cur")
    [ -n "$prev" ] || die "unknown decision $2"
    ! jq -e '.answeredAt == null' <<<"$prev" >/dev/null || die "decision $2 is still open"
    append "$(jq -c --arg at "$(now)" '.askedAt = $at | .answeredAt = null | .answer = null' <<<"$prev")" ;;
  digest)
    # digest [<YYYY-MM-DD>]: the owner's day from the ledger and the ruling log, no model. The day is an ET day (default
    # today): open asks oldest first, then the day's answers and corrections, then picker answers no ledger row holds.
    # A picker answer names no project, so the Board writes one page a project with --no-picks (no picker section),
    # then the picker section alone with --picks <ledger>..., holding the answers none of those ledgers has a row for.
    shift; day=$(TZ=America/New_York date +%Y-%m-%d) mode=all
    case ${1:-} in --*|'') ;; *) day=$1; shift ;; esac
    case ${1:-} in
      '') ;;
      --no-picks) [ $# -eq 1 ] || bad "usage: decision.sh $DIGEST_USAGE"; mode=ledger ;;
      --picks) [ $# -ge 2 ] || bad "usage: decision.sh $DIGEST_USAGE"; shift; mode=picks ;;
      *) bad "usage: decision.sh $DIGEST_USAGE" ;;
    esac
    jq -ne --arg d "$day" '$d | test("^[0-9]{4}-[0-9]{2}-[0-9]{2}$") and ((try (strptime("%Y-%m-%d") | mktime | strftime("%Y-%m-%d")) catch "") == $d)' \
      >/dev/null 2>&1 || bad "digest: '$day' is not a date (YYYY-MM-DD)"
    if [ "$mode" = picks ]; then rows=$(for L in "$@"; do lock -s; fold || exit 1; exec 9<&-; done | jq -cs 'add') || exit 1
    else lock -s; rows=$(fold) || exit 1; exec 9<&-; fi
    # The ledger and the picker rows reach jq by stdin and a file, never as arguments: at their real sizes (over 1 MB)
    # an argument list is past the host's limit and jq never starts. An empty file is "not read".
    pf=$(mktemp "${TMPDIR:-/tmp}/decision-digest.XXXXXX") || die "could not make a temp file"
    [ ! -r "$RULINGS" ] || jq -nRc '[inputs | fromjson? | objects | select(.source == "ask" and .void != true)]' "$RULINGS" > "$pf" 2>/dev/null || : > "$pf"
    printf '%s' "$rows" | TZ=America/New_York jq -nr --slurpfile pk "$pf" --arg day "$day" --arg rl "$RULINGS" --arg mode "$mode" "$SAME_Q"'
      def one: tostring | gsub("[\r\n]+"; " ");
      def q300: one | .[:300];
      def et: try (fromdateiso8601 | strflocaltime("%Y-%m-%d %H:%M")) catch "?";
      def sec($h; $l): $h + " (\($l | length))", (if $l == [] then "- none" else $l[] end);
      input as $rows | ($pk[0] // null) as $picks |
      (if $mode == "picks" then empty else
      "# The owner'"'"'s decisions, \($day) (ET)",
      sec("## Open"; [$rows[] | select(.answeredAt == null)] | sort_by(.askedAt)
        | map("- \(.id), asked \(.askedAt | et) ET: \(.question | q300) (default: \(.proposedDefault | one))")),
      sec("## Answered \($day)"; [$rows[] | select(.answeredAt != null)
          | ([.answeredAt, ((.history // [])[] | .at)] | map(select(type == "string" and ((et)[:10]) == $day)) | last) as $t
          | select($t != null) | . + {_t: $t}] | sort_by(._t)
        | map("- \(._t | et | .[11:]) \(.id): \(.question | q300) -> \(.answer | one)"
          + (if (.history // []) == [] then "" else " (corrected; earlier: \(.history | map(.answer | one) | join("; ")))" end))) end),
      (if $mode == "ledger" then empty
       elif $picks == null then "## Other picker answers \($day) (not read)", "- NOT READ: \($rl)"
       else [$rows[] | .question | flat] as $rq
         | sec("## Other picker answers \($day)"; [$picks[] | select(((.utc // "") | et)[:10] == $day)
           | ((.question // "") | flat) as $f | select(any($rq[]; . == $f) | not)] | sort_by(.utc)
         | map("- \(.utc | et | .[11:]) \(.id): \(.question | q300) -> \(.answer | one)")) end)'
    rc=$?; rm -f "$pf"; exit $rc ;;
  list)
    [ $# -eq 1 ] || usage
    lock -s
    fold ;;
  growth)
    # growth <unit> <ruling-id> <subject> +<n>...: the write is main's alone (Decision 34).
    [ $# -ge 5 ] && [ $(($# % 2)) = 1 ] || usage
    unit=$2 rid=$3; shift 3
    [[ $unit =~ ^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$ ]] && [[ $rid =~ ^r-[0-9]{8}-[0-9]{6}-[0-9a-z]+-[0-9a-z]+$ ]] || usage
    list=""
    while [ $# -gt 0 ]; do
      [[ $1 =~ ^[A-Za-z0-9._-]+$ ]] && [[ $2 =~ ^\+[1-9][0-9]*$ ]] || usage
      list="${list:+$list, }$1 $2"; shift 2
    done
    [ "$(git rev-parse --show-toplevel 2>/dev/null)" = "$(cd -P "$PP_MAIN" 2>/dev/null && pwd -P)" ] || die "growth is written from main's checkout ($PP_MAIN) only, not from here; nothing written"
    lock -x
    cur=$(fold) || exit 1
    id="growth-$unit-$(date -u +%Y%m%dT%H%M%SZ)"
    ! jq -e --arg id "$id" 'any(.[]; .id == $id)' <<<"$cur" >/dev/null || die "decision $id already exists"
    append "$(jq -cn --arg id "$id" --arg q "Unit $unit: may it grow $list?" --arg a "Yes ($rid)" --arg at "$(now)" --arg u "$unit" \
      '{id: $id, askedAt: $at, question: $q, proposedDefault: "yes", source: "decision.sh growth", answeredAt: $at, answer: $a, unit: $u}')" ;;
  rulings)
    [ $# -ge 2 ] || usage
    shift
    for t in "$@"; do [ -n "$t" ] || usage; done
    [ -r "$RULINGS" ] || die "cannot read the ruling log $RULINGS"
    # The terms go in as JSON, not --args: jq would take a term starting with - as an option.
    terms=$(printf '%s\n' "$@" | jq -Rsc 'ascii_downcase | split("\n")[:-1]') || die "could not read the terms"
    jq -nRr --argjson terms "$terms" '
      [inputs | try fromjson catch empty | objects
       | select(.source == "ask" and .void != true)
       | (("\(.question)\n\(.answer)") | ascii_downcase) as $text
       | select(any($terms[]; . as $t | $text | contains($t)))]
      | sort_by(.utc) | reverse | .[]
      | "\(.id) \(.et): \(.question) -> \(.answer)" | gsub("[\r\n]"; " ")' "$RULINGS" || die "cannot read the ruling log $RULINGS" ;;
  *) usage ;;
esac
