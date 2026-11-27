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
# names no inputs for. The test links give both to each of a.txt, c.txt and d.txt (not to e.txt, ln.txt or lst/), so a card that changes one runs
# each file its list (CONVEYOR_TEST_RERUN) does not name as passed alone, through test.fileCommand, which writes
# `<card> <file>` to $STUB/ran for each, and both pass. Card c7, whose change is d.txt (which neither file reads), runs
# them both once, on main as it was then; main then moves (c.txt, which neither reads either), and the second card's
# run is made on main as it is now. Given `binputs`, the command also names e2.txt as b.test.sh's input.
cachesetup() {
  setup "$(jq -cs . <(issue 7 2026-01-01))"
  echo 'a' > "$R/a.test.sh"; echo 'b' > "$R/b.test.sh"; echo e > "$R/e.txt"; echo e > "$R/e2.txt"; ln -s e.txt "$R/ln.txt"
  mkdir "$R/lst" && echo one > "$R/lst/one.txt"
  git -C "$R" add a.test.sh b.test.sh e.txt e2.txt ln.txt lst/one.txt || fail "main's test files could not be staged"
  linkset '{"a.txt": ["a.test.sh", "b.test.sh"], "c.txt": ["a.test.sh", "b.test.sh"], "d.txt": ["a.test.sh", "b.test.sh"]}'
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

# #1619, D1: both files name their inputs (b.test.sh reads e2.txt), and card c8 changes c.txt, which the test links
# give to both and which neither read: neither runs, and the run's log names both passes it used. Bug it catches: a
# change no test read ran the tests the links name, as the cache kept off only a file the map did not pick.
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
