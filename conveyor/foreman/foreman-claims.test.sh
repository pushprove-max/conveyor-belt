#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 120
# Foreman mode's claims (foreman.sh claim, lib.sh locked, waiter.sh --start): claims at once, the waits at
# claim.lock while the lock changes hands or one holder keeps it, and the start's line on an old engine. The other
# Foreman session cases are in foreman-session.test.sh.
set -uo pipefail
SRC=$(cd "$(dirname "$0")" && pwd -P)
# A wait that never ends fails here, with its condition, well before the file's time limit stops it with no word.
export WAIT_CEILING=30
. "$SRC/../tests/wait.sh"
. "$SRC/../lib/portable.sh"; p_tools
# Each case (t_<case>) runs side by side with the others, on a host of its own made by fixture in $B/<case> (T); a
# case that goes on from what another left (the Foreman set up, a name, a mark) makes that itself first.
B=$(mktemp -d)
# A waiter that delivers a wake leaves a waiter listening (waiter.sh handoff), which ends with the session's process:
# here a stand-in, ended with the test, and no child of it, so the wait for the cases below does not wait for it.
export CONVEYOR_FOREMAN_SESSION_PID; CONVEYOR_FOREMAN_SESSION_PID=$(sleep 600 > /dev/null 2>&1 & echo $!) # sleep: the stand-in for the session's process
trap 'kill $CONVEYOR_FOREMAN_SESSION_PID; rm -rf "$B"' EXIT
# Bug (issue 452): with no CONVEYOR_MAIN, the engine runs for the checkout of the folder it runs in (foreman/lib.sh,
# the git common dir). A draft of t_auto ran `foreman.sh claim a3a3a3a3-0000` in the folder the test was started
# from, a card's worktree, so the claim went to the real main checkout's conveyor/state/foreman. Every case runs
# from this temporary folder, in no checkout: an engine call that names no fixture checkout runs for none.
cd "$B" || exit 1
fail() { echo "FAIL [$CASE]: $*" >&2; exit 1; }
# What the Foreman's launcher exports (foreman.sh launch), and Claude Code's CLAUDE_PROJECT_DIR, name the real main
# checkout and its Foreman; the loop also runs with CONVEYOR_MAIN set (machine.sh), so its cards inherit it. A case
# that sets none of its own would run for that checkout: t_setup's launch (conveyor.sh foreman) would launch for it.
unset CONVEYOR_FOREMAN CONVEYOR_FOREMAN_DIR CONVEYOR_FOREMAN_ASK CONVEYOR_FOREMAN_LAUNCH CONVEYOR_MAIN CLAUDE_PROJECT_DIR CLAUDE_CODE_PROMPT_CACHE_TTL
# A claim opens the Board in the browser (board-open.test.sh, with a stub opener); here no claim may open a real one.
export CLAUDE_PLUGIN_OPTION_boardAutoOpen=false
export CLAUDE_PLUGIN_ROOT=$SRC/../.. PLUGIN=$SRC/../..
PIN=0123456789abcdef0123456789abcdef01234567 PIN2=89abcdef0123456789abcdef0123456789abcdef
fixture() { # <case>
T=$B/$1
export XDG_CONFIG_HOME=$T/config XDG_DATA_HOME=$T/data XDG_STATE_HOME=$T/xstate HOME=$T/home
mkdir -p "$XDG_CONFIG_HOME/conveyor" "$HOME"
# Two project checkouts: alpha is the main checkout the Foreman runs in, beta another record of the same host.
for r in alpha beta; do
  git init -q "$T/$r" && mkdir -p "$T/$r/.conveyor" && jq -n --arg p "$PIN" '{plugin: {commit: $p}}' > "$T/$r/.conveyor/project.json"
done
# alpha and beta are linked (one group, foreman.groups), so they share one Foreman, whose folder (FD: its mark, state
# and wakes) is in alpha's state folder; the case projects (foreman-projects.test.sh) has a Foreman per project.
M=$T/alpha ST=$T/state FD=$T/state/foreman
jq -n --arg s "$ST" --arg a "$M" --arg b "$T/beta" '{stateDir: $s, records: [{repo: "alpha", main: $a}, {repo: "beta", main: $b}],
  foreman: {groups: [["alpha", "beta"]]}}' > "$XDG_CONFIG_HOME/conveyor/host.json"
