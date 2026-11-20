# SPDX-License-Identifier: Apache-2.0
# `conveyor.sh pick --dry --issues <file> --state <dir>`: the issue the loop would pick, from the files given, with
# nothing written (drypick(), lib/pick.sh). `conveyor.sh pick replay judge <model> [<effort>] [--last <n>]
# [--estimate]`: the judge replay study (replay(), lib/replay.sh), which calls the judge as a review does.
# `conveyor.sh pick effort <builder|reviewer|judge> <min> <max> | pick effort <seat> clear`: the effort range of one
# seat of the rule Pick settings, saved in main's pack as models.effort.<seat> (packset(), lib/testfiles.sh), from
# the Board's Rules tab (Pick settings), or taken off, so the seat takes each effort its model's CLI takes. A min that
# comes after its max, in the order the schema lists the efforts, is refused with why, and the pack is left as it
# was. Sourced by conveyor.sh.
if [ "${2:-}" = effort ]; then
  . "$HERE/lib/prompts.sh" || exit 1
  . "$HERE/lib/pick.sh" || exit 1
  . "$HERE/lib/testfiles.sh" || exit 1
  . "$HERE/lib/run.sh" || exit 1
  . "$HERE/lib/machine.sh" || exit 1
  . "$HERE/lib/install.sh" || exit 1
  set -- "${@:3}"
  effs=$(jq -r '.properties.models.properties.effort.properties.builder.properties.min.enum | join(" ")' "$SCHEMA") && [ -n "$effs" ] || exit 1
  if [ $# = 2 ] && [ "$2" = clear ] && [[ $1 =~ ^(builder|reviewer|judge)$ ]]; then
    packset --arg s "$1" 'if .models.effort[$s] == null then . else del(.models.effort[$s]) | if .models.effort == {} then del(.models.effort) else . end end'; exit
  fi
  [ $# = 3 ] && [[ $1 =~ ^(builder|reviewer|judge)$ ]] && [[ " $effs " == *" $2 "* ]] && [[ " $effs " == *" $3 "* ]] \
    || { echo "usage: conveyor.sh pick effort <builder|reviewer|judge> <min> <max> | pick effort <builder|reviewer|judge> clear (the efforts: ${effs// /, })" >&2; exit 2; }
  i=0; for x in $effs; do [ "$x" != "$2" ] || lo=$i; [ "$x" != "$3" ] || hi=$i; i=$((i + 1)); done
  [ "$lo" -le "$hi" ] || { echo "conveyor: pick effort $1: min $2 comes after max $3 (the efforts in order: ${effs// /, }); nothing changed" >&2; exit 1; }
  packset --arg s "$1" --arg mn "$2" --arg mx "$3" '.models.effort[$s] = {min: $mn, max: $mx}'; exit
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
. "$HERE/lib/run.sh" || exit 1
. "$HERE/lib/machine.sh" || exit 1
. "$HERE/lib/install.sh" || exit 1
names || exit 1
[ $# = 6 ] && [ "$2" = --dry ] && [ "$3" = --issues ] && [ "$5" = --state ] && set -- "$1" "$2" "$3" "$(cd "$CALLED" && realpath -e -- "$4")" "$5" "$(cd "$CALLED" && realpath -e -- "$6")" \
  && [ -f "$4" ] && [ -d "$6" ] || { echo "usage: conveyor.sh pick --dry --issues <file> --state <dir>" >&2; exit 2; }
drypick "$4" "$6"
