#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 120
# Engine cases: which failures mainred.sh verdicts() gives to main, which landing brokeby() blames for a red case, and
# the links testlinks() stages for a fix card.
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner. redrunner() is mainredproof.test.sh's; eng(), linkfix() and linkfns()
# are mainred.test.sh's.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"
# The engine folder, as lib.sh sets it: named here too, so the release closure (tools/closure.sh) follows this file's paths.
SRC=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)

# Bug (O266): verdicts() alone on card c7, whose last run ran out of time in c.test (a unit naming no case). A unit
# naming no case was main's only when main's run failed the file naming no case, so the card was blamed and main got
# no main-red entry. The verdict is main, and the main-red record holds c.test, for each way main's run of c.test fails:
# - fail: it fails its case `two` (a named failure);
# - timeout (E15, review): it runs out of time in c.test too, so it names no failed case at all.
mrtimeout() { # <fail | timeout>
  redrunner ''
  local w=$T/$CASE/cards/c7 out
  echo 't_two() { false; }' > "$R/c.test" && git -C "$R" add c.test && git -C "$R" commit -qm c.test \
    && git -C "$R" worktree add -q --detach "$w" || fail "the card's worktree could not be made"
  # Main's run opens c.test and outlasts the card's time limit, set to 1 second (TEST_TIMEOUT): that limit ends the
  # run (exit 124), so main's result names c.test only as its timeout, with no failed file. A file's own exit 124 is
  # not this: it is read as the file failing with no case.
  [ "$1" = fail ] || printf '%s\n' 'cp "$CONVEYOR_TEST_RERUN" "$STUB/redlist"; echo "== c.test" | tee -a "$CONVEYOR_TEST_LOG/r"; sleep 10' > "$STUB/mainrun-cmd" # sleep: main's run must outlast its 1-second limit, which ends it
  out=$(eng 'TEST_TIMEOUT=1; TEST_WAIT=; TEST_RUN=; TEST_FREE=; verdicts c7 "$CONVEYOR_CARDS/c7" '"'"'{"files":[],"timeout":{"sec":1,"file":"c.test"}}'"'"' | jq -c .verdicts') \
    || fail "verdicts failed: $out"
  [ "$out" = '[{"case":"c.test","verdict":"main"}]' ] && grep -qx $'fail\tc.test\t*' "$STUB/redlist" \
    || fail "a time-out in a file that main's run ends with $1 did not run there or was not main's: $out: $(cat "$STUB/redlist" 2>&1)"
  [ "$(jq -c '[.reds[].cases[].case]' "$ST/mainred.json" 2>/dev/null)" = '["c.test"]' ] \
    || fail "with main's run of c.test ending with $1, the main-red record does not hold c.test: $(cat "$ST/mainred.json" 2>&1)"
}
t_mainredtimeout() { mrtimeout fail; }
t_mainredtimeoutmain() { mrtimeout timeout; }

