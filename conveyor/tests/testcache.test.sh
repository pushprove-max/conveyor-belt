#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 300
# The limit is the whole file's in a card's test step (lib/fileeach.sh), times the load factor read as the run starts:
# its cases took 200 s run alone with a load of 46 on 16 cores (67 s of cpu), and longer beside the step's other
# files, so 120 s stopped the file at random with no case failed (#1767).
# Engine cases: the test results cache (tests(): testlist.sh cachekeep(), cacheoff()). A test file that passed with the same
# inputs is not run again by a later run, of this card or another; one whose inputs changed runs, and so does one
# whose command names no inputs for it.
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"

# Main holds two test files: a.test.sh, whose command names a.txt, e.txt, the link ln.txt (to e.txt; e2.txt holds the
# same text) and the folder lst/ (which holds one.txt) as its inputs (`TESTRUN inputs`), and b.test.sh, which it
# names no inputs for. The pack's test map (areas.json) gives both to each of a.txt, c.txt and d.txt (not to e.txt, ln.txt or lst/; not the test
# links, which give a card no test file that has a pass on record: linkslive(), #1829), so a card that changes one runs
# each file its list (CONVEYOR_TEST_RERUN) does not name as passed alone, through test.fileCommand, which writes
# `<card> <file>` to $STUB/ran for each, and both pass. Card c7, whose change is d.txt (which neither file reads), runs
# them both once, on main as it was then; main then moves (c.txt, which neither reads either), and the second card's
# run is made on main as it is now. Given `binputs`, the command also names e2.txt as b.test.sh's input.
cachesetup() {
  setup "$(jq -cs . <(issue 7 2026-01-01))"
  echo 'a' > "$R/a.test.sh"; echo 'b' > "$R/b.test.sh"; echo e > "$R/e.txt"; echo e > "$R/e2.txt"; ln -s e.txt "$R/ln.txt"
  mkdir "$R/lst" && echo one > "$R/lst/one.txt"
  git -C "$R" add a.test.sh b.test.sh e.txt e2.txt ln.txt lst/one.txt || fail "main's test files could not be staged"
  echo '{"a.txt": ["a.test.sh", "b.test.sh"], "c.txt": ["a.test.sh", "b.test.sh"], "d.txt": ["a.test.sh", "b.test.sh"]}' > "$R/areas.json" \
    && git -C "$R" add areas.json && git -C "$R" commit -qm 'test map' && git -C "$R" push -q origin main || fail "main's test map could not be set"
  tune '.test.map = "areas.json"'
  cat > "$STUB/test-cmd" <<'EOF'
f=$CONVEYOR_TEST_FILE; echo "${PWD##*/} $f" >> "$STUB/ran"
[ "$f" != a.test.sh ] || printf 'TESTRUN inputs\ta.test.sh\ta.txt\te.txt\tln.txt\tlst/\n' >> "$CONVEYOR_TEST_LOG/run.log"
[ "$f" != b.test.sh ] || [ ! -f "$STUB/binputs" ] || printf 'TESTRUN inputs\tb.test.sh\te2.txt\n' >> "$CONVEYOR_TEST_LOG/run.log"
EOF
  [ "${1:-}" != binputs ] || touch "$STUB/binputs"
  cachestep c7 'echo d > d.txt' || fail "the first card's test step failed: $(cat "$T/$CASE/c7.out" "$T/$CASE/cards/c7.test" 2>&1)"
  echo moved > "$R/c.txt"; git -C "$R" add c.txt && git -C "$R" commit -qm moved || fail "main could not move"
}
cachestep() { # <card> <its change, a shell edit staged in its worktree on main>: the card's test step, its own tests()
  local wt=$T/$CASE/cards/$1
  git -C "$R" worktree add -q --detach "$wt" && (cd "$wt" && eval "$2") && git -C "$wt" add -A || return 1
  cacherun "$1"
}
cacherun() { # <card>: the card's test step in its worktree as it is, its own tests(); its output in $T/$CASE/<card>.out
  local wt=$T/$CASE/cards/$1
  ( export CONVEYOR_MAIN=$R CONVEYOR_CARDS=$T/$CASE/cards
    . "$SRC/conveyor.sh" state-dir > /dev/null && eval "$(grep '^\. "\$HERE/lib/' "$SRC/commands/run.sh")" || exit 1
    names || exit 1; tests "$wt" || exit; testrec "$wt" 0 0 > "$wt.rec" ) > "$T/$CASE/$1.out" 2>&1
}

# D1, D3: card c8 changes c.txt, which a.test.sh does not read, after main moved. a.test.sh passed before with the same
# inputs: it is not run, and the run's log, and so its test line's why (testrec()), says so. b.test.sh names no inputs: it runs
# again, as before the cache. Bug it catches: a test file that passed was run again by every later card.
t_testcacheskip() {
  cachesetup
  cachestep c8 'echo three > c.txt' || fail "the second card's test step failed: $(cat "$T/$CASE/c8.out" "$T/$CASE/cards/c8.test" 2>&1)"
  [ "$(sed -n 's/^c8 //p' "$STUB/ran" | tr '\n' ' ')" = "b.test.sh " ] \
    || fail "the second card did not run b.test.sh alone (a.test.sh kept off by the cache): $(cat "$STUB/ran")"
  local at; at=$(git -C "$T/$CASE/cards/c7" rev-parse HEAD)
  grep -qxF "TESTRUN why"$'\t'"a.test.sh"$'\t'"kept from the run at $at" "$T/$CASE/cards/c8.testlog/cache" \
    || fail "the run's log does not say why a.test.sh did not run: $(cat "$T/$CASE/cards/c8.testlog"/* 2>&1)"
  [ "$(jq -c '.why["a.test.sh"]' "$T/$CASE/cards/c8.rec")" = "[\"kept from the run at $at\"]" ] \
    || fail "the test line's why does not say why a.test.sh did not run: $(cat "$T/$CASE/cards/c8.rec")"
  # The line's ran names the file that ran, not the one the cache kept off (which why names): bug it catches, the
  # landing pull request (landpr()) listing a.test.sh as run and leaving out b.test.sh.
  [ "$(jq -c .ran "$T/$CASE/cards/c8.rec")" = '["b.test.sh"]' ] || fail "the test line's ran is not b.test.sh alone: $(cat "$T/$CASE/cards/c8.rec")"
  # And the record check takes the line (a field it does not know sets the whole line aside).
  jq -c '{card: "c8", issue: 7, step: "test", time: "2026-01-01T00:00:00Z", tokens: {claude: 0, codex: 0}, result: "pass", sha: "", reason: ""} + .' \
    "$T/$CASE/cards/c8.rec" > "$T/$CASE/line.jsonl" && recok "$T/$CASE/line.jsonl" testrec
  ! grep -q $'^off\tb.test.sh' "$T/$CASE/cards/c8.rerun" 2>/dev/null || fail "b.test.sh, with no inputs line, was kept off"
  # #1619: the line says why b.test.sh runs with no pass used. Bug it catches: a file with no input record ran with no reason given.
  [ "$(jq -c '.why["b.test.sh"]' "$T/$CASE/cards/c8.rec")" = '["no pass of it is on record with the files it reads, so the test runs"]' ] \
    || fail "the test line's why does not say b.test.sh has no pass on record with its inputs: $(cat "$T/$CASE/cards/c8.rec")"
  # #1619: so does the first card's, run with no testcache.tsv yet. Bug it catches: with no cache, no file's reason was given.
  [ "$(jq -c '[.why["a.test.sh"], .why["b.test.sh"]] | unique' "$T/$CASE/cards/c7.rec")" = '[["no pass of it is on record with the files it reads, so the test runs"]]' ] \
    || fail "the first card's test line, with no cache yet, does not say a.test.sh and b.test.sh have no pass on record: $(cat "$T/$CASE/cards/c7.rec")"
}

