#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 120
# belt3d-gif.sh, the step of make.sh that makes the README's Belt 3D GIF from the clip capture-board.js records, run on
# a clip drawn here by ffmpeg in its place (no browser runs in a test): 30 frames a second, as capture-board.js films,
# a dark frame where a box moves and a card's details (its step times, a review round, its cost and one more word)
# show from 0.5 s to 2 s, and a belt3d.json that says when.
set -u
command -v ffmpeg >/dev/null && command -v gifsicle >/dev/null && command -v tesseract >/dev/null \
  || { echo "belt3d-gif.test.sh: ffmpeg, gifsicle and tesseract are needed"; exit 1; }
HERE=$(cd "$(dirname "$0")" && pwd -P)
T=$(mktemp -d "${TMPDIR:-/tmp}/belt3d-gif-test.XXXXXX")
trap 'rm -rf "$T"' EXIT
fails=0
fail() { echo "FAIL: $*"; fails=$((fails + 1)); }
# One thread a tesseract: the frames are small, and its threads cost more CPU than they save here.
export OMP_THREAD_LIMIT=1

dt() { echo "drawtext=text='$1':x=360:y=$2:fontsize=20:fontcolor=white:enable='between(t,0.5,2.0)'"; }
box() { echo "-f lavfi -i color=c=0x101522:s=640x400:d=3:r=30 -f lavfi -i color=c=0x6b7cff:s=40x40:d=3:r=30"; }
# "Fix" with no time: a Belt 3D frame as OCR read it, the line "Fix 1 min" dropped (#652). Bug caught: a GIF whose
# frames show the details refused, as OCR read one step time, not two.
# The box moves on every frame, as the belt does: frames that do not change gifsicle joins into one.
# shellcheck disable=SC2046 # box: the inputs' words
ffmpeg -loglevel error -y $(box) \
  -filter_complex "[0:v][1:v]overlay=x='20+t*100':y=350,$(dt 'Build   3 min' 110),$(dt 'Fix' 150),$(dt 'Round 1\: NO-GO (1 P1)' 200),$(dt 'Cost so far \$2.31' 250),$(dt 'zorblat' 300)" \
  -pix_fmt yuv420p "$T/clip.mp4" || { echo "FAIL: ffmpeg could not draw the clip"; exit 1; }
# Still: the box stands still from 1 s to 2 s, frames gifsicle joins into one. Noise: a clip whose GIF is over 8 MB.
# shellcheck disable=SC2046 # box: the inputs' words
ffmpeg -loglevel error -y $(box) -filter_complex "[0:v][1:v]overlay=x='20+100*(min(t,1)+max(t-2,0))':y=350" -pix_fmt yuv420p "$T/still.mp4" \
  && ffmpeg -loglevel error -y -f lavfi -i "nullsrc=s=800x600:d=0.5:r=30,geq=lum='random(1)*255':cb=128:cr=128" -c:v rawvideo -pix_fmt gray "$T/noise.nut" \
  || { echo "FAIL: ffmpeg could not draw the clips"; exit 1; }
echo '{"open":0.5,"close":2.0}' > "$T/open.json"
# The details are marked open after the clip's frames stop showing them: the GIF would show a click that opens nothing.
echo '{"open":1.5,"close":3.0}' > "$T/late.json"
echo zorblat > "$T/terms"

# gifsicle --info as for a GIF of many frames: its info goes on long past the "loop forever" line. Bug caught (#652): with
# pipefail, grep -q ended gifsicle by SIGPIPE once it found the line, and a GIF that loops was refused.
mkdir -p "$T/bin"
printf '#!/usr/bin/env bash\n"%s" "$@" || exit\n[ "$1" != --info ] || yes "    local color table [256]" | head -c 1048576\n' "$(command -v gifsicle)" > "$T/bin/gifsicle"
chmod +x "$T/bin/gifsicle"

