#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# The pack's lint command for an engine setting given to a test command: `bash .conveyor/lint-prefix.sh <file>...`
# finds each `NAME=value tests|testonce|hosttests|bugrun|scoped ...` whose NAME is not a CONVEYOR_ one. bash exports
# a variable set in front of a call to every process the call starts, so a test file inherited the engine's own
# setting (TEST_STILL, 2026-11-27: a test's own engine refused its runs, and its cases failed in every pre-review run).
# The engine gives such a setting with scoped() (conveyor/lib/testrun.sh); a CONVEYOR_ variable is one for the test
# command itself and may be set so. Each finding is printed in gcc form, as lint-shell.sh prints shellcheck's:
# `<file>:<line>:1: error: <NAME> set in front of <function>: the test files it starts inherit it; use scoped [prefix-env]`.
# A comment line is not read, nor a value with a space in it. Exit 1 with a finding, 0 with none, 2 when a file
# cannot be read.
set -u
rc=0
for f in "$@"; do
  if [ ! -r "$f" ] || [ -d "$f" ]; then echo "lint-prefix: $f cannot be read" >&2; rc=2; continue; fi
  awk -v f="$f" '
    /^[[:space:]]*#/ { next }
    { l = $0; while (gsub(/\$\{[^{}]*\}|\$\([^()]*\)/, "X", l)) {} # a value of ${...} or $(...) is one word
      m = split(l, st, /[;&|(){}]/)
      for (s = 1; s <= m; s++) { n = split(st[s], w, /[[:space:]]+/); k = 0
        for (i = 1; i <= n; i++) {
          if (w[i] == "") continue
          if (w[i] ~ /^[A-Za-z_][A-Za-z0-9_]*=/) { a[++k] = w[i]; continue }
          if (k && w[i] ~ /^(tests|testonce|hosttests|bugrun|scoped)$/)
            for (j = 1; j <= k; j++) { v = a[j]; sub(/=.*/, "", v)
              if (v !~ /^CONVEYOR_/) { printf "%s:%d:1: error: %s set in front of %s: the test files it starts inherit it; use scoped [prefix-env]\n", f, NR, v, w[i]; bad = 1 } }
          break } } }
    END { exit bad }' "$f" || { r=$?; [ "$r" = 1 ] && [ "$rc" = 0 ] && rc=1; [ "$r" = 1 ] || rc=2; }
done
exit "$rc"
