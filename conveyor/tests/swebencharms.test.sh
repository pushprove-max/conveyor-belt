#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 300
# Engine cases: the arms of `conveyor.sh bench swe` (bench/swe.sh): runs of named arms, their preflights, logins and
# seats, and the trials that did not fire. The fixture is swebench.test.sh's swe().
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"

# Bugs: --arm ran one arm only, or the arms on other tasks; an arm ran with no preflight; a trial shared a container
# or left one behind; the login copied into a container reached the results; the results of two arms were mixed, or
# could not be compared with diff.
t_swearms() {
  swe; local first second out
  { read -r first; read -r second; } < <(sweorder)
  out=$(loop bench swe 2 --arm stub-a --arm stub-b 2>&1) || fail "the run of two arms failed: $out"
  grep -q "^1/2 $first \[stub-a\]: " <<<"$out" && grep -q "^1/2 $first \[stub-b\]: " <<<"$out" && grep -q "^2/2 $second \[stub-b\]: " <<<"$out" \
    || fail "the two arms did not each build both tasks of the pinned order: $out"
  grep -q "^Resolved 2 of 2 with Stub a; not run: 0\.$" <<<"$out" && grep -q "^Resolved 1 of 2 with Stub b; not run: 0\.$" <<<"$out" \
    || fail "the run does not end with each arm's own resolved count: $out"
  # Bug (#326): a run's line named its arms but not their results keys, so the Board could not read each arm's figures.
  [ "$(tail -n 1 "$B/runs.jsonl" | jq -c '[(.cols | map([.arm, (.key | sub("-[0-9a-f]{12}$"; ""))])), .set.revision == $rv]' --arg rv "$(jq -r .revision "$SRC/bench/swe.json")")" = '[[["stub-a","stub-a"],["stub-b","stub-b"]],true]' ] \
    || fail "the run's line does not name each arm's results key and the task set: $(tail -n 1 "$B/runs.jsonl")"
  [ "$(cat "$B"/results/stub-a-*/*.json | jq -sc 'map([.task, .resolved, .arm, .tokens]) | sort')" = "$(jq -nc --arg a proj__a-1 --arg b proj__b-2 '[[$a, true, "stub-a", 7], [$b, true, "stub-a", 7]]')" ] \
    && [ "$(cat "$B"/results/stub-b-*/*.json | jq -sc 'map([.task, .resolved]) | sort')" = '[["proj__a-1",false],["proj__b-2",true]]' ] \
    || fail "the results are not kept per arm: $(cat "$B"/results/stub-*/*.json)"
  # Each arm passed its preflight first; then every trial had a container of its own, removed after it.
  jq -se 'length == 2 and all(.ok)' "$B/preflight/stub-a/stub-a.json" "$B/preflight/stub-b/stub-b.json" > /dev/null || fail "an arm ran with no passed preflight"
  [ "$(grep -c '^create ' "$SWE_FX/docker.log")" = 6 ] && [ "$(sort -u "$SWE_FX/removed" | wc -l)" = 6 ] && [ -z "$(ls "$SWE_FX/boxes")" ] \
    || fail "the 2 preflights and 4 trials did not each get a container of their own, removed after: $(cat "$SWE_FX/docker.log")"
  [ "$(sort -u "$SWE_FX/creds-seen")" = CLAUDE-LOGIN ] || fail "the container was not given the builder's Claude login: $(cat "$SWE_FX/creds-seen" 2>&1)"
  ! grep -rq CLAUDE-LOGIN "$B" || fail "the login copied into the containers is in the results, the logs or the preflight records: $(grep -rl CLAUDE-LOGIN "$B")"
  out=$(loop bench swe diff stub-a stub-b --json 2>&1) && [ "$(jq -c '[.a.version, .b.version, [.flipped[].task], .flipped[0].changes, .same]' <<<"$out")" = '["stub-a","stub-b",["proj__a-1"],null,["proj__b-2"]]' ] \
    || fail "diff does not compare two arms on the tasks both ran: $out"
  out=$(loop bench swe arms 2>&1); grep -q "^stub-a (Stub a, agent): ready (checked " <<<"$out" && grep -q "^stub-quiet (Stub quiet, agent): not checked" <<<"$out" \
    || fail "the arms are not listed with their preflight state: $out"
}