# D2: card c8 changes a.txt, a.test.sh's input: a.test.sh runs again, and so does b.test.sh. Bug it catches: a file kept off
# though what it reads changed.
t_testcacheinput() {
  cachesetup
  cachestep c8 'echo three >> a.txt' || fail "the second card's test step failed: $(cat "$T/$CASE/c8.out" "$T/$CASE/cards/c8.test" 2>&1)"
  [ "$(sed -n 's/^c8 //p' "$STUB/ran" | sort | tr '\n' ' ')" = "a.test.sh b.test.sh " ] \
    || fail "the second card did not run a.test.sh after its input changed: $(cat "$STUB/ran")"
  ! grep -q 'passed before with the same inputs' "$T/$CASE/cards/c8.testlog/cache" 2>/dev/null \
    || fail "the run's log says a file was kept off: $(cat "$T/$CASE/cards/c8.testlog/cache")"
  # #1619: its log says why no pass of a.test.sh is used. Bug it catches: a file whose inputs changed ran with no reason given.
  grep -qxF $'TESTRUN why\ta.test.sh\tits inputs changed since its last pass, so the test runs again' "$T/$CASE/cards/c8.testlog/cache" \
    || fail "the run's log does not say a.test.sh's inputs changed: $(cat "$T/$CASE/cards/c8.testlog/cache" 2>&1)"
}

# #1619, D1: card c8 changes e.txt, which a.test.sh read in its last pass and which no test link or map names: a.test.sh
# runs, b.test.sh (no input record, no link for e.txt) does not. Bug it catches: the list came from the map and the links
# alone, so a change to a file a test read ran no test.
t_testcacheread() {
  cachesetup
  cachestep c8 'echo two >> e.txt' || fail "the second card's test step failed: $(cat "$T/$CASE/c8.out" "$T/$CASE/cards/c8.test" 2>&1)"
  [ "$(sed -n 's/^c8 //p' "$STUB/ran" | tr '\n' ' ')" = "a.test.sh " ] \
    || fail "a change to e.txt, which a.test.sh read, did not run a.test.sh alone: $(cat "$STUB/ran" "$T/$CASE/cards/c8.test" 2>&1)"
}

# #1698 D3, D4: card c7's test step passed a.test.sh (reads e.txt) and b.test.sh (reads e2.txt). Main then gains a
# commit that changes e.txt, c7's change is brought onto main as it is now, and its test step runs again (as after a
# failed run, or a fix round, on a main that moved): a.test.sh runs again, b.test.sh does not, and the step line names
# b.test.sh as kept from c7's first run. Bugs it catches: b.test.sh, kept off by the cache, ran again because the
# list had `main` lines (filecmd() ran every file it was given); a file whose input main changed kept its pass; and the
# step line did not name the run a file it did not run was kept from.
t_testcachemain() {
  cachesetup binputs
  local w=$T/$CASE/cards/c7 at n
  at=$(git -C "$w" rev-parse HEAD); n=$(wc -l < "$STUB/ran")
  echo two >> "$R/e.txt" && git -C "$R" commit -qam "main changes e.txt" \
    && git -C "$w" diff --cached --binary --no-renames > "$w.patch" && git -C "$w" reset -q --hard main && git -C "$w" apply --index "$w.patch" \
    || fail "c7's change could not be brought onto main as it is now"
  cacherun c7 || fail "c7's test step on main as it is now failed: $(cat "$T/$CASE/c7.out" "$w.test" 2>&1)"
  [ "$(tail -n +"$((n + 1))" "$STUB/ran" | tr '\n' ' ')" = "c7 a.test.sh " ] \
    || fail "after main changed e.txt, c7's step did not run a.test.sh alone: $(cat "$STUB/ran" "$w.test" 2>&1)"
  [ "$(jq -c '[.why["a.test.sh"], .why["b.test.sh"]]' "$w.rec")" = "[[\"its inputs changed since its last pass, so the test runs again\"],[\"kept from the run at $at\"]]" ] \
    || fail "the step line does not say a.test.sh ran for its changed input and b.test.sh was kept from the run at $at: $(cat "$w.rec")"
}

# #1619, D1: both files name their inputs (b.test.sh reads e2.txt), and card c8 changes c.txt, which the test map
# gives to both and which neither read: neither runs, and the run's log names both passes it used. Bug it catches: a
# change no test read ran the tests the map names, as the cache kept off only a file the map did not pick.
t_testcachenone() {
  cachesetup binputs
  cachestep c8 'echo three > c.txt' || fail "the second card's test step failed: $(cat "$T/$CASE/c8.out" "$T/$CASE/cards/c8.test" 2>&1)"
  [ -z "$(sed -n 's/^c8 //p' "$STUB/ran")" ] || fail "a change to c.txt, which no test read, ran tests: $(cat "$STUB/ran" "$T/$CASE/cards/c8.testlog/cache" 2>&1)"
  [ "$(grep -c "^TESTRUN why"$'\t'"[ab].test.sh"$'\t'"kept from the run at $(git -C "$T/$CASE/cards/c7" rev-parse HEAD)\$" "$T/$CASE/cards/c8.testlog/cache" 2>/dev/null)" = 2 ] \
    || fail "the run's log does not name the passes of a.test.sh and b.test.sh it used: $(cat "$T/$CASE/cards/c8.testlog/cache" 2>&1)"
}

# #1619: card c8 adds lst/two.txt to the folder a.test.sh listed: a.test.sh runs, its pass not used. Bugs it catches: a
# folder input hashed as a missing file, so the pass stood though the folder changed; and a file added to a listed
# folder selected no test.
t_testcachefolder() {
  cachesetup
  cachestep c8 'echo two > lst/two.txt' || fail "the second card's test step failed: $(cat "$T/$CASE/c8.out" "$T/$CASE/cards/c8.test" 2>&1)"
  [ "$(sed -n 's/^c8 //p' "$STUB/ran" | tr '\n' ' ')" = "a.test.sh " ] \
    || fail "a file added to lst/, which a.test.sh listed, did not run a.test.sh alone: $(cat "$STUB/ran" "$T/$CASE/cards/c8.test" "$T/$CASE/cards/c8.testlog/cache" 2>&1)"
}

# #1619: card c8 makes e.txt, which a.test.sh read, a file that can run, its text the same: a.test.sh runs. Bug it
# catches: the hash held a file's text alone, so a test that runs a file kept its pass after the file could not run.
t_testcachemode() {
  cachesetup
  cachestep c8 'chmod +x e.txt' || fail "the second card's test step failed: $(cat "$T/$CASE/c8.out" "$T/$CASE/cards/c8.test" 2>&1)"
  [ "$(sed -n 's/^c8 //p' "$STUB/ran" | tr '\n' ' ')" = "a.test.sh " ] \
    || fail "a change to whether e.txt can run did not run a.test.sh alone: $(cat "$STUB/ran" "$T/$CASE/cards/c8.testlog/cache" 2>&1)"
}

# #1619: card c8 makes the link ln.txt, which a.test.sh read, lead to e2.txt, whose text is e.txt's: a.test.sh runs.
# Bug it catches: the hash held the text the link led to, so a test that reads the link kept its pass.
t_testcachelink() {
  cachesetup
  cachestep c8 'ln -sfn e2.txt ln.txt' || fail "the second card's test step failed: $(cat "$T/$CASE/c8.out" "$T/$CASE/cards/c8.test" 2>&1)"
  [ "$(sed -n 's/^c8 //p' "$STUB/ran" | tr '\n' ' ')" = "a.test.sh " ] \
    || fail "a change to where ln.txt leads did not run a.test.sh alone: $(cat "$STUB/ran" "$T/$CASE/cards/c8.testlog/cache" 2>&1)"
}

