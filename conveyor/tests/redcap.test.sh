#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 300
# Engine cases: a main-red fix card takes one slot beyond the project's cap (run(): redfix()).
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"

# Issue 612. Bug it catches: a main-red fix card was picked only below the cap, so with every slot held by cards that
# wait for main to go green it never started, and nothing moved. Cap 1, #1 on the belt (its build holds until let go),
# #5 queued: one card holds every slot as well as two would (the cap is reached either way), without a second card's
# run. Two red main commits wait for their fix cards (issue 0, #597; the main-red record names them): at the next turn
# the first one's card starts in one slot beyond the cap, its picked line saying so for the Board, and no queued issue
# starts (D1); while it runs, the second commit's card waits as the others do (D2). The first lands;
# the second takes the slot beyond the cap in turn and fails its build at once; then #5 still waits (D3), and starts
# only once #1 ends: no slot beyond the cap is left over for it.
t_redcap() {
  local lp t red='select(.step == "picked") | if .mainRed then "red\(.mainRed[0:1])" else .issue end'
  setup "$(jq -cs . <(issue 1 2026-01-01 P1) <(issue 5 2026-01-05 P1))"
  echo "$GO" > "$STUB/review.1"; mkdir -p "$T/$CASE/cards"; loop control cap 1 >/dev/null || fail "cap 1 was refused"
  tune '.tunables.poll = 1'; watchturns
  # A fix card (its worktree ends -0) is labelled as a P0 bug: the first (its card id in building.0) adds a line to
  # a.txt, and main's red case (the run on main, mainrun-cmd) holds that a.txt has that line, so it fails on main's code
  # without the change and passes with it (bugproof.sh redproof()); the second fails its build at once. Any other build holds until
  # let go (go<n>), then fails. The case reads a.txt, not a.test.sh: main has its own stub a.test.sh (filemode), which
  # passes without the change, so the card would close as main no longer red. The second card's case (b.test) fails on
  # main always: with the first card landed, a.txt has its line, and a case passing on main closes its card before any build.
  echo "[ \"\${CONVEYOR_TEST_FILE:-}\" != b.test ] && [ \$(wc -l < a.txt) -ge $(($(wc -l < "$R/a.txt") + 1)) ]" > "$STUB/mainrun-cmd"
  echo 'n=${PWD##*-}; if [ "$n" = 0 ] && [ -e "$STUB/building.0" ] && [ "$(cat "$STUB/building.0")" != "${PWD##*/}" ]; then : > "$STUB/building.0b"; exit 1; fi
[ "$n" != 0 ] || [ -e "$STUB/building.0" ] || echo "${PWD##*/}" > "$STUB/building.0"; : >> "$STUB/building.$n"
while [ -d "$STUB" ] && [ ! -e "$STUB/go$n" ]; do sleep 0.1; done; [ "$n" = 0 ] || exit 1
echo two >> a.txt' > "$STUB/build"
  ( loop run > "$STUB/run.out" 2>&1 ) & lp=$!
  wait_until '[ -e "$STUB/building.1" ]' 'cat "$STUB/run.out"' || fail "#1 did not start: $(cat "$STUB/run.out")"
  jq -cn '{reds: [{sha: "1111111111111111111111111111111111111111", cases: [{case: "a.test: one", file: "a.test", by: "c1", files: [], last: ""}], card: null},
    {sha: "2222222222222222222222222222222222222222", cases: [{case: "b.test: two", file: "b.test", by: "c2", files: [], last: ""}], card: null}]}' > "$ST/mainred.json"
  t=$(grep -cxF "$R" "$TURNS")
  # The next turn: the first that reads the record. A turn counts as it starts its sleep: one already past its read
  # when the record was written, and the one after the pick, which may start before the pick is seen here, count too.
  wait_until "jq -e 'select(.step == \"picked\" and .mainRed)' \"\$ST/cards.jsonl\" >/dev/null" 'cat "$STUB/run.out"' \
    || fail "D1: the main-red fix card did not start with the cap reached: $(cat "$STUB/run.out")"
  [ $(($(grep -cxF "$R" "$TURNS") - t)) -le 2 ] || fail "D1: the main-red fix card started $(($(grep -cxF "$R" "$TURNS") - t)) turns after its commit was recorded, not at the next turn"
  wait_until '[ -e "$STUB/building.0" ]' 'cat "$STUB/run.out"' || fail "D1: the main-red fix card did not build: $(cat "$STUB/run.out")"
  turns 2 # each would have picked the second fix card or #5 had it taken a slot
  [ "$(st "$red" | tr '\n' ' ')" = "1 red1 " ] \
    || fail "D1, D2: beside the fix card in the slot beyond the cap, another card started: $(st "$red" | tr '\n' ' ')"
  [ "$(st 'select(.step == "picked") | .beyond' | tr '\n' ' ')" = "null main is red " ] \
    || fail "the fix card's picked line does not say it took a slot beyond the cap: $(st 'select(.step == "picked") | .beyond' | tr '\n' ' ')"
  [ "$(loop snapshot --fresh | jq -c '[.belt[] | [.issue, .beyond]]')" = '[[1,null],[0,"main is red"]]' ] \
    || fail "the snapshot's belt does not carry the slot beyond the cap: $(loop snapshot --fresh | jq -c '[.belt[] | [.issue, .beyond]]')"
  : > "$STUB/go0"
  wait_until "[ \"\$(st 'select(.step == \"landed\" or .step == \"blocked\") | \"\\(.card[-1:]) \\(.step)\"' | tr '\n' ,)\" = '0 landed,0 blocked,' ]" 'cat "$STUB/run.out"' \
    || fail "the first fix card did not land, then the second take the slot beyond the cap and block: $(st '"\(.card) \(.step) \(.reason)"' | tr '\n' ,)"
  [ -e "$STUB/building.0b" ] || fail "the second fix card did not build: $(st '"\(.card) \(.step) \(.reason)"' | tr '\n' ,)"
  [ "$(st "$red" | tr '\n' ' ')" = "1 red1 red2 " ] && [ "$(st 'select(.step == "picked") | .beyond' | tail -n 1)" = "main is red" ] \
    || fail "the second fix card did not take the slot beyond the cap: $(st "$red" | tr '\n' ' ')"
  turns 2
  [ -z "$(st 'select(.issue == 5 and .step == "picked") | .card')" ] || fail "D3: #5 started after the fix landed, with the capped card still on the belt"
  : > "$STUB/go1"
  wait_until '[ -e "$STUB/building.5" ]' 'cat "$STUB/run.out"' || fail "D3: #5 did not start once #1 ended: $(cat "$STUB/run.out")"
  [ "$(st 'select(.step == "picked" or (.step == "blocked" and .issue == 1)) | "\(.issue) \(.step)"' | tail -n 2 | tr '\n' ,)" = "1 blocked,5 picked," ] \
    || fail "D3: #5 was not picked after #1 ended: $(st '"\(.issue) \(.step)"' | tr '\n' ,)"
  [ "$(st 'select(.issue == 5 and .step == "picked") | .beyond')" = null ] || fail "#5 was marked as taking a slot beyond the cap"
  : > "$STUB/go5"
  wait "$lp" || fail "run exited non-zero: $(cat "$STUB/run.out")"
  loop check || fail "the record check refuses a picked line with its slot beyond the cap"
}

