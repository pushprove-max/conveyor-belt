#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 30
# The project runs no GitHub Actions (each run cost the owner's Actions minutes, and the account can no longer start
# Actions jobs; a release is `conveyor.sh release` on the build machine). Bug caught: the README, the contributing
# guide or a file under docs/ (its tests aside) still names Actions, a workflow, CI (its badge or its runs) or
# Scorecard, so a reader looks for runs that never come. The one sentence allowed is "This (or The) project runs no
# GitHub Actions"; the rest of its line is still checked. Then a fixture: each word is found, and the allowed sentence
# hides no other word on its line.
set -uo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd -P)
fail() { echo "FAIL [actions]: $*" >&2; exit 1; }
# hits <file>...: each line that names one, as <file>:<line>: <word>.
hits() {
  perl -ne 's/\b(?:This|The) project runs no GitHub Actions\b//g;
    print "$ARGV:$.: $1\n" while /(\bActions\b|\b[Ww]orkflows?\b|\bCI\b|[Ss]corecard)/g; close ARGV if eof' "$@"
}
# The text files git lists, but the tests, which name these words to check them.
mapfile -t F < <(cd "$ROOT" && git ls-files README.md CONTRIBUTING.md docs | grep -vF '.test.' | while IFS= read -r f; do grep -Iq . "$f" && echo "$f"; done)
[ ${#F[@]} -gt 2 ] || fail "the README, the contributing guide and docs/ are not found: ${F[*]}"
out=$(cd "$ROOT" && hits "${F[@]}") || fail "the pages could not be read: $out"
[ -z "$out" ] || fail "a page names GitHub Actions, a workflow, CI or Scorecard: $out"

T=$(mktemp -d) || exit 1; trap 'rm -rf "$T"' EXIT
printf '%s\n' 'Open Actions, then Release.' 'Run the release workflow.' 'A CI badge.' 'The Scorecard badge.' \
  'This project runs no GitHub Actions.' 'The project runs no GitHub Actions; CI runs at a release.' > "$T/page.md"
out=$(cd "$T" && hits page.md | tr '\n' '|')
[ "$out" = 'page.md:1: Actions|page.md:2: workflow|page.md:3: CI|page.md:4: Scorecard|page.md:6: CI|' ] \
  || fail "the check named [$out], not each word, with the allowed sentence alone left out"
echo "ok [actions]: no page names GitHub Actions, a workflow, CI or Scorecard"
