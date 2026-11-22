#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 120
# Engine cases: setup offers the project's .conveyor/test-machine.sh, the script that installs what its suite needs on
# the box a release's suite runs on (machineoffer(), lib/setup.sh).
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"

# Bugs it catches: a project with no script was never told it could have one; yes wrote no script, or one that names
# no tool of the pack's test commands (a shell, jq and git are on any box and are left out); and a script the project
# had finished was written over by a second yes. no writes nothing and says nothing.
t_setupmachine() {
  local X out f
  setupdone; f=$S/.conveyor/test-machine.sh
  jq '.test.command = "npm test" | .test.full = "pytest -q tests/ && bash run.sh" | .test.fileCommand = "bash run.sh"' "$S/.conveyor/project.json" > "$T/$CASE/p" \
    && mv "$T/$CASE/p" "$S/.conveyor/project.json" || fail "the pack could not be changed"
  out=$(cd "$S" && bash "$X" setup --fast-lane no --research-lane no 2>&1) && [ ! -e "$f" ] && grep -qF -- 'pass --test-machine yes to write one from the pack' <<<"$out" \
    || fail "setup with no .conveyor/test-machine.sh did not offer one, or wrote it unasked: $out"
  out=$(cd "$S" && bash "$X" setup --fast-lane no --research-lane no --test-machine no 2>&1) && [ ! -e "$f" ] && ! grep -q 'test-machine' <<<"$out" \
    || fail "setup --test-machine no wrote the script or offered it: $out"
  out=$(cd "$S" && bash "$X" setup --fast-lane no --research-lane no --test-machine yes 2>&1) && grep -qx '# needs: npm' "$f" && grep -qx '# needs: pytest' "$f" \
    && [ "$(grep -c '^# needs:' "$f")" = 2 ] && bash -n "$f" && grep -qF 'the project must finish it' <<<"$out" \
    || fail "setup --test-machine yes did not write a script with a needs line for npm and pytest only, or did not say the project must finish it: $out $(cat "$f" 2>&1)"
  echo 'sudo apt-get install -y nodejs' >> "$f"; cp "$f" "$T/$CASE/finished"
  out=$(cd "$S" && bash "$X" setup --fast-lane no --research-lane no --test-machine yes 2>&1) && cmp -s "$f" "$T/$CASE/finished" && ! grep -q 'test-machine' <<<"$out" \
    || fail "setup changed or offered again a .conveyor/test-machine.sh the project had: $out"
}
