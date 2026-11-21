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
# Issue 357: the watcher's last poll, from its poll log. Bug it catches: a wake 5 minutes late, and nothing told how
# long each poll had taken.
mkdir -p "$FD" && echo '2026-11-15T11:59:00Z 2026-11-15T11:59:47Z 47s alpha: slow, read health; woke' > "$FD/conveyor-polls.log"
echo alpha/blocked:c7 > "$FD/conveyor-reported.txt" # #7 was reported (t_unreported is the case of one that was not)
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
  'watcher: last poll ended 2026-11-15T11:59:47Z, took 47 s (alpha: slow, read health; woke)' \
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
# Bug (#253): a case stopped at its file's `# timeout:` limit (timedout) read as a plain failure, so the Foreman could
# not tell a hung case from a broken one.
snap ".belt = [$(card 3 One build)] | .suites = [$run + {ended: \"2026-11-15T11:59:00Z\", state: \"failed\", done: 140, failed: 2, cases: [\"stall\", \"metrics\"], timedout: [\"metrics\"]}]"
poll || fail "a release run that ended red woke nothing: $(cat "$T/err")"
w=$(cat "$FD"/pending/*.wake)
grep -qxF 'alpha: release 1.2.0 failed on abcdef012345 at 2026-11-15T11:59:00Z; failed cases: stall, metrics (timed out)' <<<"$w" \
  || fail "the wake does not name the result and the failed cases, the timed-out one as timed out: $w"
}

# Issue 240: a full test run whose process was killed ends with no result (the snapshot's suites: an error, with its
# reason). Bug it catches: the wake said only "full test error", so the Foreman could not tell the run never ended.
t_suitedead() {
CASE=suitedead; fixture suitedead
snap '.suites = [{kind: "full test", version: null, step: "push", sha: "abcdef0123456789", since: null, ended: "2026-11-15T11:59:00Z",
  state: "error", done: null, failed: 0, cases: [], moved: false, reasons: ["the run ended without a result: its process (4242) is gone"]}]'
poll || fail "a full test run that ended with no result woke nothing: $(cat "$T/err")"
w=$(cat "$FD"/pending/*.wake)
grep -qxF 'alpha: full test error on abcdef012345 at 2026-11-15T11:59:00Z: the run ended without a result: its process (4242) is gone' <<<"$w" \
  || fail "the wake does not say the run ended with no result: $w"
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

# Issue 248: a merge of the landing pull request that GitHub refused (health's landingPr). Bug it catches: the
# pull request stayed open and the Foreman was never told why.
t_prmerge() {
CASE=prmerge; fixture prmerge
snap '.health.landingPr = {number: 12, url: "https://github.com/o/r/pull/12", cards: 2,
  merge: {time: "2026-11-15T11:59:00Z", by: "idle", sha: "abcdef0123456789", result: "refused", reason: "Pull request is not mergeable: required checks failed"}}'
poll || fail "a refused merge woke nothing: $(cat "$T/err")"
grep -qxF 'alpha: GitHub refused the merge of landing pull request #12, which stays open: Pull request is not mergeable: required checks failed' "$FD"/pending/*.wake \
  || fail "the wake does not give GitHub's reason: $(cat "$FD"/pending/*.wake)"
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
# The health read between the two fails, so it shows no new problem; only the snapshot reads' waits are recorded.
slowask() { # <what the read with the longer wait does>
  export CONVEYOR_FOREMAN_ASK="[ \"\$CONVEYOR_CMD\" = snapshot ] || exit 1; echo \$ASK_LIMIT >> $T/limits; [ \"\$ASK_LIMIT\" -gt 45 ] || exit 124; $1"
  echo "$((NOW - 120)) $((NOW - 60)) 2" > "$FD/conveyor-down-alpha.txt" # two failed polls before this one
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

# Issue 282: after `control resume` put back a card a sign-in failure blocked, its retry rewrote the card records,
# and the next snapshot, made anew from the whole history, ran past the ask's wait (its timeout exit, 124). Bug it
# catches: the status printed "alpha: no snapshot ()" for a minute, as if the engine had failed. The engine says
# first that the snapshot is made anew, and the status line gives that; a stopped read that said nothing is named too.
nosnap() { # <what the ask does>
  export CONVEYOR_FOREMAN_ASK="$1"
  out=$(cd "$M" && bash "$SRC/../conveyor.sh" foreman status 2>&1) || fail "foreman status failed: $out"
  ! grep -qF '()' <<<"$out" || fail "the status has an empty reason: $out"
}
t_nosnapanew() {
CASE=nosnapanew; fixture nosnapanew
nosnap "echo 'conveyor: the snapshot is being made anew from the whole card records (a retry or a resume rewrote them, or the engine changed); this one takes longer' >&2; exit 124"
grep -qxF 'alpha: no snapshot (conveyor: the snapshot is being made anew from the whole card records (a retry or a resume rewrote them, or the engine changed); this one takes longer)' <<<"$out" \
  || fail "the status does not say the snapshot is being made anew: $out"
}
t_nosnapquiet() {
CASE=nosnapquiet; fixture nosnapquiet
nosnap "exit 124"
grep -qxF 'alpha: no snapshot (it took over 45 s and was stopped)' <<<"$out" || fail "the status does not say the read was stopped at its wait: $out"
}

# Issue 359: a snapshot that failed while the loop worked gave "no snapshot" and the tail of a Python stack trace, and
# the Foreman saw nothing of the belt. Bug it catches: a failed read that shows no earlier snapshot, its age or one line
# of reason, that says "no snapshot" when it shows one, or that shows the stack. The poll keeps the one it read; the
# status keeps the one it read, and shows it. The kept copy holds the accounts' email addresses: a copy other users
# can read (made under umask 022) is a bug too.
t_nosnaplast() {
CASE=nosnaplast; fixture nosnaplast; mkdir -p "$FD"
local tb="printf 'Traceback (most recent call last):\n  File \"cardruns.py\", line 53, in main\n    with open(program) as f:\nFileNotFoundError: [Errno 2] No such file or directory: cardruns.jq\n' >&2; exit 1"
snap ".belt = [$(card 3 'Polled' build)]"; (umask 022 && poll)
[ "$(ls -l "$FD/conveyor-snapshot-alpha.json" | cut -c1-10)" = '-rw-------' ] || fail "the kept snapshot is readable by others: $(ls -l "$FD/conveyor-snapshot-alpha.json")"
export CONVEYOR_FOREMAN_ASK="$tb" CONVEYOR_FOREMAN_NOW=$((NOW + 300))
out=$(cd "$M" && bash "$SRC/../conveyor.sh" foreman status 2>&1) || fail "foreman status failed: $out"
for l in 'alpha: the last snapshot, made 5m ago (a new one failed: FileNotFoundError: [Errno 2] No such file or directory: cardruns.jq):' \
  'alpha: 1 on the belt' '  #3 build 17m Polled'; do
  grep -qxF -- "$l" <<<"$out" || fail "no line '$l' in: $out"
done
! grep -qE 'no snapshot|Traceback|File "|open\(' <<<"$out" || fail "the status says no snapshot or shows the stack trace: $out"
snap ".belt = [$(card 4 'Read by status' review)] | .health.time = \"2026-11-15T12:05:00Z\""; export CONVEYOR_FOREMAN_ASK="cat $T/snap"
out=$(cd "$M" && bash "$SRC/../conveyor.sh" foreman status 2>&1) || fail "foreman status failed: $out"
export CONVEYOR_FOREMAN_ASK="$tb" CONVEYOR_FOREMAN_NOW=$((NOW + 330))
out=$(cd "$M" && bash "$SRC/../conveyor.sh" foreman status 2>&1) || fail "foreman status failed: $out"
grep -qxF 'alpha: the last snapshot, made under a minute ago (a new one failed: FileNotFoundError: [Errno 2] No such file or directory: cardruns.jq):' <<<"$out" && grep -qxF '  #4 review 17m Read by status' <<<"$out" \
  || fail "the status does not show the snapshot it read last: $out"
}

# Issue 357: a snapshot made anew from the whole card records runs past the ask's wait (its timeout exit, 124) while
# health lists a blocked card, with the record already 2 minutes without a snapshot. Bug it catches: the watcher read
# health only from the snapshot, and each poll waited for the read with the longer wait too, so the Foreman heard of
# two blocked cards 5 minutes late. Health's blocked card wakes at this poll, with no longer read and no
# "unreachable"; the other kinds stay the snapshot's.
t_healthwake() {
CASE=healthwake; fixture healthwake; mkdir -p "$FD"
snap '.health.blocked = [{card: "c948", issue: 948, since: "2026-11-15T11:58:00Z", reason: "tests failed twice"}] | .health.loop = false | .health'
export CONVEYOR_FOREMAN_ASK="echo \"\$CONVEYOR_CMD \${ASK_LIMIT:-45}\" >> $T/asks; [ \"\$CONVEYOR_CMD\" = health ] && cat $T/snap && exit;
  echo 'conveyor: the snapshot is being made anew from the whole card records; this one takes longer' >&2; exit 124"
echo "$((NOW - 120)) $((NOW - 60)) 2" > "$FD/conveyor-down-alpha.txt"
poll || fail "no wake for the blocked card health lists: $(cat "$T/err")"
w=$(cat "$FD"/pending/*.wake)
grep -qxF 'alpha: #948 is blocked since 2026-11-15T11:58:00Z: tests failed twice' <<<"$w" || fail "the wake does not name the blocked card: $w"
! grep -qF -e 'no loop' -e 'no snapshot' <<<"$w" || fail "the wake holds more than health's blocked card: $w"
[ "$(paste -sd' ' "$T/asks")" = "snapshot 45 health 45" ] || fail "the poll did not read health after the slow snapshot alone: $(cat "$T/asks")"
grep -qxF 'alpha/blocked:c948' "$FD/conveyor-reported.txt" || fail "the blocked card is not marked reported: $(cat "$FD/conveyor-reported.txt")"
# Once reported, the next poll finds the snapshot slow still: the blocked card does not wake again, the longer read
# is made, and with it failing too the record is unreachable; the blocked card stays reported.
: > "$T/asks"; rm -f "$FD"/pending/*.wake
poll || fail "no unreachable wake when both snapshot reads fail: $(cat "$T/err")"
[ "$(paste -sd' ' "$T/asks")" = "snapshot 45 health 45 snapshot 150" ] || fail "the longer read was not made once health had nothing new: $(cat "$T/asks")"
w=$(cat "$FD"/pending/*.wake)
grep -qF 'alpha: no snapshot for 2 minutes' <<<"$w" && ! grep -qF '#948' <<<"$w" || fail "the second wake is not the outage alone: $w"
grep -qxF 'alpha/blocked:c948' "$FD/conveyor-reported.txt" || fail "the blocked card is no longer marked reported"
# A new blocked card in health, with the outage reported: it wakes with no longer read, and the outage stays
# reported. Bug it catches: that poll dropped the unreachable key, so the next failed longer read reported the same
# outage again.
snap '.health.blocked += [{card: "c950", issue: 950, since: "2026-11-15T11:59:00Z", reason: "review said no"}] | .health.loop = false | .health'
: > "$T/asks"; rm -f "$FD"/pending/*.wake
poll || fail "no wake for the second blocked card: $(cat "$T/err")"
w=$(cat "$FD"/pending/*.wake)
grep -qF '#950' <<<"$w" && ! grep -qF -e '#948' -e 'no snapshot' <<<"$w" || fail "the third wake is not the new blocked card alone: $w"
grep -qxF 'alpha/unreachable' "$FD/conveyor-reported.txt" || fail "the outage is no longer marked reported: $(cat "$FD/conveyor-reported.txt")"
rm -f "$FD"/pending/*.wake
poll && fail "the same outage woke again: $(cat "$FD"/pending/*.wake)"
grep -qxF 'alpha/unreachable' "$FD/conveyor-reported.txt" || fail "the outage is not marked reported after the longer read"
# The Foreman closed for 10 minutes, with the outage still marked reported, then a new outage: its first poll reads
# health with no longer read, and on its third poll, three minutes on, the longer read fails too. Bug it catches: that
# first poll kept the old outage's unreachable key, so the new outage never woke. Its second poll is two minutes on, so
# only the count of failed polls holds its wake (#715: the record unreachable wakes on the third failed poll, not the
# second, however long the outage is).
echo "$((NOW - 660)) $((NOW - 600)) 5" > "$FD/conveyor-down-alpha.txt"
poll && fail "the first poll of a new outage woke: $(cat "$FD"/pending/*.wake)"
! grep -qxF 'alpha/unreachable' "$FD/conveyor-reported.txt" || fail "the new outage keeps the old outage's reported key"
CONVEYOR_FOREMAN_NOW=$((NOW + 120)) poll && fail "the second poll of a new outage woke after 2 minutes: $(cat "$FD"/pending/*.wake)"
CONVEYOR_FOREMAN_NOW=$((NOW + 180)) poll || fail "no wake for the new outage on its third poll: $(cat "$T/err")"
grep -qF 'alpha: no snapshot for 3 minutes' "$FD"/pending/*.wake || fail "the wake does not name the new outage: $(cat "$FD"/pending/*.wake)"
}

# Issue 357: each poll writes one line to the poll log: its start, end, time taken, each record's outcome and the read
# it used; the log keeps to its limit. Bug it catches: nothing told how long each poll took, so a late wake could not
# be explained from the logs.
t_polllog() {
CASE=polllog; fixture polllog; mkdir -p "$FD"; snap .
L=$FD/conveyor-polls.log
poll && fail "a snapshot with no problem woke: $(cat "$FD"/pending/*.wake)"
[ "$(wc -l < "$L")" = 1 ] || fail "one poll did not write one line: $(cat "$L")"
grep -Eqx '20[0-9]{2}-[0-9]{2}-[0-9]{2}T[0-9:]{8}Z 20[0-9]{2}-[0-9]{2}-[0-9]{2}T[0-9:]{8}Z [0-9]+s alpha: ok, read snapshot; no wake' "$L" \
  || fail "the line does not give start, end, time and outcome: $(cat "$L")"
export CONVEYOR_FOREMAN_ASK="echo 'the engine is stopped' >&2; exit 1"
for i in $(seq 1000); do echo "old line $i"; done > "$L"
poll
[ "$(wc -l < "$L")" -le 1000 ] || fail "the poll log grew past its limit: $(wc -l < "$L") lines"
tail -n 1 "$L" | grep -Eq ' alpha: failed, read none; no wake$' || fail "the last line is not this poll's failed read: $(tail -n 1 "$L")"
}

# Issue 361: a card blocked two polls ago or more that no session has got is named on the status and in the next
# wake. Bug it catches: a block whose wake reached no session (or that no watcher saw) was told to no one, and the
# Foreman learned of it only when the owner asked. #5: no wake put (not in the reported list); #8: its wake still
# pending; #7: reported and delivered; #6: blocked under two polls ago.
t_unreported() {
CASE=unreported; fixture unreported; mkdir -p "$FD/pending"
b() { echo "{card: \"c$1\", issue: $1, since: \"$2\", reason: \"tests failed twice\"}"; } # <issue> <since>
snap ".health.blocked = [$(b 5 2026-11-15T11:00:00Z), $(b 6 2026-11-15T11:59:30Z), $(b 7 2026-11-15T11:00:00Z), $(b 8 2026-11-15T11:00:00Z)]"
printf '%s\n' alpha/blocked:c6 alpha/blocked:c7 alpha/blocked:c8 > "$FD/conveyor-reported.txt"
old=$FD/pending/20261115T110000Z-1-old.wake
printf '%s\n' 'Conveyor: alpha: blocked: #8' 'alpha: #8 is blocked since 2026-11-15T11:00:00Z: tests failed twice' > "$old"
out=$(CONVEYOR_MAIN=$M bash "$SRC/watch-conveyor.sh" --status 2>&1) || fail "the status failed: $out"
[ "$(grep '^not yet reported: ' <<<"$out")" = $'not yet reported: blocked #5\nnot yet reported: blocked #8' ] \
  || fail "the status does not name exactly the unreported blocked cards #5 and #8: $out"
poll || fail "no wake for the new blocked card #5: $(cat "$T/err")"
w=$(cat "$(find "$FD/pending" -name '*.wake' ! -name "${old##*/}")")
grep -qxF 'alpha: #5 is blocked since 2026-11-15T11:00:00Z: tests failed twice' <<<"$w" || fail "the wake does not name #5: $w"
[ "$(grep 'not yet reported' <<<"$w")" = 'alpha: not yet reported: blocked #8' ] \
  || fail "the wake does not name the pending #8 alone as not yet reported: $w"
}

