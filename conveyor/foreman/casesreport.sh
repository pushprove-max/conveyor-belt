# SPDX-License-Identifier: Apache-2.0
# The Foreman's test files that run their cases side by side (each case in a subshell, its output in <dir>/<case>.out,
# a mark <dir>/<case>.passed when it passed) report them through this. Sourced, never run.
# casesreport <dir> <name prefix> <case>...: for each case, prints its output to stderr, then the line `ok <prefix><case>`
# when it passed: the name its FAIL line gives, which is the one the main-red proof reads a case's pass by (a file that
# prints one summary line gives a case no result). Returns 1 when a case did not pass.
casesreport() {
  local d=$1 p=$2 c bad=0
  shift 2
  for c in "$@"; do
    cat "$d/$c.out" >&2
    if [ -e "$d/$c.passed" ]; then echo "ok $p$c"; else bad=1; fi
  done
  return "$bad"
}
