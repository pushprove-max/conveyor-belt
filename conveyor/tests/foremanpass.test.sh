#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 60
# Engine cases: the pass lines of the Foreman test files that run as one whole, as a main-red fix card's check
# (bugproof.sh redproof()) reads them: a case passes there only from an `ok <case>` line (testrun.sh testfails()), named
# as the case's FAIL line names it. A file that runs its cases one by one is checked by a run of a case
# (mainredproof.test.sh t_redproofforemanwaiter).
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"

# The awk program that prints a line for each gap in a Foreman test file's pass lines: a case a FAIL line names with no
# `ok <case>` line, an `ok` line naming no case, and a pass named for another case than the one whose result it reads.
# A case is a `FAIL [<case>]` name, or, for a FAIL line with a name built at run time (`FAIL [<prefix>$1]`), the prefix
# and the first word of a top-level call `<function> <word> ... & <pid>=$!`. A process `( ... FAIL [<case>] ... ) & <pid>=$!`
# is the case of its last FAIL line. A pass reads the result of <pid> from `wait "$<pid>"; ... echo "ok <case>"` or
# from a word `"$<pid> <case>"` of the list it waits on.
FOREMANPASS_AWK='match($0, /FAIL \[[a-z0-9-]*\$/) { pre = substr($0, RSTART + 6, RLENGTH - 7) }
{ s = $0; while (match(s, /FAIL \[[a-z0-9-]+\]/)) { cur = substr(s, RSTART + 6, RLENGTH - 7); fails[cur] = 1; s = substr(s, RSTART + RLENGTH) } }
(/^[^ ]/ || /\) & [a-z]+=\$!/) && match($0, /& [a-z]+=\$!/) { v = substr($0, RSTART + 2, RLENGTH - 5)
  n = /\) & / ? cur : ($2 ~ /^[a-z0-9-]+$/) ? pre $2 : ""; if (n != "") { of[v] = n; fails[n] = 1 } }
{ s = $0; while (match(s, /"\$[a-z]+ [a-z0-9-]+"/)) { split(substr(s, RSTART + 2, RLENGTH - 3), p, " "); oks[p[2]] = 1
    if (of[p[1]] != p[2]) print "the pass ok " p[2] " reads the result of the case " of[p[1]]; s = substr(s, RSTART + RLENGTH) } }
match($0, /echo "ok [a-z0-9-]+"/) { n = substr($0, RSTART + 9, RLENGTH - 10); oks[n] = 1
  if (match($0, /wait "\$[a-z]+"/) && of[v = substr($0, RSTART + 7, RLENGTH - 8)] != n) print "the pass ok " n " reads the result of the case " of[v] }
END { for (n in fails) if (!(n in oks)) print "the case " n " has no pass line ok " n
  for (n in oks) if (!(n in fails)) print "the pass ok " n " names no case" }'

# Bug it catches: these files printed `ok [<case>]: <check>`, `ok [<title>]` or nothing on a pass, so the check read no
# case as passed and blocked each fix as giving no result; and a pass named for another case (two names swapped in a wait
# list) would pass a case that still fails.
# It reads the files' text: they run only whole, and a whole run of another test file from an engine case is a nested
# run that the card's test step refuses (.conveyor/test-changed.sh metaran()).
t_foremanpasslines() {
  local f gaps
  for f in filing-repo watch-conveyor-newoutage watch-conveyor-outage watch-gh watch-idle watch-landed watch-limit \
    watch-recordsnewer watch-relfix watch-wait; do
    gaps=$(awk "$FOREMANPASS_AWK" "$SRC/foreman/$f.test.sh") || fail "conveyor/foreman/$f.test.sh could not be read"
    [ -z "$gaps" ] || fail "conveyor/foreman/$f.test.sh does not print one pass line ok <case> for each case its FAIL lines name: $(tr '\n' ';' <<<"$gaps")"
  done
}
