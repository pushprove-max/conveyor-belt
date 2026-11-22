#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# test-changed.sh on a change to comment lines alone (issue 640). Bug: a card that added a one-line licence (SPDX)
# comment to 422 files ran 2,303 of 2,729 cases, as a change to a comment line selected tests as a code change does.
# A change to the comment and blank lines alone of a shell, Python, YAML, JS, TS, CSS or HTML file now selects no
# test, and the run names it; a #! line, a code line and any change to another file type (JSON) still select theirs.
set -u
HERE=$(cd "$(dirname "$0")" && pwd -P)
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
AT=@
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t${AT}example.com GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t${AT}example.com
unset CONVEYOR_TEST_LOG CONVEYOR_SHELL_TEST_CASE CONVEYOR_TEST_FILE CONVEYOR_TEST_FILES BASH_ENV CONVEYOR_TEST_RERUN
ok() { echo "ok - $1"; }
no() { echo "not ok - $1"; }

# A scratch repo: the real script, an empty engine map, and in tool/ a shell file, a JS file (with a template string
# that holds a `//` line), a JSON file and a shell test file, each source file with a test named after it that writes
# its name to ran.
R=$T/r; mkdir -p "$R/.conveyor" "$R/tool"
cp "$HERE/test-changed.sh" "$HERE/test-share.sh" "$HERE/lint-shell.sh" "$HERE/test-lint.sh" "$HERE/no-browser-tests.sh" "$HERE/no-records-split.sh" "$R/.conveyor/"
echo '{"outside": "conveyor/README.md"}' > "$R/.conveyor/engine-areas.json"
printf '#!/usr/bin/env bash\necho s\n' > "$R/tool/s.sh"
printf 'export const a = 1;\nexport const t = `\n// data\n`;\n' > "$R/tool/a.js"
echo '{"a": 1}' > "$R/tool/c.json"
for s in s a c u; do echo "echo $s >> \"\$(dirname \"\$0\")/../ran\"" > "$R/tool/$s.test.sh"; done
echo ran > "$R/.gitignore"
git -C "$R" init -q && git -C "$R" add -A && git -C "$R" commit -qm init
# What one run ran (its exit in $T/rc, its output in $T/out), sorted; the list for a run again: $T/rerun when it is there.
ran() {
  rm -f "$R/ran"
  (cd "$R" && if [ -f "$T/rerun" ]; then CONVEYOR_TEST_RERUN=$T/rerun bash .conveyor/test-changed.sh; else bash .conveyor/test-changed.sh; fi) > "$T/out" 2>&1
  echo $? > "$T/rc"; cat "$R/ran" 2>/dev/null | sort | paste -sd' ' -
}
spdx() { # <comment mark> <file>: a licence line after its first line (after the #! line of a shell file)
  awk -v l="$1 SPDX-License-Identifier: Apache-2.0" 'NR == 1 { print; print l; next } { print }' "$R/$2" > "$T/e" && cat "$T/e" > "$R/$2"
}
PARTS=()
part() { PARTS+=("$1"); (B=$T; T=$T/$1; mkdir "$T" && cp -a "$B/r" "$T/r" || exit 1; R=$T/r; "p_$1") > "$T/$1.res" 2>&1 & }

# D1: a licence comment in a shell file and in a JS file selects neither's tests, and the run names both.
p_spdx() {
  spdx '#' tool/s.sh; spdx '//' tool/a.js; got=$(ran)
  [ -z "$got" ] && [ "$(cat "$T/rc")" = 0 ] && grep -qx 'comment-only change: tool/s.sh, no tests selected' "$T/out" \
    && grep -qx 'comment-only change: tool/a.js, no tests selected' "$T/out" \
    && ok "a licence comment in a shell and a JS file selects no test, and the run names both as comment-only" \
    || no "licence comments: ran '$got', exit $(cat "$T/rc"): $(cat "$T/out")"
}
# A blank line added at the end of a file is a blank-line change too. Bug: $(...) dropped it, so both sides read the
# same, the change was not taken as comment-only, and the file's test ran.
p_blank() {
  echo '' >> "$R/tool/a.js"; got=$(ran)
  [ -z "$got" ] && grep -qx 'comment-only change: tool/a.js, no tests selected' "$T/out" \
    && ok "a blank line added at the end of a JS file selects no test, and the run names it" \
    || no "trailing blank line: ran '$got': $(cat "$T/out")"
}
# D2: the same, with one code line of the JS file changed too: its test runs.
p_code() {
  spdx '#' tool/s.sh; spdx '//' tool/a.js; sed 's/a = 1/a = 2/' "$R/tool/a.js" > "$T/e" && cat "$T/e" > "$R/tool/a.js"; got=$(ran)
  [ "$got" = a ] && ! grep -q 'comment-only change: tool/a.js' "$T/out" \
    && ok "a code line changed beside a licence comment runs the JS file's test" || no "JS code changed: ran '$got': $(cat "$T/out")"
}
# A `//` line inside a template string is data, not a comment: its change runs the test.
p_template() {
  sed 's,^// data$,// other,' "$R/tool/a.js" > "$T/e" && cat "$T/e" > "$R/tool/a.js"; got=$(ran)
  [ "$got" = a ] && ok "a // line inside a JS template string is data: its change runs the test" || no "template line changed: ran '$got': $(cat "$T/out")"
}
# D3: a #! line is code, not a comment.
p_shebang() {
  sed 's,^#!/usr/bin/env bash$,#!/bin/bash,' "$R/tool/s.sh" > "$T/e" && cat "$T/e" > "$R/tool/s.sh"; got=$(ran)
  [ "$got" = s ] && ok "a change to a shell file's #! line runs its test" || no "#! changed: ran '$got': $(cat "$T/out")"
}
# D3: a JSON file has no comment lines: any change runs its test.
p_json() {
  echo '' >> "$R/tool/c.json"; got=$(ran)
  [ "$got" = c ] && ok "any change to a JSON file runs its test" || no "JSON changed: ran '$got': $(cat "$T/out")"
}
# D4: a test file changed in its comments alone, which passed in the card's earlier run, is kept as passed; changed
# in a code line, it runs again though it passed.
p_testfile() {
  spdx '#' tool/u.test.sh
  printf 'change\tabc\npass\ttool/u.test.sh\nchanged\ttool/u.test.sh\n' > "$T/rerun"; got=$(ran)
  [ -z "$got" ] && grep -qx 'comment-only change: tool/u.test.sh, no tests selected' "$T/out" \
    && ok "a test file changed in its comments alone that passed before is not run again" \
    || no "test file comment, passed before: ran '$got': $(cat "$T/out")"
  echo ': code' >> "$R/tool/u.test.sh"; got=$(ran)
  [ "$got" = u ] && ok "a test file changed in a code line runs again though it passed before" || no "test file code changed: ran '$got': $(cat "$T/out")"
}

for p in spdx blank code template shebang json testfile; do part "$p"; done
wait
for p in "${PARTS[@]}"; do cat "$T/$p.res"; grep -q '^ok' "$T/$p.res" || echo "not ok - part $p checked nothing"; done | awk '{ sub(/^ok -/, "ok " NR " -"); sub(/^not ok -/, "not ok " NR " -"); print } /^not ok/ { f = 1 } END { exit f }'
