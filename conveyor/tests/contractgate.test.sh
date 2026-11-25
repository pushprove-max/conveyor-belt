#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 240
# Engine cases: the persisted-contract check before a card lands (conveyor/lib/contract.sh): at the landing gate
# (contractgate(), in cardtest()), for a card that waits to land in a batch (contractwait(), in settle()) and on each
# commit that lands (landone(), lib/claim.sh). It runs
# adversarial-review-gate.sh --contract-range on the card's change when main's pre-push hook runs that check, so a
# change that hook refuses does not land.
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"
# The engine folder, as lib.sh sets it: named here too, so the release closure (tools/closure.sh) follows this file's paths.
SRC=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)

# Main ($R, setup with <issues json>) holds a persisted-contract writer, src/repositories/widget-repository.ts, with a
# reader and a writer export, pushed. Its pre-push hook runs the check on each pushed range from the installed Conveyor
# (this engine's .claude/hooks/adversarial-review-gate.sh, or <checker>): main holds no copy of it, as in a project that
# loads it so. <checker> 0 leaves the hook out.
contractmain() { # <issues json> [<checker>]
  setup "$1"
  mkdir -p "$R/src/repositories" && printf '%s\n' 'export function readWidget(id) {' '  return id;' '}' 'export function saveWidget(id) {' '  return id;' '}' > "$R/src/repositories/widget-repository.ts" \
    && git -C "$R" add -A && git -C "$R" commit -qm 'the writer' && git -C "$R" push -q origin main || fail "main's writer"
  [ "${2:-}" = 0 ] && return
  printf '%s\n' '#!/usr/bin/env bash' 'z=0000000000000000000000000000000000000000' \
    "while read -r _ l _ r; do [ \"\$r\" = \"\$z\" ] || bash '${2:-$SRC/../.claude/hooks/adversarial-review-gate.sh}' --contract-range \"\$r\" \"\$l\" || exit 1; done" \
    > "$R/.git/hooks/pre-push" && chmod +x "$R/.git/hooks/pre-push" || fail "main's pre-push hook"
}
# A change that adds the writer saveGadget to widget-repository.ts.
GADGET='printf "%s\n" "export function saveGadget(id) {" "  return id;" "}" >> src/repositories/widget-repository.ts'
# A changed test that names the writer saveGadget and the reader readWidget.
COVER='mkdir -p src/repositories/__tests__ && echo "readWidget saveGadget" > src/repositories/__tests__/widget.test.ts'
MSG='BLOCKED: persisted-contract writer src/repositories/widget-repository.ts needs one changed test that names both it and a changed reader.'
# Card #7's sessions: its build runs <build>; a contract fix session (CONTRACTFIX's heading in its brief) keeps its
# brief from that heading on in $STUB/fixbrief (not the findings an earlier round carried) and its BLOCKED line in
# $STUB/fixed, then runs <fix> (default: it changes a.txt only, so the check refuses the change again). Its reviews
# are GO. card() runs the card to its landing or block.
contractcard() { # <build> [<fix>]
  contractmain "[$(issue 7 2026-01-01)]"
  printf '%s\n' "if grep -q '^# Persisted-contract check' \"\$STUB/brief\"; then sed -n '/^# Persisted-contract check/,\$p' \"\$STUB/brief\" > \"\$STUB/fixbrief\"; grep -m 1 'BLOCKED:' \"\$STUB/fixbrief\" >> \"\$STUB/fixed\"; ${2:-echo fixed >> a.txt}; else $1; fi" > "$STUB/build"
  for i in 1 2 3 4 5 6; do echo "$GO" > "$STUB/review.$i"; done
  rulecard 7
}

