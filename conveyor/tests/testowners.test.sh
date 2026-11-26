#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 60
# Engine cases: the case names and test file names testowners (lib/testfiles.sh) reads from main's test files, which
# give a runner's failures and flaky entries to the files that define their cases.
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"

# testowners as the snapshot loads it (its . lines and SNAPLIBS, commands/snapshot.sh), in a shell of the case's main
# ($R), printing [defs, refs].
# shellcheck source=/dev/null disable=SC2154 # the snapshot's libraries, by its . lines or its SNAPLIBS list; testowners sets defs and refs
to_owners() { ( export CONVEYOR_MAIN=$R CONVEYOR_CARDS=$T/$CASE/cards; . "$SRC/conveyor.sh" state-dir > /dev/null \
  && eval "$(grep -e '^\. "\$HERE/lib/' -e '^SNAPLIBS=' "$SRC/commands/snapshot.sh")" \
  && for l in ${SNAPLIBS-}; do . "$HERE/lib/$l.sh" || exit 1; done && testowners \
  && jq -cn --argjson d "$defs" --argjson r "$refs" '[$d, $r]' ); }

# Bug it catches: testowners read main's test files with grep, which follows a link, so a test file committed as a
# link to a file outside the checkout gave that file's functions as its cases (private) and its test file names as
# its own (other.test.sh). A link is read as no file; the checkout's own test file is still read.
t_toownlink() {
  setup '[]'
  mkdir -p "$R/tests" "$T/$CASE/outside"
  printf 't_private() { bash other.test.sh; }\n' > "$T/$CASE/outside/secret.sh"
  printf 't_own() { bash run.test.sh; }\n' > "$R/tests/own.test.sh"
  ln -s "$T/$CASE/outside/secret.sh" "$R/tests/linked.test.sh"
  git -C "$R" add -A && git -C "$R" commit -qm 'tests' || fail "main's files"
  got=$(to_owners) || fail "testowners failed: $got"
  [ "$(jq -c '[.[0].private, .[1]["tests/linked.test.sh"]]' <<<"$got")" = '[null,null]' ] \
    || fail "testowners read the file outside main that tests/linked.test.sh links to: $got"
  [ "$(jq -c '[.[0].own, .[1]["tests/own.test.sh"]]' <<<"$got")" = '[["tests/own.test.sh"],["run.test.sh"]]' ] \
    || fail "the checkout's own test file, its case and the runner it names: $got"
}
