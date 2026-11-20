#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 300
# Engine cases: the land turn through the real loop with two cards: a holder gives way, and the other card lands meanwhile.
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"

# The two cases below run two cards through the real loop (loop run): a direct check of giveway(), claim() or land()
# shows each part, but only card() and settle() join them (a holder gives way before its rebase or fix session, and the
# other card claims, is tested and lands while that session runs), and only a run of both cards shows that join.
# The stubs meet at named pipes in $STUB (gwpipes). `hear <pipe>` waits for one line on it, 100 s at most, so a run
# where the engine never gets there fails what the case checks and does not hang; `listen <pipe>` opens it, and
# `heard` waits so, for a reader that must be open before the writer can come. `say <pipe>` gives the pipe its line
# and goes on at once: a process of its own waits for the reader, 100 s at most, as a writer left waiting holds the
# loop's output open. `tell <pipe>` writes with no wait, to a reader that listened first (with none, the line is lost).
# Main's pre-commit hook, which land() runs just before it lands, does <say|tell> landed8 when it lands #8.
# No stub polls a file.
gwpipes() { # <say|tell> <pipe>...
  local p
  for p in "${@:2}"; do mkfifo "$STUB/$p" || fail "the pipe $p could not be made"; done
  # say's writer closes the engine's lock (fd 8) and fd 9, which it must not hold while it waits.
  cat > "$STUB/pipes.sh" <<'EOF'
say() { ( timeout 100 bash -c 'echo go > "$1"' _ "$STUB/$1" ) > /dev/null 2>&1 < /dev/null 8>&- 9>&- & }
tell() { echo go 1<> "$STUB/$1"; }
hear() { local l; read -r -t 100 l <> "$STUB/$1"; }
listen() { exec {LISTEN}<> "$STUB/$1"; }
heard() { local l; read -r -t 100 l <&"$LISTEN"; }
EOF
  printf '#!/usr/bin/env bash\ncase $GIT_INDEX_FILE in *-8.index) STUB=%q; . "$STUB/pipes.sh"; %s landed8 ;; esac\n' "$STUB" "$1" > "$R/.git/hooks/pre-commit"
  chmod +x "$R/.git/hooks/pre-commit"
}
# Ends any writer still waiting (a run where its reader gave up): it opens each pipe and closes it.
gwfree() { local p; for p in "$@"; do : <> "$STUB/$p"; done; } # <pipe>...

# Bug it catches: a card took its land turn and kept it through its rebase session (card.sh: the give-way before the
# rebuild), so a card that shares its files and is ready waited the whole session. #7 changes a.txt's line 8 and
# appends seven; its first tests change main's last line, so its landing conflicts and it is rebuilt. #8 changes line 1
# and line 8 (it clashes with #7's change) and is built only once #7's rebase session has begun (go8). That session waits
# for #8's landing (landed8): #8 claims a.txt, is tested and lands during it; the session then appends seven on main as
# it was at the rebase, and #7 is fitted onto #8's main and lands. Main has both changes.
t_givewayrebase() {
  local out rc
  setup "[$(issue 7 2026-01-01),$(issue 8 2026-01-02)]"; for i in $(seq 8); do echo "$GO" > "$STUB/review.$i"; done
  seq 20 > "$R/a.txt"; git -C "$R" commit -qam "a longer a.txt"
  # The rebase session listens on landed8 before it lets #8 be built: #8 cannot land before it listens (tell).
  gwpipes tell go8 landed8
  cat > "$STUB/build" <<'EOF'
. "$STUB/pipes.sh"
if grep -q '^# Landing conflict' "$STUB/brief" && [ "${PWD##*-}" = 7 ]; then
  listen landed8; say go8; ! heard || : > "$STUB/heard8"; cp "$PWD.claim" "$STUB/rebaseclaim"; echo seven >> a.txt
elif grep -q '^# Main moved' "$STUB/brief"; then sed -i '1s/.*/eight/;8s/.*/eight-8/' a.txt
else case $PWD in
  *-7) echo seven >> a.txt; sed -i 8s/.*/seven-8/ a.txt ;;
  *) hear go8; sed -i '1s/.*/eight/;8s/.*/eight-8/' a.txt ;;
esac; fi
EOF
  { echo 'case $PWD in *-7) [ -e "$STUB/moved" ] || { : > "$STUB/moved"; sed -i 20s/.*/twenty/ "$R/a.txt"; git -C "$R" commit -qnam "main changes the last line"; } ;; esac'
    cat "$STUB/test-cmd"; } > "$STUB/test-cmd.new" && mv "$STUB/test-cmd.new" "$STUB/test-cmd"
  out=$(loop run 2>&1); rc=$?; gwfree go8 landed8; [ $rc = 0 ] || fail "run exited $rc: $out"
  [ -e "$STUB/heard8" ] && [ "$(st 'select(.step == "landed") | .issue' | tr '\n' ' ')" = "8 7 " ] \
    || fail "#8 did not land during #7's rebase session, before #7: $(st '"\(.issue) \(.step) \(.result) \(.reason)"' | tr '\n' ,)"
  [ "$(jq -c '[.held, .away, .to]' "$STUB/rebaseclaim" 2>/dev/null)" = '[false,true,8]' ] \
    || fail "#7 did not give way for its rebase, or does not name #8: $(cat "$STUB/rebaseclaim" 2>/dev/null)"
  [ "$(sed -n '1p;8p;20p;21p' "$R/a.txt" | tr '\n' ' ')" = "eight eight-8 twenty seven " ] && [ "$(wc -l < "$R/a.txt")" -eq 21 ] \
    || fail "main does not hold #8's change, main's own and #7's as rebuilt: $(cat "$R/a.txt")"
  [ "$(st "select(.issue == 7 and $NOMARK) | .step" | tr '\n' ' ')" = "picked worktree brief build review test rebase review test test landed " ] \
    || fail "steps of #7: $(st "select(.issue == 7) | .step" | tr '\n' ' ')"
}

