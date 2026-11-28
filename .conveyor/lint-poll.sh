#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# The pack's lint command for a test's wait with no ceiling: `bash .conveyor/lint-poll.sh <file>...` finds each loop
# that waits for a file with a pause and nothing more: `until [ -e <file> ]; do sleep <n>; done` and
# `while [ ! -s <file> ]; do sleep <n>; done` (one file test of `[`, `[[` or test, the `!` before it or in it; the
# loop on one line or on several; in the test's own code or in the text of a script it writes). When the file never
# comes, such a loop runs until a limit outside the test ends it: a fixture of test-changed-failfast.test.sh waited so
# for 35 minutes of a proof run's 3600 s (issue 1840). The test waits with wait_until (conveyor/tests/wait.sh), and a
# script an engine case writes with wait_poll (the text wait_fn prints: conveyor/tests/wait.test.sh); both end at a
# ceiling and say what they waited for. A loop with a second condition, or with more than the pause in its body (a
# count, a check of a process), is no finding, nor is one in the text of a `timeout <n> bash -c` (or sh) on its line,
# which that limit ends. A comment line is not read. Each finding is printed in gcc form, as lint-shell.sh prints the
# findings of shellcheck:
# `<file>:<line>:1: error: a wait for a file with no ceiling: use wait_until, or wait_poll in a script the test writes [poll-ceiling]`.
# Exit 1 with a finding, 0 with none, 2 when a file cannot be read.
set -u
rc=0
for f in "$@"; do
  if [ ! -r "$f" ] || [ -d "$f" ]; then echo "lint-poll: $f cannot be read" >&2; rc=2; continue; fi
  awk -v f="$f" '
    { s = s ($0 ~ /^[[:space:]]*#/ ? "" : $0) "\n" }
    END {
      t = "(\\[\\[?|test)[ \t]+"; nw = "([^A-Za-z0-9_]|$)"
      # The loop: its start (after the \n of a printf text too), the one file test, do, the pause and done.
      re = "(^|[^A-Za-z0-9_]|\\\\n)(until[ \t]+" t "|while[ \t]+(![ \t]+" t "|" t "![ \t]+))-[edfsrwxLhpS][ \t]+[^];&|\n]*(\\]\\]?)?" \
        "[ \t]*(;|\n)[ \t\n]*do[ \t\n]+sleep[ \t]+[^ \t\n;&|]+[ \t]*(#[^\n]*)?(;|\n)[ \t\n]*done" nw
      for (at = 0; match(substr(s, at + 1), re); at = e - 1) {
        k = at + RSTART; e = k + RLENGTH; match(substr(s, k, e - k), /(until|while)[ \t]/); k += RSTART - 1
        pre = substr(s, 1, k - 1); n = gsub(/\n/, "\n", pre) + 1; sub(/.*\n/, "", pre)
        if (pre ~ /(^|[^A-Za-z0-9_.\/-])timeout[ \t]+([^ \t;&|]+[ \t]+)+(bash|sh)[ \t]+-c[ \t]+["\047][^"\047]*$/) continue
        printf "%s:%d:1: error: a wait for a file with no ceiling: use wait_until, or wait_poll in a script the test writes [poll-ceiling]\n", f, n; bad = 1
      }
      exit bad }' "$f" || { r=$?; [ "$r" = 1 ] && [ "$rc" = 0 ] && rc=1; [ "$r" = 1 ] || rc=2; }
done
exit "$rc"
