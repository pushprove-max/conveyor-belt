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
# The units, run 4 at once: each case of the engine's runner (conveyor/conveyor.test.sh, CONVEYOR_SHELL_TEST_CASE=<case>);
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
#   {"traced": <UTC time>}
#   {"testfile": <n>, "path": <test file>}   each test file that ran a traced function, numbered from 1
#   {"unit": <n>, "testfile": <n>, "case": <case or part>}   each unit that ran one, numbered from 1; no "case" for a
#                                                            test file run whole
#   {"file": <file>, "fn": <function>, "sum": <sum>, "units": [<n>, ...]}   each function of each traced file, as it
#                                                                           was traced (sumsof), and the units that ran it
# A unit that fails is named, with the end of its output, and the map is still written (what it ran, it ran); the
# exit is then 1. A trace takes several times the time of the run it traces, and its logs, each removed as its unit
# ends, are under TMPDIR.
# `coverage.sh --write <traced> <sums> <runs>` prints the map made from a run's two lists (covwrite, below), and
# traces nothing.
set -u
COV=.conveyor/coverage.jsonl
# covwrite <traced> <sums> <runs>: the map, from the traced files' functions (<file><TAB><function><TAB><sum>) and
# the functions each unit ran (<file><TAB><function><TAB><test file><TAB><case, or nothing>). A line of <runs> that is
# not such a fact is dropped: of another shape (a line of a unit's output), of a function no traced file defines, or
# with no test file or an absolute one. It fails when jq or sort does, so a failed write is never an empty map.
# The facts, sorted by test file and case, are numbered in that order: a T line for each test file, a U line for each
# unit, then an F line for each function with its units' numbers, each line made a row by jq.
covwrite() (
  set -o pipefail
  { jq -cn --arg t "$1" '{traced: $t}' \
    && awk -F'\t' 'NR == FNR { if (NF == 3) has[$1 FS $2] = 1; next }
        NF == 4 && $3 != "" && substr($3, 1, 1) != "/" && (($1 FS $2) in has)' "$2" "$3" \
      | LC_ALL=C sort -u | LC_ALL=C sort -t $'\t' -k3,3 -k4,4 \
      | awk -F'\t' 'NR == FNR { if (NF == 3) fns[++n] = $0; next }
          $3 != t { t = $3; tn++; print "T\t" tn "\t" t }
          ($3 FS $4) != k { k = $3 FS $4; un++; print "U\t" un "\t" tn "\t" $4 }
          { x = $1 FS $2; if (x in u) u[x] = u[x] "," un; else u[x] = un }
          END { for (i = 1; i <= n; i++) { split(fns[i], a, FS); x = a[1] FS a[2]; print "F\t" fns[i] "\t" ((x in u) ? u[x] : "") } }' "$2" - \
      | jq -cR 'split("\t") | if .[0] == "T" then {testfile: (.[1] | tonumber), path: .[2]}
          elif .[0] == "U" then {unit: (.[1] | tonumber), testfile: (.[2] | tonumber)} + (if .[3] != "" then {case: .[3]} else {} end)
          else {file: .[1], fn: .[2], sum: .[3], units: (.[4] | if . == "" then [] else split(",") | map(tonumber) end)} end'
  } | LC_ALL=C sort -u
)
if [ "${1:-}" = --write ]; then covwrite "$2" "$3" "$4"; exit; fi
[ -f .conveyor/test-changed.sh ] || { echo "coverage.sh: run it from the checkout's root" >&2; exit 2; }
# timeout, on macOS too.
. conveyor/lib/portable.sh && p_tools || exit 1
TR=$(mktemp -d "${TMPDIR:-/tmp}/coverage.XXXXXX") || exit 1
trap 'rm -rf "$TR"' EXIT
traced=$(date -u +%Y-%m-%dT%H:%M:%SZ)
cat > "$TR/env.sh" <<'EOF'
if [ -n "${COVERAGE_LOG:-}" ] && exec {COVERAGE_FD}>>"$COVERAGE_LOG"; then
  BASH_XTRACEFD=$COVERAGE_FD; PS4=$'\001${BASH_SOURCE[0]-}\t${FUNCNAME[0]-}\002'; set -x
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
# with others. Each <file><TAB><label><TAB><text> into $TR/labels, for the proof below. It fails, and the file is
# traced whole, when that run fails or a label leaves no text.
checks() {
  local t=$1 l s src x i k
  local -a w
  env -u CONVEYOR_SHELL_TEST_CASE timeout 900 bash "$t" > "$TR/list" 2>&1 < /dev/null || return 1
  src=$(< "$t")
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

# unit <n> <test file> <case>: runs it traced; its functions, <bash's file><TAB><function>, in $TR/<n>.fn, its exit in
# $TR/<n>.rc.
unit() {
  local n=$1 t=$2 c=$3
  local -a cmd
  case $t in
    *.mjs) cmd=(node --max-old-space-size=4096 --test "$t") ;;
    *.py) cmd=(python3 "$t") ;;
    *) cmd=(bash "$t") ;;
  esac
  # The unit's own bash, first on its PATH: it sets the trace again in a bash started with env -i (above), and leaves
  # a BASH_ENV a test set (a case's own hook) as it is.
  mkdir -p "$TR/$n.bin" && printf '#!%s\n[ -n "${BASH_ENV:-}" ] || export COVERAGE_LOG=%q BASH_ENV=%q\nexec %q "$@"\n' "$BASH" "$TR/$n.log" "$TR/env.sh" "$BASH" \
    > "$TR/$n.bin/bash" && chmod +x "$TR/$n.bin/bash" || { echo 1 > "$TR/$n.rc"; return; }
  env PATH="$TR/$n.bin:$PATH" COVERAGE_LOG="$TR/$n.log" BASH_ENV="$TR/env.sh" ${c:+"CONVEYOR_SHELL_TEST_CASE=$c"} timeout 900 "${cmd[@]}" \
    > "$TR/$n.out" 2>&1 < /dev/null
  echo $? > "$TR/$n.rc"; rm -rf "$TR/$n.bin"
  awk 'substr($0, 1, 1) == "\001" && (i = index($0, "\002")) { x = substr($0, 1, i - 1); sub(/^\001+/, "", x)
    if (x ~ /\t./) print x }' "$TR/$n.log" 2>/dev/null | LC_ALL=C sort -u > "$TR/$n.fn"
  rm -f "$TR/$n.log"
}
n=0
while IFS=$'\t' read -r t c; do
  n=$((n + 1))
  [ "$(jobs -rp | wc -l)" -lt 4 ] || wait -n
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
  [ "$(jobs -rp | wc -l)" -lt 4 ] || wait -n
  unit "$n" "$t" "" &