# Bug (#338): an arm on the builder's model keeps each model's results under a key of its own, but the results and
# diff called both keys by the arm's label alone, so two models' runs could not be told apart. An arm of a fixed model
# (its key is its name) has the model in its label already, and was named with it twice.
t_swearmmodel() {
  swe; local m out
  for m in m1 m2; do
    mkdir -p "$B/results/stub-a-$m" && jq -nc --arg m "$m" '{task: "proj__a-1", arm: "stub-a", label: "Stub a", key: "stub-a-\($m)", engine: null, version: null,
      model: $m, resolved: true, fired: true, sessions: 1, tokens: 7, minutes: 1}' > "$B/results/stub-a-$m/proj__a-1.json" || fail "the results could not be written"
  done
  mkdir -p "$B/results/stub-f" && jq -nc '{task: "proj__a-1", arm: "stub-f", label: "Stub f (m3)", key: "stub-f", engine: null, version: null,
    model: "m3", resolved: true, fired: true, sessions: 1, tokens: 7, minutes: 1}' > "$B/results/stub-f/proj__a-1.json" || fail "the results could not be written"
  out=$(loop bench swe results 2>&1); grep -q "^Stub a (m1): 1 of 1 resolved" <<<"$out" && grep -q "^Stub a (m2): 1 of 1 resolved" <<<"$out" \
    && grep -q "^Stub f (m3): 1 of 1 resolved" <<<"$out" || fail "the results do not name each key's model once: $out"
  out=$(loop bench swe diff stub-a-m1 stub-a-m2 --json 2>&1) && [ "$(jq -c '[.a.version, .b.version]' <<<"$out")" = '["Stub a (m1)","Stub a (m2)"]' ] \
    || fail "diff does not name each key's model: $out"
}

# Bugs: an arm whose preflight fails could still be picked, or failed with no word of what is missing; an arm that
# cannot run here was offered.
t_swearmpre() {
  swe; local out
  rm "$CODEX_HOME/auth.json"
  out=$(loop bench swe 1 --arm stub-a --arm stub-codex 2>&1) && fail "an arm with no Codex login ran: $out"
  grep -q "the arm stub-codex cannot run: its preflight failed: no codex login on this machine: .*auth.json is missing" <<<"$out" || fail "the refusal does not say what is missing: $out"
  [ ! -d "$B/results" ] && [ ! -s "$SWE_FX/log" ] || fail "a task was built though an arm of the run cannot run"
  # Bug: the refusal came after the Board stopped reading the command's answer, and was recorded nowhere.
  [ "$(jq -r '.state + ": " + .why' "$B/live.json")" = "refused: $(grep -o 'the arm stub-codex cannot run: .*' <<<"$out")" ] \
    || fail "the refused run is not recorded with why: $(cat "$B/live.json")"
  out=$(loop bench swe arms 2>&1); grep -q "^stub-codex (Stub codex, agent): failed (.*): no codex login" <<<"$out" || fail "the list does not show the failed preflight: $out"
  # Bug: an arm whose install failed was reported as having a fired or tokens filter that is not valid jq.
  out=$(loop bench swe arms check stub-broken 2>&1) && fail "a preflight passed with a failed install: $out"
  grep -q "^stub-broken: failed: on the trivial task, its install failed: .*no-such-package" <<<"$out" || fail "the preflight does not say its install failed: $out"
  : > "$SWE_FX/nodocker"
  out=$(loop bench swe arms check stub-a 2>&1) && fail "a preflight passed with no Docker: $out"
  grep -qx 'conveyor: Docker did not answer on the build machine. Install or start Docker, check that `docker info` works, then check again.' <<<"$out" \
    || fail "the check does not name Docker as missing and its repair: $out"
  # Bugs (#633): a run of arms whose preflight passed started with no Docker, every task not run; its refusal removed an
  # arms check's container (chk), was on stderr only (History had no why) and named no engine (the Board said main).
  mkdir -p "$SWE_FX/boxes/chk" "$B/check/stub-a.h" && echo chk > "$B/check/stub-a.h/box"
  out=$(loop bench swe 1 --solo --arm conveyor --engine v1.5.0 2>&1) && fail "a run started with no Docker: $out"
  grep -q '^conveyor: Docker did not answer on the build machine\.' <<<"$out" || fail "the run's refusal does not name Docker: $out"
  [ ! -d "$B/results" ] && [ -d "$SWE_FX/boxes/chk" ] || fail "a task was run, or a check's container removed, with no Docker"; rm -r "$SWE_FX/nodocker" "$B/check/stub-a.h"
  out=$(loop bench swe history 2>&1); jq -e '.runs[0] | .state == "refused" and (.cols | map(.arm) == ["solo", "conveyor"]) and .cols[1].version == "v1.5.0"
    and (.why | startswith("Docker did not answer on the build machine."))' <<<"$out" > /dev/null || fail "the run history does not keep the Docker refusal: $out"
  # The engine's own arms: every file is an arm, and one that cannot run on a subscription login says why.
  out=$(CONVEYOR_BENCH_ARMS=$SRC/bench/arms loop bench swe arms 2>&1)
  [ "$(grep -c '' <<<"$out")" = "$(ls "$SRC"/bench/arms/*.json | wc -l)" ] && ! grep -q 'not a JSON object' <<<"$out" \
    && grep -q "^aider (Aider, agent): not offered: Aider runs on a model provider's API key" <<<"$out" || fail "the engine's arms are not all listed: $out"
  out=$(CONVEYOR_BENCH_ARMS=$SRC/bench/arms loop bench swe 1 --arm openhands 2>&1) && fail "an arm that is not offered ran: $out"
  grep -q "the arm openhands is not offered" <<<"$out" || fail "the refusal does not say the arm is not offered: $out"
}

