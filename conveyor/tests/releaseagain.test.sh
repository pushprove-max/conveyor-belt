#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 120
# Engine cases: a release made from a suite run that passed before: the Board's Release reuses release-prep's pass on
# main's head, not on a main that moved since, and release tried again after a refusal keeps that pass's record. Their
# fixture is releaseboard.test.sh's runsetup (release.test.sh's cutsetup).
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"

# relreusesetup <suite>: runsetup, with the record of a release-prep of 1.1.0 that passed on main's head ($O), main not
# moved, and its passing status kept by gh, as release-prep leaves them.
relreusesetup() {
  runsetup "$1"
  mkdir -p "$T/$CASE/cards/release" && printf '[{"context":"conveyor/release-suite","state":"success"}]\n' > "$STUB/statuses" \
    && jq -cn --arg o "$O" '{kind: "release", step: "release-prep", version: "1.1.0", since: "2026-11-15T08:00:00Z", ended: "2026-11-15T08:25:00Z",
      state: "passed", sha: $o, mode: "parallel", atOnce: 2, done: 3, failed: 0, cases: [], moved: false, main: $o, reasons: [], pid: 1}' > "$RUN" || fail "the fixture could not be made"
}
# Bug (#35): the Board's Release ran the whole suite again (release-prep, about 25 min) on the commit whose pass
# release-prep had just recorded. The suite here fails if called.
# Bug (#821): release dropped release-prep's mode, so step 2 showed the passed suite with no mode.
t_relreuse() {
  local O RUN out
  relreusesetup 'exit 1'
  out=$(loop release-run 1.1.0 2>&1) && grep -q 'with the suite that passed on' <<<"$out" || fail "release-run did not start release alone on the pass: $out"
  relwait "the run did not end" '.step == "release" and .ended != null'
  [ ! -e "$STUB/runs" ] || fail "the suite ran again on the commit it passed on: $(cat "$T/$CASE/cards/release/run.log")"
  jq -e --arg o "$O" '.state == "released" and .sha == $o and .done == 3' "$RUN" > /dev/null || fail "release did not release the passed commit $O: $(cat "$RUN") $(cat "$T/$CASE/cards/release/run.log")"
  jq -e '.mode == "parallel" and .atOnce == 2' "$RUN" > /dev/null || fail "release lost the mode, or the files at once (#1174), of release-prep's suite it kept: $(cat "$RUN")"
  [ -n "$(git -C "$T/$CASE/origin" tag -l v1.1.0)" ] || fail "no tag v1.1.0 was pushed"
}
# Bug (#35): a pass on a main that moved since is reused, so a commit no suite tested is released. Here a card lands
# after the pass: release-run runs release-prep first, on the new head.
t_relreusemoved() {
  local O RUN out new
  relreusesetup true
  git -C "$R" commit -q --allow-empty -m 'fix: landed after the pass' && git -C "$R" push -q origin main || fail "the fixture could not be made"
  new=$(git -C "$R" rev-parse HEAD)
  out=$(loop release-run 1.1.0 2>&1) && grep -q 'release-prep 1.1.0 is running' <<<"$out" || fail "release-run did not start release-prep: $out"
  relwait "the run did not end" '.step == "release" and .ended != null'
  [ "$(wc -l < "$STUB/runs" 2>/dev/null)" = 1 ] && [ "$(cat "$STUB/full-at")" = "$new" ] || fail "the suite did not run once on the new head $new: $(cat "$STUB/full-at" 2>&1)"
  jq -e --arg n "$new" '.state == "released" and .sha == $n' "$RUN" > /dev/null || fail "release did not release the tested head: $(cat "$RUN")"
}
# Bug: release tried again after a refusal takes release-prep's pass from the status and runs no suite, but its record
# lost the commit and cases that pass was of.
# Bug (#821): the refused release, and the release tried again after it, lost that pass's mode, while step 2 shows
# the pass.
t_relretry() {
  local O RUN out
  runsetup 'mkdir -p "$CONVEYOR_TEST_LOG/cases/ok" && : > "$CONVEYOR_TEST_LOG/cases/ok/one"'
  out=$(loop release-prep 1.1.0 --parallel 2>&1) || fail "release-prep failed: $out"
  echo changed >> "$R/docs/releases/1.1.0.md"
  out=$(loop release 1.1.0 2>&1); [ $? = 1 ] || fail "release was not refused with an uncommitted change: $out"
  jq -e '.state == "refused" and .mode == "parallel"' "$RUN" > /dev/null || fail "the refused release lost the passed suite's mode: $(cat "$RUN")"
  printf '# 1.1.0\n\n## Fixes\n\n- A fix\n' > "$R/docs/releases/1.1.0.md"
  out=$(loop release 1.1.0 2>&1) || fail "the release tried again was refused: $out"
  jq -e --arg o "$O" '.state == "released" and .sha == $o and .done == 1 and .mode == "parallel"' "$RUN" > /dev/null || fail "the released record lost the tested commit, its mode or its cases: $(cat "$RUN")"
  [ "$(wc -l < "$STUB/runs")" = 1 ] || fail "the suite ran $(wc -l < "$STUB/runs") times, not once"
}
