#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# test-changed.sh's checks and Claude Code's own check of the plugin, `claude plugin validate` (issue 604): a change to
# hooks/, types/ or .claude-plugin/ runs it, and an error fails the checks (the Test step's test.checkCommand) with its
# error lines in the output; a change to none of them does not run it; with no `claude`, the checks say so and fail.
# Bug: #497 kept a value in the /units mod (hooks/units.tsx) that types/index.d.ts did not declare; every test passed,
# the card landed, and Claude Code refused to load the mod on main until a hand fix.
set -u
HERE=$(cd "$(dirname "$0")" && pwd -P); ROOT=${HERE%/*}
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
AT=@
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t${AT}example.com GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t${AT}example.com
unset CONVEYOR_TEST_LOG CONVEYOR_SHELL_TEST_CASE CONVEYOR_TEST_FILE CONVEYOR_TEST_FILELIST BASH_ENV CONVEYOR_TEST_RERUN
ok() { echo "ok - $1"; }
no() { echo "not ok - $1"; }

# A scratch repo: the real script, the plugin's mod, types contract and manifest as they are here, an engine file in
# an area, and a `claude` on PATH that notes each run in $R/runs and runs the real one (the check is Claude Code's own).
# Every part's HEAD is the same commit, so the real validate of HEAD's plugin copy runs once here ($T/head): the
# `claude` gives a directory with the same files that output, with its path put in, and runs the real one on any
# other. $R/stub/claude only notes its runs, for the parts that check only whether the check runs.
CLAUDE=$(command -v claude) || { no "claude is not installed: the plugin's validate cannot be tested"; exit 1; }
R=$T/r; mkdir -p "$R/.conveyor" "$R/conveyor/lib" "$R/conveyor/tests" "$R/bin" "$R/stub" "$T/head"
cp "$HERE/test-changed.sh" "$HERE/funcs.awk" "$HERE/test-share.sh" "$HERE/lint-shell.sh" "$HERE/test-lint.sh" "$HERE/no-browser-tests.sh" "$HERE/no-records-split.sh" "$R/.conveyor/"
cp -a "$ROOT/hooks" "$ROOT/types" "$ROOT/.claude-plugin" "$R/"
printf '%s\n' '{"area": "a", "file": "conveyor/lib/x.sh"}' '{"area": "a", "test": "a.test.sh"}' > "$R/.conveyor/engine-areas.json"
echo 'x() { :; }' > "$R/conveyor/lib/x.sh"; printf 't_aone() {\n  :\n}\n' > "$R/conveyor/tests/a.test.sh"
HC=$(cd "$T/head" && pwd -P)
printf '%s\n' '#!/usr/bin/env bash' 'echo "$*" >> "$(dirname "$0")/../runs"' \
  "hc=$(printf %q "$HC")" \
  'if [ "$1 $2" = "plugin validate" ] && [ $# = 3 ] && [ "$3" != . ] && diff -r -q "$3" "$hc" > /dev/null 2>&1; then' \
  '  o=$(cat "$hc.out"); printf "%s\n" "${o//"$hc"/"$3"}"; exit "$(cat "$hc.rc")"; fi' \
  "exec $(printf %q "$CLAUDE") \"\$@\"" > "$R/bin/claude"
printf '%s\n' '#!/usr/bin/env bash' 'echo "$*" >> "$(dirname "$0")/../runs"' > "$R/stub/claude"
chmod +x "$R/bin/claude" "$R/stub/claude"
printf 'runs\n' > "$R/.gitignore"
git -C "$R" init -q && git -C "$R" add -A && git -C "$R" commit -qm init
git -C "$R" archive HEAD -- hooks types .claude-plugin | tar -x -C "$HC" || { no "could not copy HEAD's plugin"; exit 1; }
"$CLAUDE" plugin validate "$HC" > "$HC.out" 2>&1; echo $? > "$HC.rc"
grep -q "^Validating hooks: $HC/hooks/elements.ts" "$HC.out" || { no "HEAD's validate does not name its files: $(cat "$HC.out")"; exit 1; }
# A kept value the mod adds: an atom it writes, `conveyor-belt.extra`.
EXTRA="const extra = atom({ plugin: 'conveyor-belt', key: 'extra' } as const, 0)
export const bumpExtra = (\$: any) => update(\$, extra, (v: number) => v + 1)"
# checks [<PATH>]: the checks of the Test step (--checks) on the copy; output in $T/out, exit in $T/rc.
checks() {
  rm -f "$R/runs"
  (cd "$R" && PATH=${1:-$R/bin:$PATH} bash .conveyor/test-changed.sh --checks) > "$T/out" 2>&1; echo $? > "$T/rc"
}
# runs: the worktree's validate runs (`plugin validate .`); the run on HEAD's copy (issue 617) names its directory.
runs() { grep -c '^plugin validate \.$' "$R/runs" 2>/dev/null || echo 0; }
PARTS=()
part() { PARTS+=("$1"); (B=$T; T=$T/$1; mkdir "$T" && cp -a "$B/r" "$T/r" || exit 1; R=$T/r; "p_$1") > "$T/$1.res" 2>&1 & }

# D1: the mod keeps a value its types contract does not declare: the checks fail, naming the key.
p_undeclared() {
  echo "$EXTRA" >> "$R/hooks/units.tsx"; checks
  [ "$(cat "$T/rc")" = 1 ] && [ "$(runs)" = 1 ] && grep -q 'conveyor-belt\.extra is not declared' "$T/out" && grep -q '✘ Validation failed' "$T/out" \
    && ok "a mod change that keeps an undeclared value fails the checks, and the output names the key" \
    || no "undeclared extra: exit $(cat "$T/rc"), runs $(runs): $(cat "$T/out")"
}
# D2: the same change with the key declared in types/index.d.ts passes (its validate ran, with warnings only).
p_declared() {
  echo "$EXTRA" >> "$R/hooks/units.tsx"
  awk '{ print } /^      now: number$/ { print "      extra: number" }' "$R/types/index.d.ts" > "$T/d" && cat "$T/d" > "$R/types/index.d.ts"
  grep -q '^      extra: number$' "$R/types/index.d.ts" || { no "the fixture did not declare extra"; return; }
  checks
  [ "$(cat "$T/rc")" = 0 ] && [ "$(runs)" = 1 ] && ! grep -q 'claude plugin validate' "$T/out" \
    && ok "the same change with the key declared in the types contract passes the checks" \
    || no "declared extra: exit $(cat "$T/rc"), runs $(runs): $(cat "$T/out")"
}
# D3: a change to conveyor/lib/ alone does not run the check (the stub notes a run).
p_lib() {
  echo 'y() { :; }' >> "$R/conveyor/lib/x.sh"; checks "$R/stub:$PATH"
  [ "$(cat "$T/rc")" = 0 ] && ! grep -q '^plugin validate' "$R/runs" 2>/dev/null \
    && ok "a change to conveyor/lib/ alone does not run claude plugin validate" || no "lib change: exit $(cat "$T/rc"), runs $(runs): $(cat "$T/out")"
}
# No `claude` on the build machine: the checks say the check could not run and fail, so the mod never lands unchecked.
p_noclaude() {
  mkdir "$T/nobin"; for d in ${PATH//:/ }; do ln -s "$d"/* "$T/nobin/" 2>/dev/null; done; rm -f "$T/nobin/claude"
  echo note > "$R/.claude-plugin/note.txt"; checks "$T/nobin"
  [ "$(cat "$T/rc")" = 1 ] && grep -q 'claude plugin validate: could not run, claude is not installed' "$T/out" \
    && ok "with no claude, a change to the plugin fails the checks and says the check could not run" \
    || no "no claude: exit $(cat "$T/rc"): $(cat "$T/out")"
}

# A change to types/ alone runs the check (D2's case also edits hooks/, so it does not show this). These two parts
# check only that the check runs, so the stub stands for claude.
p_types() {
  echo '// a note' >> "$R/types/index.d.ts"; checks "$R/stub:$PATH"
  [ "$(cat "$T/rc")" = 0 ] && [ "$(runs)" = 1 ] \
    && ok "a change to types/ alone runs claude plugin validate" || no "types change: exit $(cat "$T/rc"), runs $(runs): $(cat "$T/out")"
}
# A file moved out of hooks/ runs the check: git's rename view names only the new path, outside hooks/.
p_moved() {
  git -C "$R" mv hooks/units.test.tsx units.test.tsx; checks "$R/stub:$PATH"
  [ "$(runs)" = 1 ] \
    && ok "a file moved out of hooks/ runs claude plugin validate" || no "moved file: exit $(cat "$T/rc"), runs $(runs): $(cat "$T/out")"
}

# Issue 617: validate reports type errors as warnings only, so a change could add one that breaks a /units view at
# run time and pass. HEAD's elements.ts has one "Object is possibly 'undefined'" (TS2532); the change adds a second.
p_typeerr() {
  echo "export const firstLen = (a: string[]) => a[0].length" >> "$R/hooks/elements.ts"; checks
  local l; l=$(wc -l < "$R/hooks/elements.ts"); l=${l// /}
  [ "$(cat "$T/rc")" = 1 ] && grep -q '^plugin validate /' "$R/runs" \
    && grep -q "^claude plugin validate: a type error this change adds" "$T/out" \
    && grep -qF "hooks/elements.ts:$l: error TS2532: Object is possibly 'undefined'." "$T/out" \
    && ok "a mod change that adds a type error HEAD's copy does not have fails the checks, naming its file, line and text" \
    || no "added type error: exit $(cat "$T/rc"): $(cat "$T/out")"
}
# The same errors as HEAD's at other lines (two lines added above all of them) are not new: the checks pass.
p_typemoved() {
  { printf '// a\n// b\n'; cat "$R/hooks/elements.ts"; } > "$T/e" && cat "$T/e" > "$R/hooks/elements.ts"; checks
  [ "$(cat "$T/rc")" = 0 ] && grep -q '^plugin validate /' "$R/runs" && ! grep -q 'claude plugin validate' "$T/out" \
    && ok "a mod change with HEAD's type errors at other lines passes the checks" \
    || no "moved type errors: exit $(cat "$T/rc"): $(cat "$T/out")"
}

for p in undeclared declared lib noclaude types moved typeerr typemoved; do part "$p"; done
wait
for p in "${PARTS[@]}"; do cat "$T/$p.res"; grep -q '^ok' "$T/$p.res" || echo "not ok - part $p checked nothing"; done | awk '{ sub(/^ok -/, "ok " NR " -"); sub(/^not ok -/, "not ok " NR " -"); print } /^not ok/ { f = 1 } END { exit f }'
