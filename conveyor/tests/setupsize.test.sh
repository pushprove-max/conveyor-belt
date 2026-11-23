#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 120
# Engine cases: setup writes the file-length limit (setupsize(), sizeself(): lib/setup.sh); the cases of the limit's first
# run (t_setupsize) are in setup.test.sh.
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"

# sizelint <what setup was asked>: the size check as the first card runs it, `conveyor.sh lint` in $S, on the pack and the
# exempt file as setup wrote them. A file over the limit that the exempt file does not name fails the case.
sizelint() {
  local out
  out=$(cd "$S" && bash "$X" lint 2>&1) || fail "conveyor.sh lint after setup $1 found a file over the limit that the exempt file does not name: $out exempt: $(cat "$S/.conveyor/size-exempt.txt" 2>&1)"
}
# Bug it catches (R302): a pathspec git refuses (':(glbo)*.sh') still wrote the size entry, since mapfile < <(git ...) reports 0.
t_setupsizebad() {
  local X out; setupdone
  out=$(cd "$S" && bash "$X" setup --fast-lane no --research-lane no --size 3 --size-files ':(glbo)*.sh' 2>&1) && fail "setup --size 3 --size-files ':(glbo)*.sh' exited 0: $out"
  ! jq -e 'any(.lint.commands[]?; .size)' "$S/.conveyor/project.json" >/dev/null && [ ! -e "$S/.conveyor/size-exempt.txt" ] || fail "setup with a pathspec git refuses wrote a size entry or the exempt file: $(jq -c .lint "$S/.conveyor/project.json") $out"
}
# Bugs it catches (R303, E1): with --size 1 --size-files '*', the exempt file was scanned empty, then grew past the limit and
# failed its own size check; and the lookup of the pack in a long file list (over a pipe's buffer) died of grep -q closing the
# pipe under pipefail, so the pack and the exempt file were left out.
t_setupsizeself() {
  local X out i; setupdone
  mkdir "$S/many"; for ((i = 0; i < 4000; i++)); do echo x > "$S/many/file-with-a-long-name-for-the-list-$i.txt"; done
  # Three more files over the limit, so the exempt file ends with more lines than the limit and has to name itself.
  for i in 1 2 3; do printf 'a\nb\n' > "$S/two$i.txt"; done
  out=$(cd "$S" && bash "$X" setup --fast-lane no --research-lane no --size 1 --size-files '*' 2>&1) || fail "setup --size 1 --size-files '*' exited non-zero: $out"
  grep -qxF .conveyor/size-exempt.txt "$S/.conveyor/size-exempt.txt" || fail "setup --size 1 --size-files '*' did not name the exempt file in itself: $(cat "$S/.conveyor/size-exempt.txt")"
  sizelint "--size 1 --size-files '*'"
}
# Bug it catches (E2): the exempt file was named in itself while it was at the limit (one line, limit 1), though it is not over it.
t_setupsizeatlimit() {
  local X out; setupdone
  printf '1\n2\n3\n' > "$S/big.txt"; git -C "$S" add big.txt
  out=$(cd "$S" && bash "$X" setup --fast-lane no --research-lane no --size 1 --size-files big.txt --size-files .conveyor/size-exempt.txt 2>&1) \
    && [ "$(cat "$S/.conveyor/size-exempt.txt")" = big.txt ] || fail "setup --size 1 with only big.txt over the limit wrote more than big.txt in the exempt file: $(cat "$S/.conveyor/size-exempt.txt") $out"
}
# Bug it catches (E3): the pack was counted before setup wrote the rest of it (test.firstSurvey, a line more), so a pack at the
# limit then was over it at the end and not exempt. The limit is the pack's lines with the size entry, less the survey line.
t_setupsizegrow() {
  local X out n; setupdone
  jq 'del(.test.firstSurvey)' "$S/.conveyor/project.json" > "$T/$CASE/p" && mv "$T/$CASE/p" "$S/.conveyor/project.json"
  n=$(jq '.lint.commands = [{files: ["x"], size: {file: 1, exempt: "x"}}] | .lint.policy = ["x"]' "$S/.conveyor/project.json" | wc -l)
  out=$(cd "$S" && bash "$X" setup --fast-lane no --research-lane no --survey no --size "$n" --size-files .conveyor/project.json 2>&1) || fail "setup --size $n exited non-zero: $out"
  [ "$(wc -l < "$S/.conveyor/project.json")" -gt "$n" ] || fail "the pack did not grow after the size entry was written, so this case proves nothing: $(wc -l < "$S/.conveyor/project.json") lines, limit $n"
  sizelint "--survey no --size $n --size-files .conveyor/project.json"
}
# Bug it catches (E6): setup stopped after it wrote the size entry (here, the fast lane could not be made), and the run after
# it found the entry there and did not name the pack and the exempt file in the exempt file, so the first lint failed on them.
t_setupsizeretry() {
  local X out call i; setupdone; lanestubs
  call=(setup --fast-lane yes --research-lane no --size 1 --size-files '*')
  # Three files over the limit, so the exempt file has more lines than the limit and has to name itself.
  for i in 1 2 3; do printf 'a\nb\n' > "$S/two$i.txt"; done
  mkdir "$S-fast-lane" && touch "$S-fast-lane/in-the-way"
  out=$(cd "$S" && bash "$X" "${call[@]}" 2>&1) && fail "setup ${call[*]} with a folder in the fast lane's place exited 0: $out"
  jq -e 'any(.lint.commands[]?; .size)' "$S/.conveyor/project.json" >/dev/null || fail "the run that stopped did not write the size entry, so this case proves nothing: $out"
  rm -r "$S-fast-lane"
  out=$(cd "$S" && bash "$X" "${call[@]}" 2>&1) || fail "setup ${call[*]} run again, with the fast lane's place free, exited non-zero: $out"
  sizelint "${call[*]:1}, run again after a run that stopped"
}
# Bug it catches (R304): an exempt file whose last line had no newline got the next name glued on ('keep.txtbig.txt').
t_setupsizenl() {
  local X out; setupdone
  printf '1\n2\n3\n4\n5\n' > "$S/big.txt"; git -C "$S" add big.txt; printf keep.txt > "$S/.conveyor/size-exempt.txt"
  out=$(cd "$S" && bash "$X" setup --fast-lane no --research-lane no --size 3 --size-files 'big.txt' 2>&1) && [ "$(cat "$S/.conveyor/size-exempt.txt")" = "$(printf 'keep.txt\nbig.txt')" ] || fail "setup --size 3 on an exempt file 'keep.txt' with no final newline did not add big.txt as its own line: $(cat "$S/.conveyor/size-exempt.txt") $out"
}
