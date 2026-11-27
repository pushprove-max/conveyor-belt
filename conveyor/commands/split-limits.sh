# SPDX-License-Identifier: Apache-2.0
# `conveyor.sh split-limits [<limit>=<n | default>]...`: the four limits of the rule Split large issues (split.doneWhen,
# split.files, split.areas, split.chars in the pack, read by splitcheck(), lib/slices.sh). With no argument it prints
# each limit in force, one a line: `<limit> <n> pack` when the pack sets it, `<limit> <n> default` when the schema's
# default counts. Each argument sets a limit to a whole number of 1 or more, or takes it out of the pack (default), so
# the schema's default counts again. A limit not named, a value that is not such a number, or a pack that cannot be
# changed is refused with why, and the pack is left as it was: all the arguments are saved, or none. Sourced by conveyor.sh.
. "$HERE/lib/prompts.sh" || exit 1
. "$HERE/lib/testfiles.sh" || exit 1
shift
SPLIT_LIMITS='doneWhen files areas chars'
if [ $# = 0 ]; then
  packget split.doneWhen t1 split.files t2 split.areas t3 split.chars t4 || exit 1
  set=$(jq -r '.split // {} | keys[]' "$PACK") || exit 1
  i=1
  for l in $SPLIT_LIMITS; do
    v=t$i; i=$((i + 1))
    printf '%s %s %s\n' "$l" "${!v}" "$(grep -qx "$l" <<<"$set" && echo pack || echo default)"
  done
  exit 0
fi
f='.'
for a in "$@"; do
  l=${a%%=*} v=${a#*=}
  { [[ $a == *=* ]] && [[ " $SPLIT_LIMITS " == *" $l "* ]]; } || { echo "usage: conveyor.sh split-limits [doneWhen|files|areas|chars=<n | default>]..." >&2; exit 2; }
  if [ "$v" = default ]; then f+=" | del(.split.$l)"
  elif [[ $v =~ ^[1-9][0-9]{0,8}$ ]]; then f+=" | .split.$l = $v"
  else echo "conveyor: split-limits $a: split.$l is a whole number of 1 or more, or default; nothing changed" >&2; exit 1; fi
done
packset "$f"' | if .split == {} then del(.split) else . end'
