#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 120
# Engine cases: an arm's check (`conveyor.sh bench swe arms check`, swe_arms.sh) and the state History, `bench swe
# arms` and Start read of it: the check's record from its start (checking, with its step) to its end (ready, or failed
# with why), one check shared by the requests made while it runs, and the one readiness decision that keeps an arm
# from reading ready on a pass the run would not take. The fixture is swebench.test.sh's swe().
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"

# Bugs: a check wrote its state only at its end, so while it ran the arm read "not checked" and nothing said the check
# was going or where it was; a second request of the same arm while one ran started a second check in the same
# sandbox, on its own container. Here stub-slow's preflight command waits while $SWE_FX/phold is there, and
# stub-slowfail's does the same, then fails.
t_swecheckheld() {
  swe; local o p1 p2 id
  jq --arg p "$(jq -r .preflight "$SWE_FX/arms/stub-slow.json")"'; [ ! -e "$SWE_FX/pfail" ] || { echo PFAIL-SAID; exit 1; }' '.preflight = $p | .label = "Stub slowfail"' \
    "$SWE_FX/arms/stub-slow.json" > "$SWE_FX/arms/stub-slowfail.json" && : > "$SWE_FX/phold" && : > "$SWE_FX/pfail" || fail "the held arms were not made"
  loop bench swe arms check stub-slow stub-slowfail > "$T/$CASE/one.out" 2>&1 & p1=$!
  wait_until "jq -e '.state == \"checking\" and .step == \"Checking its tools and logins\"' '$B/preflight/stub-slow/stub-slow.json'" "cat '$T/$CASE/one.out'" \
    || fail "the held check's record does not say it is checking its tools"
  # Both arms read as checking while the first is held: the second was admitted at once and waits its turn.
  o=$(loop bench swe history 2>&1); [ "$(jq -c '[.arms[] | select(.name | startswith("stub-slow")) | [.name, .state, .step]]' <<<"$o")" \
    = '[["stub-slow","checking","Checking its tools and logins"],["stub-slowfail","checking","Waiting for the arms named before it"]]' ] \
    || fail "history does not show the held checks as checking, with their steps: $(jq -c '.arms' <<<"$o" | head -c 600)"
  o=$(loop bench swe arms 2>&1); grep -q '^stub-slow (Stub slow, agent): checking (k[0-9T-]*): Checking its tools and logins$' <<<"$o" \
    || fail "the arms list does not show the check that runs: $o"
  # A second request of stub-slow while its check runs joins it: the same check ID, no second container.
  id=$(sed -n 's/^stub-slow: checking //p' "$T/$CASE/one.out"); [ -n "$id" ] || fail "the check printed no ID when it was admitted: $(cat "$T/$CASE/one.out")"
  loop bench swe arms check stub-slow > "$T/$CASE/two.out" 2>&1 & p2=$!
  wait_until "grep -q '^stub-slow: ' '$T/$CASE/two.out'" || fail "the second request said nothing on admission"
  [ "$(cat "$T/$CASE/two.out")" = "stub-slow: checking $id" ] || fail "the second request did not join the check that runs: $(cat "$T/$CASE/two.out") (first: $id)"
  rm "$SWE_FX/phold"; wait "$p1"; wait "$p2"
  grep -qx 'stub-slow: ready' "$T/$CASE/one.out" && grep -qx 'stub-slow: ready' "$T/$CASE/two.out" \
    || fail "the released check did not answer ready to both requests: $(cat "$T/$CASE/one.out") | $(cat "$T/$CASE/two.out")"
  grep -q '^stub-slowfail: failed: on the trivial task, its preflight command failed: PFAIL-SAID' "$T/$CASE/one.out" \
    || fail "the released check that failed does not say why: $(cat "$T/$CASE/one.out")"
  [ "$(grep -c '^create .*-check-stub-slow-preflight ' "$SWE_FX/docker.log")" = 1 ] || fail "the two requests ran two checks: $(grep '^create ' "$SWE_FX/docker.log")"
  o=$(loop bench swe history 2>&1); [ "$(jq -c --arg id "$id" '[.arms[] | select(.name | startswith("stub-slow")) | [.name, .state, .step, (.check == $id), (.why // "" | test("PFAIL-SAID"))]]' <<<"$o")" \
    = '[["stub-slow","ready",null,true,false],["stub-slowfail","failed",null,false,true]]' ] \
    || fail "history does not show the ended checks, ready and failed with why: $(jq -c '.arms' <<<"$o" | head -c 600)"
}

