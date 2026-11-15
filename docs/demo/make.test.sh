#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# make.sh with a Claude Code clip missing: it fails naming the clip, before it records or renders anything, and never
# renders a card in the clip's place. make.sh runs from a copy, so the checkout's captures folder is never read.
set -u
T=$(mktemp -d "${TMPDIR:-/tmp}/demo-make-test.XXXXXX")
trap 'rm -rf "$T"' EXIT
fails=0
fail() { echo "FAIL: $*"; fails=$((fails + 1)); }
mkdir -p "$T/docs/demo/captures"
cp "$(dirname "$0")/make.sh" "$T/docs/demo/make.sh"

# Bug caught: with captures/foreman.mp4 missing the demo is rendered with a card saying the clip is not recorded yet,
# or make.sh fails without naming the clip to record.
echo clip > "$T/docs/demo/captures/beat9.mp4"
out=$(bash "$T/docs/demo/make.sh" --terms /dev/null 2>&1); rc=$?
[ "$rc" = 1 ] || fail "make.sh with foreman.mp4 missing exited $rc, not 1: $out"
grep -qF 'captures/foreman.mp4 is missing' <<<"$out" || fail "make.sh did not name captures/foreman.mp4: $out"
! grep -qF 'beat9.mp4' <<<"$out" || fail "make.sh named beat9.mp4, which is there: $out"
! grep -qE 'recording|capturing|rendering' <<<"$out" || fail "make.sh went on with the clip missing: $out"

[ "$fails" = 0 ] && echo "make.test.sh: ok"
[ "$fails" = 0 ]
