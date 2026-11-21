#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 120
# Engine cases (#1079): a push whose pre-push hook failed naming test files (lib/pushrun.sh hookalone()): each file runs
# alone, once; when each passes, the same commit is pushed with no hook, the files go on the flaky-test record and one
# held issue holds them (lib/flaky.sh flakypush()); a file that fails alone too, or a hook that failed a check that is
# no test file, holds the push as before. A file flaky twice within the flaky days reopens the issue of its earlier fix,
# and the Tests page names it (testspart(), lib/testfiles.sh).
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"
# The engine folder, as lib.sh sets it: named here too, so the release closure (tools/closure.sh) follows this file's paths.
SRC=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)

# The fixture of every case: one landing since origin, c1 (issue 1), adds lib/a.test.sh, which passes alone unless
# $STUB/a-fails is there (it defines the case adds and names the runner run.test.sh: a runner's name for its case,
# `lib/run.test.sh: adds`, is the file's too, caseowners in lib/testfiles.sh); the pack's test.fileCommand runs a file
# through $STUB/one, which notes it in $STUB/ran, wrapped as the Board's Record CPU time wraps it (cputwrap(),
# lib/testfiles.sh: it calls $CONVEYOR_TEST_TIME). The push check is off (push.check false), so the run before the
# push runs nothing. Main's pre-push hook notes each run in $STUB/hookruns, prints $STUB/hook-says (by default a
# runner's failure lines naming lib/a.test.sh, then Python's unittest summary, FAILED (failures=1), which names no
# check) and fails. Sets base and l1.
pfix() {
  setup '[]'
  base=$(git -C "$R" rev-parse HEAD)
  printf '%s\n' 'echo "$1" >> "$STUB/ran"; bash "$1"' > "$STUB/one"
  tune --arg c "$(. "$SRC/lib/testfiles.sh" && cputwrap '"$CONVEYOR_TEST_FILE"' 'bash "$STUB/one"')" '.push.check = false | .test.fileCommand = $c'
  mkdir -p "$R/lib" && printf '%s\n' '# its cases run through run.test.sh too' 't_adds() { :; }' '[ ! -e "$STUB/a-fails" ]' > "$R/lib/a.test.sh" \
    && git -C "$R" add -A && git -C "$R" commit -qm c1 && l1=$(git -C "$R" rev-parse HEAD) || fail "the landing could not be made"
  jq -cn --arg s "$l1" '{card: "c1", issue: 1, step: "landed", time: "2026-11-18T10:00:00Z", tokens: {claude: 0, codex: 0}, result: "ok", sha: $s, reason: "", product: false}' >> "$ST/cards.jsonl"
  printf '%s\n' '-- FAIL lib/a.test.sh' 'not ok 1 - adds two' 'actual: false expected: true' 'FAILED (failures=1)' > "$STUB/hook-says"
  printf '%s\n' '#!/usr/bin/env bash' 'echo run >> "$STUB/hookruns"; cat "$STUB/hook-says" >&2; exit 1' > "$R/.git/hooks/pre-push" \
    && chmod +x "$R/.git/hooks/pre-push" || fail "the pre-push hook could not be written"
}
# The loop's push of c1 (push(), as `conveyor.sh run` loads the engine), its output in push.out.
pnow() {
  # shellcheck disable=SC2034 # HERE is read by the lines of conveyor.sh and commands/run.sh run by the eval
  ( HERE=$SRC; export CONVEYOR_MAIN=$R CONVEYOR_CARDS=$T/$CASE/cards
    eval "$(sed -n '/^\. "\$HERE\/lib\/portable.sh"/,/^\. "\$HERE\/lib\/records.sh"/p' "$SRC/conveyor.sh")"
    eval "$(grep '^\. "\$HERE/lib/' "$SRC/commands/run.sh")"
    names || exit 1; push c1 1 ) > "$T/$CASE/push.out" 2>&1
}
origin() { git -C "$T/$CASE/origin" rev-parse main; }

