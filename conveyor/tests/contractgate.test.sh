#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 240
# Engine cases: the persisted-contract check before a card lands (conveyor/lib/contract.sh): at the landing gate
# (contractgate(), in cardtest()) and on each commit that lands (landone(), lib/claim.sh). It runs
# adversarial-review-gate.sh --contract-range on the card's change when main's pre-push hook runs that check, so a
# change that hook refuses does not land. Then the push checks at the landing gate (pushgate(), after contractgate())
# and for a card whose change a session changed only in its documentation (pushgatewait(), in docstested()): main's
# pre-push hook, when it names CONVEYOR_PUSH_GATE, run on the card's change alone, on a test slot.
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

# Bug it catches: with pushes not made on landing, the push checks every commit from the checker's base (--base-only),
# which stays before a landed card that no review record covers, but landone() checked each card's own commit alone.
# #8 (shared/gizmo.ts) lands alone with a leftover finding and no filed follow-up; #7 (gizmo-note.ts naming Gizmo) then
# passes alone, and the push of both is refused. Through land(), one card after the other: #7 does not land, the
# check's message names #8's writer, and main stays at #8's commit.
t_contractpushrange() {
  contractmain '[]'
  CARDS=$T/$CASE/cards; mkdir -p "$CARDS"
  for n in 7 8; do landed "$n" | jq -c --arg c "c$n-$n" '.card = $c | .step = "picked"' >> "$ST/cards.jsonl"; done
  git -C "$R" worktree add -q --detach "$CARDS/c8-8" main && mkdir -p "$CARDS/c8-8/shared" && echo 'export interface Gizmo { id: string }' > "$CARDS/c8-8/shared/gizmo.ts" \
    && git -C "$CARDS/c8-8" add -A || fail "#8's change"
  # shellcheck disable=SC2016 # expanded in fx_in's shell
  fx_in 'cd "$R" || exit 9
    land c8-8 8 "$CARDS/c8-8" "title 8 (#8)" "{\"leftover\":true,\"followups\":[]}"; echo "land 8: $?"; git rev-parse main > "$T/$CASE/at8"
    git worktree add -q --detach "$CARDS/c7-7" main && echo "// Gizmo" > "$CARDS/c7-7/src/repositories/gizmo-note.ts" && git -C "$CARDS/c7-7" add -A || exit 9
    land c7-7 7 "$CARDS/c7-7" "title 7 (#7)" "{}"; echo "land 7: $?"'
  grep -qx 'land 8: 0' "$T/$CASE/run.out" || fail "#8 (shared/gizmo.ts) did not land alone, so this case proves nothing: $(cat "$T/$CASE/run.out")"
  grep -qx 'land 7: 1' "$T/$CASE/run.out" && [ "$(git -C "$R" rev-parse main)" = "$(cat "$T/$CASE/at8")" ] \
    && grep -qF 'BLOCKED: persisted-contract writer shared/gizmo.ts' "$T/$CASE/run.out" \
    || fail "#7 (src/repositories/gizmo-note.ts naming Gizmo) landed after #8 (shared/gizmo.ts, landed with no filed follow-up), so the push of both is refused: $(cat "$T/$CASE/run.out")"
}
# Bug it catches: the check read only from the push's base, so a card passed on a test that an earlier unpushed card
# changed. Push landed then pushes that earlier commit alone, and the next push, from it, has no changed test. #8 adds
# the writer saveGadget with a test naming readWidget and saveGadget, and lands with a leftover finding and no filed
# follow-up; #7 then adds the writer saveGizmo with no test. From origin/main (the push's base) #7 passes, on #8's test;
# from #8's commit it is refused. Through land(): #7 does not land, with the check's message, and main stays at #8.
t_contractpushborrow() {
  contractborrow
}
# Bug it catches: an older installed checker, which has no <from>, answers --base-only <tip> <from> from origin/main,
# so the check read only the range that holds #8's test, and #7 landed on it. The cards of t_contractpushborrow with
# such a checker: #7 does not land.
t_contractpushold() {
  # shellcheck disable=SC2016 # expanded in the checker's shell
  contractborrow '[ "$1" != --base-only ] || set -- "$1" "$2"; exec bash "$SRC/../.claude/hooks/adversarial-review-gate.sh" "$@"'
}
# The cards of t_contractpushborrow, checked by the installed checker or by <checker> (a script, $SRC set).
contractborrow() { # [<checker>]
  contractmain '[]'
  CARDS=$T/$CASE/cards; mkdir -p "$CARDS"
  for n in 7 8; do landed "$n" | jq -c --arg c "c$n-$n" '.card = $c | .step = "picked"' >> "$ST/cards.jsonl"; done
  git -C "$R" worktree add -q --detach "$CARDS/c8-8" main && (cd "$CARDS/c8-8" && eval "$GADGET" && eval "$COVER") && git -C "$CARDS/c8-8" add -A || fail "#8's change"
  [ -z "${1-}" ] || printf '%s\n' "SRC='$SRC'" "$1" > "$T/$CASE/checker.sh" || fail "the checker"
  # shellcheck disable=SC2016 # expanded in fx_in's shell
  fx_in '[ ! -e "$T/$CASE/checker.sh" ] || contracthook() { echo "$T/$CASE/checker.sh"; }
    cd "$R" || exit 9
    land c8-8 8 "$CARDS/c8-8" "title 8 (#8)" "{\"leftover\":true,\"followups\":[]}"; echo "land 8: $?"; git rev-parse main > "$T/$CASE/at8"
    git worktree add -q --detach "$CARDS/c7-7" main && printf "%s\n" "export function saveGizmo(id) {" "  return id;" "}" >> "$CARDS/c7-7/src/repositories/widget-repository.ts" \
      && git -C "$CARDS/c7-7" add -A && h=$(cd "$CARDS/c7-7" && git commit-tree "$(git write-tree)" -p HEAD -m 7) || exit 9
    bash "$(contracthook)" --contract-range origin/main "$h" < /dev/null && echo "from origin/main: passes"
    land c7-7 7 "$CARDS/c7-7" "title 7 (#7)" "{}"; echo "land 7: $?"'
  grep -qx 'land 8: 0' "$T/$CASE/run.out" && grep -qx 'from origin/main: passes' "$T/$CASE/run.out" \
    || fail "#8 (saveGadget with its test) did not land, or #7 (saveGizmo, no test) does not pass from origin/main on #8's test, so this case proves nothing: $(cat "$T/$CASE/run.out")"
  grep -qx 'land 7: 1' "$T/$CASE/run.out" && [ "$(git -C "$R" rev-parse main)" = "$(cat "$T/$CASE/at8")" ] && grep -qF "nothing was landed: $MSG" "$T/$CASE/run.out" \
    || fail "#7 (saveGizmo in src/repositories/widget-repository.ts, no changed test) landed on #8's unpushed test, so the push that starts at #8 is refused (checker: ${1:-installed}): $(cat "$T/$CASE/run.out")"
}
# Bug it catches: the check read from every commit between the push's base and the card's, though a push starts only
# at the checker's answer from a commit main has been at (--base-only <tip> <from>). #6 (src/six.ts and a test naming
# Gizmo and readWidget) lands with a leftover finding and no filed follow-up; the batch of #7 (src/seven.ts) then #8
# (shared/gizmo.ts) moves main once. #9 adds "// Gizmo" beside readWidget: it passes from origin/main and from #8's
# commit (the checker's answer from #6's), the bases a push can start at, and is refused from #7's commit, where main
# never was, and from #6's, where no push starts. Through land(): #9 lands.
t_contractbatchstart() {
  contractmain '[]'
  CARDS=$T/$CASE/cards; mkdir -p "$CARDS"
  for n in 6 7 8 9; do landed "$n" | jq -c --arg c "c$n-$n" '.card = $c | .step = "picked"' >> "$ST/cards.jsonl"; done
  # shellcheck disable=SC2016 # expanded in fx_in's shell
  fx_in 'cd "$R" || exit 9
    wt() { git worktree add -q --detach "$CARDS/c$1-$1" main && (cd "$CARDS/c$1-$1" && eval "$2") && git -C "$CARDS/c$1-$1" add -A; }
    wt 6 "echo \"export const six = 6;\" > src/six.ts && mkdir -p src/repositories/__tests__ && echo \"Gizmo readWidget\" > src/repositories/__tests__/gizmo.test.ts" \
      && land c6-6 6 "$CARDS/c6-6" "title 6 (#6)" "{\"leftover\":true,\"followups\":[]}" || exit 9
    wt 7 "echo \"export const seven = 7;\" > src/seven.ts" && wt 8 "mkdir -p shared && echo \"export interface Gizmo { id: string }\" > shared/gizmo.ts" \
      && land c7-7 7 "$CARDS/c7-7" "title 7 (#7)" "{}" c8-8 8 "$CARDS/c8-8" "title 8 (#8)" "{}" || exit 9
    b6=$(git rev-parse main~2) && b7=$(git rev-parse main~1) \
      && wt 9 "awk '\''{ print } /^export function readWidget/ { print \"  // Gizmo\" }'\'' src/repositories/widget-repository.ts > w && mv w src/repositories/widget-repository.ts" \
      && h=$(cd "$CARDS/c9-9" && git commit-tree "$(git write-tree)" -p HEAD -m 9) || exit 9
    for p in origin/main main "$b7" "$b6"; do bash "$(contracthook)" --contract-range "$p" "$h" < /dev/null > /dev/null 2>&1; echo "from $p: $?"; done | sed "s|$b7|#7|; s|$b6|#6|"
    land c9-9 9 "$CARDS/c9-9" "title 9 (#9)" "{}"; echo "land 9: $?"'
  [ "$(grep -c '^from \(origin/main\|main\): 0$' "$T/$CASE/run.out")" = 2 ] && [ "$(grep -c '^from #[67]: 2$' "$T/$CASE/run.out")" = 2 ] \
    || fail "#9 (// Gizmo beside readWidget) does not pass from origin/main and #8's commit, or is not refused from #7's and #6's commits, so this case proves nothing: $(cat "$T/$CASE/run.out")"
  grep -qx 'land 9: 0' "$T/$CASE/run.out" && git -C "$R" show main:src/repositories/widget-repository.ts | grep -qx '  // Gizmo' \
    || fail "#9 (// Gizmo beside readWidget) did not land, refused from #7's or #6's commit, which no push starts at: $(cat "$T/$CASE/run.out")"
}
# Bug it catches: in a batch, the checker has no landed line yet for the cards before the card, so its answer stopped
# at one of them, though the push, which reads their lines, starts after them. One batch of three reviewed cards: #5
# (a test naming Gizmo and readWidget), #6 (shared/gizmo.ts), #7 ("// Gizmo" beside readWidget). The checker's answer
# for #7 stops at #5's commit (a test-only commit it skips), and from there #6 and #7 are refused, as the check after
# the landing shows; the push, with all three lines, checks none of them. Through land(): all three land.
t_contractbatchcovered() {
  contractmain '[]'
  CARDS=$T/$CASE/cards; mkdir -p "$CARDS"
  for n in 5 6 7; do landed "$n" | jq -c --arg c "c$n-$n" '.card = $c | .step = "picked"' >> "$ST/cards.jsonl"; done
  # shellcheck disable=SC2016 # expanded in fx_in's shell
  fx_in 'cd "$R" || exit 9
    wt() { git worktree add -q --detach "$CARDS/c$1-$1" main && (cd "$CARDS/c$1-$1" && eval "$2") && git -C "$CARDS/c$1-$1" add -A; }
    wt 5 "mkdir -p src/repositories/__tests__ && echo \"Gizmo readWidget\" > src/repositories/__tests__/gizmo.test.ts" \
      && wt 6 "mkdir -p shared && echo \"export interface Gizmo { id: string }\" > shared/gizmo.ts" \
      && wt 7 "awk '\''{ print } /^export function readWidget/ { print \"  // Gizmo\" }'\'' src/repositories/widget-repository.ts > w && mv w src/repositories/widget-repository.ts" || exit 9
    land c5-5 5 "$CARDS/c5-5" "title 5 (#5)" "{}" c6-6 6 "$CARDS/c6-6" "title 6 (#6)" "{}" c7-7 7 "$CARDS/c7-7" "title 7 (#7)" "{}"; echo "land: $?"
    bash "$(contracthook)" --contract-range main~2 main < /dev/null > /dev/null 2>&1; echo "from #5: $?"'
  grep -qx 'land: 0' "$T/$CASE/run.out" && [ "$(git -C "$R" rev-list --count origin/main..main)" = 3 ] \
    && git -C "$R" show main:src/repositories/widget-repository.ts | grep -qx '  // Gizmo' \
    || fail "the batch of #5 (test naming Gizmo and readWidget), #6 (shared/gizmo.ts) and #7 (// Gizmo beside readWidget) did not land, refused from a commit of its batch: $(cat "$T/$CASE/run.out")"
  grep -qx 'from #5: 2' "$T/$CASE/run.out" || fail "#6 and #7 are not refused from #5's commit, so this case proves nothing: $(cat "$T/$CASE/run.out")"
}

