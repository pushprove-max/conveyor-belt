#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 300
# Engine cases: a ready card lands first (the owner, 2026-11-18). A card whose review gave a GO and whose tests passed
# never waits on a card that changes the same files and is behind it (still in its tests or its fix); of two ready
# cards, the one ready first lands first. The card behind is fitted onto main with the change that landed.
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"
# The engine folder, as lib.sh sets it: named here too, so the release closure (tools/closure.sh) follows this file's paths.
SRC=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
# t_readyclaim has the per-file fixture (lib.sh, filemode()). The cases of rfsetup keep the old one: #7 lands on a main
# where #8 changed a.txt too, and they read which test files the whole run names (s.test, x.test, y.test).

# Bug: a card that passed its review and its tests waited at its claim on a card that held the same files and was
# still in its tests (#326 waited over 2 hours so), because that card was picked first. claim() as the engine has it:
# #8, tested, goes past #7, which holds a.txt untested, and #7 is marked fit (not reviewed again only for that, was);
# #7 then waits on #8 and claims once #8 landed. Gone past by an ordered card instead, #7 is reviewed again (was).
# #8 does not go past an ordered #7, nor before #7 when #7's tests passed first; tested on a stack's base, #8 is not
# ready. Of two waiting ready cards, the one ready first goes first, though picked second.
t_readyclaim() {
  setup '[]'; seq 20 > "$R/a.txt"; git -C "$R" commit -qam "a longer a.txt"
  CARDS=$T/$CASE/cards; mkdir -p "$CARDS"
  for n in 7 8; do
    git -C "$R" worktree add -q "$CARDS/c$n-$n" -b "card-$n" main
    echo "{\"card\":\"c$n-$n\",\"issue\":$n,\"step\":\"picked\"}" >> "$ST/cards.jsonl"
  done
  sed -i 1s/1/seven/ "$CARDS/c7-7/a.txt"; git -C "$CARDS/c7-7" add -A
  sed -i 1s/1/eight/ "$CARDS/c8-8/a.txt"; git -C "$CARDS/c8-8" add -A
  eval "$(sed -n '/^claim() {/,/^}/p; /^claimline() {/,/^}/p; /^readyrows() {/,/^}/p; /^together() {/,/^}/p; /^ready() {/,/^}/p; /^fits() {/,/^}/p; /^merge3() {/,/^}/p; /^cardpatch() {/p; /^tested() {/,/} # <worktree>$/p; /^readyput() {/,/^}/p; /^testedhere() {/p; /^readysince() {/,/^}/p; /^bpid() {/,/^}/p; /^turnq() {/,/^}/p' "$SRC/lib/claim.sh")"
  packget() { printf -v "$2" 1; } # for turnq(): the test pack's landBatch, batches off
  eval "$(sed -n '/^declare -A ASKED_K/p; /^stdb() {/,/^}/p' "$SRC/lib/records.sh")"
  # shellcheck disable=SC2034 # read by stdb(), for the folder state.py is in
  local HERE=$SRC GIVEWAY=3 w
  ctl() { cat "$ST/control.json"; }
  cl() { (cd "$R" && STATE=$ST/cards.jsonl BRANCH=main claim "c$1-$1" "$CARDS/c$1-$1" $$); } # <issue>
  set7() { echo "{\"pid\":$$,\"paths\":[\"a.txt\"],$1}" > "$CARDS/c7-7.claim"; } # <the rest of #7's claim>
  pass() { echo "{\"issue\":$1}" > "$CARDS/c$1-$1.ready"; (cd "$R" && tested "$CARDS/c$1-$1") && jq -c --argjson s "$2" '.since = $s' "$CARDS/c$1-$1.ready" > "$STUB/r" && mv "$STUB/r" "$CARDS/c$1-$1.ready"; } # <issue> <since>
  order() { jq -c --argjson o "$1" '.order = $o' "$ST/control.json" > "$STUB/c" && mv "$STUB/c" "$ST/control.json"; } # <order json>
  set7 '"held":true'; pass 8 200
  echo '{"on":"c7-7","base":"'"$(git -C "$CARDS/c8-8" rev-parse HEAD)"'"}' > "$CARDS/c8-8.stack"
  w=$(cl 8) && [ "$(jq -r .on <<<"$w")" = c7-7 ] || fail "#8, tested on a stack's base, went past #7: $w"
  rm -f "$CARDS/c8-8.stack"; order '[7]'
  w=$(cl 8) && [ "$(jq -r .on <<<"$w")" = c7-7 ] || fail "#8, ready, went past the ordered #7: $w"
  order '[]'; pass 7 100; set7 '"held":true'
  w=$(cl 8) && [ "$(jq -r .on <<<"$w")" = c7-7 ] || fail "#8 went past #7, whose tests passed first: $w"
  rm -f "$CARDS/c7-7.ready"; set7 '"held":true'
  w=$(cl 8) && [ -z "$w" ] && [ "$(jq -c .held "$CARDS/c8-8.claim")" = true ] || fail "#8, ready, waited on #7, still in its tests: $w"
  [ "$(jq -c '[.passed, .fit]' "$CARDS/c7-7.claim")" = '[true,true]' ] || fail "#7 was not marked gone past by a ready card: $(cat "$CARDS/c7-7.claim")"
  w=$(cl 7) && [ "$(jq -r .on <<<"$w")" = c8-8 ] && [ "$(jq -c '[.held, .passed, .fit]' "$CARDS/c7-7.claim")" = '[false,true,true]' ] \
    || fail "#7 did not wait on #8 at its next claim, still marked fit: $w $(cat "$CARDS/c7-7.claim")"
  echo '{"card":"c8-8","issue":8,"step":"landed"}' >> "$ST/cards.jsonl"
  w=$(cl 7) && [ -z "$w" ] && [ "$(jq -c '[.held, .was]' "$CARDS/c7-7.claim")" = '[true,false]' ] \
    || fail "#7, gone past by a ready card only, did not claim once #8 landed, or is to be reviewed again for it: $w $(cat "$CARDS/c7-7.claim")"
  # Gone past by an ordered card, #7 is reviewed again, as before.
  sed -i '$d' "$ST/cards.jsonl"; rm -f "$CARDS/c8-8.ready"; set7 '"held":true'; order '[8]'
  w=$(cl 8) && [ -z "$w" ] && [ "$(jq -c '[.passed, .fit]' "$CARDS/c7-7.claim")" = '[true,null]' ] || fail "the ordered #8 did not go past #7, or marked it fit: $w $(cat "$CARDS/c7-7.claim")"
  echo '{"card":"c8-8","issue":8,"step":"landed"}' >> "$ST/cards.jsonl"
  w=$(cl 7) && [ "$(jq -c .was "$CARDS/c7-7.claim")" = true ] || fail "#7, gone past by the ordered #8, is not to be reviewed again: $(cat "$CARDS/c7-7.claim")"
  # Both wait, ready: #8, ready first, goes first, though #7 was picked first.
  sed -i '$d' "$ST/cards.jsonl"; order '[]'; pass 8 100; pass 7 200
  set7 '"held":false'; echo "{\"pid\":$$,\"paths\":[\"a.txt\"],\"held\":false}" > "$CARDS/c8-8.claim"
  w=$(cl 7) && [ "$(jq -r .on <<<"$w")" = c8-8 ] || fail "#7, ready after #8, did not wait on it: $w"
  w=$(cl 8) && [ -z "$w" ] || fail "#8, ready first, waited on #7: $w"
  # Bug (#400): #7, ready first, holds a.txt for its batch, its worktree lent to it (batch(): <worktree>.lent, its own
  # change in .bpatch, the batch's staged). #8, ready later, took that for #7 not ready, went past it and marked it
  # passed, and land() refused the batch.
  pass 7 100; pass 8 200; set7 '"held":true'; rm -f "$CARDS/c8-8.claim"
  git -C "$CARDS/c7-7" diff --cached --binary --no-renames > "$CARDS/c7-7.bpatch"; git -C "$CARDS/c7-7" rev-parse HEAD > "$CARDS/c7-7.lent"
  echo mate > "$CARDS/c7-7/z.txt"; git -C "$CARDS/c7-7" add -A
  # Main moves under the batch (its third line, in the context of #7's patch, apart from #8's change) and the lent
  # worktree's HEAD with it: #7's own change is read on the commit it was lent on, not on HEAD, where it does not apply.
  sed -i 3s/3/main/ "$R/a.txt"; git -C "$R" commit -qam "main moves under the batch"; git -C "$CARDS/c7-7" reset -q --soft main
  w=$(cl 8) && [ "$(jq -r .on <<<"$w")" = c7-7 ] && [ "$(jq -c .passed "$CARDS/c7-7.claim")" = null ] \
    || fail "#8, ready after #7, went past #7 while #7's batch ran: $w $(cat "$CARDS/c7-7.claim")"
}

