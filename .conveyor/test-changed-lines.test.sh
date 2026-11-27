#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Issue 1830: a change runs only the cases that ran a changed line. The coverage map (coverage.sh) keeps, for a
# function more than 50 units ran, the units that ran each of its lines, and test-changed.sh (covof, covlines) runs
# only those of the changed lines. Bug it catches: a 2-line change to one branch of testrun.sh tests(), which 573 of
# 3132 cases ran, picked 387 test files; and a function the map did not hold with more than 25 callers ran its file's
# whole area (callersof's cap): 86 files for cardland.sh.
set -u
HERE=$(cd "$(dirname "$0")" && pwd -P); ROOT=$(dirname "$HERE")
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
AT=@
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t${AT}example.com GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t${AT}example.com
# The loop's test step sets these: left set, the scratch test-changed.sh runs below would select the card's files too.
unset CONVEYOR_SHELL_TEST_CASE CONVEYOR_TEST_LOG CONVEYOR_TEST_FILELIST CONVEYOR_TEST_RERUN CONVEYOR_TEST_CASES
bad=0; n=0
ok() { n=$((n + 1)); echo "ok $n - $1"; }
no() { n=$((n + 1)); echo "not ok $n - $1"; bad=1; }

# A scratch checkout: f.sh's big() (line 4 runs on the x path alone, line 6 on the other), run by the 60 cases of
# a.test.sh (c01 and c02 take the x path); g.sh's lone(), which the map does not hold, named by 26 functions of
# h.sh and by b.test.sh's case alone; g.sh's area also lists d.test.sh, which names none of them.
R=$T/r; mkdir -p "$R/.conveyor" "$R/conveyor/lib" "$R/conveyor/tests"
cp "$HERE/coverage.sh" "$HERE/test-changed.sh" "$HERE/funcs.awk" "$HERE/test-share.sh" "$HERE/lint-shell.sh" "$R/.conveyor/"
cp "$ROOT/conveyor/lib/portable.sh" "$R/conveyor/lib/"
printf '%s\n' '{"outside": "conveyor/lib/portable.sh"}' '{"area": "a", "file": "conveyor/lib/f.sh"}' '{"area": "a", "test": "a.test.sh"}' \
  '{"area": "g", "file": "conveyor/lib/g.sh"}' '{"area": "g", "file": "conveyor/lib/h.sh"}' '{"area": "g", "test": "b.test.sh"}' \
  '{"area": "g", "test": "d.test.sh"}' '{"area": "g", "file": "conveyor/conveyor.sh"}' > "$R/.conveyor/engine-areas.json"
