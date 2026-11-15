#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 120
# Engine cases: the state database (state.py), the only reader and writer of state.db: its answers, its appends.
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"
# The engine folder, as lib.sh sets it: named here too, so the release closure (tools/closure.sh) follows this file's paths.
SRC=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)

statedb() { python3 "$SRC/state.py" "$@"; }
# The rows of a table of the database itself, one line each, in their order: what it holds, not what it answers.
statedb_rows() { python3 -c 'import sqlite3, sys; [print(r[0]) for r in sqlite3.connect(sys.argv[1]).execute("SELECT line FROM \"%s\" ORDER BY n" % sys.argv[2])]' "$1/state.db" "$2"; }
# A history: c1 landed and pushed, c2 blocked for the owner's yes with a kept patch, c3 in its review rounds and
# tested, c4 blocked for a failed build, and c9 being written (its line not ended yet); c0's lines were retried; the
# samples hold a number as written (31.70), a sample with no slots and one with a time that does not read; the
# readings are of two accounts and one has no percent.
statedb_history() { # <state folder>
  mkdir -p "$1"
  jq -cn '
    def l($c; $i; $s; $t): {card: $c, issue: $i, step: $s, time: $t, tokens: {claude: 0, codex: 0}, result: "ok", sha: "", reason: ""};
    l("c1"; 1; "picked"; "2026-03-01T00:00:00Z"), l("c1"; 1; "landed"; "2026-03-01T00:10:00Z") + {sha: "a1"},
    l("c1"; 1; "push"; "2026-03-01T00:11:00Z") + {sec: 4, head: "a1", result: "fail", reason: "rejected"},
    l("c1"; 1; "pushed"; "2026-03-01T00:12:00Z") + {sec: 2.5, head: ""},
    l("c2"; 2; "picked"; "2026-03-01T01:00:00Z"),
    l("c2"; 2; "blocked"; "2026-03-01T01:10:00Z") + {result: "blocked", reason: "visible change: needs the yes", kept: "kept"},
    l("c3"; 3; "picked"; "2026-03-01T02:00:00Z"), l("c3"; 3; "review"; "2026-03-01T02:10:00Z") + {result: "NO-GO", patch: "p1"},
    l("c3"; 3; "fix"; "2026-03-01T02:20:00Z"), l("c3"; 3; "review"; "2026-03-01T02:30:00Z") + {result: "GO", patch: "p2"},
    l("c3"; 3; "test"; "2026-03-01T02:40:00Z"), l("c3"; 3; "start"; "2026-03-01T02:50:00Z") + {of: "land"},
    l("c4"; 4; "picked"; "2026-03-01T03:00:00Z"),
    l("c4"; 4; "blocked"; "2026-03-01T03:10:00Z") + {result: "blocked", reason: "build: failed", kept: "kept"}' > "$1/cards.jsonl"
  printf '{"card":"c9","issue":9,"step":"pic' >> "$1/cards.jsonl"
  jq -cn '{card: "c0", issue: 1, step: "push", time: "2026-02-01T00:00:00Z", sec: 9, head: "a0"}, {card: "c0", issue: 1, step: "blocked", time: "2026-02-01T00:01:00Z", reason: "visible change: x", kept: "k"}' > "$1/retried.jsonl"
  printf '%s\n' '{"time":"2026-03-01T00:00:00Z","slots":2,"load":31.70}' '{"time":"2026-03-01T00:01:00Z","load":1}' \
    '{"time":"yesterday","slots":1}' '{"time":"2026-03-01T00:02:00Z","slots":0,"cap":null}' > "$1/samples.jsonl"
  printf '%s\n' '{"time":"2026-03-01T00:00:00Z","pct":40}' '{"time":"2026-03-01T00:00:00Z","pct":50,"account":"b"}' \
    '{"time":"2026-03-01T00:01:00Z"}' '{"time":"2026-03-01T00:02:00Z","pct":41.50}' > "$1/limit.jsonl"
}
# What the engine read with jq before the database, of the same files, for each question the helper answers
# (lib/session.sh card and stopped, lib/review.sh reusable, lib/run.sh, lib/testrun.sh testedbefore, and
# lib/snapshot.sh: its copy, pushes, the cards waiting for the yes, samples and readings).
statedb_jq() { # <state folder> <question> [<arg>...]
  local s=$1/cards.jsonl o=$1/retried.jsonl
  case $2 in
    lines) head -n "$(wc -l < "$1/$3.jsonl")" "$1/$3.jsonl" ;;
    card) jq -c --arg c "$3" 'select(.card == $c)' "$s" 2>/dev/null ;;
    last) jq -c --arg c "$3" 'select(.card == $c)' "$s" 2>/dev/null | tail -n 1 ;;
    lastreview) grep -F "\"card\":\"$3\"" "$s" 2>/dev/null | jq -cR 'fromjson? | objects | select(.step == "review")' 2>/dev/null | tail -n 1 ;;
    ended) jq -Rne --arg c "$3" 'any(inputs | fromjson? | objects; .card == $c and (.step | IN("landed", "closed", "blocked")))' "$s" >/dev/null 2>&1 && echo true || echo false ;;
    tested) jq -Rne --arg c "$3" 'any(inputs | fromjson? | objects; .card == $c and .step == "test")' "$s" >/dev/null 2>&1 && echo true || echo false ;;
    pushes) jq -c 'select(.step | IN("push", "pushed")) | {step, time, sec} + (if (.head | type) == "string" and .head != "" then {head} else {} end)' "$(head -n "$(wc -l < "$s")" "$s" > "$1/whole"; echo "$1/whole")" "$o" 2>/dev/null ;;
    yes) jq -r --arg yes "$3" --arg st "$4" 'select(.step == "blocked" and (.reason | startswith($yes)) and (.kept // "") != "") | [.card, $st + "/" + .kept] | @tsv' "$s" 2>/dev/null ;;
    samples) tail -n 20160 "$1/samples.jsonl" 2>/dev/null | jq -c 'select((.time | type == "string") and (.slots | type == "number")) | select(try (.time | fromdate | true) catch false)' 2>/dev/null ;;
    issue) head -n "$(wc -l < "$1/$3.jsonl")" "$1/$3.jsonl" | jq -c --argjson n "$4" 'select(.issue == $n)' 2>/dev/null ;;
    tail) tail -n "$4" "$1/$3.jsonl" ;;
    limit) tail -n 4000 "$1/limit.jsonl" 2>/dev/null | jq -c --arg a "$3" 'select((.pct | type == "number") and (.time | type == "string") and (.account // "") == $a)' 2>/dev/null ;;
  esac
}
# Each question, asked of the helper in one call and of jq, gives the same lines; prints the first that differs.
statedb_same() { # <state folder>
  # Each question is its words joined by |, with a | after the last ("limit||" asks of the default login's readings).
  local i n qs=() all=("lines|cards|" "lines|retried|" "card|c3|" "card|c5|" "last|c3|" "lastreview|c3|" "lastreview|c1|" "ended|c1|"
    "ended|c2|" "ended|c3|" "tested|c3|" "tested|c1|" "pushes|" "yes|visible change|$1|" "samples|" "limit||" "limit|b|"
    "issue|cards|3|" "issue|retried|1|" "issue|cards|7|" "tail|limit|2|")
  for i in "${!all[@]}"; do IFS='|' read -r -a n <<<"${all[i]}"; qs+=(-o "$1/a$i" "${n[@]}" --); done
  statedb "$1" ask "${qs[@]:0:${#qs[@]}-1}" || { echo "the helper failed"; return; }
  for i in "${!all[@]}"; do IFS='|' read -r -a n <<<"${all[i]}"
    cmp -s "$1/a$i" <(statedb_jq "$1" "${n[@]}") || { echo "${all[i]}: the helper gave [$(tr '\n' ' ' < "$1/a$i")], jq [$(statedb_jq "$1" "${n[@]}" | tr '\n' ' ')]"; return; }
  done
}

