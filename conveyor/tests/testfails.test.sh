#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 300
# Engine cases: what a failed test run says went wrong, read from the runners' logs and the output (testfails()).
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"

# Bug: a test printed the `== ` line of a file two runners ran before the second runner began that file. The two
# earliest lines were read as the runners' own and the runner's real, later line was thrown away, so the failing case
# after it went to the file before it alone: the Board named another file for the failure and not the one that
# failed. Which of the three lines the test printed cannot be told, so the case is under each file it can be of.
# What a failed run says went wrong, as a card's test line holds it (lib/testrun.sh testfails(), the line's .failures):
# the test command $T/$CASE/cmd run as a card's test step runs it, its output and its runners' logs where a card's
# worktree <w> has them (<w>.test, <w>.testlog), then read with the given exit and the step's timeout. A whole loop run
# to read them cost each case about 2 s more; testruns.test.sh's t_testfails proves a card's test line holds them.
logfails() { # <exit> [<testTimeout>]
  allfails "$@" | jq -c 'del(.passed, .okcases, .passcases)'
}
# The readers of a test's output (lib/failat.sh): the frame patterns, their jq, tapjq() (the jq of TAP's result lines), atsource()
# and wtline(), for eval.
frameread() { sed -n '/^FRAMERX=/p; /^PYFRAMERX=/p; /^FRAMEJQ=/p; /^tapjq() {/p; /^atsource() {/,/^}/p; /^wtline() {/,/^}/p' "$SRC/lib/failat.sh"; }
# logfails() with the files and cases the run passed.
allfails() { # <exit> [<testTimeout>]
  local w=$T/$CASE/wt; mkdir -p "$w.testlog"
  (cd "$T/$CASE" && CONVEYOR_TEST_LOG=$w.testlog bash cmd > "$w.test" 2>&1 < /dev/null)
  ( eval "$(frameread; sed -n '/^testfails() {/,/^}/p; /^RECJQ=/p' "$SRC/lib/testrun.sh"; sed -n '/^testlogs() {/,/^}/p' "$SRC/lib/session.sh")"
    packget() { [ -n "${PACKCMD:-}" ] && printf -v "$2" '%s' "$PACKCMD"; } # the pack's test.command: $PACKCMD, else none
    TEST_TIMEOUT=${2:-600} testfails "$w.test" "$1" )
}
# Why the card's run allfails() last ran gave no result, given its exit and the step's timeout (voidrun()); fails
# when the run gave a result.
void() { # <exit> [<testTimeout>]
  ( eval "$(sed -n '/^voidrun() {/,/^}/p; /^testfails() {/,/^}/p' "$SRC/lib/testrun.sh"; sed -n '/^testlogs() {/,/^}/p' "$SRC/lib/session.sh")"
    packget() { [ -n "${PACKCMD:-}" ] && printf -v "$2" '%s' "$PACKCMD"; }
    TEST_TIMEOUT=${2:-600} voidrun "$T/$CASE/wt" "$1" )
}
# Issue 442: a passed node case (`✔ <name> (<n>ms)`) or TAP case (`ok <n> - <name>`) was not read as passed, only a
# line `ok <case>` with no space in its case was: a main-red fix card for a named node case always blocked with "gave
# no result". Each is a passed case under its file, named as its failure line names it; a skipped TAP case is not,
# nor node's line for the file itself (a run with a name filter that ran no case, as speedproof.sh splitstart() makes, prints it).
# R389: nor is a to-do TAP case (`ok 5 - h # TODO later`): no fixture held one, so the TODO filter was not tested.
t_testfailspassed() {
  mkdir -p "$T/$CASE"; cat > "$T/$CASE/cmd" <<'EOF'
echo "== f.test.mjs" | tee -a "$CONVEYOR_TEST_LOG/a.log"
printf '%s\n' '✔ a b, c (12.3ms)' 'ok 2 - d e' 'ok 3 - g # SKIP no db' 'ok 5 - h # TODO later' '✔ f.test.mjs (43.1ms)' 'ok 4 - ./f.test.mjs'
echo "-- ok f.test.mjs" >> "$CONVEYOR_TEST_LOG/a.log"
EOF
  f=$(allfails 0 | jq -c .passcases) || fail "the passed cases could not be read"
  [ "$f" = '[{"file":"f.test.mjs","cases":["a b, c","d e"]}]' ] || fail "node's ✔ and TAP's ok lines are not the file's passed cases: $f"
}
# R389. Bug it catches: a to-do TAP case that fails (`not ok 2 - k # TODO later`) is expected to fail, and is no failure
# of its file; no fixture held one, so a reader that took it for a failed case passed. The file failed on case real
# alone.
t_testfailstodo() {
  mkdir -p "$T/$CASE"; cat > "$T/$CASE/cmd" <<'EOF'
echo "== f.test.mjs" | tee -a "$CONVEYOR_TEST_LOG/a.log"
printf '%s\n' 'not ok 1 - real' 'not ok 2 - k # TODO later'
echo "-- FAIL f.test.mjs" >> "$CONVEYOR_TEST_LOG/a.log"
EOF
  f=$(logfails 1) || fail "the failures could not be read"
  [ "$(jq -c '[.files[] | {file, cases: [.cases[].name]}]' <<<"$f")" = '[{"file":"f.test.mjs","cases":["real"]}]' ] || fail "a failed to-do TAP case was read as a failure of its file: $f"
}
# R140 of #1393 (the loop runs a node file with TAP). Bug it catches: node's TAP writes `\#` for a `#` and `\\` for a
# `\` in a case's name, so a passed or failed case `id #413` was read as `id \#413` and matched no case of that name
# (its main-red check said none); and it writes the actual and expected values of a failed assertion as a YAML block, so a
# line in one that began as a result (`ok 4 ghost`, `not ok 5 phantom`, `✔ ghost (1ms)`) was read as a pass or a failure of a case that
# never ran. The output is what node's TAP reporter prints (a top-level failing case and a nested one, each with such
# values), with the file's own printed lines marked `# ` as node marks them: it is run through testfails() directly.
t_testfailstap() {
  mkdir -p "$T/$CASE"; cat > "$T/$CASE/cmd" <<'EOF'
echo "== f.test.mjs" | tee -a "$CONVEYOR_TEST_LOG/a.log"
cat <<'TAP'
TAP version 13
# ok 6 - printed
# Subtest: id \#413
ok 1 - id \#413
  ---
  duration_ms: 1.1
  type: 'test'
  ...
# Subtest: a\\b
ok 2 - a\\b
  ---
  type: 'test'
  ...
# Subtest: merges
not ok 3 - merges
  ---
  duration_ms: 1.2
  type: 'test'
  expected: |-
    ok 4 ghost
    not ok 5 phantom
    ✔ ghost (1ms)
    ✖ phantom (1ms)
  actual: 'x'
  ...
# Subtest: outer
    # Subtest: inner
    not ok 1 - inner
      ---
      expected: |-
        ok 7 nested ghost
        not ok 8 nested phantom
        ✔ nested ghost (1ms)
      ...
    1..1
not ok 4 - outer
  ---
  type: 'suite'
  ...
# Subtest: lost \#2
not ok 5 - lost \#2
  ---
  type: 'test'
  ...
1..5
TAP
echo "-- FAIL f.test.mjs" >> "$CONVEYOR_TEST_LOG/a.log"
EOF
  f=$(allfails 1) || fail "the run could not be read"
  [ "$(jq -c '[.files[].cases[].name]' <<<"$f")" = '["merges","inner","outer","lost #2"]' ] \
    || fail "a line in a result's YAML block was read as a failing case, a failing case was missed, or its TAP name was not read back as the case has it: $f"
  [ "$(jq -c .okcases <<<"$f")" = '[{"file":"f.test.mjs","cases":["a\\b","id #413"]}]' ] \
    || fail "a case's TAP name was not read back as the case has it, or a line in a result's YAML block was read as a pass: $f"
}
# Done when 1 (#1310). Bug it catches: which file a case is of was read from the output alone, so two workers whose
# output interleaves gave a case of one file to the other (a wrong red of a file that did not fail it) and a passed
# case to the wrong file. Two runners at once, a.test.sh and b.test.sh each failing one case and passing one, print
# both `== ` lines before any case; each case's record (results/: tests/lib.sh run_case) names its file, and the
# failures and passes are the records', each failure line still the output's.
t_testfailsrecords() {
  mkdir -p "$T/$CASE"; cat > "$T/$CASE/cmd" <<'EOF'
l=$CONVEYOR_TEST_LOG; mkdir -p "$l/results"
printf '%s\n' '== a.test.sh' '-- FAIL a.test.sh' > "$l/a.log"; printf '%s\n' '== b.test.sh' '-- FAIL b.test.sh' > "$l/b.log"
for r in 'a.test.sh one fail' 'a.test.sh two ok' 'b.test.sh three fail' 'b.test.sh four ok'; do
  set -- $r; jq -cn --arg f "$1" --arg c "$2" --arg r "$3" '{file: $f, case: $c, result: $r, sec: 0.1}' > "$l/results/$2"
done
printf '%s\n' '== a.test.sh' '== b.test.sh' 'FAIL [one]: boom' 'ok two' 'FAIL [three]: bang' 'ok four'; exit 1
EOF
  f=$(allfails 1 | jq -c '[[.files[] | {file, cases: [.cases[] | [.name, .line]]}], (.okcases | sort_by(.file)), .passed]') || fail "the failures could not be read"
  [ "$f" = '[[{"file":"a.test.sh","cases":[["one","FAIL [one]: boom"]]},{"file":"b.test.sh","cases":[["three","FAIL [three]: bang"]]}],[{"file":"a.test.sh","cases":["two"]},{"file":"b.test.sh","cases":["four"]}],[]]' ] \
    || fail "two workers' interleaved output (cmd: $(cat "$T/$CASE/cmd")) gave cases not as their records say: $f"
}
# Done when 4 (#1084). Bug it catches: a test that fails with no message of its own (node's assert.ok(false): its
# report printed only `ERR_ASSERTION actual: false expected: true`) gave a failure report with no command or line, so
# it could not be read without a run again. #1152: node's reporter prints the failed expression before its stack, and
# the `== ` in its `=== ` was read as a file line, which ended the case's search: the case had no place. A real node run
# of a stub test file in the worktree, whose only assertion is assert.ok(1 + 1 === 3): its case's line names the file,
# the line and that line's text, read from the failure's stack.
t_testfailsat() {
  mkdir -p "$T/$CASE/wt" && printf '%s\n' "import assert from 'node:assert';" "import test from 'node:test';" \
    "test('stub', () => {" '  assert.ok(1 + 1 === 3);' '});' > "$T/$CASE/wt/a.test.mjs" || fail "the stub test file could not be made"
  cat > "$T/$CASE/cmd" <<'EOF'
cd wt && echo "== a.test.mjs" | tee -a "$CONVEYOR_TEST_LOG/a.log"
node --max-old-space-size=4096 --test a.test.mjs; echo "-- FAIL a.test.mjs" >> "$CONVEYOR_TEST_LOG/a.log"; exit 1
EOF
  f=$(logfails 1 | jq -r '.files[] | select(.file == "a.test.mjs") | .cases[] | select(.name == "stub") | .line') || fail "the failures could not be read"
  [[ $f == *" (at a.test.mjs:4: assert.ok(1 + 1 === 3);)" ]] || fail "the case's line does not give the assertion's file, line and text: $f ($(cat "$T/$CASE/wt.test"))"
}
# #1084, E5 of its review. Bug it catches: only JavaScript stacks were read, so a Python test file that failed (python3
# on a unittest file, as the release's suite runs one; its failure names no case) had no place in its failure report.
# A real python3 run of a unittest file whose test calls a helper that asserts: the file's at is the helper's line,
# the traceback's last frame in the worktree (its first frame, the call in the test, is not where it failed).
t_testfailspy() {
  mkdir -p "$T/$CASE/wt" && printf '%s\n' 'import unittest' 'def check(x):' '    assert x' 'class T(unittest.TestCase):' \
    '    def test_x(self):' '        check(False)' 'unittest.main()' > "$T/$CASE/wt/t.py" || fail "the stub test file could not be made"
  cat > "$T/$CASE/cmd" <<'EOF'
cd wt && echo "== t.py" | tee -a "$CONVEYOR_TEST_LOG/a.log"
python3 -I t.py; echo "-- FAIL t.py" >> "$CONVEYOR_TEST_LOG/a.log"; exit 1
EOF
  f=$(logfails 1 | jq -c '.files[] | select(.file == "t.py") | [.cases, .at]') || fail "the failures could not be read"
  [ "$f" = '[[],"t.py:3: assert x"]' ] || fail "the failed file's place is not the helper's assertion: $f ($(cat "$T/$CASE/wt.test"))"
}
# R141. Bug it catches: Conveyor's own runner (lib/filerun.sh) ran plain `pytest <file>`, whose default traceback ends
# a failure with `tests/test_example.py:4: AssertionError`, a path from the package's folder that no frame pattern
# reads, so the failure had no place. pytest is not installed here: its stand-in on PATH runs the file's test_
# functions and prints a failure as pytest does, with --tb=native Python's own traceback, else pytest's default form.
# The file runner runs a failing file: its failure's place is the assertion's line.
t_testfailspytest() {
  mkdir -p "$T/$CASE/wt/tests" "$T/$CASE/bin" && echo '[project]' > "$T/$CASE/wt/pyproject.toml" \
    && printf '%s\n' 'import os' '' 'def test_example():' '    assert 1 + 1 == 3' > "$T/$CASE/wt/tests/test_example.py" || fail "the stub test file could not be made"
  cat > "$T/$CASE/bin/pytest" <<'EOF'
#!/usr/bin/env python3
import os, runpy, sys, traceback
f, rc = sys.argv[-1], 0
for n, fn in runpy.run_path(os.path.abspath(f)).items():
    if not n.startswith("test_"):
        continue
    try:
        fn()
    except AssertionError:
        rc = 1
        print("_" * 20, n, "_" * 20)
        if "--tb=native" in sys.argv[1:-1]:
            traceback.print_exc(file=sys.stdout)
        else:
            print("E       AssertionError")
            print(f"{f}:{traceback.extract_tb(sys.exc_info()[2])[-1].lineno}: AssertionError")
sys.exit(rc)
EOF
  chmod +x "$T/$CASE/bin/pytest" || fail "the pytest stand-in could not be made"
  cat > "$T/$CASE/cmd" <<EOF
cd wt && echo "== tests/test_example.py" | tee -a "\$CONVEYOR_TEST_LOG/a.log"
PATH=$(printf %q "$T/$CASE/bin"):\$PATH bash $(printf %q "$SRC/lib/filerun.sh") tests/test_example.py; echo "-- FAIL tests/test_example.py" >> "\$CONVEYOR_TEST_LOG/a.log"; exit 1
EOF
  f=$(logfails 1 | jq -r '.files[] | select(.file == "tests/test_example.py") | .at') || fail "the failures could not be read"
  [ "$f" = 'tests/test_example.py:4: assert 1 + 1 == 3' ] || fail "the failed pytest file's place is not its assertion's line: $f ($(cat "$T/$CASE/wt.test"))"
}
# #1084, E1 of its review. Bug it catches: the text of a failure's place was read through a symbolic link in the
# worktree, so a link to a file outside it (committed, or made by a test) put that file's line into a report that may
# go to a GitHub issue. A frame names a link to a file outside the worktree, another a file under a linked folder: each
# case's place is named, with no text.
t_testfailslink() {
  mkdir -p "$T/$CASE/wt" "$T/$CASE/out" && echo 'the secret' > "$T/$CASE/out/s.txt" && ln -s "$T/$CASE/out/s.txt" "$T/$CASE/wt/l.mjs" \
    && ln -s "$T/$CASE/out" "$T/$CASE/wt/d" || fail "the fixture could not be made"
  cat > "$T/$CASE/cmd" <<'EOF'
cd wt && echo "== a.test.mjs" | tee -a "$CONVEYOR_TEST_LOG/a.log"
printf '%s\n' 'not ok 1 - one' "    at f ($PWD/l.mjs:1:1)" 'not ok 2 - two' "    at g ($PWD/d/s.txt:1:1)"
echo "-- FAIL a.test.mjs" >> "$CONVEYOR_TEST_LOG/a.log"; exit 1
EOF
  f=$(logfails 1 | jq -c '[.files[] | select(.file == "a.test.mjs") | .cases[].line]') || fail "the failures could not be read"
  [ "$f" = '["not ok 1 - one (at l.mjs:1)","not ok 2 - two (at d/s.txt:1)"]' ] || fail "a place read through a link shows a line outside the worktree: $f"
}
# #1306. Bug it catches: the test fix's prompt held only the last 200 raw lines of the output, so the fix session
# searched them for the failures the engine had already read. The prompt now names each failing case with its file
# and place first, then the raw tail: two cases of a node file (the place of each from its stack), a shell case (no
# stack: the line of its t_<name>() in its file) and two cases of standalone shell files with no t_ function (the line
# that prints its `FAIL [<name>]`, and the line that hands its quoted name to the check that prints it), listed before the output's own lines.
t_testfixprompt() {
  mkdir -p "$T/$CASE/wt" && printf '%s\n' 'x' 'y' > "$T/$CASE/wt/l.mjs" && printf '%s\n' '#!/bin/bash' '' 't_other() {' ':' '}' 't_boom() {' 'fail x' '}' > "$T/$CASE/wt/s.test.sh" \
    && printf '%s\n' '#!/bin/bash' 'bad() { echo "FAIL [solo]: $1"; }' 'bad x' > "$T/$CASE/wt/h.test.sh" \
    && printf '%s\n' '#!/bin/bash' 'check() { echo "FAIL [$1]"; }' "check 'quoted' x" > "$T/$CASE/wt/q.test.sh" || fail "the fixture could not be made"
  cat > "$T/$CASE/cmd" <<'EOF'
cd wt && echo "== a.test.mjs" | tee -a "$CONVEYOR_TEST_LOG/a.log"
printf '%s\n' 'not ok 1 - one' "    at f ($PWD/l.mjs:1:1)" 'not ok 2 - two' "    at g ($PWD/l.mjs:2:1)"
echo "-- FAIL a.test.mjs" >> "$CONVEYOR_TEST_LOG/a.log"
echo "== s.test.sh" | tee -a "$CONVEYOR_TEST_LOG/s.log"; echo 'FAIL [boom]: it broke'; echo "-- FAIL s.test.sh" >> "$CONVEYOR_TEST_LOG/s.log"
echo "== h.test.sh" | tee -a "$CONVEYOR_TEST_LOG/h.log"; echo 'FAIL [solo]: it broke too'; echo "-- FAIL h.test.sh" >> "$CONVEYOR_TEST_LOG/h.log"
echo "== q.test.sh" | tee -a "$CONVEYOR_TEST_LOG/q.log"; echo 'FAIL [quoted]: it broke as well'; echo "-- FAIL q.test.sh" >> "$CONVEYOR_TEST_LOG/q.log"; exit 1
EOF
  local p want got
  p=$(logfails 1 > "$T/$CASE/fails" && eval "$(sed -n '/^testfixprompt() {/,/^}/p' "$SRC/lib/card.sh")" && testfixprompt 'CARD' "$T/$CASE/wt" 1 "$(cat "$T/$CASE/fails")") || fail "the prompt could not be made: $p"
  want=$'- a.test.mjs: not ok 1 - one (at l.mjs:1: x)\n- a.test.mjs: not ok 2 - two (at l.mjs:2: y)\n- h.test.sh: FAIL [solo]: it broke too (at h.test.sh:2)\n- q.test.sh: FAIL [quoted]: it broke as well (at q.test.sh:3)\n- s.test.sh: FAIL [boom]: it broke (at s.test.sh:6)'
  got=$(sed -n '/^# The failing cases/,/^$/p' <<<"$p" | sed '1d;$d')
  [ "$got" = "$want" ] || fail "the prompt lists these failing cases, not the five with file and line: $got"
  # They come before the raw output, whose own lines carry no place, under its heading (which testruns.test.sh t_testsfix cuts at).
  [ "$(grep -n '^# The failing cases' <<<"$p" | cut -d: -f1)" -lt "$(grep -n '^not ok 1 - one$' <<<"$p" | cut -d: -f1)" ] \
    && grep -q '^# The changed tests fail (exit 1): fix that and nothing else. The end of the test output:$' <<<"$p" || fail "the failing cases are not before the raw output under its heading: $p"
}
# #1084, E1 and E5 of its review, for the push check's reader (failat(): a pre-push hook's output, and a test file the
# push check ran). Bugs it catches: a Python traceback gave no place, and a link in the worktree to a file outside it
# had that file's line read into the push line's reason. A Python traceback (its places: the call in the test, then the
# helper's assertion) and a JavaScript frame of a link to a file outside the worktree.
t_failatread() {
  local w=$T/$CASE/wt f
  mkdir -p "$w" "$T/$CASE/out" && echo 'the secret' > "$T/$CASE/out/s.txt" && ln -s "$T/$CASE/out/s.txt" "$w/l.mjs" \
    && printf '%s\n' 'import unittest' 'def check(x):' '    assert x' > "$w/t.py" || fail "the fixture could not be made"
  f=$( eval "$(frameread; sed -n '/^failat() {/,/^}/p' "$SRC/lib/failat.sh")"
    printf '%s\n' 'Traceback (most recent call last):' "  File \"$w/t.py\", line 2, in test_x" '    check(False)' \
      "  File \"$w/t.py\", line 3, in check" '    assert x' 'AssertionError' "    at f ($w/l.mjs:1:1)" | failat "$w" )
  [ "$f" = $'t.py:3: assert x\nl.mjs:1' ] || fail "failat did not give the traceback's last place, or read a line through a link: $f"
}
# Issue 442: bugproof.sh redproof() with a stub runner (mainredproof.test.sh's redrunner) that prints node's `✔ <case> (<n>ms)` for a
# passed case: a fix whose case fails without the change and passes with it was blocked with "gave no result".
t_redproofnode() {
  redrunner ''; sed -i 's/echo "ok \$c"/echo "✔ $c (12.3ms)"/' "$STUB/mainrun-cmd"
  grep -qF '✔' "$STUB/mainrun-cmd" || fail "the stub runner does not print node's passed line"
  eng 'mainred c1 "a.test: one two, three" a.test '"$(git -C "$R" rev-parse HEAD)" || fail "the case was not recorded"
  local got; got=$(redcheck 'one two, three')
  [ "$(head -n 1 <<<"$got")" = "exit 0" ] || fail "a fix of a named node case that passes with the change did not hold: $got"
}
t_testforged() {
  mkdir -p "$T/$CASE"; cat > "$T/$CASE/cmd" <<'EOF'
begin() { echo "== $2"; echo "== $2" >> "$CONVEYOR_TEST_LOG/$1.log"; }
end() { echo "-- $3 $2" >> "$CONVEYOR_TEST_LOG/$1.log"; }
begin b shared.test.sh; echo "== shared.test.sh"; end b shared.test.sh ok
begin b b.test.sh; end b b.test.sh FAIL
begin a shared.test.sh; echo "FAIL [alpha]: wrong"; end a shared.test.sh FAIL
exit 1
EOF
  f=$(logfails 1) || fail "the failures could not be read"
  [ "$(jq -r '.files | map("\(.file):\(.cases | map(.name) | join(","))") | join(" ")' <<<"$f")" = "shared.test.sh:alpha b.test.sh:alpha" ] \
    || fail "a failing case of a file two runners ran is not under it when a test printed that file's == line first: $f"
}

