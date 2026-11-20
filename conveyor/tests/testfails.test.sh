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
# logfails() with the files and cases the run passed.
allfails() { # <exit> [<testTimeout>]
  local w=$T/$CASE/wt; mkdir -p "$w.testlog"
  (cd "$T/$CASE" && CONVEYOR_TEST_LOG=$w.testlog bash cmd > "$w.test" 2>&1 < /dev/null)
  ( eval "$(sed -n '/^testfails() {/,/^}/p' "$SRC/lib/testrun.sh"; sed -n '/^testlogs() {/,/^}/p' "$SRC/lib/session.sh")"
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
# nor node's line for the file itself (a run with a name filter that ran no case, as splitstart() makes, prints it).
t_testfailspassed() {
  mkdir -p "$T/$CASE"; cat > "$T/$CASE/cmd" <<'EOF'
echo "== f.test.mjs" | tee -a "$CONVEYOR_TEST_LOG/a.log"
printf '%s\n' '✔ a b, c (12.3ms)' 'ok 2 - d e' 'ok 3 - g # SKIP no db' '✔ f.test.mjs (43.1ms)' 'ok 4 - ./f.test.mjs'
echo "-- ok f.test.mjs" >> "$CONVEYOR_TEST_LOG/a.log"
EOF
  f=$(allfails 0 | jq -c .passcases) || fail "the passed cases could not be read"
  [ "$f" = '[{"file":"f.test.mjs","cases":["a b, c","d e"]}]' ] || fail "node's ✔ and TAP's ok lines are not the file's passed cases: $f"
}
# Issue 442: redproof() with a stub runner (mainredproof.test.sh's redrunner) that prints node's `✔ <case> (<n>ms)` for a
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
