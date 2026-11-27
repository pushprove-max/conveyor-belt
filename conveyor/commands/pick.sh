# SPDX-License-Identifier: Apache-2.0
# `conveyor.sh pick --dry --issues <file> --state <dir>`: the issue the loop would pick, from the files given, with
# nothing written (drypick(), lib/pick.sh). `conveyor.sh pick replay judge <model> [<effort>] [--last <n>]
# [--estimate]`: the judge replay study (replay(), lib/replay.sh), which calls the judge as a review does.
# `conveyor.sh pick models <builder|reviewer|judge> <model>[=<min>-<max>]... | pick models <seat> clear`: the models
# the rule Pick settings may give one seat, each with its effort range (<min> or <max> left empty: no bound on that
# side), saved in main's pack as pick.<seat> (packset(), lib/testfiles.sh), from the Board's Rules tab (Pick
# settings), or taken off, so the pick may give the seat any model models.allowed lists for it, at any effort. A
# model the seat does not allow, an effort its model's program does not take (cardok(), lib/control.sh), or a min
# that comes after its max, is refused with why, and the pack is left as it was. Sourced by conveyor.sh.
if [ "${2:-}" = models ]; then
  . "$HERE/lib/prompts.sh" || exit 1
  . "$HERE/lib/control.sh" || exit 1
  . "$HERE/lib/pick.sh" || exit 1
  . "$HERE/lib/testfiles.sh" || exit 1
  . "$HERE/lib/run.sh" || exit 1
  . "$HERE/lib/machine.sh" || exit 1
  . "$HERE/lib/install.sh" || exit 1
  set -- "${@:3}"
  use="usage: conveyor.sh pick models <builder|reviewer|judge> <model>[=<min>-<max>]... | pick models <builder|reviewer|judge> clear"
  [ $# -ge 2 ] && [[ $1 =~ ^(builder|reviewer|judge)$ ]] || { echo "$use" >&2; exit 2; }
  if [ "$2" = clear ]; then
    [ $# = 2 ] || { echo "$use" >&2; exit 2; }
    packset --arg s "$1" 'if .pick[$s] == null then . else del(.pick[$s]) | if .pick == {} then del(.pick) else . end end'; exit
  fi
  s=$1; l='{}'; shift
  for x in "$@"; do
    [[ $x =~ ^([^=[:space:]]+)(=([a-z]*)-([a-z]*))?$ ]] || { echo "$use (not <model>[=<min>-<max>]: $x)" >&2; exit 2; }
    m=${BASH_REMATCH[1]} mn=${BASH_REMATCH[3]} mx=${BASH_REMATCH[4]}
    for f in - "$mn" "$mx"; do
      [ -n "$f" ] || continue
      why=$(cardok "$s" "$m" "${f#-}") || exit 1
      [ -z "$why" ] || { echo "conveyor: pick models $s: $why; nothing changed" >&2; exit 1; }
    done
    if [ -n "$mn" ] && [ -n "$mx" ] && ! jq -en --arg a "$mn" --arg b "$mx" --argjson e "$EFFORTS" '$e.opencode | index($a) <= index($b)' >/dev/null; then
      echo "conveyor: pick models $s: $m: min $mn comes after max $mx (the efforts in order: $(jq -r '.opencode | join(", ")' <<<"$EFFORTS")); nothing changed" >&2; exit 1
    fi
    l=$(jq -c --arg m "$m" --arg a "$mn" --arg b "$mx" '.[$m] = ({} + (if $a == "" then {} else {min: $a} end) + (if $b == "" then {} else {max: $b} end))' <<<"$l") || exit 1
  done
  packset --arg s "$s" --argjson l "$l" '.pick[$s] = $l'; exit
fi
if [ "${2:-}" = replay ]; then
  . "$HERE/lib/slots.sh" || exit 1
  . "$HERE/lib/prompts.sh" || exit 1
  . "$HERE/lib/control.sh" || exit 1
  . "$HERE/lib/issues.sh" || exit 1
  . "$HERE/lib/pick.sh" || exit 1
  . "$HERE/lib/session.sh" || exit 1
  . "$HERE/lib/review.sh" || exit 1
  . "$HERE/lib/replay.sh" || exit 1
  names || exit 1
  replay "${@:3}"; exit
fi
. "$HERE/lib/prompts.sh" || exit 1
. "$HERE/lib/control.sh" || exit 1
. "$HERE/lib/issues.sh" || exit 1
. "$HERE/lib/pick.sh" || exit 1
. "$HERE/lib/fulltest.sh" || exit 1 # the release limit's fix list (RELFIXJQ), read by the dry pick
. "$HERE/lib/push.sh" || exit 1 # the release hold (relheld()), read by the dry pick's release limit
. "$HERE/lib/run.sh" || exit 1
. "$HERE/lib/machine.sh" || exit 1
. "$HERE/lib/install.sh" || exit 1
names || exit 1
[ $# = 6 ] && [ "$2" = --dry ] && [ "$3" = --issues ] && [ "$5" = --state ] && set -- "$1" "$2" "$3" "$(cd "$CALLED" && realpath -e -- "$4")" "$5" "$(cd "$CALLED" && realpath -e -- "$6")" \
  && [ -f "$4" ] && [ -d "$6" ] || { echo "usage: conveyor.sh pick --dry --issues <file> --state <dir>" >&2; exit 2; }
drypick "$4" "$6"
