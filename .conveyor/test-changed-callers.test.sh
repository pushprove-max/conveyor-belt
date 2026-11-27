#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Issue 1775. With no coverage map (or a function it does not hold), a change to functions alone of an engine shell
# file ran every case file of the file's area, though most of them never reach the function (#1696 ran 63 test files).
# test-changed.sh's callersof runs, in its place, the case files that name a changed function or a function that
# calls it, and of a command script that calls it (in its functions or outside them), the case files that run its
# commands; a function with more than 25
# callers, and a change outside any function, still run by the area. The shared setup is in test-changed.lib.sh.
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
# A helper that many functions call reaches most cases through them: with 26 callers, target() runs its area. Bug it
# catches: a limit of 26 or more (cfix 24 is helper(), v0 to v23 and upmain() of commands/up.sh, 26 callers, one over
# the limit of 25; the code of commands/go.sh outside its functions is no caller).
p_callersmany() {
  cfix 24; edit 's/echo one/: one/'; got=$(ran)
  [ "$got" = "wcmd wfour wone wthree wtwo wup" ] && [ "$(cat "$T/rc")" = 0 ] \
    && ok "a changed function with more than 25 callers runs its area's case files" \
    || no "lib/w.sh target() with 26 callers changed: ran '$got', want its area, exit $(cat "$T/rc"): $(cat "$T/out")"
  grep -qxF 'coverage map rule: conveyor/lib/w.sh target(): area' "$T/out" \
    && ok "the run says the area picked the tests of a function with more than 25 callers" || no "26 callers: no area rule line: $(cat "$T/out")"
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

for p in callers callersmany callerstop; do part "$p"; done
results
