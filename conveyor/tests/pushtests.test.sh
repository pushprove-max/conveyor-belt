#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 120
# Engine cases (#384): the run before a push (lib/push.sh pushtests()): the test files the test map and the links give
# the landings since the last push, each alone, once; a file that fails is run on the landings in turn to find the one
# that broke it, goes to a main-fix card naming that landing, and holds the push.
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"
# The engine folder, as lib.sh sets it: named here too, so the release closure (tools/closure.sh) follows this file's paths.
SRC=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)

# D3, D4. Bugs it catches: a landing that broke a test file the map links to its change was pushed, as its card ran
# only its own test files; the push's run named no landing, or the first one, so the main-fix card was sent to the
# wrong change; the push's run ran the test command (the whole suite) or a test runner of the whole suite.
# Origin holds main as setup made it. Two landings since: c1 adds lib/cart.js, its test lib/cart.test.js and
# lib/cart-all.test.js, the pack's runner of the whole suite (test.wholeCommands), which the names link to cart.js
# too; c2 breaks lib/cart.js. The push of c2 runs lib/cart.test.js alone on main, then on c1's commit, where it passes.
t_pushtests() {
  local l1 l2 base
  setup '[]'
  base=$(git -C "$R" rev-parse HEAD)
  printf '%s\n' 'echo "$(git rev-parse HEAD) $1" >> "$STUB/ran"; bash "$1"' > "$STUB/one"
  tune '.test.fileCommand = "bash \"$STUB/one\"" | .test.wholeCommands = ["lib/cart-all.test.js"] | .test.full = "touch \"$STUB/whole\""'
  mkdir -p "$R/lib" && echo good > "$R/lib/cart.js" && echo 'grep -qx good lib/cart.js' > "$R/lib/cart.test.js" \
    && echo 'touch "$STUB/whole"' > "$R/lib/cart-all.test.js" && git -C "$R" add -A && git -C "$R" commit -qm c1 \
    && l1=$(git -C "$R" rev-parse HEAD) && echo bad > "$R/lib/cart.js" && git -C "$R" commit -qam c2 && l2=$(git -C "$R" rev-parse HEAD) \
    || fail "the two landings could not be made"
  printf '%s\n' "{\"card\":\"c1\",\"issue\":1,\"step\":\"landed\",\"time\":\"2026-11-18T10:00:00Z\",\"result\":\"ok\",\"sha\":\"$l1\"}" \
    "{\"card\":\"c2\",\"issue\":2,\"step\":\"landed\",\"time\":\"2026-11-18T11:00:00Z\",\"result\":\"ok\",\"sha\":\"$l2\"}" >> "$ST/cards.jsonl"
  # The loop's shell, as `conveyor.sh run` starts it.
  # shellcheck disable=SC2034 # HERE is read by the lines of conveyor.sh and commands/run.sh run by the eval
  ( HERE=$SRC; export CONVEYOR_MAIN=$R CONVEYOR_CARDS=$T/$CASE/cards
    eval "$(sed -n '/^\. "\$HERE\/lib\/portable.sh"/,/^\. "\$HERE\/lib\/records.sh"/p' "$SRC/conveyor.sh")"
    eval "$(grep '^\. "\$HERE/lib/' "$SRC/commands/run.sh")"
    names || exit 1; push c2 2; checkheld && echo held > "$T/$CASE/held" ) > "$T/$CASE/push.out" 2>&1
  [ "$(git -C "$T/$CASE/origin" rev-parse main)" = "$base" ] || fail "the push was not held: $(cat "$T/$CASE/push.out")"
  [ "$(cat "$STUB/ran" 2>&1)" = "$l2 lib/cart.test.js
$l1 lib/cart.test.js" ] || fail "the run did not run lib/cart.test.js alone on main, then on c1's landing: $(cat "$STUB/ran" "$T/$CASE/push.out" 2>&1)"
  [ ! -e "$STUB/whole" ] && [ ! -e "$STUB/tests" ] || fail "the run ran the whole suite or its runner: $(ls "$STUB")"
  [ "$(jq -c --arg s "$l2" '.reds[] | select(.sha == $s) | .cases[] | [.file, .landing.sha, .landing.card]' "$ST/mainred.json" 2>&1)" = "[\"lib/cart.test.js\",\"$l2\",\"c2\"]" ] \
    || fail "no main-fix entry names c2's landing: $(cat "$ST/mainred.json" "$T/$CASE/push.out" 2>&1)"
  st 'select(.step == "push") | "\(.result) \(.kind) \(.check) \(.reason)"' | grep -qF "fail check lib/cart.test.js the run before the push failed 1 test file(s) linked to the landings since the last push: lib/cart.test.js (broken by the landing ${l2:0:12} of c2)" \
    && [ -e "$T/$CASE/held" ] || fail "the push line does not hold the push naming the file and c2: $(st 'select(.step == "push")')"
}