# A checker for main's pre-push hook (contracthook() names it in contractcardwith()). Each --contract-range call adds
# "main" or "card" (where it ran) to $STUB/checks. A range with a changed test passes. Else it refuses in main's
# checkout, that is at landone(); in a card's worktree, at the landing gate, it refuses only after such a refusal, and
# only when <gate too> is 1: a check that comes to refuse the change between its gate and its landing.
landrefusing() { # <gate too: 0 or 1>
  # shellcheck disable=SC2016 # expanded in the checker's shell
  printf '%s\n' 'case $1 in --contract-range) ;; *) exit 0 ;; esac' \
    'w=card; [ "$(git rev-parse --git-dir)" != "$(git rev-parse --git-common-dir)" ] || w=main; echo "$w" >> "$STUB/checks"' \
    '! git diff --name-only "$2" "$3" | grep -q __tests__ || exit 0' \
    "[ \"\$w\" = main ] || { [ -e \"\$STUB/refused\" ] && [ $1 = 1 ]; } || exit 0" \
    ': > "$STUB/refused"; echo "BLOCKED: persisted-contract writer src/repositories/widget-repository.ts needs one changed test that names both it and a changed reader." >&2; exit 2'
}
# contractcard() with the checker <checker> in place of the installed one: card() runs card #7 to its landing or block.
# A whole card run: only it shows where cardland() sends a card that land() refused.
contractcardwith() { # <checker> <build> [<fix>]
  contractmain "[$(issue 7 2026-01-01)]"
  printf '%s\n' "$1" > "$T/$CASE/checker.sh" || fail "the checker"
  printf '%s\n' "if grep -q '^# Persisted-contract check' \"\$STUB/brief\"; then sed -n '/^# Persisted-contract check/,\$p' \"\$STUB/brief\" > \"\$STUB/fixbrief\"; ${3:-echo fixed >> a.txt}; else $2; fi" > "$STUB/build"
  for i in 1 2 3 4 5 6; do echo "$GO" > "$STUB/review.$i"; done
  # shellcheck disable=SC2016 # expanded in fx_in's shell
  fx_in 'contracthook() { echo "$T/$CASE/checker.sh"; }
    cd "$R" && read -r c n _ <<<"$(locked pick "" "" "$(asked)")" && [ "$n" = 7 ] || { echo "pick took ${n:-nothing}"; exit 3; }; card "$c" "$n"'
  [ "$RC" != 3 ] && [ -s "$ST/cards.jsonl" ] || fail "#7 was not picked (exit $RC): $(tail -n 20 "$T/$CASE/run.out")"
}
# Bug it catches: a solo card that landone()'s check refused was blocked with no fix session, though the card goes back
# to its landing gate. The gate passes the change, the landing refuses it, and the gate then refuses it too: its fix
# session gets the check's message, adds a test, and the card lands at its second landing.
t_contractlandgate() {
  contractcardwith "$(landrefusing 1)" "$GADGET" "$COVER"
  [ "$(grep -cx main "$STUB/checks")" = 2 ] && grep -qF 'BLOCKED: persisted-contract writer src/repositories/widget-repository.ts' "$STUB/fixbrief" 2>/dev/null \
    && [ -n "$(st 'select(.step == "landed") | .sha')" ] \
    || fail "the card whose landing the check refused (change: $GADGET) did not go back to its gate, get its fix session ($COVER) and land: checks $(paste -sd ' ' "$STUB/checks" 2>&1); $(st 'select(.step | IN("blocked", "landed")) | "\(.step) \(.reason)"')"
}
# Bug it catches: a refusal at the landing that the gate does not give sends the card between the two without end. The
# gate passes the change each time; the second refusal at the landing (the second check in main's checkout) blocks the
# card with the check's message.
t_contractlandagain() {
  contractcardwith "$(landrefusing 0)" "$GADGET"
  [ "$(grep -cx main "$STUB/checks")" = 2 ] && [ ! -e "$STUB/fixbrief" ] \
    && [[ $(st 'select(.step == "blocked") | .reason') == 'contract: the persisted-contract check refuses card '*'BLOCKED: persisted-contract writer'* ]] \
    || fail "the card whose landing the check refused twice (change: $GADGET), its gate passing, was not blocked at the second: checks $(paste -sd ' ' "$STUB/checks" 2>&1); $(st 'select(.step | IN("blocked", "landed")) | "\(.step) \(.reason)"')"
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

# Card #7 with main's pre-push hook <hook> (lines after its shebang; it names CONVEYOR_PUSH_GATE, so the landing gate
# runs it, pushgate() in lib/contract.sh), and the pack changed by the jq filter <tune>. Its build adds web.ts; its
# reviews are GO. card() runs it to its landing or block.
pushgatecard() { # <hook> [<tune>]
  setup "[$(issue 7 2026-01-01)]"
  tune "${2:-.}" || fail "the pack"
  pushgatehook "$1"
  echo 'echo "export const n: number = 1" > web.ts' > "$STUB/build"
  for i in 1 2 3 4 5 6; do echo "$GO" > "$STUB/review.$i"; done
  rulecard 7
}

# #1683, Done-when 1. Bug it catches: the push checks ran only at the push, so a card whose change fails one landed and
# main then held a commit it could not push. Main's hook selects its checks by the files of the pushed range, as a
# project's does: given the card's change alone (web.ts), its typecheck fails. The card is blocked before it lands,
# its record naming the check and holding the check's error. The hook's file is named from $T/$CASE, not $STUB:
# setup(), in pushgatecard(), sets $STUB after this hook's text is made.
t_pushgatefail() {
  local g=$T/$CASE/gatefiles
  pushgatecard "read -r _ l _ r; git diff --name-only \"\$r\" \"\$l\" > $(printf %q "$g")
grep -qx web.ts $(printf %q "$g") || exit 0
echo 'web.ts(1,14): error TS2322: Type string is not assignable to type number.' >&2; echo 'push-checks: FAILED typecheck-web' >&2; exit 1"
  [ "$(cat "$g" 2>&1)" = web.ts ] || fail "main's hook was not given the card's change (web.ts) alone as the pushed range: $(cat "$g" 2>&1)"
  [ -z "$(st 'select(.step == "landed")')" ] && [ ! -e "$R/web.ts" ] || fail "the card whose change (web.ts) fails the push check typecheck-web landed: $(st 'select(.step == "landed")')"
  [[ $(st 'select(.step == "blocked") | .reason') == "push check: typecheck-web failed on the card's change (exit 1); nothing landed."* ]] \
    && st 'select(.step == "blocked") | .tail' | grep -qF 'error TS2322' \
    || fail "the card (change web.ts) was not blocked naming typecheck-web with its error in the record: $(st 'select(.step == "blocked") | {reason, tail}')"
}

# #1683, Done-when 2 and 3. Bug it catches: a push check past its time limit let the card land (exit 0), and the check
# ran in a card folder that was gone ("cd: ... No such file or directory"). Main's hook passes one check, then runs one
# for 20 s, past pushTimeout 1 (times the load factor, at most 3 s); while it runs, it notes once each 0.2 s whether its
# folder is gone. The card is blocked as its checks not finished, the hook ran in the card's worktree, that folder was
# there each time it looked, and neither the run's output nor the card's record (its reason and the hook's output
# in .tail, which the engine captures from the hook) names a missing folder.
t_pushgateslow() {
  local d=$T/$CASE
  pushgatecard "pwd -P > $(printf %q "$d/gatedir"); echo 'push-checks: ok lint-web'
for i in \$(seq 100); do [ -d \"\$PWD\" ] || echo gone >> $(printf %q "$d/gone"); sleep 0.2; done; echo 'push-checks: ok slow-web'" '.tunables.pushTimeout = 1' # sleep: the hook's check must run past its time limit
  [ -z "$(st 'select(.step == "landed")')" ] && [[ $(st 'select(.step == "blocked") | .reason') == "push check: its checks not finished: "* ]] \
    || fail "a card whose push check ran 20 s past pushTimeout 1 was not held back as its checks not finished: $(st 'select(.step | IN("blocked", "landed")) | "\(.step) \(.reason)"')"
  [[ $(cat "$d/gatedir" 2>&1) == "$(cd "$d/cards" && pwd -P)/c"* ]] || fail "the push check did not run in the card's worktree: $(cat "$d/gatedir" 2>&1)"
  [ ! -e "$d/gone" ] || fail "the card's worktree was gone while its push check ran ($(wc -l < "$d/gone") looks)"
  ! grep -q 'cd: .*No such file or directory' "$d/run.out" || fail "the run printed a missing folder: $(grep 'cd: .*No such file or directory' "$d/run.out")"
  ! st 'select(.step == "blocked") | .reason, .tail' | grep -q 'No such file or directory' \
    || fail "the card's record names a missing folder from the push check: $(st 'select(.step == "blocked") | {reason, tail}')"
}

# Main ($R) with a pre-push hook that names CONVEYOR_PUSH_GATE and runs <hook>.
pushgatehook() { # <hook>
  printf '%s\n' '#!/usr/bin/env bash' '# CONVEYOR_PUSH_GATE: run before a card lands, on its change alone' "$1" > "$R/.git/hooks/pre-push" \
    && chmod +x "$R/.git/hooks/pre-push" || fail "main's pre-push hook"
}

# Main ($R) with README.md, its hook failing the check docs-lint on a change that holds README.md while the file <o>
# is there, and card c7 ($FXWT) on that main, its change code.txt and README.md, staged, its <worktree>.ready marked
# tested on that change (tested()).
docscard() { # <o>
  contractmain '[]' 0
  pushgatehook "read -r _ l _ r; [ -e $(printf %q "$1") ] && git diff --name-only \"\$r\" \"\$l\" | grep -qx README.md || exit 0; echo 'push-checks: FAILED docs-lint' >&2; exit 1"
  echo base > "$R/README.md" && git -C "$R" add README.md && git -C "$R" commit -qm 'the readme' || fail "main's README.md"
  FXWT=$T/$CASE/cards/c7; git -C "$R" worktree add -q --detach "$FXWT" && echo seven > "$FXWT/code.txt" && echo seven > "$FXWT/README.md" \
    && git -C "$FXWT" add -A && echo '{"issue":7}' > "$FXWT.ready" || fail "the card's change"
}

# Bug it catches: a session that brought a card's change onto main, changing only its documentation (README.md), kept
# its test pass (tested() in settle()), so the card waited marked tested, ran no push check, and a batch took it on
# that mark (gather()) with a push check its new
# README.md fails never run. Main moves README.md under c7, so its change no longer applies; settle(), as card() calls
# it at the landing, gives it to the session (a stand-in that merges README.md and keeps code.txt), and with main's
# hook failing docs-lint on README.md its <worktree>.ready is gone: no batch takes it.
t_pushgatedocs() {
  local o=$T/$CASE/docsfail
  docscard "$o"; : > "$o"
  landed 7 | jq -c '.card = "c7" | .step = "picked"' >> "$ST/cards.jsonl"
  echo main > "$R/README.md" && git -C "$R" commit -qam 'main moves README.md' || fail "main's move"
  # shellcheck disable=SC2016 # expanded in fx_in's shell
  fx_in 'cd "$R" || exit 8; caught="" waitsec=0 behind="[]" parsecheck=""
    tested "$FXWT"; testedhere "$FXWT" || { echo "c7 not marked tested"; exit 8; }
    session() { (cd "$1" && echo seven > code.txt && printf "%s\n" main seven > README.md); echo "{}"; }
    checked() { :; }
    settle c7 7 "$FXWT" "Build the issue." land "$(issue 7 2026-01-01)"; echo "settle: $?"'
  [ "$(tail -n 1 "$T/$CASE/run.out")" = 'settle: 0' ] && [ "$(git -C "$FXWT" diff --cached --name-only HEAD | tr '\n' ' ')" = 'README.md code.txt ' ] \
    || fail "settle() did not bring c7's change (code.txt, README.md) onto main by the session: $(cat "$T/$CASE/run.out")"
  [ ! -e "$FXWT.ready" ] && grep -qx "push check: docs-lint failed on the card's change (exit 1); nothing landed." "$T/$CASE/run.out" \
    || fail "after a README.md-only merge session in settle(), c7 whose README.md fails the push check docs-lint kept its test pass, so a batch can land it: $(cat "$FXWT.ready" "$T/$CASE/run.out" 2>&1)"
}

# Bug it catches: the same at the landing rebuild (cardlanding(), lib/cardland.sh): back from a rebuild that changed
# only README.md (docpass, its change outside documentation as it was), the card kept its test pass (tested()) with no
# push check run. cardlanding() is called as card() calls it; settle() is a stand-in that prints the card's mark and
# ends it. With main's hook passing, the card is marked tested on its new change; with it failing docs-lint on
# README.md, its <worktree>.ready is gone, so no batch takes it.
t_pushgatedocsland() {
  local o=$T/$CASE/docsfail
  docscard "$o"
  # shellcheck disable=SC2016 # expanded in fx_in's shell
  fx_in 'cd "$R" || exit 8; c=c7 n=7 wt=$FXWT br="" sprompt="Build the issue." issue=$(issue 7 2026-01-01)
    settle() { if [ -e "$wt.ready" ]; then echo "ready: $(testedhere "$wt" && echo tested)"; else echo "ready: gone"; fi; return 1; }
    echo "{\"issue\":7,\"tested\":true}" > "$wt.ready"; docpass=$(cardpatch "$wt" ":(exclude)*.md"); cardlanding
    : > '"$(printf %q "$o")"'; echo "{\"issue\":7,\"tested\":true}" > "$wt.ready"; docpass=$(cardpatch "$wt" ":(exclude)*.md"); cardlanding'
  [ "$(grep '^ready: ' "$T/$CASE/run.out" | head -n 1)" = 'ready: tested' ] \
    || fail "back from a README.md-only rebuild whose change passes main's hook, cardlanding() did not mark c7 tested on it: $(cat "$T/$CASE/run.out")"
  [ "$(grep '^ready: ' "$T/$CASE/run.out" | sed -n 2p)" = 'ready: gone' ] && grep -qx "push check: docs-lint failed on the card's change (exit 1); nothing landed." "$T/$CASE/run.out" \
    || fail "back from a README.md-only rebuild whose README.md fails the push check docs-lint, cardlanding() kept c7's test pass, so a batch can land it: $(cat "$T/$CASE/run.out")"
}

# Bug it catches: the push check ran outside the test slots, beside every test run of a full machine, and with no live
# record, so the loop took a quiet hook for a card with no process of its step (stuckcard(), lib/run.sh) and stopped
# it before pushTimeout; and (review of #1683) a check that took a slot when one was free but ran the hook with none
# when the pool was full. With a pool of one slot, held by another test run, the push check of card c7's change
# (web.ts) waits and its live record says so; the hook has not run. Once that slot is given back, main's hook finds the
# slot held while it runs (as a lint command does in t_lintbasedeps), it ran only after the slot was given back, and
# the card's live record says it runs the hook; after, the record is gone and the gate passed.
t_pushgateslot() {
  local p=$T/$CASE/slots o=$T/$CASE/gate fr=$T/$CASE/free gp
  contractmain '[]' 0
  pushgatehook "h=0; flock -n $(printf %q "$p/1") true 2>/dev/null || h=1; [ -e $(printf %q "$fr") ] && f=1 || f=0; echo \"slots=\$h freed=\$f live=\$(jq -r .action \"\$PWD.live\" 2>&1)\" > $(printf %q "$o")"
  FXWT=$T/$CASE/cards/c7; git -C "$R" worktree add -q --detach "$FXWT" && echo 'export const n = 1' > "$FXWT/web.ts" && git -C "$FXWT" add -A || fail "the card's change"
  mkdir -p "$p" && : >> "$p/1" || fail "the test slot"
  flock "$p/1" bash -c 'until [ -e "$0" ]; do sleep 0.05; done' "$fr" & # sleep: the other test run's poll for the case to give its slot back
  # The path is put in here: wait_run() has a local p of its own, so "$p" in the condition would read that one.
  wait_until "! flock -n $(printf %q "$p/1") true" || fail "the one test slot was not held"
  # shellcheck disable=SC2016 # expanded in fx_in's shell
  fx_in 'unset CONVEYOR_TEST_SLOT; export CONVEYOR_TEST_POOL=1:'"$p"'; pushgaterun c7 "$FXWT"; echo "rc=$? $PUSH_WHY"; [ ! -e "$FXWT.live" ] || echo "live left"' & gp=$!
  wait_until '[ "$(jq -r .action "$FXWT.live" 2>/dev/null)" = "waiting for a test slot (1 of 1 in use)" ]' 'cat "$FXWT.live" "$o"' \
    || fail "the push check of the card's change (web.ts) did not wait for the one test slot, held by another run, with its live record saying so: $(cat "$FXWT.live" "$o" 2>&1)"
  [ ! -e "$o" ] || fail "main's hook on the card's change (web.ts) ran while the one test slot was held by another run: $(cat "$o")"
  : > "$fr"; wait "$gp"
  [ "$(cat "$o" 2>&1)" = "slots=1 freed=1 live=running main's pre-push hook on the card's change" ] \
    || fail "main's hook on the card's change (web.ts) did not run on the one test slot, after the other run gave it back, with the card's live record naming it: $(cat "$o" 2>&1)"
  [ "$(cat "$T/$CASE/run.out")" = 'rc=0 ' ] || fail "the push check of the card's change (web.ts) did not pass and clear its live record: $(cat "$T/$CASE/run.out")"
}
