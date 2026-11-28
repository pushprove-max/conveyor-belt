#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# The coverage map (issue 527): for each function of the shell files below, the test cases that ran it, so that
# .conveyor/test-changed.sh runs only those cases on a change to the function (covof). Run from the checkout's root,
# `bash .conveyor/coverage.sh`: by hand, or by each release after its whole suite passed, which commits the map (the
# pack's coverageMap; conveyor/lib/relcov.sh); never on a card's test step: it runs every case once, traced, and
# writes .conveyor/coverage.jsonl whole, to commit.
# The traced files: the engine's shell files (each .sh file of .conveyor/engine-areas.json), the Board's collector
# (.claude/scripts/dashboard.sh) and the hooks' (.claude/hooks/, its lib/ too), each one test-changed.sh --funcs can
# read (FUNCS).
# The units, run half the machine's cores at once (portable.sh p_ncpu, at least 1; COVERAGE_JOBS sets the number): each case of the engine's runner (conveyor/conveyor.test.sh, CONVEYOR_SHELL_TEST_CASE=<case>);
# each part of a test file under .claude/scripts/__tests__ or .claude/hooks/__tests__ that CONVEYOR_SHELL_TEST_CASE
# runs by parts (test-changed.sh --parts: `) & started <part>` lines, as dashboard.test.sh; a `CASES=" ... "` line, as
# the hooks' case_on files); each check of one that selects its checks by their text (bash-guardrails.test.sh: checks,
# below); each other test file there (shell, node, python) whole.
# The trace: each bash a unit starts reads BASH_ENV, which turns xtrace on into the unit's own log, on a descriptor of
# its own (BASH_XTRACEFD), each line headed by the file and the function it runs (PS4). A bash started with an emptied
# environment (env -i) loses BASH_ENV, so each unit's PATH starts with a folder of its own whose `bash` sets the trace
# again and runs this bash; on macOS this bash's p_tools (below) has put Homebrew's folders on PATH already, so the
# p_tools or p_path a test calls (conveyor/tests/lib.sh) leaves that folder ahead of Homebrew's bash (issue 1723: a
# case that ran a function only under env -i was missing from the map, and a change to that function did not run it).
# A bash started with an emptied environment other than as `bash` on the
# unit's PATH (by its full path, or with no PATH), or given a BASH_ENV of the test's own, is not traced, nor are the
# functions it runs.
# A function a log names belongs to the traced file whose path ends most like the one bash read it from (a case runs a
# copy of the engine from a scratch folder), or to each that defines it when bash names no file (an exported
# function) or names a file that holds no definition of it (a case that loads the function's body with eval: bash
# names the case file), and only to a file that defines it.
# The map is one fact a line, sorted (issue 1593: one row a function, each test file and unit named once by its
# number, about a twentieth of the size of a row for each function and unit). Its numbers are this map's own, so two
# maps do not merge by union; a release writes it whole.
#   {"traced": <UTC time>, "sha": <HEAD at the trace>}   no "sha" when HEAD could not be read
#   {"testfile": <n>, "path": <test file>}   each test file that ran a traced function, numbered from 1
#   {"unit": <n>, "testfile": <n>, "case": <case or part>}   each unit that ran one, numbered from 1; no "case" for a
#                                                            test file run whole
#   {"file": <file>, "fn": <function>, "sum": <sum>, "units": [<n>, ...]}   each function of each traced file, as it
#                                                                           was traced (sumsof), and the units that ran it
#   {"file": <file>, "fn": <function>, "line": <n>, "units": [<n>, ...]}   issue 1830: of each function more than
#        LINEUNITS (50) units ran, each of its lines (as the file was at "sha") and the units that ran it, so a change
#        to one line of a function most cases run (testrun.sh tests()) runs only the cases that ran that line (covof).
#        The map stays at most COVMAX bytes (20 MB): over that, the line rows of the functions with the most lines go
#        first, each named in the output, and those functions select by their units alone.
# The trace's line of a command is the line it starts on (bash's LINENO): a line no command starts on (`else`, `fi`, a
# continued line) has no row, and covof reads it as the nearest lines before and after it that have one.
# A unit that fails is named, with the end of its output, and the map is still written (what it ran, it ran); the
# exit is then 1. A trace takes several times the time of the run it traces, and its logs, each removed as its unit
# ends, are under TMPDIR.
# `coverage.sh --write <traced> <sums> <runs> [<lines> <sha>]` prints the map made from a run's lists (covwrite,
# below), and traces nothing.
set -u
COV=.conveyor/coverage.jsonl
LINEUNITS=50 COVMAX=${COVERAGE_MAX_BYTES:-20971520}
# covwrite <traced> <sums> <runs> [<lines> <sha>]: the map, from the traced files' functions
# (<file><TAB><function><TAB><sum>), the functions each unit ran (<file><TAB><function><TAB><test file><TAB><case, or
# nothing>) and the lines each unit ran (<file><TAB><function><TAB><line><TAB><test file><TAB><case, or nothing>). A
# line of <runs> or <lines> that is not such a fact is dropped: of another shape (a line of a unit's output), of a
# function no traced file defines, or with no test file or an absolute one. It fails when jq or sort does, so a failed
# write is never an empty map. The facts, sorted by test file and case, are numbered in that order: a T line for each
# test file, a U line for each unit, then an F line for each function with its units' numbers, and an L line for each
# line of a function more than LINEUNITS units ran, each line made a row by jq. COVMAX (COVERAGE_MAX_BYTES, for the
# tests) caps the map's bytes: over it, the L rows of the functions with the most of them are dropped until it fits,
# each function named on stderr.
covwrite() (
  set -o pipefail
  w=$(mktemp -d) || exit 1
  trap 'rm -rf "$w"' EXIT
  awk -F'\t' 'NR == FNR { if (NF == 3) has[$1 FS $2] = 1; next }
      NF == 4 && $3 != "" && substr($3, 1, 1) != "/" && (($1 FS $2) in has)' "$2" "$3" \
    | LC_ALL=C sort -u | LC_ALL=C sort -t $'\t' -k3,3 -k4,4 \
    | awk -F'\t' 'NR == FNR { if (NF == 3) fns[++n] = $0; next }
        $3 != t { t = $3; tn++; print "T\t" tn "\t" t }
        ($3 FS $4) != k { k = $3 FS $4; un++; print "U\t" un "\t" tn "\t" $4 }
        { x = $1 FS $2; if (x in u) u[x] = u[x] "," un; else u[x] = un }
        END { for (i = 1; i <= n; i++) { split(fns[i], a, FS); x = a[1] FS a[2]; print "F\t" fns[i] "\t" ((x in u) ? u[x] : "") } }' "$2" - \
    > "$w/facts" || exit 1
  # The L lines: each line of a function of more than LINEUNITS units, with the units (by test file and case) that ran it.
  : > "$w/lines"
  [ -z "${4:-}" ] || awk -F'\t' -v max="$LINEUNITS" '
      FILENAME == ARGV[1] { if ($1 == "T") tp[$2] = $3; else if ($1 == "U") un[tp[$3] FS $4] = $2
        else if ($1 == "F" && split($5, x, ",") > max) big[$2 FS $3] = 1; next }
      NF == 5 && ($1 FS $2) in big && $3 ~ /^[0-9]+$/ && (($4 FS $5) in un) { k = $1 FS $2 FS $3; v = un[$4 FS $5]
        if (!((k FS v) in seen)) { seen[k FS v] = 1; if (k in l) l[k] = l[k] "," v; else l[k] = v } }
      END { for (k in l) print "L\t" k "\t" l[k] }' "$w/facts" "$4" > "$w/lines" || exit 1
  { jq -cn --arg t "$1" --arg s "${5:-}" '{traced: $t} + (if $s != "" then {sha: $s} else {} end)' \
    && jq -cR 'split("\t") | if .[0] == "T" then {testfile: (.[1] | tonumber), path: .[2]}
        elif .[0] == "U" then {unit: (.[1] | tonumber), testfile: (.[2] | tonumber)} + (if .[3] != "" then {case: .[3]} else {} end)
        else {file: .[1], fn: .[2], sum: .[3], units: (.[4] | if . == "" then [] else split(",") | map(tonumber) end)} end' "$w/facts"
  } > "$w/rows" || exit 1
  jq -cR 'split("\t") | {file: .[1], fn: .[2], line: (.[3] | tonumber), units: (.[4] | split(",") | map(tonumber) | sort)}' "$w/lines" > "$w/lrows" || exit 1
  # Over COVMAX: the line rows of the functions with the most of them go first, until the map fits.
  r=$(wc -c < "$w/rows") && l=$(wc -c < "$w/lrows") || exit 1
  if [ $((r + l)) -gt "$COVMAX" ]; then
    # <rows of the function><TAB><its bytes><TAB><file><TAB><function>, the most rows first.
    jq -r '[.file, .fn, (tostring | length + 1)] | @tsv' "$w/lrows" \
      | awk -F'\t' '{ k = $1 FS $2; c[k]++; b[k] += $3 } END { for (k in c) print c[k] "\t" b[k] "\t" k }' \
      | LC_ALL=C sort -t $'\t' -k1,1nr -k3,4 > "$w/byfn" || exit 1
    : > "$w/drop"
    while IFS=$'\t' read -r _ b f n; do
      [ $((r + l)) -gt "$COVMAX" ] || break
      l=$((l - b)); printf '%s\t%s\n' "$f" "$n" >> "$w/drop"
      echo "coverage.sh: the map is over $COVMAX bytes: the line rows of $f $n() are dropped; a change to it runs the cases that ran it" >&2
    done < "$w/byfn"
    jq -c --rawfile d "$w/drop" '($d | split("\n")) as $x | select(([.file, .fn] | join("\t")) as $k | any($x[]; . == $k) | not)' \
      "$w/lrows" > "$w/kept" && mv "$w/kept" "$w/lrows" || exit 1
  fi
  cat "$w/rows" "$w/lrows" | LC_ALL=C sort -u
)
if [ "${1:-}" = --write ]; then covwrite "$2" "$3" "$4" "${5:-}" "${6:-}"; exit; fi
[ -f .conveyor/test-changed.sh ] || { echo "coverage.sh: run it from the checkout's root" >&2; exit 2; }
# timeout, on macOS too.
. conveyor/lib/portable.sh && p_tools && . conveyor/lib/loadfactor.sh || exit 1
# The units at once: half the cores, as the slots read them (portable.sh p_ncpu), at least 1. A fixed 4 left a
# 32-core machine three quarters idle and took two hours on a 16-thread one.
JOBS=${COVERAGE_JOBS:-$(( $(p_ncpu || echo 2) / 2 ))}
[[ $JOBS =~ ^[1-9][0-9]*$ ]] || JOBS=1
TR=$(mktemp -d "${TMPDIR:-/tmp}/coverage.XXXXXX") || exit 1
trap 'rm -rf "$TR"' EXIT
traced=$(date -u +%Y-%m-%dT%H:%M:%SZ)
cat > "$TR/env.sh" <<'EOF'
if [ -n "${COVERAGE_LOG:-}" ]; then
  for COVERAGE_FD in /dev/fd/*; do COVERAGE_FD=${COVERAGE_FD##*/}; [ "/dev/fd/$COVERAGE_FD" -ef "$COVERAGE_LOG" ] && break; COVERAGE_FD=; done
  [ -n "$COVERAGE_FD" ] || exec {COVERAGE_FD}>>"$COVERAGE_LOG" || COVERAGE_FD=
  [ -z "$COVERAGE_FD" ] || { BASH_XTRACEFD=$COVERAGE_FD; PS4=$'\001${BASH_SOURCE[0]-}\t${FUNCNAME[0]-}\t${LINENO}\002'; set -x; }