# D1. Bugs caught: no GIF, a GIF that plays once and stops, one of 8 MB or more, or frames the privacy check never read.
# #653: a GIF that drops frames or plays them slower than 25 a second (it played 10 a second, and choppy): each of the
# clip's 90 frames is in it, every delay but the last 4/100 s.
out=$(PATH="$T/bin:$PATH" bash "$HERE/belt3d-gif.sh" "$T/clip.mp4" "$T/open.json" "$T/ok.gif" /dev/null 2>&1); rc=$?
[ "$rc" = 0 ] && [ -s "$T/ok.gif" ] || fail "a clip that shows the details made no GIF (exit $rc): $out"
info=$(gifsicle --info "$T/ok.gif" 2>/dev/null)
grep -q 'loop forever' <<<"$info" || fail "the GIF does not loop forever"
[ "$(grep -c '^  + image' <<<"$info")" = 90 ] || fail "the GIF has not the clip's 90 frames: $(grep -c '^  + image' <<<"$info")"
[ "$(grep -o 'delay [0-9.]*s' <<<"$info" | sed '$d' | grep -vc '^delay 0.04s$')" = 0 ] && [ "$(grep -c 'delay 0.04s' <<<"$info")" -ge 89 ] \
  || fail "a frame of the GIF is not shown 4/100 s: $(grep -o 'delay [0-9.]*s' <<<"$info" | sort | uniq -c | tr -s ' \n' ' ')"
[ "$(wc -c < "$T/ok.gif" 2>/dev/null || echo 0)" -lt $((8 * 1024 * 1024)) ] || fail "the GIF is 8 MB or more"
grep -q 'privacy: no hit' <<<"$out" || fail "the privacy check did not run on the frames: $out"

# D1. Bug caught: a GIF whose frames gifsicle joined (a still stretch shown as one frame of a long delay) is written.
out=$(bash "$HERE/belt3d-gif.sh" "$T/still.mp4" "$T/open.json" "$T/still.gif" /dev/null 2>&1); rc=$?
[ "$rc" = 1 ] && [ ! -e "$T/still.gif" ] || fail "a GIF with frames not shown 4/100 s was written (exit $rc): $out"
grep -qF 'not shown 4/100 s each' <<<"$out" || fail "the frames' delays were not reported: $out"

# D1. Bug caught: a GIF of 8 MB or more is written, or made to fit by fewer frames: it fails, with its size.
out=$(bash "$HERE/belt3d-gif.sh" "$T/noise.nut" "$T/open.json" "$T/big.gif" /dev/null 2>&1); rc=$?
[ "$rc" = 1 ] && [ ! -e "$T/big.gif" ] || fail "a GIF of 8 MB or more was written (exit $rc): $out"
grep -qE 'the GIF is [0-9]+ bytes, 8 MB' <<<"$out" || fail "the size was not reported: $out"

# D1. Bug caught: a private word in the frames is published: the privacy check reads one frame a second with the terms.
out=$(bash "$HERE/belt3d-gif.sh" "$T/clip.mp4" "$T/open.json" "$T/private.gif" "$T/terms" 2>&1); rc=$?
[ "$rc" = 1 ] && [ ! -e "$T/private.gif" ] || fail "a private word in the frames still made the GIF (exit $rc): $out"
grep -qF 'the privacy check found' <<<"$out" || fail "the privacy hit was not reported: $out"

# D4. Bug caught: the click opens no details, or they close before belt3d.json says: the frames from the click to
# the close must show the card's steps, review rounds and cost.
out=$(bash "$HERE/belt3d-gif.sh" "$T/clip.mp4" "$T/late.json" "$T/late.gif" /dev/null 2>&1); rc=$?
[ "$rc" = 1 ] && [ ! -e "$T/late.gif" ] || fail "frames with no details while they should be open still made the GIF (exit $rc): $out"
grep -qF 'does not show the card' <<<"$out" || fail "the missing details were not reported: $out"

[ "$fails" = 0 ] && echo "belt3d-gif.test.sh: ok"
[ "$fails" = 0 ]