# #1668, Done-when 1. Bug: the check ran only at push, so a card whose change edits a contract writer with no test naming
# writer and reader landed, and main then held a commit it could not push. The card does not land: its fix session
# gets the check's message as the finding to fix, and a refusal after that fix blocks it with the message, which names
# the writer.
t_contractlandrefused() {
  contractcard "$GADGET"
  grep -qF "$MSG" "$STUB/fixbrief" 2>/dev/null || fail "the fix session did not get the check's message (change: $GADGET): $(cat "$STUB/fixbrief" 2>&1)"
  [ -z "$(st 'select(.step == "landed")')" ] && ! grep -q saveGadget "$R/src/repositories/widget-repository.ts" \
    || fail "the change with no covering test landed (change: $GADGET): $(st 'select(.step == "landed")')"
  st 'select(.step == "blocked") | .reason' | grep -qF "$MSG" && [[ $(st 'select(.step == "blocked") | .reason') == 'contract: the persisted-contract check still refuses the change after its fix session; nothing landed'* ]] \
    || fail "the card was not blocked with the check's message after its fix (change: $GADGET): $(st 'select(.step == "blocked") | .reason')"
}
# #1668, Done-when 2. Bug it catches: a gate that refuses every writer change. With a changed test naming the writer and
# its reader, the card lands with no contract fix session.
t_contractlandcovered() {
  contractcard "$GADGET; $COVER"
  [ -n "$(st 'select(.step == "landed") | .sha')" ] && grep -q saveGadget "$R/src/repositories/widget-repository.ts" && [ ! -e "$STUB/fixbrief" ] \
    || fail "the change with a covering test did not land, or got a contract fix (change: $GADGET; $COVER): $(st 'select(.step | IN("blocked", "landed")) | "\(.step) \(.reason)"')"
}
# Bug it catches: the check stops at the first writer with no covering test, so a change with two such writers names
# the second only after the first is fixed; a gate that gives one fix session in all blocked the card then, though its
# fix did what it was asked. Each fix session covers the writer its brief names: the card gets two, and lands.
t_contracttwowriters() {
  local sprocket='printf "%s\n" "export function readSprocket(id) {" "  return id;" "}" "export function saveSprocket(id) {" "  return id;" "}" > src/repositories/sprocket-repository.ts'
  local scover='mkdir -p src/repositories/__tests__ && echo "readSprocket saveSprocket" > src/repositories/__tests__/sprocket.test.ts'
  contractcard "$GADGET; $sprocket" "if grep -q 'sprocket-repository.ts needs' \"\$STUB/fixbrief\"; then $scover; else $COVER; fi"
  local want=$'BLOCKED: persisted-contract writer src/repositories/sprocket-repository.ts needs one changed test that names both it and a changed reader.\n'$MSG
  [ "$(cat "$STUB/fixed" 2>&1)" = "$want" ] \
    || fail "the fix sessions were not given the two writers, one each (change: $GADGET; $sprocket): $(cat "$STUB/fixed" 2>&1)"
  [ -n "$(st 'select(.step == "landed") | .sha')" ] && grep -q saveGadget "$R/src/repositories/widget-repository.ts" \
    || fail "the card whose two fix sessions covered both writers did not land (change: $GADGET; $sprocket): $(st 'select(.step | IN("blocked", "landed")) | "\(.step) \(.reason)"')"
}

# Bug it catches: the gate ran a checker other than the one Git runs at push, so a change the push refuses could land:
# a copy in main's checkout, or this engine's own, while the project's engine is another install. With the pack pinned
# to a commit whose install's checker refuses, main's pre-push hook loading that install's checker, and passing copies
# in main's checkout and in this engine, the gate's check is that install's, and a push of the same change gets the
# same refusal: the gate and the push run one checker.
t_contractpinned() {
  local c=0123456789abcdef0123456789abcdef01234567
  contractmain '[]' "$T/$CASE/versions/$c/.claude/hooks/adversarial-review-gate.sh"
  tune --arg c "$c" '.plugin.commit = $c'
  mkdir -p "$T/$CASE/versions/$c/.claude/hooks" "$R/.claude/hooks" \
    && printf '%s\n' 'echo "BLOCKED: the pinned install checked this" >&2; exit 2' > "$T/$CASE/versions/$c/.claude/hooks/adversarial-review-gate.sh" \
    && echo 'exit 0' > "$R/.claude/hooks/adversarial-review-gate.sh" || fail "the checkers"
  FXWT=$T/$CASE/cards/c7; git -C "$R" worktree add -q --detach "$FXWT" && (cd "$FXWT" && eval "$GADGET; $COVER") && git -C "$FXWT" add -A || fail "the card's change"
  # shellcheck disable=SC2016 # expanded in fx_in's shell
  fx_in 'VERSIONS=$T/$CASE/versions; contractrun "$FXWT"; echo "rc=$? $CONTRACT_OUT"'
  grep -qx 'rc=2 BLOCKED: the pinned install checked this' "$T/$CASE/run.out" \
    || fail "the gate did not run the pinned install's checker on the change ($GADGET; $COVER): $(cat "$T/$CASE/run.out")"
  local push
  git -C "$FXWT" commit -qm 'the change' || fail "the card's commit"
  push=$(git -C "$FXWT" push origin HEAD:main 2>&1) && fail "the push of the change ($GADGET; $COVER) was not refused: $push"
  grep -qx 'BLOCKED: the pinned install checked this' <<<"$push" \
    || fail "the push of the change ($GADGET; $COVER) did not run the gate's checker, the pinned install's: $push"
}