# cachelistsetup <file>...: main holds the files (each made before), and card c7's worktree, whose change the case makes.
# #1829: the command of the changed tests, asked in its list mode with CONVEYOR_TEST_NOCASE, names l2.test.sh (a
# linked file) and k.test.sh (its last pass read the change) as files a run would start with no case: neither is on
# the list, and the list's record names both (noCase). A command that only leaves them off its list, and names no
# such file, keeps all three: a project's command that knows no links cannot take a linked file off. Bugs it catches:
# each linked file started, and its one-file run made the selection, found no case and passed; and a file was taken
# off because the command's list did not hold it.
t_testcachenocase() {
  setup '[]'
  local w=$T/$CASE/cards/c7 i ls=()
  for i in k l1 l2; do echo x > "$R/$i.test.sh"; ls+=("$i.test.sh"); done; echo d > "$R/d.md"
  linkset '{"d.md": ["l1.test.sh", "l2.test.sh"]}'; cachelistsetup "${ls[@]}" d.md
  echo two >> "$w/d.md" && git -C "$w" add -A || fail "the card's change could not be staged"
  tune '.test.changed = "sel.sh" | .test.command = "ls | grep -E \"^l1[.]test\" > \"$CONVEYOR_TEST_LIST\""'
  LASTPASS=$'k.test.sh\td.md' cachelistrun 'listcmd "$wt" && echo $TEST_FILES > "$T/$CASE/got"; jq -c .noCase "$wt.testlist" > "$T/$CASE/nc"'
  [ "$(tr ' ' '\n' < "$T/$CASE/got" | sort | paste -sd ' ' -)" = "k.test.sh l1.test.sh l2.test.sh" ] && [ "$(cat "$T/$CASE/nc")" = null ] \
    || fail "a command that lists l1.test.sh alone and names no file with no case did not keep the three files: $(cat "$T/$CASE/got" "$T/$CASE/nc" "$T/$CASE/run.out" 2>&1)"
  tune '.test.command = "ls | grep -E \"^l1[.]test\" > \"$CONVEYOR_TEST_LIST\"; [ -z \"${CONVEYOR_TEST_NOCASE:-}\" ] || ls | grep -E \"^(k|l2)[.]test\" > \"$CONVEYOR_TEST_NOCASE\""'
  LASTPASS=$'k.test.sh\td.md' cachelistrun 'listcmd "$wt" && echo $TEST_FILES > "$T/$CASE/got2"; jq -c "[.files, .noCase]" "$wt.testlist" > "$T/$CASE/nc2"'
  [ "$(cat "$T/$CASE/got2")" = l1.test.sh ] && [ "$(cat "$T/$CASE/nc2")" = '[1,["k.test.sh","l2.test.sh"]]' ] \
    || fail "the list of a change to d.md is not l1.test.sh alone, with k.test.sh and l2.test.sh named as files with no case: $(cat "$T/$CASE/got2" "$T/$CASE/nc2" "$T/$CASE/run.out" 2>&1)"
  # d.md links 8 files now, and the command lists l1.test.sh, and x.test.sh, which no link names, and names the 7
  # others as files with no case: the list is l1.test.sh and x.test.sh. Bug it catches: with the files of no case
  # taken off before the command's list was read, that list left no linked file out, so it was read as one that
  # narrowed nothing and the file it adds did not run (on card 1829, the case files of the cases the coverage map
  # selects: 32 cases ran of the 100 and more it selects).
  for i in l3 l4 l5 l6 l7 l8 x; do echo x > "$w/$i.test.sh"; done
  linkset "$(printf 'l%s.test.sh\n' 1 2 3 4 5 6 7 8 | jq -Rn '{"d.md": [inputs]}')"; cp "$R/.conveyor/test-links.json" "$w/.conveyor/test-links.json"
  git -C "$w" add -A && git -C "$w" commit -qm 'more files' && echo three >> "$w/d.md" && git -C "$w" add -A || fail "the card's files could not be added"
  tune '.test.command = "ls | grep -E \"^(l1|x)[.]test\" > \"$CONVEYOR_TEST_LIST\"; [ -z \"${CONVEYOR_TEST_NOCASE:-}\" ] || ls | grep -E \"^(k|l[2-8])[.]test\" > \"$CONVEYOR_TEST_NOCASE\""'
  LASTPASS=$'k.test.sh\td.md' cachelistrun 'listcmd "$wt" && echo $TEST_FILES > "$T/$CASE/got3"'
  [ "$(tr ' ' '\n' < "$T/$CASE/got3" | sort | paste -sd ' ' -)" = "l1.test.sh x.test.sh" ] \
    || fail "with 8 linked files, 7 of them with no case, and x.test.sh on the command's list, the list is not l1.test.sh and x.test.sh: $(cat "$T/$CASE/got3" "$T/$CASE/run.out" 2>&1)"
}
# #1829: a change to d.md, which the links give 400 test files with long names (a list of more than 4096 bytes): each
# is on the list, once. Bug it catches: a lookup in the list by `printf | grep -q` failed under pipefail when grep
# ended at its match before printf had written the whole list, so a linked file past the 5 was left off the list
# (the lookup that says it is linked failed), or one of the 5 was listed twice (the lookup that says it is listed).
t_testcachelonglist() {
  setup '[]'
  local w=$T/$CASE/cards/c7 i ls=()
  for i in $(seq 400); do ls+=("a-long-name-of-a-test-file-that-fills-the-list-of-the-card-$i.test.sh"); echo x > "$R/${ls[-1]}"; done; echo d > "$R/d.md"
  linkset "$(printf '%s\n' "${ls[@]}" | jq -Rn '{"d.md": [inputs]}')"; cachelistsetup "${ls[@]}" d.md
  echo two >> "$w/d.md" && git -C "$w" add -A || fail "the card's change could not be staged"
  LASTPASS=$'z.test.sh\tz.txt' cachelistrun 'listcmd "$wt" && printf "%s\n" "$TEST_FILES" > "$T/$CASE/got"'
  [ "$(grep -c . "$T/$CASE/got")" = 400 ] && [ "$(LC_ALL=C sort -u "$T/$CASE/got" | grep -c .)" = 400 ] \
    || fail "the list of a change that 400 test files are linked to holds $(grep -c . "$T/$CASE/got" 2>&1) lines and $(LC_ALL=C sort -u "$T/$CASE/got" 2>&1 | grep -c .) files, not each of the 400 once: $(head -c 600 "$T/$CASE/run.out")"
}
# #1829: card c7 changes its own test file own.test.sh and s.txt, which the test map gives m1 to m6; the command of
# the changed tests lists own.test.sh and m1.test.sh and leaves the rest out. The list holds own.test.sh once. Bug it
# catches: a file the command lists that the map does not give was added to the map's files, also when it was the
# card's own test file, which the list held already: it was listed twice, and started twice.
t_testcacheownonce() {
  setup '[]'
  local w=$T/$CASE/cards/c7 i ls=(own.test.sh)
  for i in 1 2 3 4 5 6; do ls+=("m$i.test.sh"); done; for i in "${ls[@]}"; do echo x > "$R/$i"; done; echo s > "$R/s.txt"
  printf '%s\n' "${ls[@]:1}" | jq -Rn '{"s.txt": [inputs]}' > "$R/areas.json"; cachelistsetup "${ls[@]}" s.txt areas.json
  tune '.test.map = "areas.json" | .test.changed = "sel.sh" | .test.command = "ls | grep -E \"^(own|m1)[.]test\" > \"$CONVEYOR_TEST_LIST\""'
  echo two >> "$w/s.txt" && echo y >> "$w/own.test.sh" && git -C "$w" add -A || fail "the card's change could not be staged"
  LASTPASS=$'z.test.sh\tz.txt' cachelistrun 'listcmd "$wt" && printf "%s\n" "$TEST_FILES" > "$T/$CASE/got"'
  [ "$(grep -cxF own.test.sh "$T/$CASE/got")" = 1 ] && grep -qxF m1.test.sh "$T/$CASE/got" \
    || fail "the list does not hold the card's own test file once, with m1.test.sh: $(paste -sd ' ' "$T/$CASE/got" 2>&1): $(head -c 600 "$T/$CASE/run.out")"
}
# #1829: card c7 changes only d.md, which no map or link gives a test. The command of the changed tests names
# l1.test.sh with its case ca and l2.test.sh whole in the file CONVEYOR_TEST_ALSO: both are on the list, l1.test.sh with
# that case alone, and the note says so. With d.md linked to l1.test.sh, that file is on the list for the link and
# runs whole: no case of it is named. Bug it catches: a card that changed only a page ran none of the cases that read
# it, as a file the command adds was taken only into a list of more than 5 files that the command narrowed.
t_testcachealso() {
  setup '[]'
  local w=$T/$CASE/cards/c7 i
  for i in l1 l2; do echo x > "$R/$i.test.sh"; done; echo d > "$R/d.md"
  printf '%s\n' 'ls | grep -E "^l[12][.]test" > "$CONVEYOR_TEST_LIST"' \
    '[ -z "${CONVEYOR_TEST_ALSO:-}" ] || printf "l1.test.sh\tca\nl2.test.sh\n" > "$CONVEYOR_TEST_ALSO"' > "$R/sel.sh"
  cachelistsetup l1.test.sh l2.test.sh d.md sel.sh
  tune '.test.changed = "sel.sh" | .test.command = "bash sel.sh"'
  echo two >> "$w/d.md" && git -C "$w" add -A || fail "the card's change could not be staged"
  LASTPASS=$'z.test.sh\tz.txt' cachelistrun 'listcmd "$wt" && echo $TEST_FILES > "$T/$CASE/got"; printf "%s" "$TEST_CASES" > "$T/$CASE/cs"; jq -c "[.files, .cases, .why]" "$wt.testlist" > "$T/$CASE/rec"'
  [ "$(tr ' ' '\n' < "$T/$CASE/got" | sort | paste -sd ' ' -)" = "l1.test.sh l2.test.sh" ] && [ "$(cat "$T/$CASE/cs")" = $'l1.test.sh\tca' ] \
    && [ "$(cat "$T/$CASE/rec")" = '[2,[{"file":"l1.test.sh","case":"ca"}],"the card ran 2 test files that the test command names for the change"]' ] \
    || fail "the list of a change to d.md is not the two files the command names, l1.test.sh with its case ca: $(cat "$T/$CASE/got" "$T/$CASE/cs" "$T/$CASE/rec" "$T/$CASE/run.out" 2>&1)"
  linkset '{"d.md": ["l1.test.sh"]}'; cp "$R/.conveyor/test-links.json" "$w/.conveyor/test-links.json"
  git -C "$w" reset -q && git -C "$w" add -f .conveyor/test-links.json && git -C "$w" commit -qm links && git -C "$w" add -A || fail "the card's links could not be set"
  LASTPASS=$'z.test.sh\tz.txt' cachelistrun 'listcmd "$wt" && echo $TEST_FILES > "$T/$CASE/got2"; printf "%s" "$TEST_CASES" > "$T/$CASE/cs2"'
  [ "$(tr ' ' '\n' < "$T/$CASE/got2" | sort | paste -sd ' ' -)" = "l1.test.sh l2.test.sh" ] && [ ! -s "$T/$CASE/cs2" ] \
    || fail "with d.md linked to l1.test.sh, the list is not the two files, l1.test.sh whole: $(cat "$T/$CASE/got2" "$T/$CASE/cs2" "$T/$CASE/run.out" 2>&1)"
}
# #1829: main changed m.txt since card c7 last ran its tests (MAINFROM), and the links give that change m.test.sh
# (`main:m.txt`): the list of c7's change to d.md, linked to l1.test.sh, holds both. When the command of the changed
# tests names m.test.sh as a file a run would start with no case, the list holds l1.test.sh alone. Bug it catches:
# the question of the files with no case did not cover the files main's links add, so such a file still started.
t_testcachemainnocase() {
  setup '[]'
  local w=$T/$CASE/cards/c7 i at
  for i in l1 m; do echo x > "$R/$i.test.sh"; done; echo d > "$R/d.md"; echo m > "$R/m.txt"
  printf '%s\n' 'ls | grep -E "^l1[.]test" > "$CONVEYOR_TEST_LIST"' \
    '[ ! -f "$PWD/../nocase-on" ] || [ -z "${CONVEYOR_TEST_NOCASE:-}" ] || echo m.test.sh > "$CONVEYOR_TEST_NOCASE"' > "$R/sel.sh"
  linkset '{"d.md": ["l1.test.sh"], "main:m.txt": ["m.test.sh"]}'
  git -C "$R" add l1.test.sh m.test.sh d.md m.txt sel.sh && git -C "$R" commit -qm files || fail "main's files could not be committed"
  at=$(git -C "$R" rev-parse HEAD); echo two >> "$R/m.txt"; cachelistsetup m.txt
  tune '.test.changed = "sel.sh" | .test.command = "bash sel.sh"'
  echo two >> "$w/d.md" && git -C "$w" add -A || fail "the card's change could not be staged"
  LASTPASS=$'z.test.sh\tz.txt' cachelistrun "MAINFROM=$at"' listcmd "$wt" && echo $TEST_FILES > "$T/$CASE/got"'
  [ "$(tr ' ' '\n' < "$T/$CASE/got" | sort | paste -sd ' ' -)" = "l1.test.sh m.test.sh" ] \
    || fail "after main changed m.txt, the list is not l1.test.sh and m.test.sh: $(cat "$T/$CASE/got" "$T/$CASE/run.out" 2>&1)"
  touch "$T/$CASE/cards/nocase-on"
  LASTPASS=$'z.test.sh\tz.txt' cachelistrun "MAINFROM=$at"' listcmd "$wt" && echo $TEST_FILES > "$T/$CASE/got2"; jq -c .noCase "$wt.testlist" > "$T/$CASE/nc"'
  [ "$(cat "$T/$CASE/got2")" = l1.test.sh ] && [ "$(cat "$T/$CASE/nc")" = '["m.test.sh"]' ] \
    || fail "with m.test.sh named as a file with no case, the list is not l1.test.sh alone: $(cat "$T/$CASE/got2" "$T/$CASE/nc" "$T/$CASE/run.out" 2>&1)"
}
# The owner, 2026-11-28: card c7 changes tests/lib.sh, a file of an area of the test map that runs all tests, which the
# last pass of each of a, b and c.test.sh read, and e.txt, which the last pass of c.test.sh read. The list is
# c.test.sh alone, and its record and note name tests/lib.sh as left to the release's whole run. A change to
# tests/lib.sh alone lists no test file. Bug it catches: the rule of the last passes had no stop for a file that every
# test reads, so a card that changed the engine cases' shared harness ran 97 test files, 95 of them whole.
t_testcacheshared() {
  setup '[]'
  local w=$T/$CASE/cards/c7 i lp=$'a.test.sh\ttests/lib.sh\ta.txt\nb.test.sh\ttests/lib.sh\nc.test.sh\ttests/lib.sh\te.txt'
  mkdir -p "$R/tests"; for i in a b c; do echo x > "$R/$i.test.sh"; done; echo l > "$R/tests/lib.sh"; echo a > "$R/a.txt"; echo e > "$R/e.txt"
  printf '%s\n' '{"area": "core", "tests": "all"}' '{"area": "core", "file": "tests/lib.sh"}' '{"area": "a", "file": "a.txt"}' \
    '{"area": "a", "test": "a.test.sh"}' > "$R/areas.json"
  cachelistsetup a.test.sh b.test.sh c.test.sh tests/lib.sh a.txt e.txt areas.json; tune '.test.map = "areas.json"'
  echo two >> "$w/tests/lib.sh" && echo two >> "$w/e.txt" && git -C "$w" add -A || fail "the card's change could not be staged"
  LASTPASS=$lp cachelistrun 'listcmd "$wt" && echo $TEST_FILES > "$T/$CASE/got"; jq -c "[.files, .sharedRead, .why]" "$wt.testlist" > "$T/$CASE/rec"'
  [ "$(cat "$T/$CASE/got")" = c.test.sh ] \
    && [ "$(cat "$T/$CASE/rec")" = '[1,["tests/lib.sh"],"The change touches tests/lib.sh, which most tests read: no test file ran only because its last pass read such a file, and the whole-suite run of the release covers that change."]' ] \
    || fail "a change to tests/lib.sh and e.txt did not list c.test.sh alone, with tests/lib.sh named as left to the release: $(cat "$T/$CASE/got" "$T/$CASE/rec" "$T/$CASE/run.out" 2>&1)"
  git -C "$w" reset -q && git -C "$w" checkout -q e.txt && git -C "$w" add -A || fail "the card's change could not be made tests/lib.sh alone"
  LASTPASS=$lp cachelistrun 'listcmd "$wt" && echo "[$TEST_FILES]" > "$T/$CASE/got2"; jq -c "[.files, .sharedRead]" "$wt.testlist" > "$T/$CASE/rec2"'
  [ "$(cat "$T/$CASE/got2")" = '[]' ] && [ "$(cat "$T/$CASE/rec2")" = '[0,["tests/lib.sh"]]' ] \
    || fail "a change to tests/lib.sh alone listed test files: $(cat "$T/$CASE/got2" "$T/$CASE/rec2" "$T/$CASE/run.out" 2>&1)"
}
cachelistsetup() {
  git -C "$R" add -- "$@" && git -C "$R" commit -qm files || fail "main's files could not be committed"
  tune '.test.fileCommand = "true" | .tests.patterns = ["*.test.sh"]'
  git -C "$R" worktree add -q --detach "$T/$CASE/cards/c7" || fail "the card's worktree could not be made"
}
# cachelistrun <code>: <code> in the engine's shell (the loop's libraries sourced, names() run), wt the card's worktree and
# $TESTCACHE holding the line `h<n><TAB>c0<TAB><line>` for the <n>th line of $LASTPASS (a pass of a file and its inputs,
# in a run on the commit c0); its output in $T/$CASE/run.out.
cachelistrun() {
  ( export CONVEYOR_MAIN=$R CONVEYOR_CARDS=$T/$CASE/cards; wt=$T/$CASE/cards/c7
    . "$SRC/conveyor.sh" state-dir > /dev/null && eval "$(grep '^\. "\$HERE/lib/' "$SRC/commands/run.sh")" || exit 1
    names && mkdir -p "${TESTCACHE%/*}" && awk '{ print "h" NR "\tc0\t" $0 }' <<<"$LASTPASS" > "$TESTCACHE" || exit 1; eval "$1" ) > "$T/$CASE/run.out" 2>&1 \
    || fail "the engine's code could not be run: $(cat "$T/$CASE/run.out")"
}

