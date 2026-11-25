#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 120
# Engine cases: the split before the build (splitcheck(), lib/slices.sh) while a slice that an earlier card of the same
# issue filed for its grown change is still open. The helpers (slices, big, SPLIT2, FXWT) are slices.test.sh's.
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"

# Issue 7, the rule On, the judge splitting it (SPLIT2). An earlier card (c6) filed #100101 for its grown change
# (splitfile(), so it has the body GitHub shows), and it is open (list-filed). The card's split check runs after
# <shell>, as card() calls it.
splitopen() { # <shell or ''>
  slices on "$SPLIT2" "[$(big 7)]"; touch "$STUB/list-filed"
  fx_in "splitfile c6 \"\$(big 7)\" '[{\"title\":\"old\",\"doneWhen\":[\"x\"],\"files\":[\"src/s1.sh\"],\"dependsOn\":[]}]' 0 >/dev/null; $1"'splitcheck c1-7 7'
}
splitwhy() { st 'select(.step == "split") | [.result, (.split.filed // null), .split.why] | @json'; }

# Bug caught (review of #1684): the owner edited the issue to hold the open grown slice's work, so a split before the
# build filed a second copy of it. No slice is filed, the card builds the issue whole, and the split line says why.
t_slicesopengrown() {
  splitopen ''
  [ "$RC" = 0 ] && [ "$(jq -s length "$STUB/filed")" = 1 ] && [ "$(jq -c .held "$ST/control.json")" = '[]' ] \
    || fail "splitcheck c1-7 7, with #100101 open, filed a slice or held #7, or ended the card (exit $RC): filed $(jq -sc 'map(.number)' "$STUB/filed") held $(jq -c .held "$ST/control.json"): $(cat "$T/$CASE/run.out")"
  [ "$(splitwhy)" = '["split",null,"two parts; #100101, slices that earlier cards filed for its grown changes, are still open, so no slice is filed and the issue is built whole"]' ] \
    || fail "the split line of splitcheck c1-7 7, with #100101 open, does not say why no slice was filed: $(cat "$ST/cards.jsonl")"
}
# GitHub's list of open issues fails: the open grown slices are not known, so nothing is filed. Bug caught: with them
# unknown, the split filed its slices anyway.
t_slicesopenunread() {
  splitopen 'echo "exit 1" > "$STUB/list-cmd"; '
  [ "$RC" = 0 ] && [ "$(jq -s length "$STUB/filed")" = 1 ] || fail "splitcheck c1-7 7, with the open issues unread, filed a slice or ended the card (exit $RC): $(cat "$T/$CASE/run.out")"
  [ "$(splitwhy)" = '["split",null,"two parts; the open follow-ups of #7 could not be read, so no slice is filed and the issue is built whole"]' ] \
    || fail "the split line of splitcheck c1-7 7, with the open issues unread, does not say why no slice was filed: $(cat "$ST/cards.jsonl")"
}
