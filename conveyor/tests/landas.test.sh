#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 300
# Engine cases: the rule Land as (lib/push.sh pushone, landas, landpr; lib/control.sh `control land-as`): with pr, the
# push sends main to conveyor/landing and keeps one pull request open from it, never pushing origin's default branch;
# with main, the push goes to the default branch and opens no pull request.
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"
# The engine folder, as lib.sh sets it: named here too, so the release closure (tools/closure.sh) follows this file's paths.
SRC=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)

# One engine function, in the loop's shell (conveyor.sh's own engine files, then the ones commands/run.sh loads).
la_eng() { # <command...>
  local a=("$@")
  # shellcheck disable=SC2034 # HERE is read by the lines of conveyor.sh and commands/run.sh run by the eval
  ( HERE=$SRC; export CONVEYOR_MAIN=$R CONVEYOR_CARDS=$T/$CASE/cards; set --
    eval "$(sed -n '/^\. "\$HERE\/lib\/portable.sh"/,/^\. "\$HERE\/lib\/records.sh"/p' "$SRC/conveyor.sh")"
    eval "$(grep '^\. "\$HERE/lib/' "$SRC/commands/run.sh")"
    names || exit 1; "${a[@]}" )
}
# Card <n> of issue <n> lands: a commit on main and its lines, as a card that passed its Done-when check (its reply's
# D<n> lines on the build line) and tests: a run of two cases of one file (its why names a second file, which the test
# cache kept off: the body must not list it as run), then a pass that reused that run (its line
# names no test, as card() writes it). With <fix rounds>, that many fix lines come before the tests.
la_land() { # <n> [<fix rounds>]
  local sha fx='' i
  for ((i = 0; i < ${2:-0}; i++)); do fx+="record c$1 $1 fix ok '{}'"$'\n'; done
  echo "$1" > "$R/f$1.txt"; git -C "$R" add -A; git -C "$R" commit -qm "card $1"; sha=$(git -C "$R" rev-parse HEAD)
  la_eng eval "record c$1 $1 picked ok '{\"title\":\"T$1\"}'
    record c$1 $1 build ok '{\"doneWhen\":{\"items\":2,\"met\":2,\"failed\":[]},\"doneLines\":[\"D1 met: t/a.test.sh case one\",\"D2 met: f$1.txt holds $1\"]}'
    $fx record c$1 $1 test pass '{\"ended\":\"passed\",\"tests\":{\"passed\":4,\"failed\":0},\"ran\":[\"t/a.test.sh\"],\"why\":{\"t/a.test.sh\":[\"changed\"],\"t/b.test.sh\":[\"passed before with the same inputs\"]},\"ranCases\":{\"t/a.test.sh\":[\"one\",\"two\"]}}'
    record c$1 $1 test pass '{\"sec\":1,\"usage\":{\"input\":0,\"write\":0,\"write1h\":0,\"read\":0,\"output\":0},\"reused\":true}'
    record c$1 $1 landed ok '{\"sha\":\"$sha\",\"product\":false}'" \
    || fail "card $1's lines could not be written"
}
# gh's pull requests, in front of the shared stub (its issues): each one a file $STUB/pr.<n>, numbered from 7; every
# pr call is logged in $STUB/pr-calls.
la_prstub() {
  mv "$STUB/gh" "$STUB/gh.issues"
  cat > "$STUB/gh" <<'EOF'
#!/usr/bin/env bash
[ "$1" = pr ] || exec "$STUB/gh.issues" "$@"
echo "$*" >> "$STUB/pr-calls"; c=$2; n=''; [ "$c" != edit ] || { n=$3; shift; }; shift 2
while [ $# -gt 0 ]; do case $1 in --head) h=$2 ;; --base) b=$2 ;; --title) t=$2 ;; --body) y=$2 ;; esac; shift 2; done
case $c in
  list) cat "$STUB"/pr.* 2>/dev/null | jq -cs --arg h "$h" --arg b "$b" '[.[] | select(.head == $h and .base == $b and .state == "OPEN") | {number}]' ;;
  create) n=$((7 + $(cat "$STUB"/pr.* 2>/dev/null | jq -s length)))
    jq -n --argjson n "$n" --arg h "$h" --arg b "$b" --arg t "$t" --arg y "$y" '{number: $n, head: $h, base: $b, title: $t, body: $y, state: "OPEN"}' > "$STUB/pr.$n"
    echo "https://github.com/o/r/pull/$n" ;;
  edit) jq --arg t "$t" --arg y "$y" '.title = $t | .body = $y' "$STUB/pr.$n" > "$STUB/pr.new" && mv "$STUB/pr.new" "$STUB/pr.$n" ;;
esac
EOF
  chmod +x "$STUB/gh"
}

