#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# The room check of the test files' share of the temp space (.conveyor/test-share.sh share_free, share_noroom, and the
# reason share_take gives when the room missing is the user's quota: share_quotanote), which
# the full suite and the card's test step run before each file starts. Bug (#1238 review): the check read only the
# space's free blocks (df), but the build machine's /tmp is mounted with usrquota, so a file started when the build
# user had less quota left than a share, and failed with "Disk quota exceeded" in no fault of its own. The check takes
# the lesser of the space's free blocks and what is left of the user's quota. share_quota is given here: a quota
# cannot be set up without root, so the test gives the number that a quota read would give.
set -u
HERE=$(cd "$(dirname "$0")" && pwd -P)
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
fails=0
no() { echo "not ok - $1"; fails=1; }
# shellcheck source=.conveyor/test-share.sh
. "$HERE/test-share.sh"
mkdir -p "$T/config/conveyor" && echo '{"testTmpMB": 1}' > "$T/config/conveyor/host.json"
XDG_CONFIG_HOME=$T/config share_init "$T" > "$T/why" || no "share_init failed on a share of 1 MB: $(cat "$T/why")"
df=$(df -Pk "$T" | awk 'NR == 2 { print $4 }')
[ "$df" -ge 4096 ] || { echo "not ok - $T has $df KB free, too little for the checks below"; exit 1; }

# A quota with 2 MB left, the space with more than 3 MB free: one file running, the next needs 3 shares (3 MB).
share_quota() { echo 2048; }
why=$(share_noroom "$T" 1) || no "share_noroom $T 1 found room with 2,048 KB of quota left, 3 MB needed and $df KB free in the space"
[ "$why" = "2 MB is free to this user under $SPACE (its free space, or what is left of the user's quota there when that is less), and it needs 3 MB there: a share (the host file's testTmpMB, 1 MB) for each of the 1 file(s) running, one for it and one kept for the belt" ] \
  || no "share_noroom $T 1, with 2,048 KB of quota left, gave another reason: $why"
# The same quota, no file running: 2 shares (2 MB) fit in it.
share_noroom "$T" 0 > /dev/null && no "share_noroom $T 0 found no room with 2,048 KB of quota left and 2 MB needed"
# A quota with more left than the space has free: the space's free blocks stand.
share_quota() { echo $((df * 4)); }
f=$(share_free "$T"); [ $((f - df)) -le 1024 ] && [ $((df - f)) -le 1024 ] || no "share_free $T gave $f KB with a quota of $((df * 4)) KB left and $df KB free in the space"
# No quota (share_quota fails): the space's free blocks stand.
share_quota() { return 1; }
f=$(share_free "$T"); [ $((f - df)) -le 1024 ] && [ $((df - f)) -le 1024 ] || no "share_free $T gave $f KB with no quota and $df KB free in the space"

# Bug #1662: the build user's own old files (caches, old repo copies) filled the user's quota on /tmp while df still
# showed free space, test files did not start, and the reason named only the free space, so nothing told the owner
# what to clear. A quota with 1 MB left, less than the space's free blocks and than the 2 MB a share needs, and no
# wait for room (SHARE_WAIT 0, the host file's testTmpWaitSec: the note was once given only after a wait): share_take
# fails for want of room (SHARE_NOROOM), and its reason names the quota and the user's biggest folders at the top of
# the space (SPACE, here a folder with two of them).
share_quota() { echo 1024; }
mkdir -p "$T/f" "$T/space/big" "$T/space/small" && head -c 2097152 /dev/zero > "$T/space/big/f" && head -c 1048576 /dev/zero > "$T/space/small/f"
SPACE=$T/space SHARE_DIR='' SHARE_WAIT=0 share_take "$T/f" && no "share_take $T/f took a share with 1,024 KB of quota left and 2 MB needed"
[ "${SHARE_NOROOM:-}" = 1 ] && [[ $SHARE_WHY == "1 MB is free to this user under $T/space "*"and it needs 2 MB there"*"; the room missing is this user's quota on $T/space (1 MB left of it), not the space ("*" MB free): the user's own files there fill it, and the user's biggest folders there are $T/space/big (2 MB), $T/space/small (1 MB)" ]] \
  || no "share_take $T/f, with 1,024 KB of quota left and $df KB free in the space, did not fail for want of room (SHARE_NOROOM '${SHARE_NOROOM:-}') naming the quota and the biggest folders: $SHARE_WHY"

# Bug #1662: a test file run with a time limit of its own (the engine's fileeach(), CONVEYOR_TEST_END) waited for
# room up to the host file's testTmpWaitSec, past that limit, so the limit stopped the wait and the file was a test
# that ran out of time, not a host problem. With 6 s left of the file's limit and a wait for room of 60 s, share_take
# gives up for want of room (SHARE_NOROOM) before the limit ends.
share_quota() { return 1; }
rm -rf "$T/f" && mkdir -p "$T/f"
e=$((EPOCHSECONDS + 6))
LIMKB=$((df * 2)) SPACE=$T/space SHARE_DIR='' SHARE_WAIT=60 CONVEYOR_TEST_END=$e share_take "$T/f" && no "share_take $T/f took a share of $((df * 2)) KB with $df KB free"
[ "${SHARE_NOROOM:-}" = 1 ] && [ "$EPOCHSECONDS" -lt "$e" ] \
  || no "share_take $T/f, with no room, a wait for room of 60 s and a file limit ending at $e, did not give up for want of room (SHARE_NOROOM '${SHARE_NOROOM:-}') before that limit (now $EPOCHSECONDS): $SHARE_WHY"

# Bug #1662: the same, while another run held a share on the space the whole time: share_take waited for that share
# to end with no look at the file's limit, so the limit stopped it and the file was a test that ran out of time, with
# no host problem logged. Another run's share (a file of the shares folder that this shell holds an flock on, as a
# running file holds its own) and 6 s left of the file's limit: share_take gives up for want of room before the limit
# ends. It runs under timeout, as without the fix it waits as long as the share is held.
mkdir -p "$T/shares" && printf '%s\t%s\t%s\n' 1024 "$T/space" "$T/other/ft" > "$T/shares/r.other" && exec {hf}>> "$T/shares/r.other" && flock "$hf" \
  || no "another run's share in $T/shares could not be made and held"
e=$((EPOCHSECONDS + 6))
got=$(LIMKB=$((df * 2)) SHARE=1 SPACE=$T/space SHARE_DIR=$T/shares SHARE_WAIT=60 CONVEYOR_TEST_END=$e timeout 15 bash -c '
  . "$1/test-share.sh"; . "$1/../conveyor/lib/slots.sh"; share_quota() { return 1; }
  share_take "$2"; echo "exit $? noroom ${SHARE_NOROOM:-none} at $EPOCHSECONDS"' _ "$HERE" "$T/f")
[[ $got =~ ^exit\ 1\ noroom\ 1\ at\ ([0-9]+)$ ]] && [ "${BASH_REMATCH[1]}" -lt "$e" ] \
  || no "share_take $T/f, with no room, another run's share held in $T/shares and a file limit ending at $e, did not give up for want of room before that limit: '$got'"
exec {hf}>&-

[ "$fails" = 0 ] && echo "ok - the room check takes the lesser of the free space and the user's quota left, a want of quota names the biggest folders, and the wait for room ends before the file's own limit"
exit $fails
