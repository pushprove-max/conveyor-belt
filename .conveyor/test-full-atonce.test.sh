#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# How many test files this project's full test suite (.conveyor/test-full.sh) runs at once (#1174): in parallel mode
# at most CONVEYOR_SUITE_AT_ONCE (release-prep's, from the control record's suiteAtOnce), 2 when unset, and never more
# than the pool's slots; in serial mode one, whatever it is. Bugs: a parallel run started a file on every slot of the
# machine (16 on the build machine), so the belt crawled while the suite ran; a setting above the slots ran more files
# than the slots; a setting reached serial mode.
set -u
HERE=$(cd "$(dirname "$0")" && pwd -P)
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
AT=@
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t${AT}example.com GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t${AT}example.com
fails=0
no() { echo "not ok - $1"; fails=1; }

# A scratch repo with the real script and six engine case files, which hold no slot of the pool (each of their cases
# takes its own), so the files at once are the suite's limit alone, not the machine's free cores. Each file marks
# itself live in $LIVE, pauses, notes how many files are live, and ends.
R=$T/r; mkdir -p "$R/.conveyor" "$R/conveyor/tests"
cp "$HERE/test-full.sh" "$HERE/test-share.sh" "$R/.conveyor/"
for i in 1 2 3 4 5 6; do
  # sleep: a stand-in test file that runs a while, so files the suite runs at once overlap
  printf '%s\n' ': > "$LIVE/live.$$"; sleep 0.5' 'find "$LIVE" -name "live.*" | wc -l >> "$LIVE/seen"; rm "$LIVE/live.$$"' > "$R/conveyor/tests/fx-$i.test.sh"
done
git -C "$R" init -q && git -C "$R" add -A && git -C "$R" commit -qm init
mkdir "$T/config"

# The pool's slots for a pool of <size>: slot_pool makes it no larger than the machine's cores.
slots() { (XDG_CONFIG_HOME=$T/config CONVEYOR_TEST_POOL=$1:$T/slots$1 && . "$HERE/../conveyor/lib/slots.sh" && slot_pool > /dev/null && echo "$SLOT_N"); }
min() { echo $(($1 < $2 ? $1 : $2)); }
# One run of the suite, in <name>'s own folder, with <mode>, a pool of <size> and CONVEYOR_SUITE_AT_ONCE <n> ('':
# unset). This runs the whole suite script, not one of its functions: the limit is in its top-level parallel loop, which
# is no function, and only files running side by side show how many it lets run at once.
run() { # <name> <mode> <size> <n>
  mkdir "$T/$1" && (cd "$R" && unset CONVEYOR_TEST_SLOT CONVEYOR_CARD CONVEYOR_TEST_WHOLE CONVEYOR_TEST_LOG CONVEYOR_SUITE_AT_ONCE \
    && export LIVE=$T/$1 XDG_CONFIG_HOME=$T/config CONVEYOR_TEST_POOL=$3:$T/pool-$1 CONVEYOR_TEST_SLOTS=$HERE/../conveyor/lib/slots.sh \
      CONVEYOR_SUITE_MODE=$2 ${4:+CONVEYOR_SUITE_AT_ONCE=$4} && timeout 60 bash .conveyor/test-full.sh) > "$T/$1.out" 2>&1
  echo $? > "$T/$1.rc"
}
# The four runs side by side, as each holds no slot: the test takes about its slowest, the serial one.
run unset parallel 8 '' & run four parallel 8 4 & run above parallel 3 9 & run serial serial 8 4 &
wait
# The most files live at once in run <name>; fails unless it passed with each of the six files run once.
most() { # <name>
  [ "$(cat "$T/$1.rc")" = 0 ] && [ "$(grep -c '' "$T/$1/seen" 2>/dev/null)" = 6 ] || { echo "the run did not pass with each file run once (exit $(cat "$T/$1.rc")): $(cat "$T/$1.out")"; return 1; }
  tr -d ' ' < "$T/$1/seen" | sort -n | tail -n 1
}
s8=$(slots 8) s3=$(slots 3)
[ -n "$s8" ] && [ -n "$s3" ] || no "the pool's slots could not be read"
# No setting is 2 at once (fewer only on a machine of fewer cores).
got=$(most unset); [ "$got" = "$(min 2 "$s8")" ] || no "a parallel run with no CONVEYOR_SUITE_AT_ONCE on a pool of $s8 slots did not run $(min 2 "$s8") at most at once: $got"
# The setting at 4 is at most 4 and, with six files waiting, 4 at some point.
got=$(most four); [ "$got" = "$(min 4 "$s8")" ] || no "a parallel run with CONVEYOR_SUITE_AT_ONCE=4 on a pool of $s8 slots did not run $(min 4 "$s8") at most at once: $got"
[ "$s8" -ge 4 ] || echo "# this machine has $s8 cores: the run with the setting at 4 ran $s8 at once"
# A setting above the slots runs at the slots.
got=$(most above); [ "$got" = "$s3" ] || no "a parallel run with CONVEYOR_SUITE_AT_ONCE=9 on a pool of $s3 slots did not run $s3 at most at once: $got"
# Serial mode is one at a time, whatever the setting.
got=$(most serial); [ "$got" = 1 ] || no "a serial run with CONVEYOR_SUITE_AT_ONCE=4 did not run one file at a time: $got"
exit $fails
