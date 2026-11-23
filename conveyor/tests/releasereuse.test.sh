#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 120
# Engine cases: release-prep (and release, issue 1069) reruns only the files that failed or changed since the whole-suite run on the nearest
# ancestor and reuses its passes (issue 43), Push landed counts its pass on the same commit, and suitebase() takes
# that ancestor's run (issue 44). Their fixture is rrsetup, below, on releaseboard.test.sh's runsetup (release.test.sh's
# cutsetup); fullreuse.test.sh uses it too. ftended is fulltest.test.sh's.
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"

# rrsetup: runsetup, with the pack's test.full the committed .conveyor/test-full.sh, which runs the tracked t/*.test.sh
# (those CONVEYOR_SUITE_FILES lists, when set), notes each in $STUB/ran and prints its `-- ok|FAIL` line; t/f1 fails,
# t/f2 and t/f3 pass, and the changed-tests command (test.command, $STUB/test-cmd) lists t/f3.test.sh for a change to
# src/s3.sh. A whole release-prep (with `full`: a whole Run full test suite) runs on that commit (A), then t/f1 is made
# to pass, not yet committed. With `pick`, test.command runs the committed .conveyor/pick.sh, which picks as
# $STUB/test-cmd does, and test.changed names it, as this repository's pack names .conveyor/test-changed.sh in both.
rrsetup() { # [full | pick]
  runsetup true
  tune '.test.full = "bash .conveyor/test-full.sh"'
  [ "${1:-}" != pick ] || tune '.test.command = "bash .conveyor/pick.sh" | .test.changed = ".conveyor/pick.sh"'
  mkdir -p "$R/t" "$R/src" && printf '%s\n' 'fs=$(git ls-files "t/*.test.sh"); [ -z "${CONVEYOR_SUITE_FILES:-}" ] || fs=$(grep -xFf "$CONVEYOR_SUITE_FILES" <<<"$fs")' \
    'echo "TESTRUN files=$(grep -c . <<<"$fs")"; rc=0' \
    'for f in $fs; do echo "$f" >> "$STUB/ran"; if bash "$f"; then echo "-- ok $f"; else echo "-- FAIL $f"; rc=1; fi; done; exit $rc' > "$R/.conveyor/test-full.sh" \
    && echo 'exit 1' > "$R/t/f1.test.sh" && echo 'exit 0' > "$R/t/f2.test.sh" && echo 'exit 0' > "$R/t/f3.test.sh" && echo one > "$R/src/s3.sh" \
    && echo '[ -z "${CONVEYOR_TEST_LIST:-}" ] || git diff --name-only HEAD | sed -n "s|^src/s3[.]sh\$|t/f3.test.sh|p" > "$CONVEYOR_TEST_LIST"' > "$STUB/test-cmd" \
    && { [ "${1:-}" != pick ] || cp "$STUB/test-cmd" "$R/.conveyor/pick.sh"; } \
    && git -C "$R" add -f .conveyor/test-full.sh t src && { [ "${1:-}" != pick ] || git -C "$R" add -f .conveyor/pick.sh; } \
    && git -C "$R" commit -qm 'the suite' && git -C "$R" push -q origin main || fail "the fixture could not be made"
  A=$(git -C "$R" rev-parse HEAD)
  if [ "${1:-}" = full ]; then
    loop full-test > "$T/$CASE.a" 2>&1 || fail "full-test did not start: $(cat "$T/$CASE.a")"
    ftended 1; [ "$(ftl .state)" = '"failed"' ] || fail "full-test did not fail with t/f1 failing: $(cat "$ST/fulltest.jsonl")"
  else loop release-prep 1.1.0 > "$T/$CASE.a" 2>&1 && fail "release-prep passed with t/f1 failing: $(cat "$T/$CASE.a")"; fi
  # A red full test also runs t/f1 alone (fulljudge()), which this runner runs whole: each file ran, once or more.
  [ "$(sort -u "$STUB/ran" 2>/dev/null | paste -sd' ' -)" = "t/f1.test.sh t/f2.test.sh t/f3.test.sh" ] || fail "the first run did not run every file: $(cat "$STUB/ran" "$T/$CASE.a" 2>&1)"
  rm -f "$STUB/ran"; echo 'exit 0' > "$R/t/f1.test.sh"
}
# rrprep: B, the commit of what the case changed, pushed; release-prep runs on it and passes. Sets B and got (the
# files the suite ran, sorted, on one line).
rrprep() {
  git -C "$R" commit -qam 'fix: B' && git -C "$R" push -q origin main || fail "the fixture could not be made"
  B=$(git -C "$R" rev-parse HEAD)
  loop release-prep 1.1.0 > "$T/$CASE.b" 2>&1 || fail "release-prep failed on B: $(cat "$T/$CASE.b")"
  got=$(sort "$STUB/ran" 2>/dev/null | paste -sd' ' -)
}