# Bug: a question the helper answers differently from the jq read it replaced shows the Board, and gives each card
# step, another state than before: a card taken as ended, or not, a review reused that was not the last, a sample or
# a reading dropped, a number not as written. The first call imports the files; a rewrite of the card records
# (`retry` moves a card's lines to the retried file) and a line ended since are answered as jq reads them too.
t_statedbsame() {
  local s=$T/$CASE/st d
  statedb_history "$s"
  d=$(statedb_same "$s"); [ -z "$d" ] || fail "after the import: $d"
  [ -s "$s/state.db" ] || fail "the first call made no database"
  [ "$(statedb_rows "$s" cards | wc -l)" = 14 ] || fail "the import did not take the 14 whole lines of the records: $(statedb_rows "$s" cards | wc -l)"
  # The line of c9 ends, and c3's lines move out (a retry): the next answers are the files' again.
  printf 'ked","time":"2026-03-01T04:00:00Z"}\n' >> "$s/cards.jsonl"
  grep '"card":"c3"' "$s/cards.jsonl" >> "$s/retried.jsonl"; grep -v '"card":"c3"' "$s/cards.jsonl" > "$s/rest"; cat "$s/rest" > "$s/cards.jsonl"
  d=$(statedb_same "$s"); [ -z "$d" ] || fail "after the records were rewritten: $d"
  [ "$(statedb_rows "$s" cards | grep -c '"card":"c3"')" = 0 ] && [ "$(statedb_rows "$s" cards | grep -c '"card":"c9"')" = 1 ] \
    || fail "the database still holds the moved card, or not the line ended since: $(statedb_rows "$s" cards | jq -r .card | tr '\n' ' ')"
}

