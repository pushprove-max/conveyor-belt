#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# No real-browser tests in this project, by the owner's order of 2026-11-14: the Board's
# browser layout tests ran a Chromium per case side by side, timed out Board cards on a busy machine and blocked them
# for hours. Exit 1, naming each line, when a tracked or new file under conveyor/ or .claude/ (outside conveyor/state)
# starts or names a browser for a test: playwright, puppeteer, a headless Chrome or Chromium, or CONVEYOR_BROWSER.
# test-changed.sh runs it on every test run; no-browser-tests.test.sh is its own test.
set -u
cd "$(dirname "$0")/.." || exit 1
pat='playwright|puppeteer|chrome-headless|headless[-_ ]?(chrome|chromium|shell)|--headless|CONVEYOR_BROWSER|chromium\.launch'
mapfile -t files < <(git ls-files -co --exclude-standard conveyor .claude | grep -v -e "^conveyor/state/" -e "^\.conveyor/no-browser-tests" | while read -r f; do [ -f "$f" ] && echo "$f"; done)
[ ${#files[@]} = 0 ] && exit 0
bad=$(grep -n -I -E "$pat" "${files[@]}" 2>/dev/null)
[ -z "$bad" ] && exit 0
printf "%s\n" "$bad" | sed "s/^/no browser tests (the owner's order, 2026-11-14): /" >&2
exit 1
