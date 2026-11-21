#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 300
# Engine cases: one Conveyor per machine (`conveyor.sh machine`): the machine cap, the turn between projects, the
# records it serves and doctor's count of loops. machineend.test.sh has the rest; project() and dispatch() are lib.sh's.
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"
# The engine folder, as lib.sh sets it: named here too, so the release closure (tools/closure.sh) follows this file's paths.
SRC=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
# doctor's line on the loops of this machine, and its exit status: doctorloops() (lib/setup.sh) called in <main> with
# the engine read as commands/doctor.sh reads it. The whole doctor took a case 5 to 30 s a call, in checks (the Board,
# the pack, the CLIs) that these cases do not look at.
loopline() { (cd "$1" && export CONVEYOR_MAIN=$1 && . "$SRC/conveyor.sh" state-dir > /dev/null && eval "$(grep '^\. "\$HERE/lib/' "$SRC/commands/doctor.sh")" && doctorloops) 2>&1; } # <main>
picked() { jq -e --argjson n "$2" 'select(.step == "picked" and .issue == $n)' "$3/conveyor/state/cards.jsonl" >/dev/null 2>&1; } # <name> <issue> <main>

# Bugs: one project's card is written to, or pushed with, the other's records, kept work or repo; a blocked card of
# one project wakes the other's Foreman. One run of two projects under the machine's Conveyor, as only a whole run
# shows what each card writes and pushes where; the cap and the turn between projects are room()'s, checked by
# t_machinegate.
t_machinecap() {
  SH=$T/$CASE/shared; mkdir -p "$SH"; export XDG_CONFIG_HOME=$T/$CASE/config # the machine's folder is the case's own
  project alpha "[$(issue 1 2026-01-01)]"
  project beta "[$(issue 21 2026-01-01), $(issue 23 2026-01-03)]"
  dispatch; watchturns
  # shellcheck disable=SC2154 # P_alpha and P_beta are set by project(), with printf -v
  local A=$P_alpha B=$P_beta fp
  mkdir -p "$XDG_CONFIG_HOME/conveyor"
  # A machine cap of 2, which the two projects' three cards share. Every build goes on at once: #1 and #21 land, and
  # #23 is blocked (its build fails).
  jq -n --arg a "$A" --arg b "$B" '{records: [{repo: "alpha", main: $a}, {repo: "beta", main: $b}], cap: 2}' > "$XDG_CONFIG_HOME/conveyor/host.json"
  : > "$SH/go"
  ( cd "$A" && CONVEYOR_MAIN=$A exec bash "$SRC/conveyor.sh" machine > "$SH/machine.out" 2>&1 ) & mp=$!
  trap 'kill -TERM $mp 2>/dev/null; wait $mp 2>/dev/null' EXIT
  out() { cat "$SH/machine.out"; }
  # One loop per machine: doctor names the machine's as the one loop (the projects' loops it started are under it),
  # and a second machine loop is refused. Asked once each project's loop has picked a card, so both run.
  wait_until 'picked alpha 1 "$A" && picked beta 21 "$B"' || fail "alpha and beta did not pick a card each: $(out)"
  out=$(loopline "$A")
  grep -qx "ok: one Conveyor loop on this machine: the machine's Conveyor (pid $mp)" <<<"$out" || fail "doctor did not name the machine's loop: $out"
  (cd "$B" && CONVEYOR_MAIN=$B exec bash "$SRC/conveyor.sh" machine > "$SH/second.out" 2>&1); [ $? != 0 ] && grep -q "the machine's Conveyor already runs" "$SH/second.out" \
    || fail "a second machine loop started: $(cat "$SH/second.out")"
  ended() { jq -ne --slurpfile a "$A/conveyor/state/cards.jsonl" --slurpfile b "$B/conveyor/state/cards.jsonl" \
    '($a | map(select(.step == "landed")) | length) == 1 and ($b | map(select(.step == "landed")) | length) == 1 and any($b[]; .step == "blocked" and .issue == 23)' >/dev/null; }
  wait_until ended || fail "the cards did not end: $(out)"
  # Each project's records, kept work and pushes are its own.
  [ "$(jq -sc 'map(.issue) | unique' "$A/conveyor/state/cards.jsonl")" = '[1]' ] && [ "$(jq -sc 'map(.issue) | unique' "$B/conveyor/state/cards.jsonl")" = '[21,23]' ] \
    || fail "a project's records hold another's cards"
  jq -se 'all(.repo == "alpha")' "$A/conveyor/state/cards.jsonl" >/dev/null && jq -se 'all(.repo == "beta")' "$B/conveyor/state/cards.jsonl" >/dev/null \
    || fail "a record line does not name its project"
  jq -se 'all(.card | test("^c[0-9]{8}T[0-9]{6}-alpha-[0-9]+$"))' "$A/conveyor/state/cards.jsonl" >/dev/null \
    && jq -se 'all(.card | test("^c[0-9]{8}T[0-9]{6}-beta-[0-9]+$"))' "$B/conveyor/state/cards.jsonl" >/dev/null \
    || fail "a card id does not name its project, so two projects' cards of one issue and second share it: $(jq -sc 'map(.card) | unique' "$A/conveyor/state/cards.jsonl" "$B/conveyor/state/cards.jsonl")"
  [ -d "$B/conveyor/state/kept" ] && [ ! -e "$A/conveyor/state/kept" ] || fail "beta's blocked card's work was not kept in beta's own state folder"
  wait_until '[ "$(git -C "$T/$CASE/alpha/origin" ls-tree --name-only main | grep "^f" | tr "\n" " ")" = "f1.txt " ]' \
    && wait_until '[ "$(git -C "$T/$CASE/beta/origin" ls-tree --name-only main | grep "^f" | tr "\n" " ")" = "f21.txt " ]' \
    || fail "a push went to another project's repo: $(git -C "$T/$CASE/alpha/origin" ls-tree --name-only main) / $(git -C "$T/$CASE/beta/origin" ls-tree --name-only main)"
  # beta's blocked card wakes beta's Foreman, never alpha's. The machine's Conveyor is stopped first, so its loops
  # do not turn while each Foreman reads its records (a loop down is told only after minutes: DOWN_S,
  # foreman/watch-conveyor.sh); the two Foremen read at once.
  kill -TERM $mp; wait $mp 2>/dev/null
  export CONVEYOR_FOREMAN_ASK="cd \"\$CONVEYOR_MAIN\" && bash $SRC/conveyor.sh \$CONVEYOR_CMD"
  (cd "$A" && CONVEYOR_MAIN=$A exec bash "$SRC/foreman/watch-conveyor.sh" --once >/dev/null 2>&1) & fp=$!
  (cd "$B" && CONVEYOR_MAIN=$B bash "$SRC/foreman/watch-conveyor.sh" --once >/dev/null 2>&1) || fail "beta's blocked card woke nothing"
  wait $fp
  grep -qF '#23 is blocked' "$B"/conveyor/state/foreman/pending/*.wake 2>/dev/null || fail "beta's Foreman was not woken by its blocked card"
  ! grep -qs '#23\|beta' "$A"/conveyor/state/foreman/pending/*.wake || fail "beta's blocked card woke alpha's Foreman"
}

# Under a machine cap of 1, the slot file of the loop of the project alpha, which is gone (a pid that has ended), with
# <started> as its start time and its card running: that card holds alpha's run lock (taken here by this case, as a
# card holds it: run(), lib/run.sh). room() is asked by this project's loop (none of its cards running; the engine read
# as commands/run.sh reads it) while the lock is held, and again once it is let go. For t_machinekill and t_machinegone.
goneroom() { # <started> <the loop gone, for the failure>
  export XDG_CONFIG_HOME=$T/$CASE/config # the machine's folder is the case's own
  setup '[]'
  local H=$XDG_CONFIG_HOME/conveyor/host.json d lk why; mkdir -p "${H%/*}/machine/slots"
  jq -n --arg r "$R" '{records: [{repo: "solo", main: $r}], cap: 1}' > "$H"
  true & d=$!; wait "$d"
  jq -n --argjson p "$d" --arg t "$1" --arg u "$T/$CASE/alpha.run" '{pid: $p, started: $t, running: 1, wants: false, last: 1, run: $u}' > "${H%/*}/machine/slots/alpha.json"
  exec {lk}>>"$T/$CASE/alpha.run" && flock "$lk" || fail "alpha's card did not take its run lock"
  ask() { (cd "$R" && export CONVEYOR_MAIN=$R && . "$SRC/conveyor.sh" state-dir > /dev/null && eval "$(grep '^\. "\$HERE/lib/' "$SRC/commands/run.sh")" && RUNNING=0 room 21); }
  ! why=$(ask) && [ "$why" = "waiting for a machine slot: 1 of the machine cap 1 in use" ] \
    || fail "#21 started past the machine cap while the card of $2 held its run lock: ${why:-a slot was given}"
  exec {lk}>&- # alpha's card ends
  why=$(ask) || fail "#21 never got the slot once the card of $2 ended: $why"
}
# Bugs: a project's loop killed with its cards still building frees their machine slots, so another project starts
# cards past the machine cap beside them; once they end, the slots are never freed.
t_machinekill() { goneroom 'Fri Nov 20 20:11:45 2026' "alpha's killed loop"; }
# A loop killed while it wrote its slot file leaves it with no start time (its `ps` found it gone). Bug: read split on
# tabs, that empty field shifted the rest, so the run lock its card still holds read as none and the card was not
# counted: a card started past the machine cap.
t_machinegone() { goneroom '' "alpha's loop, its slot file with no start time,"; }

# Bugs: the last project is removed from the host file (its records an empty list) and its loop goes on running and
# picking cards; a host file cut short for a moment stops a project's loop.
t_machineempty() {
  SH=$T/$CASE/shared; mkdir -p "$SH"; export XDG_CONFIG_HOME=$T/$CASE/config # the machine's folder is the case's own
  project solo '[]'
  dispatch; watchturns
  local S=$P_solo H=$XDG_CONFIG_HOME/conveyor/host.json lp; mkdir -p "$XDG_CONFIG_HOME/conveyor"
  jq -n --arg s "$S" '{records: [{repo: "solo", main: $s}], cap: 3}' > "$H"
  # The records as the machine's loop reads them at each turn (projects(), lib/machine.sh): one that does not read
  # (known empty in machineloop) stops no loop; records that read as none stop every loop. The engine is read once,
  # while the host file reads (one started while it does not cannot name its state folder).
  ( cd "$S" && export CONVEYOR_MAIN=$S && . "$SRC/conveyor.sh" state-dir > /dev/null && . "$SRC/lib/machine.sh" || fail "the engine could not be read"
    r=$(projects 2>&1) && [ "$r" = "solo"$'\t'"$S"$'\t' ] || fail "solo's record did not read: $r"
    # The host file cut short: its records are not known.
    : > "$H"; ! r=$(projects 2>&1) && [ "$r" = "conveyor: the records of $H are not understood" ] || fail "a host file cut short read as records: '$r'"
    # No records, then text that is not JSON: the file does not read as a whole, so its empty records are not believed.
    echo '{"records":[]} garbage' > "$H"; ! r=$(projects 2>&1) || fail "a host file with text after its value read as records: '$r'"
    echo '{"records":[],"cap":3}' > "$H"; r=$(projects 2>&1) && [ -z "$r" ] || fail "a host file of no records did not read as none: '$r'"
  ) || exit 1
  jq -n --arg s "$S" '{records: [{repo: "solo", main: $s}], cap: 3}' > "$H"
  ( cd "$S" && CONVEYOR_MAIN=$S exec bash "$SRC/conveyor.sh" machine > "$SH/machine.out" 2>&1 ) & mp=$!
  trap 'kill -TERM $mp 2>/dev/null; wait $mp 2>/dev/null' EXIT
  out() { cat "$SH/machine.out"; }
  wait_until 'kill -0 "$(jq -er .pid "$S/conveyor/state/loop.json" 2>/dev/null)" 2>/dev/null' || fail "solo's loop did not start: $(out)"
  lp=$(jq -er .pid "$S/conveyor/state/loop.json")
  # The last project removed: its loop is stopped, and its next issue is never picked.
  echo '{"records":[],"cap":3}' > "$H"
  wait_until "! kill -0 $lp 2>/dev/null" || fail "solo's loop still runs after its record, the last, was removed: $(out)"
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
# and one that could not write would run unseen), in a checkout of any name (a tab in it here). And the loops of two
# records on their own (the machine's gone, as with per-project services) are two loops. doctorloops() is called on
# the machine's files made by hand; each process is a stand-in that sleeps, a loop one a bash that runs a file named
# conveyor.sh with serve, as doctor finds a loop.
t_machinestray() {
  SH=$T/$CASE/shared; export XDG_CONFIG_HOME=$T/$CASE/config # the machine's folder is the case's own
  local A=$T/$CASE/alpha G=$T/$CASE/beta B=$T/$CASE/$'be\tta' MS=$XDG_CONFIG_HOME/conveyor/machine out rc ka kb
  mkdir -p "$SH" "$B" "$MS/slots" "$A/conveyor/state" "$G/conveyor/state"
  for r in "$A" "$G"; do git init -q -b main "$r" || fail "the repo $r was not made"; done
  jq -n --arg a "$A" '{records: [{repo: "alpha", main: $a}]}' > "$XDG_CONFIG_HOME/conveyor/host.json"
  printf 'sleep 60 & trap "kill $!" TERM; wait\n' > "$SH/conveyor.sh" # sleep: a stand-in for a running process
  cp "$SH/conveyor.sh" "$SH/edit.sh"
  named() { jq -n --argjson p "$2" --arg t "$(p_started "$2")" '{pid: $p, started: $t}' > "$1"; } # <file> <pid>: the file a loop writes, naming that process
  ran() { wait_until "[ \"\$(ps -o args= -p $1)\" = '$2' ]" || fail "the stand-in $1 did not start: $2"; } # <pid> <its arguments>: it has made its exec
  sleep 60 & mp=$!; named "$MS/loop.json" "$mp" # sleep: the machine's Conveyor
  # The loop names the machine's host file by another path to it (a slash at the end): it is the same host file. It
  # leaves its slot file in the machine's folder.
  ( cd "$B" && XDG_CONFIG_HOME=$XDG_CONFIG_HOME/ exec bash "$SH/conveyor.sh" serve ) & bp=$! # loop: a stand-in that sleeps, no loop run
  # A process that is no loop, in the same checkout with the same environment, its arguments ending as a loop's do (an
  # editor with the engine open, a script handed its path): doctor counts no loop for it.
  ( cd "$B" && exec bash "$SH/edit.sh" "$SH/conveyor.sh" run ) & ep=$!
  trap 'kill -TERM $mp $bp $ep ${la:-} ${lb:-} 2>/dev/null; wait $mp $bp $ep ${la:-} ${lb:-} 2>/dev/null' EXIT
  ran "$bp" "bash $SH/conveyor.sh serve"; ran "$ep" "bash $SH/edit.sh $SH/conveyor.sh run"; named "$MS/slots/be-tta.json" "$bp"
  out=$(loopline "$A")
  grep -qxF "missing: one Conveyor loop on this machine: a loop of $B, no record of the host file, on its own (pid $bp) runs beside the machine's Conveyor (pid $mp); fix: stop every loop but the machine's (a per-project service: systemctl --user disable --now conveyor-<name>.service, or launchctl bootout gui/\$(id -u)/conveyor.<name>), then run install-service once" <<<"$out" \
    || fail "doctor did not name the loop of the project that is no record: $out"
  # Once that loop is stopped, what it left in the machine's folder names no loop; and a loop of another host file is
  # another machine's, as every other test's loops are: the machine's is the one loop.
  kill -TERM $bp; wait $bp 2>/dev/null
  ( cd "$B" && XDG_CONFIG_HOME=$T/$CASE/other exec bash "$SH/conveyor.sh" serve ) & bp=$! # loop: a stand-in that sleeps, no loop run
  ran "$bp" "bash $SH/conveyor.sh serve"
  out=$(loopline "$A")
  grep -qx "ok: one Conveyor loop on this machine: the machine's Conveyor (pid $mp)" <<<"$out" \
    || fail "doctor named a loop that no longer runs, a process that is no loop (pid $ep) or a loop of another host file (pid $bp): $out"
  # The machine's Conveyor gone, and the loops of two records running on their own: each holds its project's run lock
  # (here this case does, KA and KB) and names itself in its loop.json. doctor names the second, and fails.
  kill -TERM $mp; wait $mp 2>/dev/null
  jq -n --arg a "$A" --arg b "$G" '{records: [{repo: "alpha", main: $a}, {repo: "beta", main: $b}]}' > "$XDG_CONFIG_HOME/conveyor/host.json"
  sleep 60 & la=$!; sleep 60 & lb=$! # sleep: the two loops
  named "$A/conveyor/state/loop.json" "$la"; named "$G/conveyor/state/loop.json" "$lb"
  exec {ka}>>"$A/conveyor/state/cards.jsonl.run" {kb}>>"$G/conveyor/state/cards.jsonl.run" && flock "$ka" && flock "$kb" || fail "the loops' run locks were not taken"
  out=$(loopline "$A"); rc=$?
  [ "$rc" = 1 ] && grep -q "^missing: one Conveyor loop on this machine: a loop of beta on its own (pid $lb) runs beside a loop of alpha on its own (pid $la)" <<<"$out" \
    || fail "doctor did not name the second loop, or did not count it as missing (exit $rc): $out"
}

# Bugs: the old machine-room settings of a host file (maxLoad, minFreeMemMB, pressure) still hold a card back, however
# the machine reads (issue 346: the machine room is removed, the caps and the test slots are the only limits); a host
# file cut short, or a link to settings that are taken away (there, and not reading, so not absent), reads as no host
# file, and the card passes every machine gate; once it reads again, the card is still held. Two projects on one
# machine each run up to their own cap, so their cards add up past the machine's; one project holds every slot while
# the other has work and waits for good; a card the machine cap holds back does not say why in health or on the
# Board. room(), as the loop's pick asks it for its next card, beside the slot files of the loops of alpha and beta
# made by hand.
t_machinegate() {
  export XDG_CONFIG_HOME=$T/$CASE/config # the machine's folder is the case's own
  setup '[]'
  local H=$XDG_CONFIG_HOME/conveyor/host.json M=$T/$CASE/room why lk snap; mkdir -p "${H%/*}"
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
  # A machine cap of 2. A loop's slot file (MACH/slots/<project>.json): <running> cards, whether one <wants> a slot,
  # and the <last> slot it got; its loop alive (this case's runner stands in for it).
  jq -n --arg r "$R" '{records: [{repo: "solo", main: $r}], cap: 2}' > "$H"
  slot() { jq -n --argjson p "$$" --arg t "$(p_started $$)" --argjson r "$2" --argjson w "$3" --argjson l "$4" '{pid: $p, started: $t, running: $r, wants: $w, last: $l}' > "$MACH/slots/$1.json"; } # <project> <running> <wants> <last>
  # alpha runs a card and this loop one: no third. This loop's slot file says its card waits, in the slots' folder:
  # beside the machine loop's own file (MACH/loop.json), a project named loop would overwrite it.
  slot alpha 1 false 1
  RUNNING=1 held 6 "waiting for a machine slot: 2 of the machine cap 2 in use" || fail "#6 started past the machine cap of 2: $why"
  [ "$(jq -c '[.running, .wants]' "$MACH/slots/solo.json")" = '[1,true]' ] || fail "this loop's slot file does not say its card waits: $(cat "$MACH/slots/solo.json")"
  # #6 open and its loop running (it holds the run lock: here this case does), health says why #6 waits, and so does
  # the Board's queue row: the snapshot's queue.order (dashboard.sh's boardOf), whose room board.js draws
  # (dashboard-view.overview.test.mjs, "a card the machine holds back"). Bug: the held card's row did not say why.
  echo "[$(issue 6 2026-01-01)]" > "$STUB/issues.json"
  exec {lk}>>"$STATE.run" && flock "$lk" || fail "the loop's run lock was not taken"
  snap=$(bash "$SRC/conveyor.sh" snapshot --fresh); exec {lk}>&-
  jq -e '.health.room.reason == "waiting for a machine slot: 2 of the machine cap 2 in use"' <<<"$snap" >/dev/null \
    || fail "health does not say the held card waits for a machine slot: $(jq -c '.health.room' <<<"$snap")"
  jq -e '[.queue.order[] | select(.issue == 6)] | length == 1 and .[0].room == "waiting for a machine slot: 2 of the machine cap 2 in use"' <<<"$snap" >/dev/null \
    || fail "the Board's queue row of the held #6 does not say why it waits: $(jq -c .queue.order <<<"$snap")"
  # A slot free (this loop runs none), and beta's card waits too: beta got its last slot (1) before this project
  # (3), so beta goes first.
  slot beta 0 true 1; slot solo 0 true 3
  held 7 "waiting for a machine slot: beta got its last slot before this project and goes first" || fail "#7 took the free slot though beta waited and this project had the last one: $why"
  # beta's card waits no more (it got its slot, or beta was paused): the slot is this project's, counted in its file
  # as the machine's next turn (5 granted before it, so 6), and the machine counts it. Bug: a grant that kept the
  # last turn number put this project at the same place in the round-robin again, so it went first once more.
  slot beta 0 false 1; echo 5 > "$MACH/seq"
  gate 7 && [ ! -e "$ROOMF" ] && [ "$(jq -c '[.running, .wants, .last]' "$MACH/slots/solo.json")" = "[1,false,6]" ] && [ "$(cat "$MACH/seq")" = 6 ] \
    || fail "#7 did not get the free slot, or its slot file or the machine's count does not count it as turn 6: $why $(cat "$MACH/slots/solo.json" "$MACH/seq")"
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