# Bug: an end line of one runner's log was read as the end of a file another runner had begun and not ended: with one
# runner still in `tests/b 0s` and another's `tests/b` failing in 0s (`-- FAIL tests/b 0s`), the failure named
# `tests/b 0s` and the timeout named `tests/b`, each the other's file. And a file two runners ran, ended by one, read
# as ended in both: the timeout did not name the runner still in it. A log's end lines are of its own files.
t_testfailsown() {
  mkdir -p "$T/$CASE"; cat > "$T/$CASE/cmd" <<'EOF'
L=$CONVEYOR_TEST_LOG
echo "== tests/b 0s" | tee -a "$L/a.log" # the first log read: its runner is in this file to the end
echo "== tests/b" | tee -a "$L/b.log"; echo "-- FAIL tests/b 0s" >> "$L/b.log"
echo "== tests/b 0s" | tee -a "$L/c.log"; echo "-- ok tests/b 0s" >> "$L/c.log"
EOF
  # Exit 124: the run was cut by its timeout (2 s) in a test file that hung.
  f=$(logfails 124 2 | jq -c '[.timeout, (.files | map(.file))]') || fail "the failures could not be read"
  [ "$f" = '[{"sec":2,"file":"tests/b 0s"},["tests/b"]]' ] \
    || fail "an end line in one runner's log ended a file another runner had open: the failed file or the file the timeout names is the other runner's: $f"
}

