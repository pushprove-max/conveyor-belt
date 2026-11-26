#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 120
# Engine cases: the plugin's default limits of the rule Split large issues (the defaults of split.doneWhen, split.files
# and split.chars in schema/pack.schema.json, read by splitcheck(), lib/slices.sh). The fixture pack sets no `split`
# object, unless a case says so. Each case calls splitcheck() with a stub judge (CONVEYOR_SPLIT_CMD, a line in
# $STUB/judged per call); no card runs.
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"
# fx_in reads its worktree's .unfixed (FXWT): these cases have no worktree.
# shellcheck disable=SC2034 # read by fx_in (lib.sh)
FXWT=$T/none

# Issue 7 with <items> Done-when items, naming <files> files, padded so that its title and body hold <chars> characters
# (the split check counts the title, a newline and the body). The rule is shadow, the stub judge keeps the issue.
sdissue() { # <items> <files> <chars>
  local body="Change" i
  for ((i = 1; i <= $2; i++)); do body+=" src/f$i.sh"; done
  body+=$'.\n\nDone when:'
  for ((i = 1; i <= $1; i++)); do body+=$'\n'"- item $i"; done
  body+=$'\n\n'
  local pad=$(($3 - 2 - ${#body}))
  body+=$(head -c "$pad" /dev/zero | tr '\0' x)
  setup "$(jq -cn --arg b "$body" '[{number: 7, title: "t", body: $b, milestone: null, createdAt: "2026-11-01", labels: [], authorAssociation: "OWNER"}]')"
  jq -c '.rules.split = "shadow"' "$ST/control.json" > "$STUB/c.new" && mv "$STUB/c.new" "$ST/control.json"
  printf '%s\n' '{"verdict":"keep","why":"small"}' > "$STUB/answer"
  export CONVEYOR_SPLIT_CMD='cat > "$STUB/prompt"; echo x >> "$STUB/judged"; cat "$STUB/answer"'
}

# Bug caught: the default split.doneWhen stayed 6, so an issue of 4 Done-when items (the cost data's lower bound) was
# kept with no judge call.
t_slicedefaultdw() {
  sdissue 4 1 500
  fx_in 'splitcheck c1-7 7'
  [ "$(judged)" = 1 ] || fail "splitcheck c1-7 7, an issue of 4 Done-when items under a pack with no split object, asked the judge $(judged) times, not 1: $(st 'select(.step == "split")')"
}

# Bug caught: a default of doneWhen above 4, files above 6 or chars above 3000 let too much through unjudged; this issue
# is just under the new ones (3 items, 5 files, 2999 characters) and must be kept whole with the verdict under and no
# call. The size on the line proves that the issue was measured as built.
t_slicedefaultunder() {
  sdissue 3 5 2999
  fx_in 'splitcheck c1-7 7'
  [ "$RC" = 0 ] && [ "$(judged)" = 0 ] || fail "splitcheck c1-7 7, 3 items, 5 files, 2999 characters under a pack with no split object, asked the judge ($(judged) calls) or stopped (exit $RC): $(cat "$T/$CASE/run.out")"
  [ "$(st 'select(.step == "split") | [.result, .split.verdict, .split.size.doneWhen, .split.size.files, .split.size.chars] | @json')" = '["kept","under",3,5,2999]' ] \
    || fail "the split line of 3 items, 5 files and 2999 characters is not kept, under, 3, 5, 2999: $(st 'select(.step == "split")')"
}

# Bug caught: the default split.files stayed 8, so an issue naming 6 files (1 item, 500 characters) was kept with no
# judge call.
t_slicedefaultfiles() {
  sdissue 1 6 500
  fx_in 'splitcheck c1-7 7'
  [ "$(judged)" = 1 ] || fail "splitcheck c1-7 7, an issue naming 6 files under a pack with no split object, asked the judge $(judged) times, not 1: $(st 'select(.step == "split")')"
}

# Bug caught: the default split.chars stayed 6000, so an issue of 3000 characters (1 item, 1 file) was kept with no
# judge call.
t_slicedefaultchars() {
  sdissue 1 1 3000
  fx_in 'splitcheck c1-7 7'
  [ "$(judged)" = 1 ] || fail "splitcheck c1-7 7, an issue of 3000 characters under a pack with no split object, asked the judge $(judged) times, not 1: $(st 'select(.step == "split")')"
}

# Bug caught: the schema default beat the pack's own value. A pack that sets split.doneWhen to 6 keeps an issue of 5
# Done-when items whole, with no call, though the default of 4 would send it to the judge.
t_slicedefaultpack() {
  sdissue 5 1 500
  tune '.split.doneWhen = 6'
  fx_in 'splitcheck c1-7 7'
  [ "$RC" = 0 ] && [ "$(judged)" = 0 ] || fail "splitcheck c1-7 7, 5 items under a pack with split.doneWhen 6, asked the judge ($(judged) calls) or stopped (exit $RC): $(cat "$T/$CASE/run.out")"
  [ "$(st 'select(.step == "split") | [.result, .split.verdict] | @json')" = '["kept","under"]' ] \
    || fail "the split line of 5 items under split.doneWhen 6 is not kept and under: $(st 'select(.step == "split")')"
}