# #1619: card c7 changes the case t_one of j.test.sh and of k.test.sh, and e.txt, which k.test.sh's last pass read
# whole (j.test.sh's read f.txt): k.test.sh runs whole, and of j.test.sh only t_one. Bugs it catches: the list kept
# only k.test.sh's changed case t_one, so t_two, which can read e.txt, did not run; and a change to a test file itself
# ran it whole when a pass of it was on record, so a change to one case of j.test.sh ran every case.
t_testcachewhole() {
  setup '[]'
  local f
  for f in j k; do printf 't_one() {\n  :\n}\nt_two() {\n  :\n}\n' > "$R/$f.test.sh"; done; echo e > "$R/e.txt"; cachelistsetup j.test.sh k.test.sh e.txt
  for f in j k; do printf 't_one() {\n  echo one\n}\nt_two() {\n  :\n}\n' > "$T/$CASE/cards/c7/$f.test.sh"; done
  echo two >> "$T/$CASE/cards/c7/e.txt" && git -C "$T/$CASE/cards/c7" add -A || fail "the card's change could not be staged"
  LASTPASS=$'j.test.sh\tf.txt\nk.test.sh\te.txt' cachelistrun 'listcmd "$wt" && printf "%s|%s" "$TEST_FILES" "$TEST_CASES" > "$T/$CASE/got"'
  [ "$(cat "$T/$CASE/got" 2>&1)" = $'j.test.sh\nk.test.sh|j.test.sh\tone' ] \
    || fail "with e.txt changed, which k.test.sh read, the list did not run k.test.sh whole and j.test.sh's t_one alone (files|cases): $(cat "$T/$CASE/got" "$T/$CASE/run.out" 2>&1)"
}

