#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# The test lint (test-lint.sh): a test that sleeps a set time and then checks fails on a busy machine, where the thing
# has not happened yet. So such a sleep fails the lint, and with it every test run (test-changed.sh runs the lint);
# a wait for the condition, a loop's own pause and a sleep that says why pass. A full-loop run the change adds with no
# "# loop: <why>" fails it too, and so does a hand-written CLI stub it adds with no "# stub: <why>".
set -u
HERE=$(cd "$(dirname "$0")" && pwd -P); ROOT=$(dirname "$HERE")
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
n=0; bad=0
ok() { n=$((n + 1)); echo "ok $n - $1"; }
no() { n=$((n + 1)); bad=1; echo "not ok $n - $1"; }
# lint <name> <line>...: the lint over a test file of those lines; its output in $T/<name>.out, its exit status returned.
lint() { local f=$T/$1.test.sh; shift; printf '%s\n' "$@" > "$f"; bash "$HERE/test-lint.sh" "$f" > "${f%.test.sh}.out" 2>&1; }
# passes and fails each run side by side with the others, their result (ok or no, a tab, the message) in $T/res.<k>;
# results reports them in the order they were called. Each name is the case's own.
k=0
passes() { k=$((k + 1)); { lint "$@" && printf 'ok\tpasses: %s' "$1" || printf 'no\t%s failed the lint: %s' "$1" "$(cat "$T/$1.out")"; } > "$T/res.$k" & }
# fails <name> <line number> <line>...: the lint fails and names that line of the file.
fails() { k=$((k + 1)); failed "$@" > "$T/res.$k" & }
failed() {
  local name=$1 at=$2; shift 2
  if lint "$name" "$@"; then printf 'no\t%s passed the lint' "$name"
  elif grep -q "^$T/$name.test.sh:$at: " "$T/$name.out"; then printf 'ok\tfails: %s' "$name"
  else printf 'no\t%s: the lint does not name line %s: %s' "$name" "$at" "$(cat "$T/$name.out")"; fi
}
results() {
  local i r; wait
  for i in $(seq "$k"); do
    r=$(cat "$T/res.$i" 2>/dev/null); case $r in ok$'\t'* | no$'\t'*) ;; *) r=$'no\tlint case '$i' gave no result' ;; esac
    "${r%%$'\t'*}" "${r#*$'\t'}"
  done
}

# That this checkout's own tests pass the lint is not checked here: test-changed.sh lints them on every run (the last
# case below proves it does for a whole run, and fails on a sleep-then-check), or once a tree in one-file mode in a
# test step (test-changed-one.test.sh proves that), and the lint of the whole checkout was nine tenths of this file's
# time.

