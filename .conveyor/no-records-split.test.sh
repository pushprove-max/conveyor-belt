#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# No engine code splits a whole records file in jq (no-records-split.sh). Bugs it catches: a reader that parses the
# card records as one jq string (recs piped to jq -Rs and split, or adopted()'s old --rawfile of recs split on a later
# line, which ran for minutes under the records' lock and stopped the belt) is let through; or a reader that reads a
# line at a time, or splits a text that is not the records, is refused.
set -u
ROOT=$(cd "$(dirname "$0")/.." && pwd -P)
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
chk() { bash "$ROOT/.conveyor/no-records-split.sh" "$@"; }
# recs piped to jq -Rs and split with splits("\n").
printf '%s\n' 'landed() { recs | jq -Rs '"'"'[splits("\n") | fromjson? | select(.step == "landed")]'"'"'; }' > "$T/piped.sh"
out=$(chk "$T/piped.sh" 2>&1) && { echo "not ok - recs piped to jq -Rs and split was let through: $(cat "$T/piped.sh")"; exit 1; }
grep -q "piped.sh:1:" <<<"$out" || { echo "not ok - the refusal of $T/piped.sh does not name its file and line: $out"; exit 1; }
# adopted()'s old shape: --rawfile of recs, the split two lines below, in one command.
printf '%s\n' 'adopted() {' '  jq -c --argjson c "$1" --rawfile r <([[ $1 == *'"'"'"order":[]'"'"'* ]] || recs 2>/dev/null) '"'"'. as $o' \
  '    | map(.number) as $open' '    | [$r | splits("\n") | fromjson? | objects] as $l | $c'"'"' <<<"$2"' '}' > "$T/rawfile.sh"
out=$(chk "$T/rawfile.sh" 2>&1) && { echo "not ok - a --rawfile of recs split on a later line was let through: $(cat "$T/rawfile.sh")"; exit 1; }
grep -q "rawfile.sh:2:" <<<"$out" || { echo "not ok - the refusal of $T/rawfile.sh does not name the command's first line: $out"; exit 1; }
# The same split in its other forms, one a line, each refused by its line: -R and -s apart, blanks inside splits( ),
# a pipe that ends the line, --slurp with the filter in double quotes, --arg of the records' text with jq's / "\n", and
# -s -R across a backslash with the records as its input. Bug it catches: a form the check does not read lets the
# belt-stopping jq back in under another spelling.
printf '%s\n' 'a() { recs | jq -R -s '"'"'[splits("\n")]'"'"'; }' 'b() { recs | jq -Rs '"'"'splits( "\n" )'"'"'; }' \
  'c() { recs |' '  jq -Rs '"'"'[splits("\n")]'"'"'; }' 'd() { olds 2>/dev/null | jq --slurp -cR "[split(\"\\n\")]"; }' \
  'e() { jq -n --arg r "$(recs)" '"'"'$r / "\n"'"'"'; }' 'f() { jq -s \' '  -R '"'"'[splits("\n")]'"'"' < <(recs); }' > "$T/forms.sh"
out=$(chk "$T/forms.sh" 2>&1)
for l in 1 2 3 5 6 7; do
  grep -q "forms.sh:$l: " <<<"$out" || { echo "not ok - line $l of this file was let through: $(cat "$T/forms.sh") -> $out"; exit 1; }
done
# The project's checks (test-changed.sh --checks, the pack's test.checkCommand) run it: an engine file that splits the
# records fails them. It runs test-changed.sh in a small repo: no direct call shows that the checks start this script.
R=$T/r; mkdir -p "$R/.conveyor" "$R/conveyor/lib"
cp "$ROOT/.conveyor/test-changed.sh" "$ROOT/.conveyor/test-share.sh" "$ROOT/.conveyor/lint-shell.sh" "$ROOT/.conveyor/no-records-split.sh" "$R/.conveyor/"
: > "$R/.conveyor/test-lint.sh"; : > "$R/.conveyor/no-browser-tests.sh"; cp "$T/piped.sh" "$R/conveyor/lib/landed.sh"
git -C "$R" init -q && git -C "$R" add -A && git -C "$R" -c user.name=t -c user.email=t@example.com commit -qm init
out=$(cd "$R" && unset CONVEYOR_TEST_LOG CONVEYOR_TEST_RERUN && bash .conveyor/test-changed.sh --checks 2>&1)
grep -q "conveyor/lib/landed.sh:1: " <<<"$out" || { echo "not ok - the project's checks did not refuse conveyor/lib/landed.sh, which splits recs: $out"; exit 1; }
# Not refused: the records read a line at a time, and a --rawfile of git's output split (its commits, not the records).
printf '%s\n' 'a() { recs | jq -cR '"'"'fromjson? | .issue'"'"'; } # the records'"'"' lines' \
  'b() { jq -n --rawfile in <(git rev-list HEAD) '"'"'$in | split("\n")'"'"' < "$STATE"; }' > "$T/lines.sh"
out=$(chk "$T/lines.sh" 2>&1) || { echo "not ok - a line-at-a-time read, or a split of git's output, was refused: $(cat "$T/lines.sh") -> $out"; exit 1; }
out=$(chk 2>&1) || { echo "not ok - the engine itself splits a whole records file in jq: $out"; exit 1; }
echo "ok - no whole records split in jq"