# The pinned install is this checkout, so the hooks setup writes run through the real shim.
mkdir -p "$XDG_DATA_HOME/conveyor/versions" && ln -s "$(cd "$SRC/../.." && pwd -P)" "$XDG_DATA_HOME/conveyor/versions/$PIN"
}
# ready: the Foreman set up, and run as its launcher runs it (as the cases setup and launch, in foreman.test.sh, leave it).
ready() {
  CONVEYOR_MAIN=$M bash "$SRC/foreman.sh" setup > "$T/setup.out" 2>&1 || fail "setup failed: $(cat "$T/setup.out")"
  export CONVEYOR_FOREMAN=1 CONVEYOR_FOREMAN_DIR=$FD CONVEYOR_MAIN=$M CONVEYOR_FOREMAN_ASK="cat $T/ask/\$CONVEYOR_REPO"
}
# fileask: each record command is noted in $T/calls, and control says new issues start in the queue.
fileask() { export CONVEYOR_FOREMAN_ASK="echo \"\$CONVEYOR_REPO \$CONVEYOR_CMD\" >> $T/calls; [ \"\$CONVEYOR_CMD\" != control ] || echo '{\"start\":\"queue\"}'"; }

# A health record and a snapshot holding it, with the waiting and blocked issues given.
health() { # <waiting issues> <blocked issues> [<reason>]
  jq -cn --argjson w "$1" --argjson b "$2" --arg r "${3:-it changes the sign-in page}" '{time: "2026-11-11T12:00:00Z", loop: true, gh: true,
    state: "running", reason: null, stuck: [], pushError: null, pushFailingSince: null,
    waiting: [$w[] | {card: "c\(.)", issue: ., since: "2026-11-11T11:00:00Z", reason: $r}],
    blocked: [$b[] | {card: "c\(.)", issue: ., since: "2026-11-11T10:00:00Z", reason: $r}]}'
}
snap() { jq -cn --argjson h "$(health "$@")" '{health: $h, belt: [{card: "x"}], queue: {next: []}}'; }
# A hook's input for the session given: its id, how it started (startup) and its transcript.
ctx() { jq -r '.hookSpecificOutput.additionalContext // empty'; } # the text a start's JSON output gives the session
sess() { jq -cn --arg s "$1" --arg src "${2:-startup}" --arg t "${3:-}" '{session_id: $s, source: $src, transcript_path: $t, stop_hook_active: false}'; }