# #1722: cacheoff() of a card whose list is b.test.sh alone, with a pass of a.test.sh and of b.test.sh on record, their
# inputs the same, a.test.sh's from a run on the commit c1 and b.test.sh's from one on c2: the run's log names b.test.sh's
# pass as used, from the run at c2, not a.test.sh's. Bugs it catches: the log named every file with a pass on record as
# reused, also one the card never selected; and a file it did not run again named another file's run.
t_testcachelisted() {
  setup '[]'
  echo a > "$R/a.test.sh"; echo b > "$R/b.test.sh"; echo e > "$R/e.txt"; cachelistsetup a.test.sh b.test.sh e.txt
  LASTPASS='' cachelistrun 'printf "a.test.sh\te.txt\nb.test.sh\te.txt\n" | cachesums "$wt" | awk '\''BEGIN { FS = OFS = "\t" } { $1 = $1 OFS "c" NR } 1'\'' > "$TESTCACHE" \
    && TEST_FILES=b.test.sh cacheoff "$wt" > "$T/$CASE/got"'
  [ "$(cat "$T/$CASE/got" 2>&1)" = $'TESTRUN why\tb.test.sh\tkept from the run at c2' ] \
    || fail "with a list of b.test.sh alone, the log does not name b.test.sh's pass alone as used: $(cat "$T/$CASE/got" "$T/$CASE/run.out" 2>&1)"
}

# #1619: cachesums() of a pass that listed lst/ and looked for gone, which was not there. Making the file lst/one.txt
# a folder of that name changes the hash, and so does making gone a folder; cachereaders() picks u.test.sh, which
# looked for gone, for a change that adds gone/x. Bugs it catches: the listing named one.txt as a file and as a folder
# alike, so a test that listed lst/ kept its pass; and a path that was not there counted the same as a folder made
# there since, and a change that added a file under it ran no test that looked for it.
t_testcachekinds() {
  setup '[]'
  mkdir "$R/lst" && echo one > "$R/lst/one.txt" && echo t > "$R/t.test.sh" && echo u > "$R/u.test.sh"; cachelistsetup t.test.sh u.test.sh lst/one.txt
  LASTPASS=$'t.test.sh\tlst/\tgone\nu.test.sh\tgone' cachelistrun 'h() { printf "t.test.sh\tlst/\tgone\n" | cachesums "$wt" | cut -f1; }
    h > "$T/$CASE/h0" && git -C "$wt" rm -q lst/one.txt && mkdir -p "$wt/lst/one.txt" && echo x > "$wt/lst/one.txt/f.js" && git -C "$wt" add lst \
      && h > "$T/$CASE/h1" && mkdir "$wt/gone" && echo x > "$wt/gone/x" && git -C "$wt" add gone && h > "$T/$CASE/h2" \
      && cachereaders "$(git -C "$wt" diff --cached --name-status --no-renames HEAD -- gone)" > "$T/$CASE/readers"'
  [ -s "$T/$CASE/h0" ] && ! cmp -s "$T/$CASE/h0" "$T/$CASE/h1" \
    || fail "making lst/one.txt a folder of that name did not change the hash of a pass that listed lst/: $(cat "$T/$CASE/h0" "$T/$CASE/h1" "$T/$CASE/run.out" 2>&1)"
  [ -s "$T/$CASE/h1" ] && ! cmp -s "$T/$CASE/h1" "$T/$CASE/h2" \
    || fail "making gone, which was not there, a folder did not change the hash: $(cat "$T/$CASE/h1" "$T/$CASE/h2" "$T/$CASE/run.out" 2>&1)"
  [ "$(cat "$T/$CASE/readers" 2>&1)" = $'t.test.sh\nu.test.sh' ] \
    || fail "a change that adds gone/x did not pick the tests that looked for gone: $(cat "$T/$CASE/readers" "$T/$CASE/run.out" 2>&1)"
}

# #1619: cachekeep() of a run that passed the engine case files f.test.sh, every case of it named in the log's
# `TESTRUN case` lines, and g.test.sh, only t_one of its two cases named: f.test.sh's pass is kept, g.test.sh's is
# not; f.test.sh's pass names the commit the run was on (the worktree's HEAD). Bugs it catches: no engine case file's
# pass was kept, as every `TESTRUN case` line counted as a run of some cases; a run of some cases of a file kept a pass
# of the whole file; and a kept pass named no run, so a later step could not say which run it was kept from.
t_testcachekeep() {
  setup '[]'
  local f
  for f in f g; do printf 't_one() {\n  :\n}\nt_two() {\n  :\n}\n' > "$R/$f.test.sh"; done; echo e > "$R/e.txt"; cachelistsetup f.test.sh g.test.sh e.txt
  mkdir -p "$T/$CASE/cards/c7.testlog" && { printf 'TESTRUN case\t%s\t%s\n' f.test.sh one f.test.sh two g.test.sh one
    printf -- '-- ok %s\n' f.test.sh g.test.sh; printf 'TESTRUN inputs\t%s\te.txt\n' f.test.sh g.test.sh; } > "$T/$CASE/cards/c7.testlog/run.log" \
    || fail "the run's log could not be written"
  LASTPASS=$'x.test.sh\te.txt' cachelistrun 'cachekeep "$wt" && cut -f2,3 "$TESTCACHE" > "$T/$CASE/got"'
  [ "$(sort -k2 "$T/$CASE/got" 2>&1)" = "$(git -C "$T/$CASE/cards/c7" rev-parse HEAD)"$'\tf.test.sh\nc0\tx.test.sh' ] \
    || fail "the cache does not hold f.test.sh's pass (every case run) with its run's commit, and not g.test.sh's (one of two run): $(cat "$T/$CASE/got" "$T/$CASE/run.out" 2>&1)"
}