# Bugs (review E1): a request made while a check of its arm ran on another task set printed that check's ID, then took
# its answer, though its own set was not checked (the set was not part of the request); when it did start its own
# check, it printed no ID for it. Here the other set's seed puts the same task first: the same image, so only the set
# tells the two requests apart.
t_swecheckother() {
  swe; local s f0 id; f0=$(sweorder | head -n 1)
  for s in s1 s2 s3 s4 s5 s6 s7 s8; do [ "$(sweorder "$s" | head -n 1)" != "$f0" ] || break; done
  [ "$(sweorder "$s" | head -n 1)" = "$f0" ] || fail "no seed of s1 to s8 puts the same task first"
  : > "$SWE_FX/phold" || fail "the hold was not made"
  loop bench swe arms check stub-slow > "$T/$CASE/one.out" 2>&1 & local p1=$!
  wait_until "jq -e '.state == \"checking\" and .step == \"Checking its tools and logins\"' '$B/preflight/stub-slow/stub-slow.json'" "cat '$T/$CASE/one.out'" \
    || fail "the held check's record does not say it is checking its tools"
  id=$(sed -n 's/^stub-slow: checking //p' "$T/$CASE/one.out"); [ -n "$id" ] || fail "the held check printed no ID: $(cat "$T/$CASE/one.out")"
  loop bench swe arms check --settings "{\"seed\": \"$s\"}" stub-slow > "$T/$CASE/two.out" 2>&1 & local p2=$!
  wait_until "grep -q '^stub-slow: ' '$T/$CASE/two.out'" || fail "the second request said nothing on admission"
  [ "$(cat "$T/$CASE/two.out")" = "stub-slow: waiting for the check of the arm that runs now" ] \
    || fail "a request of another task set was given the ID of the check that runs: $(cat "$T/$CASE/two.out") (that check: $id)"
  rm "$SWE_FX/phold"; wait "$p1"; wait "$p2"
  [ "$(sed -n 2p "$T/$CASE/two.out" | grep -c '^stub-slow: checking k')" = 1 ] && [ "$(sed -n 2p "$T/$CASE/two.out")" != "stub-slow: checking $id" ] \
    && [ "$(sed -n 3p "$T/$CASE/two.out")" = "stub-slow: ready" ] || fail "the request of another task set did not print its own check's ID, then its answer: $(cat "$T/$CASE/two.out")"
  [ "$(grep -c '^create .*-check-stub-slow-preflight ' "$SWE_FX/docker.log")" = 2 ] || fail "the request of another task set took the other set's check: $(grep '^create ' "$SWE_FX/docker.log")"
  jq -e --arg s "$s" '.state == "ready" and .set.seed == $s' "$B/preflight/stub-slow/stub-slow.json" > /dev/null || fail "its own check's record is not of its set: $(cat "$B/preflight/stub-slow/stub-slow.json")"
}

# Bug (review): a request made while a check of its arm fetched its image printed that check's ID, then, when the fetch
# failed, matched the check on the image its own setup could not learn, so it ran a second check and printed a second
# ID. Here the image fetch waits while $SWE_FX/ihold is there, then fails.
t_swecheckimage() {
  swe; local i id; i=img-$(sweorder | head -n 1)
  echo "$i" > "$SWE_FX/broken" && : > "$SWE_FX/ihold" || fail "the outage was not made"
  loop bench swe arms check stub-a > "$T/$CASE/one.out" 2>&1 & local p1=$!
  wait_until "jq -e '.state == \"checking\" and .step == \"Fetching the test image\"' '$B/preflight/stub-a/stub-a.json'" "cat '$T/$CASE/one.out'" \
    || fail "the check's record does not say it fetches the image"
  id=$(sed -n 's/^stub-a: checking //p' "$T/$CASE/one.out"); [ -n "$id" ] || fail "the check printed no ID: $(cat "$T/$CASE/one.out")"
  loop bench swe arms check stub-a > "$T/$CASE/two.out" 2>&1 & local p2=$!
  wait_until "grep -q '^stub-a: ' '$T/$CASE/two.out'" || fail "the second request said nothing on admission"
  rm "$SWE_FX/ihold"; wait "$p1"; wait "$p2"
  [ "$(cat "$T/$CASE/two.out")" = "$(printf 'stub-a: checking %s\nstub-a: failed: the base image %s could not be fetched' "$id" "$i")" ] \
    || fail "the second request did not give the answer of the check whose ID it printed: $(cat "$T/$CASE/two.out") (that check: $id)"
  jq -e --arg id "$id" '.id == $id and .state == "failed"' "$B/preflight/stub-a/stub-a.json" > /dev/null \
    || fail "a second check replaced the one both requests named: $(cat "$B/preflight/stub-a/stub-a.json")"
}