# A sleep, then a check: on one line, on the next line, and in a script the test writes.
fails sleep-then-check 2 'start &' 'sleep 2; [ -e "$T/done" ] || fail "not done"'
fails sleep-then-check-next-line 1 'sleep 2' '[ -e "$T/done" ] || fail "not done"'
fails sleep-in-a-written-script 1 "printf 'echo one\\nsleep 0.3\\necho two\\n' > \"\$T/script\"" 'grep -q two "$T/out" || fail "no two"'
fails sleep-of-a-variable 1 'sleep "$PAUSE"; [ -e "$T/done" ] || fail "not done"'
fails sleep-of-a-quoted-number 1 'sleep "2"; [ -e "$T/done" ] || fail "not done"'
fails sleep-of-a-single-quoted-number 1 "sleep '2'; [ -e \"\$T/done\" ] || fail \"not done\""
fails sleep-of-a-fraction 1 'sleep .5; [ -e "$T/done" ] || fail "not done"'
fails sleep-after-two-dashes 1 'sleep -- 1; test -e ready'
fails sleep-of-a-quoted-variable-after-two-dashes 1 'sleep -- "$PAUSE"; test -e ready'
fails sleep-of-a-signed-number 1 'sleep +1; test -e ready'
fails sleep-of-a-command-output 1 'sleep `cat "$T/pause"`; test -e ready'
fails sleep-with-no-end 1 'sleep inf & pid=$!' 'kill -0 "$pid" || fail "it ended"'
# A sleep called by its path is a sleep all the same, the path quoted or not.
fails sleep-by-its-path 1 '/bin/sleep 1; test -e ready'
fails sleep-by-a-path-in-a-variable 1 '$BIN/sleep 1; test -e ready'
fails sleep-by-a-quoted-path 1 '"/bin/sleep" 1; test -e ready'
# A loop's pause does not excuse a sleep before a check further along the line, nor a comment that gives no reason.
fails sleep-after-a-loop 1 'until [ -e "$T/up" ]; do sleep 0.1; done; sleep 1; [ -e "$T/done" ] || fail "not done"'
fails sleep-with-an-empty-reason 1 'sleep 2 # sleep:' '[ -e "$T/done" ] || fail "not done"'
fails sleep-with-another-comment 1 'sleep 2 # give it a moment' '[ -e "$T/done" ] || fail "not done"'
# A sleep before a loop's check is not that loop's pause.
fails sleep-then-check-in-a-loop 1 'until [ -e "$T/up" ]; do sleep 0.1; kill -0 "$pid" || fail "it ended"; done'
# A loop that checks nothing is a set time: one that only counts, on a line or over lines, and one with no condition.
fails sleep-in-a-counted-loop 1 'for i in 1; do sleep 2; done; [ -e "$T/done" ] || fail "not done"'
fails sleep-in-a-counted-loop-over-lines 2 'for i in 1 2 3; do' '  sleep 1' 'done' '[ -e "$T/done" ] || fail "not done"'
fails sleep-in-a-loop-with-no-condition 1 'while :; do sleep 1; done & pid=$!' 'kill -0 "$pid" || fail "it ended"'
fails sleep-in-a-counted-loop-after-a-checking-one 1 'until [ -e "$T/up" ]; do sleep 0.1; done; for i in 1 2; do sleep 1; done'
# A while or until that only counts is a set time too: its condition runs no command and its body sets nothing from one.
fails sleep-in-a-counted-while 1 'i=0; while [ "$i" -lt 2 ]; do i=$((i+1)); sleep 1; done; test -e ready'
fails sleep-in-a-counted-while-over-lines 3 'i=0; until (( i >= 2 )); do' '  i=$((i + 1))' '  sleep 1' 'done' 'test -e ready'
fails sleep-in-a-while-on-the-clock 1 'end=$((SECONDS + 2)); while [[ $SECONDS -lt $end ]]; do sleep 0.5; done; test -e ready'

