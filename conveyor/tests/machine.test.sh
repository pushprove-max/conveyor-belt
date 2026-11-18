#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 300
# Engine cases: one Conveyor per machine (`conveyor.sh machine`): the machine cap, the turn between projects, and the
# machine's pause.
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"
# The engine folder, as lib.sh sets it: named here too, so the release closure (tools/closure.sh) follows this file's paths.
SRC=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
# One project of the machine under $T/<case>/<name>: lib.sh's setup there, polling every second, every review a GO, and
# a build that marks its card running ($SH/run/<name>-<issue>) and waits for $SH/go-<name>-<issue> (or $SH/go) before
# it writes a file of its own, so no two cards share a file. Sets P_<name> to its main checkout.
project() { # <name> <issues json>
  local c=$CASE; CASE=$c/$1; setup "$2"; CASE=$c
  tune '.tunables.idle = 1 | .tunables.poll = 1'
  for i in $(seq 1 20); do echo "$GO" > "$STUB/review.$i"; done
  printf 'n=${PWD##*-}; k=%s-$n; echo "$k" >> %q; [ "$n" != 23 ] || exit 1; : > %q/run/$k
for i in $(seq 600); do [ -e %q/go-$k ] || [ -e %q/go ] && break; sleep 0.1; done; rm -f %q/run/$k; echo "$n" > "f$n.txt"\n' \
    "$1" "$SH/started" "$SH" "$SH" "$SH" "$SH" > "$STUB/build"
  printf -v "P_$1" %s "$R"
}
# gh, claude and codex as each project's own stubs: the project is the one whose checkout the call runs in (its main
# checkout, or a card's worktree of it).
dispatch() {
  mkdir -p "$SH/bin" "$SH/run"
  for p in gh claude codex; do
    printf '#!/usr/bin/env bash\nm=$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || exit 9\nm=${m%%/.git}; export STUB=${m%%/main}/stub\nexec "$STUB/%s" "$@"\n' "$p" > "$SH/bin/$p"
    chmod +x "$SH/bin/$p"
  done
  PATH=$SH/bin:$PATH
}
picked() { jq -e --argjson n "$2" 'select(.step == "picked" and .issue == $n)' "$3/conveyor/state/cards.jsonl" >/dev/null 2>&1; } # <name> <issue> <main>
# The cards in flight now across the projects: picked and not landed, closed or blocked.
inflight() { cat "$@" 2>/dev/null | jq -s '[group_by(.card)[] | select(all(.step | IN("landed", "closed", "blocked") | not))] | length'; }