# The fixture of batchreuse.test.sh (reusesetup): #7 and #8 change a.txt (#7 its first line, #8 a line at its end) and
# a file each, x.txt and y.txt; a.txt selects s.test, x.txt x.test, y.txt y.test. #7 holds a.txt first, and a product
# check holds it before its tests until #8, its tests passed, waits at its claim. #7's first tests end only once #8 has
# landed ($STUB/during then), is gone, or writes a wait at its claim after they began (its live record's `last`; the
# bug: #8 waits on #7, which waits in its tests on #8), so a change in who waits fails the cases rather than hanging
# them. No card is in the order list.
rfsetup() {
  reusesetup "[$(issue 7 2026-01-01),$(issue 8 2026-01-02)]" 'a.txt s.test' 'x.txt x.test' 'y.txt y.test'
  jq -c '.order = []' "$ST/control.json" > "$STUB/c.new" && mv "$STUB/c.new" "$ST/control.json"
  cat >> "$STUB/test-cmd" <<'EOF'
case $PWD in *-7) [ -e "$STUB/ran7" ] || { : > "$STUB/ran7"; s=$(date +%s); while [ -d "$STUB" ]; do
  jq -e 'select(.issue == 8 and .step == "landed")' "$ST/cards.jsonl" >/dev/null 2>&1 && { : > "$STUB/during"; break; }
  ls -d ../*-8 >/dev/null 2>&1 || break
  jq -e --argjson s "$s" '.waits.on and (.last | fromdate) > $s + 1' ../*-8.live >/dev/null 2>&1 && break; sleep 0.1; done; } ;; esac
EOF
}

# Bug: #8 passed its review and its tests, and waited on #7, picked first and still in its test step, until #7 landed.
# #8 lands while #7 is in its tests. #7 is then fitted onto main with #8's change (it applies there): it is not
# reviewed again, and it lands on its pass with no second run, though #8's landing touched s.test, one of its test files
# (the owner's pick, #1777). Bug it catches too: #7 ran s.test again before it landed.
t_readyfirst() {
  rfsetup
  # loop: only a whole run shows #8 landing while card() holds #7 in its tests, and #7 then landing on its pass
  out=$(loop run 2>&1) || fail "run exited non-zero: $out"
  [ -e "$STUB/during" ] && [ "$(st 'select(.step == "landed") | .issue' | tr '\n' ' ')" = "8 7 " ] \
    || fail "#8, ready, did not land while #7 was in its tests: $(st '"\(.issue) \(.step) \(.result)"' | tr '\n' ,) $(st 'select(.step == "blocked") | .reason')"
  [ "$(runs)" = "8 s1 y1 y2,7 s1 x1 x2," ] || fail "#7 ran its tests again after #8 landed on s.test, its test file: $(runs): $out"
  [ "$(st 'select(.step == "review") | "\(.issue) \(.result)"' | tr '\n' ,)" = "7 GO,8 GO," ] && [ -z "$(st 'select(.step == "fix") | .issue')" ] \
    || fail "#7 was reviewed again or brought onto main by a session, though its change applied there: $(st '"\(.issue) \(.step) \(.result)"' | tr '\n' ,)"
  [ "$(sed -n '1p;$p' "$R/a.txt" | tr '\n' ' ')" = "seven eight " ] && [ "$(cat "$R/x.txt" "$R/y.txt" | tr '\n' ' ')" = "x y " ] \
    && [ -z "$(ls "$T/$CASE/cards")" ] || fail "main does not hold both changes, or a worktree or mark is left: $(ls "$T/$CASE/cards")"
}

# Bug it catches too: the card a ready card went past, its change clashing with the one that landed, landed on a
# fit nobody reviewed. #7 and #8 both change line 20 of a.txt: #8 lands first, a session brings #7 onto main, and #7
# is reviewed again there, then tested and landed.
t_readyclash() {
  rfsetup
  cat > "$STUB/build" <<'EOF'
if grep -q '^# Landing conflict' "$STUB/brief"; then cp "$STUB/brief" "$STUB/fit.${PWD##*-}"; sed -i 20s/.*/seven/ a.txt; echo x > x.txt
else case $PWD in *-7) sed -i 20s/.*/seven/ a.txt; echo x > x.txt ;; *) sed -i 20s/.*/eight/ a.txt; echo y > y.txt ;; esac; fi
EOF
  echo 'case $PWD in *-7) [ ! -e "$STUB/during" ] || git -C "$R" log --format=%s > "$STUB/main-at-7" ;; esac' >> "$STUB/review-cmd"
  out=$(loop run 2>&1) || fail "run exited non-zero: $out"
  [ -e "$STUB/during" ] && [ "$(st 'select(.step == "landed") | .issue' | tr '\n' ' ')" = "8 7 " ] \
    || fail "#8, ready, did not land while #7 was in its tests: $(st '"\(.issue) \(.step) \(.result)"' | tr '\n' ,)"
  # The session is the landing's rebuild (step rebase), told the conflict: its tests ran on the change put back as it
  # was (settle(): caught).
  [ "$(st 'select(.issue == 7 and .step == "rebase") | .issue')" = 7 ] && grep -q 'rebase onto main conflicts' "$STUB/fit.7" \
    || fail "no session brought #7 onto main: $(st '"\(.issue) \(.step)"' | tr '\n' ,)"
  [ "$(st 'select(.step == "review") | "\(.issue) \(.result)"' | tr '\n' ,)" = "7 GO,8 GO,7 GO," ] && grep -q '^feat(product): title 8 (#8)' "$STUB/main-at-7" \
    || fail "#7 was not reviewed again on main with #8's change before it landed: $(st '"\(.issue) \(.step) \(.result)"' | tr '\n' ,)"
  [ "$(sed -n 20p "$R/a.txt")" = seven ] && [ -z "$(ls "$T/$CASE/cards")" ] || fail "#7 did not land its fitted change, or a worktree or mark is left: $(sed -n 20p "$R/a.txt"); $(ls "$T/$CASE/cards")"
}
