#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# The card's test step (.conveyor/test-changed.sh) runs each test file with a share of the temp space (the host file's
# testTmpMB) and a TMPDIR of its own, as the full suite does (.conveyor/test-share.sh). Bug (#1238): the step ran its
# files with no share and in the caller's TMPDIR, so one file could fill the build machine's /tmp for every other file
# and card, and the files' temp folders were left there. A file past its share fails alone with the reason, an engine
# case file run beside it passes, each file's temp folder is gone once it ends, and with no room for a share no file
# starts, and once the wait for room (the host file's testTmpWaitSec) ends each is a host problem with the reason.
set -u
HERE=$(cd "$(dirname "$0")" && pwd -P)
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
AT=@
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t${AT}example.com GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t${AT}example.com
unset CONVEYOR_TEST_LOG CONVEYOR_SHELL_TEST_CASE CONVEYOR_TEST_FILE CONVEYOR_TEST_FILELIST BASH_ENV CONVEYOR_TEST_RERUN CONVEYOR_TEST_SLOT CONVEYOR_TEST_SLOTS CONVEYOR_TEST_POOL
fails=0
no() { echo "not ok - $1"; fails=1; }

# A scratch repo: the real script, three areas (a: x.sh and a.test.sh; b: y.sh and b.test.sh; c: z.sh and c.test.sh,
# which no change here selects, so the change is not a run of every case file, which the runner runs) and a runner stub that
# notes its TMPDIR in $R/dirs/<case file> and writes there: 100 KB for a.test.sh, two files of 600 KB for b.test.sh
# (1,200 KB, past the 1 MB share, each under the size limit); and two other test files, lib/big.test.sh, which writes
# the same 1,200 KB, and lib/fine.test.sh, which notes its TMPDIR and writes 100 KB. The share is 1 MB.
R=$T/r; mkdir -p "$R/.conveyor" "$R/conveyor/tests" "$R/lib" "$R/dirs"
cp "$HERE/test-changed.sh" "$HERE/test-share.sh" "$HERE/lint-shell.sh" "$R/.conveyor/"; : > "$R/.conveyor/test-lint.sh"; : > "$R/.conveyor/no-browser-tests.sh"; : > "$R/.conveyor/no-records-split.sh"
printf '%s\n' '{"area": "a", "file": "conveyor/x.sh"}' '{"area": "a", "test": "a.test.sh"}' \
  '{"area": "b", "file": "conveyor/y.sh"}' '{"area": "b", "test": "b.test.sh"}' \
  '{"area": "c", "file": "conveyor/z.sh"}' '{"area": "c", "test": "c.test.sh"}' > "$R/.conveyor/engine-areas.json"