# Bugs: two projects on one machine each run up to their own cap, so their cards add up past the machine's; one
# project holds every slot while the other has work and waits for good; a pause of one project stops the other; one
# project's card is written to, or pushed with, the other's records, kept work or repo; a blocked card of one project
# wakes the other's Foreman.
t_machinecap() {
  SH=$T/$CASE/shared; mkdir -p "$SH"; export XDG_CONFIG_HOME=$T/$CASE/config # the machine's folder is the case's own
  project alpha "[$(issue 1 2026-01-01), $(issue 2 2026-01-02), $(issue 3 2026-01-03)]"
  project beta '[]'
  dispatch; watchturns
  local A=$P_alpha B=$P_beta MS=$XDG_CONFIG_HOME/conveyor/machine
  mkdir -p "$XDG_CONFIG_HOME/conveyor"
  # A machine cap of 2, the least that one project can fill and the other still share: each card more costs seconds.
  jq -n --arg a "$A" --arg b "$B" '{records: [{repo: "alpha", main: $a}, {repo: "beta", main: $b}], cap: 2}' > "$XDG_CONFIG_HOME/conveyor/host.json"
  ( cd "$A" && CONVEYOR_MAIN=$A exec bash "$SRC/conveyor.sh" machine > "$SH/machine.out" 2>&1 ) & mp=$!
  trap 'kill -TERM $mp $wp 2>/dev/null; wait $mp 2>/dev/null' EXIT
  # The most cards in flight at once, sampled all along.
  ( while :; do inflight "$A/conveyor/state/cards.jsonl" "$B/conveyor/state/cards.jsonl" >> "$SH/inflight"; sleep 0.1; done ) & wp=$! # sleep: the pause between two samples
  out() { cat "$SH/machine.out"; }
  wait_until '[ "$(ls "$SH/run" | wc -l)" = 2 ]' || fail "alpha did not build 2 cards: $(out)"
  loop() { CONVEYOR_MAIN=$1 bash "$SRC/conveyor.sh" "${@:2}"; }
  # alpha's loop says its 3rd card waits for a slot; a whole turn later it still has not started it.
  slotsaid() { loop "$A" health | jq -e '.repo == "alpha" and (.room.reason | test("waiting for a machine slot: 2 of the machine cap 2 in use"))'; }
  wait_until slotsaid || fail "alpha's health does not say its card waits for a machine slot: $(loop "$A" health | jq -c '{repo, room}')"
  turns 2 "$A"
  ! picked alpha 3 "$A" || fail "alpha's 3rd card started past the machine cap of 2 (alpha's own cap is 5): $(out)"
  # The Board's queue rows are the snapshot's queue.order (dashboard.sh's boardOf); board.js draws a row's room
  # (dashboard-view.overview.test.mjs, "a card the machine holds back"). Bug: the held card's row did not say why.
  loop "$A" snapshot --fresh | jq -e '[.queue.order[] | select(.issue == 3)] | length == 1 and (.[0].room | test("^waiting for a machine slot: 2 of the machine cap 2 in use"))' >/dev/null \
    || fail "the Board's queue row of alpha's #3 does not say why it waits: $(loop "$A" snapshot --fresh | jq -c .queue.order)"
  # beta gets work while alpha holds every slot and still has work: the next slot is beta's.
  echo "[$(issue 21 2026-01-01), $(issue 22 2026-01-02)]" > "$B/../stub/issues.json"
  wait_until 'jq -e .wants "$MS/slots/beta.json" >/dev/null 2>&1' || fail "beta's card never waited for a slot: $(cat "$MS"/slots/*.json) $(out)"
  # A project's slot file is never beside the machine loop's own file: a project named loop would overwrite it.
  [ "$(ls "$MS"/*.json)" = "$MS/loop.json" ] || fail "a project's slot file is beside the machine's loop.json: $(ls "$MS")"
  : > "$SH/go-alpha-1"
  wait_until 'picked beta 21 "$B"' || fail "beta never got a slot: $(out)"
  ! picked alpha 3 "$A" || fail "alpha took the freed slot though beta waited and alpha had the last one"
  # A pause of alpha leaves beta running: alpha's card in flight ends, and its slot goes to beta alone.
  loop "$A" control pause >/dev/null || fail "alpha's pause was refused"
  : > "$SH/go-alpha-2"
  wait_until 'picked beta 22 "$B"' || fail "beta stopped picking while alpha was paused: $(out)"
  turns 2 "$A"; ! picked alpha 3 "$A" || fail "the paused alpha picked a card"
  # beta's next card is blocked (its build fails); all the rest land.
  echo "[$(issue 21 2026-01-01), $(issue 22 2026-01-02), $(issue 23 2026-01-03)]" > "$B/../stub/issues.json"
  : > "$SH/go"
  wait_until '[ "$(jq -s "map(select(.step == \"landed\")) | length" "$A/conveyor/state/cards.jsonl")" = 2 ] && [ "$(jq -s "map(select(.step == \"landed\")) | length" "$B/conveyor/state/cards.jsonl")" = 2 ] && jq -e "select(.step == \"blocked\" and .issue == 23)" "$B/conveyor/state/cards.jsonl" >/dev/null' \
    || fail "the cards did not end: $(out)"
  kill $wp 2>/dev/null
  [ "$(sort -n "$SH/inflight" | tail -1)" -le 2 ] || fail "more than 2 cards were in flight at once: $(sort -n "$SH/inflight" | uniq -c)"
  # Each project's records, kept work and pushes are its own.
  [ "$(jq -sc 'map(.issue) | unique' "$A/conveyor/state/cards.jsonl")" = '[1,2]' ] && [ "$(jq -sc 'map(.issue) | unique' "$B/conveyor/state/cards.jsonl")" = '[21,22,23]' ] \
    || fail "a project's records hold another's cards"
  jq -se 'all(.repo == "alpha")' "$A/conveyor/state/cards.jsonl" >/dev/null && jq -se 'all(.repo == "beta")' "$B/conveyor/state/cards.jsonl" >/dev/null \
    || fail "a record line does not name its project"
  jq -se 'all(.card | test("^c[0-9]{8}T[0-9]{6}-alpha-[0-9]+$"))' "$A/conveyor/state/cards.jsonl" >/dev/null \
    && jq -se 'all(.card | test("^c[0-9]{8}T[0-9]{6}-beta-[0-9]+$"))' "$B/conveyor/state/cards.jsonl" >/dev/null \
    || fail "a card id does not name its project, so two projects' cards of one issue and second share it: $(jq -sc 'map(.card) | unique' "$A/conveyor/state/cards.jsonl" "$B/conveyor/state/cards.jsonl")"
  [ -d "$B/conveyor/state/kept" ] && [ ! -e "$A/conveyor/state/kept" ] || fail "beta's blocked card's work was not kept in beta's own state folder"
  wait_until '[ "$(git -C "$T/$CASE/alpha/origin" ls-tree --name-only main | grep "^f" | tr "\n" " ")" = "f1.txt f2.txt " ]' \
    && wait_until '[ "$(git -C "$T/$CASE/beta/origin" ls-tree --name-only main | grep "^f" | tr "\n" " ")" = "f21.txt f22.txt " ]' \
    || fail "a push went to another project's repo: $(git -C "$T/$CASE/alpha/origin" ls-tree --name-only main) / $(git -C "$T/$CASE/beta/origin" ls-tree --name-only main)"
  # beta's blocked card wakes beta's Foreman, never alpha's.
  export CONVEYOR_FOREMAN_ASK="cd \"\$CONVEYOR_MAIN\" && bash $SRC/conveyor.sh \$CONVEYOR_CMD"
  (cd "$A" && CONVEYOR_MAIN=$A bash "$SRC/foreman/watch-conveyor.sh" --once >/dev/null 2>&1)
  (cd "$B" && CONVEYOR_MAIN=$B bash "$SRC/foreman/watch-conveyor.sh" --once >/dev/null 2>&1) || fail "beta's blocked card woke nothing"
  grep -qF '#23 is blocked' "$B"/conveyor/state/foreman/pending/*.wake 2>/dev/null || fail "beta's Foreman was not woken by its blocked card"
  ! grep -qs '#23\|beta' "$A"/conveyor/state/foreman/pending/*.wake || fail "beta's blocked card woke alpha's Foreman"
  # One loop per machine: a second machine loop is refused, and doctor names the machine's as the one loop.
  (cd "$B" && CONVEYOR_MAIN=$B exec bash "$SRC/conveyor.sh" machine > "$SH/second.out" 2>&1); [ $? != 0 ] && grep -q "the machine's Conveyor already runs" "$SH/second.out" \
    || fail "a second machine loop started: $(cat "$SH/second.out")"
  out=$(cd "$A" && bash "$SRC/conveyor.sh" doctor 2>&1)
  grep -qx "ok: one Conveyor loop on this machine: the machine's Conveyor (pid $mp)" <<<"$out" || fail "doctor did not name the machine's loop: $out"
  # The projects' loops running on their own (the machine's gone, as with per-project services): doctor names the second.
  kill -KILL $mp; wait $mp 2>/dev/null
  out=$(cd "$A" && bash "$SRC/conveyor.sh" doctor 2>&1)
  kill -TERM "$(jq -r .pid "$A/conveyor/state/loop.json")" "$(jq -r .pid "$B/conveyor/state/loop.json")" 2>/dev/null
  grep -q "^missing: one Conveyor loop on this machine: a loop of beta on its own (pid [0-9]*) runs beside a loop of alpha on its own" <<<"$out" \
    || fail "doctor did not name the second loop: $out"
}

# Bugs: a project's loop killed with its cards still building frees their machine slots, so another project starts
# cards past the machine cap beside them; once they end, the slots are never freed. One card under a machine cap of 1:
# a card run costs a case seconds, and more of them free no other slot.
t_machinekill() {
  SH=$T/$CASE/shared; mkdir -p "$SH"; export XDG_CONFIG_HOME=$T/$CASE/config # the machine's folder is the case's own
  project alpha "[$(issue 1 2026-01-01)]"
  project beta '[]'
  dispatch; watchturns
  local A=$P_alpha B=$P_beta; mkdir -p "$XDG_CONFIG_HOME/conveyor"
  jq -n --arg a "$A" --arg b "$B" '{records: [{repo: "alpha", main: $a}, {repo: "beta", main: $b}], cap: 1}' > "$XDG_CONFIG_HOME/conveyor/host.json"
  ( cd "$A" && CONVEYOR_MAIN=$A exec bash "$SRC/conveyor.sh" machine > "$SH/machine.out" 2>&1 ) & mp=$!
  trap 'kill -TERM $mp 2>/dev/null; wait $mp 2>/dev/null' EXIT
  out() { cat "$SH/machine.out"; }
  wait_until '[ -e "$SH/run/alpha-1" ]' || fail "alpha did not build its card: $(out)"
  kill -KILL "$(jq -r .pid "$A/conveyor/state/loop.json")" || fail "alpha's loop was not there to kill"
  echo "[$(issue 21 2026-01-01)]" > "$B/../stub/issues.json"
  turns 2 "$B" # a whole turn of beta's loop with its issue there
  ! picked beta 21 "$B" || fail "beta started a card past the machine cap while alpha's card still built: $(out)"
  [ -e "$SH/run/alpha-1" ] || fail "alpha's card did not go on building after its loop was killed"
  : > "$SH/go"
  wait_until 'picked beta 21 "$B"' || fail "beta never got a slot once alpha's cards ended: $(out)"
}
# A loop killed while it wrote its slot file leaves it with no start time (its `ps` found it gone). Bug: read split on
# tabs, that empty field shifted the rest, so the run lock its card still holds read as none and the card was not
# counted: beta started past the machine cap (t_machinekill failed so whenever the kill fell in that write).
t_machinegone() {
  SH=$T/$CASE/shared; mkdir -p "$SH"; export XDG_CONFIG_HOME=$T/$CASE/config # the machine's folder is the case's own
  project beta "[$(issue 21 2026-01-01)]"
  dispatch; watchturns
  local B=$P_beta MS=$XDG_CONFIG_HOME/conveyor/machine dead; mkdir -p "$MS/slots"
  jq -n --arg b "$B" '{records: [{repo: "beta", main: $b}], cap: 1}' > "$XDG_CONFIG_HOME/conveyor/host.json"
  # gone's card, still holding gone's run lock until $SH/free; gone's loop, ended.
  ( exec 5>>"$SH/gone.run"; flock 5; : > "$SH/held"; until [ -e "$SH/free" ]; do sleep 0.1; done ) & # sleep: the card's wait for its end
  wait_until '[ -e "$SH/held" ]' || fail "gone's card did not take its run lock"
  true & dead=$!; wait "$dead"
  jq -n --argjson p "$dead" --arg u "$SH/gone.run" '{pid: $p, started: "", running: 1, wants: false, last: 1, run: $u}' > "$MS/slots/gone.json"
  ( cd "$B" && CONVEYOR_MAIN=$B exec bash "$SRC/conveyor.sh" serve > "$SH/beta.out" 2>&1 ) & bp=$!
  trap 'kill -TERM $bp 2>/dev/null; wait $bp 2>/dev/null' EXIT
  turns 2 "$B" # a whole turn of beta's loop with its issue there
  ! picked beta 21 "$B" || fail "beta started a card past the machine cap while gone's card held its run lock: $(cat "$SH/beta.out")"
  : > "$SH/free"; : > "$SH/go"
  wait_until 'picked beta 21 "$B"' || fail "beta never got the slot once gone's card ended: $(cat "$SH/beta.out")"
}

# Bugs: the last project is removed from the host file (its records an empty list) and its loop goes on running and
# picking cards; a host file cut short for a moment stops a project's loop.
t_machineempty() {
  SH=$T/$CASE/shared; mkdir -p "$SH"; export XDG_CONFIG_HOME=$T/$CASE/config # the machine's folder is the case's own
  project solo '[]'
  dispatch; watchturns
  local S=$P_solo H=$XDG_CONFIG_HOME/conveyor/host.json lp; mkdir -p "$XDG_CONFIG_HOME/conveyor"
  jq -n --arg s "$S" '{records: [{repo: "solo", main: $s}], cap: 3}' > "$H"
  ( cd "$S" && CONVEYOR_MAIN=$S exec bash "$SRC/conveyor.sh" machine > "$SH/machine.out" 2>&1 ) & mp=$!
  trap 'kill -TERM $mp 2>/dev/null; wait $mp 2>/dev/null' EXIT
  out() { cat "$SH/machine.out"; }
  wait_until 'kill -0 "$(jq -er .pid "$S/conveyor/state/loop.json" 2>/dev/null)" 2>/dev/null' || fail "solo's loop did not start: $(out)"
  lp=$(jq -er .pid "$S/conveyor/state/loop.json")
  # The host file cut short: its records are not known, so the loop stays.
  : > "$H"; turns 2 machine # a whole turn of the machine's loop with the file cut short
  kill -0 "$lp" 2>/dev/null || fail "solo's loop was stopped by a host file that does not read: $(out)"
  # No records, then text that is not JSON: the file does not read as a whole, so its empty records are not believed.
  echo '{"records":[]} garbage' > "$H"; turns 2 machine
  kill -0 "$lp" 2>/dev/null || fail "solo's loop was stopped by a host file with text after its value: $(out)"
  # The last project removed: its loop is stopped, and its next issue is never picked.
  echo '{"records":[],"cap":3}' > "$H"
  wait_until '! kill -0 "$lp" 2>/dev/null' || fail "solo's loop still runs after its record, the last, was removed: $(out)"
  grep -q "solo is no longer a record of .*: its loop is stopped" "$SH/machine.out" || fail "the machine's Conveyor did not say it stopped solo's loop: $(out)"
  echo "[$(issue 1 2026-01-01)]" > "$S/../stub/issues.json"
  # The machine's Conveyor has seen the loop end, so from here it holds a time to start it again at; then a whole
  # turn of it begun past that time (MACHINE_RESTART, 10 s, and the two clocks' part seconds), the turn that would
  # start the loop again; then one more, so a loop started in it has had its time to come up.
  wait_until 'grep -q "the loop of solo ended; it starts again" "$SH/machine.out"' || fail "the machine's Conveyor did not see solo's loop end: $(out)"
  local due=$((SECONDS + 12))
  wait_until "[ \"\$SECONDS\" -ge $due ]" || fail "the time to start solo's loop again did not come"
  turns 3 machine
  ! pgrep -P "$mp" -f 'conveyor\.sh serve' > /dev/null || fail "the removed project's loop was started again: $(out)"
  ! picked solo 1 "$S" || fail "the removed project picked a card: $(out)"
  kill -0 "$mp" 2>/dev/null || fail "the machine's Conveyor ended with no project left: $(out)"
}

# Bug: a loop of a project that is no record of the host file (a `serve` started by hand) runs beside the machine's
# Conveyor, its cards on top of the machine's, and doctor, which looked only at the records, says there is one loop.
# Doctor finds it among the machine's processes, by nothing the loop writes (a loop on older code writes nothing new,
# and one that could not write would run unseen), in a checkout of any name (a tab in it here).
t_machinestray() {
  SH=$T/$CASE/shared; mkdir -p "$SH"; export XDG_CONFIG_HOME=$T/$CASE/config # the machine's folder is the case's own
  project alpha '[]'
  project beta '[]'
  dispatch
  local A=$P_alpha B=$T/$CASE/$'be\tta' out; mv "$P_beta" "$B"; mkdir -p "$XDG_CONFIG_HOME/conveyor"
  jq -n --arg a "$A" '{records: [{repo: "alpha", main: $a}]}' > "$XDG_CONFIG_HOME/conveyor/host.json"
  ( cd "$A" && CONVEYOR_MAIN=$A exec bash "$SRC/conveyor.sh" machine > "$SH/machine.out" 2>&1 ) & mp=$!
  # The loop names the machine's host file by another path to it (a slash at the end): it is the same host file.
  ( cd "$B" && unset CONVEYOR_CARDS && XDG_CONFIG_HOME=$XDG_CONFIG_HOME/ CONVEYOR_MAIN=$B exec bash "$SRC/conveyor.sh" serve > "$SH/beta.out" 2>&1 ) & bp=$!
  # A process that is no loop, in the same checkout with the same environment, its arguments ending as a loop's do (an
  # editor with the engine open, a script handed its path): doctor counts no loop for it.
  printf 'sleep 30 & trap "kill $!" TERM; wait\n' > "$SH/edit.sh" # sleep: a stand-in for a running process that is no loop
  ( cd "$B" && exec sh "$SH/edit.sh" "$SRC/conveyor.sh" run ) & ep=$!
  trap 'kill -TERM $mp $bp $ep 2>/dev/null; wait $mp $bp $ep 2>/dev/null' EXIT
  wait_until 'kill -0 "$(jq -er .pid "$A/conveyor/state/loop.json" 2>/dev/null)" 2>/dev/null && [ "$(jq -er .pid "$B/conveyor/state/loop.json" 2>/dev/null)" = "$bp" ]' \
    || fail "the two loops did not start: $(cat "$SH/machine.out" "$SH/beta.out")"
  out=$(cd "$A" && CONVEYOR_MAIN=$A bash "$SRC/conveyor.sh" doctor 2>&1)
  grep -qxF "missing: one Conveyor loop on this machine: a loop of $B, no record of the host file, on its own (pid $bp) runs beside the machine's Conveyor (pid $mp); fix: stop every loop but the machine's (a per-project service: systemctl --user disable --now conveyor-<name>.service, or launchctl bootout gui/\$(id -u)/conveyor.<name>), then run install-service once" <<<"$out" \
    || fail "doctor did not name the loop of the project that is no record: $out"
  # Once that loop is stopped, what it left in the machine's folder names no loop: the machine's is the one.
  kill -TERM $bp; wait $bp 2>/dev/null
  out=$(cd "$A" && CONVEYOR_MAIN=$A bash "$SRC/conveyor.sh" doctor 2>&1)
  grep -qx "ok: one Conveyor loop on this machine: the machine's Conveyor (pid $mp)" <<<"$out" || fail "doctor named a loop that no longer runs, or a process that is no loop (pid $ep): $out"
  # A loop of another host file is another machine's, as every other test's loops are: it is not counted here.
  ( cd "$B" && unset CONVEYOR_CARDS && XDG_CONFIG_HOME=$T/$CASE/other CONVEYOR_MAIN=$B exec bash "$SRC/conveyor.sh" serve > "$SH/beta.out" 2>&1 ) & bp=$!
  wait_until '[ "$(jq -er .pid "$B/conveyor/state/loop.json" 2>/dev/null)" = "$bp" ]' || fail "the loop of another host file did not start: $(cat "$SH/beta.out")"
  out=$(cd "$A" && CONVEYOR_MAIN=$A bash "$SRC/conveyor.sh" doctor 2>&1)
  grep -qx "ok: one Conveyor loop on this machine: the machine's Conveyor (pid $mp)" <<<"$out" || fail "doctor counted a loop of another host file: $out"
}

# Bugs: the old machine-room settings of a host file (maxLoad, minFreeMemMB, pressure) still hold a card back, however
# the machine reads (issue 346: the machine room is removed, the caps and the test slots are the only limits); a host
# file cut short, or a link to settings that are taken away (there, and not reading, so not absent), reads as no host
# file, and the card passes every machine gate; once it reads again, the card is still held. room(), as the loop's
# pick asks it for its next card with none running.
t_machinegate() {
  export XDG_CONFIG_HOME=$T/$CASE/config # the machine's folder is the case's own
  setup '[]'
  local H=$XDG_CONFIG_HOME/conveyor/host.json M=$T/$CASE/room why; mkdir -p "${H%/*}"
  # Settings no machine can pass: a load limit of 1, more free memory than any machine has, Strained at once.
  jq -n --arg r "$R" '{records: [{repo: "solo", main: $r}], maxLoad: 1, minFreeMemMB: 999999999,
    pressure: {strained: {cpu: 0, memory: 0, wakeMs: 0, freeMB: 999999999}}}' > "$H"
  # The engine as a loop holds it: read once, while the host file reads (one started while it does not cannot name its
  # state folder). gate <issue>: room()'s yes (0), or its no (1) with why in $why.
  export CONVEYOR_MAIN=$R; cd "$R" && . "$SRC/conveyor.sh" state-dir > /dev/null \
    && eval "$(grep '^\. "\$HERE/lib/' "$SRC/commands/run.sh")" || fail "the engine could not be read"
  # shellcheck disable=SC2034 # RUNNING is read by room(), from lib/pick.sh, read by the eval
  RUNNING=0 # the loop's count of its cards running, as run() sets it before a pick
  gate() { why=$(room "$1"); }
  held() { # <issue> <why>: room() says no, with that why, and keeps it for health and the Board
    ! gate "$1" && [ "$why" = "$2" ] && [ "$(jq -c '[.issue, .reason]' "$R/conveyor/state/room.json")" = "$(jq -cn --argjson n "$1" --arg r "$2" '[$n, $r]')" ]
  }
  gate 3 && [ ! -e "$R/conveyor/state/room.json" ] || fail "#3 was held back by the old machine-room settings: $why"
  # The host file cut short: the machine's cap and pause are not known, so no card starts.
  cp "$H" "$M.h"; : > "$H"
  held 4 "waiting for a machine slot: the host file could not be read, so the machine's cap and pause are not known" \
    || fail "#4 was not held by a host file that cannot be read: $why"
  cp "$M.h" "$H"
  gate 4 || fail "#4 was held once the host file read again: $why"
  # The host file a link to settings that are taken away: it is there and does not read, not absent, so the machine's
  # gates are not known and no card starts (read as absent, every gate would be passed).
  mv "$H" "$M.settings"; ln -s "$M.settings" "$H"; rm "$M.settings"
  held 5 "waiting for a machine slot: the host file could not be read, so the machine's cap and pause are not known" \
    || fail "#5 was not held by a host file whose link leads nowhere: $why"
  cp "$M.h" "$M.settings"
  gate 5 || fail "#5 was held once the host file's link led to its settings again: $why"
}

# Bugs: two projects whose checkouts sit in one folder share one cards folder, so a card of one can take the other's
# worktree path, and each one's push empties the push workspace the other is pushing from; a project alone in its
# folder has its cards folder moved.
t_machinecards() {
  export XDG_CONFIG_HOME=$T/$CASE/config # the machine's folder is the case's own
  local P=$T/$CASE/projects G=$T/$CASE/solo/gamma r; mkdir -p "$P/alpha" "$P/beta" "$G" "$XDG_CONFIG_HOME/conveyor"
  for r in "$P/alpha" "$P/beta" "$G"; do git -C "$r" init -q -b main || fail "the repo $r was not made"; done
  jq -n --arg a "$P/alpha" --arg b "$P/beta" --arg g "$G" '{records: [{repo: "alpha", main: $a}, {repo: "beta", main: $b}, {repo: "gamma", main: $g}]}' \
    > "$XDG_CONFIG_HOME/conveyor/host.json"
  for r in "$P/alpha" "$P/beta" "$G"; do (unset CONVEYOR_CARDS; CONVEYOR_MAIN=$r bash "$SRC/conveyor.sh" check >/dev/null 2>&1) || fail "check in $r failed"; done
  [ -d "$P/conveyor-cards-alpha" ] && [ -d "$P/conveyor-cards-beta" ] && [ ! -e "$P/conveyor-cards" ] || fail "two projects of one folder share a cards folder: $(ls "$P")"
  [ -d "$T/$CASE/solo/conveyor-cards" ] || fail "a project alone in its folder did not keep conveyor-cards: $(ls "$T/$CASE/solo")"
  # Bug: a project added beside one already at work moved that project's cards folder for every later command, while
  # its running loop wrote on to the first: health and watch read an empty folder and its live cards were not seen
  # (every command makes the cards folder it reads, so the folders made are the folders read).
  # The folder a project first made stays its folder; the project added takes one of its own.
  local Q=$T/$CASE/later; mkdir -p "$Q/alpha" "$Q/beta"
  for r in "$Q/alpha" "$Q/beta"; do git -C "$r" init -q -b main || fail "the repo $r was not made"; done
  jq -n --arg a "$Q/alpha" '{records: [{repo: "alpha", main: $a}]}' > "$XDG_CONFIG_HOME/conveyor/host.json"
  (unset CONVEYOR_CARDS; CONVEYOR_MAIN=$Q/alpha bash "$SRC/conveyor.sh" check >/dev/null 2>&1) || fail "check in $Q/alpha failed"
  [ -d "$Q/conveyor-cards" ] || fail "alpha alone did not make conveyor-cards: $(ls "$Q")"
  jq -n --arg a "$Q/alpha" --arg b "$Q/beta" '{records: [{repo: "alpha", main: $a}, {repo: "beta", main: $b}]}' > "$XDG_CONFIG_HOME/conveyor/host.json"
  for r in "$Q/alpha" "$Q/beta"; do (unset CONVEYOR_CARDS; CONVEYOR_MAIN=$r bash "$SRC/conveyor.sh" check >/dev/null 2>&1) || fail "check in $r failed"; done
  [ ! -e "$Q/conveyor-cards-alpha" ] && [ -d "$Q/conveyor-cards-beta" ] || fail "a project added beside alpha moved alpha's cards folder, or shares it: $(ls "$Q")"
  # Bug: a command that chose its cards folder while a second command of the project, started after a project was
  # added beside it, kept another name, went on with its own choice: the loop wrote live cards where health and
  # watch did not read. Here the second command's name is kept just after the first has read that none is (jq is
  # the first program run after that read): the first takes the kept name and makes no folder of its own.
  local R=$T/$CASE/race; mkdir -p "$R/alpha/conveyor/state" "$R/bin"; git -C "$R/alpha" init -q -b main || fail "the repo $R/alpha was not made"
  jq -n --arg a "$R/alpha" '{records: [{repo: "alpha", main: $a}]}' > "$XDG_CONFIG_HOME/conveyor/host.json"
  printf '%s\n' '#!/usr/bin/env bash' "[ \"\${2:-}\" != '.records | arrays | .[] | objects | .main | strings' ] || echo conveyor-cards-alpha > '$R/alpha/conveyor/state/cards-folder'" \
    "exec '$(command -v jq)' \"\$@\"" > "$R/bin/jq"; chmod +x "$R/bin/jq"
  (unset CONVEYOR_CARDS; PATH=$R/bin:$PATH CONVEYOR_MAIN=$R/alpha bash "$SRC/conveyor.sh" check >/dev/null 2>&1) || fail "check in $R/alpha failed"
  [ -d "$R/conveyor-cards-alpha" ] && [ ! -e "$R/conveyor-cards" ] || fail "a command kept its own cards folder after another kept the project's: $(ls "$R")"
  # Bug: a kept-name file that held no name (an empty one) was never replaced, so the project went on choosing: once
  # a project was added beside it, its next command read conveyor-cards-<repo> while its loop wrote conveyor-cards.
  # The first command replaces such a file with the name it chose, and that stays the folder.
  local E=$T/$CASE/empty; mkdir -p "$E/alpha/conveyor/state" "$E/beta"
  for r in "$E/alpha" "$E/beta"; do git -C "$r" init -q -b main || fail "the repo $r was not made"; done
  : > "$E/alpha/conveyor/state/cards-folder"
  jq -n --arg a "$E/alpha" '{records: [{repo: "alpha", main: $a}]}' > "$XDG_CONFIG_HOME/conveyor/host.json"
  (unset CONVEYOR_CARDS; CONVEYOR_MAIN=$E/alpha bash "$SRC/conveyor.sh" check >/dev/null 2>&1) || fail "check in $E/alpha failed"
  [ "$(cat "$E/alpha/conveyor/state/cards-folder")" = conveyor-cards ] || fail "an empty kept-name file was not replaced with the name chosen: '$(cat "$E/alpha/conveyor/state/cards-folder")'"
  jq -n --arg a "$E/alpha" --arg b "$E/beta" '{records: [{repo: "alpha", main: $a}, {repo: "beta", main: $b}]}' > "$XDG_CONFIG_HOME/conveyor/host.json"
  (unset CONVEYOR_CARDS; CONVEYOR_MAIN=$E/alpha bash "$SRC/conveyor.sh" check >/dev/null 2>&1) || fail "check in $E/alpha failed"
  [ -d "$E/conveyor-cards" ] && [ ! -e "$E/conveyor-cards-alpha" ] || fail "a project that started with an empty kept-name file had its cards folder moved by a project added beside it: $(ls "$E")"
  # Bug: a record renamed keeps the folder of its old name, and a project then added under that old name chose the
  # same folder: two projects shared one cards folder. The project added takes the next name free.
  local N=$T/$CASE/renamed; mkdir -p "$N/alpha" "$N/beta" "$N/new"
  for r in "$N/alpha" "$N/beta" "$N/new"; do git -C "$r" init -q -b main || fail "the repo $r was not made"; done
  jq -n --arg a "$N/alpha" --arg b "$N/beta" '{records: [{repo: "alpha", main: $a}, {repo: "beta", main: $b}]}' > "$XDG_CONFIG_HOME/conveyor/host.json"
  for r in "$N/alpha" "$N/beta"; do (unset CONVEYOR_CARDS; CONVEYOR_MAIN=$r bash "$SRC/conveyor.sh" check >/dev/null 2>&1) || fail "check in $r failed"; done
  jq -n --arg a "$N/alpha" --arg b "$N/beta" --arg n "$N/new" '{records: [{repo: "alpha", main: $a}, {repo: "gamma", main: $b}, {repo: "beta", main: $n}]}' > "$XDG_CONFIG_HOME/conveyor/host.json"
  for r in "$N/beta" "$N/new"; do (unset CONVEYOR_CARDS; CONVEYOR_MAIN=$r bash "$SRC/conveyor.sh" check >/dev/null 2>&1) || fail "check in $r failed"; done
  [ "$(cat "$N/beta/conveyor/state/cards-folder")" = conveyor-cards-beta ] && [ ! -e "$N/conveyor-cards-gamma" ] || fail "a record renamed did not keep its cards folder: $(ls "$N")"
  [ "$(cat "$N/new/conveyor/state/cards-folder")" = conveyor-cards-beta-2 ] && [ -d "$N/conveyor-cards-beta-2" ] || fail "a project added under a renamed record's old name took that record's cards folder: '$(cat "$N/new/conveyor/state/cards-folder")'"
}

# One machine's Conveyor over one project, solo, with issue #1 (or the issues given), started in the background: sets
# S (solo's main checkout) and mp (the machine's Conveyor), its output in $SH/machine.out. With lines given, the
# card's session runs them before its build.
machine1() { # [issues json] [lines]
  SH=$T/$CASE/shared; mkdir -p "$SH"; export XDG_CONFIG_HOME=$T/$CASE/config # the machine's folder is the case's own
  project solo "${1:-[$(issue 1 2026-01-01)]}"
  dispatch; watchturns
  S=$P_solo; mkdir -p "$XDG_CONFIG_HOME/conveyor"
  [ -z "${2:-}" ] || { printf '%s\n' "$2" "$(cat "$STUB/build")" > "$SH/build" && mv "$SH/build" "$STUB/build"; }
  jq -n --arg s "$S" '{records: [{repo: "so_lo.1", main: $s}]}' > "$XDG_CONFIG_HOME/conveyor/host.json"
  ( cd "$S" && CONVEYOR_MAIN=$S exec bash "$SRC/conveyor.sh" machine > "$SH/machine.out" 2>&1 ) & mp=$!
}
# <pid>...: those of them that still run (one that has ended and is not waited for yet does not), each with its command.
running() { ps -o pid=,stat=,args= -p "$(IFS=,; echo "$*")" 2>/dev/null | awk '$2 !~ /Z/'; }

# What the case inside t_machineleft and t_machinekilled starts (run_case's "t_$CASE": left_killed, left_stays; no
# case of the runner's, their names are not a case's), under a scratch folder $d/in of the case that runs it: a
# machine's Conveyor building a card; a `serve` under `timeout`, as cases start one (it is in timeout's group, with
# nothing over it that is told to end); and, on Linux, a `serve` that has left all the case could be known by: a
# session of its own (setsid), the case's mark out of its environment, no parent. Writes them and all under them to
# $d/all, the conveyor.sh processes among them to $d/procs, their process groups to $d/groups and the case's own to
# $d/group.
left_start() {
  local d=${T%/in} sp far=''
  machine1
  wait_until '[ -e "$SH/run/solo-1" ]' || fail "#1 did not start: $(cat "$SH/machine.out")"
  project side '[]'
  ( export CONVEYOR_MAIN=$P_side CONVEYOR_CARDS=$T/$CASE/side-cards; exec timeout 120 bash "$SRC/conveyor.sh" serve > "$SH/serve.out" 2>&1 ) & sp=$!
  turns 1 "$P_side"
  if [ "$(uname -s)" = Linux ]; then
    project far '[]'
    CONVEYOR_MAIN=$P_far CONVEYOR_CARDS=$T/$CASE/far-cards setsid env -u CONVEYOR_TEST_CASE_ID \
      bash -c 'echo $$ > "$1"; exec bash "$2" serve > "$3" 2>&1' _ "$d/far" "$SRC/conveyor.sh" "$SH/far.out" &
    turns 1 "$P_far"; far=$(cat "$d/far")
    [ "$(ps -o sid= -p "$far" | tr -d ' ')" != "$(ps -o sid= -p "$BASHPID" | tr -d ' ')" ] || fail "the serve under setsid is in the case's session"
    ! tr '\0' '\n' < "/proc/$far/environ" | grep -q '^CONVEYOR_TEST_CASE_ID=' || fail "the serve under setsid has the case's mark in its environment"
  fi
  { below "$mp"; below "$sp"; [ -z "$far" ] || below "$far"; } > "$d/all"
  for p in $(cat "$d/all"); do running "$p" | grep -q 'conveyor\.sh' && echo "$p"; done > "$d/procs"
  ps -o pgid= -p "$(paste -sd, "$d/all")" | tr -d ' ' | sort -u > "$d/groups"; ps -o pgid= -p "$BASHPID" | tr -d ' ' > "$d/group"
}
t_left_killed() { left_start; kill -KILL "$BASHPID"; }
t_left_stays() { left_start; : > "${T%/in}/ready"; while :; do sleep 1; done; } # sleep: the case goes on until it is killed
# That the case inside listed what it started: the machine's Conveyor, the project's loop and the card it builds, and
# the `serve` under timeout, at least, and the `serve` under setsid on Linux; the loop and the session under the
# machine's Conveyor, and the two `serve`, each in a process group that is not the case's.
left_listed() {
  local d=$T/$CASE n=4 g
  [ "$(uname -s)" != Linux ] || n=5
  [ "$(wc -l < "$d/procs")" -ge "$n" ] || fail "the case inside did not list its conveyor.sh processes: $(cat "$d/procs")"
  g=$(grep -cvxF -f "$d/group" "$d/groups"); [ "$g" -ge $((n - 1)) ] || fail "the loop and the session under the machine's Conveyor, and each serve, did not leave the case's process group: $(cat "$d/group" "$d/groups")"
}

# Bug: a case that started `conveyor.sh machine` in the background and was killed before its exit trap ran (the
# runner's timeout) left the machine's Conveyor, its loop and its card running: they wrote on for hours to a file of
# the deleted scratch folder until /tmp was full, and every card's tests on the machine failed. A case killed with
# KILL, with all left_start starts running: when its worker (run_case, as the runner starts it) has reported it, no
# conveyor.sh process of it runs, nor any other process it started: those that are not in the case's process group
# (each loop and session is a group of its own), and the one that is in nothing of the case's, are ended all the same.
t_machineleft() {
  local d=$T/$CASE; mkdir -p "$d/in"
  ( T=$d/in; CASE=left_killed; run_case ) > "$d/report" 2>&1
  [ "$(cat "$d/in/left_killed.rc")" = 137 ] || fail "the case inside was not killed while its machine's Conveyor ran: $(cat "$d/report")"
  left_listed
  [ -z "$(running $(cat "$d/procs") | grep 'conveyor\.sh')" ] || fail "conveyor.sh processes of a killed case run on after it is reported: $(running $(cat "$d/procs"))"
  [ -z "$(running $(cat "$d/all"))" ] || fail "processes of a killed case that left its process group run on after it is reported: $(running $(cat "$d/all"))"
}

# Bug: a runner killed with its workers by a signal none of them can catch (KILL to the runner's process group) ended
# no case: the workers' own ending of their cases never ran, and each case, a process group of its own, ran on with
# its loops. A worker's process group killed with KILL while its case runs, with all left_start starts: nothing of
# the case runs soon after (its keeper, in no group of the runner's, sees the worker gone).
t_machinekilled() {
  local d=$T/$CASE w; mkdir -p "$d/in"
  set -m; ( T=$d/in; CASE=left_stays; run_case ) > "$d/report" 2>&1 & w=$!; set +m
  wait_until '[ -e "$d/ready" ]' || fail "the case inside did not start: $(cat "$d/report" "$d/in/left_stays.out")"
  left_listed
  kill -KILL -- "-$w"; wait "$w" 2>/dev/null
  WAIT_CEILING=20 wait_until '[ -z "$(running $(cat "$d/all"))" ]' 'running $(cat "$d/all")' || fail "processes of a case run on after its worker's process group was killed"
  [ ! -e "$d/in/left_stays.rc" ] || fail "the case inside ended on its own, not with its worker: $(cat "$d/in/left_stays.rc")"
}

# Bug: `conveyor.sh machine` given TERM ended, and the project's loop with it, while the cards the loop was building
# and their sessions ran on with no loop over them; or a process that a session started on that TERM, before it ended
# itself, ran on: it is under nothing the machine's Conveyor knew, and one started in a session of its own (setsid)
# is in no process group it knew either. TERM with a card's session running, which on TERM starts a process that
# ignores TERM (its pid in $SH/spawned) and one in a session of its own (with an empty environment too on Linux,
# where it is found whatever it carries; both pids in $SH/spawned) and ends: within 10 s nothing that ran under the
# machine's Conveyor does, nor do the processes started on TERM.
t_machineterm() { term_ends; }
term_ends() {
  local all pre
  pre=$(cat <<'EOF2'
deaf() { trap "" TERM; while :; do sleep 1; done; } # sleep: a stand-in that goes on until it is killed
apart() { python3 -c 'import subprocess, sys; print(subprocess.Popen(["sleep", "60"], start_new_session=True, env={} if sys.platform == "linux" else None).pid)'; }
trap 'deaf & { echo $!; apart; } > "$STUB/spawned" && mv "$STUB/spawned" "${STUB%/solo/stub}/shared/spawned"; exit' TERM
EOF2
  )
  machine1 '' "$pre"
  wait_until '[ -e "$SH/run/solo-1" ]' || fail "#1 did not start: $(cat "$SH/machine.out")"
  # A card id holds its project's name in letters, digits and hyphens only: with a dot or an underscore in it, the
  # reader of the card a card resumes (jq/rows.jq, from) cuts the id short and the time of its earlier tries is lost.
  jq -se 'length > 0 and all(.card | test("^c[0-9]{8}T[0-9]{6}-so-lo-1-[0-9]+$")) and all(.repo == "so_lo.1")' "$S/conveyor/state/cards.jsonl" >/dev/null \
    || fail "a card id carries the project's name as written: $(jq -sc 'map(.card) | unique' "$S/conveyor/state/cards.jsonl")"
  all=$(below "$mp")
  running $all | grep -q 'stub/claude' || fail "no session of #1 runs under the machine's Conveyor: $(running $all)"
  kill -TERM "$mp"
  # One wait, of 10 s from the TERM: for the session's process started on it, and for that and all the others gone.
  WAIT_CEILING=10 wait_until '[ "$(wc -l < "$SH/spawned")" = 2 ] && [ -z "$(running $all $(cat "$SH/spawned"))" ]' 'cat "$SH/spawned"; running $all $(cat "$SH/spawned")' \
    || fail "10 s after its TERM, the machine's Conveyor has not passed it on to the session (which then starts a process), or it, a process under it, or the one started on its TERM, still runs"
}

# Bug: the machine's Conveyor took a variable of its environment (CONVEYOR_MACHINE_KEPT) as its word that it was the
# reaper of all it starts, so one started with that variable set (whoever starts it sets its environment) was not: the
# process a session started on TERM in a session of its own, with an empty environment, was under nothing the
# machine's Conveyor could find, and ran on after it. t_machineterm's TERM, with that variable set: the same end.
t_machinekept() { export CONVEYOR_MACHINE_KEPT=1; term_ends; }

# Bug: a loop held back wrote why at every turn, the same line each time, so the output of the machine's Conveyor
# grew for as long as it ran (a pack that does not read holds every turn's push and pick: one line a second). Held
# for many turns by the same reason, the loop says it once; and once more when it holds the loop again later.
t_machinesame() {
  local said="so_lo.1: conveyor pack: .*project.json: no such file"
  machine1 '[]'
  said() { grep -c "^$said" "$SH/machine.out"; }
  turns 2 "$S"
  mv "$S/.conveyor/project.json" "$SH/pack"
  wait_until '[ "$(said)" -ge 1 ]' || fail "the loop does not say its pack does not read: $(cat "$SH/machine.out")"
  turns 6 "$S"
  [ "$(said)" = 1 ] || fail "held for 6 turns by one reason, the loop said it $(said) times: $(cat "$SH/machine.out")"
  [ "$(wc -l < "$SH/machine.out")" = 1 ] || fail "the loop wrote more than the reason in those turns: $(cat "$SH/machine.out")"
  cp "$SH/pack" "$S/.conveyor/project.json"; turns 2 "$S"
  rm "$S/.conveyor/project.json"
  wait_until '[ "$(said)" -ge 2 ]' || fail "the loop does not say that its pack, read again since, does not read once more: $(cat "$SH/machine.out")"
  turns 4 "$S"
  [ "$(said)" = 2 ] || fail "held a second time, the loop said its reason $(($(said) - 1)) times: $(cat "$SH/machine.out")"
  kill -TERM "$mp"; wait "$mp" 2>/dev/null
}

# Bug: the machine's Conveyor wrote that its host file's records are not understood at every turn for as long as the
# file did not read, the same line each time. A host file that does not read for many turns: said once; and once
# more when the file, read again since, does not read again.
t_machinehost() {
  local said="conveyor: the records of .*host.json are not understood" H
  machine1 '[]'; H=$XDG_CONFIG_HOME/conveyor/host.json
  said() { grep -c "^$said" "$SH/machine.out"; }
  turns 2 machine
  cp "$H" "$SH/host"; echo '{' > "$H"
  wait_until '[ "$(said)" -ge 1 ]' || fail "the machine's Conveyor does not say its host file does not read: $(cat "$SH/machine.out")"
  turns 4 machine
  [ "$(said)" = 1 ] || fail "with a host file that did not read for 3 turns, the machine's Conveyor said so $(said) times: $(cat "$SH/machine.out")"
  [ "$(wc -l < "$SH/machine.out")" = 1 ] || fail "the machine's Conveyor wrote more than the reason in those turns: $(cat "$SH/machine.out")"
  cp "$SH/host" "$H"; turns 2 machine
  echo '{' > "$H"
  wait_until '[ "$(said)" -ge 2 ]' || fail "the machine's Conveyor does not say that its host file, read again since, does not read once more: $(cat "$SH/machine.out")"
  kill -TERM "$mp"; wait "$mp" 2>/dev/null
}

# Bugs: the whole machine could be paused only by editing the host file by hand, so the Board had no control for it;
# the Board could not say whether the machine is paused or what its cap is, as no record a project gives named them;
# a pause of the machine rewrote a project's own record, so resuming the machine resumed a project its owner paused.
t_machinemode() {
  SH=$T/$CASE/shared; mkdir -p "$SH"; export XDG_CONFIG_HOME=$T/$CASE/config # the machine's folder is the case's own
  project alpha '[]'
  project beta '[]'
  local A=$P_alpha B=$P_beta H=$XDG_CONFIG_HOME/conveyor/host.json out
  loop() { CONVEYOR_MAIN=$1 bash "$SRC/conveyor.sh" "${@:2}"; }
  mkdir -p "${H%/*}"
  jq -n --arg a "$A" --arg b "$B" '{records: [{repo: "alpha", main: $a}, {repo: "beta", main: $b}], cap: 4}' > "$H"
  [ "$(loop "$A" health | jq -c .machine)" = '{"cap":4,"paused":false}' ] || fail "health does not name the machine's settings: $(loop "$A" health | jq -c .machine)"
  loop "$B" control pause >/dev/null || fail "beta's own pause was refused"
  out=$(loop "$A" machine pause) && grep -q "the machine's Conveyor is paused" <<<"$out" || fail "the machine's pause was refused: $out"
  [ "$(jq -c '[.mode, .cap, (.records | map(.repo))]' "$H")" = '["pause",4,["alpha","beta"]]' ] || fail "the pause is not the host file's mode, or it lost a setting or a record: $(cat "$H")"
  # Every project says the machine is paused; a project's own record is as it was.
  [ "$(loop "$A" health | jq -c '[.machine.paused, .machine.cap, .state]')" = '[true,4,"running"]' ] || fail "alpha does not say the machine is paused, or its own record changed: $(loop "$A" health | jq -c '{machine, state}')"
  [ "$(loop "$B" snapshot --fresh | jq -c '[.health.machine.paused, .health.state]')" = '[true,"paused"]' ] || fail "beta's snapshot does not say the machine is paused: $(loop "$B" snapshot --fresh | jq -c '.health | {machine, state}')"
  out=$(loop "$B" machine resume) && grep -q "the machine's Conveyor runs again" <<<"$out" || fail "the machine's resume was refused: $out"
  [ "$(jq -c '[has("mode"), .cap, (.records | length)]' "$H")" = '[false,4,2]' ] || fail "the resume did not take the mode away, or it lost a setting or a record: $(cat "$H")"
  [ "$(loop "$A" health | jq -c .machine.paused)" = false ] || fail "the machine still reads as paused after its resume"
  [ "$(loop "$B" health | jq -r .state)" = paused ] || fail "the machine's resume resumed beta, which its owner paused"
  # Bug: the pause was written under the machine's lock alone, and a lane's note replaces the host file under the
  # host file's own lock: a note that read the file before the pause wrote its older reading over it, and the machine
  # ran on. The pause waits for the host file's lock, so it reads what the note wrote.
  flock "$H.lock" sh -c 'touch "$1.held"; until [ -e "$1.go" ]; do sleep 0.1; done; jq ".noted = true" "$1" > "$1.note" && mv "$1.note" "$1"' sh "$H" & local lk=$!
  until [ -e "$H.held" ]; do sleep 0.1; done
  loop "$A" machine pause >/dev/null & local mp=$!
  # While the lock is held, the pause waits at it (its flock runs) and has neither ended nor written.
  wait_until 'under "$mp" flock || ! kill -0 "$mp" 2>/dev/null'; kill -0 "$mp" 2>/dev/null && [ "$(jq -r '.mode // "none"' "$H")" = none ] \
    || { touch "$H.go"; fail "the machine's pause did not wait for the host file's lock: $(cat "$H")"; }
  touch "$H.go"; wait "$mp" || fail "the machine's pause failed after waiting for the host file's lock"
  wait "$lk"; [ "$(jq -c '[.mode, .noted, .cap]' "$H")" = '["pause",true,4]' ] || fail "the pause or the other writer's change was lost: $(cat "$H")"
  loop "$A" machine resume >/dev/null || fail "the machine's resume was refused"
  # A host file that does not read is left as it is; anything but pause or resume is a usage error.
  echo '{"cap": 4' > "$H"
  ! loop "$A" machine pause >/dev/null 2>&1 && [ "$(cat "$H")" = '{"cap": 4' ] || fail "a host file that does not read was written over"
  jq -n '{}' > "$H"; out=$(loop "$A" machine stop 2>&1); [ $? = 2 ] && grep -q 'usage: conveyor.sh machine \[pause | resume\]' <<<"$out" || fail "machine stop is not a usage error: $out"
  # Issue 347: steer is removed, so `machine steer off` is a usage error and writes no steer to the host file.
  out=$(loop "$A" machine steer off 2>&1); [ $? = 2 ] && [ "$(jq -c . "$H")" = '{}' ] || fail "machine steer is still taken: $out $(cat "$H")"
  # No machine setting: the record's machine is null, as a host file that sets none caps and pauses nothing.
  jq -n --arg a "$A" '{records: [{repo: "alpha", main: $a}]}' > "$H"
  [ "$(loop "$A" health | jq -c .machine)" = null ] || fail "a host file that sets nothing reads as a machine setting: $(loop "$A" health | jq -c .machine)"
}

# Bug: the machine's Conveyor ran every project on its own engine, so the plugin's own belt (served from its checkout,
# its pack naming no plugin to follow or pin) could not run under it: its loop would run the machine's code for good,
# never its checkout's, and install-service left its per-project service running. A record run from its own checkout
# ("engine": "checkout") runs that checkout's conveyor.sh and restarts on the checkout's new code; any other record
# runs the machine's; a record whose engine changes is restarted on the other; an engine mistyped is not taken.
t_machinecheckout() {
  SH=$T/$CASE/shared; mkdir -p "$SH"; export XDG_CONFIG_HOME=$T/$CASE/config # the machine's folder is the case's own
  project alpha '[]'
  project beta '[]'
  dispatch
  local A=$P_alpha B=$P_beta H=$XDG_CONFIG_HOME/conveyor/host.json f h
  # alpha's checkout holds the engine (its conveyor/ beside its state folder), as the plugin's own checkout does.
  for f in "$SRC"/*; do [ "${f##*/}" = state ] || cp -r "$f" "$A/conveyor/" || fail "the engine was not copied into alpha's checkout"; done
  mkdir -p "${H%/*}"
  jq -n --arg a "$A" --arg b "$B" '{records: [{repo: "alpha", main: $a, engine: "checkout"}, {repo: "beta", main: $b}]}' > "$H"
  ( cd "$B" && CONVEYOR_MAIN=$B exec bash "$SRC/conveyor.sh" machine > "$SH/machine.out" 2>&1 ) & mp=$!
  trap 'kill -TERM $mp 2>/dev/null; wait $mp 2>/dev/null' EXIT
  ran() { jq -r ".$2 // empty" "$1/conveyor/state/loop.json" 2>/dev/null; } # <main> <field> of its loop's own record
  h=$(git -C "$A" rev-parse HEAD)
  wait_until '[ "$(ran "$A" checkout)" -ef "$A/conveyor" ] && [ "$(ran "$A" commit)" = "$h" ]' \
    || fail "alpha, run from its own checkout, does not run that checkout's code: $(cat "$A/conveyor/state/loop.json" 2>/dev/null) $(cat "$SH/machine.out")"
  wait_until '[ "$(ran "$B" checkout)" -ef "$SRC" ]' || fail "beta does not run the machine's own code: $(cat "$B/conveyor/state/loop.json" 2>/dev/null)"
  # beta has shown it; its loop stops, so it does not take its turns through the rest (alpha's record is as it was).
  jq 'del(.records[1])' "$H" > "$SH/h" && mv "$SH/h" "$H"
  # The checkout moves on: alpha's loop restarts on its new code, as a `serve` from a checkout does.
  git -C "$A" commit -q --allow-empty -m next && h=$(git -C "$A" rev-parse HEAD)
  wait_until '[ "$(ran "$A" commit)" = "$h" ] && [ "$(ran "$A" checkout)" -ef "$A/conveyor" ]' \
    || fail "alpha's loop did not restart on its checkout's new code: $(cat "$A/conveyor/state/loop.json") $(cat "$SH/machine.out")"
  # Its record no longer says so: its loop is stopped and runs the machine's code.
  jq '.records[0] |= del(.engine)' "$H" > "$SH/h" && mv "$SH/h" "$H"
  wait_until '[ "$(ran "$A" checkout)" -ef "$SRC" ]' || fail "alpha's loop did not move to the machine's code once its record dropped its engine: $(cat "$A/conveyor/state/loop.json")"
  # An engine mistyped: the records are not understood, and no loop runs on an engine its record does not name.
  jq '.records[0].engine = "chekout"' "$H" > "$SH/h" && mv "$SH/h" "$H"
  wait_until 'grep -q "conveyor: the records of .*host.json are not understood" "$SH/machine.out"' || fail "a mistyped engine was taken: $(cat "$SH/machine.out")"
}
