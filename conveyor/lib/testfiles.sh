# SPDX-License-Identifier: Apache-2.0
# The test files in the snapshot (README.md, The test files in the snapshot): the snapshot's tests part, and the
# command that sets the pack's test settings the Board saves (conveyor.sh test-settings).

# The snapshot's tests part, read from the card records (recs, olds: a retried card's runs count too), the pack, the
# flaky-test record ($FLAKY), the slow-test record ($SLOWFILED), the test rules' log ($TESTRULESLOG) and the Board's
# test issues ($TAFILED):
# settings: the pack's slowIssues (true or false), slower ({share, runs, minRuns}) and files (each file's own
#   settings, as the pack holds them), and report (the pack's test.report, {runner, format, path, env,
#   args, option}, null with none: the runner whose report gives a Wall only file's clock seconds, #190), and cpuTime
#   (cpuplan(): {file, was, command}, the test command Record CPU time saves, or {why}; null when it cannot be told);
# suite: the newest whole-suite run on record ($SUITERUNS), {time, cpu: the CPU seconds of its files summed, null with
#   none}, null with no run: what a change to a wholeOnly file waits for (#190);
# rules: the test rules (lib/testrules.sh): the pack's switch, guards and rules (testrulesettings()), and last: the
#   list of the last pass (testrulespass()), {time, on, matches, burst}, null before the first, and log: the last
#   TESTRULES_SHOWN lines of the rules' log ($TESTRULESLOG), newest first; null when the pack cannot be read;
# files: each test file main's checkout tracks (a name with `.test.` in it), and each other file with a run on record:
#   a card's test line (times, and clocks: a file timed by the clock only, from its runner's report, has cpu null) or a whole-suite run ($SUITERUNS, suiterec() of lib/testrun.sh); the highest CPU seconds
#   now first, a file with none last: file, cpu (its newest run's that has CPU seconds; null with none), median (of
#   every run on record with CPU seconds), change (cpu against median, as a share: 0.5 is 50% over; null when the
#   median is 0 or null), runs (its last TESTKEEP runs, newest first: {cpu, sec: clock seconds, null on a line that
#   gives none; card (null for a whole-suite run), time, whole (a whole-suite run), and a whole-suite run's result: ok,
#   fail or null}; [] for a file never run), lastRun ({sec, cpu, clockPerCpu, time, whole} of its newest run; null with
#   none), timedRuns (its runs with CPU seconds), runsOnRecord (its runs on record; its older runs and test edits are
#   not here but in testolder(), below, so the part does not grow with every run), wholeOnly (its test.files entry's wholeOnly), failedSteps (the test steps
#   that failed with it among the failed files, or with a case it defines that its runner named, or timed out in it;
#   a step that went again counts with the failures of its first run too: failedrun, FAILURE),
#   failures (those steps, newest first, each {card, issue, time, verdict: main, flaky, card or null, cases, tail}
#   (FAILURE); tail is null past the newest TESTKEEP), caught and changedToPass (those of them whose card landed: caught when the landed commit left the file as it was,
#   so the fix went into the code; changedToPass when that commit changed the file),
#   flaky (its entries in the flaky-test record, its cases' too, a runner's name for them as well), issue (the issue last filed for it, the highest number of the slow-test record's, the test rules' log's and the Board's filings ($TAFILED), else null; the Board's Close its issue as done closes it), slowOnPurpose (its reason, else null), usual (the median of
#   its runs before its last slower.runs runs; null with fewer than slower.minRuns runs on record) and slower; a wholeOnly
#   file (a runner that starts other test files whole, each timed on its own) has slower false; optimize: each issue the Board filed for it ($TAFILED: Optimize, and older
#   speed-up, issues), newest first: {issue, time (filed), state (open: no card took it; building; blocked, with reason;
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
#   mutation: its newest mutation check (lib/mutate.sh), {file, at, sha, seed, state, reason, of (its mutants), tried,
#   killed, survived ([{source, line, kind, before, after}]), noresult, notMutated, end}; null when none was made;
#   mutationPlace: its place in the mutation checks' asked list ($MUTS/asked, mutask()), 1 first; null when not asked;
#   cases: the names of the cases it defines in main's checkout (its `t_<case>() {` lines the runner selects, not its
#   helpers or a heredoc's lines), A to Z, []
#   with none; the Board's search matches them;
#   waits: the waits its newest judge that ended done named on WAIT lines (lib/testaction.sh tawaits()), [{case, kind,
#   at, reason}]; null when no judge of it named waits or none (a judge from before WAIT lines were asked for);
#   neverRun: why a file of main's checkout with no run on record never ran, when the engine can tell (neverwhy(),
#   below), {kind, reason}; null for a file with a run, or one it cannot tell of;
#   a file that only a Board filing names is listed too;
# slower: the files slower than their usual, by name: each of their last slower.runs runs over usual by more than
#   slower.share;
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
  defs=$(git -C "$MAIN" grep -oE '^(t_)?[A-Za-z0-9_]+\(\)' -- '*.test.*' 2>/dev/null \
    | jq -cRn '[inputs | capture("^(?<f>.+):(t_)?(?<c>[A-Za-z0-9_]+)\\(\\)$")] | group_by(.c) | map({key: .[0].c, value: [.[].f] | unique}) | from_entries') || defs='{}'
  refs=$(git -C "$MAIN" grep -oE '[A-Za-z0-9_.-]+\.test\.[A-Za-z0-9]+' -- '*.test.*' 2>/dev/null \
    | jq -cRn '[inputs | capture("^(?<f>[^:]+):(?<n>.+)$")] | group_by(.f) | map({key: .[0].f, value: [.[].n] | unique}) | from_entries') || refs='{}'
}
OWNERS='$defs[0] as $defs | $refs[0] as $refs | def owners($f; $c): ($defs[$c // ""] // []) as $d | ($f | split("/")[-1]) as $n
      | if $c == null or any($d[]; . == $f) then [$f] else [$f] + [$d[] | select(any($refs[.][]?; . == $n))] end;
    def caseowners: index(": ") as $i | if $i == null then [.] else owners(.[:$i]; .[$i + 2:]) end;
    def failedfiles: [(.failures.files | arrays | .[] | objects | (.file | strings) as $f
        | if (.cases | arrays | length) > 0 then .cases[] | owners($f; .name | strings)[] else $f end), (.failures.timeout.file? | strings)] | unique;'