# Issue 247 (the owner: cards land into one open pull request that collects them until it is merged).
# Bugs it catches: a pr push that still goes to origin's default branch; a second pull request opened while one is
# open; a body rewritten with only the cards of the last push (the earlier ones would not close on the merge); and a
# landing push not counted as pushed (atorigin), so the loop would push the same commit again at every turn; a body
# without each card's D<n> lines or its fix rounds (card 2 has two, card 1 none), or with the tests of its last test line (a
# reused pass names none) in place of the run that ran them, its files and their cases; and a card pushed into the pull request shown on the Board's belt as
# waiting for its issue to close (Push failed once the wait ends), when it closes only when the owner merges.
# The pack sets pr; cards 1 and 2 land and push, then card 3. Their issues are open, as they are until the merge.
t_landpr() {
  local o sha body want
  setup "[$(issue 1 2026-01-01),$(issue 2 2026-01-01),$(issue 3 2026-01-01)]"; la_prstub
  tune '.push.landAs = "pr"'
  o=$(git -C "$T/$CASE/origin" rev-parse main)
  la_land 1; la_land 2 2; la_eng push c2 2 || fail "the push failed"
  sha=$(git -C "$R" rev-parse HEAD)
  [ "$(git -C "$T/$CASE/origin" rev-parse refs/heads/conveyor/landing 2>/dev/null)" = "$sha" ] || fail "main was not pushed to conveyor/landing: $(cat "$ST/cards.jsonl" 2>/dev/null | tail -n 3)"
  [ "$(git -C "$T/$CASE/origin" rev-parse main)" = "$o" ] || fail "origin's default branch moved with Land as pr"
  [ "$(cat "$STUB"/pr.* | jq -sc 'map([.number, .head, .base, .state])')" = '[[7,"conveyor/landing","main","OPEN"]]' ] || fail "not one pull request from conveyor/landing: $(cat "$STUB"/pr.* 2>/dev/null)"
  body=$(jq -r .body "$STUB/pr.7")
  [ "$(grep -o '^Closes #[0-9]*' <<<"$body" | paste -sd ' ')" = 'Closes #1 Closes #2' ] || fail "the body does not close both issues, in landing order: $body"
  want=$(printf '%s\n' '## #2 T2' '' 'Closes #2' '- Card: `c2`' '- Done when: 2 of 2 met' '  - D1 met: t/a.test.sh case one' '  - D2 met: f2.txt holds 2' \
    '- Fix rounds: 2' '- Tests: passed, 4 passed, 0 failed' '  - `t/a.test.sh`: one, two')
  [ "$(awk '/^## / {p = ($0 == "## #2 T2")} p && NF' <<<"$body")" = "$(grep . <<<"$want")" ] || fail "card 2's part of the body is not its Done-when lines, its fix rounds and the tests it ran: $body"
  # Card 1 has none: with card 2's two, a count fixed at any one value fails one of these checks.
  [ "$(awk '/^## / {p = ($0 == "## #1 T1")} p && /^- Fix rounds:/' <<<"$body")" = '- Fix rounds: 0' ] || fail "card 1's part of the body does not give its zero fix rounds: $body"
  [ "$(loop snapshot | jq -c '[.belt[] | select(.issue == 1 or .issue == 2) | .issue]')" = '[]' ] || fail "a card pushed into the pull request is on the belt, waiting for its issue: $(loop snapshot | jq -c '.belt | map({issue, state})')"
  la_eng atorigin "$sha" || fail "the commit pushed to conveyor/landing does not count as pushed: the loop would push it again"
  la_land 3; la_eng push c3 3 || fail "the third push failed"
  [ "$(cat "$STUB"/pr.* | jq -s length)" = 1 ] || fail "a second pull request was opened while one was open"
  body=$(jq -r .body "$STUB/pr.7")
  [ "$(grep -o '^Closes #[0-9]*' <<<"$body" | paste -sd ' ')" = 'Closes #1 Closes #2 Closes #3' ] || fail "the updated body does not name the three cards: $body"
  [ "$(jq -r .title "$STUB/pr.7")" = 'Conveyor: 3 cards landed on main' ] || fail "the title was not rewritten: $(jq -r .title "$STUB/pr.7")"
  [ "$(git -C "$T/$CASE/origin" rev-parse main)" = "$o" ] || fail "origin's default branch moved at the third push"
}
# Bug it catches: the control record's main not taking over from the pack's pr (`control land-as`), so a push opens
# a pull request, or misses the default branch.
t_landmain() {
  local sha
  setup '[]'; la_prstub
  tune '.push.landAs = "pr"'
  loop control land-as main > /dev/null || fail "control land-as main was refused"
  # The Board's Rules tab shows the record's value over the pack's: the snapshot gives both.
  [ "$(loop snapshot | jq -c '[.packLandAs, .control.landAs]')" = '["pr","main"]' ] || fail "the snapshot does not give the pack's and the record's Land as: $(loop snapshot | jq -c '[.packLandAs, .control.landAs]')"
  la_land 1; la_eng push c1 1 || fail "the push failed"
  sha=$(git -C "$R" rev-parse HEAD)
  [ "$(git -C "$T/$CASE/origin" rev-parse main)" = "$sha" ] || fail "the push did not go to origin's default branch"
  [ ! -e "$STUB/pr-calls" ] && ! git -C "$T/$CASE/origin" rev-parse -q --verify refs/heads/conveyor/landing >/dev/null || fail "Land as main touched a pull request or conveyor/landing: $(cat "$STUB/pr-calls" 2>/dev/null)"
}
