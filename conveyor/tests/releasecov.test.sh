#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 120
# Engine cases: the coverage map each release makes again and commits (issue 1593; the pack's coverageMap,
# lib/relcov.sh). Their fixture is covsetup, below, on releaseboard.test.sh's runsetup (release.test.sh's cutsetup);
# t_relcovdevbox's is suitehost.test.sh's devboxsetup.
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"

# covcmd <command lines>...: the pack's coverageMap a command that notes the folder it runs in ($STUB/cov-at), then
# runs <command lines>, its map cov.jsonl. covsetup <command lines>...: runsetup with a passing suite, and covcmd.
covcmd() {
  tune '.coverageMap = {command: ". \"$STUB/cov-cmd\"", file: "cov.jsonl"}'
  printf '%s\n' 'echo "$PWD" >> "$STUB/cov-at"' "$@" > "$STUB/cov-cmd"
}
covsetup() { runsetup true; covcmd "$@"; }
# Bug: no release made the coverage map again, so it went stale as functions changed. release-prep's pass runs the
# command in the worktree of the commit it tested; the release after it, which runs no suite on that pass, commits the
# map in its release commit. The command fails after it wrote the map (as coverage.sh does when a unit fails): it is
# named, and its map is still committed.
# Bug (issue 1708): the map was made before the suite's status was posted and its result reported, so a long map held
# the result back. The status is posted and the result printed before the map starts, and the run's record says the suite
# passed, the run ended and the map runs (the Release panel's Suite passed, not Suite running) while the map is made.
# Bug (review of issue 1708): the run's end (ended) was written only after the map, and the Foreman's report and wake go
# by it, as do the fix cards (relfixes(): those filed after it), so a fix filed while the map ran was not counted. The
# end is in the record while the map runs, the run's own end keeps that time, and the record says nothing of the map
# once it is made.
t_relcovmap() {
  local O out t a b rr=$T/$CASE/cards/release/run.json
  # The command checks the record and the status while it runs, then rewrites the end to a marked time, so the end the
  # run writes after the map cannot pass for the one written before it.
  covsetup 'grep -qF state=success "$STUB/gh-calls" || echo "no status posted" >> "$STUB/cov-at"' 'git rev-parse HEAD > cov.jsonl' \
    "jq -e '(.ended | type) == \"string\" and .state == \"passed\" and .coverage == \"running\"' '$rr' > /dev/null || echo 'the record does not say the run ended with its suite passed and the map runs' >> \"\$STUB/cov-at\"" \
    "jq -c '.ended = \"2000-01-01T00:00:00Z\"' '$rr' > '$rr.t' && mv '$rr.t' '$rr'" \
    'echo "a unit failed"; exit 1'
  out=$(loop release-prep 1.1.0 2>&1) || fail "release-prep failed: $out"
  jq -e '.state == "passed" and has("coverage") == false and .ended == "2000-01-01T00:00:00Z"' "$rr" > /dev/null \
    || fail "the ended run's record is not passed, still says the map runs, or its end is not the one written before the map: $(cat "$rr")"
  a=$(grep -nF 'the whole suite passed on' <<<"$out" | cut -d: -f1) b=$(grep -nF 'makes the coverage map' <<<"$out" | cut -d: -f1)
  [ -n "$a" ] && [ -n "$b" ] && [ "$a" -lt "$b" ] || fail "the suite's result was not reported before the coverage map step started: $out"
  grep -qF "the coverage map's command failed (exit 1)" <<<"$out" && grep -qF 'a unit failed' <<<"$out" \
    || fail "release-prep did not name the coverage command's failure and its output: $out"
  [ "$(grep -c . "$STUB/cov-at" 2>/dev/null)" = 1 ] && [ "$(cat "$STUB/cov-at")" != "$R" ] \
    || fail "the coverage command did not run once, in the suite's worktree: $(cat "$STUB/cov-at" 2>&1)"
  out=$(loop release 1.1.0 2>&1) || fail "the release was refused: $out"
  [ "$(wc -l < "$STUB/runs")" = 1 ] && [ "$(grep -c . "$STUB/cov-at")" = 1 ] || fail "the release ran the suite or the coverage command again: $out"
  t=$(git -C "$T/$CASE/origin" rev-parse 'v1.1.0^{commit}') || fail "origin has no tag v1.1.0: $out"
  [ "$(git -C "$R" show "$t:cov.jsonl" 2>&1)" = "$O" ] && [ "$(git -C "$R" rev-parse "$t^")" = "$O" ] \
    || fail "the release commit $t does not hold the map the command wrote on $O: $(git -C "$R" show --stat "$t" 2>&1)"
}
# Bug (issue 1712): a release whose suite failed still made its coverage map, and the release's hold on landing lasted
# to the map's end, for a map the release commits no use of. The failed suite starts no map (the command never runs, so
# nothing is written to $STUB/cov-at), says so, ends the run with no map mark in its record, and a release over the
# failed suite (--anyway) goes on and commits none.
t_relcovanyway() {
  local O out t rr=$T/$CASE/cards/release/run.json
  anysetup; covcmd 'git rev-parse HEAD > cov.jsonl'
  out=$(loop release-prep 1.1.0 2>&1); [ $? = 1 ] || fail "release-prep did not fail on the red suite: $out"
  [ ! -e "$STUB/cov-at" ] || fail "the failed suite ran the coverage command: $(cat "$STUB/cov-at") $out"
  grep -qF 'the whole suite failed, so no coverage map is made' <<<"$out" || fail "the failed suite did not say it makes no coverage map: $out"
  ! grep -qF 'makes the coverage map' <<<"$out" || fail "the failed suite started the coverage map: $out"
  jq -e '.state == "failed" and has("coverage") == false and (.ended | type) == "string"' "$rr" > /dev/null \
    || fail "the failed run's record is not ended failed with no map mark: $(cat "$rr")"
  out=$(loop release 1.1.0 --anyway --by 'the owner' 2>&1) || fail "--anyway over the red suite was refused: $out"
  t=$(git -C "$T/$CASE/origin" rev-parse 'v1.1.0^{commit}') || fail "origin has no tag v1.1.0: $out"
  ! git -C "$R" cat-file -e "$t:cov.jsonl" 2>/dev/null || fail "the release over the failed suite committed a map: $(git -C "$R" show --stat "$t" 2>&1)"
  [ ! -e "$STUB/cov-at" ] || fail "the release over the failed suite ran the coverage command: $(cat "$STUB/cov-at")"
}
# Bug (review of issue 1712): the map was skipped when only the status post failed, though the suite passed: the skip went
# by release-prep's result, not the suite's. The suite passes, the post fails, and the map is still made.
t_relcovposted() {
  local out
  covsetup 'echo map > cov.jsonl'
  # stub: gh whose status post fails while the suite passed
  printf '%s\n' '#!/usr/bin/env bash' 'if [[ " $* " == *" -X POST "* ]] && [[ " $* " == *statuses* ]]; then exit 1; fi' 'echo "[]"' > "$STUB/gh" \
    || fail "the fixture could not be made"
  out=$(loop release-prep 1.1.0 2>&1); [ $? = 1 ] && grep -qF 'could not be posted (the suite passed)' <<<"$out" || fail "release-prep did not fail on the status post: $out"
  [ "$(grep -c . "$STUB/cov-at" 2>/dev/null)" = 1 ] && ! grep -qF 'the whole suite failed, so no coverage map' <<<"$out" \
    || fail "the passed suite's coverage map was skipped when its status could not be posted: $(cat "$STUB/cov-at" 2>&1) $out"
}
# Bug (review of issue 1712): the skip went by the suite's raw result, so a suite that failed in the whole run and passed
# once each failed case ran alone (judged flaky: the suite passes) still made no map. The failing case passes alone, the
# suite passes, and the map is made.
t_relcovflaky() {
  local out
  runsetup '[ -n "${CONVEYOR_TEST_RERUN:-}" ] || { echo "FAIL [flips]: off"; exit 1; }'; covcmd 'echo map > cov.jsonl'
  out=$(loop release-prep 1.1.0 2>&1) || fail "release-prep failed on a case that passes alone: $out"
  grep -qF 'judged flaky: flips' <<<"$out" || fail "the case was not judged flaky, so the fixture does not test the path: $out"
  [ "$(grep -c . "$STUB/cov-at" 2>/dev/null)" = 1 ] && ! grep -qF 'the whole suite failed, so no coverage map' <<<"$out" \
    || fail "the suite that passed after its flaky case passed alone made no coverage map: $(cat "$STUB/cov-at" 2>&1) $out"
}
# Bug: a release whose push fails left the map it put in the checkout there, staged, so the checkout was not as the
# release found it. The command moves origin's main (as a card that lands meanwhile does), so the push fails.
t_relcovundo() {
  local O out
  covsetup 'echo map > cov.jsonl' 'git commit -q --allow-empty -m landed && git push -q origin HEAD:refs/heads/main'
  out=$(loop release 1.1.0 2>&1); [ $? = 1 ] && grep -qF 'could not be pushed' <<<"$out" || fail "the release's push did not fail: $out"
  [ ! -e "$R/cov.jsonl" ] && [ "$(git -C "$R" rev-parse HEAD)" = "$O" ] && [ -z "$(git -C "$R" status --porcelain --untracked-files=no)" ] \
    || fail "the undone release left the map or a change in the checkout: $(git -C "$R" status --porcelain 2>&1) $(git -C "$R" log --oneline -2)"
}
# Bugs: a suite run on a devbox (or a box over ssh) made no map; then (issue 1708) it made it on the build machine, 4
# units at a time, after the box was given back and before the suite's result was posted or reported. The command runs
# on the devbox, in its checkout of the tested commit, with the lease still held and the suite's status posted; the
# older map the commit holds is not there for it (only a map this run wrote comes back); the map comes back and is kept,
# and the lease is given back once after it.
t_relcovdevbox() {
  local O out a b
  runsetup "$BOXSUITE"; devboxsetup 3
  covcmd '[ -e "$STUB/devbox-leased" ] || echo "lease given back" >> "$STUB/cov-at"' '[ ! -e cov.jsonl ] || echo "an older map is there" >> "$STUB/cov-at"' \
    'grep -qF context=conveyor/release-suite "$STUB/gh-calls" || echo "no status posted" >> "$STUB/cov-at"' 'echo map > cov.jsonl'
  echo old > "$R/cov.jsonl" && git -C "$R" add cov.jsonl && git -C "$R" commit -qm 'an older map' && git -C "$R" push -q origin main && O=$(git -C "$R" rev-parse HEAD) \
    || fail "the fixture could not be made"
  out=$(loop release-prep 1.1.0 2>&1) || fail "release-prep on the devbox failed: $out"
  [ "$(cat "$STUB/full-pwd" 2>&1)" = "$BOX/wt" ] || fail "the suite did not run on the devbox: $(cat "$STUB/full-pwd" 2>&1)"
  [ "$(cat "$STUB/cov-at" 2>&1)" = "$BOX/wt" ] || fail "the coverage command did not run once on the devbox's checkout, with the lease held, the status posted and no older map: $(cat "$STUB/cov-at" 2>&1): $out"
  [ "$(cat "$T/$CASE/cards/release/coverage."* 2>&1)" = map ] && grep -qF "the coverage map of ${O:0:12} is kept for its release to commit" <<<"$out" \
    || fail "the map the devbox wrote did not come back and was not kept: $(cat "$T/$CASE/cards/release/coverage."* 2>&1): $out"
  [ "$(cat "$STUB/devbox-released" 2>&1)" = lease-1274 ] && [ ! -e "$STUB/devbox-leased" ] || fail "the lease was not given back once after the map: $(cat "$STUB/devbox-released" 2>&1)"
  a=$(grep -nF 'the whole suite passed on' <<<"$out" | cut -d: -f1) b=$(grep -nF 'makes the coverage map' <<<"$out" | cut -d: -f1)
  [ -n "$a" ] && [ -n "$b" ] && [ "$a" -lt "$b" ] || fail "the suite's result was not reported before the coverage map step started: $out"
}
# Bug (review of issue 1708): when the devbox call that removes the old map and runs the command failed before it ran
# (a lost connection), the next call still brought back the map the commit holds, and it was kept as fresh. No map
# comes back from a call that did not run there, and the output says none is kept.
t_relcovdevboxlost() {
  local O out
  runsetup "$BOXSUITE"; devboxsetup 3; covcmd 'echo map > cov.jsonl'
  echo old > "$R/cov.jsonl" && git -C "$R" add cov.jsonl && git -C "$R" commit -qm 'an older map' && git -C "$R" push -q origin main \
    && O=$(git -C "$R" rev-parse HEAD) && mv "$STUB/devbox" "$STUB/devbox-real" || fail "the fixture could not be made"
  # stub: the stand-in devbox, whose call that runs the coverage command fails before it runs there, as a lost connection does
  printf '%s\n' '#!/usr/bin/env bash' 'case "$*" in *cov-cmd*) exit 255 ;; esac' 'exec "$STUB/devbox-real" "$@"' > "$STUB/devbox" && chmod +x "$STUB/devbox" \
    || fail "the fixture could not be made"
  out=$(loop release-prep 1.1.0 2>&1) || fail "release-prep on the devbox failed: $out"
  [ ! -e "$STUB/cov-at" ] && ! compgen -G "$T/$CASE/cards/release/coverage.*" > /dev/null && grep -qF "the coverage map's command wrote no cov.jsonl" <<<"$out" \
    || fail "a map came back from a call that did not run there, or the output did not say none is kept: $(cat "$T/$CASE/cards/release/coverage."* 2>&1): $out"
}
# Bugs (review of issue 1708): release-run stop while a box made the map left the map's units running there: each runs
# under `timeout` (.conveyor/coverage.sh), which starts a process group of its own, and the stop signalled only the
# group in wt.pid. And a run whose end is written before the map is one the stop must still find, whose suite's result
# it keeps. The record's machine step says the map runs, not the suite. A whole release-run, as only it starts the map
# in the background, holds the lock and is stopped by `release-run stop`; the box's processes carry no mark of the run
# (boxsetup), so only the stop sent over ssh ends them. The session read is the box's /proc: a Linux box.
t_relcovboxstop() {
  local O RUN out
  [ "$(uname -s)" = Linux ] || return 0
  runsetup "$BOXSUITE"; boxsetup 3; boxrule
  covcmd 'timeout 300 sleep 300 & echo $! > "$STUB/map-unit"; wait' # sleep: the map's unit, under timeout as coverage.sh runs one, which only the stop ends
  out=$(loop release-run prep 1.1.0 2>&1) || fail "release-run prep did not start the run: $out"
  # wait_until: the map starts on the box in the background; only its note there shows when it runs.
  wait_until '[ -s "$STUB/map-unit" ]' || fail "the map did not start on the box: $(cat "$T/$CASE/cards/release/run.log" 2>&1)"
  jq -e '.state == "passed" and (.ended | type) == "string" and .coverage == "running" and .machine.step == "map"' "$RUN" > /dev/null \
    || fail "while the map runs, the record does not say the suite passed, the run ended and the box makes the map: $(cat "$RUN")"
  out=$(loop release-run stop 2>&1) || fail "the stop failed: $out"
  # wait_until: a process sent TERM ends a moment later; only a check of it shows when it has.
  wait_until "! kill -0 $(cat "$STUB/map-unit") 2>/dev/null" || { kill "$(cat "$STUB/map-unit")"; fail "the map's unit still runs on the box after release-run stop: $out"; }
  jq -e '.state == "passed" and has("coverage") == false and (.reasons | index("the coverage map was stopped by the owner"))' "$RUN" > /dev/null \
    || fail "the stop did not keep the suite's pass and say the map was stopped: $(cat "$RUN")"
}
# Bug (review of issue 1708): release-prep posts the suite's status before it makes the map, so a run stopped while the
# map is made, or a command that writes none, leaves a passed status and no map; the release after it reuses that
# status and runs no suite, and it committed no map with no word of it. It says it commits none.
t_relcovnone() {
  local O out t
  covsetup ':'
  out=$(loop release-prep 1.1.0 2>&1) || fail "release-prep failed: $out"
  out=$(loop release 1.1.0 2>&1) || fail "the release was refused: $out"
  t=$(git -C "$T/$CASE/origin" rev-parse 'v1.1.0^{commit}') || fail "origin has no tag v1.1.0: $out"
  grep -qF "no coverage map of ${O:0:12} is kept" <<<"$out" && ! git -C "$R" cat-file -e "$t:cov.jsonl" 2>/dev/null \
    || fail "the release with no map kept did not say it commits none, or committed one: $out"
}
# Bug: a release replaced a map in the checkout that no commit holds (the Foreman's first map, made by hand), and its
# undo then deleted it. The release leaves it as it is and commits no map; its push fails (the command moves origin's
# main), so its undo runs too.
t_relcovhand() {
  local O out
  covsetup 'echo new > cov.jsonl' 'git commit -q --allow-empty -m landed && git push -q origin HEAD:refs/heads/main'
  echo hand > "$R/cov.jsonl"
  out=$(loop release 1.1.0 2>&1); [ $? = 1 ] && grep -qF 'could not be pushed' <<<"$out" || fail "the release's push did not fail: $out"
  grep -qF 'holds a cov.jsonl that' <<<"$out" && [ "$(cat "$R/cov.jsonl" 2>&1)" = hand ] && [ -z "$(git -C "$R" ls-files cov.jsonl)" ] \
    || fail "the release did not leave the hand-made map as it was, or did not say so: $(cat "$R/cov.jsonl" 2>&1): $out"
}
# Bug: the release pushed the map with no privacy check: the checks of the tracked files run before the map is put in
# the checkout. A map with a person's email is not committed, and the release goes out without it.
t_relcovprivacy() {
  local O out t AT=@
  covsetup "echo 'a case of other${AT}mail.io' > cov.jsonl"
  out=$(loop release 1.1.0 2>&1) || fail "the release was refused: $out"
  t=$(git -C "$T/$CASE/origin" rev-parse 'v1.1.0^{commit}') || fail "origin has no tag v1.1.0: $out"
  grep -qF 'the privacy check finds something in the coverage map' <<<"$out" && ! git -C "$R" cat-file -e "$t:cov.jsonl" 2>/dev/null && [ ! -e "$R/cov.jsonl" ] \
    || fail "the release committed a map the privacy check finds a hit in, or did not say why it left it out: $(git -C "$R" show --stat "$t" 2>&1): $out"
}
