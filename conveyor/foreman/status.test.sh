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
# card and the push error.
t_status() {
CASE=status; fixture status
snap '.belt = ['"$(card 3 'Fix the login form on the account page so that it keeps the address typed' build),$(card 4 'Add a field' review),$(card 5 'Speed up tests' tests)"']
  | .queue.waiting = [{issue: 6, title: "Later", waitsFor: [3]}] | .open.held = [{issue: 8}]
  | .health.blocked = [{card: "c7", issue: 7, since: "2026-11-15T11:00:00Z", reason: "tests failed twice"}]
  | .health.pushFailingSince = "2026-11-15T11:59:00Z" | .health.pushError = {reason: "remote rejected the push"}
  | .suites = [{kind: "release", version: "1.2.0", step: "release-prep", sha: "abcdef0123456789", since: "2026-11-15T11:30:00Z", ended: null,
      state: "running", done: 40, of: 120, failed: 2, cases: ["stall", "metrics"], moved: false, reasons: []}]'
out=$(cd "$M" && bash "$SRC/../conveyor.sh" foreman status 2>&1) || fail "foreman status failed: $out"
for l in 'alpha: 3 on the belt' '  #3 build 12m Fix the login form on the account page so that it keeps the' '  #4 review 12m Add a field' \
  '  #5 tests 12m Speed up tests' 'waiting: #6 on #3' 'held: #8' \
  'release 1.2.0 running on abcdef012345 for 30m: 40 of 120 cases done, 2 failed: stall, metrics' \
  'needs you: #7 is blocked since 2026-11-15T11:00:00Z: tests failed twice' \
  'needs you: the push has failed since 2026-11-15T11:59:00Z: remote rejected the push'; do
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

cases=(status wake suite)
for c in "${cases[@]}"; do ("t_$c" && : > "$B/$c.passed") > "$B/$c.out" 2>&1 & done
wait
bad=0
for c in "${cases[@]}"; do
  cat "$B/$c.out" >&2
  [ -e "$B/$c.passed" ] || { bad=1; [ -s "$B/$c.out" ] || echo "FAIL [$c]: ended with no word" >&2; }
done
[ "$bad" = 0 ] || exit 1
echo ok