printf 't_aone() {\n  :\n}\n' > "$R/conveyor/tests/a.test.sh"; printf 't_bone() {\n  :\n}\n' > "$R/conveyor/tests/b.test.sh"
printf 't_cone() {\n  :\n}\n' > "$R/conveyor/tests/c.test.sh"
cat > "$R/conveyor/conveyor.test.sh" <<'EOF'
f=${CONVEYOR_TEST_FILE##*/}; echo "$TMPDIR" > "$(dirname "$0")/../dirs/$f"
if [ "$f" = b.test.sh ]; then head -c 614400 /dev/zero > "$TMPDIR/b1"; head -c 614400 /dev/zero > "$TMPDIR/b2"; else head -c 102400 /dev/zero > "$TMPDIR/a"; fi
echo "ok $CONVEYOR_SHELL_TEST_CASE"
EOF
printf '%s\n' 'head -c 614400 /dev/zero > "$TMPDIR/q1"; head -c 614400 /dev/zero > "$TMPDIR/q2"' > "$R/lib/big.test.sh"
printf '%s\n' 'echo "$TMPDIR" > "$(dirname "$0")/../dirs/fine"; head -c 102400 /dev/zero > "$TMPDIR/f"' > "$R/lib/fine.test.sh"
echo one > "$R/conveyor/x.sh"; echo one > "$R/conveyor/y.sh"; echo one > "$R/conveyor/z.sh"
echo '{"test": {"files": {"conveyor/conveyor.test.sh": {"wholeOnly": true}}}}' > "$R/.conveyor/project.json"
echo dirs > "$R/.gitignore"
git -C "$R" init -q && git -C "$R" add -A && git -C "$R" commit -qm init
echo two >> "$R/conveyor/x.sh"; echo two >> "$R/conveyor/y.sh"; echo ': two' >> "$R/lib/big.test.sh"; echo ': two' >> "$R/lib/fine.test.sh"
# run <name> <share in MB> [<wait for room, s>]: the step on that change, with a host file of its own that gives the
# share and the wait (testTmpWaitSec, 0 by default here), and the step's TMPDIR $T/<name>.tmp. The real step runner,
# on its scratch repo: only a run of it shows that each place it starts a file (the engine case files side by side,
# then each other file) gives the file its share and a folder of its own.
run() {
  rm -f "$R"/dirs/*; mkdir -p "$T/$1.log" "$T/$1.tmp" "$T/$1.config/conveyor" && echo "{\"testTmpMB\": $2, \"testTmpWaitSec\": ${3:-0}}" > "$T/$1.config/conveyor/host.json"
  (cd "$R" && env CONVEYOR_TEST_LOG="$T/$1.log" XDG_CONFIG_HOME="$T/$1.config" TMPDIR="$T/$1.tmp" timeout 120 bash .conveyor/test-changed.sh) > "$T/$1.out" 2>&1
  echo $? > "$T/$1.rc"
}

run share 1
L=$T/share.log/test-changed.log; space=$(df -Pk "$T/share.tmp" | awk 'NR == 2 { print $NF }')
[ "$(cat "$T/share.rc")" = 1 ] || no "the step with two files past their share exited $(cat "$T/share.rc"), not 1: $(cat "$T/share.out")"
for f in conveyor/tests/b.test.sh lib/big.test.sh; do
  grep -qxF -- "-- FAIL $f" "$L" \
    && grep -qE "^test-changed: ${f//./\\.} wrote [0-9]+ KB in its temp folder, and its share of the space under $space is 1024 KB \\(the host file's testTmpMB, 1 MB\\): it fails\$" "$T/share.out" \
    || no "$f, past its share, did not fail with the reason that names the share and the space: $(cat "$T/share.out")"
done
grep -qxF -- '-- ok conveyor/tests/a.test.sh' "$L" && grep -qxF -- '-- ok lib/fine.test.sh' "$L" \
  || no "a file within its share did not pass beside the ones past theirs: $(cat "$L") $(cat "$T/share.out")"
for f in a.test.sh b.test.sh fine; do
  read -r d < "$R/dirs/$f" || { no "$f noted no TMPDIR: $(cat "$T/share.out")"; continue; }
  [ "${d#"$T"/share.tmp/}" != "$d" ] || no "$f's TMPDIR was no folder of its own in the step's TMPDIR: '$d'"
  [ ! -e "$d" ] || no "$f's temp folder $d is left once it ended: $(ls -A "$d")"
done
[ -z "$(ls -A "$T/share.tmp")" ] || no "the step left files in its TMPDIR: $(ls -A "$T/share.tmp")"

# Bug #1662: a file that did not start for want of room in the temp space was a failed test (`-- FAIL`), and the
# engine marked main red on it. With no room for a share, no file of another run holding one and a wait for room of
# 1 s, the run waits, and then each file is a host problem: not run (`-- notrun`), and a `TESTRUN host` line with the
# reason, which the engine reads as a run with no result (conveyor/lib/testrun.sh voidrun()). The run still fails.
run full 9999999 1
[ "$(cat "$T/full.rc")" = 1 ] && [ -z "$(ls -A "$R/dirs")" ] || no "files ran with no room for their share (exit $(cat "$T/full.rc")): $(ls -A "$R/dirs") $(cat "$T/full.out")"
for f in conveyor/tests/a.test.sh lib/fine.test.sh; do
  grep -qE "^test-changed: ${f//./\\.} did not start: [0-9]+ MB is free to this user under .*, and it needs 19999998 MB there" "$T/full.out" \
    || no "$f, with no room for its share, did not fail with the reason: $(cat "$T/full.out")"
done
L=$T/full.log/test-changed.log; tab=$'\t'
! grep -q '^-- FAIL ' "$L" || no "a file that did not start for want of room was logged as failed: $(grep '^-- FAIL ' "$L")"
for f in conveyor/tests/a.test.sh conveyor/tests/b.test.sh lib/big.test.sh lib/fine.test.sh; do
  grep -qxF -- "-- notrun $f" "$L" && grep -qE "^TESTRUN host$tab${f//./\\.}${tab}test-changed: ${f//./\\.} did not start: [0-9]+ MB is free to this user under .*, and it needs 19999998 MB there" "$L" \
    || no "$f, with no room for its share after the wait, was not logged as not run for a host problem with the reason: $(cat "$L")"
done

# Bug #1662: with no file of any run holding a share, the step did not wait for room at all, so space that other
# things held for a while failed the files. df here (on PATH, the only df the step reads) shows 1 MB free for its
# first 4 reads (the step's setup, then the first file's look and its wait), then 1 GB; the share is 64 MB and the wait
# for room 60 s. The run waits, and once room comes back every file runs and passes. On the machine's slots (a shares
# folder: share_take's path on a build machine), so no file of another run holds a share there.
mkdir -p "$T/back.bin" "$T/back.log" "$T/back.tmp" "$T/back.config/conveyor" && echo '{"testTmpMB": 64, "testTmpWaitSec": 60}' > "$T/back.config/conveyor/host.json"
printf '#!/usr/bin/env bash\nn=$(($(cat %q 2>/dev/null || echo 0) + 1)); echo "$n" > %q\necho "Filesystem 1024-blocks Used Available Capacity Mounted on"\necho "room 0 0 $([ "$n" -le 4 ] && echo 1024 || echo 1048576) 0%% /room"\n' \
  "$T/back.n" "$T/back.n" > "$T/back.bin/df" && chmod +x "$T/back.bin/df"
rm -f "$R"/dirs/*
(cd "$R" && env PATH="$T/back.bin:$PATH" CONVEYOR_TEST_SLOTS="$HERE/../conveyor/lib/slots.sh" CONVEYOR_TEST_POOL=2:"$T/back.pool" CONVEYOR_TEST_LOG="$T/back.log" \
  XDG_CONFIG_HOME="$T/back.config" TMPDIR="$T/back.tmp" timeout 120 bash .conveyor/test-changed.sh) > "$T/back.out" 2>&1
b=$?; L=$T/back.log/test-changed.log
[ $b = 0 ] && [ "$(grep -c '^-- ok ' "$L")" = 4 ] && ! grep -q '^TESTRUN host' "$L" && [ "$(cat "$T/back.n")" -gt 4 ] \
  || no "with 1 MB free for df's first 4 reads ($(cat "$T/back.n" 2>&1) reads) and 1 GB after, a 64 MB share and a wait for room of 60 s, the step (exit $b) did not wait and run its 4 files to a pass: $(grep '^-- \|^TESTRUN host' "$L") $(cat "$T/back.out")"

# Bug: when a file that started had ended before the wait for one to end began, a bash before 5.3 left `wait -n -p`'s
# pid unset, and the step stopped at it (set -u) without the other files' results. A share the space holds for one
# file but not two makes b.test.sh wait for a.test.sh, and a `wait -n` that, as such a bash does, leaves the pid unset
# (BASH_ENV, read by the step's own bash): both still run and pass.
. "$HERE/test-share.sh"; free=$(share_free "$T") || no "the free space under $T could not be read"
printf '%s\n' 'wait() { if [ "${1:-}" = -n ]; then shift 3; local q; while :; do for q; do kill -0 "$q" 2>/dev/null || return 127; done; sleep 0.1; done; fi; builtin wait "$@"; }' > "$T/oldwait.sh"
rm -f "$R"/dirs/*; mkdir -p "$T/wait.log" "$T/wait.tmp" "$T/wait.config/conveyor" && echo "{\"testTmpMB\": $((${free:-0} * 2 / 5 / 1024))}" > "$T/wait.config/conveyor/host.json"
(cd "$R" && env BASH_ENV="$T/oldwait.sh" CONVEYOR_TEST_LOG="$T/wait.log" XDG_CONFIG_HOME="$T/wait.config" TMPDIR="$T/wait.tmp" timeout 120 bash .conveyor/test-changed.sh) > "$T/wait.out" 2>&1
w=$?
[ $w = 0 ] && grep -qxF -- '-- ok conveyor/tests/a.test.sh' "$T/wait.log/test-changed.log" && grep -qxF -- '-- ok conveyor/tests/b.test.sh' "$T/wait.log/test-changed.log" \
  || no "with a wait -n that left its pid unset, the step (exit $w) did not run both engine case files: $(cat "$T/wait.out")"

# Bug: when the step's own temp file could not be made (a full /tmp), its name was empty, and the cleanup at its end
# removed "$o".*, that is .* in the checkout: .git, .conveyor and every other hidden file. Last, as that bug removes them.
(cd "$R" && env CONVEYOR_TEST_LOG="$T/gone.log" TMPDIR="$T/gone" timeout 120 bash .conveyor/test-changed.sh) > "$T/gone.out" 2>&1
g=$?
[ $g = 1 ] && grep -qxF "test-changed: no temp file could be made in $T/gone; nothing run" "$T/gone.out" \
  || no "with no temp file to be made in TMPDIR, the step exited $g without the reason: $(cat "$T/gone.out")"
[ -d "$R/.git" ] && [ -d "$R/.conveyor" ] && [ -e "$R/.gitignore" ] || no "with no temp file to be made in TMPDIR, the step removed hidden files of its checkout: $(ls -A "$R")"

[ $fails = 0 ] && echo "ok - the card's test step runs each test file with its share of the temp space and a temp folder of its own" || exit 1
