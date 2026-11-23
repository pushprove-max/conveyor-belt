#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 120
# Engine cases: the record of a release's suite run, as the snapshot shows it (suites, release). Their fixture is
# release.test.sh's relsetup. The Board's Release (`conveyor.sh release-run`) is in releaseboard.test.sh,
# releasestop.test.sh and releaseagain.test.sh.
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"

# relcall <command...>: runs the command in main ($R) with the snapshot's engine functions loaded, as `loop snapshot --fresh`
# has them, so a case calls the one function it proves (suites(), releasemain()) and not the whole snapshot.
relcall() {
  # shellcheck source=/dev/null # the snapshot's libraries, by the list snapshot.sh names (SNAPLIBS)
  ( export CONVEYOR_MAIN=$R CONVEYOR_CARDS=$T/$CASE/cards; . "$SRC/conveyor.sh" state-dir > /dev/null && eval "$(grep '^SNAPLIBS=' "$SRC/commands/snapshot.sh")" && for l in $SNAPLIBS; do . "$HERE/lib/$l.sh" || exit 1; done && names || exit 1
    cd "$R" && "$@" )
}
# relsnap <what> <jq arguments, the test last>: the test holds of the release's entry of the snapshot's suites
# (suites(), lib/snapshot.sh). t_relrecord's last check reads it from a whole snapshot.
relsnap() {
  local what=$1 s; shift
  s=$(relcall suites | jq -c '.[] | select(.kind == "release")')
  jq -e "$@" <<<"$s" > /dev/null || fail "$what: $s"
}
# Bug: nothing shows a release's suite while it runs (the owner asks the Foreman whether it runs and how far it is), or
# after it ends, with the commit it tested. The stub suite names each case as it ends, as the engine's runner does,
# says so ($STUB/at1, at2), and waits for the case to read the snapshot. Bug (#11): the snapshot gave the cases done
# but not how many the run selected, so the Foreman's status could not say how far the suite is: the stub's log says
# it selected 3 (`TESTRUN cases=3`), and the snapshot's of says so.
t_relrecord() {
  local O pid s
  relsetup 'mkdir -p "$CONVEYOR_TEST_LOG/cases/ok" && printf "%s\n" "TESTRUN cases=3" "TESTRUN files=2" "-- FAIL a.test" > "$CONVEYOR_TEST_LOG/run.log" && : > "$CONVEYOR_TEST_LOG/cases/ok/one" && : > "$STUB/at1"
until [ -e "$STUB/go" ]; do sleep 0.1; done; : > "$CONVEYOR_TEST_LOG/cases/ok/two"; : > "$STUB/at2"
until [ -e "$STUB/go2" ]; do sleep 0.1; done'
  loop release-prep 1.1.0 > "$T/$CASE.prep" 2>&1 & pid=$!
  wait_until '[ -e "$STUB/at1" ]' || fail "the suite did not start: $(cat "$T/$CASE.prep")"
  relsnap "the snapshot does not show the run on $O, 1 case done" --arg o "$O" '.state == "running" and .sha == $o and .version == "1.1.0" and .done == 1 and .of == 3 and .ended == null'
  # Bug (#27): the Release panel shows the suite's cases, not its files done of all and the failed files' names.
  relsnap "the snapshot does not count the suite's files" '.files == {done: 1, of: 2, failed: ["a.test"]}'
  : > "$STUB/go"; wait_until '[ -e "$STUB/at2" ]' || fail "the suite did not go on"
  relsnap "the snapshot's cases done do not rise as the suite runs" '.state == "running" and .done == 2'
  : > "$STUB/go2"; wait "$pid" || fail "release-prep failed: $(cat "$T/$CASE.prep")"
  # One whole snapshot, so its suites and release are those suites() and releasemain() give.
  s=$(loop snapshot --fresh) || fail "the snapshot failed: $s"
  jq -e --arg o "$O" '.suites[] | select(.kind == "release") | .state == "passed" and .sha == $o and .done == 2 and .failed == 0 and .ended != null' <<<"$s" > /dev/null \
    || fail "the snapshot does not show the passed run on $O once it ended: $(jq -c .suites <<<"$s")"
  # Bug (issue 34): a release's suite kept no file's result, so the Tests page never showed a whole-suite run.
  [ "$(jq -sc --arg o "$O" 'map([.how, .sha == $o, .files])' "$ST/suiteruns.jsonl" 2>&1)" = '[["release",true,{"a.test":{"result":"fail","sec":null,"cpu":null}}]]' ] \
    || fail "the release's suite run is not kept for the Tests page: $(cat "$ST/suiteruns.jsonl" 2>&1)"
  # Bug: the Release panel cannot say what a release would hold: main's newest tag (the one release-prep fetched), the
  # commits since it, the next version and whether main holds its notes.
  jq -e --arg h "$(git -C "$R" rev-parse HEAD)" '.release | .tag == "v1.0.0" and .count == 3 and .next == "1.1.0" and .notes == true and .head == $h
    and (.commits | map(.subject)) == ["feat: Not pushed yet", "fix: A fix", "feat(engine): A new thing (#5)"]' <<<"$s" > /dev/null \
    || fail "the snapshot's release does not show main since v1.0.0: $(jq -c .release <<<"$s")"
}
# Bugs (#27): the Release panel shows a project that does not release with Conveyor (no docs/releases/ on main), and
# fills in the tag's next minor (0.1.0 with no tag) where main already holds the notes of the release being prepared
# (docs/releases/1.0.0.md). The engine's own releasemain() (lib/snapshot.sh),
# called on one main as it moves.
t_relnext() {
  setup '[]'
  relmain() { relcall releasemain | jq -c "${1:-[.tag, .next, .notes, .releases]}"; }
  relput() { mkdir -p "$R/${1%/*}" && printf '%s\n' "$2" > "$R/$1" && git -C "$R" add "$1" && git -C "$R" commit -q -m "add $1" || fail "the fixture could not be made"; }
  [ "$(relmain)" = '[null,"0.1.0",false,false]' ] || fail "a main with no docs/releases/ and no tag: $(relmain)"
  relput docs/releases/1.0.0.md '# 1.0.0'
  [ "$(relmain)" = '[null,"1.0.0",true,true]' ] || fail "no tag and docs/releases/1.0.0.md: not 1.0.0, or not a project that releases with Conveyor: $(relmain)"
  # Bug (#413): the version box took plugin.json's version, one with no notes that is not the next after the newest
  # release.
  git -C "$R" tag v1.0.0 && relput .claude-plugin/plugin.json '{"version": "1.1.5"}'
  [ "$(relmain)" = '["v1.0.0","1.1.0",false,true]' ] || fail "with no notes over v1.0.0, not its next minor (plugin.json's 1.1.5 has no notes): $(relmain)"
  relput docs/releases/1.3.0.md '# 1.3.0'; relput docs/releases/1.10.0-rc.md 'not a version'
  [ "$(relmain)" = '["v1.0.0","1.3.0",true,true]' ] || fail "the notes of 1.3.0 over v1.0.0 are not the next version: $(relmain)"
  # Bug: the panel marks the notes written for a version the owner types in place of next: written names each version
  # with notes on main, so the panel checks the one typed.
  [ "$(relmain .written)" = '["1.0.0","1.3.0"]' ] || fail "written does not name the versions with notes on main: $(relmain .written)"
  git -C "$R" tag v1.3.0
  [ "$(relmain)" = '["v1.3.0","1.4.0",false,true]' ] || fail "with notes and plugin.json no higher than v1.3.0, not its next minor: $(relmain)"
  # Bug it catches: the newest tag is read in the shell now (no grep or sort): v1.10.0 is newer than v1.9.0 (a version
  # order, not a text one), and v2.0.0-rc1 is no release.
  git -C "$R" tag v1.9.0 && git -C "$R" tag v1.10.0 && git -C "$R" tag v2.0.0-rc1
  [ "$(relmain)" = '["v1.10.0","1.11.0",false,true]' ] || fail "with tags v1.9.0, v1.10.0 and v2.0.0-rc1, not v1.10.0 and its next minor: $(relmain)"
}
# Bug it catches (E6): while a large failed suite's cases ran alone, suites() passed the suite's progress and the record
# read again as one jq argument each; past Linux's 128 KiB limit of one argument jq did not start, and the Release
# panel lost the run. Here 2,000 failed cases of 105 bytes are in both, with the release lock held as a running run holds it.
t_relbigrun() {
  local c=$T/$CASE/cards/release pid
  setup '[]'
  mkdir -p "$c/wt.testlog/cases/failed" && (cd "$c/wt.testlog/cases/failed" && for i in $(seq 2000); do : > "$(printf "case%04d-%096d" "$i" 0)"; done) \
    && ls "$c/wt.testlog/cases/failed" | jq -Rn --arg s "$(git -C "$R" rev-parse HEAD)" '[inputs] as $c | {kind: "release", step: "release-prep",
      version: "1.1.0", since: "2026-01-01T00:00:00Z", ended: null, state: "running", sha: $s, main: null, moved: false, reasons: [],
      rerun: {since: "2026-01-01T00:00:01Z"}, counts: {done: 2000, failed: 2000, cases: $c}}' > "$c/run.json" || fail "the fixture could not be made"
  [ "$(wc -c < "$c/run.json")" -gt 131072 ] || fail "the fixture's record is under 128 KiB"
  ( exec 9>>"$c/lock"; flock 9; : > "$STUB/held"; exec sleep 120 ) & pid=$! # sleep: the running run's hold of the lock, ended below
  wait_until '[ -e "$STUB/held" ]' || fail "the lock was not taken"
  relsnap "the snapshot does not show the running run of 2000 failed cases with its rerun's progress" \
    '.state == "running" and .failed == 2000 and (.cases | length) == 2000 and .rerun.failed == 2000 and .rerun.done == 2000'
  kill "$pid" 2>/dev/null
}
# Bug: the Release panel says main moved only once the suite ends, so the owner waits for a whole suite whose result
# no release can use. A card lands (main moves) while the stub suite waits; the snapshot must say moved before it ends.
t_relmoving() {
  local O pid
  relsetup ': > "$STUB/at1"; until [ -e "$STUB/go" ]; do sleep 0.1; done'
  loop release-prep 1.1.0 > "$T/$CASE.prep" 2>&1 & pid=$!
  wait_until '[ -e "$STUB/at1" ]' || fail "the suite did not start: $(cat "$T/$CASE.prep")"
  relsnap "the snapshot says main moved before any card landed" '.state == "running" and .moved == false and (has("main") | not)'
  git -C "$R" commit -q --allow-empty -m 'fix: A card landed' || fail "the fixture could not be made"
  relsnap "the snapshot does not say main moved while the suite runs" '.state == "running" and .moved == true'
  : > "$STUB/go"; wait "$pid" || fail "release-prep failed: $(cat "$T/$CASE.prep")"
}
