#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# coverage.sh, the traced run that writes the coverage map (issue 527): test-changed.sh runs, on a change to one
# function, only the cases the map lists for it, so a function the map gives a case that never ran it costs time on
# every change to it, and a case that ran it but is missing from the map is a break no card's test finds.
set -u
HERE=$(cd "$(dirname "$0")" && pwd -P); ROOT=$(dirname "$HERE")
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
AT=@
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t${AT}example.com GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t${AT}example.com
unset CONVEYOR_SHELL_TEST_CASE
bad=0; n=0
ok() { n=$((n + 1)); echo "ok $n - $1"; }
no() { n=$((n + 1)); echo "not ok $n - $1"; bad=1; }

# A scratch checkout, traced once: an engine file of two functions and two cases of the runner that each call one
# (t_two through a copy of the file in a scratch folder, in a bash of its own, as engine cases run the engine);
# dashboard.sh with two functions and a test file of two parts that each run one; a hook with a function its whole
# test file runs and one no test runs.
R=$T/r; mkdir -p "$R/.conveyor" "$R/conveyor/lib" "$R/conveyor/tests" "$R/.claude/scripts/__tests__" "$R/.claude/hooks/__tests__"
cp "$HERE/coverage.sh" "$HERE/test-changed.sh" "$R/.conveyor/"; cp "$ROOT/conveyor/lib/portable.sh" "$R/conveyor/lib/"
printf '%s\n' '{"area": "a", "file": "conveyor/lib/f.sh"}' '{"area": "a", "test": "a.test.sh"}' > "$R/.conveyor/engine-areas.json"
printf 'fone() {\n  echo one\n}\nftwo() {\n  echo two\n}\n' > "$R/conveyor/lib/f.sh"
cat > "$R/conveyor/tests/a.test.sh" <<'EOF'
t_one() {
  fone
}
t_two() {
  local d; d=$(mktemp -d) && mkdir "$d/lib" && cp conveyor/lib/f.sh "$d/lib/" && bash -c ". '$d/lib/f.sh' && ftwo"; rm -rf "$d"
}
EOF
cat > "$R/conveyor/conveyor.test.sh" <<'EOF'
cd "$(dirname "$0")/.." || exit 1
. conveyor/lib/f.sh
for f in conveyor/tests/*.test.sh; do . "$f"; done
for c in ${CONVEYOR_SHELL_TEST_CASE//,/ }; do "t_$c" || exit 1; done
EOF
printf 'dpa() {\n  echo a\n}\ndpb() {\n  echo b\n}\n"$@"\n' > "$R/.claude/scripts/dashboard.sh"
cat > "$R/.claude/scripts/__tests__/dashboard.test.sh" <<'EOF'
# Its parts, as CONVEYOR_SHELL_TEST_CASE names them.
D=$(dirname "$0")/../dashboard.sh
on() { [[ " ${CONVEYOR_SHELL_TEST_CASE:-pa pb} " == *" $1 "* ]]; }
started() { wait "$!"; }
( if on pa; then bash "$D" dpa; fi
) & started pa
( if on pb; then bash "$D" dpb; fi
) & started pb
EOF
printf 'hone() {\n  :\n}\nhtwo() {\n  :\n}\nhone\n' > "$R/.claude/hooks/h.sh"
printf 'bash "$(dirname "$0")/../h.sh"\n' > "$R/.claude/hooks/__tests__/h.test.sh"
# A hook of five functions: a test file of two case_on cases (as dependency-addition-guard.test.sh), one that selects
# its checks by their text through lib/case-filter.sh (as bash-guardrails.test.sh; a label with a comma and with an
# expansion at its start, and one with an expansion at its end, as `($SEAT)`: that one was mapped whole), and one of a check whose label no text selects (the file holds it only in a comment).
printf 'gone() {\n  :\n}\ngtwo() {\n  :\n}\ngthree() {\n  :\n}\ngfour() {\n  :\n}\ngfive() {\n  :\n}\n"$@"\n' > "$R/.claude/hooks/g.sh"
cat > "$R/.claude/hooks/__tests__/g.test.sh" <<'EOF'
# CONVEYOR_SHELL_TEST_CASE=<case>[,<case>] runs only those cases.
CASES=" ga gb "
case_on() { [ -z "${CONVEYOR_SHELL_TEST_CASE:-}" ] || [[ ",$CONVEYOR_SHELL_TEST_CASE," == *",$1,"* ]]; }
if case_on ga; then bash "$(dirname "$0")/../g.sh" gone; fi
if case_on gb; then bash "$(dirname "$0")/../g.sh" gtwo; fi
EOF
mkdir -p "$R/.claude/hooks/__tests__/lib"; cp "$ROOT/.claude/hooks/__tests__/lib/case-filter.sh" "$R/.claude/hooks/__tests__/lib/"
for k in k m; do printf '%s\n' '# CONVEYOR_SHELL_TEST_CASE=<text>[,<text>]: the checks whose text holds one.' \
  '. "$(dirname "${BASH_SOURCE[0]}")/lib/case-filter.sh"' 'cf_refuse_empty' '[ -z "${CONVEYOR_SHELL_TEST_CASE+x}" ] || cf_install ""' \
  'ON=1 G=$(dirname "$0")/../g.sh X=the V=five' 'check() { echo "ok   $1"; }' > "$R/.claude/hooks/__tests__/$k.test.sh"; done
printf '%s\n' 'check "first, $X gthree check" "$(bash "$G" gthree)"' 'check "the gfour check ($X)" "$(bash "$G" gfour)"' >>"$R/.claude/hooks/__tests__/k.test.sh"
printf '%s\n' '# gfive' 'check "g$V" "$(bash "$G" "g$V")"' >> "$R/.claude/hooks/__tests__/m.test.sh"
git -C "$R" init -q && git -C "$R" add -A && git -C "$R" commit -qm init
(cd "$R" && bash .conveyor/coverage.sh) > "$T/out" 2>&1; rc=$?
M=$R/.conveyor/coverage.jsonl
# runs <file> <function>: the units the map lists for it, `<test>:<case>` a line, sorted.
runs() { jq -r --arg f "$1" --arg n "$2" 'select(.file == $f and .fn == $n and has("test")) | "\(.test):\(.case // "")"' "$M" | sort | paste -sd ' ' -; }
[ "$rc" = 0 ] && [ -s "$M" ] && ok "coverage.sh traces the scratch checkout and writes the map" || no "coverage.sh exit $rc: $(cat "$T/out")"

# D1: each function with only its own case, a case running a copy in a bash of its own included.
[ "$(runs conveyor/lib/f.sh fone)" = conveyor/conveyor.test.sh:one ] && [ "$(runs conveyor/lib/f.sh ftwo)" = conveyor/conveyor.test.sh:two ] \
  && ok "the map lists each engine function with only the case that ran it" \
  || no "fone: '$(runs conveyor/lib/f.sh fone)', ftwo: '$(runs conveyor/lib/f.sh ftwo)': $(cat "$M")"
# The owner's order of 2026-11-14: dashboard.sh by the parts of dashboard.test.sh, and the hooks by their test files.
[ "$(runs .claude/scripts/dashboard.sh dpa)" = .claude/scripts/__tests__/dashboard.test.sh:pa ] \
  && [ "$(runs .claude/scripts/dashboard.sh dpb)" = .claude/scripts/__tests__/dashboard.test.sh:pb ] \
  && ok "the map lists each dashboard.sh function with only the part of dashboard.test.sh that ran it" \
  || no "dpa: '$(runs .claude/scripts/dashboard.sh dpa)', dpb: '$(runs .claude/scripts/dashboard.sh dpb)'"
[ "$(runs .claude/hooks/h.sh hone)" = .claude/hooks/__tests__/h.test.sh: ] && [ -z "$(runs .claude/hooks/h.sh htwo)" ] \
  && ok "a hook's function is listed with the test file that ran it whole, and one no test ran with none" \
  || no "hone: '$(runs .claude/hooks/h.sh hone)', htwo: '$(runs .claude/hooks/h.sh htwo)'"
# Bug: hook tests that CONVEYOR_SHELL_TEST_CASE runs by parts (a CASES line, or the text of a check) were traced whole,
# so a change to one hook function ran its whole test file. Each case and each check is a unit; a check its text does
# not run alone leaves its file whole, as a function only it ran would else be missing from the map.
h=.claude/hooks/__tests__
[ "$(runs .claude/hooks/g.sh gone)" = $h/g.test.sh:ga ] && [ "$(runs .claude/hooks/g.sh gtwo)" = $h/g.test.sh:gb ] \
  && [ "$(runs .claude/hooks/g.sh gthree)" = "$h/k.test.sh:gthree check" ] && [ "$(runs .claude/hooks/g.sh gfour)" = "$h/k.test.sh:the gfour check" ] \
  && [ "$(runs .claude/hooks/g.sh gfive)" = $h/m.test.sh: ] \
  && ok "the map lists each hook function with only the case or check text of its test that ran it" \
  || no "$(for x in gone gtwo gthree gfour gfive; do printf "%s: '%s' " $x "$(runs .claude/hooks/g.sh $x)"; done)"
# Each function's sum is the one test-changed.sh takes of it (so a function changed since is told), and the map says
# when it was traced, for the map check's age.
want=$(for f in conveyor/lib/f.sh .claude/scripts/dashboard.sh .claude/hooks/h.sh .claude/hooks/g.sh; do
  (cd "$R" && bash .conveyor/test-changed.sh --funcs "$f") | awk -v f="$f" -F'\t' '{ print f "\t" $1 "\t" $2 }'; done | sort)
got=$(jq -r 'select(has("sum")) | [.file, .fn, .sum] | @tsv' "$M" | sort)
[ -n "$want" ] && [ "$got" = "$want" ] && [ "$(jq -r 'select(has("traced")) | .traced' "$M" | grep -cE '^[0-9]{4}-[0-9]{2}-[0-9]{2}T')" = 1 ] \
  && ok "the map holds each function's sum as test-changed.sh --funcs gives it, and when it was traced" || no "sums: '$got', want '$want'"

# dashboard.test.sh runs the parts CONVEYOR_SHELL_TEST_CASE names: each part ends at once in fresh when left out, so
# each part's subshell starts with fresh <its name>; and a name of no part exits 2, never a run of nothing.
parts=$(sed -n 's/^) & started \([a-z0-9]*\)$/\1/p' "$ROOT/.claude/scripts/__tests__/dashboard.test.sh" | sort)
fresh=$(sed -n 's/^( fresh \([a-z0-9]*\).*/\1/p' "$ROOT/.claude/scripts/__tests__/dashboard.test.sh" | sort)
[ -n "$parts" ] && [ "$parts" = "$fresh" ] && ok "each part of dashboard.test.sh starts with fresh <its name>" || no "parts '$parts', fresh '$fresh'"
(cd "$ROOT" && CONVEYOR_SHELL_TEST_CASE=nosuch bash .claude/scripts/__tests__/dashboard.test.sh) > "$T/dash" 2>&1
[ $? = 2 ] && grep -q 'unknown part nosuch' "$T/dash" && ok "dashboard.test.sh refuses a part it does not have" || no "unknown part: $(cat "$T/dash")"
exit $bad
