#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# test-changed.sh and Claude Code plugin test files (*.test.ts, *.test.tsx: the /units mod's tests in hooks/): the test
# step runs them under `claude plugin test`, which runs every such file of the plugin in one run, and writes one
# `-- ok` or `-- FAIL` line per file, as for the other test files.
# Bugs: the mod's tests are never run by a card's test step (it knew only .sh, .mjs and .py tests), so a change to
# the mod lands untested; one file's failure is read as every file's, or as none; the plugin's whole test run is made
# again for each of its files.
set -u
HERE=$(cd "$(dirname "$0")" && pwd -P)
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
AT=@
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t${AT}example.com GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t${AT}example.com
unset CONVEYOR_TEST_LOG CONVEYOR_SHELL_TEST_CASE CONVEYOR_TEST_FILE CONVEYOR_TEST_FILELIST BASH_ENV CONVEYOR_TEST_RERUN
ok() { echo "ok - $1"; }
no() { echo "not ok - $1"; }

# A scratch repo: the real script, an empty engine map, a mod's two sources and their test files, and a stub `claude`
# on PATH whose `plugin test` prints the parts $R/plugin-out holds (as Claude Code's runner prints them: a `<file>:`
# heading, a `(pass)` or `(fail)` line a test), exits 1 when one says (fail), and counts its runs in $R/runs. When
# $R/write is there, it writes 600 KB in its TMPDIR for each of the two test files, as each file's tests would.
R=$T/r; mkdir -p "$R/.conveyor" "$R/hooks" "$R/bin"
cp "$HERE/test-changed.sh" "$HERE/test-share.sh" "$HERE/lint-shell.sh" "$HERE/test-lint.sh" "$HERE/no-browser-tests.sh" "$HERE/no-records-split.sh" "$R/.conveyor/"
echo '{"outside": "conveyor/README.md"}' > "$R/.conveyor/engine-areas.json"
for s in a b; do echo "export const $s = 1" > "$R/hooks/$s.ts"; printf "test('%s one', () => {})\ntest('%s two', () => {})\n" "$s" "$s" > "$R/hooks/$s.test.tsx"; done
# Its `plugin validate` (the checks' run of it on a change to hooks/: issue 604) passes.
# stub: the test step runs the plugin's tests through `claude plugin test`, which no test here can run for real.
printf '%s\n' '#!/usr/bin/env bash' '[ "$1 $2" != "plugin validate" ] || { echo "✔ Validation passed"; exit 0; }' '[ "$1 $2" = "plugin test" ] || exit 2' 'echo run >> "$(dirname "$0")/../runs"' \
  '[ ! -e "$(dirname "$0")/../write" ] || for f in a b; do head -c 614400 /dev/zero > "$TMPDIR/$f"; done' \
  'cat "$(dirname "$0")/../plugin-out"' '! grep -q "^(fail)" "$(dirname "$0")/../plugin-out"' > "$R/bin/claude"
chmod +x "$R/bin/claude"
printf 'runs\nplugin-out\nwrite\nlog/\n' > "$R/.gitignore"
git -C "$R" init -q && git -C "$R" add -A && git -C "$R" commit -qm init
# run <the runner's output> <changed file>...: the card's test step on the copy (its log in $R/log); its output in
# $T/out, its exit in $T/rc. Prints the log's result lines.
run() {
  printf '%b' "$1" > "$R/plugin-out"; shift
  for f; do echo 'void 0;' >> "$R/$f"; done
  rm -rf "$R/runs" "$R/log"; mkdir "$R/log"
  (cd "$R" && PATH=$R/bin:$PATH CONVEYOR_TEST_LOG=$R/log bash .conveyor/test-changed.sh) > "$T/out" 2>&1; echo $? > "$T/rc"
  grep '^-- ' "$R/log/test-changed.log" | LC_ALL=C sort | paste -sd'|' -
}
runs() { wc -l < "$R/runs" 2>/dev/null | tr -d ' '; }
PASS='hooks/a.test.tsx:\n(pass) a one\n(pass) a two\n\nhooks/b.test.tsx:\n(pass) b one\n(pass) b two\n\n 4 pass\n 0 fail\n'
BFAIL='hooks/a.test.tsx:\n(pass) a one\n(pass) a two\n\nhooks/b.test.tsx:\n(pass) b one\n(fail) b two\n  AssertionError\n\n 3 pass\n 1 fail\n'
PARTS=()
part() { PARTS+=("$1"); (B=$T; T=$T/$1; mkdir "$T" && cp -a "$B/r" "$T/r" || exit 1; R=$T/r; "p_$1") > "$T/$1.res" 2>&1 & }