# Bugs: History showed an arm ready on a pass Start would not take: one over a day old, one before a seat moved to
# another CLI, one of an engine commit that is no longer main's, or one from before a check that failed in its setup
# (its image could not be fetched), which wrote no record; and a check whose process was gone read as checking.
t_swecheckstale() {
  swe; local o i lim dead
  i=img-$(sweorder | head -n 1); lim=$(jq -c '{cpus: .limits.cpus, memory: .limits.memory, taskTimeout}' "$SRC/bench/swe.json")
  swepass() { # <arm> <key> <logins> [checking]: a record of a pass now on the run's image, limits and task set, or of a check that runs
    mkdir -p "$B/preflight/$1" && jq -cn --arg k "$2" --arg l "$3" --arg st "${4:-ready}" --argjson e "$(date +%s)" --arg i "$i" --argjson lim "$lim" --argjson p "$dead" \
      --argjson set "$(jq -c '{dataset, revision, seed}' "$SRC/bench/swe.json")" \
      --argjson s "$(jq -cS --arg n "$1" '.name = $n' "$SWE_FX/arms/$1.json")" '{id: "k1", arm: $s.name, key: $k, state: $st, ok: ($st == "ready"), why: null,
      at: "2026-11-19T00:00:00Z", epoch: $e, spec: $s, logins: $l, image: $i, limits: $lim, set: $set} + (if $st == "checking" then {pid: $p, step: "Running the trivial task"} else {} end)' > "$B/preflight/$1/$2.json"
  }
  bash -c 'exit 0' & dead=$!; wait "$dead" # a process that is gone
  cp "$SWE_FX/arms/conveyor.json" "$SWE_FX/arms/conveyor-b.json"
  # conveyor-b passed on v1.0.0's engine, with the logins it takes once the reviewer moves (below): only its commit is not main's.
  # stub-seed passed on the same image and limits, but of another task set (review E1: the set was not compared).
  cp "$SWE_FX/arms/stub-quiet.json" "$SWE_FX/arms/stub-seed.json"
  swepass stub-a stub-a claude && swepass stub-quiet stub-quiet claude && swepass stub-b stub-b claude checking && swepass conveyor-b "conveyor-b-$EA" claude \
    && swepass stub-seed stub-seed claude && jq -c '.set.seed = "another-seed"' "$B/preflight/stub-seed/stub-seed.json" > "$B/s.new" \
    && mv "$B/s.new" "$B/preflight/stub-seed/stub-seed.json" || fail "the records were not written"
  echo "$i" > "$SWE_FX/broken"
  o=$(loop bench swe arms check stub-a 2>&1) && fail "the check passed with no image: $o"
  grep -qx "stub-a: failed: the base image $i could not be fetched" <<<"$o" || fail "the check does not say the image could not be fetched: $o"
  # Solo's pass from the fixture is a day and a minute old; the conveyor arm's reviewer moves from Codex to Claude.
  jq -c --argjson e "$(($(date +%s) - 86460))" '.epoch = $e' "$B/preflight/solo/solo-m.json" > "$B/s.new" && mv "$B/s.new" "$B/preflight/solo/solo-m.json" \
    && jq -c '.reviewer = {cli: "claude", model: "m"} | .judgeOn = false' "$ST/control.json" > "$ST/c.new" && mv "$ST/c.new" "$ST/control.json" || fail "the records were not changed"
  o=$(loop bench swe history 2>&1)
  [ "$(jq -c '[.arms[] | select(.name | IN("solo", "conveyor", "conveyor-b", "stub-a", "stub-b", "stub-quiet", "stub-seed")) | [.name, .state, .why]]' <<<"$o")" \
    = "$(jq -nc --arg i "$i" '[["conveyor-b","changed",null],["conveyor","changed",null],["solo","expired",null],["stub-a","failed","the base image \($i) could not be fetched"],
      ["stub-b","failed","the check stopped before it ended"],["stub-quiet","ready",null],["stub-seed","changed",null]]')" ] \
    || fail "history reads an arm ready on a pass the run would not take: $(jq -c '[.arms[] | [.name, .state, .why]]' <<<"$o")"
}

