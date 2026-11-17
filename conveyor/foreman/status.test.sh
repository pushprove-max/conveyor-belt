#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 60
# The Foreman's status command (`conveyor.sh foreman status`, watch-conveyor.sh --status) and the wakes that carry
# their outcome (watch-conveyor.sh). Bug (#11): a status check took the Foreman 4 to 6 shell calls (snapshot, jq, log
# tails), and a wake needed more calls to learn what it was about; each call re-reads the whole conversation.
set -uo pipefail
SRC=$(cd "$(dirname "$0")" && pwd -P)
B=$(mktemp -d); trap 'rm -rf "$B"' EXIT
cd "$B" || exit 1
unset CONVEYOR_FOREMAN CONVEYOR_FOREMAN_LAUNCH CONVEYOR_MAIN CLAUDE_PROJECT_DIR
fail() { echo "FAIL [$CASE]: $*" >&2; exit 1; }
NOW=$(jq -n '"2026-11-15T12:00:00Z" | fromdate')
# One project, alpha, on a host of its own in $B/<case> (T); its snapshot is the file $T/snap (ask, through
# CONVEYOR_FOREMAN_ASK), its Foreman's folder FD.
fixture() { # <case>
  T=$B/$1 M=$B/$1/alpha
  export XDG_CONFIG_HOME=$T/config XDG_DATA_HOME=$T/data HOME=$T/home CONVEYOR_FOREMAN_DIR=$T/state/foreman CONVEYOR_FOREMAN_NOW=$NOW
  FD=$CONVEYOR_FOREMAN_DIR
  mkdir -p "$XDG_CONFIG_HOME/conveyor" "$HOME" "$M/.conveyor" && git init -q "$M" && echo '{}' > "$M/.conveyor/project.json"
  jq -n --arg s "$T/state" --arg m "$M" '{stateDir: $s, records: [{repo: "alpha", main: $m}]}' > "$XDG_CONFIG_HOME/conveyor/host.json"
  export CONVEYOR_FOREMAN_ASK="cat $T/snap"
}
# A snapshot: its health holds no problem; the jq filter given changes it.
snap() { # <jq filter>
  jq -n "{belt: [], queue: {next: [{issue: 99}], waiting: []}, open: {held: []}, suites: [],
    health: {time: \"2026-11-15T12:00:00Z\", loop: true, gh: true, blocked: [], waiting: [], stuck: [], pushFailingSince: null}} | $1" > "$T/snap"
}
card() { echo "{card: \"c$1\", issue: $1, title: \"$2\", step: \"$3\", stepAt: \"2026-11-15T11:48:00Z\"}"; } # <issue> <title> <step>
poll() { CONVEYOR_MAIN=$M bash "$SRC/watch-conveyor.sh" --once 2>"$T/err"; }

# D1: one call gives the whole state, in plain text, each item on its own line: the cards in flight with their step
# and time in it, a card waiting on others, a held issue, the release run under way with its failed cases, the blocked
# card, the push error and (#157) a card records line set aside with the field the check refused: the loop reads on
# without it, so only the status tells the Foreman it is gone. Last, the Foreman's waiter (#215: the owner saw it down
# and never why): here none has run.
t_status() {
CASE=status; fixture status
snap '.belt = ['"$(card 3 'Fix the login form on the account page so that it keeps the address typed' build),$(card 4 'Add a field' review),$(card 5 'Speed up tests' tests)"']
  | .queue.waiting = [{issue: 6, title: "Later", waitsFor: [3]}] | .open.held = [{issue: 8}]
  | .health.blocked = [{card: "c7", issue: 7, since: "2026-11-15T11:00:00Z", reason: "tests failed twice"}]
  | .health.pushFailingSince = "2026-11-15T11:59:00Z" | .health.pushError = {reason: "remote rejected the push"}
  | .health.quarantined = [{line: 2518, field: "list", time: "2026-11-15T11:57:00Z"}]
  | .suites = [{kind: "release", version: "1.2.0", step: "release-prep", sha: "abcdef0123456789", since: "2026-11-15T11:30:00Z", ended: null,
      state: "running", done: 40, of: 120, failed: 2, cases: ["stall", "metrics"], moved: false, reasons: []}]'
out=$(cd "$M" && bash "$SRC/../conveyor.sh" foreman status 2>&1) || fail "foreman status failed: $out"
for l in 'alpha: 3 on the belt' '  #3 build 12m Fix the login form on the account page so that it keeps the' '  #4 review 12m Add a field' \
  '  #5 tests 12m Speed up tests' 'waiting: #6 on #3' 'held: #8' \
  'release 1.2.0 running on abcdef012345 for 30m: 40 of 120 cases done, 2 failed: stall, metrics' \
  'needs you: #7 is blocked since 2026-11-15T11:00:00Z: tests failed twice' \
  'needs you: the push has failed since 2026-11-15T11:59:00Z: remote rejected the push' \
  'needs you: the card records line 2518 is set aside in quarantined.jsonl: the record check refused its field list' \
  'waiter: down: no waiter has run yet; the end of the next turn starts one'; do
  grep -qxF -- "$l" <<<"$out" || fail "no line '$l' in: $out"
done
grep -q '[{}]' <<<"$out" && fail "the status holds JSON: $out"
[ "$(wc -l <<<"$out")" -le 12 ] || fail "the status holds more than its items: $out"
# A project that is none of the Foreman's is refused, not shown as empty.
out=$(cd "$M" && bash "$SRC/../conveyor.sh" foreman status beta 2>&1) && fail "a project not the Foreman's gave a status: $out"
grep -qF 'beta is none of' <<<"$out" || fail "the refusal does not name the project: $out"
}

# D2: a card moving from build to review wakes no one; an awaited card that landed and another that blocked give one
# wake that names the landed commit and the block reason, so the Foreman need not look them up.
t_wake() {
CASE=wake; fixture wake
mkdir -p "$FD" && echo 3 > "$FD/await-alpha.txt"
snap ".belt = [$(card 3 One build),$(card 4 Two build)]"
poll && fail "a belt with no problem woke the Foreman: $(cat "$FD"/pending/*.wake)"
snap ".belt = [$(card 3 One build),$(card 4 Two review)]"
poll && fail "a card moving from build to review woke the Foreman: $(cat "$FD"/pending/*.wake)"
snap '.belt = [] | .landed = [{card: "c3", issue: 3, sha: "0123456789abcdef0123"}] | .pushedCards = [{card: "c3", issue: 3}]
  | .health.blocked = [{card: "c4", issue: 4, since: "2026-11-15T11:58:00Z", reason: "the review found the change breaks the form"}]'
poll || fail "a landed card and a blocked one woke nothing: $(cat "$T/err")"
[ "$(ls "$FD"/pending/*.wake | wc -l)" = 1 ] || fail "not one wake: $(ls "$FD/pending")"
w=$(cat "$FD"/pending/*.wake)
grep -qxF 'alpha: #3 landed as 0123456789ab: your step is due' <<<"$w" || fail "the wake does not name the landed commit: $w"
grep -qxF 'alpha: #4 is blocked since 2026-11-15T11:58:00Z: the review found the change breaks the form' <<<"$w" || fail "the wake does not name the block reason: $w"
}

# D3: a release run that ends red wakes the Foreman with its result and its failed cases; while it runs, it wakes no one.
# Bug (#26): the wake called the failed names "failed files", but a suite's runner names cases (an engine case by its
# own name, as conveyor/tests/lib.sh marks it), so the Foreman read a case name as a file.
t_suite() {
CASE=suite; fixture suite
run='{kind: "release", version: "1.2.0", step: "release-prep", sha: "abcdef0123456789", since: "2026-11-15T11:30:00Z", ended: null,
  state: "running", done: 40, failed: 1, cases: ["stall"], moved: false, reasons: []}'
snap ".belt = [$(card 3 One build)] | .suites = [$run]"
poll && fail "a release run under way woke the Foreman: $(cat "$FD"/pending/*.wake)"
snap ".belt = [$(card 3 One build)] | .suites = [$run + {ended: \"2026-11-15T11:59:00Z\", state: \"failed\", done: 140, failed: 2, cases: [\"stall\", \"metrics\"]}]"
poll || fail "a release run that ended red woke nothing: $(cat "$T/err")"
w=$(cat "$FD"/pending/*.wake)
grep -qxF 'alpha: release 1.2.0 failed on abcdef012345 at 2026-11-15T11:59:00Z; failed cases: stall, metrics' <<<"$w" \
  || fail "the wake does not name the result and the failed cases: $w"
}

# Bug (#141): a main-red fix card is of issue 0, so the status, the wake and the Foreman's questions called it "#0".
# They name it as health and the snapshot do (name: "Main is red (<commit>)"), and a card waiting on it the same way.
t_mainred() {
CASE=mainred; fixture mainred
red='{card: "c20261115T110000-alpha-0", issue: 0, name: "Main is red (0123456789ab)"}'
snap ".belt = [$red + {title: \"Main is red: stall\", step: \"build\", stepAt: \"2026-11-15T11:48:00Z\"},
    $(card 3 One build) + {step: \"waiting\", waitsOn: ($red + {state: \"build\"})}]"
out=$(cd "$M" && bash "$SRC/../conveyor.sh" foreman status 2>&1) || fail "foreman status failed: $out"
for l in '  Main is red (0123456789ab) build 12m Main is red: stall' '  #3 waiting on Main is red (0123456789ab) 12m One'; do
  grep -qxF -- "$l" <<<"$out" || fail "no line '$l' in: $out"
done
grep -qF '#0' <<<"$out" && fail "the status calls the main-red card #0: $out"
snap ".health.blocked = [$red + {since: \"2026-11-15T11:58:00Z\", reason: \"tests failed twice\"}]"
poll || fail "a blocked main-red card woke nothing: $(cat "$T/err")"
w=$(cat "$FD"/pending/*.wake)
grep -qxF 'Conveyor: alpha: blocked: Main is red (0123456789ab)' <<<"$w" || fail "the wake's first line does not name the card: $w"
grep -qxF 'alpha: Main is red (0123456789ab) is blocked since 2026-11-15T11:58:00Z: tests failed twice' <<<"$w" || fail "the wake does not name the card: $w"
! grep -qF '#0' <<<"$w" || fail "the wake calls the main-red card #0: $w"
}

# Issue 201: a card that only waits on another card takes no build slot, and the status says so. Bug it catches: the
# owner saw three cards on the belt with the cap at 3 and could not tell one of them was waiting and held no slot.
t_building() {
CASE=building; fixture building
snap ".belt = [$(card 3 One build),$(card 4 Two land)] | .health.builderCap = 1 | .health.building = 1 | .health.waitingCount = 1"
out=$(cd "$M" && bash "$SRC/../conveyor.sh" foreman status 2>&1) || fail "foreman status failed: $out"
grep -qxF 'alpha: 2 on the belt; building 1 of the cap 1, 1 waiting not counted' <<<"$out" || fail "the status does not give the count against the cap without the waiting card: $out"
}

# Issue 241: a snapshot read that takes longer than the ask's first wait (45 s), here as the ask's timeout exit, after 2
# minutes with no snapshot. Bug it catches: under a high machine load the live engine's snapshot ran past the wait,
# and the Foreman was woken with "unreachable" while the engine ran. The read is tried once more with a longer wait.
slowask() { # <what the read with the longer wait does>
  export CONVEYOR_FOREMAN_ASK="echo \$ASK_LIMIT >> $T/limits; [ \"\$ASK_LIMIT\" -gt 45 ] || exit 124; $1"
  echo "$((NOW - 120)) $((NOW - 60))" > "$FD/conveyor-down-alpha.txt"
}
t_slowlive() {
CASE=slowlive; fixture slowlive; mkdir -p "$FD"
snap .; slowask "cat $T/snap"
poll && fail "a slow but live engine woke the Foreman: $(cat "$FD"/pending/*.wake)"
[ "$(paste -sd' ' "$T/limits")" = "45 150" ] || fail "the snapshot was not read once more with the longer wait: $(cat "$T/limits")"
[ ! -e "$FD/conveyor-down-alpha.txt" ] || fail "the outage is still timed after a snapshot read"
}
# The same slow read with the engine stopped: the read with the longer wait fails too, and the wake comes at the
# same poll as before. Bug it catches: a retry that hid a real outage.
t_slowdown() {
CASE=slowdown; fixture slowdown; mkdir -p "$FD"
slowask "echo 'the engine is stopped' >&2; exit 1"
poll || fail "no wake for an engine stopped 2 minutes: $(cat "$T/err")"
grep -qF 'alpha: no snapshot for 2 minutes (the engine is stopped' "$FD"/pending/*.wake || fail "the wake does not name the outage:$(cat "$FD"/pending/*.wake)"
}

cases=(status wake suite mainred building slowlive slowdown)
for c in "${cases[@]}"; do ("t_$c" && : > "$B/$c.passed") > "$B/$c.out" 2>&1 & done
wait
bad=0
for c in "${cases[@]}"; do
  cat "$B/$c.out" >&2
  [ -e "$B/$c.passed" ] || { bad=1; [ -s "$B/$c.out" ] || echo "FAIL [$c]: ended with no word" >&2; }
done
[ "$bad" = 0 ] || exit 1
echo ok