# The wait helper in the sleep's place, and right after a sleep (on its line or the next).
passes wait-helper 'start &' "wait_until '[ -e \"\$T/done\" ]' || fail \"not done\""
passes sleep-then-wait-helper "sleep 1; wait_until '[ -e \"\$T/done\" ]' || fail \"not done\""
passes sleep-then-wait-helper-next-line 'sleep 1' "wait_until '[ -e \"\$T/done\" ]' || fail \"not done\""
# A reason comment on the sleep's own line.
passes reason-comment 'sleep 2 # sleep: the retry may not come before 2 s' '[ ! -e "$T/retried" ] || fail "retried early"'
passes reason-comment-after-the-line "echo 'exec sleep 30' > \"\$STUB/build\"; start=\$SECONDS # sleep: a build that hangs"
# Quoted text that reads as a reason comment is no comment: the sleep before the check is as unexplained as before.
fails reason-in-quoted-text 1 "echo '# sleep: example'; sleep 1; test -e ready"
fails reason-in-double-quoted-text 1 'echo "x # sleep: example"; sleep 1; test -e ready'
fails reason-with-no-space-before-it 1 'echo x# sleep: example; sleep 1; test -e ready'
# Nor is it one in a quoted text begun on a line before, or in the quotes of a command whose output is quoted: the
# quotes inside "$(...)", a backquoted command and "${...}" do not end the text around them.
fails reason-in-quoted-text-over-lines 2 "echo 'first" "text # sleep: example'; sleep 1; test -e ready"
fails reason-in-a-quoted-command-output 1 'echo "$(printf "x # sleep: example")"; sleep 1; test -e ready'
fails reason-in-a-quoted-backquoted-command 1 'echo "`printf "x # sleep: example"`"; sleep 1; test -e ready'
fails reason-in-a-quoted-default 1 'echo "${X:-"x # sleep: example"}"; sleep 1; test -e ready'
passes reason-comment-after-quoted-text-over-lines "echo 'first" "text'; sleep 2 # sleep: the retry may not come before 2 s"
passes reason-comment-after-a-quoted-command-output 'x="$(printf "a # b")"; sleep 2 # sleep: the retry may not come before 2 s'
passes reason-comment-in-a-command-over-lines 'out=$(' '  sleep 2 # sleep: the retry may not come before 2 s' '  cat "$T/log")'
# A backquoted command is code too: a comment in it is one, up to the end of its line or the backquote that closes
# the command. The code after that backquote is read as code: a quote in the comment opens no quoted text.
passes reason-comment-in-a-backquoted-command-over-lines 'out=`sleep 1 # sleep: deliberately let time pass' 'printf x`'
passes reason-comment-in-a-backquoted-command 'out=`sleep 1 # sleep: deliberately let time pass`; test -e ready'
fails comment-with-no-reason-in-a-backquoted-command 1 'out=`sleep 1 # a pause`; echo "x # sleep: example"; test -e ready'
fails quote-in-a-backquoted-command-comment 2 'out=`date # it'"'"'s now`' "echo '# sleep: example'; sleep 1; test -e ready"
passes reason-comment-after-a-quoted-hash "echo 'a # b' \"it's\"; sleep 2 # sleep: the retry may not come before 2 s"
# The text of a here-document opens no quoted text of the file: an apostrophe in it does not turn the quoted text
# after it into code, nor the code after it into quoted text. A <<< and a shift begin no here-document.
fails reason-in-quoted-text-after-a-here-document 4 "cat <<'EOF'" "'" 'EOF' "echo 'x # sleep: example'; sleep 1; test -e ready"
fails reason-in-quoted-text-after-a-tabbed-here-document 4 'cat <<-EOF' "	it's" '	EOF' "echo 'x # sleep: example'; sleep 1; test -e ready"
fails reason-in-quoted-text-in-a-here-document 2 'cat > "$T/s" <<EOF' "echo 'x # sleep: example'; sleep 1; test -e ready" 'EOF'
passes reason-comment-after-a-here-document 'cat <<EOF' "it's" 'EOF' 'sleep 2 # sleep: the retry may not come before 2 s'
passes reason-comment-in-a-here-document 'cat > "$T/s" <<EOF' "it's" 'sleep 2 # sleep: the retry may not come before 2 s' 'EOF'
fails reason-in-quoted-text-after-a-here-string 2 "cat <<<EOF; n=\$((1 << EOF)); echo 'first" "text # sleep: example'; sleep 1; test -e ready"
# A loop that checks its condition again after each pause: the pause on the loop's line, and before its done.
passes loop-pause 'until [ -e "$T/done" ] || ! kill -0 "$pid"; do sleep 0.1; done' '[ -e "$T/done" ] || fail "not done"'
passes loop-pause-before-done 'until [ -e "$T/done" ]; do' '  kill -0 "$pid" || fail "it ended"; sleep 0.1' 'done'
# A loop that leaves by break (or return) when its check holds, whatever kind of loop it is.
passes loop-pause-with-a-break 'for i in $(seq 600); do [ -e "$T/go" ] && break; sleep 0.1; done'
passes loop-pause-with-a-break-and-no-condition 'while :; do' '  [ ! -e "$T/go" ] || break' '  sleep 0.1' 'done'
# A loop over a variable checks when its body sets the variable from a command; so does a count of what a command sees.
passes loop-pause-on-a-variable-a-command-sets 'n=0; while [ "$n" -lt 3 ]; do n=$(wc -l < "$T/log"); sleep 0.1; done'
passes loop-pause-on-a-command-count 'while [ "$(wc -l < "$T/log")" -lt 3 ]; do sleep 0.1; done'
passes loop-pause-in-an-inner-loop 'for n in 1 2; do' '  until [ -e "$T/$n" ]; do sleep 0.1; done' 'done'
# Not a sleep: the word in a comment line, a file of that name, a function of that name.
passes no-sleep '# sleep 2 here would hide a slow start' 'rm "$BIN/sleep"; stub sleep "exit 0"' 'export -f sleep'