# Bug (#1016): a conveyor arm's engine run writes to its loop log, not to the command's stderr, so when it exited 1
# the reason read the empty stderr and said nothing of why. Here the fixture engine exits 1 with a line in its log.
t_swecheckenginefail() {
  swe; local o
  : > "$SWE_FX/efail" || fail "the failing engine was not set"
  o=$(loop bench swe arms check conveyor 2>&1) && fail "the check passed with an engine run that exited 1: $o"
  grep -q "^conveyor: failed: on the trivial task, its command failed (exit 1): ENGINE-FAIL-SAID" <<<"$o" \
    || fail "the reason does not hold the last line of the engine's loop log: $o"
}

# Bug (#1025): an engine version whose card blocked in the container (its commit refused there) failed its check with
# "changed no file" alone, so the Benchmarks page did not say why that version cannot run. Here the card blocks.
t_swecheckblocked() {
  swe; local o
  : > "$SWE_FX/eblock" || fail "the blocking engine was not set"
  o=$(loop bench swe arms check conveyor 2>&1) && fail "the check passed with a card that changed nothing: $o"
  grep -q "^conveyor: failed: it ran the trivial task headless but changed no file; its card ended at its blocked step (blocked): commit: git: 'hook' is not a git command" <<<"$o" \
    || fail "the reason does not give the card's last step and its reason: $o"
}

# Bug (R44): a request that joined a check read the answer at the record of the arm's key, which a check of other
# settings (the key does not name them) can replace first: it found no answer, so it ran a check of its own and
# printed a second ID. Here the joiner is held in the check of its first arm (stub-slowb, held while $SWE_FX/bhold is
# there) while the joined check ends and a check of another taskTimeout runs and replaces the record.
# It polls three real requests: the bug is in the order they take the arm's lock, which one call cannot show.
t_swecheckjoinkept() {
  swe; local id
  jq '.preflight |= sub("phold"; "bhold") | .label = "Stub slowb"' "$SWE_FX/arms/stub-slow.json" > "$SWE_FX/arms/stub-slowb.json" \
    && : > "$SWE_FX/phold" && : > "$SWE_FX/bhold" || fail "the held arms were not made"
  loop bench swe arms check stub-slow > "$T/$CASE/one.out" 2>&1 & local p1=$!
  wait_until "jq -e '.step == \"Checking its tools and logins\"' '$B/preflight/stub-slow/stub-slow.json'" "cat '$T/$CASE/one.out'" \
    || fail "the held check's record does not say it is checking its tools"
  id=$(sed -n 's/^stub-slow: checking //p' "$T/$CASE/one.out"); [ -n "$id" ] || fail "the held check printed no ID: $(cat "$T/$CASE/one.out")"
  loop bench swe arms check stub-slowb stub-slow > "$T/$CASE/two.out" 2>&1 & local p2=$!
  wait_until "jq -e '.step == \"Checking its tools and logins\"' '$B/preflight/stub-slowb/stub-slowb.json'" "cat '$T/$CASE/two.out'" \
    || fail "the joiner's first arm is not held in its check"
  grep -qx "stub-slow: checking $id" "$T/$CASE/two.out" || fail "the request did not join the check that runs: $(cat "$T/$CASE/two.out") (that check: $id)"
  loop bench swe arms check --settings '{"taskTimeout": 7200}' stub-slow > "$T/$CASE/three.out" 2>&1 & local p3=$!
  wait_until "grep -q '^stub-slow: ' '$T/$CASE/three.out'" || fail "the request of other settings said nothing on admission"
  rm "$SWE_FX/phold"; wait "$p1"; wait "$p3"
  jq -e --arg id "$id" '.id != $id and .limits.taskTimeout == 7200 and .state == "ready"' "$B/preflight/stub-slow/stub-slow.json" > /dev/null \
    || fail "the check of other settings did not replace the joined check's record: $(cat "$B/preflight/stub-slow/stub-slow.json")"
  rm "$SWE_FX/bhold"; wait "$p2"
  [ "$(sed -n '3,$p' "$T/$CASE/two.out")" = "$(printf 'stub-slowb: ready\nstub-slow: ready')" ] \
    || fail "the joiner did not print the joined check's answer: $(cat "$T/$CASE/two.out") (joined: $id)"
  [ "$(grep -c '^create .*-check-stub-slow-preflight ' "$SWE_FX/docker.log")" = 2 ] || fail "the joiner ran a check of its own: $(grep '^create ' "$SWE_FX/docker.log")"
}

