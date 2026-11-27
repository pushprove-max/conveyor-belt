#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# The tests a card's change touches, until CI (C1) replaces this: each changed test file, and each test file named
# after a changed source file (same stem, beside it or in __tests__ next to it; `_` in the stem read as `-`), and the
# test files TESTS_OF lists for it (ones named after another file, or none). A test named <stem>-<rest> belongs to the
# longest source name its name starts with: a change to <stem> does not select it when another source file beside it
# or beside its __tests__ folder, or a name in NAMED, is named <stem>-<part>… and the test's name starts with that
# (issue 463). And the test files .conveyor/test-links.json links to a changed file (issue 598: LINKS, below). And the
# Board test files that import a changed module beside them, or draw a changed panel (issue 544: boardtests, below).
# Exit 1 if any fails or none ran for a changed source file that has tests.
# The engine: each engine source file is in one area of .conveyor/engine-areas.json, which names the case files
# (conveyor/tests/) that cover it ("all": every one). In a build or fix session an engine change runs only the cases of
# its areas' files, and of each changed case file, and so does the loop's test step (CONVEYOR_TEST_LOG set: conveyor.sh tests()).
# Every run first runs the unit cases of the changed engine files (conveyor/unit/unit.sh, issue 1620), then checks the
# map (both in one-file mode in a test step, once a tree: issue 422, below): an engine source
# file (a file under conveyor/ that is not a test and not in its "outside" list) in no area, or in two, an area whose tests are not "all" or a non-empty list,
# or a file or case file it names that does not exist, fails it. So does a file under conveyor/lib/ in an "all" area
# with no `why` (each engine file names its own case files; "all" is for what every case runs through, and says why),
# and a case file under conveyor/tests/ that no area names in a list (it would run on no engine file's change).
# A deleted engine file runs the whole engine test: its area can no longer be read from the map.
# A change to the texts, comments and blanks alone of an engine file under conveyor/lib/, of conveyor/conveyor.sh or of
# a Board file under .claude/dashboard/ (issues 512, 513: textonly) runs neither its area nor the tests named after it:
# only the tests that hold a text it changed, the tests of each source file that holds an old text, and its parse check.
# Ahead of every rule here, a change to the comment and blank lines alone of a shell, Python, YAML, JS, TS, CSS or HTML
# file (issue 640: commentonly) selects no test, not even itself when it is a test file (one that passed before stays
# passed), only a shell file's parse check; the run prints `comment-only change: <file>, no tests selected` for each.
# A changed case file whose shared part (its lines outside its t_<case> functions) is the same but for comments and
# blanks runs only its changed and added cases (issue 513: casesof); else it runs whole.
# A change to functions alone of an engine shell file (conveyor/lib/paths.sh too) runs the test files that name a
# changed function or a function that calls one (one hop), and of a command script whose lines outside its functions
# call one, the case files that run its commands, and the tests named after the file or listed for it; not its area,
# unless one runs at start-up or they have more than 25 callers (issue 1775: callersof). A change to lines of
# conveyor.sh's command table alone (a command added, removed or changed, with its usage text) runs the case files that
# run those commands (cmdsof; issue 530). Else each runs the whole, as before. A change to keys of the control record's
# defaults (conveyor/lib/control-defaults.json) runs the case files of the code that reads those keys and of the case
# files that read the file (keysof); else the file's area. So a change to functions runs by three rules, in this order:
# the coverage map (covof, below), then callersof, then the area; a line per changed function names the rule that
# picked its tests (covrules).
# Ahead of those, a change to functions alone of a shell file the coverage map holds (.conveyor/coverage.jsonl,
# written by a traced run of every case: .conveyor/coverage.sh; issue 527: covof) runs the cases the map lists for each
# changed function: engine cases through the runner, parts of dashboard.test.sh and of the hooks' tests (partsof;
# CONVEYOR_SHELL_TEST_CASE, comma-separated), other test
# files whole; and of the tests named after the file or listed for it (TESTS_OF), those the map names nowhere (that the
# trace did not run). A part runs only when nothing selects its test file whole. A function changed since the map was
# traced (its sum differs) runs the cases the map lists for it as traced; a function the change adds runs the cases of
# the functions of its file that call it (up to 3 calls away). A change outside any function, to a function the map
# does not hold or lists no case for, or an added one that no mapped function of its file calls, runs by the rules above
# (callersof, else its area; a hook library, .claude/hooks/lib/, the hooks' tests that reach it: hooklibtests).
# The map check says how old the coverage map is.
# A change to the map itself runs the map check, the map's own tests (MAPTESTS: .conveyor/test-changed.test.sh,
# .conveyor/test-changed-map.test.sh and .conveyor/test-changed-areas.test.sh, which read this checkout's map) and the case files whose naming changed: each
# case file an area lists in the map now and did not list at HEAD, and every case file of an area whose files list changed, so a file moved to other cases runs them. An "all" area among those, or a map that cannot be read at HEAD or in the worktree, runs the whole engine
# test. A map edit that wrongly drops a case file from an area is not caught here: the map check (every case file is
# named by some area) and the nightly whole test are the net. `test-changed.sh --check` runs the map check alone, and
# lists the meta-runners (below) the runs saw and those the pack marks, each with its mark.
# Meta-runners (issue 584): each test file it starts is marked (CONVEYOR_TEST_FILE names it), and every bash it starts
# reads a hook (BASH_ENV) that sees a bash test file of this checkout (its path ends in one that git lists here, as a
# copy of the checkout's does) start whole (no CONVEYOR_SHELL_TEST_CASE) under another's mark: that file is a
# meta-runner, and the log says so (`TESTRUN nested<TAB><file><TAB><inner file>`). The runs' meta-runners are kept in
# the repository's git folder (conveyor-meta-runners) for --check. A meta-runner needs one of two marks in the pack
# (.conveyor/project.json): `test.files.<file>.cardMode`, a NAME=VALUE this script runs it with (its card mode: its own
# checks, a stub in place of the files it starts), or `test.files.<file>.wholeOnly`: this script never runs it, and
# says so (`TESTRUN whole-only<TAB><file>`); the whole test, which does not run through it, runs it whole. A file that
# starts another test file with neither mark fails, its failure naming the file and the two marks. The engine runner
# sources its case files, which the hook does not see: its run of every case file is a meta-runner's run, logged so,
# and with neither mark it is not run, and fails; its run of chosen cases is not, and runs whatever its mark.
# Every run also runs the test lint (.conveyor/test-lint.sh): a sleep-then-check in any test file fails the run.
# And the records split check (.conveyor/no-records-split.sh): engine code that splits a whole records file in jq fails it.
# And shellcheck on the changed .sh files: a warning on a line the change added or changed fails the run (below).
# And `claude plugin validate` when the change touches hooks/, types/ or .claude-plugin/: an error fails the run, and so
# does a type error HEAD's copy of the plugin does not have (below).
# In one-file mode in a test step these checks run once a tree, and later runs of that tree reuse their result.
# In a test step, each test file it runs whole (an engine case file with every case it holds, but a plugin test file)
# runs under strace where the host can trace, and when it passes, its log names the files it read (`TESTRUN inputs`,
# issue 1619: TRACE, below).
# A run again of the same change (conveyor.sh tests(): CONVEYOR_TEST_RERUN names what passed and what failed) runs
# no file that passed, and of the engine's runner only the cases that failed, when the run before named them, else
# those of its selection that did not print `ok <case>` (a runner killed part-way). A file the list names failed cases
# of runs even when no changed file selects it (the loop runs a card's failing cases on main, where nothing changed):
# of the engine's runner, those cases, when the list names one of its cases; of a node test file, those cases alone; a
# `fail` line naming no case (a file that failed naming none), the file whole; of an engine case file, each of its
# cases, through the runner (the run of one file by hand: conveyor.sh testaction run), and with a case the file does
# not have (the split check's conveyor-no-case), the runner with no case, timed as that file: its start-up.
# A node test file it runs leaves out each case an `ok` line of the list names, as the runner does (the loop keeps a
# flaky case off a card's run so: conveyor.sh flakyoff()); a Python or other shell test file has no case filter and
# runs whole. A case an `off` line names (one the loop keeps off as flaky) is left out of the runner and of a node test
# file even where a `changed` or `main` line below selects it; a file an `off` line names with no case (one the loop
# keeps off for its CPU seconds) does not run at all, nor, of an engine case file, any of its cases. After a session changed the change
# (the list's `changed` lines: the files whose content it changed), the tests those files select, picked as above (an
# "all" area's file runs the whole engine test; a changed map runs what the map rule says), run too, whether or not
# they passed before. After the change moved onto a newer main (the list's `main` lines: the files main changed since
# the list was made), the tests those files select run too, only where the change's own selection holds them: a test
# file it selects, of the engine's runner the cases both select. Each file such a run runs, and each file a first run
# of the loop's test step runs (CONVEYOR_TEST_LOG set, no list), its log says why
# (`TESTRUN why<TAB><file><TAB><reason>`: "the card changed <file>", "main changed <file>", "did not pass", and of the
# runner, "the area <name> runs all engine tests" when an "all" area selected it). A run of every engine case file
# says so in its log (`TESTRUN whole-suite`). A run again's log says how many cases of the selection passed before and are not run:
# `TESTRUN kept=<n>`. A file the list names as passed and also names failed cases of (it passed, then failed them in
# such a run) runs: of the runner, those cases alone. When it runs only some of the runner's cases, its log names
# each (`TESTRUN case<TAB><file><TAB><case>`). Each Board or shell test file it runs, its log times as it ends
# (`TESTRUN sec<TAB><file><TAB><seconds><TAB><CPU seconds>`: clock, and user plus system of all it started), and each
# engine case file whose every case the runner ran, as the runner ends (the sums of its cases' times:
# CONVEYOR_TEST_TIMES), for the times the loop records of a test file (conveyor/README.md).
# The engine's runner above is the set of engine cases the selection picks; they run as their case files (issue 214):
# each engine case file that holds some of them is a test file of its own, run with those cases alone (the runner,
# given them, under that file's mark), side by side on the machine's test slots. Its log lines (`==`, `-- ok|FAIL`,
# why, case, sec) name the case file, not the runner, and a list's lines naming either are read alike. The runner runs
# as a file only to run every engine case file, whole-only or in its card mode.
set -u
unset CONVEYOR_SHELL_TEST_CASE
# One-file mode (issue 379; the pack's test.fileCommand, which Conveyor runs once for each listed test file):
# `test-changed.sh --file <path>` runs that test file alone and nothing else: an engine case file
# (conveyor/tests/<area>.test.sh) with the cases the selection chose in it (all its cases when it chose none there,
# none when the coverage map chose the selection: cnarrow, below; the cases CONVEYOR_TEST_CASES names of it, `<file><TAB><case>` lines, when it names any),
# a shell test file that selects its cases as the runner does with the cases CONVEYOR_TEST_CASES names of it, and
# any other test file (the Board's under .claude/scripts/__tests__/, the hooks' under hooks/) whole. The checks every
# run makes (checks(): the unit cases of the changed engine files, the map check, the test lint, no browser tests, no records split, shellcheck, the plugin's
# validate when the change touches it) still run, once a tree in a test step (issue 422, below). A
# path that is no file fails at once, before any of it, as does a runner of the whole suite (issue 382: the engine's runner, this script and the full test's), which is no
# test file.
ONE=
if [ "${1:-}" = --file ]; then
  ONE=${2:-}; ONE=${ONE#./}
  [ -n "$ONE" ] && [ -f "$ONE" ] || { echo "test-changed: --file: no such test file: '${ONE}'" >&2; exit 2; }
  for r in conveyor/conveyor.test.sh .conveyor/test-changed.sh .conveyor/test-full.sh; do
    [ ! "$ONE" -ef "$r" ] || { echo "test-changed: --file: $ONE is a runner of the whole suite, not a test file: not run" >&2; exit 2; }
  done
fi
RERUN=${CONVEYOR_TEST_RERUN:-}; unset CONVEYOR_TEST_RERUN
# The mark of a card's run that stops at its first failure (conveyor/lib/fileeach.sh): given to the engine's runner
# and to a node test file (below), which stop at their first failed case (the node file's case pool takes it out of
# its environment: dashboard-view.helpers.mjs); no other test file this runs reads it, as one may run a loop of its
# own. Each other file stops at its first failed case all the same (failstop(), unittest's -f).
FAILFAST=${CONVEYOR_TEST_FAILFAST:-}; unset CONVEYOR_TEST_FAILFAST
RERUN0=$RERUN
# The cases the loop names of the test files it gives (conveyor/lib/testlist.sh owncases(): `<file><TAB><case>` lines),
# read in one-file mode (below); unset, as the list is, so no test this runs reads the loop's.
TCASES=${CONVEYOR_TEST_CASES:-}; unset CONVEYOR_TEST_CASES
# onecases <engine case file> <chosen cases, words> [narrow]: the cases of that file a run of it alone runs, one a line:
# the chosen ones it holds, else all its cases (with narrow, none: cnarrow, below), and of those the cases the loop
# names of it (TCASES) when it names any. Fails when the file holds no case.
onecases() {
  local own c k
  own=$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$1" | sort -u); [ -n "$own" ] || return 1
  c=; [ -z "$2" ] || c=$(tr ' ' '\n' <<<"$2" | grep -xF -f <(echo "$own"))
  k=$(awk -F'\t' -v f="$1" '$1 == f {print $2}' <<<"$TCASES" | grep -xF -f <(echo "$own")) && c=$k
  [ -n "$c" ] || [ -n "${3:-}" ] || c=$own
  [ -z "$c" ] || printf '%s\n' "$c"
}
# Each engine case file runs as its own test file (issue 214, below), so the list names its cases under it; a list
# written before that names them under the runner, conveyor/conveyor.test.sh. Both are read as one: the selection
# below picks the engine's cases as the runner's, and runs each case file of them on its own. An `ok`, `off` or
# `fail` line of a case of an engine case file is read as the runner's line of that case; a `pass` line of an engine
# case file as an `ok` line of each of its cases that no `fail` line names (it passed, so they are kept as passed),
# unless a `fail` line names the file with no case. Any other line, and one of a case the file does not have (the
# split check's run with no case, below), is read as it is.
if [ -s "$RERUN" ]; then
  rlist=$(mktemp); trap 'rm -f "$rlist"' EXIT
  { grep -H '^t_[a-z0-9]*() {' conveyor/tests/*.test.sh 2>/dev/null | sed -n 's/^\([^:]*\):t_\([a-z0-9]*\)() {.*/\1\t\2/p' | sed 's/^/def\t/'
    sed 's/^/rerun\t/' "$RERUN"; } | awk -F'\t' -v OFS='\t' '
    $1 == "def" { def[$2 "\t" $3] = 1; of[$2] = of[$2] "\t" $3; next }
    { l[++n] = $0; k[n] = $2; f[n] = $3; c[n] = $4
      if ($2 == "fail") { if ($4 == "") whole[$3] = 1; else failed[$3 "\t" $4] = 1 } }
    END {
      for (i = 1; i <= n; i++) {
        if (f[i] !~ /^conveyor\/tests\/[^\/]+[.]test[.]sh$/) { print substr(l[i], 7); continue }
        if (k[i] == "pass" && c[i] == "" && !(f[i] in whole)) {
          m = split(substr(of[f[i]], 2), cs, "\t")
          for (j = 1; j <= m; j++) if (!((f[i] "\t" cs[j]) in failed) && !(("conveyor/conveyor.test.sh\t" cs[j]) in failed)) print "ok", "conveyor/conveyor.test.sh", cs[j]
        } else if ((k[i] == "ok" || k[i] == "off" || k[i] == "fail") && c[i] != "" && ((f[i] "\t" c[i]) in def)) print k[i], "conveyor/conveyor.test.sh", c[i]
        else print substr(l[i], 7)
      }
    }' > "$rlist" && RERUN=$rlist
fi
MAP=.conveyor/engine-areas.json
# The map's own tests, the ones that read this checkout's map: a change to the map runs each that exists.
MAPTESTS=".conveyor/test-changed.test.sh .conveyor/test-changed-map.test.sh .conveyor/test-changed-areas.test.sh"
# The map is one fact a line, so two changes that each add a line to it merge with no conflict (the repository's
# .gitattributes merges it keeping both sides): {"outside": <path>}, or of an area {"area": <name>} with one more key,
# "file": <engine file>, "test": <case file>, "tests": "all" or "why": <text>. AREAS reads its lines (jq -s) as
# {outside: [paths], areas: {<name>: {files, tests: "all" or [case files], why}}}; any other line, or an area with both
# "all" and case files, is an error: the map cannot be read. `test-changed.sh --map` prints it so.
AREAS='reduce .[] as $l ({outside: [], areas: {}};
  if ($l | type) == "object" and ($l | keys) == ["outside"] and ($l.outside | type) == "string" then .outside += [$l.outside]
  elif ($l | type) == "object" and ($l.area | type) == "string" and ($l | length) == 2 then
    .areas[$l.area] |= ((. // {files: []}) | if ($l.file | type) == "string" then .files += [$l.file]
      elif ($l.test | type) == "string" and .tests != "all" then .tests = (.tests // []) + [$l.test]
      elif $l.tests == "all" and .tests == null then .tests = "all"
      elif ($l.why | type) == "string" then .why = $l.why
      else error("not a line of the map: \($l)") end)
  else error("not a line of the map: \($l)") end)'
if [ "${1:-}" = --map ]; then jq -s "$AREAS" "$MAP"; exit; fi
# The coverage map (covof, below; .conveyor/coverage.sh writes it).
COV=.conveyor/coverage.jsonl
# FUNCS, an awk program, reads a bash file as its functions and the rest (coverage: covof, coverage.sh), less strictly
# than CASES: a function starts at a line at the left `<name>() {` or `<name>() (` (or `function <name>() ...`), and ends
# on that line when it closes there, else at the next line that starts with the `}` or `)` that closes it, past the
# heredocs it starts (a heredoc starts at `<<<word>` on a line that is not a comment, its word not starting with `-`:
# `<<123` in a comment and `<<-?` in a pattern start none); a line in it may be at the left (a comment, a line of a
# string). A `{` function with no such `}` line before the next function or the end of the file ends at its last
# indented line that ends with `; }` (or `& }`, as a one-line function may end; not a comment), and the lines after it
# are other lines (issue 1775: `  ...; }` as a function's last line). A top-level line (at the left) that ends with
# `; }` is not such a line, nor is the end of a string at the left. A `K<TAB><name><TAB><body>` line for each, its
# lines joined by \001; `S<TAB><line>` for each other line; and `U` when a name is defined twice, a function does not
# end, or a line in one starts a function before such a `; }` line (a function it misread as not ended there).
FUNCS='function heredoc(x) {
  x = $0; gsub(/<<</, "", x)
  if (x !~ /^[ \t]*#/ && match(x, /<<-?[ \t]*[\047"\\]?[A-Za-z_0-9.][A-Za-z_0-9.-]*/)) { x = substr(x, RSTART, RLENGTH); hdt = (x ~ /^<<-/); sub(/^<<-?[ \t]*[\047"\\]?/, "", x); hd = x }
}
function start() { return match($0, /^(function[ \t]+)?[A-Za-z_][A-Za-z0-9_]*[ \t]*\(\)[ \t]*[{(]/) }
function fin(i, k, l) {
  print "K\t" c "\t" cb; k = split(t, l, "\001"); for (i = 2; i <= k; i++) print "S\t" l[i]; c = ""; cb = ""
}
c != "" {
  if (hd != "") { b = b "\001" $0; t = t "\001" $0; x = $0; if (hdt) sub(/^\t+/, "", x); if (x == hd) hd = ""; next }
  if (substr($0, 1, 1) == e) { print "K\t" c "\t" b "\001" $0; c = ""; cb = ""; next }
  if (start()) { if (cb == "") { print "U"; u = 1; exit } fin() }
  else {
    b = b "\001" $0
    if (e == "}" && $0 ~ /^[ \t]+[^ \t#]/ && $0 ~ /[;&] *}([ \t]*[0-9]*>+[ \t]*[^ \t;&|]+)*[ \t]*(#.*)?$/) { cb = b; t = "" } else t = t "\001" $0
    heredoc(); next
  }
}
start() {
  x = substr($0, 1, RLENGTH); e = substr(x, RLENGTH) == "{" ? "}" : ")"; r = substr($0, RLENGTH + 1)
  n = x; sub(/^function[ \t]+/, "", n); sub(/[ \t]*\(.*/, "", n)
  if (n in seen) { print "U"; u = 1; exit }
  seen[n] = 1
  if (r !~ /^[ \t]*(#.*)?$/ && r ~ (e == "}" ? "[;&] *}([ \t]*[0-9]*>+[ \t]*[^ \t;&|]+)*[ \t]*(#.*)?$" : "\\)([ \t]*[0-9]*>+[ \t]*[^ \t;&|]+)*[ \t]*(#.*)?$")) { print "K\t" n "\t" $0; next }
  c = n; b = $0; cb = ""; t = ""; heredoc(); next
}
{ print "S\t" $0 }
END { if (!u && c != "") { if (cb == "") print "U"; else fin() } }'
# sumsof: of FUNCS output on stdin, `<name><TAB><sum>` for each function, its sum the cksum of its body: the coverage
# map's sum of a function as it was traced, and covof's of it as the change found it.
sumsof() {
  local k n b
  while IFS=$'\t' read -r k n b; do [ "$k" != K ] || printf '%s\t%s\n' "$n" "$(cksum <<<"$b" | cut -d' ' -f1)"; done
  return 0
}
# `test-changed.sh --funcs <file>`: the sums of its functions (coverage.sh), or exit 1 when FUNCS cannot read it.
if [ "${1:-}" = --funcs ]; then s=$(awk "$FUNCS" "$2") && ! grep -qx U <<<"$s" || exit 1; sumsof <<<"$s"; exit; fi
# partsof <test file>: the parts of a shell test file CONVEYOR_SHELL_TEST_CASE runs (comma-separated), one a line: the
# names of its `) & started <part>` lines (dashboard.test.sh), else of its `CASES=" <case> ... "` line (the hooks'
# case_on files). Exit 3 for a file that selects its checks by their text (it sources lib/case-filter.sh:
# bash-guardrails.test.sh), whose parts are texts (coverage.sh); exit 1 for a file with no parts, run whole.
# `test-changed.sh --parts <test file>` prints them so (coverage.sh).
partsof() {
  local p
  grep -q CONVEYOR_SHELL_TEST_CASE "$1" 2>/dev/null || return 1
  p=$(sed -n 's/^) & started \([a-z0-9]*\)$/\1/p' "$1")
  [ -n "$p" ] || p=$(sed -n 's/^CASES=" \([a-z0-9 -]*\) "$/\1/p' "$1" | tr ' ' '\n' | grep .)
  [ -z "$p" ] || { echo "$p"; return 0; }
  grep -q '^[.] .*/lib/case-filter[.]sh"\?$' "$1" && return 3
  return 1
}
# partok <test file> <part>: the file has that part now: one partsof names, or a text with no comma the file holds.
partok() {
  local p r
  p=$(partsof "$1"); r=$?
  if [ $r = 0 ]; then grep -qxF -- "$2" <<<"$p"; else [ $r = 3 ] && [[ $2 != *,* ]] && grep -qF -- "$2" "$1"; fi
}
if [ "${1:-}" = --parts ]; then partsof "$2"; exit; fi
AMAP=$(jq -cs "$AREAS" "$MAP" 2>/dev/null) || AMAP=''
# FNSCAN, an awk program run with -v q="'" on case files: a line for each function name more than one of them defines,
# read as sourcing defines them: a `<name>() {` or `<name>() (` line at the left, outside a heredoc. Only a << outside
# quotes and comments starts a heredoc (a fixture's functions, written into a scratch file, are not the file's own).
FNSCAN='function opener(s,   i, n, c, t, h) {
  n = length(s)
  for (i = 1; i <= n; i++) {
    c = substr(s, i, 1)
    if (t == q) { if (c == q) t = ""; continue }
    if (c == "\\") { i++; continue }
    if (t == "\"") { if (c == "\"") t = ""; continue }
    if (c == q || c == "\"") t = c
    else if (c == "#" && (i == 1 || substr(s, i - 1, 1) ~ /[ \t;|&(]/)) return ""
    else if (substr(s, i, 3) == "<<<") i += 2
    else if (match(substr(s, i), "^<<-?[ \t]*[\"" q "\\\\]?[A-Za-z_][A-Za-z0-9_]*")) {
      h = substr(s, i, RLENGTH); dash = (h ~ /^<<-/); sub(/^<<-?[ \t]*/, "", h); gsub("[\"" q "\\\\]", "", h); return h }
  }
  return ""
}
FNR == 1 { end = "" }
end != "" { l = $0; if (dash) sub(/^\t+/, "", l); if (l == end) end = ""; next }
/^[A-Za-z_][A-Za-z0-9_]*\(\) *[{(]/ { k = $0; sub(/\(.*/, "", k)
  if (!((k, FILENAME) in seen)) { seen[k, FILENAME] = 1; nf[k]++; at[k] = at[k] (nf[k] > 1 ? ", " : "") FILENAME } }
{ end = opener($0) }
END { for (k in nf) if (nf[k] > 1) print k "(): defined in " nf[k] " case files (" at[k] "); the runner sources them all, so one replaces the others in every run: rename it" }'
mapcheck() {
  local bad
  [ -n "$AMAP" ] && bad=$(git ls-files -co --exclude-standard conveyor | while read -r f; do [ -e "$f" ] && echo "$f"; done \
    | jq -Rrn --argjson m "$AMAP" --arg map "$MAP" '[inputs] as $all
      | ([$m.areas[].files[]]) as $named
      | ($all[] | select(endswith(".test.sh") | not) | . as $f
          | select($m.outside | any(. as $o | $f == $o or (($o | endswith("/")) and ($f | startswith($o)))) | not)
          | ([$named[] | select(. == $f)] | length) as $n
          | if $n == 0 then "\($f): an engine source file in no area of \($map)"
            elif $n > 1 then "\($f): in \($n) areas of \($map); a file is in one" else empty end),
        ($named - $all | .[] | "\(.): named in \($map), but there is no such file"),
        ($m.areas | to_entries[] | select(.value.tests != "all" and ((.value.tests | type) != "array" or .value.tests == []))
          | "\(.key): an area of \($map) with no case files; its tests are \"all\" or a non-empty list"),
        ([$m.areas[].tests | arrays | .[] | "conveyor/tests/" + .] | unique - $all | .[] | "\(.): named in \($map), but there is no such case file"),
        ($m.areas | to_entries[] | select(.value.tests == "all" and ((.value.why // "") | length) == 0) | .key as $k
          | .value.files[] | select(startswith("conveyor/lib/"))
          | "\(.): in \($k), an area of \($map) whose tests are \"all\" with no why; name its case files"),
        ([$all[] | select(test("^conveyor/tests/[^/]+[.]test[.]sh$"))]
          - [$m.areas[].tests | arrays | .[] | "conveyor/tests/" + .] | .[]
          | "\(.): a case file no area of \($map) names; an area of the engine files it covers lists it")') \
    || bad="$MAP could not be read"
  # A case file the map names by file name alone is, to the engine's map reader (lib/testmap.sh mapread()), the one
  # test file of the repository with that name: with two (#332: standing.test.sh under conveyor/tests/ and
  # conveyor/foreman/), the reader cannot read the map and every card runs without it.
  [ -n "$AMAP" ] && bad=$bad${bad:+$'\n'}$(git ls-files -co --exclude-standard | grep -E '\.test\.' | while read -r f; do [ -e "$f" ] && echo "$f"; done \
    | jq -Rrn --argjson m "$AMAP" --arg map "$MAP" '[inputs] as $ts
      | [$m.areas[].tests | arrays[] | select(contains("/") | not)] | unique[] as $n
      | [$ts[] | select(split("/")[-1] == $n)] | select(length > 1)
      | "\($n): named in \($map), but \(length) test files have that name (\(join(", "))); the map cannot tell them apart: rename one"')
  # A function two case files define (#871: watched() in views.test.sh and stall.test.sh, of other arguments): the
  # runner, conveyor/conveyor.test.sh, sources every case file before any case runs, so the later file's replaces the
  # other's for the cases of both.
  local cf=() f
  while read -r f; do [ -e "$f" ] && cf+=("$f"); done < <(git ls-files -co --exclude-standard 'conveyor/tests/*.test.sh' | grep -E '^conveyor/tests/[^/]+\.test\.sh$')
  [ ${#cf[@]} = 0 ] || bad=$bad${bad:+$'\n'}$(awk -v q="'" "$FNSCAN" "${cf[@]}" | sort)
  bad=${bad%$'\n'}
  [ -z "$bad" ] || { echo "engine area map check failed:"; echo "$bad"; return 1; }
}
# covage: how old the coverage map is (issue 527), with the map check: when it was traced (its `traced` line; the oldest,
# if a hand edit left two) and how many days ago, or that there is none or it cannot be read. It fails nothing: with
# no map, a change to functions runs by the rules after covof (callersof, then the area).
covage() {
  local a
  if [ ! -s "$COV" ]; then echo "coverage map: none ($COV); a change to a function runs the case files that name it or its callers, else its area's cases"
  elif a=$(jq -rn '[inputs | .traced? // empty] | min | select(. != null)
      | "\(.), \((now - fromdateiso8601) / 86400 | floor) days ago"' "$COV" 2>/dev/null) && [ -n "$a" ]; then
    echo "coverage map $COV: traced $a"
  else echo "coverage map $COV: cannot be read, or says not when it was traced; a change to a function runs the case files that name it or its callers, else its area's cases"; fi
}
# covrules (issue 1775): after the pick, with covage's lines, a line for each changed function of a shell file that
# names the rule that picked its tests (RULES, rulefor): `coverage map rule: <file> <function>(): covof` (the map's
# cases), `callersof` (the tests that name it or its callers) or `area` (its area's cases); `coverage map rule: <file>,
# a change outside its functions: area` when no changed function was read. None for a file textonly picked for.
covrules() {
  [ -z "$RULES" ] || awk -F'\t' '!s[$0]++ { if ($2 == "-") print "coverage map rule: " $1 ", a change outside its functions: " $3
    else print "coverage map rule: " $1 " " $2 "(): " $3 }' <<<"${RULES%$'\n'}"
}
# The pack's marks of meta-runners (issue 584): cmode, a test file's card mode (a NAME=VALUE for env; another value
# is no mark, as env would run it as a command), and wonly, a file marked whole-only.
declare -A cmode=() wonly=()
while IFS=$'\t' read -r k f v; do
  case $k in c) [[ $v =~ ^[A-Za-z_][A-Za-z0-9_]*= ]] && cmode[$f]=$v ;; w) wonly[$f]=1 ;; esac
done < <(jq -r '.test.files // {} | to_entries[] | (select(.value.cardMode | type == "string") | "c\t\(.key)\t\(.value.cardMode)"),
  (select(.value.wholeOnly == true) | "w\t\(.key)\t")' .conveyor/project.json 2>/dev/null)
METAREC=$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null)/conveyor-meta-runners
# metarunners: each meta-runner the runs saw (METAREC) or the pack marks, with its mark and the files it was seen start.
metarunners() {
  local f
  for f in $( { cut -f1 "$METAREC" 2>/dev/null; printf '%s\n' "${!cmode[@]}" "${!wonly[@]}"; } | grep . | LC_ALL=C sort -u); do
    printf 'meta-runner %s: ' "$f"
    if [ -n "${wonly[$f]:-}" ]; then printf 'wholeOnly'; elif [ -n "${cmode[$f]:-}" ]; then printf 'cardMode %s' "${cmode[$f]}"
    else printf 'no mark: a card'"'"'s test step fails it'; fi
    awk -F'\t' -v f="$f" '$1 == f { s[$2] = 1 } END { n = 0; for (i in s) n++; if (n) printf "; seen starting %d test file(s)", n }' "$METAREC" 2>/dev/null
    echo
  done
}
if [ "${1:-}" = --check ]; then mapcheck; r=$?; covage; metarunners; exit $r; fi
mapfile -t changed < <({ git diff --name-only HEAD; git ls-files --others --exclude-standard; } | sort -u)
# checks: the checks every run makes (the unit cases of the changed engine files, the map check, the test lint, no browser
# tests, no records split, shellcheck, the plugin's validate when the change touches it), printing what they
# find; exit 1 when one fails. In one-file mode in a test step they run once a tree (below), not on every run.
checks() {
local rc=0 scfiles scrc scout keep new f pv pvout moved pvhead pvmain pvp
# First, the engine's unit cases of the changed files (conveyor/unit/unit.sh, issue 1620): they call the
# functions alone and take milliseconds; the engine cases still run in the Test step. A failed case fails the checks.
[ ! -f conveyor/unit/unit.sh ] || [ ${#changed[@]} = 0 ] || bash conveyor/unit/unit.sh "${changed[@]}" || rc=1
mapcheck || rc=1
covage
# The test lint, with the map check: a test that sleeps a set time and then checks fails the run (test-lint.sh).
bash .conveyor/test-lint.sh || rc=1
# No browser tests (no-browser-tests.sh, the owner's order of 2026-11-14), with the map check too.
bash .conveyor/no-browser-tests.sh || rc=1
# No engine code splits a whole card records file in jq (no-records-split.sh, issue 1427: one such jq held the records'
# lock for minutes and stopped the belt), with the map check too.
bash .conveyor/no-records-split.sh || rc=1
# The shellcheck of each changed .sh file, with the map check too (issue 525): a warning or error (-S warning) on a
# line the change added or changed (every line of a new file) fails the run, printed with its file and line; one on a line it
# did not touch does not (the engine's files hold old ones). shellcheck runs through .conveyor/lint-shell.sh, the
# pack's lint command, which reads a file with no #! line as bash. With no shellcheck, it says so once and the run
# goes on; when shellcheck cannot check the files, the run fails with its output.
scfiles=()
for f in "${changed[@]}"; do case $f in *.sh) [ ! -f "$f" ] || scfiles+=("$f") ;; esac; done
if [ ${#scfiles[@]} -gt 0 ]; then
  scrc=0; scout=$(bash .conveyor/lint-shell.sh "${scfiles[@]}") || scrc=$?
  if [ "$scrc" = 127 ] && [ "$scout" = "lint: missing shellcheck" ]; then
    echo "shellcheck is not installed: the changed shell lines are not checked"
  elif [ "$scrc" -ge 2 ]; then
    echo "shellcheck could not check the changed shell files (exit $scrc):"; echo "$scout"; rc=1
  else
    # The lines the change added or changed, <file>:<line> one a line: of each hunk of the diff, +<start>[,<count>]
    # (count 1 when left out); of a file git does not track, <file>:all.
    keep=$({ git diff -U0 --no-color --no-ext-diff --no-prefix HEAD -- "${scfiles[@]}" | awk '/^\+\+\+ / { f = substr($0, 5) }
        /^@@ / { split($3, a, ","); n = (2 in a) ? a[2] : 1; for (i = 0; i < n; i++) print f ":" substr(a[1], 2) + i }'
      git ls-files -o --exclude-standard -- "${scfiles[@]}" | sed 's/$/:all/'; })
    new=$(printf '%s\n' "$scout" | awk -F: -v k="$keep" 'BEGIN { n = split(k, a, "\n"); for (i = 1; i <= n; i++) keep[a[i]] = 1 }
        ($1 ":" $2) in keep || ($1 ":all") in keep')
    [ -z "$new" ] || { echo "shellcheck: a new warning on a line this change added or changed:"; echo "$new"; rc=1; }
  fi
fi
# Claude Code's own check of the plugin, with the map check too (issue 604): a change to the mod (hooks/), its types
# contract (types/) or its manifest (.claude-plugin/) runs `claude plugin validate` on the worktree. An error
# ("✘ Validation failed", or a failed exit) fails the run, printed with its error lines; a warning does not, but for a
# type error HEAD's copy does not have (below). With no `claude`, the run says the check could not run and fails, so a change to the mod never lands unchecked. It is a
# static check: it runs no test file. A change to none of those paths does not run it.
pv=
# The paths both sides of a move (--no-renames): a file moved out of those directories changes the plugin too.
mapfile -t moved < <(git diff --name-only --no-renames HEAD)
for f in "${changed[@]}" "${moved[@]}"; do
  case $f in hooks/*|types/*|.claude-plugin/*) pv=$f; break ;; esac
done
if [ -n "$pv" ] && ! command -v claude > /dev/null; then
  echo "claude plugin validate: could not run, claude is not installed: $pv changed and the plugin is not checked"; rc=1
elif [ -n "$pv" ]; then
  if ! pvout=$(claude plugin validate . 2>&1) || grep -q '✘ Validation failed' <<<"$pvout"; then
    echo "claude plugin validate: the plugin fails Claude Code's check ($pv changed):"
    # Each `✘ Found <n> error(s)` block's lines, under the `Validating` line they are of, and the result line (not the
    # plugin directory's `✘ Found <n> problem` block, which does not change the result); when there is none (the
    # command failed some other way), its last lines.
    new=$(awk '/^Validating / { h = $0 } /^✘ Found [0-9]+ errors?:/ { print h; print; on = 1; s = 0; next }
      on && /^  / { print; s = 1; next } on && s && /^$/ { on = 0 } /^✘ Validation failed/ { print }' <<<"$pvout")
    if [ -n "$new" ]; then echo "$new"; else tail -n 20 <<<"$pvout"; fi
    rc=1
  fi
  # The type errors validate reports as warnings (issue 617): validate also runs on HEAD's copy of hooks/, types/ and
  # .claude-plugin/, and a type error the change has that HEAD's copy does not (or has more times than HEAD's) fails
  # the run, named with its file, line and text. Errors are matched by file, TS code and message, not line and column,
  # so moved lines are not new errors.
  pvhead=$(mktemp -d)
  if mapfile -t pvp < <(git ls-tree --name-only HEAD -- hooks types .claude-plugin) \
    && { [ ${#pvp[@]} = 0 ] || git archive HEAD -- "${pvp[@]}" | tar -x -C "$pvhead"; }; then
    pvmain=$(claude plugin validate "$pvhead" 2>&1)
    # tserrs <root> <root>: each `❯ line <l>, column <c>: error TS<n>: <text>` line as <file>\t<line>\t<TS<n>: text>,
    # the file relative to the root validate ran on (given as it is and as its physical path).
    tserrs() { awk -v a="$1/" -v b="$2/" '/^Validating / { f = $0; sub(/^Validating [^:]*: /, "", f)
        if (index(f, a) == 1) f = substr(f, length(a) + 1); else if (index(f, b) == 1) f = substr(f, length(b) + 1) }
      match($0, /^  ❯ line [0-9]+, column [0-9]+: error TS[0-9]+: /) { l = $0; sub(/^  ❯ line /, "", l); sub(/,.*/, "", l)
        t = $0; sub(/^  ❯ line [0-9]+, column [0-9]+: error /, "", t); print f "\t" l "\t" t }'; }
    new=$(awk -F'\t' 'NR == FNR { m[$1 "\t" $3]++; next } { k = $1 "\t" $3; c[k]++; line[k] = line[k] $1 ":" $2 ": error " $3 "\n" }
        END { for (k in c) if (c[k] > m[k] + 0) { printf "%s", line[k]; if (m[k]) printf "  (%d of this error here, %d in HEAD'\''s copy)\n", c[k], m[k] } }' \
      <(tserrs "$pvhead" "$(cd "$pvhead" && pwd -P)" <<<"$pvmain") <(tserrs "$PWD" "$(pwd -P)" <<<"$pvout"))
    [ -z "$new" ] || { echo "claude plugin validate: a type error this change adds, that HEAD's copy of the plugin does not have:"; echo "$new"; rc=1; }
  else
    echo "claude plugin validate: could not copy HEAD's plugin to compare its type errors ($pv changed)"; rc=1
  fi
  rm -rf "$pvhead"
fi
return $rc
}
# treekey: the commit and the tree of the worktree (its tracked and untracked files, as the checks read them), which
# the checks' result depends on; exit 1 when git cannot say.
treekey() {
  local ix h t r
  h=$(git rev-parse HEAD 2>/dev/null) && ix=$(mktemp) || return 1
  cp -p "$(git rev-parse --git-path index)" "$ix" 2>/dev/null || rm -f "$ix" # -p: as treeof() (conveyor/lib/donewhen.sh), so a same-second rewrite is not read as unchanged
  t=$(GIT_INDEX_FILE=$ix git add -A 2>/dev/null && GIT_INDEX_FILE=$ix git write-tree 2>/dev/null); r=$?
  rm -f "$ix"; [ $r = 0 ] && [ -n "$t" ] && echo "$h-$t"
}
# In one-file mode under the loop's test step (issue 422: test.fileCommand runs once for each listed file), the checks
# run once a tree: the first run keeps their output and exit in checks/<treekey>.out and .rc of the step's log folder
# (a folder: the files at its top are the step's logs), and a later run of the same tree prints them again, saying so,
# and fails as they did. A changed tree, or a key git cannot give, runs them.
# `--checks` (issue 436: the pack's test.checkCommand) runs the checks alone and exits as they do. The loop runs it
# after each session and at the start of a test step, and puts its result for the tree in the step's log folder as
# checks/<treekey>.out and .rc (conveyor/lib/donewhen.sh checkskept()): a one-file run of that tree reuses it, as below.
[ "${1:-}" != --checks ] || { checks; exit; }
rc=0; ck=
if [ -n "$ONE" ] && [ -d "${CONVEYOR_TEST_LOG:-}" ] && tk=$(treekey); then ck=$CONVEYOR_TEST_LOG/checks/$tk; fi
# The list of the selection (CONVEYOR_TEST_LIST) runs no test and ends with exit 0 whatever the checks say: it makes none.
if [ -n "${CONVEYOR_TEST_LIST:-}" ]; then :
elif [ -n "$ck" ] && [ -s "$ck.rc" ] && [ -f "$ck.out" ]; then
  cat "$ck.out"; echo "test-changed: the checks of this tree ran before this one-file run of this step (an earlier one, or the loop's test.checkCommand): their result is kept"
  [ "$(cat "$ck.rc")" = 0 ] || rc=1
elif [ -n "$ck" ] && mkdir -p "${ck%/*}" && co=$(mktemp "$ck.XXXXXX"); then
  checks > "$co" 2>&1 || rc=1
  cat "$co"; mv "$co" "$ck.out"; echo $rc > "$ck.rc.$$" && mv "$ck.rc.$$" "$ck.rc"
else
  checks || rc=1
fi
declare -A run=() area=() ccase=() allby=()
# The parts of a test file the coverage map selects (covof): npart, of the pick under way; tparts, of every pick; and
# twhole, each file a pick also selected whole, which then runs whole.
declare -A npart=() tparts=() twhole=()
oparts=
COVTESTS=
# COVSEL: set when the coverage map chose the tests of a changed file (covof, in pick), for cnarrow (below).
COVSEL=
# CFN: the changed functions of the file pick reads (covof, callersof); RULES: which rule picked each one's tests (rulefor).
CFN=; RULES=
# RANKED: the test files hooklibtests gave, one a line, most of the library's users first: the list (CONVEYOR_TEST_LIST,
# below) names them first, in this order.
RANKED=
all=
# A source file's test files that are not named after it (pick), space-separated: Rules' Undo is tested in
# dashboard-view.needs; dashboard.sh, the collector, is run by dashboard-limit and dashboard-limit-wait (through the
# collector) and dashboard-server (--restart, and the standalone Board), named after dashboard_limit.py and
# dashboard_server.py.
# The engine's foreman command (conveyor/commands/foreman.sh, outside the map: it starts conveyor/foreman/foreman.sh)
# is run by the Foreman's tests. The /units mod's views (hooks/units.tsx) are drawn by sources.ts with elements.ts, so
# units.test.tsx tests them too; its two-project fixture is the fetch's test's and the views' tests'. The area map and
# the engine's map reader (conveyor/lib/testmap.sh) are checked against each other by test-map-areas.test.sh (#150).
# askfiling() of the Foreman's lib.sh (outside the map) is tested by askfiling.test.sh alone.
declare -A TESTS_OF=([.claude/dashboard/panels/rules.js]=.claude/scripts/__tests__/dashboard-view.needs.test.mjs
  [.claude/scripts/dashboard.sh]=".claude/scripts/__tests__/dashboard-limit.test.sh .claude/scripts/__tests__/dashboard-limit-wait.test.sh
    .claude/scripts/__tests__/dashboard-server.test.sh"
  [conveyor/commands/foreman.sh]="conveyor/foreman/foreman.test.sh conveyor/foreman/foreman-session.test.sh conveyor/foreman/foreman-claims.test.sh
    conveyor/foreman/foreman-projects.test.sh"
  [hooks/sources.ts]=hooks/units.test.tsx [hooks/elements.ts]="hooks/sources.test.tsx hooks/units.test.tsx"
  [hooks/fixtures/units-two-projects.ts]="hooks/units-fetch.test.sh hooks/units.test.tsx hooks/sources.test.tsx"
  [.conveyor/engine-areas.json]=.conveyor/test-map-areas.test.sh [conveyor/lib/testmap.sh]=.conveyor/test-map-areas.test.sh
  [conveyor/foreman/lib.sh]=conveyor/tests/askfiling.test.sh)
# outside <file>: the area map keeps <file> outside (an "outside" line names it or a folder above it). No coverage map,
# callers or area narrows such a file's tests, so pick lists its TESTS_OF first (RANKED), and a card's cap of its linked
# files keeps them: bug, askfiling.test.sh, the only test of askfiling() (conveyor/foreman/lib.sh), sorted after the
# Board tests linked to lib.sh, and the cap left it out.
outside() { jq -e --arg f "$1" '.outside | any(. as $o | $f == $o or (($o | endswith("/")) and ($f | startswith($o))))' <<<"${AMAP:-null}" > /dev/null 2>&1; }
# The parts of the Board's scripts, each with its script: dashboard.sh sources its parts, and dashboard_server.py and
# dashboard_limit.py run theirs in their own namespace, so a part has its script's tests (pick): those named after the
# script, its TESTS_OF and its links (LINKS).
declare -A PART_OF=([.claude/scripts/dashboard_panels.sh]=.claude/scripts/dashboard.sh
  [.claude/scripts/dashboard_service.sh]=.claude/scripts/dashboard.sh
  [.claude/scripts/dashboard_server_base.py]=.claude/scripts/dashboard_server.py
  [.claude/scripts/dashboard_server_control.py]=.claude/scripts/dashboard_server.py
  [.claude/scripts/dashboard_server_auth.py]=.claude/scripts/dashboard_server.py
  [.claude/scripts/dashboard_server_pages.py]=.claude/scripts/dashboard_server.py
  [.claude/scripts/dashboard_server_handler.py]=.claude/scripts/dashboard_server.py
  [.claude/scripts/dashboard_limit_usage.py]=.claude/scripts/dashboard_limit.py
  [.claude/scripts/dashboard_limit_pricing.py]=.claude/scripts/dashboard_limit.py
  [.claude/scripts/dashboard_limit_requests.py]=.claude/scripts/dashboard_limit.py)
# boardtests <file>: the Board test files a change to a shared test module or to a panel reaches, read from the test
# files, not from a list (issue 544): a module beside the Board's tests (.claude/scripts/__tests__/, not a test) selects
# each test file there that imports it (`from './<module>'`), as dashboard-view.helpers.mjs, the page's fixture, is
# imported by most of them; a panel file (.claude/dashboard/panels/<id>.js) selects each one whose cases draw that
# panel: they fill its data (`panels.<id>`) or read its element (`panel(w, '<id>')`, `panel-<id>`; `<id>-<part>` for a
# panel drawn as several; `panelState.<state>('<id>')`), or they draw each panel of the helpers' list (a loop over LIST
# or OVERVIEW). A test that only names the file (`panels/<id>.js`) is not selected.
# hooklibtests <file>: the hooks' test files a change to a hook library (.claude/hooks/lib/<name>.sh) reaches when the
# coverage map selects none for it (issue 1593: a library the map does not hold yet, or a change outside its
# functions): each one that names lib/<name>.sh, or names a hook (.claude/hooks/<hook>.sh) that does. A
# library has no test of its own name and no area, so with none of these its change would run no test. A card's Test
# step runs only the files the engine lists (CONVEYOR_TEST_FILELIST, below), from the map and the links, so
# .conveyor/test-links.json links each library to these same tests (issue 1723; test-changed-hooklib.test.sh).
# Those that name the most of the library's users (the library, and each hook that names it) come first, then by name:
# they run the most of the code that calls it. The list mode (below) keeps that order (RANKED), and the engine runs the
# first of them when it caps the linked files (conveyor/lib/testlist.sh selfirst()): bug, a cap that kept the first by
# name ran tests of one hook each and left out git-safety.test.sh, whose hooks both strip-quoted.sh and
# hook-fire-log.sh serve (issue 1723).
hooklibtests() {
  local b=lib/${1##*/} h
  { grep -lF -- "$b" .claude/hooks/__tests__/*.test.* 2>/dev/null
    for h in $(grep -lF -- "$b" .claude/hooks/*.sh 2>/dev/null); do grep -lF -- "/${h##*/}" .claude/hooks/__tests__/*.test.* 2>/dev/null; done
  } | LC_ALL=C sort | uniq -c | LC_ALL=C sort -k1,1nr -k2,2 | awk '{ print $2 }'
}
boardtests() {
  local f=$1 d=.claude/scripts/__tests__ b re e='([^A-Za-z0-9_]|$)'
  local -a tests=()
  case $f in
    "$d"/*.test.*) return 0 ;;
    "$d"/*.mjs|"$d"/*.js) b=${f##*/}; re="(from|import[(]) *['\"]\\./${b//./[.]}['\"]" ;;
    .claude/dashboard/panels/*.js) b=${f##*/}; b=${b%.js}; re="panels[.]$b$e|panel[(][A-Za-z0-9_]+, *['\"\`]$b(-[a-z0-9]+)?['\"\`]|panel-$b$e|panelState[.][a-z]+[(]['\"\`]${b}['\"\`]"
      re+="|(of |[^A-Za-z0-9_.])(LIST|OVERVIEW)[.](map|filter|flatMap|forEach)[(]|of (LIST|OVERVIEW)$e" ;;
    *) return 0 ;;
  esac
  mapfile -t tests < <(git ls-files -co --exclude-standard "$d" | grep -E '[.]test[.](mjs|js|ts|tsx)$')
  [ ${#tests[@]} = 0 ] || grep -lE -- "$re" "${tests[@]}" 2>/dev/null
  return 0
}
# The test links (issue 598): a test that broke main without the card running it is run by later cards that change
# the files of the landing that broke it. .conveyor/test-links.json, {"<changed file>": ["<test file>", ...]}, written
# by the engine (conveyor/lib/mainred.sh brokeby(), testlinks()) and committed by the main-red fix card. LINKS holds
# one `<changed file><TAB><test file>` a line; a link whose test file no longer exists is dropped as it is read, and a
# file that cannot be read links nothing. Each test file a link adds to a pick (an engine case file to the engine's
# runner, as a changed one; a meta-runner by its pack mark, below) the log names: linked, `<test file><TAB><changed file>`.
LINKS=$(jq -r 'to_entries[] | .key as $k | .value | arrays[] | strings | "\($k)\t\(.)"' .conveyor/test-links.json 2>/dev/null \
  | while IFS=$'\t' read -r f t; do [ ! -f "$t" ] || printf '%s\t%s\n' "$f" "$t"; done)
declare -A linked=()
# Test names that are no source file's beside them (<folder>/<name>): dashboard-view.* test the page in
# .claude/dashboard, not dashboard.sh (owned).
NAMED=(.claude/scripts/__tests__/dashboard-view)
# owned <test file> <stem>: the test is another source file's, one named <stem>-<part>… (`_` read as `-`) that its name
# starts with, beside it, beside its __tests__ folder or in NAMED; so a change to <stem> does not select it by name.
owned() {
  local d=${1%/*} b=${1##*/} s=${2//_/-} o n
  local -a names=() near=("$d"/*)
  [ "${d##*/}" != __tests__ ] || near+=("${d%/*}"/*)
  for o in "${near[@]}"; do
    case $o in *.test.*) continue ;; esac
    [ ! -f "$o" ] || { n=${o##*/}; names+=("${n%.*}"); }
  done
  for o in "${NAMED[@]}"; do [ "${o%/*}" != "$d" ] || names+=("${o##*/}"); done
  for n in "${names[@]}"; do
    n=${n//_/-}
    case $n in "$s"-?*) case $b in "$n".*|"$n"-*) return 0 ;; esac ;; esac
  done
  return 1
}
# A text-only change (issue 512). TEXT, an awk program run with lang=sh (bash), js (the Board's JavaScript) or css, reads
# a file as its code and its texts: a `C<TAB><code>` line for each line of code, with its comments (but a `#!` line and a
# `# shellcheck` line), its blank lines and its runs of blanks left out and each text left as a mark; a
# `T<TAB><n><TAB><piece>` line for each piece of a text (split where an expansion or a line end is), n the text's place
# among the file's texts (so two texts that swap places are changed texts, issue 529); and `U` when it cannot read the
# file to its end. A text is a human message only. In bash: an echo or printf message (a printf format less its directives and
# escapes), the body of a cat heredoc with a quoted word, an argument of block() or of gh --body or --title, and a
# sentence of 3 words or more set to a name (a fixed reason, `SHUT='...'`; a list of names is code: sentence()). In the Board: a string of 2 words or more that
# is no key, compared value, class, selector, attribute or pattern. CSS has comments only. Any other quoted text is
# code: a jq, sed, awk or grep program, any other single-quoted string, a path, a redirect, a command substitution, and
# what echo or printf write into a substitution, a pipe or a file.
TEXT='function piece() { gsub(/^[ \t]+|[ \t]+$/, "", p); if (p != "") ps[++np] = p; p = "" }
function sp() { if (s != "" && substr(s, length(s)) != " ") s = s " " }
function prose(k, j, all, m, wa) {
  all = ""; for (j = 1; j <= np; j++) all = all " " ps[j]
  if (all ~ /[][|{}<>=\\^$]/) return 0
  m = 0; for (j = split(all, wa, /[ \t]+/); j > 0; j--) if (wa[j] ~ /^[^-]/ && wa[j] ~ /[A-Za-z][A-Za-z]/) m++
  return m >= k
}
# A sentence, not a list of names a command reads (a field list, or the protocols of LANEPROTO): it holds a word such as
# the, of or was, and no camelCase name.
function sentence(j, all) {
  all = " "; for (j = 1; j <= np; j++) all = all ps[j] " "
  if (all ~ /[a-z][A-Z]/) return 0
  all = tolower(all); gsub(/[,.:;!?]/, " ", all)
  return all ~ / (the|a|an|is|was|are|were|be|been|not|no|of|to|in|on|by|for|its|it|with|from|and|but|has|have|had|this|that|could|cannot|did|does|since|while|when|nothing|each|every) /
}
# Board words, not class names (all lowercase, one with a hyphen), a camelCase name or a .class or #id selector.
function words(j, all, wa, m, kebab) {
  all = ""; for (j = 1; j <= np; j++) all = all " " ps[j]
  if (all ~ /[a-z][A-Z]|(^|[ ,])[.#][A-Za-z]/) return 0
  m = split(all, wa, /[ ,]+/); kebab = 0
  for (j = 1; j <= m; j++) { if (wa[j] != "" && wa[j] !~ /^[a-z0-9-]+$/) return 1; if (wa[j] ~ /[a-z0-9]-[a-z0-9]/) kebab = 1 }
  return !kebab
}
function sclose(text, j) {
  if (text) { s = s sq sskel sq; ntx++; for (j = 1; j <= np; j++) print "T\t" ntx "\t" ps[j] } else s = s sraw
  np = 0; p = ""; sskel = ""; sraw = ""; q = 0
}
# A message holds no braces: a string of JSON or of a program that echo prints is code. Nor is it piped on or written
# to a file (what follows the string in its command, or a loop or group it ends, on its line): that output is data.
function msg(j, r) {
  for (j = 1; j <= np; j++) if (ps[j] ~ /[{}]/) return 0
  r = substr($0, i + 1); gsub(/[0-9]?>&[0-9]|[0-9]?>+ *\/dev\/null/, "", r)
  if (r ~ /(done|[})])[^;&|]*>/) return 0
  if (match(r, /;|&&|\|\||\)/)) r = substr(r, 1, RSTART - 1)
  return r !~ /[|>]/
}
function wend(x) { x = substr($0, i + 1, 1); return x == "" || x == " " || x == "\t" || x == ";" || x == ")" }
function out(x) { gsub(/\n/, "\nC\t", x); print "C\t" x }
function newcmd() { cstart = 1; cmd = ""; argn = 0; fmt = 0; prev = "" }
# A "(" or "$(" (lv: "p", "s"; "d" a double-quoted string a "$(" is in) keeps the command it is in, for after its ")".
function push(k, l) { lv = lv k; l = length(lv); sc[l] = cmd; sa[l] = argn; sf[l] = fmt; ss[l] = cstart; sv[l] = prev }
function pop(l, k) {
  l = length(lv); k = substr(lv, l); lv = substr(lv, 1, l - 1)
  if (k != "d") { cmd = sc[l]; argn = sa[l]; fmt = sf[l]; cstart = ss[l]; prev = sv[l] }
  return k
}
BEGIN { newcmd() }
lang == "sh" {
  if (inhd) {
    t = $0; if (hdtab) sub(/^\t+/, "", t)
    if (t == hd) { inhd = 0; hd = ""; print "C\t" $0; next }
    if (hdtext) { t = $0; gsub(/^[ \t]+|[ \t]+$/, "", t); print "C\tH"; if (t != "") print "T\t" ++ntx "\t" t } else print "C\tH\t" $0
    next
  }
  if (NR == 1 && /^#!/) { print "C\t" $0; next }
  if (!q && !cont) newcmd()
  # A line starts a word (issue 513: an echo at the left after `set -u` was read as an argument of set, so as code).
  if (!q) inw = 0
  cont = 0; n = length($0); i = 1
  while (i <= n) {
    c = substr($0, i, 1); d = substr($0, i + 1, 1)
    # The directives and escapes of a printf format are code; the text between them is a message.
    if (q && !codeq && ctx == "fmt" && (c == "%" || c == "\\") && d != "") {
      match(substr($0, i), c == "%" ? /^%[-+ #0-9.]*[a-zA-Z%]/ : /^\\./); if (RLENGTH < 2) RLENGTH = 2
      x = substr($0, i, RLENGTH); piece(); sskel = sskel "\001" x; sraw = sraw x; i += RLENGTH; continue
    }
    if (q == 1) {
      if (c == "\047") { piece(); sraw = sraw c; sclose((ctx == "assign" && prose(3) && sentence() && wend()) || (ctx == "fmt" && msg())); i++; continue }
      sraw = sraw c; p = p c; i++; continue
    }
    # A command substitution makes its double-quoted string code, read on as code to its ")", even over lines.
    if (q == 2 && c == "$" && d == "(") {
      if (!codeq) { s = s sraw; np = 0; p = ""; sskel = ""; sraw = ""; push("d") }
      s = s "$("; push("s"); q = 0; codeq = 0; inw = 0; newcmd(); i += 2; continue
    }
    if (q == 2 && codeq) {
      if (c == "\\") { s = s c d; i += 2; continue }
      if (c == "\"") { s = s c; q = 0; codeq = 0; pop(); i++; continue }
      s = s c; i++; continue
    }
    if (q == 2) {
      if (c == "\\") { sraw = sraw c d; if (d == "") { i++; continue }; p = p (index("$`\"\\", d) ? d : c d); i += 2; continue }
      if (c == "\"") {
        piece(); sraw = sraw c
        sclose(!sbad && (((ctx == "msg" || ctx == "fmt") && msg()) || (ctx == "assign" && prose(3) && sentence() && wend())))
        i++; continue
      }
      if (c == "`" || (c == "$" && (d == "\047" || d == "\""))) sbad = 1
      if (c == "$" && d == "{") {
        e = index(substr($0, i), "}"); x = e ? substr($0, i, e) : ""
        if (!e || substr(x, 3) ~ /[${"`\047]/) { sbad = 1; sraw = sraw c; p = p c; i++; continue }
        piece(); sskel = sskel "\001" x; sraw = sraw x; i += e; continue
      }
      if (c == "$" && d ~ /[A-Za-z_]/) { match(substr($0, i + 1), /^[A-Za-z_0-9]+/); x = substr($0, i, RLENGTH + 1); piece(); sskel = sskel "\001" x; sraw = sraw x; i += RLENGTH + 1; continue }
      if (c == "$" && d ~ /[0-9#?@*$!-]/) { piece(); sskel = sskel "\001" c d; sraw = sraw c d; i += 2; continue }
      sraw = sraw c; p = p c; i++; continue
    }
    if (c == " " || c == "\t") { sp(); inw = 0; i++; continue }
    if (c == "#" && (i == 1 || substr($0, i - 1, 1) ~ /[ \t;&|()]/)) { if (substr($0, i) ~ /^#[ \t]*shellcheck/) s = s substr($0, i); break }
    if (c == "\\") { if (d == "") { cont = 1; s = s c; i++; continue }; s = s c d; i += 2; continue }
    if (c == "<" && d == "<") {
      if (substr($0, i + 2, 1) == "<") { s = s "<<<"; inw = 0; i += 3; continue }
      r = substr($0, i)
      if (hd != "" || !match(r, /^<<-?[ \t]*(\047[A-Za-z_0-9.-]+\047|"[A-Za-z_0-9.-]+"|\\?[A-Za-z_0-9.-]+)/)) { bad = 1; s = s c; i++; continue }
      w = substr(r, 1, RLENGTH); s = s w; i += RLENGTH
      hdtab = (w ~ /^<<-/); hdq = (w ~ /[\047"]/); sub(/^<<-?[ \t]*\\?/, "", w); gsub(/[\047"]/, "", w); hd = w
      r = substr($0, i); gsub(/\|\||>&/, "", r)
      hdtext = (cmd == "cat" && hdq && s !~ />/ && r !~ /[|>]/); continue
    }
    if (c == "$" && d == "\047") {
      for (j = i + 2; j <= n && substr($0, j, 1) != "\047"; j++) if (substr($0, j, 1) == "\\") j++
      if (j > n) bad = 1
      if (!inw) { inw = 1; if (!cstart) argn++ }; s = s substr($0, i, j - i + 1); i = j + 1; continue
    }
    if (c == "$" && d == "{" && (e = index(substr($0, i), "}")) && substr($0, i + 2, e - 3) !~ /[$`"\047]/) { if (!inw) { inw = 1; if (!cstart) argn++ }; s = s substr($0, i, e); i += e; continue }
    if (c == "$" && d == "(") { if (!inw) { inw = 1; if (!cstart) argn++ }; s = s "$("; push("s"); newcmd(); inw = 0; i += 2; continue }
    if (c == "(") { s = s c; push("p"); newcmd(); inw = 0; i++; continue }
    if (c == ")" && lv != "") {
      s = s c; inw = 1
      if (pop() == "s" && substr(lv, length(lv)) == "d") { q = 2; codeq = 1 }
      i++; continue
    }
    if (index(";&|){}!", c)) { s = s c; inw = 0; if (c != "}") newcmd(); i++; continue }
    if (c == ">" || c == "<") { s = s c; inw = 0; redir = 1; i++; continue }
    if (c == "\047" || c == "\"") {
      if (!inw) { inw = 1; if (!cstart) argn++; rw = redir; redir = 0 }
      if (rw) ctx = "code"
      else if (cstart && asg && substr($0, i - 1, 1) == "=") ctx = "assign"
      # echo or printf output a substitution reads is data, not a message.
      else if (!cstart && index(lv, "s") && (cmd == "echo" || cmd == "printf")) ctx = "code"
      else if (!cstart && (cmd == "echo" || cmd == "block")) ctx = "msg"
      else if (!cstart && cmd == "printf" && argn == (fmt ? fmt : 1)) ctx = "fmt"
      else if (!cstart && cmd ~ /^gh(_[a-z]+)?$/ && (prev == "--body" || prev == "--title")) ctx = "msg"
      else ctx = "code"
      q = (c == "\047") ? 1 : 2; codeq = 0; sq = c; sraw = c; sskel = ""; np = 0; p = ""; sbad = 0; i++; continue
    }
    if (!inw) {
      inw = 1; rw = redir; redir = 0; match(substr($0, i), /^[^ \t;&|()<>"\047\\$`]+/); w = substr($0, i, RLENGTH)
      asg = (w ~ /^[A-Za-z_][A-Za-z0-9_]*(\[[^]]*\])?\+?=/)
      if (cstart && !asg && w !~ /^(if|then|do|else|elif|while|until|time|!|local|export|declare|readonly)$/) { cstart = 0; cmd = w; argn = 0; fmt = 0; prev = "" }
      else if (!cstart) { argn++; if (cmd == "printf" && argn == 1 && w == "-v") fmt = 3; prev = w }
    }
    s = s c; i++
  }
  if (q && !codeq) { piece(); sraw = sraw "\n"; sskel = sskel "\n" }
  else { sub(/[ \t]+$/, "", s); sub(/^ /, "", s); if (s != "") out(s); s = "" }
  if (hd != "") inhd = 1
  next
}
lang != "sh" {
  n = length($0); i = 1
  while (i <= n) {
    c = substr($0, i, 1); d = substr($0, i + 1, 1)
    if (bc) { if (c == "*" && d == "/") { bc = 0; i += 2 } else i++; continue }
    # A template with a ${ is code, read on as code to its } (lv: "t" the template, "e" the ${, "b" a brace in it).
    if (q == 3 && c == "$" && d == "{") {
      if (!codeq) { s = s sraw; np = 0; p = ""; sskel = ""; sraw = ""; lv = lv "t" }
      s = s "${"; lv = lv "e"; q = 0; codeq = 0; i += 2; continue
    }
    if (q == 3 && codeq) {
      if (c == "\\") { s = s c d; i += 2; continue }
      if (c == "`") { s = s c; q = 0; codeq = 0; lv = substr(lv, 1, length(lv) - 1); i++; continue }
      s = s c; i++; continue
    }
    if (q) {
      if (c == "\\") { sraw = sraw c d; p = p c d; i += 2; continue }
      if (c == sq) {
        piece(); sraw = sraw c; r = substr($0, i + 1); t = s
        sub(/^[ \t]+/, "", r); sub(/[ \t]+$/, "", t)
        # A Board label: words, not a directive, a key, a class (the second argument of h()), a compared value, a
        # selector, an attribute or a pattern.
        sclose(lang == "js" && prose(2) && words() && r !~ /^(:|[!=]=)/ && !(t ~ /(^|[;{}])$/ && r ~ /^(;|$)/) \
          && t !~ /((^|[^A-Za-z0-9_$])h\((\047[^\047]*\047|"[^"]*"), ?|(^|[^A-Za-z0-9_$])(class|className|rel|target|type|role|autocomplete|inputmode) ?[:=] ?)$/ && t !~ /([!=]=|\[|(^|[^A-Za-z0-9_])case|\.(querySelector|querySelectorAll|closest|matches|getElementById|getAttribute|setAttribute|removeAttribute|hasAttribute|toggleAttribute|addEventListener|removeEventListener|includes|startsWith|endsWith|indexOf|lastIndexOf|split|replace|replaceAll|match|matchAll|search|test|get|has|set|delete|add|remove|toggle|contains)\()$/)
        i++; continue
      }
      sraw = sraw c; p = p c; i++; continue
    }
    if (c == " " || c == "\t") { sp(); i++; continue }
    if (c == "/" && d == "*") { bc = 1; i += 2; continue }
    if (lang == "js" && c == "/" && d == "/") break
    if (lv != "" && c == "{") { s = s c; lv = lv "b"; i++; continue }
    if (lv != "" && c == "}") {
      s = s c; t = substr(lv, length(lv)); lv = substr(lv, 1, length(lv) - 1)
      if (t == "e") { q = 3; codeq = 1 }
      i++; continue
    }
    if (c == "\047" || c == "\"" || (c == "`" && lang == "js")) { q = (c == "`") ? 3 : 1; codeq = 0; sq = c; sraw = c; sskel = ""; np = 0; p = ""; i++; continue }
    if (lang == "js" && c == "/") {
      t = s; sub(/ +$/, "", t); if (t == "") t = last
      if (t == "" || t ~ /[(,=:[!&|?{};+*%~^<>-]$/ || t ~ /(^|[^A-Za-z0-9_$])(return|typeof|case|do|else|in|of|void|yield|await|delete|new)$/) {
        j = i + 1; cl = 0
        while (j <= n) { e = substr($0, j, 1); if (e == "\\") { j += 2; continue }; if (e == "[") cl = 1; else if (e == "]") cl = 0; else if (e == "/" && !cl) break; j++ }
        if (j > n) { bad = 1; s = s c; i++; continue }
        s = s substr($0, i, j - i + 1); i = j + 1; continue
      }
    }
    s = s c; i++
  }
  if (q == 3 && !codeq) { piece(); sraw = sraw "\n"; sskel = sskel "\n"; next }
  if (q == 3) next
  if (q) { bad = 1; q = 0 }
  sub(/[ \t]+$/, "", s); sub(/^ /, "", s)
  if (s != "") { out(s); last = s }
  s = ""
}
END { if (bad || q || inhd || lv != "") print "U" }'
NOTEXT=; TXFROM=HEAD; TXTO=
declare -A parse=()
# needles <piece>...: what a test that checks one of these texts holds: a piece whole, or any 3 words of it in a row (a
# test checks part of a message).
needles() { printf '%s\n' "$@" | awk 'NF < 4 { print; next } { for (i = 1; i + 2 <= NF; i++) print $i " " $(i + 1) " " $(i + 2) }'; }
# textof <lang>: the file on stdin as TEXT reads it (sh, js, css), or, for the base area's test fixtures (issue 513), a
# JSON file (json) as one code line, jq's compact form, with no texts (its values are data the cases read), so only
# its blanks can change alone; and a Markdown file (md, the test pack's card rules) as its non-blank lines, each a text
# at its place among them.
textof() {
  local x
  case $1 in
    json) x=$(jq -c .) && printf 'C\t%s\n' "$x" ;;
    md) awk '{ sub(/^[ \t]+/, ""); sub(/[ \t]+$/, "") } $0 != "" { print "T\t" ++n "\t" $0 }' ;;
    *) awk -v lang="$1" "$TEXT" ;;
  esac
}
# textonly <file>: when the change of <file> is to its texts, comments and blanks alone (its code, TEXT, the same both
# sides), its tests in place of those pick gives any other change (its area's case files, the tests named after it).
# Such a file is an engine file under conveyor/lib/ or the dispatcher conveyor/conveyor.sh (bash, or JSON or Markdown
# as textof reads them; issue 513: so a text change to the dispatcher or to a base file, portable.sh, paths.sh or a
# test pack fixture, runs no "all" area's whole engine test) or a
# Board file under .claude/dashboard/ (JavaScript or CSS, not vendor/). The change is from TXFROM to TXTO (a commit, or
# the worktree when empty): the card's whole change, HEAD to the worktree, or what main changed under it (the list's `main` lines), from the main of its last run to HEAD. Its
# tests: its parse check (parse), into area each case file under conveyor/tests/ and into run each other test file
# that holds an old or new text that changed (needles), and, as pick gives them, the tests of each engine or Board
# source file that holds an old one whole: code there may match the text (app.js compares step names). A change to
# comments or blanks alone selects its parse check alone. It fails, and pick goes on as for any change, when the file
# is none of those or cannot be read either side, TEXT cannot read it or its code changed, a changed text is too short
# to look for, or a shared file of the cases (a .sh under conveyor/tests/ that is no case file) holds one.
textonly() {
  local f=$1 lang a b
  [ -n "$TXFROM" ] || return 1
  case $f in
    conveyor/lib/*.sh|conveyor/conveyor.sh) lang='sh' ;;
    conveyor/lib/*.json) lang=json ;;
    conveyor/lib/*.md) lang=md ;;
    .claude/dashboard/vendor/*) return 1 ;;
    .claude/dashboard/*.js) lang=js ;;
    .claude/dashboard/*.css) lang=css ;;
    *) return 1 ;;
  esac
  a=$(git show "$TXFROM:$f" 2>/dev/null) && a=$(textof $lang <<<"$a") || return 1
  if [ -n "$TXTO" ]; then b=$(git show "$TXTO:$f" 2>/dev/null) && b=$(textof $lang <<<"$b") || return 1
  else b=$(textof $lang < "$f") || return 1; fi
  ! grep -qx U <<<"$a"$'\n'"$b" && [ "$(grep -v '^T' <<<"$a")" = "$(grep -v '^T' <<<"$b")" ] || return 1
  texttests "$a" "$b" || return 1
  parse[$f]=1
}
# CODE, an awk program (lang: sh, py, yml, js, css or html): the lines of a file that are not comment or blank lines, as
# they are (commentonly). A comment line: in shell, Python and YAML a line that starts with `#` (never the #! first
# line, nor a shell file's `# shellcheck` directive, which changes what the shellcheck of the run checks); in JS and TS
# a line that starts with `//` (not in CSS, where `//` is no comment and drops the next rule); in JS, TS and CSS a line
# inside `/* */`, and in HTML inside `<!-- -->`, with nothing else on it. A line of a shell heredoc, of a Python triple-quoted string or of a JS template string
# is data, and counted as code, though it starts with `#` or `//` or is blank. A block comment that opens after code on
# a line is not followed: its next lines count as code.
CODE='function heredoc(x) {
  x = $0; gsub(/<<</, "", x)
  if (match(x, /<<-?[ \t]*[\047"\\]?[A-Za-z_0-9.-]+/)) { x = substr(x, RSTART, RLENGTH); hdt = (x ~ /^<<-/); sub(/^<<-?[ \t]*[\047"\\]?/, "", x); hd = x }
}
function blk(o, c, s, i) {
  s = $0
  while (1) {
    if (inb) { i = index(s, c); if (!i) return 1; s = substr(s, i + length(c)); inb = 0; continue }
    sub(/^[ \t]+/, "", s)
    if (s == "" || (lang == "js" && substr(s, 1, 2) == "//")) return 1
    if (substr(s, 1, length(o)) != o) return 0
    s = substr(s, length(o) + 1); inb = 1
  }
}
lang == "sh" && hd != "" { print; x = $0; if (hdt) sub(/^\t+/, "", x); if (x == hd) hd = ""; next }
q != "" { print; x = $0; gsub(/\\./, "", x); if (gsub(q, "", x) % 2) q = ""; next }
NR == 1 && /^#!/ { print; next }
lang == "sh" && /^[ \t]*#[ \t]*shellcheck[ \t]/ { print; next }
lang ~ /^(sh|py|yml)$/ && /^[ \t]*(#|$)/ { next }
lang ~ /^(js|css)$/ && blk("/*", "*/") { next }
lang == "html" && blk("<!--", "-->") { next }
{ print; x = $0; gsub(/\\./, "", x)
  if (lang == "sh") heredoc()
  else if (lang == "py") { if (gsub(/"""/, "", x) % 2) q = "\"\"\""; else if (gsub(/\047\047\047/, "", x) % 2) q = "\047\047\047" }
  else if (lang == "js" && gsub(/`/, "", x) % 2) q = "`" }'
# commentonly <file> (issue 640): when the change of <file> (TXFROM to TXTO, as textonly reads it) adds, removes or
# edits its comment and blank lines alone (CODE the same both sides): it selects no test, only a shell file's parse
# check (bash -n), and the run says so (conly). It fails, and pick goes on as for any change, for another file type
# (Markdown, JSON and the rest), a file new or gone, or one whose content is the same (a change of its mode alone).
declare -A conly=()
commentonly() {
  local f=$1 lang a b
  [ -n "$TXFROM" ] || return 1
  case $f in
    *.sh|*.bash) lang='sh' ;;
    *.py) lang=py ;;
    *.yml|*.yaml) lang=yml ;;
    *.js|*.mjs|*.ts|*.tsx) lang=js ;;
    *.css) lang=css ;;
    *.html) lang=html ;;
    *) return 1 ;;
  esac
  # Each side ends in a `.` that is cut after, so that blank lines at the end, which $(...) drops, are compared too.
  a=$(git show "$TXFROM:$f" 2>/dev/null && echo .) || return 1
  if [ -n "$TXTO" ]; then b=$(git show "$TXTO:$f" 2>/dev/null && echo .) || return 1
  else [ -f "$f" ] && b=$(cat -- "$f" && echo .) || return 1; fi
  a=${a%.} b=${b%.}
  [ "$a" != "$b" ] && [ "$(awk -v lang=$lang "$CODE" <<<"$a")" = "$(awk -v lang=$lang "$CODE" <<<"$b")" ] || return 1
  conly[$f]=1; [ $lang != sh ] || parse[$f]=1
}
# texttests <old> <new>: the tests of a change to texts alone, from the file's two sides as TEXT reads them (the code
# the same): as textonly says. It fails, having chosen none, when a changed text is too short to look for or a shared
# file of the cases holds one.
texttests() {
  local a=$1 b=$2 t
  local -a old new tests src hold
  # The pieces of the texts that changed, old and new; one under 6 characters is too short to look for. Counted, not
  # as sets, and each with its text's place (the code is the same both sides, so a place is the same text): a piece
  # that one message loses and another keeps (`could not be read` after a name) is an old one too, and so are two
  # texts that swap places.
  mapfile -t old < <(LC_ALL=C comm -23 <(grep '^T' <<<"$a" | LC_ALL=C sort) <(grep '^T' <<<"$b" | LC_ALL=C sort) | cut -f3- | LC_ALL=C sort -u)
  mapfile -t new < <(LC_ALL=C comm -13 <(grep '^T' <<<"$a" | LC_ALL=C sort) <(grep '^T' <<<"$b" | LC_ALL=C sort) | cut -f3- | LC_ALL=C sort -u)
  for t in "${old[@]}" "${new[@]}"; do [ ${#t} -ge 6 ] || return 1; done
  if [ $((${#old[@]} + ${#new[@]})) -gt 0 ]; then
    mapfile -t tests < <(git ls-files -co --exclude-standard '*.test.sh' '*.test.mjs' '*.test.py' 'conveyor/tests/*.sh' | grep -vx conveyor/conveyor.test.sh)
    mapfile -t hold < <(grep -lF -f <(needles "${old[@]}" "${new[@]}") -- "${tests[@]}" 2>/dev/null < /dev/null)
    for t in "${hold[@]}"; do case $t in conveyor/tests/*.test.sh) ;; conveyor/tests/*) return 1 ;; esac; done
    for t in "${hold[@]}"; do case $t in conveyor/tests/*) area[$t]=1 ;; *) run[$t]=1 ;; esac; done
  fi
  [ ${#old[@]} -gt 0 ] || return 0
  # Code that matches a text holds it whole (app.js compares a step name), so an old piece whole is looked for here.
  mapfile -t src < <(git ls-files -co --exclude-standard conveyor .claude/dashboard .claude/scripts \
    | grep -vE '^conveyor/tests/|[.]test[.]|/__tests__/|^[.]claude/dashboard/vendor/|[.]md$')
  mapfile -t hold < <(grep -lF -f <(printf '%s\n' "${old[@]}") -- "${src[@]}" 2>/dev/null < /dev/null)
  [ ${#hold[@]} = 0 ] || NOTEXT=1 pick "${hold[@]}"
}
# CASES, an awk program, reads an engine case file as its cases and its shared part: a `K<TAB><case><TAB><body>` line
# for each case, the function t_<case> as the runner names it (conveyor.test.sh), one line `t_<case>() { ...; }` or
# from its `t_<case>() {` line to the first line that is `}`, its lines joined by \001; an `S<TAB><line>` line for each
# other line (its setup, helpers and top-level lines); and `U`, and no more, when a case is of no such shape, is defined
# twice or does not end. A line in a case is indented or blank, or a line of a heredoc it starts (to the heredoc's
# word), so a line at the left (`helper() {`, a comment) after a case read wrongly as not ended is U, not taken into the
# case: the file runs whole. A one-line case may end in a redirect (`...; } 2>/dev/null`).
CASES='function bad() { print "U"; u = 1; exit }
function heredoc(x) {
  x = $0; gsub(/<<</, "", x)
  if (match(x, /<<-?[ \t]*[\047"\\]?[A-Za-z_0-9.-]+/)) { x = substr(x, RSTART, RLENGTH); hdt = (x ~ /^<<-/); sub(/^<<-?[ \t]*[\047"\\]?/, "", x); hd = x }
}
c != "" {
  if (hd != "") { x = $0; if (hdt) sub(/^\t+/, "", x); if (x == hd) hd = ""; b = b "\001" $0; next }
  if ($0 ~ /^}([ \t]*[0-9]*>+[ \t]*[^ \t;&|]+)*[ \t]*(#.*)?$/) { print "K\t" c "\t" b; c = ""; next }
  if ($0 !~ /^([ \t]|$)/) bad()
  b = b "\001" $0; heredoc(); next
}
/^t_[a-z0-9]*\(/ {
  if ($0 !~ /^t_[a-z0-9]+\(\) \{/) bad()
  n = substr($0, 3, index($0, "(") - 3); if (n in seen) bad(); seen[n] = 1
  if ($0 ~ /[;&] *\}([ \t]*[0-9]*>+[ \t]*[^ \t;&|]+)*[ \t]*(#.*)?$/) print "K\t" n "\t" $0; else { c = n; b = $0; heredoc() }
  next
}
{ print "S\t" $0 }
END { if (!u && c != "") print "U" }'
# casesof <case file>: when the change of <file> (TXFROM to TXTO, as textonly reads it) leaves its shared part (CASES)
# the same but for comments and blanks (its code and texts, TEXT, the same both sides), its changed and added cases,
# into ccase (a removed case runs nothing). It fails, and the file runs whole, when the file cannot be read either side,
# CASES or TEXT cannot read it, or its shared part changed: a helper or setup line that the cases share.
casesof() {
  local f=$1 a b sa sb n
  [ -n "$TXFROM" ] || return 1
  a=$(git show "$TXFROM:$f" 2>/dev/null) && a=$(awk "$CASES" <<<"$a") || return 1
  if [ -n "$TXTO" ]; then b=$(git show "$TXTO:$f" 2>/dev/null) && b=$(awk "$CASES" <<<"$b") || return 1
  else b=$(awk "$CASES" "$f") || return 1; fi
  ! grep -qx U <<<"$a"$'\n'"$b" || return 1
  sa=$(awk 'sub(/^S\t/, "")' <<<"$a" | awk -v lang=sh "$TEXT") && sb=$(awk 'sub(/^S\t/, "")' <<<"$b" | awk -v lang=sh "$TEXT") || return 1
  ! grep -qx U <<<"$sa"$'\n'"$sb" && [ "$sa" = "$sb" ] || return 1
  while IFS= read -r n; do [ -z "$n" ] || ccase[$n]=1; done \
    < <(LC_ALL=C comm -13 <(grep '^K' <<<"$a" | LC_ALL=C sort) <(grep '^K' <<<"$b" | LC_ALL=C sort) | cut -f2)
}
# areaof <engine file>: its area's case files into area, or all when its tests are "all" (and the area's name into
# allby: why the runner runs).
areaof() {
  local a t
  while IFS=$'\t' read -r a t; do if [ "$t" = all ]; then all=1; allby[$a]=1; else area[conveyor/tests/$t]=1; fi; done \
    < <(jq -r --arg f "$1" '.areas | to_entries[] | select(.value.files | index($f)) | .key as $k | .value.tests
      | if . == "all" then [$k, "all"] else .[] | [$k, .] end | @tsv' <<<"$AMAP")
}
# callers <ERE> <file> (issue 514): the engine test of each file of the map and case file under conveyor/tests/, but
# <file>, with a line that matches <ERE> and is no comment line: a case file into area, any other file's area
# (areaof: so conveyor/tests/lib.sh, which every case runs through, runs the whole engine test).
callers() {
  local t
  local -a files
  mapfile -t files < <({ jq -r '.areas[].files[]' <<<"$AMAP"; git ls-files -co --exclude-standard 'conveyor/tests/*.test.sh'; } \
    | LC_ALL=C sort -u | while read -r t; do [ "$t" = "$2" ] || [ ! -f "$t" ] || echo "$t"; done)
  [ ${#files[@]} -gt 0 ] || return 0
  while read -r t; do case $t in conveyor/tests/*.test.sh) area[$t]=1 ;; *) areaof "$t" ;; esac; done \
    < <(awk -v p="$1" '!/^[ \t]*#/ && $0 ~ p { print FILENAME; nextfile }' "${files[@]}" < /dev/null)
}
# callersof <file> (issue 1775): when the change of an engine shell file (a .sh file of the map under conveyor/, not
# under conveyor/tests/; TXFROM to TXTO) edits, adds or removes its functions alone (FUNCS; its other lines the same
# but for comments and blanks, TEXT), the test files that name a changed function or a function that calls one (one
# hop, no more): each case file under conveyor/tests/ into area, each test file under .claude/scripts/__tests__/ and
# .claude/hooks/__tests__/ into run; and when the changed function, a caller, or a line outside the functions is in a
# command script (conveyor/commands/), the tests cmdtests gives for that script's commands (no test names its entry
# function, as releaseprep() of release-prep.sh: they run `loop release-prep`). A caller is a function of an engine
# shell file of the map with a line that names a changed function as a word and is no comment. It leaves the changed functions'
# names in CFN once it has read them. It fails, and the rules after it pick (the file's area), when the file cannot be
# read either side, a line outside its functions changed, a code line outside the functions of the file, or any code
# line of conveyor/conveyor.sh or conveyor/lib/portable.sh, names a changed function (it runs at start-up), a line
# outside the functions of another engine file (but a command script) names one, a command script that names one has
# no command, an engine file that names one cannot be read (FUNCS), or the changed functions have more than 25 callers
# (a helper that many functions use).
callersof() {
  local f=$1 a b sa sb st w re t k n c
  local -a fn=() files=() hit=() cmds=()
  local -A who=() scr=()
  CFN=
  case $f in conveyor/tests/*) return 1 ;; conveyor/*.sh) ;; *) return 1 ;; esac
  [ -n "$TXFROM" ] && jq -e --arg f "$f" 'any(.areas[].files[]; . == $f)' <<<"$AMAP" > /dev/null || return 1
  a=$(git show "$TXFROM:$f" 2>/dev/null) && a=$(awk "$FUNCS" <<<"$a") || return 1
  if [ -n "$TXTO" ]; then b=$(git show "$TXTO:$f" 2>/dev/null) && b=$(awk "$FUNCS" <<<"$b") || return 1
  else b=$(awk "$FUNCS" "$f") || return 1; fi
  ! grep -qx U <<<"$a"$'\n'"$b" || return 1
  # The functions changed, added or removed: a K line on one side alone.
  mapfile -t fn < <(grep '^K' <<<"$a"$'\n'"$b" | LC_ALL=C sort | uniq -u | cut -f2 | LC_ALL=C sort -u)
  [ ${#fn[@]} -gt 0 ] || return 1
  CFN=${fn[*]}
  sa=$(awk 'sub(/^S\t/, "")' <<<"$a" | awk -v lang=sh "$TEXT") && sb=$(awk 'sub(/^S\t/, "")' <<<"$b" | awk -v lang=sh "$TEXT") || return 1
  ! grep -qx U <<<"$sa"$'\n'"$sb" && [ "$sa" = "$sb" ] || return 1
  w=$(IFS='|'; echo "${fn[*]}"); re="(^|[^A-Za-z0-9_])($w)([^A-Za-z0-9_]|\$)"
  st=$({ textof sh < conveyor/conveyor.sh && textof sh < conveyor/lib/portable.sh; } 2>/dev/null) && ! grep -qx U <<<"$st" || return 1
  ! grep '^C' <<<"$sb"$'\n'"$st" | grep -qE "$re" || return 1
  # The callers: of each engine shell file that names one, its functions with a line that is no comment and names one
  # (K), and S when a line outside its functions does.
  mapfile -t files < <(jq -r '.areas[].files[] | select(test("^conveyor/.*[.]sh$"))' <<<"$AMAP" | LC_ALL=C sort -u \
    | while read -r t; do [ ! -f "$t" ] || echo "$t"; done)
  mapfile -t hit < <(grep -lwE -- "$w" "${files[@]}" 2>/dev/null < /dev/null)
  # A command script's functions run by its commands (scr): the changed ones, when the file is one, and its callers.
  [[ $f != conveyor/commands/*.sh ]] || scr[$f]=1
  for t in "${hit[@]}"; do
    c=$(awk "$FUNCS" "$t") && ! grep -qx U <<<"$c" || return 1
    while IFS=$'\t' read -r k n; do
      if [ "$k" = K ]; then { [ "$t" = "$f" ] && [[ " $CFN " == *" $n "* ]]; } || who[$n]=1
      elif [ "$t" != "$f" ] && [[ $t != conveyor/commands/*.sh ]]; then return 1; fi
      [[ $t != conveyor/commands/*.sh ]] || scr[$t]=1
    done < <(awk -v re="$re" '/^K\t/ { n = substr($0, 3); sub(/\t.*/, "", n); k = split(substr($0, length(n) + 4), l, "\001")
        sub(/^(function[ \t]+)?[A-Za-z_][A-Za-z0-9_]*[ \t]*\(\)/, "", l[1])
        for (i = 1; i <= k; i++) if (l[i] !~ /^[ \t]*#/ && l[i] ~ re) { print "K\t" n; break } }
      /^S\t/ && !s { x = substr($0, 3); if (x !~ /^[ \t]*#/ && x ~ re) { print "S\t-"; s = 1 } }' <<<"$c")
  done
  [ ${#who[@]} -le 25 ] || return 1
  for t in "${!scr[@]}"; do
    n=$(awk -v s="${t##*/}" '$1 == "cmd" && $3 == s { print $2 }' conveyor/conveyor.sh) && [ -n "$n" ] || return 1
    mapfile -t -O "${#cmds[@]}" cmds <<<"$n"
  done
  [ ${#who[@]} = 0 ] || w+="|$(IFS='|'; echo "${!who[*]}")"
  mapfile -t files < <(git ls-files -co --exclude-standard 'conveyor/tests/*.test.sh' '.claude/scripts/__tests__/*' \
    '.claude/hooks/__tests__/*' | grep -E '[.]test[.][a-z]+$' | while read -r t; do [ ! -f "$t" ] || echo "$t"; done)
  [ ${#files[@]} = 0 ] || while read -r t; do case $t in conveyor/tests/*) area[$t]=1 ;; *) run[$t]=1 ;; esac; done \
    < <(awk -v p="(^|[^A-Za-z0-9_])($w)([^A-Za-z0-9_]|\$)" '!/^[ \t]*#/ && $0 ~ p { print FILENAME; nextfile }' "${files[@]}" < /dev/null)
  [ ${#cmds[@]} = 0 ] || cmdtests "${cmds[@]}"
  parse[$f]=1
}
# TABLE, an awk program, reads conveyor/conveyor.sh as its command table and the rest: a `K<TAB><command><TAB><line>`
# line for each line of the table (`cmd <command> <script> <usage>`, at the left: issue 530), and an `S<TAB><line>`
# line for each other line; and `U` when it has no table line or names a command twice.
TABLE='/^cmd / && $2 ~ /^[a-z][a-z-]*$/ { if ($2 in seen) { print "U"; u = 1; exit } seen[$2] = 1; n++; print "K\t" $2 "\t" $0; next }
{ print "S\t" $0 }
END { if (!u && !n) print "U" }'
# usages: of K lines (TABLE) on stdin, a line `T<TAB>K<command><TAB><usage>` for each line's usage text (the quoted
# text that ends it; none for `-`).
usages() { awk -F'\t' 'index($3, "\047") { u = substr($3, index($3, "\047") + 1); sub(/\047[ \t]*$/, "", u); print "T\tK" $2 "\t" u }'; }
# cmdsof <file> (issue 514): when the change of conveyor/conveyor.sh (TXFROM to TXTO) is to lines of its command table
# alone (TABLE: a line added, removed or changed), the rest the same but for comments, blanks and texts (TEXT), the
# engine test of the files that run those commands (callers): a line with `conveyor.sh <command>` or
# `conveyor.sh" <command>`, or `"$X" <command>` where an engine file or a file under conveyor/tests/ sets X to a path
# that ends in conveyor.sh, or with the command after a function that a file under conveyor/tests/ defines to run
# conveyor.sh with its arguments (`loop <command>`, or `loop <main> <command>`); and the tests texttests gives for
# the texts that changed: those of the rest, and the tests that hold a usage text of a changed line (usages), a part of
# the usage message. A command conveyor/tests/lib.sh runs (setup's `loop state-dir`) runs the whole engine test. It
# fails, and the file's area ("all") runs, when the file cannot be read either side, TABLE or TEXT cannot read it, a
# code line outside the table changed, or texttests fails (a changed usage text under 6 characters).
cmdsof() {
  local f=$1 a b sa sb ka kb
  local -a cs
  [ "$f" = conveyor/conveyor.sh ] && [ -n "$TXFROM" ] || return 1
  a=$(git show "$TXFROM:$f" 2>/dev/null) && a=$(awk "$TABLE" <<<"$a") || return 1
  if [ -n "$TXTO" ]; then b=$(git show "$TXTO:$f" 2>/dev/null) && b=$(awk "$TABLE" <<<"$b") || return 1
  else b=$(awk "$TABLE" "$f") || return 1; fi
  ! grep -qx U <<<"$a"$'\n'"$b" || return 1
  sa=$(awk 'sub(/^S\t/, "")' <<<"$a" | awk -v lang=sh "$TEXT") && sb=$(awk 'sub(/^S\t/, "")' <<<"$b" | awk -v lang=sh "$TEXT") || return 1
  ! grep -qx U <<<"$sa"$'\n'"$sb" && [ "$(grep -v '^T' <<<"$sa")" = "$(grep -v '^T' <<<"$sb")" ] || return 1
  mapfile -t cs < <(grep '^K' <<<"$a"$'\n'"$b" | LC_ALL=C sort | uniq -u | cut -f2 | LC_ALL=C sort -u)
  [ ${#cs[@]} -gt 0 ] || return 1
  # The usage texts that changed, old and new (a command's line added, removed, or changed in its usage text), go to
  # texttests as new texts, each in a place of its own: the tests that hold one run, and no source file is looked for
  # that holds an old one (the command's own files run as its callers; an old text the new one extends, `retry <issue>`
  # of `retry <issue> [--now]`, would find conveyor.sh itself, and the whole test).
  ka=$(LC_ALL=C comm -23 <(grep '^K' <<<"$a" | LC_ALL=C sort) <(grep '^K' <<<"$b" | LC_ALL=C sort) | usages)
  kb=$(LC_ALL=C comm -13 <(grep '^K' <<<"$a" | LC_ALL=C sort) <(grep '^K' <<<"$b" | LC_ALL=C sort) | usages)
  ka=$(LC_ALL=C comm -3 <(grep . <<<"$ka" | LC_ALL=C sort) <(grep . <<<"$kb" | LC_ALL=C sort) | awk -F'\t' '{ print "T\tK" NR "\t" $NF }')
  texttests "$sa" "$sb${ka:+$'\n'$ka}" || return 1
  cmdtests "${cs[@]}"
  parse[$f]=1
}
# cmdtests <command>... (issue 514): the engine test of the files that run those commands of conveyor/conveyor.sh
# (callers, but conveyor.sh's own table), as cmdsof reads them; callersof uses it for a command script that calls a
# changed function.
cmdtests() {
  local w v t p
  w=$(sed -nE 's/^[ \t]*([A-Za-z_][A-Za-z0-9_]*)\(\) *\{.*conveyor[.]sh"? +"\$(@|\{@:2\})".*/\1/p' conveyor/tests/*.sh 2>/dev/null \
    | LC_ALL=C sort -u | paste -sd '|' -)
  v=$({ jq -r '.areas[].files[]' <<<"$AMAP"; git ls-files -co --exclude-standard 'conveyor/tests/*.sh'; } 2>/dev/null \
    | LC_ALL=C sort -u | while read -r t; do [ ! -f "$t" ] || echo "$t"; done \
    | xargs -r sed -nE 's/.*(^|[^A-Za-z0-9_])([A-Za-z_][A-Za-z0-9_]*)="?[^ ;"]*conveyor[.]sh"?([ \t;)]|$).*/\2/p' 2>/dev/null \
    | LC_ALL=C sort -u | paste -sd '|' -)
  p='conveyor[.]sh"?'; [ -z "$v" ] || p="($p|\"?[\$][{]?($v)[}]?\"?)"
  [ -z "$w" ] || p="($p|(^|[^A-Za-z0-9_-])($w)([ \t]+[^ \t]+)?)"
  callers "${p}[ \t]+($(IFS='|'; echo "$*"))([^A-Za-z0-9_-]|\$)" conveyor/conveyor.sh
}
# keysof <file> (issue 530): when the change of conveyor/lib/control-defaults.json (TXFROM to TXTO), the control
# record's default for each key, adds, removes or changes keys (at the top, or in rules), the engine test of the code
# that reads one (callers: a line with `.<key>` or `"<key>"`) and each case file under conveyor/tests/ that reads the
# file; not the whole area of control.sh, which reads the file whole for any key. It fails, and the file's area runs,
# when either side cannot be read as a JSON object, no key changed, or a changed key is no plain name.
keysof() {
  local f=$1 a b k t
  [ "$f" = conveyor/lib/control-defaults.json ] && [ -n "$TXFROM" ] || return 1
  a=$(git show "$TXFROM:$f" 2>/dev/null | jq -ce 'objects') || return 1
  if [ -n "$TXTO" ]; then b=$(git show "$TXTO:$f" 2>/dev/null | jq -ce 'objects') || return 1
  else b=$(jq -ce 'objects' "$f" 2>/dev/null) || return 1; fi
  k=$(jq -rn --argjson a "$a" --argjson b "$b" '($a + $b | keys[]) as $k
    | if $k == "rules" and ($a.rules | type) == "object" and ($b.rules | type) == "object"
      then ($a.rules + $b.rules | keys[]) as $r | select($a.rules[$r] != $b.rules[$r]) | $r
      else select($a[$k] != $b[$k]) | $k end' | LC_ALL=C sort -u) && [ -n "$k" ] || return 1
  ! grep -qvE '^[A-Za-z_][A-Za-z0-9_]*$' <<<"$k" || return 1
  k=$(paste -sd '|' - <<<"$k")
  callers "([.]($k)([^A-Za-z0-9_]|\$)|\"($k)\")" "$f"
  for t in $(git ls-files -co --exclude-standard 'conveyor/tests/*.test.sh'); do
    [ ! -f "$t" ] || ! grep -q 'control-defaults[.]json' "$t" || area[$t]=1
  done
  parse[$f]=1
}
# covof <file> (issue 527): when the change of a shell file (TXFROM to TXTO) edits or removes its functions alone (FUNCS;
# its other lines the same but for comments and blanks, TEXT), and the coverage map ($COV) holds each of them with at
# least one case: the cases it lists for them. The map's row of a function stands for it whatever its sum: one changed
# since the trace runs the cases that ran it then. A function the change adds stands as the functions of the changed
# file that call it, up to 3 calls away (an added caller of an added function looks one call further). An engine case
# into ccase (the runner's cases), a part of a test file into npart, a whole test file into run. It leaves the changed
# functions' names in CFN once it has read them. It fails, and the rules after it pick, when there is no map or it cannot be read, the file cannot be read either side, a line outside
# its functions changed, an added function has no caller the map can stand on, or the map lacks one, lists no case for one,
# names a unit or test file number twice or one it does not name, or names a test file, an engine case or a part
# (partok) that is not there now.
covof() {
  local f=$1 a b sa sb sel t c ac k n body x y z
  local -a fn front next
  local -A old=() kb=() use=() seen=()
  [ -n "$TXFROM" ] && [ -s "$COV" ] || return 1
  a=$(git show "$TXFROM:$f" 2>/dev/null) && a=$(awk "$FUNCS" <<<"$a") || return 1
  if [ -n "$TXTO" ]; then b=$(git show "$TXTO:$f" 2>/dev/null) && b=$(awk "$FUNCS" <<<"$b") || return 1
  else b=$(awk "$FUNCS" "$f") || return 1; fi
  ! grep -qx U <<<"$a"$'\n'"$b" || return 1
  sa=$(awk 'sub(/^S\t/, "")' <<<"$a" | awk -v lang=sh "$TEXT") && sb=$(awk 'sub(/^S\t/, "")' <<<"$b" | awk -v lang=sh "$TEXT") || return 1
  ! grep -qx U <<<"$sa"$'\n'"$sb" && [ "$sa" = "$sb" ] || return 1
  mapfile -t fn < <(grep '^K' <<<"$a"$'\n'"$b" | LC_ALL=C sort | uniq -u | cut -f2 | LC_ALL=C sort -u)
  [ ${#fn[@]} -gt 0 ] || return 1
  CFN=${fn[*]}
  # The functions TXFROM has (old) and the bodies of those the change leaves (kb). A function TXFROM has stands for
  # itself; an added one, for the functions TXFROM has that call it in kb, a call being its name as a whole word.
  while IFS=$'\t' read -r k n body; do [ "$k" != K ] || old[$n]=1; done <<<"$a"
  while IFS=$'\t' read -r k n body; do [ "$k" != K ] || kb[$n]=$body; done <<<"$b"
  for x in "${fn[@]}"; do
    [ -z "${old[$x]:-}" ] || { use[$x]=1; continue; }
    front=("$x"); seen=([$x]=1); z=
    for _ in 1 2 3; do
      next=()
      for y in "${!kb[@]}"; do
        [ -z "${seen[$y]:-}" ] || continue
        for n in "${front[@]}"; do
          [[ ${kb[$y]} =~ (^|[^A-Za-z0-9_])$n([^A-Za-z0-9_]|$) ]] || continue
          seen[$y]=1
          if [ -n "${old[$y]:-}" ]; then use[$y]=1; z=1; else next+=("$y"); fi
          break
        done
      done
      [ ${#next[@]} -gt 0 ] || break
      front=("${next[@]}")
    done
    [ -n "$z" ] || return 1
  done
  # The map's form (coverage.sh): its test files and units by number, each number named once (else two maps were
  # merged and no number can be trusted), and each function's rows with the numbers of the units that ran it.
  sel=$(jq -rn --arg f "$f" --arg s "$(printf '%s\n' "${!use[@]}")" '[inputs | objects] as $m | [$s | split("\n")[] | select(. != "")] as $fs
    | [$m[] | select(has("testfile") and has("path"))] as $tf | [$m[] | select(has("unit"))] as $un
    | (reduce $tf[] as $x ({}; .[$x.testfile | tostring] = $x.path)) as $p
    | (reduce $un[] as $x ({}; .[$x.unit | tostring] = [$p[$x.testfile | tostring], $x.case // ""])) as $u
    | [$m[] | select(.file == $f and has("sum"))] as $rows
    | if ($p | length) == ($tf | length) and ($u | length) == ($un | length)
        and all($fs[]; . as $n | [$rows[] | select(.fn == $n)] | any((.units // []) | length > 0))
      then [$rows[] | select(.fn as $n | any($fs[]; . == $n)) | .units[] | $u[tostring]]
        | if all(.[]; . != null and .[0] != null) then .[] | @tsv else error("not held") end
      else error("not held") end' "$COV" 2>/dev/null) && [ -n "$sel" ] || return 1
  ac=$(allcases)
  while IFS=$'\t' read -r t c; do
    [ -f "$t" ] || return 1
    if [ "$t" = conveyor/conveyor.test.sh ]; then [ -n "$c" ] && grep -qxF -- "$c" <<<"$ac" || return 1
    elif [ -n "$c" ]; then partok "$t" "$c" || return 1; fi
  done <<<"$sel"
  while IFS=$'\t' read -r t c; do
    if [ -z "$c" ]; then run[$t]=1; elif [ "$t" = conveyor/conveyor.test.sh ]; then ccase[$c]=1; else npart[$t]+=$'\n'$c; fi
  done <<<"$sel"
  [ -n "$COVTESTS" ] || COVTESTS=$(jq -rn '[inputs | objects | select(has("testfile") and has("path")) | .path] | unique[]' "$COV")
  parse[$f]=1
}
# rulefor <file> <rule> (issue 1775): a line `<file><TAB><function><TAB><rule>` in RULES for each changed function
# (CFN), `-` for none: which rule picked the tests of each (covof, callersof or area), which the run prints.
rulefor() {
  local n
  for n in ${CFN:--}; do RULES+=$1$'\t'$n$'\t'$2$'\n'; done
}
# The tests of the changed files <file>...: into run (test files), area (engine case files) and all (the whole engine
# test), then (but in textonly's pick) pick's cases (the engine runner's cases, none for all of them) and run[the runner].
pick() {
local f t s named stem dir cov cal cpart helpers of nmap
[ -n "$NOTEXT" ] || npart=()
for f; do
  # A change to its comment and blank lines alone: no test, its linked ones and itself, a test file, too (commentonly).
  [ -n "$NOTEXT" ] || ! commentonly "$f" || continue
  # A case file: its changed and added cases alone when its shared part is the same (casesof, cpart), else all of them.
  # Then helpers: the functions its shared part defines, one a line.
  cpart=; helpers=; case $f in conveyor/tests/*.test.sh) [ ! -f "$f" ] || ! casesof "$f" || { cpart=1
    helpers=$(awk "$CASES" "$f" | sed -n 's/^S\t\([A-Za-z_][A-Za-z0-9_]*\)() *{.*/\1/p'); } ;; esac
  # Its linked test files (LINKS), whatever else it selects; not in textonly's pick (NOTEXT): its files are not changed.
  # When its cases alone run (cpart), not a link to a case file that names one of its helpers: that link is for a change
  # to the helpers it calls (slots.test.sh's slotpool, in slotwhole.test.sh). A link a main-red fix wrote names none.
  # A part of a Board script (PART_OF): the script's links, too.
  of=${PART_OF[$f]:-$f}
  [ -z "$LINKS" ] || [ -n "$NOTEXT" ] || while IFS=$'\t' read -r s t; do
    [ "$s" = "$f" ] || [ "$s" = "$of" ] || continue
    case $t in conveyor/tests/*.test.sh) [ -z "$helpers" ] || ! grep -qwF -f <(printf '%s\n' "$helpers") -- "$t" || continue ;; esac
    case $t in conveyor/tests/*.test.sh) area[$t]=1 ;; *) run[$t]=1 ;; esac
    linked[$t$'\t'$f]=1
  done <<<"$LINKS"
  if [ "$f" = "$MAP" ]; then
    # The map's own tests (MAPTESTS), and the case files whose naming changed: each one an area lists now that it did
    # not list at HEAD, and each one of an area whose files changed (in the map now, else at HEAD). "all", or a map either side
    # that cannot be read (none at HEAD, or a line that is not one of its shapes: AREAS), runs the whole engine test.
    for t in $MAPTESTS; do [ ! -f "$t" ] || run[$t]=1; done
    # With MAPOLD (freshen: main changed the map) the two maps are MAPOLD's and HEAD's: the card's own map change, if any,
    # is not main's.
    nmap=$AMAP; [ -z "${MAPOLD:-}" ] || nmap=$(git show "HEAD:$MAP" 2>/dev/null | jq -cs "$AREAS" 2>/dev/null) || nmap=
    if [ -n "$nmap" ] && named=$(git show "${MAPOLD:-HEAD}:$MAP" 2>/dev/null) && named=$(jq -cs "$AREAS" <<<"$named" 2>/dev/null) \
      && named=$(jq -rn --argjson o "$named" --argjson n "$nmap" '($o.areas + $n.areas) | keys[] as $k
        | (($n.areas[$k].tests | arrays) - ($o.areas[$k].tests | arrays // []))[],
          (select($o.areas[$k].files != $n.areas[$k].files)
            | ($n.areas[$k] // $o.areas[$k]).tests | if . == "all" then "all\t\($k)" else .[] end)' 2>/dev/null); then
      while read -r t; do [ -z "$t" ] || if [[ $t == all$'\t'* ]]; then all=1; allby[${t#all$'\t'}]=1; else area[conveyor/tests/$t]=1; fi; done <<<"$named"
    else
      all=1
    fi
    continue
  fi
  if [ ! -f "$f" ]; then
    case $f in conveyor/*)
      jq -e --arg f "$f" 'any(.outside[]; . as $o | $f == $o or (($o | endswith("/")) and ($f | startswith($o)))) | not' \
        <<<"$AMAP" > /dev/null && all=1 ;;
      # A hook library removed: the hooks' tests that reach it (hooklibtests), as for a change to it below.
      .claude/hooks/lib/*.sh) while read -r t; do [ -z "$t" ] || { run[$t]=1; RANKED+=$t$'\n'; }; done < <(hooklibtests "$f") ;;
    esac
    continue
  fi
  case $f in
    conveyor/tests/*.test.sh) [ -n "$cpart" ] || area[$f]=1; continue ;;
    *.test.sh|*.test.mjs|*.test.ts|*.test.tsx) run[$f]=1; continue ;;
  esac
  # The Board tests that import a changed module or draw a changed panel, before the rules below can end the pick: a
  # panel's texts and rows are what those tests check (boardtests).
  while read -r t; do [ -z "$t" ] || run[$t]=1; done < <(boardtests "$f")
  # A change to its texts and comments alone: the tests that hold the texts (textonly).
  [ -n "$NOTEXT" ] || ! textonly "$f" || continue
  # A change to functions alone that the coverage map holds: the cases it lists (issue 527), and of the tests below,
  # those the map names nowhere (a test the trace did not run); not its area.
  cov=; [ -n "$NOTEXT" ] || ! covof "$f" || { cov=1; COVSEL=1; rulefor "$f" covof; }
  # Else a change to functions alone of an engine shell file: the tests that name them or their callers, and the tests
  # named after the file or listed for it; not its area (issue 1775).
  cal=; [ -n "$NOTEXT" ] || [ -n "$cov" ] || ! callersof "$f" || { cal=1; rulefor "$f" callersof; }
  # A change to commands of conveyor.sh alone: the tests that run them (issue 514). A change to the control record's
  # defaults: the tests of the code that reads the keys it changed (issue 530).
  [ -n "$NOTEXT" ] || [ -n "$cov$cal" ] || ! { cmdsof "$f" || keysof "$f"; } || continue
  # A part of a Board script (of, above): the script's tests.
  stem=$(basename "${of%.*}"); dir=$(dirname "$of")
  for s in "$stem" "${stem//_/-}"; do
    for t in "$dir/$s".test.* "$dir/$s"-*.test.* "$dir/__tests__/$s".test.* "$dir/__tests__/$s"-*.test.* \
             "$dir/__tests__/$s"*.refute.test.*; do
      # A file at the root is named as git names it, not ./<file> (issue 595: the meta-runner hook took
      # ./README.test.sh's own start for another file's, and the pack's marks are keyed by git's name).
      t=${t#./}
      [ -f "$t" ] && ! owned "$t" "$stem" && { [ -z "$cov" ] || ! grep -qxF -- "$t" <<<"$COVTESTS"; } && run[$t]=1
    done
  done
  for t in ${TESTS_OF[$of]:-}; do [ ! -f "$t" ] || { [ -n "$cov" ] && grep -qxF -- "$t" <<<"$COVTESTS"; } || { run[$t]=1; ! outside "$of" || RANKED+=$t$'\n'; }; done
  [ -n "$cov$cal" ] || [ -n "$NOTEXT" ] || case $f in conveyor/tests/*) ;; conveyor/*.sh) rulefor "$f" area ;; esac
  [ -n "$cov$cal" ] || case $f in conveyor/*) areaof "$f" ;; .claude/hooks/lib/*.sh) while read -r t; do [ -z "$t" ] || { run[$t]=1; RANKED+=$t$'\n'; }; done < <(hooklibtests "$f") ;; esac
done
# A part the coverage map selected runs as a part, unless this pick, or another, selected its file whole (run, here).
[ -n "$NOTEXT" ] || { for t in "${!run[@]}"; do twhole[$t]=1; done
  for t in "${!npart[@]}"; do run[$t]=1; tparts[$t]+=${npart[$t]}; done; }
# The engine's runner: whole when the runner changed, an area is "all" or the map could not be read; else the cases of
# the areas' files and the changed cases of a case file (casesof), in a session and in the loop's test step alike
# (owner, 2026-11-13: a card tests what it touched). Not in the pick textonly calls (NOTEXT): run[the runner] would read
# as a change to the runner, and the pick it is in sets cases.
[ -z "$NOTEXT" ] || return 0
cases=
if [ -n "$all" ] || [ -n "${run[conveyor/conveyor.test.sh]:-}" ]; then
  run[conveyor/conveyor.test.sh]=1
elif [ ${#area[@]} -gt 0 ] || [ ${#ccase[@]} -gt 0 ]; then
  cases=$({ [ ${#area[@]} = 0 ] || sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "${!area[@]}"
    [ ${#ccase[@]} = 0 ] || printf '%s\n' "${!ccase[@]}"; } | sort -u | tr '\n' ' ')
  run[conveyor/conveyor.test.sh]=1
fi
}
allcases() { sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' conveyor/tests/*.test.sh 2>/dev/null | sort -u; }
filecases() { cat "$@" 2>/dev/null | grep -cE '^[[:space:]]*((test|it)\(|def test_)'; } # <node, python or plugin test files>
shellcases() { # <shell test files>
  local f c s=0
  for f; do
    c=$(grep -cE '^t_[a-z0-9_]+\(\) *\{|^[[:space:]]*check[a-z_]* |(^|[;&|{][[:space:]]*)ok "' "$f" 2>/dev/null)
    s=$((s + (${c:-0} > 0 ? c : 1)))
  done
  echo $s
}
# casefiles <cases>: the engine case files that hold any of the cases (words), one a line.
casefiles() { [ -n "${1// /}" ] && grep -lE "^t_($(tr ' ' '\n' <<<"$1" | grep . | paste -sd'|' -))\(\) \{" conveyor/tests/*.test.sh; }
pick "${changed[@]}"
for f in "${!conly[@]}"; do echo "comment-only change: $f, no tests selected"; done | LC_ALL=C sort
covrules
# The tests the engine chose for the change (#150): a card's run is given them in the file CONVEYOR_TEST_FILELIST names
# (conveyor/lib/testrun.sh testonce()), one path a line (testsel(), reading .conveyor/engine-areas.json through
# conveyor/lib/testmap.sh mapread(), as a user's card reads its map); so is each one-file run (ONE) of the loop of
# test.fileCommand (filecmd()). Each runs: an engine case file with all its
# cases (but with cnarrow, below), as a test file of its own (below); another file whole. The selection above adds the tests it finds and the engine does not
# (TESTS_OF, NAMED, the coverage map's parts), so no case it ran is lost. With no list (a session's run, or a change
# the engine sends to the whole suite) the selection above is the run's.
# cnarrow (issue 1723): when the coverage map chose the tests of a changed file (COVSEL) and nothing chose the runner
# whole, a listed engine case file brings none of its cases: it runs the chosen cases it holds and those the loop names
# of it (TCASES), and with none of them it runs no case. Else a change to one function ran every case of each case file
# of the file's area, as the engine lists those (bug: the map's selection never narrowed a card's run). Before its cap
# of linked files, the engine puts the files this list mode selects of them first (conveyor/lib/testlist.sh selfirst()).
# BYLIST: the other files the loop's list brings that the selection above did not choose, which the list names last.
cnarrow=; [ -z "$COVSEL" ] || { [ -n "${run[conveyor/conveyor.test.sh]:-}" ] && [ -z "$cases" ]; } || cnarrow=1
declare -A BYLIST=()
while IFS= read -r t; do
  case $t in
    '') ;;
    conveyor/tests/*.test.sh)
      # The list of the selection (CONVEYOR_TEST_LIST) of a card's run: of each engine case file only the cases a run of it alone
      # runs (onecases), as every case of the runner is explicit, so a case of the file the loop did not name is no reason to start it.
      if [ -n "${CONVEYOR_TEST_LIST:-}" ]; then
        [ -z "${run[conveyor/conveyor.test.sh]:-}" ] || [ -n "$cases" ] || cases=$(allcases)
        add=$(onecases "$t" "${cnarrow:+$cases}" "$cnarrow") && [ -n "$add" ] || continue
        cases=$({ tr ' ' '\n' <<<"$cases" | grep -vxF -f <(comm -23 <(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$t" | sort -u) <(sort -u <<<"$add")); echo "$add"; } | grep . | sort -u | tr '\n' ' ')
      else
        [ -z "${run[conveyor/conveyor.test.sh]:-}" ] || [ -n "$cases" ] || continue
        if [ -n "$cnarrow" ]; then add=$(onecases "$t" "" 1) && [ -n "$add" ] || continue
        else add=$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$t"); fi
        cases=$({ tr ' ' '\n' <<<"$cases"; echo "$add"; } | grep . | sort -u | tr '\n' ' ')
      fi
      run[conveyor/conveyor.test.sh]=1 ;;
    *) [ -n "${run[$t]:-}" ] || BYLIST[$t]=1; run[$t]=1; twhole[$t]=1 ;;
  esac
done < "${CONVEYOR_TEST_FILELIST:-/dev/null}"
# One-file mode (ONE, above): the selection is that file alone. An engine case file keeps the chosen cases it holds,
# or all its cases when none of them is chosen or the runner was chosen whole (with cnarrow, none: it runs no case and
# passes); any other file runs whole. The cases
# the loop names of the file (TCASES: a card's change adds or changes them, issue 414) are the chosen cases then, of
# an engine case file and of a shell test file that selects its cases (below).
if [ -n "$ONE" ]; then
  if [[ $ONE == conveyor/tests/*.test.sh && $ONE != conveyor/tests/*/* ]]; then
    c=$(onecases "$ONE" "${run[conveyor/conveyor.test.sh]:+$cases}" "$cnarrow") || { echo "test-changed: --file: $ONE holds no t_ case" >&2; exit 1; }
    if [ -n "$c" ]; then cases=$(tr '\n' ' ' <<<"$c"); run=([conveyor/conveyor.test.sh]=1)
    else cases=; run=(); echo "test-changed: --file: the coverage map selects none of the cases of $ONE for this change: none run"; fi
  else
    # Any other shell test file that selects its cases as the runner does (`SEL=${CONVEYOR_SHELL_TEST_CASE...`) runs
    # the cases TCASES names of it, as its parts, and only them: the loop lists the file (CONVEYOR_TEST_FILELIST, above)
    # and a pick may select it, each of which marks it whole. Else, or with none named, it runs whole. They are kept
    # in oparts, not twhole and tparts: freshen() picks again below, which marks the file whole again (issue 423).
    run=(["$ONE"]=1); cases=
    k=$(awk -F'\t' -v f="$ONE" '$1 == f {print $2}' <<<"$TCASES")
    if [ -n "$k" ] && [[ $ONE == *.sh ]] && grep -q '^SEL=\${CONVEYOR_SHELL_TEST_CASE' "$ONE"; then
      oparts=$k
    else twhole[$ONE]=1; fi
  fi
fi
# The whole selection, before what passed is taken out of it (the cases kept as passed: kept, below).
declare -A full=()
for t in "${!run[@]}"; do full[$t]=1; done; fullcases=$cases
# The tests that run whatever passed before (fresh, fcases), each with why it runs (why: one reason a line): those of
# the files a session changed in the card's change (the loop's `changed` lines), picked as the change's own are; and
# those of the files main changed since the HEAD the list was made on (its `main` lines), only where the change's own
# selection holds them too: a test file it selects, and of the engine's runner the cases both select.
declare -A fresh=() why=() cwhy=() only=() nocase=()
fcases=
freshen() { # <reason> <only within the change's selection: 1, or empty> <file>...
  local w=$1 o=$2 f t c a
  shift 2
  # A file changed in its texts alone (textonly) is judged on the card's whole change, or on what main changed in it
  # since the main of the last run (the list's `from` line; with none, as any change).
  if [ -n "$o" ]; then TXFROM=$(awk -F'\t' '$1 == "from" {print $2; exit}' "$RERUN"); TXTO=HEAD; else TXFROM=HEAD; TXTO=; fi
  for f; do
    run=(); area=(); ccase=(); allby=(); all=
    # The map as main changed it: the map at the list's `from` commit (TXFROM) against HEAD's, as pick() reads a card's
    # own change of it, so the entries that changed run where the change's selection holds them, as for any file main
    # changed, and the map's own tests (MAPTESTS) run though the list omits them (below; not in a one-file run, which runs
    # its file alone: a map test the list names runs there). A map that cannot be compared (no
    # `from` line, or a map either side that cannot be read) is "all": every case of the runner the change selects runs.
    if [ -n "$o" ] && [ "$f" = "$MAP" ] && [ -n "$TXFROM" ]; then MAPOLD=$TXFROM pick "$f"
    elif [ -n "$o" ] && [ "$f" = "$MAP" ]; then
      run[conveyor/conveyor.test.sh]=1; cases=
      for t in $MAPTESTS; do [ ! -f "$t" ] || run[$t]=1; done
    else pick "$f"; fi
    for t in "${!run[@]}"; do
      c=$cases
      if [ -n "$o" ]; then
        # A test the selection does not hold is left out, but the map's own tests when main changed the map: they run
        # though the card's list omits them. Not in a one-file run (ONE): it runs its file alone, and the loop stops a
        # run that starts a file beyond its list.
        [ -n "${full[$t]:-}" ] || { [ -z "$ONE" ] && [ "$f" = "$MAP" ] && [[ " $MAPTESTS " == *" $t "* ]]; } || continue
        if [ "$t" = conveyor/conveyor.test.sh ] && [ -n "$fullcases" ]; then
          if [ -z "$c" ]; then c=$fullcases
          else c=$(comm -12 <(tr ' ' '\n' <<<"$c" | grep . | sort -u) <(tr ' ' '\n' <<<"$fullcases" | grep . | sort -u) | tr '\n' ' ')
            [ -n "$c" ] || continue
          fi
        fi
      fi
      if [ "$t" = conveyor/conveyor.test.sh ]; then
        if [ -z "${fresh[$t]:-}" ]; then fcases=$c
        elif [ -n "$fcases" ] && [ -n "$c" ]; then fcases=$(tr ' ' '\n' <<<"$fcases $c" | grep . | sort -u | tr '\n' ' ')
        else fcases=; fi
      fi
      # Of the runner's chosen cases, the reason is also each engine case file's that holds one (cwhy: each runs on its own).
      fresh[$t]=1; why[$t]+="$w $f"$'\n'
      [ "$t" != conveyor/conveyor.test.sh ] || [ -z "$c" ] || while IFS= read -r a; do cwhy[$a]+="$w $f"$'\n'; done < <(casefiles "$c")
      # An area that runs every engine case file selected the runner, and it runs them all for this file: the area's
      # name is a reason too.
      [ "$t" != conveyor/conveyor.test.sh ] || [ -n "$c" ] || for a in "${!allby[@]}"; do why[$t]+="the area $a runs all engine tests"$'\n'; done
    done
  done
}
# A first run of the loop's test step (a log folder, no list) says why each file of its selection runs too: the
# reasons of each changed file, picked one at a time (freshen); the selection is the one picked above. A first run's
# list holds no line but what the loop keeps off (`ok`, `off` and `pass` lines: conveyor.sh flakyoff()); a
# run again's has its `change` line, a run by hand's its `fail` line. Nothing of a first run's selection "did not pass".
first=; ! grep -qvE $'^(ok|off|pass)\t' "$RERUN" 2>/dev/null && first=1
if [ -n "$first" ] && [ -d "${CONVEYOR_TEST_LOG:-}" ] && [ ${#full[@]} -gt 0 ]; then
  freshen "the card changed" '' "${changed[@]}"
  run=(); for t in "${!full[@]}"; do run[$t]=1; done; cases=$fullcases; fresh=(); fcases=
fi
if [ -s "$RERUN" ]; then
  mapfile -t since < <(awk -F'\t' '$1 == "changed" {print $2}' "$RERUN")
  mapfile -t moved < <(awk -F'\t' '$1 == "main" {print $2}' "$RERUN")
  [ ${#since[@]} = 0 ] || freshen "the card changed" '' "${since[@]}"
  [ ${#moved[@]} = 0 ] || freshen "main changed" 1 "${moved[@]}"
  run=(); for t in "${!full[@]}"; do run[$t]=1; done; cases=$fullcases
fi
if [ -s "$RERUN" ]; then
  # A file listed as passed is not run, unless the list also names cases of it that failed (it passed before a run
  # after a fix failed them): then, of the engine's runner, those cases alone.
  failed=$(awk -F'\t' '$1 == "fail" {print $2}' "$RERUN")
  while IFS=$'\t' read -r k f _; do [ "$k" != pass ] || grep -qxF -- "$f" <<<"$failed" || unset "run[$f]"; done < "$RERUN"
  rpass=$(awk -F'\t' '$1 == "pass" && $2 == "conveyor/conveyor.test.sh"' "$RERUN")
  # A `fail` line naming an engine case file and no case (the run of that one file: conveyor.sh testaction run) runs
  # its cases through the runner, which times the file as a card's run does.
  again=$({ awk -F'\t' '$1 == "fail" && $2 == "conveyor/conveyor.test.sh" {print $3}' "$RERUN"
      awk -F'\t' '$1 == "fail" && $3 == "" && $2 ~ /^conveyor\/tests\/[^\/]+[.]test[.]sh$/ {print $2}' "$RERUN" \
        | while IFS= read -r f; do [ ! -f "$f" ] || sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$f"; done; } \
    | grep -Fxf <(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' conveyor/tests/*.test.sh) | sort -u | tr '\n' ' ')
  # One-file mode (ONE) runs that file's cases alone: of these, its own. Another file's (a whole-file `fail` line of a
  # file that failed before any case passed: a run that stops at its first failure) would take the place of its
  # selection, then be left out with that file below, and the file passed with none of its cases run.
  [ -z "$ONE" ] || again=$(tr ' ' '\n' <<<"$again" | grep -xFf <(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$ONE") | tr '\n' ' ')
  # A file the list names failed cases of runs though no change selects it: the loop runs a card's failing cases on
  # main (mainred.sh verdicts()), where nothing changed. Of the engine's runner, only when a case it names is one; of
  # a node test file, those cases alone (only, below). A `fail` line naming no case (a file that failed naming none, or
  # ran out of time) runs its file whole, the runner too.
  whole=$(awk -F'\t' '$1 == "fail" && $3 == "" {print $2}' "$RERUN")
  while IFS=$'\t' read -r k f c; do
    [ "$k" = fail ] && [ -f "$f" ] && [ -z "${run[$f]:-}" ] || continue
    case $f in conveyor/tests/*.test.sh) ! grep -qxF -- "$f" <<<"$whole" || { [ -z "$again" ] || { run[conveyor/conveyor.test.sh]=1; cases=$again; }; continue; }
      # A case the file does not have (the split check's run with no case selected, lib/speedproof.sh splitstart():
      # conveyor-no-case) runs the file's start-up alone: the runner with no case, timed as the file.
      sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$f" | grep -qxF -- "$c" || { run[$f]=1; nocase[$f]=1; continue; } ;;
    esac
    if grep -qxF -- "$f" <<<"$whole"; then run[$f]=1; [ "$f" != conveyor/conveyor.test.sh ] || again=
    elif [ "$f" != conveyor/conveyor.test.sh ]; then run[$f]=1; only[$f]=1; elif [ -n "$again" ]; then run[$f]=1; cases=$again; fi
  done < "$RERUN"
  sel=$cases; [ -z "$again" ] || cases=$again
  # Cases of the runner that passed in a run of it that did not (one killed part-way, after or before a case failed):
  # the rest of its selection runs, not only the cases that failed.
  oks=$(awk -F'\t' '$1 == "ok" && $2 == "conveyor/conveyor.test.sh" {print $3}' "$RERUN")
  if [ -n "$oks" ] && [ -z "$rpass" ] && [ -n "${run[conveyor/conveyor.test.sh]:-}" ]; then
    left=$(tr ' ' '\n' <<<"${sel:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' conveyor/tests/*.test.sh)}" | grep . | grep -vFxf <(echo "$oks") | sort -u | tr '\n' ' ')
    if [ -n "$left" ]; then cases=$left; else unset "run[conveyor/conveyor.test.sh]"; fi
  fi
  [ -n "$first" ] || for t in "${!run[@]}"; do
    why[$t]+='did not pass'$'\n'
    [ "$t" != conveyor/conveyor.test.sh ] || [ -z "$cases" ] || while IFS= read -r af; do cwhy[$af]+='did not pass'$'\n'; done < <(casefiles "$cases")
  done
  # The tests of the files the session changed run beside what had not passed: a test file whole, and of the runner
  # the cases of their areas (all of them for an "all" area), added to its cases that had not passed.
  for t in "${!fresh[@]}"; do
    if [ "$t" = conveyor/conveyor.test.sh ]; then
      if [ -z "$fcases" ]; then cases=
      elif [ -z "${run[$t]:-}" ]; then cases=$fcases
      elif [ -n "$cases" ]; then cases=$(tr ' ' '\n' <<<"$cases $fcases" | grep . | sort -u | tr '\n' ' ')
      fi
    fi
    run[$t]=1
  done
  # Of the runner, a case the loop keeps off as flaky (an `off` line: conveyor.sh flakyoff()) does not run, though a
  # change selects it or its whole area: it is left out last, after every case above was added.
  # A whole test file an `off` line names (one that passed before with the same inputs: conveyor.sh cacheoff()) does not
  # run either: an engine case file's cases are left out of the runner so, and any other file is not run.
  off=$(awk -F'\t' '$1 == "off" && $2 == "conveyor/conveyor.test.sh" && $3 != "" {print $3}' "$RERUN")
  while IFS=$'\t' read -r k f c; do
    [ "$k" = off ] && [ -z "$c" ] && [ -n "$f" ] || continue
    case $f in
      conveyor/tests/*.test.sh) off+=$'\n'$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$f" 2>/dev/null) ;;
      *) unset "run[$f]" ;;
    esac
  done < "$RERUN"
  off=$(grep . <<<"$off")
  if [ -n "$off" ] && [ -n "${run[conveyor/conveyor.test.sh]:-}" ]; then
    left=$(tr ' ' '\n' <<<"${cases:-$(allcases)}" | grep . | grep -vFxf <(echo "$off") | sort -u | tr '\n' ' ')
    if [ -n "$left" ]; then cases=$left; else unset "run[conveyor/conveyor.test.sh]"; fi
  fi
fi
# A file of no test kind this script runs (*.test.sh, .mjs, .py, .ts, .tsx), as a document in a test folder
# (conveyor/tests/speed/<page>.md) or a helper, is no test file: whatever put it on the selection (the engine's list,
# a link, a `fail` line of the loop's list), it does not run, and so never fails (#367), nor counts as kept.
for t in "${!run[@]}" "${!full[@]}"; do
  case $t in *.test.sh|*.test.mjs|*.test.py|*.test.ts|*.test.tsx) ;; *) [ -z "${run[$t]:-}" ] || echo "== $t: not run: no test file"; unset "run[$t]" "full[$t]" ;; esac
done
# The list of the selection (issue 43: release-prep, which reruns only what changed since an earlier whole-suite run,
# conveyor/commands/release-prep.sh): with CONVEYOR_TEST_LIST, it writes the test files it selected to that file, one
# a line, and runs none: each file it selected whole or in parts (a whole-only one too), and of the engine's runner the
# case files that hold its chosen cases, or with none chosen the runner and every case file. The files of RANKED still
# selected come first, in its order, then by name those a link of a changed file names (linked), then by name the rest
# the selection chose, then those only the loop's list brought (BYLIST): a card that runs only the first few runs those
# (conveyor/lib/testlist.sh selfirst()). Bug: a link named a test for one file of a large area (testruns.test.sh for
# conveyor/jq/check.jq), and the area's case files that sort before it filled the card's few, so it never ran.
if [ -n "${CONVEYOR_TEST_LIST:-}" ]; then
  lsel=$(for t in "${!run[@]}"; do
      if [ "$t" != conveyor/conveyor.test.sh ]; then echo "$t"
      elif [ -z "$cases" ]; then echo "$t"; printf '%s\n' conveyor/tests/*.test.sh
      else grep -lE "^t_($(tr ' ' '\n' <<<"$cases" | grep . | paste -sd'|' -))\(\) \{" conveyor/tests/*.test.sh; fi
    done | LC_ALL=C sort -u) || exit 1
  { while IFS= read -r t; do [ -z "$t" ] || [ -z "${run[$t]:-}" ] || echo "$t"; done <<<"$RANKED"
    for k in "${!linked[@]}"; do echo "${k%%$'\t'*}"; done | LC_ALL=C sort -u | grep -xF -f <(printf '%s\n' "$lsel")
    while IFS= read -r t; do [ -z "$t" ] || [ -n "${BYLIST[$t]:-}" ] || echo "$t"; done <<<"$lsel"
    while IFS= read -r t; do [ -z "$t" ] || [ -z "${BYLIST[$t]:-}" ] || echo "$t"; done <<<"$lsel"
  } | awk '!seen[$0]++' > "$CONVEYOR_TEST_LIST" || exit 1
  # Of the files the loop gave (CONVEYOR_TEST_FILELIST) that the list keeps something of (a `pass`, `ok` or `off` line, no `fail`
  # line: as conveyor/lib/testlist.sh runfiles() reads it) and does not name, the loop starts none: the cases a run of each alone
  # would count as kept (below) are logged here, once.
  if [ -s "$RERUN0" ] && [ -d "${CONVEYOR_TEST_LOG:-}" ]; then
    kc=0
    while IFS= read -r t; do
      [ -n "$t" ] && [ -f "$t" ] && ! grep -qxF -- "$t" "$CONVEYOR_TEST_LIST" \
        && awk -F'\t' -v f="$t" '$2 == f { if ($1 == "pass" || $1 == "ok" || $1 == "off") p = 1; else if ($1 == "fail") x = 1 } END { exit !(p && !x) }' "$RERUN0" || continue
      case $t in
        conveyor/tests/*.test.sh) kc=$((kc + $(onecases "$t" "$fullcases" "$cnarrow" | grep -c .))) ;;
        *.mjs|*.py|*.ts|*.tsx) kc=$((kc + $(filecases "$t"))) ;;
        *) kc=$((kc + $(shellcases "$t"))) ;;
      esac
    done < "${CONVEYOR_TEST_FILELIST:-/dev/null}"
    [ "$kc" = 0 ] || echo "TESTRUN kept=$kc" >> "$CONVEYOR_TEST_LOG/test-changed.log"
  fi
  exit 0
fi
# The loop's test step reads which files ran and which failed from a log in the folder it names (conveyor.sh
# testfails()), where no test's own output can pass for these lines.
log=/dev/null; [ ! -d "${CONVEYOR_TEST_LOG:-}" ] || log=$CONVEYOR_TEST_LOG/test-changed.log
for t in "${!linked[@]}"; do printf 'TESTRUN linked\t%s\n' "$t" >> "$log"; done
# enginewhole: 0 when the runner's run starts every case file of the engine: no cases chosen, or a case of each (issue
# 546: a whole run with a flaky case kept off; a file an `off` line keeps off whole is not run so). Such a run sources
# them all, which the hook does not see: it is a meta-runner's run (issue 584).
enginewhole() {
  [ -n "$cases" ] || return 0
  local f c
  for f in conveyor/tests/*.test.sh; do
    c=$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$f")
    [ -z "$c" ] || grep -qxFf <(tr ' ' '\n' <<<"$cases" | grep .) <<<"$c" || return 1
  done
}
# A file the pack marks whole-only (wonly, above) is not run here: the whole test runs it. The runner's chosen cases
# are no meta-runner's run, and run, as their case files (below).
for t in "${!run[@]}"; do
  [ -n "${wonly[$t]:-}" ] || continue
  [ "$t" != conveyor/conveyor.test.sh ] || enginewhole || continue
  unset "run[$t]"; printf 'TESTRUN whole-only\t%s\n' "$t" >> "$log"
  echo "== $t: not run: whole-only (test.files.\"$t\".wholeOnly in .conveyor/project.json), the nightly whole test runs it"
  # The whole engine left to the nightly run still runs the engine case files this change adds or changes, each
  # whole: else a change to conveyor/tests/lib.sh with a new case ran no engine case at all, and the bug-card check
  # read that as the new case passing without the fix (#229).
  if [ "$t" = conveyor/conveyor.test.sh ]; then
    own=$(for f in "${changed[@]}"; do case $f in conveyor/tests/*.test.sh) [ -f "$f" ] && sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$f";; esac; done | sort -u | paste -sd' ' -)
    [ -z "$own" ] || { cases=$own; run[conveyor/conveyor.test.sh]=1; echo "== the engine case files this change touches run whole: $own"; }
  fi
done
# Each engine case file is a test file of its own (the owner, 2026-11-17; issue 214): the runner's chosen cases run as
# the case files that hold them, each with its own cases alone (ecases), its own process, start-up, test slot and
# result, so a failure, a red main, a flaky entry and a time name the case file, and a broken start-up of one file
# fails no other file's cases. A file runs so as it runs alone (its first lines): the runner, which sources every case
# file, given that file's cases, under that file's mark (below). The runner as a test file of its own runs only when it
# runs every case file (enginewhole: whole-only, or its card mode).
declare -A ecases=()
if [ -n "${run[conveyor/conveyor.test.sh]:-}" ] && [ -n "$cases" ] && ! enginewhole; then
  for t in conveyor/tests/*.test.sh; do
    c=$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$t" | grep -xFf <(tr ' ' '\n' <<<"$cases" | grep .) | LC_ALL=C sort -u | tr '\n' ' ')
    [ -n "$c" ] || continue
    ecases[$t]=${c% }; run[$t]=1; unset "nocase[$t]"; why[$t]+=${cwhy[$t]:-}
  done
  unset "run[conveyor/conveyor.test.sh]"
fi
# One-file mode: no other file runs, not one a run again's list names (a `fail` line of another file) nor the case
# files a whole-only runner leaves to run.
[ -z "$ONE" ] || for t in "${!run[@]}"; do [ "$t" = "$ONE" ] || unset "run[$t]" "ecases[$t]"; done
# What it selected and out of how many (the step's record, conveyor.sh testrec()): the test files it can run (each
# engine case file, never the runner, which runs only in the nightly whole test), and the cases: the engine's, and each node test file's
# test() and it() and each python one's def test_ (the Board's), and each Claude Code plugin test file's test() (the
# /units mod's), and each other shell test file's t_ cases, check calls and ok calls, or 1 for a file that has none of
# them (it runs as one case).
nf=$(git ls-files -co --exclude-standard '*.test.sh' '*.test.mjs' '*.test.py' '*.test.ts' '*.test.tsx' | grep -vcx conveyor/conveyor.test.sh)
nc=$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' conveyor/tests/*.test.sh 2>/dev/null | sort -u | wc -l)
# fparts <test file>: the parts it runs of a file that is no engine case file, comma-separated (CONVEYOR_SHELL_TEST_CASE):
# those the coverage map selected (covof) when nothing selected it whole, or those the one-file mode runs of it
# (oparts); none when it runs whole. A file run with parts counts one case a part, not all its cases (issue 1439).
fparts() { [ -z "$oparts" ] && [ -n "${twhole[$1]:-}" ] || grep . <<<"${oparts:-${tparts[$1]:-}}" | LC_ALL=C sort -u | paste -sd, -; }
mapfile -t board < <(git ls-files -co --exclude-standard '*.test.mjs' '*.test.py' '*.test.ts' '*.test.tsx')
[ ${#board[@]} = 0 ] || nc=$((nc + $(filecases "${board[@]}")))
mapfile -t shell < <(git ls-files -co --exclude-standard '*.test.sh' | grep -v '^conveyor/tests/' | grep -vx conveyor/conveyor.test.sh)
[ ${#shell[@]} = 0 ] || nc=$((nc + $(shellcases "${shell[@]}")))
sc=0; [ -z "${run[conveyor/conveyor.test.sh]:-}" ] || if [ -n "$cases" ]; then sc=$(wc -w <<<"$cases"); else sc=$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' conveyor/tests/*.test.sh 2>/dev/null | sort -u | wc -l); fi
board=(); shell=()
for t in "${!run[@]}"; do
  if [ -n "${ecases[$t]:-}" ]; then sc=$((sc + $(wc -w <<<"${ecases[$t]}"))); continue; fi
  case $t in
    conveyor/conveyor.test.sh) ;;
    *.mjs|*.py|*.ts|*.tsx) board+=("$t") ;;
    *) p=$(fparts "$t"); if [ -n "$p" ]; then sc=$((sc + $(tr , '\n' <<<"$p" | grep -c .))); else shell+=("$t"); fi ;;
  esac
done
[ ${#board[@]} = 0 ] || sc=$((sc + $(filecases "${board[@]}")))
[ ${#shell[@]} = 0 ] || sc=$((sc + $(shellcases "${shell[@]}")))
# Run by test.fileCommand (one-file mode, its mark CONVEYOR_TEST_FILE naming the file: conveyor/lib/testrun.sh
# filecmd()), the engine's own log line counts the file: a second count in a log would read as more files run than
# given, and the step would stop the run (#350). The run says its count in its output then, which the step does not
# add up beside the logs (testprogress(), testfails()).
fmark=${CONVEYOR_TEST_FILE:-}
if [ -n "$ONE" ] && [ "${fmark#./}" = "$ONE" ]; then echo "TESTRUN files=${#run[@]} of=$nf"
else echo "TESTRUN files=${#run[@]} of=$nf" >> "$log"; fi
echo "TESTRUN cases=$sc of=$nc" >> "$log"
# A run again (the loop's list) also says how many cases of the whole selection passed before and are not run: kept.
if [ -s "$RERUN" ]; then
  kc=0; board=(); shell=()
  for t in "${!full[@]}"; do
    if [ "$t" = conveyor/conveyor.test.sh ]; then
      # Its cases of the selection that do not run (all of them when it does not run; none when it runs whole), its
      # chosen cases running in their case files (ecases) or through it.
      r=; [ -z "${run[$t]:-}" ] && [ ${#ecases[@]} = 0 ] || r=1
      [ -n "$r" ] && [ -z "$cases" ] && continue
      kc=$((kc + $(comm -23 <(tr ' ' '\n' <<<"${fullcases:-$(allcases)}" | grep . | sort -u) \
        <([ -z "$r" ] || tr ' ' '\n' <<<"$cases" | grep . | sort -u) | wc -l)))
    elif [ -z "${run[$t]:-}" ]; then
      case $t in *.mjs|*.py|*.ts|*.tsx) board+=("$t") ;; *) shell+=("$t") ;; esac
    fi
  done
  [ ${#board[@]} = 0 ] || kc=$((kc + $(filecases "${board[@]}")))
  [ ${#shell[@]} = 0 ] || kc=$((kc + $(shellcases "${shell[@]}")))
  echo "TESTRUN kept=$kc" >> "$log"
fi
# The loop's live record counts the cases selected above that have ended, from the records in cases/ok and
# cases/failed of its log folder (session.sh testdone()). The engine's runner writes a record for each of its own cases.
# This script writes the records for a Board or other shell test file when the file ends, one for each case counted
# above. A file that passed gets them all in ok. A failed file gets as many in failed as its runner's summary says
# (node's `fail N`, python's `FAILED (failures=N, errors=M)`, the plugin test run's `(fail) ` lines), at least 1 and
# at most all of them, and the rest in ok.
# With FAILFAST, a failed file stopped at its first failed case, so the rest did not all run: only as many go in ok
# as its runner's summary says passed (node's `pass N`; python's `Ran N tests` less its failures, errors and skips),
# else, with no summary (a file the stop ended part-way, a shell test file, the plugin test run), as many as its
# output has lines of a passed case (TAP's `ok` but a TODO or SKIP, the plugin test run's `(pass) `), and the rest
# get no record.
# A shell test file run with parts (fparts) gets one record a part, as it was counted.
ended() { # <test file> <ok|FAIL> <its output> [<its parts, comma-separated>]
  [ -d "${CONVEYOR_TEST_LOG:-}" ] || return 0
  local k f=0 g i d=$CONVEYOR_TEST_LOG/cases
  case $1 in
    *.mjs|*.py|*.ts|*.tsx) k=$(filecases "$1") ;;
    *) if [ -n "${4:-}" ]; then k=$(tr , '\n' <<<"$4" | grep -c .); else k=$(shellcases "$1"); fi ;;
  esac
  g=$k
  if [ "$2" = FAIL ]; then
    f=$(sed 's/\x1b\[[0-9;]*m//g' "$3" | awk '/^(ℹ|#) fail [0-9]+$/ { n += $3 }
      /^\(fail\) / { n++ }
      /^FAILED \(/ { while (match($0, /(failures|errors)=[0-9]+/)) { split(substr($0, RSTART, RLENGTH), a, "="); n += a[2]; $0 = substr($0, RSTART + RLENGTH) } }
      END { print n + 0 }')
    f=$((f < 1 ? 1 : f)); f=$((f > k ? k : f)); g=$k
    [ -z "$FAILFAST" ] || g=$(sed 's/\x1b\[[0-9;]*m//g' "$3" | awk -v f="$f" '/^(ℹ|#) pass [0-9]+$/ { n += $3; s = 1 }
      /^Ran [0-9]+ tests? / { n += $2; py = 1; s = 1 }
      py && /^FAILED \(/ { while (match($0, /(failures|errors|skipped|expected failures)=[0-9]+/)) { split(substr($0, RSTART, RLENGTH), a, "="); n -= a[2]; $0 = substr($0, RSTART + RLENGTH) } }
      (/^ok( [0-9]+)? - / && !/# *(TODO|SKIP)/) || /^\(pass\) / { c++ }
      END { if (!s) n = c; print f + (n > 0 ? n : 0) }')
    g=$((g > k ? k : g))
  fi
  mkdir -p "$d/ok" "$d/failed"
  for ((i = 1; i <= g; i++)); do
    if [ "$i" -le "$f" ]; then : > "$d/failed/${1//\//:}#$i"; else : > "$d/ok/${1//\//:}#$i"; fi
  done
}
# A node test file runs with node's TAP reporter (NODETEST): it puts `# ` before each line the file prints, so a line a
# test file prints itself (`✔ X (1ms)`, `ok 1 - X`) is never read as the pass of a case X that the file did not run
# (testfails() reads `ok <n> - <name>` and `not ok <n> - <name>`); the default reporter prints it as it prints a pass.
NODETEST=(node --max-old-space-size=4096 --test --test-reporter=tap)
# With FAILFAST, a node test file runs with NODEHOLD (node's --import, which node --test gives the file's process):
# after a case that did not pass, the next case waits before it starts, and failstop (below), which reads the failed
# case's `not ok` line, ends the file in that wait. Node starts its next case at once, before failstop could read the
# line, and a case of a file with no case pool of its own (dashboard-view.helpers.mjs cases()) ran past the failure.
# A failed TODO case, at which failstop does not stop, is not told apart: the case after it starts 30 s later.
NODEHOLD="data:text/javascript,import { afterEach, beforeEach } from 'node:test'; let held = false; afterEach((t) => { if (!t.passed) held = true; }); beforeEach(async () => { if (held) { held = false; await new Promise((r) => setTimeout(r, 30000)); } });"
# Of a node test file, the cases the list says to leave out or to run alone, as node's options (nargs): each case named
# whole (its own name, as testfails() reads it from node's `not ok <n> - <name>` line, matched exactly). Not run: each case of an
# `ok` line (one the loop keeps off as flaky, conveyor.sh flakyoff(), or that passed in a run killed part-way) or of an
# `off` line (one kept off as flaky). Run
# alone: each case of a `fail` line, when only such lines select the file (the run of a card's failing cases on main).
# A Python or other shell test file has no such option: it runs whole.
nodecases() { # <node test file>
  local k f c p; nargs=()
  [ -s "$RERUN" ] || return 0
  while IFS=$'\t' read -r k f c; do
    [ "$f" = "$1" ] && [ -n "$c" ] || continue
    p="^$(sed 's/[][\\.*+?^${}()|/]/\\&/g' <<<"$c")\$"
    if [ "$k" = ok ] || [ "$k" = off ]; then nargs+=("--test-skip-pattern=$p"); elif [ "$k" = fail ] && [ -n "${only[$1]:-}" ]; then nargs+=("--test-name-pattern=$p"); fi
  done < "$RERUN"
}
# nostart <why>: no file of the run starts, as its temp file or folder could not be made (a full /tmp, or one out of
# inodes). Bug: the run ended failed with no line for its files, and the engine took each for a failed test (fileeach()
# logged `-- FAIL`). It is a host problem, as a file that did not start for want of room (below): each file is logged
# `TESTRUN host<TAB><file><TAB><why>` and `-- notrun <file>`, and the run ends failed.
nostart() {
  local t
  for t in $(printf '%s\n' "${!run[@]}" | LC_ALL=C sort); do
    { echo "== $t"; printf 'TESTRUN host\t%s\t%s\n' "$t" "$1"; echo "-- notrun $t"; } >> "$log"
  done
  echo "$1; nothing run"; exit 1
}
# No temp file: it stops before the trap, as an empty $o would make "$o".* every hidden file here.
o=$(mktemp) && [ -n "$o" ] || nostart "test-changed: no temp file could be made in ${TMPDIR:-/tmp}"
trap 'chmod -R u+w "$o.tmp" 2>/dev/null; rm -rf "$o" "$o".* "${rlist:-}"' EXIT
# Each test file runs with a share of the temp space and a TMPDIR of its own in $o.tmp, removed when it ends, and
# with $o.tmp when this run ends (share_run, .conveyor/test-share.sh, as the full suite runs them): a file that writes
# past its share fails alone, and one starts only when the space holds its share (#1238).
mkdir "$o.tmp" || nostart "test-changed: the test files' temp folder $o.tmp could not be made"
# shellcheck source=.conveyor/test-share.sh
. "${BASH_SOURCE[0]%/*}/test-share.sh" || { echo "test-changed: ${BASH_SOURCE[0]%/*}/test-share.sh could not be read; nothing run"; exit 1; }
# A $o.why that could not be made (the same full space) is a host problem too; a share_init that failed, a bad host file.
{ : > "$o.why"; } 2>/dev/null || nostart "test-changed: the test files' temp file $o.why could not be made"
share_init "$o.tmp" > "$o.why" || {
  echo "test-changed: the test files' temp space could not be set up (${BASH_SOURCE[0]%/*}/test-share.sh, $o.tmp): $(cat "$o.why" 2>/dev/null); nothing run"; exit 1; }
# A Claude Code plugin test file (*.test.ts, *.test.tsx: the /units mod's, in hooks/) runs under Claude Code's own
# runner, `claude plugin test` on the plugin, which runs every such file of the plugin in one run. So it runs once, at
# the first such file, and a file's result is its own part of that run's output: its `<file>:`
# heading and the lines under it. A file with a `(fail)` line there, or with no `(pass)` line (it did not run), fails.
# That run has a share of the temp space for each plugin test file, and its own TMPDIR, $o.tmp/p (share_run): under
# the share of its first file, the files' writes together failed it, or left the later files' parts cut off (#1394).
# When it did not start or wrote past its share, each file fails with the reason; when it did not start for want of
# room ($o.tmp/p.noroom, or the exit SHARE_NOSTART when its temp folder or output file could not be made: it returns
# that exit, and the next plugin test file tries the run again), each file did not run, a host problem (below).
plugintest() { # <test file>
  local n s=0 p='test-changed: the plugin test run'
  if [ ! -s "$o.plugin" ]; then
    n=$(git ls-files -co --exclude-standard '*.test.ts' '*.test.tsx' | grep -c .)
    # With FAILFAST, the run ends at the first failed case of this file (failstop --in): a failed case of another
    # file is that file's to report.
    # Its output file is opened inside, so one that cannot be made is SHARE_NOSTART too.
    ( exec > "$o.plugin" 2>&1 || exit "$SHARE_NOSTART"; LIMKB=$((LIMKB * (n > 1 ? n : 1)))
      failstop --in "$1:" share_run "$p (claude plugin test, a share for each of its $n test files)" "$o.tmp/p" env "${mk[@]}" claude plugin test . ) || s=$?
    # A run that did not start is not kept: the next plugin test file tries it again.
    [ "$s" != "$SHARE_NOSTART" ] || { cat "$o.plugin" 2>/dev/null; rm -f "$o.plugin"; return "$s"; }
  fi
  awk -v f="$1:" -v p="$p (" 'index($0, p) == 1 { next } $0 == f { on = 1; next } on && /^[^ (].*:$/ { exit } on' "$o.plugin" > "$o.part"
  cat "$o.part"
  ! awk -v p="$p (" 'index($0, p) == 1 { print; r = 1 } END { exit !r }' "$o.plugin" || return 1
  grep -q '^(pass)' "$o.part" && ! grep -q '^(fail)' "$o.part"
}
# One test file's command, run one at a time after the engine case files (below), with its share of the temp space
# and its own TMPDIR, $o.tmp/f<n> (share_run; n: fk, the file's place in the run, below); it waits for room for its
# share, or fails with the reason ($o.tmp/f<n>.noroom when that is want of room: a host problem, below).
fshare() { # <test file> <command>...
  local t=$1; shift
  [ -z "${trc:-}" ] || set -- "${TRACE[@]}" "$o.trace" "$@"
  share_run "test-changed: $t" "$o.tmp/f$fk" "$@"
}
# The files a test file reads (issue 1619). In the loop's test step (CONVEYOR_TEST_LOG), on a host where strace can
# trace this run's children (Linux) and says nothing doing so, each test file run whole runs under strace: a file run
# one at a time below (trc, its calls in $o.trace) and an engine case file run with every case it holds (etr, below: its
# calls in $o.e<n>.trace). Not a part of a file, nor an engine case file run with some of its cases, nor a plugin test
# file: one plugin test run runs them all, so its trace cannot tell which file read what, and the test map picks them.
# When it passes, its log names what it read (inputsof): the engine keeps that with the pass, keeps the file off a later run
# while those files are the same, and runs it for a change to one of them (conveyor/README.md, Test file
# times, the paragraph "The test results cache"). With no such strace, no file names its inputs, and the test map picks it as before. strace runs apart from
# the file's process (-D), so the file ends as it would untraced, not when the last process it left behind ends. It
# traces each call that takes a path (%file): a test can read a file with no open (a readlink, a stat, an access check
# or an exec of it). It traces the calls that failed too: a lookup of a file that is not there (a package.json that
# Node looks for) changes what the test does once that file is added.
# CONVEYOR_TEST_NOTRACE set (the run before a push, for a file whose list of inputs is fresh: lib/pushrun.sh pushfile())
# traces nothing: the trace would give the list the engine already holds.
TRACE=(strace -D -f -qq --seccomp-bpf -y -e trace=%file -o)
if [ -d "${CONVEYOR_TEST_LOG:-}" ] && [ -z "${CONVEYOR_TEST_NOTRACE:-}" ] && command -v strace > /dev/null 2>&1 && tp=$("${TRACE[@]}" /dev/null true 2>&1) && [ -z "$tp" ]; then :
else TRACE=(); fi
# inputsof <test file> <trace>: its `TESTRUN inputs<TAB><file><TAB><input>...` line, from the trace: each tracked file
# of this checkout that a call read, by the path the call was given (a symbolic link as itself, not its target) and, for
# an open, by the path of the file it opened; and each folder holding a tracked file that it opened, as <folder>/ (./
# for the root), so a file added there or deleted changes its inputs; and each path here that a call looked for and
# did not find (it failed with ENOENT or ENOTDIR), so adding a file or folder there changes its inputs. A read is an
# open (not one for writing alone), a stat, an access check, a readlink, an exec or a failed chdir. A relative path is
# of the folder the call names (AT_FDCWD<folder>, or <fd><folder>), else of the folder the process was last seen in
# (its last AT_FDCWD, or its last chdir that did not fail), else of the checkout. A call strace split (`<unfinished
# ...>`) takes its result from the line it resumed on. Not the file itself, nor .git. Nothing, and so no pass kept, for
# a trace that names a path here with a byte strace escapes, which no tracked path can be matched to; that opens this
# checkout's Git index or a file of its Git objects (a `git ls-files -s`, a `git diff`, a `git show`): what the test then
# reads is the list of tracked files or their content in Git, which no input names, so a pass kept on its inputs could
# stand after a file was added. But a process that opens the index after its exec of a `git ls-files` that prints
# only the tracked paths (lists(): its options -z, -c, --cached, --full-name, --error-unmatch and --exclude-standard,
# and paths) reads the list of tracked files alone: its inputs name every folder that holds a tracked file, so a file
# added or deleted anywhere changes them, and the engine runs the test for it. Bug: spdx.test.sh lists the tracked
# files so and named no inputs, and no map, link or name selects it for a new file, so a new hooks/new.sh with no SPDX
# line ran no test that fails on it. A trace that read a path here that is not tracked and was there (a dependency
# folder linked from main, such as node_modules, or a file a test left) gives the same list as a `TESTRUN reads` line:
# no input names that path's content, so the engine keeps no pass on it (a pass kept could stand after a file in it
# changed or was deleted), but it still picks the file for a change to one of its inputs (conveyor/lib/testlist.sh
# cachekeep()). Bug: such a trace gave no line, so a test that loads jsdom named no input, and adding the package.json
# that Node looked for beside it picked no test.
inputsof() {
  local in g c k=inputs rc=0
  [ -s "$2" ] && git -c core.quotePath=false ls-files > "$o.tracked" && g=$(git rev-parse --absolute-git-dir) && g=$(cd "$g" && pwd -P) \
    && c=$(git rev-parse --path-format=absolute --git-common-dir) && c=$(cd "$c" && pwd -P) || return 1
  in=$(awk -v r="$(pwd -P)" -v r2="$PWD" -v t="$1" -v T="$o.tracked" -v G="$g" -v C="$c" '
    function norm(p,  n, a, s, i, k, o) {
      n = split(p, a, "/"); k = 0
      for (i = 1; i <= n; i++) { if (a[i] == "" || a[i] == ".") continue; if (a[i] == "..") { if (k) k--; continue }; s[++k] = a[i] }
      o = ""; for (i = 1; i <= k; i++) o = o "/" s[i]; return o == "" ? "/" : o }
    # Whether the arguments s of an exec (`, ["git", ...], ...`, after its path) are a git ls-files that prints only
    # the tracked paths: else, or when strace cut short the list or an option of it (`...`), not. A path or a value
    # strace cut short (`"<its first characters>"...`: a -C folder of a long name) still counts.
    function lists(s,   a, cut, n, i, k, w) {
      if (substr(s, 1, 3) != ", [") return 0; s = substr(s, 4); n = 0
      while (match(s, /^"([^"\\]|\\.)*"/)) {
        a[++n] = substr(s, 2, RLENGTH - 2); s = substr(s, RLENGTH + 1)
        if (substr(s, 1, 3) == "...") { cut[n] = 1; s = substr(s, 4) }
        if (substr(s, 1, 2) != ", ") break; s = substr(s, 3) }
      if (substr(s, 1, 1) != "]" || a[1] !~ /(^|\/)git$/ || (1 in cut)) return 0
      for (i = 2; i <= n && a[i] != "ls-files"; i++) if (!(i in cut) && (a[i] == "-C" || a[i] == "-c")) i++; else return 0
      if (i > n || (i in cut)) return 0
      for (k = 0; ++i <= n;) { w = a[i]; if (k || w !~ /^-/) continue
        if ((i in cut) || w !~ /^(--|-[zc]+|--cached|--full-name|--error-unmatch|--exclude-standard)$/) return 0; if (w == "--") k = 1 }
      return 1 }
    # x read by process q by a call (op: an open) whose result was st: ok, or the error it failed with (ENOENT and so on).
    function add(x, op, st, q) {
      if (op && x == G "/index" && ls[q]) { all = 1; return }
      if (op && (x == G "/index" || index(x, C "/objects/") == 1)) { bad = 1; return }
      if (x == r || x == r2) x = "./"; else if (index(x, r "/") == 1) x = substr(x, length(r) + 2)
      else if (index(x, r2 "/") == 1) x = substr(x, length(r2) + 2); else return
      if (x ~ /^\.git(\/|$)/ || x == t) return
      if (index(x, "\\")) { bad = 1; return }
      if (x in f) use[x] = 1; else if (x == "./") { if (op) use[x] = 1 } else if ((x "/") in d) { if (op) use[x "/"] = 1 }
      else if (st == "ENOENT" || st == "ENOTDIR") use[x] = 1; else ut = 1 }
    # The call c of process q on the path x, its result on the line l.
    function done(q, c, x, l,   st) {
      st = "ok"; if (match(l, / = -1 E[A-Z0-9]+( \(.*\))?$/)) { st = substr(l, RSTART + 6); sub(/ .*/, "", st) }
      if (c == "chdir") { if (st == "ok") cwd[q] = x; else add(x, 0, st, q); return }
      # An exec: whether the program q runs now is a git ls-files of the tracked paths alone (lists, of the line it began on).
      if (c ~ /^execve/ && st == "ok") ls[q] = pv[q]
      add(x, c ~ /^open/, st, q) }
    FILENAME == T { f[$0] = 1; d["./"] = 1; n = split($0, a, "/"); p = ""; for (i = 1; i < n; i++) { p = p a[i] "/"; d[p] = 1 }; next }
    /O_WRONLY/ { next }
    { pid = $1; at = r }
    match($0, /AT_FDCWD<[^>]*>/) { cwd[pid] = substr($0, RSTART + 9, RLENGTH - 10) }
    pid in cwd { at = cwd[pid] }
    # An open: the path of the file it opened (its fd, -y), on its line or on the line it resumed on.
    match($0, /^[0-9]+ +(<\.\.\. )?open(at2?)?[ (]/) && match($0, / = [0-9]+<.*>$/) {
      x = substr($0, RSTART, RLENGTH); sub(/^ = [0-9]+</, "", x); sub(/>$/, "", x); add(x, 1, "ok", pid) }
    # The path the call was given: its first string, of the folder its first argument names when that is one.
    match($0, /^[0-9]+ +[a-z0-9_]+\(/) {
      c = substr($0, RSTART, RLENGTH - 1); sub(/^[0-9]+ +/, "", c); g = substr($0, RSTART + RLENGTH)
      if (c !~ /^(open|openat2?|l?stat(64)?|newfstatat|fstatat64|statx|access|faccessat2?|readlink(at)?|execve(at)?|chdir)$/) next
      b = at; if (match(g, /^(AT_FDCWD|[0-9]+)<[^>]*>, /)) { b = substr(g, 1, RLENGTH - 3); sub(/^[^<]*</, "", b); g = substr(g, RLENGTH + 1) }
      if (!match(g, /^"([^"\\]|\\.)*"/)) next
      if (c ~ /^execve/) pv[pid] = lists(substr(g, RLENGTH + 1))
      x = substr(g, 2, RLENGTH - 2); x = (substr(x, 1, 1) == "/") ? norm(x) : norm(b "/" x)
      if ($0 ~ /<unfinished \.\.\.>$/) { pc[pid] = c; px[pid] = x; next }
      done(pid, c, x, $0); next }
    # A call strace split: the path from the line it began on, the result from this one.
    match($0, /^[0-9]+ +<\.\.\. [a-z0-9_]+ resumed>/) && (pid in px) { c = pc[pid]; x = px[pid]; delete pc[pid]; delete px[pid]; done(pid, c, x, $0) }
    END { if (bad) exit 1; if (all) for (x in d) use[x] = 1; for (x in use) print x; exit ut ? 3 : 0 }' "$o.tracked" "$2") || rc=$?
  [ $rc = 0 ] || { [ $rc = 3 ] && k=reads; } || return 1
  printf 'TESTRUN %s\t%s%s\n' "$k" "$1" "$(LC_ALL=C sort <<<"$in" | awk 'length { printf "\t%s", $0 }')"
}
# failstop [--in <line>] <command>...: runs it, its output and errors to this run's output. With FAILFAST (a card's
# run that stops at its first failure), it ends the command and all it started (its own process group) at the first
# failed case line its output has: `FAIL [<case>]: ` or `FAIL: ` (a shell test file's), TAP's `not ok` but a TODO or
# SKIP, or `(fail) ` (the plugin test run's); with --in, only such a line after the line <line> and before the next
# line that ends in `:` (the plugin test run's section of one file, plugintest()). A shell test file goes on after
# its failed case, and the plugin test run after a failed file; a node test file holds its next case until the line
# ends it (NODEHOLD, above; the Board's case pool, dashboard-view.helpers.mjs cases(), stops its own workers), and a
# Python test file is told with unittest's -f (below), but the line ends it too. In a subshell of its own, so its trap is its own: told to end (the file's group is, when the
# loop ends the file: lib/fileeach.sh), it ends the command's group as well, which no signal to the file's group
# reaches. It ends the command with fsend.
# Its lines are read with the shell's own read, a line as it comes: awk (mawk) reads a pipe in blocks, and saw the
# failed case only once the command had ended.
# fstree <pid>: it and each process under it, one a line, each stopped (STOP) before the processes under it are looked
# for, so none starts one more unseen.
fstree() { local c; kill -STOP "$1" 2>/dev/null; echo "$1"; for c in $(pgrep -P "$1" 2>/dev/null); do fstree "$c"; done; }
# fsend <pid>: TERM to the process group <pid> leads and to each process under <pid> and its group, then CONT to let
# them end. A process under it can run in a group of its own (timeout makes one for its command: a Board collect of
# dashboard-limit.test.sh), which a signal to the command's group does not reach, and it ran on after the stop.
fsend() {
  # Its own IFS: failstop's trap runs it in the middle of an `IFS= read`, whose empty IFS left the list one word.
  local q ps IFS=$' \t\n'; ps=$(fstree "$1")
  kill -TERM -- "-$1" 2>/dev/null
  for q in $ps; do kill -TERM -- "-$q" 2>/dev/null; kill -TERM "$q" 2>/dev/null; done
  for q in $ps; do kill -CONT -- "-$q" 2>/dev/null; kill -CONT "$q" 2>/dev/null; done
}
failstop() (
  [ -n "$FAILFAST" ] || { [ "$1" != --in ] || shift 2; "$@"; exit; }
  p='' s='' in='' on=1 f=$o.ff fx='^FAIL( \[[^]]+\])?: ' nx='^[[:space:]]*not ok ' kx='# *(TODO|SKIP)' px='^\(fail\) ' hx='^[^ (].*:$'
  [ "$1" != --in ] || { in=$2; on=''; shift 2; }
  trap '[ -z "$p" ] || { fsend "$p"; wait "$p" 2>/dev/null; }; exit 143' TERM INT HUP
  # A fifo that cannot be made (a temp space out of inodes): the command did not start, as share_run says it so.
  rm -f "$f"; mkfifo "$f" || { echo "test-changed: the file did not start: its pipe $f could not be made"; exit "$SHARE_NOSTART"; }
  set -m; "$@" > "$f" 2>&1 & p=$!; set +m
  while IFS= read -r l || [ -n "$l" ]; do
    printf '%s\n' "$l"
    [ -z "$s" ] || continue
    if [ -n "$in" ]; then
      if [ "$l" = "$in" ]; then on=1; continue; elif [[ $l =~ $hx ]]; then on=''; fi
    fi
    [ -n "$on" ] || continue
    if [[ $l =~ $fx ]] || [[ $l =~ $px ]] || { [[ $l =~ $nx ]] && ! [[ $l =~ $kx ]]; }; then s=1; fsend "$p"; fi
  done < "$f"
  wait "$p" 2>/dev/null; rc=$?; rm -f "$f"; exit "$rc"
)
# The meta-runner hook (BASH_ENV, header above): a bash test file of this checkout, started whole under the mark of
# another, writes `TESTRUN nested` to $o.nested. A test file's own start, and one of a scratch file no path here
# ends, write nothing. Under an engine case file's mark the runner is the file's own: it runs the file's cases, and
# starts each case's keeper as itself, with no CONVEYOR_SHELL_TEST_CASE (conveyor/tests/lib.sh run_case).
{ printf '%s\n' 'case $0 in *.test.sh) if [ -n "${CONVEYOR_TEST_FILE:-}" ] && [ -z "${CONVEYOR_SHELL_TEST_CASE:-}" ]; then' \
    '  case $0 in */*) __n=$(cd "${0%/*}" 2>/dev/null && pwd -P)/${0##*/} ;; *) __n=$PWD/$0 ;; esac' \
    '  case $CONVEYOR_TEST_FILE:$__n in *:*/"$CONVEYOR_TEST_FILE"|conveyor/tests/*.test.sh:*/conveyor/conveyor.test.sh) ;; *) for __f in \'
  git ls-files -co --exclude-standard '*.test.sh' | while IFS= read -r f; do printf '    %q \\\n' "$f"; done
  printf '%s\n' '    ; do case $__n in */"$__f") printf '"'TESTRUN nested\\t%s\\t%s\\n'"' "$CONVEYOR_TEST_FILE" "$__f" >> '"$(printf %q "$o.nested")"'; break ;; esac; done ;; esac' \
    '  unset __n __f; fi ;; esac'
} > "$o.hook"
# metaran <test file>: after it ran (or, for the engine runner's whole run, in its place), its nested starts to the log
# and to METAREC; 1, and says why, when it started a test file and the pack gives it neither mark. Its own lines alone:
# engine case files run side by side, each under its own mark.
metaran() {
  local in n
  n=$(awk -F'\t' -v f="$1" '$2 == f' "$o.nested" 2>/dev/null); [ -n "$n" ] || return 0
  printf '%s\n' "$n" >> "$log"; cut -f2- <<<"$n" >> "$METAREC" 2>/dev/null
  in=$(cut -f3 <<<"$n" | LC_ALL=C sort -u | paste -sd' ' -)
  awk -F'\t' -v f="$1" '$2 != f' "$o.nested" > "$o.nest2"; mv -f "$o.nest2" "$o.nested"
  [ -z "${cmode[$1]:-}${wonly[$1]:-}" ] || return 0
  echo "$1 starts other test files ($in): it is a meta-runner, and a card's test step does not run a whole suite. Give it one of two marks in .conveyor/project.json: test.files.\"$1\".cardMode, the NAME=VALUE that makes it run its own checks with a stub in place of the files it starts; or test.files.\"$1\".wholeOnly: true, so that it runs only in the nightly whole test"
  return 1
}
# Bug (issue 452): a test run wrote a fake Foreman claim into the real main checkout's state, and the project took a
# Foreman to hold the role. The Foreman's mark there (conveyor/state/foreman: session, former, claim.lock) is read
# before the tests and after each test file, and a file that changed it fails. The rest of the state folder is the
# live loop's and the Foreman's, written while the tests run, so it is not compared.
REAL=$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null) && REAL=${REAL%/.git}/conveyor/state/foreman
realmark() { local f; for f in session former claim.lock; do printf '%s ' "$f"; { cksum < "$REAL/$f"; } 2>/dev/null || echo none; done; }
mark=$(realmark)
marked() { # <test file>: 1, and says so, when the Foreman's mark changed since the last check
  local now; now=$(realmark); [ "$now" = "$mark" ] && return 0; mark=$now
  echo "$1 changed the Foreman's mark in the main checkout's state, $REAL (session, former or claim.lock): a test writes only under its own temporary folder"
  return 1
}
# The parse check of each file changed in its texts or comments alone (textonly, commentonly), whose other tests need
# not run: bash -n, or node --check for the Board's JavaScript.
for t in "${!parse[@]}"; do
  [ -f "$t" ] || continue
  case $t in *.sh) out=$(bash -n "$t" 2>&1) ;; *.js) out=$(node --check "$t" 2>&1) ;; *) continue ;; esac \
    || { echo "$t does not parse: $out"; rc=1; }
done
# The machine's test slots (the engine's lib/slots.sh, the library the loop names, else this checkout's): with none to
# be had, the engine case files run on no slot.
slots=
# shellcheck disable=SC1090 # the library the loop names
! . "${CONVEYOR_TEST_SLOTS:-conveyor/lib/slots.sh}" 2>/dev/null || ! slot_pool 2>/dev/null || slots=1
# The engine case files of the selection (ecases) start side by side before any other file runs, as the runner's cases
# did: each is a worker of this run on a slot of the machine's pool (slot_take: this run's home slot to one at a time,
# a slot of the pool to each beside it), pinned to its slot's core (slot_mine), and its runner runs its cases on that
# slot and on what more of the pool it gets. With no pool to be had, they start side by side all the same. The cases
# each one runs are logged as it starts (`TESTRUN case`), so a run that never ends keeps the passes of the cases it did
# not run (testlist.sh rerunlist()). Their output is read below once all have ended, so their nested starts (metaran)
# are whole. Told to end (its timeout), this run tells each to end, as the runner tells its cases, and prints what each
# not shown yet printed under its own `== ` line, begun and not ended in the log: the cases that passed stay passed,
# and the run's timeout names the last of them.
declare -A epid=() erc=() eout=() shown=()
eend() {
  # Each runs its runner under share_run, a child of its worker, which passes the TERM on to the runner. Each worker is
  # waited for by its pid, never with a bare `wait` (issue 1607): a TERM to the run's whole group (timeout's) ends a
  # worker as it reaches the run, so the `wait "$p"` it cut short can have taken the worker's exit unrecorded, and bash
  # then keeps a running job that is no child of the shell, which a bare `wait` asks for again and again, an error
  # line each time, until the KILL.
  trap "" TERM INT HUP; [ ${#epid[@]} = 0 ] || pkill -TERM -P "$(IFS=,; echo "${epid[*]}")" 2>/dev/null
  for q in "${epid[@]}"; do wait "$q" 2>/dev/null; done
  for t in $(printf '%s\n' "${!epid[@]}" | LC_ALL=C sort); do
    [ -z "${shown[$t]:-}" ] || continue
    echo "== $t" >> "$log"; echo "== $t (cases: ${ecases[$t]})"; cat "${eout[$t]}"
  done
  exit 143
}
trap eend TERM INT HUP
# One that starts waits for one that runs to end while the space cannot hold a share for each (share_noroom), and for
# the files of other runs while they hold theirs, or for room up to the host file's testTmpWaitSec while none does
# (share_run, share_take); with still no room, it does not run, with the reason, and $o.tmp/e<n>.noroom (enr) says so:
# a host problem, not a failed test (below). Once one did not start so, the run's next files do not wait again.
# erun: the pid of each still running.
declare -A erun=() enr=() etr=()
# One that ended: its exit in erc. One that ended before this wait began is not among the jobs a bash before 5.3 waits
# for with `wait -n` (p is left unset): its exit is asked for by itself, as test-full.sh reap() does.
ereap() {
  local p='' q s
  for q in "${!erun[@]}"; do kill -0 "$q" 2>/dev/null || { p=$q; break; }; done
  if [ -n "$p" ]; then wait "$p"; s=$?; else wait -n -p p "${!erun[@]}"; s=$?; fi
  if [ -z "${p:-}" ]; then
    for q in "${!erun[@]}"; do kill -0 "$q" 2>/dev/null || { p=$q; break; }; done
    [ -n "${p:-}" ] || { echo "test-changed: no file it started could be waited for (exit $s); the run ends failed"; exit 1; }
    wait "$p"; s=$?
  fi
  erc[${erun[$p]}]=$s; unset "erun[$p]"
}
k=0
for t in $(printf '%s\n' "${!ecases[@]}" | LC_ALL=C sort); do
  k=$((k + 1)); eout[$t]=$o.e$k; enr[$t]=$o.tmp/e$k.noroom
  # In a subshell ($(...)), not under a redirect: a TERM then runs eend with this run's own output, not /dev/null.
  while [ ${#erun[@]} -gt 0 ] && nr=$(share_noroom "$o.tmp" ${#erun[@]}); do
    ereap
  done
  for c in ${ecases[$t]}; do printf 'TESTRUN case\t%s\t%s\n' "$t" "$c" >> "$log"; done
  # It runs under strace when this run traces (TRACE, inputsof above) and it runs every case it holds (etr: its trace).
  et=(); [ ${#TRACE[@]} = 0 ] || [ "$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$t" | LC_ALL=C sort -u | paste -sd' ' -)" != "${ecases[$t]}" ] \
    || { etr[$t]=$o.e$k.trace; et=("${TRACE[@]}" "${etr[$t]}"); }
  [ -z "$slots" ] || slot_take
  # Its output file is opened inside, so one that cannot be made (a temp space out of inodes) is SHARE_NOSTART, a file
  # that did not start, as share_run's folder is.
  ( exec > "$o.e$k" 2>&1 || exit "$SHARE_NOSTART"
    [ -z "$slots" ] || slot_mine
    share_run "test-changed: $t" "$o.tmp/e$k" "${et[@]}" env CONVEYOR_TEST_FILE="$t" BASH_ENV="$o.hook" CONVEYOR_TEST_TIMES="$o.e$k.times" \
      CONVEYOR_SHELL_TEST_CASE="${ecases[$t]}" ${FAILFAST:+"CONVEYOR_TEST_FAILFAST=$FAILFAST"} bash conveyor/conveyor.test.sh ) < /dev/null &
  epid[$t]=$!; erun[$!]=$t
  [ -z "$slots" ] || slot_free
done
for p in "${!erun[@]}"; do wait "$p"; erc[${erun[$p]}]=$?; done
# The engine case files first, as they ran, then each other file.
mapfile -t order < <(for t in "${!run[@]}"; do if [ -n "${ecases[$t]:-}" ]; then printf '0\t%s\n' "$t"; else printf '1\t%s\n' "$t"; fi; done | LC_ALL=C sort | cut -f2-)
fk=0
for t in "${order[@]}"; do
  # nr: the file share_run leaves when the file did not start for want of room in the temp space (enr above; fshare's,
  # or the plugin test run's for a plugin test file); ns: set when its run exited SHARE_NOSTART, as it does when its temp
  # folder (share_run), its output file or its pipe (failstop) could not be made: a space where nr cannot be written.
  fk=$((fk + 1)); r=ok; ns=; trc=; nr=$o.tmp/f$fk.noroom; echo "== $t" >> "$log"
  # Why it runs (the step's record, conveyor.sh testrec()): one line a reason.
  printf '%s' "${why[$t]:-}" | awk -v t="$t" 'length { printf "TESTRUN why\t%s\t%s\n", t, $0 }' >> "$log"
  # Its mark and the meta-runner hook (header above), and its card mode when the pack gives it one (issue 584).
  mk=(CONVEYOR_TEST_FILE="$t" BASH_ENV="$o.hook" ${cmode[$t]:+"${cmode[$t]}"})
  if [ "$t" = conveyor/conveyor.test.sh ]; then
    # A run of every case file (enginewhole) starts each of them: the runner is then a meta-runner, its starts go to
    # the log and METAREC (metaran), and with no card mode it is not run, and fails (a whole-only mark took it off above).
    w=; ! enginewhole || { w=1; for f in conveyor/tests/*.test.sh; do printf 'TESTRUN nested\t%s\t%s\n' "$t" "$f"; done >> "$o.nested"; }
    if [ -n "$w" ] && [ -z "${cmode[$t]:-}" ]; then
      echo "== $t: not run: every case file of the engine"; metaran "$t" || r=FAIL
    elif [ -n "$cases" ]; then
      # The cases it runs of the runner, so a run that never ends keeps the passes of the cases it did not run (testlist.sh rerunlist()).
      for c in $cases; do printf 'TESTRUN case\t%s\t%s\n' "$t" "$c" >> "$log"; done
      # Every case file of the engine still runs when the list holds a case of each (enginewhole): the step's record
      # says so as below.
      [ -z "$w" ] || echo "TESTRUN whole-suite" >> "$log"
      echo "== $t (cases: $cases)"; fshare "$t" env "${mk[@]}" CONVEYOR_TEST_TIMES="$o.times" CONVEYOR_SHELL_TEST_CASE="$cases" ${FAILFAST:+"CONVEYOR_TEST_FAILFAST=$FAILFAST"} bash "$t" || { [ $? != "$SHARE_NOSTART" ] || ns=1; r=FAIL; }
    else
      # Every case file of the engine runs: the step's record says so in one field (testrec(): wholeSuite).
      echo "TESTRUN whole-suite" >> "$log"
      echo "== $t"; fshare "$t" env "${mk[@]}" CONVEYOR_TEST_TIMES="$o.times" ${FAILFAST:+"CONVEYOR_TEST_FAILFAST=$FAILFAST"} bash "$t" || { [ $? != "$SHARE_NOSTART" ] || ns=1; r=FAIL; }
    fi
    # Each case file whose every case it ran, timed by the runner (the sums of its cases' clock and CPU seconds, as
    # they run at once), for the times the loop records of a test file (conveyor/README.md, The test step).
    [ ! -s "$o.times" ] || awk -F'\t' 'NF == 3 { printf "TESTRUN sec\tconveyor/tests/%s\t%s\t%s\n", $1, $2, $3 }' "$o.times" >> "$log"
    rm -f "$o.times"; marked "$t" || r=FAIL; metaran "$t" || r=FAIL
  elif [ -n "${ecases[$t]:-}" ]; then
    # An engine case file run on its own (above), with its chosen cases.
    shown[$t]=1; nr=${enr[$t]}; echo "== $t (cases: ${ecases[$t]})"; cat "${eout[$t]}" 2>/dev/null; [ "${erc[$t]}" = 0 ] || r=FAIL
    [ "${erc[$t]}" != "$SHARE_NOSTART" ] || ns=1
    # Its time when it ran every case it has, timed by the runner (the sums of its cases' clock and CPU seconds, as
    # they run at once), for the times the loop records of a test file (conveyor/README.md, The test step).
    [ ! -s "${eout[$t]}.times" ] || awk -F'\t' 'NF == 3 { printf "TESTRUN sec\tconveyor/tests/%s\t%s\t%s\n", $1, $2, $3 }' "${eout[$t]}.times" >> "$log"
    marked "$t" || r=FAIL; metaran "$t" || r=FAIL
    [ -z "${etr[$t]:-}" ] || [ $r != ok ] || inputsof "$t" "${etr[$t]}" >> "$log"
  else
    # Its CPU seconds are the shell's children's user and system times (`times`) after it, less those before: the
    # file's process tree, each process counted as it is waited for.
    # The parts of it the coverage map selected (covof), when nothing selected it whole, or the cases the one-file mode
    # runs of it (oparts): CONVEYOR_SHELL_TEST_CASE.
    # Each part it runs is logged as it starts (`TESTRUN case`), as an engine case file's cases are: the step's record
    # names them (testrun.sh), the test cache does not keep the file as passed whole (testlist.sh cachekeep()), and a
    # run that never ends keeps the passes of its other cases (testlist.sh rerunlist()).
    p=$(fparts "$t")
    [ -z "$p" ] || tr , '\n' <<<"$p" | grep . | while IFS= read -r c; do printf 'TESTRUN case\t%s\t%s\n' "$t" "$c"; done >> "$log"
    # It runs under strace when this run traces (TRACE, inputsof above) and it runs whole (trc), but a plugin test file.
    tf=; [ ${#TRACE[@]} = 0 ] || [ -n "$p" ] || [[ $t == *.ts || $t == *.tsx ]] || { trc=1; tf=$o.trace; rm -f "$tf"; }
    echo "== $t${p:+ (parts: $p)}"; s=${EPOCHREALTIME/,/.}; times > "$o.cpu"; [[ $t != *.ts && $t != *.tsx ]] || nr=$o.tmp/p.noroom
    # A meta-runner runs in its card mode (the pack's test.files cardMode, mk above): its own checks, with a stub in
    # place of the files it starts.
    case $t in
      *.mjs) nodecases "$t"; failstop fshare "$t" env "${mk[@]}" ${FAILFAST:+"CONVEYOR_TEST_FAILFAST=$FAILFAST"} "${NODETEST[@]}" ${FAILFAST:+"--import=$NODEHOLD"} "${nargs[@]}" "$t" ;;
      *.py) fshare "$t" env "${mk[@]}" python3 "$t" ${FAILFAST:+-f} ;;
      *.ts|*.tsx) plugintest "$t" ;;
      # An engine case file's run with no case (nocase, above): a selection of a blank, which the file keeps (it gives
      # the runner all its cases only when none is set) and in which the runner finds no case.
      *) failstop fshare "$t" env "${mk[@]}" ${p:+"CONVEYOR_SHELL_TEST_CASE=$p"} ${nocase[$t]:+"CONVEYOR_SHELL_TEST_CASE= "} bash "$t" ;;
    esac 2>&1 | tee "$o"; st=${PIPESTATUS[0]}; [ "$st" = 0 ] || r=FAIL; [ "$st" != "$SHARE_NOSTART" ] || ns=1
    marked "$t" || r=FAIL; metaran "$t" || r=FAIL
    [ -z "$tf" ] || [ $r != ok ] || inputsof "$t" "$tf" >> "$log"; trc=
    times >> "$o.cpu"
    # Its own time and CPU seconds, for the times the loop records of a test file (conveyor/README.md, The test step); not
    # of a run of some of its parts, which is not the file's time.
    [ -n "$p" ] || printf 'TESTRUN sec\t%s\t%s\t%s\n' "$t" "$(awk -v a="$s" -v b="${EPOCHREALTIME/,/.}" 'BEGIN { printf "%.1f", b - a }')" \
      "$(awk 'function c(x, a) { sub(/s$/, "", x); split(x, a, "m"); return a[1] * 60 + a[2] } { gsub(/,/, ".") }
        NR == 2 || NR == 4 { n[NR] = c($1) + c($2) } END { printf "%.1f", n[4] - n[2] }' "$o.cpu")" >> "$log"
    [ -s "$nr" ] || [ -n "$ns" ] || ended "$t" $r "$o" "$p"
  fi
  # Bug #1662: a file that did not start for want of room in the temp space failed, and the engine marked main red on
  # it. It is a host problem, not a failed test: logged `TESTRUN host<TAB><file><TAB><why>` and `-- notrun <file>`
  # (the engine's voidrun(): a run with no result), and the next files do not wait for room again. The same when its
  # temp folder, output file or pipe could not be made (ns).
  if [ -s "$nr" ] || [ -n "$ns" ]; then
    hw=$(head -n 1 "$nr" 2>/dev/null); hw=${hw:-test-changed: $t did not start: its temp folder, output file or pipe could not be made}
    printf 'TESTRUN host\t%s\t%s\n' "$t" "$hw" >> "$log"; echo "-- notrun $t" >> "$log"; rc=1
  else
    echo "-- $r $t" >> "$log"; [ $r = ok ] || rc=1
  fi
done
[ ${#run[@]} -gt 0 ] || echo "no test touches this change"
exit $rc
