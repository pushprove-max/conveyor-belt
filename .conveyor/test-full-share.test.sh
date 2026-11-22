#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# This project's full test suite (.conveyor/test-full.sh) in parallel mode, with each file's share of the temp space
# (the host file's testTmpMB) at 1 MB. Bug (#1238): a run of 4 files at once filled the machine's /tmp, and 155 files and
# the suite's own log failed with "Disk quota exceeded". A file that writes past its share fails alone with a reason
# that names the share and the space, and a file run beside it passes. Bugs (#1394): a file wrote two shares before
# the first look at its folder (R15); one whose file the size limit cut passed (R16); one that wrote many files outside
# its temp folder, each under the limit, passed (R18).
set -u
HERE=$(cd "$(dirname "$0")" && pwd -P)
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
AT=@
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t${AT}example.com GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t${AT}example.com
fails=0
no() { echo "not ok - $1"; fails=1; }

# A scratch repo with the real script and six files, four at once:
# - fine writes 100 KB in its TMPDIR, notes the folder, waits for many to start and passes;
# - many writes four files of 400 KB in its TMPDIR (each under the size limit, 1,600 KB in all) and then would sleep
#   30 s: only the suite's look at its folder while it runs (share_guard) stops it;
# - quick writes two files of 600 KB in its TMPDIR and exits 0 at once, often before the first look: the look when it
#   has ended fails it then;
# - surge writes 2 MB (two shares) in its TMPDIR in 64 KB parts over about 0.5 s, noting each part before it writes
#   it, and would then sleep 30 s: a look each 1 s let it write it all before the first look (#1394 R15);
# - big writes one file of 3 MB outside its TMPDIR, in the checkout, where no look sees it, and notes its size: the
#   size limit (ulimit -f) cuts it at the share, which kills only head, so big exits 0 (#1394 R16);
# - spread writes four files of 1,000 KB in the checkout, each under the size limit (#1394 R18).
# Big and spread write only once fine's temp folder is gone, that is once share_run has checked fine: the checkout is
# checked only when a file has ended, so a file that ran while they wrote there fails too (share_run).
R=$T/r; mkdir -p "$R/.conveyor" "$R/lib"
cp "$HERE/test-full.sh" "$HERE/test-share.sh" "$R/.conveyor/"
printf '%s\n' 'head -c 102400 /dev/zero > "$TMPDIR/f"; echo "$TMPDIR" > "$(dirname "$0")/../fine.tmp"' \
  'i=0; while [ ! -e "$(dirname "$0")/../many.started" ] && [ $i -lt 100 ]; do sleep 0.1; i=$((i + 1)); done' \
  '[ -e "$(dirname "$0")/../many.started" ]' > "$R/lib/fine.test.sh"
printf '%s\n' ': > "$(dirname "$0")/../many.started"' \
  'for i in 1 2 3 4; do head -c 409600 /dev/zero > "$TMPDIR/m$i"; done; sleep 30' > "$R/lib/many.test.sh"
printf '%s\n' 'for i in 1 2; do head -c 614400 /dev/zero > "$TMPDIR/q$i"; done' > "$R/lib/quick.test.sh"
printf '%s\n' 'for i in $(seq 32); do echo "$i" > "$(dirname "$0")/../surge.n"; head -c 65536 /dev/zero > "$TMPDIR/s$i"; sleep 0.015; done; sleep 30' \
  > "$R/lib/surge.test.sh"
w='d=$(dirname "$0")/..; i=0; while { [ ! -s "$d/fine.tmp" ] || [ -e "$(cat "$d/fine.tmp")" ]; } && [ $i -lt 100 ]; do sleep 0.1; i=$((i + 1)); done'
printf '%s\n' "$w" 'head -c 3145728 /dev/zero > "$d/big.out"' 'wc -c < "$d/big.out" | tr -d " " > "$d/big.size"' > "$R/lib/big.test.sh"
printf '%s\n' "$w" 'for i in 1 2 3 4; do head -c 1024000 /dev/zero > "$d/spread$i.out"; done' > "$R/lib/spread.test.sh"
printf '%s\n' many.started fine.tmp surge.n big.out big.size 'spread*.out' > "$R/.gitignore"
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
[ "$rc" = 1 ] || no "the run with five files past their share exited $rc, not 1: $(cat "$T/out")"
grep -qxF -- '-- ok lib/fine.test.sh' "$T/out" || no "the file run beside them did not pass: $(cat "$T/out")"
for f in many quick surge; do
  grep -qxF -- "-- FAIL lib/$f.test.sh" "$T/out" \
    && grep -qE "^test-full: lib/$f\\.test\\.sh wrote [0-9]+ KB in its temp folder, and its share of the space under $space is 1024 KB \\(the host file's testTmpMB, 1 MB\\): it fails\$" "$T/out" \
    || no "lib/$f.test.sh did not fail with the reason that names its share and the space under $space: $(cat "$T/out")"
done
# R15: the folder was stopped at most 640 KB past its 1,024 KB share, what surge writes in about 0.15 s (a look each
# 0.1 s, and the TERM): surge noted at most 26 of its 32 parts of 64 KB. A look each 1 s let it write all 32.
n=$(cat "$R/surge.n" 2>/dev/null)
[ "${n:-99}" -le 26 ] || no "lib/surge.test.sh, writing 2 MB in its temp folder over 0.5 s, was not stopped by 1,664 KB: it began part ${n:-?} of 32 of 64 KB: $(cat "$T/out")"
[ "$(cat "$R/big.size" 2>/dev/null)" = 1048576 ] || no "one file of 3 MB was not cut at the 1 MB share, but is $(cat "$R/big.size" 2>/dev/null) bytes: $(cat "$T/out")"
# R16: big's last command passed after the size limit killed head; the cut file fails it.
grep -qxF -- '-- FAIL lib/big.test.sh' "$T/out" \
  && grep -qE "^test-full: lib/big\\.test\\.sh wrote a file larger than its share, or one the size limit \\(ulimit -f\\) cut at its share of 1024 KB \\(the host file's testTmpMB, 1 MB\\): .*/big\\.out: it fails" "$T/out" \
  || no "lib/big.test.sh, whose 3 MB file outside its temp folder was cut at the share, did not fail with the 'file larger than its share' reason: $(cat "$T/out")"
# R18: four files under the size limit in the checkout, 4,000 KB in all, fail spread with the space reason. The reason
# must count at least those 4,000 KB: big may write its 1,024 KB file while spread runs, and that alone meets the share.
o=$(sed -nE "s/^test-full: lib\\/spread\\.test\\.sh wrote ([0-9]+) KB in .*, outside its temp folder, and [0-9]+ KB in it, and its share of the space is 1024 KB \\(the host file's testTmpMB, 1 MB\\): it fails.*/\\1/p" "$T/out")
grep -qxF -- '-- FAIL lib/spread.test.sh' "$T/out" && [ "${o:-0}" -ge 4000 ] \
  || no "lib/spread.test.sh, which wrote four files of 1,000 KB outside its temp folder, did not fail with the space reason for 4,000 KB or more (it gave ${o:-none}): $(cat "$T/out")"
[ "$took" -lt 25 ] || no "the file past its share was not stopped, but ran on: the run took ${took}s"
[ "$fails" = 0 ] && echo "ok - a file past its share of the temp space fails alone, with the reason"
exit $fails
