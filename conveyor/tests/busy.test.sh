#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 120
# Engine cases: why the machine is busy (lib/busy.sh): `conveyor.sh why` and `conveyor.sh work` over a fixture process
# tree and card worktrees, and `why` over a real one.
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"
# The engine folder, as lib.sh sets it: named here too, so the release closure (tools/closure.sh) follows this file's paths.
SRC=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)

# <function> [<argument>...] of lib/busy.sh, given stdin, for the case's main and cards folder.
busyfn() { ( export CONVEYOR_MAIN=$R CONVEYOR_CARDS=$T/$CASE/cards; . "$SRC/conveyor.sh" state-dir > /dev/null && . "$SRC/lib/busy.sh" && . "$SRC/lib/machine.sh" && "$@" ); }

# Two cards of the case's main: c...-5 open (its records name no end, and the loop that made its worktree is this
# shell), in its build step; c...-6 closed (landed). Sets C, the cards folder as the kernel names it.
busycards() {
  setup '[]'
  mkdir -p "$T/$CASE/cards/c20261117T000001-main-5" "$T/$CASE/cards/c20261117T000002-main-6"
  C=$(cd "$T/$CASE/cards" && pwd -P)
  echo '{"step": "build", "at": "2026-11-17T00:00:01Z"}' > "$C/c20261117T000001-main-5.live"
  echo '{"step": "test", "at": "2026-11-17T00:00:02Z"}' > "$C/c20261117T000002-main-6.live"
  jq -cn --argjson p $$ --arg t "$(p_started $$)" '{card: "c20261117T000001-main-5", issue: 5, step: "picked"},
    {card: "c20261117T000001-main-5", issue: 5, step: "worktree", pid: $p, started: $t},
    {card: "c20261117T000002-main-6", issue: 6, step: "worktree", pid: $p, started: $t},
    {card: "c20261117T000002-main-6", issue: 6, step: "landed"}' > "$ST/cards.jsonl"
}

# Bugs: a process was given to no card when it worked outside the worktree (a test worker in /tmp) though its parent
# was the card's; a test of a card's main run (mainrun/<card>.speed) was given to no card, as "mainrun" is no card id; a closed
# card whose worktree was removed under its process lost the process (cwd "<folder> (deleted)"), so a leftover showed
# as no card's, and its stop command left out the card's idle processes; a folder of the cards folder that is no card
# (push, mainrun/machine) or a review's <card>.rv was misread; the groups were not by card and step, heaviest first.
t_busytree() {
  busycards
  local tab out
  tab=$(printf '%s\t%s\t%s\t%s\t%s\n' \
    100 1 3.0 /home 'bash conveyor.sh serve' \
    200 100 50.0 "$C/c20261117T000001-main-5" 'claude -p --model m' \
    201 200 25.0 /tmp 'node tool.js' \
    300 100 90.0 "$C/c20261117T000001-main-5/sub" 'node --test a.test.js' \
    400 1 80.0 "$C/c20261117T000002-main-6 (deleted)" 'node leftover.js' \
    401 400 0.0 / 'tail -f /dev/null' \
    500 1 60.0 /home '/usr/lib/firefox/firefox -new-window' \
    501 1 20.0 / 'node stray.js' \
    600 1 2.0 "$C/c20261117T000001-main-5.rv" 'codex review' \
    700 1 10.0 "$C/push" 'git push' \
    800 1 30.0 "$C/mainrun/c20261117T000002-main-6.speed" 'node --test b.test.js' \
    801 1 7.0 "$C/mainrun/machine" 'node --test c.test.js')
  out=$(busyfn busy_work --json <<<"$tab") || fail "work failed: $out"
  [ "$(jq -c '[.groups[] | [.card[-1:], .step, .closed, .cpu, .stop, [.processes[].pid]]]' <<<"$out")" \
    = '[["5","build",false,165,null,[300,200,201]],["6",null,true,110,"kill 400 401 800",[400,800]]]' ] \
    || fail "the groups are not by card and step, heaviest first, with the closed card's stop command: $(jq -c .groups <<<"$out")"
  [ "$(jq -c '[.other[].pid]' <<<"$out")" = '[500,501,700,801]' ] \
    || fail "the busy work no card owns is not listed, heaviest first: $(jq -c .other <<<"$out")"
  [ "$(jq -c '.groups[0] | [.issue, .project]' <<<"$out")" = '[5,"main"]' ] || fail "the card's issue and project: $(jq -c .groups[0] <<<"$out")"
  out=$(busyfn busy_work <<<"$tab")
  grep -q '^card c20261117T000002-main-6 (issue #6) of main, closed: left over: 110%$' <<<"$out" && grep -q '^  stop them: kill 400 401 800$' <<<"$out" \
    && grep -q '^no card owns:$' <<<"$out" || fail "work's text does not mark the leftover and its stop command: $out"
  out=$(busyfn busy_why 201 --json <<<"$tab") || fail "why 201 failed: $out"
  [ "$(jq -c '.[] | [.card, .issue, .project, .step, .closed, [.parents[].pid]]' <<<"$out")" = '["c20261117T000001-main-5",5,"main","build",false,[200,100]]' ] \
    || fail "why does not give a worker outside the worktree to its parent's card: $out"
  out=$(busyfn busy_why 401 <<<"$tab")
  grep -q 'card c20261117T000002-main-6 (issue #6) of project main, which is closed: it is left over; stop what the card left with: kill 400 401 800$' <<<"$out" \
    || fail "why does not name the closed card of a removed worktree and its stop command: $out"
  out=$(busyfn busy_why firefox <<<"$tab")
  grep -q '^500 /usr/lib/firefox/firefox' <<<"$out" && grep -q '^  no card owns it$' <<<"$out" || fail "why by name: $out"
  [ "$(busyfn busy_why 600 --json <<<"$tab" | jq -c '.[0].card')" = '"c20261117T000001-main-5"' ] || fail "a review's folder beside the worktree is not its card's"
  out=$(busyfn busy_why 999 2>&1 <<<"$tab"); [ $? = 1 ] && grep -q 'no process is 999' <<<"$out" || fail "why of no process: $out"
}