# Bug: a line appended through the helper missing from the file (the Board and every reader not moved yet read the
# files) or from the database. A database that cannot be read is made anew from the files, and the line is in both.
t_statedbappend() {
  local s=$T/$CASE/st l='{"card":"c5","issue":5,"step":"picked","time":"2026-03-02T00:00:00Z"}' m='{"time":"2026-03-02T00:00:00Z","slots":3}'
  statedb_history "$s"; printf 'ked","time":"2026-03-01T04:00:00Z"}\n' >> "$s/cards.jsonl"
  statedb "$s" ask ended c1 > /dev/null || fail "the import failed"
  printf '%s\n' "$l" | statedb "$s" append cards || fail "the append failed"
  printf '%s\n' "$m" | statedb "$s" append samples || fail "the append of a sample failed"
  [ "$(tail -n 1 "$s/cards.jsonl")" = "$l" ] && [ "$(tail -n 1 "$s/samples.jsonl")" = "$m" ] || fail "an appended line is not the last of its file"
  [ "$(statedb_rows "$s" cards | tail -n 1)" = "$l" ] && [ "$(statedb_rows "$s" samples | tail -n 1)" = "$m" ] || fail "an appended line is not the last row of its table"
  cmp -s <(statedb_rows "$s" cards) "$s/cards.jsonl" || fail "the table and the file differ: $(diff <(statedb_rows "$s" cards) "$s/cards.jsonl" | head -n 5)"
  # A broken database: the next append makes it anew from the file, and loses nothing.
  echo 'not a database' > "$s/state.db"; rm -f "$s/state.db-wal" "$s/state.db-shm"
  printf '%s\n' "${l/c5/c6}" | statedb "$s" append cards 2>/dev/null || fail "the append to a broken database failed"
  cmp -s <(statedb_rows "$s" cards) "$s/cards.jsonl" && [ "$(tail -n 1 "$s/cards.jsonl")" = "${l/c5/c6}" ] \
    || fail "the database made anew does not hold the file's lines: $(diff <(statedb_rows "$s" cards) "$s/cards.jsonl" | head -n 5)"
}