# One failed test line, as a failure of the file $f it counts for (failedfiles), read with OWNERS: {card, issue, time,
# verdict, cases, tail}. verdict: the test line's verdicts (verdicts(), lib/testrun.sh) of the cases that count for $f,
# main when one of them failed on main too, else flaky when one failed and then passed when run again, else card (the
# card's own change made it fail: the test did its job); null when the line has none for it (a line written before
# verdicts were kept). cases: the names of its failing cases that count for $f ([] for a file that failed naming no
# case). tail: the last 1500 characters of the step's output (the line's tail), null with none. failedrun: a test
# line as a failed step: a line that failed, with its first run's failures (in rerun, firstrun(), when the run went
# again) added to its own, so a case that passed on the run again (its verdict flaky) still counts while another file
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
       tail: (if (.again | type) == "array" and (any(.again[]; . == $f) | not) then .rerun.tail else .tail end | (strings | .[-1500:]) // null)};'
# What a card did to the test files it changed that main already had (#76), written on its landed line as testedits:
# one entry a file, {file, read, removedAsserts, changedExpected, skipsAdded, timeoutsRaised, casesDeleted}. The one
# table of patterns, a language a row: the file name endings it reads and the jq regular expressions of an assertion,
# a skip, only or todo mark, a case and a timeout (its number captured as n). A file whose ending no row has is
# recorded as edited, not read: read false, its counts null.
TESTEDIT_TABLE='def table: [
  {ext: ["sh", "bash", "bats"], assert: "\\|\\|\\s*fail\\b|\\bassert[A-Za-z_]*\\b", skip: "^\\s*skip\\b",
   case: "^\\s*(function\\s+)?(t_|test)[A-Za-z0-9_]*\\s*\\(\\)|^\\s*@test\\s",
   timeout: "(\\btimeout\\s+|--timeout[= ]|^#\\s*timeout:\\s*)(?<n>[0-9][0-9_]*)"},
  {ext: ["js", "mjs", "cjs", "jsx", "ts", "mts", "cts", "tsx"], assert: "\\b(expect|assert)(\\.[A-Za-z]+)*\\s*\\(",
   skip: "\\b(it|test|describe|suite)\\.(skip|only|todo)\\b|\\b[xf](it|describe|test)\\s*\\(|\\bt\\.(skip|todo)\\s*\\(|[{,]\\s*(skip|only|todo)\\s*:\\s*(true|[\"\u0027`])",
   case: "^\\s*[xf]?(it|test)(\\.[A-Za-z]+)?\\s*\\(",
   timeout: "\\b(timeout|setTimeout)\\s*[:(=]\\s*(?<n>[0-9][0-9_]*)"}];'
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
      # assert(value, message) and assert.ok, whose value is masked in key and is val.
      def parts: if $t.ext[0] == "sh" then sub("\\s*\\|\\|\\s*fail\\b[\\s\\S]*$"; "") | {key: mask, val: norm}
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
  local n s f o w e out=''
  # Each changed (M) or deleted (D) test file, as its status and path.
  n=$(git -C "$1" diff --cached --name-status --no-renames --diff-filter=MD -z -- '*.test.*' | jq -Rsc 'split("\u0000") | map(select(. != ""))') || return 1
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
testhollow() { # <the test files of main's checkout, a JSON list>
  local f fs=()
  while IFS= read -r -d '' f; do [ ! -f "$MAIN/$f" ] || fs+=("./$f"); done < <(jq -j --arg re "$HOLLOWFILES" '.[] | select(test($re)) | . + "\u0000"' <<<"$1")
  [ ${#fs[@]} -gt 0 ] || { echo '{}'; return; }
  (cd "$MAIN" && printf '%s\0' "${fs[@]}" | LC_ALL=C xargs -0 awk "$HOLLOW_AWK") \
    | jq -Rnc --rawfile fs <(printf '%s\n' "${fs[@]}") '($fs | split("\n") | map(select(. != "") | {key: .[2:], value: []}) | from_entries) as $all
    | reduce (inputs | split("\t") | select(length == 3)) as [$f, $c, $k] ($all; .[$f] += [{case: $c, kind: $k,
        reason: (if $k == "no-assert" then "no expect or assert call" else "its only assertions are toBeDefined or toBeTruthy" end)}])'
}
# What the Tests part reads of each line of the records (linesum(), lib/records.sh). A project with no test line has
# its part all the same. The steps other than test are those that give a Board filing's state (optimize, below) and a
# card's landed commit (caught, below), as the text of the line names them (so a line that names one in a field of
# its own counts too). Of each, the fields the part reads and none other: a test line's failures, verdicts and output
# only when it failed or ran again (failedrun), its output's last 1500 characters (failure), and a review's reason
# only its COVERED-BY lines (optimize).
TESTLINE='select(test("\"step\":\"(test|picked|bugproof|blocked|closed|landed|review)\"")) | fromjson? | objects
  | def cut: if type == "string" then .[-1500:] else . end;
  {card, issue, step, time, result} + if .step == "test" then {times, clocks, reused, wait, run}
      + (if .result == "fail" or .rerun != null then {verdicts, failures, rerun: (.rerun | if type == "object" and has("tail") then .tail |= cut else . end), tail: (.tail | cut)} else {} end)
    elif .step == "landed" then {sha, testedits} elif .step == "bugproof" then {speed} elif .step == "blocked" then {reason}
    elif .step == "review" then {reason: (.reason | if type == "string" then [split("\n")[] | select(test("^COVERED-BY: [^\\s:]+: "))] | join("\n") else . end)}
    else {} end'
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
# run's result}; and each test edit of a landed line ($cr, the lines oldest first), newest first, with its card, issue
# and time.
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
  local ln
  ln=$(testlines) || return 1
  printf '%s\n' "$ln" | jq -cRn --arg f "$1" --argjson keep "$TESTKEEP" --slurpfile su <(jq -cR 'fromjson? | objects' "$SUITERUNS" 2>/dev/null) "$RUNDEFS"'
    [inputs | fromjson? | objects] | sort_by(.time) | . as $cr | map(select(.step == "test")) as $ls
    | [testruns($ls; $su) | select(.file == $f)] | sort_by(.time) as $r
    | {file: $f, olderRuns: ($r[:-$keep] | reverse | map(del(.file))), olderEdits: ([alledits($cr)[] | select(.file == $f)][$keep:])}'
}
# The case scan of test files (testspart(): the cases each file defines; owncases(), lib/testrun.sh: the cases a card's
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
testspart() { # <the first day of the 7 days, YYYY-MM-DD>
  # The caller's defs and refs when it has read them (testowners: the snapshot's), else read here.
  local si sh rn mn fs fl sf defs=${defs:-} refs=${refs:-} cs ru all ln ch hv out nv rp cp
  packget test.slowIssues si test.slower.share sh test.slower.runs rn test.slower.minRuns mn test.files fs || return 1
  all=$(git -C "$MAIN" ls-files -z -- '*.test.*' 2>/dev/null | jq -Rsc 'split("\u0000") | map(select(. != ""))') || all='[]'
  fl=$(jq -ce 'objects' "$FLAKY" 2>/dev/null) || fl='{}'
  sf=$(jq -ce 'objects' "$SLOWFILED" 2>/dev/null) || sf='{}'
  ru=$(testrulesettings) || ru=null
  hv=$(testhollow "$all" 2>/dev/null) && [ -n "$hv" ] || hv='{}'
  [ -n "$defs" ] && [ -n "$refs" ] || testowners
  # The cases each test file of main's checkout defines, by file (the case scan, CASESCAN).
  cs=$(git -C "$MAIN" grep -lzE '^t_[a-z0-9]+\(\) \{' -- '*.test.*' 2>/dev/null | (cd "$MAIN" && xargs -0 awk -v q="'" "$CASESCAN" 2>/dev/null) \
    | jq -cRn '[inputs | split("\t") | {f: .[0], c: .[1]}] | group_by(.f) | map({key: .[0].f, value: [.[].c] | unique}) | from_entries') || cs='{}'
  ln=$(testlines) || return 1
  # The files each landed commit of a card with a failed test step changed, by its sha: {sha: [file...]}, from one git
  # call (a commit main's checkout does not have is left out). A path is a commit's key only when it is one of the
  # commits asked for.
  ch=$(jq -rRn '[inputs | fromjson? | objects] | (map(select(.step == "test" and .result == "fail") | .card) | unique) as $f
      | [.[] | select(.step == "landed" and (.card | IN($f[])) and (.sha | strings | test("^[0-9a-f]{40}$"))) | .sha] | unique[]' <<<"$ln" 2>/dev/null)
  ch=$(printf '%s\n' "$ch" | git -C "$MAIN" diff-tree --stdin -r --root --name-only --no-renames -z 2>/dev/null \
    | jq -Rsc --arg want "$ch" '($want | split("\n") | map(select(. != "") | {key: ., value: true}) | from_entries) as $w
      | reduce (split("\u0000")[] | select(. != "")) as $x ({k: null, m: {}}; if $w[$x] then .k = $x | .m[$x] = [] elif .k == null then . else .m[.k] += [$x] end) | .m') || ch='{}'
  out=$(printf '%s\n' "$ln" | jq -cRn --arg since "$1" --arg si "$si" --argjson sh "$sh" --argjson rn "$rn" --slurpfile ch <(printf '%s\n' "$ch") \
    --argjson mn "$mn" --slurpfile fs <(printf '%s' "$fs") --slurpfile fl <(printf '%s' "$fl") --slurpfile sf <(printf '%s' "$sf") --argjson keep "$TESTKEEP" \
    --slurpfile cs <(printf '%s' "$cs") --slurpfile defs <(printf '%s' "$defs") --slurpfile refs <(printf '%s' "$refs") --argjson ru "$ru" --slurpfile all <(printf '%s' "$all") \
    --slurpfile hv <(printf '%s' "$hv") --slurpfile mu <(cat "$MUTS"/*.json 2>/dev/null | jq -c 'objects' 2>/dev/null) --rawfile mq <(cat "$MUTS/asked" 2>/dev/null) --slurpfile su <(jq -cR 'fromjson? | objects' "$SUITERUNS" 2>/dev/null) --slurpfile last <(jq -ce 'objects' "$TESTRULES" 2>/dev/null || echo null) \
    --slurpfile lg <(tail -n "$TESTRULES_SHOWN" "$TESTRULESLOG" 2>/dev/null | jq -cRn '[inputs | fromjson? | objects] | reverse' 2>/dev/null || echo '[]') \
    --slurpfile fd <(cat "$TESTRULESLOG" "$TAFILED" 2>/dev/null | jq -cR 'fromjson? | objects | select(.event == "filed")' 2>/dev/null) \
    --slurpfile ta <(jq -cR 'fromjson? | objects | select(.event == "filed" and (.file | type == "string") and (.issue | type == "number"))' "$TAFILED" 2>/dev/null) \
    --slurpfile tj <(cat "$TESTACTS"/*.json 2>/dev/null | jq -c 'objects | select(.action == "judge" and .state == "done" and (.file | type) == "string" and (.waits | type) == "array") | {file, end, waits}' 2>/dev/null) '$fs[0] as $fs | $fl[0] as $fl | $sf[0] as $sf | $all[0] as $all | $hv[0] as $hv | '"$OWNERS$FAILURE$RUNDEFS"'
    def median: sort | if length == 0 then null else (.[(length - 1) / 2 | floor] + .[length / 2 | floor]) / 2 end;
    def r3: if . == null then null else . * 1000 | round / 1000 end;
    [inputs | fromjson? | objects] | sort_by(.time) | . as $cr | map(select(.step == "test")) as $ls
    # A check that ended done, as the Optimize history counts it: {at, killed, of}; null for none.
    | def mutsaid: if . == null then null else {at, killed, of: (.mutants | length)} end;
    # A Board filing ($TAFILED) as its cards left it, given the runs of its file ($r, oldest first).
    def optimize($r): . as $o | [$cr[] | select(.issue == $o.issue)] as $c
        | (first($c[] | select(.step == "landed")) // null) as $l
        | ([$c[] | select(.step == "bugproof" and (.speed | type == "object") and ($l == null or .card == $l.card))] | last | .speed // {}) as $p
        # A delete changes no other test file: the files that cover its cases are those its card'"'"'s last review named
        # on its COVERED-BY lines (optproof()).
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
           mutantsAfter: (if $l == null then null else [$mu[] | select(.file == $o.file and .state == "done" and .at > $l.time)] | max_by(.at) | mutsaid end)};
    # The asked list of the mutation checks (lib/mutate.sh mutask()): each file to its place, 1 first.
    ($mq | split("\n") | map(select(. != "")) | to_entries | map({key: .value, value: (.key + 1)}) | from_entries) as $place
    # The failed test steps of each file (FAILURE: failedrun), newest first.
    | (reduce ($ls | reverse[] | failedrun) as $l ({}; reduce ($l | failedfiles[]) as $f (.; .[$f] += [$l | failure($f)]))) as $failed
    # Each failed test step of a card that landed, for each file it failed in: caught when the landed commit left the
    # file as it was (the fix went into the code), changed to pass when it changed the file.
    | (reduce ($cr[] | select(.step == "landed" and (.card | type == "string"))) as $l ({}; .[$l.card] = $l.sha)) as $land
    | (reduce ($ls[] | select(.result == "fail" and (.card | type == "string")) | ($ch[0][$land[.card] | strings] // null) as $d | select($d != null)
        | failedfiles[] | [., IN($d[])]) as [$f, $ed] ({}; if $ed then .[$f].changed += 1 else .[$f].caught += 1 end)) as $catch
    | (reduce ($fl.entries | arrays | .[] | objects | .case | strings | caseowners[]) as $f ({}; .[$f] += 1)) as $flaky
    | alledits($cr) as $alledits
    | [testruns($ls; $su), ($all[], $ta[].file | {file: ., none: true})]
    | group_by(.file)
    | map(.[0].file as $f | map(select(.none != true)) | sort_by(.time) as $r | [$r[].cpu | numbers] as $c | ($c | median) as $m | $c[-1] as $now
        | ($fs[$f] // {}) as $own | ($own.wholeOnly == true) as $wo
        | (if ($c | length) >= $mn and ($c | length) > $rn then $c[:-$rn] | median else null end) as $usual
        | {file: $f, cpu: $now, median: ($m | r3), change: (if $m > 0 then ($now - $m) / $m | r3 else null end),
           runs: ($r[-$keep:] | reverse | map(del(.file))),
           lastRun: (if $r == [] then null else $r[-1] | {sec, cpu, clockPerCpu: (if .sec != null and .cpu > 0 then .sec / .cpu | r3 else null end), time, whole} end),
           timedRuns: ($c | length), runsOnRecord: ($r | length), wholeOnly: $wo, failedSteps: ($failed[$f] // [] | length),
           failures: ($failed[$f] // [] | to_entries | map(.value + if .key < $keep then {} else {tail: null} end)),
           caught: ($catch[$f].caught // 0), changedToPass: ($catch[$f].changed // 0),
           flaky: ($flaky[$f] // 0),
           issue: ([($sf.filed | arrays | .[] | objects), $fd[] | select(.file == $f) | .issue | numbers] | max),
           slowOnPurpose: ($own.slowOnPurpose // null), usual: ($usual | r3),
           slower: ($wo | not) and $usual != null and all($c[-$rn:][]; . > $usual * (1 + $sh)), hollow: ($hv[$f] // null),
           mutation: ([$mu[] | select(.file == $f)] | max_by(.at) | if . == null then null
             else {file, at, sha, seed, state, reason, of: (.mutants | length), tried, killed, survived, noresult, notMutated, end} end),
           mutationPlace: ($place[$f] // null), cases: ($cs[0][$f] // []),
           waits: ([$tj[] | select(.file == $f)] | max_by(.end // "") | if . == null or .waits == [] then null else .waits end)}
        | .optimize = ([$ta[] | select(.file == $f)] | unique_by(.issue) | sort_by(.time) | reverse | map(optimize($r)))
        | .removed = (($f | IN($all[]) | not) and any(.optimize[]; .state == "landed" and (.fix | IN("deleted", "merged")))))
    | sort_by(-(.cpu // -1), .file)
    | [$ls[] | select(.reused != true and ((.time | fromdate? | strflocaltime("%Y-%m-%d")) // "") >= $since)] as $wk
    | {settings: {slowIssues: ($si == "true"), slower: {share: $sh, runs: $rn, minRuns: $mn}, files: $fs},
       rules: (if $ru == null then null else $ru + {last: $last[0], log: ($lg[0] // [])} end),
       files: ., slower: map(select(.slower) | .file),
       edits: (reduce $alledits[] as $e ({n: {}, out: []};
           if (.n[$e.file] // 0) < $keep then .out += [$e] | .n[$e.file] += 1 else . end) | .out),
       totals: (map(select(.removed | not)) | {files: (map(select(.timedRuns > 0)) | length), slower: (map(select(.slower)) | length)}) + {
         steps: {count: ($wk | length), waitSec: ([$wk[].wait | numbers] | add // 0 | r3), runSec: ([$wk[].run | numbers] | add // 0 | r3)}}}') || return 1
  nv=$(neverwhy "$(jq -c '[.files[] | select(.runsOnRecord == 0 and (.removed | not)) | .file]' <<<"$out")") || nv='{}'
  rp=$(jq -ce '.test.report | objects' "$PACK" 2>/dev/null) || rp=null
  cp=$(cpuplan 2>/dev/null) || cp=null
  jq -c --slurpfile nv <(printf '%s' "$nv") --argjson rp "$rp" --argjson cp "$cp" --slurpfile su <(jq -cR 'fromjson? | objects' "$SUITERUNS" 2>/dev/null) '$nv[0] as $nv | .files |= map(.neverRun = ($nv[.file] // null))
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
# file is parsed once a content; skipped: it
# holds skip markers (the test edits' table, TESTEDIT_TABLE, an `only` mark aside), each named once.
neverwhy() { # <the files, a JSON list>
  local f cmd rn w pat x ld bl e l1 le sk new='' out='' nl=$TESTACTS/neverloads
  [ "$(jq 'length' <<<"$1" 2>/dev/null)" != 0 ] || { echo '{}'; return; }
  packget test.command cmd 2>/dev/null || cmd=''
  rn=$(testrunner "$cmd" "$MAIN" 2>/dev/null); w=''; [[ $rn != named\ * ]] || w=${rn##* }
  pat=$(jq -r '.[]' <<<"$1" | testpaths 2>/dev/null)
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
  done < <(jq -r '.[]' <<<"$1")
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
#   cpu-time <file>              test.command made the one cpuplan() gives for that file (Record CPU time, #190)
# A file with no setting left is taken out of test.files (packset()).
TESTSET_USAGE='usage: conveyor.sh test-settings slow-issues <true | false> | slow-mark <file> <reason> | slow-mark-clear <file> | cpu-time <file>'
testsettings() { # <what> [<file>] [<value>]
  local why='' r=${3:-} p
  case ${1:-}:$# in
    slow-issues:2 | slow-mark:3 | slow-mark-clear:2 | cpu-time:2) ;;
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
    cpu-time) packset --arg c "$(jq -r '.command' <<<"$p")" '.test.command = $c' ;;
  esac
}
# Record CPU time (#190): how the pack's test command can give a Wall only file's CPU seconds, as JSON. No runner's
# report gives CPU seconds (README.md, Test file times), so a report option never can. The wrapper
# conveyor/tools/testtime.sh times one command as one file's run, so it applies when the test command runs one test
# file and nothing else: the command is given no list (test.list not set, or none), is one plain command (no ; & | < >
# $ ` quote or bracket), and of its words exactly one names a path of main's checkout, a test file. Then it prints
# {file, was, command}: the command wrapped in testtime.sh (its path in CONVEYOR_TEST_TIME, testonce()), its output
# as before and its `TESTRUN sec` line put in the run's log, where the run reads it. The wrapper is a shell function
# called last, so the words a run adds at the command's end (the runner's report args, reportask()) go to the test
# command. Else {why}: why neither applies.
cpuplan() {
  local cmd lm w ws=() ps=() q
  packget test.command cmd test.list lm || return 1
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
  q=$(printf %q "${ps[0]}")
  jq -cn --arg f "${ps[0]}" --arg was "$cmd" --arg c "conveyor_cputime() { local o r; o=\$(mktemp); \"\$CONVEYOR_TEST_TIME\" $q -- $cmd \"\$@\" > \"\$o\" 2>&1; r=\$?; cat \"\$o\"; grep '^TESTRUN sec' \"\$o\" >> \"\$CONVEYOR_TEST_LOG/cputime\"; rm -f \"\$o\"; return \$r; }; conveyor_cputime" \
    '{file: $f, was: $was, command: $c}'
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