# Bug: a failing file that printed the `== ` line of a file still to run gave that file its failing case; the file
# passed, so the case was dropped and the Board named the failed file with no case: a test could hide what failed.
# The runner's own `== ` line for the later file comes after, so the first may be the failing file's: its case is kept.
# Bugs: when the later file failed too, the case was under it alone, and the file that printed it still showed none:
# which of the two printed it cannot be told, so both name it; and a passing file that printed an earlier file's
# `== ` line after a FAIL line of its own had that line counted against the earlier, failed file: the runner prints no
# file's line after a later file's, so the line is the passing file's own and no failure.
# Bug: a failing file that printed the next file's `== ` line and ended its output without a newline had the runner's
# line for the next file joined to its last line, where it was not read: the case was the next, passing file's alone
# and was dropped. A `== ` line counts wherever it is in a line.
t_testhide() {
  mkdir -p "$T/$CASE"; cat > "$T/$CASE/cmd" <<'EOF'
L=$CONVEYOR_TEST_LOG/run.log
begin() { echo "== $1"; echo "== $1" >> "$L"; }
end() { echo "-- $1 $2" >> "$L"; }
begin tests/a.test.sh; echo "== tests/b.test.sh"; echo "FAIL [alpha]: wrong"; end FAIL tests/a.test.sh
begin tests/b.test.sh; echo "FAIL [own]: words a passing test prints"; echo "== tests/a.test.sh"; end ok tests/b.test.sh
begin tests/c.test.sh; echo "== tests/d.test.sh"; echo "FAIL [gamma]: wrong"; end FAIL tests/c.test.sh
begin tests/d.test.sh; echo "FAIL [delta]: wrong"; end FAIL tests/d.test.sh
begin tests/e.test.sh; echo "== tests/f.test.sh"; echo "FAIL [eps]: wrong"; printf x; end FAIL tests/e.test.sh
begin tests/f.test.sh; end ok tests/f.test.sh; exit 1
EOF
  f=$(logfails 1) || fail "the failures could not be read"
  [ "$(jq -r '.files | map([.file, (.cases | map(.name) | join(","))] | join(":")) | join(" ")' <<<"$f")" \
    = "tests/a.test.sh:alpha tests/c.test.sh:gamma tests/d.test.sh:gamma,delta tests/e.test.sh:eps" ] \
    || fail "a failing file's case behind a later file's == line is not under it, or a passing file's own line is a failure: $f"
}

