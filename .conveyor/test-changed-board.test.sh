#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# test-changed.sh's Board rules (issue 544, boardtests): a change to the page's shared fixture
# (dashboard-view.helpers.mjs) selects every Board test file that imports it, and a change to a panel file every one
# that draws that panel, both read from the test files. Bug it catches: #310 changed the landed fixture in the helpers
# and #403 changed panels/declined.js, neither selected dashboard-view.cards-needs.test.mjs, and main went red for it.
# The scratch repo holds this checkout's Board tests and panels, so the files named below are the real ones.
set -u
HERE=$(cd "$(dirname "$0")" && pwd -P); ROOT=$(dirname "$HERE")
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
AT=@
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t${AT}example.com GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t${AT}example.com
unset CONVEYOR_TEST_LOG CONVEYOR_SHELL_TEST_CASE CONVEYOR_TEST_FILE CONVEYOR_TEST_FILES BASH_ENV CONVEYOR_TEST_RERUN
# no <why>: a failure, kept in a file, as listed() runs in a command substitution, whose variables are lost.
no() { echo "not ok - $1" | tee -a "$T/notok" >&2; }

D=.claude/scripts/__tests__
R=$T/r; mkdir -p "$R/.conveyor" "$R/conveyor/tests"
cp "$HERE/test-changed.sh" "$HERE/test-lint.sh" "$HERE/no-browser-tests.sh" "$R/.conveyor/"
printf '%s\n' '{"area": "a", "file": "conveyor/x.sh"}' '{"area": "a", "test": "a.test.sh"}' > "$R/.conveyor/engine-areas.json"
printf 't_aone() {\n  :\n}\n' > "$R/conveyor/tests/a.test.sh"; echo 'echo one' > "$R/conveyor/x.sh"
(cd "$ROOT" && git ls-files -z "$D" .claude/dashboard/panels | tar -cf - --null -T -) | tar -xf - -C "$R" || { echo "not ok - the Board files could not be copied"; exit 1; }
# Tests no list names: a new one that imports the fixture and draws Landed is selected by both rules; one that only
# names the fixture and the panel's file, or a panel whose id starts with landed, is selected by neither.
printf "import { boot, panel } from './dashboard-view.helpers.mjs';\nconst l = (w) => panel(w, 'landed');\n" > "$R/$D/zz-new.test.mjs"
printf "// './dashboard-view.helpers.mjs.bak' and .claude/dashboard/panels/landed.js\nconst x = data.panels.landedx;\n" > "$R/$D/zz-names.test.mjs"
git -C "$R" init -q && git -C "$R" add -A && git -C "$R" commit -qm init
total=$(git -C "$R" ls-files "$D" | grep -c '[.]test[.]')
# listed <changed file> [<text> <new text>]: the file changed (its <text> made <new text>, else a line added), the list
# made (not run); prints it one file a line. The change is undone.
listed() {
  if [ $# = 3 ]; then
    grep -qF -- "$2" "$R/$1" || no "$1 no longer holds '$2'"
    local s; s=$(cat "$R/$1"); printf '%s\n' "${s/"$2"/"$3"}" > "$R/$1"
  else
    echo 'const changed = 1;' >> "$R/$1"
  fi
  (cd "$R" && CONVEYOR_TEST_LIST=$T/list bash .conveyor/test-changed.sh) > "$T/out" 2>&1 || no "the listing of $1 failed: $(tail -5 "$T/out")"
  git -C "$R" checkout -q -- .
  cat "$T/list" 2>/dev/null
}
has() { grep -qxF "$D/$2" <<<"$1"; }

got=$(listed "$D/dashboard-view.helpers.mjs"); n=$(grep -c . <<<"$got")
importers=$(cd "$R" && grep -lE "from '[.]/dashboard-view[.]helpers[.]mjs'" "$D"/*.test.*)
missing=$(grep -vxF -f <(printf '%s\n' "$got") <<<"$importers")
[ -z "$missing" ] && has "$got" dashboard-view.cards-needs.test.mjs && has "$got" zz-new.test.mjs \
  || no "a change to dashboard-view.helpers.mjs does not list every test file that imports it; $(grep -c . <<<"$missing") missing: $(head -3 <<<"$missing" | tr '\n' ' ')"
! has "$got" zz-names.test.mjs || no "a test that only names dashboard-view.helpers.mjs was listed"
[ "$n" -lt "$total" ] || no "a change to dashboard-view.helpers.mjs lists $n files, not fewer than the $total Board test files"

# A change to a panel's texts alone still lists the tests that draw it: they check those texts (the text-only rule
# ended the pick before the panel rule ran).
got=$(listed .claude/dashboard/panels/landed.js 'The Board could not read the landed cards' 'Landed cards are unavailable')
n=$(grep -c . <<<"$got")
has "$got" dashboard-view.cards-needs.test.mjs && has "$got" zz-new.test.mjs \
  || no "a text-only change to panels/landed.js does not list the tests that draw Landed: $(tr '\n' ' ' <<<"$got")"
! has "$got" zz-names.test.mjs || no "a test that only names panels/landed.js, or reads panels.landedx, was listed"
[ "$n" -lt "$total" ] || no "a change to panels/landed.js lists $n files, not fewer than the $total Board test files"

# A change to a panel's default length: page-panels checks every panel's length through the helpers' list, page-states
# draws each panel through panelState; neither names the panel in a way the other rules read.
got=$(listed .claude/dashboard/panels/declined.js 'rows: 6' 'rows: 7'); n=$(grep -c . <<<"$got")
for t in cards-needs declined page-panels page-states; do
  has "$got" "dashboard-view.$t.test.mjs" || no "a change to panels/declined.js does not list dashboard-view.$t.test.mjs: $(tr '\n' ' ' <<<"$got")"
done
[ "$n" -lt "$total" ] || no "a change to panels/declined.js lists $n files, not fewer than the $total Board test files"
! grep -q '^conveyor/' <<<"$got" || no "a Board change listed engine tests: $(grep '^conveyor/' <<<"$got" | tr '\n' ' ')"

[ ! -s "$T/notok" ] && echo "ok - a change to the Board's fixture or a panel lists the test files that import it or draw it" || exit 1
