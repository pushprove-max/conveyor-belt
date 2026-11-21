#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# This project's full test suite (.conveyor/test-full.sh): a file starts only when the space this user can still
# write in its temp folder holds a share (the host file's testTmpMB) for each file running, one for it and one kept for the belt. Bug (#1238): files
# started on a /tmp with no room left, and 155 failed with "Disk quota exceeded" in no file's own fault. Two fixtures,
# run side by side: in one the space can never hold the share, and the file fails without running, with the reason;
# in the other, in parallel, the third file waits for a running one to end.
set -u
HERE=$(cd "$(dirname "$0")" && pwd -P)
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
AT=@
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t${AT}example.com GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t${AT}example.com
fails=0
no() { echo "not ok - $1"; fails=1; }
repo() { # <name> <file>...: a scratch repo with the real script and a test file of each name, that notes when it
  # starts and ends in its own times file, sleeping the seconds of the file's name between
  local r=$T/$1 f; mkdir -p "$r/.conveyor" "$r/lib" "$r/times"; cp "$HERE/test-full.sh" "$HERE/test-share.sh" "$r/.conveyor/"
  for f in "${@:2}"; do
    printf '%s\n' "echo \"\$EPOCHREALTIME\" > \"\$(dirname \"\$0\")/../times/$f.start\"" "sleep ${f#*-}" \
      "echo \"\$EPOCHREALTIME\" > \"\$(dirname \"\$0\")/../times/$f.end\"" > "$r/lib/$f.test.sh"
  done
  echo times > "$r/.gitignore"
  git -C "$r" init -q && git -C "$r" add -A && git -C "$r" commit -qm init
}
# The real suite runner, on a scratch repo: only a run of it shows a file kept from starting until a worker ends, as
# the wait is in its loop that starts the workers, not in a function of its own.
suite() { # <name> <share in MB> <env>...: the suite run in that repo, with a host file of its own that gives the share
  mkdir -p "$T/$1.config/conveyor" && echo "{\"testTmpMB\": $2}" > "$T/$1.config/conveyor/host.json"
  (cd "$T/$1" && unset CONVEYOR_TEST_SLOT CONVEYOR_CARD CONVEYOR_TEST_WHOLE CONVEYOR_TEST_LOG && XDG_CONFIG_HOME=$T/$1.config \
    CONVEYOR_TEST_POOL=3:$T/$1.pool CONVEYOR_TEST_SLOTS=$HERE/../conveyor/lib/slots.sh env "${@:3}" timeout 60 bash .conveyor/test-full.sh) > "$T/$1.out" 2>&1
  echo $? > "$T/$1.rc"
}
space=$(df -Pk "${TMPDIR:-/tmp}" | awk 'NR == 2 { print $NF }')
# The MB this user can still write there, as the suite reckons it: the free space, or the quota left when that is less.
# shellcheck source=.conveyor/test-share.sh
. "$HERE/test-share.sh"; free=$(($(share_free "${TMPDIR:-/tmp}") / 1024))
# none: a share of 9,999,999 MB, which no space here holds.
repo none x-0
# wait: a share of the free space / 3.5, so two files start (2 then 3 shares) and the third (4 shares) waits for one
# of them to end; half a share is left either way, for what others write meanwhile.
repo wait a-1 b-2 c-0
suite none 9999999 & suite wait $((free * 2 / 7)) CONVEYOR_SUITE_MODE=parallel CONVEYOR_SUITE_AT_ONCE=3 & wait

[ "$(cat "$T/none.rc")" = 1 ] && grep -qxF -- '-- FAIL lib/x-0.test.sh' "$T/none.out" \
  && grep -qE "^test-full: lib/x-0\\.test\\.sh did not start: [0-9]+ MB is free to this user under $space \\(its free space, or what is left of the user's quota there when that is less\\), and it needs 19999998 MB there: a share \\(the host file's testTmpMB, 9999999 MB\\) for each of the 0 file\\(s\\) running, one for it and one kept for the belt\$" "$T/none.out" \
  || no "a file the space cannot hold did not fail with the reason (exit $(cat "$T/none.rc")): $(cat "$T/none.out")"
[ ! -e "$T/none/times/x-0.start" ] || no "a file the space cannot hold ran"
[ "$(cat "$T/wait.rc")" = 0 ] || no "the files that had room did not all pass (exit $(cat "$T/wait.rc")): $(cat "$T/wait.out")"
read -r ae < "$T/wait/times/a-1.end"; read -r bs < "$T/wait/times/b-2.start"; read -r cs < "$T/wait/times/c-0.start"
awk -v a="$ae" -v b="$bs" -v c="$cs" 'BEGIN { exit !(b < a && c >= a) }' \
  || no "the third file did not wait for a running one to end, or the second waited (a ended $ae, b started $bs, c started $cs; $free MB free): $(cat "$T/wait.out")"
[ "$fails" = 0 ] && echo "ok - a file starts only with room for its share, and waits for it or fails with the reason"
exit $fails
