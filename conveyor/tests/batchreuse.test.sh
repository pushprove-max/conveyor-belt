#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 300
# Engine cases: a batch's test run reuses the tests each card of it passed (batch(), batchkeep()). Its fixture
# (reusesetup) and helpers serve the batch's other reuse cases too, each in a file of its own (batchreuse*.test.sh):
# each is a whole batch run, and together they were over the test step's CPU budget for one file.
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"

# Cards (#7, #8 and, when named, #9) with batches on, each GO. Each changes a.txt and a file of its own: #7 x.txt, #8
# y.txt, #9 z.txt; #7 and #8 change b.txt too. #7 first holds a.txt; each other card's review ends only once it does
# (its change then waits on #7's), #9's only once #8 is ready. A product check holds #7 before its own tests until #8
# waits, ready, at its claim, so #7's batch takes it; $STUB/held-then, when there is one, runs once there. That check
# gives up once #8 is gone (it held its files beside #7 and landed, or was blocked), failing the case, not hanging it.
# Each test file $STUB/map names for a file (`<file> <test file>`) is a file of main, <test file>.sh (or the name,
# when it ends in .sh), linked to that file: a card runs each alone, through test.fileCommand (#374). Its run runs
# the cases $STUB/cases gives the test file (`<test file> <case>...`), and does what CONVEYOR_TEST_RERUN asks: a file
# listed `pass` does not run, a case listed `ok` does not run (unless its file is named in $STUB/whole: a file
# whose cases cannot run apart, which honours only `pass`), and a file a `changed` line
# selects runs whole. Each card run writes a line to $STUB/runs, `<card> <cases its files ran>` (a run of no file
# writes none), and each file's log says how many cases ran and how many it kept.
# The cards are in the control record's order list in the order they become ready (#8, #9, #7), as batch.test.sh's
# batchsetup says: so #8 waits on #7, as ordered cards never go past each other.
reusesetup() { # <issues json> <map lines>...
  setup "$1"; shift; tune '.landBatch = 8'; for i in 1 2 3 4 5 6; do echo "$GO" > "$STUB/review.$i"; done
  jq -c '.order = [8, 9, 7]' "$ST/control.json" > "$STUB/c.new" && mv "$STUB/c.new" "$ST/control.json"
  seq 20 > "$R/a.txt"; seq 20 > "$R/b.txt"; git -C "$R" add b.txt; git -C "$R" commit -qam "a longer a.txt, and b.txt"
  printf '%s\n' "$@" > "$STUB/map"; printf '%s\n' 's.test s1' 'x.test x1 x2' 'y.test y1 y2' 'z.test z1 z2' > "$STUB/cases"
  local s t l='{}'
  while read -r s t; do
    [[ $t == *.sh ]] || t=$t.sh; mkdir -p "$R/$(dirname "$t")" && echo x > "$R/$t" && git -C "$R" add "$t" || fail "main's test file $t"
    l=$(jq -c --arg s "$s" --arg t "$t" '.[$s] += [$t]' <<<"$l")
  done < "$STUB/map"
  linkset "$l"
  echo 'case $PWD in *-7) sed -i 1s/.*/seven/ a.txt b.txt; echo x > x.txt ;; *-8) echo eight | tee -a a.txt >> b.txt; echo y > y.txt ;; *) sed -i 10s/.*/nine/ a.txt; echo z > z.txt ;; esac' > "$STUB/build"
  cat > "$STUB/review-cmd" <<'EOF'
n=${PWD##*-}
[ "$n" = 7 ] || [ -e "$STUB/rev.$n" ] || { : > "$STUB/rev.$n"; while [ -d "$STUB" ]; do jq -e .held ../*-7.claim >/dev/null 2>&1 && break; sleep 0.1; done
  rm -f ../*-7.cpatch
  [ "$n" != 9 ] || while [ -d "$STUB" ]; do jq -e .tested ../*-8.ready >/dev/null 2>&1 && break; sleep 0.1; done; }
EOF
  cat > "$STUB/hold" <<'EOF'
case $PWD in *-7) [ -e "$STUB/held" ] || while [ -d "$STUB" ]; do
  jq -e .tested ../*-8.ready >/dev/null 2>&1 && jq -e '.held == false' ../*-8.claim >/dev/null 2>&1 \
    && { : > "$STUB/held"; [ ! -f "$STUB/held-then" ] || . "$STUB/held-then"; exit 0; }
  ls -d ../*-8 >/dev/null 2>&1 || { : > "$STUB/held"; exit 0; }; sleep 0.1; done ;; esac
EOF
  tune --arg h "$STUB/hold" '.checks = [$h]'
  wait_fn > "$STUB/test-cmd"; cat >> "$STUB/test-cmd" <<'EOF'
L=$CONVEYOR_TEST_LOG/run.log; RR=${CONVEYOR_TEST_RERUN:-/dev/null}; f=$CONVEYOR_TEST_FILE
[ "${CONVEYOR_TEST_N:-1}" != 1 ] || echo x >> "$STUB/tests"
tf() { while read -r f; do awk -v f="$f" '$1 == f {print $2}' "$STUB/map"; done | sort -u; } # changed files on stdin: their test files
fresh=$(awk -F'\t' '$1 == "changed" {print $2}' "$RR" | tf)
t=$(awk -v f="$f" '$2 == f || $2 ".sh" == f {print $2; exit}' "$STUB/map") # the map's name of the file
ran=''; k=0; kept=0
cs=$(awk -v t="$t" '$1 == t { for (i = 2; i <= NF; i++) print $i }' "$STUB/cases")
if ! grep -qxF "$t" <<<"$fresh"; then
  if grep -qxF "pass	$f" "$RR"; then kept=$(wc -w <<<"$cs"); cs=
  else all=$cs; grep -qxF "$t" "$STUB/whole" 2>/dev/null || cs=$(grep -vxFf <(awk -F'\t' -v f="$f" '$1 == "ok" && $2 == f {print $3}' "$RR") <<<"$cs")
    kept=$(($(wc -w <<<"$all") - $(wc -w <<<"$cs"))); fi
fi
for c in $cs; do echo "ok $c"; ran="$ran $c"; k=$((k + 1)); done
f=${f%%"$f"}; c=${PWD##*-}
# Two cards' runs can go side by side (#7's run alone and #9's, in batchreuseagain), and a card's own files run side
# by side too, ending in any order (#1594, E7: file 2 taking the lock before file 1 found no line of its run and
# dropped its cases): one writer at a time. The run's first file to take the lock adds its line, and keeps the line's
# number in a folder of the run's log folder (no log: the run reads only the files there, and makes the folder new each
# run); each file keeps its cases there by its place in the run, and the line is made again from them in that order.
runslock() { mkdir "$STUB/runs.lock" 2>/dev/null; }; wait_poll runslock
d=$CONVEYOR_TEST_LOG/stub-runs; mkdir -p "$d"; printf '%s' "$ran" > "$d/${CONVEYOR_TEST_N:-1}"
[ -s "$d/line" ] || { echo "$c" >> "$STUB/runs"; wc -l < "$STUB/runs" > "$d/line"; }
awk -v n="$(cat "$d/line")" -v r="$c$(for p in $(ls "$d" | grep -x '[0-9]*' | sort -n); do cat "$d/$p"; done)" '{ print (NR == n ? r : $0) }' \
  "$STUB/runs" > "$STUB/runs.new" && mv "$STUB/runs.new" "$STUB/runs"
rmdir "$STUB/runs.lock"
echo "TESTRUN cases=$k" >> "$L"; [ "$RR" = /dev/null ] || echo "TESTRUN kept=$kept" >> "$L"
EOF
}
# cardof is batch.test.sh's: the runner loads every case file into one shell, so a second definition replaces the first.
runs() { tr '\n' ',' < "$STUB/runs"; } # every run, in order, as `<card> <cases>,`
landedtogether() { [ "$(st 'select(.step == "landed") | .batch | join(" ")' | sort -u)" = "$1" ]; } # <the batch's cards, in order>

# The owner (2026-11-13): card #323, its change unchanged since its tests passed, ran its 219 cases three more times in
# batch runs. Two cards that each passed alone, on changes unchanged since, with no case selected by both (a.txt and
# b.txt, the files they share, select none): their batch lands with no test run, and #7's test line says no case ran
# and the seven passes were kept. #7's x.txt selects two whole files, w.test's three cases and x.test's two: the count
# keeps all five, not four (five shared evenly between the two files, rounded down, lost one).
t_batchreusenone() {
  reusesetup "[$(issue 7 2026-01-01),$(issue 8 2026-01-02)]" 'x.txt w.test' 'x.txt x.test' 'y.txt y.test'
  echo 'w.test w1 w2 w3' >> "$STUB/cases"
  out=$(loop run 2>&1) || fail "run exited non-zero: $out"
  c7=$(cardof 7); c8=$(cardof 8)
  [ "$(runs)" = "8 y1 y2,7 w1 w2 w3 x1 x2," ] && [ "$(wc -l < "$STUB/tests")" = 2 ] || fail "a test run beside the two cards' own: $(runs): $out"
  grep -q "card $c7: its batch of 2 runs no case, each having passed on its cards' changes (7 kept)" <<<"$out" || fail "#7 did not say its batch runs no case, seven kept: $out"
  landedtogether "$c8 $c7" || fail "the two cards did not land as one batch: $(st 'select(.step == "landed")')"
  [ "$(st 'select(.issue == 7 and .step == "test") | [.result, .selected.cases, .selected.kept] | tojson' | tail -n 1)" = '["pass",0,7]' ] \
    || fail "#7's last test line does not say no case ran and seven passes were kept: $(st 'select(.issue == 7 and .step == "test")')"
  loop check || fail "the record check refuses the test line of a batch that ran no case"
  [ "$(sed -n '1p;$p' "$R/a.txt" | tr '\n' ' ')" = "seven eight " ] && [ "$(cat "$R/x.txt" "$R/y.txt" | tr '\n' ' ')" = "x y " ] \
    && [ -z "$(ls "$T/$CASE/cards")" ] || fail "main does not hold both changes, or a worktree or mark is left: $(ls "$T/$CASE/cards")"
}