# Bug: a test file whose name has a space was cut at it (`tests/my file.test.sh` read as `tests/my`): the failure row
# and the timeout named a file that does not exist, and the file that ended still read as running. The name is whole,
# with the words a runner puts after it (the cases run, a duration) left off.
# Bugs: a name's last space was dropped (the timeout named `tests/my slow file.test.sh` for a file whose name ends in
# a space); and an end line was read as the end of a file already done whose name it began with (`-- FAIL tests/b 0s`
# as the passed `tests/b 0s`, not the running `tests/b`), so a passing file was named as failed.
# Bug: a passing test that printed its own `== ` line again (`== tests/b 0s`, a file done) was read as the beginning
# of the later file its name begins with (`tests/b`), which failed: the passing file's `FAIL [` line became a case of it.
t_testfailsspace() {
  mkdir -p "$T/$CASE"; cat > "$T/$CASE/cmd" <<'EOF'
L=$CONVEYOR_TEST_LOG/run.log
echo "== tests/my file.test.sh" | tee -a "$L"; echo "FAIL [spaced]: wrong"; echo "-- FAIL tests/my file.test.sh 0s" >> "$L"
echo "== tests/a.test.sh" >> "$L"; echo "== tests/a.test.sh (cases: one two)"; echo "FAIL [plain]: wrong"; echo "-- FAIL   tests/a.test.sh 0s" >> "$L"
echo "== tests/b 0s" | tee -a "$L"; echo "== tests/b 0s"; echo "FAIL [own]: wrong"; echo "-- ok tests/b 0s 0s" >> "$L"
echo "== tests/b" >> "$L"; echo "== tests/b (cases: late)"; echo "FAIL [late]: wrong"; echo "-- FAIL tests/b 0s" >> "$L"; exit 1
EOF
  f=$(logfails 1) || fail "the failures could not be read"
  [ "$(jq -c '[.of, .timeout, (.files | map([.file, (.cases | map(.name) | join(","))] | join(":")))]' <<<"$f")" \
    = '[4,null,["tests/my file.test.sh:spaced","tests/a.test.sh:plain","tests/b:late"]]' ] \
    || fail "a failed file with a space in its name is not named whole with its case, a file done whose name an end line begins with is named for the one running, or a passing file's own line is a case of the failed file its name begins with: $f"
}
# The timeout of t_testfailsspace's bugs: a run cut by its time (2 s, exit 124) in a file whose name has spaces, its
# last one too. The card's reason names the timeout's file as it is (testruns.test.sh t_testfails).
t_testfailsspacetimeout() {
  mkdir -p "$T/$CASE"; cat > "$T/$CASE/cmd" <<'EOF'
L=$CONVEYOR_TEST_LOG/run.log
echo "== tests/my file.test.sh" | tee -a "$L"; echo "-- ok tests/my file.test.sh" >> "$L"
echo "== tests/my slow file.test.sh " | tee -a "$L"
EOF
  f=$(logfails 124 2 | jq -c '[.of, .timeout, .files]') || fail "the failures could not be read"
  [ "$f" = '[2,{"sec":2,"file":"tests/my slow file.test.sh "},[]]' ] \
    || fail "a timeout does not name, whole to its last space, the file with spaces in its name that was still running: $f"
}
# Bug it catches (E1 of the #1461 follow-up): two files past their own limits (filecmd()'s `-- timeout` line, no end
# line) left the timeout naming the last alone, so the Tests judge told the first one's partial run as a pass.
# stopped names each file begun and not ended, and not the file between them that passed.
t_testfailsstopped() {
  mkdir -p "$T/$CASE"; cat > "$T/$CASE/cmd" <<'EOF'
L=$CONVEYOR_TEST_LOG/run.log
echo "== tests/a.test.sh" | tee -a "$L"; echo "-- timeout tests/a.test.sh" >> "$L"
echo "== tests/b.test.sh" | tee -a "$L"; echo "-- ok tests/b.test.sh" >> "$L"
echo "== tests/c.test.sh" | tee -a "$L"; echo "-- timeout tests/c.test.sh" >> "$L"
EOF
  f=$(logfails 124 2 | jq -c '[.timeout, .stopped]') || fail "the failures could not be read"
  [ "$f" = '[{"sec":2,"file":"tests/c.test.sh"},["tests/a.test.sh","tests/c.test.sh"]]' ] \
    || fail "a run (exit 124) where tests/a.test.sh and tests/c.test.sh timed out and tests/b.test.sh passed: stopped does not name both timed-out files alone: $f"
}

