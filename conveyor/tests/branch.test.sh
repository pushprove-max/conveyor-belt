#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 300
# Engine cases: land-branch.
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"
# The engine folder, as lib.sh sets it: named here too, so the release closure (tools/closure.sh) follows this file's paths.
SRC=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)

# Bugs: a branch landed by land-branch runs a build session, skips the review, the visible-change check or the
# changed tests, or lands on a NO-GO without its fix session; its lines are not a card's (no card id, no branch on the
# picked line, the wrong issue); the branch itself is moved; a refusal (no branch, no change, a conflict with main, an
# issue whose card is open) leaves a card behind; a card of no issue posts on issue 0.
# One case for each part (t_branch, t_branchfix, t_branchtests, t_branchvisible, t_branchrefused, t_branchnolink), so
# they run side by side, each on a main of its own (branchsetup). count is of the part's own sessions, reviews and
# test runs. t_branchfix and t_branchrefused are in branchfix.test.sh, t_branchtests in branchtests.test.sh and
# t_branchvisible in branchvisible.test.sh, using this file's branchsetup (the runner sources every case file): the
# six cost about 17 CPU s together, over a file's CPU budget (test.fileBudget).
branchsetup() {
  setup "[$(issue 7 2026-01-01 area:billing)]"
  lane() { # <branch> <file> <text> [commit message] [start point]: a branch with one commit, made in a worktree of its own
    git -C "$R" worktree add -q -b "$1" "$T/$CASE/lane-$1" "${5:-main}" && mkdir -p "$(dirname "$T/$CASE/lane-$1/$2")" && echo "$3" > "$T/$CASE/lane-$1/$2" && git -C "$T/$CASE/lane-$1" add "$2" \
      && git -C "$T/$CASE/lane-$1" commit -qm "${4:-fix(tooling): $1 change}"
  }
  steps() { st "select(.card == \"$1\") | .step" | tr '\n' ' '; }
  newest() { st 'select(.step == "picked") | .card' | tail -n 1; }
  count() { [ "$(cat "$STUB/sessions" 2>/dev/null | wc -l) $(cat "$STUB/reviews" 2>/dev/null | wc -l) $(cat "$STUB/tests" 2>/dev/null | wc -l)" = "$1" ] || fail "sessions, reviews and test runs so far are $(cat "$STUB/sessions" 2>/dev/null | wc -l) $(cat "$STUB/reviews" 2>/dev/null | wc -l) $(cat "$STUB/tests" 2>/dev/null | wc -l), not $1"; }
  init=$(git -C "$R" rev-parse HEAD)
}
t_branch() {
  branchsetup
  # A good change on a branch that names no issue: one review, the changed tests, landed. No build session.
  lane fast-lane b.txt bee; tip=$(git -C "$R" rev-parse fast-lane); echo "$GO" > "$STUB/review.1"
  out=$(loop land-branch fast-lane) || fail "a good branch did not land: $out"
  c=$(newest); count "0 1 1"
  [ "$(steps "$c")" = "picked worktree deps brief start review start test start landed " ] || fail "steps of a good branch: $(steps "$c")"
  [ "$(st 'select(.step == "picked") | [.issue, .branch, .title] | join("|")')" = "0|fast-lane|fix(tooling): fast-lane change" ] || fail "picked line: $(st 'select(.step == "picked")')"
  [ "$(st 'select(.step == "landed") | .sha')" = "$(git -C "$R" rev-parse main)" ] && [ "$(cat "$R/b.txt")" = bee ] && [ -z "$(git -C "$R" status --porcelain)" ] \
    && [ "$(git -C "$R" rev-parse main~1)" = "$init" ] || fail "main is not its old head plus one commit holding the branch's change"
  [ "$(git -C "$R" log -1 --format=%B main)" = "fix(tooling): fast-lane change"$'\n\n'"Conveyor card $c, branch fast-lane" ] || fail "commit message: $(git -C "$R" log -1 --format=%B main)"
  [ "$(git -C "$R" rev-parse fast-lane)" = "$tip" ] && grep -q "card $c, branch fast-lane: landed" <<<"$out" && [ -z "$(ls "$T/$CASE/cards")" ] || fail "the branch moved, the landing was not reported, or the worktree is left: $out"
  loop check || fail "the record check refuses a branch card"
  [ "$(loop cards | jq -c '[.landed, (.cards | map("\(.issue) \(.step) \(.reviews)"))]')" = '[1,["0 landed 1"]]' ] || fail "dashboard row of a branch card: $(loop cards)"
  # A branch card that has its brief line is in review 1, not in a build.
  jq -c 'select(.step | IN("picked", "worktree", "brief")) | .card = "c1-0"' "$ST/cards.jsonl" > "$STUB/open" && cat "$STUB/open" >> "$ST/cards.jsonl"
  [ "$(loop cards | jq -c '.cards | map(select(.card == "c1-0") | [.step, .stage])')" = '[["review",2]]' ] || fail "a branch card after its brief is not shown in review 1: $(loop cards)"
  grep -v '"c1-0"' "$ST/cards.jsonl" > "$STUB/open"; cat "$STUB/open" > "$ST/cards.jsonl"
  # Landed already: the same branch holds no change against main now, and no card is made for it.
  out=$(loop land-branch fast-lane) && grep -q 'nothing to land' <<<"$out" && [ "$(newest)" = "$c" ] || fail "a branch main already holds made a card or failed: $out"
}
t_branchnolink() {
  branchsetup
  # Bug: a branch merged into the card's worktree, then the dependencies could not be linked
  # (here a folder the branch tracks is where the link goes), and the block threw the staged change away. It is
  # kept as a patch.
  P=$R/.conveyor/project.json; jq '.linkFromMain += ["sub/node_modules"]' "$P" > "$P.new" && mv "$P.new" "$P"
  lane nolink g.txt gee; mkdir -p "$T/$CASE/lane-nolink/sub/node_modules/node_modules" "$R/sub/node_modules"
  echo '{}' > "$T/$CASE/lane-nolink/sub/package.json"; echo x > "$T/$CASE/lane-nolink/sub/node_modules/node_modules/x"
  git -C "$T/$CASE/lane-nolink" add -f sub; git -C "$T/$CASE/lane-nolink" commit -qm 'fix(tooling): nolink, its package'
  out=$(loop land-branch nolink 2>&1) && fail "a branch card whose dependencies could not be linked exited zero: $out"
  c=$(newest); k=$(st "select(.card == \"$c\" and .step == \"blocked\") | \"\\(\$ENV.ST)/\\(.kept)\"")
  st "select(.card == \"$c\" and .step == \"blocked\") | .reason" | grep -q "^worktree: the engine could not link the dependencies of the main checkout" \
    && [ "$(steps "$c")" = "picked worktree blocked " ] && [ "$(git -C "$R" apply --numstat "$k/$c.patch" 2>&1 | cut -f3 | tr '\n' ' ')" = "g.txt sub/node_modules/node_modules/x sub/package.json " ] && [ "$(cat "$k/$c.base" 2>&1)" = "$(git -C "$R" rev-parse main)" ] \
    || fail "a branch card whose dependencies could not be linked did not keep its merged change as a patch: $(st "select(.card == \"$c\")") $(ls "$k" 2>&1)"
  [ -z "$(ls "$T/$CASE/cards")" ] || fail "that blocked card left files beside its worktree: $(ls "$T/$CASE/cards")"
  rm -rf "$R/sub"; loop check || fail "the record check fails after the card whose dependencies could not be linked"
}
