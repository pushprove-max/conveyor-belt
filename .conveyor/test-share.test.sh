#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# The room check of the test files' share of the temp space (.conveyor/test-share.sh share_free, share_noroom), which
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

[ "$fails" = 0 ] && echo "ok - the room check takes the lesser of the free space and the user's quota left"
exit $fails
