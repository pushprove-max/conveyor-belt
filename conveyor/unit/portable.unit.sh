# SPDX-License-Identifier: Apache-2.0
# Unit cases of the portability helpers, run by unit.sh (its header says how).
# unit: conveyor/lib/portable.sh
# shellcheck source=conveyor/lib/portable.sh
. "$SRC/lib/portable.sh"

# Bug: p_bashok passes a bash older than the one asked for, so require_bash lets the engine start on macOS's bash 3.2
# and fail later on syntax it does not have; or it refuses a newer major whose minor is lower.
u_bashok() {
  local maj=${BASH_VERSINFO[0]} min=${BASH_VERSINFO[1]}
  p_bashok "$maj.$min" || fail "this bash, $maj.$min, is not read as $maj.$min or newer"
  ! p_bashok "$maj.$((min + 1))" || fail "this bash, $maj.$min, is read as $maj.$((min + 1)) or newer"
  ! p_bashok "$((maj + 1)).0" || fail "this bash, $maj.$min, is read as $((maj + 1)).0 or newer"
  p_bashok "$((maj - 1)).99" || fail "this bash, $maj.$min, is not read as $((maj - 1)).99 or newer"
}

# Bug: diffid gives the same change another id when it moved to other line numbers or another blob (the loop then
# reads a change it saw before as new), or gives a change of whitespace the same id (Python and YAML read whitespace).
u_diffid() {
  local a b c
  a=$(printf '%s\n' 'index 1111111..2222222 100644' '@@ -1 +1 @@' '-x' '+y' | diffid)
  b=$(printf '%s\n' 'index 3333333..4444444 100644' '@@ -9 +9 @@' '-x' '+y' | diffid)
  c=$(printf '%s\n' 'index 1111111..2222222 100644' '@@ -1 +1 @@' '-x' '+ y' | diffid)
  [ -n "$a" ] || fail "a diff has no id"
  [ "$a" = "$b" ] || fail "the same change at other lines and blobs has another id: $a, $b"
  [ "$a" != "$c" ] || fail "a change of whitespace has the same id: $a"
  [ -z "$(: | diffid)" ] || fail "an empty diff has an id"
}

# Bug: the engine read the CPU count with `nproc --all`, which macOS does not have, so the slots and the coverage trace
# read no count there. p_ncpu gives a positive count on either system, and the count this Linux host reports.
u_ncpu() {
  local n; n=$(p_ncpu) || fail "p_ncpu gave no count"
  [[ $n =~ ^[1-9][0-9]*$ ]] || fail "p_ncpu gave $n, not a positive count"
  if p_darwin; then [ "$n" = "$(sysctl -n hw.ncpu)" ] || fail "p_ncpu gave $n, not hw.ncpu"
  else [ "$n" = "$(nproc --all)" ] || fail "p_ncpu gave $n, not nproc --all"; fi
}