# Issue 1029: `serve` and all under it were stopped by a stop signal (state T), and the wake said only "#N is stuck:
# no new step and no output", with no cause and no way out. A stopped engine health reads (engineStopped) is one item,
# naming the card it holds, and a stuck card whose own process health reads as stopped (stopped: {pid, of, since}) is
# named so, each since health first read it stopped (not the card's last output), in the status and the wake, with the
# command that resumes it; a held card whose own process is stopped too (own) names that command as well, as resuming
# the engine leaves it stopped; a stuck card with no stopped process reads as before. Their wake comes on the second
# poll that lists them, a poll apart, not the first, as a stuck one's: one reading can catch a stop a SIGCONT soon ends.
# Issue 1039: each command names every stopped process of its tree (health's pids), as one to the engine or the card
# alone left the builder and its timeout wrapper stopped.
# shellcheck disable=SC2016 # the backquotes are the wake's own text, not an expansion
# The engine's process state as ps shows it now (the status reads it again, #1107): `ps -o stat= -p 4242` prints
# <state>, or, with none, nothing and exit 1 as ps does for no such process; any other ps call is the real one.
psstub() { # <state>
  local real; real=$(command -v ps) && mkdir -p "$T/bin" || return
  if [ -n "$1" ]; then printf '#!/usr/bin/env bash\n[ "$*" = "-o stat= -p 4242" ] && { echo %q; exit 0; }\nexec %q "$@"\n' "$1" "$real" > "$T/bin/ps"
  else printf '#!/usr/bin/env bash\n[ "$*" = "-o stat= -p 4242" ] && exit 1\nexec %q "$@"\n' "$real" > "$T/bin/ps"; fi
  chmod +x "$T/bin/ps"; export PATH=$T/bin:$PATH
}
stopsnap() {
snap '.health.engineStopped = {pid: 4242, since: "2026-11-15T11:40:00Z", pids: [4242, 4250]}
  | .needsYou.stopped = {title: "The engine is stopped", reason: "Run kill -CONT 4242 4250 to resume them.", since: "2026-11-15T11:40:00Z", pid: 4242, pids: [4242, 4250]}
  | .health.stuck = [{card: "c5", issue: 5, step: "build", since: "2026-11-15T11:30:00Z", stopped: {pid: 4242, of: "engine", since: "2026-11-15T11:40:00Z"}},
  {card: "c8", issue: 8, step: "build", since: "2026-11-15T11:30:00Z", stopped: {pid: 4242, of: "engine", since: "2026-11-15T11:40:00Z", own: {pid: 4444, since: "2026-11-15T11:45:00Z", pids: [4444, 4450, 4451]}}},
  {card: "c6", issue: 6, step: "review", since: "2026-11-15T11:00:00Z", stopped: {pid: 4343, of: "card", since: "2026-11-15T11:31:00Z", pids: [4343, 4350]}},
  {card: "c7", issue: 7, step: "build", since: "2026-11-15T11:32:00Z"}]'
}
t_stopped() {
CASE=stopped; fixture stopped; stopsnap; psstub T
out=$(CONVEYOR_MAIN=$M bash "$SRC/watch-conveyor.sh" --status 2>&1) || fail "the status failed: $out"
own='; #8'"'"'s own process is stopped too since 2026-11-15T11:45:00Z: `kill -CONT 4444 4450 4451` resumes it'
for l in "needs you: the engine is stopped (state T) since 2026-11-15T11:40:00Z: \`kill -CONT 4242 4250\` resumes it (it holds #5, #8)$own" \
    'needs you: #6: its process is stopped (state T) since 2026-11-15T11:31:00Z: `kill -CONT 4343 4350` resumes it' \
    'needs you: #7 is stuck: no new step and no output since 2026-11-15T11:32:00Z (last step: build)'; do
  grep -qxF -- "$l" <<<"$out" || fail "no line '$l' in: $out"
done
grep -qE '#[568] is stuck|#[58]:' <<<"$out" && fail "the status calls a stopped card stuck, or names the stopped engine's card apart: $out"
poll && fail "the first poll to read the stopped engine woke: $(cat "$FD"/pending/*.wake)"
CONVEYOR_FOREMAN_NOW=$((NOW + 60)) poll || fail "the stopped engine woke nothing on its second poll: $(cat "$T/err")"
w=$(cat "$FD"/pending/*.wake)
grep -qxF 'Conveyor: alpha: stuck: #7; stopped: #5 #8 #6' <<<"$w" || fail "the wake's first line does not name the stopped cards: $w"
grep -qxF "alpha: the engine is stopped (state T) since 2026-11-15T11:40:00Z: \`kill -CONT 4242 4250\` resumes it (it holds #5, #8)$own" <<<"$w" \
  || fail "the wake does not name the stopped engine and how to resume it: $w"
# Issue 1106: the Board's Needs you lists the stopped engine too (needsYou.stopped, a kind of dashboard_needs.json);
# the watcher reads it from health alone, so neither the status nor the wake names it a second time.
! grep -qF 'The engine is stopped' <<<"$out$w" || fail "the stopped engine is named twice, once from the Board's Needs you: $out $w"
}

# Bug (#1107): the status took the engine's state from the snapshot alone, so after `kill -CONT` it still said "the
# engine is stopped (state T)" while the engine (state S) picked cards. The same snapshot as above, the engine now in
# state S: the status says it runs, names it stopped nowhere, and no longer counts #5 held by it; #8's own process,
# stopped too, is still named, as resuming the engine left it stopped, and so is #9's overdue test (bug: the entry
# of a held card with no own stop was dropped whole, its overdue test with it).
# shellcheck disable=SC2016 # the backquotes are the status's own text, not an expansion
t_resumed() {
CASE=resumed; fixture resumed; stopsnap; psstub S
jq '.health.stuck += [{card: "c9", issue: 9, step: "test", since: "2026-11-15T11:20:00Z", cases: ["stall"], stopped: {pid: 4242, of: "engine", since: "2026-11-15T11:40:00Z"}}]' \
  "$T/snap" > "$T/snap.new" && mv "$T/snap.new" "$T/snap" || fail "the snapshot could not be set"
out=$(CONVEYOR_MAIN=$M bash "$SRC/watch-conveyor.sh" --status 2>&1) || fail "the status failed: $out"
grep -qxF 'alpha: the engine (pid 4242) runs (state S now); the snapshot had it stopped since 2026-11-15T11:40:00Z' <<<"$out" \
  || fail "the status does not say the resumed engine runs: $out"
grep -qF 'engine is stopped' <<<"$out" && fail "the status names the resumed engine stopped: $out"
grep -qF '#5' <<<"$out" && fail "the status still names #5, held only by the resumed engine: $out"
grep -qxF 'needs you: #8: its process is stopped (state T) since 2026-11-15T11:45:00Z: `kill -CONT 4444 4450 4451` resumes it' <<<"$out" \
  || fail "the status drops #8, whose own process is still stopped: $out"
grep -qxF 'needs you: #9 is stuck: its test step has had stall running since 2026-11-15T11:20:00Z' <<<"$out" \
  || fail "the status drops #9's overdue test with the engine's stop: $out"
# An engine ps no longer lists has ended: not stopped either.
psstub ''
out=$(CONVEYOR_MAIN=$M bash "$SRC/watch-conveyor.sh" --status 2>&1) || fail "the status failed: $out"
grep -qxF 'alpha: the engine (pid 4242) has ended; the snapshot had it stopped since 2026-11-15T11:40:00Z' <<<"$out" \
  && ! grep -qF 'engine is stopped' <<<"$out" || fail "the status does not say the engine has ended: $out"
}

# Bug (#1107 review): with a host file that names an ssh target, the snapshot is the host's, but ps ran on this
# machine, where the host's engine pid is no process: the status said the engine had ended while it stayed stopped.
# Here ps on this machine says S and the host (an ssh stub) says T: the status reads the host and keeps the stop.
# shellcheck disable=SC2016 # the stub's own text, not an expansion
t_resumedhost() {
CASE=resumedhost; fixture resumedhost; stopsnap; psstub S
jq '.ssh = "devhost"' "$XDG_CONFIG_HOME/conveyor/host.json" > "$T/host.new" && mv "$T/host.new" "$XDG_CONFIG_HOME/conveyor/host.json" || fail "the host file could not be set"
# stub: ssh to the host, answering its ps of the engine's pid; this machine has no host to reach
printf '#!/usr/bin/env bash\n[ "$1 ${*: -1}" = "-o LC_ALL=C ps -o stat= -p 4242" ] && { echo T; exit 0; }\nexit 255\n' > "$T/bin/ssh" && chmod +x "$T/bin/ssh"
out=$(CONVEYOR_MAIN=$M bash "$SRC/watch-conveyor.sh" --status 2>&1) || fail "the status failed: $out"
grep -qF 'needs you: the engine is stopped (state T) since 2026-11-15T11:40:00Z' <<<"$out" \
  && ! grep -qF 'the engine (pid 4242)' <<<"$out" || fail "the status did not read the engine's state on the host: $out"
# The host now has it running: the status says so.
# stub: the same host, its engine resumed
printf '#!/usr/bin/env bash\n[ "$1 ${*: -1}" = "-o LC_ALL=C ps -o stat= -p 4242" ] && { echo S; exit 0; }\nexit 255\n' > "$T/bin/ssh"
out=$(CONVEYOR_MAIN=$M bash "$SRC/watch-conveyor.sh" --status 2>&1) || fail "the status failed: $out"
grep -qxF 'alpha: the engine (pid 4242) runs (state S now); the snapshot had it stopped since 2026-11-15T11:40:00Z' <<<"$out" \
  || fail "the status does not say the host's engine runs: $out"
}

# Bug (#1213): `foreman.sh ask <repo> foreman status` with a host set ran the status over ssh, and its last two lines
# (watcher, waiter) read the host's Foreman folder, where no Foreman runs: "waiter: down: no waiter has run yet" while
# this Foreman's waiter listened. Here the ssh stub answers as such a host (its status ends with those two lines) and
# this side has a live waiter and a poll log: the answer carries this side's lines, and the host's records stay.
# shellcheck disable=SC2016 # the stub's own text, not an expansion
t_askhost() {
CASE=askhost; fixture askhost; unset CONVEYOR_FOREMAN_ASK
jq '.ssh = "devhost"' "$XDG_CONFIG_HOME/conveyor/host.json" > "$T/host.new" && mv "$T/host.new" "$XDG_CONFIG_HOME/conveyor/host.json" || fail "the host file could not be set"
mkdir -p "$T/bin" "$FD" && echo '2026-11-15T11:59:00Z 2026-11-15T11:59:47Z 47s alpha: slow, read health; woke' > "$FD/conveyor-polls.log"
# A live waiter: a process whose argument list names waiter.sh, as waiter_state reads it.
bash -c 'exec -a "$0/conveyor/foreman/waiter.sh" sleep 30' "$T" & wp=$! # sleep: the stand-in for the live waiter process
trap 'kill "$wp" 2>/dev/null' EXIT; echo "$wp" > "$FD/waiter.pid"
# stub: ssh to the host, whose status reads its own empty Foreman folder
printf '#!/usr/bin/env bash\nprintf "%%s\\n" "alpha: 1 on the belt" "watcher: no poll logged yet" "waiter: down: no waiter has run yet; the end of the next turn starts one"\n' > "$T/bin/ssh" && chmod +x "$T/bin/ssh"
out=$(cd "$M" && PATH=$T/bin:$PATH CONVEYOR_MAIN=$M bash "$SRC/foreman.sh" ask alpha foreman status 2>&1) || fail "ask alpha foreman status failed: $out"
[ "$out" = "alpha: 1 on the belt
watcher: last poll ended 2026-11-15T11:59:47Z, took 47 s (alpha: slow, read health; woke)
waiter: listening" ] || fail "ask alpha foreman status (host devhost, live waiter $wp) did not give this Foreman's watcher and waiter: $out"
}

cases=(status wake suite suitedead mainred prmerge building slowlive slowdown nosnapanew nosnapquiet nosnaplast healthwake polllog unreported stopped resumed resumedhost askhost)
# The cases CONVEYOR_SHELL_TEST_CASE names (comma-separated), as the runner selects them; all of them with none set.
SEL=${CONVEYOR_SHELL_TEST_CASE:-${cases[*]}}; SEL=${SEL//,/ }
for c in $SEL; do case " ${cases[*]} " in *" $c "*) ;; *) echo "unknown case $c" >&2; exit 2 ;; esac; done
read -ra cases <<<"$SEL"
for c in "${cases[@]}"; do ("t_$c" && : > "$B/$c.passed") > "$B/$c.out" 2>&1 & done
wait
bad=0
for c in "${cases[@]}"; do
  cat "$B/$c.out" >&2
  [ -e "$B/$c.passed" ] || { bad=1; [ -s "$B/$c.out" ] || echo "FAIL [$c]: ended with no word" >&2; }
done
[ "$bad" = 0 ] || exit 1
echo ok
