#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# `bash .conveyor/where.sh <function>` (issue 1821): where a bash function of the engine is, for a build or fix session
# that has no symbol search. Run from anywhere in the checkout; it reads the checkout it is in. It prints, in order:
#   def <file>:<line>                   each engine shell file that defines it (a .sh file under conveyor/ of
#                                       .conveyor/engine-areas.json, read as .conveyor/funcs.awk reads it)
#   caller <file>:<line> <function>     each other function of those files with a line that is no comment and names
#                                       it as a whole word (its first such line), at most 25, then `and <n> more`
#   test <file>                         each test file (*.test.*) with a line that is no comment and names it or a
#                                       listed caller as a whole word, at most 20, then `and <n> more`
#   covered <test file> [<case>]        each unit of .conveyor/coverage.jsonl that ran it, at most 20, then `and <n>
#                                       more`; first the line `coverage row older than the function` when the row's
#                                       sum is not the function's sum now (the sum test-changed.sh --funcs gives)
# No row, or no map, prints no covered line. It exits 1 with `no function <name>` when no engine file defines it, and 2
# when it cannot read the engine area map or funcs.awk. An engine file funcs.awk cannot read is named on stderr and
# skipped.
set -u
cd "$(dirname "$0")/.." || exit 2
[ $# = 1 ] || { echo "usage: bash .conveyor/where.sh <function>" >&2; exit 2; }
name=$1
# A name that is no bash function name defines nothing; and it goes into a regular expression below.
[[ $name =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || { echo "no function $name"; exit 1; }
FUNCS=$(cat .conveyor/funcs.awk) || { echo "where: .conveyor/funcs.awk cannot be read" >&2; exit 2; }
files=$(jq -r 'select(type == "object" and (.file | type) == "string") | .file | select(test("^conveyor/.*[.]sh$"))' \
  .conveyor/engine-areas.json) || { echo "where: .conveyor/engine-areas.json cannot be read" >&2; exit 2; }
# cap <n>: the first <n> lines of stdin, then `and <k> more` for the rest.
cap() { awk -v m="$1" 'NR <= m; END { if (NR > m) print "and " NR - m " more" }'; }
word() { echo "(^|[^A-Za-z0-9_])($1)([^A-Za-z0-9_]|\$)"; }
defs='' calls=''
declare -A out=()
while read -r f; do
  [ -f "$f" ] || continue
  o=$(awk "$FUNCS" "$f") && ! grep -qx U <<<"$o" || { echo "where: $f cannot be read as functions; skipped" >&2; continue; }
  out[$f]=$o
  # The FUNCS lines in file order: an S line is one line of the file, a K line as many as its body joins with \001.
  r=$(awk -F'\t' -v w="$name" -v f="$f" -v re="$(word "$name")" '
    $1 == "S" { ln++; next }
    $1 == "K" { n = $2; k = split(substr($0, length(n) + 4), l, "\001")
      if (n == w) print "def " f ":" (ln + 1)
      else {
        sub(/^(function[ \t]+)?[A-Za-z_][A-Za-z0-9_]*[ \t]*\(\)/, "", l[1])
        for (i = 1; i <= k; i++) if (l[i] !~ /^[ \t]*#/ && l[i] ~ re) { print "caller " f ":" (ln + i) " " n; break }
      }
      ln += k }' <<<"$o")
  defs+=$(grep '^def ' <<<"$r")$'\n'
  calls+=$(grep '^caller ' <<<"$r")$'\n'
done < <(LC_ALL=C sort -u <<<"$files")
defs=$(grep . <<<"$defs")
[ -n "$defs" ] || { echo "no function $name"; exit 1; }
echo "$defs"
calls=$(grep . <<<"$calls" | cap 25)
[ -z "$calls" ] || echo "$calls"
# The tests: of each test file of the checkout, those that name the function or a caller listed above.
w=$(sed -n 's/^caller [^ ]* //p' <<<"$calls" | LC_ALL=C sort -u | paste -sd '|' -)
mapfile -t tf < <(git ls-files -co --exclude-standard -- '*.test.*' 2>/dev/null | LC_ALL=C sort -u \
  | while read -r t; do [ ! -f "$t" ] || echo "$t"; done)
# A comment line is one that starts with # in a shell or Python file, and with //, /* or * in a JavaScript or
# TypeScript file.
[ ${#tf[@]} = 0 ] || awk -v re="$(word "$name${w:+|$w}")" '
  FNR == 1 { cm = FILENAME ~ /[.](m?js|tsx?)$/ ? "^[ \t]*(//|/[*]|[*])" : "^[ \t]*#" }
  $0 !~ cm && $0 ~ re { print "test " FILENAME; nextfile }' "${tf[@]}" < /dev/null | cap 20
# The coverage map's rows of the function in each file that defines it: the units that ran it, and whether the row's
# sum is still the function's (sumsof of test-changed.sh: the cksum of its body as FUNCS joins it).
[ -f .conveyor/coverage.jsonl ] || exit 0
stale='' cov=''
while read -r f; do
  rows=$(jq -rn --arg f "$f" --arg n "$name" '[inputs | objects] as $m
    | (reduce ($m[] | select(has("testfile") and has("path"))) as $x ({}; .[$x.testfile | tostring] = $x.path)) as $p
    | (reduce ($m[] | select(has("unit"))) as $x ({}; .[$x.unit | tostring] = [$p[$x.testfile | tostring], $x.case // ""])) as $u
    | $m[] | select(.file == $f and .fn == $n and has("sum"))
    | "S\t\(.sum)", ((.units // [])[] | $u[tostring] // empty | select(.[0] != null) | "covered \(.[0]) \(.[1])")' \
    .conveyor/coverage.jsonl) || { echo "where: .conveyor/coverage.jsonl cannot be read" >&2; exit 0; }
  [ -n "$rows" ] || continue
  sum=$(while IFS=$'\t' read -r k n b; do
    [ "$k" = K ] && [ "$n" = "$name" ] && { cksum <<<"$b" | cut -d' ' -f1; break; }
  done <<<"${out[$f]}")
  [ "$(sed -n 's/^S\t//p' <<<"$rows" | head -n 1)" = "$sum" ] || stale=1
  cov+=$(grep '^covered ' <<<"$rows" | sed 's/ $//')$'\n'
done < <(sed 's/^def //; s/:[0-9]*$//' <<<"$defs" | LC_ALL=C sort -u)
[ -z "$stale" ] || echo "coverage row older than the function"
# A unit that ran two definitions of the function (rows of two files) is one line.
grep . <<<"$cov" | awk '!seen[$0]++' | cap 20
exit 0
