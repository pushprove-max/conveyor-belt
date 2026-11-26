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
# The loop's test step sets these: left set, the scratch test-changed.sh runs below would select the card's files too.
unset CONVEYOR_SHELL_TEST_CASE CONVEYOR_TEST_LOG CONVEYOR_TEST_FILELIST CONVEYOR_TEST_RERUN CONVEYOR_TEST_CASES
bad=0; n=0
ok() { n=$((n + 1)); echo "ok $n - $1"; }
no() { n=$((n + 1)); echo "not ok $n - $1"; bad=1; }

# A scratch checkout, traced once: an engine file of four functions and two cases of the runner that each call one
# (t_two through a copy of the file in a scratch folder, in a bash of its own, as engine cases run the engine), and a
# third that fails, its output naming a path of this machine, and a fourth that loads the fourth function's body with
# eval and calls it with a stub of the first that it defines itself; dashboard.sh with two functions and a test file of two
# parts that each run one; a hook with a function its whole test file runs and one no test runs.
R=$T/r; mkdir -p "$R/.conveyor" "$R/conveyor/lib" "$R/conveyor/tests" "$R/.claude/scripts/__tests__" "$R/.claude/hooks/__tests__"
cp "$HERE/coverage.sh" "$HERE/test-changed.sh" "$HERE/test-share.sh" "$HERE/lint-shell.sh" "$R/.conveyor/"; cp "$ROOT/conveyor/lib/portable.sh" "$R/conveyor/lib/"
# portable.sh outside the map, so the map check of a one-file run passes (issue 1723's checks of its exit, below).
printf '%s\n' '{"outside": "conveyor/lib/portable.sh"}' '{"area": "a", "file": "conveyor/lib/f.sh"}' '{"area": "a", "test": "a.test.sh"}' > "$R/.conveyor/engine-areas.json"
printf 'fone() {\n  echo one\n}\nftwo() {\n  echo two\n}\nfbare() {\n  echo bare\n}\nfthree() {\n  echo three\n}\n' > "$R/conveyor/lib/f.sh"
# fbare: run by t_one in its own bash and by t_two only in a bash started with an emptied environment (env -i), as
# apiroute.test.sh's t_apicard runs the engine. fthree: run by t_evl only, its body loaded with eval.
cat > "$R/conveyor/tests/a.test.sh" <<'EOF'
t_one() {
  fone; fbare
}
t_two() {
  local d; d=$(mktemp -d) && mkdir "$d/lib" && cp conveyor/lib/f.sh "$d/lib/" && bash -c ". '$d/lib/f.sh' && ftwo" \
    && env -i PATH="$PATH" bash -c ". '$d/lib/f.sh' && fbare"; rm -rf "$d"
}
t_bad() {
  echo "$PWD/conveyor/tests/a.test.sh: line 9: boom"; return 1
}
t_evl() {
  ( eval "$(sed -n '/^fthree() {/,/^}/p' conveyor/lib/f.sh)"; fone() { :; }; fthree && fone )
}
EOF
# The runner calls p_tools, as conveyor/tests/lib.sh does: on macOS it puts Homebrew's folders on PATH (below).
cat > "$R/conveyor/conveyor.test.sh" <<'EOF'
cd "$(dirname "$0")/.." || exit 1
. conveyor/lib/portable.sh && p_tools || exit 1
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
# The checks every test-changed.sh run starts, empty: the selection runs below check none of them.
for c in test-lint no-browser-tests no-records-split; do : > "$R/.conveyor/$c.sh"; done
git -C "$R" init -q && git -C "$R" add -A && git -C "$R" commit -qm init
# Traced as on macOS (a `uname -s` of Darwin, which portable.sh's p_darwin asks): a Homebrew (B) of this machine's own
# tools, its bash in B/bin, which p_tools puts on PATH in coverage.sh and again in the runner.
B=$T/brew; mkdir -p "$B/bin" && ln -s "$BASH" "$B/bin/bash" && ln -s "$(command -v gtimeout || command -v timeout)" "$B/bin/gtimeout" \
  && printf '#!/bin/sh\n[ "$1" = -s ] && echo Darwin || exec %s "$@"\n' "$(command -v uname)" > "$B/bin/uname" && chmod +x "$B/bin/uname" \
  || no "the Homebrew folder could not be made"
