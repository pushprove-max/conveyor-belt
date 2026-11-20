#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# test-changed.sh and meta-runners (issue 584): a test file that starts other test files costs a card a whole suite
# (#563 paid about an hour for a few-second change). A card's test step marks the file it starts; one that starts
# another test file of the checkout whole needs the pack's card mode (test.files.<file>.cardMode) or whole-only mark
# (wholeOnly), else it fails the step naming the file and the two marks; --check lists the meta-runners with their marks.
set -u
HERE=$(cd "$(dirname "$0")" && pwd -P)
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
AT=@
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t${AT}example.com GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t${AT}example.com
unset CONVEYOR_TEST_LOG CONVEYOR_SHELL_TEST_CASE CONVEYOR_TEST_FILE CONVEYOR_TEST_FILES BASH_ENV CONVEYOR_TEST_RERUN
ok() { echo "ok - $1"; }
no() { echo "not ok - $1"; }

# A scratch repo: the real script, an empty engine map, and two test files: lib/inner.test.sh, and lib/meta.test.sh,
# which in its card mode (CONVEYOR_META_STUB set) writes a stub line, else starts lib/inner.test.sh. Each part changes
# lib/meta.test.sh (so a run selects it alone) in its own copy, with its own pack.
R=$T/r; mkdir -p "$R/.conveyor" "$R/lib"
cp "$HERE/test-changed.sh" "$HERE/lint-shell.sh" "$HERE/test-lint.sh" "$HERE/no-browser-tests.sh" "$R/.conveyor/"
echo '{"outside": "conveyor/README.md"}' > "$R/.conveyor/engine-areas.json"
echo 'echo inner >> "$(dirname "$0")/../ran"' > "$R/lib/inner.test.sh"
echo 'echo "meta:${CONVEYOR_META_STUB:-whole}" >> "$(dirname "$0")/../ran"; [ -n "${CONVEYOR_META_STUB:-}" ] || bash "$(dirname "$0")/inner.test.sh"' > "$R/lib/meta.test.sh"
printf 'ran\nlog/\n' > "$R/.gitignore"
git -C "$R" init -q && git -C "$R" add -A && git -C "$R" commit -qm init
# run [pack test.files]: the card's test step on the copy (its log in $R/log), its output in $T/out and exit in $T/rc;
# prints what ran.
run() {
  [ -z "${1:-}" ] || jq -n --argjson f "$1" '{test: {files: $f}}' > "$R/.conveyor/project.json"
  echo ': changed' >> "$R/lib/meta.test.sh"; rm -rf "$R/ran" "$R/log"; mkdir "$R/log"
  (cd "$R" && CONVEYOR_TEST_LOG=$R/log bash .conveyor/test-changed.sh) > "$T/out" 2>&1; echo $? > "$T/rc"
  paste -sd' ' "$R/ran" 2>/dev/null
}
check() { (cd "$R" && bash .conveyor/test-changed.sh --check) 2>&1 | grep '^meta-runner '; }
PARTS=()
part() { PARTS+=("$1"); (B=$T; T=$T/$1; mkdir "$T" && cp -a "$B/r" "$T/r" || exit 1; R=$T/r; "p_$1") > "$T/$1.res" 2>&1 & }

