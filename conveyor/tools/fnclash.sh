#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# fnclash.sh <file>...: each function name that more than one of the shell files defines at the top level, one line
# each, `<name>: <file> <file>...` (file names without their folder), sorted; exit 1 when there is one, 2 when a file
# cannot be read. The engine's test runner (conveyor.test.sh) loads lib.sh and every tests/*.test.sh into one shell, so
# a second definition of a name replaces the first, and the cases of the first file run the other file's function.
# The body of a heredoc is a script written to a file, not a definition of the shell, and is skipped.
set -uo pipefail
[ $# -gt 0 ] || { echo "usage: fnclash.sh <file>..." >&2; exit 2; }
for f in "$@"; do [ -r "$f" ] || { echo "fnclash.sh: cannot read $f" >&2; exit 2; }; done
out=$(awk '
  FNR == 1 { hd = ""; f = FILENAME; sub(/.*\//, "", f) }
  hd != "" { l = $0; sub(/^\t+/, "", l); if (l == hd) hd = ""; next }
  {
    if (match($0, /^(function[ \t]+)?[A-Za-z_][A-Za-z0-9_]*[ \t]*\(\)/)) {
      n = substr($0, 1, RLENGTH); sub(/^function[ \t]+/, "", n); sub(/[ \t]*\(\)$/, "", n)
      if (!((n, f) in seen)) { seen[n, f] = 1; files[n] = files[n] " " f; count[n]++ }
    }
    s = $0
    while ((i = index(s, "<<")) > 0) {
      r = substr(s, i + 2)
      if (substr(r, 1, 1) == "<") { s = substr(r, 2); continue }
      if (substr(r, 1, 1) == "-") r = substr(r, 2)
      sub(/^[ \t]*/, "", r); sub(/^["\047]/, "", r)
      if (match(r, /^[A-Za-z_][A-Za-z0-9_]*/)) { hd = substr(r, 1, RLENGTH); break }
      s = r
    }
  }
  END { for (n in count) if (count[n] > 1) print n ":" files[n] }' "$@" | LC_ALL=C sort) || exit 2
[ -z "$out" ] || { printf '%s\n' "$out"; exit 1; }
