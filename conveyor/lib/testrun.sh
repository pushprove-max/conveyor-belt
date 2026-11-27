# SPDX-License-Identifier: Apache-2.0
# The test map (which tests cover which source files), which a card's list of tests reads: lib/testmap.sh.
. "${BASH_SOURCE[0]%/*}/testmap.sh" || return 1
# The parts of how the engine tests a card that are kept in files of their own: lib/testlist.sh (what a run runs and
# keeps), lib/mainred.sh (a failure that is main's or the machine's), lib/bugproof.sh (the bug-card check),
# lib/speedproof.sh (the checks of the Tests page's fix cards), lib/donewhen.sh (the checks, the commit trailers,
# the Done-when check and the review's findings), lib/failat.sh (where a test failed, read from its output's stack
# traces), lib/loadfactor.sh (the load factor a run's time limits grow by) and lib/fileeach.sh (the run of a card's
# test files side by side).
. "${BASH_SOURCE[0]%/*}/testlist.sh" || return 1
. "${BASH_SOURCE[0]%/*}/mainred.sh" || return 1
. "${BASH_SOURCE[0]%/*}/bugproof.sh" || return 1
. "${BASH_SOURCE[0]%/*}/speedproof.sh" || return 1
. "${BASH_SOURCE[0]%/*}/donewhen.sh" || return 1
. "${BASH_SOURCE[0]%/*}/failat.sh" || return 1
. "${BASH_SOURCE[0]%/*}/loadfactor.sh" || return 1
. "${BASH_SOURCE[0]%/*}/fileeach.sh" || return 1
# Only the lines the jq of testfails() acts on reach it, so a log of millions of lines of noise (a loop, a stuck retry)
# costs it no more than the same output without them: a `== ` line, a result line (`FAIL [`, `ok`, `not ok`, `✔`,
# `✖`), the `---` of a TAP block (only straight after a result line, as tapyaml reads it) and its `...`, a stack frame
# (JavaScript: a path, a line and a column at the end; Python: `File "/`) and the first line with no indent after a
# Python frame (its exception). A kept line is read as it would be in the whole output; the lines left out change none
# of its state.
# What a failed test run says went wrong: the failing test files, never the passing ones or their `ok` lines. Which
# files ran and which failed is read from the logs the runner wrote (testlogs), never from the output, where a test's
# own lines could pass for the runner's: `== <file>` as a file begins (the whole line: a name may have spaces),
# `-- ok|FAIL <file>` as it ends, `TESTRUN files=N` for how many it selected. A failed file is listed even when no line names a case of it. A failing case is a
# line of the output: `FAIL [<case>]: ...`, TAP's `not ok N - <case>` (never a TODO or SKIP one; tapjq(), lib/failat.sh: its name is read back as the case has it, and a line in a result's YAML block is no result) or node's
# `✖ <case> (Nms)`; it is its file's when the output has `== <file>` before it for a file the logs say began, and
# began after the file the output was in (a log is one runner's and its files run in its order, so a `== ` line that
# goes back in its log, or names no file of the run, is a test's own), else the run's one failed file's when it failed one, else under the file "" unless a file has the case (issue 1639). A case line under a
# file that passed is that test's own output and is no failure. A runner prints each of its files' `== ` lines once,
# in its log's order, so a case line can be of each file that leaves every file of its log up to it a `== ` line
# before the case, in order, and every later file one after it. The logs of two runners say nothing of which ran
# first, so the output says it: a case is of the file whose `== ` line is the last before it, and a file is none of
# its when another runner's log cannot have its lines around that line, in order: some of them by that line and the
# rest from the case on. A file two runners ran has a line of each: whose a line is, is the reading that lets the
# most `== ` lines of the whole output move a log on; a line of such a file that moves no log on (a test printed one
# of its lines) is of each runner that ran it, so the runner's own line, coming after a test's, still names its file. A test that prints `== ` lines of its own can widen that to more than one file, which cannot be told apart: then
# the case is under each of them that failed, so no test hides its failing case behind another file's line (the price:
# a test that forges a neighbour's line can put a case of its own under a failed neighbour too). An output without
# every file's line in the logs' order is read as before: a case is of the last file whose line went forward. A
# `== <file>` counts wherever it is in a line, after the line's own case: a test whose output ends without a newline
# has the runner's next line joined to its last, and could else hide its case by leaving the later file no line.
# A case has its first such line, cut to 200 characters at a word. of is the files selected,
# else those the logs name (null when none). timeout is null unless the run ran out of time (exit 124): then the
# seconds it had (<worktree>.limit, the limit scaled by the run's load factor: testonce(); else TEST_TIMEOUT; when the file named was stopped by its own limit, that file's, read from the line `conveyor: <file> timed out: it ran past its time limit, <n> s`) and the last file begun and not ended (null when there is none). passed is the files the logs say
# ended ok (tests() runs them no more on the same change), a file begun and not ended in one log too when another log
# ended it (a machine stopped as the file's own runner, its pass logged, cleaned up: fileeach() logs the end line only
# once that command ends), unless its own limit stopped it; okcases, of each other file, the cases a line `ok <case>`
# (or node's `✔ <name> (<n>ms)`, or TAP's `ok <n> - <name>`) under it says passed (a runner killed part-way runs
# them no more); passcases, the same of each file that passed (what a batch that takes the card need not run again:
# testlist.sh passlist()); stopped, with a timeout only, each file begun and not ended (its own limit stopped it, or
# the run's did): timeout names only the last of them, and another file's cases may have passed; ownLimit, when there is one, each its own limit stopped (`-- timeout <file>`: fileeach()). A run whose command wrote no such
# log is one file, named by the command (test.command): its cases are that file's, and a timeout is in it. An output
# that is no run's (norun(): no log folder) names no file. notRun, only when there is one, is each file a card's run
# that stopped at its first failure did not run or did not finish (`-- notrun <file>` log lines: fileeach()): none of
# timeout, stopped or passed names it, as the stop ended it, not a limit, and it did not pass. host, only when there
# is one: each file logged `TESTRUN host<TAB><file><TAB><why>` (not started for want of room), no other field's (#1662).
# A case's line ends with where it failed, ` (at <file>:<line>: <that line's text>)`, when a stack trace follows a
# failure line of the case in the output: its place in a file of the worktree (<worktree>.test's <worktree>, outside
# node_modules; FRAMEJQ: a JavaScript stack's first frame there, a Python traceback's last), the text read there
# (wtline()), trimmed and cut to 120 characters. A failed file whose failure names no case (python3 on a unittest
# file) has at, `<file>:<line>: <text>`, of the first stack after its `== ` line that no case took. So a failure that
# prints no message of its own (node's assert.ok(false) under TAP: only actual and expected) still shows the assertion.
testfails() { # <test output file> <exit> [the pack's field of the run's command: test.command]; prints {of, files: [{file, cases: [{name, line}], at}], timeout, passed, okcases: [{file, cases}], passcases: [{file, cases}], notRun, host}
  local logs=() log cmd='' named out own wd=${1%.test} wdr=''
  [ -d "$wd" ] && wd=$(cd "$wd" && pwd) && wdr=$(cd "$wd" && pwd -P) || wd=''
  # A file's name may have spaces, at its end too, and words may follow it on a line that is not its beginning in the
  # logs (a duration, the cases run): the file such a line names is the longest of the files it can be that the line's
  # words begin with. An end can be only of a file begun and not ended: never of a file that is done, whose name the
  # line may begin with too, and never of a file of another runner's log: a log's end lines are of its own files. A
  # `== ` line of the output is of the longest of all the run's files: one that names again a file that is done goes
  # back, and is never the beginning of a later file whose name its name begins with.
  named='def named($fs): . as $r | [$fs[] | select(. as $f | $r == $f or ($r | startswith($f + " ")))] | max_by(length);'
  own=$(sed 's/\x1b\[[0-9;]*m//g' "$1" 2>/dev/null | tr -d '\000\r' | jq -cRn '[inputs | capture("^conveyor: (?<f>.*\\S) timed out: it ran past its time limit, (?<n>[0-9]+) s, and it was stopped there(; .*)?$") | {key: .f, value: (.n | tonumber)}] | from_entries') || own='{}'; mapfile -t logs < <(testlogs "${1%.test}"); [ ! -d "${1%.test}.testlog" ] || packget "${3:-test.command}" cmd 2>/dev/null || cmd=''
  # Each log begins on a line of its own: a log that ends without a newline would else join the next log's mark.
  log=$(for log in "${logs[@]}"; do printf '\n\001\n'; cat "$log" 2>/dev/null; done | sed 's/\x1b\[[0-9;]*m//g' | tr -d '\000\r' | jq -cRn "$named"'
    (reduce inputs as $l ({n: null, files: [], order: [], failed: [], open: [], ended: [], notrun: [], host: [], limit: []};
      . as $s | ([$l | capture("^== (?<f>.*\\S.*)")][0].f) as $b | ([$l | capture("^-- notrun (?<f>.*\\S.*)")][0].f) as $x | ([$l | capture("^-- timeout (?<f>.*\\S.*)")][0].f) as $lf | ([$l | capture("^TESTRUN host\t(?<f>[^\t]*\\S[^\t]*)\t")][0].f) as $hf
      | ([$l | capture("^-- (?<r>ok|FAIL) (?<f>.*\\S.*)") | .f |= (named($s.open[-1]) // (sub("^ +"; "") | named($s.open[-1]) // named($s.order[-1]) // sub(" .*"; "")))][0]) as $e
      | ([$l | capture("^TESTRUN files=(?<n>[0-9]+)")][0].n) as $n
      | if $l == "\u0001" then .order += [[]] | .open += [[]] | .ended += [[]]
        elif $b then .files |= (. + [$b] | unique) | (if .order[-1] | index($b) then . else .order[-1] += [$b] end) | .open[-1] += [$b]
        elif $e then .files |= (. + [$e.f] | unique) | .open[-1] -= [$e.f] | .ended[-1] += [$e.f] | if $e.r == "FAIL" and (.failed | index($e.f) | not) then .failed += [$e.f] else . end
        elif $x then .notrun |= (. + [$x] | unique) elif $lf then .limit |= (. + [$lf] | unique) elif $hf then .host |= (. + [$hf] | unique) elif $n then .n += ($n | tonumber) else . end) | .failed -= .host | .notrun -= .host)') || return 1
  out=$(sed 's/\x1b\[[0-9;]*m//g' "$1" 2>/dev/null | tr -d '\000\r' | awk '{ k = /== / || /^[[:space:]]*(not ok |ok |✔|✖)/ || /^FAIL \[/ || /^ *[.][.][.]$/ || (/^ *---$/ && prev ~ /^ *(not )?ok /) || /\/[^():]*:[0-9]+:[0-9]+\)?([[:space:]]*[{])?[[:space:]]*$/ || /^[[:space:]]*File "\//; if (py && /^[^[:space:]]/ && !/^Traceback /) { k = 1; py = 0 }; if (/^[[:space:]]*File "\//) py = 1; prev = $0; if (k) print }' | jq -cRn --arg rc "$2" --arg sec "$(cat "${1%.test}.limit" 2>/dev/null || echo "${TEST_TIMEOUT:-}")" --arg cmd "$cmd" --argjson own "$own" --slurpfile log <(printf '%s' "$log") --slurpfile rec <(cat "${1%.test}.testlog"/results/* 2>/dev/null | jq -cR 'fromjson? // empty') \
    --arg rx "${FRAMERX:-}" --arg pyrx "${PYFRAMERX:-}" --arg wd "$wd" --arg wdr "$wdr" '$log[0] as $log | '"$named ${FRAMEJQ:-def frame: null; def pyend(\$l): false;} ${RECJQ:-def recs(\$r; \$l): .;} $(tapjq 2>/dev/null || printf %s 'def tapname: .; def tapyaml: .;')"'
    def cut: if length <= 200 then . else (.[0:201] | sub("\\s+\\S*$"; "")) as $w | if ($w | length) > 200 then .[0:200] else $w end end;
    def failcase: [capture("^FAIL \\[(?<c>[^\\]]+)\\]: "), (capture("^\\s*not ok [0-9]+ (- )?(?<c>.*\\S)") | tapname), capture("^\\s*✖ (?<c>.+) \\([0-9.]+ms\\)$")][0].c;
    (if $log.files == [] and $cmd != "" then $cmd else null end) as $only | (if ($log.failed | length) == 1 then $log.failed[0] else "" end) as $one
    | ([inputs] | tapyaml) as $ls | ($log.order | map(length)) as $ns
    # $at: of each failing case, [file, line] of the first place a stack after its failure line names in the worktree
    # (FRAMEJQ); a passed case line or a `== ` line of a file of the run (not the `=== ` of an assertion node prints before
    # the stack) ends the search. $fat: of each file of the run, the first such place after its `== ` line that no
    # failing case took (a file whose failure names no case, as python3 runs a unittest file). With no FRAMERX (no
    # globals of this file) there is no place, and stand-ins of the defs of FRAMEJQ, which read no frame, compile.
    | (if $wd == "" or $rx == "" then {at: {}, fat: {}} else
        def put($a): if .c then .at[.c] = $a | .c = null elif .f and (.fat[.f] | not) then .fat[.f] = $a else . end;
        reduce ($ls[], "\u0000") as $l ({c: null, f: null, py: null, at: {}, fat: {}};
          (if .py and pyend($l) then put(.py) | .py = null else . end)
          | ($l | failcase) as $c | ($l | frame) as $fr
          | ([$l | split("== ")[1:][] | named($log.order | flatten) // empty] | last) as $mf
          | if $c then .c = (if .at[$c] then null else $c end) | .py = null
            elif $mf then .c = null | .py = null | .f = $mf
            elif ($l | test("^\\s*(ok |✔ )")) then .c = null
            elif $fr == null or $fr.f == null then .
            elif $fr.py then .py = [$fr.f, $fr.n]
            else put([$fr.f, $fr.n]) end) | {at, fat} end) as {at: $at, fat: $fat}
    # $ts: each `== ` line of a file of the run, as [line, file]: anywhere in the line, since an output that ends
    # without a newline has the next `== ` line of the runner joined to its last line.
    | [$ls | to_entries[] | .key as $k | .value | split("== ")[1:][] | (named($log.order | flatten) // empty) as $f | [$k, $f]] as $ts
    # $took: the log each `== ` line moves on, by its place in $ts: a line moves a log on when it can, and one that
    # could move either of two logs moves the one that lets the most lines of the whole output move a log on.
    | (reduce range(0; $ts | length) as $t ([{at: ($ns | map(-1)), p: []}]; $ts[$t][1] as $f
        | [.[] | . as $s | [$log.order | to_entries[] | .key as $r | (.value | index($f)) as $j | select($j != null and $j > $s.at[$r]) | {at: ($s.at | .[$r] = $j), p: ($s.p + [[$t, $r]])}]
          | if . == [] then $s else .[] end]
        | group_by(.at) | map(sort_by([-(.p | length), .p]) | first))
      | sort_by([-(.p | length), .p]) | first | .p | map({key: (.[0] | tostring), value: .[1]}) | from_entries) as $took
    # $hs[k]: the files line k has a `== ` line of, each as [log, place in the log]: a file of one log is of that log,
    # a file two runners ran is of the log its line moves on; a line of it that moves none on is one line more than
    # its runners printed, and which of its lines a test printed cannot be told: that line is of each of its logs.
    | (reduce range(0; $ts | length) as $t ($ls | map([]); $ts[$t] as [$k, $f]
        | [$log.order | to_entries[] | select(.value | index($f)) | .key] as $rs
        | reduce (if ($rs | length) == 1 then $rs[0] else $took[$t | tostring] // $rs[] end) as $r (.;
            .[$k] += [[$r, ($log.order[$r] | index($f))]]))) as $hs
    # $pre[k][r]: how many of the first files of log r have their `== ` lines, in order, before line k; $suf[k][r]:
    # how many of its last files have theirs from line k on. $whole: every file of every log has its line, in order.
    | [foreach $hs[] as $h ({p: ($ns | map(0))}; .b = .p | .p = reduce $h[] as [$r, $i] (.p; if $i == .[$r] then .[$r] += 1 else . end); .b)] as $pre
    | ([foreach ($hs | reverse | .[]) as $h ($ns | map(0); reduce ($h | reverse | .[]) as [$r, $i] (.; if $i == $ns[$r] - 1 - .[$r] then .[$r] += 1 else . end); .)] | reverse) as $suf
    | (reduce $hs[][] as [$r, $i] ($ns | map(0); if $i == .[$r] then .[$r] += 1 else . end) == $ns) as $whole
    # seen: the last line so far with a `== ` line of each file of each log.
    | reduce range(0; $ls | length) as $k ({cur: "", at: ($ns | map(-1)), seen: {}, oks: {}, files: ([$only // $log.failed[]] | map({file: ., cases: []}))};
      $ls[$k] as $l
      # A passed case: `ok <case>`, `✔ <name> (<n>ms)` of node or `ok <n> - <name>` of TAP (not a skipped or to-do
      # one), named as its failure lines name it. Node also prints a file it ran as one of these lines, or as a failure
      # line when it failed: a name that is the file itself, or a path of it, is no case, passed or failed (issue 1639).
      | (if .cur == "" then $only else .cur end) as $of
      | ([$l | capture("^ok (?<c>\\S+)$"), capture("^\\s*✔ (?<c>.+) \\([0-9.]+ms\\)$"),
          (select(test("^\\s*ok .*# *(TODO|SKIP)"; "i") | not) | capture("^\\s*ok [0-9]+ (- )?(?<c>.*\\S)") | tapname)][0].c
         | . as $n | if $n and $of and ($n == $of or ($n | endswith("/" + $of)) or ($of | endswith("/" + $n))) then null else $n end) as $o
      | (if $o and $of then .oks[$of] += [$o] else . end)
      | ($l | failcase) as $c
      | (if $c and ($l | test("^\\s*not ok .*# *(TODO|SKIP)"; "i") | not) then
          (if $whole | not then [.cur | if . == "" then $one else . end | select(. == "" or IN($log.failed[]))]
           elif all($pre[$k][]; . == 0) then [$only // $one] # $one: a line no `== ` line gives a file is of the one failed file, when there is one; after recs, a case a file has is not also one with no file (issue 1639)
           else .seen as $seen | [range(0; $ns | length) as $r | range(([$ns[$r] - $suf[$k][$r] - 1, 0] | max); $pre[$k][$r]) as $j
             | $seen["\($r) \($j)"] as $t | select(all(range(0; $ns | length); . == $r or $pre[$t + 1][.] + $suf[$k][.] >= $ns[.]))
             | $log.order[$r][$j] | select(IN($log.failed[]))] end) as $own
          | reduce $own[] as $file (.; (if any(.files[]; .file == $file) then . else .files += [{file: $file, cases: []}] end)
            | .files |= map(if .file == $file and (any(.cases[]; .name == $c) | not) and ($c == $file or ($c | endswith("/" + $file)) or ($file | endswith("/" + $c)) | not) then .cases += [{name: $c, line: ($l | sub("^\\s+"; "") | cut)}] else . end))
        else . end)
      | reduce $hs[$k][] as [$r, $i] (.; .seen["\($r) \($i)"] = $k | if $i > .at[$r] then .cur = $log.order[$r][$i] | .at[$r] = $i else . end))
    | recs($rec; $log) | .files |= ([.[] | select(.file != "") | .cases[].name] as $fc | map(if .file == "" then .cases |= map(select(IN(.name; $fc[]) | not)) else . end) | map(select(.file != "" or .cases != []))) | (($log.open | flatten) - $log.notrun - $log.host) as $open | ([range(0; $log.open | length) as $r | $log.open[$r][] | select(. as $f | any(range(0; $log.ended | length); . != $r and IN($log.ended[.][]; $f)))] - $log.limit) as $shut | ($log.files - $log.failed - ($open - $shut) - $log.notrun - $log.host) as $passed | .files as $fs
    | {of: ($log.n // ($log.files | length | if . == 0 then null else . end)),
       files: (.files | map((.cases |= map(. + if $at[.name] then {at: $at[.name]} else {} end)) + if .cases == [] and $fat[.file] then {at: $fat[.file]} else {} end)),
       timeout: (if $rc == "124" then ($only // ($open | last)) as $tf | {sec: (if $tf and ($log.limit | index($tf)) then $own[$tf] else null end // ($sec | tonumber? // $sec)), file: $tf} else null end),
       passed: $passed,
       okcases: [.oks | to_entries[] | .key as $f | select(IN($passed[]; $f) | not)
         | {file: $f, cases: ((.value | unique) - [$fs[] | select(.file == $f) | .cases[].name])} | select(.cases != [])],
       passcases: [.oks | to_entries[] | select(IN($passed[]; .key)) | {file: .key, cases: (.value | unique)}]} + (if $rc == "124" then {stopped: (if $only then [$only] else $open | unique end)} else {} end) + ($log.limit - $log.notrun - $log.host | if . == [] then {} else {ownLimit: .} end) + (if $log.notrun == [] then {} else {notRun: $log.notrun} end) + (if $log.host == [] then {} else {host: $log.host} end)') || return 1
  [[ $out == *'"at":['* ]] || { printf '%s\n' "$out"; return 0; }
  atsource "$wd" <<<"$out"
}
# What testfails() reads of the records of the cases ($rec: {file, case, result, sec} lines in results/ of the log
# folder, tests/lib.sh run_case): a file the logs name that has any has the cases they say failed and passed, not those
# the output's lines gave it, each failure with its line of the output when it has one. With no RECJQ (no globals of
# this file) the records are not read.
RECJQ='def recs($rec; $log): [$rec[] | objects | select((.case | type) == "string" and IN(.file; $log.files[]) and IN(.result; "ok", "fail"))] as $rd | reduce ([$rd[].file] | unique)[] as $f (.; .oks[$f] = [$rd[] | select(.file == $f and .result == "ok") | .case] | [.files[].cases[]] as $tc | .files |= map(if .file == $f then .cases = ([$rd[] | select(.file == $f and .result == "fail") | .case] | unique | map(. as $c | {name: $c, line: ([$tc[] | select(.name == $c) | .line][0] // "FAIL [\($c)]: its record says it failed")})) else . end));'

# A test output that is no run's (the loop's own words for why nothing ran): the logs and times of the run before are not its.
norun() { rm -rf "$1.testlog" "$1.first" "$1.testlist" "$1.noresult" "$1.uncovered"; TEST_WAIT=''; TEST_RUN=''; TEST_FREE=''; printf '%s\n' "$2" > "$1.test"; } # <worktree> <text>
# A run's output and the logs it wrote, copied as one: what failed is read from both (testfails()); its first run's
# record when it went again (tests()); and its coverage (<worktree>.uncovered, testrec()), which a later run writes over.
keeprun() { # <worktree> <output file to> <log folder to> <first run's record to> <coverage to> [<no-result reason to>]
  rm -rf "$3" "$4" "$5" ${6:+"$6"}; cp -f "$1.test" "$2" && { [ ! -d "$1.testlog" ] || cp -R "$1.testlog" "$3"; } && { [ ! -e "$1.first" ] || cp -f "$1.first" "$4"; } && { [ ! -e "$1.uncovered" ] || cp -f "$1.uncovered" "$5"; } \
    && { [ -z "${6:-}" ] || [ ! -e "$1.noresult" ] || cp -f "$1.noresult" "$6"; }
}

# The fields of a test record of a run (README.md, The test step): sec (all the step took), usage (none), tests
# (testcounts()), wait and run (tests(): the seconds it waited for its slot and the seconds its command ran, null when
# not known), slotsFree, selected ({files, filesOf, cases, casesOf, kept}: what the runner selected and out of how many, from
# its log lines `TESTRUN files=<n> of=<m>` and `TESTRUN cases=<n> of=<m>`, and the cases that passed in the last run
# and were kept as passed, not run (`TESTRUN kept=<n>`), summed over its logs; files is testcounts()'s
# when no log names it; a count nothing gives is null) and ended: "passed", "failed" (a case failed), "killed" (by a
# signal: an exit over 128), "timed out" (124) or "nothing selected" (a run that passed and selected no file); and
# why, why each file ran, {file: [reasons]}, from its log lines `TESTRUN why<TAB><file><TAB><reason>`, when it gives
# any (a first run and a run again alike); wholeSuite (true), when a log says the runner ran every case file of the
# engine (`TESTRUN whole-suite`); ran, the files the logs name as begun (`== <file>`), sorted: the files it ran (why
# also names files it kept off, such as those the test cache skipped: testlist.sh cacheoff()); ranCases, the cases it selected of each file it ran only part of, {file: [cases]},
# from its log lines `TESTRUN case<TAB><file><TAB><case>` (mainred.sh brokeby()); refused, "refused full run: <why>", when
# tests() refused the whole selection (TEST_REFUSED); and list, the list of tests the command was given (listcmd():
# {mode: "changed", files} or {mode: "whole", why}), when the pack sets test.list; and coverage, the changed lines no
# test reached ({uncovered: [{file, lines}], count, checked} or {unknown: why}: testlist.sh uncovered()), when the pack sets
# test.coverage.
testrec() { # <worktree> <exit> <seconds>
  local k l logs=()
  k=$(testcounts "$1.test"); mapfile -t logs < <(testlogs "$1")
  for l in "${logs[@]}"; do printf '\n'; cat "$l" 2>/dev/null; done | jq -cRn --argjson rc "$2" --argjson s "$3" --argjson k "$k" \
    --arg w "${TEST_WAIT:-}" --arg r "${TEST_RUN:-}" --arg f "${TEST_FREE:-}" --arg z "${TEST_REFUSED:-}" '
    [inputs] as $in
    | [$in[] | capture("^TESTRUN why\t(?<f>[^\t]+)\t(?<w>.+)$")] as $why
    | [$in[] | capture("^TESTRUN case\t(?<f>[^\t]+)\t(?<c>[^\t]+)$")] as $cs
    | [$in[] | capture("^TESTRUN (?<k>files|cases|kept)=(?<n>[0-9]+)( of=(?<of>[0-9]+))?") | {k, n: (.n | tonumber), of: (.of | tonumber? // null)}] as $l
    | def sum($k): [$l[] | select(.k == $k) | .n] | if . == [] then null else add end;
      def of($k): [$l[] | select(.k == $k) | .of] | if . == [] or any(. == null) then null else add end;
    {files: (sum("files") // $k.files), filesOf: of("files"), cases: sum("cases"), casesOf: of("cases"), kept: sum("kept")} as $sel
    | {sec: $s, usage: {input: 0, write: 0, write1h: 0, read: 0, output: 0}, tests: $k,
       wait: ($w | tonumber? // null), run: ($r | tonumber? // null), slotsFree: ($f | tonumber? // null), selected: $sel,
       ended: (if $rc == 0 then (if $sel.files == 0 then "nothing selected" else "passed" end) elif $rc == 124 then "timed out"
         elif $rc > 128 then "killed" else "failed" end)}
    + if $why == [] then {} else {why: ($why | group_by(.f) | map({key: .[0].f, value: (map(.w) | unique)}) | from_entries)} end
    + if any($in[]; . == "TESTRUN whole-suite") then {wholeSuite: true} else {} end
    + ([$in[] | capture("^== (?<f>.*\\S.*)$") | .f] | unique | if . == [] then {} else {ran: .} end)
    + if $cs == [] then {} else {ranCases: ($cs | group_by(.f) | map({key: .[0].f, value: (map(.c) | unique)}) | from_entries)} end
    + if $z == "" then {} else {refused: $z} end
    + if $tl[0] | type == "object" then {list: $tl[0]} else {} end
    + if $cv[0] | type == "object" then {coverage: $cv[0]} else {} end' --slurpfile tl <(cat "$1.testlist" 2>/dev/null) --slurpfile cv <(cat "$1.uncovered" 2>/dev/null)
}
# The card's changed tests, run by the loop itself, never by a session: the pack's test.command in the worktree, under
# the timeout, with CONVEYOR_TEST_LOG naming an empty folder for its progress logs (README.md, the live record).
# Output in <worktree>.test; the exit is the command's (124 is the timeout).
# The run holds one of the machine's test slots (lib/slots.sh) from before it starts until the command and all it
# started have ended (but for a while that a runner of the command, waiting for a whole-suite turn, gives it up to a
# run that asked first and then takes the same slot back on the same descriptor: slot_whole): the command inherits the descriptor that holds the slot (CONVEYOR_TEST_SLOT names it, the run's
# home slot, for its runners' workers; CONVEYOR_TEST_SLOTS is the library a runner sources to take them) and is pinned
# to the slot's core, so whatever it starts without a slot of its own runs on that core alone. With no slot free the
# card waits, its live record saying so and brought up to date as it waits (so `health` does not call it stuck); the
# timeout's clock starts only once it has the slot, and does not run while a runner of the command waits for a
# whole-suite turn (testclock). A loop that itself runs inside a test run (a test of the engine)
# takes none, once it has shown that it holds that run's slot (slot_pool): its commands run on that one.
# The whole test on main (maintest()) runs the same way: its command is the pack's test.main; so does the full test
# suite (fulltest()), the pack's test.full.
# Sets TEST_WAIT (the seconds it waited for its slot), TEST_RUN (the seconds the command ran, its run again included)
# and TEST_FREE (the slots of the pool free beside its own as the command started), each empty when the command did
# not start (testrec()).
# A card's run (test.command) that ends with cases that did not pass (failed, or never finished: killed or timed out)
# runs once more, still holding the slot, for those cases alone (the owner, 2026-11-13: a failure goes to a fix
# session only when it fails again). What passed is not run again: <worktree>.rerun, which CONVEYOR_TEST_RERUN names
# to the command (README.md), says it (testlist.sh rerunlist()). The run after a fix session that left the staged change as it was,
# byte for byte (a whitespace edit is a change, and cardpatch() sees it), runs only what had not passed. The run
# after a session that changed it on the same HEAD (a fix: the owner, 2026-11-13, only failed tests run again and
# passes are kept) runs what had not passed and the tests of the files the session changed: the list names each file
# whose content differs between the tree last tested and the tree now (rerunsince()), and the command runs their
# tests too; every other case that passed is kept as passed. A change on another HEAD (moved onto a newer main: the
# owner, 2026-11-14) keeps its passes too, and runs what had not passed, the tests of the files of the card's change
# that differ between the two trees, and those of the files main changed between the two HEADs that the card's own
# selection holds too (rerunsince()); it runs the whole selection when the merge is in doubt: a session that brought
# the change onto main edited it outside the conflicts (settle() writes <worktree>.whole; rerunsince() sees a rebuild's
# or a port's edit outside the files main changed), or the merge left a file that does not parse (card() writes
# <worktree>.whole). A run that passed keeps what it
# passed in the list too, for such a run and for a retried card (block() keeps it). The first run's exit and failures (testfails())
# are in <worktree>.first, {exit, failures, tail: the end of its output, left out when it gave none}, when the run went again, and the files it timed in <worktree>.times
# (its `TESTRUN sec` lines, testlist.sh slowtests()), and those the runs before it timed in <worktree>.oldtimes when this run keeps
# their passes (a run after a fix session does not run again a file that passed); the output is the last run's. A run that passed
# on re-run adds its cases to the flaky-test record (flakyrun()) as it ends, a batch's run (batch()) too; a run again
# that failed adds the cases that passed in it. A card's run that passed leaves what it passed in <worktree>.passed
# (testlist.sh passlist()). A card's run is told to keep the cases the flaky-test record keeps off card runs as passed (flakyoff()),
# and its run again is told the same. Any run but the full
# test suite and a run alone is told to keep off the files that passed before with the same inputs (testlist.sh cacheoff()), its
# log saying so; each run's files that passed whole go to that cache (testlist.sh cachekeep()).
# With alone, the command is told what to run by <worktree>.rerun as the caller wrote it (fulltest()'s run of one
# failed case alone: every other file listed as passed).
# A full run (the owner, 2026-11-14; README.md, When a full test run is allowed): a card's run whose list cannot be
# kept (rerunsince() fails, RERUN_WHY saying why) runs the whole selection only when it is the card's first (no test
# line of the card before it, and no list kept on the HEAD it runs on: a retried card's list on a main that moved
# since is a first run too) or a merge in doubt (<worktree>.whole, written by card() and settle(), or rerunsince()'s
# 2); the full test suite and the whole test on main (test.full, test.main) keep no list and run whole. Any other is
# refused: it runs what its list did not keep as passed (with no list, nothing was kept, and the whole selection
# runs), and TEST_REFUSED, "refused full run: <why>", goes on its test line as refused (testrec()), which health lists
# for the Foreman's watcher (views.sh).
# The field test.fileCommand runs one test file: the run (filecmd()) gives it each file its list names `fail`, each
# in a process of its own. A card never runs the suite command (test.command) to run tests (runfiles() runs it only to list the
# files to start, and it runs none): its own run (no field) and every run
# of a card's files (the fix round's run again, the bug-card check, the run on main, the main-red check, the proofs,
# the mutation check and the test actions: test.fileCommand alone) are per file. With no test.fileCommand set, each
# file runs with Conveyor's own runner (testlist.sh ownrunner(): lib/filerun.sh), and on a check of main (TEST_PACKONLY) with the
# pack's test command (testlist.sh nofilecmd()); when it gives none, the run does not run and fails with <worktree>.stop naming test.fileCommand and why (NORUNNER); a card's run
# linked to no test file runs nothing and passes, as with it set. Only the suite runs (test.full: the full test
# suite, Push landed's and the release's; test.main: the whole test on main) run a suite command.
# A card's run (not alone) gives test.fileCommand the tests its change touches (listcmd()), and <worktree>.testlist
# says which (the live record's and the test line's list); it never makes or adds to the test map (lib/testmap.sh).
# A change linked to no test file runs nothing and passes,
# its output saying so (NONELINKED); and a run that reports more test files than it was given (TEST_GIVEN: watch()
# ends it, <worktree>.wide) does not run again and fails with <worktree>.stop saying why. card() blocks a card whose
# run left <worktree>.stop.
tests() { # <worktree> [the pack's field of the command: test.fileCommand] [alone]
  local cmd at rc r p='' b='' t='' f o l=() wn wb w=$SECONDS t0 ob mf mw off kp ko ka kc cw='' x RUNOFF='' TEST_BEFORE='' LISTNONE='' CAPNOTE='' TEST_CASES='' TEST_GIVEN=${TEST_GIVEN:-} TEST_FAST=''
  TEST_WAIT=''; TEST_RUN=''; TEST_FREE=''; TEST_REFUSED=''; TEST_FILES=''; rm -f "$1.testlist" "$1.stop" "$1.wide" "$1.noresult"
  # The files the run before timed (testlist.sh timed()): kept below when this run keeps its passes and so may not run them.
  mapfile -t l < <(testlogs "$1"); o=$({ cat "$1.oldtimes" "$1.times" "$1.reported"; [ ${#l[@]} = 0 ] || grep -h '^TESTRUN sec' "${l[@]}"; } 2>/dev/null)
  # The commit the last run's list was tested on (ob: its `base`; mf, for main's change, its `from` when it has one, as a batch's
  # list made on the new HEAD has: batchlist()), and a merge in doubt (<worktree>.whole: card(), settle()), before either goes.
  ob=$(sed -n 's/^base\t//p' "$1.rerun" 2>/dev/null); mf=$(sed -n 's/^from\t//p' "$1.rerun" 2>/dev/null | head -n 1); mf=${mf:-$ob}; mw=$(cat "$1.whole" 2>/dev/null); rm -f "$1.whole"
  rm -rf "$1.testlog" "$1.turnwait" "$1.first" "$1.passed" "$1.oldtimes" "$1.oldfiles" "$1.times" "$1.reported" "$1.uncovered" "$1.covfirst"; { mkdir "$1.testlog" && checkskept "$1" && packget "${2:-test.fileCommand}" cmd && slot_pool; } 2>"$1.test" || return 1
  if [ "${2:-}" = test.fileCommand ]; then
    [ -n "$cmd" ] || cmd=$(mapfile -t l < <(awk -F'\t' '$1 == "fail" && $2 != "" && !s[$2]++ { print $2 }' "$1.rerun" 2>/dev/null)
      nofilecmd "$1" "${l[@]}") || { narrowstop "$cmd" > "$1.stop"; cat "$1.stop" > "$1.test"; return 1; }
    cmd=$(filecmd "$cmd")
  fi
  # A card's run and the full test suite (fulltest(), release-prep's relsuite()) ask for the runner's report: setup
  # gives test.full the card's command. A card's run gives each file's run the report's args (listcmd()), each file
  # its own report (reportask() files).
  REPORT_ENV=(); REPORT_ARGS=''; if [ -z "${2:-}" ]; then reportask "$1" files; elif [ "$2" = test.full ]; then reportask "$1"; [ -z "$REPORT_ARGS" ] || cmd="$cmd $REPORT_ARGS"; fi
  if [ -z "${2:-}" ] && [ "${3:-}" != alone ]; then
    MAINFROM=$mf listcmd "$1" "$REPORT_ARGS" 2>"$1.test" || { [ ! -s "$1.stop" ] || cat "$1.stop" >> "$1.test"; return 1; }
    cmd=$LISTCMD
    # No test file linked to the change: nothing runs, and its output says so.
    [ -z "$LISTNONE" ] || { printf 'conveyor: %s\n' "$NONELINKED" > "$1.test"; runnernote "$RUNOFF" >> "$1.test"; TEST_WAIT=0; TEST_RUN=0; return 0; }
    # The file of a case that failed in the last run runs again, though the card's list holds it no more (testlist.sh failsleft()).
    failsleft "$1"
  fi
  if [ -z "${2:-}" ]; then
    p=$(git -C "$1" diff --cached --binary --no-renames HEAD 2>/dev/null | git hash-object --stdin)
    b=$(git -C "$1" rev-parse -q --verify HEAD 2>/dev/null); for x in 1 2 3; do t=$(git -C "$1" write-tree 2>/dev/null) && break; [ $x = 3 ] || sleep 0.5; done # sleep: a tree that could not be read (write-tree failed under load, #788) is read again, twice at most; with none no list is kept (rerunlist())
  fi
  if [ "${3:-}" != alone ]; then
    rerunsince "$1" "$p" "$b" "$t"; r=$?
    # A card's run that would run its whole selection, and is none of a first run, a merge in doubt or the full test
    # suite (the owner, 2026-11-14): refused. It runs what the list did not keep as passed, and says why on its line.
    # With no HEAD or tree now, it keeps no list (testlist.sh rerunlist()): the whole selection runs.
    if [ $r = 1 ] && [ -n "$p" ] && [ -z "$mw" ] && { { [ -n "$ob" ] && [ "$ob" = "$b" ]; } || testedbefore "$1"; }; then
      TEST_REFUSED="refused full run: $RERUN_WHY"
      if [ -s "$1.rerun" ] && [ -n "$b" ] && [ -n "$t" ] && { printf 'change\t%s\nbase\t%s\ntree\t%s\n' "$p" "$b" "$t"; grep -E $'^(pass|ok|fail)\t' "$1.rerun"; } > "$1.rerun.new" \
        && mv -f "$1.rerun.new" "$1.rerun"; then r=0; fi
    fi
    # Those times are in <worktree>.oldtimes, apart from this run's own (<worktree>.times).
    if [ $r = 0 ]; then [ -z "$o" ] || printf '%s\n' "$o" > "$1.oldtimes"; else rm -f "$1.rerun"; fi
    # A card's run keeps the flaky cases off (flakyoff()): the full suite and the whole test on main run them.
    [ -n "${2:-}" ] || flakyoff "$1"
    # It keeps off the files that passed before with the same inputs (testlist.sh cacheoff()), its log saying so (cw): not the full
    # test suite, which runs whole.
    [ "${2:-}" = test.full ] || { cw=$(cacheoff "$1"); [ -z "$cw" ] || printf '%s\n' "$cw" > "$1.testlog/cache"; }
  fi
  # A card's list holds no suite runner, wherever it got it (#382): testlist.sh runnersoff() takes each off its list, and the
  # run's output names it (RUNOFF, with those listcmd() took off). The release's runs (test.full, test.main) keep theirs.
  # A run alone left with no `fail` line has no file to run: it runs nothing, and fails.
  if [ "${2:-}" != test.full ] && [ "${2:-}" != test.main ]; then
    x=$(runnersoff "$1.rerun"); RUNOFF=$(printf '%s\n' "$RUNOFF" "$x" | grep . | sort -u)
    if [ -n "$x" ] && [ "${3:-}" = alone ] && ! grep -q $'^fail\t' "$1.rerun"; then
      runnernote "$RUNOFF" > "$1.test"; return 1
    fi
  fi
  # Its ask (slot_ask), held until it ends, so no mutation check of any project runs beside it; a mutation check's own
  # run (MUT_RUN, lib/mutate.sh mutone()) makes none.
  [ -n "${MUT_RUN:-}" ] || slot_ask || :
  if [ -z "$SLOT_HOME" ]; then
    at=$(date -u +%FT%TZ)
    until slot_try || slot_wait; do
      jq -cn --arg at "$at" --arg a "$(slot_waiting)" '{step: "test", at: $at, last: (now | todate), turns: 0, files: {run: 0, of: null}, tests: null,
        action: $a}' > "$1.live.tmp" 2>/dev/null && mv -f "$1.live.tmp" "$1.live"
    done
  fi
  TEST_WAIT=$((SECONDS - w)); TEST_FREE=$((SLOT_N - $(slot_used))); w=$SECONDS; t0=$(date +%s)
  # The `off` lines (flakyoff()), which testlist.sh rerunlist() does not keep: given to the run again too, so it runs no
  # case or file kept off that its list would otherwise select (a case of the runner that did not finish).
  off=$(grep $'^off\t' "$1.rerun" 2>/dev/null)
  # The files its list keeps whole as passed (`pass` lines): not run. A file it runs only some cases of is run.
  kp=$(awk -F'\t' '$1 == "pass" {print $2}' "$1.rerun" 2>/dev/null)
  runfiles "$1"
  testonce "$1" "$cmd"; rc=$?; cachekeep "$1"; runnernote "$RUNOFF" >> "$1.test"
  if [ ! -s "$1.wide" ] && [ $rc != 0 ] && [ -n "$p" ] && f=$(testfails "$1.test" "$rc") && f=$(nopass "$1" "$f") && rerunlist "$1" "$p" "$f" "$b" "$t" \
    && { [ -z "$off" ] || printf '%s\n' "$off" >> "$1.rerun"; } \
    && { [ -z "$TEST_FAST" ] || jq -r '.files[].file | "fail\t\(.)"' <<<"$f" >> "$1.rerun"; }; then
    # A run that stopped at its first failure (TEST_FAST: listcmd()) ran none of a failed file's cases after its
    # failed one: the run again runs each failed file (a `fail` line naming no case), all its cases but those an `ok`
    # line names as passed when the command can leave out one case (the whole file when it cannot), so a pass of the
    # failed case on re-run is never taken for the cases after it, which never ran.
    # Its output's end (the last 60 lines, as a failed test line's tail, card()) goes with them: the run again
    # overwrites <worktree>.test, and a pass on re-run is the only record of the flaky failure (FAILURE, testfiles.sh).
    jq -c --argjson rc "$rc" --rawfile t <(tail -n 60 "$1.test" 2>/dev/null | tr -d '\000') \
      '{exit: $rc, failures: del(.passed, .okcases, .passcases, .host)} + ($t | sub("\n+$"; "") | if . == "" then {} else {tail: .} end)' <<<"$f" > "$1.first"
    # The files the first run timed, which the run again does not run, after those of the runs before it (testlist.sh slowtests()), and its `TESTRUN case` lines (.oldfiles, below).
    mapfile -t l < <(testlogs "$1"); { cat "$1.reported"; [ ${#l[@]} = 0 ] || grep -h -e '^TESTRUN sec' -e $'^TESTRUN case\t' "${l[@]}"; } >> "$1.times" 2>/dev/null
    # The first run's coverage report, which the run again may write over: kept (testlist.sh covkeep()) for uncovered(), in the same file.
    covkeep "$1"
    rm -rf "$1.testlog"; if mkdir "$1.testlog" 2>"$1.test"; then
      # The first run's seconds go in the run again's live record (watch(): before), so the views still count them (#433).
      checkskept "$1"; [ -z "$cw" ] || printf '%s\n' "$cw" > "$1.testlog/cache"
      # shellcheck disable=SC2034 # TEST_BEFORE is read by watch() in lib/session.sh
      TEST_BEFORE=$((SECONDS - w)); testonce "$1" "$cmd"; rc=$?; cachekeep "$1"; runnernote "$RUNOFF" >> "$1.test"
    else rc=1; fi
    [ $rc = 0 ] || { f=$(testfails "$1.test" "$rc") && f=$(nopass "$1" "$f") && rerunlist "$1" "$p" "$f" "$b" "$t"; } || rm -f "$1.rerun"
  fi
  TEST_RUN=$((SECONDS - w))
  # A card's run that passed with a file whose filter ran no case (nocases()) gave no result: its exit is 1 and
  # <worktree>.noresult says why (voidrun()). Its list stays, and nothing of it is a pass on re-run (flakyrun(): f).
  # In a run that failed, such a file is no pass either: nopass() above.
  [ $rc != 0 ] || [ -n "${2:-}" ] || ! x=$(nocases "$1" | awk -F'\t' 'NR == 1 { c = $2; for (i = 3; i <= NF; i++) c = c ", " $i; print $1 ": its filter (" c ") ran no case, and the run passed" }' | grep .) || { printf '%s\n' "$x" > "$1.noresult"; printf 'conveyor: no result: %s\n' "$x" >> "$1.test"; rc=1; f=''; }
  # A card's run: the changed lines its coverage report says no test reached (testlist.sh uncovered()), the first run's report
  # (testlist.sh covkeep()) and a run again's together.
  [ -n "${2:-}" ] || uncovered "$1" "$t0"; rm -rf "$1.covfirst"
  # Of those, the files the runs before timed (<worktree>.oldtimes) and this run did not, nor ran some cases of (testlist.sh partran(): its test line names them partial): carried (testlist.sh carriedrec()).
  # The maps and the list go to jq as files: as arguments, a big project's pass Linux's 128 KiB limit of one.
  [ -z "$kp" ] || [ ! -s "$1.oldtimes" ] || { ko=$(timed "$1" own) && ka=$(timed "$1") && kc=$(partran "$1") \
    && jq -cn --slurpfile o <(printf '%s' "$ko") --slurpfile a <(printf '%s' "$ka") --slurpfile c <(printf '%s' "$kc") --rawfile k <(printf '%s' "$kp") '$o[0] as $o | $a[0] as $a | $c[0] as $c | [$k | split("\n")[] | select($a[.] != null and $o[.] == null and (IN($c[]) | not))] | unique' > "$1.oldfiles"; } \
    || rm -f "$1.oldfiles"
  # Given TEST_GIVEN files, a run reported more (watch() ended it, <worktree>.wide): it does not run again, and
  # <worktree>.stop says why. It names the file test.fileCommand was running then (the file on the second line of <worktree>.wide, wideeach() in lib/testlist.sh, else its last `== <file>` log line): that file ran the rest. A count not over TEST_GIVEN is of one invocation that reported more files than had begun.
  # With a third line `begun <n>` (wideeach()), the second line is not the file that ran the rest: it is the file the
  # runners' logs named <wn> times though the run began it n times, so another file's run ran it too.
  if [ -s "$1.wide" ]; then
    wb=''; { read -r wn; read -r f; read -r wb; } < "$1.wide"; [ -n "$f" ] || f=$(sed -n 's/^== //p' "$1.testlog/files" 2>/dev/null | tail -n 1)
    if [[ $wb == 'begun '* ]]; then narrowstop "the test command, given $TEST_GIVEN test file(s), reported $f $wn times, though its run began it ${wb#begun } time(s): another file, run alone by test.fileCommand, ran it too, so its run was stopped" > "$1.stop"
    elif [ -n "$f" ] && [ "$wn" -le "$TEST_GIVEN" ] 2>/dev/null; then narrowstop "the test command, given $TEST_GIVEN test file(s), reported $wn test files before it had begun them all: $f, run alone by test.fileCommand, ran test files it is not given, so its run was stopped" > "$1.stop"
    elif [ -n "$f" ]; then narrowstop "the test command, given $TEST_GIVEN test file(s), reported $wn test files: $f, run alone by test.fileCommand, ran test files it is not given, so its run was stopped" > "$1.stop"
    else narrowstop "the test command, given $TEST_GIVEN test file(s), reported $wn test files: it runs test files it is not given, so its run was stopped" > "$1.stop"; fi
    cat "$1.stop" >> "$1.test"; [ -n "$SLOT_HOME" ] || slot_free; slot_unask; return 1
  fi
  if [ $rc = 0 ] && [ -n "$p" ]; then
    passlist "$1" || rm -f "$1.passed"
    { f=$(testfails "$1.test" 0) && rerunlist "$1" "$p" "$f" "$b" "$t"; } || rm -f "$1.rerun"
  elif [ $rc = 0 ]; then rm -f "$1.rerun"; fi
  [ -n "$SLOT_HOME" ] || slot_free
  slot_unask
  # A pass on re-run goes to the flaky-test record now, before a later run (a batch's) clears <worktree>.first; so do
  # the cases of a run again that failed which passed in it (f: its failures).
  if [ -e "$1.first" ]; then if [ $rc = 0 ]; then flakyrun "$1"; else flakyrun "$1" "${f:-}"; fi; fi
  # A change with no test file of its own ran linked test files (listcmd(), testcap()): its output says how many, and
  # that the run before the push runs them all. One that ran only the changed cases of its own says how many (OWNCASES).
  [ -z "$CAPNOTE" ] || printf 'conveyor: %s\n' "$CAPNOTE" >> "$1.test"
  return $rc
}
# The rule Stop a card's tests at the first failure (rules.failfast of the control record the card started on, CARDCTL,
# else the one in force): on unless it is false. Only a card's run reads it (listcmd()): a release's runs every case.
failfast() { [ "$(jq -r '.rules.failfast' <<<"${CARDCTL:-$(ctl 2>/dev/null)}" 2>/dev/null)" != false ]; }
# The command of a card's run (tests()) given the list of the tests its change touches (README.md, The list of tests a
# card's run is given), in LISTCMD: test.fileCommand, which runs each file of the list alone (filecmd() files, the
# files in TEST_FILES). A card never runs the whole suite: the list is the test files its own change adds or changes
# (by: "own"), of each only the cases its change adds or changes where testlist.sh owncases() can name them (TEST_CASES; the
# list's cases, [{file, case}], and its why, OWNCASES, say so); with none, testsel()'s narrow one, the test files the
# test map and the links give the changed files, up to CARDLINKED of them (testcap(); the output says so, LINKED, and
# the list, {mode: "changed", files, by, left, why}, says how many were left out); notTests, [{file, why}], names each
# test runner the change touches, RUNNERFIX, which is on no list: #350). <worktree>.testlist says which: {mode:
# "changed", files: <count>, by: "own", "map" or "name", age: the commits the made test map is behind (only with
# one)}. A list of none runs nothing (LISTNONE set; the list, {mode: "changed", files: 0, by, why}, says so). With no
# test.fileCommand set, Conveyor's own runner runs each file (testlist.sh ownrunner()); when it has none for one of them, nothing
# runs, <worktree>.stop says why (NORUNNER) and it fails. TEST_GIVEN is how many files it got (watch() stops a run that
# reports more: tests()). <report args> (reportask() files) go after the command, before each file's path. TEST_FAST is
# `fast` when the command stops at its first failure (failfast()), else empty, as for a main-red fix card (in $MAINRED): cardland.sh redelse() needs a verdict of each case it fails.
listcmd() { # <worktree> [report args]
  local s fs=() by fc rn='' f c nf=0 nw=0 lk=() READADD=() READWHOLE='' READLINKS=0 SELN=0
  LISTCMD=''; TEST_FILES=''; TEST_CASES=''; LISTNONE=''
  # The list that could not be made says why (the error of the command that failed); test.fileCommand is named only while it is not set.
  # A suite runner (SUITERUNNERS) is on no list (#382): testpaths() leaves each off the card's own files, and
  # testlist.sh runnersout() off those the map and the links give; RUNOFF names those, which tests() names in its output.
  names > /dev/null 2>&1 || :
  # The test files the card's own change adds or changes (the pack's test patterns: testpaths(), so no runner and no
  # document; no shared helper, which testsel() does not run as a test either) are the card's tests (#384); with
  # none, the CARDLINKED test files the test map and the links give the change (testsel() narrow), those that failed
  # most recently first, after those the pack's changed-tests command selects (selfirst(), testcap()), and its output says so (LINKED). The run before the push runs the files the map
  # links to every landing (pushtests(), lib/pushrun.sh).
  mapfile -t fs < <(git -C "$1" -c core.quotePath=false diff --cached --name-only --no-renames --diff-filter=AM HEAD -- 2>/dev/null | testpaths \
    | jq -Rr "$SHAREDJQ"'select(. != "" and (shared | not))')
  CAPLEFT=0; CAPNOTE=''
  if [ ${#fs[@]} != 0 ]; then by='{"by":"own","age":null}'
    # Of each, only the cases the change adds or changes run (testlist.sh owncases(), #414): TEST_CASES, `<file><TAB><case>`
    # lines, which testonce() gives the command (CONVEYOR_TEST_CASES), and its output says how many (OWNCASES); a
    # file whose cases cannot be named so runs whole.
    for f in "${fs[@]}"; do
      if c=$(owncases "$1" "$f"); then nf=$((nf + 1)); TEST_CASES+=$(awk -v f="$f" '{print f "\t" $0}' <<<"$c")$'\n'
      else nw=$((nw + 1)); fi
    done
    # Each of the card's test files, whole or only its changed cases, brings the test files .conveyor/test-links.json
    # links to it, those still there, each run whole: they call its helpers (#1000), or a change that needed this file
    # changed broke them before (a Foreman title case and the start's size cases). One already on the list with only its
    # changed cases runs whole too, as a case it did not change can call them; a link of a file to itself is no reason.
    mapfile -t lk < <(jq -r '. as $m | $ARGS.positional[] as $k | $m[$k] | arrays[] | strings | select(. != $k)' \
      --args "${fs[@]}" < "$1/.conveyor/test-links.json" 2>/dev/null | sort -u)
    for f in "${lk[@]}"; do
      [ -n "$f" ] && [ -f "$1/$f" ] || continue
      if printf '%s\n' "${fs[@]}" | grep -qxF -- "$f"; then
        TEST_CASES=$(awk -F'\t' -v f="$f" '$1 != f' <<<"$TEST_CASES"); TEST_CASES=${TEST_CASES:+$TEST_CASES$'\n'}
      else fs+=("$f"); fi
    done
    readersin "$1" # each file whose last pass read a file the change touches, whole (testlist.sh, #1619), before the note's counts
    if [ ${#lk[@]} != 0 ] || [ ${#READADD[@]} != 0 ] || [ -n "$READWHOLE" ]; then
      runnersout; nf=$(cut -f1 <<<"$TEST_CASES" | grep . | sort -u | grep -c .) || :; nw=$((${#fs[@]} - nf))
    fi
    if [ $nf != 0 ]; then
      c=$(grep -c . <<<"$TEST_CASES"); CAPNOTE=${OWNCASES/'<n>'/$c}; CAPNOTE=${CAPNOTE/'<s>'/$([ "$c" = 1 ] || echo s)}
      CAPNOTE=${CAPNOTE/'<m>'/$nf}; CAPNOTE=${CAPNOTE/'<s>'/$([ $nf = 1 ] || echo s)}
      [ $nw = 0 ] || { c=${OWNWHOLE/'<w>'/$nw}; CAPNOTE+=${c/'<s>'/$([ $nw = 1 ] || echo s)}; }
    fi
  else
    s=$(testsel "$1" narrow) || { packget test.fileCommand fc 2>/dev/null || fc=''
      narrowstop "the list of the card's tests could not be made: $s" ${fc:+bare} > "$1.stop"; return 1; }
    by=${s%%$'\n'*}; [[ $s != *$'\n'* ]] || mapfile -t fs <<<"${s#*$'\n'}"; runnersout
    lk=("${fs[@]}"); selfirst "$1" "$CARDLINKED"; CAPMAX=$CARDLINKED CAPFIRST=$SELN testcap "${fs[@]}"; fs=("${CAPFILES[@]}")
    # Past the cap, each file whose last pass read a file the change touches (testlist.sh readersin(), #1619): a linked one (READLINKS) is not left out: bug, the list said 5 of 10 were left out with 6 on it.
    readersin "$1"; CAPLEFT=$((CAPLEFT - READLINKS))
    # The note's <n> counts only the linked files the cap chose, most recent failure first (those the changed-tests command selects, SELN, before them: SELLINKED); the linked files past it that ran for the last passes (READLINKS) get their own sentence (READLINKED): bug, the note said all of them ran in order of most recent failure.
    [ ${#lk[@]} = 0 ] || [ ${#fs[@]} = 0 ] || { CAPNOTE=${LINKED//'<n>'/$((${#lk[@]} - CAPLEFT - READLINKS))}; CAPNOTE=${CAPNOTE//'<all>'/${#lk[@]}}
      [ "$SELN" = 0 ] || CAPNOTE+=${SELLINKED//'<k>'/$((SELN < CARDLINKED ? SELN : CARDLINKED))}; [ "$READLINKS" = 0 ] || CAPNOTE+=${READLINKED//'<k>'/$READLINKS}; }
  fi
  [ -z "${MAINFROM:-}" ] || [ ${#fs[@]} = 0 ] || while IFS= read -r f; do printf '%s\n' "${fs[@]}" | grep -qxF -- "$f" || fs+=("$f"); done < <(mainlinks "$1" "$MAINFROM")
  # A test runner the change touches (TESTRUNNERS) is on no list: notTests says why.
  [ -z "${TESTRUNNERS:-}" ] || rn=$(git -C "$1" -c core.quotePath=false diff --cached --name-only --no-renames HEAD -- 2>/dev/null | grep -xF -f <(printf '%s\n' "$TESTRUNNERS")) || rn=''
  jq -cn --argjson n ${#fs[@]} --argjson b "$by" --arg w "$NONELINKED" --argjson l "$CAPLEFT" --arg c "$CAPNOTE" --arg rn "$rn" --arg rf "$RUNNERFIX" --arg cs "$TEST_CASES" '{mode: "changed", files: $n, by: $b.by} + if $b.age == null then {} else {age: $b.age} end
    + if $n == 0 then {why: $w} elif $l > 0 then {left: $l, why: $c} else {} end
    + ([$cs | split("\n")[] | select(. != "") | split("\t") | {file: .[0], case: .[1]}] | if . == [] then {} else {cases: ., why: $c} end)
    + ([$rn | split("\n")[] | select(. != "") | {file: ., why: $rf}] | if . == [] then {} else {notTests: .} end)' > "$1.testlist" || return 1
  [ ${#fs[@]} != 0 ] || { LISTNONE=1; return 0; }
  packget test.fileCommand fc || return 1
  [ -n "$fc" ] || fc=$(ownrunner "$1" "${fs[@]}") || { narrowstop "$fc" > "$1.stop"; return 1; }
  TEST_FAST=; ! failfast || jq -e --arg c "${1##*/}" 'any(.reds[]?; .card == $c)' "$MAINRED" > /dev/null 2>&1 || TEST_FAST=fast; LISTCMD=$(filecmd "$fc${2:+ $2}" files "$TEST_FAST"); TEST_FILES=$(printf '%s\n' "${fs[@]}"); TEST_GIVEN=${#fs[@]}
}
# Of the test files <file>... linked to a card's change (testsel() narrow: listcmd(); and those of the bug-card check,
# bugproof.sh bugproof()), the ones a card runs, in CAPFILES: all of them up to the
# pack's test.cardFiles (CAPMAX when set: listcmd()'s CARDLINKED); of more, that many: first those that failed most recently in a test step on record (the card
# records' test lines: FAILURE and failedrun, lib/testfiles.sh), newest first, then the rest in the order given (the
# test map's; listcmd()'s, after selfirst()); with CAPFIRST <k>, the first k (those the changed-tests command selects: selfirst()) before the rest, each part so ordered (#1723: bug, a file that failed most recently, of which the command runs no case, took the place of the file of the cases it selected). CAPLEFT is how many it left out, CAPNOTE says so (CAPPED), empty when none: the release's run covers them.
testcap() { # <file>...
  local n=${CAPMAX:-} fl ks=() defs refs
  CAPFILES=("$@"); CAPLEFT=0; CAPNOTE=''
  [ -n "$n" ] || { packget test.cardFiles n 2>/dev/null && [[ $n =~ ^[1-9][0-9]*$ ]] || n=50; }
  [ $# -gt "$n" ] || return 0
  testowners
  fl=$({ olds; recs; } 2>/dev/null | jq -cRn --slurpfile defs <(printf '%s' "$defs") --slurpfile refs <(printf '%s' "$refs") "$OWNERS$FAILURE"'
    [inputs | fromjson? | objects | select(.step == "test") | failedrun | (.time // "") as $t | failedfiles[] | {f: ., t: $t}]
    | group_by(.f) | map(max_by(.t)) | sort_by(.t) | reverse | map(.f)') || fl='[]'
  # A record that cannot be read leaves the given order: the first test.cardFiles files.
  CAPFILES=("${@:1:n}")
  fl=$(printf '%s\n' "$@" | jq -cRn --slurpfile fl <(printf '%s' "$fl") --argjson n "$n" --argjson k "${CAPFIRST:-0}" '$fl[0] as $fl
    | def byfail: . as $all | ($all | map({key: ., value: true}) | from_entries) as $have | [$fl[] | select($have[.])] as $f
      | ($f | map({key: ., value: true}) | from_entries) as $first | $f + [$all[] | select($first[.] | not)]; [inputs] as $all | (($all[:$k] | byfail) + ($all[$k:] | byfail))[:$n]') \
    && mapfile -t ks < <(jq -r '.[]' <<<"$fl") && [ ${#ks[@]} = "$n" ] && CAPFILES=("${ks[@]}")
  CAPLEFT=$(($# - ${#CAPFILES[@]}))
  CAPNOTE=${CAPPED//'<left>'/$CAPLEFT}; CAPNOTE=${CAPNOTE//'<all>'/$#}; CAPNOTE=${CAPNOTE//'<max>'/$n}
}
# The tests a card's change touches (its staged change against HEAD), one path a line after a first line that says how
# they were found, {by: "map" or "name", age} (age: the commits the made test map is behind, lib/testmap.sh mapread(),
# with one; else null): a document (.md, .txt, .rst) is never a test file here, whatever folder holds it (#367); of
# each changed file, a document selects none; a test runner (TESTRUNNERS,
# no test file: #350) selects its own tests, never itself and never the whole suite: those the map and its links give
# it, the test files whose text names its file name (those that import or run it) and those named after it (as
# below), the whole suite only without narrow and none found; a test file (testpaths())
# selects itself, while it is there, and the test files .conveyor/test-links.json links to it (the project's own
# links, those still there); else a source the test map marks as shared by most tests selects the whole suite, links
# or not; else the tests the map says cover it and those its links name (those still there) are its tests (by map,
# when the map names one); else, a test file that is gone selects none; else a test file that is shared (shared(),
# below) selects the whole suite, as does any other file at the root, shared or with a config extension; else the
# test files whose name holds its name (no extension) as a word, the nearest by folder (those that share the most leading folders with it). A file of which none of these finds a test,
# a change that selects none, or a test map that cannot be read, runs the whole suite: it fails then, and prints why
# in place of the list.
# With narrow (a card's list, listcmd(), and every other caller), nothing selects the whole suite: a file that would
# selects the tests the test map and its links give it (none for a file they give none), a document selects the test
# files the test map and its links name (without narrow, a change of documents alone runs the whole suite), a map that cannot be read
# is read as no map (the links and the names still give tests), a change to a test map of the project's own (the
# pack's test.map path) selects, with its links' tests, the tests of each source the map changes, those it gave the
# source before and those it gives now (as the project's selector of the changed tests runs them, whose count the stop
# on a card's run allows: watch(), lib/session.sh), and a change that selects none prints the first line alone. Given two commits, the change between them stands in for the staged change (a landing's own change, pushtests(), lib/push.sh).
# A helper, setup, fixture or mock file (or one in a folder of such a name), that many tests may read (shared): no
# test of its own (testsel(), listcmd()). A file named as a test (<name>.test.<ext>, <name>_spec.<ext>) is a test by
# its file name, though the name starts with or holds setup or helper (tests/setup.test.sh, setupservice.test.sh).
# base: a path's file name.
SHAREDJQ='def base: split("/")[-1];
  def shared: test("(^|/)(__mocks__|__fixtures__|fixtures?|helpers?|support|testdata|mocks?)/"; "i")
    or (base | test("[._](test|spec)\\.[^.]+$"; "i") | not) and (base | test("^setup"; "i") or (sub("\\.[^.]*$"; "") | ascii_downcase | split("[._-]"; null)
      | any(IN("helper", "helpers", "setup", "fixture", "fixtures", "mock", "mocks", "conftest", "globals"))));'
testsel() { # <worktree> [narrow] [<from commit> <to commit>]
  local out tm d=(--cached HEAD) rn='' rt='{}' f mp='' om=null
  [ -z "${3:-}" ] || d=("$3" "$4")
  tm=$(mapread "$1") || { [ "${2:-}" = narrow ] || { printf '%s\n' "$tm"; return 1; }; tm=null; }
  # With narrow, a change to the project's own test map (the pack's test.map path): the map at the change's base (om),
  # so each source whose tests it changes selects its tests on both sides, as a selector of the changed tests runs them.
  if [ "${2:-}" = narrow ] && packget test.map mp 2>/dev/null && [ -n "$mp" ] && [ "$mp" != off ] \
    && git -C "$1" -c core.quotePath=false diff --name-only --no-renames "${d[@]}" -- 2>/dev/null | grep -qxF -- "$mp"; then
    om=$(mapread "$1" <(git -C "$1" show "${3:-HEAD}:$mp" 2>/dev/null) "${3:-HEAD}") && [ -n "$om" ] || om=null
  else mp=''; fi
  # The test runners the change touches (TESTRUNNERS: no test files, testpaths()), and of each the test files that name it
  # (by its file name: those that import or run it).
  names > /dev/null 2>&1 || :
  [ -z "${TESTRUNNERS:-}" ] || rn=$(git -C "$1" -c core.quotePath=false diff --name-only --no-renames "${d[@]}" -- 2>/dev/null | grep -xF -f <(printf '%s\n' "$TESTRUNNERS")) || rn=''
  if [ -n "$rn" ]; then
    rt=$(while IFS= read -r f; do
           git -C "$1" -c core.quotePath=false grep -lF -e "${f##*/}" 2>/dev/null | testpaths | jq -cRn --arg f "$f" '{($f): [inputs]}'
         done <<<"$rn" | jq -cs 'add // {}') || rt='{}'
  fi
  out=$(jq -rn '$tm[0] as $tm | $om[0] as $om | '"$RX$SHAREDJQ"'def ls: split("\n") | map(select(. != ""));
      def dir: split("/")[:-1];
      def stem: base | sub("\\.[^.]*$"; "");
      # A document (.md, .txt, .rst): no test to run, though a test folder holds it (tests/speed/<page>.md, #367).
      def doc: test("\\.(md|txt|rst)$"; "i");
      def config: test("\\.(json|ya?ml|toml|ini|cfg|conf|lock)$"; "i") or (base | test("(^|[._-])config([._-]|$)"; "i"));
      def common($a; $b): [range([$a, $b] | map(length) | min) | select($a[.] != $b[.])] | first // ([$a, $b] | map(length) | min);
      # The test files whose name holds the file'"'"'s name (no extension) as a word, the nearest by folder.
      def named($all): (stem | rx) as $s | dir as $d
        | [$all[] | select($s != "" and (base | test("(^|[._-])" + $s + "([._-]|[A-Z]|$)"))) | {t: ., n: common(dir; $d)}]
        | if . == [] then [] else (map(.n) | max) as $n | map(select(.n == $n) | .t) end;
      ($rn | ls | INDEX(.)) as $rn
      | ($ch | ls) as $ch | ($ct | ls | INDEX(.)) as $ct | ($all | ls) as $all | ($all | INDEX(.)) as $have
      | ($map[0] // {} | if type == "object" then . else {} end) as $map
      | ($tm.shared // [] | INDEX(.)) as $sh
      | [$ch[] | . as $p
         | ([$map[$p] | arrays[] | strings | select($have[.])]) as $m
         | ([$tm.sources[$p] // [] | .[] | select($have[.])]) as $c
         | if $p == $mp then ($tm.sources // {}) as $n | ($om.sources // {}) as $o
             | {map: ($m + $c + [$o + $n | keys[] | select($o[.] != $n[.]) as $k | ($o[$k] // [])[], ($n[$k] // [])[] | select($have[.])] | unique)}
           elif doc then (if ($nw | not) then [] elif $c != [] then {map: ($m + $c)} else $m end)
           elif $rn[$p] then ($m + $c + [$rt[$p] // [] | .[] | select($have[.])] + named($all) | unique)
             | if . == [] then (if $nw then [] else {whole: "\($p): the test runner, and no test of it found"} end) elif $c != [] then {map: .} else . end
           elif $ct[$p] and $have[$p] and (shared | not) then [$p] + $m
           elif $sh[$p] then {whole: "\($p): shared by most tests (map)", map: ($m + $c)}
           elif $c != [] then {map: ($m + $c)}
           elif $m != [] then $m
           elif $ct[$p] and ($have[$p] | not) then []
           elif $ct[$p] or (contains("/") | not) or shared or config then {whole: "\($p): shared setup or config"}
           else named($all) | if . == [] then {whole: "\($p): no test found for it"} else . end end]
      | (map(objects | select(.whole)) | first) as $w | . as $l
      | if $w and ($nw | not) then error($w.whole) else [.[] | if type == "array" then .[] else (.map // [])[] end] | unique
        | if . == [] and ($nw | not) then error("the change touches no test")
          else {by: (if any($l[]; type == "object" and (.map // []) != []) then "map" else "name" end), age: $tm.age} as $b
          | ($b | tojson), .[] end end' --slurpfile tm <(printf '%s' "${tm:-null}") --argjson nw "$([ "${2:-}" = narrow ] && echo true || echo false)" \
    --rawfile ch <(git -C "$1" -c core.quotePath=false diff --name-only --no-renames "${d[@]}" -- 2>/dev/null) \
    --rawfile ct <(git -C "$1" -c core.quotePath=false diff --name-only --no-renames "${d[@]}" -- 2>/dev/null | testpaths) \
    --rawfile all <(git -C "$1" -c core.quotePath=false ls-files 2>/dev/null | testpaths) \
    --slurpfile map <(jq -c . "$1/.conveyor/test-links.json" 2>/dev/null || :) --arg rn "$rn" --argjson rt "$rt" --arg mp "$mp" --slurpfile om <(printf '%s' "$om") 2>&1) \
    || { out=${out#jq: error (at <unknown>): }; printf '%s\n' "${out:-the list of tests could not be made}"; return 1; }
  printf '%s\n' "$out"
}
# The part of a test line that says the run went again (tests()): {rerun: {exit, failures, tail}} of the first run, else {};
# on a pass line, with the reason "passed on re-run: " and what had not passed (each case as <file>: <case>), each
# of those a failure whose verdict is flaky (mainred.sh verdicts()).
firstrun() { # <worktree> [pass]
  jq -ce --arg p "${2:-}" "$NOTPASSED"'. as $x | {rerun: $x} + if $p == "" then {} else
    {reason: ("passed on re-run: " + ($x | notpassed | if . == [] then "exit \($x.exit)" else join(", ") end)),
     verdicts: [$x | notpassed[] | {case: ., verdict: "flaky"}]} end' "$1.first" 2>/dev/null || echo '{}'
}
# What did not pass in a first run (<worktree>.first, {exit, failures, tail}): each case as <file>: <case>, a file that failed
# naming no case or ran out of time (testfails() timeout or ownLimit) as the file alone; each once. Not a file only stopped
# beside it (testfails() stopped: files side by side stop together): run one at a time it had not begun (#1594), so it did not fail.
NOTPASSED='def notpassed: [.failures.files[] | .file as $f | if .cases == [] then $f else .cases[] | "\($f): \(.name)" end]
  + [(.failures.ownLimit // [])[], (.failures.timeout.file // empty)] | unique;'
# The command of a run with the pack's test.fileCommand (tests()): each file its list (CONVEYOR_TEST_RERUN) names
# `fail`, in order, runs alone with that command, once however many of its lines name it, the file's path added as its
# last argument, one at a time (fileeach() one, lib/fileeach.sh: its logs, time limits and end are there).
# It logs each as a runner does, so the run is read as any other (testfails()); it fails when a file fails.
# With files (a card's run, listcmd()), they run side by side, each on a test slot of its own (fileeach() side), and are those
# the file CONVEYOR_TEST_FILELIST names lists (testonce()), one a line, but for each the list keeps as passed (a `pass` line) and names in no `fail`
# line (a file that passed before and failed since keeps its `pass` line beside the `fail` lines of its cases): a run
# again after a failure runs only the files that did not pass. A list with a `changed` or `main` line (rerunsince(): a fix or main
# changed code since those passes) keeps none: every file it is given runs, as any of them may test that code; tests() gives it
# the files of the card's list but those the list keeps something of (a `pass`, `ok` or `off` line) and that the pack's test.changed
# command selects nothing of (testlist.sh runfiles()).
# With fast too (the rule Stop a card's tests at the first failure: failfast()), the run stops at its first failure:
# the command exports CONVEYOR_TEST_FAILFAST=1, which fileeach() and each file's command read (lib/fileeach.sh).
# The command holds fileeach()'s own text, so it needs no file of the engine's where it runs.
filecmd() { # <the pack's test.fileCommand> [files [fast]]
  local q m=one; q=$(printf %q "$1")
  if [ "${2:-}" = files ]; then m=side
    [ "${3:-}" != fast ] || echo 'export CONVEYOR_TEST_FAILFAST=1'
    printf '%s\n' 'fs=() t=$'"'"'\t'"'"' c=; l=$CONVEYOR_TEST_LOG/files' \
      '! grep -qE "^(changed|main)$t" "${CONVEYOR_TEST_RERUN:-/dev/null}" 2>/dev/null || c=1' \
      'while IFS= read -r f; do' \
      '  [ -n "$f" ] && { [ -n "$c" ] || ! grep -qxF "pass$t$f" "${CONVEYOR_TEST_RERUN:-/dev/null}" 2>/dev/null \' \
      '    || awk -F "$t" -v f="$f" "\$1 == \"fail\" && \$2 == f { e = 1 } END { exit !e }" "$CONVEYOR_TEST_RERUN"; } || continue; fs+=("$f")' \
      'done < "${CONVEYOR_TEST_FILELIST:-/dev/null}"'
  else
    printf '%s\n' 'fs=(); l=$CONVEYOR_TEST_LOG/files' \
      'while IFS=$'"'"'\t'"'"' read -r k f _; do' \
      '  [ "$k" = fail ] && [ -n "$f" ] || continue; [ ${#fs[@]} = 0 ] || ! printf "%s\n" "${fs[@]}" | grep -qxF -- "$f" || continue; fs+=("$f")' \
      'done < "${CONVEYOR_TEST_RERUN:-/dev/null}"'
  fi
  printf '%s\n' "$(declare -f fileeach)" "fileeach $m $q $(printf %q "${FILELIMIT:-}") $(printf %q "${LOADSCALE:-}") \"\$l\" \"\${fs[@]}\""
}
# The awk program that prints a test file's own time limit: the number of its `# timeout: <seconds>` line in the
# comments the file starts with (as the engine's runner reads it for its cases), words after the number (a note) left
# out; nothing when it has none.
FILELIMIT='FNR > 1 && !/^#/ && NF { exit } /^#[[:space:]]*timeout:[[:space:]]*[0-9]+([[:space:]].*)?$/ { sub(/^#[[:space:]]*timeout:[[:space:]]*/, ""); print $0 + 0; exit }'
# The awk program that prints a time limit n (seconds) times a load factor f, held between 1 and 3, rounded up.
LOADSCALE='BEGIN { f += 0; if (f < 1) f = 1; if (f > 3) f = 3; x = n * f; printf "%d\n", (x == int(x)) ? x : int(x) + 1 }'
# A failed run of the bug-card check that gave no result for a file it was given: the runner's logs (testlogs()) name
# it neither passed nor failed, and name no case of it that passed (testfails()), and no case the run names as passed
# or failed, under any file, is in its text (a runner that runs another's cases logs them under its own name: the
# engine's runner, conveyor/conveyor.test.sh, those of its case files). Prints the first such file; fails when there is
# none, the run passed, or the command writes no logs (its exit is all it says).
noresult() { # <worktree> <exit> <file>...
  local w=$1 rc=$2 t f cs; shift 2
  [ "$rc" != 0 ] && [ -n "$(testlogs "$w")" ] && t=$(testfails "$w.test" "$rc") || return 1
  cs=$(jq -r '(.okcases + .passcases)[]?.cases[]?, .files[]?.cases[]?.name | select(. != "")' <<<"$t")
  for f in "$@"; do
    jq -e --arg f "$f" 'IN(.passed[]?, .files[]?.file, .okcases[]?.file; $f)' <<<"$t" >/dev/null && continue
    [ -n "$cs" ] && grep -qF -- "$cs" "$w/$f" 2>/dev/null && continue
    printf '%s\n' "$f"; return 0
  done
  return 1
}
# A card's test run that failed with no result (card(): it proves nothing, so none of it runs on main, goes to the
# main-red record, a wait for main or a fix session; the test step runs again): it was killed by a signal (an exit
# over 128: the service stopping or restarting), or its time ran out with no test file begun and not ended (the runner
# itself, not a test, ran out of time), or its runner wrote logs that name nothing it ran (no `TESTRUN`, `== ` or `-- `
# line), or its only failure is the test command itself (testfails()'s name for a run that logged no file, when its
# output names no failing case either), or a host problem kept a file from starting, whatever else failed (hostonly()). Or it
# passed with a file whose filter ran no case (nocases(): <worktree>.noresult). Prints why; fails on a result.
voidrun() { # <worktree> <exit>
  local l=() f cmd h
  [ "$2" != 0 ] || return 1
  [ "$2" -le 128 ] || { echo "exit $2: the run was killed by a signal"; return 0; }
  [ ! -s "$1.noresult" ] || { cat "$1.noresult"; return 0; }
  mapfile -t l < <(testlogs "$1" | grep -v '/cache$') # the loop's own file there (cacheoff()) is none of the runner's
  if [ "$2" = 124 ]; then
    f=$(testfails "$1.test" 124 | jq -r '.timeout.file // empty' 2>/dev/null)
    [ -n "$f" ] && [ ${#l[@]} -gt 0 ] && grep -qxF -- "== $f" "${l[@]}" 2>/dev/null \
      || { echo "exit 124: the run's time ran out with no test file running"; return 0; }
  fi
  [ ${#l[@]} -gt 0 ] && ! grep -qE '^(TESTRUN |== |-- )' "${l[@]}" 2>/dev/null && { echo "exit $2: the runner's logs name no test it ran"; return 0; }
  [ ${#l[@]} -eq 0 ] || ! h=$(hostonly "${l[@]}") || { echo "exit $2: a problem of the host, not of a test: $h"; return 0; }
  # Logs that name tests it ran are a result: the command failed on a check of its own (a lint, shellcheck, a map
  # check), which its output says and a fix session can act on (#195 was blocked three times for its own warnings).
  [ ${#l[@]} -eq 0 ] || return 1
  packget test.command cmd 2>/dev/null && [ -n "$cmd" ] && testfails "$1.test" "$2" \
    | jq -e --arg c "$cmd" '.files != [] and all(.files[]; .file == $c and .cases == [])' > /dev/null 2>&1 || return 1
  echo "exit $2: the run named no test that failed, only the test command"
}
# Each file of a run whose filter ran no case: its list (<worktree>.rerun) names cases of it (`fail<TAB><file>
# <TAB><case>` lines, and no such line of it with no case), the logs say it ended ok, its runner said it writes a
# record of each case it runs (a record {file} with no case in results/ of the log folder: tests/lib.sh; or that its
# filter ran none: lib/filerun.sh), and no record of a case is of it (testfails()). A runner may exit 0 on a filter
# that matches no case, and that is no pass. A file whose runner writes no records is read as before. Prints
# `<file><TAB><case><TAB><case>...` for each; fails when there is none.
nocases() { # <worktree>
  local rs l=()
  rs=$(cat "$1.testlog"/results/* 2>/dev/null | jq -rR 'fromjson? | objects | select(.file | type == "string") | [if .case == null then "runner" else "case" end, .file] | @tsv')
  [ -n "$rs" ] && [ -s "$1.rerun" ] || return 1
  mapfile -t l < <(testlogs "$1"); [ ${#l[@]} -gt 0 ] || return 1
  awk -F'\t' 'FILENAME == ARGV[1] { if ($1 == "fail" && $2 != "") { if ($3 == "") w[$2] = 1; else c[$2] = c[$2] "\t" $3 }; next }
    FILENAME == ARGV[2] { if ($1 == "runner") rn[$2] = 1; else r[$2] = 1; next }
    /^-- ok / { f = substr($0, 7); if ((f in c) && (f in rn) && !(f in w) && !(f in r) && !s[f]++) print f c[f] }' \
    "$1.rerun" <(printf '%s\n' "$rs") "${l[@]}" | grep .
}
# A failed run's record (testfails()) with each file nocases() names out of its passes and among its failures, with
# the cases its filter named: such a file passed nothing, so the list (rerunlist()) keeps its `fail` lines for the run
# again, not a `pass` line.
nopass() { # <worktree> <the run's record>
  jq -c --rawfile z <(nocases "$1") '[$z | split("\n")[] | select(. != "") | split("\t")] as $z | .passed -= [$z[][0]]
    | .files += [$z[] | {file: .[0], cases: [.[1:][] | {name: ., line: "its filter ran no case"}]}]' <<<"$2"
}
# One run of the command <cmd> in the worktree, on the slot tests() holds. The report file an earlier run wrote
# (<worktree>.report, reportask()) goes first: a runner that adds to it (tools/mochatimes.cjs) would otherwise give the
# run again the first run's times too. It runs on its slot's core (slot_mine, or the home slot's that the runner
# has), which is never a core kept for the user (slot_cpus): slot_keepwords's taskset of the cores left would undo
# that pin, so it is put before the run only when no slot has a core to pin to.
# CONVEYOR_TEST_TIME is the path of tools/testtime.sh, for a test command the Board's Record CPU time wrapped in it
# (cpuplan(), lib/testfiles.sh). CONVEYOR_LOAD_FACTOR is the machine's load factor as the run starts (loadfactor()),
# which the run's limits are scaled by too (testclock()'s and TEST_HARD). CONVEYOR_TEST_FILELIST is the path of <worktree>.testfiles,
# the files a card's run is given (TEST_FILES), one a line; empty with none. A file, not the list itself: one value of
# the environment over Linux's 128 KiB limit stops the command from starting.
# TEST_HARD, when set, is a limit in seconds (scaled, as above) that timeout itself keeps: the run ends there even while a runner of the
# command waits for a whole-suite turn, which stops testclock's clock (the check on main, mainred.sh verdicts()).
testonce() { # <worktree> <cmd>
  local pid clock rc r='' t0 lf lim hard=${TEST_HARD:-0} given='' KEEP=()
  [ ! -s "$1.rerun" ] || r=$1.rerun; rm -f "$1.report" "$1".report.[0-9]* "$1.testfiles"
  [ -z "${TEST_FILES:-}" ] || { printf '%s\n' "$TEST_FILES" > "$1.testfiles" && given=$1.testfiles; } || return 1
  t0=$(date +%s); lf=$(loadfactor); [ -n "$SLOT_CPUS" ] || slot_keepwords
  # The run's limits, scaled by its load factor as each file's own is (filecmd()): the clock's, kept in <worktree>.limit
  # for the line that says the run timed out (testfails()) and the Tests action's record, and TEST_HARD's. A Tests
  # action's run (TALIMIT, its record: lib/testaction.sh tarunfile()) has it in its record now, while it runs.
  lim=$(awk -v n="${TEST_TIMEOUT:-3600}" -v f="$lf" "$LOADSCALE") || lim=${TEST_TIMEOUT:-3600}
  printf '%s\n' "$lim" > "$1.limit" || return 1
  [ -z "${TALIMIT:-}" ] || talimit "$lim"
  [ "$hard" = 0 ] || hard=$(awk -v n="$hard" -v f="$lf" "$LOADSCALE") || hard=$TEST_HARD
  (cd "$1" && { [ -n "$SLOT_HOME" ] || slot_mine; } && { [ ${#REPORT_ENV[@]} = 0 ] || export "${REPORT_ENV[@]}"; } && CONVEYOR_TEST_SLOTS=$HERE/lib/slots.sh CONVEYOR_TEST_LOG=$1.testlog CONVEYOR_TEST_TURNWAIT=$1.turnwait \
    CONVEYOR_TEST_TIME=$HERE/tools/testtime.sh CONVEYOR_LOAD_FACTOR=$lf CONVEYOR_TEST_RERUN=$r CONVEYOR_TEST_FILELIST=$given CONVEYOR_TEST_CASES=${TEST_CASES:-} exec "${KEEP[@]}" timeout --kill-after=30 "$hard" bash -c "$2" > "$1.test" 2>&1 < /dev/null 8>&-) &
  pid=$!; testclock $pid "$1.turnwait" "$lim" & clock=$!
  watch $pid "$1.test" "$1.live" test; rc=$?
  kill $clock 2>/dev/null; wait $clock 2>/dev/null; rm -f "$1.turnwait"
  reported "$1" "$t0"
  # timeout made the command a process group of its own ($pid): a process left of it that closed the slot's
  # descriptor still keeps the slot (slot_left).
  [ -n "$SLOT_HOME" ] || slot_left "$pid"; return $rc
}
# What a card's run and a full test suite's run (tests()) ask the runner for so that it writes its report, with no
# change to the test command
# (the pack's test.report env and args, setup.sh reportguess()), its <file> made <worktree>.report: REPORT_ENV, each
# variable as `<name>=<value>`, the words after the variable's own (testonce() exports them), <file> and <mochatimes>
# (Conveyor's mocha timer, tools/mochatimes.cjs) in double quotes, as an option in NODE_OPTIONS takes a path;
# REPORT_ARGS, words for the command's end, the file quoted for the shell. Both empty when the pack names neither.
# With files (a card's run, which runs each file alone: filecmd()), the args' <file> is <worktree>.report.<n>, n the
# file's place in the run (CONVEYOR_TEST_N), so no file's run writes over the report of the file before it.
REPORT_ENV=()
reportask() { # <worktree> [files]
  local e a q
  REPORT_ENV=(); REPORT_ARGS=''
  packget test.report.env e test.report.args a 2>/dev/null || return 0
  printf -v q '%q' "$1.report"; [ "${2:-}" != files ] || q+='."$CONVEYOR_TEST_N"'; REPORT_ARGS=${a//<file>/$q}
  [ -z "$e" ] || mapfile -t REPORT_ENV < <(jq -r --arg f "\"$1.report\"" --arg m "\"$HERE/tools/mochatimes.cjs\"" 'objects | to_entries[]
    | select((.key | test("^[A-Za-z_][A-Za-z0-9_]*$")) and (.value | type == "string"))
    | "\(.key)=\(env[.key] // "" | if . == "" then "" else . + " " end)\(.value | gsub("<file>"; $f) | gsub("<mochatimes>"; $m) | gsub("\n"; " "))"' <<<"$e")
}