# Bug: a test command that writes no runner log (a pack that runs one test file itself) had its failing cases under
# no file: the Board could not say what failed. Such a run is one file, the command (the pack's test.command).
t_testnolog() {
  mkdir -p "$T/$CASE"; echo 'echo "ok lane"; echo "FAIL [views]: wrong"; exit 1' > "$T/$CASE/cmd"
  local -x PACKCMD='bash run-tests.sh'
  f=$(logfails 1 | jq -c '[.timeout, .files]') || fail "the failures could not be read"
  [ "$f" = '[null,[{"file":"bash run-tests.sh","cases":[{"name":"views","line":"FAIL [views]: wrong"}]}]]' ] \
    || fail "a failing case of a command with no runner log is not under the command: $f"
}
# Bug (issue 218): the time of a command with no runner log running out was read as a test's: it is the runner's, so
# that run gave no result, and says so.
t_testnologtimeout() {
  mkdir -p "$T/$CASE"; echo 'echo "ok one"' > "$T/$CASE/cmd"
  local -x PACKCMD='bash run-tests.sh'
  allfails 124 2 > /dev/null || fail "the failures of the timed-out run could not be read"
  f=$(void 124 2) && [ "$f" = "exit 124: the run's time ran out with no test file running" ] \
    || fail "a timed-out command with no runner log is not a run with no result: $f"
}

