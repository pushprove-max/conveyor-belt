# SPDX-License-Identifier: Apache-2.0
# The test files whose record of the lines they ran a change touches (lib/testlines.sh cachereaders(), and this
# project's selector of the changed tests, .conveyor/test-changed.sh ranlines).
# The input: one record a line, `<test file>\t<source>\t<blob>\t<lines>\t<gaps>`: the lines of the source, as the
# blob has it, with code the test file ran, and the lines whose end it ran, each as ranges (`3-7,12`; `-` for none).
# $d: for each source and blob, a line `K\t<source>\t<blob>` and then the hunk lines (`@@ -a,b +c,d @@`) of a diff
# with no context from the blob to the source as the change has it, or a line `!` when the blob cannot be read.
# The output: the test file of each record the change touches. A hunk touches a record when it changes or removes a
# line the test ran, or, when it has more new lines than old ones, when the test ran the end of the line before it
# or of its last old line (the place the new lines stand at; before line 1, every test did). A record with no hunks
# on $d, or with `!`, is touched.
def spans: split(",") | map(select(test("^[0-9]")) | split("-") | map(tonumber) | [.[0], (.[1] // .[0])]);
def touches($a; $b): any(.[]; .[0] <= $b and $a <= .[1]);
(reduce ($d | split("\n")[] | select(. != "")) as $x ({k: "", h: {}};
    if $x | startswith("K\t") then .k = $x[2:] | .h[.k] = []
    elif $x == "!" then .h[.k] = null
    elif .h[.k] != null then ($x | capture("^@@ -(?<a>[0-9]+)(,(?<b>[0-9]+))? \\+[0-9]+(,(?<d>[0-9]+))? @@")) as $m
      | .h[.k] += [[($m.a | tonumber), (($m.b // "1") | tonumber), (($m.d // "1") | tonumber)]]
    else . end) | .h) as $h
| inputs | split("\t") | select(length >= 5) | . as [$t, $s, $b, $l, $g]
| $h["\($s)\t\($b)"] as $hs | ($l | spans) as $L | ($g | spans) as $G
| select($hs == null or any($hs[]; . as [$a, $n, $m]
    | ($n > 0 and ($L | touches($a; $a + $n - 1)))
      or ($m > $n and (if $n == 0 then [$a] else [$a - 1, $a + $n - 1] end | any(.[]; . as $x | $x == 0 or ($G | touches($x; $x)))))))
| $t