# Issue 1613. Bug it catches: with every control failing on main, verdicts() gave each failing case to the machine, so
# a landing that broke a case put the loop on a machine hold that named no landing, and the hold stood until main
# passed. Card c8 fails a.test: one and b.test: two on main while the control c.test fails there. Landing l1 ran both
# files; then landing bad changed lib/x.sh, which the pack's test map (areas.json, as main has it) links to a.test.
# a.test: one is main's, and its main-red entry names bad; b.test: two, whose file and mapped file lib/y.sh did not
# change since l1, is still the machine's, and the hold holds it alone.
# Follow-up (review): each case is judged from the landing that last ran that case (mainchanged() gives brokeby() the
# case). Landing l2, after bad, ran a.test's case three alone (ranCases), so a.test: three last passed after bad and is
# the machine's, while a.test: one, in the same file, last passed on l1 and is main's. Bug it catches: with the case
# dropped, both cases of a.test get one landing to judge from, so one of the two gets the wrong verdict.
t_mainredcontrolchanged() {
  local s v='{"files":[{"file":"a.test","cases":[{"name":"one","line":1},{"name":"three","line":2}]},{"file":"b.test","cases":[{"name":"two","line":1}]}]}'
  mrshared; tune '.test.control = ["c.test"] | .test.map = "areas.json"'; : > "$STUB/broken"
  mkdir -p "$R/lib" && echo 't_three() { false; }' >> "$R/a.test" && echo 't_two() { false; }' > "$R/b.test" && echo y > "$R/lib/y.sh" \
    && echo '{"lib/x.sh": ["a.test"], "lib/y.sh": ["b.test"]}' > "$R/areas.json" \
    && git -C "$R" add a.test b.test lib/y.sh areas.json && git -C "$R" commit -qm 'b.test and the map' || fail "main's b.test and map could not be committed"
  mrland l1 1 '{"a.test": 1, "b.test": 1}' || fail "landing l1 could not be made"
  echo x > "$R/lib/x.sh" && git -C "$R" add lib/x.sh && git -C "$R" commit -qm bad && s=$(git -C "$R" rev-parse HEAD) \
    && eng "append \"\$(line bad 2 landed ok '{\"sha\": \"$s\"}')\"" || fail "landing bad could not be made"
  echo l2 > "$R/l2.txt" && git -C "$R" add l2.txt && git -C "$R" commit -qm l2 && s=$(git -C "$R" rev-parse HEAD) \
    && eng "append \"\$(line l2 3 test pass '{\"times\": {\"a.test\": 1}, \"ranCases\": {\"a.test\": [\"three\"]}}')\" && append \"\$(line l2 3 landed ok '{\"sha\": \"$s\"}')\"" \
    || fail "landing l2 could not be made"
  mrv c8 "$v"
  [ "$(jq -c .verdicts "$STUB/v.c8")" = '[{"case":"a.test: one","verdict":"main"},{"case":"a.test: three","verdict":"machine"},{"case":"b.test: two","verdict":"machine"}]' ] \
    || fail "card c8 failing $v with the control c.test failing on main, after bad changed lib/x.sh (mapped to a.test) and l2 ran a.test: three alone: not main for a.test: one and machine for a.test: three and b.test: two: $(cat "$STUB/v.c8" "$STUB/v.c8.err")"
  [ "$(jq -c '[.reds[].cases[] | [.case, .landing.card]]' "$ST/mainred.json" 2>/dev/null)" = '[["a.test: one","bad"]]' ] \
    || fail "the main-red record does not hold a.test: one alone with the landing bad: $(cat "$ST/mainred.json" 2>&1)"
  [ "$(jq -c .cases "$ST/machinehold.json" 2>/dev/null)" = '["a.test: three","b.test: two"]' ] \
    || fail "the machine hold does not hold a.test: three and b.test: two alone: $(cat "$ST/machinehold.json" 2>&1)"
}
# Bug it catches: mainchanged() read main's area map against the card worktree's index, so a card whose staged change
# deletes b.test, which main's map names by file name alone, made the whole map unreadable: the link of lib/x.sh to
# a.test was lost, and a.test broken by landing bad through lib/x.sh was not main's. Card c8 is based on main before
# b.test came, so b.test is in neither its index nor its HEAD: a map read against either fails, one read against main's
# commit does not. mainchanged() itself is called.
t_mainchangeddeleted() {
  local s b w=$T/$CASE/cards/c8 out
  mrshared; b=$(git -C "$R" rev-parse HEAD); tune '.test.map = "areas.json" | .tests.patterns = ["*.test"]'
  mkdir -p "$R/lib" && echo 't_two() { :; }' > "$R/b.test" \
    && printf '%s\n' '{"area": "x", "file": "lib/x.sh"}' '{"area": "x", "test": "a.test"}' '{"area": "y", "test": "b.test"}' > "$R/areas.json" \
    && git -C "$R" add b.test areas.json && git -C "$R" commit -qm 'b.test and the map' || fail "main's b.test and map could not be committed"
  mrland l1 1 '{"a.test": 1}' || fail "landing l1 could not be made"
  echo x > "$R/lib/x.sh" && git -C "$R" add lib/x.sh && git -C "$R" commit -qm bad && s=$(git -C "$R" rev-parse HEAD) \
    && eng "append \"\$(line bad 2 landed ok '{\"sha\": \"$s\"}')\"" || fail "landing bad could not be made"
  git -C "$R" worktree add -q --detach "$w" "$b" || fail "card c8's worktree could not be made on main before b.test"
  # Main moves on past $s and deletes b.test: a map read with main's HEAD tests in place of $s's cannot name b.test,
  # so the case fails unless the given commit is read.
  git -C "$R" rm -q b.test && git -C "$R" commit -qm later || fail "main's later commit could not be made"
  out=$(eng "mainchanged a.test $s \"\$CONVEYOR_CARDS/c8\" one && echo changed" 2>&1)
  [ "$out" = changed ] || fail "mainchanged a.test $s <c8, on main before b.test> one, main's areas.json linking lib/x.sh (changed by bad) to a.test: not changed: $out"
}

