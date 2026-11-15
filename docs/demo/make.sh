#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# make.sh [--terms <file>] -- rebuilds the README's product demo, docs/demo.mp4 and docs/demo.gif, and its Belt 3D
# GIF, docs/belt-3d.gif, from this folder alone: the terminal beat recorded in a neutral Docker container
# (record-terminal.sh, its lines kept as captures/beat2.txt), the Board beats captured from the real Board page served from the mock timeline
# (capture-board.js, timeline.js), beat 10 (/units) from captures/beat9.mp4 and beat 11 (the Foreman) from
# captures/foreman.mp4, cut together by the HyperFrames composition (index.html). The two clips are recorded by
# record-cli.sh from a signed-in Claude Code session in a neutral container and committed; make.sh fails, naming each
# one, when one is missing. docs/belt-3d.gif is made by belt3d-gif.sh from the Belt 3D clip capture-board.js records:
# every frame played 25 a second, under 8 MB, looping, the clicked card's details read by OCR in its frames while
# open, and one frame a second through the privacy check below. Re-running make.sh is how the demo follows Board changes.
# Before any file is written into docs/, every 10th frame of the GIF is read by tesseract OCR and the text checked
# by the privacy check (conveyor/privacy/check.sh) with the terms list: --terms <file>, else the host file's terms
# (~/.config/conveyor/host.json, as the engine reads it). Any hit, no readable terms list, or a GIF of 10 MB or more
# (GitHub's limit for a README image) writes nothing.
# Needs: node 22+, npm, ffmpeg, gifsicle, tesseract, jq and Docker; the npm packages of package.json (installed here
# with npm ci when node_modules is missing).
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd -P)
ROOT=$(cd "$HERE/../.." && pwd -P)
MAX_BYTES=$((10 * 1024 * 1024))
# Beats 10 and 11, the Claude Code clips record-cli.sh records: checked first, as nothing can stand in for them.
missing=0
for clip in beat9 foreman; do
  [ -s "$HERE/captures/$clip.mp4" ] || { echo "make.sh: captures/$clip.mp4 is missing: record it with record-cli.sh" >&2; missing=1; }
done
[ "$missing" = 0 ] || exit 1

terms=''
[ "${1:-}" != --terms ] || { [ $# -ge 2 ] || { echo "usage: make.sh [--terms <file>]" >&2; exit 2; }; terms=$2; }
if [ -z "$terms" ]; then
  terms=$(jq -r '.terms // empty' "${XDG_CONFIG_HOME:-$HOME/.config}/conveyor/host.json" 2>/dev/null || true)
  # shellcheck disable=SC2088 # a literal ~/ in the host file, which the engine reads as the home
  [[ $terms != "~/"* ]] || terms=$HOME/${terms#"~/"}
fi
{ [ -n "$terms" ] && [ -r "$terms" ] && [ ! -d "$terms" ]; } || { echo "make.sh: no readable terms list: pass --terms <file>, or name one in the host file" >&2; exit 1; }
for t in node npm ffmpeg gifsicle tesseract jq docker; do
  command -v "$t" >/dev/null || { echo "make.sh: $t is not installed" >&2; exit 1; }
done
[ -d "$HERE/node_modules" ] || (cd "$HERE" && npm ci --no-audit --no-fund)
# No usage reports from the render.
export HYPERFRAMES_NO_TELEMETRY=1 DO_NOT_TRACK=1

B=$(mktemp -d "${TMPDIR:-/tmp}/conveyor-demo.XXXXXX")
trap 'rm -rf "$B"' EXIT
mkdir -p "$B/captures"
echo "make.sh: recording the terminal beat"
bash "$HERE/record-terminal.sh" "$B/captures"
echo "make.sh: capturing the Board beats"
node "$HERE/capture-board.js" "$B/captures"
cp "$HERE/captures/beat9.mp4" "$HERE/captures/foreman.mp4" "$B/captures/"
cp "$HERE/index.html" "$B/index.html"

echo "make.sh: making the Belt 3D GIF"
bash "$HERE/belt3d-gif.sh" "$B/captures/belt3d.mp4" "$B/captures/belt3d.json" "$B/belt-3d.gif" "$terms"

echo "make.sh: rendering"
"$HERE/node_modules/.bin/hyperframes" render "$B" -o "$B/demo.mp4" --quality looks --fps 30 >"$B/render.log" 2>&1 \
  || { tail -20 "$B/render.log" >&2; echo "make.sh: the render failed" >&2; exit 1; }
# The GIF: 10 frames a second, 800 px wide, one palette made for the whole film, then gifsicle's optimiser.
ffmpeg -loglevel error -y -i "$B/demo.mp4" -vf "fps=10,scale=800:-1:flags=lanczos,palettegen=max_colors=192:stats_mode=diff" "$B/palette.png"
ffmpeg -loglevel error -y -i "$B/demo.mp4" -i "$B/palette.png" \
  -lavfi "fps=10,scale=800:-1:flags=lanczos[v];[v][1:v]paletteuse=dither=bayer:bayer_scale=4:diff_mode=rectangle" -loop 0 "$B/raw.gif"
gifsicle -O3 --lossy=40 --loopcount=forever "$B/raw.gif" -o "$B/demo.gif"
size=$(wc -c < "$B/demo.gif")
[ "$size" -lt "$MAX_BYTES" ] || { echo "make.sh: the GIF is $size bytes, over GitHub's 10 MB" >&2; exit 1; }

# Privacy: P4 cannot read pixels, so the text in every 10th frame is read and checked before anything is written.
mkdir -p "$B/frames"
ffmpeg -loglevel error -y -i "$B/demo.gif" -vf "select=not(mod(n\,10)),scale=iw*2:-1:flags=lanczos" -vsync vfr "$B/frames/%04d.png"
frames=$(ffprobe -v error -count_frames -select_streams v:0 -show_entries stream=nb_read_frames -of csv=p=0 "$B/demo.gif")
checked=0
for f in "$B"/frames/*.png; do
  tesseract "$f" stdout 2>/dev/null >> "$B/ocr.txt"
  checked=$((checked + 1))
done
if ! "$ROOT/conveyor/privacy/check.sh" --terms "$terms" "$B/ocr.txt" > "$B/hits.txt"; then
  echo "make.sh: the privacy check found text it must not publish in the demo's frames (OCR text line: kind):" >&2
  sed "s|^$B/ocr.txt:|line |" "$B/hits.txt" >&2
  exit 1
fi
cp "$B/demo.mp4" "$ROOT/docs/demo.mp4"
cp "$B/demo.gif" "$ROOT/docs/demo.gif"
cp "$B/belt-3d.gif" "$ROOT/docs/belt-3d.gif"
cp "$B/captures/beat2.txt" "$HERE/captures/beat2.txt"
echo "make.sh: wrote docs/demo.mp4 ($(wc -c < "$ROOT/docs/demo.mp4") bytes) and docs/demo.gif ($size bytes, $frames frames)"
echo "make.sh: wrote docs/belt-3d.gif ($(wc -c < "$ROOT/docs/belt-3d.gif") bytes)"
echo "make.sh: privacy: $checked frames read by OCR (every 10th of $frames) and checked with the privacy check and the terms list: no hit"