# Bug: two runners each wrote a log, and the files' order was read from the logs joined by name: the runner whose log
# sorts last ran first, so the other's `== ` line read as going back and its failing case went to the wrong file. The
# Board named one file for both failures. Order holds within a runner's log only; a `== ` line that goes back in its
# own log is still a test's own. And a file both runners ran was kept in the first log's order only, so the second
# runner's run of it read as going back and its failing case went to the file before it.
t_testrunners() {
  mkdir -p "$T/$CASE"; cat > "$T/$CASE/cmd" <<'EOF'
begin() { echo "== $2"; echo "== $2" >> "$CONVEYOR_TEST_LOG/$1.log"; }
end() { echo "-- FAIL $2" >> "$CONVEYOR_TEST_LOG/$1.log"; }
begin b b.test.sh; echo "FAIL [beta]: wrong"; end b b.test.sh
begin a shared.test.sh; echo "FAIL [first]: wrong"; end a shared.test.sh
begin a a.test.sh; echo "FAIL [alpha]: wrong"; end a a.test.sh
begin b shared.test.sh; echo "FAIL [second]: wrong"; end b shared.test.sh
begin a a2.test.sh; echo "== a.test.sh"; echo "FAIL [again]: wrong"; end a a2.test.sh
exit 1
EOF
  f=$(logfails 1) || fail "the failures could not be read"
  [ "$(jq -r '.files | map("\(.file):\(.cases | map(.name) | join(","))") | join(" ")' <<<"$f")" \
    = "shared.test.sh:first,second a.test.sh:alpha a2.test.sh:again b.test.sh:beta" ] \
    || fail "each runner's failing case is not under its own file: $f"
}

