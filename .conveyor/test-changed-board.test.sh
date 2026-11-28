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
unset CONVEYOR_TEST_LOG CONVEYOR_SHELL_TEST_CASE CONVEYOR_TEST_FILE CONVEYOR_TEST_FILELIST BASH_ENV CONVEYOR_TEST_RERUN
# no <why>: a failure, kept in a file, as listed() runs in a command substitution, whose variables are lost.
no() { echo "not ok - $1" | tee -a "$T/notok" >&2; }

D=.claude/scripts/__tests__
R=$T/r; mkdir -p "$R/.conveyor" "$R/conveyor/tests"
cp "$HERE/test-changed.sh" "$HERE/funcs.awk" "$HERE/test-share.sh" "$HERE/lint-shell.sh" "$HERE/test-lint.sh" "$HERE/no-browser-tests.sh" "$HERE/no-records-split.sh" "$R/.conveyor/"
printf '%s\n' '{"area": "a", "file": "conveyor/x.sh"}' '{"area": "a", "test": "a.test.sh"}' > "$R/.conveyor/engine-areas.json"
printf 't_aone() {\n  :\n}\n' > "$R/conveyor/tests/a.test.sh"; echo 'echo one' > "$R/conveyor/x.sh"
(cd "$ROOT" && git ls-files -z "$D" .claude/dashboard/panels .claude/dashboard/app.css .claude/dashboard/app.js | tar -cf - --null -T -) | tar -xf - -C "$R" || { echo "not ok - the Board files could not be copied"; exit 1; }
# This checkout's links of the page's stylesheet, app.js and guide (.conveyor/test-links.json), so the links of the
# other files changed below do not add to their lists.
jq '{".claude/dashboard/app.css": .[".claude/dashboard/app.css"], ".claude/dashboard/app.js": .[".claude/dashboard/app.js"], "docs/board.md": .["docs/board.md"],
  ".claude/scripts/__tests__/dashboard-view.selfheals.test.mjs": .[".claude/scripts/__tests__/dashboard-view.selfheals.test.mjs"]}' \
  "$HERE/test-links.json" > "$R/.conveyor/test-links.json" || { echo "not ok - the page's test links could not be read"; exit 1; }
mkdir -p "$R/docs"; cp "$ROOT/docs/board.md" "$R/docs/board.md"; cp "$ROOT/docs-claims.test.sh" "$R/docs-claims.test.sh"
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
got=$(listed .claude/dashboard/panels/declined.js 'rows: 5,' 'rows: 6,'); n=$(grep -c . <<<"$got")
for t in cards-needs declined page-panels page-states; do
  has "$got" "dashboard-view.$t.test.mjs" || no "a change to panels/declined.js does not list dashboard-view.$t.test.mjs: $(tr '\n' ' ' <<<"$got")"
done
[ "$n" -lt "$total" ] || no "a change to panels/declined.js lists $n files, not fewer than the $total Board test files"
! grep -q '^conveyor/' <<<"$got" || no "a Board change listed engine tests: $(grep '^conveyor/' <<<"$got" | tr '\n' ' ')"

# Issue 1439. Bug: a font size off the scale in the page's stylesheet did not list page-live, the test that checks
# every font size there is on the scale, as no rule reads that test as the stylesheet's.
got=$(listed .claude/dashboard/app.css 'font-size: var(--fs-sm);' 'font-size: 13px;')
has "$got" dashboard-view.page-live.test.mjs \
  || no "a font size of 13px in app.css does not list dashboard-view.page-live.test.mjs: $(tr '\n' ' ' <<<"$got")"

# Bug: a focus call without preventScroll in app.js did not list the focus test, the test that checks every focus call
# in .claude/dashboard, as no rule reads that test as app.js's, and main went red for it. Any code change to app.js
# is enough: the list does not read what the change is.
got=$(listed .claude/dashboard/app.js)
has "$got" dashboard-view.focus.test.mjs \
  || no "a code change to app.js does not list dashboard-view.focus.test.mjs: $(tr '\n' ' ' <<<"$got")"

# Bug: a card that changed only docs/board.md did not list dashboard-view.rules-index.test.mjs, which reads that page
# and checks the order of its two top lines of the Rules panel, as no link named it. The same card also did not list
# the two other tests that read the guide (dashboard-server-plugin.test.sh, docs-claims.test.sh). A card that adds or
# changes no test file runs only the first CARDLINKED (5) of the files the test map links (conveyor/lib/prompts.sh;
# each file .conveyor/test-links.json links runs too), so rules-index must be among the first five.
got=$(listed docs/board.md)
for t in dashboard-view.rules-index.test.mjs dashboard-server-plugin.test.sh; do
  has "$got" "$t" || no "a change to docs/board.md alone does not list $t, which reads it: $(tr '\n' ' ' <<<"$got")"
