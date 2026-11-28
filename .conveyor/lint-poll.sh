#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# The pack's lint command for a test's wait with no ceiling: `bash .conveyor/lint-poll.sh <file>...` finds each loop
# that waits with one condition and a pause and nothing more, on one line or on several, in the test's own code or in
# the text of a script it writes:
# - for a file to come or to go: `until [ -e <file> ]; do sleep <n>; done`, `while [ ! -s <file> ]; do sleep <n>; done`,
#   `while [ -e <file> ]; do sleep <n>; done` (one file test of `[`, `[[` or test, with a `!` before it or in it or none);
# - for a command to pass or to fail: `until mkdir <lock>; do sleep <n>; done`, `until grep -q <text> <file>; do ...`,
#   `while kill -0 <pid>; do ...` (any one command that is not `[`, `[[`, test, `:`, true or false).
# When what it waits for never comes, such a loop runs until a limit outside the test ends it: a fixture of
# test-changed-failfast.test.sh waited so for 35 minutes of a proof run's 3600 s (issue 1840). The test waits with
# wait_until (conveyor/tests/wait.sh), and a script an engine case writes with wait_poll (the text wait_fn prints:
# conveyor/tests/wait.test.sh); both end at a ceiling and say what they waited for. No finding: a loop with a second
# condition (`||`, `&&`), or with more than the pause in its body (a count, a check of a process); a loop that
# compares texts or numbers (a wait on the clock); a loop with no condition (`while :`, a stand-in that goes on until
# it is killed); a loop in the text of a `timeout <n> bash -c` (or sh) on its line, which that limit ends. A comment
# line is not read. Each finding is printed in gcc form, as lint-shell.sh prints the findings of shellcheck:
# `<file>:<line>:1: error: a wait with no ceiling: use wait_until, or wait_poll in a script the test writes [poll-ceiling]`.
# Exit 1 with a finding, 0 with none, 2 when a file cannot be read.
set -u
rc=0
for f in "$@"; do
  if [ ! -r "$f" ] || [ -d "$f" ]; then echo "lint-poll: $f cannot be read" >&2; rc=2; continue; fi
  awk -v f="$f" '
    # waits(c): whether the condition c, one command, is a wait for a file or for a command.
    function waits(c) {
      sub(/^![ \t]+/, "", c); sub(/[ \t]+$/, "", c)
      if (c ~ /^(:|true|false|\(\()/) return 0
      if (c !~ /^(\[\[?|test)[ \t]/) return 1
      return c ~ /^(\[\[?|test)[ \t]+(![ \t]+)?-[edfsrwxLhpS][ \t]+("[^"]*"|[^ \t]+)([ \t]+\]\]?)?$/
    }
    { s = s ($0 ~ /^[[:space:]]*#/ ? "" : $0) "\n" }
    END {
      gsub(/>&/, ">_", s); gsub(/&>/, "_>", s) # a redirection is no second condition
      sep = "[ \t]*(;|\n)[ \t\n]*do[ \t\n]+sleep[ \t]+"
      # The loop: its start (after the \n of a printf text too), one command, do, the pause and done.
      re = "(^|[^A-Za-z0-9_]|\\\\n)(until|while)[ \t]+([^;&|\n\"\047]|\"[^\"\n]*\"|\047[^\047\n]*\047)+" sep \
        "[^ \t\n;&|]+[ \t]*(#[^\n]*)?(;|\n)[ \t\n]*done([^A-Za-z0-9_]|$)"
      for (at = 0; match(substr(s, at + 1), re); at = e - 1) {
        k = at + RSTART; e = k + RLENGTH; m = substr(s, k, e - k); match(m, /(until|while)[ \t]+/); k += RSTART - 1
        c = substr(m, RSTART + RLENGTH); match(c, sep); c = substr(c, 1, RSTART - 1)
        if (!waits(c)) continue
        pre = substr(s, 1, k - 1); n = gsub(/\n/, "\n", pre) + 1; sub(/.*\n/, "", pre)
        if (pre ~ /(^|[^A-Za-z0-9_.\/-])timeout[ \t]+([^ \t;&|]+[ \t]+)+(bash|sh)[ \t]+-c[ \t]+["\047][^"\047]*$/) continue
        printf "%s:%d:1: error: a wait with no ceiling: use wait_until, or wait_poll in a script the test writes [poll-ceiling]\n", f, n; bad = 1
      }
      exit bad }' "$f" || { r=$?; [ "$r" = 1 ] && [ "$rc" = 0 ] && rc=1; [ "$r" = 1 ] || rc=2; }
done
exit "$rc"