# Issue 1688. Bug it catches: redfix() gave the loop no fix card while one of its own cards was a main-red fix card,
# even when that card waited itself for main to change on another entry. With every slot waiting, the fix for that
# entry never started and the whole belt stood. Fix card cfix (entry of 1111) is in flight; entries 0000 (older) and
# 2222 have no card. While cfix builds, redfix() names nothing (one fix card at a time, issue 612); once cfix waits for
# main on 2222's case, it names 2222, not the older 0000 (review E1: the pick took the oldest entry, a fix that does
# not end the wait), and the loop's pick turn at the cap (turnpick(), with run()'s variables as t_locklimit sets
# them; cardrun() only says) starts the fix card of 2222. The wait is the real mainwait(), run in the background until
# its live record is written: a hand-written record would not show that mainwait() marks the wait that redfix() reads.
t_redfixwaiting() {
  setup "[$(issue 7 2026-01-01)]"
  local s; s=$(git -C "$R" rev-parse HEAD)
  mkdir -p "$T/$CASE/cards/cfix"
  jq -cn '{reds: [{sha: "1111111111111111111111111111111111111111", cases: [{case: "a.test: one", file: "a.test", by: "c1", files: [], last: ""}], card: "cfix"},
    {sha: "0000000000000000000000000000000000000000", cases: [{case: "c.test: three", file: "c.test", by: "c3", files: [], last: ""}], card: null},
    {sha: "2222222222222222222222222222222222222222", cases: [{case: "b.test: two", file: "b.test", by: "c2", files: [], last: ""}], card: null}]}' > "$ST/mainred.json"
  fx_in 'cd "$R" || exit 8; append "$(line cfix 0 picked ok "{\"mainRed\": \"1111111111111111111111111111111111111111\"}")" || exit 8
    cardrun() { echo "started: issue $2"; }
    asking=1 urgent="" building=1 cap=1 left=5 pct="" running=0 serve=1 pusher="" started=0 waits="" ctl=$(ctl) issues=$(cat "$STUB/issues.json")
    declare -A mine=()
    echo "building: $(redfix cfix)"; mainwait "$CARDS/cfix" '"$s"' "b.test: two" & p=$!
    wait_until "[ -s \"\$CARDS/cfix.live\" ]" || echo "mainwait wrote no live record"
    red=$(redfix cfix); echo "waiting: $red"; kill "$p"
    turnpick; wait'
  [ "$(cat "$T/$CASE/run.out")" = $'building: \nwaiting: 2222222222222222222222222222222222222222\nstarted: issue 0' ] \
    || fail "redfix cfix, with fix card cfix building and then waiting for main on b.test: two (entry 2222, no card; older entry 0000 no card), then the pick turn: not nothing, then 2222, then a start: $(cat "$T/$CASE/run.out")"
  [ "$(st 'select(.step == "picked") | .mainRed' | tr '\n' ' ')" = "1111111111111111111111111111111111111111 2222222222222222222222222222222222222222 " ] \
    || fail "the pick turn at the cap, with cfix waiting on entry 2222 and red=2222, did not start the fix card of 2222: $(st 'select(.step == "picked") | .mainRed' | tr '\n' ' ')"
}