# #1619: a change to doc.md, which the map links to ten test files, of which a card runs five; l7.test.sh, past those
# five, read doc.md in its last pass, so it runs too, and the list says four were left out. Bug it catches: the list
# said five were left out with six of the ten on it.
t_testcachecap() {
  setup '[]'
  local i ls=()
  for i in 0 1 2 3 4 5 6 7 8 9; do echo x > "$R/l$i.test.sh"; ls+=("l$i.test.sh"); done; echo d > "$R/doc.md"; cachelistsetup "${ls[@]}" doc.md
  echo two >> "$T/$CASE/cards/c7/doc.md" && git -C "$T/$CASE/cards/c7" add -A || fail "the card's change could not be staged"
  LASTPASS=$'l7.test.sh\tdoc.md' cachelistrun 'testsel() { printf "%s\n" "{\"by\": \"map\"}" '"${ls[*]}"'; }
    listcmd "$wt" && echo $TEST_FILES > "$T/$CASE/got"'
  [ "$(cat "$T/$CASE/got" 2>&1)" = "l0.test.sh l1.test.sh l2.test.sh l3.test.sh l4.test.sh l7.test.sh" ] \
    || fail "the list of a change to doc.md is not the five linked files and l7.test.sh, which read doc.md: $(cat "$T/$CASE/got" "$T/$CASE/run.out" 2>&1)"
  jq -e '.left == 4 and (.why | endswith(" It also ran 1 more of the linked files, because their last pass read a file that the change touches."))' \
    "$T/$CASE/cards/c7.testlist" > /dev/null || fail "the list does not say four linked files were left out and why l7.test.sh ran: $(cat "$T/$CASE/cards/c7.testlist" 2>&1)"
}

# #1619: card c7's last run passed r.test.sh, whose last pass read e.txt, and q.test.sh; a fix then changes e.txt. The
# list for the run again (rerunsince()) keeps no line of r.test.sh, so it runs, and keeps q.test.sh's pass. Bug it
# catches: r.test.sh's pass stood, and runfiles() left it off, as the command's selection has no link from e.txt to it.
t_testcachefix() {
  setup '[]'
  local w=$T/$CASE/cards/c7 t1
  echo r > "$R/r.test.sh"; echo q > "$R/q.test.sh"; echo e > "$R/e.txt"; cachelistsetup r.test.sh q.test.sh e.txt
  t1=$(git -C "$w" write-tree) && printf 'change\told\nbase\t%s\ntree\t%s\npass\tr.test.sh\nfail\tr.test.sh\tone\npass\tq.test.sh\n' "$(git -C "$w" rev-parse HEAD)" "$t1" > "$w.rerun" \
    && echo two >> "$w/e.txt" && git -C "$w" add -A || fail "the fix's change could not be staged"
  LASTPASS=$'r.test.sh\te.txt' cachelistrun 'rerunsince "$wt" new "$(git -C "$wt" rev-parse HEAD)" "$(git -C "$wt" write-tree)"; echo $? > "$T/$CASE/rc"'
  [ "$(cat "$T/$CASE/rc")" = 0 ] && [ "$(sed 1,3d "$w.rerun")" = $'pass\tq.test.sh\nchanged\te.txt' ] \
    || fail "after a fix changed e.txt, which r.test.sh's last pass read, the list still keeps r.test.sh, or lost q.test.sh's pass (exit $(cat "$T/$CASE/rc")): $(cat "$w.rerun" "$T/$CASE/run.out" 2>&1)"
}

# The engine's runner sources every case file to find its cases (conveyor.test.sh: `. tests/*.test.sh`), so the traced
# pass of each engine case file names every other one, and their folder, as read. Card c7 changes only t_one of the
# engine case file conveyor/tests/j.test.sh; the passes on record of the case file conveyor/tests/k.test.sh (which read
# e.txt too) and of s.test.sh, a test run on its own, read it and listed conveyor/tests/. The card's list is s.test.sh
# whole and j.test.sh's t_one (listcmd(), the whole path a card's test step takes); a case file added to
# conveyor/tests/ picks s.test.sh alone, and a change to e.txt still picks k.test.sh (cachereaders()). Bugs it catches:
# a change to one case of review.test.sh ran 34 other engine case files whole (2026-11-27); and a rule that kept every
# changed test file from picking its readers left out a test that reads it in a run of its own (spdx.test.sh, which
# reads each file's SPDX line).
t_testcachetestreads() {
  setup '[]'
  local f
  mkdir -p "$R/conveyor/tests" || fail "the case folder could not be made"
  for f in j k; do printf 't_one() {\n  :\n}\nt_two() {\n  :\n}\n' > "$R/conveyor/tests/$f.test.sh"; done; echo s > "$R/s.test.sh"; echo e > "$R/e.txt"
  # -f: the scratch repo's .gitignore names conveyor/.
  git -C "$R" add -f conveyor/tests || fail "the case files could not be added"
  cachelistsetup s.test.sh e.txt
  printf 't_one() {\n  echo one\n}\nt_two() {\n  :\n}\n' > "$T/$CASE/cards/c7/conveyor/tests/j.test.sh" && git -C "$T/$CASE/cards/c7" add -A \
    || fail "the card's change could not be staged"
  LASTPASS=$'conveyor/tests/k.test.sh\tconveyor/tests/\tconveyor/tests/j.test.sh\te.txt\ns.test.sh\tconveyor/tests/\tconveyor/tests/j.test.sh' \
    cachelistrun 'listcmd "$wt" && printf "%s|%s" "$TEST_FILES" "$TEST_CASES" > "$T/$CASE/got" \
    && cachereaders $'"'"'A\tconveyor/tests/n.test.sh'"'"' > "$T/$CASE/add" && cachereaders $'"'"'M\te.txt'"'"' > "$T/$CASE/src"'
  [ "$(cat "$T/$CASE/got" 2>&1)" = $'conveyor/tests/j.test.sh\ns.test.sh|conveyor/tests/j.test.sh\tone' ] \
    || fail "a change to one case of conveyor/tests/j.test.sh, which the passes of conveyor/tests/k.test.sh and s.test.sh read, did not run s.test.sh whole and j.test.sh's t_one alone (files|cases): $(cat "$T/$CASE/got" "$T/$CASE/run.out" 2>&1)"
  [ "$(cat "$T/$CASE/add" 2>&1)" = s.test.sh ] \
    || fail "a case file added to conveyor/tests/, which both passes listed, did not pick s.test.sh alone: '$(cat "$T/$CASE/add" 2>&1)' $(cat "$T/$CASE/run.out")"
  [ "$(cat "$T/$CASE/src" 2>&1)" = conveyor/tests/k.test.sh ] \
    || fail "a change to e.txt, which conveyor/tests/k.test.sh's pass read, did not pick it alone: '$(cat "$T/$CASE/src" 2>&1)' $(cat "$T/$CASE/run.out")"
}