# D1. Bug: a meta-runner with no mark ran its whole suite on a card. It fails the step, naming the file and both marks,
# its log names the file it started, and --check lists it with no mark.
p_nomark() {
  got=$(run)
  [ "$(cat "$T/rc")" = 1 ] && grep -q 'lib/meta.test.sh starts other test files (lib/inner.test.sh)' "$T/out" \
    && grep -qF 'test.files."lib/meta.test.sh".cardMode' "$T/out" && grep -qF 'test.files."lib/meta.test.sh".wholeOnly' "$T/out" \
    && grep -qxF "$(printf 'TESTRUN nested\tlib/meta.test.sh\tlib/inner.test.sh')" "$R/log/test-changed.log" \
    && ok "a meta-runner with no mark fails the card's test step, naming the file and the two marks" \
    || no "no mark: ran '$got', exit $(cat "$T/rc"): $(cat "$T/out")"
  got=$(check)
  [ "$got" = "meta-runner lib/meta.test.sh: no mark: a card's test step fails it; seen starting 1 test file(s)" ] \
    && ok "--check lists a meta-runner the runs saw, with no mark" || no "--check, no mark: '$got'"
}
# D2. With cardMode a card runs it in that mode (the stub, no inner file) and passes; run whole, as the nightly whole
# test runs it (not through the card's test step), it starts its inner file. --check lists the mark.
p_cardmode() {
  got=$(run '{"lib/meta.test.sh": {"cardMode": "CONVEYOR_META_STUB=1"}}')
  [ "$got" = meta:1 ] && [ "$(cat "$T/rc")" = 0 ] && ok "a meta-runner with cardMode runs in that mode on a card" \
    || no "cardMode: ran '$got', exit $(cat "$T/rc"): $(cat "$T/out")"
  rm -f "$R/ran"; (cd "$R" && bash lib/meta.test.sh); got=$(paste -sd' ' "$R/ran")
  [ "$got" = "meta:whole inner" ] && ok "the same file run whole starts its inner file" || no "cardMode, whole run: ran '$got'"
  got=$(check)
  [ "$got" = "meta-runner lib/meta.test.sh: cardMode CONVEYOR_META_STUB=1" ] && ok "--check lists a meta-runner's card mode" \
    || no "--check, cardMode: '$got'"
}
# Bug: a cardMode that is no NAME=VALUE would be run by env as a command. It is no mark: the meta-runner fails.
p_badmode() {
  got=$(run '{"lib/meta.test.sh": {"cardMode": "touch pwned"}}')
  [ "$got" = "meta:whole inner" ] && [ "$(cat "$T/rc")" = 1 ] && [ ! -e "$R/pwned" ] \
    && ok "a cardMode that is no NAME=VALUE is not run, and is no mark" || no "bad cardMode: ran '$got', exit $(cat "$T/rc"): $(cat "$T/out")"
}
# D2. With wholeOnly a card runs nothing of it and says so, in its output and its log; --check lists the mark.
p_wholeonly() {
  got=$(run '{"lib/meta.test.sh": {"wholeOnly": true}}')
  [ -z "$got" ] && [ "$(cat "$T/rc")" = 0 ] && grep -q '^== lib/meta.test.sh: not run: whole-only' "$T/out" \
    && grep -qxF "$(printf 'TESTRUN whole-only\tlib/meta.test.sh')" "$R/log/test-changed.log" \
    && ! grep -q '^== lib/meta.test.sh$' "$R/log/test-changed.log" \
    && ok "a whole-only meta-runner runs nothing on a card and says so" || no "wholeOnly: ran '$got', exit $(cat "$T/rc"): $(cat "$T/out")"
  got=$(check)
  [ "$got" = "meta-runner lib/meta.test.sh: wholeOnly" ] && ok "--check lists a whole-only meta-runner" || no "--check, wholeOnly: '$got'"
}
# Bug: a test that starts a scratch test file of its own (an engine case's fixture), or one case of a checkout's test
# file, is no meta-runner: neither runs a suite, and failing them would fail cards that run no suite.
p_notmeta() {
  printf '%s\n' 'echo meta >> "$(dirname "$0")/../ran"; d=$(mktemp -d); echo "echo scratch >> $(dirname "$0")/../ran" > "$d/a.test.sh"' \
    'bash "$d/a.test.sh"; rm -rf "$d"; CONVEYOR_SHELL_TEST_CASE=one bash "$(dirname "$0")/inner.test.sh"' > "$R/lib/meta.test.sh"
  git -C "$R" commit -qam notmeta; got=$(run)
  [ "$got" = "meta scratch inner" ] && [ "$(cat "$T/rc")" = 0 ] && ! grep -q 'TESTRUN nested' "$R/log/test-changed.log" \
    && ok "a scratch test file, or one case of a test file, started by a test is no meta-runner" \
    || no "not a meta-runner: ran '$got', exit $(cat "$T/rc"): $(cat "$T/out")"
}
# Bug (issue 595): a change to a root file ran its root test file as ./<file>, and the hook took the file's own start
# for another test file's: README.test.sh, which starts no test file, failed every card as a meta-runner.
p_root() {
  echo 'echo root >> "$(dirname "$0")/ran"' > "$R/top.test.sh"; echo one > "$R/top.md"
  git -C "$R" add -A && git -C "$R" commit -qm root
  echo two >> "$R/top.md"; rm -rf "$R/ran" "$R/log"; mkdir "$R/log"
  (cd "$R" && CONVEYOR_TEST_LOG=$R/log bash .conveyor/test-changed.sh) > "$T/out" 2>&1; echo $? > "$T/rc"
  got=$(paste -sd' ' "$R/ran" 2>/dev/null)
  [ "$got" = root ] && [ "$(cat "$T/rc")" = 0 ] && ! grep -q 'TESTRUN nested' "$R/log/test-changed.log" \
    && ok "a root test file, named after a changed root file, is no meta-runner" \
    || no "root test file: ran '$got', exit $(cat "$T/rc"): $(cat "$T/out")"
}

