# SPDX-License-Identifier: Apache-2.0
# `conveyor.sh wording adversarial|review`: the wording /conveyor-belt:review gives Codex, for the project it is called
# in. It is the plugin's rules/review.md, or the project's own file when its pack names one (review.wording, from the
# checkout's root): the section of the kind asked (`# adversarial` or `# review`), then the `# every pass` section.
# Exit 2, naming what is wrong, when the file cannot be read or either section is missing or empty: the command then
# stops rather than review with wording made up by hand. Sourced by conveyor.sh.
. "$HERE/lib/prompts.sh" || exit 1
[ $# = 2 ] && [[ $2 == adversarial || $2 == review ]] || { echo "usage: conveyor.sh wording adversarial|review" >&2; exit 2; }
f=''
# A project with no pack reads the plugin's wording; a pack that fails the check stops it, naming why.
[ ! -e "$PACK" ] || packget review.wording f || exit 2
if [ -n "$f" ]; then
  # The project's file, inside its checkout: an absolute path or one that climbs out is refused.
  [[ $f != /* && /$f/ != */../* ]] || { echo "conveyor: the pack's review.wording, $f, is not a path inside the checkout" >&2; exit 2; }
  f=$MAIN/$f
else f=$HERE/rules/review.md; fi
[ -f "$f" ] && [ -r "$f" ] || { echo "conveyor: the review wording $f cannot be read" >&2; exit 2; }
# section <name>: the lines under `# <name>` up to the next `# ` heading, blank lines at either end dropped.
section() { awk -v h="# $1" '$0 == h { on = 1; next } /^# / { on = 0 } !on { next }
  /[^[:space:]]/ { printf "%s%s\n", gap, $0; gap = ""; seen = 1; next } seen { gap = gap "\n" }' "$f"; }
a=$(section "$2") && b=$(section 'every pass') || exit 2
[ -n "$a" ] && [ -n "$b" ] || { echo "conveyor: the review wording $f has no $([ -n "$a" ] && echo "'# every pass'" || echo "'# $2'") section, or it is empty" >&2; exit 2; }
printf '%s\n\n%s\n' "$a" "$b"