# Bug (#1594, E6): a card's files run side by side, so the time limit stops several at once. testfails() lists them
# all in stopped, but timeout names only the last: verdicts() read timeout alone, so c.test, stopped beside d.test,
# never ran on main and got no verdict, and main's red went unrecorded for it.
t_mainredstopped() {
  redrunner ''
  local w=$T/$CASE/cards/c7 out
  printf 't_two() { false; }\n' > "$R/c.test" && printf 't_three() { false; }\n' > "$R/d.test" && git -C "$R" add c.test d.test \
    && git -C "$R" commit -qm tests && git -C "$R" worktree add -q --detach "$w" || fail "the card's worktree could not be made"
  out=$(eng 'TEST_TIMEOUT=1; TEST_WAIT=; TEST_RUN=; TEST_FREE=; verdicts c7 "$CONVEYOR_CARDS/c7" '"'"'{"files":[],"timeout":{"sec":1,"file":"d.test"},"stopped":["c.test","d.test"]}'"'"' | jq -c .verdicts') \
    || fail "verdicts failed: $out"
  [ "$out" = '[{"case":"c.test","verdict":"main"},{"case":"d.test","verdict":"main"}]' ] \
    || fail "with c.test and d.test both stopped by the time limit, each did not get main's verdict: $out: $(cat "$STUB/redlist" 2>&1)"
}

# Bug (E6, follow-up of #1594): main's run stopped c.test and d.test at their time limits (testfails() stopped; timeout
# names only d.test). mainkeep() left out only timeout's file, so it kept c.test as passed on main (res null), and the
# next card's probe took that result and did not run c.test there. Only a.test, which ended, is kept.
t_mainkeepstopped() {
  local mf='{"files":[],"timeout":{"sec":1,"file":"d.test"},"stopped":["c.test","d.test"]}' u='[{"file":"a.test","case":null},{"file":"c.test","case":null},{"file":"d.test","case":null}]' out
  mrshared
  out=$(eng 'rm -f "$MAINPROBE"; sha='"$s"' dk="" hits="[]" ctl="[]" mf='"'$mf'"'; mainkeep c7 '"'$u'"'; jq -c ".files | keys" "$MAINPROBE"' 2>&1)
  [ "$out" = '["a.test"]' ] || fail "mainkeep of units $u after main's run $mf kept files other than a.test: $out"
}

# Bug (E6, follow-up of #1594): redrun() read timeout alone, so of two files the time limit stopped (testfails()
# stopped), the one timeout did not name got the verdict none, not fail. The stand-in tests() ends as a time-out does
# (124) and testfails() names both files stopped: each file's verdict is fail.
t_redrunstopped() {
  local got c='[{"name":"c.test","file":"c.test","files":[],"case":""},{"name":"d.test","file":"d.test","files":[],"case":""}]'
  mkdir -p "$T/$CASE"
  got=$( cd "$T/$CASE" && eval "$(sed -n '/^redrun() {/,/^}/p' "$SRC/lib/mainred.sh")"
    names() { :; }; tests() { mkdir -p "$1.testlog" && : > "$1.testlog/a.log"; return 124; }; testlogs() { echo "$1.testlog/a.log"; }
    testfails() { echo '{"files":[],"timeout":{"sec":1,"file":"d.test"},"stopped":["c.test","d.test"]}'; }
    redrun "$T/$CASE/wt" "$c" | jq -c 'map(.verdict)' ) || fail "redrun() did not run: $got"
  [ "$got" = '["fail","fail"]' ] || fail "redrun of $c, with testfails() naming c.test and d.test stopped, did not fail both: $got"
}

