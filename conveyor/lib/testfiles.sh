# SPDX-License-Identifier: Apache-2.0
# The test files in the snapshot (README.md, The test files in the snapshot): the snapshot's tests part, and the
# command that sets the pack's test settings the Board saves (conveyor.sh test-settings).

# The snapshot's tests part, read from the card records (recs, olds: a retried card's runs count too), the pack, the
# flaky-test record ($FLAKY), the slow-test record ($SLOWFILED), the test rules' log ($TESTRULESLOG) and the Board's
# test issues ($TAFILED):
# settings: the pack's fileBudget, slowIssues (true or false), slower ({share, runs, minRuns}) and files (each file's own
#   budget and slowOnPurpose, as the pack holds them);
# rules: the test rules (lib/testrules.sh): the pack's switch, guards and rules (testrulesettings()), and last: the
#   list of the last pass (testrulespass()), {time, on, matches, burst}, null before the first, and log: the last
#   TESTRULES_SHOWN lines of the rules' log ($TESTRULESLOG), newest first; null when the pack cannot be read;
# files: each test file main's checkout tracks (a name with `.test.` in it), and each other file with a run on record:
#   a card's test line (times) or a whole-suite run ($SUITERUNS, suiterec() of lib/testrun.sh); the highest CPU seconds
#   now first, a file with none last: file, cpu (its newest run's that has CPU seconds; null with none), median (of
#   every run on record with CPU seconds), change (cpu against median, as a share: 0.5 is 50% over; null when the
#   median is 0 or null), runs (its last TESTKEEP runs, newest first: {cpu, sec: clock seconds, null on a line that
#   gives none; card (null for a whole-suite run), time, whole (a whole-suite run), and a whole-suite run's result: ok,
#   fail or null}; [] for a file never run), lastRun ({sec, cpu, clockPerCpu, time, whole} of its newest run; null with
#   none), timedRuns (its runs with CPU seconds), runsOnRecord (its runs on record), wholeOnly (its test.files entry's wholeOnly), failedSteps (the test steps
#   that failed with it among the failed files, or with a case it defines that its runner named, or timed out in it),
#   caught and changedToPass (those of them whose card landed: caught when the landed commit left the file as it was,
#   so the fix went into the code; changedToPass when that commit changed the file),
#   flaky (its entries in the flaky-test record, its cases' too, a runner's name for them as well), issue (the issue last filed for it, the highest number of the slow-test record's, the test rules' log's and the Board's filings ($TAFILED), else null; the Board's Close its issue as done closes it), budget and budgetFrom (file: its own;
#   project: test.fileBudget), slowOnPurpose (its reason, else null), over (cpu over its budget; false with no cpu), usual (the median of
#   its runs before its last slower.runs runs; null with fewer than slower.minRuns runs on record) and slower; a wholeOnly
#   file (a runner that starts other test files whole, each timed with its own budget) is held to no budget: budget and
#   budgetFrom null, over and slower false; optimize: each issue the Board filed for it ($TAFILED: Optimize, and older
#   speed-up, issues), newest first: {issue, time (filed), state (open: no card took it; building; blocked, with reason;
#   landed, with sha and landed, the time; closed: its card closed it without landing), fix, into, before and after
#   (from the bugproof line's speed of its landed card, else of its newest: fix is sped up, split, merged or deleted,
#   into the test files a split added or a merge changed, or, for a delete, those the last review of its landed card
#   named on its COVERED-BY lines; null and [] with none), since (the median CPU seconds of the
#   file's runs after it landed; null with none or before it lands) and sinceRuns (their count)}; removed: true for a
#   file main's checkout no longer tracks whose landed Optimize deleted or merged it (the totals leave it out);
#   a file that only a Board filing names is listed too;
# slower: the files slower than their usual, by name: each of their last slower.runs runs over usual by more than
#   slower.share;
# edits: each entry of the landed lines' testedits (testedits(), below), newest first, with its card, issue and time;
#   a file's newest TESTKEEP alone, so the list grows with the test files, not with the cards that land;
# totals: files (those with CPU seconds on record), overBudget (over and not slow on purpose), slower, and steps: the card test steps that ran in
#   the 7 days to today ({count, waitSec: their seconds waiting for a test slot, runSec: their test commands' seconds}).
TESTKEEP=5
# A runner (the engine's conveyor/conveyor.test.sh) names its cases' failures and flaky entries as its own, while the
# times name each case file it ran: a case counts for the named file alone when that file defines it (`t_<case>()` or
# `<case>()`), else for the named file and the test files of main's checkout that define it and name that runner (a
# case file runs itself through its runner). A file with a case of the same name that runs alone or through another
# runner is not that runner's. testowners sets the caller's defs (each case name to the files that define it) and refs
# (each test file to the test file names it holds); OWNERS is the jq that reads them, given as $defs and $refs:
# caseowners (the files a flaky entry's case counts for) and failedfiles (the files a failed test line counts for).
testowners() {
  defs=$(git -C "$MAIN" grep -oE '^(t_)?[A-Za-z0-9_]+\(\)' -- '*.test.*' 2>/dev/null \
    | jq -cRn '[inputs | capture("^(?<f>.+):(t_)?(?<c>[A-Za-z0-9_]+)\\(\\)$")] | group_by(.c) | map({key: .[0].c, value: [.[].f] | unique}) | from_entries') || defs='{}'
  refs=$(git -C "$MAIN" grep -oE '[A-Za-z0-9_.-]+\.test\.[A-Za-z0-9]+' -- '*.test.*' 2>/dev/null \
    | jq -cRn '[inputs | capture("^(?<f>[^:]+):(?<n>.+)$")] | group_by(.f) | map({key: .[0].f, value: [.[].n] | unique}) | from_entries') || refs='{}'
}
OWNERS='def owners($f; $c): ($defs[$c // ""] // []) as $d | ($f | split("/")[-1]) as $n
      | if $c == null or any($d[]; . == $f) then [$f] else [$f] + [$d[] | select(any($refs[.][]?; . == $n))] end;
    def caseowners: index(": ") as $i | if $i == null then [.] else owners(.[:$i]; .[$i + 2:]) end;
    def failedfiles: [(.failures.files | arrays | .[] | objects | (.file | strings) as $f
        | if (.cases | arrays | length) > 0 then .cases[] | owners($f; .name | strings)[] else $f end), (.failures.timeout.file? | strings)] | unique;'
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
testspart() { # <the first day of the 7 days, YYYY-MM-DD>
  local b si sh rn mn fs fl sf defs refs ru all ln ch
  packget test.fileBudget b test.slowIssues si test.slower.share sh test.slower.runs rn test.slower.minRuns mn test.files fs || return 1
  all=$(git -C "$MAIN" ls-files -z -- '*.test.*' 2>/dev/null | jq -Rsc 'split("\u0000") | map(select(. != ""))') || all='[]'
  fl=$(jq -ce 'objects' "$FLAKY" 2>/dev/null) || fl='{}'
  sf=$(jq -ce 'objects' "$SLOWFILED" 2>/dev/null) || sf='{}'
  ru=$(testrulesettings) || ru=null
  testowners
  # A project with no test line has its part all the same: grep finding none is no failure. The steps other than test
  # are those that give a Board filing's state (optimize, below) and a card's landed commit (caught, below).
  ln=$({ olds; recs; } 2>/dev/null | { grep -E '"step":"(test|picked|bugproof|blocked|closed|landed|review)"' || :; })
  # The files each landed commit of a card with a failed test step changed, by its sha: {sha: [file...]}, from one git
  # call (a commit main's checkout does not have is left out). A path is a commit's key only when it is one of the
  # commits asked for.
  ch=$(jq -rRn '[inputs | fromjson? | objects] | (map(select(.step == "test" and .result == "fail") | .card) | unique) as $f
      | .[] | select(.step == "landed" and (.card | IN($f[])) and (.sha | strings | test("^[0-9a-f]{40}$"))) | .sha' <<<"$ln" 2>/dev/null | sort -u)
  ch=$(printf '%s\n' "$ch" | git -C "$MAIN" diff-tree --stdin -r --root --name-only --no-renames -z 2>/dev/null \
    | jq -Rsc --arg want "$ch" '($want | split("\n") | map(select(. != "") | {key: ., value: true}) | from_entries) as $w
      | reduce (split("\u0000")[] | select(. != "")) as $x ({k: null, m: {}}; if $w[$x] then .k = $x | .m[$x] = [] elif .k == null then . else .m[.k] += [$x] end) | .m') || ch='{}'
  printf '%s\n' "$ln" | jq -cRn --arg since "$1" --argjson b "$b" --arg si "$si" --argjson sh "$sh" --argjson rn "$rn" --slurpfile ch <(printf '%s\n' "$ch") \
    --argjson mn "$mn" --argjson fs "$fs" --argjson fl "$fl" --argjson sf "$sf" --argjson keep "$TESTKEEP" --argjson defs "$defs" --argjson refs "$refs" \
    --argjson ru "$ru" --argjson all "$all" --slurpfile su <(jq -cR 'fromjson? | objects' "$SUITERUNS" 2>/dev/null) --slurpfile last <(jq -ce 'objects' "$TESTRULES" 2>/dev/null || echo null) \
    --slurpfile lg <(tail -n "$TESTRULES_SHOWN" "$TESTRULESLOG" 2>/dev/null | jq -cRn '[inputs | fromjson? | objects] | reverse' 2>/dev/null || echo '[]') \
    --slurpfile fd <(cat "$TESTRULESLOG" "$TAFILED" 2>/dev/null | jq -cR 'fromjson? | objects | select(.event == "filed")' 2>/dev/null) \
    --slurpfile ta <(jq -cR 'fromjson? | objects | select(.event == "filed" and (.file | type == "string") and (.issue | type == "number"))' "$TAFILED" 2>/dev/null) "$OWNERS"'
    def median: sort | if length == 0 then null else (.[(length - 1) / 2 | floor] + .[length / 2 | floor]) / 2 end;
    def r3: if . == null then null else . * 1000 | round / 1000 end;
    [inputs | fromjson? | objects] | sort_by(.time) | . as $cr | map(select(.step == "test")) as $ls
    # A Board filing ($TAFILED) as its cards left it, given the runs of its file ($r, oldest first).
    | def optimize($r): . as $o | [$cr[] | select(.issue == $o.issue)] as $c
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
           before: ($p.before // null), after: ($p.after // null), since: ($since | if . == null then null else median | r3 end), sinceRuns: ($since | length)};
    (reduce ($ls[] | select(.result == "fail") | failedfiles[]) as $f ({}; .[$f] += 1)) as $failed
    # Each failed test step of a card that landed, for each file it failed in: caught when the landed commit left the
    # file as it was (the fix went into the code), changed to pass when it changed the file.
    | (reduce ($cr[] | select(.step == "landed" and (.card | type == "string"))) as $l ({}; .[$l.card] = $l.sha)) as $land
    | (reduce ($ls[] | select(.result == "fail" and (.card | type == "string")) | ($ch[0][$land[.card] | strings] // null) as $d | select($d != null)
        | failedfiles[] | [., IN($d[])]) as [$f, $ed] ({}; if $ed then .[$f].changed += 1 else .[$f].caught += 1 end)) as $catch
    | (reduce ($fl.entries | arrays | .[] | objects | .case | strings | caseowners[]) as $f ({}; .[$f] += 1)) as $flaky
    | [($ls[] | . as $l | .times | objects | to_entries[] | select(.value | type == "number") | .key as $f
        | {file: $f, cpu: .value, sec: (($l.clocks | objects | .[$f] | numbers) // null), card: $l.card, time: $l.time, whole: false}),
       ($su[] | . as $w | .files | objects | to_entries[] | select(.value | type == "object")
        | {file: .key, cpu: ((.value.cpu | numbers) // null), sec: ((.value.sec | numbers) // null), card: null, time: $w.time, whole: true,
           result: ((.value.result | strings) // null)}),
       ($all[], $ta[].file | {file: ., none: true})]
    | group_by(.file)
    | map(.[0].file as $f | map(select(.none != true)) | sort_by(.time) as $r | [$r[].cpu | numbers] as $c | ($c | median) as $m | $c[-1] as $now
        | ($fs[$f] // {}) as $own | ($own.budget // $b) as $bud | ($own.wholeOnly == true) as $wo
        | (if ($c | length) >= $mn and ($c | length) > $rn then $c[:-$rn] | median else null end) as $usual
        | {file: $f, cpu: $now, median: ($m | r3), change: (if $m > 0 then ($now - $m) / $m | r3 else null end),
           runs: ($r[-$keep:] | reverse | map(del(.file))),
           lastRun: (if $r == [] then null else $r[-1] | {sec, cpu, clockPerCpu: (if .sec != null and .cpu > 0 then .sec / .cpu | r3 else null end), time, whole} end),
           timedRuns: ($c | length), runsOnRecord: ($r | length), wholeOnly: $wo, failedSteps: ($failed[$f] // 0),
           caught: ($catch[$f].caught // 0), changedToPass: ($catch[$f].changed // 0),
           flaky: ($flaky[$f] // 0),
           issue: ([($sf.filed | arrays | .[] | objects), $fd[] | select(.file == $f) | .issue | numbers] | max),
           budget: (if $wo then null else $bud end), budgetFrom: (if $wo then null elif $own.budget != null then "file" else "project" end),
           slowOnPurpose: ($own.slowOnPurpose // null), over: ($wo | not) and $now != null and $now > $bud, usual: ($usual | r3),
           slower: ($wo | not) and $usual != null and all($c[-$rn:][]; . > $usual * (1 + $sh))}
        | .optimize = ([$ta[] | select(.file == $f)] | unique_by(.issue) | sort_by(.time) | reverse | map(optimize($r)))
        | .removed = (($f | IN($all[]) | not) and any(.optimize[]; .state == "landed" and (.fix | IN("deleted", "merged")))))
    | sort_by(-(.cpu // -1), .file)
    | [$ls[] | select(.reused != true and ((.time | fromdate? | strflocaltime("%Y-%m-%d")) // "") >= $since)] as $wk
    | {settings: {fileBudget: $b, slowIssues: ($si == "true"), slower: {share: $sh, runs: $rn, minRuns: $mn}, files: $fs},
       rules: (if $ru == null then null else $ru + {last: $last[0], log: ($lg[0] // [])} end),
       files: ., slower: map(select(.slower) | .file),
       edits: (reduce ($cr | reverse[] | select(.step == "landed" and (.testedits | type == "array")) | . as $l
         | .testedits[] | objects | select(.file | type == "string") | {card: $l.card, issue: $l.issue, time: $l.time} + .) as $e ({n: {}, out: []};
           if (.n[$e.file] // 0) < $keep then .out += [$e] | .n[$e.file] += 1 else . end) | .out),
       totals: (map(select(.removed | not)) | {files: (map(select(.timedRuns > 0)) | length), overBudget: (map(select(.over and .slowOnPurpose == null)) | length), slower: (map(select(.slower)) | length)}) + {
         steps: {count: ($wk | length), waitSec: ([$wk[].wait | numbers] | add // 0 | r3), runSec: ([$wk[].run | numbers] | add // 0 | r3)}}}'
}

# conveyor.sh test-settings: one test setting of the pack saved, as the Board saves it. Each refuses a bad value, says
# why and changes nothing:
#   budget <CPU s>               test.fileBudget, a number of at least 1
#   slow-issues <true | false>   test.slowIssues
#   file-budget <file> <CPU s>   test.files.<file>.budget, for a file main's checkout tracks
#   file-budget-clear <file>     that budget taken off: the file is held to test.fileBudget again
#   slow-mark <file> <reason>    test.files.<file>.slowOnPurpose: the reason, one line that is not blank
#   slow-mark-clear <file>       that mark taken off
# A file with neither setting left is taken out of test.files.
TESTSET_USAGE='usage: conveyor.sh test-settings budget <CPU s> | slow-issues <true | false> | file-budget <file> <CPU s> | file-budget-clear <file> | slow-mark <file> <reason> | slow-mark-clear <file>'
testsettings() { # <what> [<file>] [<value>]
  local why='' r=${3:-}
  case ${1:-}:$# in
    budget:2 | slow-issues:2 | file-budget:3 | file-budget-clear:2 | slow-mark:3 | slow-mark-clear:2) ;;
    *) echo "$TESTSET_USAGE" >&2; return 2 ;;
  esac
  case $1 in
    budget | file-budget) [[ ${!#} =~ ^[1-9][0-9]{0,5}(\.[0-9]{1,3})?$ ]] || why="the budget is CPU seconds, a number of at least 1 (such as 8 or 12.5), not \"${!#}\"" ;;
    slow-issues) [[ $2 =~ ^(true|false)$ ]] || why="test.slowIssues is true or false, not \"$2\"" ;;
    slow-mark) r=${r#"${r%%[![:space:]]*}"}; r=${r%"${r##*[![:space:]]}"}  # the reason with no space at its ends
      [[ $3 != *[$'\n\r']* ]] || why="the reason is one line"; [ -n "$r" ] || why="a file is marked slow on purpose only with a reason" ;;
  esac
  case $1 in file-budget | slow-mark)
    { [ -n "$2" ] && [ "$(git -C "$MAIN" ls-files -- ":(literal)$2" 2>/dev/null)" = "$2" ]; } || why=${why:-"\"$2\" is not a file of main's checkout"} ;;
  esac
  [ -z "$why" ] || { echo "conveyor: test-settings $1: $why; nothing changed" >&2; return 1; }
  case $1 in
    budget) packset --argjson v "$2" '.test.fileBudget = $v' ;;
    slow-issues) packset --argjson v "$2" '.test.slowIssues = $v' ;;
    file-budget) packset --arg f "$2" --argjson v "$3" '.test.files[$f].budget = $v' ;;
    slow-mark) packset --arg f "$2" --arg v "$r" '.test.files[$f].slowOnPurpose = $v' ;;
    file-budget-clear) packset --arg f "$2" 'if .test.files[$f] == null then . else del(.test.files[$f].budget) end' ;;
    slow-mark-clear) packset --arg f "$2" 'if .test.files[$f] == null then . else del(.test.files[$f].slowOnPurpose) end' ;;
  esac
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