fi 2>/dev/null
EOF

# The traced files' functions and sums: <file><TAB><function><TAB><sum>.
areas=$(bash .conveyor/test-changed.sh --map) || { echo "coverage.sh: .conveyor/engine-areas.json cannot be read" >&2; exit 1; }
: > "$TR/sums"
while IFS= read -r f; do
  [ -f "$f" ] || continue
  if s=$(bash .conveyor/test-changed.sh --funcs "$f"); then
    [ -z "$s" ] || awk -v f="$f" '{ print f "\t" $0 }' <<<"$s" >> "$TR/sums"
  else echo "coverage.sh: the functions of $f cannot be read; a change to it runs by its area"; fi
done < <({ jq -r '.areas[].files[] | select(endswith(".sh"))' <<<"$areas"
  git ls-files -co --exclude-standard .claude/scripts/dashboard.sh .claude/hooks \
    | grep -E '^[.]claude/(hooks/(lib/)?[^/]+|scripts/dashboard)[.]sh$'; } | LC_ALL=C sort -u)

# checks <test file>: the units of a file that selects its checks by their text (exit 3 of test-changed.sh --parts):
# one a check its whole run, untraced, prints (`ok   <label>`, `FAIL <label> (expected ...`), whose text is the end of
# the label after its last comma, or else the longest run of its words the file holds (the leftmost of equal ones), as
# an expansion at its start or end (`($SEAT)`) leaves words the file does not hold: the text selects that check, maybe
# with others. The text is searched for only in the lines the case filter can select (.claude/hooks/__tests__/lib/
# case-filter.sh): those outside a function whose first word is check or a function that calls check. A text in a
# helper's body or a loop's word list selected no check, and its unit failed. Each <file><TAB><label><TAB><text>
# into $TR/labels, for the proof below. It fails, and the file is traced whole, when that run fails or a label
# leaves no text.
checks() {
  local t=$1 l s src x i k
  local -a w
  env -u CONVEYOR_SHELL_TEST_CASE timeout 900 bash "$t" > "$TR/list" 2>&1 < /dev/null || return 1
  src=$(awk 'function def() { return match($0, /^[A-Za-z_][A-Za-z0-9_]*\(\) *\{/) }
    function one() { return $0 ~ /\}[[:space:]]*(#.*)?$/ }
    function calls() { return $0 ~ /(^|[^A-Za-z0-9_-])check([^A-Za-z0-9_-]|$)/ }
    FNR == NR { if (def()) { f = substr($0, 1, index($0, "(") - 1); in_f = !one(); if (f != "check" && calls()) k[f] = 1; next }
      if (in_f) { if (/^}/) in_f = 0; else if (f != "check" && calls()) k[f] = 1 }; next }
    def() { in_f = !one(); next } in_f { if (/^}/) in_f = 0; next } $1 == "check" || $1 in k' "$t" "$t")
  : > "$TR/these"
  while IFS= read -r l; do
    read -ra w <<<"${l##*,}"; s=
    for ((k = ${#w[@]}; k > 0 && ${#s} == 0; k--)); do
      for ((i = 0; i + k <= ${#w[@]}; i++)); do x="${w[*]:i:k}"; [[ $src == *"$x"* ]] && { s=$x; break; }; done
    done
    [ -n "$s" ] || return 1
    printf '%s\t%s\t%s\n' "$t" "$l" "$s" >> "$TR/these"
  done < <(sed -n 's/^ok   //p; s/^FAIL \(.*\) (expected .*/\1/p' "$TR/list" | LC_ALL=C sort -u)
  [ -s "$TR/these" ] || return 1
  cat "$TR/these" >> "$TR/labels"; cut -f1,3 "$TR/these" | LC_ALL=C sort -u
}
# The units: <test file><TAB><case or part, or nothing for the whole file>.
: > "$TR/labels"
{ sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' conveyor/tests/*.test.sh 2>/dev/null | LC_ALL=C sort -u | sed 's|^|conveyor/conveyor.test.sh\t|'
  git ls-files -co --exclude-standard .claude/scripts/__tests__ .claude/hooks/__tests__ \
    | grep -E '^[.]claude/(scripts|hooks)/__tests__/[^/]+[.]test[.](sh|mjs|py)$' | LC_ALL=C sort | while IFS= read -r t; do
      p=$(bash .conveyor/test-changed.sh --parts "$t"); r=$?
      if [ $r = 0 ]; then while IFS= read -r x; do printf '%s\t%s\n' "$t" "$x"; done <<<"$p"
      elif [ $r = 3 ] && checks "$t"; then :
      else printf '%s\t\n' "$t"; fi
    done; } > "$TR/units"

# unit <n> <test file> <case>: runs it traced; the lines of its functions it ran, <bash's file><TAB><function><TAB><line>,
# in $TR/<n>.fn, its exit in $TR/<n>.rc.
unit() {
  local n=$1 t=$2 c=$3
  local -a cmd
  case $t in
    *.mjs) cmd=(node --max-old-space-size=4096 --test "$t") ;;
    *.py) cmd=(python3 "$t") ;;
    *) cmd=(bash "$t") ;;
  esac
  # The trace goes down a pipe ($TR/<n>.fifo), which one reader writes to the unit's log: a size limit a test sets
  # (ulimit -f: test-share.sh, test-full.sh) caps the files a shell writes, the log too, and the first trace line past
  # it killed that shell (SIGXFSZ), but it caps no pipe. This runner holds the pipe open while the unit runs (the unit
  # does not get that descriptor), so the reader ends once the unit and all it started have closed it; one left
  # running (an orphan) holds it, and the reader is stopped 10 s after the unit ends.
  local w r i lf
  mkfifo "$TR/$n.fifo" && { cat "$TR/$n.fifo" > "$TR/$n.log" & r=$!; } && exec {w}> "$TR/$n.fifo" || { echo 1 > "$TR/$n.rc"; return; }
  # The unit's own bash, first on its PATH: it sets the trace again in a bash started with env -i (above), and leaves
  # a BASH_ENV a test set (a case's own hook) as it is. It runs bash under the name it was called by (bash), so a
  # process list shows the command as the test started it (machinestray reads `bash <file> serve`).
  mkdir -p "$TR/$n.bin" && printf '#!%s\n[ -n "${BASH_ENV:-}" ] || export COVERAGE_LOG=%q BASH_ENV=%q\nexec -a bash %q "$@"\n' "$BASH" "$TR/$n.fifo" "$TR/env.sh" "$BASH" \
    > "$TR/$n.bin/bash" && chmod +x "$TR/$n.bin/bash" || { echo 1 > "$TR/$n.rc"; exec {w}>&-; return; }
  # The unit's time limits scale as a loop's test run's do (CONVEYOR_LOAD_FACTOR, lib/loadfactor.sh): the machine's
  # load factor as the unit starts, times the trace's own cost, 1.2 (a case traced alone ran 1.0 to 1.2 times as long
  # as untraced, 2026-11-27), at most 3. The units run side by side, and 16 at once timed cases out.
  lf=$(awk -v f="$(loadfactor)" 'BEGIN { f *= 1.2; if (f > 3) f = 3; printf "%.2f", f }')
  env PATH="$TR/$n.bin:$PATH" COVERAGE_LOG="$TR/$n.fifo" BASH_ENV="$TR/env.sh" CONVEYOR_LOAD_FACTOR="$lf" ${c:+"CONVEYOR_SHELL_TEST_CASE=$c"} timeout 900 "${cmd[@]}" \
    > "$TR/$n.out" 2>&1 < /dev/null {w}>&-
  echo $? > "$TR/$n.rc"; rm -rf "$TR/$n.bin"
  exec {w}>&-
  for ((i = 0; i < 100; i++)); do kill -0 "$r" 2>/dev/null || break; sleep 0.1; done
  kill "$r" 2>/dev/null; wait "$r" 2>/dev/null; rm -f "$TR/$n.fifo"
  awk 'substr($0, 1, 1) == "\001" && (i = index($0, "\002")) { x = substr($0, 1, i - 1); sub(/^\001+/, "", x)
    if (x ~ /\t[^\t]+\t[0-9]+$/) print x }' "$TR/$n.log" 2>/dev/null | LC_ALL=C sort -u > "$TR/$n.fn"
  rm -f "$TR/$n.log"
}
n=0
while IFS=$'\t' read -r t c; do
  n=$((n + 1))
  [ "$(jobs -rp | wc -l)" -lt "$JOBS" ] || wait -n
  unit "$n" "$t" "$c" &
done < "$TR/units"
wait

# A file traced by its checks' texts (checks) keeps them only when each check its whole run printed was printed by its
# own text's unit; else it is traced once more whole, and its units count as the whole file ($TR/whole), as a check
# no unit ran would be missing.
: > "$TR/whole"
while IFS=$'\t' read -r t l s; do
  n=$(T=$t S=$s awk -F'\t' '$1 == ENVIRON["T"] && $2 == ENVIRON["S"] { print NR; exit }' "$TR/units")
  [ -n "$n" ] && L=$l awk 'index($0, "ok   " ENVIRON["L"]) == 1 && length($0) == length(ENVIRON["L"]) + 5 ||
    index($0, "FAIL " ENVIRON["L"] " (expected ") == 1 { f = 1 } END { exit !f }' "$TR/$n.out" || echo "$t" >> "$TR/whole"
done < "$TR/labels"
n=$(wc -l < "$TR/units")
while IFS= read -r t; do
  echo "coverage.sh: a check of $t is not run by its text alone; the file is traced and mapped whole"
  n=$((n + 1)); printf '%s\t\n' "$t" >> "$TR/units"
  [ "$(jobs -rp | wc -l)" -lt "$JOBS" ] || wait -n
  unit "$n" "$t" "" &
done < <(LC_ALL=C sort -u "$TR/whole")
wait

# Each unit's functions, named by the traced file they belong to: <file><TAB><function><TAB><test><TAB><case>. Only
# the facts go to $TR/runs; a failed unit's lines go to this run's output (issue 1593: they were written to the map).
bad=0; n=0; : > "$TR/runs"; : > "$TR/lines"
while IFS=$'\t' read -r t c; do
  n=$((n + 1))
  if [ "$(cat "$TR/$n.rc" 2>/dev/null)" != 0 ]; then
    bad=1; echo "coverage.sh: $t${c:+ $c} failed (exit $(cat "$TR/$n.rc" 2>/dev/null)); what it ran is kept. Its last lines:"
    tail -n 15 "$TR/$n.out" | sed 's/^/  /'
  fi
  ! grep -qxF -- "$t" "$TR/whole" || c=
  # The case through ENVIRON: a check's text may hold a backslash, which awk -v would read as an escape. Each line it
  # ran goes to $TR/lines too (LF), for the line rows (issue 1830).
  LF=$TR/lines T=$t C=$c awk -F'\t' '
    BEGIN { t = ENVIRON["T"]; c = ENVIRON["C"] }
    function score(a, b, x, y, i, j, k) {
      i = split(a, x, "/"); j = split(b, y, "/"); k = 0
      while (i > 0 && j > 0 && x[i] == y[j]) { k++; i--; j-- }
      return k
    }
    # evald(f, n): bash read n from f, a file that holds no definition of n in its own text: a case loaded the traced
    # body with eval (`eval "$(sed -n "/^n() {/,/^}/p" ...)"`). Not a file that defines a stub of that name, nor one
    # that cannot be read.
    function evald(f, n, l, x) {
      if (!(f in rd)) {
        rd[f] = 0
        while ((getline l < f) > 0) {
          rd[f] = 1
          while (match(l, /(^|[;{(&|])[ \t]*[A-Za-z_][A-Za-z0-9_]*[ \t]*\(\)/)) {
            x = substr(l, RSTART, RLENGTH); sub(/^[;{(&| \t]*/, "", x); sub(/[ \t]*\(\)$/, "", x); def[f, x] = 1
            l = substr(l, RSTART + RLENGTH)
          }
        }
        close(f)
      }
      return rd[f] && !((f, n) in def)
    }
    NR == FNR { has[$1, $2] = 1; of[$2] = of[$2] " " $1; next }
    !($2 in of) { next }
    {
      m = split(substr(of[$2], 2), fs, " "); best = 0; got = ""
      for (i = 1; i <= m; i++) { s = score($1, fs[i]); if (s > best) { best = s; got = fs[i] } else if (s == best && s > 0) got = got " " fs[i] }
      if (best == 0 && ($1 == "" || $1 == "environment" || evald($1, $2))) got = substr(of[$2], 2)
      m = split(got, fs, " ")
      for (i = 1; i <= m; i++) if ((fs[i], $2) in has) {
        if (!((fs[i], $2) in done)) { done[fs[i], $2] = 1; print fs[i] "\t" $2 "\t" t "\t" c }
        print fs[i] "\t" $2 "\t" $3 "\t" t "\t" c >> ENVIRON["LF"]
      }
    }' "$TR/sums" "$TR/$n.fn" >> "$TR/runs"
done < "$TR/units"

# The map, sorted, one fact a line, written whole.
covwrite "$traced" "$TR/sums" "$TR/runs" "$TR/lines" "$(git rev-parse -q --verify HEAD 2>/dev/null)" > "$TR/map" && mv "$TR/map" "$COV" \
  || { echo "coverage.sh: $COV could not be written" >&2; exit 1; }
echo "coverage.sh: $COV: $(grep -c '"sum"' "$COV") functions, $(wc -l < "$TR/units") units traced"
exit $bad