# Issue 1813. Bug it catches: with the cap filled by a card waiting for main on a red commit (entry 2222, no card yet),
# its fix card never started until a card was shut by hand: redfix() named the oldest entry whose card had no line in
# the card records, here 0000, whose fix card landed and whose lines went to the archive (the ended list). redpick()
# reads that list too, so it picked nothing for 0000, and 2222 waited for a slot under the cap that never came. Cap 1,
# held by c7 waiting in the real mainwait() (run in the background until its live record is written, as in
# t_redfixwaiting, and still waiting through the pick); the turn's red is redfix() of the loop's cards, as turnask()
# asks it, then the pick turn (turnpick(); cardrun() only says) starts the fix card of 2222 beyond the cap.
t_redfixarchived() {
  setup "[$(issue 7 2026-01-01)]"
  local s; s=$(git -C "$R" rev-parse HEAD)
  mkdir -p "$T/$CASE/cards/c7"
  jq -cn '{reds: [{sha: "0000000000000000000000000000000000000000", cases: [{case: "c.test: three", file: "c.test", by: "c3", files: [], last: ""}], card: "cold"},
    {sha: "2222222222222222222222222222222222222222", cases: [{case: "b.test: two", file: "b.test", by: "c7", files: [], last: ""}], card: null}]}' > "$ST/mainred.json"
  fx_in 'cd "$R" || exit 8; mkdir -p "${ENDED%/*}" && { line cold 0 picked ok "{\"mainRed\": \"0000000000000000000000000000000000000000\"}"; line cold 0 landed ok; } > "$ENDED" || exit 8
    cardrun() { echo "started: issue $2"; }
    asking=1 urgent="" building=1 cap=1 left=5 pct="" running=0 serve=1 pusher="" started=0 waits="" ctl=$(ctl) issues=$(cat "$STUB/issues.json")
    mainwait "$CARDS/c7" '"$s"' "b.test: two" & p=$!; declare -A mine=([$p]="c7 7")
    wait_until "[ -s \"\$CARDS/c7.live\" ]" || echo "mainwait wrote no live record"
    red=$(redfix "$(for k in "${!mine[@]}"; do echo "${mine[$k]% *}"; done)"); echo "red: $red"
    turnpick; kill "$p"; wait'
  [ "$(cat "$T/$CASE/run.out")" = $'red: 2222222222222222222222222222222222222222\nstarted: issue 0' ] \
    || fail "redfix c7 with c7 waiting for main on b.test: two at the cap (entry 0000: card cold, landed, its lines in the ended list; entry 2222: no card), then the pick turn: not red 2222, then a start: $(cat "$T/$CASE/run.out")"
  [ "$(st 'select(.step == "picked") | "\(.mainRed) \(.beyond)"')" = "2222222222222222222222222222222222222222 main is red" ] \
    || fail "the pick turn at the cap, with c7 waiting on entry 2222 and 0000's card archived, did not start the fix card of 2222 beyond the cap: $(st 'select(.step == "picked") | "\(.mainRed) \(.beyond)"')"
}