# R273. Bug it catches: when the main-red entry of main's commit names no landing, verdicts() took brokeMain from the
# newest entry holding the case, so a case fixed and broken again blamed the landing that broke it the first time.
# E8 (review). Bug it catches: verdicts() read brokeMain only from the entry of main's commit, but while the fix card of
# an older entry holding the case is open, mainred() adds the case to no entry of main's commit (a landing since then
# did not break it), so brokeMain lost the known cause.
# The entry of commit 1111... holds b.test: flaky, broken by landing old, its fix card cold <its last step>; b.test:
# flaky now fails on main (another commit) and no landing ran b.test. Closed: the case is broken again, a new entry of
# main's commit names no landing, and brokeMain is none, not old. Picked (open): the case stays in the old entry alone
# and brokeMain is old.
# E8 (review, again). Bug it catches: when another failure already made the entry of main's commit, mainred() adds the
# case to it with no landing (brokeby() searches a limited depth), and verdicts() stopped there. Picked, with that
# entry (head): the old entry's landing is still named, and the record holds both entries.
# Bug it catches (newer): verdicts() read the older entries oldest first, so when the case was fixed on main and broken
# again by landing new, which a newer entry (its fix card cnew open too) names, while cold stays blocked, brokeMain
# named old, the landing of the first break.
# E10 (review). Bug it catches: with no entry for the new break (mainred() adds none while cold is open), verdicts()
# named old, though the case passed on main after old's landing and broke again: landings on main after old's are
# fixed (its test line ran b.test, so passed it) and new (which did not run it). Again: brokeMain is new, as brokeby()
# finds it, and the record still holds the old entry alone.
mrland() { # <card> <issue> [<its test line's times, as JSON>]: a landing of <card> on main, with its test and landed lines
  local s t=${3:-'{}'}
  echo "$1" > "$R/$1.txt" && git -C "$R" add "$1.txt" && git -C "$R" commit -qm "$1" && s=$(git -C "$R" rev-parse HEAD) \
    && eng "append \"\$(line $1 $2 test pass '{\"times\": $t}')\" && append \"\$(line $1 $2 landed ok '{\"sha\": \"$s\"}')\""
}
mrblame() { # <cold's last step> <brokeMain, as JSON> <entries the record then holds> [head | newer | again]
  rerunsetup '1 fail flaky' '2 fail flaky' 'main fail flaky'; rerunfiles
  local v fl='{"of":null,"files":[{"file":"b.test","cases":[{"name":"flaky","line":"1"}]}],"timeout":null}'
  jq -cn '{reds: [{sha: "1111111111111111111111111111111111111111", card: "cold", cases: [{case: "b.test: flaky", file: "b.test", by: "c1", files: ["b.test"], last: "",
    landing: {sha: "2222222222222222222222222222222222222222", card: "old", issue: 1}}]}]}' > "$ST/mainred.json" || fail "the old entry could not be written"
  [ "${4:-}" != head ] || { jq -c --arg s "$(git -C "$R" rev-parse refs/heads/main)" '.reds += [{sha: $s, card: null, cases: [{case: "c.test: other", file: "c.test", by: "c2", files: ["c.test"], last: ""}]}]' \
    "$ST/mainred.json" > "$ST/mainred.new" && mv "$ST/mainred.new" "$ST/mainred.json"; } || fail "the entry of main's commit could not be written"
  [ "${4:-}" != newer ] || { jq -c '.reds += [{sha: "3333333333333333333333333333333333333333", card: "cnew", cases: [{case: "c.test: other", file: "c.test", by: "c2", files: ["c.test"], last: ""},
    {case: "b.test: flaky", file: "b.test", by: "c3", files: ["b.test"], last: "", landing: {sha: "4444444444444444444444444444444444444444", card: "new", issue: 2}}]}]' \
    "$ST/mainred.json" > "$ST/mainred.new" && mv "$ST/mainred.new" "$ST/mainred.json" && eng 'append "$(line cnew 0 picked ok)"'; } || fail "the newer entry could not be written"
  [ "${4:-}" != again ] || { mrland old 1 && jq -c --arg s "$(git -C "$R" rev-parse HEAD)" '.reds[0].cases[0].landing.sha = $s' "$ST/mainred.json" > "$ST/mainred.new" \
    && mv "$ST/mainred.new" "$ST/mainred.json" && mrland fixed 2 '{"b.test": 1}' && mrland new 3; } || fail "the landings on main could not be made"
  eng 'append "$(line cold 0 '"$1"' ok)"' || fail "card cold's line could not be written"
  git -C "$R" worktree add -q --detach "$T/$CASE/cards/c7" && rerunedit 'echo two >> a.txt' || fail "the card's worktree could not be made"
  v=$(mrverdicts "$fl") || fail "verdicts failed: $v"
  [ "$(jq -c '[.verdicts[].verdict, .brokeMain]' <<<"$v")" = "[\"main\",$2]" ] && [ "$(jq '.reds | length' "$ST/mainred.json")" = "$3" ] \
    || fail "given b.test: flaky failing on main with fix card cold $1, verdicts() did not name $2 in brokeMain, or the record does not hold $3 entries: $v: $(cat "$ST/mainred.json" 2>&1)"
}
t_mainredblameold() { mrblame closed null 2; }
t_mainredblameopen() { mrblame picked '"old"' 1; }
t_mainredblamehead() { mrblame picked '"old"' 2 head; }
t_mainredblamenewer() { mrblame picked '"new"' 2 newer; }
t_mainredblameagain() { mrblame picked '"new"' 1 again; }