# Bug: the card's own engine process (card(), which works in the project's main folder, not the worktree) and what it
# starts there were given to no card, as ownership read only working folders; its worktree record names its pid. A pid
# a closed card's record names, or one that started at another time (a reused pid), owns nothing.
t_busyenginepid() {
  busycards
  local p q r w tab out
  sleep 60 & p=$! # sleep: a stand-in for the open card's engine process, never waited on; killed below
  sleep 60 & q=$! # sleep: a stand-in for a closed card's engine process, never waited on; killed below
  sleep 60 & r=$! # sleep: a stand-in for a reused pid, never waited on; killed below
  jq -cn --argjson p "$p" --arg t "$(p_started "$p")" --argjson q "$q" --arg u "$(p_started "$q")" --argjson r "$r" '
    {card: "c20261117T000001-main-5", issue: 5, step: "worktree", pid: $p, started: $t},
    {card: "c20261117T000002-main-6", issue: 6, step: "worktree", pid: $q, started: $u},
    {card: "c20261117T000003-main-7", issue: 7, step: "worktree", pid: $r, started: "Thu Jan  1 00:00:00 1970"}' >> "$ST/cards.jsonl"
  tab=$(printf '%s\t%s\t%s\t%s\t%s\n' "$p" 1 1.0 "$R" 'bash conveyor.sh run' \
    900 "$p" 1.0 "$R" 'git fetch' "$q" 1 1.0 "$R" 'bash closed' \
    "$r" 1 1.0 "$R" 'bash reused')
  out=$(for w in "$p" 900 "$q" "$r"; do busyfn busy_why "$w" --json <<<"$tab" | jq -c '.[0] | [.card, .step]'; done | tr '\n' ' ')
  kill "$p" "$q" "$r" 2>/dev/null
  [ "$out" = '["c20261117T000001-main-5","build"] ["c20261117T000001-main-5","build"] [null,null] [null,null] ' ] \
    || fail "the card's engine process in the main folder and its child there are not the card's, or a closed card's or a reused pid is: $out"
}

# Bug: why and work read only the cards folder of the project they were run for, so another record's card work on the
# machine (a second project of the host file) was named as no card's.
t_busyrecords() {
  busycards
  local o=$T/$CASE/shop k out
  mkdir -p "$o/conveyor/state" "$T/$CASE/conveyor-cards-shop/c20261117T000003-shop-7" "${XDG_CONFIG_HOME:-$HOME/.config}/conveyor"
  jq -cn --arg a "$R" --arg b "$o" '{records: [{repo: "main", main: $a}, {repo: "shop", main: $b}]}' > "${XDG_CONFIG_HOME:-$HOME/.config}/conveyor/host.json"
  echo conveyor-cards-shop > "$o/conveyor/state/cards-folder"
  k=$(cd "$T/$CASE/conveyor-cards-shop" && pwd -P)
  echo '{"step": "fix"}' > "$k/c20261117T000003-shop-7.live"
  jq -cn --argjson p $$ --arg t "$(p_started $$)" '{card: "c20261117T000003-shop-7", issue: 7, step: "worktree", pid: $p, started: $t}' > "$o/conveyor/state/cards.jsonl"
  out=$(printf '%s\t%s\t%s\t%s\t%s\n' 900 1 40.0 "$k/c20261117T000003-shop-7" 'claude -p' \
    200 1 50.0 "$C/c20261117T000001-main-5" 'claude -p --model m' | busyfn busy_work --json) || fail "work failed: $out"
  [ "$(jq -c '[.groups[] | [.card[-1:], .issue, .project, .step, .closed]], .other' <<<"$out")" = '[["5",5,"main","build",false],["7",7,"shop","fix",false]]
[]' ] || fail "another record's card work is not given to its card and project: $out"
}

# Bug: why read nothing of the machine's own processes (the table: /proc on Linux, ps and lsof on macOS), so it named
# no card for a real worker that works outside its card's worktree.
t_busywhy() {
  busycards
  local p w out
  (cd "$C/c20261117T000001-main-5" && exec bash -c '(cd / && exec sleep 60) & wait') & p=$! # sleep: the worker why reads, alive until it is killed
  for _ in $(seq 50); do w=$(pgrep -P "$p" sleep) && break; sleep 0.1; done
  out=$(loop why "$w" --json); kill "$p" "$w" 2>/dev/null
  [ "$(jq -c '.[0] | [.card, .step, .closed, (.parents[0].pid == '"$p"')]' <<<"$out")" = '["c20261117T000001-main-5","build",false,true]' ] \
    || fail "why does not give the real worker to its parent's card: $out"
}
