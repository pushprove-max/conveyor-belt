#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# This project's full test suite (.conveyor/test-full.sh): the order it starts its files in. Bug: in parallel mode
# the files started in the suite's list order, so a heavy file that started late ran alone at the end while the other
# slots sat idle. In parallel mode it starts them longest first by the suite record (CONVEYOR_SUITE_RECORD), files
# with no time there before every timed file; serial mode keeps the list order.
set -u
HERE=$(cd "$(dirname "$0")" && pwd -P)
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
AT=@
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t${AT}example.com GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t${AT}example.com
fails=0
no() { echo "not ok - $1"; fails=1; }

# A scratch repo with the real script and four stub files, t/a to t/d in the suite's list order, each noting its name
# when it starts. The record's newest run times a 1 s, b 50 s and c 10 s; d has no time. An older run before it (a at
# 99 s, d at 5 s) and a line that is no JSON show that only the newest run counts, for a file it times and for one it
# does not (bug: a merge of all runs gave d the older 5 s, so it started third), and a bad line is passed over.
R=$T/r; mkdir -p "$R/.conveyor" "$R/t"
cp "$HERE/test-full.sh" "$HERE/test-share.sh" "$R/.conveyor/"
for f in a b c d; do printf '%s\n' "echo $f >> \"\$(dirname \"\$0\")/../ran\"" > "$R/t/$f.test.sh"; done
echo ran > "$R/.gitignore"
git -C "$R" init -q && git -C "$R" add -A && git -C "$R" commit -qm init
{ echo '{"time": "2026-11-01T00:00:00Z", "how": "release", "sha": "", "files": {"t/a.test.sh": {"result": "ok", "sec": 99, "cpu": 99}, "t/d.test.sh": {"result": "ok", "sec": 5, "cpu": 5}}}'
  echo 'not json'
  echo '{"time": "2026-11-02T00:00:00Z", "how": "release", "sha": "", "files": {"t/a.test.sh": {"result": "ok", "sec": 1, "cpu": 1},
    "t/b.test.sh": {"result": "ok", "sec": 50, "cpu": 50}, "t/c.test.sh": {"result": "ok", "sec": 10, "cpu": 10}}}' | tr -d '\n'; echo
} > "$T/suiteruns.jsonl"
printf '%s\n' t/a.test.sh t/b.test.sh t/c.test.sh > "$T/three"
# Ties: a and b have no time, c and d the same time.
echo '{"time": "2026-11-02T00:00:00Z", "how": "release", "sha": "", "files": {"t/c.test.sh": {"result": "ok", "sec": 5, "cpu": 5}, "t/d.test.sh": {"result": "ok", "sec": 5, "cpu": 5}}}' > "$T/ties.jsonl"

# The suite on a pool of one slot, so its files start one at a time; <mode> [<list> [<record>]]: the files in the
# order they ran.
order() {
  rm -f "$R/ran"
  (cd "$R" && unset CONVEYOR_TEST_SLOT CONVEYOR_CARD CONVEYOR_TEST_WHOLE CONVEYOR_TEST_LOG && XDG_CONFIG_HOME=$T/config \
    CONVEYOR_TEST_POOL=1:$T/pool CONVEYOR_TEST_SLOTS=$HERE/../conveyor/lib/slots.sh CONVEYOR_SUITE_RECORD=${3:-$T/suiteruns.jsonl} \
    CONVEYOR_SUITE_MODE=$1 CONVEYOR_SUITE_FILES=${2:-} timeout 60 bash .conveyor/test-full.sh) > "$T/out" 2>&1 || no "the $1 suite did not pass: $(cat "$T/out")"
  paste -sd' ' "$R/ran" 2>/dev/null
}
mkdir "$T/config"
# Three timed files 1, 50 and 10 in list order: longest first. A list of some files (a reused run's) orders them the same.
got=$(order parallel "$T/three"); [ "$got" = "b c a" ] || no "the three timed files did not start longest first (b c a): $got"
# A fourth file with no recorded time starts before every timed one.
got=$(order parallel); [ "$got" = "d b c a" ] || no "the file with no recorded time did not start first (d b c a): $got"
# Files with the same time, and files with no time, keep the list order among them (a sort that reversed ties gave b a d c).
got=$(order parallel '' "$T/ties.jsonl"); [ "$got" = "a b c d" ] || no "tied files did not keep the list order (a b c d): $got"
# No record: every file keeps the list order.
got=$(order parallel '' "$T/none.jsonl"); [ "$got" = "a b c d" ] || no "with no record the files did not keep the list order (a b c d): $got"
# Serial mode keeps the list order, with the same record.
got=$(order serial); [ "$got" = "a b c d" ] || no "the serial suite did not run the files in list order (a b c d): $got"
exit $fails
