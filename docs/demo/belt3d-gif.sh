#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# belt3d-gif.sh <belt3d.mp4> <belt3d.json> <out.gif> <terms file> -- makes the README's Belt 3D GIF, docs/belt-3d.gif,
# from the clip capture-board.js records (make.sh runs it): every frame of the clip, none dropped, played 25 a second
# (a delay of 4/100 s each, which every browser keeps; a clip of 30 frames a second plays 6/5 as long), at most 800 px
# wide, one palette made for the whole clip, no dithering, looping forever, under 8 MB (GitHub shows a README image
# under 10 MB). Before out.gif is written, two checks read the GIF's frames with tesseract OCR:
# - the clicked card's details: each frame while they are open (belt3d.json: open to close, the clip's seconds) shows
#   a step's time, a review round and its cost, and a frame a second after they close shows no cost;
# - privacy: the text of every 25th frame (one a second), and of those, has no hit of the privacy check
#   (conveyor/privacy/check.sh) with the terms list.
# Any failure, a frame whose delay is not 4/100 s (but the last), or a GIF of 8 MB or more exits 1, says why (the
# GIF's size), and writes nothing: nothing lowers the frame rate to fit. Needs ffmpeg, gifsicle, tesseract and jq.
set -euo pipefail
[ $# = 4 ] || { echo "usage: belt3d-gif.sh <belt3d.mp4> <belt3d.json> <out.gif> <terms file>" >&2; exit 2; }
clip=$1 marks=$2 out=$3 terms=$4
ROOT=$(cd "$(dirname "$0")/../.." && pwd -P)
MAX_BYTES=$((8 * 1024 * 1024))
die() { echo "belt3d-gif.sh: $*" >&2; exit 1; }
[ -s "$clip" ] || die "no clip at $clip"
open=$(jq -er '.open | numbers' "$marks" 2>/dev/null) && shut=$(jq -er '.close | numbers' "$marks" 2>/dev/null) \
  || die "$marks does not say when the details open and close"
# The details must be open long enough to read: at least a second and a half.
awk -v a="$open" -v b="$shut" 'BEGIN { exit !(b - a >= 1.5) }' || die "the details are open from $open s to $shut s: under 1.5 s"

B=$(mktemp -d "${TMPDIR:-/tmp}/conveyor-belt3d.XXXXXX")
trap 'rm -rf "$B"' EXIT
# Frame n of the clip is shown at n/25 s: the clip's seconds (belt3d.json) are the GIF's times rate/25.
rate=$(ffprobe -v error -select_streams v:0 -show_entries stream=r_frame_rate -of csv=p=0 "$clip")
[[ $rate =~ ^[0-9]+(/[0-9]+)?$ ]] || die "$clip has no frame rate"
stretch=$(awk -v r="$rate" 'BEGIN { split(r, a, "/"); print a[1] / (a[2] ? a[2] : 1) / 25 }')
open=$(awk -v a="$open" -v k="$stretch" 'BEGIN { print a * k }') shut=$(awk -v b="$shut" -v k="$stretch" 'BEGIN { print b * k }')
EACH="setpts=N/25/TB,scale='min(800,iw)':-2:flags=lanczos"
ffmpeg -loglevel error -y -i "$clip" -vf "$EACH,palettegen=stats_mode=full" "$B/palette.png"
ffmpeg -loglevel error -y -i "$clip" -i "$B/palette.png" \
  -lavfi "[0:v]${EACH}[v];[v][1:v]paletteuse=dither=none:diff_mode=rectangle" -r 25 -loop 0 "$B/raw.gif"
gifsicle -O3 --loopcount=forever "$B/raw.gif" -o "$B/out.gif"
size=$(wc -c < "$B/out.gif")
[ "$size" -lt "$MAX_BYTES" ] || die "the GIF is $size bytes, 8 MB ($MAX_BYTES bytes) or more"
# The info is read whole first: with pipefail, grep -q stopping at the line it found ended gifsicle by SIGPIPE, and a
# GIF that loops was refused.
info=$(gifsicle --info "$B/out.gif")
grep -q 'loop forever' <<<"$info" || die "the GIF does not loop"
# Each frame shown 4/100 s, the last as it may: gifsicle joins frames that do not change into one of a longer delay.
# A frame with no delay in the info has none (0 s).
read -r frames off < <(awk '/^  \+ image #/ { n++; d[n] = "none" } match($0, /delay [0-9.]+s/) { d[n] = substr($0, RSTART + 6, RLENGTH - 6) }
  END { for (i = 1; i < n; i++) if (d[i] != "0.04s") bad++; print n + 0, bad + 0 }' <<<"$info")
[ "$frames" -ge 2 ] && [ "$off" = 0 ] || die "$off of its $frames frames are not shown 4/100 s each"

# Each frame OCR reads is drawn twice the size, in grey (a PGM: a PNG of that size costs more to write than to read).
ocr() { tesseract "$1" stdout 2>/dev/null | tr '\n' ' '; echo; }
BIG='scale=iw*2:-1:flags=lanczos,format=gray'
# The details: two frames a second while they are open (a quarter second in from each end, as the panel slides), then
# one a second after they close, in the GIF's seconds. The GIF is read at a steady 10 frames a second and cut by time.
mkdir -p "$B/open" "$B/after"
ffmpeg -loglevel error -y -i "$B/out.gif" -vf "fps=10,trim=start=$(awk -v a="$open" 'BEGIN { print a + 0.25 }'):end=$(awk -v b="$shut" 'BEGIN { print b - 0.25 }'),fps=2,$BIG" "$B/open/%04d.pgm"
ffmpeg -loglevel error -y -i "$B/out.gif" -vf "fps=10,trim=start=$(awk -v b="$shut" 'BEGIN { print b + 1 }'),$BIG" -frames:v 1 "$B/after/0001.pgm"
# What the details say, as OCR reads it (it reads a small "so" as "$0", a 1 as I): a step's time ("3 min"), a review
# round ("Round 1") and the cost ("Cost so far $2.31"). The round and the cost are the details' alone (the pointer's
# tooltip has a time, the header strip step names): a frame that shows them shows the details. One time is enough:
# OCR of a whole frame drops one of the details' lines now and then (the "1 min" of a step).
COST='Cost .{0,8}\$[0-9]'
n=0
for f in "$B"/open/*.pgm; do
  [ -e "$f" ] || break
  n=$((n + 1)); t=$(ocr "$f"); printf '%s\n' "$t" >> "$B/ocr.txt"
  for w in '1:steps:[0-9I] ?min' '1:review rounds:Round [0-9]' "1:cost:$COST"; do # <times it is read>:<what>:<pattern>
    k=${w%%:*} w=${w#*:}
    [ "$(grep -oE -- "${w#*:}" <<<"$t" | wc -l)" -ge "$k" ] || die "a frame while the details are open (from $open s to $shut s) does not show the card's ${w%%:*}"
  done
done
[ "$n" -ge 2 ] || die "no frames while the details are open, from $open s to $shut s"
[ -e "$B/after/0001.pgm" ] || die "no frame a second after the details close at $shut s"
t=$(ocr "$B/after/0001.pgm"); printf '%s\n' "$t" >> "$B/ocr.txt"
! grep -qE -- "$COST" <<<"$t" || die "the details still show a second after they close at $shut s"

# Privacy: P4 cannot read pixels, so the text of one frame a second is read and checked before anything is written.
mkdir -p "$B/frames"
ffmpeg -loglevel error -y -i "$B/out.gif" -vf "select=not(mod(n\,25)),$BIG" -vsync vfr "$B/frames/%04d.pgm"
for f in "$B"/frames/*.pgm; do ocr "$f" >> "$B/ocr.txt"; done
if ! "$ROOT/conveyor/privacy/check.sh" --terms "$terms" "$B/ocr.txt" > "$B/hits.txt"; then
  echo "belt3d-gif.sh: the privacy check found text it must not publish in the Belt 3D frames (OCR text line: kind):" >&2
  sed "s|^$B/ocr.txt:|line |" "$B/hits.txt" >&2
  exit 1
fi
cp "$B/out.gif" "$out"
echo "belt3d-gif.sh: wrote $out ($(wc -c < "$out") bytes, $frames frames at 25 a second, looping); the details shown in $n frames; privacy: no hit"