# Bug: a file two runners ran was given to the runner whose log sorts first whenever either could have begun it. Here
# the other runner began it first, so the first runner's own run of it read as going back, and its failing case went
# to the file before it: the Board named a file for a failure that was another's. Only the reading of the whole
# output that takes every one of the runners' `== ` lines is right.
t_testshared() {
  mkdir -p "$T/$CASE"; cat > "$T/$CASE/cmd" <<'EOF'
begin() { echo "== $2"; echo "== $2" >> "$CONVEYOR_TEST_LOG/$1.log"; }
end() { echo "-- $3 $2" >> "$CONVEYOR_TEST_LOG/$1.log"; }
begin a x.test.sh; end a x.test.sh ok
begin b shared.test.sh; end b shared.test.sh ok
begin b b.test.sh; echo "FAIL [beta]: wrong"; end b b.test.sh FAIL
begin a shared.test.sh; echo "FAIL [alpha]: wrong"; end a shared.test.sh FAIL
exit 1
EOF
  f=$(logfails 1) || fail "the failures could not be read"
  [ "$(jq -r '.files | map("\(.file):\(.cases | map(.name) | join(","))") | join(" ")' <<<"$f")" = "shared.test.sh:alpha b.test.sh:beta" ] \
    || fail "a failing case of a file two runners ran is not under that file: $f"
}

# The pass lines of the Foreman test files that run as one whole, as a main-red fix card's check (bugproof.sh
# redproof()) reads them: a case passes there only from an `ok <case>` line (testfails()), named as the case's FAIL line
# names it. A file that runs its cases one by one is checked by a run of a case (mainredproof.test.sh
# t_redproofforemanwaiter).
# The awk program that prints a line for each gap in a Foreman test file's pass lines: a case a FAIL line names with no
# `ok <case>` line, an `ok` line naming no case, and a pass named for another case than the one whose result it reads.
# A case is a `FAIL [<case>]` name, or, for a FAIL line with a name built at run time (`FAIL [<prefix>$1]`), the prefix
# and the first word of a top-level call `<function> <word> ... & <pid>=$!`. A process `( ... FAIL [<case>] ... ) & <pid>=$!`
# is the case of its last FAIL line. A pass reads the result of <pid> from `wait "$<pid>"; ... echo "ok <case>"` or
# from a word `"$<pid> <case>"` of the list it waits on.
FOREMANPASS_AWK='match($0, /FAIL \[[a-z0-9-]*\$/) { pre = substr($0, RSTART + 6, RLENGTH - 7) }
{ s = $0; while (match(s, /FAIL \[[a-z0-9-]+\]/)) { cur = substr(s, RSTART + 6, RLENGTH - 7); fails[cur] = 1; s = substr(s, RSTART + RLENGTH) } }
(/^[^ ]/ || /\) & [a-z]+=\$!/) && match($0, /& [a-z]+=\$!/) { v = substr($0, RSTART + 2, RLENGTH - 5)
  n = /\) & / ? cur : ($2 ~ /^[a-z0-9-]+$/) ? pre $2 : ""; if (n != "") { of[v] = n; fails[n] = 1 } }
{ s = $0; while (match(s, /"\$[a-z]+ [a-z0-9-]+"/)) { split(substr(s, RSTART + 2, RLENGTH - 3), p, " "); oks[p[2]] = 1
    if (of[p[1]] != p[2]) print "the pass ok " p[2] " reads the result of the case " of[p[1]]; s = substr(s, RSTART + RLENGTH) } }
match($0, /echo "ok [a-z0-9-]+"/) { n = substr($0, RSTART + 9, RLENGTH - 10); oks[n] = 1
  if (match($0, /wait "\$[a-z]+"/) && of[v = substr($0, RSTART + 7, RLENGTH - 8)] != n) print "the pass ok " n " reads the result of the case " of[v] }
END { for (n in fails) if (!(n in oks)) print "the case " n " has no pass line ok " n
  for (n in oks) if (!(n in fails)) print "the pass ok " n " names no case" }'

# Bug it catches: these files printed `ok [<case>]: <check>`, `ok [<title>]` or nothing on a pass, so the check read no
# case as passed and blocked each fix as giving no result; and a pass named for another case (two names swapped in a wait
# list) would pass a case that still fails.
# It reads the files' text: they run only whole, and a whole run of another test file from an engine case is a nested
# run that the card's test step refuses (.conveyor/test-changed.sh metaran()). The case is in this file, which the area
# map names in each checkout, and not in a file of its own: a new case file has no area in a checkout without the fix,
# so the bug-card check of a fix read the map error there as the case failing without the fix. Its name is not
# foremanpasslines: a checkout without this change still has that case in foremanpass.test.sh, and a name two case
# files define is a map error there too.
t_foremanoklines() {
  local f gaps
  for f in filing-repo watch-conveyor-newoutage watch-conveyor-outage watch-gh watch-idle watch-landed watch-limit \
    watch-recordsnewer watch-relfix watch-wait; do
    gaps=$(awk "$FOREMANPASS_AWK" "$SRC/foreman/$f.test.sh") || fail "conveyor/foreman/$f.test.sh could not be read"
    [ -z "$gaps" ] || fail "conveyor/foreman/$f.test.sh does not print one pass line ok <case> for each case its FAIL lines name: $(tr '\n' ';' <<<"$gaps")"
  done
}

