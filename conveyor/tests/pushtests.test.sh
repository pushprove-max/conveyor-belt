#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 120
# Engine cases (#384): the run before a push (lib/pushrun.sh pushtests()): the test files the test map and the links give
# the landings since the last push, each alone, once; a file that fails is run on the landings in turn to find the one
# that broke it, goes to a main-fix card naming that landing, and holds the push; with the push check off (#395: the
# pack's push.check, or `control push-check`), it runs nothing; with the rule Push after a combined test run on (#1621),
# the loop holds the push until its run is due (pushbatchwhen), and the run runs whatever the push check says.
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"
# The engine folder, as lib.sh sets it: named here too, so the release closure (tools/closure.sh) follows this file's paths.
SRC=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)

# The fixture of every case: origin holds main as setup made it. Two landings since: c1 adds lib/cart.js, its test
# lib/cart.test.js and lib/cart-all.test.js, the pack's runner of the whole suite (test.wholeCommands), which the names
# link to cart.js too; c2 breaks lib/cart.js, so lib/cart.test.js fails on main. Sets base, l1 and l2; the pack's
# push.check is <check>. pushnow then pushes c2 as the loop does, its output in push.out.
pushfix() { # <push.check>
  setup '[]'
  base=$(git -C "$R" rev-parse HEAD)
  printf '%s\n' 'echo "$(git rev-parse HEAD) $1" >> "$STUB/ran"; bash "$1"' > "$STUB/one"
  tune --argjson c "$1" '.push.check = $c | .test.fileCommand = "bash \"$STUB/one\"" | .test.wholeCommands = ["lib/cart-all.test.js"] | .test.full = "touch \"$STUB/whole\""'
  mkdir -p "$R/lib" && echo good > "$R/lib/cart.js" && echo 'grep -qx good lib/cart.js' > "$R/lib/cart.test.js" \
    && echo 'touch "$STUB/whole"' > "$R/lib/cart-all.test.js" && git -C "$R" add -A && git -C "$R" commit -qm c1 \
    && l1=$(git -C "$R" rev-parse HEAD) && echo bad > "$R/lib/cart.js" && git -C "$R" commit -qam c2 && l2=$(git -C "$R" rev-parse HEAD) \
    || fail "the two landings could not be made"
  # Whole records (jq/check.jq): a `run` sets a partial line aside before it reads the landings.
  printf '%s\n' "{\"card\":\"c1\",\"issue\":1,\"step\":\"landed\",\"time\":\"2026-11-18T10:00:00Z\",\"tokens\":{\"claude\":0,\"codex\":0},\"result\":\"ok\",\"sha\":\"$l1\",\"reason\":\"\",\"product\":false}" \
    "{\"card\":\"c2\",\"issue\":2,\"step\":\"landed\",\"time\":\"2026-11-18T11:00:00Z\",\"tokens\":{\"claude\":0,\"codex\":0},\"result\":\"ok\",\"sha\":\"$l2\",\"reason\":\"\",\"product\":false}" >> "$ST/cards.jsonl"
}
pushnow() { # [<what the loop's shell runs>]
  # The loop's shell, as `conveyor.sh run` starts it.
  # shellcheck disable=SC2034 # HERE is read by the lines of conveyor.sh and commands/run.sh run by the eval
  ( HERE=$SRC; export CONVEYOR_MAIN=$R CONVEYOR_CARDS=$T/$CASE/cards
    eval "$(sed -n '/^\. "\$HERE\/lib\/portable.sh"/,/^\. "\$HERE\/lib\/records.sh"/p' "$SRC/conveyor.sh")"
    eval "$(grep '^\. "\$HERE/lib/' "$SRC/commands/run.sh")"
    names || exit 1; eval "${1:-push c2 2; checkheld && echo held > \"\$T/\$CASE/held\"}" ) > "$T/$CASE/push.out" 2>&1
}
# A pool of the case's own of <n> test slots (the host file's testSlots, in a folder no other case shares) for the run
# before the push, which then takes its slot there: with 1, it has no other slot free and runs its files one at a time.
pushpool() { # <n>
  mkdir -p "$XDG_CONFIG_HOME/conveyor" && echo "{\"testSlots\": $1, \"testSlotsDir\": \"$T/$CASE/slots\"}" > "$XDG_CONFIG_HOME/conveyor/host.json" \
    || fail "the case's pool of $1 test slot(s)"
}
# A push with the check off (#395): no test file runs, nothing is held, and main as it is is pushed.
pushedunchecked() {
  [ "$(git -C "$T/$CASE/origin" rev-parse main)" = "$l2" ] && [ ! -e "$T/$CASE/held" ] || fail "the push was held or did not push c2: $(cat "$T/$CASE/push.out")"
  [ ! -e "$STUB/ran" ] && [ ! -e "$STUB/whole" ] || fail "a test ran before the push with the check off: $(cat "$STUB/ran" "$T/$CASE/push.out" 2>&1)"
  grep -qF 'the push check is off (push.check, control push-check): no test file runs before the push' "$T/$CASE/push.out" \
    || fail "the push does not say the check is off: $(cat "$T/$CASE/push.out")"
}