# Issue 1813 (D1). Bug it catches: the Foreman's fix for a red main is a Tests page card ($TACARDS, no main-red record
# entry), and the pick beyond the cap took only redfix()'s entries, so with every slot held by cards waiting for main
# that card sat in the queue until a card was shut by hand. Cap 2, held by c7 and c8 in the real mainwait() on
# b.test (as in t_redfixwaiting), both still waiting through the pick. Queued: a released card about z.test (older, so
# a pick that ignored the file would take it) and the fix card about b.test, held for the owner, then released as
# `control release` does. The turn's redtests() of the loop's cards, as turnask() asks it, then the pick turn
# (turnpick(); cardrun() only says) starts the b.test card beyond the cap, and not the z.test one.
t_redtestsfull() {
  setup "[$(issue 7 2026-01-01)]"
  local s; s=$(git -C "$R" rev-parse HEAD)
  mkdir -p "$T/$CASE/cards"; echo '{"reds": []}' > "$ST/mainred.json"
  fx_in 'cd "$R" || exit 8
    cardrun() { echo "started: issue $2"; }
    asking=1 urgent="" building=2 cap=2 left=5 pct="" running=0 serve=1 pusher="" started=0 waits="" ctl=$(ctl) issues=$(cat "$STUB/issues.json")
    tcadd z.test "Tests page: z.test" "z body" "" > /dev/null || exit 8; id=$(tcadd b.test "Tests page: b.test" "b body" held) || exit 8
    mainwait "$CARDS/c7" '"$s"' "b.test: two" & p7=$!; mainwait "$CARDS/c8" '"$s"' "b.test: two" & p8=$!; declare -A mine=([$p7]="c7 7" [$p8]="c8 8")
    wait_until "[ -s \"\$CARDS/c7.live\" ] && [ -s \"\$CARDS/c8.live\" ]" || echo "mainwait wrote no live record"
    own=$(for k in "${!mine[@]}"; do echo "${mine[$k]% *}"; done)
    red=$(redfix "$own"); redtc=$(redtests "$own"); echo "held: [$red] [$redtc]"
    . "$HERE/lib/testcardact.sh" && testcardact release "$id" > /dev/null || echo "release failed"; redtc=$(redtests "$own"); echo "released: $redtc"
    turnpick; echo "z.test card: $(jq -r ".cards[] | select(.file == \"z.test\") | .card" "$TACARDS")"; kill "$p7" "$p8"; wait'
  [ "$(cat "$T/$CASE/run.out")" = $'held: [] []\nreleased: ["b.test"]\nstarted: issue 0\nz.test card: null' ] \
    || fail "cap 2 held by c7 and c8 waiting for main on b.test: two, queued a released z.test card and a held b.test card, then b.test released, then the pick turn: not nothing while held, b.test once released, one start, z.test not picked: $(cat "$T/$CASE/run.out")"
  [ "$(st 'select(.step == "picked") | "\(.testFile) \(.beyond)"')" = "b.test main is red" ] \
    || fail "the pick turn at the cap did not start the b.test Tests page card beyond the cap: $(st 'select(.step == "picked") | "\(.testFile) \(.beyond)"')"
}