# Bug (R45): a request that waited for a check of other settings ran its setup (Docker, the harness, the image fetch)
# before it wrote its record or printed its ID, so through that setup `bench swe arms` showed the other settings'
# ended check and no ID of this one. Here the image fetch is held while $SWE_FX/ihold is there, once the first check
# is past its own. It polls two real requests: the bug is what a second process reads while the waiter is mid-setup.
t_swecheckwaitid() {
  swe; local id o
  : > "$SWE_FX/phold" || fail "the hold was not made"
  loop bench swe arms check stub-slow > "$T/$CASE/one.out" 2>&1 & local p1=$!
  wait_until "jq -e '.step == \"Checking its tools and logins\"' '$B/preflight/stub-slow/stub-slow.json'" "cat '$T/$CASE/one.out'" \
    || fail "the held check's record does not say it is checking its tools"
  loop bench swe arms check --settings '{"taskTimeout": 7200}' stub-slow > "$T/$CASE/two.out" 2>&1 & local p2=$!
  wait_until "grep -qx 'stub-slow: waiting for the check of the arm that runs now' '$T/$CASE/two.out'" "cat '$T/$CASE/two.out'" \
    || fail "the request of other settings did not wait for the check that runs"
  : > "$SWE_FX/ihold" && rm "$SWE_FX/phold" || fail "the image fetch was not held"
  wait "$p1"
  WAIT_CEILING=30 wait_until "grep -q '^stub-slow: checking ' '$T/$CASE/two.out'" "cat '$T/$CASE/two.out'" \
    || fail "the waited check printed no ID before its image fetch: $(cat "$T/$CASE/two.out")"
  id=$(sed -n 's/^stub-slow: checking //p' "$T/$CASE/two.out")
  wait_until "jq -e --arg id '$id' '.id == \$id and .step == \"Fetching the test image\"' '$B/preflight/stub-slow/stub-slow.json'" \
    "cat '$B/preflight/stub-slow/stub-slow.json'" || fail "the waited check's record does not say it fetches the image"
  o=$(loop bench swe arms 2>&1); grep -qx "stub-slow (Stub slow, agent): checking ($id): Fetching the test image" <<<"$o" \
    || fail "the arms list does not show the waited check fetching its image, with its ID $id: $o"
  rm "$SWE_FX/ihold"; wait "$p2"
  [ "$(sed -n 3p "$T/$CASE/two.out")" = "stub-slow: ready" ] || fail "the waited check did not end ready: $(cat "$T/$CASE/two.out")"
}

# Bug (R46): a check recorded the logins of its admission but tested, and gave its container, the logins read when its
# preflight ran: with the reviewer moved from Codex to Claude while the conveyor arm's check fetched its image, its
# container had no Codex login though its record, of a Codex reviewer, passed; and its sandbox's control record,
# read then too, gave the card the Claude reviewer its record did not name. Here the image fetch is held while
# $SWE_FX/ihold is there. It polls a real request: the seat must move between its admission and its preflight.
t_swecheckloginsadmit() {
  swe; local id
  : > "$SWE_FX/ihold" || fail "the image fetch was not held"
  loop bench swe arms check conveyor > "$T/$CASE/one.out" 2>&1 & local p1=$!
  wait_until "grep -q '^conveyor: checking ' '$T/$CASE/one.out'" "cat '$T/$CASE/one.out'" || fail "the check printed no ID"
  id=$(sed -n 's/^conveyor: checking //p' "$T/$CASE/one.out")
  wait_until "jq -e --arg id '$id' 'select(.id == \$id) | .step == \"Fetching the test image\" and .logins == \"claude codex\"' '$B/preflight/conveyor/'*.json" \
    "cat '$B/preflight/conveyor/'*.json" || fail "the check's record does not say it fetches the image with the Codex reviewer's logins"
  jq -c '.reviewer = {cli: "claude", model: "m"} | .judgeOn = false' "$ST/control.json" > "$ST/c.new" && mv "$ST/c.new" "$ST/control.json" || fail "the reviewer was not moved"
  rm "$SWE_FX/ihold"; wait "$p1"
  grep -qx 'conveyor: ready' "$T/$CASE/one.out" || fail "the check did not pass: $(cat "$T/$CASE/one.out")"
  [ "$(cat "$SWE_FX/codex.seen" 2>/dev/null)" = CODEX-LOGIN ] \
    || fail "the container was not given the logins of the check's admission (claude codex) but those read after the reviewer moved"
  jq -e '.reviewer.model == "x" and .reviewer.cli != "claude"' "$SWE_FX/control.seen" > /dev/null \
    || fail "the preflight's card was not given the reviewer of the check's admission (Codex, x) but $(jq -c .reviewer "$SWE_FX/control.seen" 2>&1)"
}