# A change to a mod source runs the test file named after it, through the plugin's runner, with its own ok line.
p_source() {
  got=$(run "$PASS" hooks/a.ts)
  [ "$got" = "-- ok hooks/a.test.tsx" ] && [ "$(cat "$T/rc")" = 0 ] && [ "$(runs)" = 1 ] \
    && ok "a change to a mod source runs its test file under claude plugin test, with its own ok line" \
    || no "source changed: '$got', runs $(runs), exit $(cat "$T/rc"): $(cat "$T/out")"
}
# Two test files selected: one plugin run, and each file's result its own part: b's failing test fails b alone.
p_perfile() {
  got=$(run "$BFAIL" hooks/a.test.tsx hooks/b.test.tsx)
  [ "$got" = "-- FAIL hooks/b.test.tsx|-- ok hooks/a.test.tsx" ] && [ "$(cat "$T/rc")" = 1 ] && [ "$(runs)" = 1 ] \
    && ok "two plugin test files: one run of the plugin's runner, an ok line for the passing file and a FAIL line for the failing one" \
    || no "two files, b failing: '$got', runs $(runs), exit $(cat "$T/rc"): $(cat "$T/out")"
}
# A file the runner printed no part for (it did not run) fails: no pass is never read as a pass.
p_missing() {
  got=$(run 'hooks/a.test.tsx:\n(pass) a one\n(pass) a two\n' hooks/b.test.tsx)
  [ "$got" = "-- FAIL hooks/b.test.tsx" ] && [ "$(cat "$T/rc")" = 1 ] \
    && ok "a plugin test file the runner printed no part for fails" || no "b not run: '$got', exit $(cat "$T/rc"): $(cat "$T/out")"
}

# Bug (#1394 R30): the one plugin run ran under the share of the first file selected, so the files' writes together
# (1,200 KB) passed that share (1 MB) though each file's (600 KB) is within it, and the files failed. The run has a
# share for each plugin test file: both pass.
p_share() {
  mkdir -p "$T/config/conveyor" && echo '{"testTmpMB": 1}' > "$T/config/conveyor/host.json" && : > "$R/write"
  got=$(XDG_CONFIG_HOME=$T/config run "$PASS" hooks/a.test.tsx hooks/b.test.tsx)
  [ "$got" = "-- ok hooks/a.test.tsx|-- ok hooks/b.test.tsx" ] && [ "$(cat "$T/rc")" = 0 ] && [ "$(runs)" = 1 ] \
    && ok "the plugin run has a share for each plugin test file: files within their own share pass though their writes together pass one share" \
    || no "a 1 MB share, the plugin run writing 600 KB for each of two files: '$got', runs $(runs), exit $(cat "$T/rc"): $(cat "$T/out")"
}

# Bug #1662: the plugin run did not start for want of room in the temp space, each plugin test file failed on it, and
# the engine marked main red on hooks/units.test.tsx. With no room for the run's shares and no wait for room
# (testTmpWaitSec 0), the runner does not start, and each file is a host problem, not a failed test: `-- notrun` and a
# `TESTRUN host` line with the reason (the engine's voidrun(): a run with no result). No slots library (so no shares
# folder): the shares the machine's other runs hold would make it wait for them.
p_noroom() {
  mkdir -p "$T/config/conveyor" && echo '{"testTmpMB": 9999999, "testTmpWaitSec": 0}' > "$T/config/conveyor/host.json"
  got=$(CONVEYOR_TEST_SLOTS=$T/noslots XDG_CONFIG_HOME=$T/config run "$PASS" hooks/a.test.tsx hooks/b.test.tsx)
  [ "$got" = "-- notrun hooks/a.test.tsx|-- notrun hooks/b.test.tsx" ] && [ "$(cat "$T/rc")" = 1 ] && [ ! -e "$R/runs" ] \
    && [ "$(grep -c $'^TESTRUN host\thooks/[ab]\\.test\\.tsx\ttest-changed: the plugin test run (claude plugin test, a share for each of its 2 test files) did not start: [0-9]* MB is free' "$R/log/test-changed.log")" = 2 ] \
    && ok "a plugin run that did not start for want of room makes each plugin test file a host problem, not a failure" \
    || no "no room for the plugin run's shares: '$got', runs $(runs 2>&1), exit $(cat "$T/rc"): $(cat "$R/log/test-changed.log" "$T/out")"
}

