#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 300
# Engine cases: a batch formed again after one of its cards landed alone reuses the passes of the cards left
# (batch(), batchkeep()). Its own file, with the fixture of batchreuse.test.sh (reusesetup): each case of the batch's
# reuse is a whole batch run, and together they were over the test step's CPU budget for one file.
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"

# The owner: when a card of a batch landed alone first, the batch formed again ran everything again. #7 and #8 share
# b.txt, which selects s.test: their batch runs s1 alone, passes, and does not land, main's commit-msg hook refusing
# #8's commit once. #7 is tested alone again and lands alone. #8, unchanged, then takes #9 into a batch: #9 changes
# line 20 of a.txt, beside the line #8 appends, so it overlaps #8 and, its review ending only once #8 holds a.txt
# again, it is stacked on #8 (stackto(): put on main plus #8's change, tested there, and waiting on #8 until #8's batch
# takes it). It was kept waiting by taking #8's kept patch away, before stacking; #8 writes that patch again at its
# claim before it lands, so #9, whose change then applied with #8's, went past it and both landed alone. A product
# check holds #8 before its tests until #9 waits, ready. Every case of #8 passed on its own change, and of #9 on its
# own, none selected by both, so the batch runs no case.
t_batchreuseagain() {
  reusesetup "[$(issue 7 2026-01-01),$(issue 8 2026-01-02),$(issue 9 2026-01-03)]" 'b.txt s.test' 'x.txt x.test' 'y.txt y.test' 'z.txt z.test'
  printf '%s\n' '! grep -q "(#8)" "$1" || [ -e "$STUB/refused" ] || { : > "$STUB/refused"; echo "not #8 yet"; exit 1; }' | sed "s|\$STUB|$STUB|g" > "$R/.git/hooks/commit-msg"
  chmod +x "$R/.git/hooks/commit-msg"
  echo 'case $PWD in *-7) sed -i 1s/.*/seven/ a.txt b.txt; echo x > x.txt ;; *-8) echo eight | tee -a a.txt >> b.txt; echo y > y.txt ;; *) sed -i 20s/.*/nine/ a.txt; echo z > z.txt ;; esac' > "$STUB/build"
  cat > "$STUB/review-cmd" <<'EOF'
n=${PWD##*-}
case $n in
  8) [ -e "$STUB/rev.8" ] || { : > "$STUB/rev.8"; while [ -d "$STUB" ]; do jq -e .held ../*-7.claim >/dev/null 2>&1 && break; ls -d ../*-7 >/dev/null 2>&1 || break; sleep 0.1; done; rm -f ../*-7.cpatch; } ;;
  9) [ -e "$STUB/rev.9" ] || { : > "$STUB/rev.9"; while [ -d "$STUB" ]; do
      [ -e "$STUB/refused" ] && ! ls ../*-7.claim >/dev/null 2>&1 && jq -e .held ../*-8.claim >/dev/null 2>&1 && break; ls -d ../*-8 >/dev/null 2>&1 || break; sleep 0.1; done; } ;;
esac
EOF
  # Each wait gives up once the card it waits on is gone (landed or blocked: its worktree removed), and the hold once #9
  # holds a.txt beside #8, failing the case below rather than hanging when the engine takes another path.
  cat >> "$STUB/hold" <<'EOF'
case $PWD in *-8) [ -e "$STUB/refused" ] && [ ! -e "$STUB/again" ] && jq -e '.held == true' "$PWD.claim" >/dev/null 2>&1 && {
  while [ -d "$STUB" ]; do jq -e .tested ../*-9.ready >/dev/null 2>&1 && jq -e '.held == false and .away != true' ../*-9.claim >/dev/null 2>&1 && break
    ! jq -e '.held == true' ../*-9.claim >/dev/null 2>&1 || break; ls -d ../*-9 >/dev/null 2>&1 || break; sleep 0.1; done
  : > "$STUB/again"; } ;; esac
exit 0
EOF
  out=$(loop run 2>&1) || fail "run exited non-zero: $out"
  c7=$(cardof 7); c8=$(cardof 8); c9=$(cardof 9)
  [ -e "$STUB/refused" ] && grep -q "card $c7: its batch did not land, so it is tested alone" <<<"$out" || fail "the first batch was not refused: $out"
  grep -q "card $c9 is stacked on card $c8" <<<"$out" || fail "#9 was not stacked on #8, whose change it overlaps: $out"
  # The own runs of #8 and #7, the batch's run of s1, #7's run alone on the same main (issue 460: it keeps the passes
  # of the batch's run, x1 and x2, whose x.txt is as it was, and runs s1 again, as b.txt, which #8 changed too, differs),
  # #9's own run, and none for the batch of #8 and #9.
  [ "$(runs)" = "8 s1 y1 y2,7 s1 x1 x2,7 s1,7 s1,9 z1 z2," ] || fail "a run for the batch formed again, or not one run of s1 for the first batch: $(runs): $out"
  [ "$(st 'select(.step == "landed") | "\(.issue) \(.batch)"' | head -n 1)" = "7 null" ] || fail "#7 did not land alone first: $(st 'select(.step == "landed")')"
  [ "$(st 'select(.step == "landed" and .issue != 7) | .batch | sort | join(" ")' | sort -u)" = "$(printf '%s\n' "$c8" "$c9" | sort | tr '\n' ' ' | sed 's/ $//')" ] \
    || fail "#8 and #9 did not land as one batch: $(st 'select(.step == "landed")')"
  # Five kept: #8's s1 y1 y2 and #9's z1 z2. Bug it catches (issue #354): #8 brought the first batch's x1 and x2,
  # which only #7, gone, selected, and the batch said seven were kept.
  grep -q "its batch of 2 runs no case, each having passed on its cards' changes (5 kept)" <<<"$out" || fail "the batch formed again did not say it runs no case, five kept: $out"
  [ "$(cat "$R/x.txt" "$R/y.txt" "$R/z.txt" | tr '\n' ' ')" = "x y z " ] || fail "main does not hold the three changes"
}