# Bug it catches: a card stacked on another (stackto()) whose checks or tests failed there, on the other card's change,
# was sent to a fix of its own (claim(): stackred), or waited on that card through its fix (card(): the give-way for
# the fix of failed tests). #7 changes a.txt's first and last lines and adds `broken`, which fails the tests. #8,
# built once #7 holds a.txt (go8), appends eight, which does not apply with #7's last line: it waits on #7 and is stacked
# on it (the control record's order, #8 then #7, lets it be stacked on #7 before #7's tests pass), and its tests there
# fail on `broken` (red8). Only then do #7's first tests end, failing. #7's fix session waits for #8's landing
# (landed8): #8 is brought onto main alone, reviewed and tested there, and lands alone during it. The fix then removes
# `broken` and puts the last line back, and #7 lands on #8's main. The mark (settle(): stackred) is what keeps #8 from
# running its tests on #7's stack again: #7's tests wait up to 2 s on again8, which #8's tests say when a second run
# of them starts there (again8.seen; the run again of the failed cases within one run, <worktree>.first, is not one),
# so without the mark #8 runs them again before #7 gives way.
t_givewaystackred() {
  local out rc c7 c8
  setup "[$(issue 7 2026-01-01),$(issue 8 2026-01-02)]"; tune '.landBatch = 8'; for i in $(seq 10); do echo "$GO" > "$STUB/review.$i"; done
  jq -c '.order = [8, 7]' "$ST/control.json" > "$STUB/c.new" && mv "$STUB/c.new" "$ST/control.json"
  seq 20 > "$R/a.txt"; git -C "$R" commit -qam "a longer a.txt"
  # #7's first tests listen on red8 before they let #8 be built (tell); #8 can land before #7's fix session opens
  # landed8 (#7 gives way just before it), so the hook says it.
  gwpipes say go8 red8 landed8 again8
  cat > "$STUB/build" <<'EOF'
. "$STUB/pipes.sh"
if grep -q '^# The changed tests fail' "$STUB/brief"; then
  [ "${PWD##*-}" != 7 ] || { ! hear landed8 || : > "$STUB/heard8"; }; rm -f broken; sed -i 20s/.*/20/ a.txt
else case $PWD in
  *-7) sed -i '1s/.*/seven/;20s/.*/seven-20/' a.txt; : > broken ;;
  *) grep -q '^# Stacked\|^# Main moved' "$STUB/brief" || hear go8; echo eight >> a.txt ;;
esac; fi
EOF
  { echo 'case $PWD in *-7) [ -e "$STUB/said7" ] || { : > "$STUB/said7"; . "$STUB/pipes.sh"; exec {AG}<> "$STUB/again8"; listen red8; say go8; heard; read -r -t 2 l <&"$AG"; } ;;'
    echo '  *-8) [ ! -e broken ] || [ -e "$PWD.first" ] || { . "$STUB/pipes.sh"; if [ -e "$STUB/said8" ]; then : > "$STUB/again8.seen"; tell again8; else : > "$STUB/said8"; tell red8; fi; } ;; esac'
    cat "$STUB/test-cmd"; echo '[ ! -e broken ] || { echo "FAIL broken.test"; exit 1; }'; } > "$STUB/test-cmd.new" && mv "$STUB/test-cmd.new" "$STUB/test-cmd"
  out=$(loop run 2>&1); rc=$?; gwfree go8 red8 landed8 again8; [ $rc = 0 ] || fail "run exited $rc: $out"
  c7=$(st 'select(.issue == 7 and .step == "picked") | .card'); c8=$(st 'select(.issue == 8 and .step == "picked") | .card')
  grep -q "card $c8 is stacked on card $c7" <<<"$out" && grep -q "card $c8: its checks or tests failed on main with the change of card $c7" <<<"$out" \
    || fail "#8 was not stacked on #7, or its tests there did not fail on #7's change: $out"
  [ ! -e "$STUB/again8.seen" ] || fail "#8 was not marked stackred: it ran its tests again on #7's stack: $out"
  [ -e "$STUB/heard8" ] && [ "$(st 'select(.step == "landed") | .issue' | tr '\n' ' ')" = "8 7 " ] \
    || fail "#8 did not land during #7's fix session, before #7: $(st '"\(.issue) \(.step) \(.result) \(.reason)"' | tr '\n' ,)"
  [ "$(st 'select(.issue == 8 and .step == "fix") | .reason' | cut -c1-14 | tr '\n' ,)" = "stacked on car,main moved sin," ] \
    && [ -z "$(st 'select(.issue == 8 and .step == "test" and .result == "fail")')" ] && [ "$(st 'select(.issue == 8 and .step == "landed") | .batch')" = null ] \
    || fail "#8 was not brought onto main alone after its stack, or was sent to a fix for #7's failure, or did not land alone: $(st 'select(.issue == 8) | "\(.step) \(.result) \(.reason)"' | tr '\n' ,)"
  [ "$(st "select(.issue == 8 and $NOMARK) | .step" | tr '\n' ' ' | sed 's/.* fix //')" = "review test landed " ] \
    || fail "#8 was not reviewed and tested on main alone before it landed: $(st "select(.issue == 8) | .step" | tr '\n' ' ')"
  [ "$(sed -n '1p;$p' "$R/a.txt" | tr '\n' ' ')" = "seven eight " ] && [ ! -e "$R/broken" ] || fail "main does not hold both changes, #7's as fixed: $(cat "$R/a.txt"; ls "$R")"
}