# Every case starts the engine, which sources every library file, so the traced pass of each engine case file names
# each of them as read. The pass of the case file conveyor/tests/k.test.sh and of s.test.sh, a test run on its own,
# read conveyor/lib/x.sh: a change to it picks s.test.sh alone (cachereaders()); the test map gives a card the case
# files of a library file (listcmd()). Bug it catches: a change to bugproof.sh picked budgetkept.test.sh and 24 more
# case files that run none of its functions (2026-11-27).
t_testcachelibreads() {
  setup '[]'
  mkdir -p "$R/conveyor/tests" "$R/conveyor/lib" && echo k > "$R/conveyor/tests/k.test.sh" && echo x > "$R/conveyor/lib/x.sh" && echo s > "$R/s.test.sh" \
    && git -C "$R" add -f conveyor || fail "the engine files could not be added"
  cachelistsetup s.test.sh
  LASTPASS=$'conveyor/tests/k.test.sh\tconveyor/lib/x.sh\ns.test.sh\tconveyor/lib/x.sh' \
    cachelistrun 'cachereaders $'"'"'M\tconveyor/lib/x.sh'"'"' > "$T/$CASE/got"'
  [ "$(cat "$T/$CASE/got" 2>&1)" = s.test.sh ] \
    || fail "a change to conveyor/lib/x.sh, which both passes read, did not pick s.test.sh alone: '$(cat "$T/$CASE/got" 2>&1)' $(cat "$T/$CASE/run.out")"
}

# A file the change adds holds a new name in its own folder alone. The pass of t.test.sh listed ./, of u.test.sh
# docs/ and of v.test.sh docs/sub/: a change that adds docs/sub/new.md picks v.test.sh alone, and one that adds top.md
# picks t.test.sh alone (cachereaders()). Bug it catches: an added file marked each folder above it too, so adding a
# case file picked each test that listed ./ or conveyor/.
t_testcacheaddfolder() {
  setup '[]'
  echo t > "$R/t.test.sh"; echo u > "$R/u.test.sh"; echo v > "$R/v.test.sh"; cachelistsetup t.test.sh u.test.sh v.test.sh
  LASTPASS=$'t.test.sh\t./\nu.test.sh\tdocs/\nv.test.sh\tdocs/sub/' cachelistrun 'cachereaders $'"'"'A\tdocs/sub/new.md'"'"' > "$T/$CASE/sub" \
    && cachereaders $'"'"'A\ttop.md'"'"' > "$T/$CASE/top"'
  [ "$(cat "$T/$CASE/sub" 2>&1)" = v.test.sh ] \
    || fail "a change that adds docs/sub/new.md did not pick v.test.sh alone, which listed docs/sub/: '$(cat "$T/$CASE/sub" 2>&1)' $(cat "$T/$CASE/run.out")"
  [ "$(cat "$T/$CASE/top" 2>&1)" = t.test.sh ] \
    || fail "a change that adds top.md did not pick t.test.sh alone, which listed ./: '$(cat "$T/$CASE/top" 2>&1)' $(cat "$T/$CASE/run.out")"
}

# Card c7 changes the case t_one of its own test file o.test.sh and the file src.txt, to which the test map gives
# o.test.sh and seven files m0 to m6.test.sh. The list is o.test.sh's t_one and five of the seven (CARDLINKED), and its
# note says so and that two did not run (listcmd()). Bug it catches: a card with a test file of its own ran none of
# the tests the map gives its other files, so a card that added redflaky.test.sh and changed bugproof.sh ran none of
# the 25 main-red cases the coverage map gives the functions it changed (#1827).
t_testcacheownmap() {
  setup '[]'
  local i ms=()
  printf 't_one() {\n  :\n}\nt_two() {\n  :\n}\n' > "$R/o.test.sh"; echo s > "$R/src.txt"
  for i in 0 1 2 3 4 5 6; do echo x > "$R/m$i.test.sh"; ms+=("m$i.test.sh"); done; cachelistsetup o.test.sh src.txt "${ms[@]}"
  printf 't_one() {\n  echo one\n}\nt_two() {\n  :\n}\n' > "$T/$CASE/cards/c7/o.test.sh" && echo two >> "$T/$CASE/cards/c7/src.txt" \
    && git -C "$T/$CASE/cards/c7" add -A || fail "the card's change could not be staged"
  LASTPASS='' cachelistrun 'testsel() { printf "%s\n" "{\"by\": \"map\"}" o.test.sh '"${ms[*]}"'; }
    listcmd "$wt" && printf "%s|%s" "$(echo $TEST_FILES)" "$TEST_CASES" > "$T/$CASE/got"'
  [ "$(cat "$T/$CASE/got" 2>&1)" = $'o.test.sh m0.test.sh m1.test.sh m2.test.sh m3.test.sh m4.test.sh|o.test.sh\tone' ] \
    || fail "the list of a change to o.test.sh's t_one and src.txt is not t_one and five of the seven files the map gives src.txt (files|cases): $(cat "$T/$CASE/got" "$T/$CASE/run.out" 2>&1)"
  jq -e '.left == 2 and .why == "the card ran 1 changed case of 1 test file, and 5 more test files for the other files that the change touches (2 of the 7 did not run, as a card runs at most 5 of them, those that failed most recently first)"' \
    "$T/$CASE/cards/c7.testlist" > /dev/null || fail "the list does not say five map files ran and two did not: $(cat "$T/$CASE/cards/c7.testlist" 2>&1)"
}


# The links key t/*.test.sh links each test file of t/ to t/x.test.sh. Card c7 changes the case t_one of t/a.test.sh:
# its list is t_one and t/x.test.sh whole (changelinks()). The test t/sub/b.test.sh matches no key, and this
# repository's own links bring testcountrunner.test.sh for a case file (linksto()). Bug it catches (#1827 review): a
# card that added a case file whose function name another case file defines did not run testcountrunner.test.sh,
# whose t_casefnclash is the one check of such a name, and the duplicate landed.
t_testcachelinkglob() {
  setup '[]'
  local w=$T/$CASE/cards/c7
  mkdir -p "$R/t/sub" && printf 't_one() {\n  :\n}\nt_two() {\n  :\n}\n' > "$R/t/a.test.sh" && echo x > "$R/t/x.test.sh" && echo b > "$R/t/sub/b.test.sh"
  linkset '{"t/*.test.sh": ["t/x.test.sh"]}'; cachelistsetup t/a.test.sh t/x.test.sh t/sub/b.test.sh
  printf 't_one() {\n  echo one\n}\nt_two() {\n  :\n}\n' > "$w/t/a.test.sh" && git -C "$w" add -A || fail "the card's change could not be staged"
  LASTPASS='' cachelistrun 'listcmd "$wt" && printf "%s|%s" "$(echo $TEST_FILES)" "$TEST_CASES" > "$T/$CASE/got" \
    && echo t/sub/b.test.sh | linksto "$wt" > "$T/$CASE/sub" && echo conveyor/tests/zz.test.sh | linksto "$SRC/.." > "$T/$CASE/own"'
  [ "$(cat "$T/$CASE/got" 2>&1)" = $'t/a.test.sh t/x.test.sh|t/a.test.sh\tone' ] \
    || fail "a change to t_one of t/a.test.sh did not run t_one and t/x.test.sh, which t/*.test.sh links, whole (files|cases): $(cat "$T/$CASE/got" "$T/$CASE/run.out" 2>&1)"
  [ ! -s "$T/$CASE/sub" ] || fail "t/sub/b.test.sh, in a folder below t/, matched t/*.test.sh: $(cat "$T/$CASE/sub")"
  [ "$(cat "$T/$CASE/own" 2>&1)" = conveyor/tests/testcountrunner.test.sh ] \
    || fail "this repository's links do not bring testcountrunner.test.sh for a change to a case file: '$(cat "$T/$CASE/own" 2>&1)'"
}

