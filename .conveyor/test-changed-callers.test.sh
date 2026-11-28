#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Issue 1775. With no coverage map (or a function it does not hold), a change to functions alone of an engine shell
# file ran every case file of the file's area, though most of them never reach the function (#1696 ran 63 test files).
# test-changed.sh's callersof runs, in its place, the case files that name a changed function or a function that
# calls it, and of a command script that calls it (in its functions or outside them), the case files that run its
# commands, however many callers it has (issue 1830); a change outside any function still runs by the area. The
# shared setup is in test-changed.lib.sh.
set -u
HERE=$(cd "$(dirname "$0")" && pwd -P)
# shellcheck disable=SC2034 # ROOT is read by test-changed.lib.sh
ROOT=$(dirname "$HERE")
. "$HERE/test-changed.lib.sh"

# cfix [callers]: the scratch repository (R) with an area w of four engine files and six case files, and no
# coverage map. lib/w.sh's target() is called by helper() there, by the code of commands/go.sh outside its
# functions, the script of `conveyor.sh go`, and by upmain(), the entry function of commands/up.sh, the script of
# `conveyor.sh up`; wone names target, wtwo names helper, wcmd runs `conveyor.sh go`, wup runs `conveyor.sh up`, wthree
# names other() and wfour names none. With <callers>, lib/v.sh has that many more functions that call target.
cfix() {
  local i
  mkdir -p "$R/conveyor/lib" "$R/conveyor/commands"
  printf '%s\n' '{"area": "boot", "file": "conveyor/conveyor.sh"}' '{"area": "boot", "file": "conveyor/lib/portable.sh"}' \
    '{"area": "boot", "test": "b.test.sh"}' '{"area": "w", "file": "conveyor/lib/w.sh"}' '{"area": "w", "file": "conveyor/lib/v.sh"}' \
    '{"area": "w", "file": "conveyor/commands/go.sh"}' '{"area": "w", "file": "conveyor/commands/up.sh"}' \
    >> "$R/.conveyor/engine-areas.json"
  for i in wone wtwo wthree wfour wcmd wup; do
    echo "{\"area\": \"w\", \"test\": \"$i.test.sh\"}" >> "$R/.conveyor/engine-areas.json"
  done
  printf '%s\n' '#!/usr/bin/env bash' 'cmd go go.sh '"'go'" 'cmd up up.sh '"'up'" > "$R/conveyor/conveyor.sh"
  printf 'pfx() {\n  :\n}\n' > "$R/conveyor/lib/portable.sh"
  printf '%s\n' 'export W=1' 'target() {' '  echo one' '}' 'helper() {' '  target' '}' 'other() {' '  echo other' '}' > "$R/conveyor/lib/w.sh"
  : > "$R/conveyor/lib/v.sh"
  for ((i = 0; i < ${1:-0}; i++)); do printf 'v%s() {\n  target\n}\n' "$i" >> "$R/conveyor/lib/v.sh"; done
  printf '%s\n' '. "$HERE/lib/w.sh"' 'target' > "$R/conveyor/commands/go.sh"
  printf '%s\n' '. "$HERE/lib/w.sh"' 'upmain() {' '  target' '}' 'upmain "$@"' > "$R/conveyor/commands/up.sh"
  printf 't_wone() {\n  target\n}\n' > "$R/conveyor/tests/wone.test.sh"
  printf 't_wtwo() {\n  helper\n}\n' > "$R/conveyor/tests/wtwo.test.sh"
  printf 't_wthree() {\n  other\n}\n' > "$R/conveyor/tests/wthree.test.sh"
  printf 't_wfour() {\n  :\n}\n' > "$R/conveyor/tests/wfour.test.sh"
  printf 't_wcmd() {\n  bash "$HERE/conveyor.sh" go\n}\n' > "$R/conveyor/tests/wcmd.test.sh"
  printf 't_wup() {\n  bash "$HERE/conveyor.sh" up\n}\n' > "$R/conveyor/tests/wup.test.sh"
  git -C "$R" add -A && git -C "$R" commit -qm callers
}
# edit <sed program>: lib/w.sh changed so, in the worktree. A change of code, not of a text alone (textonly).
edit() { sed "$1" "$R/conveyor/lib/w.sh" > "$T/e" && cat "$T/e" > "$R/conveyor/lib/w.sh"; }

