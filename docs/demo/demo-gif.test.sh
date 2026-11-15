#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# The README's committed demo, docs/demo.gif: its /units and Foreman beats are the Claude Code clips record-cli.sh
# recorded, not a card in their place, and its end card shows the README's two install lines. Frames from the middle
# of each beat (index.html: /units from 62 s to 71 s, the Foreman from 71 s to 85 s, the end card from 85 s) are read
# by tesseract OCR.
set -u
command -v ffmpeg >/dev/null && command -v tesseract >/dev/null || { echo "demo-gif.test.sh: ffmpeg and tesseract are needed"; exit 1; }
HERE=$(cd "$(dirname "$0")" && pwd -P)
GIF=$HERE/../demo.gif
T=$(mktemp -d "${TMPDIR:-/tmp}/demo-gif-test.XXXXXX")
trap 'rm -rf "$T"' EXIT
fails=0
fail() { echo "FAIL: $*"; fails=$((fails + 1)); }
export OMP_THREAD_LIMIT=1

# beat <name> <second> ...: the GIF's frames at those seconds, twice as wide (as make.sh reads them), as text.
beat() {
  local name=$1 sel='' s; shift
  for s in "$@"; do sel+="${sel:+ + }eq(n\\,$((s * 10)))"; done
  mkdir -p "$T/$name"
  ffmpeg -loglevel error -y -i "$GIF" -vf "fps=10,select='$sel',scale=iw*2:-1:flags=lanczos" -vsync vfr "$T/$name/%02d.png" \
    || { fail "ffmpeg could not read the $name frames of docs/demo.gif"; return; }
  for f in "$T/$name"/*.png; do tesseract "$f" stdout 2>/dev/null; done > "$T/$name.txt"
}
beat units 64 67 70
beat foreman 76 80 84
beat end 87 88 89

# Bug caught: the end card shows only /plugin install, which fails until the marketplace is added.
for cmd in '/plugin marketplace add pushprove-max/conveyor-belt' '/plugin install conveyor-belt@conveyor-belt'; do
  grep -qF "$cmd" "$T/end.txt" || fail "the end card shows no \"$cmd\": $(head -c 400 "$T/end.txt")"
done

# Bug caught (#652): the demo built with a placeholder card ("This clip is recorded ...") in place of the Claude Code
# clips, or the clips missing from the beats: /units shows the CONVEYOR pane, the Foreman asks to retry #44.
grep -qF 'CONVEYOR' "$T/units.txt" || fail "the /units beat shows no CONVEYOR pane: $(head -c 400 "$T/units.txt")"
grep -qF 'Retry #44' "$T/foreman.txt" || fail "the Foreman beat shows no \"Retry #44\": $(head -c 400 "$T/foreman.txt")"
! cat "$T/units.txt" "$T/foreman.txt" | grep -qiF 'This clip is recorded' || fail "a beat shows the placeholder card \"This clip is recorded\""

[ "$fails" = 0 ] && echo "demo-gif.test.sh: ok"
[ "$fails" = 0 ]