# Done when 1. Bug it catches: a hook that failed on a busy machine naming a test file that passes alone held the
# push until someone ran the tests again by hand; or the push went on with nothing recorded, or filed one issue a file.
t_pushflaky() {
  local base l1
  pfix; pnow
  [ "$(origin)" = "$l1" ] || fail "the push was held: $(cat "$T/$CASE/push.out")"
  [ "$(cat "$STUB/ran" 2>&1)" = lib/a.test.sh ] && [ "$(wc -l < "$STUB/hookruns")" = 1 ] \
    || fail "the file did not run alone once, or the hook ran again: ran $(cat "$STUB/ran" 2>&1), hook $(cat "$STUB/hookruns")"
  [ "$(jq -c '.entries | map([.case, .source])' "$ST/flaky.json")" = "[[\"lib/a.test.sh\",\"push ${l1:0:12}\"]]" ] \
    || fail "the file is not on the flaky-test record: $(cat "$ST/flaky.json" 2>&1)"
  [ "$(wc -l < "$STUB/filed")" = 1 ] && jq -e '.title | contains("lib/a.test.sh") and contains("passed alone")' "$STUB/filed" >/dev/null \
    && jq -e '.body | contains("-- FAIL lib/a.test.sh")' "$STUB/filed" >/dev/null || fail "not one issue naming the file: $(cat "$STUB/filed" 2>&1)"
  jq -e '.held | index(100101)' "$ST/control.json" >/dev/null || fail "the flaky issue is not held: $(cat "$ST/control.json")"
  [ "$(st 'select(.step == "pushed") | .flaky' | jq -c .)" = '{"files":["lib/a.test.sh"],"issues":[100101]}' ] && [ -z "$(st 'select(.step == "push")')" ] \
    || fail "the pushed line does not name the flaky file and its issue, or a push failed: $(st 'select(.step | startswith("push"))')"
  loop check || fail "the record check refuses the pushed line"
}

# Done when 2. Bug it catches: a file that fails alone too was taken for flaky, and a red commit was pushed.
t_pushflakyred() {
  local base l1
  pfix; touch "$STUB/a-fails"; pnow
  [ "$(origin)" = "$base" ] || fail "a commit whose test file fails alone too was pushed: $(cat "$T/$CASE/push.out")"
  [ "$(cat "$STUB/ran" 2>&1)" = lib/a.test.sh ] || fail "the file did not run alone: $(cat "$STUB/ran" 2>&1)"
  st 'select(.step == "push") | "\(.kind) \(.reason)"' | grep -qF 'check ' && st 'select(.step == "push") | .reason' | grep -qF 'lib/a.test.sh, which fails alone too' \
    || fail "the push line does not hold the push naming the file: $(st 'select(.step == "push")')"
  [ ! -e "$STUB/filed" ] && [ ! -s "$ST/flaky.json" ] || fail "a red file was recorded flaky: $(cat "$STUB/filed" "$ST/flaky.json" 2>&1)"
}

# Bug it catches: a hook that failed a check that is no test file (FAILED fast-checks) as well as a test file that
# passes alone was pushed with no hook, past the check that failed.
t_pushflakyother() {
  local base l1
  pfix; echo 'push-checks: FAILED fast-checks' >> "$STUB/hook-says"; pnow
  [ "$(origin)" = "$base" ] && [ ! -e "$STUB/ran" ] || fail "a hook that failed more than test files was pushed past: $(cat "$T/$CASE/push.out")"
  [ "$(st 'select(.step == "push") | [.kind, .check] | join(" ")')" = 'check fast-checks' ] || fail "the push line: $(st 'select(.step == "push")')"
}