# bkinit <text of tests/x.test.sh>: the case's repository, with that test file. bkland <card> <issue> <the rest of its
# test line, as JSON>: a landing of that card that changes lib/a.sh, with its test line and landed line in the case's
# card records. bkblame <case>: the card brokeby() blames for <case> of tests/x.test.sh at HEAD, as brokeby() reads them.
bkinit() { BR=$T/$CASE/r; mkdir -p "$BR/tests" "$BR/lib" && git -C "$BR" init -q && printf '%s\n' "$1" > "$BR/tests/x.test.sh" || fail "the repository"; }
bkland() {
  echo "$1" > "$BR/lib/a.sh"; git -C "$BR" add -A; git -C "$BR" commit -qm "$1"
  jq -cn --arg c "$1" --argjson n "$2" --arg s "$(git -C "$BR" rev-parse HEAD)" --argjson t "$3" \
    '({card: $c, issue: $n, step: "test", result: "pass"} + $t), {card: $c, issue: $n, step: "landed", result: "ok", sha: $s}' >> "$T/$CASE/cards.jsonl"
}
bkblame() {
  ( cd "$BR" && eval "$(sed -n '/^brokeby() {/,/^}/p; /^landingof() {/,/^}/p; /^TESTLINK_DEPTH=/p' "$SRC/lib/mainred.sh")"
    stdb() { cat "$T/$CASE/cards.jsonl"; }
    brokeby tests/x.test.sh HEAD tests/x.test.sh "$1" | jq -r .card )
}

# Bug (O255): brokeby() took a card's test line that names the file in why or times as a run of the red case, before it
# looked at ranCases; a card that ran only some cases of the file (its ranCases for the file lack the case) stopped the
# walk, and the landing after it was blamed. Landings, oldest first: l1 ran the whole file (why alone), p2 ran only
# `other` of it (why and ranCases), b3 ran nothing of it. For the case `partial`, the landing after l1 broke it: p2.
t_brokebypartial() {
  local got
  bkinit $'t_partial() { :; }\nt_other() { :; }'
  bkland l1 1 '{"why": {"tests/x.test.sh": "linked"}}'
  bkland p2 2 '{"why": {"tests/x.test.sh": "linked"}, "ranCases": {"tests/x.test.sh": ["other"]}}'
  bkland b3 3 '{}'
  got=$(bkblame partial) || fail "brokeby found no landing: $got"
  [ "$got" = p2 ] || fail "brokeby for the case partial blamed $got, not p2, the landing after the last one that ran it (l1)"
}

# Bug (O255, review): a test line's ranCases for another file that the test file names (here tests/y.test.sh, in a
# comment) were read as a partial run of this file, so its full run (times) did not count and the walk went past it.
# Landings, oldest first: l1 ran the whole file, f2 ran the whole file and only `zz` of y.test.sh, b3 ran nothing of it.
# For the case `partial`, the landing after f2 broke it: b3.
t_brokebyother() {
  local got
  bkinit $'# its cases join those of tests/y.test.sh\nt_partial() { :; }'
  bkland l1 1 '{"why": {"tests/x.test.sh": "linked"}}'
  bkland f2 2 '{"times": {"tests/x.test.sh": 3}, "ranCases": {"tests/y.test.sh": ["zz"]}}'
  bkland b3 3 '{}'
  got=$(bkblame partial) || fail "brokeby found no landing: $got"
  [ "$got" = b3 ] || fail "brokeby for the case partial blamed $got, not b3, the landing after f2, whose test line ran the whole file and some cases of y.test.sh"
}