# Bug: an engine write that does not go through the helper (here `declined add`, as the card records' and the
# samples' appends) leaves the database behind its file until a reader brings it up to date.
t_statedbengine() {
  setup '[]'
  loop declined add c1-7 7 code 'follow-up of a follow-up' '[P2] a.txt:1 wrong word' || fail "a declined finding was not taken"
  [ "$(statedb_rows "$ST" declined | jq -r .card)" = c1-7 ] || fail "the declined line is not in the database: $(statedb_rows "$ST" declined 2>&1 | head -n 3)"
  [ "$(jq -r .card "$ST/declined.jsonl")" = c1-7 ] || fail "the declined line is not in its file"
  # Bug: the dismissal rewrote the list with mv, around the helper: the database kept the line not dismissed.
  loop declined dismiss "$(jq -r .id "$ST/declined.jsonl")" >/dev/null || fail "the dismissal failed"
  [ "$(statedb_rows "$ST" declined | jq -r '.dismissed.by')" = 'the host' ] && cmp -s <(statedb_rows "$ST" declined) "$ST/declined.jsonl" \
    || fail "the dismissal is not in the database and the file both: $(statedb_rows "$ST" declined | head -n 3)"
}

# Bug: `retry` wrote both history files around the helper (cat >> and cat >): the database still held the moved lines
# in the card records and not in the retried table. The helper moves them, and rewrites the records in place: the
# records' lock is held on the file itself, so a replaced file would let two writers in at once.
t_statedbretry() {
  setup '[]'
  local ino
  jq -cn 'def l($c; $i; $s; $t): {card: $c, issue: $i, step: $s, time: $t, tokens: {claude: 0, codex: 0}, result: "ok", sha: "", reason: ""};
    l("c7"; 7; "picked"; "2026-03-01T00:00:00Z"), l("c8"; 8; "picked"; "2026-03-01T00:01:00Z"),
    l("c7"; 7; "blocked"; "2026-03-01T00:02:00Z") + {result: "blocked", reason: "build: failed"}' >> "$ST/cards.jsonl"
  statedb "$ST" ask ended c7 > /dev/null || fail "the import failed"
  ino=$(ls -i "$ST/cards.jsonl" | awk '{print $1}')
  loop retry 7 >/dev/null || fail "retry of the blocked #7 failed"
  [ "$(statedb_rows "$ST" cards | jq -r .card | sort -u | tr '\n' ' ')" = 'c8 ' ] && cmp -s <(statedb_rows "$ST" cards) "$ST/cards.jsonl" \
    || fail "the card records' table is not the rewritten file: $(statedb_rows "$ST" cards | jq -r .card | tr '\n' ' ')"
  [ "$(statedb_rows "$ST" retried | jq -r .card | tr '\n' ' ')" = 'c7 c7 ' ] && cmp -s <(statedb_rows "$ST" retried) "$ST/retried.jsonl" \
    || fail "the moved lines are not in the retried table and file both: $(statedb_rows "$ST" retried | head -n 3)"
  [ "$(ls -i "$ST/cards.jsonl" | awk '{print $1}')" = "$ino" ] || fail "the card records were replaced, not rewritten in place"
}

