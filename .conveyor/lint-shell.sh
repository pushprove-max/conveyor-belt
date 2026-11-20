#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# The pack's shellcheck lint command: `bash .conveyor/lint-shell.sh <file>...` runs shellcheck on the files, a warning
# or error (-S warning) printed as `<file>:<line>:<column>: <level>: <text> [SC<n>]` (-f gcc). A file with no #! line
# is read as bash (-s bash), as the engine's sourced files are. Its exit is the lint command's (docs/configuration.md,
# Lint): 0 no finding, 1 findings, 127 with `lint: missing shellcheck` when shellcheck is not installed, and 2 or more
# when shellcheck could not check the files (its own exit 2 to 4, or another end). test-changed.sh reads its output
# too, and keeps the findings on the lines a change made.
if ! command -v shellcheck > /dev/null; then echo "lint: missing shellcheck"; exit 127; fi
bang=() nobang=()
for f in "$@"; do if [ "$(head -c 2 -- "$f" 2>/dev/null)" = '#!' ]; then bang+=("$f"); else nobang+=("$f"); fi; done
rc=0
# One group's run: the exit is the higher of the two groups', but the first failure to run (2 or more) is kept.
sc() { local r=0; shellcheck "$@" 2>&1 || r=$?; [ "$r" -le "$rc" ] || [ "$rc" -ge 2 ] || rc=$r; }
[ ${#bang[@]} = 0 ] || sc -S warning -f gcc -- "${bang[@]}"
[ ${#nobang[@]} = 0 ] || sc -s bash -S warning -f gcc -- "${nobang[@]}"
exit "$rc"
