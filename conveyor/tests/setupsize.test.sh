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
# Bug it catches (review of #1532, E2): the size entry was written after the survey issue was filed, so a pathspec git refuses
# stopped the run after the issue was filed, and the run the owner corrected filed a second one.
t_setupsizebadsurvey() {
  local X out; setupdone
  out=$(cd "$S" && bash "$X" setup --fast-lane no --research-lane no --survey yes --size 3 --size-files ':(glbo)*.sh' 2>&1) && fail "setup --survey yes --size 3 --size-files ':(glbo)*.sh' exited 0: $out"
  [ ! -e "$G/filed" ] || fail "setup filed an issue before it refused the pathspec ':(glbo)*.sh': $(cat "$G/filed") $out"
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
# The entry is now written after the lanes, so a stop there leaves no entry; the run after it writes the entry and its names.
t_setupsizeretry() {
  local X out call i; setupdone; lanestubs
  call=(setup --fast-lane yes --research-lane no --size 1 --size-files '*')
  # Three files over the limit, so the exempt file has more lines than the limit and has to name itself.
  for i in 1 2 3; do printf 'a\nb\n' > "$S/two$i.txt"; done
  mkdir "$S-fast-lane" && touch "$S-fast-lane/in-the-way"
  out=$(cd "$S" && bash "$X" "${call[@]}" 2>&1) && fail "setup ${call[*]} with a folder in the fast lane's place exited 0: $out"
  ! jq -e 'any(.lint.commands[]?; .size)' "$S/.conveyor/project.json" >/dev/null || fail "the run that stopped at the fast lane wrote the size entry, which no exemption of the pack follows: $out"
  rm -r "$S-fast-lane"
  out=$(cd "$S" && bash "$X" "${call[@]}" 2>&1) || fail "setup ${call[*]} run again, with the fast lane's place free, exited non-zero: $out"
  sizelint "${call[*]:1}, run again after a run that stopped"
}
# Bug it catches (review of #1532, 1): a setup run after setup had finished named the pack in the exempt file when the owner's own
# edit had made it grow past the limit, so the size check passed on growth it must report.
t_setupsizererun() {
  local X out n; setupdone
  out=$(cd "$S" && bash "$X" setup --fast-lane no --research-lane no --size 1000 --size-files .conveyor/project.json 2>&1) || fail "setup --size 1000 exited non-zero: $out"
  n=$(wc -l < "$S/.conveyor/project.json")
  jq --argjson n "$n" '(.lint.commands[] | select(.size).size.file) = $n' "$S/.conveyor/project.json" > "$T/$CASE/p" && mv "$T/$CASE/p" "$S/.conveyor/project.json" || fail "the limit was not set to the pack's $n lines"
  sizelint "--size 1000 --size-files .conveyor/project.json, with the limit then set to the pack's $n lines"
  jq '.worktree.setup = "true"' "$S/.conveyor/project.json" > "$T/$CASE/p" && mv "$T/$CASE/p" "$S/.conveyor/project.json" || fail "the pack was not grown"
  out=$(cd "$S" && bash "$X" lint 2>&1) && fail "the pack grew past its limit of $n lines and lint did not report it, so this case proves nothing: $out"
  out=$(cd "$S" && bash "$X" setup --fast-lane no --research-lane no 2>&1) || fail "setup run again exited non-zero: $out"
  ! grep -qxF .conveyor/project.json "$S/.conveyor/size-exempt.txt" || fail "setup run again named the pack, grown by the owner, in the exempt file: $(cat "$S/.conveyor/size-exempt.txt")"
  if out=$(cd "$S" && bash "$X" lint 2>&1); then fail "lint passed on the pack grown past its limit after setup ran again: $out"; fi
}
# Bug it catches (review of #1532, 2): setup wrote .conveyor/test-machine.sh after the first count of files over the limit, so with
# --size 1 --size-files '*' the script was over the limit and the first lint reported it.
t_setupsizemachine() {
  local X out; setupdone
  out=$(cd "$S" && bash "$X" setup --fast-lane no --research-lane no --test-machine yes --size 1 --size-files '*' 2>&1) || fail "setup --test-machine yes --size 1 --size-files '*' exited non-zero: $out"
  [ "$(wc -l < "$S/.conveyor/test-machine.sh")" -gt 1 ] || fail "setup wrote no .conveyor/test-machine.sh of more than the limit's 1 line, so this case proves nothing: $out"
  sizelint "--test-machine yes --size 1 --size-files '*'"
}
# Bug it catches (R304): an exempt file whose last line had no newline got the next name glued on ('keep.txtbig.txt').
t_setupsizenl() {
  local X out; setupdone
  printf '1\n2\n3\n4\n5\n' > "$S/big.txt"; git -C "$S" add big.txt; printf keep.txt > "$S/.conveyor/size-exempt.txt"
  out=$(cd "$S" && bash "$X" setup --fast-lane no --research-lane no --size 3 --size-files 'big.txt' 2>&1) && [ "$(cat "$S/.conveyor/size-exempt.txt")" = "$(printf 'keep.txt\nbig.txt')" ] || fail "setup --size 3 on an exempt file 'keep.txt' with no final newline did not add big.txt as its own line: $(cat "$S/.conveyor/size-exempt.txt") $out"
}
