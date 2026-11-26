#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Issue 1723. A card's Test step runs the test files the engine lists for its change: those the area map and
# .conveyor/test-links.json give each changed file, not test-changed.sh's own selection. A hook library
# (.claude/hooks/lib/<name>.sh) has no area and no test of its own name: its tests are the ones test-changed.sh's
# hooklibtests finds (the hooks' tests that name it, or name a hook that does). Bug it catches: the links named none of
# them, so a card that changed strip-quoted.sh or hook-fire-log.sh ran no hook test (git-safety.test.sh among them).
# Each test file a test-changed.sh listing (CONVEYOR_TEST_LIST, which runs no test) names for a change to each library
# of this checkout must be linked to that library in this checkout's links.
set -u
HERE=$(cd "$(dirname "$0")" && pwd -P); ROOT=$(dirname "$HERE")
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
AT=@
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t${AT}example.com GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t${AT}example.com
# The loop's test step sets these: left set, the listing would name the card's own files as well.
unset CONVEYOR_TEST_LOG CONVEYOR_SHELL_TEST_CASE CONVEYOR_TEST_FILE CONVEYOR_TEST_FILELIST CONVEYOR_TEST_RERUN CONVEYOR_TEST_CASES BASH_ENV
fails=0
no() { echo "not ok - $1"; fails=1; }

# A scratch repo: the real script and this checkout's real links, this checkout's hooks (their libraries and tests), and
# an area map of one engine file, so the map check passes.
R=$T/r; mkdir -p "$R/.conveyor" "$R/conveyor/tests"
cp "$HERE/test-changed.sh" "$HERE/test-share.sh" "$HERE/lint-shell.sh" "$HERE/test-links.json" "$R/.conveyor/"
: > "$R/.conveyor/test-lint.sh"; : > "$R/.conveyor/no-browser-tests.sh"; : > "$R/.conveyor/no-records-split.sh"
printf '%s\n' '{"area": "a", "file": "conveyor/x.sh"}' '{"area": "a", "test": "a.test.sh"}' > "$R/.conveyor/engine-areas.json"
echo one > "$R/conveyor/x.sh"; printf 't_one() {\n  :\n}\n' > "$R/conveyor/tests/a.test.sh"
(cd "$ROOT" && git ls-files -co --exclude-standard -z .claude/hooks | xargs -0 tar -cf -) | tar -xf - -C "$R" \
  && git -C "$R" init -q && git -C "$R" add -A && git -C "$R" commit -qm init || { echo "not ok - the scratch repo could not be made"; exit 1; }

n=0
for lib in "$R"/.claude/hooks/lib/*.sh; do
  lib=${lib#"$R/"}; n=$((n + 1)); rm -f "$T/list"
  # A line outside its functions: the coverage map cannot select its tests, so test-changed.sh lists hooklibtests'.
  echo true >> "$R/$lib"
  (cd "$R" && CONVEYOR_TEST_LIST=$T/list bash .conveyor/test-changed.sh) > "$T/out" 2>&1 || no "$lib changed: the listing failed: $(cat "$T/out")"
  git -C "$R" checkout -q -- "$lib"
  got=$(LC_ALL=C sort -u "$T/list" 2>/dev/null)
  missing=$(comm -23 <(printf '%s\n' "$got") <(jq -r --arg k "$lib" '.[$k] // [] | .[]' "$HERE/test-links.json" | LC_ALL=C sort -u) | grep .)
  [ -n "$got" ] && [ -z "$missing" ] \
    || no "$lib changed: the listing named '$(paste -sd' ' <<<"$got")'; not linked to it in .conveyor/test-links.json: '$(paste -sd' ' <<<"$missing")'"
  # The listing names first the tests that name the most of the library's users (the library, each hook that names
  # it): the engine runs only the first 5 of its linked files (CARDLINKED, conveyor/lib/testlist.sh selfirst()). Bug it
  # catches: the listing was in name order, and for strip-quoted.sh and hook-fire-log.sh those 5 left out
  # git-safety.test.sh, which runs git-safety.sh, a user of both.
  users=$(cd "$R" && grep -lF -- "lib/${lib##*/}" .claude/hooks/*.sh | sed 's,.*/,/,'; echo "lib/${lib##*/}")
  ranks=$(grep '^\.claude/hooks/__tests__/' "$T/list" | while IFS= read -r t; do grep -oF -f <(echo "$users") "$R/$t" | sort -u | grep -c .; done)
  [ "$ranks" = "$(sort -nr <<<"$ranks")" ] \
    || no "$lib changed: the listing '$(paste -sd' ' "$T/list")' does not name first the tests that name the most of its users ($(paste -sd' ' <<<"$users")): counts '$(paste -sd' ' <<<"$ranks")'"
  case ${lib##*/} in strip-quoted.sh|hook-fire-log.sh)
    head -5 "$T/list" | grep -qxF .claude/hooks/__tests__/git-safety.test.sh \
      || no "$lib changed: git-safety.test.sh is not in the first 5 of the listing: '$(paste -sd' ' "$T/list")'" ;;
  esac
done
[ "$n" -gt 0 ] || no "no hook library found under .claude/hooks/lib/"
[ "$fails" = 0 ] && echo "ok - each hook library's tests are linked to it ($n libraries)"
exit $fails
