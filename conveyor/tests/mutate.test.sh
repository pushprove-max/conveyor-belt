#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 300
# Engine cases: the mutation checks of test files (lib/mutate.sh): `conveyor.sh mutate <test file>`, a check that
# gives way to the cards, and the idle queue's order. The loop's idle job, and no card step that runs a check, are in
# mutidle.test.sh, which uses the mu* helpers below.
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"

# The helpers are named mu*: every case file is sourced into one shell, so a name another file uses would replace its.
# The setup of a check: a pool of one test slot of the case's own; main holds src.sh, whose line 3 is
# `if [ "$a" -lt 3 ]`, k.test.sh, which checks the boundary (2 is small, 3 is big), and s.test.sh, which calls the
# function and asserts nothing. Each sources src.sh by a path that starts with $(dirname "$0"). The test command runs
# the file its list names, after it writes the line the mutant changed (base with none) to $STUB/mut-runs, and, as a
# runner that selects tests by the change does, with a change every other test file its list does not name as passed;
# with $STUB/mut-hold, its third run is a card of another project that asks for a slot: it holds an ask in the shared
# pool (slot_ask()), then runs until it is ended ($STUB/mut-pid). A card's own test run writes to $STUB/asks a line
# for each ask the pool holds.
musetup() {
  export XDG_CONFIG_HOME=$T/$CASE/config
  mkdir -p "$XDG_CONFIG_HOME/conveyor" && echo "{\"testSlots\": 1, \"testSlotsDir\": \"$T/$CASE/slots\"}" > "$XDG_CONFIG_HOME/conveyor/host.json" \
    || fail "the host file was not written"
  setup "${1:-[]}"
  printf '%s\n' 'small() {' '  local a=$1' '  if [ "$a" -lt 3 ]; then echo small; else echo big; fi' '}' > "$R/src.sh"
  printf '%s\n' '. "$(dirname "$0")/src.sh"' '[ "$(small 2)" = small ] && [ "$(small 3)" = big ]' > "$R/k.test.sh"
  printf '%s\n' '. "$(dirname "$0")/src.sh"' 'small 2 > /dev/null' > "$R/s.test.sh"
  git -C "$R" add src.sh k.test.sh s.test.sh && git -C "$R" commit -qm 'a source and its tests' || fail "main's files"
  cat > "$STUB/mut-cmd" <<'EOF'
f=$(sed -n 's/^fail\t//p' "$CONVEYOR_TEST_RERUN")
d=$(git diff -U0 | grep '^+' | grep -v '^+++' | cut -c2-); echo "${d:-base}" >> "$STUB/mut-runs"
if [ -e "$STUB/mut-hold" ] && [ "$(wc -l < "$STUB/mut-runs")" -ge 3 ]; then
  rm -f "$STUB/mut-hold"; echo $$ > "$STUB/mut-pid"; mkdir -p "$STUB/../slots/asks"; exec 7>> "$STUB/../slots/asks/$$"; flock 7
  while :; do sleep 0.1; done # sleep: a card's test run, which runs until the check ends it
fi
rc=0; bash "$f" || rc=1
if [ -n "$d" ]; then for t in $(git ls-files '*.test.sh'); do
  [ "$t" != "$f" ] && ! grep -qxF $'pass\t'"$t" "$CONVEYOR_TEST_RERUN" || continue; bash "$t" || rc=1
done; fi
exit $rc
EOF
  echo 'case $PWD in */cards/mutate/*) . "$STUB/mut-cmd" ;; *) echo x >> "$STUB/tests"
    for a in "$STUB"/../slots/asks/[0-9]*; do [ -e "$a" ] && ! flock -n "$a" true && echo asked; done >> "$STUB/asks"; : ;; esac' > "$STUB/test-cmd"
  mkdir -p "$T/$CASE/cards"
}
muone() { jq -c "${@:2}" "$1" "$ST"/testactions/mutations/*.json; } # <jq filter> [jq options]: of the one check's record
muof() { jq -c --arg f "$1" "select(.file == \$f) | $2" "$ST"/testactions/mutations/*.json; } # <test file> <jq filter>: of that file's check's record
mufree() { flock -n "$T/$CASE/slots/1" true; } # the pool's one slot is free
# The engine's functions as `serve` loads them, in a shell of the case's main: <function> run there. The runner's own
# pool (SLOT_DIR, where the runner's test run asks for a slot) is dropped, so the shell reads the case's pool.
mu_in() { ( unset SLOT_DIR; export CONVEYOR_MAIN=$R CONVEYOR_CARDS=$T/$CASE/cards; . "$SRC/conveyor.sh" state-dir > /dev/null \
  && eval "$(grep '^\. "\$HERE/lib/' "$SRC/commands/serve.sh")" && "$@" ); }

# D2. Bugs this guards: a mutant started while a card is in its test step, a test run of another project (which shares
# the test slots) asks for a slot, or the load is not below the Load limit; a mutant that went on, or kept the test
# slot, when another project's card asked for one; a check that began again from its first mutant, or drew new ones,
# when it resumed.
t_mutyield() {
  musetup; local out i ms ap
  echo '{"step": "test"}' > "$T/$CASE/cards/c-1.live"
  out=$(loop mutate k.test.sh 2>&1) || fail "the check failed: $out"
  [ "$(muone '[.state, .reason, .base, .tried]')" = '["stopped","card c-1 is in its test step",null,0]' ] && [ ! -e "$STUB/mut-runs" ] \
    || fail "a run started with a card in its test step: $(muone .), $(cat "$STUB/mut-runs" 2>&1)"
  rm "$T/$CASE/cards/c-1.live"; jq '.maxLoad = 0' "$XDG_CONFIG_HOME/conveyor/host.json" > "$STUB/h" && mv "$STUB/h" "$XDG_CONFIG_HOME/conveyor/host.json"
  out=$(loop mutate k.test.sh 2>&1) || fail "the check failed: $out"
  [ "$(muone '[.state, (.reason | startswith("the load ")), .tried]')" = '["stopped",true,0]' ] && [ ! -e "$STUB/mut-runs" ] \
    || fail "a run started with the load not below the Load limit: $(muone .)"
  jq 'del(.maxLoad)' "$XDG_CONFIG_HOME/conveyor/host.json" > "$STUB/h" && mv "$STUB/h" "$XDG_CONFIG_HOME/conveyor/host.json"
  # A test run of another project, which this project's cards folder does not show, holds an ask in the shared pool.
  mkdir -p "$T/$CASE/slots/asks" && { ( exec 7>> "$T/$CASE/slots/asks/99"; flock 7; exec tail -f /dev/null ) & ap=$!; }
  wait_until "! flock -n '$T/$CASE/slots/asks/99' true" || fail "the other project's ask was not held"
  out=$(loop mutate k.test.sh 2>&1); kill "$ap"; wait "$ap" 2>/dev/null
  [ "$(muone '[.state, .reason, .tried]')" = '["stopped","1 test run(s) on this machine ask for a test slot or hold one",0]' ] && [ ! -e "$STUB/mut-runs" ] \
    || fail "a run started while another project's test run asked for a slot: $(muone .), $out"
  ms=$(muone '.mutants'); : > "$STUB/mut-hold"
  out=$(loop mutate k.test.sh 2>&1) || fail "the check failed: $out"
  [ "$(muone '[.state, .reason, .base, .next, .tried]')" = '["stopped","1 test run(s) on this machine ask for a test slot or hold one","pass",1,1]' ] \
    || fail "the check did not stop at its second mutant when another project's card asked for a slot: $(muone .)"
  ! kill -0 "$(cat "$STUB/mut-pid")" 2>/dev/null && mufree || fail "the stopped mutant still runs, or holds the test slot"
  i=$(wc -l < "$STUB/mut-runs")
  out=$(loop mutate k.test.sh 2>&1) || fail "the check failed: $out"
  [ "$(muone '[.state, .tried, .killed, .mutants == $ms]' --argjson ms "$ms")" = '["done",3,3,true]' ] || fail "the check did not resume and end with its own mutants: $(muone .)"
  [ "$(sed -n "$((i + 1))p" "$STUB/mut-runs")" = "$(jq -r '.[1].after' <<<"$ms")" ] && [ "$(wc -l < "$STUB/mut-runs")" = $((i + 2)) ] \
    || fail "the check did not resume from its next mutant: $(cat "$STUB/mut-runs")"
}

# The Board's Mutation check (#79): `mutate ask` puts files at the front of the idle queue, the newest ask first, and
# the idle job checks them even when it found its queue empty on main's commit. Bugs this guards: an ask that took a
# file that is not a test file of main, put a file behind those asked before, started a check itself, or that the idle
# job never read; an asked file left on the list after its check.
# D1. The same two checks guard a check itself (mutrun()). Of k.test.sh: one that found no source the test file sources
# by a $(dirname "$0") path, changed main's own checkout, left its copy of main, or counted a mutant the boundary test
# kills as one that survived. Of s.test.sh: a survivor recorded with no line or change, or one the Tests part of the
# snapshot (and so dashboard.sh's tests part) does not carry; a mutant counted as killed by k.test.sh, which the
# mutant's change selects beside s.test.sh, as the test command picks tests.
t_mutask() {
  musetup; local out
  out=$(loop mutate ask k.test.sh src.sh 2>&1); [ $? = 2 ] && [ ! -s "$ST/testactions/mutations/asked" ] || fail "an ask with a file that is not a test file was taken: $out"
  out=$(loop mutate ask s.test.sh 2>&1) && out=$(loop mutate ask k.test.sh 2>&1) || fail "an ask was refused: $out"
  [[ $out == *"front of the idle queue. A check starts only when no card needs a test slot."* ]] || fail "the ask's answer: $out"
  [ "$(mu_in testspart 2026-11-09 | jq -c '[.files[] | [.file, .mutationPlace]] | sort')" = '[["k.test.sh",1],["s.test.sh",2]]' ] && [ ! -e "$STUB/mut-runs" ] \
    || fail "the asked files' places, or the ask started a check: $(mu_in testspart 2026-11-09 | jq -c '[.files[] | [.file, .mutationPlace]]')"
  git -C "$R" rev-parse HEAD > "$ST/testactions/mutations/idle"
  mu_in eval 'names && mutnext' > /dev/null 2>&1
  [ "$(jq -cs 'map([.file, .state]) | sort' "$ST"/testactions/mutations/*.json)" = '[["k.test.sh","done"],["s.test.sh","done"]]' ] && [ ! -s "$ST/testactions/mutations/asked" ] \
    || fail "the idle job did not check the asked files, or left them asked: $(cat "$ST"/testactions/mutations/*.json "$ST/testactions/mutations/asked")"
  [ "$(muof k.test.sh '[.state, .base, (.mutants | length), .tried, .killed, (.survived | length), .noresult]')" = '["done","pass",3,3,3,0,0]' ] \
    || fail "the boundary test did not kill each of its 3 mutants: $(muof k.test.sh .)"
  [ "$(muof k.test.sh '[.mutants[] | select(.kind == "flip") | [.source, .line, .after]]')" = '[["src.sh",3,"  if [ \"$a\" -ge 3 ]; then echo small; else echo big; fi"]]' ] \
    || fail "the flipped comparison was not among the mutants: $(muof k.test.sh .mutants)"
  [ "$(muof k.test.sh '[(.seed | type), (.blobs | keys)]')" = '["number",["k.test.sh","src.sh"]]' ] || fail "the record has no seed, or not the blobs of the file and its source: $(muof k.test.sh .)"
  git -C "$R" diff --quiet && [ "$(git -C "$R" worktree list | wc -l)" = 1 ] && [ -z "$(ls "$T/$CASE/cards/mutate" 2>/dev/null)" ] \
    || fail "main's checkout was changed, or the copy the check ran in was left: $(git -C "$R" status --short; git -C "$R" worktree list)"
  [ "$(muof s.test.sh '[.state, .tried, .killed, (.survived | length)]')" = '["done",3,0,3]' ] || fail "the test with no assertion did not let its mutants survive: $(muof s.test.sh .)"
  [ "$(muof s.test.sh '.survived[] | select(.kind == "flip") | [.source, .line, .before, .after]')" = '["src.sh",3,"  if [ \"$a\" -lt 3 ]; then echo small; else echo big; fi","  if [ \"$a\" -ge 3 ]; then echo small; else echo big; fi"]' ] \
    || fail "the record does not list the flipped comparison as a survivor, with its line and change: $(muof s.test.sh .survived)"
  [ "$(mu_in testspart 2026-11-09 | jq -c '.files[] | select(.file == "s.test.sh") | .mutation | [.state, .tried, (.survived | length), .seed == ($s | tonumber)]' --arg s "$(muof s.test.sh .seed)")" = '["done",3,3,true]' ] \
    || fail "the Tests part does not carry the file's newest check: $(mu_in testspart 2026-11-09 | jq -c '.files[] | select(.file == "s.test.sh")')"
}

# D3. Bug this guards: a queue that did not put first the files the Tests page flags. On main, n.test.sh has 20 runs
# on record and never caught anything; a.test.sh is unflagged and was never checked, so it would go first by age; its
# check is older than any, but its file changed since. c.test.sh was checked on the blobs main has now: it is not queued.
t_mutqueue() {
  musetup; local b
  touch "$R/a.test.sh" "$R/n.test.sh" "$R/c.test.sh" && git -C "$R" add . && git -C "$R" commit -qm 'more tests' || fail "main's test files"
  b=$(git -C "$R" rev-parse HEAD:c.test.sh)
  mkdir -p "$ST/testactions/mutations" && jq -cn --arg b "$b" '{id: "1", file: "n.test.sh", at: "2026-01-01T00:00:00Z", state: "done", blobs: {"n.test.sh": "0"}},
      {id: "2", file: "c.test.sh", at: "2026-01-02T00:00:00Z", state: "done", blobs: {"c.test.sh": $b}}' \
    | while read -r l; do printf '%s\n' "$l" > "$ST/testactions/mutations/$(jq -r .id <<<"$l").json"; done
  jq -cn 'range(20) | {card: "c-\(.)", issue: 1, step: "test", time: "2026-11-10T12:00:00Z", result: "pass", sha: "", reason: "", times: {"n.test.sh": 1}}' >> "$ST/cards.jsonl"
  [ "$(mu_in mutqueue "$(git -C "$R" rev-parse HEAD)" | paste -sd' ' -)" = 'n.test.sh a.test.sh k.test.sh s.test.sh' ] \
    || fail "the queue's order: $(mu_in mutqueue "$(git -C "$R" rev-parse HEAD)" | paste -sd' ' -)"
}