# Bug it catches: with batches on, a card that waits to land runs its checks and tests and is marked tested, so a batch
# lands it with no landing gate, and the check never runs on its change. Card #8 (its change: GADGET) waits on #7, which
# changes the same file, in settle() as card() calls it. It runs no test, and its <worktree>.ready is gone, so no batch
# takes it. Each look of the wait sleeps: here sleep() counts the looks and the third ends the call (exit 8).
t_contractwait() {
  contractmain '[]'
  echo 'echo test >> "$STUB/tested"' >> "$STUB/test-cmd"
  tune '.landBatch = 2'
  CARDS=$T/$CASE/cards; mkdir -p "$CARDS"
  for n in 7 8; do
    git -C "$R" worktree add -q --detach "$CARDS/c$n-$n" main || fail "the worktree of card $n"
    landed "$n" | jq -c --arg c "c$n-$n" '.card = $c | .step = "picked"' >> "$ST/cards.jsonl"
  done
  echo '// seven' >> "$CARDS/c7-7/src/repositories/widget-repository.ts"; (cd "$CARDS/c8-8" && eval "$GADGET")
  git -C "$CARDS/c7-7" add -A && git -C "$CARDS/c8-8" add -A || fail "the cards' changes"
  echo '{"issue":8,"msg":"title 8 (#8)","extra":{"waitSec":0}}' > "$CARDS/c8-8.ready"
  local looks='sleep() { [ "${FUNCNAME[1]}" = settle ] || { command sleep "$@"; return; }; LOOKS=$((LOOKS + 1)); [ $LOOKS -lt 3 ] || exit 8; }' # sleep: a stand-in that counts the looks of settle() and runs no wait
  fx_in 'cd "$R" || exit 9; caught="" waitsec=0 behind="[]" parsecheck="" LOOKS=0
    [ -z "$(locked claim c7-7 "$CARDS/c7-7" $$)" ] || { echo "#7 did not hold the file"; exit 9; }
    '"$looks"'
    settle c8-8 8 "$CARDS/c8-8" "Build the issue." land "$(issue 8 2026-01-01)"; echo "settle: $?"'
  [ "$RC" = 8 ] && grep -q 'conveyor: card c8-8 waits on card c7-7' "$T/$CASE/run.out" || fail "#8 did not wait on #7: exit $RC: $(cat "$T/$CASE/run.out")"
  [ ! -e "$STUB/tested" ] && [ ! -e "$CARDS/c8-8.ready" ] \
    || fail "the waiting card whose change the check refuses (change: $GADGET) ran its tests or is still ready, so a batch can land it: $(cat "$STUB/tested" "$CARDS/c8-8.ready" 2>&1)"
  # The check's own BLOCKED line: a check that never ran on #8's change (a wrong path, an error) prints no such line.
  grep -qx 'conveyor: card c8-8: the persisted-contract check refused its change while it waits, or could not run: it runs no check or test, and its landing gate deals with it at its turn' "$T/$CASE/run.out" \
    && grep -qxF "$MSG" "$T/$CASE/run.out" || fail "settle() did not say why the card runs no test, with the check's message (change: $GADGET): $(cat "$T/$CASE/run.out")"
}