# Bug (review of #1662): when the plugin run's temp folder could not be made (a full /tmp, or one out of inodes, where
# no .noroom file can be written either), each plugin test file failed. A mkdir shim on PATH fails for that folder
# alone: the runner does not start, and each file is a host problem (the second one too, though the first one's run
# output was kept for it before).
p_nodir() {
  mkdir -p "$T/nd" && printf '#!/usr/bin/env bash\ncase $1 in */*.tmp/p) echo "mkdir: No space left on device" >&2; exit 1 ;; esac\nexec %q "$@"\n' "$(command -v mkdir)" > "$T/nd/mkdir" && chmod +x "$T/nd/mkdir"
  got=$(PATH=$T/nd:$PATH run "$PASS" hooks/a.test.tsx hooks/b.test.tsx)
  [ "$got" = "-- notrun hooks/a.test.tsx|-- notrun hooks/b.test.tsx" ] && [ "$(cat "$T/rc")" = 1 ] && [ ! -e "$R/runs" ] \
    && [ "$(grep -c $'^TESTRUN host\thooks/[ab]\\.test\\.tsx\ttest-changed: hooks/[ab]\\.test\\.tsx did not start: its temp folder, output file or pipe could not be made$' "$R/log/test-changed.log")" = 2 ] \
    && ok "a plugin run whose temp folder could not be made makes each plugin test file a host problem, not a failure" \
    || no "no temp folder for the plugin run: '$got', runs $(runs 2>&1), exit $(cat "$T/rc"): $(cat "$R/log/test-changed.log" "$T/out")"
}

# Bug (review of #1662): the same when the plugin run's output file $o.plugin could not be made. The mkdir shim, as it
# makes the step's $o.tmp, puts a link to a missing folder in $o.plugin's place, so the first open of it fails: the
# first file is a host problem, and the run is not kept as made, so the second file runs it again, and passes.
p_noout() {
  mkdir -p "$T/no" && printf '#!/usr/bin/env bash\ncase $1 in */tmp.*.tmp) %q "$1" && ln -s "$1/gone/out" "${1%%.tmp}.plugin"; exit ;; esac\nexec %q "$@"\n' "$(command -v mkdir)" "$(command -v mkdir)" > "$T/no/mkdir" && chmod +x "$T/no/mkdir"
  got=$(PATH=$T/no:$PATH run "$PASS" hooks/a.test.tsx hooks/b.test.tsx)
  [ "$got" = "-- notrun hooks/a.test.tsx|-- ok hooks/b.test.tsx" ] && [ "$(cat "$T/rc")" = 1 ] && [ "$(runs)" = 1 ] \
    && grep -q $'^TESTRUN host\thooks/a\\.test\\.tsx\ttest-changed: hooks/a\\.test\\.tsx did not start: ' "$R/log/test-changed.log" \
    && ok "a plugin run whose output file could not be made makes the file a host problem, and the next file runs it again" \
    || no "no output file for the plugin run (hooks/a.test.tsx and hooks/b.test.tsx changed): '$got', runs $(runs 2>&1), exit $(cat "$T/rc"): $(cat "$R/log/test-changed.log" "$T/out")"
}

for p in source perfile missing share noroom nodir noout; do part "$p"; done
wait
for p in "${PARTS[@]}"; do cat "$T/$p.res"; grep -q '^ok' "$T/$p.res" || echo "not ok - part $p checked nothing"; done | awk '{ sub(/^ok -/, "ok " NR " -"); sub(/^not ok -/, "not ok " NR " -"); print } /^not ok/ { f = 1 } END { exit f }'
