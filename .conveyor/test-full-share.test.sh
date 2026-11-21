#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# This project's full test suite (.conveyor/test-full.sh) in parallel mode, with each file's share of the temp space
# (the host file's testTmpMB) at 1 MB. Bug (#1238): a run of 4 files at once filled the machine's /tmp, and 155 files and
# the suite's own log failed with "Disk quota exceeded". A file that writes past its share fails alone with a reason
# that names the share and the space, and a file run beside it passes.
set -u
HERE=$(cd "$(dirname "$0")" && pwd -P)
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
AT=@
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t${AT}example.com GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t${AT}example.com
fails=0
no() { echo "not ok - $1"; fails=1; }

# A scratch repo with the real script and four files, all run at once:
# - fine writes 100 KB in its TMPDIR, waits for many to start and passes;
# - many writes four files of 400 KB in its TMPDIR (each under the size limit, 1,600 KB in all) and then would sleep
#   30 s: only the suite's look at its folder while it runs (spaceguard) stops it;
# - quick writes two files of 600 KB in its TMPDIR and exits 0 at once, before that first look: only the look when it
#   has ended fails it;
# - big writes one file of 3 MB outside its TMPDIR, where no look sees it, and notes its size: only the size limit
#   (ulimit -f) cuts it at the share.
R=$T/r; mkdir -p "$R/.conveyor" "$R/lib"
cp "$HERE/test-full.sh" "$HERE/test-share.sh" "$R/.conveyor/"
printf '%s\n' 'head -c 102400 /dev/zero > "$TMPDIR/f"' \
  'i=0; while [ ! -e "$(dirname "$0")/../many.started" ] && [ $i -lt 100 ]; do sleep 0.1; i=$((i + 1)); done' \
  '[ -e "$(dirname "$0")/../many.started" ]' > "$R/lib/fine.test.sh"
printf '%s\n' ': > "$(dirname "$0")/../many.started"' \
  'for i in 1 2 3 4; do head -c 409600 /dev/zero > "$TMPDIR/m$i"; done; sleep 30' > "$R/lib/many.test.sh"
printf '%s\n' 'for i in 1 2; do head -c 614400 /dev/zero > "$TMPDIR/q$i"; done' > "$R/lib/quick.test.sh"
printf '%s\n' 'head -c 3145728 /dev/zero > "$(dirname "$0")/../big.out"' \
  'wc -c < "$(dirname "$0")/../big.out" | tr -d " " > "$(dirname "$0")/../big.size"' > "$R/lib/big.test.sh"
printf '%s\n' many.started big.out big.size > "$R/.gitignore"
git -C "$R" init -q && git -C "$R" add -A && git -C "$R" commit -qm init
mkdir -p "$T/config/conveyor" && echo '{"testTmpMB": 1}' > "$T/config/conveyor/host.json"

s=$SECONDS
# The real suite runner, on its scratch repo: only a run of it shows a file stopped by the look at its folder while a
# file beside it, in a parallel worker of its own, runs on and passes.
(cd "$R" && unset CONVEYOR_TEST_SLOT CONVEYOR_CARD CONVEYOR_TEST_WHOLE CONVEYOR_TEST_LOG && XDG_CONFIG_HOME=$T/config \
  CONVEYOR_TEST_POOL=4:$T/pool CONVEYOR_TEST_SLOTS=$HERE/../conveyor/lib/slots.sh CONVEYOR_SUITE_MODE=parallel \
  CONVEYOR_SUITE_AT_ONCE=4 timeout 60 bash .conveyor/test-full.sh) > "$T/out" 2>&1
rc=$? took=$((SECONDS - s))
space=$(df -Pk "${TMPDIR:-/tmp}" | awk 'NR == 2 { print $NF }')
[ "$rc" = 1 ] || no "the run with two files past their share exited $rc, not 1: $(cat "$T/out")"
grep -qxF -- '-- ok lib/fine.test.sh' "$T/out" || no "the file run beside them did not pass: $(cat "$T/out")"
for f in many quick; do
  grep -qxF -- "-- FAIL lib/$f.test.sh" "$T/out" \
    && grep -qE "^test-full: lib/$f\\.test\\.sh wrote [0-9]+ KB in its temp folder, and its share of the space under $space is 1024 KB \\(the host file's testTmpMB, 1 MB\\): it fails\$" "$T/out" \
    || no "lib/$f.test.sh did not fail with the reason that names its share and the space under $space: $(cat "$T/out")"
done
[ "$(cat "$R/big.size" 2>/dev/null)" = 1048576 ] || no "one file of 3 MB was not cut at the 1 MB share, but is $(cat "$R/big.size" 2>/dev/null) bytes: $(cat "$T/out")"
[ "$took" -lt 25 ] || no "the file past its share was not stopped, but ran on: the run took ${took}s"
[ "$fails" = 0 ] && echo "ok - a file past its share of the temp space fails alone, with the reason"
exit $fails