# ada: the Foreman named Ada (as launch names it), each record command noted, and no CONVEYOR_FOREMAN. Each case
# here starts from it.
ada() {
ready; fileask
jq '.foreman.name = "Ada"' "$XDG_CONFIG_HOME/conveyor/host.json" > "$T/h" && mv "$T/h" "$XDG_CONFIG_HOME/conveyor/host.json"
unset CONVEYOR_FOREMAN
rm -f "$FD"/pending/*.wake
}

t_session_claims() {
CASE=session-claims
ada
bash "$SRC/foreman.sh" claim s6 > /dev/null || fail "the claim for s6 failed"
# Claims at once each keep their own mark and former: every one succeeds, the mark is one of them, and every other
# is told at its next start.
pids=(); for i in $(seq 7 16); do bash "$SRC/foreman.sh" claim "c$i" > "$T/claim.$i" 2>&1 & pids+=($!); done
for p in "${pids[@]}"; do wait "$p" || fail "a claim made at the same time as others failed: $(cat "$T"/claim.*)"; done
win=$(cut -d' ' -f1 "$FD/session")
[[ $win =~ ^c([7-9]|1[0-6])$ ]] || fail "claims at once left the mark wrong: $(cat "$FD/session")"
for i in $(seq 7 16); do
  [ "c$i" = "$win" ] && { grep -qxF "c$i" "$FD/former" && fail "the Foreman is listed as former"; continue; }
  grep -qxF "c$i" "$FD/former" || fail "c$i, displaced by claims at once, is not told: $(cat "$FD/former")"
done
grep -qxF s6 "$FD/former" || fail "the Foreman before the claims at once is not told: $(cat "$FD/former")"
# A session started without the launcher (no CONVEYOR_MAIN) still wakes on an awaited issue landing in its checkout.
rm -f "$FD"/pending/*.wake; echo 40 >> "$FD/await-alpha.txt"
mkdir -p "$T/ask"; snap '[12,15,16,17,18]' '[7,8]' | jq -c '.pushedCards = [{issue: 40}]' > "$T/ask/alpha"; snap '[19]' '[]' > "$T/ask/beta"
(cd "$M" && env -u CONVEYOR_MAIN -u CONVEYOR_FOREMAN_DIR CONVEYOR_FOREMAN_ASK="cat $T/ask/\$CONVEYOR_REPO" bash "$SRC/watch-conveyor.sh" --once) || fail "no wake for an awaited issue landing without the launcher"
grep -qF 'alpha: #40 landed' "$FD"/pending/*.wake || fail "the awaited issue's landing was not named: $(cat "$FD"/pending/*.wake)"
}

# Bug (issue 1687): claim.lock's wait was a fixed 30 s, so of ten claims at once on a loaded machine five gave up before
# their turn, though no holder was stuck. A claim waits while the lock changes hands, and gives up, with its message,
# only when one holder keeps it for a whole wait (CONVEYOR_FOREMAN_LOCK_WAIT, 1 s here). hold <name>: lib.sh locked,
# which writes its pid to $T/<name>.held and keeps claim.lock until a line comes on the fifo $T/<name>; held <name> waits
# for it. The case's end kills each process kept at a fifo ($T/*.held, $T/gate*/pid<n>): a failed check blocks none.
hold() { mkfifo "$T/$1"; trap 'kill $(cat "$T"/*.held "$T"/gate*/pid* 2>/dev/null) 2>/dev/null' EXIT; (. "$SRC/lib.sh" && locked bash -c 'echo $$ > "$1.held"; read -r _ < "$1"' _ "$T/$1") & }
held() { wait_until "[ -s '$T/$1.held' ]" || fail "the holder $1 did not take claim.lock"; }
# claimer <session> <gate folder>: foreman.sh claim <session> in the background (its pid in cp), each of its waits at
# claim.lock held back at the gate folder (GATE, below); it returns once the claim's first wait is called.
claimer() {
  mkdir -p "$2"; (export -f flock; export GATE=$2 CONVEYOR_FOREMAN_LOCK_WAIT=1; exec bash "$SRC/foreman.sh" claim "$1") > "$T/$1" 2>&1 & cp=$!
  wait_until "[ -e '$2/call1' ] || ! kill -0 $cp 2>/dev/null"; [ -e "$2/call1" ] || fail "the claim (foreman.sh claim $1) did not wait at claim.lock: $(cat "$T/$1")"
}
# waitsagain <session> <gate folder> <who took claim.lock>: lets the claim's first wait run, then checks that the wait
# timed out and that the claim waits again: the lock changed hands in that wait, though its new holder has not yet
# written its turn (the review finding of issue 1687: the claim gave up, as the turn it read was the last take's).
waitsagain() {
  echo > "$2/go1"; wait_until "[ -e '$2/call2' ] || ! kill -0 $cp 2>/dev/null"
  [ "$(cat "$2/rc1" 2>/dev/null)" = 1 ] || fail "the first wait at claim.lock of foreman.sh claim $1 ($3) did not time out: status $(cat "$2/rc1" 2>/dev/null)"
  [ -e "$2/call2" ] || fail "a claim (foreman.sh claim $1) whose wait timed out after $3, before it wrote its turn, gave up: $(cat "$T/$1")"
}
t_lock_turns() {
CASE=lock-turns
ada
# With GATE set, each wait at claim.lock (flock -w <s> 9) waits first for a line on the fifo $GATE/go<n> (its nth
# wait), after writing $GATE/call<n>, then runs the real flock for its whole time and writes its status to
# $GATE/rc<n>: the test, not the clock, picks who holds the lock while each wait runs. With GAP set, a take of
# claim.lock, once it has it but before it writes its turn, writes its pid to $GAP.held and waits for a line on the
# fifo $GAP. With HOLD set, flock -n 7 (the start hook's next step once it holds claim.lock) writes its pid to
# $HOLD.held and waits for a line on the fifo $HOLD: the line "exit" ends the hook there, any other goes on.
flock() {
  local n rc l
  if [ -n "${GATE:-}" ] && [ "${1:-}" = -w ] && [ "${3:-}" = 9 ]; then
    n=$(($(cat "$GATE/n" 2>/dev/null || echo 0) + 1)); echo "$n" > "$GATE/n"; echo "$BASHPID" > "$GATE/pid$n"
    mkfifo "$GATE/go$n" && : > "$GATE/call$n" && read -r _ < "$GATE/go$n"
    command flock "$@"; rc=$?; echo "$rc" > "$GATE/rc$n"; return "$rc"
  elif [ -n "${GAP:-}" ] && [ "${1:-}" = -w ] && [ "${3:-}" = 9 ]; then command flock "$@" || return; echo "$BASHPID" > "$GAP.held"; read -r _ < "$GAP"; return 0
  elif [ -n "${HOLD:-}" ] && [ "$*" = '-n 7' ]; then echo "$BASHPID" > "$HOLD.held"; read -r l < "$HOLD"; [ "$l" != exit ] || exit 0; fi
  command flock "$@"
}
# A holder writes a turn as it frees claim.lock, so a wait that ends after the next take but before that taker writes
# its turn still reads a new turn. Each of the three ways to free the lock is checked with a claim of its own: only a
# claim's first wait starts from a turn the test picks (each later one starts from the turn its last wait read).
# 1. b, the start hook of w0 (waiter.sh --start), holds claim.lock while c1's first wait is held back; b frees it where
# it writes waiter.pid, and d takes it but does not yet write its turn. b's mktemp fails, so b ends at its first step
# after that free, once its exit no longer frees the lock: only the free at waiter.pid can have written a turn.
echo 'w0 2026-01-01T00:00:00Z' > "$FD/session"; echo w0 > "$FD/started"; mkfifo "$T/b" "$T/b2" "$T/dgap" "$T/egap" "$T/fgap"
(mktemp() { return 1; }; export -f flock mktemp; export HOLD=$T/b CONVEYOR_WAITER_START=1; exec bash "$SRC/waiter.sh" <<<'{"session_id":"w0"}') > "$T/b.out" 2>&1 & held b
claimer c1 "$T/gate1"; c1p=$cp; GAP=$T/dgap hold d; echo > "$T/b"; held dgap
waitsagain c1 "$T/gate1" 'the start hook (waiter.sh --start, input {"session_id":"w0"}) freed it at waiter.pid and lib.sh locked took it'
# 2. d (lib.sh locked) writes its turn and holds claim.lock while c2's first wait is held back; d frees it, and e takes
# it but does not yet write its turn.
echo > "$T/dgap"; held d
claimer c2 "$T/gate2"; c2p=$cp; GAP=$T/egap hold e; echo > "$T/d"; held egap
waitsagain c2 "$T/gate2" 'lib.sh locked freed it and another lib.sh locked took it'
# 3. b2, the start hook of w0 again, takes claim.lock once e frees it, and holds it while c3's first wait is held back;
# b2 ends before it writes waiter.pid (its exit frees the lock, as when another waiter runs), and f takes it but does
# not yet write its turn.
echo > "$T/egap"; held e; echo w0 > "$FD/started"
(export -f flock; export HOLD=$T/b2 CONVEYOR_WAITER_START=1; exec bash "$SRC/waiter.sh" <<<'{"session_id":"w0"}') > "$T/b2.out" 2>&1 &
echo > "$T/e"; held b2
claimer c3 "$T/gate3"; GAP=$T/fgap hold f; echo exit > "$T/b2"; held fgap
waitsagain c3 "$T/gate3" 'the start hook (waiter.sh --start, input {"session_id":"w0"}) freed it by its exit and lib.sh locked took it'
echo > "$T/fgap"; held f; echo > "$T/f"
echo > "$T/gate1/go2"; wait "$c1p" || fail "a claim that waited again for claim.lock (foreman.sh claim c1) failed once the lock was free: $(cat "$T/c1")"
echo > "$T/gate2/go2"; wait "$c2p" || fail "a claim that waited again for claim.lock (foreman.sh claim c2) failed once the lock was free: $(cat "$T/c2")"
echo > "$T/gate3/go2"; wait "$cp" || fail "a claim that waited again for claim.lock (foreman.sh claim c3) failed once the lock was free: $(cat "$T/c3")"
[ "$(cut -d' ' -f1 "$FD/session")" = c3 ] || fail "the last claim that waited (foreman.sh claim c3, after c1 and c2) did not move the mark: $(cat "$FD/session")"
}
t_lock_stuck() {
CASE=lock-stuck
ada; hold a; held a
# Each wait at claim.lock (flock -w <s> 9) adds a line to $WAITS: the claim must give up after its first whole wait
# behind one holder, not after more (a claim that waited twice before it gave up passed the case without this).
flock() { [ "${1:-}" != -w ] || [ "${3:-}" != 9 ] || echo "$2" >> "$WAITS"; command flock "$@"; }
out=$(export -f flock; export WAITS=$T/waits CONVEYOR_FOREMAN_LOCK_WAIT=1; bash "$SRC/foreman.sh" claim c1 2>&1) && fail "a claim (foreman.sh claim c1) behind a holder that kept claim.lock for the whole wait succeeded: $out"
grep -qxF "foreman: this session could not be made the Foreman ($FD/session)" <<<"$out" \
  || fail "a claim (foreman.sh claim c1) that could not get claim.lock did not say so: $out"
[ "$(wc -l < "$T/waits")" = 1 ] || fail "a claim (foreman.sh claim c1) behind a holder that kept claim.lock did not give up after its first whole wait: $(wc -l < "$T/waits") waits"
}