# Bug: a trial whose arm did not fire (its output shows no use of its method) was graded on the change it left, or
# skipped as a task not run, when it is the arm's failure.
t_swearmquiet() {
  swe; local out
  out=$(loop bench swe 2 --arm stub-quiet 2>&1) || fail "the run failed: $out"
  [ "$(grep -c ': unresolved (it did not fire: its output shows no use of its method)$' <<<"$out")" = 2 ] && grep -q "^Resolved 0 of 2 with Stub quiet; not run: 0\.$" <<<"$out" \
    || fail "the trials that did not fire are not the arm's failures: $out"
  [ "$(cat "$B"/results/stub-quiet-*/*.json | jq -sc 'map([.fired, .resolved]) | unique')" = '[[false,false]]' ] && [ ! -e "$SWE_FX/graded" ] \
    || fail "a trial that did not fire was graded, or not kept as failed: $(cat "$B"/results/stub-quiet-*/*.json)"
}

# Bug: after an arm's container exited, the host ran git in the sandbox the arm could write (its clean filter ran on
# the host) and wrote the patch through the arm's link to a file outside the sandbox.
t_swearmhost() {
  swe; local out
  echo ORIGINAL > "$SWE_FX/victim"
  out=$(loop bench swe 1 --arm stub-evil 2>&1) || fail "the run failed: $out"
  grep -q "^Resolved 1 of 1 with Stub evil; not run: 0\.$" <<<"$out" || fail "the arm's patch was not read and graded: $out"
  [ -s "$SWE_FX/filter-home" ] && ! grep -qv "^$SWE_FX/boxes/" "$SWE_FX/filter-home" || fail "the arm's git filter ran outside its container: $(cat "$SWE_FX/filter-home" 2>&1)"
  [ "$(cat "$SWE_FX/victim")" = ORIGINAL ] || fail "the host wrote through the arm's link to a file outside the sandbox: $(cat "$SWE_FX/victim")"
}