# Bug it catches: a batch lands card #8 on #7's commit, a range that #8's own checks never read, and the check reads
# the whole tip: #7 adds a repository file that names Gizmo, which makes #8's shared/gizmo.ts a contract writer. #8
# passes the check on its own HEAD, so only landone()'s check on the commit it lands can refuse it. Through land()
# with the batch of #7 then #8: nothing lands, the check's message names #8's writer, and #8 is no longer ready, though
# #8's wait rewrites its ready file at the same time.
t_contractbatchland() {
  contractmain '[]'
  CARDS=$T/$CASE/cards; mkdir -p "$CARDS"
  for n in 7 8; do
    git -C "$R" worktree add -q --detach "$CARDS/c$n-$n" main || fail "the worktree of card $n"
    landed "$n" | jq -c --arg c "c$n-$n" '.card = $c | .step = "picked"' >> "$ST/cards.jsonl"
  done
  echo '// Gizmo' > "$CARDS/c7-7/src/repositories/gizmo-note.ts" && mkdir -p "$CARDS/c8-8/shared" && echo 'export interface Gizmo { id: string }' > "$CARDS/c8-8/shared/gizmo.ts" \
    && git -C "$CARDS/c7-7" add -A && git -C "$CARDS/c8-8" add -A || fail "the cards' changes"
  echo '{"issue":8,"msg":"title 8 (#8)"}' > "$CARDS/c8-8.ready"
  m=$(git -C "$R" rev-parse main)
  # #8's own wait rewrites its .ready (readyput(), as settle() does) while the batch lands: that rewrite stops after
  # writing its temp file, before its rename, so the landing's removal of the file comes at that weak point. The
  # landing then says it is about to wait on the ready lock (flock from readyrm()) or that it ended; only then does the
  # rewrite go on. A removal outside the lock happens before the rename, which puts the file back.
  mkfifo "$T/$CASE/sig" "$T/$CASE/go" || fail "the fifos"
  # shellcheck disable=SC2016 # expanded in fx_in's shell
  fx_in 'cd "$R" || exit 9; contractrun "$CARDS/c8-8" && echo "alone: passes"
    exec {s}<>"$T/$CASE/sig" {g}<>"$T/$CASE/go"
    ( mv() { echo put >&$s; read -r _ <&$g; command mv "$@"; }; readyput "$CARDS/c8-8" ".extra.waitSec = \$w" --argjson w 5 ) & p1=$!
    read -r _ <&$s
    ( flock() { [ "${FUNCNAME[1]}" != readyrm ] || echo lock >&$s; command flock "$@"; }
      land c7-7 7 "$CARDS/c7-7" "title 7 (#7)" "{}" c8-8 8 "$CARDS/c8-8" "title 8 (#8)" "{}"; echo "land: $?"; echo done >&$s ) & p2=$!
    read -r _ <&$s; echo go >&$g; wait $p1 $p2'
  grep -qx 'alone: passes' "$T/$CASE/run.out" || fail "#8's change (shared/gizmo.ts, interface Gizmo) does not pass the check on its own HEAD, so this case proves nothing: $(cat "$T/$CASE/run.out")"
  grep -qx 'land: 1' "$T/$CASE/run.out" && [ "$(git -C "$R" rev-parse main)" = "$m" ] && grep -qF 'contract: the persisted-contract check refuses card c8-8' "$T/$CASE/run.out" \
    && grep -qF 'BLOCKED: persisted-contract writer shared/gizmo.ts' "$T/$CASE/run.out" && [ ! -e "$CARDS/c8-8.ready" ] \
    || fail "the batch of #7 (src/repositories/gizmo-note.ts naming Gizmo) then #8 (shared/gizmo.ts) landed, or #8 is still ready: $(cat "$T/$CASE/run.out"); ready: $(cat "$CARDS/c8-8.ready" 2>&1)"
}

# Bug it catches: a project whose pre-push hook does not run the check gets a refusal it would never meet at push. With
# no such hook, the gate passes the same change and runs no fix session.
t_contractnohook() {
  contractmain '[]' 0
  FXWT=$T/$CASE/cards/c7; git -C "$R" worktree add -q --detach "$FXWT" && (cd "$FXWT" && eval "$GADGET") && git -C "$FXWT" add -A || fail "the card's change"
  # shellcheck disable=SC2016 # expanded in fx_in's shell
  fx_in 'session() { echo fix >> "$STUB/fixbrief"; echo "{}"; }; cfix=""; contractgate c7 7 "$FXWT" "{}" prompt br; echo "rc=$?"'
  grep -qx 'rc=0' "$T/$CASE/run.out" && [ ! -e "$STUB/fixbrief" ] \
    || fail "the gate refused a change (change: $GADGET) though main's pre-push hook runs no contract check: $(cat "$T/$CASE/run.out")"
}
