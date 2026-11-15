#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# notes-check.sh <notes file, or - for stdin> [<name to report it by>]: the mechanical rules of the release notes style
# (docs/releases.md, Release notes). The notes are for users: they hold no ### heading, no issue or pull request number
# (#12), no commit hash (7 or more hex characters, with a digit and a letter), no path or file name, and no Closes
# line. A web address is not taken for a path. A slash command (/conveyor-belt:setup) is not a path: it has no name
# before its slash.
# Exit 0: none found; 1: one line per finding on stdout, "<name>:<line>: <rule>: <the line>"; 2: the notes cannot be read.
# Run by `conveyor.sh release` on the notes it would release, and by release-prep on the draft it writes.
set -uo pipefail
[ $# -ge 1 ] && [ $# -le 2 ] || { echo "usage: notes-check.sh <notes file, or -> [<name>]" >&2; exit 2; }
name=${2:-$1}
if [ "$1" = - ]; then text=$(cat) || exit 2; else text=$(cat -- "$1" 2>/dev/null) || { echo "notes-check: $1 cannot be read" >&2; exit 2; }; fi
out=$(jq -nRr --arg f "$name" '
  [["a ### heading", "^\\s*###"],
   ["an issue or pull request number", "(^|[^\\w&])#[0-9]+\\b"],
   ["a commit hash", "\\b(?=[0-9a-f]*[0-9])(?=[0-9a-f]*[a-f])[0-9a-f]{7,}\\b"],
   ["a path or file name", "[\\w.-]+/[\\w.-]+/|[\\w.-]*[\\w-]/[\\w-][\\w.-]*\\.[A-Za-z]{1,5}\\b|(^|[\\s`(\"])\\.[\\w-]+/|\\b[\\w-]+\\.(sh|py|jq|json|md|js|ts|jsx|tsx|mjs|cjs|yml|yaml|toml|txt|css|html|svg|png|jpg|jpeg|gif|webp|ico)\\b"],
   ["a Closes line", "\\bCloses\\b"]] as $rules
  | [inputs] | to_entries[] | (.value | gsub("[A-Za-z][A-Za-z0-9+.-]*://\\S+"; "")) as $l
  | .key as $i | .value as $raw | $rules[] as $r | select($l | test($r[1])) | "\($f):\($i + 1): \($r[0]): \($raw)"' <<<"$text") || exit 2
[ -z "$out" ] || { printf '%s\n' "$out"; exit 1; }