# Bug: a conveyor arm's seats were not given to the engine in its container (it built on the project's seats), or the
# container's control record named a host account it does not hold.
t_sweseats() {
  swe; local out
  jq '.seats = {model: {cli: "codex", model: "x"}, reviewer: {cli: "claude", model: "m"}} | .label = "Conveyor, Codex builds"' "$SWE_FX/arms/conveyor.json" > "$SWE_FX/arms/conveyor-seats.json"
  out=$(loop bench swe 1 --arm conveyor-seats 2>&1) || fail "the run failed: $out"
  grep -q "^Resolved 1 of 1 with Conveyor, Codex builds on engine main ($EB); not run: 0\.$" <<<"$out" || fail "the seats arm did not resolve the task on main's engine: $out"
  jq -e '.model == {cli: "codex", model: "x"} and .reviewer == {cli: "claude", model: "m"} and (has("account") | not)' "$SWE_FX/control.seen" > /dev/null \
    && jq -e '.models.allowed.codex | index("x")' "$SWE_FX/pack.seen" > /dev/null || fail "the engine was not given the arm's seats: $(cat "$SWE_FX/control.seen") $(jq -c .models "$SWE_FX/pack.seen")"
  # Bug: the engine in the container ran the project's own test command, not the task's (its cmd in the task list).
  jq -e '.test.command == "true" and .test.survey == false' "$SWE_FX/pack.seen" > /dev/null || fail "the engine's pack does not hold the task's test command: $(jq -c .test "$SWE_FX/pack.seen")"
  # Bug: the pack set no test.fileCommand, so a card that added a test file to a task repository with no test
  # configuration blocked at its Test step. It is run here as filecmd() runs it, on one named file, in the task's
  # environment (the fixture task's env sources a stand-in activate that sets SWE_TASKENV and, as conda's does, fails
  # when given the file's path as an argument; a file run outside it cannot import the task's packages):
  # by python3 when that python3 has no pytest (a pytest that cannot be imported), else by python3 -m pytest (a
  # stand-in pytest that notes its arguments).
  local fc d=$T/$CASE/py; fc=$(jq -r '.test.fileCommand // ""' "$SWE_FX/pack.seen")
  mkdir -p "$d/nopytest/pytest" "$d/pytest/pytest" "$d/repo" && echo 'raise ImportError("no pytest")' > "$d/nopytest/pytest/__init__.py" && : > "$d/pytest/pytest/__init__.py" \
    && printf '%s\n' 'import sys' 'import os' 'open(sys.argv[0] + ".ran", "w").write("RAN " + os.environ.get("SWE_TASKENV", ""))' > "$d/repo/test_one.py" && echo 'raise SystemExit(1)' > "$d/repo/test_bad.py" \
    && printf '%s\n' 'import sys' 'import swepkg' 'open("pytest.args", "w").write(" ".join(sys.argv[1:]) + " " + swepkg.WHERE)' > "$d/pytest/pytest/__main__.py" || fail "the test files were not made"
  # Bug: the image installs the task's package from its own checkout (/testbed), so a file run from the card's worktree
  # imported the image's copy, without the card's fix, and the fix was rejected. $d/image stands in for that install (on
  # PYTHONPATH, which Python reads before site-packages, so the worktree's copies must come first to win): a package in
  # the worktree's src/ (as Flask's is), imported by the pytest run, and that one with one at the worktree's root,
  # imported by a python3 run of a file in a subfolder.
  mkdir -p "$d/image/swepkg" "$d/image/rootpkg" "$d/repo/src/swepkg" "$d/repo/rootpkg" "$d/repo/tests" \
    && for x in image/swepkg image/rootpkg repo/src/swepkg repo/rootpkg; do echo "WHERE = '${x%%/*}'" > "$d/$x/__init__.py"; done \
    && printf '%s\n' 'import swepkg, rootpkg' 'open("where", "w").write(swepkg.WHERE + " " + rootpkg.WHERE)' > "$d/repo/tests/test_where.py" || fail "the package copies were not made"
  ( cd "$d/repo" && PYTHONPATH=$d/nopytest CONVEYOR_TEST_FILE=test_one.py bash -c "$fc"' "$CONVEYOR_TEST_FILE"' ) && [ "$(cat "$d/repo/test_one.py.ran" 2>&1)" = 'RAN testbed' ] \
    || fail "the pack's test.fileCommand did not run the named test file with python3 in the task's environment: $fc $(cat "$d/repo/test_one.py.ran" 2>&1)"
  ! ( cd "$d/repo" && PYTHONPATH=$d/nopytest bash -c "$fc"' "$1"' _ test_bad.py ) || fail "the pack's test.fileCommand passed a failing test file: $fc"
  ( cd "$d/repo" && PYTHONPATH=$d/pytest:$d/image bash -c "$fc"' "$1"' _ test_one.py ) && [ "$(cat "$d/repo/pytest.args" 2>&1)" = 'test_one.py repo' ] \
    || fail "the pack's test.fileCommand did not run the named test file with pytest, on the worktree's src/ copy of the package, where pytest is installed: $fc $(cat "$d/repo/pytest.args" 2>&1)"
  ( cd "$d/repo" && PYTHONPATH=$d/nopytest:$d/image bash -c "$fc"' "$1"' _ tests/test_where.py ) && [ "$(cat "$d/repo/where" 2>&1)" = 'repo repo' ] \
    || fail "the pack's test.fileCommand ran the named test file on the image's copy of the package, not the worktree's: $fc $(cat "$d/repo/where" 2>&1)"
  # Bug: the Python files a card's test run writes (__pycache__/, *.pyc) were in the trial's change.
  ! grep -qE '__pycache__|\.pyc' "$B"/results/conveyor-seats-*-"$EB/$(sweorder | head -n 1).patch" && grep -q '^+fixed' "$B"/results/conveyor-seats-*-"$EB/$(sweorder | head -n 1).patch" \
    || fail "the trial's change holds Python's generated files: $(cat "$B"/results/conveyor-seats-*-"$EB/$(sweorder | head -n 1).patch" 2>&1)"
  # Bug: the container was given the arm file's logins only, so the Codex builder seat had no Codex login there.
  [ "$(cat "$SWE_FX/codex.seen" 2>/dev/null)" = CODEX-LOGIN ] || fail "the Codex seat's container had no Codex login"
  # Bug: the engine in the container gave its Codex sessions Codex's own sandbox (-s read-only), which cannot start a
  # command in the task's container, so the review read nothing and the card blocked.
  [ "$(cat "$SWE_FX/sandbox.seen" 2>&1)" = --dangerously-bypass-approvals-and-sandbox ] \
    || fail "the engine in the benchmark's container kept Codex's own sandbox: $(cat "$SWE_FX/sandbox.seen" 2>&1)"
  [ -n "$(cat "$B"/results/conveyor-seats-*-"$EB/$(sweorder | head -n 1).json" 2>/dev/null)" ] || fail "the seats arm's results are not kept apart from the conveyor arm's: $(ls "$B/results")"
}

