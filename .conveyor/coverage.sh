#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# The coverage map (issue 527): for each function of the shell files below, the test cases that ran it, so that
# .conveyor/test-changed.sh runs only those cases on a change to the function (covof). Run by hand from the checkout's
# root, `bash .conveyor/coverage.sh`; never on a card's test step: it runs every case once, traced, and writes
# .conveyor/coverage.jsonl whole, to commit.
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
# environment (env -i) is not traced, nor are the functions it runs.
# A function a log names belongs to the traced file whose path ends most like the one bash read it from (a case runs a
# copy of the engine from a scratch folder), or to each that defines it when bash names no file (an exported
# function), and only to a file that defines it.
# The map is one fact a line, sorted, so two of them merge by union (.gitattributes):
#   {"traced": <UTC time>}
#   {"file": <file>, "fn": <function>, "sum": <sum>}   each function of each traced file, as it was traced (sumsof)
#   {"file": <file>, "fn": <function>, "test": <test file>, "case": <case or part>}   a unit that ran it; no "case" for
#                                                                                      a test file run whole
# A unit that fails is named, with the end of its output, and the map is still written (what it ran, it ran); the
# exit is then 1. A trace takes several times the time of the run it traces, and its logs, each removed as its unit
# ends, are under TMPDIR.
set -u
COV=.conveyor/coverage.jsonl
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
  env COVERAGE_LOG="$TR/$n.log" BASH_ENV="$TR/env.sh" ${c:+"CONVEYOR_SHELL_TEST_CASE=$c"} timeout 900 "${cmd[@]}" \
    > "$TR/$n.out" 2>&1 < /dev/null
  echo $? > "$TR/$n.rc"
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

# Each unit's functions, named by the traced file they belong to: <file><TAB><function><TAB><test><TAB><case>.
bad=0; n=0
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
    NR == FNR { has[$1, $2] = 1; of[$2] = of[$2] " " $1; next }
    !($2 in of) { next }
    {
      m = split(substr(of[$2], 2), fs, " "); best = 0; got = ""
      for (i = 1; i <= m; i++) { s = score($1, fs[i]); if (s > best) { best = s; got = fs[i] } else if (s == best && s > 0) got = got " " fs[i] }
      if (best == 0 && ($1 == "" || $1 == "environment")) got = substr(of[$2], 2)
      m = split(got, fs, " ")
      for (i = 1; i <= m; i++) if ((fs[i], $2) in has) print fs[i] "\t" $2 "\t" t "\t" c
    }' "$TR/sums" "$TR/$n.fn"
done < "$TR/units" > "$TR/runs"

# The map, sorted, one fact a line, written whole.
{ jq -cn --arg t "$traced" '{traced: $t}'
  jq -cR 'split("\t") | {file: .[0], fn: .[1], sum: .[2]}' "$TR/sums"
  LC_ALL=C sort -u "$TR/runs" | jq -cR 'split("\t") | {file: .[0], fn: .[1], test: .[2]} + (if .[3] != "" then {case: .[3]} else {} end)'
} | LC_ALL=C sort -u > "$TR/map" && mv "$TR/map" "$COV" || { echo "coverage.sh: $COV could not be written" >&2; exit 1; }
echo "coverage.sh: $COV: $(grep -c '"sum"' "$COV") functions, $(wc -l < "$TR/units") units traced"
exit $bad