# Bug: each call read and hashed the whole of each file it touched (an append twice), so every card step cost more as
# the history grew. Now a call reads the first and last bytes of the part the table holds and what follows it: a
# change in the middle of that part, which only a reread of the whole file would see, is not seen. A file shorter
# than that part is a rewrite, read anew; `keep` trims through the helper, the file in place.
t_statedbsync() {
  local s=$T/$CASE/st i
  mkdir -p "$s"
  for i in $(seq 1 400); do printf '{"card":"c%03d","issue":%d,"step":"picked","time":"2026-03-01T00:00:00Z"}\n' "$i" "$i"; done > "$s/cards.jsonl"
  [ "$(statedb "$s" ask last c200)" = '{"card":"c200","issue":200,"step":"picked","time":"2026-03-01T00:00:00Z"}' ] || fail "the import failed"
  # c200's line, past the first and last 4096 bytes of the 30 kB file, changed by hand to the same length.
  sed -i.bak 's/"card":"c200"/"card":"x200"/' "$s/cards.jsonl"
  printf '%s\n' '{"card":"c401","issue":401,"step":"picked","time":"2026-03-01T00:00:00Z"}' | statedb "$s" append cards || fail "the append failed"
  [ "$(statedb "$s" ask card c200 -- card x200 -- card c401 | jq -r .card | tr '\n' ' ')" = 'c200 c401 ' ] \
    || fail "the call read the whole file again, or missed the appended line: $(statedb "$s" ask card c200 -- card x200 -- card c401 | jq -r .card | tr '\n' ' ')"
  # A shorter file is read anew; keep trims file and table to the same last lines.
  head -n 10 "$s/cards.jsonl.bak" > "$s/cards.jsonl"
  [ "$(statedb "$s" ask lines cards | wc -l)" = 10 ] || fail "the shorter file was not read anew: $(statedb "$s" ask lines cards | wc -l) lines"
  statedb "$s" keep cards 8 3 || fail "keep failed"
  [ "$(jq -r .card "$s/cards.jsonl" | tr '\n' ' ')" = 'c008 c009 c010 ' ] && cmp -s <(statedb_rows "$s" cards) "$s/cards.jsonl" \
    || fail "keep did not leave the last 3 lines in the file and the table both: $(jq -r .card "$s/cards.jsonl" | tr '\n' ' ')"
  statedb "$s" keep cards 8 3 && [ "$(wc -l < "$s/cards.jsonl")" = 3 ] || fail "keep under its bound changed the file"
}

# Bug: a call held the database's lock while it wrote its answer, so with two calls read by one jq (upnext's
# `--slurpfile cards <(recs) --slurpfile retried <(olds)`), the one jq did not read yet held its lock on a full pipe
# and the other waited 60 s for it, then failed: jq read no cards and every issue with a card was picked again. Here
# the first call's answer (over the pipe's 64 kB) is left unread past its first line while a second call asks.
t_statedbpipe() {
  local s=$T/$CASE/st x
  mkdir -p "$s"
  awk 'BEGIN { for (i = 1; i <= 3000; i++) printf "{\"card\":\"c%04d\",\"issue\":%d,\"step\":\"picked\",\"time\":\"2026-03-01T00:00:00Z\",\"reason\":\"a reason long enough\"}\n", i, i }' > "$s/cards.jsonl"
  exec 3< <(statedb "$s" ask lines cards)
  read -r -u 3 x || fail "the first call gave no line"
  x=$(timeout 10 python3 "$SRC/state.py" "$s" ask ended c0001 2>&1) && [ "$x" = false ] \
    || fail "a call waited on another call's unread answer: $x"
  [ "$(cat <&3 | wc -l)" = 2999 ] || fail "the first call's answer was cut"
  exec 3<&-
}

# Bug: a reader that stops early (`| head -1`) made `ask` end in a BrokenPipeError traceback on stderr, about one
# every 6 s in the service log. 20,000 lines are well over the pipe's 64 kB, so the write meets the closed pipe.
t_statedbheadpipe() {
  local s=$T/$CASE/st x
  mkdir -p "$s"
  awk 'BEGIN { for (i = 1; i <= 20000; i++) printf "{\"card\":\"c%05d\",\"issue\":%d,\"step\":\"picked\",\"time\":\"2026-03-01T00:00:00Z\"}\n", i, i }' > "$s/cards.jsonl"
  x=$(statedb "$s" ask lines cards 2>"$s/err" | head -n 1) && [[ $x == *c00001* ]] || fail "the first line was not read: $x"
  [ ! -s "$s/err" ] || fail "a reader that stopped early left this on stderr: $(head -c 600 "$s/err")"
}
