# SPDX-License-Identifier: Apache-2.0
# The test files in the snapshot (README.md, The test files in the snapshot): the snapshot's tests part, and the
# command that sets the pack's test settings the Board saves (conveyor.sh test-settings).

# The part counts only what is on or after the test history's start (histstart(), below): each file's runs, failed
# steps, failures, flaky entries and what they give (cpu, median, change, usual, slower); the records keep every line.
# The snapshot's tests part, read from the card records (recs, olds: a retried card's runs count too), the pack, the
# flaky-test record ($FLAKY), the slow-test record (slow.json beside the card records: {filed: [{file, issue}]}, the "Slow test" issues the test rules replaced; nothing writes it now), the test rules' log ($TESTRULESLOG) and the Board's test issues ($TAFILED):
# settings: the pack's slowIssues (true or false), the control record's historyStart (the test history's start, a UTC
#   time, or null), slower ({share, runs, minRuns}) and files (each file's own settings, as the pack holds them), and report (the pack's test.report, {runner, format, path, env,
#   args, option}, null with none: the runner whose report gives a Wall only file's clock seconds, #190), and cpuTime
#   (cpuplan(): {file, was, command}, the test command Record CPU time saves, or {why}; null when it cannot be told);
# suite: the newest whole-suite run on record ($SUITERUNS) on or after the history's start, {time, cpu: the CPU seconds of its files summed, null with
#   none}, null with no run: what a change to a wholeOnly file waits for (#190);
# rules: the test rules (lib/testrules.sh): the pack's switch, guards and rules (testrulesettings()), and last: the
#   list of the last pass (testrulespass()), {time, on, matches, burst}, null before the first, and log: the last
#   TESTRULES_SHOWN lines of the rules' log ($TESTRULESLOG), newest first; null when the pack cannot be read;
# files: each test file main's checkout tracks (a name with `.test.` in it), and each other file with a run on record:
#   a card's test line (times, and clocks: a file timed by the clock only, from its runner's report, has cpu null) or a whole-suite run ($SUITERUNS, suiterec() of lib/testlist.sh); the highest CPU seconds
#   now first, a file with none last: file, cpu (its newest run's that has CPU seconds; null with none), median (of
#   every run on record with CPU seconds), change (cpu against median, as a share: 0.5 is 50% over; null when the
#   median is 0 or null), runs (its last TESTKEEP runs, newest first: {cpu, sec: clock seconds, null on a line that
#   gives none; card (null for a whole-suite run and for a time the test-speed survey saved), time, whole (a
#   whole-suite run), a whole-suite run's result: ok, fail or null, and a survey time's survey: true}; [] for a file never
#   run; a survey time of a file that is not listed is left out), lastRun ({sec, cpu, clockPerCpu, time, whole, and
#   survey: true when it is a survey time} of its newest run; null with none), timedRuns (its runs with CPU seconds),
#   runsOnRecord (its runs on record; its older runs and test edits are not here but in testolder(), below, so the part does not grow with every run),
#   everRun (a run on record at all, one before the history start too: the Board's Never run has none), wholeOnly (its test.files entry's wholeOnly), failedSteps (the test steps
#   that failed with it among the failed files, or with a case it defines that its runner named, or timed out in it;
#   a step that went again counts with the failures of its first run too: failedrun, FAILURE),
#   failures (those steps, newest first, each {card, issue, time, verdict: main, flaky, card or null, cases, caseVerdicts, tail}
#   (FAILURE); tail is null past the newest TESTKEEP), caught and changedToPass (those of them whose card landed: caught when the landed commit left the file as it was,
#   so the fix went into the code; changedToPass when that commit changed the file),
#   flaky (its entries in the flaky-test record, its cases' too, a runner's name for them as well), flakyAgain (the
#   issue of its earlier fix when it is flaky again: two entries within FLAKY_DAYS days, FLAKYAGAIN in lib/flaky.sh; else null), issue (the issue last filed for it, the highest number of the slow-test record's, the test rules' log's and the Board's filings ($TAFILED), else null; the Board's Close its issue as done closes it), slowOnPurpose (its reason, else null), usual (the median of
#   its runs before its last slower.runs runs; null with fewer than slower.minRuns runs on record) and slower; a wholeOnly
#   file (a runner that starts other test files whole, each timed on its own) has slower false; optimize: each issue the Board filed for it ($TAFILED: Optimize, and older
#   speed-up, issues), and each Tests page card of no issue ($TACARDS: issue null, with card, null until picked, and
#   name "No issue"), newest first: {issue, time (filed), state (open: no card took it; building; blocked, with reason;
#   landed, with sha and landed, the time; closed: its card closed it without landing), fix, into, before and after
#   (from the bugproof line's speed of its landed card, else of its newest: fix is sped up, split, merged or deleted,
#   into the test files a split added or a merge changed, or, for a delete, those the last review of its landed card
#   named on its COVERED-BY lines; null and [] with none), since (the median CPU seconds of the
#   file's runs after it landed; null with none or before it lands), sinceRuns (their count), and mutantsBefore and
#   mutantsAfter (the file's newest mutation check that ended done before it landed, and after: {at, killed, of};
#   null with none or before it lands)}; a Board filing of another kind (Fix failures, Fix hollow cases, Fix the
#   waiting, Make it run, Delete it) is listed here as well; removed: true for a
#   file main's checkout no longer tracks whose landed Optimize deleted or merged it (the totals leave it out);
#   hollow: the cheap check's hollow cases of a JavaScript or TypeScript file (testhollow(), below), [{case, kind,
#   reason}], [] with none; null for a file of another kind or not in main's checkout;
#   proxy: the lines of a file of main's checkout that start another test file or the suite runner, or poll a real
#   process (testproxy(), below), [{line, kind: runs or polls, text, why: the comment beside it, null with none}], []
#   with none; null for a file not in main's checkout;
#   mutation: its newest mutation check (lib/mutate.sh), {file, at, sha, seed, state, reason, of (its mutants), tried,
#   killed, survived ([{source, line, kind, before, after}]), noresult, notMutated, end}; null when none was made;
#   mutationPlace: its place in the mutation checks' asked list ($MUTS/asked, mutask()), 1 first; null when not asked;
#   cases: the names of the cases a file defines in main's checkout, A to Z, [] with none: a shell file's (.sh, .bash)
#   `t_<case>() {` lines the runner selects (not its helpers or a heredoc's lines), another's by its language's row of
#   TESTEDIT_TABLE (TABLECASES); null for a file of a kind with no row; the Board's search matches them;
#   waits: the waits its newest judge that ended done named on WAIT lines (lib/testaction.sh tawaits()), [{case, kind,
#   at, reason}]; null when no judge of it named waits or none (a judge from before WAIT lines were asked for);
#   neverRun: why a file of main's checkout with no run on record never ran, when the engine can tell (neverwhy(),
#   below), {kind, reason}; null for a file with a run, or one it cannot tell of; a file that only a Board filing names is listed too;
# slower: the files slower than their usual, by name: each of their last slower.runs runs over usual by more than slower.share;
# edits: each entry of the landed lines' testedits (testedits(), below), newest first, with its card, issue and time;
#   a file's newest TESTKEEP alone, so the list grows with the test files, not with the cards that land;
# totals: files (those with CPU seconds on record), slower, and steps: the card test steps that ran in
#   the 7 days to today ({count, waitSec: their seconds waiting for a test slot, runSec: their test commands' seconds}).
TESTKEEP=5
# A runner (the engine's conveyor/conveyor.test.sh) names its cases' failures and flaky entries as its own, while the
# times name each case file it ran: a case counts for the named file alone when that file defines it (`t_<case>()` or
# `<case>()`), else for the named file and the test files of main's checkout that define it and name that runner (a
# case file runs itself through its runner). A file with a case of the same name that runs alone or through another
# runner is not that runner's. testowners sets the caller's defs (each case name to the files that define it) and refs
# (each test file to the test file names it holds); OWNERS is the jq that reads them, given as files (they grow with
# the project, too long for an argument: `--slurpfile defs <(printf '%s' "$defs")`, and refs the same), at the start
# of the program: caseowners (the files a flaky entry's case counts for) and failedfiles (the files a failed test line counts for).
testowners() {
  local tf=()
  # Main's test files (testtracked(), lib/issues.sh), as paths, not globs; none, no search (git grep with no path
  # searches the whole checkout).
  mapfile -d '' -t tf < <(testtracked -z 2>/dev/null)
  defs='{}' refs='{}'
  [ ${#tf[@]} != 0 ] || return 0
  # Both from one git grep and one jq, as the snapshot reads them each time: a function's match ends in (), a name's
  # never does (its last character is a letter or a digit), and neither match can hold the other's.
  local o=()
  mapfile -t o < <(git -C "$MAIN" --literal-pathspecs grep -oE -e '^(t_)?[A-Za-z0-9_]+\(\)' -e '[A-Za-z0-9_.-]+\.test\.[A-Za-z0-9]+' -- "${tf[@]}" 2>/dev/null \
    | jq -cRn '[inputs] | (map(capture("^(?<f>.+):(t_)?(?<c>[A-Za-z0-9_]+)\\(\\)$")) | group_by(.c) | map({key: .[0].c, value: [.[].f] | unique}) | from_entries),
      (map(select(endswith("()") | not) | capture("^(?<f>[^:]+):(?<n>.+)$")) | group_by(.f) | map({key: .[0].f, value: [.[].n] | unique}) | from_entries)')
  [ ${#o[@]} = 2 ] && defs=${o[0]} refs=${o[1]}
}
OWNERS='$defs[0] as $defs | $refs[0] as $refs | def owners($f; $c): ($defs[$c // ""] // []) as $d | ($f | split("/")[-1]) as $n
      | if $c == null or any($d[]; . == $f) then [$f] else [$f] + [$d[] | select(any($refs[.][]?; . == $n))] end;
    def caseowners: index(": ") as $i | if $i == null then [.] else owners(.[:$i]; .[$i + 2:]) end;
    def failedfiles: [(.failures.files | arrays | .[] | objects | (.file | strings) as $f
        | if (.cases | arrays | length) > 0 then .cases[] | owners($f; .name | strings)[] else $f end), (.failures.timeout.file? | strings)] | unique;'
# One failed test line, as a failure of the file $f it counts for (failedfiles), read with OWNERS: {card, issue, time,
# verdict, cases, caseVerdicts, tail}. verdict: the test line's verdicts (verdicts(), lib/mainred.sh) of the cases that count for $f,
# main when one of them failed on main too, else flaky when one failed and then passed when run again, else card (the
# card's own change made it fail: the test did its job); null when the line has none for it (a line written before
# verdicts were kept). cases: the names of its failing cases that count for $f ([] for a file that failed naming no
# case). caseVerdicts: each of those cases with a verdict, its own ({<case>: <verdict>}): a step whose cases' verdicts differ is a catch of the card for its card cases and a failure to fix for the rest (the Board's caughtOf() and fixable(); R323: one verdict for the step hid the catch).
# tail: the last 1500 characters of the step's output (the line's tail), null with none. failedrun: a test line as a failed step: a line that failed, with its first run's failures (in rerun, firstrun(), when the run went again) added to its own, so a case that passed on the run again (its verdict flaky) still counts while another file
# failed again, with the first run's output's end as its tail (the files that failed again kept in again, with the
# line's own tail); a first run's time-out as its file failing naming no case; a line that passed on re-run (card():
# `test pass` with the first run's failures and output's end in rerun) with those failures and that tail as its own;
# no other line.
FAILURE='def failedrun: if .result == "fail" then (if (.rerun.failures | type) == "object"
        then .again = failedfiles | .failures.files = [(.failures.files | arrays | .[]), (.rerun.failures.files | arrays | .[]),
          (.rerun.failures.timeout.file? | strings | {file: ., cases: []})] else . end)
      elif .result == "pass" and (.rerun.failures | type) == "object" then .failures = .rerun.failures | .tail = .rerun.tail
      else empty end;
    def failure($f): [.verdicts | arrays | .[] | objects | select(any((.case | strings | caseowners[]); . == $f)) | .verdict | strings] as $v
    | {card, issue, time,
       verdict: (if any($v[]; . == "main") then "main" elif any($v[]; . == "flaky") then "flaky" elif any($v[]; . == "card") then "card" else null end),
       cases: [.failures.files | arrays | .[] | objects | (.file | strings) as $x | .cases | arrays | .[] | (.name | strings) as $n
         | select(any(owners($x; $n)[]; . == $f)) | $n] | unique,
       caseVerdicts: ([.verdicts | arrays | .[] | objects | (.case | strings) as $c | ($c | index(": ")) as $i | select($i != null) | select(any(owners($c[:$i]; $c[$i + 2:])[]; . == $f)) | {key: $c[$i + 2:], value: (.verdict | strings)}] | from_entries),
       tail: (if (.again | type) == "array" and (any(.again[]; . == $f) | not) then .rerun.tail else .tail end | (strings | .[-1500:]) // null)};'
# What a card did to the test files it changed that main already had (#76), written on its landed line as testedits:
# one entry a file, {file, read, removedAsserts, changedExpected, skipsAdded, timeoutsRaised, casesDeleted}. The one
# table of patterns, a language a row: the file name endings it reads and the jq regular expressions of an assertion,
# a skip, only or todo mark, a case and a timeout (its number captured as n). It is also the case reader of the hollow
# check (HOLLOW_JQ, lib/testrun.sh). A case is a shell `t_<name>()`, `test<name>()` or bats `@test`; a node:test, Jest
# or Vitest `test(` or `it(` (`.only`, `.skip` and the like too) whose name is a literal string on its line (a name
# from a variable, a template with ${...} or a test.each table is not read); a pytest `def test<name>(`; and a Go
# `func Test<Name>(`. A file whose ending no row has is a test file all the same, recorded as edited, not read: read
# false, its counts null.
TESTEDIT_TABLE='def table: [
  {ext: ["sh", "bash", "bats"], assert: "\\|\\|\\s*fail\\b|\\bassert[A-Za-z_]*\\b", skip: "^\\s*skip\\b",
   case: "^\\s*(function\\s+)?(t_|test)[A-Za-z0-9_]*\\s*\\(\\)|^\\s*@test\\s",
   timeout: "(\\btimeout\\s+|--timeout[= ]|^#\\s*timeout:\\s*)(?<n>[0-9][0-9_]*)"},
  {ext: ["js", "mjs", "cjs", "jsx", "ts", "mts", "cts", "tsx"], assert: "\\b(expect|assert)(\\.[A-Za-z]+)*\\s*\\(",
   skip: "\\b(it|test|describe|suite)\\.(skip|only|todo)\\b|\\b[xf](it|describe|test)\\s*\\(|\\bt\\.(skip|todo)\\s*\\(|[{,]\\s*(skip|only|todo)\\s*:\\s*(true|[\"\u0027`])",
   case: "^\\s*[xf]?(it|test)(\\.[A-Za-z]+)?\\s*\\(\\s*([\"\\x27]|`(?![^`]*\\$\\{))",
   timeout: "\\b(timeout|setTimeout)\\s*[:(=]\\s*(?<n>[0-9][0-9_]*)"},
  {ext: ["py"], assert: "^\\s*assert\\b|\\bself\\.(assert[A-Za-z]*|fail)\\s*\\(|\\bpytest\\.(raises|fail)\\b",
   skip: "@pytest\\.mark\\.(skip|skipif|xfail)\\b|\\bpytest\\.(skip|xfail)\\s*\\(|@unittest\\.(skip|skipIf|skipUnless|expectedFailure)\\b|\\bself\\.skipTest\\s*\\(",
   case: "^\\s*(async\\s+)?def\\s+test[A-Za-z0-9_]*\\s*\\(",
   timeout: "(@pytest\\.mark\\.timeout\\s*\\(\\s*(timeout\\s*=\\s*)?|\\btimeout\\s*=\\s*)(?<n>[0-9][0-9_]*)"},
  {ext: ["go"], assert: "\\bt\\.(Error|Errorf|Fatal|Fatalf|Fail|FailNow)\\s*\\(|\\b(assert|require)\\.[A-Z][A-Za-z]*\\s*\\(",
   skip: "\\bt\\.(Skip|Skipf|SkipNow)\\s*\\(",
   case: "^func\\s+Test([A-Z0-9_][A-Za-z0-9_]*)?\\s*\\(",
   timeout: "\\b(time\\.After|WithTimeout)\\s*\\([^0-9)]*(?<n>[0-9][0-9_]*)"}];'
# The cases of the files jq -Rn reads (after TESTEDIT_TABLE), each by its language's row: {<file>: [names, A to Z]}, no key for a file of a kind with no row. A name is what the quotes after its case start hold, else that start's last word.
TABLECASES='reduce inputs as $l ({}; input_filename as $f | (first(table[] | select(any(.ext[]; . == ((($f | capture("\\.(?<x>[^./]+)$").x) // "") | ascii_downcase)))) // null) as $t
  | if $t == null then . else .[$f] += [$l | select(test($t.case)) | (match($t.case) | .offset + .length) as $e | .[:$e] as $m | .[$e:]
    | if ($m | test("[\"\u0027`]$")) then capture("^(?<n>(\\\\.|[^\\\\" + $m[-1:] + "])*)").n elif test("^\\s*\"") then capture("^\\s*\"(?<n>(\\\\.|[^\\\\\"])*)").n
      else [$m | scan("[A-Za-z0-9_]+")] | last end | gsub("\\\\(?<c>.)"; .c)] end) | map_values(unique)'
# The counts, from the file as main had it and as the card left it (the input, raw: the two joined by a NUL; nothing
# after it for a file the card deleted) and its path ($f). Each is read as statements: a line, or an assertion line
# with the lines after it that close its brackets, so an expected value on a line of its own is part of its assertion.
# A statement the card removes and adds again unchanged (a move) counts for nothing. A removed and an added statement
# that differ only in the number of a timeout pair up: a raised timeout when the new number is higher. Of the
# assertions left, a removed and an added one with the same call and actual value pair up (key): a changed expected
# value when the expected value (val) differs, while a changed message alone counts for nothing. Removed assertions,
# added marks and deleted cases are what the file lost or gained on balance (never below 0), so a case renamed or an
# assertion rewritten counts for nothing.
TESTEDIT_JQ='def count($re): map(select(test($re))) | length;
  def minus($b): (reduce $b[] as $x ({}; .[$x] += 1)) as $n
    | reduce .[] as $x ({n: $n, o: []}; if (.n[$x] // 0) > 0 then .n[$x] -= 1 else .o += [$x] end) | .o;
  def norm: gsub("\\s+"; " ") | gsub("^ | $"; "");
  # Strings to S, numbers to N, literals to L; with $js also a regular expression literal (a / where a value starts,
  # its escapes and [classes] read) to R, so its brackets, quotes and commas are not read as code.
  def mask($js): gsub("\"([^\"\\\\]|\\\\.)*\"|\u0027([^\u0027\\\\]|\\\\.)*\u0027|`([^`\\\\]|\\\\.)*`"
      + (if $js then "|(?<p>^|[(,=:\\[!&|?{};])\\s*/(?![/*])([^/\\\\\\[\\n]|\\\\.|\\[([^\\]\\\\\\n]|\\\\.)*\\])+/[A-Za-z]*" else "" end);
      if .p == null then "S" else .p + "R" end) | gsub("\\b[0-9][0-9_.]*"; "N")
    | gsub("\\b(true|false|null|undefined)\\b"; "L") | norm;
  def mask: mask(false);
  def depth($js): mask($js) | [explode[] | if . == 40 or . == 91 or . == 123 then 1 elif . == 41 or . == 93 or . == 125 then -1 else 0 end] | add // 0;
  # The arguments of a call, its text read from just after its "(": {args, rest: the text after its ")"}. A / where a
  # value starts (p: the last character that is not a space) opens a regular expression literal (q 47, k: in a class).
  def call: explode as $c | (reduce range(0; $c | length) as $i ({d: 0, q: null, e: false, k: false, p: 40, s: 0, a: [], end: null};
      if .end != null then . else $c[$i] as $h
      | (if .q == 47 then (if .e then .e = false elif $h == 92 then .e = true elif .k then (if $h == 93 then .k = false else . end)
          elif $h == 91 then .k = true elif $h == 47 then .q = null else . end)
        elif .q != null then (if .e then .e = false elif $h == 92 then .e = true elif $h == .q then .q = null else . end)
        elif $h == 47 and (.p | IN(40, 44, 61, 58, 91, 33, 38, 124, 63, 123, 59)) and ($c[$i + 1] | IN(47, 42) | not) then .q = 47 | .k = false
        elif $h == 34 or $h == 39 or $h == 96 then .q = $h
        elif $h == 40 or $h == 91 or $h == 123 then .d += 1
        elif $h == 41 or $h == 93 or $h == 125 then (if .d == 0 then .a += [$c[.s:$i] | implode] | .end = $i else .d -= 1 end)
        elif $h == 44 and .d == 0 then .a += [$c[.s:$i] | implode] | .s = $i + 1
        else . end) | if $h | IN(32, 9, 10, 13) then . else .p = $h end end)) as $r
    | {args: ($r.a + (if $r.end == null then [$c[$r.s:] | implode] else [] end) | map(norm | select(. != ""))),
       rest: (if $r.end == null then "" else $c[$r.end + 1:] | implode end)};
  def pair(f): . as $in | ($in.r | map({s: ., k: f})) as $rk | reduce ($in.a[] | {s: ., k: f}) as $x ({r: $rk, a: [], p: []};
      (if $x.k == null then null else first(range(0; .r | length) as $j | select(.r[$j].k == $x.k) | $j) // null end) as $j
      | if $j == null then .a += [$x.s] else .p += [[.r[$j].s, $x.s]] | .r |= del(.[$j]) end) | .r |= map(.s);
  ((($f | capture("\\.(?<x>[^./]+)$").x | ascii_downcase) // "") as $x | first(table[] | select(any(.ext[]; . == $x))) // null) as $t
  | if $t == null then {file: $f, read: false, removedAsserts: null, changedExpected: null, skipsAdded: null, timeoutsRaised: null, casesDeleted: null}
    else def stmts: split("\n") | reduce .[] as $l ({o: [], c: null, d: 0, n: 0};
        if .c != null then .c += "\n" + $l | .d += ($l | depth($t.ext[0] != "sh")) | .n += 1 | if .d <= 0 or .n >= 50 then .o += [.c] | .c = null else . end
        elif ($l | test($t.assert)) and ($l | depth($t.ext[0] != "sh")) > 0 then .c = $l | .d = ($l | depth($t.ext[0] != "sh")) | .n = 1
        else .o += [$l] end) | .o + if .c == null then [] else [.c] end;
      # An assertion as key (the call and its actual value) and val (its expected value), its message left out: a shell
      # test the text before `|| fail`; expect(actual).matcher(expected); assert.method(actual, expected, message), or
      # assert(value, message) and assert.ok, whose value is masked in key and is val. Python: self.assertX(actual,
      # expected, msg), self.assertTrue(value, msg) and the like as assert.ok, and `assert value, msg` as assert(value,
      # msg). Go: t.Errorf(msg, ...) and the like are their message alone (val empty), and testify assert.X(t,
      # expected, ..., msg) and require.X(...) are keyed by the call and t, val the value after t.
      def parts: if $t.ext[0] == "sh" then sub("\\s*\\|\\|\\s*fail\\b[\\s\\S]*$"; "") | {key: mask, val: norm}
        elif $t.ext[0] == "py" and test("\\bself\\.(assert[A-Za-z]*|fail)\\s*\\(") then
          capture("^(?<h>[\\s\\S]*?\\bself\\.(?<n>assert[A-Za-z]*|fail))\\s*\\((?<b>[\\s\\S]*)$") as $m | ($m.b | call) as $a
          | if $m.n == "fail" then {key: ($m.h + "() " + $a.rest | norm), val: ""}
            elif $m.n | IN("assertTrue", "assertFalse", "assertIsNone", "assertIsNotNone") then {key: ($m.h + "(" + ($a.args[0] // "" | mask) + ") " + $a.rest | norm), val: ($a.args[0] // "")}
            else {key: ($m.h + "(" + ($a.args[0] // "") + ") " + $a.rest | norm), val: ($a.args[1] // "")} end
        elif $t.ext[0] == "py" and test("^\\s*assert\\b") then (sub("^\\s*assert\\b"; "") | call) as $a
          | {key: ("assert " + ($a.args[0] // "" | mask)), val: ($a.args[0] // "")}
        elif $t.ext[0] == "go" and test("\\bt\\.(Error|Errorf|Fatal|Fatalf|Fail|FailNow)\\s*\\(") then
          capture("^(?<h>[\\s\\S]*?\\bt\\.[A-Za-z]+)\\s*\\((?<b>[\\s\\S]*)$") as $m | {key: ($m.h + "() " + ($m.b | call).rest | norm), val: ""}
        elif $t.ext[0] == "go" and test("\\b(assert|require)\\.[A-Z][A-Za-z]*\\s*\\(") then
          capture("^(?<h>[\\s\\S]*?\\b(assert|require)\\.[A-Za-z]+)\\s*\\((?<b>[\\s\\S]*)$") as $m | ($m.b | call) as $a
          | {key: ($m.h + "(" + ($a.args[0] // "") + ") " + $a.rest | norm), val: ($a.args[1] // "")}
        elif test("\\bexpect\\s*\\(") then capture("^(?<h>[\\s\\S]*?\\bexpect)\\s*\\((?<b>[\\s\\S]*)$") as $m | ($m.b | call) as $a
          | ($a.rest | capture("^(?<m>(\\s*\\.\\s*[A-Za-z_$]+)+)\\s*\\((?<b>[\\s\\S]*)$") // null) as $x
          | if $x == null then {key: ($m.h + "(" + ($a.args | join(", ")) + ")" + $a.rest | norm), val: ""}
            else ($x.b | call) as $e | {key: ($m.h + "(" + ($a.args | join(", ")) + ")" + $x.m + "() " + $e.rest | norm), val: ($e.args | join(", "))} end
        elif test("\\bassert(\\.[A-Za-z]+)*\\s*\\(") then capture("^(?<h>[\\s\\S]*?\\bassert(?<m>(\\.[A-Za-z]+)*))\\s*\\((?<b>[\\s\\S]*)$") as $m
          | ($m.b | call) as $a | ($m.m | sub("^.*\\."; "")) as $n
          | if $n | IN("", "ok", "ifError") then {key: ($m.h + "(" + ($a.args[0] // "" | mask(true)) + ") " + $a.rest | norm), val: ($a.args[0] // "")}
            elif $n == "fail" then {key: ($m.h + "() " + $a.rest | norm), val: ""}
            else {key: ($m.h + "(" + ($a.args[0] // "") + ") " + $a.rest | norm), val: ($a.args[1] // "")} end
        else {key: mask(true), val: norm} end;
      split("\u0000") as $v | ($v[0] | stmts) as $o | ($v[1] // "" | stmts) as $w
      | {r: ($o | minus($w)), a: ($w | minus($o))} as $c
      | def tval: capture($t.timeout).n | gsub("_"; "") | tonumber;
      ($c | pair(if test($t.timeout) then sub($t.timeout; "T") else null end)) as $to
      | ($to | {r, a} | pair(if test($t.assert) then parts.key else null end)) as $ex
      | {file: $f, read: true, removedAsserts: ([($ex.r | count($t.assert)) - ($ex.a | count($t.assert)), 0] | max),
         changedExpected: ([$ex.p[] | select((.[0] | parts.val) != (.[1] | parts.val))] | length),
         skipsAdded: ([($c.a | count($t.skip)) - ($c.r | count($t.skip)), 0] | max),
         timeoutsRaised: ([$to.p[] | select((.[1] | tval) > (.[0] | tval))] | length),
         casesDeleted: ([($c.r | count($t.case)) - ($c.a | count($t.case)), 0] | max)} end'
testedits() { # <worktree>: its staged change's testedits, a JSON list (empty when it changed no test file main had)
  local n s f o w e out='' tf=()
  # Each changed (M) or deleted (D) test file, as its status and path: of the test files the card's base had
  # (testtracked(), lib/issues.sh), taken as paths, not globs; none, no diff (one with no path takes every file).
  mapfile -d '' -t tf < <(testtracked -z "$1" HEAD); wait $! || return 1
  [ ${#tf[@]} != 0 ] || { echo '[]'; return 0; }
  n=$(git -C "$1" --literal-pathspecs diff --cached --name-status --no-renames --diff-filter=MD -z -- "${tf[@]}" | jq -Rsc 'split("\u0000") | map(select(. != ""))') || return 1
  while IFS= read -r -d '' s && IFS= read -r -d '' f; do
    o=$(git -C "$1" show "HEAD:$f") || return 1
    w=''; [ "$s" = D ] || w=$(git -C "$1" show ":$f") || return 1
    e=$(printf '%s\0%s' "$o" "$w" | jq -Rsc --arg f "$f" "$TESTEDIT_TABLE$TESTEDIT_JQ") || return 1
    out+=$e
  done < <(jq -j '.[] | . + "\u0000"' <<<"$n")
  jq -sc '.' <<<"$out"
}
# The cheap check for hollow cases (#77), with no model: in each JavaScript or TypeScript test file of main's checkout
# (HOLLOWFILES), a case (a line that starts `it(` or `test(` with its name, `.only` or `.concurrent` too) is its line
# after the name and the lines up to the next case, skipped case, describe or hook (a hook is its bare call, such as
# `before(`: a variable named before, as in `before.click()`, does not end a case). A case with no `expect(` and no
# `assert` (assert.equal, t.assert, a helper named assert...) is no-assert; one whose every assertion is
# `expect(...).toBeDefined()` or `.toBeTruthy()` is defined-only. An assertion in a comment counts too: the check may
# miss a hollow case, never flag a case that asserts. testhollow prints {file: [{case, kind, reason}]}, a file with
# none []. A judge's own HOLLOW lines (lib/testaction.sh tahollow()) take the place of these on the Board.
# One awk reads every file, a line at a time (jq, a regular expression a line, took over half a CPU second on 70
# files), and prints a line for each hollow case: its file, its name and its kind, between tabs.
HOLLOWFILES='\.test\.[cm]?[jt]sx?$'
HOLLOW_AWK='function flush() {
    if (name != "" && e + a == 0) print f "\t" name "\tno-assert"
    else if (name != "" && a == 0 && d >= e) print f "\t" name "\tdefined-only"
    name = ""; e = 0; a = 0; d = 0
  }
  function count(s,  t) {
    t = s; e += gsub(/(^|[^A-Za-z0-9_$])expect[ \t]*\(/, "", t)
    t = s; a += gsub(/(^|[^A-Za-z0-9_$])assert/, "", t)
    t = s; d += gsub(/\.toBe(Defined|Truthy)[ \t]*\(/, "", t)
  }
  FNR == 1 { flush(); f = FILENAME; sub(/^\.\//, "", f) }
  match($0, /^[ \t]*((it|test|describe|suite)([.](only|skip|todo|concurrent|each|failing|sequential))*|before|after|beforeEach|afterEach|beforeAll|afterAll)[ \t]*\(/) {
    flush()
    w = substr($0, 1, RLENGTH); sub(/^[ \t]*/, "", w); sub(/[ \t]*\($/, "", w)
    rest = substr($0, RLENGTH + 1); sub(/^[ \t]*/, "", rest); q = substr(rest, 1, 1)
    if ((w == "it" || w == "test" || w == "it.only" || w == "test.only" || w == "it.concurrent" || w == "test.concurrent") && (q == "\047" || q == "\"" || q == "`")) {
      i = index(substr(rest, 2), q)
      if (i > 1) { name = substr(rest, 2, i - 1); gsub(/\t/, " ", name); count(substr(rest, i + 2)) }
    }
    next
  }
  name != "" { count($0) }
  END { flush() }'
# Each file is given to awk as ./<path>, so a name with = in it is never read as an assignment; xargs gives them in
# runs that fit the argument limit (awk starts each file afresh).
testhollow() { # <each test file of main's checkout>...
  local f fs=()
  for f; do [[ $f =~ $HOLLOWFILES ]] && [ -f "$MAIN/$f" ] && fs+=("./$f"); done
  [ ${#fs[@]} -gt 0 ] || { echo '{}'; return; }
  (cd "$MAIN" && printf '%s\0' "${fs[@]}" | LC_ALL=C xargs -0 awk "$HOLLOW_AWK") \
    | jq -Rnc --rawfile fs <(printf '%s\n' "${fs[@]}") '($fs | split("\n") | map(select(. != "") | {key: .[2:], value: []}) | from_entries) as $all
    | reduce (inputs | split("\t") | select(length == 3)) as [$f, $c, $k] ($all; .[$f] += [{case: $c, kind: $k,
        reason: (if $k == "no-assert" then "no expect or assert call" else "its only assertions are toBeDefined or toBeTruthy" end)}])'
}
# The proxy checks (#780), found by reading the test files of main's checkout, with no test run and no model: each line
# of a file that starts another test file or the suite runner (kind runs) or polls a real process (kind polls). A line
# that ends in a backslash is read with the lines it goes on to, as one. A line is read as commands, split at ; & | (
# $( and ` (never inside single quotes, and inside double quotes only at $( and `, so a command quoted as text is not
# read; a ( or $( starts its quotes afresh); each command is read from its first word on, past quotes, { } ) and !, a variable set before it (its value
# quoted or not), the words then, do, else, if, while, until, exec, time, command, nohup and env, timeout with
# its time, an interpreter (bash, sh, zsh, node, python, python3, ruby, perl, bun, deno) with its options, and ./.
# runs: that word is a path ending in a test file's suffix (.test.<ext>), or is one of the runners (the pack's
# test.command and test.full, conveyor/conveyor.test.sh and .conveyor/test-full.sh, each read the same way; a path
# that ends in /<runner> too) with the runner's other words after it, except .conveyor/test-changed.sh with --check,
# --checks, --map, --funcs or --parts, which exits before it runs a test file. polls: that word is one of the pack's
# test.pollHelpers (wait_until by default). A comment (a line that starts # or //, or the end of a line from a # or //
# after a space and outside quotes), a helper's own definition and a word set alone (NAME=value) start no command; a
# command in a heredoc or a string over several lines can be marked too. why: the comment at the end of the line,
# else the comment lines right above it, joined; null with none: the card rule asks for a comment that says why.
# PROXY_AWK prints a line for each mark: its file, the line number its command is on, kind, that line's text and why, between tabs.
# shellcheck disable=SC2016 # awk's own $0 and $(, not the shell's
PROXY_AWK='function norm(s,  t) {
    do { t = s
      sub(/^[ \t!{})"\047]+/, "", s); sub(/^[A-Za-z_][A-Za-z0-9_]*=([^ \t"\047]|\047[^\047]*\047|"[^"]*")*[ \t]+/, "", s)
      sub(/^(then|do|else|if|while|until|exec|time|command|nohup|env)([ \t]+|$)/, "", s)
      sub(/^timeout[ \t]+(-[^ \t]+[ \t]+)*[0-9.]+[smhd]?([ \t]+|$)/, "", s)
      sub(/^(bash|sh|zsh|node|python3?|ruby|perl|bun|deno)([ \t]+-[^ \t]+)*([ \t]+|$)/, "", s)
      sub(/^\.\//, "", s)
    } while (s != t)
    return s
  }
  function first(s) { sub(/[ \t].*/, "", s); sub(/["\047)]+$/, "", s); return s }
  function ends(s, x) { return s == x || (length(s) > length(x) && substr(s, length(s) - length(x)) == "/" x) }
  function said(s) { gsub(/\t/, " ", s); sub(/^[ \t]+/, "", s); sub(/[ \t]+$/, "", s); return length(s) > 300 ? substr(s, 1, 300) "..." : s }
  # mark: the physical line p of the command line read, its text up to the comment and why.
  function mark(k, p,  why, t) {
    t = tx[p]; why = ""
    if (cut < length(buf) + 1 && (p == pn || off[p + 1] > cut)) { why = substr(buf, cut); sub(/^(#+|\/\/+)[ \t]*/, "", why); t = substr(t, 1, cut - off[p]) }
    sub(/\\$/, "", t)
    if (why == "") why = above
    print f "\t" ln[p] "\t" k "\t" said(t) "\t" said(why)
  }
  BEGIN { nr = split(ENVIRON["PROXY_RUNNERS"], rr, "\n"); np = split(ENVIRON["PROXY_POLLS"], pp, "\n")
    # cand: what a line must hold to be read at all (a test file suffix, the name of a runner or of a helper), so the
    # character walk below runs on few lines.
    cand = "\\.test\\.[A-Za-z0-9]"
    for (i = 1; i <= nr; i++) { rr[i] = norm(rr[i]); rw[i] = first(rr[i]); rt[i] = rr[i]; sub(/^[^ \t]*[ \t]*/, "", rt[i]); if (rw[i] != "") cand = cand "|" rx(rw[i]) }
    for (i = 1; i <= np; i++) if (pp[i] != "") cand = cand "|" rx(pp[i]) }
  function rx(s) { gsub(/[][\\.^$|?*+(){}\/]/, "\\\\&", s); return s }
  FNR == 1 { f = FILENAME; sub(/^\.\//, "", f); above = ""; prev = 0; pn = 0; buf = "" }
  pn == 0 && /^[ \t]*(#|\/\/)/ { c = $0; sub(/^[ \t]*(#+|\/\/+)[ \t]*/, "", c); above = (prev ? above " " : "") c; prev = 1; next }
  # The command line: the physical lines joined where one ends with a backslash, as the shell reads them; off[], ln[]
  # and tx[] hold where each starts in buf, its line number and its text, so a mark names the line its command is on.
  { t = $0; sub(/\\$/, "", t); off[++pn] = length(buf) + 1; ln[pn] = FNR; tx[pn] = $0; buf = buf t
    if ($0 ~ /\\$/) next }
  buf !~ cand { prev = 0; above = ""; pn = 0; buf = ""; next }
  { line = buf; def = ""; delete mk
    # A function the line defines (name() or function name): its own name there is no call.
    if (match(line, /^[ \t]*(function[ \t]+)?[A-Za-z_][A-Za-z0-9_]*[ \t]*\(\)/)) { def = substr(line, 1, RLENGTH); sub(/^[ \t]*(function[ \t]+)?/, "", def); sub(/[ \t]*\(\)$/, "", def) }
    # The commands of the line, split where the shell would start one: never inside single quotes, inside double
    # quotes only at $( or `, and up to a # (or //) that starts a comment, outside quotes. A ( or $( starts its quotes
    # afresh, as the shell does, and its ) gives back the double quote it was in (st[], sp), so the quotes inside a
    # "$( )" do not turn the rest of the line into text.
    n = 0; sq = 0; dq = 0; sp = 0; from = 1; L = length(line); cut = L + 1
    for (k = 1; k <= L; k++) { ch = substr(line, k, 1)
      if (sq) { if (ch == "\047") sq = 0; continue }
      if (ch == "\\") { k++; continue }
      if (ch == "\047" && !dq) { sq = 1; continue }
      if (ch == "\"") { dq = !dq; continue }
      if (ch == ")" && !dq && sp > 0) { dq = st[sp--]; continue }
      if (ch == "(" && (!dq || substr(line, k - 1, 1) == "$")) { st[++sp] = dq; dq = 0 }
      if (!dq && (k == 1 || substr(line, k - 1, 1) ~ /[ \t]/) && (ch == "#" || substr(line, k) ~ /^\/\/([ \t]|$)/)) { cut = k; break }
      if (ch !~ /[;&|(`]/ || (dq && ch != "`" && !(ch == "(" && substr(line, k - 1, 1) == "$"))) continue
      sf[++n] = from; seg[n] = substr(line, from, k - from); from = k + 1 }
    sf[++n] = from; seg[n] = substr(line, from, cut - from)
    for (j = 1; j <= n; j++) {
      s = norm(seg[j]); w = first(s); rest = s; sub(/^[^ \t]*[ \t]*/, "", rest)
      # A word set alone (NAME=value) starts no command.
      if (w == "" || w ~ /^[A-Za-z_][A-Za-z0-9_]*=/) continue
      # norm() cuts words from the front only, so the command word is at sf[j] + what it cut; p: its physical line.
      pos = sf[j] + length(seg[j]) - length(s); p = 1; while (p < pn && off[p + 1] <= pos) p++
      if (w ~ /\.test\.[A-Za-z0-9]+$/) mk[p, "runs"] = 1
      # .conveyor/test-changed.sh with --check, --checks, --map, --funcs or --parts exits before it runs a test file.
      norun = ends(w, ".conveyor/test-changed.sh") && rest ~ /^(--check|--checks|--map|--funcs|--parts)([ \t"\047);]|$)/
      for (i = 1; i <= nr; i++) if (!norun && rw[i] != "" && ends(w, rw[i]) && (rt[i] == "" || index(rest " ", rt[i] " ") == 1)) mk[p, "runs"] = 1
      for (i = 1; i <= np; i++) if (pp[i] != "" && w == pp[i] && !(j == 1 && w == def)) mk[p, "polls"] = 1
    }
    for (p = 1; p <= pn; p++) { if ((p, "runs") in mk) mark("runs", p); if ((p, "polls") in mk) mark("polls", p) }
    prev = 0; above = ""; pn = 0; buf = "" }'
# testproxy prints {file: [{line, kind, text, why}]} for each test file of main's checkout, a file with none []; a link, or a file below one, is read as no file (it could name one outside the checkout).
testproxy() { # <each test file of main's checkout>...
  local f fs=() run pol c a p x
  for f; do p=$MAIN; while IFS= read -r -d / x || [ -n "$x" ]; do p+=/$x; [ ! -L "$p" ] || continue 2; done < <(printf '%s' "$f"); [ ! -f "$p" ] || fs+=("./$f"); done
  [ ${#fs[@]} -gt 0 ] || { echo '{}'; return; }
  packget test.command c test.full a test.pollHelpers pol || return 1
  run=$(printf '%s\n' "$c" "$a" conveyor/conveyor.test.sh .conveyor/test-full.sh)
  pol=$(jq -r '.[]? | strings' <<<"$pol")
  (cd "$MAIN" && printf '%s\0' "${fs[@]}" | PROXY_RUNNERS=$run PROXY_POLLS=$pol LC_ALL=C xargs -0 awk "$PROXY_AWK") \
    | jq -Rnc --rawfile fs <(printf '%s\n' "${fs[@]}") '($fs | split("\n") | map(select(. != "") | {key: .[2:], value: []}) | from_entries) as $all
    | reduce (inputs | split("\t") | select(length == 5)) as [$f, $n, $k, $t, $w] ($all;
        .[$f] += [{line: ($n | tonumber), kind: $k, text: $t, why: (if $w == "" then null else $w end)}])'
}
# What the Tests part reads of each line of the records (linesum(), lib/records.sh). A project with no test line has
# its part all the same. The steps other than test are those that give a Board filing's state (optimize, below) and a
# card's landed commit (caught, below), as the text of the line names them (so a line that names one in a field of
# its own counts too). Of each, the fields the part reads and none other: a test line's failures, verdicts and output
# only when it failed or ran again (failedrun), its output's last 1500 characters (failure), and a review's reason
# only its COVERED-BY lines (optimize).
TESTLINE='select(test("\"step\":\"(test|picked|bugproof|blocked|closed|landed|review)\"")) | fromjson? | objects
  | def cut: if type == "string" then .[-1500:] else . end;
  {card, issue, step, time, result} + if .step == "test" then {times, clocks, carried, partial, reused, wait, run}
      + (if .result == "fail" or .rerun != null then {verdicts, failures, rerun: (.rerun | if type == "object" and has("tail") then .tail |= cut else . end), tail: (.tail | cut)} else {} end)
    elif .step == "landed" then {sha, testedits} elif .step == "bugproof" then {speed} elif .step == "blocked" then {reason}
    elif .step == "review" then {reason: (.reason | if type == "string" then [split("\n")[] | select(test("^COVERED-BY: [^\\s:]+: "))] | join("\n") else . end)}
    else {} end'
# The test history's start: the control record's testsFrom (`conveyor.sh test-settings history-start`), a UTC time, or
# nothing when none is set (or the record cannot be read: every run then counts). Nothing is deleted: the readers of the
# history (testspart() here, testfacts() in lib/testaction.sh) count only the runs, failures and flaky entries that are
# on or after it. HISTFROM is the one jq filter for that: `fromstart($s)` keeps a record whose .time is on or after
# the start $s ("" for none: all of them); with a start set, a record with no time is left out. Both read the time
# as the same UTC text the records write (2026-11-21T00:00:00Z), so the text compares as the time does.
# `startlines($s)` does it for the card test lines, oldest first: a line on or after the start, and of its times,
# clocks and timed entries only those of a run on or after it. A file the line carried (`carried`: kept as passed, not
# run) has the time of the latest earlier line of that card that did not carry it, did not run only some cases of it
# (`partial`, testlist.sh partran()) and is not a reused pass: that step ran it whole (a failed step saves no times, so
# the later line that carries the file is the only record of its time); a time with no such line is left out.
HISTFROM='def fromstart($s): select($s == "" or ((.time | strings) >= $s));
  def startlines($s): if $s == "" then . else
    (reduce .[] as $l ({h: {}, out: []};
      ($l.card | tostring) as $c | ($l.carried | if type == "array" then . else [] end) as $cf | .h[$c] as $h
      | (reduce ((($l.times, $l.clocks) | objects | keys[]), ($l.timed | arrays | .[] | objects | .file | strings), $cf[]) as $f ({};
          .[$f] = (if any($cf[]; . == $f) then ([$h[]? | select(.r != true and (.c | any(. == $f) | not) and (.p | any(. == $f) | not))] | last | .t) else $l.time end))) as $o
      | .out += [$l | select((.time | strings) >= $s) | (.times, .clocks) |= (if type == "object" then with_entries(select(.key as $k | ($o[$k] | strings) >= $s)) else . end)
          | .timed |= (if type == "array" then map(select(.file as $k | ($o[$k] | strings) >= $s)) else . end)]
      | .h[$c] += [{t: $l.time, c: $cf, p: ($l.partial | if type == "array" then . else [] end), r: ($l.reused == true)}])).out end;'
histstart() { ctl 2>/dev/null | jq -r '.testsFrom // ""' 2>/dev/null || :; }
# The retried lines, then the card records, as the Tests part reads them (TESTLINE), each from its summary (linesum());
# nothing when they cannot be read.
testlines() {
  local td
  td=$(mktemp -d) || return 1
  { olds > "$td/old" && recs > "$td/rec" && linesum "$td/old" "$RETRIED.tests" "$td/o" "$TESTLINE" && linesum "$td/rec" "$STATE.tests" "$td/r" "$TESTLINE" \
      && cat "$td/o" "$td/r"; } 2>/dev/null
  rm -rf "$td"
}
# The runs of the test files on record, in no order, as the Tests part and testolder() read them: each card test
# line's times and clocks ($ls) and each whole-suite run ($su), {file, cpu, sec, card, time, whole, and a whole-suite
# run's result}; and each test edit of a landed line ($cr, the lines oldest first), newest first, with its card, issue and time.
# shellcheck disable=SC2016 # jq's variables, not the shell's
RUNDEFS='def testruns($ls; $su): ($ls[] | . as $l | (.times | objects) as $t | ($l.clocks | objects // {}) as $k | $t + $k | keys[] as $f
        | select(($t[$f] | type) == "number" or ($k[$f] | type) == "number")
        | {file: $f, cpu: (($t[$f] | numbers) // null), sec: (($k[$f] | numbers) // null), card: $l.card, time: $l.time, whole: false}),
       ($su[] | . as $w | .files | objects | to_entries[] | select(.value | type == "object")
        | {file: .key, cpu: ((.value.cpu | numbers) // null), sec: ((.value.sec | numbers) // null), card: null, time: $w.time, whole: true,
           result: ((.value.result | strings) // null)});
  def alledits($cr): [$cr | reverse[] | select(.step == "landed" and (.testedits | type == "array")) | . as $l
        | .testedits[] | objects | select(.file | type == "string") | {card: $l.card, issue: $l.issue, time: $l.time} + .];'
# testolder <test file> -- the runs and test edits of one test file that the Tests part leaves out (its runs and edits
# hold the newest TESTKEEP), for the Board's Timeline, which asks for them when it is opened (`conveyor.sh history test
# <file>`, GET /older of the page server): {file, olderRuns, olderEdits}, each newest first, as runs and edits have
# them. The snapshot does not carry them, so it does not grow with every run on record (#251).
testolder() {
  local ln st
  ln=$(testlines) || return 1; st=$(histstart) # as the Tests part, no run before the test history's start (HISTFROM)
  printf '%s\n' "$ln" | jq -cRn --arg f "$1" --arg st "$st" --argjson keep "$TESTKEEP" --slurpfile su <(jq -cR 'fromjson? | objects' "$SUITERUNS" 2>/dev/null) --slurpfile sv <(testsurvey) "$RUNDEFS$HISTFROM"'
    [inputs | fromjson? | objects] | sort_by(.time) | . as $cr | (map(select(.step == "test")) | startlines($st)) as $ls
    | [testruns($ls; $su), $sv[0][] | select(.file == $f) | fromstart($st)] | sort_by(.time) as $r
    | {file: $f, olderRuns: ($r[:-$keep] | reverse | map(del(.file))), olderEdits: ([alledits($cr)[] | select(.file == $f)][$keep:])}'
}
# The times the latest test-speed survey saved in main's .conveyor/test-times.json (lib/survey.sh), each as a run of
# its file dated by the commit that last wrote it, with no card, as the Tests part and testolder() read them: [{file,
# cpu, sec, card: null, time, whole: false, survey: true}]; [] with none.
testsurvey() {
  local t sv
  t=$(git -C "$MAIN" log -1 --format=%ct -- .conveyor/test-times.json 2>/dev/null)
  [ -n "$t" ] && sv=$(git -C "$MAIN" show HEAD:.conveyor/test-times.json 2>/dev/null | jq -c --argjson t "$t" '[.files | objects | to_entries[]
      | select(.value | type == "object") | {file: .key, cpu: ((.value.cpu | numbers) // null), sec: ((.value.sec | numbers) // null), card: null,
        time: ($t | todate), whole: false, survey: true} | select(.cpu != null or .sec != null)]' 2>/dev/null) && [ -n "$sv" ] || sv='[]'
  printf '%s\n' "$sv"
}
# The case scan of test files (testspart(): the cases each file defines; owncases(), lib/testlist.sh: the cases a card's
# change adds or changes), an awk program run with -v q="'": a line for each case, <file><TAB><case><TAB><first
# line><TAB><last line>. A case is a `t_<case>() {` line the runner selects (conveyor/conveyor.test.sh: a case name of
# a-z and 0-9 only, so a t_left_stays helper is no case), outside a heredoc (a fixture's cases, written into a scratch
# file, are not the file's own). Only a << outside quotes and comments starts a heredoc. A case's lines are the comment
# lines right above its first line and every line to its end: the next line outside a heredoc and quotes that starts
# with `}`, or its first line when it ends there (`t_<case>() { ...; }`); for one that closes inline on a later line
# (`  ...; }`), the line that ends with `}` right before (but for blank and comment lines) the first line at the first
# column after it, or before the next case or the file's end (shut(), below); a line inside a quoted string of many
# lines is neither. A case with no end has last line 0.
CASESCAN='
  # The end word of the first heredoc opener on line s, or "" (sets dash for a <<- opener): a scan that keeps the
  # quote it is in (S single, A dollar-single, D double, P a $( or a parenthesis, N none) and stops at a comment, so a
  # << inside quotes is text, not an opener (#370). The quotes still open at the line end (QS, QT: the stack and its
  # top) are where the next line starts, so a line inside a quoted string of many lines is text (inq()); a stack with
  # no quote in it starts the next line empty, as does a heredoc opener.
  function inq(   j) { for (j = 1; j <= QT; j++) if (QS[j] != "P") return 1; return 0 }
  function opener(s,   i, n, c, t, h) {
    n = length(s); if (!inq()) QT = 0; QS[0] = "N"
    for (i = 1; i <= n; i++) {
      c = substr(s, i, 1); t = QS[QT]
      if (t == "S") { if (c == q) QT--; continue }
      if (t == "A") { if (c == "\\") i++; else if (c == q) QT--; continue }
      if (c == "\\") { i++; continue }
      if (t == "D") { if (c == "\"") QT--; else if (substr(s, i, 2) == "$(") { QS[++QT] = "P"; i++ }; continue }
      if (substr(s, i, 2) == "$" q) { QS[++QT] = "A"; i++ }
      else if (c == q) QS[++QT] = "S"
      else if (c == "\"") QS[++QT] = "D"
      else if (c == "(") QS[++QT] = "P"
      else if (c == ")") { if (QT > 0) QT-- }
      else if (c == "#" && (i == 1 || substr(s, i - 1, 1) ~ /[ \t;|&(]/)) return ""
      else if (substr(s, i, 3) == "<<<") i += 2
      else if (substr(s, i, 2) == "<<" && match(substr(s, i), "^<<-?[ \t]*[\"" q "\\\\]?[A-Za-z_][A-Za-z0-9_]*")) {
        h = substr(s, i, RLENGTH); dash = (h ~ /^<<-/); sub(/^<<-?[ \t]*/, "", h); gsub("[\"" q "\\\\]", "", h); QT = 0; return h }
    }
    return ""
  }
  # The open case (open: its name c, its first line at), printed with its inline end (pe), else its last line that is
  # not blank and no comment (lb) when that line ends with `}` outside quotes (lz), else with no end. pe is lb as it
  # was at the first line at the first column (not blank, `#` or `}`) and outside quotes (q0: the line starts outside
  # them) after a line that ends with `}`: a top-level line after an inline close, or a line of the case itself, which
  # ends it early, so a changed line after it counts as one outside all cases. A case line resets the quotes (QT): a
  # quote the scan read wrong leaves at most one case unended.
  function shut() { if (open) print pf "\t" c "\t" at "\t" (pe ? pe : lz ? lb : 0); open = 0 }
  FNR == 1 { shut(); end = ""; cm = 0; QT = 0; pf = FILENAME }
  end != "" { l = $0; if (dash) sub(/^\t+/, "", l); if (l == end) end = ""; cm = 0; next }
  { q0 = inq() }
  open && !q0 && /^\}/ { print pf "\t" c "\t" at "\t" (pe ? pe : FNR); open = 0 }
  open && !q0 && /^[^ \t#}]/ && !pe && lz { pe = lb }
  /^t_[a-z0-9]+\(\) \{/ { shut(); c = $0; sub(/^t_/, "", c); sub(/\(.*/, "", c); at = cm ? cm : FNR; open = 1; pe = 0; lz = 0; QT = 0
    if (substr($0, index($0, "{") + 1) ~ /\}[ \t]*(#.*)?$/) { print pf "\t" c "\t" at "\t" FNR; open = 0 } }
  # cm: the first of the comment lines right above this line, 0 when the line above is no comment.
  { if ($0 ~ /^#/) { if (!cm) cm = FNR } else cm = 0; end = opener($0) }
  open && !/^[ \t]*(#.*)?$/ { lb = FNR; lz = !inq() && /\}[ \t]*(#.*)?$/ }
  END { shut() }'
# <file>: the file, for jq's --rawfile, or /dev/null (read as no lines) when it is not a file that can be read: jq
# parses each line of a records file itself (JSONL), with no program started to read it first.
rawok() { if [ -f "$1" ] && [ -r "$1" ]; then printf '%s' "$1"; else printf /dev/null; fi; }
# Each line of the text on the input that is a JSON object, as `jq -cR 'fromjson? | objects'` reads a file's lines.
JSONL='def jsonl: split("\n") | map(fromjson? | objects);'
testspart() { # <the first day of the 7 days, YYYY-MM-DD>
  # The caller's defs and refs when it has read them (testowners: the snapshot's), else read here.
  local si sh rn mn fs fl sf defs=${defs:-} refs=${refs:-} cs ru tf=() ln ch hv px out nv rp cp su sv CTL_V ot=() t x
  packget test.slowIssues si test.slower.share sh test.slower.runs rn test.slower.minRuns mn test.files fs || return 1
  # The test files once, as names (tf: testhollow and testproxy take them so, with no jq of their own; the part's jq
  # reads them ended by NULs, all): main's tracked test files (testtracked(), lib/issues.sh; #1036: a project's
  # test-*.mjs files were missing).
  mapfile -d '' -t tf < <(testtracked -z 2>/dev/null)
  # The flaky and slow-filed records; a file not there is none, and starts no jq.
  { [ -s "$FLAKY" ] && fl=$(jq -ce 'objects' "$FLAKY" 2>/dev/null); } || fl='{}'
  { [ -s "${STATE%/*}/slow.json" ] && sf=$(jq -ce 'objects' "${STATE%/*}/slow.json" 2>/dev/null); } || sf='{}'
  ru=$(testrulesettings) || ru=null
  ctlread 2>/dev/null || CTL_V=null # the part's jq reads the test history's start (histstart()) from it: no jq more
  hv=$(testhollow "${tf[@]}" 2>/dev/null) && [ -n "$hv" ] || hv='{}'
  px=$(testproxy "${tf[@]}" 2>/dev/null) && [ -n "$px" ] || px='{}'
  [ -n "$defs" ] && [ -n "$refs" ] || testowners
  # The cases each test file of main's checkout defines, by file: a shell file's by the case scan (CASESCAN), another's
  # by TABLECASES (no program runs for it with no such file); the paths taken as they are, not as globs. No file, no search: git grep with no path searches the whole checkout.
  cs='{}'; for t in "${tf[@]}"; do [[ $t == *.sh || $t == *.bash ]] || ot+=("$t"); done
  [ ${#tf[@]} = 0 ] || cs=$(git -C "$MAIN" --literal-pathspecs grep -lzE '^t_[a-z0-9]+\(\) \{' -- "${tf[@]}" 2>/dev/null | (cd "$MAIN" && xargs -0 awk -v q="'" "$CASESCAN" 2>/dev/null) \
    | jq -cRn '[inputs | split("\t") | {f: .[0], c: .[1]}] | group_by(.f) | map({key: .[0].f, value: [.[].c] | unique}) | from_entries') || cs='{}'
  [ ${#ot[@]} = 0 ] || ! x=$(cd "$MAIN" && printf '%s\0' "${ot[@]}" | xargs -0 jq -cRn "$TESTEDIT_TABLE$TABLECASES" 2>/dev/null | jq -cs --slurpfile cs <(printf '%s' "$cs") '$cs[0] + add') || cs=$x
  ln=$(testlines) || return 1
  su=$(rawok "$SUITERUNS")
  sv=$(testsurvey)
  # The files each landed commit of a card with a failed test step changed, by its sha: {sha: [file...]}, from one git
  # call (a commit main's checkout does not have is left out). A path is a commit's key only when it is one of the
  # commits asked for, read from a file: as one argument, more than about 3,200 of them pass Linux's 128 KiB limit.
  ch=$(jq -rRn '[inputs | fromjson? | objects] | (map(select(.step == "test" and .result == "fail") | .card) | unique) as $f
      | [.[] | select(.step == "landed" and (.card | IN($f[])) and (.sha | strings | test("^[0-9a-f]{40}$"))) | .sha] | unique[]' <<<"$ln" 2>/dev/null)
  ch=$(printf '%s\n' "$ch" | git -C "$MAIN" diff-tree --stdin -r --root --name-only --no-renames -z 2>/dev/null \
    | jq -Rsc --rawfile want <(printf '%s\n' "$ch") '($want | split("\n") | map(select(. != "") | {key: ., value: true}) | from_entries) as $w
      | reduce (split("\u0000")[] | select(. != "")) as $x ({k: null, m: {}}; if $w[$x] then .k = $x | .m[$x] = [] elif .k == null then . else .m[.k] += [$x] end) | .m') || ch='{}'
  out=$(printf '%s\n' "$ln" | jq -cRn --arg since "$1" --argjson ctl "$CTL_V" --arg si "$si" --argjson sh "$sh" --argjson rn "$rn" --slurpfile ch <(printf '%s\n' "$ch") \
    --argjson mn "$mn" --slurpfile fs <(printf '%s' "$fs") --slurpfile fl <(printf '%s' "$fl") --slurpfile sf <(printf '%s' "$sf") --argjson keep "$TESTKEEP" --argjson days "$FLAKY_DAYS" \
    --slurpfile cs <(printf '%s' "$cs") --slurpfile defs <(printf '%s' "$defs") --slurpfile refs <(printf '%s' "$refs") --argjson ru "$ru" --rawfile all <(printf '%s\0' "${tf[@]}") \
    --slurpfile hv <(printf '%s' "$hv") --slurpfile px <(printf '%s' "$px") --slurpfile mu <(cat "$MUTS"/*.json 2>/dev/null | jq -c 'objects' 2>/dev/null) --rawfile mq "$(rawok "$MUTS/asked")" --rawfile su "$su" --slurpfile sv <(printf '%s' "$sv") --slurpfile last <(jq -ce 'objects' "$TESTRULES" 2>/dev/null || echo null) \
    --rawfile rl "$(rawok "$TESTRULESLOG")" --argjson shown "$TESTRULES_SHOWN" --rawfile tf "$(rawok "$TAFILED")" \
    --slurpfile tc <(jq -c '[.cards | arrays | .[] | objects | select(.file | type == "string") | {file, time, card: ((.card | strings) // null), issue: null}]' "$TACARDS" 2>/dev/null || echo '[]') \
    --slurpfile tj <(cat "$TESTACTS"/*.json 2>/dev/null | jq -c 'objects | select(.action == "judge" and .state == "done" and (.file | type) == "string" and (.waits | type) == "array") | {file, end, waits}' 2>/dev/null) "$HISTFROM"'(($ctl | objects | .testsFrom) // "") as $st | $fs[0] as $fs | ($fl[0] | if (.entries | type) == "array" then .entries |= map(fromstart($st)) else . end) as $fl | $sf[0] as $sf | ($all | split("\u0000") | map(select(. != ""))) as $all | $hv[0] as $hv | $px[0] as $px | '"$JSONL$OWNERS$FAILURE$RUNDEFS$FLAKYAGAIN"'
    # The rules log and the Board test issues, each read once: the log'"'"'s last $shown lines, newest first (lg), and
    # their filed lines (fd); the test issues with a file and an issue number (ta).
    ($su | jsonl) as $su | ($rl | split("\n") | if .[-1] == "" then .[:-1] else . end | .[-$shown:] | map(fromjson? | objects) | reverse) as $lg
    | ($rl | jsonl) as $rl | ($tf | jsonl | map(select(.event == "filed"))) as $tf | [$rl[], $tf[] | select(.event == "filed")] as $fd
    | [$tf[] | select((.file | type == "string") and (.issue | type == "number"))] as $ta
    # The Tests page cards of no issue ($TACARDS, lib/testaction.sh testcard()), each {file, time, card (null until
    # picked), issue: null}: kept in the Optimize history as a filing is (tc).
    | $tc[0] as $tc
    |
    def median: sort | if length == 0 then null else (.[(length - 1) / 2 | floor] + .[length / 2 | floor]) / 2 end;
    def r3: if . == null then null else . * 1000 | round / 1000 end;
    [inputs | fromjson? | objects] | sort_by(.time) | . as $cr | map(select(.step == "test")) as $ls
    # A check that ended done, as the Optimize history counts it: {at, killed, of}; null for none.
    | def mutsaid: if . == null then null else {at, killed, of: (.mutants | length)} end;
    # A Board filing ($TAFILED) as its cards left it, given the runs of its file ($r, oldest first).
    # A Tests page card of no issue (tc) by the lines of its card, none before it is picked.
    def optimize($r): . as $o | [$cr[] | select(if $o.issue == null then $o.card != null and .card == $o.card else .issue == $o.issue end)] as $c
        | (first($c[] | select(.step == "landed")) // null) as $l
        | ([$c[] | select(.step == "bugproof" and (.speed | type == "object") and ($l == null or .card == $l.card))] | last | .speed // {}) as $p
        # A delete changes no other test file: the files that cover its cases are those its card'"'"'s last review named
        # on its COVERED-BY lines (speedproof.sh optproof()).
        | ([$c[] | select(.step == "review" and $l != null and .card == $l.card)] | last | (.reason | strings) // ""
           | [split("\n")[] | capture("^COVERED-BY: (?<f>[^\\s:]+): ").f] | unique) as $cov
        | ([$c[] | select(.step != "closed" and .step != "landed" and .step != "review")] | last) as $n
        | (if $l == null then null else [$r[] | select(.time > $l.time) | .cpu | numbers] end) as $since
        | (if $l != null then "landed" elif any($c[]; .step == "closed") then "closed" elif $n == null then "open"
           elif $n.step == "blocked" then "blocked" else "building" end) as $st
        | {issue, time, state: $st, reason: (if $st == "blocked" then $n.reason else null end),
           sha: ($l.sha // null), landed: ($l.time // null), fix: ($p.fix // null), into: (if $p.fix == "deleted" then $cov else $p.into // [] end),
           before: ($p.before // null), after: ($p.after // null), since: ($since | if . == null then null else median | r3 end), sinceRuns: ($since | length),
           mutantsBefore: (if $l == null then null else [$mu[] | select(.file == $o.file and .state == "done" and .at < $l.time)] | max_by(.at) | mutsaid end),
           mutantsAfter: (if $l == null then null else [$mu[] | select(.file == $o.file and .state == "done" and .at > $l.time)] | max_by(.at) | mutsaid end)}
        + (if $o.issue == null then {card: $o.card, name: "No issue"} else {} end);
    # The asked list of the mutation checks (lib/mutate.sh mutask()): each file to its place, 1 first.
    ($mq | split("\n") | map(select(. != "")) | to_entries | map({key: .value, value: (.key + 1)}) | from_entries) as $place
    # The failed test steps of each file (FAILURE: failedrun), newest first.
    | ($ls | startlines($st)) as $lf
    | (reduce ($lf | reverse[] | failedrun) as $l ({}; reduce ($l | failedfiles[]) as $f (.; .[$f] += [$l | failure($f)]))) as $failed
    # Each failed test step of a card that landed, for each file it failed in: caught when the landed commit left the
    # file as it was (the fix went into the code), changed to pass when it changed the file.
    | (reduce ($cr[] | select(.step == "landed" and (.card | type == "string"))) as $l ({}; .[$l.card] = $l.sha)) as $land
    | (reduce ($lf[] | select(.result == "fail" and (.card | type == "string")) | ($ch[0][$land[.card] | strings] // null) as $d | select($d != null)
        | failedfiles[] | [., IN($d[])]) as [$f, $ed] ({}; if $ed then .[$f].changed += 1 else .[$f].caught += 1 end)) as $catch
    | (reduce ($fl.entries | arrays | .[] | objects | .case | strings | caseowners[]) as $f ({}; .[$f] += 1)) as $flaky
    | alledits($cr) as $alledits
    # A survey time counts for each file the part has a row for (listed, run or filed), as testolder() counts it, so
    # a file the patterns do not list keeps it beside its card runs (#1044); it adds no row of its own (#1036). $ever: a run before the start too.
    | [testruns($lf; $su) | fromstart($st)] as $tr | ([$all[], $tr[].file, $ta[].file, $tc[].file] | map({key: ., value: true}) | from_entries) as $rows | (if $st == "" then {} else [(testruns($ls; $su) | .file), ($sv[0][] | .file)] | map(strings | {key: ., value: true}) | from_entries end) as $ever
    | [$tr[], ($sv[0][] | select($rows[.file] == true) | fromstart($st)), ($all[], $ta[].file, $tc[].file | {file: ., none: true})]
    | group_by(.file)
    | map(.[0].file as $f | map(select(.none != true)) | sort_by(.time) as $r | [$r[].cpu | numbers] as $c | ($c | median) as $m | $c[-1] as $now
        | ($fs[$f] // {}) as $own | ($own.wholeOnly == true) as $wo
        | (if ($c | length) >= $mn and ($c | length) > $rn then $c[:-$rn] | median else null end) as $usual
        | {file: $f, cpu: $now, median: ($m | r3), change: (if $m > 0 then ($now - $m) / $m | r3 else null end),
           runs: ($r[-$keep:] | reverse | map(del(.file))),
           lastRun: (if $r == [] then null else $r[-1] | {sec, cpu, clockPerCpu: (if .sec != null and .cpu > 0 then .sec / .cpu | r3 else null end), time, whole} + (if .survey == true then {survey: true} else {} end) end),
           timedRuns: ($c | length), runsOnRecord: ($r | length), everRun: ($r != [] or $ever[$f] == true), wholeOnly: $wo, failedSteps: ($failed[$f] // [] | length),
           failures: ($failed[$f] // [] | to_entries | map(.value + if .key < $keep then {} else {tail: null} end)),
           caught: ($catch[$f].caught // 0), changedToPass: ($catch[$f].changed // 0),
           flaky: ($flaky[$f] // 0),
           flakyAgain: ($fl | again($f; (($ENV.CONVEYOR_NOW // "" | tonumber?) // now); $days)),
           issue: ([($sf.filed | arrays | .[] | objects), $fd[] | select(.file == $f) | .issue | numbers] | max),
           slowOnPurpose: ($own.slowOnPurpose // null), usual: ($usual | r3),
           slower: ($wo | not) and $usual != null and all($c[-$rn:][]; . > $usual * (1 + $sh)), hollow: ($hv[$f] // null), proxy: ($px[$f] // null),
           mutation: ([$mu[] | select(.file == $f)] | max_by(.at) | if . == null then null
             else {file, at, sha, seed, state, reason, of: (.mutants | length), tried, killed, survived, noresult, notMutated, end} end),
           mutationPlace: ($place[$f] // null), cases: (if $f | test("\\.(sh|bash)$") then $cs[0][$f] // [] else $cs[0][$f] end),
           waits: ([$tj[] | select(.file == $f)] | max_by(.end // "") | if . == null or .waits == [] then null else .waits end)}
        | .optimize = (([$ta[] | select(.file == $f)] | unique_by(.issue)) + [$tc[] | select(.file == $f)] | sort_by(.time) | reverse | map(optimize($r)))
        | .removed = (($f | IN($all[]) | not) and any(.optimize[]; .state == "landed" and (.fix | IN("deleted", "merged")))))
    | sort_by(-(.cpu // -1), .file)
    | [$lf[] | select(.reused != true and ((.time | fromdate? | strflocaltime("%Y-%m-%d")) // "") >= $since)] as $wk
    | {settings: {slowIssues: ($si == "true"), historyStart: ($st | if . == "" then null else . end), slower: {share: $sh, runs: $rn, minRuns: $mn}, files: $fs},
       rules: (if $ru == null then null else $ru + {last: $last[0], log: $lg} end),
       files: ., slower: map(select(.slower) | .file),
       edits: (reduce $alledits[] as $e ({n: {}, out: []};
           if (.n[$e.file] // 0) < $keep then .out += [$e] | .n[$e.file] += 1 else . end) | .out),
       totals: (map(select(.removed | not)) | {files: (map(select(.timedRuns > 0)) | length), slower: (map(select(.slower)) | length)}) + {
         steps: {count: ($wk | length), waitSec: ([$wk[].wait | numbers] | add // 0 | r3), runSec: ([$wk[].run | numbers] | add // 0 | r3)}}}') || return 1
  nv=$(neverwhy "$(jq -c '[.files[] | select((.everRun | not) and (.removed | not)) | .file]' <<<"$out")") || nv='{}'
  packget test.report rp 2>/dev/null && [ -n "$rp" ] || rp=null
  cp=$(cpuplan 2>/dev/null) || cp=null
  jq -c --slurpfile nv <(printf '%s' "$nv") --argjson rp "$rp" --argjson cp "$cp" --rawfile su "$su" "$JSONL$HISTFROM"'(.settings.historyStart // "") as $st | $nv[0] as $nv | ($su | jsonl | map(fromstart($st))) as $su | .files |= map(.neverRun = ($nv[.file] // null))
    | .settings.report = $rp | .settings.cpuTime = $cp
    | .suite = ($su | max_by(.time // "") | if . == null then null
        else {time, cpu: ([.files | objects | .[] | objects | .cpu | numbers] | if . == [] then null else add * 1000 | round / 1000 end)} end)' <<<"$out"
}
# Why a test file of main's checkout with no run on record never ran (#189), when the engine can tell, for the
# Board's Never run: {file: {kind, reason}}; a file it cannot tell of is left out. The first that holds, in this order:
# patterns: the pack's tests.patterns do not match it (testpaths()), or the test command names what it runs
# (testrunner(): `named`, a glob, a file or a folder) and that does not match it; load: loading it fails, the error
# of a shell file that bash -n, a JavaScript file that node --check, or a Python file that python3 cannot parse, kept
# by the file's content (its blob) in $TESTACTS/neverloads (nl; not a .json name, which the action records have), so a
# file is parsed once a content; skipped: it holds skip markers (the test edits' table, TESTEDIT_TABLE, an `only` mark aside), each named once.
neverwhy() { # <the files, a JSON list>
  local f cmd rn w pat x ld bl e l1 le sk new='' out='' nl=$TESTACTS/neverloads fs
  # The files read from the list once, for the patterns and for the loop below.
  mapfile -t fs < <(jq -r '.[]' <<<"$1" 2>/dev/null); [ ${#fs[@]} != 0 ] || { echo '{}'; return; }
  packget test.command cmd 2>/dev/null || cmd=''
  rn=$(testrunner "$cmd" "$MAIN" 2>/dev/null); w=''; [[ $rn != named\ * ]] || w=${rn##* }
  pat=$(printf '%s\n' "${fs[@]}" | testpaths 2>/dev/null)
  ld=$(jq -ce 'objects' "$nl" 2>/dev/null) || ld='{}'
  while IFS= read -r f; do
    [ -f "$MAIN/$f" ] || continue
    x=''
    # shellcheck disable=SC2053 # $w is the command's glob: matched as a pattern
    if ! grep -qxF -- "$f" <<<"$pat"; then x=$(jq -cn '{kind: "patterns", reason: "the pack'"'"'s tests.patterns do not match it"}')
    elif [ -n "$w" ] && ! { [ "$f" = "$w" ] || [[ $w == *[*?[]* && $f == $w ]] || [[ -d $MAIN/$w && $f == "${w%/}"/* ]]; }; then
      x=$(jq -cn --arg c "$cmd" --arg w "$w" '{kind: "patterns", reason: "the test command (\($c)) runs \($w), which does not match it"}')
    else
      bl=$(git -C "$MAIN" hash-object -- "$f" 2>/dev/null) || bl=''
      if [ -n "$bl" ] && e=$(jq -er --arg b "$bl" 'if has($b) then .[$b] else error end' <<<"$ld" 2>/dev/null); then :
      else
        e=''
        case $f in
          *.sh | *.bash) e=$(cd "$MAIN" && bash -n "$f" 2>&1) || e=${e:-bash -n failed} ;;
          *.js | *.mjs | *.cjs) ! command -v node > /dev/null || e=$(cd "$MAIN" && node --check "$f" 2>&1) || e=${e:-node --check failed} ;;
          *.py) e=$(cd "$MAIN" && python3 -c 'import ast, sys
try: ast.parse(open(sys.argv[1], "rb").read(), sys.argv[1])
except SyntaxError as x: print(f"{sys.argv[1]}: line {x.lineno}: {x.msg}"); sys.exit(1)' "$f" 2>&1) || e=${e:-python3 could not parse it} ;;
        esac
        # Its location line and its error line, one line, its paths relative to main's checkout.
        e=${e//"$MAIN/"/}; l1=$(head -n 1 <<<"$e"); le=$(grep -m 1 -iE 'error' <<<"$e"); [ -z "$le" ] || [ "$le" = "$l1" ] || l1+=" $le"; e=${l1:0:300}
        [ -z "$bl" ] || { ld=$(jq -c --arg b "$bl" --arg e "$e" '.[$b] = $e' <<<"$ld"); new=1; }
      fi
      if [ -n "$e" ]; then x=$(jq -cn --arg e "$e" '{kind: "load", reason: "loading it fails: \($e)"}')
      else
        sk=$(jq -Rsr --arg f "$f" "$TESTEDIT_TABLE"'(($f | capture("\\.(?<x>[^./]+)$").x | ascii_downcase) // "") as $x
            | (first(table[] | select(any(.ext[]; . == $x))) // null) as $t | if $t == null then empty
              else [split("\n")[] | match($t.skip; "g").string | gsub("^[\\s{,]+|[\\s(:]+$"; "") | select(test("only") | not)] | unique | join(", ") end' "$MAIN/$f" 2>/dev/null)
        [ -z "$sk" ] || x=$(jq -cn --arg s "$sk" '{kind: "skipped", reason: "it is skipped: \($s)"}')
      fi
    fi
    [ -z "$x" ] || out+=$(jq -cn --arg f "$f" --argjson x "$x" '{($f): $x}')$'\n'
  done < <(printf '%s\n' "${fs[@]}")
  # The parse results, kept for the next snapshot (a write that fails costs a parse again, nothing else).
  [ -z "$new" ] || { mkdir -p "$TESTACTS" && taput "$nl" "$ld"; } 2>/dev/null || :
  jq -cs 'add // {}' <<<"$out"
}

# conveyor.sh test-settings: one test setting of the pack saved, as the Board saves it. Each refuses a bad value, says
# why and changes nothing:
#   slow-issues <true | false>   test.slowIssues
#   slow-mark <file> <reason>    test.files.<file>.slowOnPurpose: the reason, one line that is not blank, for a file
#                                main's checkout tracks
#   slow-mark-clear <file>       that mark taken off
#   cpu-time <file>              test.command made the one cpuplan() gives for that file (Record CPU time, #190), and
#                                test.fileCommand its wrapped one, when it gives one
#   history-start <time | clear> the control record's testsFrom (histstart()): a UTC time like 2026-11-21T00:00:00Z;
#                                only the runs and failures on or after it count; clear: all of them count
# A file with no setting left is taken out of test.files (packset()). record-times (no argument) runs the plan the snapshot's
# health gives as timesPlan (Record test times: recordtimes(), lib/setup.sh).
TESTSET_USAGE='usage: conveyor.sh test-settings slow-issues <true | false> | slow-mark <file> <reason> | slow-mark-clear <file> | cpu-time <file> | history-start <UTC time | clear> | record-times'
testsettings() { # <what> [<file>] [<value>]
  local why='' r=${3:-} p
  case ${1:-}:$# in
    slow-issues:2 | slow-mark:3 | slow-mark-clear:2 | cpu-time:2) ;;
    history-start:2) locked control tests-from "$2" > /dev/null; return ;;
    *) echo "$TESTSET_USAGE" >&2; return 2 ;;
  esac
  case $1 in
    slow-issues) [[ $2 =~ ^(true|false)$ ]] || why="test.slowIssues is true or false, not \"$2\"" ;;
    slow-mark) r=${r#"${r%%[![:space:]]*}"}; r=${r%"${r##*[![:space:]]}"}  # the reason with no space at its ends
      [[ $3 != *[$'\n\r']* ]] || why="the reason is one line"; [ -n "$r" ] || why="a file is marked slow on purpose only with a reason" ;;
  esac
  case $1 in slow-mark)
    { [ -n "$2" ] && [ "$(git -C "$MAIN" ls-files -- ":(literal)$2" 2>/dev/null)" = "$2" ]; } || why=${why:-"\"$2\" is not a file of main's checkout"} ;;
  esac
  if [ "$1" = cpu-time ]; then
    p=$(cpuplan) || p='{"why": "the pack cannot be read"}'
    why=$(jq -r --arg f "$2" 'if .file == $f then empty elif .why then .why else "the test command runs \(.file), not \($f)" end' <<<"$p")
  fi
  [ -z "$why" ] || { echo "conveyor: test-settings $1: $why; nothing changed" >&2; return 1; }
  case $1 in
    slow-issues) packset --argjson v "$2" '.test.slowIssues = $v' ;;
    slow-mark) packset --arg f "$2" --arg v "$r" '.test.files[$f].slowOnPurpose = $v' ;;
    slow-mark-clear) packset --arg f "$2" 'if .test.files[$f] == null then . else del(.test.files[$f].slowOnPurpose) end' ;;
    cpu-time) packset --arg c "$(jq -r '.command' <<<"$p")" --arg fc "$(jq -r '.fileCommand // ""' <<<"$p")" '.test.command = $c | if $fc == "" then . else .test.fileCommand = $fc end' ;;
  esac
}
# Record CPU time (#190): how the pack's test command can give a Wall only file's CPU seconds, as JSON. No runner's
# report gives CPU seconds (README.md, Test file times), so a report option never can. The wrapper
# conveyor/tools/testtime.sh times one command as one file's run, so it applies when the test command runs one test
# file and nothing else: the command is given no list (test.list not set, or none), is one plain command (no ; & | < >
# $ ` quote or bracket), and of its words exactly one names a path of main's checkout, a test file. Then it prints
# {file, was, command, fileCommand}: the command wrapped in testtime.sh (its path in CONVEYOR_TEST_TIME, testonce()),
# and test.fileCommand so wrapped when the pack sets it (it too must be one plain command), its output
# as before and its `TESTRUN sec` line put in the run's log, where the run reads it. The wrapper is a shell function
# called last, so the words a run adds at the command's end (the runner's report args, reportask()) go to the test
# command. Else {why}: why neither applies.
cpuplan() {
  local cmd lm fc w ws=() ps=() q
  packget test.command cmd test.list lm test.fileCommand fc || return 1
  local no='No report option gives CPU time: a runner'"'"'s report gives clock seconds only. The wrapper conveyor/tools/testtime.sh does not apply either:'
  local how='wrap each test file'"'"'s run with it in your test script (conveyor/README.md, Test file times).'
  if [[ $cmd == *testtime.sh* || $cmd == *CONVEYOR_TEST_TIME* ]]; then jq -cn --arg w "The test command already runs conveyor/tools/testtime.sh, and its runs give no CPU seconds for this file: check that the wrapper names this file." '{why: $w}'; return 0; fi
  if [ -n "$lm" ] && [ "$lm" != none ]; then jq -cn --arg w "$no the test command is given the test files of each card's change (test.list $lm), and one wrapper around it gives one time for all of them: $how" '{why: $w}'; return 0; fi
  if [[ $cmd == *[\;\&\|\<\>\$\`\"\'\(\)\{\}\\]* || $cmd == *$'\n'* ]]; then jq -cn --arg w "$no the test command is not one plain command, so Conveyor cannot wrap it safely: $how" '{why: $w}'; return 0; fi
  read -ra ws <<<"$cmd"
  for w in "${ws[@]}"; do [[ $w == -* ]] || [ ! -e "$MAIN/$w" ] || ps+=("$w"); done
  # The file the command names is the runner too (TESTRUNNERS, no test file to testpaths(): #350), so it is read
  # against tests.patterns alone (testpaths() with no TESTRUNNERS).
  names || return 1
  if [ ${#ps[@]} != 1 ] || [ ! -f "$MAIN/${ps[0]}" ] || [ -z "$(printf '%s\n' "${ps[0]}" | TESTRUNNERS='' testpaths)" ]; then
    jq -cn --arg w "$no the test command runs more than one test file, or a folder or script, and one wrapper around it gives one time for all of them: $how" '{why: $w}'; return 0
  fi
  # A card runs each test file through test.fileCommand (filecmd(), lib/testrun.sh): it is wrapped too, each run timed
  # as the file the run gives it (CONVEYOR_TEST_FILE), so a card's run of the file records its CPU seconds.
  [ -z "$fc" ] || [[ $fc != *[\;\&\|\<\>\$\`\"\'\(\)\{\}\\]* && $fc != *$'\n'* && $fc != *testtime.sh* ]] \
    || { jq -cn --arg w "$no test.fileCommand, which a card runs each test file with, is not one plain command, so Conveyor cannot wrap it safely: $how" '{why: $w}'; return 0; }
  q=$(printf %q "${ps[0]}")
  jq -cn --arg f "${ps[0]}" --arg was "$cmd" --arg c "$(cputwrap "$q" "$cmd")" --arg fc "${fc:+$(cputwrap '"$CONVEYOR_TEST_FILE"' "$fc")}" \
    '{file: $f, was: $was, command: $c} + if $fc == "" then {} else {fileCommand: $fc} end'
}
# <command> wrapped in conveyor/tools/testtime.sh, timed as the test file <file> (a word for the shell).
cputwrap() { # <file> <command>
  printf '%s' "conveyor_cputime() { local o r; o=\$(mktemp); \"\$CONVEYOR_TEST_TIME\" $1 -- $2 \"\$@\" > \"\$o\" 2>&1; r=\$?; cat \"\$o\"; grep '^TESTRUN sec' \"\$o\" >> \"\$CONVEYOR_TEST_LOG/cputime\"; rm -f \"\$o\"; return \$r; }; conveyor_cputime"
}
# The pack in main's checkout changed by a jq filter, checked against the schema and then saved whole by one rename;
# a pack that does not read or whose change fails the check is left as it was. One writer at a time (a lock in the
# state folder). An empty test.files entry, and an empty test.files, are taken out.
packset() { # [jq options] <jq filter>
  local lock new rc=0
  { exec {lock}>>"${STATE%/*}/pack.lock"; } 2>/dev/null && flock "$lock" || { echo "conveyor: the pack could not be locked; nothing changed" >&2; return 1; }
  if new=$(jq "${@:1:$#-1}" "(${!#})"' | if .test.files then .test.files |= with_entries(select(.value != {})) | if .test.files == {} then del(.test.files) else . end else . end' "$PACK") \
    && packcheck "$PACK" "$new" "$(<"$SCHEMA")"; then
    printf '%s\n' "$new" > "$PACK.new" && mv -f "$PACK.new" "$PACK" || { rm -f "$PACK.new"; echo "conveyor: the pack $PACK could not be written; nothing changed" >&2; rc=1; }
  else echo "conveyor: the pack $PACK could not be changed; nothing changed" >&2; rc=1; fi
  exec {lock}>&-; return $rc
}