# A full-loop run a change adds pays for the loop, its sessions and waits on every run, so the lint fails one with no
# "# loop: <why>" (on its line or the line above). The change is read from the merge base with main to the worktree:
# a line the card committed, one not yet committed and a file git does not track all count; a line it did not touch
# does not. A "# loop:" in quoted text is text the test prints, and clears nothing; a run named in quoted text (a
# process table row, a rule's text the test looks for, a failure message) or passed as an argument to another command
# (an editor stand-in) runs nothing, and passes; one after assignments (a quoted value with spaces in it too), exec
# and bash is a run. Bug: without it, a card's new test ran the whole loop where a call of the function would do, and
# nothing said so.
loopcheck() {
  local L=$T/loop exp got
  mkdir -p "$L/.conveyor" "$L/conveyor/tests"; cp "$HERE/test-lint.sh" "$L/.conveyor/"
  printf '%s\n' 't_old() {' '  loop run >/dev/null' '  loop serve &' '}' > "$L/conveyor/tests/old.test.sh"
  echo ': x' > "$L/conveyor/tests/big.test.sh"
  printf '%s\n' 't_a() {' '}' > "$L/conveyor/tests/a.test.sh"
  git -C "$L" init -q -b main && git -C "$L" add -A && git -C "$L" -c user.name=t -c user.email=t@example.com commit -qm init \
    && git -C "$L" checkout -q -b card || { printf 'no\tloop check: the fixture could not be made'; return; }
  printf '%s\n' 't_a() {' '  loop run >/dev/null || fail "run failed"' '}' > "$L/conveyor/tests/a.test.sh"
  git -C "$L" -c user.name=t -c user.email=t@example.com commit -qam card
  printf '%s\n' 't_a() {' '  loop run >/dev/null || fail "run failed"' '  loop run 1 # loop: only a whole run lands the card' \
    '  # loop: the service picks the card up' '  loop serve &' "  echo '# loop: x'; loop run" '  out=$("$SRC/conveyor.sh" serve 2>&1)' \
    '  echo "a # loop: x' '  "; loop run' "  ps='bash conveyor.sh serve'; grep -qxF -- 'the lint fails a \`loop run\`' rules.md" \
    '  grep -q x <<<"$out" || fail "a card of a loop run did not go on"' '  ( exec sh "$SH/edit.sh" "$SRC/conveyor.sh" run ) &' \
    '  echo "x; loop run"' '  ( cd "$B" && X=1 exec bash "$SRC/conveyor.sh" serve ) &' \
    '  CMD=". \"$S/limit\"" loop run 2>&1' '  out=$(A="$d c1 $(git -C "$SRC" rev-parse HEAD) $(date)" loop run 2>&1)' '}' > "$L/conveyor/tests/a.test.sh"
  echo 'loop run' > "$L/conveyor/tests/new.test.sh"
  # Over 128 KiB of changed-line keys (the most one argument can hold on Linux): the lint still reads them all.
  { seq 6000 | sed 's/^/: /'; echo 'loop run'; } > "$L/conveyor/tests/big.test.sh"
  if (cd "$L" && bash .conveyor/test-lint.sh) > "$T/loop.out" 2>&1; then printf 'no\tloop check: the lint passed'; return; fi
  exp=$(printf '%s\n' conveyor/tests/a.test.sh:{2,6,7,9,14,15,16} conveyor/tests/big.test.sh:6001 conveyor/tests/new.test.sh:1 | LC_ALL=C sort)
  got=$(grep -o '^conveyor/tests/[a-z]*\.test\.sh:[0-9]*' "$T/loop.out" | LC_ALL=C sort)
  if [ "$got" != "$exp" ]; then printf 'no\tloop check: not the lines %s: %s' "$(echo $exp)" "$(cat "$T/loop.out")"
  elif ! grep -q '"# loop: <why>" comment' "$T/loop.out"; then printf 'no\tloop check: the comment that clears it is not named: %s' "$(cat "$T/loop.out")"
  else printf 'ok\tfails: a full-loop run the change added with no "# loop:", and only that'; fi
}
k=$((k + 1)); loopcheck > "$T/res.$k" &
# A claude, codex, opencode or gh a test writes for itself does not answer in the form the engine reads, and
# clicontract.test.sh does not see it, so the lint fails one a change adds (with >, >>, tee, cp, mv or install) with no
# "# stub: <why>" on its line or the line above. A file the shared stub reads ($STUB/build, codex-answer) is no stub;
# a stub named in quoted text, copied from, or moved off PATH is written by nothing; a "# stub:" in quoted text clears
# nothing; a line the change did not touch is not read. Bug: without it, a card's new test wrote its own stub where
# the shared one would do, and nothing said so.
stubcheck() {
  local L=$T/stub exp got
  mkdir -p "$L/.conveyor" "$L/conveyor/tests"; cp "$HERE/test-lint.sh" "$L/.conveyor/"
  printf '%s\n' 't_old() {' '  printf x > "$STUB/codex"' '}' > "$L/conveyor/tests/old.test.sh"
  git -C "$L" init -q -b main && git -C "$L" add -A && git -C "$L" -c user.name=t -c user.email=t@example.com commit -qm init \
    && git -C "$L" checkout -q -b card || { printf 'no\tstub check: the fixture could not be made'; return; }
  printf '%s\n' 't_a() {' "  cat > \"\$STUB/codex\" <<'EOF'" 'exit 0' 'EOF' '  # stub: a codex that keeps its arguments' \
    "  printf '#!/bin/sh\\n' > \"\$STUB/claude\"" "  echo x >> \"\$G/opencode\" # stub: setup's own PATH folder" \
    '  echo 1 > "$STUB/build"; echo a > "$STUB/codex-answer"; echo b >"$STUB/gh.out"' '  cp "$SRC/x" "$B/gh"' \
    '  mv "$T/c" "$STUB"/claude' '  printf x | tee -a "$STUB/codex" >/dev/null' '  X=1 install -m 755 /dev/null $D/opencode' \
    "  echo \"a > \$STUB/codex\"; cp \"\$STUB/codex\" \"\$T/saved\"" "  echo '# stub: x'; cat >\"\$STUB/gh\"" \
    '  mv "$STUB/codex" "$STUB/codex.off"' '}' > "$L/conveyor/tests/a.test.sh"
  if (cd "$L" && bash .conveyor/test-lint.sh) > "$T/stub.out" 2>&1; then printf 'no\tstub check: the lint passed'; return; fi
  exp=$(printf '%s\n' conveyor/tests/a.test.sh:{2,9,10,11,12,14} | LC_ALL=C sort)
  got=$(grep -o '^conveyor/tests/[a-z]*\.test\.sh:[0-9]*' "$T/stub.out" | LC_ALL=C sort)
  if [ "$got" != "$exp" ]; then printf 'no\tstub check: not the lines %s: %s' "$(echo $exp)" "$(cat "$T/stub.out")"
  elif ! grep -q '"# stub: <why>" comment' "$T/stub.out"; then printf 'no\tstub check: the comment that clears it is not named: %s' "$(cat "$T/stub.out")"
  else printf 'ok\tfails: a hand-written stub the change added with no "# stub:", and only that'; fi
}
k=$((k + 1)); stubcheck > "$T/res.$k" &
# With no merge base with main, the loop and stub checks find nothing, and the sleep check still fails a
# sleep-then-check.
nobase() {
  local N=$T/nobase
  mkdir -p "$N/.conveyor" "$N/conveyor/tests"; cp "$HERE/test-lint.sh" "$N/.conveyor/"
  printf '%s\n' 'loop run' 'sleep 2; [ -e x ] || fail "no x"' 'cat > "$STUB/codex"' > "$N/conveyor/tests/a.test.sh"
  git -C "$N" init -q -b trunk && git -C "$N" add -A || { printf 'no\tno merge base: the fixture could not be made'; return; }
  if (cd "$N" && bash .conveyor/test-lint.sh) > "$T/nobase.out" 2>&1; then printf 'no\tno merge base: a sleep-then-check passed'
  elif grep -q 'full-loop\|hand-written\|a.test.sh:[13]:' "$T/nobase.out" || ! grep -q '^conveyor/tests/a.test.sh:2: ' "$T/nobase.out"; then
    printf 'no\tno merge base: not the sleep alone: %s' "$(cat "$T/nobase.out")"
  else printf 'ok\tfails: with no merge base, the sleep-then-check alone'; fi
}
k=$((k + 1)); nobase > "$T/res.$k" &

