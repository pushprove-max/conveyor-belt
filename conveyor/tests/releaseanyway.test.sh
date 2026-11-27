#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 120
# Engine cases: a release over a red suite, the owner's choice (`conveyor.sh release <version> --anyway --by <who>`,
# and the Board's Release anyway, `conveyor.sh release-run anyway <version> --by <who>`). Their fixture is anysetup,
# below (releaseboard.test.sh's runsetup). A red suite without --anyway is refused as before: release.test.sh's
# t_cutsuite.
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"

# anysetup: runsetup with a suite that fails one file (a.test) and one case of it (breaks), as the engine's runner
# names them, and a gh that keeps each conveyor/release-suite status it is sent and the GitHub release's body
# ($STUB/body).
anysetup() {
  runsetup 'mkdir -p "$CONVEYOR_TEST_LOG/cases/failed" && printf "%s\n" "TESTRUN files=2" "-- ok b.test" "-- FAIL a.test" > "$CONVEYOR_TEST_LOG/run.log" && : > "$CONVEYOR_TEST_LOG/cases/failed/breaks"; exit 1'
  printf '%s\n' '#!/usr/bin/env bash' 'if [ "$1" = release ] || [[ " $* " == *" -X POST "* ]]; then printf "%s\n" "$*" >> "$STUB/gh-calls"' \
    '[[ " $* " =~ \ state=([a-z]+)\  ]] && printf "[{\"context\":\"conveyor/release-suite\",\"state\":\"%s\"}]\n" "${BASH_REMATCH[1]}" > "$STUB/statuses" || :' \
    'while [ $# -gt 0 ]; do [ "$1" != --notes-file ] || cp "$2" "$STUB/body"; shift; done' \
    'else cat "$STUB/statuses" 2>/dev/null || echo "[]"; fi' > "$STUB/gh"
}
# Bugs: --anyway releases a head no release-prep suite ran on, so a commit no one tested goes out; or, over the red run
# of the head, it is still refused (no honest way to release), runs the suite again, or posts a success status the
# suite did not earn; or the release does not say who released it over which failures: the output before it goes, the
# release's record and the GitHub release's body (the notes, with a "Known test failures" section) name them.
t_relanyway() {
  local O RUN out
  anysetup
  out=$(loop release 1.1.0 --anyway --by 'the owner' 2>&1); [ $? = 1 ] && grep -q "refused, nothing tagged or released: --anyway: release-prep's suite of 1.1.0 did not run and fail on ${O:0:12}" <<<"$out" \
    || fail "--anyway with no suite run on the head was not refused: $out"
  [ ! -e "$STUB/runs" ] && [ -z "$(git -C "$T/$CASE/origin" tag -l v1.1.0)" ] && ! grep -q '^release' "$STUB/gh-calls" 2>/dev/null || fail "the refused --anyway ran the suite or released"

  out=$(loop release-prep 1.1.0 2>&1); [ $? = 1 ] && grep -q "statuses/$O -f state=failure" "$STUB/gh-calls" || fail "release-prep did not fail on the red suite: $out"
  # Bug: --by goes into the published release notes unchecked, so a home path in it is made public. (The home path and
  # the address below are put together here, so this file holds none itself.)
  local hp=/ho"me/someone" by="the owner on 10.0.0".1
  out=$(loop release 1.1.0 --anyway --by "$hp" 2>&1); [ $? = 1 ] && grep -q "refused, nothing tagged or released: --anyway: the privacy check finds something in --by" <<<"$out" \
    && grep -q 'home path' <<<"$out" && ! grep -qF "$hp" <<<"$out" || fail "a home path in --by ($hp) was not refused before the release: $out"
  [ -z "$(git -C "$T/$CASE/origin" tag -l v1.1.0)" ] && ! grep -q '^release' "$STUB/gh-calls" || fail "the refused --by was tagged or released"
  # Bug (#821): the release refused over release-prep's failed suite lost that suite's mode, while step 2 shows it.
  jq -e '.state == "refused" and .mode == "serial"' "$RUN" > /dev/null || fail "the refused release lost the failed suite's mode: $(cat "$RUN")"
  # Bug (#1648): a private address in --by was refused as a privacy hit, though it is none; the release goes out
  # with --by as written, in its output, record and notes.
  out=$(loop release 1.1.0 --anyway --by "$by" 2>&1) || fail "--anyway over the red run of the head, --by $by, was refused: $out"
  grep -qF "1.1.0 goes out over the failed suite on ${O:0:12}, by $by; failed files: a.test; failed cases: breaks" <<<"$out" \
    || fail "release did not print the failed files and cases before it went: $out"
  [ "$(wc -l < "$STUB/runs")" = 1 ] || fail "the suite ran again: $(wc -l < "$STUB/runs") runs"
  [ "$(grep -c statuses "$STUB/gh-calls")" = 1 ] && ! grep -q 'state=success' "$STUB/gh-calls" && grep -q '"state":"failure"' "$STUB/statuses" \
    || fail "a status other than release-prep's failure was posted: $(cat "$STUB/gh-calls")"
  [ -n "$(git -C "$T/$CASE/origin" tag -l v1.1.0)" ] && grep -q '^release create v1.1.0 --verify-tag ' "$STUB/gh-calls" || fail "v1.1.0 was not tagged and released: $out"
  jq -e --arg o "$O" --arg by "$by" '.state == "released" and .anyway == {sha: $o, files: ["a.test"], cases: ["breaks"], by: $by}' "$RUN" > /dev/null \
    || fail "the release's record does not say it went over the failed suite, by whom, with what: $(cat "$RUN")"
  [ "$(head -n "$(wc -l < "$R/docs/releases/1.1.0.md")" "$STUB/body")" = "$(cat "$R/docs/releases/1.1.0.md")" ] \
    && [ "$(tail -n +"$(($(wc -l < "$R/docs/releases/1.1.0.md") + 1))" "$STUB/body")" = "
## Known test failures

1.1.0 was released over a failed suite by $by: the whole suite failed on ${O:0:12}.

Failed files:

- a.test

Failed cases:

- breaks" ] || fail "the GitHub release's body is not the notes with the known test failures: $(cat "$STUB/body" 2>&1)"
}
# Bug: the Board's Release anyway releases a head that moved since release-prep's suite failed, so a commit that suite
# never ran on goes out over it.
t_relanywaymoved() {
  local O RUN out
  anysetup
  out=$(loop release-prep 1.1.0 2>&1); [ $? = 1 ] || fail "release-prep did not fail on the red suite: $out"
  git -C "$R" commit -q --allow-empty -m 'fix: landed after the red run' && git -C "$R" push -q origin main || fail "the fixture could not be made"
  out=$(loop release-run anyway 1.1.0 --by 'Board user u' 2>&1) && grep -q "over release-prep's failed suite, by Board user u" <<<"$out" \
    || fail "release-run anyway did not start release --anyway: $out"
  relwait "the run did not end" '.step == "release" and .ended != null'
  jq -e --arg o "${O:0:12}" '.state == "refused" and .anyway == null and any(.reasons[]; contains("failed on \($o), not on"))' "$RUN" > /dev/null \
    || fail "--anyway on a moved head was not refused for it: $(cat "$RUN") $(cat "$T/$CASE/cards/release/run.log")"
  [ -z "$(git -C "$T/$CASE/origin" tag -l v1.1.0)" ] && ! grep -q '^release' "$STUB/gh-calls" && [ "$(wc -l < "$STUB/runs")" = 1 ] \
    || fail "the moved head was tested again or released: $(cat "$STUB/gh-calls")"
}
# Bug: `release-run stop` of a failed release-prep (its wait on its fix cards, relstopwaiting(), lib/fulltest.sh)
# marked the record stopped, and release keeps a failed suite to go over only from a failed release-prep (relstart()):
# `release --anyway` on the same commit was refused, as if no suite had failed. The stop keeps the failed suite.
t_relanywaystopped() {
  local O RUN out
  anysetup
  out=$(loop release-prep 1.1.0 2>&1); [ $? = 1 ] || fail "release-prep did not fail on the red suite: $out"
  out=$(loop release-run stop 2>&1) && grep -q 'no longer waits on its fix cards' <<<"$out" || fail "release-run stop did not stop the failed run's wait: $out: $(cat "$RUN")"
  out=$(loop release 1.1.0 --anyway --by 'the owner' 2>&1) || fail "after release-run stop, release 1.1.0 --anyway over release-prep's failed suite was refused: $out"
  jq -e --arg o "$O" '.state == "released" and .anyway == {sha: $o, files: ["a.test"], cases: ["breaks"], by: "the owner"}' "$RUN" > /dev/null \
    || fail "the release after the stop does not say it went over the failed suite: $(cat "$RUN")"
}