t_stale() {
CASE=stale
# Bug caught (issue 179): a project that follows main stayed on an old engine for hours, its background take failing,
# and the Foreman's start said nothing. alpha runs PIN2; the last take read PIN and failed.
ready; fileask; unset CONVEYOR_FOREMAN
jq '.plugin = {follow: "main"}' "$SRC/../lib/test-pack.json" > "$M/.conveyor/project.json"
jq -n --arg c "$PIN2" --arg h "$PIN" '{commit: $c, taken: [$c], head: {commit: $h, name: "main"}}' > "$M/.git/conveyor-engine.json"
printf '%s\n' '{"time":"2026-11-16T05:10:00Z","by":"x","exit":0,"output":""}' '{"time":"2026-11-16T06:10:00Z","by":"x","exit":1,"output":"conveyor: the plugin'"'"'s main could not be read from its remote\n"}' > "$M/.git/conveyor-engine.log"
bash "$SRC/foreman.sh" claim s1 > /dev/null || fail "the claim failed"
out=$(sess s1 resume | bash "$SRC/foreman.sh" start | ctx)
[ "$(grep -c 'old engine' <<<"$out")" = 1 ] && grep -qxF "# WARNING: Conveyor runs an old engine here: commit ${PIN2:0:7}, and the plugin's main is at ${PIN:0:7} · last take that worked: 2026-11-16T05:10:00Z · last failure: conveyor: the plugin's main could not be read from its remote · to take it, run: cd $M && bash $(cd "$SRC/.." && pwd -P)/conveyor.sh take" <<<"$out" \
  || fail "the Foreman's start does not give one line naming the old engine and why: $out"
# Once the newest commit read is the one it runs, the line goes.
jq -n --arg c "$PIN2" '{commit: $c, taken: [$c], head: {commit: $c, name: "main"}}' > "$M/.git/conveyor-engine.json"
out=$(sess s1 resume | bash "$SRC/foreman.sh" start | ctx); [[ $out != *'old engine'* ]] || fail "the Foreman's start names an old engine on the newest commit: $out"
}