# Bug: target() changed ran all five case files of area w. It runs those that name it (wone) or helper(), its caller
# (wtwo), wcmd, which runs the command whose script calls it outside its functions, and wup, which runs the command
# whose entry function upmain() calls it (bug: no test names upmain, so wup did not run); not wthree or wfour; and the
# run says callersof picked them.
p_callers() {
  cfix; edit 's/echo one/: one/'; got=$(ran)
  [ "$got" = "wcmd wone wtwo wup" ] && [ "$(cat "$T/rc")" = 0 ] \
    && ok "a changed function runs the case files that name it, its caller or its command, not the rest of its area" \
    || no "lib/w.sh target() changed: ran '$got', want 'wcmd wone wtwo wup', exit $(cat "$T/rc"): $(cat "$T/out")"
  grep -qxF 'coverage map rule: conveyor/lib/w.sh target(): callersof' "$T/out" \
    && ok "the run says callersof picked the changed function's tests" || no "lib/w.sh target() changed: no callersof rule line: $(cat "$T/out")"
}
# Issue 1830 (the owner's order, in place of issue 1775's cap of 25 callers): a function with 26 callers (cfix 24 is
# helper(), v0 to v23 and upmain() of commands/up.sh) runs its callers' case files as one with two does, not its area.
# Bug it catches: the cap ran the whole area, so a change to a helper many functions call (cardland.sh: 86 files) ran
# every case file of it; here wthree and wfour, which reach no caller.
p_callersmany() {
  cfix 24; edit 's/echo one/: one/'; got=$(ran)
  [ "$got" = "wcmd wone wtwo wup" ] && [ "$(cat "$T/rc")" = 0 ] \
    && ok "a changed function with 26 callers runs its callers' case files, not its area" \
    || no "lib/w.sh target() with 26 callers changed: ran '$got', want 'wcmd wone wtwo wup', exit $(cat "$T/rc"): $(cat "$T/out")"
  grep -qxF 'coverage map rule: conveyor/lib/w.sh target(): callersof' "$T/out" \
    && ok "the run says callersof picked the tests of a function with 26 callers" || no "26 callers: no callersof rule line: $(cat "$T/out")"
}
# A line outside every function runs when a command sources the file, so no caller can be named: the area runs.
p_callerstop() {
  cfix; edit 's/^export W=1$/export W=2/'; got=$(ran)
  [ "$got" = "wcmd wfour wone wthree wtwo wup" ] && [ "$(cat "$T/rc")" = 0 ] \
    && ok "a change outside any function runs its area's case files" \
    || no "lib/w.sh 'export W=1' changed to 'export W=2': ran '$got', want its area, exit $(cat "$T/rc"): $(cat "$T/out")"
  grep -qxF 'coverage map rule: conveyor/lib/w.sh, a change outside its functions: area' "$T/out" \
    && ok "the run says the area picked the tests of a change outside any function" || no "export W=2: no area rule line: $(cat "$T/out")"
}

# Issue 1830 (the owner's order): conveyor.sh and portable.sh run in every case, so a call of a changed function
# there named no caller and ran the file's whole area. Bug it catches: target(), also called at start-up by a line of
# conveyor.sh and one of portable.sh, ran every case file of area w (wthree and wfour reach no caller); it runs its
# callers' case files, as p_callers.
p_callersstartup() {
  cfix; printf '%s\n' 'target' >> "$R/conveyor/conveyor.sh"; printf '%s\n' 'target' >> "$R/conveyor/lib/portable.sh"
  git -C "$R" add -A && git -C "$R" commit -qm startup
  edit 's/echo one/: one/'; got=$(ran)
  [ "$got" = "wcmd wone wtwo wup" ] && [ "$(cat "$T/rc")" = 0 ] \
    && ok "a changed function conveyor.sh and portable.sh call at start-up runs its callers' case files, not its area" \
    || no "lib/w.sh target(), called at start-up, changed: ran '$got', want 'wcmd wone wtwo wup', exit $(cat "$T/rc"): $(cat "$T/out")"
}
# Bug it catches: a function conveyor.sh's command table names (go(), as `cmd go go.sh`) ran the file's whole area.
# It runs the case file that runs that command (wcmd), and no other.
p_callerstable() {
  cfix; printf '%s\n' 'go() {' '  echo go' '}' >> "$R/conveyor/lib/w.sh"; git -C "$R" add -A && git -C "$R" commit -qm go
  edit 's/echo go/: go/'; got=$(ran)
  [ "$got" = "wcmd" ] && [ "$(cat "$T/rc")" = 0 ] \
    && ok "a changed function conveyor.sh's command table names runs the case files of that command" \
    || no "lib/w.sh go(), a command of the table, changed: ran '$got', want 'wcmd', exit $(cat "$T/rc"): $(cat "$T/out")"
}

# Bug it catches: a Board test file whose `//` comment holds the name of a changed function ran (two of them on card
# 1829, for the word `verdicts`). One that calls nothing of target() but names it in a comment is not listed; one
# that names it in code is.
p_callerscomment() {
  cfix; mkdir -p "$R/.claude/scripts/__tests__"
  printf '%s\n' '// target is drawn by the page' "test('x', () => {});" > "$R/.claude/scripts/__tests__/wnote.test.mjs"
  printf '%s\n' "test('y', () => run('target'));" > "$R/.claude/scripts/__tests__/wcode.test.mjs"
  git -C "$R" add -A && git -C "$R" commit -qm board; edit 's/echo one/: one/'
  (cd "$R" && CONVEYOR_TEST_LIST=$T/list bash .conveyor/test-changed.sh) > "$T/out" 2>&1
  grep -qxF .claude/scripts/__tests__/wcode.test.mjs "$T/list" && ! grep -qF wnote.test.mjs "$T/list" \
    && ok "a Board test that names a changed function in a // comment alone is not selected" \
    || no "lib/w.sh target() changed: the list is '$(paste -sd ' ' "$T/list" 2>&1)', want wcode.test.mjs and not wnote.test.mjs: $(cat "$T/out")"
}

for p in callers callersmany callerstop callersstartup callerstable callerscomment; do part "$p"; done
results