done
grep -qxF docs-claims.test.sh <<<"$got" \
  || no "a change to docs/board.md alone does not list docs-claims.test.sh, which reads it: $(tr '\n' ' ' <<<"$got")"
head -n 5 <<<"$got" | grep -qxF "$D/dashboard-view.rules-index.test.mjs" \
  || no "dashboard-view.rules-index.test.mjs is not among the first 5 files listed for a change to docs/board.md alone, so a card's run leaves it out: $(tr '\n' ' ' <<<"$got")"

# Bug: a retired word in dashboard-view.selfheals.test.mjs broke main, as dashboard-local.test.sh scans that file for
# retired words; the link named conveyor/tests/healsact.test.sh instead, so a card that changed the selfheals test
# alone ran only that test, and the scan never ran.
got=$(listed "$D/dashboard-view.selfheals.test.mjs")
has "$got" dashboard-local.test.sh \
  || no "a change to dashboard-view.selfheals.test.mjs alone does not list dashboard-local.test.sh, which scans it: $(tr '\n' ' ' <<<"$got")"

# Card 1798: the lines on record. The engine's state folder (a stub conveyor.sh names it) holds a pass of two tests
# that draw Landed, and of zz-new the lines it ran of panels/landed.js: line 1 alone. A line added at the panel's end
# does not list zz-new, and lists cards-needs, which has no lines on record; with every line on record as run, or
# with the blob of its lines gone, zz-new is listed. Bug it catches: a change to one function of a panel listed each
# test that draws the panel (about 40 of the Board's test files for a change to the undo of a move, which 2 run).
P=.claude/dashboard/panels/landed.js
mkdir -p "$R/conveyor/jq" "$T/state" && cp "$ROOT/conveyor/jq/ranlines.jq" "$R/conveyor/jq/" \
  && printf '#!/usr/bin/env bash\n[ "${1:-}" != state-dir ] || echo "%s"\n' "$T/state" > "$R/conveyor/conveyor.sh" \
  && git -C "$R" add -A && git -C "$R" commit -qm engine || no "the engine's stub could not be committed"
b=$(git -C "$R" rev-parse "HEAD:$P"); pn=$(wc -l < "$R/$P")
printf 'h%s\tc0\t%s\t%s\n' 1 "$D/zz-new.test.mjs" "$P" 2 "$D/dashboard-view.cards-needs.test.mjs" "$P" > "$T/state/testpasses.tsv"
printf '%s\t%s\t%s\t1\t1\n' "$D/zz-new.test.mjs" "$P" "$b" > "$T/state/testlines.tsv"
got=$(listed "$P")
! has "$got" zz-new.test.mjs && has "$got" dashboard-view.cards-needs.test.mjs \
  || no "a line added at the end of panels/landed.js, of which zz-new ran line 1 alone, did not list cards-needs without zz-new: $(tr '\n' ' ' <<<"$got")"
printf '%s\t%s\t%s\t1-%s\t1-%s\n' "$D/zz-new.test.mjs" "$P" "$b" "$pn" "$pn" > "$T/state/testlines.tsv"
got=$(listed "$P"); has "$got" zz-new.test.mjs || no "a line added where zz-new ran did not list it: $(tr '\n' ' ' <<<"$got")"
printf '%s\t%s\t%040d\t1\t1\n' "$D/zz-new.test.mjs" "$P" 0 > "$T/state/testlines.tsv"
got=$(listed "$P"); has "$got" zz-new.test.mjs || no "with the blob of its lines gone, zz-new was not listed: $(tr '\n' ' ' <<<"$got")"
# linesof: what two case workers wrote of a test file becomes its `TESTRUN lines` lines: the lines either ran, as
# ranges, with the script's blob; a script one of them gives none of (null) has no line.
mkdir -p "$T/ln" && echo '{"panels/landed.js": {"lines": [1, 2, 3, 7], "gaps": [1, 2]}, "app.js": {"lines": [5], "gaps": []}}' > "$T/ln/x.1.json" \
  && echo '{"panels/landed.js": {"lines": [3, 4], "gaps": [9]}, "app.js": null}' > "$T/ln/x.2.json"
got=$(cd "$R" && eval "$(sed -n '/^linesof() {/,/^}/p' .conveyor/test-changed.sh)" && linesof "$D/zz-new.test.mjs" "$T/ln" 2>&1)
[ "$got" = "TESTRUN lines"$'\t'"$D/zz-new.test.mjs"$'\t'"$P"$'\t'"$b"$'\t'"1-4,7"$'\t'"1-2,9" ] && git -C "$R" cat-file -e "$b" \
  || no "the lines two workers wrote did not become one TESTRUN lines line of panels/landed.js: $got"

[ ! -s "$T/notok" ] && echo "ok - a change to the Board's fixture or a panel lists the test files that import it or draw it" || exit 1