# Issue 1829: .conveyor/test-links.json links d.md to j.test.sh, k.test.sh and l1.test.sh to l6.test.sh (a landing that
# changed d.md broke each once). j.test.sh's last pass read e.txt alone, k.test.sh's read d.md, and the six have no pass
# on record. Card c7 changes d.md: its list is the six (their links stand) and k.test.sh (its last pass read d.md), not
# j.test.sh, which d.md cannot reach; and not when the pack's command of the changed tests lists j.test.sh, as it
# reads the links file itself. Bug it catches: a link ran its test whole for every later change to the file,
# whatever the test read (8 of card #1829's test files read no file it changed).
t_testcachelinkread() {
  setup '[]'
  local w=$T/$CASE/cards/c7 i ls=() want='l1.test.sh l2.test.sh l3.test.sh l4.test.sh l5.test.sh l6.test.sh k.test.sh'
  for i in j k l1 l2 l3 l4 l5 l6; do echo x > "$R/$i.test.sh"; ls+=("$i.test.sh"); done; echo d > "$R/d.md"; echo e > "$R/e.txt"
  linkset "$(printf '%s\n' "${ls[@]}" | jq -Rn '{"d.md": [inputs]}')"; cachelistsetup "${ls[@]}" d.md e.txt
  echo two >> "$w/d.md" && git -C "$w" add -A || fail "the card's change could not be staged"
  LASTPASS=$'j.test.sh\te.txt\nk.test.sh\td.md' cachelistrun 'listcmd "$wt" && echo $TEST_FILES > "$T/$CASE/got"
    echo d.md | linksto "$wt" all | grep -c . > "$T/$CASE/all"'
  [ "$(tr ' ' '\n' < "$T/$CASE/got" | sort | paste -sd ' ' -)" = "$(tr ' ' '\n' <<<"$want" | sort | paste -sd ' ' -)" ] \
    || fail "the list of a change to d.md is not the six linked files with no pass on record and k.test.sh, which read d.md: $(cat "$T/$CASE/got" "$T/$CASE/run.out" 2>&1)"
  [ "$(cat "$T/$CASE/all" 2>&1)" = 8 ] || fail "linksto all does not give each of the 8 links the file holds: $(cat "$T/$CASE/all" 2>&1)"
  # The command lists j.test.sh and l1.test.sh by a pattern: a test file that the command names is taken as its runner.
  tune '.test.changed = "sel.sh" | .test.command = "ls | grep -E \"^(j|l1)[.]test\" > \"$CONVEYOR_TEST_LIST\""'
  LASTPASS=$'j.test.sh\te.txt\nk.test.sh\td.md' cachelistrun 'listcmd "$wt" && echo $TEST_FILES > "$T/$CASE/got2"'
  [ "$(tr ' ' '\n' < "$T/$CASE/got2" | sort | paste -sd ' ' -)" = "$(tr ' ' '\n' <<<"$want" | sort | paste -sd ' ' -)" ] \
    || fail "with a command of the changed tests that lists j.test.sh and l1.test.sh, the list is not the six and k.test.sh: $(cat "$T/$CASE/got2" "$T/$CASE/run.out" 2>&1)"
}

# cachekeep() of a run that passed d.test.sh, whose log names its reads in a `TESTRUN reads` line (it read a path
# that is not tracked, such as node_modules: .conveyor/test-changed.sh inputsof()), e.txt and pkg/package.json, which
# was not there. The cache holds the line, so cachereaders() picks d.test.sh for a change that adds pkg/package.json,
# but cachehits() does not keep it off, though its inputs are the same. Bugs it catches: such a test named no inputs,
# so adding the package.json that Node looked for beside it ran no test; and a pass kept on such a line kept the test
# off after a file of node_modules, which no input names, changed.
t_testcachereads() {
  setup '[]'
  echo d > "$R/d.test.sh"; echo e > "$R/e.txt"; cachelistsetup d.test.sh e.txt
  mkdir -p "$T/$CASE/cards/c7.testlog" && printf -- '-- ok d.test.sh\nTESTRUN reads\td.test.sh\te.txt\tpkg/package.json\n' > "$T/$CASE/cards/c7.testlog/run.log" \
    || fail "the run's log could not be written"
  LASTPASS=$'x.test.sh\te.txt' cachelistrun 'cachekeep "$wt" && cut -f3- "$TESTCACHE" > "$T/$CASE/got" && cachehits "$wt" > "$T/$CASE/hits" \
    && cachereaders $'"'"'A\tpkg/package.json'"'"' > "$T/$CASE/readers"'
  grep -qxF $'d.test.sh\te.txt\tpkg/package.json' "$T/$CASE/got" \
    || fail "given the log line 'TESTRUN reads d.test.sh e.txt pkg/package.json', the cache does not hold d.test.sh's reads: $(cat "$T/$CASE/got" "$T/$CASE/run.out" 2>&1)"
  [ "$(cat "$T/$CASE/readers")" = d.test.sh ] \
    || fail "given the log line 'TESTRUN reads d.test.sh e.txt pkg/package.json', a change that adds pkg/package.json does not pick d.test.sh: '$(cat "$T/$CASE/readers")' $(cat "$T/$CASE/run.out")"
  ! grep -qxF d.test.sh "$T/$CASE/hits" \
    || fail "given the log line 'TESTRUN reads d.test.sh e.txt pkg/package.json', the cache keeps d.test.sh off, though it read a path no input names"
}

# Card 1798: the lines on record. v.test.sh and w.test.sh passed whole and read s.js; the run's log names the lines
# v.test.sh ran of it (1 and 2, and the ends of 1 to 3), and none for w.test.sh. The pass keeps them ($TESTLINES), and a
# card's list holds v.test.sh only for a change that touches them: a ran line changed, or lines added where it ran;
# w.test.sh, with no lines on record, is listed for each change, as is v.test.sh when its blob is gone. Bug it
# catches: each test file whose last pass read a changed file was listed, whatever lines of it the test ran (the 96
# page tests of the Board for a change to one function of one script).
t_testcachelines() {
  setup '[]'
  local wt=$T/$CASE/cards/c7 b lp=$'v.test.sh\ts.js\nw.test.sh\ts.js' both=$'v.test.sh\nw.test.sh'
  echo v > "$R/v.test.sh"; echo w > "$R/w.test.sh"; printf '%s\n' one two three four five six > "$R/s.js"; cachelistsetup v.test.sh w.test.sh s.js
  b=$(git -C "$R" rev-parse HEAD:s.js)
  mkdir -p "$wt.testlog" && { printf -- '-- ok %s\n' v.test.sh w.test.sh; printf 'TESTRUN inputs\t%s\ts.js\n' v.test.sh w.test.sh
    printf 'TESTRUN lines\tv.test.sh\ts.js\t%s\t1-2\t1-3\n' "$b"; printf 'TESTRUN lines\tx.test.sh\ts.js\t%s\t1\t1\n' "$b"; } > "$wt.testlog/run.log" \
    || fail "the run's log could not be written"
  # listed <code before the list> <s.js's lines>...: the card's list for that s.js, staged.
  listed() { local c=$1; shift; printf '%s\n' "$@" > "$wt/s.js" && git -C "$wt" add -A || fail "the card's change could not be staged"
    LASTPASS=$lp cachelistrun "$c"' listcmd "$wt" && printf "%s\n" "$TEST_FILES" > "$T/$CASE/got"'; cat "$T/$CASE/got"; }
  [ "$(listed 'cachekeep "$wt" && cp "$TESTLINES" "$T/$CASE/kept" || exit 1;' one two three four FIVE six)" = w.test.sh ] \
    && [ "$(cat "$T/$CASE/kept")" = "v.test.sh"$'\t'"s.js"$'\t'"$b"$'\t'"1-2"$'\t'"1-3" ] \
    || fail "the pass did not keep v.test.sh's lines alone, or a change to line 5, which it did not run, did not list w.test.sh alone: $(cat "$T/$CASE/got" "$T/$CASE/kept" "$T/$CASE/run.out" 2>&1)"
  [ "$(listed '' one TWO three four five six)" = "$both" ] || fail "a change to line 2, which v.test.sh ran, did not list both: $(cat "$T/$CASE/got" "$T/$CASE/run.out" 2>&1)"
  [ "$(listed '' one two three new four five six)" = "$both" ] || fail "a line added after line 3, whose end v.test.sh ran, did not list both: $(cat "$T/$CASE/got" "$T/$CASE/run.out" 2>&1)"
  [ "$(listed '' one two three four five six seven)" = w.test.sh ] || fail "a line added after line 6, which v.test.sh did not run, did not list w.test.sh alone: $(cat "$T/$CASE/got" "$T/$CASE/run.out" 2>&1)"
  [ "$(listed 'printf "v.test.sh\ts.js\t%040d\t1-2\t1-3\n" 0 > "$TESTLINES";' one two three four FIVE six)" = "$both" ] \
    || fail "with the blob of its lines gone, v.test.sh was not listed for a change to s.js: $(cat "$T/$CASE/got" "$T/$CASE/run.out" 2>&1)"
}
