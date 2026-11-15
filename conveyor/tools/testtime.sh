#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# testtime.sh <file> -- <command>...: runs the command once, then prints the test file's timing line, as a project's
# test runner says it in its log for the CPU budget of a test file (conveyor/README.md, The CPU budget of a test file):
# `TESTRUN sec<TAB><file><TAB><clock seconds><TAB><CPU seconds>`, the CPU seconds the user plus system time of all the
# command started. It changes nothing else: the command's output and exit code are its own. A project copies it beside
# its test script and wraps each test file's run with it.
[ $# -ge 3 ] && [ "$2" = -- ] || { echo "usage: testtime.sh <file> -- <command>..." >&2; exit 2; }
f=$1; shift 2
# The children's user and system times (the second line of `times`), before and after, written to a file by this
# shell itself: `times` in a command substitution reads the subshell's own, which start at 0.
t=$(mktemp "${TMPDIR:-/tmp}/testtime.XXXXXX") || exit 1
trap 'rm -f "$t"' EXIT
times > "$t"; s=${EPOCHREALTIME/,/.}
"$@"; rc=$?
e=${EPOCHREALTIME/,/.}; times >> "$t"
# Either locale's decimal point.
awk -v f="$f" -v a="$s" -v b="$e" 'function c(x, a) { sub(/s$/, "", x); split(x, a, "m"); return a[1] * 60 + a[2] } { gsub(/,/, ".") }
  NR == 2 || NR == 4 { n[NR] = c($1) + c($2) } END { printf "TESTRUN sec\t%s\t%.1f\t%.1f\n", f, b - a, n[4] - n[2] }' "$t"
exit $rc
