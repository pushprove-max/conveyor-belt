#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# This project's full test suite (.conveyor/test-full.sh): a file starts only when the space this user can still
# write in its temp folder holds a share (the host file's testTmpMB) for each file running, one for it and one kept for the belt. Bug (#1238): files
# started on a /tmp with no room left, and 155 failed with "Disk quota exceeded" in no file's own fault. Two fixtures,
# run side by side: in one the space can never hold the share, and the file fails without running, with the reason;
# in the other, in parallel, the third file waits for a running one to end. Bug (#1394 R17): two runs at once each
# counted only their own files, so on a space that held 3 shares each started its second file. In a third fixture
# two runs share a slots folder, as every run on a machine does: no more than two files run at once. One of them is
# serial, a release's mode, which reads no slots: it counted no other run's files, nor did the other count its own.
# Bug (#1394): a serial run with no room failed its file at once while another run held a share that it would free.
# In a fourth fixture, the file waits for that run to end, and passes.
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
# two: the same share, two runs of two files each, started together on one slots folder: two1 parallel, two at once,
# and two2 serial. Two files take 2 then 3 shares, and a third (4) waits for one of them to end.
repo two1 a-1 b-1; repo two2 c-1 d-1
# held: a serial run with a share of 1 MB, while another run holds a share of 1 MB in its slots folder, and df (given
# on PATH, the only df the run reads) shows 1 MB free, less than the 2 shares its file needs. The other run is a
# process here: it holds its share's flock, as share_others counts only a share a process holds (slot_held), shows
# 1 GB free after 2 s, then ends.
repo held x-0
mkdir -p "$T/held.bin" "$T/held.pool/shares" && echo 1024 > "$T/held.free"
printf '#!/usr/bin/env bash\necho "Filesystem 1024-blocks Used Available Capacity Mounted on"\necho "held 0 0 $(cat %q) 0%% /held"\n' \
  "$T/held.free" > "$T/held.bin/df" && chmod +x "$T/held.bin/df"
printf '1024\t/held\t%s\n' "$T/other/f.tmp" > "$T/held.pool/shares/r.other"
flock "$T/held.pool/shares/r.other" bash -c 'touch "$1"; sleep 2; echo 1048576 > "$2"' _ "$T/held.ready" "$T/held.free" &
# Polls the process above: the run must start only once that process holds its share's flock.
i=0; while [ ! -e "$T/held.ready" ] && [ $i -lt 100 ]; do sleep 0.1; i=$((i + 1)); done
suite none 9999999 & suite wait $((free * 2 / 7)) CONVEYOR_SUITE_MODE=parallel CONVEYOR_SUITE_AT_ONCE=3 &
suite two1 $((free * 2 / 7)) "CONVEYOR_TEST_POOL=3:$T/two.pool" CONVEYOR_SUITE_MODE=parallel CONVEYOR_SUITE_AT_ONCE=2 &
suite two2 $((free * 2 / 7)) "CONVEYOR_TEST_POOL=3:$T/two.pool" CONVEYOR_SUITE_MODE=serial &
suite held 1 "PATH=$T/held.bin:$PATH" CONVEYOR_SUITE_MODE=serial & wait

[ "$(cat "$T/none.rc")" = 1 ] && grep -qxF -- '-- FAIL lib/x-0.test.sh' "$T/none.out" \
  && grep -qE "^test-full: lib/x-0\\.test\\.sh did not start: [0-9]+ MB is free to this user under $space \\(its free space, or what is left of the user's quota there when that is less\\), and it needs 19999998 MB there: a share \\(the host file's testTmpMB, 9999999 MB\\) for each of the 0 file\\(s\\) running, one for it and one kept for the belt\$" "$T/none.out" \
  || no "a file the space cannot hold did not fail with the reason (exit $(cat "$T/none.rc")): $(cat "$T/none.out")"
[ ! -e "$T/none/times/x-0.start" ] || no "a file the space cannot hold ran"
[ "$(cat "$T/wait.rc")" = 0 ] || no "the files that had room did not all pass (exit $(cat "$T/wait.rc")): $(cat "$T/wait.out")"
read -r ae < "$T/wait/times/a-1.end"; read -r bs < "$T/wait/times/b-2.start"; read -r cs < "$T/wait/times/c-0.start"
awk -v a="$ae" -v b="$bs" -v c="$cs" 'BEGIN { exit !(b < a && c >= a) }' \
  || no "the third file did not wait for a running one to end, or the second waited (a ended $ae, b started $bs, c started $cs; $free MB free): $(cat "$T/wait.out")"
[ "$(cat "$T/two1.rc")" = 0 ] && [ "$(cat "$T/two2.rc")" = 0 ] \
  || no "two runs on one slots folder did not both pass (exit $(cat "$T/two1.rc") and $(cat "$T/two2.rc")): $(cat "$T/two1.out" "$T/two2.out")"
# The most files that ran at once: at each file's start, the files started by then and not ended yet.
most=$(for f in two1/times/a-1 two1/times/b-1 two2/times/c-1 two2/times/d-1; do
  printf '%s %s\n' "$(cat "$T/$f.start" 2>/dev/null)" "$(cat "$T/$f.end" 2>/dev/null)"
done | awk '{ s[NR] = $1; e[NR] = $2 } END { for (i in s) { n = 0; for (j in s) if (s[j] <= s[i] && e[j] > s[i]) n++; if (n > m) m = n } print m + 0 }')
[ "$most" = 2 ] || no "two runs on a space that holds 3 shares ran $most files at once, not 2: a second file did not wait ($free MB free): $(cat "$T/two1.out" "$T/two2.out")"
[ "$(cat "$T/held.rc")" = 0 ] && grep -qxF -- '-- ok lib/x-0.test.sh' "$T/held.out" \
  || no "a serial run, with 1 MB free (df), a share of 1 MB and another run's share of 1 MB held until it freed 1 GB, did not wait for that run: its file did not pass (exit $(cat "$T/held.rc")): $(cat "$T/held.out")"
[ "$fails" = 0 ] && echo "ok - a file starts only with room for its share beside the files of every run, and waits for it or fails with the reason"
exit $fails