# Bug: the conveyor arm's preflight asked for a Codex login on a project whose seats all use Claude, so the default
# arm could not run on a machine with no Codex login. A seat on Codex still needs one. The Tests seat serves
# `testaction`, which the benchmark's `run 1` does not start: a Codex Tests seat asked for a Codex login too.
t_swearmlogin() {
  swe; local out
  rm "$CODEX_HOME/auth.json"
  jq -c '.model = {cli: "claude", model: "m"} | .reviewer = {cli: "claude", model: "m"} | .judgeOn = false | .tests = {cli: "codex", model: "x"}' "$ST/control.json" > "$ST/c.new" && mv "$ST/c.new" "$ST/control.json"
  jq '.seats = {model: {cli: "codex", model: "x"}}' "$SWE_FX/arms/conveyor.json" > "$SWE_FX/arms/conveyor-seats.json"
  out=$(loop bench swe arms check conveyor conveyor-seats 2>&1)
  grep -q "^conveyor: ready$" <<<"$out" || fail "the conveyor arm on Claude seats asked for a Codex login: $out"
  grep -q "^conveyor-seats: failed: no codex login on this machine" <<<"$out" || fail "an arm with a Codex seat passed with no Codex login: $out"
  # Bug: a run took the passed check from before the reviewer moved to Codex, and its task's container could not be made.
  jq -c '.reviewer = {cli: "codex", model: "x"}' "$ST/control.json" > "$ST/c.new" && mv "$ST/c.new" "$ST/control.json"
  out=$(loop bench swe 1 2>&1) && fail "the run started with a Codex seat and no Codex login: $out"
  grep -q "the arm conveyor cannot run: its preflight failed: no codex login on this machine" <<<"$out" || fail "the run reused the check from before the seat moved to Codex: $out"
  # Bug: the judge's CLI was not counted, so a judge on Codex over Claude seats ran with no Codex login.
  jq -c '.reviewer = {cli: "claude", model: "m"} | .judgeOn = true | .judge = {cli: "codex", model: "x"}' "$ST/control.json" > "$ST/c.new" && mv "$ST/c.new" "$ST/control.json"
  out=$(loop bench swe arms check conveyor 2>&1)
  grep -q "^conveyor: failed: no codex login on this machine" <<<"$out" || fail "the arm with a Codex judge passed with no Codex login: $out"
  # Bug: the logins followed the host's judge switch, not the saved arm's policy: an arm that turns the Codex judge off
  # was refused, and one that turns it on over a host judge that is off was given no Codex login.
  local off on
  off=$(loop bench swe arms save 'Judge off' '{"kind":"conveyor","policy":{"judgeOn":false}}' 2>&1) || fail "the arm was not saved: $off"
  on=$(loop bench swe arms save 'Judge on' '{"kind":"conveyor","policy":{"judgeOn":true}}' 2>&1) || fail "the arm was not saved: $on"
  out=$(loop bench swe arms check "$off" 2>&1)
  grep -q "^$off: ready$" <<<"$out" || fail "an arm with its judge off asked for the Codex judge's login: $out"
  jq -c '.judgeOn = false' "$ST/control.json" > "$ST/c.new" && mv "$ST/c.new" "$ST/control.json"
  out=$(loop bench swe arms check "$on" 2>&1)
  grep -q "^$on: failed: no codex login on this machine" <<<"$out" || fail "an arm that turns the Codex judge on passed with no Codex login: $out"
}