# D3, D4 of #384; with push.check true (#395 D2), the run is as before. Bugs it catches: a landing that broke a test
# file the map links to its change was pushed, as its card ran only its own test files; the push's run named no
# landing, or the first one, so the main-fix card was sent to the wrong change; the push's run ran the test command
# (the whole suite) or a test runner of the whole suite; push.check true did not run the check. The push of c2 runs
# lib/cart.test.js alone on main, then on c1's commit, where it passes. Then (#395) `control push-check off` frees that
# held push. Bug it catches: the push stayed held (checkheld() still matched the failed push line), so the loop never
# pushed with no run asked for.
t_pushtests() {
  local l1 l2 base
  pushfix true; pushnow
  [ "$(git -C "$T/$CASE/origin" rev-parse main)" = "$base" ] || fail "the push was not held: $(cat "$T/$CASE/push.out")"
  [ "$(cat "$STUB/ran" 2>&1)" = "$l2 lib/cart.test.js
$l1 lib/cart.test.js" ] || fail "the run did not run lib/cart.test.js alone on main, then on c1's landing: $(cat "$STUB/ran" "$T/$CASE/push.out" 2>&1)"
  [ ! -e "$STUB/whole" ] && [ ! -e "$STUB/tests" ] || fail "the run ran the whole suite or its runner: $(ls "$STUB")"
  [ "$(jq -c --arg s "$l2" '.reds[] | select(.sha == $s) | .cases[] | [.file, .landing.sha, .landing.card]' "$ST/mainred.json" 2>&1)" = "[\"lib/cart.test.js\",\"$l2\",\"c2\"]" ] \
    || fail "no main-fix entry names c2's landing: $(cat "$ST/mainred.json" "$T/$CASE/push.out" 2>&1)"
  st 'select(.step == "push") | "\(.result) \(.kind) \(.check) \(.reason)"' | grep -qF "fail check lib/cart.test.js the run before the push failed 1 test file(s) linked to the landings since the last push: lib/cart.test.js (broken by the landing ${l2:0:12} of c2)" \
    && [ -e "$T/$CASE/held" ] || fail "the push line does not hold the push naming the file and c2: $(st 'select(.step == "push")')"
  rm -f "$T/$CASE/held"
  loop control push-check off >/dev/null 2>&1 || fail "control push-check off failed"
  pushnow 'checkheld && echo held > "$T/$CASE/held"'
  [ ! -e "$T/$CASE/held" ] || fail "the push is still held with the push check off: $(st 'select(.step == "push")')"
}

# Bug it catches: the run before the push took the test files of some landings only (the newest, the oldest, or the
# first and the last), so a file linked to another landing since the last push went out unrun. The push of c4 names
# c1's commit as held by origin, so the landings since then are c2, c3 and c4, each linked to a test file of its own:
# c2 (it changes lib/cart.js) lib/cart.test.js, c3 lib/tax.test.js, c4 lib/fee.test.js. Every file passes: the run
# runs the three, each once, in the order of the landings.
t_pushtestsunion() {
  local l1 l2 l4 base n
  pushfix true; pushpool 1 # one slot: the three files run one at a time, in order, as before #1709 (its D2)
  printf '%s\n' 'echo "$(git rev-parse HEAD) $1" >> "$STUB/ran"' > "$STUB/one" # one: every test file passes
  for n in 3:tax 4:fee; do
    echo "${n#*:}" > "$R/lib/${n#*:}.js" && echo "grep -qx ${n#*:} lib/${n#*:}.js" > "$R/lib/${n#*:}.test.js" \
      && git -C "$R" add -A && git -C "$R" commit -qm "c${n%%:*}" \
      && jq -cn --arg s "$(git -C "$R" rev-parse HEAD)" --argjson i "${n%%:*}" \
        '{card: "c\($i)", issue: $i, step: "landed", time: "2026-11-18T12:0\($i):00Z", result: "ok", sha: $s}' >> "$ST/cards.jsonl" \
      || fail "the landing c${n%%:*} could not be made"
  done
  l4=$(git -C "$R" rev-parse HEAD)
  pushnow "pushtests c4 4 $l4 $l1"
  [ "$(cat "$STUB/ran" 2>&1)" = "$l4 lib/cart.test.js
$l4 lib/tax.test.js
$l4 lib/fee.test.js" ] || fail "pushtests c4 4 $l4 $l1 did not run the files of every landing since c1 (c2: lib/cart.test.js, c3: lib/tax.test.js, c4: lib/fee.test.js), each once: $(cat "$STUB/ran" "$T/$CASE/push.out" 2>&1)"
}

# The file command's first line in the cases below: it notes each file it is given with CONVEYOR_TEST_NOTRACE (or
# "traced"). PUSHONE: the whole command of a file that passes, which, as a traced runner does, logs a traced file's
# pass with its inputs (lib/cart.js).
PUSHNOTE='echo "$(git rev-parse HEAD) $1 ${CONVEYOR_TEST_NOTRACE:-traced}" >> "$STUB/ran"'
PUSHONE="$PUSHNOTE"'
[ -n "$CONVEYOR_TEST_NOTRACE" ] || printf -- "-- ok %s\nTESTRUN inputs\t%s\tlib/cart.js\n" "$1" "$1" >> "$CONVEYOR_TEST_LOG/test-changed.log"'
# A pass of lib/cart.test.js in the test results cache, read with lib/cart.js as the checkout <dir> has it, as
# cachekeep() writes it: `<hash>\t<commit>\t<file>\t<input>`, the commit the HEAD of <dir>.
pushpass() { # <dir>
  mkdir -p "${TESTCACHE%/*}" && printf 'lib/cart.test.js\tlib/cart.js\n' | cachesums "$1" \
    | awk -v h="$(git -C "$1" rev-parse HEAD)" 'BEGIN { FS = OFS = "\t" } { $1 = $1 OFS h } 1'
}
PUSHPASS=pushpass
# #1709 D1. Bug it catches: the run before the push ran lib/cart.test.js again (and held the push on it) though the
# cache holds its pass with the inputs main has, as a card's Test step left it. The pass is written here, not by a
# card's run, so the stub's run of the file would fail it (main's lib/cart.js is bad): no file runs, and c2 is pushed.
t_pushtestsreuse() {
  local l1 l2 base
  pushfix true
  pushnow "$PUSHPASS \"\$R\" > \"\$TESTCACHE\" || exit 1; push c2 2; checkheld && echo held > \"\$T/\$CASE/held\""
  [ ! -e "$STUB/ran" ] || fail "the run before the push ran a file whose pass holds with main's inputs: $(cat "$STUB/ran" "$T/$CASE/push.out" 2>&1)"
  [ "$(git -C "$T/$CASE/origin" rev-parse main)" = "$l2" ] && [ ! -e "$T/$CASE/held" ] || fail "c2 was not pushed: $(cat "$T/$CASE/push.out")"
  grep -qF '1 test file(s) linked to the landings since the last push passed before with the same inputs and do not run again' "$T/$CASE/push.out" \
    || fail "the push does not say the file was not run again: $(cat "$T/$CASE/push.out")"
}

# #1709 D2, D3. Bug it catches: a pass of lib/cart.test.js read with c1's lib/cart.js (good), which c2 changed, kept the
# file off the run, so c2's broken lib/cart.js went out; or the file ran untraced, so its new inputs were never kept.
t_pushtestsstale() {
  local l1 l2 base
  pushfix true
  printf '%s\n' "$PUSHNOTE" 'bash "$1"' > "$STUB/one"
  pushnow "pushwt \"\$CARDS/old\" $l1 && $PUSHPASS \"\$CARDS/old\" > \"\$TESTCACHE\" && pushwt \"\$CARDS/old\" || exit 1
    push c2 2; checkheld && echo held > \"\$T/\$CASE/held\""
  [ "$(git -C "$T/$CASE/origin" rev-parse main)" = "$base" ] && [ -e "$T/$CASE/held" ] || fail "the push was not held: $(cat "$T/$CASE/push.out")"
  [ "$(head -n 1 "$STUB/ran" 2>&1)" = "$l2 lib/cart.test.js traced" ] \
    || fail "lib/cart.test.js, whose input lib/cart.js changed since its pass, did not run traced on main: $(cat "$STUB/ran" "$T/$CASE/push.out" 2>&1)"
}

# #1709 D3. With pushbatchtests all every file runs: lib/cart.test.js, whose pass in the cache holds with main's inputs,
# untraced (CONVEYOR_TEST_NOTRACE=1), and a.test.sh, with no pass there, traced, its pass then kept with its inputs.
# Bugs it catches: a file whose list of inputs is fresh was traced again; a pass the run traced was not kept, so its
# trace was for nothing and the next push ran the file again; the pass was kept without its input lib/cart.js, so a
# later push would reuse it though lib/cart.js had changed. cachehits(), as the next push asks it, must name both
# files on main as it is, and neither once lib/cart.js changes.
t_pushtestsnotrace() {
  local l1 l2 base
  pushfix true; pushpool 1 # one slot: the two files run one at a time, in order (t_pushtestsside runs them side by side)
  printf '%s\n' "$PUSHONE" > "$STUB/one"
  loop control rules pushbatch=on pushbatchtests=all > /dev/null || fail "control rules pushbatch=on pushbatchtests=all failed"
  pushnow "$PUSHPASS \"\$R\" > \"\$TESTCACHE\" || exit 1; pushtests c2 2 $l2 $base && cachehits \"\$R\" > \"\$T/\$CASE/kept\" \\
    && echo changed > \"\$R/lib/cart.js\" && cachehits \"\$R\" > \"\$T/\$CASE/changed\""
  [ "$(cat "$STUB/ran" 2>&1)" = "$l2 a.test.sh traced
$l2 lib/cart.test.js 1" ] || fail "pushtests c2 2 $l2 $base with pushbatchtests all did not run a.test.sh traced and lib/cart.test.js untraced: $(cat "$STUB/ran" "$T/$CASE/push.out" 2>&1)"
  [ "$(cat "$T/$CASE/kept" 2>&1)" = $'a.test.sh\nlib/cart.test.js' ] \
    || fail "cachehits on main after pushtests c2 2 $l2 $base does not name a.test.sh, so its traced pass is not reusable: $(cat "$T/$CASE/kept" "$T/$CASE/push.out" 2>&1)"
  [ -e "$T/$CASE/changed" ] && [ ! -s "$T/$CASE/changed" ] \
    || fail "cachehits with lib/cart.js changed still names a file whose kept pass read it (its input was lost): $(cat "$T/$CASE/changed" "$T/$CASE/push.out" 2>&1)"
}

# #1709 D2. With pushbatchtests all, a.test.sh and lib/cart.test.js run on a pool of three slots: each file's command
# leaves its mark and waits, up to 10 s times the load factor, until both files have begun, then notes how many it
# saw; lib/cart.test.js then fails on main, printing a stack frame of its line 1. Bugs it catches: the run before the push ran its files one at a time
# though test slots were free (each saw only itself), so its time grew with the number of files; run side by side, a
# file whose list of inputs is fresh was traced (CONVEYOR_TEST_NOTRACE lost), or the failed file did not hold the push
# or its reason lost where the file failed.
t_pushtestsside() {
  local l1 l2 base
  pushfix true; pushpool 3
  # sleep: a file's wait for the other, in its own shell (no wait_until there)
  printf '%s\n' "d=$T/$CASE/at; mkdir -p \"\$d\"; : > \"\$d/\${1//\//_}\"" \
    "i=0; while [ \"\$(ls \"\$d\" | wc -l)\" -lt 2 ] && [ \$i -lt $(loadlimit 200) ]; do i=\$((i + 1)); sleep 0.05; done" \
    'echo "$(git rev-parse HEAD) $1 ${CONVEYOR_TEST_NOTRACE:-traced} saw $(ls "'"$T/$CASE/at"'" | wc -l)" >> "$STUB/ran"' \
    '[ "$1" != lib/cart.test.js ] || bash "$1" || { echo "    at Object.<anonymous> ($PWD/$1:1:1)"; exit 1; }' > "$STUB/one"
  loop control rules pushbatch=on pushbatchtests=all > /dev/null || fail "control rules pushbatch=on pushbatchtests=all failed"
  pushnow "$PUSHPASS \"\$R\" > \"\$TESTCACHE\" || exit 1; pushtests c2 2 $l2 $base || echo held > \"\$T/\$CASE/held\""
  [ "$(grep "^$l2 " "$STUB/ran" 2>&1 | sort)" = "$l2 a.test.sh traced saw 2
$l2 lib/cart.test.js 1 saw 2" ] || fail "pushtests c2 2 $l2 $base on three free slots did not run a.test.sh (traced) and lib/cart.test.js (untraced) side by side: $(cat "$STUB/ran" "$T/$CASE/push.out" 2>&1)"
  grep -qF 'run, each alone, side by side on the free test slots' "$T/$CASE/push.out" || fail "the push does not say its files run side by side: $(cat "$T/$CASE/push.out")"
  [ -e "$T/$CASE/held" ] && st 'select(.step == "push") | "\(.result) \(.check) \(.reason)"' | grep -qF "fail lib/cart.test.js the run before the push failed 1 test file(s) of ${l2:0:12} (pushbatchtests all): lib/cart.test.js (broken by the landing ${l2:0:12} of c2; it failed at lib/cart.test.js:1: grep -qx good lib/cart.js)" \
    || fail "pushtests c2 2 $l2 $base did not hold the push on lib/cart.test.js, which failed side by side, naming where it failed: $(st 'select(.step == "push")') $(cat "$T/$CASE/push.out")"
}

# The push record of the run before the push, as push() writes it at its stage tests (pushing()), then pushtests c2 2.
PUSHREC='pproc=$BASHPID; pushing "$l2" tests; pushtests c2 2 "$l2" "$base" || echo held > "$T/$CASE/held"'
# #1709 D4, one file at a time (one slot). Each file's command keeps the push record as it starts: a.test.sh passes,
# lib/cart.test.js fails on main. Bugs it catches: the push record did not name the files the run chose, or named
# none done while it went on, so the Board showed a push at its tests with no progress; the record, or health's push
# in progress (lib/views.sh), did not name the failed file.
t_pushtestsprogress() {
  local l1 l2 base
  pushfix true; pushpool 1
  printf '%s\n' "cp \"\$PUSHING\" \"$T/$CASE/rec.\$(git rev-parse HEAD).\${1//\//_}\"; [ \"\$1\" = a.test.sh ] || bash \"\$1\"" > "$STUB/one"
  loop control rules pushbatch=on pushbatchtests=all > /dev/null || fail "control rules pushbatch=on pushbatchtests=all failed"
  pushnow "export PUSHING; $PUSHREC"
  [ "$(jq -c .files "$T/$CASE/rec.$l2.a.test.sh" 2>&1)" = '{"chosen":["a.test.sh","lib/cart.test.js"],"done":[],"failed":[]}' ] \
    && [ "$(jq -c .files "$T/$CASE/rec.$l2.lib_cart.test.js" 2>&1)" = '{"chosen":["a.test.sh","lib/cart.test.js"],"done":["a.test.sh"],"failed":[]}' ] \
    || fail "pushtests c2 2 $l2 $base: the push record as each file began does not name the files chosen and those done: $(cat "$T/$CASE"/rec.* "$T/$CASE/push.out" 2>&1)"
  [ -e "$T/$CASE/held" ] && [ "$(loop health | jq -c .pushing.files)" = '{"chosen":["a.test.sh","lib/cart.test.js"],"done":["a.test.sh","lib/cart.test.js"],"failed":["lib/cart.test.js"]}' ] \
    || fail "pushtests c2 2 $l2 $base: health's push in progress does not name lib/cart.test.js failed: $(cat "$ST/pushing" "$T/$CASE/push.out" 2>&1)"
}

# #1709 D4, side by side (three slots). lib/cart.test.js's command waits, up to 10 s times the load factor, until the
# push record names a.test.sh done, keeps the record it saw first, then fails on main. Bugs it catches: the record named the files done only once
# every file had ended, so a long side-by-side run showed no progress; it did not name the failed file at the end.
t_pushtestssideprogress() {
  local l1 l2 base
  pushfix true; pushpool 3
  # sleep: the file's wait for the record, in its own shell (no wait_until there)
  printf '%s\n' '[ "$1" = a.test.sh ] && exit 0' \
    "i=0; until jq -e 'any(.files.done[]; . == \"a.test.sh\")' \"\$PUSHING\" > /dev/null 2>&1 || [ \$i -ge $(loadlimit 200) ]; do i=\$((i + 1)); sleep 0.05; done" \
    "[ -e \"$T/$CASE/seen\" ] || jq -c .files \"\$PUSHING\" > \"$T/$CASE/seen\"; bash \"\$1\"" > "$STUB/one"
  loop control rules pushbatch=on pushbatchtests=all > /dev/null || fail "control rules pushbatch=on pushbatchtests=all failed"
  pushnow "export PUSHING; $PUSHREC"
  grep -qF 'side by side on the free test slots' "$T/$CASE/push.out" || fail "the push did not run its files side by side: $(cat "$T/$CASE/push.out")"
  [ "$(cat "$T/$CASE/seen" 2>&1)" = '{"chosen":["a.test.sh","lib/cart.test.js"],"done":["a.test.sh"],"failed":[]}' ] \
    || fail "pushtests c2 2 $l2 $base side by side: the push record while lib/cart.test.js ran did not name a.test.sh done: $(cat "$T/$CASE/seen" "$T/$CASE/push.out" 2>&1)"
  [ -e "$T/$CASE/held" ] && [ "$(jq -c .files "$ST/pushing")" = '{"chosen":["a.test.sh","lib/cart.test.js"],"done":["a.test.sh","lib/cart.test.js"],"failed":["lib/cart.test.js"]}' ] \
    || fail "pushtests c2 2 $l2 $base side by side: the push record at the end does not name lib/cart.test.js failed: $(cat "$ST/pushing" "$T/$CASE/push.out" 2>&1)"
}

# Bug it catches: the file command logged a traced pass of lib/cart.test.js (`-- ok` and its inputs) and then failed
# it, as a check of .conveyor/test-changed.sh after the tests (mapcheck) does; the cache kept that pass, so a later push
# whose inputs still matched skipped the file and the check that failed it.
t_pushtestsfailkeep() {
  local l1 l2 base
  pushfix true
  printf '%s\n' "$PUSHONE" 'exit 1' > "$STUB/one"
  pushnow "pushtests c2 2 $l2 $base; cut -f3 \"\$TESTCACHE\" > \"\$T/\$CASE/kept\" 2>/dev/null"
  [ "$(head -n 1 "$STUB/ran" 2>&1)" = "$l2 lib/cart.test.js traced" ] || fail "pushtests c2 2 $l2 $base did not run lib/cart.test.js traced: $(cat "$STUB/ran" "$T/$CASE/push.out" 2>&1)"
  ! grep -qxF lib/cart.test.js "$T/$CASE/kept" 2>/dev/null || fail "pushtests c2 2 $l2 $base kept the pass of lib/cart.test.js, whose run failed: $(cat "$T/$CASE/kept" "$T/$CASE/push.out" 2>&1)"
}

# #1084. Bug it catches: the run before the push named the failing file and the landing that broke it, but not where
# it failed, so a failure that printed no message of its own (only a stack) could not be read without a run again.
# The file command prints a stack frame of the push worktree's lib/cart.test.js, line 1, when the file fails: the push
# line's reason gives that line and its text after the landing.
t_pushtestsat() {
  local l1 l2 base
  pushfix true
  printf '%s\n' 'echo "$(git rev-parse HEAD) $1" >> "$STUB/ran"; bash "$1" || { echo "    at Object.<anonymous> ($PWD/$1:1:1)"; exit 1; }' > "$STUB/one"
  pushnow
  st 'select(.step == "push") | .reason' | grep -qF "lib/cart.test.js (broken by the landing ${l2:0:12} of c2; it failed at lib/cart.test.js:1: grep -qx good lib/cart.js)" \
    || fail "the push line's reason does not give where the file failed: $(st 'select(.step == "push") | .reason')"
}

# #1084, E2 of its review. Bug it catches: the push check ran each file under testTimeout as it is, so on a busy
# machine a file within that limit times the load factor failed, and held the push. testTimeout 1 s and a load factor
# of 3: a file that takes 2 s passes, and one that takes 5 s fails with a reason that names the limit and the factor.
# The output is only those two lines: E7's bug, the first file's run printing an error for the log not made yet, adds one.
t_pushtestsload() {
  local l1 l2 base
  pushfix true
  printf '%s\n' 'sleep "${1%.test.sh}"' > "$STUB/one" # sleep: a file that takes the seconds its name says
  pushnow 'pushwt "$CARDS/pushtest" '"$l1"' || exit 1; export TEST_TIMEOUT=1 CONVEYOR_LOAD_FACTOR=3
    pushfile "$CARDS/pushtest" 2.test.sh && echo "2 passed"; pushfile "$CARDS/pushtest" 5.test.sh || cat "$CARDS/pushtest.failat"'
  [ "$(cat "$T/$CASE/push.out")" = $'2 passed\nit ran past its time limit, 3 s (testTimeout\'s 1 s times the load factor 3), and was stopped there' ] \
    || fail "the push check's file limit is not testTimeout times the load factor, or its timeout does not name them: $(cat "$T/$CASE/push.out")"
}

# #1709 D2: t_pushtestsload's limit, side by side (pushside()). testTimeout 1 s and a load factor of 3 on a pool of
# three: 2.test.sh (2 s) passes, and 5.test.sh (5 s) fails with the reason that names the limit and the factor. Bug it
# catches: files run side by side had no time limit of the push's, or a file stopped there was not named as such.
t_pushtestssideload() {
  local l1 l2 base
  pushfix true; pushpool 3
  printf '%s\n' 'sleep "${1%.test.sh}"' > "$STUB/one" # sleep: a file that takes the seconds its name says
  pushnow 'pushwt "$CARDS/pushtest" '"$l1"' && slot_pool && slot_try || exit 1; export TEST_TIMEOUT=1 CONVEYOR_LOAD_FACTOR=3; local -A hit=() fat=(); bad=()
    pushside "$CARDS/pushtest" "bash \"\$STUB/one\"" 2.test.sh 5.test.sh; echo "${bad[*]}: ${fat[5.test.sh]}"'
  [ "$(cat "$T/$CASE/push.out")" = "5.test.sh: it ran past its time limit, 3 s (testTimeout's 1 s times the load factor 3), and was stopped there" ] \
    || fail "pushside with testTimeout 1 and the load factor 3 did not fail 5.test.sh alone, naming the limit and the factor: $(cat "$T/$CASE/push.out" "$T/$CASE/cards/pushtest.log" 2>&1)"
}

# #395 D1. Bug it catches: with the pack's push.check false, a push after a landing still ran the linked test files
# (and held the push on the one c2 broke), where the owner had turned the check off.
t_pushcheckoff() {
  local l1 l2 base
  pushfix false; pushnow; pushedunchecked
}

# #395 D3. Bug it catches: `conveyor.sh control push-check off` (the Rules tab's Test before a push) did not override
# the pack's push.check true, so the push ran the linked files and was held.
t_pushcheckctl() {
  local l1 l2 base
  pushfix true
  [ "$(loop control push-check off 2>&1 | jq .pushCheck)" = false ] || fail "control push-check off did not set the record's pushCheck: $(cat "$ST/control.json")"
  pushnow; pushedunchecked
}

# R70 of #1441. Bug it catches: the Rules tab's Undo of a Test before a push change could only send on or off, so a
# record that set nothing (the pack's push.check holds) kept a permanent override after Undo. `push-check default`
# puts the record back to no value, so the pack's push.check holds again.
t_pushcheckdefault() {
  setup '[]'
  [ "$(loop control push-check on 2>&1 | jq .pushCheck)" = true ] || fail "control push-check on did not set the record's pushCheck: $(cat "$ST/control.json")"
  [ "$(loop control push-check default 2>&1 | jq .pushCheck)" = null ] || fail "control push-check default left a value in the record: $(cat "$ST/control.json")"
  [ "$(jq -c .pushCheck "$ST/control.json")" = null ] || fail "the stored record keeps a pushCheck after default: $(cat "$ST/control.json")"
}

# R104 of #1389. Bug it catches: a file that failed, passed, then failed again across three landings was blamed on the
# first, as the landings ran oldest first up to the first that failed it, so the main-fix card went to a change a later
# landing had fixed. c1 adds lib/cart.js broken with its test, c2 fixes it, c3 breaks it again: the push and the
# main-fix entry name c3, and the file runs alone on main (c3), then on c2, where it passes.
t_pushtestsblame() {
  local base i s ls=()
  setup '[]'; base=$(git -C "$R" rev-parse HEAD)
  printf '%s\n' 'echo "$(git rev-parse HEAD) $1" >> "$STUB/ran"; bash "$1"' > "$STUB/one"
  tune '.push.check = true | .test.fileCommand = "bash \"$STUB/one\""'
  mkdir -p "$R/lib" && echo 'grep -qx good lib/cart.js' > "$R/lib/cart.test.js" || fail "the test file could not be written"
  for i in 1 2 3; do
    { [ $i = 2 ] && echo good || echo bad; } > "$R/lib/cart.js" && git -C "$R" add -A && git -C "$R" commit -qm "c$i" && s=$(git -C "$R" rev-parse HEAD) \
      && jq -cn --arg s "$s" --argjson i $i '{card: "c\($i)", issue: $i, step: "landed", time: "2026-11-18T1\($i):00:00Z", result: "ok", sha: $s}' >> "$ST/cards.jsonl" \
      || fail "landing $i could not be made"
    ls+=("$s")
  done
  pushnow 'push c3 3; checkheld && echo held > "$T/$CASE/held"'
  [ "$(git -C "$T/$CASE/origin" rev-parse main)" = "$base" ] && [ -e "$T/$CASE/held" ] || fail "the push was not held: $(cat "$T/$CASE/push.out")"
  [ "$(cat "$STUB/ran" 2>&1)" = "${ls[2]} lib/cart.test.js
${ls[1]} lib/cart.test.js" ] || fail "the file did not run on main (c3), then on c2 alone: $(cat "$STUB/ran" "$T/$CASE/push.out" 2>&1)"
  [ "$(jq -c '[.reds[].cases[] | [.file, .landing.sha, .landing.card]]' "$ST/mainred.json" 2>&1)" = "[[\"lib/cart.test.js\",\"${ls[2]}\",\"c3\"]]" ] \
    || fail "the main-fix entry does not name c3's landing: $(cat "$ST/mainred.json" 2>&1)"
  st 'select(.step == "push") | .reason' | grep -qF "lib/cart.test.js (broken by the landing ${ls[2]:0:12} of c3)" \
    || fail "the push line does not name c3: $(st 'select(.step == "push") | .reason')"
}

# #1621 D1: the files linked to the landings since the last push are those of every landing. Bug it catches: the
# selection (pushtests(), lib/pushrun.sh) took the test files of one landing alone, the oldest or the newest, so a file
# only another landing links never ran before the push. c1 adds lib/cart.js and lib/cart.test.js, c2 adds lib/bag.js
# and lib/bag.test.js: each landing links a file the other does not, and both run on main.
t_pushtestsevery() {
  local base i s f
  setup '[]'; base=$(git -C "$R" rev-parse HEAD)
  printf '%s\n' 'echo "$(git rev-parse HEAD) $1" >> "$STUB/ran"; bash "$1"' > "$STUB/one"
  tune '.push.check = true | .test.fileCommand = "bash \"$STUB/one\""'
  mkdir -p "$R/lib" || fail "lib could not be made"
  for i in 1 2; do
    f=$([ $i = 1 ] && echo cart || echo bag)
    echo good > "$R/lib/$f.js" && echo "grep -qx good lib/$f.js" > "$R/lib/$f.test.js" && git -C "$R" add -A && git -C "$R" commit -qm "c$i" \
      && s=$(git -C "$R" rev-parse HEAD) \
      && jq -cn --arg s "$s" --argjson i $i '{card: "c\($i)", issue: $i, step: "landed", time: "2026-11-18T1\($i):00:00Z", result: "ok", sha: $s}' >> "$ST/cards.jsonl" \
      || fail "landing $i could not be made"
  done
  pushnow "pushtests c2 2 $s $base"
  [ "$(sort "$STUB/ran" 2>&1)" = "$s lib/bag.test.js
$s lib/cart.test.js" ] || fail "pushtests c2 2 $s $base did not run on main the files linked to c1 (lib/cart.test.js) and to c2 (lib/bag.test.js): $(cat "$STUB/ran" "$T/$CASE/push.out" 2>&1)"
}

# R103 of #1389. Bug it catches: a push the remote refused, as it held a commit made by hand, merged that commit into
# main and pushed the merge with no run of the linked test files on it, so a file that fails only on the merged tree
# went out. c1 adds lib/cart.test.js, which fails once hand.txt is there; hand.txt is the commit by hand on origin. The
# file passes on c1, the push is refused, main becomes the merge, and the file fails there: the push is held as a
# check failure on the merge, and origin keeps the commit by hand.
t_pushtestsmerge() {
  local l1 hand m H=$T/$CASE/hand
  setup '[]'
  printf '%s\n' 'echo "$(git rev-parse HEAD) $1" >> "$STUB/ran"; bash "$1"' > "$STUB/one"
  tune '.push.check = true | .test.fileCommand = "bash \"$STUB/one\""'
  mkdir -p "$R/lib" && echo good > "$R/lib/cart.js" && printf '%s\n' 'grep -qx good lib/cart.js' '[ ! -e hand.txt ]' > "$R/lib/cart.test.js" \
    && git -C "$R" add -A && git -C "$R" commit -qm c1 && l1=$(git -C "$R" rev-parse HEAD) || fail "the landing could not be made"
  jq -cn --arg s "$l1" '{card: "c1", issue: 1, step: "landed", time: "2026-11-18T10:00:00Z", result: "ok", sha: $s}' >> "$ST/cards.jsonl"
  git clone -q "$T/$CASE/origin" "$H" && echo hand > "$H/hand.txt" && git -C "$H" add hand.txt && git -C "$H" commit -qm 'by hand' \
    && git -C "$H" push -q origin main && hand=$(git -C "$H" rev-parse HEAD) || fail "the commit by hand could not be made"
  pushnow 'push c1 1; checkheld && echo held > "$T/$CASE/held"'
  m=$(git -C "$R" rev-parse main)
  [ "$(git -C "$R" rev-parse main^2 2>&1)" = "$hand" ] || fail "main is not the merge with the commit by hand: $(git -C "$R" log --oneline -3 main) $(cat "$T/$CASE/push.out")"
  [ "$(git -C "$T/$CASE/origin" rev-parse main)" = "$hand" ] && [ -e "$T/$CASE/held" ] || fail "the merge was pushed, or the push is not held: $(cat "$T/$CASE/push.out")"
  [ "$(cat "$STUB/ran" 2>&1)" = "$l1 lib/cart.test.js
$m lib/cart.test.js
$l1 lib/cart.test.js" ] || fail "the file did not run on c1, then on the merge (and on c1 for the landing that broke it): $(cat "$STUB/ran" "$T/$CASE/push.out" 2>&1)"
  [ "$(st 'select(.step == "push") | [.result, .kind, .check, .sha] | join(" ")')" = "fail check lib/cart.test.js $m" ] \
    || fail "the push line is not a check failure of the merge naming the file: $(st 'select(.step == "push")')"
}

# One turn of the loop's push (pushturn(), lib/push.sh), as a new loop makes it, run by pushnow: a push it starts has
# ended before the turn's word on the push ($PUSHWAIT's held) is printed. STUBPUSH: push() a stub that writes its card
# and issue to $STUB/pushcalls in place of a push.
PUSHTURN='nopack="" new="" pusher="" tried="" triedat=0 PUSH_RETRY=600; pushturn; [ -z "$pusher" ] || wait "$pusher"; jq -r .held "$PUSHWAIT"'
STUBPUSH='push() { echo "$1 $2" >> "$STUB/pushcalls"; }; '
# #1621, the rule Push after a combined test run (rules.pushbatch), with Test before a push off (the pack's push.check
# false, and the state folder's push.check.off), so only the rule makes the run. c1 and c2 have landed. Bugs it
# catches: with the rule on and its run set for 3 landings (pushbatchwhen), the turn pushed c1 and c2, so cards went
# out before the owner's count; set for a UTC time of day, the run was due before that time came, or not once it had
# passed (batchdue()); with the rule off, the turn held the push where it pushes at once; once the run was due (2
# landings), the push ran no test (Test before a push is off) and took c2's broken lib/cart.js to origin, or its push
# line did not name c2, or the next turn pushed it all the same.
t_pushbatch() {
  local l1 l2 base
  pushfix false
  loop control rules push=on pushbatch=on pushbatchwhen=3 > /dev/null || fail "control rules push=on pushbatch=on pushbatchwhen=3 failed"
  pushnow "$STUBPUSH$PUSHTURN"
  [ ! -e "$STUB/pushcalls" ] && [ "$(cat "$T/$CASE/push.out")" = 'the rule Push after a combined test run holds the push until its run is due (pushbatchwhen)' ] \
    || fail "with the rule on for 3 landings and 2 landed, the turn (pushturn) did not hold the push: $(cat "$STUB/pushcalls" "$T/$CASE/push.out" 2>&1)"
  # c1 landed at 10:00 and c2 at 11:00 UTC on 2026-11-18. At 10:30 that day, 11:00 last came the day before; at 12:00, after c1.
  loop control rules pushbatchwhen=11:00 > /dev/null && pushnow 'for n in 1794997800 1795003200; do CONVEYOR_NOW=$n batchdue && echo "$n due" || echo "$n not due"; done'
  [ "$(cat "$T/$CASE/push.out")" = $'1794997800 not due\n1795003200 due' ] \
    || fail "pushbatchwhen=11:00 was not due at 10:30 and due at 12:00 (batchdue): $(cat "$T/$CASE/push.out")"
  loop control rules pushbatch=off > /dev/null && pushnow "$STUBPUSH$PUSHTURN"
  [ "$(cat "$STUB/pushcalls" 2>&1)" = 'c2 2' ] || fail "with the rule off, the turn (pushturn) did not push c2 at once: $(cat "$T/$CASE/push.out")"
  loop control rules pushbatch=on pushbatchwhen=2 > /dev/null && : > "$ST/push.check.off"
  pushnow "$PUSHTURN; checkheld && echo held > \"\$T/\$CASE/held\""
  [ "$(git -C "$T/$CASE/origin" rev-parse main)" = "$base" ] && [ -z "$(st 'select(.step == "pushed") | .card')" ] \
    || fail "the turn with the run due pushed c1 or c2 past a failed run: $(st 'select(.step | IN("push", "pushed"))') $(cat "$T/$CASE/push.out")"
  [ "$(cat "$STUB/ran" 2>&1)" = "$l2 lib/cart.test.js
$l1 lib/cart.test.js" ] || fail "with the rule on, the push did not run lib/cart.test.js on main, then on c1's landing: $(cat "$STUB/ran" "$T/$CASE/push.out" 2>&1)"
  st 'select(.step == "push") | "\(.result) \(.kind) \(.reason)"' | grep -qF "fail check the run before the push failed 1 test file(s) linked to the landings since the last push: lib/cart.test.js (broken by the landing ${l2:0:12} of c2)" \
    && [ -e "$T/$CASE/held" ] || fail "the failed run's push line does not name c2, or does not hold the push: $(st 'select(.step == "push")')"
}

# #1621. With the rule on, its run due (2 landings) and pushbatchtests all, c1 and c2 go out in one push once the run
# before it passes. lib/other.test.js, added to main after c2 by no card, is linked to neither landing. Bugs it
# catches: a pack whose test command cannot be given one file pushed them with no run (it holds them, saying why);
# once it can, the run ran only the files linked to the landings (pushbatchtests ignored), or ran the pack's runner of
# the whole suite (lib/cart-all.test.js) as a test file, or the push left a card unpushed or pushed them apart. Also: a
# pass of the linked files alone (pushbatchtests linked) on the same main commit cleared the push after the owner set
# pushbatchtests all, so the other files never ran. a.test.sh is the fixture's own test file of main (setup()).
t_pushbatchpass() {
  local l1 l2 base m
  pushfix false
  echo 'true' > "$R/lib/other.test.js" && git -C "$R" add lib/other.test.js && git -C "$R" commit -qm other && m=$(git -C "$R" rev-parse HEAD) \
    || fail "lib/other.test.js could not be committed"
  loop control rules push=on pushbatch=on pushbatchtests=all > /dev/null || fail "control rules push=on pushbatch=on pushbatchtests=all failed"
  printf '%s\n' 'echo "$(git rev-parse HEAD) $1" >> "$STUB/ran"' > "$STUB/one" # one: every test file passes
  tune 'del(.test.fileCommand) | .test.list = "runner"'; pushnow "$PUSHTURN"
  [ "$(git -C "$T/$CASE/origin" rev-parse main)" = "$base" ] && st 'select(.step == "push") | "\(.kind) \(.reason)"' | grep -qF 'transport the test files linked to the landings did not run before the push' \
    || fail "with no test.fileCommand, the rule did not hold the push, saying why: $(st 'select(.step == "push")') $(cat "$T/$CASE/push.out")"
  tune '.test.fileCommand = "bash \"$STUB/one\""'
  loop control rules pushbatchtests=linked > /dev/null && pushnow "pushtests c2 2 $m $base" \
    && [ "$(cat "$STUB/ran" 2>&1)" = "$m lib/cart.test.js" ] || fail "pushtests c2 2 $m $base with pushbatchtests linked did not pass on lib/cart.test.js alone: $(cat "$STUB/ran" "$T/$CASE/push.out" 2>&1)"
  rm -f "$STUB/ran"; loop control rules pushbatchtests=all > /dev/null && pushnow "$PUSHTURN"
  [ "$(cat "$STUB/ran" 2>&1)" = "$m a.test.sh
$m lib/cart.test.js
$m lib/other.test.js" ] || fail "with pushbatchtests all, after a pass of the linked files on the same commit, the run before the push did not run every test file of main but the runner: $(cat "$STUB/ran" "$T/$CASE/push.out" 2>&1)"
  [ "$(git -C "$T/$CASE/origin" rev-parse main)" = "$m" ] && [ "$(st 'select(.step == "pushed") | "\(.card) \(.head)"' | paste -sd,)" = "c1 $m,c2 $m" ] \
    || fail "c1 and c2 were not pushed together at main: $(st 'select(.step | IN("push", "pushed"))') $(cat "$T/$CASE/push.out")"
}

# #1621. With the rule on, its run due and pushbatchtests all, a.test.sh (the fixture's own test file of main) fails
# already on origin, before c1 and c2, and still fails on them; c2 breaks lib/cart.test.js. Bug it catches: the run
# named c1, the oldest landing, as the one that broke a.test.sh, as it never ran the file on the commit before c1. The
# push is held, the reason says a.test.sh failed before the landings, and it names c2 for lib/cart.test.js alone.
t_pushbatchold() {
  local l1 l2 base r
  pushfix false
  printf '%s\n' 'echo "$(git rev-parse HEAD) $1" >> "$STUB/ran"; [ "$1" != a.test.sh ] && bash "$1"' > "$STUB/one"
  loop control rules push=on pushbatch=on pushbatchtests=all > /dev/null || fail "control rules push=on pushbatch=on pushbatchtests=all failed"
  pushnow "$PUSHTURN"
  r=$(st 'select(.step == "push") | "\(.result) \(.kind) \(.reason)"')
  [ "$(git -C "$T/$CASE/origin" rev-parse main)" = "$base" ] && [ -z "$(st 'select(.step == "pushed") | .card')" ] \
    || fail "with a.test.sh failing on main, the turn pushed c1 or c2: $r $(cat "$T/$CASE/push.out")"
  grep -qF "fail check the run before the push failed 2 test file(s) of ${l2:0:12} (pushbatchtests all): a.test.sh (it failed before the landings since the last push too" <<<"$r" \
    && grep -qF "lib/cart.test.js (broken by the landing ${l2:0:12} of c2" <<<"$r" && ! grep -qF "${l1:0:12}" <<<"$r" \
    || fail "the push line does not say a.test.sh failed before c1 and c2, names c1, or does not name c2 for lib/cart.test.js: $r"
  grep -qx "$base a.test.sh" "$STUB/ran" || fail "a.test.sh did not run on the commit before c1: $(cat "$STUB/ran" 2>&1)"
}

# #1621. Bug it catches: a `run` whose landings are fewer than pushbatchwhen ended only once a turn had tried their
# push, and the rule stops every turn from trying it, so the run turned for ever (run(), lib/run.sh, pushdecided()).
# It ends, exit 1, saying the rule holds the push, and nothing is pushed.
t_pushbatchrun() {
  local l1 l2 base out rc=0
  pushfix false
  loop control rules push=on pushbatch=on pushbatchwhen=3 > /dev/null || fail "control rules push=on pushbatch=on pushbatchwhen=3 failed"
  # loop: only the run's own loop shows that it ends with the push held; timeout stops one that turns for ever.
  out=$(CONVEYOR_MAIN=$R CONVEYOR_CARDS=$T/$CASE/cards timeout 60 bash "$SRC/conveyor.sh" run 2>&1) || rc=$?
  [ "$rc" = 1 ] && [[ $out == *"is not pushed: the rule Push after a combined test run holds the push until its run is due (pushbatchwhen)"* ]] \
    || fail "the run with 2 landings and pushbatchwhen 3 did not end, exit 1, saying the rule holds the push (exit $rc): $out"
  [ "$(git -C "$T/$CASE/origin" rev-parse main)" = "$base" ] || fail "the run pushed the held landings: $out"
}

# Release 1.12.0: the loop writes its word on the push (pushheld(), lib/push.sh) at each turn, most often with no push
# held. Bug caught: that turn started a jq to write a line with no text to quote, so a batch run went over its jq limit
# (stdbcalls.test.sh). A turn that held a push comes first, so the next turn must set turns back to 0 and sha and held
# to null; jq is a shell function after it, so the calls of the turn with no hold are logged.
t_pushheldnone() {
  setup '[]'
  fx_in 'owed="c1 abc"; pushheld "held \"why\""; jq -c . "$PUSHWAIT"; jq() { echo jq >> "$T/$CASE/calls"; command jq "$@"; }; pushheld ""'
  [ "$RC" = 0 ] && jq -e '.sha == "abc" and .held == "held \"why\"" and .turns == 1' "$T/$CASE/run.out" > /dev/null \
    || fail "pushheld 'held \"why\"' with owed 'c1 abc' did not write its hold (exit $RC): $(cat "$T/$CASE/run.out")"
  [ ! -e "$T/$CASE/calls" ] || fail "pushheld '' started $(wc -l < "$T/$CASE/calls") jq: the line with no hold is written by the shell"
  jq -e 'keys == ["at", "held", "pid", "sha", "turns"] and (.pid | type) == "number" and (.at | fromdate) > 0 and .sha == null and .held == null and .turns == 0' "$ST/pushwait" > /dev/null \
    || fail "pushheld '' after a held turn did not write {pid, at, sha: null, held: null, turns: 0}: $(cat "$ST/pushwait")"
}

# Bug it catches: the push read main outside the card records' lock while land() (lib/claim.sh) had moved main but not
# yet written that card's landed line, so the run before the push did not see that landing, ran none of its linked test
# files, and pushed it. Card c3 lands through locked land(), as cardland() lands it, and stops right after main moves
# (turnfree(), its next call) until the push asks for that lock (flock 9, locked()); c3 adds lib/fee.test.js, which
# fails. The push must run that file on c3's commit and hold the push, origin left at base.
t_pushtestslanding() {
  local l1 l2 base l3
  pushfix true
  printf '%s\n' 'echo "$(git rev-parse HEAD) $1" >> "$STUB/ran"; [ "$1" != lib/fee.test.js ]' > "$STUB/one" # only c3's file fails
  CARDS=$T/$CASE/cards; mkdir -p "$CARDS"
  git -C "$R" worktree add -q --detach "$CARDS/c3" refs/heads/main && echo fee > "$CARDS/c3/lib/fee.js" \
    && echo 'exit 1' > "$CARDS/c3/lib/fee.test.js" && git -C "$CARDS/c3" add -A || fail "the change of card c3 could not be staged"
  # Waits on real processes: a direct check cannot stop the real landing between its ref move and its landed line, nor
  # see the push wait on the lock. The landing's wait has a ceiling of 20 s, reached only when the push reads main with
  # no wait on the lock (the bug); then the landing goes on and the push's checks below fail.
  ( fx_in 'eval "orig_$(declare -f turnfree)"; turnfree() { touch "$T/$CASE/moved"; WAIT_CEILING=20 wait_until "[ -e \"$T/$CASE/waits\" ]"; orig_turnfree "$@"; }
    locked land c3 3 "$CARDS/c3" "title 3 (#3)"; echo "land: $?"' ) &
  wait_until '[ -e "$T/$CASE/moved" ]' || { wait; fail "locked land c3 3 did not move main: $(cat "$T/$CASE/run.out")"; }
  l3=$(git -C "$R" rev-parse main)
  pushnow 'flock() { [ "$1" != 9 ] || touch "$T/$CASE/waits"; command flock "$@"; }; push c2 2'
  wait
  [ "$(tail -n 1 "$T/$CASE/run.out")" = "land: 0" ] || fail "locked land c3 3 failed: $(cat "$T/$CASE/run.out")"
  grep -qxF "$l3 lib/fee.test.js" "$STUB/ran" \
    || fail "push c2 2, started while locked land c3 3 had moved main to ${l3:0:12} but not written its landed line, did not run c3's lib/fee.test.js on it: $(cat "$STUB/ran" "$T/$CASE/push.out" 2>&1)"
  [ "$(git -C "$T/$CASE/origin" rev-parse main)" = "$base" ] \
    || fail "push c2 2 pushed c3's ${l3:0:12} to origin though its linked lib/fee.test.js fails: $(cat "$T/$CASE/push.out")"
}