# Issue 1581. Bug it catches: the turn gave jq the open list, bodies and all, as one argument; over 128 KiB Linux
# refuses it, jq never started, and no seat account of an open issue was asked for while a seat was at the guard.
# Here #13 has a 140 KiB body; the record keeps seats for #7 (open) and #8 (not open), so only 7 is named.
t_seatissuesbig() {
  setup "[$(issue 7 2026-11-01), $(issue 13 2026-11-04)]"
  jq -c 'map(if .number == 13 then .body = ("x" * 143360) else . end)' "$STUB/issues.json" > "$STUB/i.new" && mv "$STUB/i.new" "$STUB/issues.json"
  [ "$(wc -c < "$STUB/issues.json")" -gt 131072 ] || fail "the open list over 128 KiB was not made"
  fx_in 'seatissues "{\"cards\": {\"7\": {}, \"8\": {}}}" "$(asked)"'
  [ "$RC" = 0 ] && [ "$(cat "$T/$CASE/run.out")" = 7 ] || fail "with the open list over 128 KiB, the seats of open #7 were not named (exit $RC): $(cat "$T/$CASE/run.out")"
}

# Issue 1569. Bug it catches: turnask() gave the open list, bodies and all, to the seat lookup as one argument; over
# 128 KiB (here #13's 140 KiB body) jq did not start, and the turn never asked for the account of #10's own reviewer,
# so pick saw no reading of it. #10's reviewer is Claude on the second account (95 %), the project's is Codex: only the
# seat lookup reads that account, so a reading of it in the limit record shows turnask() asked for #10's seat. The
# turn is called whole (turnask() through guardread), not seatissues() alone, which t_seatissuesbig covers. The setup
# is reviewacctsetup's (reviewacct.test.sh): the runner sources every case file before it runs a case.
t_turnaskbig() {
  reviewacctsetup "[$(issue 10 2026-01-04), $(issue 13 2026-01-05)]"
  ctl reviewer default >/dev/null; ctl review-account second >/dev/null; ctl card 10 reviewer claude-sonnet-5-5 >/dev/null
  jq -c 'map(if .number == 13 then .body = ("x" * 143360) else . end)' "$STUB/issues.json" > "$STUB/i.new" && mv "$STUB/i.new" "$STUB/issues.json"
  [ "$(wc -c < "$STUB/issues.json")" -gt 131072 ] || fail "the open list over 128 KiB was not made"
  fx_in 'declare -A shuts=() mine=(); cap=1 building=0 now=running inuse=0 running=0 sampled=$SECONDS old= nopack= nocli= mhold= guard=1 waits= issues= ctl=$(ctl)
    turnask >/dev/null 2>&1; echo "${#issues}"; ACCT=second lastread | jq -r .pct'
  [ "$RC" = 0 ] && [ "$(tail -n 1 "$T/$CASE/run.out")" = 95 ] && [ "$(sed -n '$!p' "$T/$CASE/run.out" | tail -n 1)" -gt 131072 ] \
    || fail "turnask() with an open list over 128 KiB did not ask for the seat of #10 (exit $RC): $(tail -c 400 "$T/$CASE/run.out")"
}