# #1084. Bug it catches: a pre-push hook whose test failed with no message of its own (a stack, actual: false, expected:
# true) held the push with a reason that named no line, so it could not be read without a run again; and the hook's
# run got no load factor to scale a time budget by. The hook prints a stack frame of its worktree's lib/a.test.sh,
# line 3, and the file fails alone too: the push line's reason ends with that line and its text, read from the commit
# (the push worktree is gone by then), and the hook was given CONVEYOR_LOAD_FACTOR.
t_pushflakyat() {
  local base l1
  pfix; touch "$STUB/a-fails"
  printf '%s\n' '#!/usr/bin/env bash' 'printf %s "${CONVEYOR_LOAD_FACTOR-unset}" > "$STUB/hookfactor"; cat "$STUB/hook-says" >&2' \
    'echo "    at TestContext.<anonymous> (file://$PWD/lib/a.test.sh:3:7)" >&2; exit 1' > "$R/.git/hooks/pre-push" || fail "the hook could not be written"
  pnow
  [ "$(origin)" = "$base" ] || fail "a commit whose test file fails alone too was pushed: $(cat "$T/$CASE/push.out")"
  st 'select(.step == "push") | .reason' | grep -qxF 'conveyor: a test of the hook failed at lib/a.test.sh:3: [ ! -e "$STUB/a-fails" ]' \
    || fail "the push line's reason does not end with where the hook's test failed: $(st 'select(.step == "push") | .reason')"
  [ "$(cat "$STUB/hookfactor" 2>&1)" = 1 ] || fail "the pre-push hook was not given the load factor (lib.sh gives the cases 1): $(cat "$STUB/hookfactor" 2>&1)"
}

# Done when 3, and the owner's 2026-11-20 ruling: a file recorded flaky twice within 7 days reopens the issue of its
# earlier fix (#77, closed since), with "flaky again since its fix #77", and files none; the Tests page names it so.
# The earlier entry and filing name its case as its runner names it (a card's, `lib/run.test.sh: adds`, as
# flakyfile() files one), and the new one the file. Bug it catches: the second time was filed as a new issue, as if
# its fix had held; or the earlier fix was missed when the record named the runner, not the case file.
t_pushflakyagain() {
  local base l1 got
  pfix; echo CLOSED > "$STUB/state.77"
  jq -n --arg e "$(jq -rn 'now - 2 * 86400 | todate')" \
    '{entries: [{case: "lib/run.test.sh: adds", source: "c9", time: $e, card: "c9", issue: 9}], filed: [{case: "lib/run.test.sh: adds", issue: 77}]}' > "$ST/flaky.json"
  pnow
  [ "$(origin)" = "$l1" ] || fail "the push was held: $(cat "$T/$CASE/push.out")"
  [ "$(cat "$STUB/reopened" 2>&1)" = 77 ] && grep -qF 'Flaky again since its fix #77' "$STUB/reopen-comments" && [ ! -e "$STUB/filed" ] \
    || fail "#77 was not reopened as flaky again, or a new issue was filed: $(cat "$STUB/reopened" "$STUB/reopen-comments" "$STUB/filed" "$T/$CASE/push.out" 2>&1)"
  jq -e '.held | index(77)' "$ST/control.json" >/dev/null && [ "$(st 'select(.step == "pushed") | .flaky.issues' | jq -c .)" = '[77]' ] \
    || fail "#77 is not held, or the pushed line does not name it: $(cat "$ST/control.json") $(st 'select(.step == "pushed")')"
  # shellcheck source=/dev/null # the snapshot's libraries, by its SNAPLIBS list (commands/snapshot.sh)
  got=$( export CONVEYOR_MAIN=$R CONVEYOR_CARDS=$T/$CASE/cards; . "$SRC/conveyor.sh" state-dir > /dev/null \
    && eval "$(grep '^SNAPLIBS=' "$SRC/commands/snapshot.sh")" && for l in $SNAPLIBS; do . "$HERE/lib/$l.sh" || exit 1; done \
    && testspart 2026-11-09 | jq -c '.files[] | select(.file == "lib/a.test.sh") | .flakyAgain' ) && [ "$got" = 77 ] \
    || fail "the Tests page does not name the file flaky again since #77: $got"
}