# Bug: the conveyor arm's preflight passed in a container whose jq is older than 1.8, so the engine ran on a jq it
# does not support there and failed in the run, not in the preflight.
t_swearmjq() {
  swe; local out
  jq '.install = "mkdir -p ~/.local/bin && printf \"#!/bin/sh\\necho jq-1.7.1\\n\" > ~/.local/bin/jq && chmod +x ~/.local/bin/jq"' \
    "$SWE_FX/arms/conveyor.json" > "$SWE_FX/arms/conveyor-oldjq.json" || fail "the arm was not made"
  out=$(loop bench swe arms check conveyor-oldjq 2>&1) && fail "the preflight passed with jq 1.7.1 in the container: $out"
  grep -q "^conveyor-oldjq: failed: on the trivial task, its preflight command failed: .*jq-1\.7\.1: Conveyor needs jq 1\.8 or newer" <<<"$out" \
    || fail "the failed preflight does not name the container's jq version: $out"
}

# Bug: the seats were worked out on this host's models, so on a host with no Codex and a pack that lists no models the
# default reviewer was Claude's, while in the container, where the arm installs Codex, the same default is Codex's:
# the arm passed with no Codex login and its container had none.
t_swearmdefault() {
  swe; local out p='' d
  rm "$CODEX_HOME/auth.json" "$STUB/codex"
  for d in ${PATH//:/ }; do [ -x "$d/codex" ] || p+=$d:; done
  tune 'del(.models.allowed)'
  jq -c '.model = {cli: "claude", model: "claude-opus-5-5"} | del(.reviewer) | .judgeOn = false' "$ST/control.json" > "$ST/c.new" && mv "$ST/c.new" "$ST/control.json"
  out=$(PATH=${p%:} loop bench swe arms check conveyor 2>&1)
  grep -q "^conveyor: failed: no codex login on this machine" <<<"$out" || fail "the default reviewer, Codex's in the container, asked for no Codex login: $out"
}