# callersof reads conveyor.sh's start-up lines (a changed function they name runs the area).
printf '#!/usr/bin/env bash\ntrue\n' > "$R/conveyor/conveyor.sh"
printf '%s\n' 'big() {' '  echo start' '  if [ "${1:-}" = x ]; then' '    echo x' '  else' '    echo y' '  fi' '  echo end' '}' > "$R/conveyor/lib/f.sh"
printf 'lone() {\n  echo lone\n}\n' > "$R/conveyor/lib/g.sh"
for i in $(seq -w 1 26); do printf 'hc%s() {\n  lone\n}\n' "$i"; done > "$R/conveyor/lib/h.sh"
for i in $(seq -w 1 60); do [ "$i" -le 2 ] && a=x || a=y; printf 't_c%s() {\n  big %s\n}\n' "$i" "$a"; done > "$R/conveyor/tests/a.test.sh"
printf 't_bone() {\n  hc01\n}\n' > "$R/conveyor/tests/b.test.sh"
printf 't_done() {\n  :\n}\n' > "$R/conveyor/tests/d.test.sh"
cat > "$R/conveyor/conveyor.test.sh" <<'EOF'
cd "$(dirname "$0")/.." || exit 1
. conveyor/lib/portable.sh && p_tools || exit 1
for f in conveyor/lib/f.sh conveyor/lib/g.sh conveyor/lib/h.sh conveyor/tests/*.test.sh; do . "$f"; done
for c in ${CONVEYOR_SHELL_TEST_CASE//,/ }; do "t_$c" > /dev/null || exit 1; done
EOF
for c in test-lint no-browser-tests no-records-split; do : > "$R/.conveyor/$c.sh"; done
git -C "$R" init -q && git -C "$R" add -A && git -C "$R" commit -qm init || no "the scratch checkout could not be made"
SHA=$(git -C "$R" rev-parse HEAD)
M=$R/.conveyor/coverage.jsonl F=$T/fx; mkdir -p "$F"
(cd "$R" && bash .conveyor/test-changed.sh --funcs conveyor/lib/f.sh) | sed 's|^|conveyor/lib/f.sh\t|' > "$F/sums"
# The map as coverage.sh writes it from a trace of the 60 cases (--write): big() run by each, its lines 2, 3 and 8 by
# each, line 4 by c01 and c02, line 6 by the rest.
for i in $(seq -w 1 60); do
  printf 'conveyor/lib/f.sh\tbig\tconveyor/conveyor.test.sh\tc%s\n' "$i" >> "$F/runs"
  for l in 2 3 8 $([ "$i" -le 2 ] && echo 4 || echo 6); do printf 'conveyor/lib/f.sh\tbig\t%s\tconveyor/conveyor.test.sh\tc%s\n' "$l" "$i"; done >> "$F/lines"
done
mapat() { # <sha>: the map, committed
  bash "$HERE/coverage.sh" --write 2026-11-27T00:00:00Z "$F/sums" "$F/runs" "$F/lines" "$1" > "$M" && git -C "$R" add -A && git -C "$R" commit -qm map
}
# cases: the engine cases test-changed.sh runs for the working tree's change (its log's TESTRUN case lines), sorted.
cases() {
  rm -rf "$F/log"; mkdir "$F/log"; (cd "$R" && CONVEYOR_TEST_LOG=$F/log bash .conveyor/test-changed.sh) > "$F/out" 2>&1
  sed -n 's/^TESTRUN case	conveyor\/tests\/a.test.sh	//p' "$F/log/test-changed.log" | LC_ALL=C sort | paste -sd ' ' -
}
mapat "$SHA" || no "the map could not be written"

# Done when 1: a change to line 4, which only c01 and c02 ran, runs those two and no other case of big()'s 60.
sed -i.bak '4s/echo x/echo X/' "$R/conveyor/lib/f.sh" && rm -f "$R/conveyor/lib/f.sh.bak"
got=$(cases)
[ "$got" = "c01 c02" ] && grep -qxF 'coverage map rule: conveyor/lib/f.sh big(): lines' "$F/out" \
  && ok "a change to a line two of a function's 60 cases ran runs those two, by the rule lines" \
  || no "line 4 of big() changed (run by c01, c02): ran '$got': $(cat "$F/out")"
git -C "$R" checkout -q -- conveyor/lib/f.sh
# A line no command started on in the trace (`else`, line 5) stands as the nearest lines before and after it that have
# rows: 4 and 6. (A comment added to it would be a comment-only change, which runs no test at all.)
sed -i.bak '5s/else/else :/' "$R/conveyor/lib/f.sh" && rm -f "$R/conveyor/lib/f.sh.bak"
got=$(cases); want=$(seq -w 1 60 | sed 's/^/c/' | paste -sd ' ' -)
[ "$got" = "$want" ] && ok "a changed line with no row (else) runs the cases of the lines around it" || no "line 5 (else) changed: ran '$got'"
git -C "$R" checkout -q -- conveyor/lib/f.sh

# Main added two lines above big() since the trace: the lines are read as the map's commit had them, so a change to
# line 6 (now line 8: echo y) runs the 58 cases of the y path.
{ printf '# a\n# b\n'; cat "$R/conveyor/lib/f.sh"; } > "$T/e" && cat "$T/e" > "$R/conveyor/lib/f.sh" && git -C "$R" commit -qam "main moves big" \
  || no "the main commit could not be made"
sed -i.bak '8s/echo y/echo Y/' "$R/conveyor/lib/f.sh" && rm -f "$R/conveyor/lib/f.sh.bak"
got=$(cases); want=$(seq -w 3 60 | sed 's/^/c/' | paste -sd ' ' -)
[ "$got" = "$want" ] && grep -qxF 'coverage map rule: conveyor/lib/f.sh big(): lines' "$F/out" \
  && ok "lines main moved since the trace are read as the map's commit had them" || no "line 8 (was 6) changed after main moved big(): ran '$got': $(cat "$F/out")"
git -C "$R" checkout -q -- conveyor/lib/f.sh

# Done when 3: main changed a line inside big() since the trace (line 4 of the map's commit): the lines can no longer be
# trusted, and a change to it runs the cases that ran the function, by its row (covof).
sed -i.bak '10s/echo end/echo fin/' "$R/conveyor/lib/f.sh" && rm -f "$R/conveyor/lib/f.sh.bak" && git -C "$R" commit -qam "main edits big" \
  || no "the main edit could not be made"
sed -i.bak '6s/echo x/echo X/' "$R/conveyor/lib/f.sh" && rm -f "$R/conveyor/lib/f.sh.bak"
got=$(cases); want=$(seq -w 1 60 | sed 's/^/c/' | paste -sd ' ' -)
[ "$got" = "$want" ] && ! grep -q 'big(): lines' "$F/out" \
  && ok "a function main changed since the trace runs every case that ran it, not by its lines" || no "big() edited on main, then line 6 changed: ran '$got': $(cat "$F/out")"
git -C "$R" checkout -q -- conveyor/lib/f.sh

# Done when 2: lone(), which the map does not hold and 26 functions call, runs the test files that call it (b.test.sh
# names hc01) and not its area's d.test.sh.
printf 'lone() {\n  echo alone\n}\n' > "$R/conveyor/lib/g.sh"
rm -rf "$F/log"; mkdir "$F/log"; (cd "$R" && CONVEYOR_TEST_LOG=$F/log bash .conveyor/test-changed.sh) > "$F/out" 2>&1
got=$(sed -n 's/^TESTRUN case	conveyor\/tests\///p' "$F/log/test-changed.log" | cut -f1 | LC_ALL=C sort -u | paste -sd ' ' -)
[ "$got" = b.test.sh ] && grep -qxF 'coverage map rule: conveyor/lib/g.sh lone(): callersof' "$F/out" \
  && ok "a function the map does not hold with 26 callers runs its callers' tests, not its area" \
  || no "lone() changed (26 callers, not in the map): ran '$got': $(cat "$F/out")"
git -C "$R" checkout -q -- conveyor/lib/g.sh

# Done when 4: a map over its limit drops the line rows of the functions with the most lines first, and says which.
# small() has 2 line rows, big() 5: under a limit that holds the rest and small()'s rows, big()'s go.
for i in $(seq -w 1 60); do
  printf 'conveyor/lib/f.sh\tsmall\tconveyor/conveyor.test.sh\tc%s\n' "$i"
done >> "$F/runs"
for i in $(seq -w 1 60); do printf 'conveyor/lib/f.sh\tsmall\t%s\tconveyor/conveyor.test.sh\tc%s\n' 20 "$i" 21 "$i"; done >> "$F/lines"
printf 'conveyor/lib/f.sh\tsmall\t1\n' >> "$F/sums"
bash "$HERE/coverage.sh" --write 2026-11-27T00:00:00Z "$F/sums" "$F/runs" "$F/lines" "$SHA" > "$F/full"
whole=$(wc -c < "$F/full"); bigb=$(jq -c 'select(.fn == "big" and has("line"))' "$F/full" | wc -c)
COVERAGE_MAX_BYTES=$((whole - bigb + 1)) bash "$HERE/coverage.sh" --write 2026-11-27T00:00:00Z "$F/sums" "$F/runs" "$F/lines" "$SHA" > "$F/cut" 2> "$F/cut.err"
[ "$(jq -c 'select(has("line")) | .fn' "$F/full" | sort | uniq -c | awk '{ print $2 $1 }' | paste -sd ' ' -)" = '"big"5 "small"2' ] \
  && [ "$(jq -c 'select(has("line")) | .fn' "$F/cut" | sort -u | paste -sd ' ' -)" = '"small"' ] && [ "$(wc -c < "$F/cut")" -le $((whole - bigb + 1)) ] \
  && grep -qF 'the line rows of conveyor/lib/f.sh big() are dropped' "$F/cut.err" \
  && ok "a map over its limit drops the line rows of the function with the most lines, and says so" \
  || no "limit $((whole - bigb + 1)) of $whole bytes: rows $(jq -c 'select(has("line")) | [.fn, .line]' "$F/cut" | paste -sd ' ' -): $(cat "$F/cut.err")"
# A function 50 units or fewer ran keeps no line rows (its units are few already), and the map names its commit.
head -n 50 "$F/runs" | grep -v small > "$F/runs50"
bash "$HERE/coverage.sh" --write 2026-11-27T00:00:00Z "$F/sums" "$F/runs50" "$F/lines" "$SHA" > "$F/few"
[ -z "$(jq -c 'select(has("line"))' "$F/few")" ] && [ "$(jq -r 'select(has("traced")) | .sha' "$F/few")" = "$SHA" ] \
  && ok "a function 50 units ran has no line rows, and the map names the commit it traced" || no "50 units: $(grep line "$F/few" | head -n 3)"

# The trace itself (coverage.sh run on the scratch checkout): bash's line of each command goes into the line rows.
git -C "$R" checkout -q "$SHA" -- conveyor/lib/f.sh && git -C "$R" commit -qam "f back" || no "f.sh could not be put back"
(cd "$R" && bash .conveyor/coverage.sh) > "$F/trace.out" 2>&1
l4=$(jq -rn '[inputs] as $m | (reduce ($m[] | select(has("unit"))) as $x ({}; .[$x.unit | tostring] = $x.case)) as $u
  | $m[] | select(.fn == "big" and .line == 4) | [.units[] | $u[tostring]] | sort | join(" ")' "$M" 2>/dev/null)
[ "$l4" = "c01 c02" ] && [ "$(jq -c 'select(.fn == "big" and has("line")) | .line' "$M" | sort -n | paste -sd ' ' -)" = "2 3 4 6 8" ] \
  && ok "a traced run keeps, of a function 60 cases ran, the cases that ran each of its lines" \
  || no "traced line rows of big(): line 4 '$l4', lines $(jq -c 'select(.fn == "big" and has("line")) | .line' "$M" | paste -sd ' ' -): $(tail -n 20 "$F/trace.out")"
exit $bad