done < <(LC_ALL=C sort -u "$TR/whole")
wait

# Each unit's functions, named by the traced file they belong to: <file><TAB><function><TAB><test><TAB><case>. Only
# the facts go to $TR/runs; a failed unit's lines go to this run's output (issue 1593: they were written to the map).
bad=0; n=0; : > "$TR/runs"
while IFS=$'\t' read -r t c; do
  n=$((n + 1))
  if [ "$(cat "$TR/$n.rc" 2>/dev/null)" != 0 ]; then
    bad=1; echo "coverage.sh: $t${c:+ $c} failed (exit $(cat "$TR/$n.rc" 2>/dev/null)); what it ran is kept. Its last lines:"
    tail -n 15 "$TR/$n.out" | sed 's/^/  /'
  fi
  ! grep -qxF -- "$t" "$TR/whole" || c=
  # The case through ENVIRON: a check's text may hold a backslash, which awk -v would read as an escape.
  T=$t C=$c awk -F'\t' '
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
      for (i = 1; i <= m; i++) if ((fs[i], $2) in has) print fs[i] "\t" $2 "\t" t "\t" c
    }' "$TR/sums" "$TR/$n.fn" >> "$TR/runs"
done < "$TR/units"

# The map, sorted, one fact a line, written whole.
covwrite "$traced" "$TR/sums" "$TR/runs" > "$TR/map" && mv "$TR/map" "$COV" || { echo "coverage.sh: $COV could not be written" >&2; exit 1; }
echo "coverage.sh: $COV: $(grep -c '"sum"' "$COV") functions, $(wc -l < "$TR/units") units traced"
exit $bad