# Bug (O252): mainred() gave jq the links of the landing that broke a case as one argument (--argjson), testlinks()
# main's whole .conveyor/test-links.json and the new links, and linksonly() main's copy too; over 128 KiB Linux refuses
# to start jq, so the case's landing was not recorded, the fix card's links were not staged, and its change was not
# taken as the links alone. Each map here is over 128 KiB: main's links are 2,000 entries, and the landing that broke
# tests/b.test.sh changes 2,000 files of long names, so its links in the main-red record, and the new links testlinks()
# stages, are 2,000 entries too. The record names the landing with all its links, they are staged beside main's, and
# the change is still the links alone.
t_mainredbiglinks() {
  local w=$T/$CASE got s
  linkfix "$(jq -cn '[range(2000) | {key: "lib/\(.)-\("x" * 60).sh", value: ["tests/t.test.sh"]}] | from_entries')"
  rm -f "$w/mainred.json"; mkdir -p "$w/fix/src" "$w/fix/tests" && echo 't_b() { :; }' > "$w/fix/tests/b.test.sh" \
    && seq 2000 | sed "s/\$/-$(printf 'y%.0s' {1..60}).sh/" | (cd "$w/fix/src" && xargs touch) \
    && git -C "$w/fix" add -A && git -C "$w/fix" commit -qm landing && s=$(git -C "$w/fix" rev-parse HEAD) || fail "the landing of 2,000 files"
  [ "$(wc -c < "$w/fix/.conveyor/test-links.json")" -gt 131072 ] || fail "main's links over 128 KiB were not made"
  got=$( cd "$w/fix" && eval "$(linkfns)" && eval "$(sed -n '/^mainred() {/,/^}/p; /^landingof() {/,/^}/p' "$SRC/lib/mainred.sh")"
    export MAINRED=$w/mainred.json
    mainred c9 "tests/b.test.sh: b" tests/b.test.sh "$s" "$s cbreak 5" && jq -c '.reds[0].card = "cfix"' "$MAINRED" > "$MAINRED.new" && mv "$MAINRED.new" "$MAINRED" \
      && testlinks cfix "$w/fix" && linksonly cfix "$w/fix" && echo only ) || fail "mainred(), testlinks() or linksonly() failed with link maps over 128 KiB: $got"
  [ "$(jq -c '.reds[0].cases[0] | [.landing.card, (.links | length), (.links | [.[]] | unique)]' "$w/mainred.json" 2>/dev/null)" = '["cbreak",2000,[["tests/b.test.sh"]]]' ] \
    || fail "with the landing's links over 128 KiB, the main-red record does not name the landing cbreak with its 2,000 links: $(head -c 300 "$w/mainred.json" 2>&1)"
  [ "$got" = only ] && jq -e 'length == 4000 and .["src/1-\("y" * 60).sh"] == ["tests/b.test.sh"]' "$w/fix/.conveyor/test-links.json" >/dev/null \
    && [ "$(git -C "$w/fix" diff --cached --name-only)" = .conveyor/test-links.json ] \
    || fail "with main's links and the new links each over 128 KiB, the new links were not staged beside main's, or the change was not the links alone: $got"
}
# Issue 1487. Bug it catches: depkey() read only the stat of node_modules itself, so restoring one file deep in it
# (node_modules/jsdom/lib/api.js, as a hand repair does) left the key as it was, and mainprobe() reused a failure kept
# at the same commit from before the repair. The broken and the restored file have the same size and mtime, so only
# the change time, which no program sets back, tells them apart: a key of size or mtime alone fails here.
t_mainreddepsdeep() {
  local f k1 k2 c0 i=0
  setup "[]"; tune '.linkFromMain = ["node_modules"]'
  f=$R/node_modules/jsdom/lib/api.js
  mkdir -p "${f%/*}" && echo good > "$f" && cp -p "$f" "$STUB/api.js.was" && echo evil > "$f" && touch -r "$STUB/api.js.was" "$f" \
    || fail "main's node_modules could not be made"
  k1=$(eng depkey) && [ -n "$k1" ] || fail "depkey gave no key: $k1"
  c0=$(. "$SRC/lib/portable.sh"; p_ctimens "$f")
  # The restore must land on a later ctime tick than the break for any key to see it: copy again until it does.
  until cp -p "$STUB/api.js.was" "$f" && [ "$(. "$SRC/lib/portable.sh"; p_ctimens "$f")" != "$c0" ] || [ $((i += 1)) -gt 1000 ]; do :; done
  k2=$(eng depkey)
  [ "$k2" != "$k1" ] || fail "depkey kept its key after node_modules/jsdom/lib/api.js was restored (same size and mtime), so a failed probe would be reused: $k1"
}