# Bug (#43): one failed file made release-prep rerun the whole suite (about 250 files, 43 min) on the fix, though every
# other file passed on the commit before; and reusing the passes of files whose code changed. Here B fixes t/f1 and
# changes src/s3.sh, which the changed-tests command maps to t/f3: only t/f1 and t/f3 run (t/f2's pass is kept), a pass
# is posted on B, the record names the run reused and the files rerun, and `release` takes the pass and releases B with
# no suite run.
# Bug (#44, D2): Push landed ran the whole suite on a commit release-prep had just passed. Before the release, B is made
# an unpushed landing (origin put back on A, a card's landed line naming B): Push landed runs no test and pushes B.
# Bug (#1284): release-prep's record (release/run.json, read by release-run --machine local, releasego()) names the
# machine of the pass it reused; Push landed's line in fulltest.jsonl names it too.
t_relreusefail() {
  local A B RUN got
  rrsetup
  echo two >> "$R/src/s3.sh"
  rrprep
  [ "$got" = "t/f1.test.sh t/f3.test.sh" ] || fail "release-prep on B ran '$got', not t/f1 and t/f3 alone: $(cat "$T/$CASE.b")"
  grep -q "statuses/$B -f state=success -f context=conveyor/release-suite " "$STUB/gh-calls" || fail "no passing status was posted on B: $(cat "$STUB/gh-calls")"
  jq -e --arg a "$A" --arg b "$B" '.state == "passed" and .sha == $b and (.reused | del(.time)) == {sha: $a, ran: ["t/f1.test.sh", "t/f3.test.sh"], kept: 1, machine: "local"}' "$RUN" > /dev/null \
    || fail "the record does not name the run reused and the files rerun: $(cat "$RUN")"
  git -C "$T/$CASE/origin" update-ref refs/heads/main "$A" && git -C "$R" update-ref "refs/remotes/origin/main" "$A" \
    && rm -f "$ST/pushed" && landed 7 | jq -c --arg b "$B" '.sha = $b' >> "$ST/cards.jsonl" || fail "the fixture could not be made"
  rm -f "$STUB/ran"
  loop full-test push > "$T/$CASE.p" 2>&1 || fail "push landed did not start: $(cat "$T/$CASE.p")"; ftended 1
  [ ! -e "$STUB/ran" ] || fail "Push landed ran tests on a commit release-prep passed: $(cat "$STUB/ran")"
  [ "$(git -C "$T/$CASE/origin" rev-parse refs/heads/main)" = "$B" ] \
    && [ "$(ftl '[.state, .pushed.ok, .reused.sha, .reused.ran, .reused.machine]')" = "[\"passed\",true,\"$B\",[],\"local\"]" ] \
    || fail "Push landed did not push B on release-prep's pass: $(cat "$ST/fulltest.jsonl" "$ST/fulltest.jsonl.log")"
  loop release 1.1.0 > "$T/$CASE.r" 2>&1 || fail "release did not take the pass on B: $(cat "$T/$CASE.r")"
  [ ! -e "$STUB/ran" ] && [ -n "$(git -C "$T/$CASE/origin" tag -l v1.1.0)" ] || fail "release ran the suite again or released nothing: $(cat "$T/$CASE.r")"
}
# Bug (#43): a change to the suite's own command (.conveyor/test-full.sh) can change what every file's ok means, so
# the passes of the run before it are no proof: release-prep runs every file.
t_relreusecmd() {
  local A B RUN got
  rrsetup
  echo '# changed' >> "$R/.conveyor/test-full.sh"
  rrprep
  [ "$got" = "t/f1.test.sh t/f2.test.sh t/f3.test.sh" ] || fail "a change to .conveyor/test-full.sh did not run every file: '$got'"
  jq -e '.reused == null' "$RUN" > /dev/null || fail "a whole suite's record says it reused a run: $(cat "$RUN")"
}
# Release 1.6.0: a one-line change to the changed-tests command (test.command, .conveyor/test-changed.sh here) made
# release-prep run all 400 files again, though that command picks files and runs no suite. Its file reruns as a
# changed file does: only t/f1 (failed on A) runs, and the record names the run it reused.
t_relreusepick() {
  local A B RUN got
  rrsetup pick
  echo '# changed' >> "$R/.conveyor/pick.sh"
  rrprep
  [ "$got" = "t/f1.test.sh" ] || fail "a change to the changed-tests command's file ran more than the failed file: '$got'"
  jq -e --arg a "$A" '.reused.sha == $a' "$RUN" > /dev/null || fail "the record does not say it reused the run on A: $(cat "$RUN")"
}
# rrrel: C, what the case changed after release-prep's pass on B, pushed; release runs on it. The stub's status (B's
# pass, for any commit) is cleared, so release runs the suite on C. Sets C and got (the files that suite ran).
rrrel() {
  git -C "$R" commit -qam 'fix: C' && git -C "$R" push -q origin main && rm -f "$STUB/ran" "$STUB/statuses" || fail "the fixture could not be made"
  C=$(git -C "$R" rev-parse HEAD)
  loop release 1.1.0 > "$T/$CASE.r" 2>&1 || fail "release failed on C: $(cat "$T/$CASE.r")"
  got=$(sort "$STUB/ran" 2>/dev/null | paste -sd' ' -)
}
# Bug (#1069): a card landed after a passed release-prep, and `release` on the new head ran all the files again,
# though the suite record held release-prep's run on B, an ancestor. Here C changes t/f2 and src/s3.sh (which the
# changed-tests command maps to t/f3): release reruns t/f2 and t/f3 alone, keeps t/f1's pass, and its record names B.
t_relreuserel() {
  local A B C RUN got
  rrsetup
  rrprep
  echo 'exit 0 # changed' > "$R/t/f2.test.sh"; echo three >> "$R/src/s3.sh"
  rrrel
  [ "$got" = "t/f2.test.sh t/f3.test.sh" ] || fail "release on C ran '$got', not t/f2 and t/f3 alone: $(cat "$T/$CASE.r")"
  jq -e --arg b "$B" --arg c "$C" '.step == "release" and .state == "released" and .sha == $c and (.reused | del(.time)) == {sha: $b, ran: ["t/f2.test.sh", "t/f3.test.sh"], kept: 1, machine: "local"}' "$RUN" > /dev/null \
    || fail "release's record does not name the run reused on B and the files rerun: $(cat "$RUN")"
}
# Bug (#1069, D2): a test setting changed since B can change what each file's ok means, so release, as release-prep
# does, runs every file and its record reuses no run. The fixture's pack is not tracked (.conveyor is ignored), so B
# adds it, for C to change it.
t_relreuseset() {
  local A B C RUN got
  rrsetup
  git -C "$R" add -f .conveyor/project.json || fail "the fixture could not be made"
  rrprep
  tune '.test.command += " # changed"'
  rrrel
  [ "$got" = "t/f1.test.sh t/f2.test.sh t/f3.test.sh" ] || fail "a change to a test setting did not make release run every file: '$got'"
  jq -e --arg c "$C" '.sha == $c and .reused == null' "$RUN" > /dev/null || fail "a whole suite's record says it reused a run: $(cat "$RUN")"
}
# Bug (#44 review): the record's newest line on an ancestor was taken, so a release-prep on origin's A after a green
# full test on the unpushed B hid B's pass, and Push landed on B ran every file again. suitebase() takes the line on
# the commit itself, else on the nearest ancestor (C, a child of B, takes B's line over the later A's).
t_suitebasenear() {
  local g=$T/$CASE/g A B C got
  mkdir -p "$g" && git -C "$g" init -q && for c in A B C; do git -C "$g" -c user.name=t -c user.email=t@example.com commit -q --allow-empty -m "$c" || fail "the fixture could not be made"; done
  A=$(git -C "$g" rev-parse HEAD~2) B=$(git -C "$g" rev-parse HEAD~1) C=$(git -C "$g" rev-parse HEAD)
  printf '{"sha":"%s","time":"t1","files":{"f":"ok"}}\n{"sha":"%s","time":"t2","files":{"f":"fail"}}\n' "$B" "$A" > "$T/$CASE/suites.jsonl"
  got=$(cd "$g" && export STATE=$T/$CASE/cards.jsonl && . "$SRC/lib/fulltest.sh" && suitebase "$B" | jq -r .sha && suitebase "$C" | jq -r .sha && suitebase "$A" | jq -r .sha)
  got=$(paste -sd' ' <<<"$got")
  [ "$got" = "$B $B $A" ] || fail "suitebase took '$got' for B, C and A, not '$B $B $A'"
}
# Bug (#1284): a run here that reran some files over the box's line on A kept the box's passes, but its line on B named
# this machine, so a later run told to run here (--machine local) reused them. suitekeep() of a rerun of t/f1 on B,
# over A's line of the box, must name the box in B's line and in the reuse it prints.
t_suitekeepbox() {
  local g=$T/$CASE/g A B got
  mkdir -p "$g" && git -C "$g" init -q && touch "$g/f1" "$g/f2" && git -C "$g" add f1 f2 \
    && git -C "$g" -c user.name=t -c user.email=t@example.com commit -qm A && git -C "$g" -c user.name=t -c user.email=t@example.com commit -q --allow-empty -m B \
    && printf 'TESTRUN files=1\n-- ok f1\n' > "$T/$CASE/wt.test" || fail "the fixture could not be made"
  A=$(git -C "$g" rev-parse HEAD~1) B=$(git -C "$g" rev-parse HEAD)
  # clock (lib/control.sh, which needs the whole engine's setup to load) only dates the line.
  got=$(cd "$g" && export STATE=$T/$CASE/cards.jsonl HERE=$SRC && . "$SRC/lib/session.sh" && . "$SRC/lib/fulltest.sh" && clock() { echo t2; } \
    && suitekeep "$T/$CASE/wt" "$B" 0 release-prep "$(jq -cn --arg a "$A" '{sha: $a, time: "t1", by: "release-prep", machine: "ssh", files: {f1: "fail", f2: "ok"}}')" | jq -c '{machine, kept}')
  [ "$got" = '{"machine":"ssh","kept":1}' ] && jq -e --arg b "$B" '.sha == $b and .machine == "ssh" and .files == {f1: "ok", f2: "ok"}' "$T/$CASE/suites.jsonl" > /dev/null \
    || fail "suitekeep of a rerun of f1 on B over the box's line on A did not name the box: printed '$got', suites: $(cat "$T/$CASE/suites.jsonl" 2>&1)"
}
# R253. Bug it catches: suitekeep() named a line the box's whenever it kept a pass of a box's line, by that line's
# machine alone. A pass here of f1 and f2 on A; a box (ssh) reruns f1 on B, keeping A's f2; a run here reruns f1 on C,
# keeping f2, whose pass is still A's from here. C's line held no result of a box but was named ssh, so a run told to
# run here (--machine local) passed it over for an older line, or ran the whole suite. C's line is local, and is the one
# such a run reuses; B's names the box and the file it gave.
t_suitekeepmixed() {
  local g=$T/$CASE/g A B C got c
  mkdir -p "$g" && git -C "$g" init -q && touch "$g/f1" "$g/f2" && git -C "$g" add f1 f2 \
    && for c in A B C; do git -C "$g" -c user.name=t -c user.email=t@example.com commit -q --allow-empty -m "$c" || break; done \
    && [ "$(git -C "$g" rev-list --count HEAD)" = 3 ] \
    && printf 'TESTRUN files=1\n-- ok f1\n' > "$T/$CASE/wt.test" || fail "the fixture could not be made"
  A=$(git -C "$g" rev-parse HEAD~2) B=$(git -C "$g" rev-parse HEAD~1) C=$(git -C "$g" rev-parse HEAD)
  # clock (lib/control.sh, which needs the whole engine's setup to load) only dates the line.
  got=$(cd "$g" && export STATE=$T/$CASE/cards.jsonl HERE=$SRC && . "$SRC/lib/session.sh" && . "$SRC/lib/fulltest.sh" && clock() { echo t2; } \
    && SH_KIND=ssh suitekeep "$T/$CASE/wt" "$B" 0 release-prep "$(jq -cn --arg a "$A" '{sha: $a, time: "t1", by: "release-prep", machine: "local", files: {f1: "ok", f2: "ok"}}')" > /dev/null \
    && suitekeep "$T/$CASE/wt" "$C" 0 release-prep "$(jq -c --arg b "$B" 'select(.sha == $b)' "$T/$CASE/suites.jsonl")" > /dev/null \
    && CONVEYOR_RELEASE_MACHINE=local suitebase "$C" | jq -r .sha)
  [ "$(jq -c '[.machine, .boxed]' "$T/$CASE/suites.jsonl" | paste -sd' ')" = '["ssh",["f1"]] ["local",[]]' ] \
    || fail "B's line (f1 from the box) or C's (f1 rerun here, f2 kept from A's pass here) does not name where its results came from: $(cat "$T/$CASE/suites.jsonl" 2>&1)"
  [ "$got" = "$C" ] || fail "a run told to run here on C reused '$got', not C's line, which holds no result of a box"
}