# The engine runner sources its case files (no bash start the hook sees). erun [pack test.files] <file>: the card's test
# step on a copy with a runner stub (conveyor/conveyor.test.sh, recording the cases it was asked for, ALL for every
# case file) and two areas' case files, after a change to <file>; prints what ran.
erun() {
  mkdir -p "$R/conveyor/tests"
  printf '%s\n' '{"outside": "conveyor/README.md"}' '{"area": "a", "file": "conveyor/x.sh"}' '{"area": "a", "test": "a.test.sh"}' \
    '{"area": "b", "file": "conveyor/y.sh"}' '{"area": "b", "test": "b.test.sh"}' > "$R/.conveyor/engine-areas.json"
  printf 't_aone() {\n  :\n}\n' > "$R/conveyor/tests/a.test.sh"; printf 't_bone() {\n  :\n}\n' > "$R/conveyor/tests/b.test.sh"
  # As the runner does, it then unsets the selection and starts each case's keeper as itself (lib.sh run_case).
  printf '%s\n' 'echo "runner:${CONVEYOR_SHELL_TEST_CASE:-ALL}" >> "$(dirname "$0")/../ran"' \
    'unset CONVEYOR_SHELL_TEST_CASE; bash -c : "$0"' > "$R/conveyor/conveyor.test.sh"
  echo one > "$R/conveyor/x.sh"; echo one > "$R/conveyor/y.sh"
  jq -n --argjson f "$1" '{test: {files: $f}}' > "$R/.conveyor/project.json"
  git -C "$R" add -A && git -C "$R" commit -qm engine
  echo ': changed' >> "$R/$2"; rm -rf "$R/ran" "$R/log"; mkdir "$R/log"
  (cd "$R" && CONVEYOR_TEST_LOG=$R/log bash .conveyor/test-changed.sh) > "$T/out" 2>&1; echo $? > "$T/rc"
  paste -sd' ' "$R/ran" 2>/dev/null
}
# Bug (review of 584): a change to the runner ran every engine case file on a card, with neither mark. That run is not
# made, the step fails naming the runner and both marks, the log names the case files, and --check lists it.
p_enginenomark() {
  got=$(erun '{}' conveyor/conveyor.test.sh)
  [ -z "$got" ] && [ "$(cat "$T/rc")" = 1 ] && grep -q 'conveyor/conveyor.test.sh starts other test files (conveyor/tests/a.test.sh conveyor/tests/b.test.sh)' "$T/out" \
    && grep -qF 'test.files."conveyor/conveyor.test.sh".wholeOnly' "$T/out" \
    && grep -qxF "$(printf 'TESTRUN nested\tconveyor/conveyor.test.sh\tconveyor/tests/b.test.sh')" "$R/log/test-changed.log" \
    && ok "the engine runner's run of every case file, with neither mark, is not made and fails naming it" \
    || no "engine, no mark: ran '$got', exit $(cat "$T/rc"): $(cat "$T/out")"
  got=$(check)
  [ "$got" = "meta-runner conveyor/conveyor.test.sh: no mark: a card's test step fails it; seen starting 2 test file(s)" ] \
    && ok "--check lists the engine runner the runs saw, with no mark" || no "--check, engine no mark: '$got'"
}
# With wholeOnly the runner's whole run is left to the nightly whole test, and says so; its run of one area's cases is
# no meta-runner's, and still runs (were it taken off too, a card would test none of the engine it changed). Bug
# (issue 214 review): run under its case file's mark, the runner's start of its case keepers was taken for a nested
# start, and every case file failed as a meta-runner though its cases passed.
p_enginewhole() {
  got=$(erun '{"conveyor/conveyor.test.sh": {"wholeOnly": true}}' conveyor/conveyor.test.sh)
  [ -z "$got" ] && [ "$(cat "$T/rc")" = 0 ] && grep -qxF "$(printf 'TESTRUN whole-only\tconveyor/conveyor.test.sh')" "$R/log/test-changed.log" \
    && ok "a whole-only engine runner's run of every case file is not made on a card, and says so" \
    || no "engine, wholeOnly, runner changed: ran '$got', exit $(cat "$T/rc"): $(cat "$T/out")"
}
p_enginecases() {
  got=$(erun '{"conveyor/conveyor.test.sh": {"wholeOnly": true}}' conveyor/x.sh)
  [ "$got" = "runner:aone" ] && [ "$(cat "$T/rc")" = 0 ] && ! grep -q 'TESTRUN nested\|TESTRUN whole-only' "$R/log/test-changed.log" \
    && ok "a whole-only engine runner still runs a card's chosen cases" || no "engine, wholeOnly, x.sh changed: ran '$got', exit $(cat "$T/rc"): $(cat "$T/out")"
}

# Bug (issue 642): the pack marked the case file conveyor/tests/wait.test.sh whole-only, a mark that controls nothing:
# a card runs a case file's chosen cases through the engine runner, as a test file of its own (issue 214), never
# whole and whatever its marks, so the mark only made --check list a meta-runner that is not one. A case file's old
# CPU budget (test.files.<file>.budget, ignored now) is no such mark. A pack setting, not code: it is read.
p_packmarks() {
  got=$(jq -r '.test.files // {} | to_entries[] | select((.key | startswith("conveyor/tests/")) and (.value | has("wholeOnly") or has("cardMode"))) | .key' "$HERE/project.json")
  [ -z "$got" ] && ok "the pack marks no engine case file, which the engine runner runs" || no "pack marks engine case files: $got"
}

for p in nomark cardmode badmode wholeonly notmeta root enginenomark enginewhole enginecases packmarks; do part "$p"; done
wait
for p in "${PARTS[@]}"; do cat "$T/$p.res"; grep -q '^ok' "$T/$p.res" || echo "not ok - part $p checked nothing"; done | awk '{ sub(/^ok -/, "ok " NR " -"); sub(/^not ok -/, "not ok " NR " -"); print } /^not ok/ { f = 1 } END { exit f }'
