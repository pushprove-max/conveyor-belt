# SPDX-License-Identifier: Apache-2.0
# The test map (which tests cover which source files), which a card's list of tests reads: lib/testmap.sh.
. "${BASH_SOURCE[0]%/*}/testmap.sh" || return 1
# What a failed test run says went wrong: the failing test files, never the passing ones or their `ok` lines. Which
# files ran and which failed is read from the logs the runner wrote (testlogs), never from the output, where a test's
# own lines could pass for the runner's: `== <file>` as a file begins (the whole line: a name may have spaces),
# `-- ok|FAIL <file>` as it ends, `TESTRUN files=N` for how many it selected. A failed file is listed even when no line names a case of it. A failing case is a
# line of the output: `FAIL [<case>]: ...`, TAP's `not ok N - <case>` (never a TODO or SKIP one) or node's
# `✖ <case> (Nms)`; it is its file's when the output has `== <file>` before it for a file the logs say began, and
# began after the file the output was in (a log is one runner's and its files run in its order, so a `== ` line that
# goes back in its log, or names no file of the run, is a test's own), else under the file "". A case line under a
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
# seconds it had and the last file begun and not ended (null when there is none). passed is the files the logs say
# ended ok (tests() runs them no more on the same change); okcases, of each other file, the cases a line `ok <case>`
# under it says passed (a runner killed part-way runs them no more); passcases, the same of each file that passed
# (what a batch that takes the card need not run again: passlist()). A run whose command wrote no such
# log is one file, named by the command (test.command): its cases are that file's, and a timeout is in it. An output
# that is no run's (norun(): no log folder) names no file.
testfails() { # <test output file> <exit> [the pack's field of the run's command: test.command]; prints {of, files: [{file, cases: [{name, line}]}], timeout, passed, okcases: [{file, cases}], passcases: [{file, cases}]}
  local logs=() log cmd='' named
  # A file's name may have spaces, at its end too, and words may follow it on a line that is not its beginning in the
  # logs (a duration, the cases run): the file such a line names is the longest of the files it can be that the line's
  # words begin with. An end can be only of a file begun and not ended: never of a file that is done, whose name the
  # line may begin with too, and never of a file of another runner's log: a log's end lines are of its own files. A
  # `== ` line of the output is of the longest of all the run's files: one that names again a file that is done goes
  # back, and is never the beginning of a later file whose name its name begins with.
  named='def named($fs): . as $r | [$fs[] | select(. as $f | $r == $f or ($r | startswith($f + " ")))] | max_by(length);'
  mapfile -t logs < <(testlogs "${1%.test}")
  [ ! -d "${1%.test}.testlog" ] || packget "${3:-test.command}" cmd 2>/dev/null || cmd=''
  # Each log begins on a line of its own: a log that ends without a newline would else join the next log's mark.
  log=$(for log in "${logs[@]}"; do printf '\n\001\n'; cat "$log" 2>/dev/null; done | sed 's/\x1b\[[0-9;]*m//g' | tr -d '\000\r' | jq -cRn "$named"'
    reduce inputs as $l ({n: null, files: [], order: [], failed: [], open: []};
      . as $s | ([$l | capture("^== (?<f>.*\\S.*)")][0].f) as $b
      | ([$l | capture("^-- (?<r>ok|FAIL) (?<f>.*\\S.*)") | .f |= (named($s.open[-1]) // (sub("^ +"; "") | named($s.open[-1]) // named($s.order[-1]) // sub(" .*"; "")))][0]) as $e
      | ([$l | capture("^TESTRUN files=(?<n>[0-9]+)")][0].n) as $n
      | if $l == "\u0001" then .order += [[]] | .open += [[]]
        elif $b then .files |= (. + [$b] | unique) | (if .order[-1] | index($b) then . else .order[-1] += [$b] end) | .open[-1] += [$b]
        elif $e then .files |= (. + [$e.f] | unique) | .open[-1] -= [$e.f] | if $e.r == "FAIL" and (.failed | index($e.f) | not) then .failed += [$e.f] else . end
        elif $n then .n += ($n | tonumber) else . end)') || return 1
  sed 's/\x1b\[[0-9;]*m//g' "$1" 2>/dev/null | tr -d '\000\r' | jq -cRn --arg rc "$2" --arg sec "$TEST_TIMEOUT" --arg cmd "$cmd" --argjson log "$log" "$named"'
    def cut: if length <= 200 then . else (.[0:201] | sub("\\s+\\S*$"; "")) as $w | if ($w | length) > 200 then .[0:200] else $w end end;
    (if $log.files == [] and $cmd != "" then $cmd else null end) as $only
    | [inputs] as $ls | ($log.order | map(length)) as $ns
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
      | ([$l | capture("^ok (?<c>\\S+)$")][0].c) as $o
      | (if .cur == "" then $only else .cur end) as $of
      | (if $o and $of then .oks[$of] += [$o] else . end)
      | ([$l | capture("^FAIL \\[(?<c>[^\\]]+)\\]: "), capture("^\\s*not ok [0-9]+ (- )?(?<c>.*\\S)") , capture("^\\s*✖ (?<c>.+) \\([0-9.]+ms\\)$")][0].c) as $c
      | (if $c and ($l | test("^\\s*not ok .*# *(TODO|SKIP)"; "i") | not) then
          (if $whole | not then [.cur | select(. == "" or IN($log.failed[]))]
           elif all($pre[$k][]; . == 0) then [$only // ""]
           else .seen as $seen | [range(0; $ns | length) as $r | range(([$ns[$r] - $suf[$k][$r] - 1, 0] | max); $pre[$k][$r]) as $j
             | $seen["\($r) \($j)"] as $t | select(all(range(0; $ns | length); . == $r or $pre[$t + 1][.] + $suf[$k][.] >= $ns[.]))
             | $log.order[$r][$j] | select(IN($log.failed[]))] end) as $own
          | reduce $own[] as $file (.; (if any(.files[]; .file == $file) then . else .files += [{file: $file, cases: []}] end)
            | .files |= map(if .file == $file and (any(.cases[]; .name == $c) | not) then .cases += [{name: $c, line: ($l | sub("^\\s+"; "") | cut)}] else . end))
        else . end)
      | reduce $hs[$k][] as [$r, $i] (.; .seen["\($r) \($i)"] = $k | if $i > .at[$r] then .cur = $log.order[$r][$i] | .at[$r] = $i else . end))
    | ($log.files - $log.failed - ($log.open | flatten)) as $passed | .files as $fs
    | {of: ($log.n // ($log.files | length | if . == 0 then null else . end)), files,
       timeout: (if $rc == "124" then {sec: ($sec | tonumber? // $sec), file: ($only // ($log.open | flatten | last))} else null end),
       passed: $passed,
       okcases: [.oks | to_entries[] | .key as $f | select(IN($passed[]; $f) | not)
         | {file: $f, cases: ((.value | unique) - [$fs[] | select(.file == $f) | .cases[].name])} | select(.cases != [])],
       passcases: [.oks | to_entries[] | select(IN($passed[]; .key)) | {file: .key, cases: (.value | unique)}]}'
}

# A test output that is no run's (the loop's own words for why nothing ran): the logs and times of the run before are not its.
norun() { rm -rf "$1.testlog" "$1.first" "$1.testlist"; TEST_WAIT=''; TEST_RUN=''; TEST_FREE=''; printf '%s\n' "$2" > "$1.test"; } # <worktree> <text>
# A run's output and the logs it wrote, copied as one: what failed is read from both (testfails()); and its first
# run's record when it went again (tests()).
keeprun() { # <worktree> <output file to> <log folder to> <first run's record to>
  rm -rf "$3" "$4"; cp -f "$1.test" "$2" && { [ ! -d "$1.testlog" ] || cp -R "$1.testlog" "$3"; } && { [ ! -e "$1.first" ] || cp -f "$1.first" "$4"; }
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
# engine (`TESTRUN whole-suite`); ranCases, the cases it selected of each file it ran only part of, {file: [cases]},
# from its log lines `TESTRUN case<TAB><file><TAB><case>` (brokeby()); refused, "refused full run: <why>", when
# tests() refused the whole selection (TEST_REFUSED); and list, the list of tests the command was given (listcmd():
# {mode: "changed", files} or {mode: "whole", why}), when the pack sets test.list.
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
    + if $cs == [] then {} else {ranCases: ($cs | group_by(.f) | map({key: .[0].f, value: (map(.c) | unique)}) | from_entries)} end
    + if $z == "" then {} else {refused: $z} end
    + if $tl[0] | type == "object" then {list: $tl[0]} else {} end' --slurpfile tl <(cat "$1.testlist" 2>/dev/null)
}

# The test files of a card's own run that used more than their budget (README.md, The test step): the file's own
# (test.files.<file>.budget) when the pack gives it one, else the pack's test.fileBudget CPU seconds. A file the pack
# marks slow on purpose (test.files.<file>.slowOnPurpose) is held to no budget. For its test line (slow): a note,
# never a finding of its review, and filed only by a test rule (lib/testrules.sh). CPU seconds, not clock time, as a file's clock time on a
# busy machine is the machine's load. A runner times each file it runs with a log line
# `TESTRUN sec<TAB><file><TAB><seconds><TAB><CPU seconds>` as the file ends, the last such line of a file counting,
# those of the run before a run again (<worktree>.times, tests()) first. Each is {file, sec, cpu, budget, changed}:
# changed when the card's staged change adds or modifies the file. A file the change only modifies also has main's
# own CPU seconds of it (before): the file's time recorded last (beforetimes()), with where it came from (from), null
# when none is recorded: no test runs again only to be timed.
# Written to <worktree>.slow, a JSON array ([] when no file is over); the times of each test file the change adds or
# modifies, {file, sec, cpu}, to <worktree>.timed, for its test line (timed); and the CPU seconds of every file the run
# timed, {file: cpu}, to <worktree>.cpus, for its test line (times), where a later card finds them once this one has
# landed; and the clock seconds of every file the run timed, {file: sec}, to <worktree>.clocks, for its test line
# (clocks: the snapshot's tests part, testspart()), a file timed by the clock only (a runner's report, reported())
# among them. A file whose line gives no CPU seconds (cpu null) is held to no budget.
slowtests() { # <worktree>
  local b o c m f t x y
  rm -f "$1.slow" "$1.timed" "$1.cpus" "$1.clocks"
  packget test.fileBudget b test.files o || return 1
  c=$(git -C "$1" diff --cached --no-renames --name-status -z --diff-filter=AM HEAD 2>/dev/null \
    | jq -cRs 'split("\u0000") | . as $a | [range(0; length - 1; 2) | {key: $a[. + 1], value: $a[.]}] | from_entries') || return 1
  t=$(timed "$1") || return 1
  jq -c --argjson c "$c" '[to_entries[] | select($c[.key] != null) | {file: .key} + .value]' <<<"$t" > "$1.timed" || return 1
  { IFS= read -r x && IFS= read -r y; } < <(jq -c '(with_entries(select(.value.cpu != null)) | map_values(.cpu)), map_values(.sec)' <<<"$t") \
    && printf '%s\n' "$x" > "$1.cpus" && printf '%s\n' "$y" > "$1.clocks" || return 1
  f=$(jq -c --argjson b "$b" --argjson o "$o" --argjson c "$c" 'to_entries | map(($o[.key] // {}) as $own
    | select(.value.cpu != null and $own.slowOnPurpose == null) | ($own.budget // $b) as $b | select(.value.cpu > $b)
    | {file: .key, sec: .value.sec, cpu: .value.cpu, budget: $b, changed: ($c[.key] != null)})' <<<"$t") || return 1
  m='{}'; ! jq -e --argjson c "$c" 'any(.[]; $c[.file] == "M")' <<<"$f" > /dev/null || m=$(beforetimes "$1") || m='{}'
  jq -c --argjson c "$c" --argjson m "$m" 'map(if $c[.file] == "M" then $m[.file] as $p
    | . + {before: $p.cpu} + if $p then {from: $p.from} else {} end
    else . end)' <<<"$f" > "$1.slow"
}
# The files a run in <worktree> timed, {file: {sec, cpu}} (cpu null when the line gives none): its runners'
# `TESTRUN sec` lines, those of the run before a run again (<worktree>.times, tests()) first, then those read from the
# runner's own report (<worktree>.reported, reported()), the last line of a file counting: a runner's own line wins.
timed() { # <worktree>
  local l logs=()
  mapfile -t logs < <(testlogs "$1")
  { cat "$1.times" "$1.reported" 2>/dev/null; for l in "${logs[@]}"; do printf '\n'; cat "$l" 2>/dev/null; done; } \
    | jq -cRn '[inputs | capture("^TESTRUN sec\t(?<f>[^\t]+)\t(?<s>[0-9]+(\\.[0-9]+)?)(\t(?<c>[0-9]+(\\.[0-9]+)?))?$")
      | {key: .f, value: {sec: (.s | tonumber), cpu: (.c | tonumber? // null)}}] | from_entries'
}
# A whole-suite run's files, for the Tests page (the snapshot's tests part, testspart() of lib/testfiles.sh): a line
# for the run appended to $SUITERUNS, {time, how (full: the Board's full test suite, lib/fulltest.sh; release:
# release-prep's, commands/release-prep.sh), sha, files: {<file>: {result: ok or fail (its `-- ok|FAIL <file>` line;
# null with none), sec, cpu (its last `TESTRUN sec` line's; null with none)}}}, read from the times its runner's own
# report gave (<worktree>.reported, reported()), then the logs the run in <worktree> wrote (testlogs()) and its output
# (<worktree>.test), so a runner's own line wins. A run that names no file adds no line.
SUITERUNS=${STATE%/*}/suiteruns.jsonl
suiterec() { # <worktree> <full | release> <commit>
  local logs=()
  mapfile -t logs < <(testlogs "$1")
  { [ ! -f "$1.reported" ] || cat "$1.reported"; cat "${logs[@]}" "$1.test"; } 2>/dev/null | sed 's/\x1b\[[0-9;]*m//g' | jq -cRn --arg t "$(clock)" --arg h "$2" --arg s "$3" '
    reduce (inputs | (capture("^TESTRUN sec\t(?<f>[^\t]+)\t(?<s>[0-9]+(\\.[0-9]+)?)(\t(?<c>[0-9]+(\\.[0-9]+)?))?$")
        | {f, v: {sec: (.s | tonumber), cpu: (.c | tonumber? // null)}}),
      (capture("^-- (?<r>ok|FAIL) (?<f>.+)$") | {f, v: {result: (if .r == "ok" then "ok" else "fail" end)}})) as $x ({}; .[$x.f] += $x.v)
    | select(length > 0) | {time: $t, how: $h, sha: $s, files: map_values({result: null, sec: null, cpu: null} + .)}' >> "$SUITERUNS" 2>/dev/null
}
# Main's recorded CPU seconds of each test file, {file: {cpu, from}}, the newer of two records of it: the test lines
# (times) of the newest card that ran it and landed, as of its landed line, "card #<issue>, <day>"; and the latest
# test-speed survey's, the file .conveyor/test-times.json on the commit <worktree>'s change is on, {files: {file:
# {sec, cpu}}}, as of the commit that last wrote it, "test-speed survey, <day>"; and a run of the file by hand that
# passed (testaction run: its record in $TESTACTS), as of its end, "run by hand, <day>". A card's later test line of a
# file counts over its earlier ones. A file none of them records is not in it.
beforetimes() { # <worktree>
  local s='[]' at h
  at=$(git -C "$1" log -1 --format=%ct HEAD -- .conveyor/test-times.json 2>/dev/null)
  [ -z "$at" ] || s=$(git -C "$1" show HEAD:.conveyor/test-times.json 2>/dev/null | jq -c --argjson at "$at" '[.files | objects | to_entries[]
    | select(.value | objects | .cpu | type == "number") | {file: .key, cpu: .value.cpu, at: $at, from: "test-speed survey, \($at | todate | .[:10])"}]') || s='[]'
  h=$(cat "$TESTACTS"/*.json 2>/dev/null | jq -cs '[.[] | objects | select(.action == "run" and .state == "done" and .result == "pass"
    and (.file | type == "string") and (.cpu | type == "number") and (.end | strings | fromdate? | type == "number"))
    | {file, cpu, at: (.end | fromdate), from: "run by hand, \(.end[:10])"}]') || h='[]'
  s=$(jq -cn --argjson s "$s" --argjson h "$h" '$s + $h')
  stdb ask lines cards | jq -cRn --argjson s "$s" 'reduce (inputs | fromjson? | objects | select(.step == "landed" or (.step == "test" and (.times | type == "object")))) as $l
      ({l: {}, t: {}}; if $l.step == "landed" then .l[$l.card] = $l else .t[$l.card] += $l.times end)
    | .l as $l | [.t | to_entries[] | $l[.key] as $d | select($d and ($d.time | fromdate? | type == "number")) | .value | to_entries[]
      | select(.value | type == "number") | {file: .key, cpu: .value, at: ($d.time | fromdate), from: "card #\($d.issue), \($d.time[:10])"}] + $s
    | group_by(.file) | map(max_by(.at) | {key: .file, value: {cpu, from}}) | from_entries'
}
# Its test line's part: {timed: <worktree>.timed} when the run timed a test file the change adds or modifies,
# {times: <worktree>.cpus, clocks: <worktree>.clocks} when it timed any file (times is {} when each was timed by the
# clock only), and {slow: <worktree>.slow} when a file is over, else {}.
slowrec() { # <worktree>
  jq -cn --slurpfile t "$1.timed" --slurpfile c "$1.cpus" --slurpfile k "$1.clocks" --slurpfile s "$1.slow" '(if $t[0] | length > 0 then {timed: $t[0]} else {} end)
    + (if ($c[0] | length > 0) or ($k[0] | length > 0) then {times: $c[0], clocks: $k[0]} else {} end) + if $s[0] | length > 0 then {slow: $s[0]} else {} end' 2>/dev/null || echo '{}'
}
# The slow-test record: {filed: [{file, issue, ...why}]}, the "Slow test" issue last filed for each file, by the filing
# that the test rules replaced (lib/testrules.sh). Nothing writes it now; a file it names whose issue no card has landed
# stays off card test steps (slowoffs()) until that card lands.
SLOWFILED=${STATE%/*}/slow.json
# The test files kept off card test steps for their CPU seconds (the owner, 2026-11-14): each file of $SLOWFILED whose
# issue no card has landed yet, its entry there one a line: {file, issue} and why (cpu and sec in the card run that
# filed it, card; last: {cpu, card}, the card run before it; budget) and since. Such a file runs only in the full suite
# and the whole test on main (slowoff()), and comes back to card test steps when the card of its issue lands.
slowoffs() {
  stdb ask lines cards 2>/dev/null | jq -cRn --slurpfile s "$SLOWFILED" '[inputs | fromjson? | objects | select(.step == "landed") | .issue | numbers] as $l
    | $s[0].filed | arrays | .[] | objects | select((.file | type) == "string" and (.issue | type) == "number" and (IN(.issue; $l[]) | not))' 2>/dev/null
}
# A card's run is told to keep each file slowoffs() names off (tests()): a `pass` line in its list for it (unless the
# list has one), so a command that reads no more runs it not, and an `off<TAB><file>` line (unless the list has one),
# which keeps it off though a `fail`, `changed` or `main` line selects it. Not the card of the file's own issue: its
# change is what makes the file cheaper, and its run times it.
slowoff() { # <worktree>
  local c=${1##*/} f n add=''
  while IFS=$'\t' read -r f n; do
    [ "$n" != "${c##*-}" ] || continue
    grep -qxF "pass"$'\t'"$f" "$1.rerun" 2>/dev/null || add+="pass"$'\t'"$f"$'\n'
    grep -qxF "off"$'\t'"$f" "$1.rerun" 2>/dev/null || add+="off"$'\t'"$f"$'\n'
  done < <(slowoffs | jq -r '[.file, .issue] | @tsv')
  [ -z "$add" ] || printf '%s' "$add" >> "$1.rerun"
}
# The test results cache (README.md, The CPU budget of a test file: The test results cache; the owner, 2026-11-14): each test file a run passed whole,
# with the inputs its command's log named for it (`TESTRUN inputs<TAB><file><TAB><input>...`), one a line in
# $TESTCACHE, `<hash>\t<file>\t<input>...` (cachekeep()), the hash of the file's and its inputs' contents
# (cachesums()). A later run, of any card or the whole test on main, keeps off a file whose hash in its worktree is a
# kept one (cacheoff()). A file its log gives no inputs line for is never kept, so never kept off. The last
# TESTCACHE_KEEP lines are kept; one writer at a time, under a lock of its own.
TESTCACHE=${STATE%/*}/testcache.tsv TESTCACHE_KEEP=5000
# Of lines `<file>\t<input>...` on stdin, each as `<hash>\t<the line>`: the hash of the line's paths, in its order,
# each with the hash of its content in the worktree (a path that is no file there counts as missing), by two git calls.
cachesums() { # <worktree>
  local d rc=0
  d=$(mktemp -d) || return 1
  cat > "$d/lines"
  tr '\t' '\n' < "$d/lines" | sort -u | while IFS= read -r p; do [ ! -f "$1/$p" ] || printf '%s\n' "$p"; done > "$d/paths"
  { git -C "$1" hash-object --no-filters --stdin-paths < "$d/paths" > "$d/sums" && paste "$d/paths" "$d/sums" > "$d/blobs" \
    && awk -F'\t' -v d="$d" 'FILENAME != L { b[$1] = $2; next }
      { f = d "/e" FNR; for (i = 1; i <= NF; i++) printf "%s\t%s\n", $i, ($i in b ? b[$i] : "-") > f; close(f); print f }' \
      L="$d/lines" "$d/blobs" "$d/lines" > "$d/entries" \
    && git -C "$1" hash-object --no-filters --stdin-paths < "$d/entries" > "$d/hashes" && paste "$d/hashes" "$d/lines"; } || rc=1
  rm -rf "$d"; return $rc
}
# After each run of the command (tests()), each file it passed whole, with the inputs its log names, into $TESTCACHE: a
# file its log ends `-- ok` that no `-- FAIL` line, no `TESTRUN case` line (a run of some of its cases) and no `ok`,
# `fail` or `off` line of the list the run was given (some of its cases kept or left out) names. A file a path of whose
# line is absolute or climbs out of the worktree (`..`) is not kept.
cachekeep() { # <worktree>
  local l=() add sums lock r=/dev/null
  mapfile -t l < <(testlogs "$1"); [ ${#l[@]} -gt 0 ] && grep -qh $'^TESTRUN inputs\t' "${l[@]}" 2>/dev/null || return 0
  [ ! -f "$1.rerun" ] || r=$1.rerun
  add=$(awk -F'\t' -v L="$r" 'function bad(p) { return p == "" || p ~ /^\// || p ~ /(^|\/)\.\.(\/|$)/ }
    FILENAME == L { if ($1 == "ok" || $1 == "fail" || $1 == "off") part[$2] = 1; next }
    /^-- ok / { ok[substr($0, 7)] = 1; next }
    /^-- FAIL / { part[substr($0, 9)] = 1; next }
    $1 == "TESTRUN case" { part[$2] = 1; next }
    $1 == "TESTRUN inputs" { if (bad($2)) next; seen[$2] = 1; for (i = 3; i <= NF; i++) { if (bad($i)) part[$2] = 1; inp[$2] = inp[$2] "\t" $i } }
    END { for (f in seen) if ((f in ok) && !(f in part)) print f inp[f] }' "$r" "${l[@]}")
  [ -n "$add" ] || return 0
  sums=$(printf '%s\n' "$add" | cachesums "$1") || return 1
  { exec {lock}>>"$TESTCACHE.lock"; } 2>/dev/null || return 1
  flock "$lock" || { exec {lock}>&-; return 1; }
  # Each hash once, at its last place; the last TESTCACHE_KEEP lines.
  { cat "$TESTCACHE" 2>/dev/null; printf '%s\n' "$sums"; } | awk -F'\t' 'length { a[++n] = $0; k[n] = $1; at[$1] = n }
    END { for (i = 1; i <= n; i++) if (at[k[i]] == i) print a[i] }' | tail -n "$TESTCACHE_KEEP" > "$TESTCACHE.new" \
    && mv -f "$TESTCACHE.new" "$TESTCACHE" || rm -f "$TESTCACHE.new"
  exec {lock}>&-
}
# A run (tests(): a card's, and the whole test on main) is told to keep off each file of $TESTCACHE whose hash in its
# worktree is a kept one: a `pass` and an `off` line for it in its list (as slowoff(): the off line keeps it off though
# a `changed` or `main` line selects it, its inputs being the same), unless the list names failed cases of it. Prints
# each such file's line for the run's log, `TESTRUN why<TAB><file><TAB>passed before with the same inputs`.
cacheoff() { # <worktree>
  local f m add=''
  [ -s "$TESTCACHE" ] || return 0
  m=$(cut -f2- "$TESTCACHE" | sort -u | cachesums "$1" | awk -F'\t' 'NR == FNR { k[$1] = 1; next } $1 in k { print $2 }' "$TESTCACHE" -) || return 0
  [ -n "$m" ] || return 0
  while IFS= read -r f; do
    grep -qxF "pass"$'\t'"$f" "$1.rerun" 2>/dev/null || add+="pass"$'\t'"$f"$'\n'
    grep -qxF "off"$'\t'"$f" "$1.rerun" 2>/dev/null || add+="off"$'\t'"$f"$'\n'
    printf 'TESTRUN why\t%s\tpassed before with the same inputs\n' "$f"
  done < <(cat "$1.rerun" 2>/dev/null | M=$m awk -F'\t' 'BEGIN { n = split(ENVIRON["M"], a, "\n"); for (i = 1; i <= n; i++) w[a[i]] = 1 }
    $1 == "fail" { delete w[$2] } END { for (f in w) print f }' | sort)
  [ -z "$add" ] || printf '%s' "$add" >> "$1.rerun"
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
# to the command (README.md), says it (rerunlist()). The run after a fix session that left the staged change as it was,
# byte for byte (a whitespace edit is a change: cardpatch() is blind to it), runs only what had not passed. The run
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
# are in <worktree>.first, {exit, failures}, when the run went again, and the files it timed in <worktree>.times
# (its `TESTRUN sec` lines, slowtests()), after those the runs before it timed when this run keeps their passes (a run
# after a fix session does not run again a file that passed); the output is the last run's. A run that passed
# on re-run adds its cases to the flaky-test record (flakyrun()) as it ends, a batch's run (batch()) too; a run again
# that failed adds the cases that passed in it. A card's run that passed leaves what it passed in <worktree>.passed
# (passlist()). A card's run is told to keep the cases the flaky-test record keeps off card runs as passed (flakyoff()),
# and the files kept off for their CPU seconds (slowoff()), and its run again is told the same. Any run but the full
# test suite and a run alone is told to keep off the files that passed before with the same inputs (cacheoff()), its
# log saying so; each run's files that passed whole go to that cache (cachekeep()).
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
# The field test.fileCommand runs one test file: the run (filecmd()) gives it each file its list names `fail`.
# A card's run (test.command, not alone) with the pack's test.list set gives the command the tests its change touches
# (testsel()), in the form test.list names (listcmd()), and <worktree>.testlist says which (the live record's and the
# test line's list). Such a run that passes adds the test files of its change that the test map lacks to it (mapnew(),
# lib/testmap.sh).
tests() { # <worktree> [the pack's field of the command: test.command] [alone]
  local cmd at rc r p='' b='' t='' f o l=() w=$SECONDS ob mw off cw=''
  TEST_WAIT=''; TEST_RUN=''; TEST_FREE=''; TEST_REFUSED=''; TEST_FILES=''; rm -f "$1.testlist"
  # The files the run before timed (timed()): kept below when this run keeps its passes and so may not run them.
  mapfile -t l < <(testlogs "$1"); o=$({ cat "$1.times" "$1.reported"; [ ${#l[@]} = 0 ] || grep -h '^TESTRUN sec' "${l[@]}"; } 2>/dev/null)
  # The commit the last run's list was tested on, and a merge in doubt (<worktree>.whole: card(), settle()), before
  # either goes.
  ob=$(sed -n 's/^base\t//p' "$1.rerun" 2>/dev/null); mw=$(cat "$1.whole" 2>/dev/null); rm -f "$1.whole"
  rm -rf "$1.testlog" "$1.turnwait" "$1.first" "$1.passed" "$1.times" "$1.reported"; { mkdir "$1.testlog" && packget "${2:-test.command}" cmd && slot_pool; } 2>"$1.test" || return 1
  [ "${2:-}" != test.fileCommand ] || cmd=$(filecmd "$cmd")
  if [ -z "${2:-}" ] && [ "${3:-}" != alone ]; then listcmd "$1" "$cmd" 2>"$1.test" || return 1; cmd=$LISTCMD; fi
  # A card's run and the full test suite (fulltest(), release-prep's relsuite()) ask for the runner's report: setup gives
  # test.full the card's command.
  REPORT_ENV=(); if [ -z "${2:-}" ] || [ "$2" = test.full ]; then reportask "$1"; [ -z "$REPORT_ARGS" ] || cmd="$cmd $REPORT_ARGS"; fi
  if [ -z "${2:-}" ]; then
    p=$(git -C "$1" diff --cached --binary --no-renames HEAD 2>/dev/null | git hash-object --stdin)
    b=$(git -C "$1" rev-parse -q --verify HEAD 2>/dev/null); t=$(git -C "$1" write-tree 2>/dev/null)
  fi
  if [ "${3:-}" != alone ]; then
    rerunsince "$1" "$p" "$b" "$t"; r=$?
    # A card's run that would run its whole selection, and is none of a first run, a merge in doubt or the full test
    # suite (the owner, 2026-11-14): refused. It runs what the list did not keep as passed, and says why on its line.
    if [ $r = 1 ] && [ -n "$p" ] && [ -z "$mw" ] && { { [ -n "$ob" ] && [ "$ob" = "$b" ]; } || testedbefore "$1"; }; then
      TEST_REFUSED="refused full run: $RERUN_WHY"
      if [ -s "$1.rerun" ] && { printf 'change\t%s\nbase\t%s\ntree\t%s\n' "$p" "$b" "$t"; grep -E $'^(pass|ok|fail)\t' "$1.rerun"; } > "$1.rerun.new" \
        && mv -f "$1.rerun.new" "$1.rerun"; then r=0; fi
    fi
    if [ $r = 0 ]; then [ -z "$o" ] || printf '%s\n' "$o" > "$1.times"; else rm -f "$1.rerun"; fi
    # A card's run keeps the flaky cases and the slow files off (flakyoff(), slowoff()): the full suite and the whole
    # test on main run them.
    [ -n "${2:-}" ] || { flakyoff "$1"; slowoff "$1"; }
    # It keeps off the files that passed before with the same inputs (cacheoff()), its log saying so (cw): not the full
    # test suite, which runs whole.
    [ "${2:-}" = test.full ] || { cw=$(cacheoff "$1"); [ -z "$cw" ] || printf '%s\n' "$cw" > "$1.testlog/cache"; }
  fi
  # Its ask (slot_ask), held until it ends, so no mutation check of any project runs beside it; a mutation check's own
  # run (MUT_RUN, lib/mutate.sh mutone()) makes none.
  [ -n "${MUT_RUN:-}" ] || slot_ask || :
  if [ -z "$SLOT_HOME" ]; then
    at=$(date -u +%FT%TZ)
    until slot_try || slot_wait; do
      jq -cn --arg at "$at" --argjson n "$(slot_used)" --argjson of "$SLOT_N" '{step: "test", at: $at, last: (now | todate), turns: 0, files: {run: 0, of: null}, tests: null,
        action: "waiting for a test slot (\($n) of \($of) in use)"}' > "$1.live.tmp" 2>/dev/null && mv -f "$1.live.tmp" "$1.live"
    done
  fi
  TEST_WAIT=$((SECONDS - w)); TEST_FREE=$((SLOT_N - $(slot_used))); w=$SECONDS
  # The `off` lines (flakyoff(), slowoff()), which rerunlist() does not keep: given to the run again too, so it runs no
  # case or file kept off that its list would otherwise select (a case of the runner that did not finish).
  off=$(grep $'^off\t' "$1.rerun" 2>/dev/null)
  testonce "$1" "$cmd"; rc=$?; cachekeep "$1"
  if [ $rc != 0 ] && [ -n "$p" ] && f=$(testfails "$1.test" "$rc") && rerunlist "$1" "$p" "$f" "$b" "$t" \
    && { [ -z "$off" ] || printf '%s\n' "$off" >> "$1.rerun"; }; then
    jq -c --argjson rc "$rc" '{exit: $rc, failures: del(.passed, .okcases, .passcases)}' <<<"$f" > "$1.first"
    # The files the first run timed, which the run again does not run, after those of the runs before it (slowtests()).
    mapfile -t l < <(testlogs "$1"); { cat "$1.reported"; [ ${#l[@]} = 0 ] || grep -h '^TESTRUN sec' "${l[@]}"; } >> "$1.times" 2>/dev/null
    rm -rf "$1.testlog"; if mkdir "$1.testlog" 2>"$1.test"; then
      [ -z "$cw" ] || printf '%s\n' "$cw" > "$1.testlog/cache"; testonce "$1" "$cmd"; rc=$?; cachekeep "$1"
    else rc=1; fi
    [ $rc = 0 ] || { f=$(testfails "$1.test" "$rc") && rerunlist "$1" "$p" "$f" "$b" "$t"; } || rm -f "$1.rerun"
  fi
  TEST_RUN=$((SECONDS - w))
  if [ $rc = 0 ] && [ -n "$p" ]; then
    passlist "$1" || rm -f "$1.passed"
    { f=$(testfails "$1.test" 0) && rerunlist "$1" "$p" "$f" "$b" "$t"; } || rm -f "$1.rerun"
  elif [ $rc = 0 ]; then rm -f "$1.rerun"; fi
  [ -n "$SLOT_HOME" ] || slot_free
  slot_unask
  # A pass on re-run goes to the flaky-test record now, before a later run (a batch's) clears <worktree>.first; so do
  # the cases of a run again that failed which passed in it (f: its failures).
  if [ -e "$1.first" ]; then if [ $rc = 0 ]; then flakyrun "$1"; else flakyrun "$1" "${f:-}"; fi; fi
  # A card's run that passed maps the test files its change adds or changes that the test map does not hold yet.
  [ $rc != 0 ] || [ -n "${2:-}" ] || [ "${3:-}" = alone ] || mapnew "$1" >> "$1.test"
  return $rc
}
# The command of a card's run (tests()) given the list of the tests its change touches (README.md, The list of tests a
# card's run is given), in LISTCMD, in the form the pack's test.list names: args (each path added at the end, quoted
# for the shell), placeholder (the paths in place of each `{files}` of test.command), env (CONVEYOR_TEST_FILES, one
# path a line: TEST_FILES, which testonce() gives the command), runner (go test and cargo test, which take packages
# and test targets, not files: runnercmd()) or none (the command takes no list). A run of the whole suite (none,
# testsel()'s whole, placeholder with no `{files}` in the command, args with a command that already names the test
# files its runner runs, testrunner(), which paths added at its end would not narrow, or runner with a list
# runnercmd() cannot give) adds no path. <worktree>.testlist
# says which: {mode: "changed", files: <count>, by: "map" or "name", age: the commits the made test map is behind
# (only with one)} or {mode: "whole", why}. With no test.list, the command is as it is and no file is written.
listcmd() { # <worktree> <command>
  local lm s why='' q='' fs=() by
  LISTCMD=$2; TEST_FILES=''
  packget test.list lm || return 1
  [ -n "$lm" ] || return 0
  if [ "$lm" = none ]; then why='test.list is none: the test command takes no list'
  elif [ "$lm" = placeholder ] && [[ $2 != *'{files}'* ]]; then why='test.list is placeholder, and test.command has no {files}'
  elif [ "$lm" = args ] && s=$(testrunner "$2" "$1") && [[ $s == named* ]]; then
    why="test.list is args, and test.command already names the tests it runs (${s##* }): use placeholder"
  elif ! s=$(testsel "$1"); then why=$s
  else mapfile -t fs <<<"${s#*$'\n'}"; by=${s%%$'\n'*}
    if [ "$lm" = runner ] && ! LISTCMD=$(runnercmd "$2" "$1" "${fs[@]}"); then why=$LISTCMD; LISTCMD=$2; fs=(); fi
  fi
  if [ -n "$why" ]; then jq -cn --arg w "$why" '{mode: "whole", why: $w}' > "$1.testlist"
  else jq -cn --argjson n ${#fs[@]} --argjson b "$by" '{mode: "changed", files: $n, by: $b.by} + if $b.age == null then {} else {age: $b.age} end' > "$1.testlist"; fi || return 1
  [ ${#fs[@]} = 0 ] || q=$(printf '%q ' "${fs[@]}"); q=${q% }
  case $lm in
    args) [ -z "$q" ] || LISTCMD="$2 $q" ;;
    placeholder) LISTCMD=${2//\{files\}/"$q"} ;;
    env) [ ${#fs[@]} = 0 ] || TEST_FILES=$(printf '%s\n' "${fs[@]}") ;;
  esac
}
# The command of a card's run with test.list runner (listcmd()): <command> given the test files <file>... in the form
# its runner (testrunner()) takes: go test, the package (folder) of each, as ./<folder> or ., in place of the word
# ./...; cargo test, --test <name> of each tests/<name>.rs, after `cargo test`. Else prints why the whole suite runs
# (exit 1): the command runs neither runner itself (or go test with no ./...), or a file is no test the runner can be
# given alone (a Go file not *_test.go; a Rust file not tests/<name>.rs, such as a helper module or a source file's
# own test module), as a run of less than the whole suite could skip it.
runnercmd() { # <command> <worktree> <file>...
  local c=$1 r f g a=()
  r=$(testrunner "$1" "$2") || r=''; shift 2
  case $r in
    'runner go'*)
      [[ " $c " == *' ./... '* ]] || { echo 'test.list is runner, and test.command has no ./... to put the packages in place of'; return 1; }
      for f; do
        [[ $f == *_test.go ]] || { echo "$f: go test takes packages, and this is no *_test.go file"; return 1; }
        if [[ $f == */* ]]; then a+=("./${f%/*}"); else a+=(.); fi
      done
      mapfile -t a < <(printf '%s\n' "${a[@]}" | sort -u)
      g=$(printf '%q ' "${a[@]}"); c=" $c "; c=${c// .\/... / ${g% } }; c=${c# }; printf '%s\n' "${c% }" ;;
    'runner cargo'*)
      g=${r#runner }
      [[ $c == *"$g"* ]] || { echo "test.list is runner, and test.command does not run $g itself"; return 1; }
      for f; do
        [[ $f =~ ^tests/[^/]+\.rs$ ]] || { echo "$f: cargo test takes test targets, and this is no tests/<name>.rs file"; return 1; }
        f=${f#tests/}; a+=(--test "$(printf %q "${f%.rs}")")
      done
      printf '%s\n' "${c/"$g"/"$g ${a[*]}"}" ;;
    *) echo 'test.list is runner, and test.command runs neither go test nor cargo test'; return 1 ;;
  esac
}
# The tests a card's change touches (its staged change against HEAD), one path a line after a first line that says how
# they were found, {by: "map" or "name", age} (age: the commits the made test map is behind, lib/testmap.sh mapread(),
# with one; else null): of each changed file, a document (.md, .txt, .rst) selects none; a test file (testpaths())
# selects itself, while it is there, and the test files .conveyor/test-links.json links to it (the project's own
# links, those still there); else a source the test map marks as shared by most tests selects the whole suite, links
# or not; else the tests the map says cover it and those its links name (those still there) are its tests (by map,
# when the map names one); else, a test file that is gone selects none; else a test file that is shared (shared(),
# below) selects the whole suite, as does any other file at the root, shared or with a config extension; else the
# test files whose name holds its name (no extension) as a word, the nearest by folder (those that share the most leading folders with it). A file of which none of these finds a test,
# a change that selects none, or a test map that cannot be read, runs the whole suite: it fails then, and prints why
# in place of the list.
testsel() { # <worktree>
  local out tm
  tm=$(mapread "$1") || { printf '%s\n' "$tm"; return 1; }
  out=$(jq -rn "$RX"'def ls: split("\n") | map(select(. != ""));
      def base: split("/")[-1]; def dir: split("/")[:-1];
      def stem: base | sub("\\.[^.]*$"; "");
      # A helper, setup, fixture or mock file (or one in a folder of such a name), that many tests may read.
      def shared: test("(^|/)(__mocks__|__fixtures__|fixtures?|helpers?|support|testdata|mocks?)/"; "i")
        or (base | test("^setup"; "i") or (sub("\\.[^.]*$"; "") | ascii_downcase | split("[._-]"; null)
          | any(IN("helper", "helpers", "setup", "fixture", "fixtures", "mock", "mocks", "conftest", "globals"))));
      def config: test("\\.(json|ya?ml|toml|ini|cfg|conf|lock)$"; "i") or (base | test("(^|[._-])config([._-]|$)"; "i"));
      def common($a; $b): [range([$a, $b] | map(length) | min) | select($a[.] != $b[.])] | first // ([$a, $b] | map(length) | min);
      ($ch | ls) as $ch | ($ct | ls | INDEX(.)) as $ct | ($all | ls) as $all | ($all | INDEX(.)) as $have
      | ($map[0] // {} | if type == "object" then . else {} end) as $map
      | ($tm.shared // [] | INDEX(.)) as $sh
      | [$ch[] | . as $p
         | ([$map[$p] | arrays[] | strings | select($have[.])]) as $m
         | ([$tm.sources[$p] // [] | .[] | select($have[.])]) as $c
         | if test("\\.(md|txt|rst)$"; "i") then []
           elif $ct[$p] and $have[$p] and (shared | not) then [$p] + $m
           elif $sh[$p] then {whole: "\($p): shared by most tests (map)"}
           elif $c != [] then {map: ($m + $c)}
           elif $m != [] then $m
           elif $ct[$p] and ($have[$p] | not) then []
           elif $ct[$p] or (contains("/") | not) or shared or config then {whole: "\($p): shared setup or config"}
           else (stem | rx) as $s | dir as $d
             | [$all[] | select($s != "" and (base | test("(^|[._-])" + $s + "([._-]|[A-Z]|$)"))) | {t: ., n: common(dir; $d)}]
             | if . == [] then {whole: "\($p): no test found for it"} else (map(.n) | max) as $n | map(select(.n == $n) | .t) end end]
      | (map(objects | select(.whole)) | first) as $w | . as $l
      | if $w then error($w.whole) else [.[] | if type == "array" then .[] else .map[] end] | unique
        | if . == [] then error("the change touches no test") else {by: (if any($l[]; type == "object") then "map" else "name" end), age: $tm.age} as $b
          | ($b | tojson), .[] end end' --argjson tm "${tm:-null}" \
    --rawfile ch <(git -C "$1" -c core.quotePath=false diff --cached --name-only --no-renames HEAD -- 2>/dev/null) \
    --rawfile ct <(git -C "$1" -c core.quotePath=false diff --cached --name-only --no-renames HEAD -- 2>/dev/null | testpaths) \
    --rawfile all <(git -C "$1" -c core.quotePath=false ls-files 2>/dev/null | testpaths) \
    --slurpfile map <(jq -c . "$1/.conveyor/test-links.json" 2>/dev/null || :) 2>&1) \
    || { out=${out#jq: error (at <unknown>): }; printf '%s\n' "${out:-the list of tests could not be made}"; return 1; }
  printf '%s\n' "$out"
}
# The part of a test line that says the run went again (tests()): {rerun: {exit, failures}} of the first run, else {};
# on a pass line, with the reason "passed on re-run: " and what had not passed (each case as <file>: <case>), each
# of those a failure whose verdict is flaky (verdicts()).
firstrun() { # <worktree> [pass]
  jq -ce --arg p "${2:-}" "$NOTPASSED"'. as $x | {rerun: $x} + if $p == "" then {} else
    {reason: ("passed on re-run: " + ($x | notpassed | if . == [] then "exit \($x.exit)" else join(", ") end)),
     verdicts: [$x | notpassed[] | {case: ., verdict: "flaky"}]} end' "$1.first" 2>/dev/null || echo '{}'
}
# What did not pass in a first run (<worktree>.first, {exit, failures}): each case as <file>: <case>, a file that failed
# naming no case or ran out of time as the file alone; each once.
NOTPASSED='def notpassed: [.failures.files[] | .file as $f | if .cases == [] then $f else .cases[] | "\($f): \(.name)" end]
  + [.failures.timeout.file // empty] | unique;'
# Before a card's failure goes to its fix session (card()), what still did not pass after the run again runs on main
# (the owner, 2026-11-14: a fix session cannot repair main or the machine): in a worktree of main's commit as it is now
# ($CARDS/mainrun/<card>), on a test slot, with the card's own command (test.command), its list (CONVEYOR_TEST_RERUN)
# naming every other file of the card's runs as passed (those of its last run, and those its own list names) and, of a
# file with failing cases, those cases; a file that failed naming no case or ran out of time, as `fail\t<file>` with no
# case (the command runs it whole: on main's clean tree nothing else selects it). Each failure's
# verdict, as notpassed() names it:
# - main: the same case (or the same file failing naming no case) failed on main too. A timeout or a kill on main says
#   nothing of the case.
# - card: it passed on main, or main's run did not run it (its worktree could not be made, or the command did not
#   select it): the card's to fix, as before.
# - flaky: it failed on the first run and passed on the run again (PASSEDAGAIN; flakyrun() records it).
# Prints the test line's part: {verdicts: [{case, verdict}]} and, when the cases ran on main, mainRun: {sha, sec (the
# seconds main's run took, its wait for a slot included), exit}. Each case whose verdict is main goes to the fix card of main's commit (mainred()).
# The card's own TEST_WAIT, TEST_RUN and TEST_FREE are kept (testrec()).
verdicts() { # <card> <worktree> <testfails() of the card's last run, or null>
  local mwt=$CARDS/mainrun/${2##*/} sha='' u m=null mf=null s rc out='' fst v c f w=$TEST_WAIT r=$TEST_RUN fr=$TEST_FREE
  # The units that still did not pass, each {file, case}: case null for a file that failed naming no case or ran out of time.
  u=$(jq -c '[.files[] | .file as $f | if .cases == [] then {file: $f, case: null} else .cases[] | {file: $f, case: .name} end]
    + [.timeout.file // empty | {file: ., case: null}] | unique' <<<"$3" 2>/dev/null) || u='[]'
  if [ "$u" != '[]' ]; then
    if sha=$(git rev-parse -q --verify "refs/heads/$BRANCH^{commit}" 2>/dev/null) \
      && out=$({ git worktree remove --force "$mwt" 2>/dev/null; rm -rf "$mwt" "$mwt".*; git worktree prune; mkdir -p "${mwt%/*}" \
        && git worktree add -q --detach "$mwt" "$sha" && deps "$mwt"; } 2>&1 < /dev/null) \
      && jq -r --argjson u "$u" --rawfile k <(awk -F'\t' '$1 == "pass" || $1 == "ok" || $1 == "fail" {print $2}' "$2.rerun" 2>/dev/null) \
        '([.passed[]?, .files[]?.file, .okcases[]?.file, .passcases[]?.file, (.timeout.file // empty), ($k | split("\n")[] | select(. != ""))]
          | unique - [$u[].file] | .[] | "pass\t\(.)"),
        ($u[] | if .case == null then "fail\t\(.file)" else "fail\t\(.file)\t\(.case)" end)' <<<"$3" > "$mwt.rerun"; then
      s=$SECONDS; tests "$mwt" test.command alone; rc=$?; s=$((SECONDS - s))
      # A run that passed failed nothing (testfails() names a command that wrote no log as a file whatever its exit).
      if [ $rc = 0 ]; then mf='{"files":[]}'; else mf=$(testfails "$mwt.test" "$rc") || mf=null; fi
      m=$(jq -cn --arg sha "$sha" --argjson s "$s" --argjson rc "$rc" '{sha: $sha, sec: $s, exit: $rc}')
    else
      echo "conveyor: card $1: its failing cases could not be run on main: ${out:-the commit of main could not be read}" >&2
    fi
    git worktree remove --force "$mwt" 2>/dev/null; rm -rf "$mwt" "$mwt".*; rmdir "${mwt%/*}" 2>/dev/null # the folder, once no card's run is in it
  fi
  TEST_WAIT=$w; TEST_RUN=$r; TEST_FREE=$fr
  fst=$(jq -ce objects "$2.first" 2>/dev/null) || fst=null
  v=$(jq -cn --argjson u "$u" --argjson m "${mf:-null}" --argjson l "${3:-null}" --argjson fst "$fst" "$NOTPASSED$PASSEDAGAIN"'
    [($fst | select(. != null) | passedagain($l)[] | {case: ., verdict: "flaky"}),
     ($u[] | . as $x | {case: (if .case == null then .file else "\(.file): \(.case)" end), file,
       verdict: (if $m != null and any($m.files[]?; .file == $x.file and (if $x.case == null then .cases == [] else any(.cases[]; .name == $x.case) end))
         then "main" else "card" end)})]') || v='[]'
  while IFS=$'\t' read -r c f; do mainred "$1" "$c" "$f" "$sha" || :; done < <(jq -r '.[] | select(.verdict == "main") | [.case, .file] | @tsv' <<<"$v")
  jq -cn --argjson v "$v" --argjson m "$m" '{verdicts: [$v[] | {case, verdict}]} + if $m then {mainRun: $m} else {} end'
}
# The bug-card check (card(): a card whose issue has the pack's type label, labels.type, after its build and before its
# review). The test files its staged change adds or changes (paths testpaths() takes for test files: the pack's
# tests.patterns) run on main's code without the
# fix: in a worktree of the commit the card was built on (its HEAD), $CARDS/mainrun/<card>.unfixed, holding those
# files alone, staged, on a test slot, with the card's own command (test.command), which selects them as that change's
# tests; or, when the pack sets test.fileCommand, each of them alone with that command (tests()). At least one must
# fail there: a test that passes without the fix does not prove it. A product file whose change adds or changes tests
# written inside it (the pack's tests.inline: inlinekinds(), inlinesplit()) is one of those files, staged with its
# test lines changed and the rest of its change (the fix) taken out; when such a test shares a changed line with the
# fix and the change has no other test, the check fails with that reason (SHARED), unrun. Writes the result in
# <worktree>.unfixed, which the review is shown, and fails when the check does not hold: the change adds or changes no
# test file, or no test failed in their run on main (it passed, or only its runner failed it). BUGWHY is the reason,
# which card() gives the build session and the block: "the new tests pass without the fix" (UNFIXED) only when its
# test files ran without the fix; with none found it names the patterns (NOTEST). Test files the command, given them,
# selected none of (its run ended "nothing selected") could not be run alone: the check fails with exit 2 and says
# so (NOTALONE), as a build session cannot change the pack. A failed run on main
# that gave no result for one of those files (noresult(): no pass and no fail of it) proves nothing either way: it runs
# once more, and when that run gives none either, the result's first line is "the proof run on main gave no result for
# <file>: <the run's last lines>" and the check fails with exit 2 (the card is blocked, as a build session cannot
# repair the runner). A run that cannot be made (no worktree, or the files do not apply) fails
# nothing, as a build session cannot repair it (but for a change with no test file, which fails as before): the result says so. A change to test files alone (a test fix for a
# red main) is not run and fails nothing: with no fix to take out, its tests run on the same code and pass. The result
# says it is test-only, and the review judges its tests.
# A change that selects no test of its own (the command, run on main's code with the whole change staged, ended
# "nothing selected": every changed line is a comment, or it touches no code the command knows) is proved by the test
# files the issue's `## Done when` section names that are test files of that commit (testpaths()): each named in the
# command's list (CONVEYOR_TEST_RERUN) as `fail<TAB><file>`, so the command (or test.fileCommand) runs them
# alone, with the fix and then without it. At least one must fail without it, and they must pass with it. When the
# issue names none, the check is skipped and holds: the result and the card's `bugproof` line (result skipped) say why.
# That selection run is made only when the change adds or changes no test file, or its test files' run selected nothing.
# The command of a run with the pack's test.fileCommand (tests()): each file its list (CONVEYOR_TEST_RERUN) names
# `fail`, in order, runs alone with that command, the file's path added as its last argument and in CONVEYOR_TEST_FILE.
# It logs each as a runner does (`== <file>`, then `-- ok <file>` or `-- FAIL <file>`, and `TESTRUN files=<n>`), so the
# run is read as any other (testfails()); it fails when a file fails.
filecmd() { # <the pack's test.fileCommand>
  local q; q=$(printf %q "$1")
  printf '%s\n' 'n=0 r=0; l=$CONVEYOR_TEST_LOG/files' \
    'while IFS=$'"'"'\t'"'"' read -r k f _; do' \
    '  [ "$k" = fail ] || continue; n=$((n + 1)); echo "== $f" | tee -a "$l"' \
    "  if CONVEYOR_TEST_FILE=\$f bash -c $q'"' "$CONVEYOR_TEST_FILE"'"' < /dev/null; then echo \"-- ok \$f\" | tee -a \"\$l\"; else echo \"-- FAIL \$f\" | tee -a \"\$l\"; r=1; fi" \
    'done < "${CONVEYOR_TEST_RERUN:-/dev/null}"' \
    'echo "TESTRUN files=$n" >> "$l"; exit $r'
}
# One run of the bug-card check with the pack's command <field>, in <worktree>: given files, it runs them alone, each a
# `fail` line of the run's list (CONVEYOR_TEST_RERUN); given none, the command selects the staged change's tests.
bugrun() { # <worktree> <field> [<file>...]
  local w=$1 f=$2; shift 2
  [ $# != 0 ] || { tests "$w" "$f"; return; }
  printf 'fail\t%s\n' "$@" > "$w.rerun" && tests "$w" "$f" alone
}
# Tests inside product files (#140): the pack's tests.inline (the schema's default kinds, with the pack's added; one of
# the same name replaces the default's). Of the staged change's added or changed files that are not test files
# (testpaths()), each that a kind's files match, as <path> NUL <kind json> NUL. Fails when the pack cannot be read.
inlinekinds() { # <worktree>
  local t
  packget tests.inline t || return 1
  git -C "$1" diff --cached --name-only --no-renames --diff-filter=AM -z HEAD -- 2>/dev/null | testpaths -vz \
    | jq -jRs --argjson t "$t" --argjson d "$(jq -c '.properties.tests.properties.inline.default' <<<"$SCHEMA_T")" "$GLOBRX"'
      ($d + $t) as $k | split("\u0000")[] | select(. != "") as $f
      | first($k[] | (.files | globsrx) as $r | select($f | test($r))) | ($f, tojson) | . + "\u0000"'
}
# Each line of a file (stdin) as T (in a test block of the kind IS, IE, IH: start, end and has), N (not in one) or S (in
# one, and holding code outside it: before its start or after its end). A block starts at IS's match; with IE
# "braces" it ends where the brackets opened after the start close, or at a ; before any opens; else it ends at IE's
# match. A block none of whose lines match IH (when set) is no test. Brackets inside strings are counted too.
# shellcheck disable=SC2016 # awk's own $0 and fields
INLINEMARKS='BEGIN { s = ENVIRON["IS"]; e = ENVIRON["IE"]; h = ENVIRON["IH"]; br = (e == "braces") }
function shut(last, tail,   i, t) {
  t = (h == "" || hit) ? "T" : "N"; for (i = b; i <= last; i++) c[i] = t
  if (t == "T" && (lead || tail)) { c[b] = (lead ? "S" : c[b]); if (tail) c[last] = "S" }
  inb = 0
}
{ c[NR] = "N"
  if (!inb) {
    if (!match($0, s)) next
    inb = 1; b = NR; hit = 0; d = 0; op = 0
    lead = (substr($0, 1, RSTART - 1) ~ /[^[:space:]]/); rest = substr($0, RSTART + RLENGTH)
  } else rest = $0
  if (h != "" && $0 ~ h) hit = 1
  if (br) {
    for (i = 1; i <= length(rest); i++) {
      ch = substr(rest, i, 1)
      if (ch == "{") { d++; op = 1 } else if (ch == "}") d--
      if ((op && d <= 0) || (ch == ";" && !op)) { t = substr(rest, i + 1); shut(NR, t ~ /[^[:space:]]/ && t !~ /^[[:space:]]*\/\//); next }
    }
  } else if (match(rest, e)) shut(NR, substr(rest, RSTART + RLENGTH) ~ /[^[:space:]]/)
}
END { if (inb) shut(NR, 0); for (i = 1; i <= NR; i++) print c[i] }'
# The staged file <path> of <worktree> with the fix taken out. Each line of main's file (HEAD) and of the staged one is
# marked (INLINEMARKS, by <kind json>). The fix is the diff of main's code lines (N) to the staged code lines; the
# staged file with that diff undone keeps the change's test lines and none of its code. Exit 0 when the change adds or
# changes a test line (T), printing that file; 1 when it changes none (or a file cannot be read); 3, printing nothing,
# when a line it changes is shared by a test block and code (S): the fix cannot be taken out alone.
inlinesplit() { # <worktree> <path> <kind json>
  local w=$1 f=$2 d k=() rc
  mapfile -d '' -t k < <(jq -j '.start, .end, (.has // "") | . + "\u0000"' <<<"$3") && [ ${#k[@]} = 3 ] && d=$(mktemp -d) || return 1
  { git -C "$w" show "HEAD:$f" 2>/dev/null || :; } > "$d/old" && git -C "$w" show ":$f" > "$d/new" 2>/dev/null \
    && IS=${k[0]} IE=${k[1]} IH=${k[2]} awk "$INLINEMARKS" < "$d/old" > "$d/old.m" \
    && IS=${k[0]} IE=${k[1]} IH=${k[2]} awk "$INLINEMARKS" < "$d/new" > "$d/new.m" || { rm -rf "$d"; return 1; }
  # Which kinds of line the change touches: a test line it adds or changes, a shared line it adds, changes or removes.
  # A diff --no-index exits 1 when the files differ, which under pipefail would fail the pipe: only a higher exit does.
  { git diff --no-index --no-color --no-ext-diff -U"$(( $(wc -l < "$d/old") + $(wc -l < "$d/new") + 1 ))" -- "$d/old" "$d/new"; [ $? -le 1 ]; } \
    | awk 'FILENAME == ARGV[1] { o[FNR] = $0; next } FILENAME == ARGV[2] { n[FNR] = $0; next }
      /^@@/ { h = 1; next } !h || /^\\/ { next }
      { t = substr($0, 1, 1) } t == " " { oi++; ni++ } t == "-" { if (o[++oi] == "S") sh = 1 }
      t == "+" { ni++; if (n[ni] == "S") sh = 1; else if (n[ni] == "T") nt++ }
      END { exit sh ? 3 : nt ? 0 : 1 }' "$d/old.m" "$d/new.m" -
  rc=$?
  if [ $rc = 0 ]; then
    awk 'FILENAME == ARGV[1] { m[FNR] = $0; next } m[FNR] == "N"' "$d/old.m" "$d/old" > "$d/old.c"
    awk 'FILENAME == ARGV[1] { m[FNR] = $0; next } m[FNR] == "N"' "$d/new.m" "$d/new" > "$d/new.c"
    # Each hunk of the fix (-U0: staged code lines c to c+n-1 were main's lines, or main's lines go after line c when n
    # is 0) undone in the staged file, its test lines kept where they are.
    { git diff --no-index --no-color --no-ext-diff -U0 -- "$d/old.c" "$d/new.c"; [ $? -le 1 ]; } \
      | awk 'function put(x,   i) { for (i = 1; i <= on[x]; i++) print ol[x, i] }
        FILENAME == ARGV[1] { m[FNR] = $0; next } FILENAME == ARGV[2] { nl[FNR] = $0; nn = FNR; next }
        /^@@/ { split($3, p, ","); h++; hs[h] = substr(p[1], 2) + 0; hd[h] = (p[2] == "" ? 1 : p[2] + 0); next }
        h && /^-/ { ol[h, ++on[h]] = substr($0, 2) }
        END {
          for (x = 1; x <= h; x++) if (hd[x]) { for (j = hs[x]; j < hs[x] + hd[x]; j++) rep[j] = x } else ins[hs[x]] = x
          if (0 in ins) put(ins[0])
          j = 0
          for (i = 1; i <= nn; i++) {
            if (m[i] != "N") { print nl[i]; continue }
            j++
            if (j in rep) { if (!(rep[j] in done)) { done[rep[j]] = 1; put(rep[j]) } } else print nl[i]
            if (j in ins) put(ins[j])
          }
        }' "$d/new.m" "$d/new" - || rc=1
  fi
  rm -rf "$d"; return $rc
}
bugproof() { # <card> <worktree> <issue json>
  local mwt=$CARDS/mainrun/$1.unfixed fs=() tf=() ins=() iks=() nf=() fl=() f k out rc fx held='' sha='' why nr='' fc='' fld alone='' sh=''
  rm -f "$2.unfixed"; BUGWHY=$UNFIXED
  # No change at all (an ALREADY-DONE) is not checked: it goes its own way (nochange()).
  git -C "$2" add -A 2>/dev/null && ! git -C "$2" diff --cached --quiet HEAD 2>/dev/null || return 0
  # A change to test files alone (every changed path, deleted ones too, is a test file: testpaths()) has no fix to take out:
  # its tests would run on the same code and pass, so it is not run. The review is told, and judges the tests.
  # The paths are counted, not tested with grep -q: under pipefail its early exit could fail the pipe and pass a change
  # with a source file as test-only. A diff that cannot be read, or a pack that cannot, counts as a change with one.
  if out=$(git -C "$2" diff --cached --name-only --no-renames -z HEAD -- 2>/dev/null | testpaths -vz | tr -cd '\000' | wc -c) \
    && [ "$((out))" = 0 ]; then
    { echo 'The change is test-only: every file it changes is a test file, so it has no fix to take out, and its tests were not run on main'"'"'s code.'
      echo 'Judge whether each test it changes still checks what it was written to check.'; } > "$2.unfixed"
    return 0
  fi
  mapfile -d '' -t tf < <(git -C "$2" diff --cached --name-only --no-renames --diff-filter=AM -z HEAD -- 2>/dev/null | testpaths -z)
  # Product files whose change adds or changes inline tests (inlinekinds(), inlinesplit()) run too, with only their
  # test lines changed: the fix taken out. One whose test shares a changed line with the fix cannot be run so; when the
  # change has no other test to run, that is the reason (SHARED), and no run is made.
  while IFS= read -r -d '' f && IFS= read -r -d '' k; do
    inlinesplit "$2" "$f" "$k" > /dev/null; case $? in 0) ins+=("$f") iks+=("$k") ;; 3) sh=${sh:-$f} ;; esac
  done < <(inlinekinds "$2" 2>/dev/null)
  fs=("${tf[@]}" "${ins[@]}")
  if [ ${#fs[@]} = 0 ] && [ -n "$sh" ]; then
    BUGWHY=${SHARED//'<file>'/"$sh"}; printf '%s.\nIts inline tests were not run on main'"'"'s code.\n' "${BUGWHY^}" > "$2.unfixed"; return 1
  fi
  [ ${#fs[@]} != 0 ] || { [ -n "${TESTGLOBS:-}" ] || names 2>/dev/null; BUGWHY=${NOTEST//'<patterns>'/"${TESTGLOBS:-}"}; }
  # A per-file command (test.fileCommand) runs each test file alone, whatever its language, as the list names it.
  packget test.fileCommand fc 2>/dev/null || fc=''
  fld=test.command fl=(); [ -z "$fc" ] || { fld=test.fileCommand fl=("${fs[@]}"); }
  if sha=$(git -C "$2" rev-parse -q --verify 'HEAD^{commit}' 2>/dev/null) \
    && out=$({ git worktree remove --force "$mwt" 2>/dev/null; rm -rf "$mwt" "$mwt".*; git worktree prune; mkdir -p "${mwt%/*}" \
      && git worktree add -q --detach "$mwt" "$sha" && deps "$mwt" \
      && { [ ${#tf[@]} = 0 ] || git -C "$2" diff --cached --binary --no-renames HEAD -- "${tf[@]/#/:(literal)}" | git -C "$mwt" apply --index; } \
      && for k in "${!ins[@]}"; do
           mkdir -p "$(dirname "$mwt/${ins[k]}")" && inlinesplit "$2" "${ins[k]}" "${iks[k]}" > "$mwt/${ins[k]}" \
             && git -C "$mwt" add -- ":(literal)${ins[k]}" || exit 1
         done; } 2>&1 < /dev/null); then
    if [ ${#fs[@]} = 0 ]; then
      printf '%s.\n' "${BUGWHY^}" > "$2.unfixed"
    else
      bugrun "$mwt" "$fld" "${fl[@]}"; rc=$?
      ! testfailed "$mwt" "$rc" || held=1
      # A failed run that proved nothing and gave no result for a file it was given (noresult()) says nothing either
      # way: it runs once more, and when that run gives none either the card is blocked with that reason (exit 2).
      if [ -z "$held" ] && nr=$(noresult "$mwt" "$rc" "${fs[@]}"); then
        bugrun "$mwt" "$fld" "${fl[@]}"; rc=$?
        ! testfailed "$mwt" "$rc" || held=1
        [ -z "$held" ] && nr=$(noresult "$mwt" "$rc" "${fs[@]}") || nr=''
      fi
      # A run given the files that selected none of them did not run them: it is no run without the fix, and the
      # reason is the result's first line, as the block (card()) shows it.
      [ "$rc" != 0 ] || [ "$(testrec "$mwt" "$rc" 0 | jq -r .ended)" != 'nothing selected' ] || { alone=1; BUGWHY=$NOTALONE; }
      { [ -z "$nr" ] || printf 'the proof run on main gave no result for %s: %s\n' "$nr" \
          "$(tail -n 5 "$mwt.test" 2>/dev/null | tr -d '\000\r' | sed 's/\x1b\[[0-9;]*m//g' | awk 'NF { sub(/^[ \t]+/, ""); s = s (s == "" ? "" : " / ") $0 } END { print substr(s, 1, 300) }')"
        [ -z "$alone" ] || printf '%s\n' "$NOTALONE"
        printf 'Its test files, %s on main'"'"'s code at %s without the fix:\n' "$([ -n "$alone" ] && echo 'given to the test command' || echo run)" "$sha"
        [ ${#tf[@]} = 0 ] || printf -- '- %s\n' "${tf[@]}"; [ ${#ins[@]} = 0 ] || printf -- '- %s (its inline tests, with the rest of its change taken out)\n' "${ins[@]}"
        if [ -n "$alone" ]; then echo "The command selected none of them, so none ran without the fix."
        elif [ $rc = 0 ]; then echo "They all passed there: $UNFIXED."
        elif [ -n "$nr" ]; then echo "The run failed there twice (exit $rc), and gave no result for $nr either time, so it proves nothing either way."
        elif [ -z "$held" ]; then echo "The run failed there (exit $rc), but no test failed in it (its runner stopped it): $UNFIXED."
        else echo "The run failed there (exit $rc): at least one fails without the fix, as it should."; fi
        echo 'The end of that run'"'"'s output:'; echo '```'; tail -n 30 "$mwt.test" 2>/dev/null | tr -d '\000'; echo '```'; } > "$2.unfixed"
    fi
    # Does the change select any test of its own? Asked only when its test files proved nothing and selected nothing
    # (a run that selected a test that passed says the change is not one that selects none). Asked alone with no list,
    # so no file is kept off as passed before (cacheoff()): a code change whose tests were all kept off would select none.
    if [ -z "$held" ] && [ -z "$nr" ] && { [ ${#fs[@]} = 0 ] || [ "$(testrec "$mwt" "$rc" 0 | jq -r .ended)" = 'nothing selected' ]; } \
      && git -C "$mwt" reset -q --hard && rm -f "$mwt.rerun" \
      && git -C "$2" diff --cached --binary --no-renames HEAD | git -C "$mwt" apply --index 2>/dev/null \
      && { tests "$mwt" test.command alone; rc=$?; [ "$(testrec "$mwt" "$rc" 0 | jq -r .ended)" = 'nothing selected' ]; }; then
      # The files the issue names are the proof now, and its result replaces that of the change's own test files.
      alone=''; BUGWHY=$UNFIXED
      mapfile -t nf < <(jq -r '[.body // "" | splits("\r?\n")] as $l
        | ([range($l | length) | select($l[.] | test("^#{1,2}\\s+Done when\\s*$"; "i"))] | first) as $i | select($i != null)
        | $l[($i + 1):] | ((map(test("^#{1,2}\\s")) | index(true)) as $e | if $e == null then . else .[:$e] end)[]
        | scan("[^\\s`\"'"'"'(),;<>]+") | sub("::.*$"; "") | sub("(:[0-9]+(-[0-9]+)?)?[.,:;]*$"; "")' <<<"$3" 2>/dev/null \
        | LC_ALL=C sort -u | testpaths | while IFS= read -r f; do
            [[ $f != *$'\t'* ]] && [ "$(git -C "$mwt" cat-file -t "$sha:$f" 2>/dev/null)" = blob ] && printf '%s\n' "$f"
          done)
      if [ ${#nf[@]} = 0 ]; then
        why='the change selects no test (every changed line is a comment, or it touches no code the test command knows), and the issue'"'"'s Done-when names no test file'
        printf 'The bug-card check was skipped: %s.\n' "$why" > "$2.unfixed"; held=1
        record "$1" "$(jq -r '.number // 0' <<<"$3")" bugproof skipped "$(jq -cn --arg r "$why" '{reason: $r}')"
      else
        # With the fix (staged above), then without it: the named files alone, each a `fail` line of the list.
        bugrun "$mwt" "$fld" "${nf[@]}"; fx=$?
        # Main's code put back fails the check (rc empty): the logs left are those of the run with the fix.
        if git -C "$mwt" reset -q --hard; then bugrun "$mwt" "$fld" "${nf[@]}"; rc=$?; else rc=''; fi
        [ "$fx" != 0 ] || [ -z "$rc" ] || ! testfailed "$mwt" "$rc" || held=1
        { printf 'The change selects no test of its own (every changed line is a comment, or it touches no code the test command knows), so the test files its issue'"'"'s Done-when names were run alone on main'"'"'s code at %s, with the fix and without it:\n' "$sha"
          printf -- '- %s\n' "${nf[@]}"
          if [ "$fx" != 0 ]; then echo "They failed with the fix (exit $fx): $UNFIXED."
          elif [ -z "$rc" ]; then BUGWHY=$NOTBACK; echo "Main's code could not be put back without the fix, so they did not run without it."
          elif [ "$rc" = 0 ]; then echo "They all passed without the fix: $UNFIXED."
          elif [ -z "$held" ]; then echo "The run without the fix failed (exit $rc), but no test failed in it (its runner stopped it): $UNFIXED."
          else echo "They pass with the fix, and the run without it failed (exit $rc): at least one fails without the fix, as it should."; fi
          echo 'The end of the run without the fix:'; echo '```'; tail -n 30 "$mwt.test" 2>/dev/null | tr -d '\000'; echo '```'; } > "$2.unfixed"
      fi
    fi
  elif [ ${#fs[@]} = 0 ]; then
    printf '%s.\n' "${BUGWHY^}" > "$2.unfixed"
  else
    printf 'Its test files could not be run on main'"'"'s code at %s: %s\nThe check says nothing of them.\n' "${sha:-a commit that could not be read}" "${out:0:600}" > "$2.unfixed"
    held=1
  fi
  git worktree remove --force "$mwt" 2>/dev/null; rm -rf "$mwt" "$mwt".*; rmdir "${mwt%/*}" 2>/dev/null # the folder, once no card's run is in it
  [ -z "$nr$alone" ] || return 2
  [ -n "$held" ]
}
# The test file of a speed-up issue (card()): an issue whose title starts SPEEDUP (or the title start given: OPTIMIZE),
# as the Board's Tests page files it (`conveyor.sh testissue`). The file is the one that filing kept for the issue
# ($TAFILED), else the title's word after that start. Prints it; fails for any other issue.
# shellcheck disable=SC2034 # OPTIMIZE is used in lib/card.sh
SPEEDUP='Speed up the test file ' OPTIMIZE='Optimize the test file '
speedfile() { # <issue json> [title start: SPEEDUP]
  local t f p=${2:-$SPEEDUP}
  t=$(jq -r '.title // ""' <<<"$1"); [[ $t == "$p"* ]] || return 1
  f=$(jq -rRn --argjson n "$(jq -r '.number // 0' <<<"$1")" '[inputs | fromjson? | objects | select(.event == "filed" and .issue == $n) | .file | strings] | last // empty' "$TAFILED" 2>/dev/null)
  [ -n "$f" ] || { f=${t#"$p"}; f=${f%%[[:space:]]*}; }
  [ -n "$f" ] && printf '%s\n' "$f"
}
# The check of a speed-up card (card(): a bug card whose issue speedfile() names a test file), in place of the bug-card
# check (bugproof()): a speed-up keeps what the file tests, so its tests pass on main's code by design. The file runs
# alone, on a test slot, with the pack's test.command, in a worktree of the commit the card was built on with the whole
# staged change ($CARDS/mainrun/<card>.speed). It must pass, and its CPU seconds there (its runner's `TESTRUN sec` line,
# timed()) must be lower than its median on record (the Tests page's, testspart()). Writes the result in
# <worktree>.unfixed, which the review is shown, its first line the reason when the check does not hold, and records a
# bugproof line (result ok or fail) with speed: {file, before: the median, after: the CPU seconds now; each null when
# not known; fix: sped up, or split, with into: the test files the split adds}. Fails when the check does not hold: no median on record, a run that could not be made, failed or gave no
# CPU seconds, or CPU seconds not lower than the median. Given the test files a split adds (optproof()), it runs them
# too, with the file when the change keeps it: they must all pass, and their CPU seconds summed (after) must be lower
# than the file's median.
speedproof() { # <card> <worktree> <issue json> <test file> [<test file the change adds>...]
  local mwt=$CARDS/mainrun/$1.speed f=$4 out='' rc='' sha before after='' why='' run=() l
  rm -f "$2.unfixed"
  # No change at all (an ALREADY-DONE) is not checked: it goes its own way (nochange()).
  git -C "$2" add -A 2>/dev/null && ! git -C "$2" diff --cached --quiet HEAD 2>/dev/null || return 0
  before=$(testspart "$(date +%F)" 2>/dev/null | jq -r --arg f "$f" 'first(.files[]? | select(.file == $f) | .median | numbers) // empty' 2>/dev/null)
  if [ -z "$before" ]; then why="the file $f has no CPU seconds on record to compare with"
  elif sha=$(git -C "$2" rev-parse -q --verify 'HEAD^{commit}' 2>/dev/null) \
    && out=$({ git worktree remove --force "$mwt" 2>/dev/null; rm -rf "$mwt" "$mwt".*; git worktree prune; mkdir -p "${mwt%/*}" \
      && git worktree add -q --detach "$mwt" "$sha" && deps "$mwt" \
      && git -C "$2" diff --cached --binary --no-renames HEAD | git -C "$mwt" apply --index; } 2>&1 < /dev/null); then
    # A split whose change removes the file runs the files it adds alone.
    [ $# -gt 4 ] && [ ! -e "$mwt/$f" ] || run=("$f"); run+=("${@:5}")
    l=$(printf '%s, ' "${run[@]}"); l=${l%, }
    printf 'fail\t%s\n' "${run[@]}" > "$mwt.rerun"; tests "$mwt" test.command alone; rc=$?
    after=$(timed "$mwt" 2>/dev/null | jq -r '[.[$ARGS.positional[]].cpu?] | if all(.[]; type == "number") then add else empty end' --args "${run[@]}" 2>/dev/null)
    if [ $# = 4 ]; then
      if [ "$rc" != 0 ]; then why="the file $f fails with the change (exit $rc)"
      elif [ -z "$after" ]; then why="the run of $f with the change gave no CPU seconds"
      elif ! jq -en --argjson a "$after" --argjson b "$before" '$a < $b' >/dev/null 2>&1; then why="the file is not faster: $before CPU s on record, $after CPU s now"; fi
    elif [ "$rc" != 0 ]; then why="the files of the split, $l, fail with the change (exit $rc)"
    elif [ -z "$after" ]; then why="the run of the files of the split, $l, with the change gave no CPU seconds for each"
    elif ! jq -en --argjson a "$after" --argjson b "$before" '$a < $b' >/dev/null 2>&1; then why="the files of the split are not faster: $f has $before CPU s on record, $l took $after CPU s now"; fi
  else why="the file $f could not be run with the change: ${out:0:300}"; fi
  { if [ -n "$why" ]; then printf '%s\n' "$why"
    elif [ $# = 4 ]; then printf 'This issue speeds up the test file %s, so no test must fail on main'"'"'s code. Run alone with the change, on a test slot, it passed in %s CPU s, lower than its median on record, %s CPU s.\n' "$f" "$after" "$before"
    else printf 'This change splits the test file %s, so no test must fail on main'"'"'s code. Run alone with the change, on a test slot, %s passed in %s CPU s summed, lower than the median on record of %s, %s CPU s.\n' "$f" "$l" "$after" "$f" "$before"; fi
    [ -z "$rc" ] || { echo 'The end of that run'"'"'s output:'; echo '```'; tail -n 30 "$mwt.test" 2>/dev/null | tr -d '\000'; echo '```'; }; } > "$2.unfixed"
  record "$1" "$(jq -r '.number // 0' <<<"$3")" bugproof "$(if [ -z "$why" ]; then echo ok; else echo fail; fi)" \
    "$(jq -cn --arg r "$why" --arg f "$f" --arg b "$before" --arg a "$after" '{reason: $r, speed: {file: $f, before: ($b | tonumber? // null), after: ($a | tonumber? // null),
      fix: (if $ARGS.positional == [] then "sped up" else "split" end), into: $ARGS.positional}}' --args "${@:5}")"
  git worktree remove --force "$mwt" 2>/dev/null; rm -rf "$mwt" "$mwt".*; rmdir "${mwt%/*}" 2>/dev/null # the folder, once no card's run is in it
  [ -z "$why" ]
}
# The check of an Optimize card (card(): a bug card whose issue speedfile() names with OPTIMIZE), in place of the
# bug-card check: the card speeds its test file up, splits it, merges it into another test file or deletes it, and
# keeps what it tests, so no test must fail on main's code. A change that keeps the file, or adds test files (a split),
# is checked as a speed-up (speedproof(), given the test files it adds). A change that removes the file and adds no
# test file (a delete, or a merge into a file main has) is not run: the file runs alone on the commit the card was built
# on, as it is there, and the review is told the cases its runner named (testfails()) and asked to name, for each, the
# test that still covers it, on a COVERED-BY line (the Tests page's, testspart(), for a delete). Its bugproof line is ok, with speed: {file, before: the median or null, after: null, fix:
# merged, into: the test files the change modifies, or, when it modifies none, deleted, into: []}.
# Returns as speedproof() does; a delete or merge never fails it.
optproof() { # <card> <worktree> <issue json> <test file>
  local mwt=$CARDS/mainrun/$1.speed f=$4 sha='' out='' rc='' before cs='' add=() into=()
  # No change at all (an ALREADY-DONE) is not checked: it goes its own way (nochange()).
  git -C "$2" add -A 2>/dev/null && ! git -C "$2" diff --cached --quiet HEAD 2>/dev/null || { rm -f "$2.unfixed"; return 0; }
  mapfile -t add < <(git -C "$2" diff --cached --name-only --no-renames --diff-filter=A HEAD 2>/dev/null | testpaths \
    | while IFS= read -r x; do [[ $x != "$f" ]] && printf '%s\n' "$x"; done)
  if [ -e "$2/$f" ] || [ ${#add[@]} != 0 ]; then speedproof "$@" "${add[@]}"; return; fi
  rm -f "$2.unfixed"
  mapfile -t into < <(git -C "$2" diff --cached --name-only --no-renames --diff-filter=M HEAD 2>/dev/null | testpaths)
  before=$(testspart "$(date +%F)" 2>/dev/null | jq -r --arg f "$f" 'first(.files[]? | select(.file == $f) | .median | numbers) // empty' 2>/dev/null)
  if sha=$(git -C "$2" rev-parse -q --verify 'HEAD^{commit}' 2>/dev/null) \
    && out=$({ git worktree remove --force "$mwt" 2>/dev/null; rm -rf "$mwt" "$mwt".*; git worktree prune; mkdir -p "${mwt%/*}" \
      && git worktree add -q --detach "$mwt" "$sha" && deps "$mwt"; } 2>&1 < /dev/null); then
    # The run is of the file alone: every case its runner names is the file's.
    printf 'fail\t%s\n' "$f" > "$mwt.rerun"; tests "$mwt" test.command alone; rc=$?
    cs=$(testfails "$mwt.test" "$rc" 2>/dev/null | jq -r '[(.passcases + .okcases)[]?.cases[]?, .files[]?.cases[]?.name | select(. != "")] | unique[]' 2>/dev/null)
  fi
  { printf 'This change removes the test file %s and adds no test file: it deletes the file, or merges it into another test file. No test must fail on main'"'"'s code for it, and it was not run with the change.\n' "$f"
    if [ -n "$cs" ]; then printf 'The cases %s held, as its runner named them in a run of it alone on main'"'"'s code at %s:\n' "$f" "$sha"; sed 's/^/- /' <<<"$cs"
    elif [ -n "$rc" ]; then printf 'Its runner named no case of it in a run of it alone on main'"'"'s code at %s (exit %s): read the file there for its cases.\n' "$sha" "$rc"
    else printf 'It could not be run alone on main'"'"'s code (%s): read the file there for its cases.\n' "${out:0:300}"; fi
    echo 'Name, for each of its cases, the test that still covers it after the change, each on its own line, exactly: `COVERED-BY: <its test file>: <its case>`. A case with no test named is a finding.'; } > "$2.unfixed"
  record "$1" "$(jq -r '.number // 0' <<<"$3")" bugproof ok "$(jq -cn --arg f "$f" --arg b "$before" '{reason: "", speed: {file: $f, before: ($b | tonumber? // null), after: null,
    fix: (if $ARGS.positional == [] then "deleted" else "merged" end), into: $ARGS.positional}}' --args "${into[@]}")"
  git worktree remove --force "$mwt" 2>/dev/null; rm -rf "$mwt" "$mwt".*; rmdir "${mwt%/*}" 2>/dev/null # the folder, once no card's run is in it
  return 0
}
# A run of the bug-card check (bugproof()) that is proof: it failed, and a test failed in it. With the runner's logs
# (testlogs()), they must name a file that failed (testfails()); an exit of the runner itself with no test failing (its
# own check refused the run) proves nothing. A command that writes no logs says no more than its exit.
testfailed() { # <worktree> <exit>
  [ "$2" != 0 ] && { [ -z "$(testlogs "$1")" ] || jq -e '.files != []' <<<"$(testfails "$1.test" "$2")" >/dev/null 2>&1; }
}
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
# A case that fails on main (verdicts()) goes to the fix card of main's commit, a card with no GitHub issue (issue 0;
# the owner, 2026-11-15: 13 issues filed in 9 hours, three by one landing): one card per broken main commit, holding
# every case that fails there. $MAINRED keeps {reds: [{sha, cases: [{case, file, by, files, last}], card}]}: by, the
# card that found the case; files, the case's files; last, the last commit that changed them ("%h %s"); card, the fix
# card, null until the loop picks it (redpick()). One writer at a time (a lock of its own). A case found failing on a
# commit that has an entry is added to it, while its card runs too (its brief and commit are made from the entry as
# they are made: redissue()); one an open fix card of an earlier commit holds (redopen()) starts nothing; else the
# commit gets an entry of its own, which the loop picks ahead of the queue. When the case's file is one file and the
# landing that broke it is known (brokeby()), the case's entry keeps it (landing: {sha, card, issue}), the brief names
# it, and the entry keeps the links its fix card commits (links: testlinks()).
MAINRED=${STATE%/*}/mainred.json
mainred() { # <card> <case> <its file> <main's commit>
  local lock rec c t k re f fs by
  [ -n "$4" ] || return 1
  { exec {lock}>>"$MAINRED.lock"; } 2>/dev/null || { echo "conveyor: the main-is-red record could not be locked; $2 goes to no fix card" >&2; return 1; }
  flock "$lock" || { exec {lock}>&-; echo "conveyor: the main-is-red record could not be locked; $2 goes to no fix card" >&2; return 1; }
  rec=$(jq -ce '.reds | arrays' "$MAINRED" 2>/dev/null) || rec='[]'
  if ! jq -e --arg s "$4" 'any(.[]; .sha == $s)' <<<"$rec" >/dev/null; then
    while read -r c; do
      redopen "$c" || continue
      exec {lock}>&-; return 0
    done < <(jq -r --arg c "$2" '.[] | select(any(.cases[]; .case == $c)) | .card // ""' <<<"$rec")
  elif jq -e --arg s "$4" --arg c "$2" 'any(.[]; .sha == $s and any(.cases[]; .case == $c))' <<<"$rec" >/dev/null; then
    exec {lock}>&-; return 0
  fi
  # The case's file: a runner (the engine's conveyor/conveyor.test.sh) names its cases' failures as its own, so the
  # test files at main's commit that define the case (`t_<case>()`, `<case>()` or the name quoted), the named file
  # alone when it is one of them; else the named file (a failure naming no case, or one no test file defines).
  k=${2#"$3: "}; [ "$k" != "$2" ] || k=''
  fs=()
  if [ -n "$k" ]; then
    re=$(sed 's/[][\\.*^$+?(){}|/]/\\&/g' <<<"$k")
    mapfile -t fs < <(git grep -lE -e "(^|[^[:alnum:]_])(t_)?$re\\(\\)|['\"]$re['\"]" "$4" -- '*.test.*' 2>/dev/null | sed "s/^$4://")
    for f in "${fs[@]}"; do [ "$f" != "$3" ] || { fs=("$3"); break; }; done
  fi
  [ ${#fs[@]} -gt 0 ] || [ -z "$3" ] || fs=("$3")
  t=''; [ ${#fs[@]} = 0 ] || t=$(git log -1 --format='%h %s' "$4" -- "${fs[@]}" 2>/dev/null)
  by=null; [ ${#fs[@]} != 1 ] || by=$(brokeby "${fs[0]}" "$4" "$3" "$k" | jq -ce objects 2>/dev/null) || by=null
  jq -c --arg s "$4" --arg c "$2" --arg f "$3" --arg by "$1" --arg t "$t" --argjson b "$by" --args '({case: $c, file: $f, by: $by, files: $ARGS.positional, last: $t}
      + if $b == null then {} else {landing: ($b | {sha, card, issue}), links: $b.links} end) as $x
    | {reds: (if any(.[]; .sha == $s) then map(if .sha == $s then .cases += [$x] else . end) else . + [{sha: $s, cases: [$x], card: null}] end | .[-100:])}' \
    "${fs[@]}" <<<"$rec" > "$MAINRED.new" && mv -f "$MAINRED.new" "$MAINRED" \
    || { exec {lock}>&-; echo "conveyor: main is red: $2: the main-is-red record could not be written" >&2; return 1; }
  exec {lock}>&-
}
# The landing that broke a test file on main without its card running it (issue 598; mainred()): of main's commits
# up to <main's commit>, newest first, back to the last landing whose card's test step ran the file (its test lines
# name it in why or times, or say the whole engine suite ran, for an engine case file, or its ranCases name <case>
# under the file its run named it under: a run of only some cases of the file, issue 604) and so passed it, the first
# landing after that one. Prints {sha, card, issue, links: {<each file that landing changed>: [<test file>]}}; fails
# when no landing ran the file in the last TESTLINK_DEPTH commits (when it last passed is not known) or none is after it.
TESTLINK_DEPTH=500
brokeby() { # <test file> <main's commit> [<the file its run named the case under> <case>]
  local l s by='' ran='' card iss
  l=$(stdb ask lines cards 2>/dev/null | jq -rs --arg f "$1" --arg r "${3:-}" --arg c "${4:-}" '(map(select(.step == "test")) | group_by(.card)
      | map({key: .[0].card, value: any(.[]; (.why // {} | has($f)) or (.times // {} | has($f))
        or (.wholeSuite == true and ($f | startswith("conveyor/tests/")))
        or ($c != "" and any(.ranCases // {} | objects | .[$r] | arrays | .[]; . == $c)))}) | from_entries) as $ran
    | .[] | select(.step == "landed" and (.sha | type) == "string" and .sha != "") | "\(.sha) \(.card) \(.issue) \($ran[.card] // false)"' 2>/dev/null) || return 1
  while read -r s; do
    s=$(grep -m 1 "^$s " <<<"$l") || continue
    if [ "${s##* }" = true ]; then ran=1; break; fi
    by=$s
  done < <(git rev-list -n "$TESTLINK_DEPTH" "$2" 2>/dev/null)
  [ -n "$ran" ] && [ -n "$by" ] || return 1
  read -r s card iss _ <<<"$by"
  git diff-tree --no-commit-id --name-only --no-renames -r -z --root "$s" 2>/dev/null | tr '\0' '\n' \
    | jq -cRn --arg s "$s" --arg c "$card" --arg n "$iss" --arg f "$1" '{sha: $s, card: $c, issue: ($n | tonumber? // $n),
      links: ([inputs | select(. != "" and . != $f) | {key: ., value: [$f]}] | from_entries)}'
}
# A main-red fix card (card()) stages the links its entry's cases found (mainred(): links) into
# .conveyor/test-links.json, {"<changed file>": ["<test file>", ...]}, beside the links already there, so they land
# with its fix and every later card's test selection (.conveyor/test-changed.sh) reads them.
testlinks() { # <card> <worktree>
  local new f=$2/.conveyor/test-links.json old
  new=$(jq -c --arg c "$1" 'reduce (.reds[]? | select(.card == $c) | .cases[] | .links // {} | to_entries[]) as $e ({}; .[$e.key] += $e.value)' "$MAINRED" 2>/dev/null) || return 0
  [ "$new" != '{}' ] || return 0
  old=$(jq -ce objects "$f" 2>/dev/null) || old='{}'
  mkdir -p "${f%/*}" && jq -n --argjson a "$old" --argjson b "$new" 'reduce ($b | to_entries[]) as $e ($a; .[$e.key] = ((.[$e.key] // []) + $e.value | unique))' > "$f.new" \
    && mv -f "$f.new" "$f" && git -C "$2" add -- .conveyor/test-links.json
}
# Whether a main-red fix card is open: not picked yet ("") or given back by `retry` (no line of it in the card
# records), on the belt or blocked; not when it landed or closed. Records that cannot be read count as open.
redopen() { # <card id, or "">
  [ -n "$1" ] || return 0
  stdb ask card "$1" 2>/dev/null | jq -se 'any(.step | IN("landed", "closed")) | not' >/dev/null
}
# Under the lock (pick()), ahead of the queue: the fix card of the oldest red main commit whose card is not picked yet
# or was given back by `retry` (mainred()). Its picked line is titled "Main is red: <cases>" and names main's commit
# (mainRed), and, when it takes the slot beyond the project's cap (BEYOND, run(): redfix()), says why (beyond); the
# record names the card. Prints "<card> 0 false", `wait` when the machine holds it back, nothing when
# no commit waits for a card.
redpick() {
  local lock rec s c l card=''
  [ -s "$MAINRED" ] || return 0
  { exec {lock}>>"$MAINRED.lock"; } 2>/dev/null || { echo "conveyor: the main-is-red record could not be locked; its fix card waits" >&2; return 1; }
  flock "$lock" || { exec {lock}>&-; echo "conveyor: the main-is-red record could not be locked; its fix card waits" >&2; return 1; }
  rec=$(jq -ce '.reds | arrays' "$MAINRED" 2>/dev/null) || rec='[]'
  while IFS=$'\t' read -r s c; do
    if [ -n "$c" ]; then l=$(stdb ask card "$c") && [ -z "$l" ] || continue; fi
    # The machine's yes (room()), as for any card: held back, the loop asks again at its next turn.
    room 0 >/dev/null || { exec {lock}>&-; echo wait; return 0; }
    # A card id is its second, its project and its issue: a card of issue 0 picked in the same second waits for the next.
    while card="c$(date -u +%Y%m%dT%H%M%S)-$CTAG-0"; [ -n "$(stdb ask card "$card")" ] || stdb ask lines retried | grep -F "\"card\":\"$card\"" >/dev/null; do sleep 1; done
    jq -c --arg s "$s" --arg c "$card" '{reds: map(if .sha == $s then .card = $c else . end)}' <<<"$rec" > "$MAINRED.new" && mv -f "$MAINRED.new" "$MAINRED" \
      && l=$(line "$card" 0 picked ok "$(jq -c --arg s "$s" --arg b "${BEYOND:-}" '.[] | select(.sha == $s) | {title: ("Main is red: " + ([.cases[].case] | join(", ")))[0:200], mainRed: $s}
        + if $b == "" then {} else {beyond: $b} end' <<<"$rec")") \
      && append "$l" || { exec {lock}>&-; echo "conveyor: the fix card of main's commit $s could not be picked" >&2; return 1; }
    exec {lock}>&-; echo "$card 0 false"; return 0
  done < <(jq -r '.[] | [.sha, .card // ""] | @tsv' <<<"$rec")
  exec {lock}>&-
}
# What stands in for the issue of a main-red fix card (card()), from its entry as it is now (mainred()): the title
# "Main is red: <cases>", and a body naming main's commit, each case with the last commit that changed its files (and
# the landing that broke it, when known), and what to do. Labelled as the P0 issue it stands in for was (labels.type and the first priority), so it is held to the bug-card check.
redissue() { # <card>
  jq -ce --arg c "$1" --arg t "$TYPE" --argjson p "$PRIOS" '.reds[]? | select(.card == $c)
    | {number: 0, title: ("Main is red: " + ([.cases[].case] | join(", ")))[0:200], milestone: null, labels: [{name: $t}, {name: $p[0]}],
       body: ("These test cases fail on main at \(.sha[0:12]). A card'"'"'s test step failed each on its run and its run again, and it failed again when run on main, without the card'"'"'s change. A card that fails only cases that fail on main waits (no fix session, no block) until main changes, then tests again.\n\n"
         + ([.cases[] | "- `\(.case)`, found by card \(.by). The last commit that changed \(if .files == [] then "its file" else .files | join(", ") end): \(if .last == "" then "none found" else .last end)."
           + if .landing == null then "" else " The landing that broke it: \(.landing.sha[0:12]) (card \(.landing.card), #\(.landing.issue)), whose test step did not run \(.files[0]). This card links \(.files[0]) to the files that landing changed, in .conveyor/test-links.json, so later cards that change them run it: \(.links | keys | join(", "))." end] | join("\n"))
         + "\n\nMake the cases pass on main.\n\nDone when: the cases pass on main.")}' "$MAINRED" 2>/dev/null
}
# The titles of the main-red fix cards as their entries are now ({<card>: "Main is red: <cases>"}): the Board shows a
# case added while the card runs (mainred()), which its picked line's title does not name.
redtitles() {
  jq -ce '[.reds[]? | select(.card) | {key: .card, value: ("Main is red: " + ([.cases[].case] | join(", ")))[0:200]}] | from_entries' "$MAINRED" 2>/dev/null || echo '{}'
}
# A card whose every failure is main's (verdicts()) waits in its test step until main is at another commit than
# <main's commit>, its live record saying so and brought up to date as it waits (so `health` does not call it stuck).
mainwait() { # <worktree> <main's commit> <the cases, as one text>
  local at; at=$(date -u +%FT%TZ)
  while [ "$(git rev-parse -q --verify "refs/heads/$BRANCH^{commit}" 2>/dev/null)" = "$2" ]; do
    jq -cn --arg at "$at" --arg c "$3" --arg s "${2:0:12}" '{step: "test", at: $at, last: (now | todate), turns: 0, files: {run: 0, of: null}, tests: null,
      action: "waiting for main to change: \($c) fail on main at \($s) too"}' > "$1.live.tmp" 2>/dev/null && mv -f "$1.live.tmp" "$1.live"
    sleep "$LIVE"
  done
  rm -f "$1.live"
}
# One run of the command <cmd> in the worktree, on the slot tests() holds. The report file an earlier run wrote
# (<worktree>.report, reportask()) goes first: a runner that adds to it (tools/mochatimes.cjs) would otherwise give the
# run again the first run's times too.
testonce() { # <worktree> <cmd>
  local pid clock rc r='' t0
  [ ! -s "$1.rerun" ] || r=$1.rerun; rm -f "$1.report"
  t0=$(date +%s)
  (cd "$1" && { [ -n "$SLOT_HOME" ] || slot_mine; } && { [ ${#REPORT_ENV[@]} = 0 ] || export "${REPORT_ENV[@]}"; } && CONVEYOR_TEST_SLOTS=$HERE/lib/slots.sh CONVEYOR_TEST_LOG=$1.testlog CONVEYOR_TEST_TURNWAIT=$1.turnwait \
    CONVEYOR_TEST_RERUN=$r CONVEYOR_TEST_FILES=${TEST_FILES:-} exec timeout --kill-after=30 0 bash -c "$2" > "$1.test" 2>&1 < /dev/null 8>&-) &
  pid=$!; testclock $pid "$1.turnwait" & clock=$!
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
REPORT_ENV=()
reportask() { # <worktree>
  local e a q
  REPORT_ENV=(); REPORT_ARGS=''
  packget test.report.env e test.report.args a 2>/dev/null || return 0
  printf -v q '%q' "$1.report"; REPORT_ARGS=${a//<file>/$q}
  [ -z "$e" ] || mapfile -t REPORT_ENV < <(jq -r --arg f "\"$1.report\"" --arg m "\"$HERE/tools/mochatimes.cjs\"" 'objects | to_entries[]
    | select((.key | test("^[A-Za-z_][A-Za-z0-9_]*$")) and (.value | type == "string"))
    | "\(.key)=\(env[.key] // "" | if . == "" then "" else . + " " end)\(.value | gsub("<file>"; $f) | gsub("<mochatimes>"; $m) | gsub("\n"; " "))"' <<<"$e")
}
# The times the runner's own report gives (the pack's test.report: format, and path, a file or folder from the
# worktree, else <worktree>.report when its env or args has <file> (reportask()), else the run's output, <worktree>.test
# (go test -v's, which env GOFLAGS asks for);
# conveyor/README.md, The CPU budget of a test file), as `TESTRUN sec` lines with clock seconds only
# (tools/testreport.py), in <worktree>.reported: of the report files written since <start>, so one an earlier run left
# is not read. None when the pack names no format.
reported() { # <worktree> <the run's start, epoch seconds>
  local f p e a
  rm -f "$1.reported"
  packget test.report.format f test.report.path p test.report.env e test.report.args a 2>/dev/null && [ -n "$f" ] || return 0
  if [[ $e$a == *'<file>'* ]]; then p=$1.report; elif [ -z "$p" ]; then p=$1.test; elif [[ $p != /* ]]; then p=$1/$p; fi
  python3 -I "$HERE/tools/testreport.py" "$f" "$1" "$2" "$p" > "$1.reported" 2>/dev/null || rm -f "$1.reported"
}
# What the next run of the card need not run again (tests()), in <worktree>.rerun: a line `change\t<id>` (the hash of
# the staged diff), `base\t<HEAD>` and `tree\t<the index's tree>` (what rerunsince() compares), then `pass\t<file>` for
# each file that passed in this run or one before it, `ok\t<file>\t<case>` for each case that passed in a file that
# did not (in this run or one before it), and `fail\t<file>\t<case>` for each case that failed in this run. A file
# with no line (it failed naming no case, never finished or never began) runs whole. Of a file that ran in this run,
# case by case, what the list said before goes only where this run says otherwise: a case that failed now is no
# longer kept as passed, and every other case it kept still is (a run after a fix runs a few cases of the engine's
# runner, and the runner's cases it did not run stay kept). A file `pass` before that now failed naming its cases keeps
# its `pass` line beside their `fail` lines: the command runs those cases alone. A file that now failed naming no case
# or never finished, when the run's log names the cases it selected of it (`TESTRUN case\t<file>\t<case>`, a file
# run in part), loses only what it kept of those cases: its `ok` lines of them go, and a `pass` line stays beside a
# `fail` line for each of them that did not print `ok` now, so its other cases, which did not run (a fix's run of the
# cases of the files the fix changed, then the run's timeout), stay kept. Else (a file run whole, or a log that names
# no case) it keeps no `pass` line, nor, in a run that was given `changed` lines (rerunsince()), its `ok` lines.
rerunlist() { # <worktree> <the staged change's id> <testfails() of the run> <HEAD> <tree>
  local old ran='' sel='' logs=() ch=''
  ! grep -q $'^changed\t' "$1.rerun" 2>/dev/null || ch=1
  mapfile -t logs < <(testlogs "$1")
  if [ ${#logs[@]} != 0 ]; then
    ran=$(cat "${logs[@]}" 2>/dev/null | sed -n 's/^== //p'); sel=$(cat "${logs[@]}" 2>/dev/null | sed -n 's/^TESTRUN case\t//p')
  fi
  old=$(jq -rRn --arg ran "$ran" --arg sel "$sel" --arg ch "$ch" --argjson r "$3" '
    ($ran | split("\n") | map(select(. != ""))) as $ran
    | ($sel | split("\n") | map(select(. != "") | split("\t"))) as $sel
    | inputs | split("\t") | select(.[0] == "pass" or .[0] == "ok") | . as [$k, $f, $c]
    | [$r.files[]? | select(.file == $f)] as $fl | [$fl[].cases[].name] as $n
    | [$sel[] | select(.[0] == $f) | .[1]] as $s
    | if IN($ran[]; $f) | not then join("\t")
      elif IN($r.passed[]?; $f) then empty
      elif $fl != [] and $n != [] then select($k == "pass" or (IN($n[]; $c) | not)) | join("\t")
      elif $s == [] then select($k == "ok" and $ch == "") | join("\t")
      elif $k == "ok" then select(IN($s[]; $c) | not) | join("\t")
      else join("\t"), ($s - [$r.okcases[]? | select(.file == $f) | .cases[]] | unique | .[] | "fail\t\($f)\t\(.)") end' "$1.rerun" 2>/dev/null)
  { printf 'change\t%s\nbase\t%s\ntree\t%s\n' "$2" "${4:-}" "${5:-}"
    { sed -n 's/^pass\t//p' <<<"$old"; jq -r '.passed[]?' <<<"$3"; } | sort -u | sed 's/^/pass\t/'
    { sed -n 's/^ok\t//p' <<<"$old"; jq -r '.okcases[]? | .file as $f | .cases[] | "\($f)\t\(.)"' <<<"$3"; } | sort -u | sed 's/^/ok\t/'
    { jq -r '.files[] | .file as $f | .cases[] | "\($f)\t\(.name)"' <<<"$3"; sed -n 's/^fail\t//p' <<<"$old"; } | awk '!s[$0]++' | sed 's/^/fail\t/'
  } > "$1.rerun.new" && mv -f "$1.rerun.new" "$1.rerun"
}
# What a card's run that passed passed (tests()), for a batch that takes the card (batchkeep()): <worktree>.passed,
# {units, cases}. units: each test file the run passed, as `<file>`, or, of a file whose log lines `ok <case>` name
# its cases, as `<file><TAB><case>` for each case; with what the run's list (<worktree>.rerun) kept as passed, and a
# file passed whole standing for its cases. A run whose command wrote no log is one file, the command (test.command).
# cases: how many cases the run ran and kept (testrec()), null when its runner does not say.
passlist() { # <worktree>
  local f cmd
  if [ -n "$(testlogs "$1")" ]; then f=$(testfails "$1.test" 0) || return 1
  else packget test.command cmd && f=$(jq -cn --arg c "$cmd" '{passed: [$c], passcases: [], okcases: []}') || return 1; fi
  { awk -F'\t' '$1 == "pass" {print $2} $1 == "ok" {print $2 "\t" $3}' "$1.rerun" 2>/dev/null
    jq -r '((.passcases + .okcases)[] | .file as $f | .cases[] | "\($f)\t\(.)"), (.passed - [.passcases[].file])[]' <<<"$f"
  } | jq -cRn --argjson x "$(testrec "$1" 0 0)" '[inputs | select(. != "")] | unique as $u | [$u[] | select(contains("\t") | not)] as $w
    | {units: [$u[] | select((contains("\t") | not) or (split("\t")[0] | IN($w[]) | not))],
       cases: (if $x.selected.cases == null then null else $x.selected.cases + ($x.selected.kept // 0) end)}' > "$1.passed"
}
# The list of the card's last run (rerunlist()) for its run now: kept as it is for the same staged change on the same
# HEAD; for a change made on the same HEAD (a fix session's), with a line `changed\t<file>` for each file whose content
# differs between the tree last tested and the tree now (the two trees compared, not the two patches), so the command
# runs their tests beside what had not passed. On another HEAD (the change moved onto a newer main, or a retried card's
# kept list on a main that moved since: the owner, 2026-11-14), `changed` lines for the files of the card's change, as
# it was or is now, whose content differs between the two trees, and a line `main\t<file>` for each file main changed
# between the HEAD last tested and HEAD now, whose tests the command runs when its selection for the card's change
# holds them too, and a line `from\t<the HEAD last tested>`, so the command can read what main changed in each (a
# change of text alone runs only the tests that hold the text: test-changed.sh, issue 512). Fails (1), and the whole selection would run, when there is no list, the change has no id, or the
# trees or HEADs cannot be compared, RERUN_WHY saying which (tests() refuses such a full run unless it is allowed).
# Fails (2), the whole selection to run, when HEAD moved and a file of the card's change that main did not change
# differs: the session that brought the change onto main (the rebuild, the port) edited it outside what main changed,
# a merge in doubt.
rerunsince() { # <worktree> <the staged change's id> <HEAD> <tree>
  local ot ob ch m='' c
  RERUN_WHY='no list of what the last run passed'
  [ -n "$2" ] && [ -s "$1.rerun" ] || return 1
  ob=$(sed -n 's/^base\t//p' "$1.rerun"); ot=$(sed -n 's/^tree\t//p' "$1.rerun")
  [ "$(sed -n '1s/^change\t//p' "$1.rerun")" != "$2" ] || [ "$ob" != "$3" ] || return 0
  RERUN_WHY="the last run's list names no tree or commit to compare with"
  [ -n "$3" ] && [ -n "$4" ] && [ -n "$ot" ] && [ -n "$ob" ] || return 1
  RERUN_WHY="the tree last tested ($ot) cannot be compared with the tree now"
  ch=$(treediff "$1" "$ot" "$4") || return 1
  if [ "$ob" != "$3" ]; then
    RERUN_WHY="the commit last tested on ($ob) cannot be compared with HEAD"
    m=$(treediff "$1" "$ob" "$3") && c=$(treediff "$1" "$ob" "$ot" && treediff "$1" "$3" "$4") || return 1
    ch=$(grep -xF -f <(grep . <<<"$c") <<<"$ch")
    ! grep -vxF -f <(grep . <<<"$m") <<<"$ch" | grep -q . || return 2
  fi
  RERUN_WHY="the list for this run could not be written"
  { printf 'change\t%s\nbase\t%s\ntree\t%s\n' "$2" "$3" "$4"; [ "$ob" = "$3" ] || printf 'from\t%s\n' "$ob"
    grep -E $'^(pass|ok|fail)\t' "$1.rerun"; awk 'length { print "changed\t" $0 }' <<<"$ch"; awk 'length { print "main\t" $0 }' <<<"$m"; } > "$1.rerun.new" \
    && mv -f "$1.rerun.new" "$1.rerun"
}
# Whether the card of a worktree has a test line in the records: a run of its tests ended before (tests()).
testedbefore() { # <worktree>
  [ "$(stdb ask tested "${1##*/}" 2>/dev/null)" = true ]
}
# The files that differ between two trees or commits, one a line (read NUL-separated: a name with spaces is whole).
treediff() { # <worktree> <from> <to>
  git -C "$1" diff --name-only --no-renames -z "$2" "$3" -- > "$1.rerun.new" 2>/dev/null && tr '\0' '\n' < "$1.rerun.new"
}

# The clock of a test run (tests()): TEST_TIMEOUT seconds of running, the seconds a runner of its command waited for
# a whole-suite turn not counted (slot_whole writes them to <turn wait file>), as the wait for its slot is not (the
# owner, 2026-11-13: no time limit changes for the turns). timeout itself is given no limit; when the clock runs out
# it is sent ALRM, its own timer's signal, so it ends the run as on its own timeout: TERM to the command's group, KILL
# 30 s later, exit 124. It holds no descriptor of the loop's (a lock, the slot) while it runs.
testclock() { # <timeout's pid> <turn wait file>
  local f s=$SECONDS w
  for ((f = 3; f < 256; f++)); do eval "exec $f>&-"; done
  exec </dev/null >/dev/null 2>&1
  while sleep 1; do
    w=$(cat "$2" 2>/dev/null); [[ $w =~ ^[0-9]{1,9}$ ]] || w=0
    [ $((SECONDS - s)) -ge $((TEST_TIMEOUT + w)) ] || continue
    kill -ALRM "$1"; return
  done
}

# The product checks, run by the loop beside the changed tests: a ratchet baseline raised in the same change
# as the code that needed the room, and a verification tuning schema added with no ring N-1 test
# (policy/api-conventions.md#data-access). Each takes <base> <head>: the base is the commit the card was built on
# (the worktree's HEAD), the head a commit made of the card's staged change on it, which no ref names. They are the
# pack's checks (the list, or its run when checks is an object), each a script path relative to main's checkout (or
# absolute): the loop's own copies, not the worktree's, so a card cannot change the check it is held to.
checks() { # <worktree>; prints the lines of every check that fails, and fails when one does
  local base head s out r rc=0 cs=()
  packget checks s && mapfile -t cs < <(jq -r 'if type == "object" then .run // [] else . end | .[]' <<<"$s") || { echo "the project pack's checks could not be read"; return 1; }
  base=$(git -C "$1" rev-parse HEAD 2>&1) && head=$(cd "$1" && git commit-tree "$(git write-tree)" -p "$base" -m "conveyor product checks" 2>&1) \
    || { echo "the card's change could not be made a commit for the product checks: ${head:-$base}"; return 1; }
  for s in "${cs[@]}"; do
    [[ $s == /* ]] || s=$MAIN/$s
    out=$(cd "$1" && bash "$s" "$base" "$head" 2>&1 < /dev/null 8>&-); r=$?
    [ $r = 0 ] || { rc=1; printf '%s (exit %s):\n%s\n' "${s##*/}" "$r" "$out"; }
  done
  return $rc
}

# Commit trailers. Conveyor writes every commit message, so a line a host's commit-msg hook requires (such as
# `Mutation-verified:`) is the card's to give: its sessions write such lines in <worktree>.trailers, and each kept line
# goes into the commit message after its `Closes` line. Kept: lines `<Token>: <text>` (a token of letters and hyphens),
# each under 300 characters, the first 10; never Co-Authored-By or a token the pack's commit.forbid names. The pack's
# commit.trailers names the ones a change owes: a rule's token when a path the change adds matches its when (an ERE).
trailers() { # <worktree>: the kept lines, one a line
  local f
  packget commit.forbid f || return 1
  [ -e "$1.trailers" ] || return 0
  jq -Rrn --argjson f "$f" '([$f[], "Co-Authored-By"] | map(ascii_downcase)) as $no
    | [inputs | rtrimstr("\r") | select(test("^[A-Za-z][A-Za-z-]*: .*\\S") and length < 300) | select(split(":")[0] | ascii_downcase | IN($no[]) | not)]
    | .[:10][]' "$1.trailers"
}
# The section of the sessions' prompt that names the file and the pack's rules, each with its ask.
trailerbrief() { # <worktree>
  local r f
  packget commit.trailers r && packget commit.forbid f && f=$(jq -r 'map(", " + .) | join("")' <<<"$f") || return 1
  printf '%s' "# Commit trailers
Conveyor writes this card's commit message. A line the commit must carry goes in the file $1.trailers, one a line,
as \`<Token>: <text>\` with a token of letters and hyphens: each is added to the commit message after its \`Closes\`
line. Only lines of that shape are kept, the first 10, each under 300 characters; Co-Authored-By$f lines are dropped."
  jq -r '.[] | "\n- When your change adds a file whose path matches the extended regular expression `\(.when)`: \(.ask) Write it as a `\(.token): <text>` line in that file."' <<<"$r"
}
# The pack's trailers the staged change owes and the card has not written: one {token, ask, paths} a line. The
# added paths are read unquoted and NUL-separated (-z), so a path git would quote, or one holding a newline, is matched
# whole; a when grep cannot read, or paths git cannot list, fails.
owing() { # <worktree>
  local r k m t rc
  packget commit.trailers r && t=$(trailers "$1") || return 1
  while IFS= read -r k; do
    m=$(set -o pipefail; git -C "$1" diff --cached --name-only --no-renames --diff-filter=A -z | grep -zE -- "$(jq -r .when <<<"$k")" | jq -Rsc 'split("\u0000") | map(select(. != ""))'); rc=$?
    [ $rc = 1 ] && continue
    [ $rc = 0 ] || return 1
    jq -c --argjson m "$m" --arg t "$t" 'select(.token | ascii_downcase | IN($t | split("\n")[] | split(":")[0] | ascii_downcase) | not)
      | {token, ask, paths: $m}' <<<"$k"
  done < <(jq -c '.[]' <<<"$r")
}
# What the review is shown beside the diff: the kept lines, nothing when there are none.
trailerview() { # <worktree>
  local t
  t=$(trailers "$1") || return 1
  [ -z "$t" ] || printf '\n\n# The commit trailers\nThe card wrote these lines in %s; they go into its commit message after its `Closes` line. Each must be true of the staged change:\n%s' "$1.trailers" "$t"
}

# The Done-when check: code, no model. The issue's `## Done when` section (to the next heading of level one or two)
# has a bullet per item; the session's reply ends with its own `## Done when` section, a line `D<n> met: <evidence>`
# or `D<n> not met: <why>` per item (card-core.md). Each item needs its line; a met line needs evidence that is not
# empty, none, n/a or tbd. A file it names (a path with a folder and an extension, a bare file name with an
# extension, as missing.c or x.c, but not e.g. or i.e., or any name with a :line after it that has a folder, an
# extension or a capital first letter, as src/Makefile:1 or missing.c:1; a pytest ::case after a path is dropped) that
# is not in the worktree (a bare name may
# be at its root or in any folder; an absolute path, or one under ~, is not in it) does not fail the item: it is a note
# the review is shown beside the D<n> lines, as a reply often names a missing file on purpose (the owner, 2026-11-12).
# The items are the bullets at the section's least indent (a nested bullet is part of its
# item). Every TODO or [VERIFY]
# marker the staged change adds (more lines holding it added than removed, so a moved line is not added) must be
# named in the reply, on a line that names its file exactly. DONEWHEN reads the
# issue (its input), $r (the reply), $m (the added markers, [<file>, <marker>] pairs) and $wt; it prints nothing for
# an issue with no such section or no bullet in it, else {items, met (the items met so far), failed, paths ({n, p}:
# the files each met line names), lines (the reply's D<n> lines)}.
DONEWHEN='def sect($t; $atend): [$t | splits("\r?\n")] as $l
    | [range($l | length) | select($l[.] | test("^#{1,2}\\s+Done when\\s*$"; "i"))] | (if $atend then last else first end) as $i
    | if $i == null then null else $l[($i + 1):] | (map(test("^#{1,2}\\s")) | index(true)) as $e | if $e == null then . else .[:$e] end end;
  def refs($s): [$s | scan("[^\\s`\"(),;<>]+") | sub("::.*$"; "") | capture("^(?<p>.*?)(?<l>:[0-9]+(-[0-9]+)?)?[.,:;]*$")
    | .p |= if startswith($wt + "/") then .[($wt | length) + 1:] else . end];
  def toks($s): [refs($s)[] | .p];
  (sect(.body // ""; false) // [] | map(capture("^(?<i>\\s*)[-*+]\\s+\\S") | .i | length) | (min // 0) as $min | map(select(. == $min)) | length) as $items
  | select($items > 0)
  | [sect($r; true) // [] | .[] | . as $x | capture("^\\s*(?:[-*+]\\s+)?`?D(?<n>[0-9]+)`?\\s+(?<k>met|not met)\\s*:\\s*(?<e>.*?)\\s*$"; "i")
      | .n |= tonumber | .k |= ascii_downcase | .line = $x] as $d
  | [range(1; $items + 1) as $n | ([$d[] | select(.n == $n)] | first) as $x
      | if $x == null then {n: $n, why: "D\($n): no `D\($n) met:` or `D\($n) not met:` line in the `## Done when` section that ends the reply"}
        elif $x.k == "not met" then {n: $n}
        elif ($x.e | gsub("^[\\s`*_]+|[\\s`*_.]+$"; "") | ascii_downcase | IN("", "none", "n/a", "tbd")) then {n: $n, why: "D\($n): met, with no evidence"}
        else {n: $n, met: true, paths: [refs($x.e)[] | select((.p | test("/") and test("\\.[A-Za-z][A-Za-z0-9]*$"))
            or (.p | test("^[A-Za-z0-9_][A-Za-z0-9_.-]*\\.[A-Za-z][A-Za-z0-9]*$") and (ascii_downcase | IN("e.g", "i.e") | not)) or (.l != null and (.p | test("/|\\.[A-Za-z]|^[A-Z]"))))
            | .p | select(test("://|^[$]") | not)] | unique} end] as $c
  | [$m[] | . as [$f, $k]
      | select(any($r | splits("\r?\n"); index($k) != null and IN(toks(.)[]; $f)) | not) | "\($k) added in \($f) is not named in the reply"] as $hid
  | {items: $items, met: [$c[] | select(.met) | .n], failed: ([$c[] | .why // empty] + $hid),
     paths: [$c[] | select(.met) | {n, p: .paths[]}], lines: [$d[] | select(.n <= $items) | .line]}'
# The check of the last session's reply (its stream in <worktree>.out) against the staged change: prints
# {items, met, failed} (and notes, the files named that are not there, when there is one), nothing when it is skipped
# (no such section, or no change: an ALREADY-DONE goes its own way), and keeps the reply's D<n> lines and those notes
# in <worktree>.donewhen for the review.
donewhen() { # <worktree> <issue json>
  local m k n p t v miss='[]'
  rm -f "$1.donewhen"
  git -C "$1" add -A 2>/dev/null && ! git -C "$1" diff --cached --quiet 2>/dev/null || return 0
  # A marker counts as added only when the whole change has more added lines holding it than removed ones: a line
  # moved from one file to another adds none. t and v are 1 when TODO and [VERIFY] are added, else 0.
  read -r t v < <(git -C "$1" diff --cached --no-renames --no-color -U0 | awk '/^diff --git / {h = 0; next} /^@@/ {h = 1; next}
    h && /^[+-]/ {d = substr($0, 1, 1) == "+" ? 1 : -1; if (index($0, "TODO")) a += d; if (index($0, "[VERIFY]")) b += d}
    END {print (a > 0) + 0, (b > 0) + 0}')
  # File by file, the names read NUL-separated (-z) and passed literally, so a name git would quote in a diff header is
  # read whole; the added lines are the + lines after the first hunk header.
  m=$(git -C "$1" diff --cached --name-only --no-renames --diff-filter=d -z | while IFS= read -r -d '' p; do
      k=$(git -C "$1" diff --cached --no-renames --no-color -U0 -- ":(literal)$p" | awk '/^@@/ {h = 1; next} h && /^\+/')
      [[ $t = 0 || $k != *TODO* ]] || printf '%s\0TODO\0' "$p"; [[ $v = 0 || $k != *'[VERIFY]'* ]] || printf '%s\0[VERIFY]\0' "$p"
    done | jq -Rsc 'split("\u0000") | .[:-1] | [range(0; length; 2) as $i | .[$i:$i + 2]]')
  # The issue and the reply come on stdin and in a file: either can be more than one argument can hold.
  k=$(jq -c --rawfile r <(jq -Rrjn '[inputs | fromjson? // empty | objects | select(.type == "result") | .result | strings] | last // ""' "$1.out" 2>/dev/null) \
    --argjson m "$m" --arg wt "$1" "$DONEWHEN" <<<"$2") || return 1
  [ -n "$k" ] || return 0
  while IFS=$'\t' read -r n p; do
    [[ /$p/ != */../* ]] && { [ -e "$1/$p" ] || { [[ $p != */* ]] && git -C "$1" ls-files | awk -F/ -v p="$p" '$NF == p {f = 1} END {exit !f}'; }; } || miss=$(jq -c --argjson n "$n" --arg p "$p" '. + [{n: $n, p: $p}]' <<<"$miss")
  done < <(jq -r '.paths[] | "\(.n)\t\(.p)"' <<<"$k")
  miss=$(jq -c 'unique_by([.n, .p])[] | "D\(.n): names \(.p), which is not in this worktree"' <<<"$miss" | jq -sc .)
  { jq -r '.lines[]' <<<"$k"; jq -r '.[] | "Note: " + .' <<<"$miss"; } > "$1.donewhen"
  jq -c --argjson x "$miss" '{items, met: (.met | length), failed} + (if $x == [] then {} else {notes: $x} end)' <<<"$k"
}
# A build, fix or rebase session's line, with the Done-when check of its reply on it (doneWhen). A failed check is not a
# block: one fix session is told the failed items, as a NO-GO's findings are, and the check runs again on its reply,
# its line carrying that result; a second failure blocks the card with the items listed. Fails when the card blocked.
checked() { # <card> <issue> <worktree> <issue json> <the sessions' prompt> <step> <the session's fields>
  local k t f
  k=$(donewhen "$3" "$4") || { block "$1" "$2" "$3" "the engine could not run the Done-when check"; return 1; }
  record "$1" "$2" "$6" ok "$(jq -c --argjson k "${k:-null}" 'if $k == null then . else . + {doneWhen: $k} end' <<<"$7")"
  [ -n "$k" ] && [ "$(jq '.failed | length' <<<"$k")" != 0 ] || return 0
  f=$(jq -r '.failed | join("; ")' <<<"$k")
  began "$1" "$2" fix
  t=$(session "$3" "$5"$'\n\n'"$DWFIX"$'\n'"$(jq -r '.failed[] | "- " + .' <<<"$k")" fix) || { block "$1" "$2" "$3" "fix: $t"; return 1; }
  k=$(donewhen "$3" "$4") || { block "$1" "$2" "$3" "the engine could not run the Done-when check"; return 1; }
  record "$1" "$2" fix ok "$(jq -c --argjson k "${k:-null}" --arg r "the Done-when check failed: $f" \
    '. + {reason: $r} + (if $k == null then {} else {doneWhen: $k} end)' <<<"$t")"
  [ -z "$k" ] || [ "$(jq '.failed | length' <<<"$k")" = 0 ] \
    || { block "$1" "$2" "$3" "the Done-when check failed again after its one fix session: $(jq -r '.failed | join("; ")' <<<"$k")"; return 1; }
}

# The findings of a review at each level, as its record line holds them: counted over the whole review, of which
# the line keeps only the first 1500 characters. A finding is any line followups() would file, and one with no
# [P0] to [P3] mark counts as P1, the level it is filed at. An accepted P3 listed only (a MINOR line, minor()) counts
# as the P3 it is.
counts() { # <review file>
  sed -E 's/^MINOR:[[:space:]]*//' "$1" | grep -Ev "$NOTFINDING" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//' | awk '!seen[$0]++' | jq -cRn '[inputs | select(test("[^[:space:]]")) | (capture("\\[(?<p>P[0-3])\\]").p // "P1")] as $p
    | {P0: 0, P1: 0, P2: 0, P3: 0} | with_entries(.key as $k | .value = ($p | map(select(. == $k)) | length))'
}
# A finding that comes back after its fix. Each fix round after a NO-GO keeps, in the folder <worktree>.rounds, the
# findings it was told to fix (findings.jsonl: round, line, level, key) and the diff it made (<round>.diff); a card
# that blocks keeps that folder, and the card that retries from its patch starts from it. Two
# findings are the same when their keys are: the first file:line the finding names and its first six words, lower
# case, letters and digits only, leaving out its level mark, that file:line and any proof after `Proof:`.
findings() { # <review file>: one JSON line per finding, {line, level, key}
  grep -Ev "$NOTFINDING" "$1" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//' | awk 'NF && !seen[$0]++' | jq -cR '. as $f
    | ([scan("[A-Za-z0-9_./-]+:[0-9]+")] | first // "") as $w
    | {line: $f, level: (capture("\\[(?<p>P[0-3])\\]").p // "P1"),
       key: ($w + " " + (gsub("\\[P[0-3]\\]"; "") | if $w == "" then . else index($w) as $i | .[:$i] + .[$i + ($w | length):] end
         | split("Proof:")[0] | ascii_downcase | [scan("[a-z0-9]+")] | .[:6] | join(" ")))}'
}
# The findings of the review beside the worktree that a fix round was already told to fix, one JSON line each:
# {line, level, rounds: how many fix rounds were told it, before: the finding as the last of them was told it, diff:
# the file of that round's diff}.
repeats() { # <worktree>
  [ -s "$1.rounds/findings.jsonl" ] || return 0
  findings "$1.review" | jq -c --slurpfile h "$1.rounds/findings.jsonl" --arg d "$1.rounds" '. as $f | [$h[] | select(.key == $f.key)] | select(length > 0)
    | {line: $f.line, level: $f.level, rounds: (map(.round) | unique | length), before: last.line, diff: "\($d)/\(last.round).diff"}'
}
# What the fix session after a review that repeats a finding is told, after the review: each finding that came back,
# the finding as the earlier review gave it (its proof with it) and the diff of the fix round after that review.
again() { # <repeats() lines>
  local l d
  printf '%s\n' '# These findings came back after a fix round for them' \
    'The review found each of them again after an earlier fix session changed the code for it: that fix did not hold. Do not make the same change again: read in the proof why it did not hold, and take another approach.'
  while IFS= read -r l; do
    d=$(jq -r .diff <<<"$l")
    jq -r '"\n## \(.line)\nIt came back after \(.rounds) fix round\(if .rounds == 1 then "" else "s" end) for it. The earlier review said:\n\(.before)\nThe diff of the fix round after that review (the file \(.diff)):"' <<<"$l"
    printf '```diff\n%s\n```\n' "$(head -c 20000 "$d" 2>/dev/null)"
    [ "$(wc -c < "$d" 2>/dev/null || echo 0)" -le 20000 ] || echo "That diff is cut short here: read all of it in its file."
  done <<<"$1"
}
# Does the review after fix round <round> review the fix alone? Yes when the fix's diff touches no more than the
# pack's review.rereviewWhole percent of the staged change's lines (its added and removed lines, as git counts them; a
# binary file counts none). It fails, and the whole change is reviewed, when the fix touches more, when the staged
# change has no such line, or when a count cannot be read.
fixonly() { # <worktree> <round>
  local w f='' a d=$1.rounds/$2.diff
  packget review.rereviewWhole w && [[ $w =~ ^[0-9]+$ ]] && [ -f "$d" ] || return 1
  [ ! -s "$d" ] || f=$(git -C "$1" apply --numstat "$d") || return 1
  a=$(git -C "$1" diff --cached --numstat) || return 1
  f=$(awk '{n += $1 + $2} END {print n + 0}' <<<"$f"); a=$(awk '{n += $1 + $2} END {print n + 0}' <<<"$a")
  [ "$a" -gt 0 ] && [ $((f * 100)) -le $((a * w)) ]
}
# What the review after fix round <round> is told, in its brief (REREVIEW): what else it may raise (the whole change,
# or with fix as fourth argument the fix's lines and their callers alone), the findings that round was told to fix,
# numbered E1, E2 and so on, the file of its diff, and the findings declined on this card so far, each with its reason.
rereview() { # <card> <worktree> <round> [fix]
  local dec t=$REREVIEWALL
  [ "${4:-}" != fix ] || t=$REREVIEWFIX
  printf '%s\n%s\n\n## The findings the fix was told to fix\n' "$REREVIEW" "$t"
  jq -rs --argjson r "$3" 'map(select(.round == $r)) | to_entries[] | "E\(.key + 1) \(.value.line)"' "$2.rounds/findings.jsonl"
  printf '\n## The diff of the fix\nThe file %s\n' "$2.rounds/$3.diff"
  dec=$(stdb ask lines declined 2>/dev/null | jq -rR --arg c "$1" 'fromjson? | objects | select(.card == $c) | "- \(.finding) (declined: \(.why))"' 2>/dev/null | awk '!seen[$0]++')
  printf '\n## The findings declined on this card\n%s\n' "${dec:-None.}"
}