# Every case side by side (cases_side, at most 8 at a time), each in a subshell on its own fixture; each one's output
# is shown once all have ended, and the test passes only when each case ran to its end.
cases=(session_claims lock_turns lock_stuck stale)
# The cases CONVEYOR_SHELL_TEST_CASE names (comma-separated), as the runner selects them; all of them with none set.
SEL=${CONVEYOR_SHELL_TEST_CASE:-${cases[*]}}; SEL=${SEL//,/ }
for one_case in $SEL; do case " ${cases[*]} " in *" $one_case "*) ;; *) echo "unknown case $one_case" >&2; exit 2 ;; esac; done
read -ra cases <<<"$SEL"
# side_<case>: the case on its own fixture, its output in $B/<case>.out, and $B/<case>.passed once it ran to its end.
# Each name is one of the cases above, checked, so the eval runs no text from outside.
for one_case in "${cases[@]}"; do
  eval "side_$one_case() { (CASE=${one_case//_/-}; fixture $one_case; t_$one_case; : > \"\$B/$one_case.passed\") > \"\$B/$one_case.out\" 2>&1; }"
done
cases_side side_ "${cases[@]}"
bad=0
for one_case in "${cases[@]}"; do
  cat "$B/$one_case.out" >&2
  # A passing case prints `ok <case>`, named as its FAIL line names it: the main-red proof reads a case's pass from that line.
  if [ -e "$B/$one_case.passed" ]; then echo "ok ${one_case//_/-}"; else bad=1; [ -s "$B/$one_case.out" ] || echo "FAIL [${one_case//_/-}]: ended with no word" >&2; fi
done
[ "$bad" = 0 ] || exit 1
echo ok