# Bug it catches: watch-conveyor-newoutage.test.sh's cases were renamed from `watch-conveyor-newoutage <read>` to
# `newoutage-<read>`, and the file printed a pass only under the new names, so a main-red entry recorded under an old
# name got no result from a fixed run (mainred.sh redrun() needs the same name) and its fix card blocked.
# It runs the file's own lines from its first `stage` launch to its end, with stage() made to pass for one read only,
# through testfails(): a run of the whole file from an engine case is a nested run that the card's test step refuses
# (.conveyor/test-changed.sh metaran()). As only one stage passes, a pass line that reads another stage's wait (the old
# names swapped, or one old name given twice) passes the wrong case and fails this check.
newoutagepass() { # <the one read whose stage passes: snapshot or health>
  local f=conveyor/foreman/watch-conveyor-newoutage.test.sh got
  mkdir -p "$T/$CASE"
  { echo "echo '== $f'; echo '== $f' >> \"\$CONVEYOR_TEST_LOG/a.log\""
    echo "stage() { [ \"\$1\" = $1 ]; }"
    echo "trap 'echo \"-- FAIL $f\" >> \"\$CONVEYOR_TEST_LOG/a.log\"' EXIT"
    sed -n '/^stage [a-z]* [0-9]* & [a-z]*=\$!$/,$p' "$SRC/${f#conveyor/}"; } > "$T/$CASE/cmd"
  got=$(allfails 1 | jq -c --arg f "$f" '[(.okcases + .passcases)[] | select(.file == $f) | .cases[]] | sort') || fail "the run could not be read"
  [ "$got" = "[\"newoutage-$1\",\"watch-conveyor-newoutage $1\"]" ] \
    || fail "with only the $1 stage of $f passing, its pass is not read under the case's new and old names alone (commands: $(tr '\n' ';' < "$T/$CASE/cmd")): $got"
}
t_newoutageoldsnapshot() { newoutagepass snapshot; }
t_newoutageoldhealth() { newoutagepass health; }
# #1609. Bug it catches: the jq of testfails() was given every line of a test's output, and its time and memory grew with
# the line count: a test that printed 22 million lines (a stuck retry) stalled the card's read of its result for 27+
# minutes. Two timed-out runs of three files (b passes, a fails, c is begun and not ended), one with 30000 noise lines
# between its lines and before a's stack frame, one without: both give the same result (files, cases, passed, failed,
# timeout), b is passed and c is the timeout file, the failing case still has its place (`at`) with the noise before
# its frame, and no noise line reaches the jq (what reached it is recorded, not a time).
t_testfailsnoise() {
  mkdir -p "$T/$CASE/wt" && printf '%s\n' 'line one' 'line two' 'line three' 'line four' > "$T/$CASE/wt/a.test.mjs" || fail "the stub test file could not be made"
  local clean noisy
  cat > "$T/$CASE/cmd" <<'EOF'
noise() { [ -z "$NOISE" ] || seq 1 30000 | sed 's/^/wait: pid /; s/$/ is not a child of this shell/'; }
echo "== b.test.mjs" | tee -a "$CONVEYOR_TEST_LOG/b.log"
echo 'ok 1 - fine'; noise
echo "-- ok b.test.mjs" >> "$CONVEYOR_TEST_LOG/b.log"
echo "== a.test.mjs" | tee -a "$CONVEYOR_TEST_LOG/a.log"
echo 'ok 1 - first'; noise
echo 'not ok 2 - second'; echo '  ---'; echo '  actual: 1'; echo '  stack: |-'; noise
echo "    at Context.<anonymous> ($PWD/wt/a.test.mjs:3:7)"; echo '  ...'; noise
echo 'ok 3 - third'; noise
echo "-- FAIL a.test.mjs" >> "$CONVEYOR_TEST_LOG/a.log"
echo "== c.test.mjs" | tee -a "$CONVEYOR_TEST_LOG/c.log"
noise; exit 124
EOF
  clean=$(allfails 124) || fail "the clean output could not be read"
  rm -rf "${T:?}/${CASE:?}/wt.testlog"
  jq() { case "$*" in *"--arg rc"*) tee -a "$T/$CASE/seen" | command jq "$@" ;; *) command jq "$@" ;; esac; } # the output's reader: what it is given is recorded
  noisy=$(NOISE=1 allfails 124); unset -f jq
  [ "$noisy" = "$clean" ] || fail "30000 noise lines changed the result: clean $clean, noisy $noisy"
  [ "$(command jq -c '[.passed, .timeout.file]' <<<"$clean")" = '[["b.test.mjs"],"c.test.mjs"]' ] || fail "b is not the passed file or c the timeout file: $clean"
  [[ $clean == *'(at a.test.mjs:3: line three)'* ]] || fail "the failing case has no place: $clean"
  ! grep -q '^wait:' "$T/$CASE/seen" || fail "a noise line reached the jq of testfails(): $(grep -c '^wait:' "$T/$CASE/seen") of $(wc -l < "$T/$CASE/seen") lines (cmd: $(head -c 300 "$T/$CASE/cmd"))"
}