for x in coreutils:timeout coreutils:date coreutils:stat findutils:find gnu-sed:sed grep:grep; do
  mkdir -p "$B/opt/${x%%:*}/libexec/gnubin" && ln -s "$(command -v "g${x#*:}" || command -v "${x#*:}")" "$B/opt/${x%%:*}/libexec/gnubin/${x#*:}"
done
(cd "$R" && PATH="$B/bin:$PATH" bash .conveyor/coverage.sh) > "$T/out" 2>&1; rc=$?
M=$R/.conveyor/coverage.jsonl
# facts <map>: each function-to-unit fact it holds, `<file><TAB><function><TAB><test file><TAB><case>` a line, sorted.
facts() {
  jq -rn '[inputs] as $m | (reduce ($m[] | select(has("path"))) as $x ({}; .[$x.testfile | tostring] = $x.path)) as $p
    | (reduce ($m[] | select(has("unit"))) as $x ({}; .[$x.unit | tostring] = [$p[$x.testfile | tostring], $x.case // ""])) as $u
    | $m[] | select(has("units")) | [.file, .fn] + $u[.units[] | tostring] | @tsv' "$1" | LC_ALL=C sort
}
# runs <file> <function>: the units the map lists for it, `<test>:<case>`, sorted.
runs() { facts "$M" | F=$1 N=$2 awk -F'\t' '$1 == ENVIRON["F"] && $2 == ENVIRON["N"] { print $3 ":" $4 }' | sort | paste -sd ' ' -; }
# notfacts <map>: its rows of no form coverage.sh writes, and those that hold an absolute path or this run's folder.
notfacts() {
  jq -c --arg t "$T" 'select((keys | IN(["traced"], ["path", "testfile"], ["testfile", "unit"], ["case", "testfile", "unit"], ["file", "fn", "sum", "units"]) | not)
    or any(.. | strings; startswith("/") or contains($t)))' "$1"
}
# Issue 1593. Bug: a failed unit's output lines went into the map as rows ("fn": null, the line as "file", with the
# path of the machine that ran it). The run still writes the map, with exit 1, and names the failed case.
[ "$rc" = 1 ] && [ -s "$M" ] && grep -q '^coverage.sh: conveyor/conveyor.test.sh bad failed' "$T/out" && grep -qF "$T/r/conveyor/tests/a.test.sh: line 9: boom" "$T/out" \
  && ok "coverage.sh traces the scratch checkout, names the failed case and writes the map" || no "coverage.sh exit $rc: $(cat "$T/out")"
[ -z "$(notfacts "$M")" ] && ok "the map holds no line of a failed unit's output, and no absolute path" || no "rows not facts: $(notfacts "$M")"

# D1: each function with only its own case, a case running a copy in a bash of its own included.
[ "$(runs conveyor/lib/f.sh fone)" = conveyor/conveyor.test.sh:one ] && [ "$(runs conveyor/lib/f.sh ftwo)" = conveyor/conveyor.test.sh:two ] \
  && ok "the map lists each engine function with only the case that ran it" \
  || no "fone: '$(runs conveyor/lib/f.sh fone)', ftwo: '$(runs conveyor/lib/f.sh ftwo)': $(cat "$M")"
# Issue 1723. Bug: a bash started with env -i lost the trace (BASH_ENV), so fbare was listed with t_one alone, and a
# change to it selected t_one and not t_two, which also runs it. Bug it catches too: on macOS the runner's p_tools put
# Homebrew's folders, and its bash, ahead of the unit's own bash again, so env -i started Homebrew's bash, untraced
# (portable.sh p_path). Both cases are listed.
[ "$(runs conveyor/lib/f.sh fbare)" = "conveyor/conveyor.test.sh:one conveyor/conveyor.test.sh:two" ] \
  && ok "a function a case runs only in a bash started with env -i is listed with that case" \
  || no "fbare, run by t_one and by t_two under env -i: '$(runs conveyor/lib/f.sh fbare)'"
# Bug: a case that loads a function's body with eval (`eval "$(sed -n '/^f() {/,/^}/p' ...)"`, as revive.test.sh's
# cardgone) was missing from its row, as bash names the case file for it, so a change to the function skipped that case.
# A stub the case file defines itself (fone) is still not the traced function.
[ "$(runs conveyor/lib/f.sh fthree)" = conveyor/conveyor.test.sh:evl ] \
  && ok "the map lists a function a case loads with eval with that case, and not a function the case stubs" \
  || no "fthree: '$(runs conveyor/lib/f.sh fthree)', fone: '$(runs conveyor/lib/f.sh fone)'"
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

# Issue 1593. Bug: the map was a row for each function and unit (26.9 MB for this project, too large to commit at each
# release). The map is now one row a function with its units' numbers. From the same functions and runs (with the
# output lines of a failed unit, as the run wrote them before), the new form must hold every fact the old form
# (oldform) holds and no row that is not a fact, and covof must select the same tests from either.
F=$T/fx; mkdir -p "$F"; printf '%s\n' "$want" > "$F/sums"
{ printf '%s\t%s\t%s\t%s\n' conveyor/lib/f.sh fone conveyor/conveyor.test.sh one conveyor/lib/f.sh ftwo conveyor/conveyor.test.sh two \
    .claude/scripts/dashboard.sh dpa .claude/scripts/__tests__/dashboard.test.sh pa .claude/hooks/g.sh gone $h/g.test.sh ga \
    .claude/hooks/g.sh gthree $h/k.test.sh 'gthree check' .claude/hooks/h.sh hone $h/h.test.sh ''
  printf '%s\n' 'coverage.sh: conveyor/conveyor.test.sh bad failed (exit 1); what it ran is kept. Its last lines:' "  $R/conveyor/tests/a.test.sh: line 9: boom"
} > "$F/runs"
# oldform <sums> <runs>: the map as coverage.sh wrote it before issue 1593, a row for each function and one for each
# function and unit.
oldform() {
  { echo '{"traced": "2026-11-25T00:00:00Z"}'; jq -cR 'split("\t") | {file: .[0], fn: .[1], sum: .[2]}' "$1"
    LC_ALL=C sort -u "$2" | jq -cR 'split("\t") | {file: .[0], fn: .[1], test: .[2]} + (if .[3] != "" then {case: .[3]} else {} end)'
  } | LC_ALL=C sort -u
}
oldform "$F/sums" "$F/runs" > "$F/old"; bash "$HERE/coverage.sh" --write 2026-11-25T00:00:00Z "$F/sums" "$F/runs" > "$F/new"
# The old form's facts: its unit rows of a traced function (not its rows of a failed unit's output, "fn": null).
oldf=$(jq -r 'select(has("test")) | [.file, .fn // "", .test // "", .case // ""] | @tsv' "$F/old" \
  | awk -F'\t' 'NR == FNR { s[$1 FS $2]; next } ($1 FS $2) in s' "$F/sums" - | LC_ALL=C sort)
[ "$(grep -c . <<<"$oldf")" = 6 ] && [ "$(jq -c 'select(has("test") and .fn == null)' "$F/old" | grep -c .)" = 2 ] && [ "$(facts "$F/new")" = "$oldf" ] \
  && [ -z "$(notfacts "$F/new")" ] && ok "the new form holds each fact the old form holds, and none of the old form's rows of a failed unit's output" \
  || no "old facts: '$oldf', new: '$(facts "$F/new")', rows not facts: '$(notfacts "$F/new")'"
# sel <map>: what test-changed.sh runs, with <map> committed, for a change to fone, dpa, gone, gthree and hone: the test
# files it starts and the cases and parts it names there (its log's `== ` and `TESTRUN case` lines), sorted. It runs
# the scratch checkout's tests through test-changed.sh: covof fills that run's own lists, and no mode prints them.
sel() {
  local f
  cp "$1" "$M" && git -C "$R" add -A && git -C "$R" commit -qm map || return 1
  for f in 'conveyor/lib/f.sh s/echo one/echo uno/' '.claude/scripts/dashboard.sh s/echo a$/echo A/' '.claude/hooks/g.sh 2s/:/: x/;8s/:/: y/' \
    '.claude/hooks/h.sh 2s/:/: z/'; do sed "${f#* }" "$R/${f%% *}" > "$T/e" && cat "$T/e" > "$R/${f%% *}"; done
  rm -rf "$F/log"; mkdir "$F/log"; (cd "$R" && CONVEYOR_TEST_LOG=$F/log bash .conveyor/test-changed.sh) > "$F/out" 2>&1
  grep -E '^(== |TESTRUN case	)' "$F/log/test-changed.log" | LC_ALL=C sort -u
  git -C "$R" checkout -q -- conveyor/lib/f.sh .claude/scripts/dashboard.sh .claude/hooks/g.sh .claude/hooks/h.sh
}
# A second case file of the engine, of another area, holding no case of a changed function. Bug it guards against: with
# a.test.sh the only case file, any case chosen is a case of each case file (enginewhole), so test-changed.sh starts the
# runner on none of them and logs no `TESTRUN case` line, and the checks below would compare no engine case at all.
printf 't_other() {\n  :\n}\n' > "$R/conveyor/tests/b.test.sh" && echo '{"area": "b", "test": "b.test.sh"}' >> "$R/.conveyor/engine-areas.json"
# What covof selected from the old form: its unit rows of the changed functions (its read before issue 1593), each as
# the run logs it: the file it starts (`== `) and the case or part it names there (`TESTRUN case`), an engine case
# by its case file.
oldsel=$(jq -r 'select(has("test")) | select([.file, .fn] | IN(["conveyor/lib/f.sh", "fone"], [".claude/scripts/dashboard.sh", "dpa"],
    [".claude/hooks/g.sh", "gone"], [".claude/hooks/g.sh", "gthree"], [".claude/hooks/h.sh", "hone"])) | [.test, .case // ""] | @tsv' "$F/old" \
  | while IFS=$'\t' read -r t c; do
      [ "$t" != conveyor/conveyor.test.sh ] || t=$(cd "$R" && grep -l "^t_$c() {" conveyor/tests/*.test.sh)
      echo "== $t"; [ -z "$c" ] || printf 'TESTRUN case\t%s\t%s\n' "$t" "$c"
    done | LC_ALL=C sort -u)
got=$(sel "$F/new")
# The same lines exactly (issue 1593's review: a check of the missing lines alone passed a run of an extra test file).
[ "$(grep -c '^TESTRUN case' <<<"$oldsel")" = 4 ] && [ "$got" = "$oldsel" ] \
  && ok "covof selects from the new form the tests it selected from the old: only the cases that ran each changed function" \
  || no "from the old form: '$oldsel'; the new form ran: '$got': $(cat "$F/out")"
# A map whose unit numbers are not each named once (two maps merged line by line) is not read: the change runs by area.
{ cat "$F/new"; jq -c 'select(has("unit")) | .case = "two"' "$F/new" | head -n 1; } > "$F/dup"
[ "$(sel "$F/dup" | sed -n 's/^TESTRUN case	conveyor\/tests\/a.test.sh	//p' | paste -sd ' ' -)" = "bad evl one two" ] \
  && ok "a map that names a unit number twice is not read, and the change runs its area's cases" || no "two rows of one unit number: $(cat "$F/out")"
# Issue 1723. A card's Test step runs each file the engine lists (from the area map: a.test.sh for f.sh; b.test.sh, as
# a file the engine can list for its own reasons) alone, through --file, with the list in CONVEYOR_TEST_FILELIST. Bug:
# each listed case file ran all its cases, so a change to fone ran bad, one and two of a.test.sh and other of b.test.sh,
# and the map narrowed nothing. A.test.sh runs one alone, and b.test.sh no case, and passes.
cp "$F/new" "$M" && git -C "$R" add -A && git -C "$R" commit -qm map1723 && sed 's/echo one/echo uno/' "$R/conveyor/lib/f.sh" > "$T/e" \
  && cat "$T/e" > "$R/conveyor/lib/f.sh" && printf '%s\n' conveyor/tests/a.test.sh conveyor/tests/b.test.sh > "$F/list" \
  || no "the one-file fixture could not be made"
for x in a b; do
  rm -rf "$F/o$x"; mkdir "$F/o$x"
  (cd "$R" && CONVEYOR_TEST_LOG=$F/o$x CONVEYOR_TEST_FILELIST=$F/list bash .conveyor/test-changed.sh --file conveyor/tests/$x.test.sh) > "$F/o$x.out" 2>&1
  echo $? > "$F/o$x.rc"
done
# The engine asks the list mode which of the linked files to run first when it caps them (conveyor/lib/testlist.sh
# selfirst()). Bug it catches: the list named every listed file in name order, so a Board test the engine listed, which
# the selection did not choose, came before a.test.sh, which holds the case the map chose, and took its place under the
# cap. The list names a.test.sh first, then dashboard.test.sh, and not b.test.sh, which runs no case.
{ cat "$F/list"; echo .claude/scripts/__tests__/dashboard.test.sh; } > "$F/list2"
(cd "$R" && CONVEYOR_TEST_LIST=$F/sel CONVEYOR_TEST_FILELIST=$F/list2 bash .conveyor/test-changed.sh) > "$F/sel.out" 2>&1
git -C "$R" checkout -q -- conveyor/lib/f.sh
[ "$(paste -sd ' ' "$F/sel" 2>&1)" = "conveyor/tests/a.test.sh .claude/scripts/__tests__/dashboard.test.sh" ] \
  && ok "the list names first the files the selection chose, then those only the engine's list brought" \
  || no "list mode, fone changed, files given a.test.sh, b.test.sh and dashboard.test.sh: listed '$(paste -sd ' ' "$F/sel" 2>&1)': $(cat "$F/sel.out")"
got=$(sed -n 's/^TESTRUN case	//p' "$F/oa/test-changed.log" | paste -sd ' ' -)
[ "$(cat "$F/oa.rc")" = 0 ] && [ "$got" = "conveyor/tests/a.test.sh	one" ] \
  && ok "a card's one-file run of a listed case file runs only the case the map lists for the changed function" \
  || no "--file a.test.sh, fone changed, list a and b.test.sh: exit $(cat "$F/oa.rc"), ran '$got': $(cat "$F/oa.out")"
got=$(sed -n 's/^TESTRUN case	//p' "$F/ob/test-changed.log" | paste -sd ' ' -)
[ "$(cat "$F/ob.rc")" = 0 ] && [ -z "$got" ] && grep -qF 'selects none of the cases of conveyor/tests/b.test.sh' "$F/ob.out" \
  && ok "a card's one-file run of a listed case file that holds no case the map lists runs none, and passes" \
  || no "--file b.test.sh, fone changed, list a and b.test.sh: exit $(cat "$F/ob.rc"), ran '$got': $(cat "$F/ob.out")"
# Issue 1593's review. Bug: a change to a hook library the map does not hold (--funcs cannot read hook-fire-log.sh or
# strip-quoted.sh) ran no test: a library has no test of its own name and no area. It runs the hooks' tests that name
# it, or name a hook that names it: h.test.sh (h.sh names lib/hl.sh) and l.test.sh (names it), not g, k or m.test.sh.
mkdir -p "$R/.claude/hooks/lib" && printf 'hlf() {\n  :\n}\n' > "$R/.claude/hooks/lib/hl.sh" && printf '# . lib/hl.sh\n' >> "$R/.claude/hooks/h.sh" \
  && printf '. "$(dirname "$0")/../lib/hl.sh"\n' > "$R/.claude/hooks/__tests__/l.test.sh" && cp "$F/new" "$M" && git -C "$R" add -A \
  && git -C "$R" commit -qm hooklib && printf 'hlf() {\n  echo changed\n}\n' > "$R/.claude/hooks/lib/hl.sh" || no "the hook library fixture could not be made"
rm -rf "$F/log"; mkdir "$F/log"; (cd "$R" && CONVEYOR_TEST_LOG=$F/log bash .conveyor/test-changed.sh) > "$F/out" 2>&1
got=$(grep '^== ' "$F/log/test-changed.log" | LC_ALL=C sort -u | paste -sd ' ' -)
[ "$got" = "== $h/h.test.sh == $h/l.test.sh" ] && ok "a change to a hook library the map does not hold runs the hooks' tests that reach it" \
  || no "hl.sh changed: ran '$got': $(cat "$F/out")"
# Bug: a hook library removed (`git rm`) ran no test: the pick of a file that is not there ended before hooklibtests.
git -C "$R" checkout -q -- .claude/hooks/lib/hl.sh && git -C "$R" rm -q .claude/hooks/lib/hl.sh || no "the hook library could not be removed"
rm -rf "$F/log"; mkdir "$F/log"; (cd "$R" && CONVEYOR_TEST_LOG=$F/log bash .conveyor/test-changed.sh) > "$F/out" 2>&1
got=$(grep '^== ' "$F/log/test-changed.log" | LC_ALL=C sort -u | paste -sd ' ' -)
[ "$got" = "== $h/h.test.sh == $h/l.test.sh" ] && ok "a hook library removed runs the hooks' tests that reached it" \
  || no "hl.sh removed: ran '$got': $(cat "$F/out")"
# The size: 1,000 functions each run by 200 units (of 3,000 engine cases) in under a tenth of the old form's bytes.
awk 'BEGIN { for (n = 1; n <= 1000; n++) printf "conveyor/lib/area%02d.sh\tfunction_%04d\t%d %d\n", n % 40, n, 1000000000 + n * 7919, 1000 + n }' > "$F/bsums"
awk 'BEGIN { for (n = 1; n <= 1000; n++) for (j = 0; j < 200; j++)
  printf "conveyor/lib/area%02d.sh\tfunction_%04d\tconveyor/conveyor.test.sh\tcasename%05d\n", n % 40, n, (n * 37 + j * 11) % 3000 }' > "$F/bruns"
bash "$HERE/coverage.sh" --write 2026-11-25T00:00:00Z "$F/bsums" "$F/bruns" > "$F/bnew"; oldform "$F/bsums" "$F/bruns" > "$F/bold"
o=$(wc -c < "$F/bold"); w=$(wc -c < "$F/bnew")
[ "$(jq -s '[.[] | select(has("units")) | .units | length] | [length, min] == [1000, 200]' "$F/bnew")" = true ] && [ $((w * 10)) -lt $((o)) ] \
  && ok "the map of 1,000 functions run by 200 units each is under a tenth of the old form's size ($w of $o bytes)" || no "new form $w bytes, old form $o"

# dashboard.test.sh runs the parts CONVEYOR_SHELL_TEST_CASE names: each part ends at once in fresh when left out, so
# each part's subshell starts with fresh <its name>; and a name of no part exits 2, never a run of nothing.
parts=$(sed -n 's/^) & started \([a-z0-9]*\)$/\1/p' "$ROOT/.claude/scripts/__tests__/dashboard.test.sh" | sort)
fresh=$(sed -n 's/^( fresh \([a-z0-9]*\).*/\1/p' "$ROOT/.claude/scripts/__tests__/dashboard.test.sh" | sort)
[ -n "$parts" ] && [ "$parts" = "$fresh" ] && ok "each part of dashboard.test.sh starts with fresh <its name>" || no "parts '$parts', fresh '$fresh'"
(cd "$ROOT" && CONVEYOR_SHELL_TEST_CASE=nosuch bash .claude/scripts/__tests__/dashboard.test.sh) > "$T/dash" 2>&1
[ $? = 2 ] && grep -q 'unknown part nosuch' "$T/dash" && ok "dashboard.test.sh refuses a part it does not have" || no "unknown part: $(cat "$T/dash")"
exit $bad
