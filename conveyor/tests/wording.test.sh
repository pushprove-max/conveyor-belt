#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 120
# Engine cases: the review wording /conveyor-belt:review gives Codex (conveyor.sh wording).
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"
# The engine folder, as lib.sh sets it: named here too, so the release closure (tools/closure.sh) follows this file's paths.
SRC=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)

# Bug: the review reads its wording from somewhere other than the plugin's own review prompts, or gives each pass
# the wrong part. In a project whose pack names no wording, the adversarial pass gets rules/review.md's three angles,
# the closing passes its review focus, and each the standing checks.
t_wording() {
  local a r; setup '[]'
  a=$(cd "$R" && loop wording adversarial) && r=$(cd "$R" && loop wording review) || fail "wording failed: $a $r"
  [ "$a" = "$(printf '%s\n\n%s' "$(awk '/^# adversarial$/ { on = 1; next } /^# / { on = 0 } on' "$SRC/rules/review.md" | sed '1d;$d')" \
      "$(awk '/^# every pass$/ { on = 1; next } on' "$SRC/rules/review.md" | sed '1d')")" ] || fail "the adversarial wording is not the plugin's: $a"
  grep -q '^Angle 3 of 3, tests and words' <<<"$a" && ! grep -q '^Correctness bugs' <<<"$a" || fail "the adversarial wording: $a"
  head -1 <<<"$r" | grep -qx 'Correctness bugs, security problems and missing tests in the changed lines.' && grep -q '^Severity: critical is P0' <<<"$r" \
    && ! grep -q '^Angle' <<<"$r" || fail "the review wording: $r"
  # Bug (#779): a review is not told to raise a proxy test (other test files, the real loop, polling) with no comment
  # saying why as a low finding.
  grep -qF 'Proxy tests: a test the change adds or changes that runs other test files or the suite runner, runs the real loop, or polls a real process until a condition holds, with no comment beside it that says what a direct check cannot show, is a low finding (P3).' <<<"$r" \
    || fail "the review wording lacks the direct-check rule: $r"
}

# Bugs: the pack's review.wording is not read, or a file with a section missing is used anyway (the command must
# stop rather than review with made-up wording), or a path out of the checkout is read.
t_wordingown() {
  local out; setup '[]'
  printf '# adversarial\n\nOur angle.\n\n# review\n\nOur focus.\n\n# every pass\n\nOur checks.\n' > "$R/our-review.md"
  tune '.review.wording = "our-review.md"'
  out=$(cd "$R" && loop wording review) && [ "$out" = $'Our focus.\n\nOur checks.' ] || fail "the project's wording was not read: $out"
  printf '# review\n\nOur focus.\n' > "$R/our-review.md"
  out=$(cd "$R" && loop wording review 2>&1); [ $? = 2 ] && grep -qF "has no '# every pass' section" <<<"$out" || fail "a file with no every-pass section was used: $out"
  tune '.review.wording = "../outside.md"'
  out=$(cd "$R" && loop wording review 2>&1); [ $? = 2 ] && grep -q 'not a path inside the checkout' <<<"$out" || fail "a path out of the checkout was read: $out"
}
