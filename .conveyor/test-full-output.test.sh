#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# This project's full test suite (.conveyor/test-full.sh) in parallel mode, with each file's share of the temp space
# (the host file's testTmpMB) at 1 MB. Bug (issue 1439): each file's output went to a file in the suite's own temp
# folder, outside the file's share and its size limit, and stayed there until the suite ended, so a file that printed
# without end could fill the space. Its output, on stdout or on stderr, is cut at its share, the file fails with the
# reason, and its output file is gone once it has been printed.
set -u
HERE=$(cd "$(dirname "$0")" && pwd -P)
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
AT=@
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t${AT}example.com GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t${AT}example.com
fails=0
no() { echo "not ok - $1"; fails=1; }

# A scratch repo with the real script and three files, one at a time, in this order:
# - a-loud prints 20 MB on stdout and exits 0;
# - b-fine notes the files of the suite's temp folder (its TMPDIR's parent) as it runs, after a-loud has ended;
# - c-err prints 20 MB on stderr and exits 0.
R=$T/r; mkdir -p "$R/.conveyor" "$R/lib"
cp "$HERE/test-full.sh" "$HERE/test-share.sh" "$R/.conveyor/"
printf '%s\n' 'yes "a line of output" | head -c 20000000; exit 0' > "$R/lib/a-loud.test.sh"
printf '%s\n' 'ls "${TMPDIR%/*}" > "$(dirname "$0")/../fine.ls"' > "$R/lib/b-fine.test.sh"
printf '%s\n' 'yes "a line of errors" | head -c 20000000 >&2; exit 0' > "$R/lib/c-err.test.sh"
echo fine.ls > "$R/.gitignore"
git -C "$R" init -q && git -C "$R" add -A && git -C "$R" commit -qm init
mkdir -p "$T/config/conveyor" && echo '{"testTmpMB": 1}' > "$T/config/conveyor/host.json"

# The real suite runner, on its scratch repo: the output file is the parallel worker's, which only a run of the suite
# makes.
(cd "$R" && unset CONVEYOR_TEST_SLOT CONVEYOR_CARD CONVEYOR_TEST_WHOLE CONVEYOR_TEST_LOG && XDG_CONFIG_HOME=$T/config \
  CONVEYOR_TEST_POOL=2:$T/pool CONVEYOR_TEST_SLOTS=$HERE/../conveyor/lib/slots.sh CONVEYOR_SUITE_MODE=parallel \
  CONVEYOR_SUITE_AT_ONCE=1 timeout 60 bash .conveyor/test-full.sh) > "$T/out" 2>&1
rc=$?
size=$(wc -c < "$T/out")
[ "$rc" = 1 ] || no "the run with two files that printed 20 MB each exited $rc, not 1: $(head -c 2000 "$T/out")"
for f in a-loud c-err; do
  grep -qxF -- "-- FAIL lib/$f.test.sh" "$T/out" \
    && grep -q "^test-full: lib/$f\\.test\\.sh printed 1024 KB or more, .* (the host file's testTmpMB, 1 MB): its output is cut there, and it fails\$" "$T/out" \
    || no "lib/$f.test.sh, which printed 20 MB and exited 0, did not fail with the reason that names its share: $(grep -a -e "^test-full" -e '^-- ' "$T/out")"
done
# Each file's output is at most its share (1 MB), and the suite's own lines a little more.
[ "$size" -lt 2500000 ] || no "the two files' 40 MB of output were not cut at their 1 MB shares: the suite printed $size bytes"
grep -qxF -- '-- ok lib/b-fine.test.sh' "$T/out" || no "the file run after a-loud did not pass: $(grep -a -e "^test-full" -e '^-- ' "$T/out")"
# a-loud's output file (1.out) is removed once printed, before b-fine starts.
[ -f "$R/fine.ls" ] && ! grep -qxF 1.out "$R/fine.ls" \
  || no "a-loud's output file was still in the suite's temp folder after it ended: $(paste -sd' ' "$R/fine.ls" 2>/dev/null)"
[ "$fails" = 0 ] && echo "ok - a file's output is cut at its share of the space, and removed once printed"
exit $fails