# A file that cannot be read fails, saying so: a lint that read nothing must not pass.
bash "$HERE/test-lint.sh" "$T/none.test.sh" > "$T/out" 2>&1 && no "a file that is not there passed the lint" \
  || { grep -q 'could not be read' "$T/out" && ok "a file that cannot be read fails the lint" || no "an unreadable file: $(cat "$T/out")"; }

# test-changed.sh runs the lint on every run: a sleep-then-check in a test file fails a whole run (no --file, no test
# step's log), whatever changed. Its one-file mode in a test step lints once a tree: test-changed-one.test.sh checks it.
R=$T/r; mkdir -p "$R/.conveyor" "$R/conveyor/tests"
cp "$HERE/test-changed.sh" "$HERE/lint-shell.sh" "$HERE/test-lint.sh" "$HERE/no-browser-tests.sh" "$R/.conveyor/"
printf '%s\n' '{"area": "core", "file": "conveyor/core.sh"}' '{"area": "core", "tests": "all"}' '{"area": "a", "file": "conveyor/x.sh"}' \
  '{"area": "a", "test": "a.test.sh"}' > "$R/.conveyor/engine-areas.json"
echo one > "$R/conveyor/core.sh"; echo one > "$R/conveyor/x.sh"; printf 't_one() {\n  :\n}\n' > "$R/conveyor/tests/a.test.sh"; echo 'exit 0' > "$R/conveyor/conveyor.test.sh"
git -C "$R" init -q && git -C "$R" add -A && git -C "$R" -c user.name=t -c user.email=t@example.com commit -qm init
(cd "$R" && unset CONVEYOR_TEST_LOG CONVEYOR_SHELL_TEST_CASE CONVEYOR_TEST_FILE CONVEYOR_TEST_FILES BASH_ENV CONVEYOR_TEST_RERUN && bash .conveyor/test-changed.sh) > "$T/out" 2>&1 \
  && ok "a run with no sleep-then-check passes" || no "a clean run failed: $(cat "$T/out")"
printf 't_one() {\n  sleep 2; [ -e x ] || fail "no x"\n}\n' > "$R/conveyor/tests/a.test.sh"
if (cd "$R" && unset CONVEYOR_TEST_LOG CONVEYOR_SHELL_TEST_CASE CONVEYOR_TEST_FILE CONVEYOR_TEST_FILES BASH_ENV CONVEYOR_TEST_RERUN && bash .conveyor/test-changed.sh) > "$T/out" 2>&1; then
  no "a run with a sleep-then-check in a test passed"
else grep -q '^conveyor/tests/a.test.sh:2: ' "$T/out" && ok "a run with a sleep-then-check fails, naming the line" || no "the failed run does not name the line: $(cat "$T/out")"; fi

results
echo "1..$n"
exit $bad
