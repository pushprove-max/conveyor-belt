#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 120
# Foreman mode's projects (foreman.sh, watch-conveyor.sh, watch-alerts.sh, lib.sh): the launcher reopening the
# Foreman's session, one Foreman per project (or per group of linked projects), a clone of a host's project, the role
# claimed by words or at a session's start, and no private name or path in any Foreman file. The other Foreman cases
# are in foreman.test.sh and foreman-session.test.sh.
set -uo pipefail
SRC=$(cd "$(dirname "$0")" && pwd -P)
. "$SRC/../tests/wait.sh"
# The private names of this machine, read before the test sets its own home: the terms file its host file names (the
# ones the engine's privacy gate checks), the name of each host project (every record but this plugin's own checkout)
# and the Foreman's name. The privacy case checks every Foreman file against them.
HOST0=${XDG_CONFIG_HOME:-$HOME/.config}/conveyor/host.json TERMS=$(mktemp)
t=$(jq -r '.terms // empty' "$HOST0" 2>/dev/null); [[ $t != \~/* ]] || t=$HOME/${t#\~/}
{ { [ -z "$t" ] || cat -- "$t"; } && echo &&
  { [ ! -e "$HOST0" ] || jq -r --arg me "$(cd "$(git -C "$SRC" rev-parse --path-format=absolute --git-common-dir)/.." && pwd -P)" \
    '(.records // [] | .[] | select(.main != $me) | .repo), (.foreman.name // empty) | strings' "$HOST0" 2>/dev/null; }; } > "$TERMS" \
  || { echo "FAIL [privacy]: the terms file $t cannot be read" >&2; exit 1; }
. "$SRC/../lib/portable.sh"; p_tools
# Each case (t_<case>) runs side by side with the others, on a host of its own made by fixture in $B/<case> (T); a
# case that goes on from what another left (the Foreman set up, a name, a mark) makes that itself first.
B=$(mktemp -d)
# A waiter that delivers a wake leaves a waiter listening (waiter.sh handoff), which ends with the session's process:
# here a stand-in, ended with the test, and no child of it, so the wait for the cases below does not wait for it.
export CONVEYOR_FOREMAN_SESSION_PID; CONVEYOR_FOREMAN_SESSION_PID=$(sleep 600 > /dev/null 2>&1 & echo $!) # sleep: the stand-in for the session's process
trap 'kill $CONVEYOR_FOREMAN_SESSION_PID; rm -rf "$B" "$TERMS"' EXIT
# Bug (issue 452): with no CONVEYOR_MAIN, the engine runs for the checkout of the folder it runs in (foreman/lib.sh,
# the git common dir). A draft of t_auto ran `foreman.sh claim a3a3a3a3-0000` in the folder the test was started
# from, a card's worktree, so the claim went to the real main checkout's conveyor/state/foreman. Every case runs
# from this temporary folder, in no checkout: an engine call that names no fixture checkout runs for none.
cd "$B" || exit 1
fail() { echo "FAIL [$CASE]: $*" >&2; exit 1; }
at() { local d=$1; shift; (cd "$d" && "$@"); } # <folder> <command...>: the command run in that folder
# What the Foreman's launcher exports (foreman.sh launch), and Claude Code's CLAUDE_PROJECT_DIR, name the real main
# checkout and its Foreman; the loop also runs with CONVEYOR_MAIN set (machine.sh), so its cards inherit it. A case
# that sets none of its own would run for that checkout: t_setup's launch (conveyor.sh foreman) would launch for it.
unset CONVEYOR_FOREMAN CONVEYOR_FOREMAN_DIR CONVEYOR_FOREMAN_ASK CONVEYOR_FOREMAN_LAUNCH CONVEYOR_MAIN CLAUDE_PROJECT_DIR CLAUDE_CODE_PROMPT_CACHE_TTL
# A claim opens the Board in the browser (board-open.test.sh, with a stub opener); here no claim may open a real one.
export CLAUDE_PLUGIN_OPTION_boardAutoOpen=false
export CLAUDE_PLUGIN_ROOT=$SRC/../.. PLUGIN=$SRC/../..
PIN=0123456789abcdef0123456789abcdef01234567
fixture() { # <case>
T=$B/$1
export XDG_CONFIG_HOME=$T/config XDG_DATA_HOME=$T/data XDG_STATE_HOME=$T/xstate HOME=$T/home
mkdir -p "$XDG_CONFIG_HOME/conveyor" "$HOME"
# Two project checkouts: alpha is the main checkout the Foreman runs in, beta another record of the same host.
for r in alpha beta; do
  git init -q "$T/$r" && mkdir -p "$T/$r/.conveyor" && jq -n --arg p "$PIN" '{plugin: {commit: $p}}' > "$T/$r/.conveyor/project.json"
done
# alpha and beta are linked (one group, foreman.groups), so they share one Foreman, whose folder (FD: its mark, state
# and wakes) is in alpha's state folder; the case projects below has a Foreman per project.
M=$T/alpha ST=$T/state FD=$T/state/foreman FH=$XDG_CONFIG_HOME/conveyor/filing/held
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
# standin: a stand-in for claude on PATH ($T/bin) that runs the plugin's SessionStart hook, as a session would.
standin() {
mkdir -p "$T/bin"
cat > "$T/bin/claude" <<'EOF'
#!/usr/bin/env bash
# A stand-in for claude: runs the plugin's SessionStart hook, as a session would.
echo "cwd=$PWD foreman=${CONVEYOR_FOREMAN:-} ttl=${CLAUDE_CODE_PROMPT_CACHE_TTL:-}"
echo "args=$*"
echo "launch=${CONVEYOR_FOREMAN_LAUNCH:-}"
src=startup; case " $* " in *' --resume '* | *' --continue '*) src=resume ;; esac
jq -cn --arg s "${STANDIN_SID:-}" --arg src "$src" 'if $s == "" then {} else {session_id: $s, source: $src} end' | CLAUDE_PROJECT_DIR=$PWD bash -c "$(jq -r '.hooks.SessionStart[0].hooks[0].command' "$PLUGIN/hooks/hooks.json")"
EOF
chmod +x "$T/bin/claude"
}

# A health record and a snapshot holding it, with the waiting and blocked issues given.
health() { # <waiting issues> <blocked issues> [<reason>]
  jq -cn --argjson w "$1" --argjson b "$2" --arg r "${3:-it changes the sign-in page}" '{time: "2026-11-11T12:00:00Z", loop: true, gh: true,
    state: "running", reason: null, stuck: [], pushError: null, pushFailingSince: null,
    waiting: [$w[] | {card: "c\(.)", issue: ., since: "2026-11-11T11:00:00Z", reason: $r}],
    blocked: [$b[] | {card: "c\(.)", issue: ., since: "2026-11-11T10:00:00Z", reason: $r}]}'
}
snap() { jq -cn --argjson h "$(health "$@")" '{health: $h, belt: [{card: "x"}], queue: {next: []}}'; }
# The Board's data file with the 7-day limit at the share used given.
board() { # <usedPct>
  printf 'window.DASH = %s;\n' "$(jq -cn --argjson u "$1" '{updatedAt: "2026-11-11T12:00:00Z", panels: {health: {error: null, data: {limit: {usedPct: $u, goalPct: 50}}}}}')" > "$T/data.js"
}
# A hook's input for the session given: its id, how it started (startup) and its transcript.
sess() { jq -cn --arg s "$1" --arg src "${2:-startup}" --arg t "${3:-}" '{session_id: $s, source: $src, transcript_path: $t, stop_hook_active: false}'; }

t_reopen() {
CASE=reopen
# A Foreman marked (as the case session leaves it), not in the launcher's environment, and the stand-in claude.
ready; fileask; unset CONVEYOR_FOREMAN; standin
bash "$SRC/foreman.sh" claim c7 > /dev/null || fail "the claim failed"
# A restart through the launcher brings back the Foreman's own conversation while its transcript is there; a fresh
# session would lose everything the Foreman knew. With no transcript, no mark or --new it starts fresh.
unset CLAUDE_CONFIG_DIR
launch() { (cd "$M" && PATH=$T/bin:$PATH bash "$SRC/../conveyor.sh" foreman "$@" 2>&1) | grep '^args='; }
out=$(launch --model x); [ "$out" = 'args=--settings '"$FD"'/settings.json --model x' ] || fail "the launcher resumed a session with no transcript: $out"
id=$(cut -d' ' -f1 "$FD/session")
mkdir -p "$HOME/.claude/projects/$(printf %s "$M" | tr -c 'A-Za-z0-9' -)" && echo '{}' > "$HOME/.claude/projects/$(printf %s "$M" | tr -c 'A-Za-z0-9' -)/$id.jsonl"
out=$(launch --model x); [ "$out" = 'args=--settings '"$FD"'/settings.json --resume '"$id"' --model x' ] || fail "the launcher did not reopen the Foreman's session: $out"
out=$(launch --new --model x); [ "$out" = 'args=--settings '"$FD"'/settings.json --model x' ] || fail "--new did not start a fresh session: $out"
bash "$SRC/foreman.sh" off > /dev/null
out=$(launch); [ "$out" = 'args=--settings '"$FD"'/settings.json' ] || fail "the launcher resumed a session with no mark: $out"
# A session the launcher opens by --resume or --continue is the Foreman too, its environment's promise; a later
# start in that session (/clear, a compaction, a /resume) after off does not take the role back.
for a in '--resume s9' --continue; do
  bash "$SRC/foreman.sh" off > /dev/null
  lid=$(cd "$M" && STANDIN_SID=s9 PATH=$T/bin:$PATH bash "$SRC/../conveyor.sh" foreman $a 2>&1 | sed -n 's/^launch=//p')
  [ "$(cut -d' ' -f1 "$FD/session")" = s9 ] || fail "the launcher's session opened by $a was not marked: $(cat "$FD/session")"
done
bash "$SRC/foreman.sh" off > /dev/null
[ -n "$lid" ] || fail "the launcher named no launch"
sess s9 resume | CONVEYOR_FOREMAN=1 CONVEYOR_FOREMAN_LAUNCH=$lid bash "$SRC/foreman.sh" start > /dev/null
[ ! -s "$FD/session" ] || fail "a later resume in the launcher's session took the role back after off: $(cat "$FD/session")"
# Claude Code cuts a project folder's name past 200 characters, adding a hash: the launcher still finds the transcript.
L=$T/$(printf 'l%.0s' $(seq 220)); git init -q "$L"
mkdir -p "$HOME/.claude/projects/$(printf %s "$L" | tr -c 'A-Za-z0-9' - | cut -c1-200)-1x2y3z"
echo '{}' > "$HOME/.claude/projects/$(printf %s "$L" | tr -c 'A-Za-z0-9' - | cut -c1-200)-1x2y3z/s9.jsonl"
bash "$SRC/foreman.sh" claim s9 > /dev/null
out=$( (cd "$L" && PATH=$T/bin:$PATH CONVEYOR_MAIN=$L bash "$SRC/foreman.sh" launch 2>&1) | grep '^args=')
[ "$out" = 'args=--settings '"$FD"'/settings.json --resume s9' ] || fail "the launcher missed the transcript of a long checkout path: $out"
bash "$SRC/foreman.sh" off > /dev/null
}

# What the cases projects, projects-filing and projects-groups start from: alpha's Foreman set up, the Board's data
# file with no limit alert (as the case alerts leaves it), the shared filing folder made (as the case filing leaves it),
# a third project delta, and beta's own Foreman set up, with a note, rules and an open decision of its own.
projects_start() {
ready; board 20; mkdir -p "${FH%/*}"; unset CLAUDE_CONFIG_DIR
# One Foreman per project, never one for the machine: a Foreman watching several projects mixes their memory, rules,
# state and decisions in one context. With no group, alpha and beta each have their own Foreman, its folder in its own
# project's state folder: a blocked card in alpha wakes only alpha's, and a claim in alpha moves nothing in beta.
# Each reads the decisions of its own project's ledger (in that project's checkout), its own rules and decision log
# (in its folder), and holds an issue it files in any project. Linked projects (a group: beta and delta) share one
# Foreman, its folder and decision log in the first-named one's (delta's) state folder, which both projects' cards
# wake and the ungrouped alpha's never do; claimed in either checkout it awaits the same issues of the same projects
# and sees both projects' decisions. A project in two groups is refused, and no claim is made on it.
unset CONVEYOR_FOREMAN_DIR CONVEYOR_MAIN CONVEYOR_FOREMAN
git init -q "$T/delta" && mkdir -p "$T/delta/.conveyor" && jq -n --arg p "$PIN" '{plugin: {commit: $p}}' > "$T/delta/.conveyor/project.json"
host() { # <foreman.groups>
  jq -n --arg s "$ST" --arg a "$M" --arg b "$T/beta" --arg d "$T/delta" --arg j "$T/data.js" --argjson g "$1" \
    '{stateDir: $s, records: [{repo: "alpha", main: $a}, {repo: "beta", main: $b}, {repo: "delta", main: $d}], foreman: {name: "Ada", groups: $g, board: $j}}' \
    > "$XDG_CONFIG_HOME/conveyor/host.json"
}
host '[]'
FA=$ST/foreman FB=$T/beta/conveyor/state/foreman FG=$T/delta/conveyor/state/foreman
mkdir -p "$T/ask3"; snap '[]' '[50]' > "$T/ask3/alpha"; snap '[]' '[]' > "$T/ask3/beta"; snap '[]' '[]' > "$T/ask3/delta"
export CONVEYOR_FOREMAN_ASK="echo \$CONVEYOR_REPO >> $T/asked; case \$CONVEYOR_CMD in snapshot) cat $T/ask3/\$CONVEYOR_REPO ;; *) exit 3 ;; esac"
out=$(at "$T/beta" bash "$SRC/foreman.sh" setup 2>&1) || fail "setup in beta failed: $out"
grep -q '1 record' <<<"$out" && jq -e --arg fd "$FB" '.env.CONVEYOR_FOREMAN_DIR == $fd' "$FB/settings.json" >/dev/null \
  || fail "setup in beta did not set up beta's own Foreman in beta's state folder: $out"
echo '- beta note' >> "$FB/state.md"; echo 'BETA_RULE_SENTINEL' > "$FB/rules.md"
mkdir -p "$T/beta/.claude/metrics"
jq -cn '{id: "d-beta", question: "Ship the beta page", askedAt: "2026-01-01T10:00:00Z", answeredAt: null}' > "$T/beta/.claude/metrics/decisions.jsonl"
rlog() { at "$1" bash -c '. "$0/../../.claude/hooks/lib/rulings.sh" && rulings_log' "$SRC"; }
}

t_projects() {
CASE=projects
projects_start
rm -f "$FA"/pending/*.wake
outa=$(at "$M" bash "$SRC/foreman.sh" claim a1) && outb=$(at "$T/beta" bash "$SRC/foreman.sh" claim b1) || fail "the claims failed: $outa $outb"
[ "$(cut -d' ' -f1 "$FA/session")" = a1 ] && [ "$(cut -d' ' -f1 "$FB/session")" = b1 ] || fail "each project's Foreman is not marked in its own folder"
# Each Foreman starts with its own project's saved state and decisions, and no other project's.
grep -qF -- '- beta note' <<<"$outb" && grep -qF 'd-beta' <<<"$outb" && grep -qF "$FB/state.md" <<<"$outb" && grep -qxF BETA_RULE_SENTINEL <<<"$outb" \
  || fail "beta's Foreman did not get beta's saved state, rules and decisions: $outb"
grep -qE 'beta note|d-beta|Conveyor beta|beta/conveyor/state|BETA_RULE' <<<"$outa" && fail "alpha's Foreman was given beta's state, rules, decisions or Conveyor: $outa"
# Each project's picker answers (the decision log) go to its own Foreman's folder.
[ "$(rlog "$M")" = "$FA/rulings.jsonl" ] && [ "$(rlog "$T/beta")" = "$FB/rulings.jsonl" ] || fail "the decision logs are not each project's Foreman's: $(rlog "$M") $(rlog "$T/beta")"
grep -qF 'Foreman of alpha only' <<<"$outa" || fail "alpha's Foreman is not told it is alpha's only: $outa"
# The decision is read from beta's own ledger and named for beta; beta's overdue decision wakes beta's Foreman's alert
# watcher, in beta's folder, and never alpha's.
grep -qxF 'beta open decisions (1, newest first):' <<<"$outb" && grep -qxF 'alpha open decisions: none (no ledger)' <<<"$outa" \
  || fail "the decisions are not read from each project's own ledger: $outa $outb"
rm -f "$FA"/pending/*.wake "$FB"/pending/*.wake
at "$M" bash "$SRC/watch-alerts.sh" --once && fail "beta's decision woke alpha's Foreman: $(cat "$FA"/pending/*.wake)"
at "$T/beta" bash "$SRC/watch-alerts.sh" --once && grep -qF 'beta: Ship the beta page' "$FB"/pending/*.wake \
  || fail "beta's overdue decision did not wake beta's Foreman in beta's folder"
rm -f "$FB"/pending/*.wake
# A claim in alpha moves nothing in beta: beta's mark and its waiter stay.
sess b1 | (cd "$T/beta" && CONVEYOR_FOREMAN_WATCHERS='sleep 30' bash "$SRC/waiter.sh" > /dev/null 2>&1) & bp=$! # sleep: a stand-in watcher that finds nothing
wait_until '[ -s "$FB/waiter.pid" ] || ! kill -0 "$bp" 2>/dev/null'
bw=$(cut -d' ' -f1 "$FB/waiter.pid" 2>/dev/null); [ -n "$bw" ] || fail "beta's Foreman's waiter did not start"
at "$M" bash "$SRC/foreman.sh" claim a2 > /dev/null || fail "the second claim in alpha failed"
[ "$(cut -d' ' -f1 "$FA/session")" = a2 ] && [ "$(cut -d' ' -f1 "$FB/session")" = b1 ] || fail "a claim in alpha moved beta's mark: $(cat "$FB/session")"
kill -0 "$bw" 2>/dev/null || fail "a claim in alpha stopped beta's Foreman's waiter"
at "$T/beta" bash "$SRC/foreman.sh" off > /dev/null; wait "$bp"
}

t_projects_filing() {
CASE=projects-filing
# alpha's Foreman claimed as a2 and beta's as b1 (as the case projects leaves them).
projects_start
at "$M" bash "$SRC/foreman.sh" claim a2 > /dev/null && at "$T/beta" bash "$SRC/foreman.sh" claim b1 > /dev/null || fail "the claims failed"
# Filing from alpha sets every project's new issues held, and back: the command may file in beta (`gh issue create
# -R`), so an issue there is held from its first sight too (no filing is in flight: the filing cases above ran no filed hook).
: > "$T/calls"; : > "$FH"; : > "${FH%/*}/in"
ASKC="echo \"\$CONVEYOR_REPO \$CONVEYOR_CMD\" >> $T/calls; [ \"\$CONVEYOR_CMD\" != control ] || echo '{\"start\":\"queue\"}'"
jq -cn '{session_id: "a2", tool_input: {command: "gh issue create -R example/beta --title example --body example"}}' | (cd "$M" && CONVEYOR_FOREMAN_ASK=$ASKC bash "$SRC/foreman.sh" filing) > /dev/null
grep -qx 'beta control start held' "$T/calls" || fail "filing in beta from alpha's Foreman left beta's new issues buildable: $(cat "$T/calls")"
jq -cn '{session_id: "a2", tool_input: {command: "gh issue create -R example/beta --title example --body example"}, tool_response: {stdout: "https://github.com/example/beta/issues/60\n"}}' \
  | (cd "$M" && CONVEYOR_FOREMAN_ASK=$ASKC bash "$SRC/foreman.sh" filed) > /dev/null
grep -qx 'beta control adopt 60' "$T/calls" && grep -qx 'beta control start queue filed' "$T/calls" || fail "the issue filed in beta was not held, or beta's gate not set back: $(cat "$T/calls")"
# Two Foremen filing at once share the gate: alpha's filing sets both held, beta's finds them held and sets nothing,
# and alpha's ending does not start new issues in the queue again while beta's command runs on; beta's ending does.
: > "$T/calls"; ci='{tool_input: {command: "gh issue create -R example/beta --title example --body example"}, tool_response: {stdout: ""}}'
jq -cn "{session_id: \"a2\"} + $ci" | (cd "$M" && CONVEYOR_FOREMAN_ASK=$ASKC bash "$SRC/foreman.sh" filing) > /dev/null
jq -cn "{session_id: \"b1\"} + $ci" | (cd "$T/beta" && CONVEYOR_FOREMAN_ASK="echo \"\$CONVEYOR_REPO \$CONVEYOR_CMD\" >> $T/calls; echo '{\"start\":\"held\"}'" bash "$SRC/foreman.sh" filing) > /dev/null
jq -cn "{session_id: \"a2\"} + $ci" | (cd "$M" && CONVEYOR_FOREMAN_ASK=$ASKC bash "$SRC/foreman.sh" filed) > /dev/null
! grep -q 'start queue' "$T/calls" || fail "one Foreman's filing ended set new issues in the queue while another's ran on: $(cat "$T/calls")"
jq -cn "{session_id: \"b1\"} + $ci" | (cd "$T/beta" && CONVEYOR_FOREMAN_ASK=$ASKC bash "$SRC/foreman.sh" filed) > /dev/null
[ "$(grep 'start queue' "$T/calls" | cut -d' ' -f1)" = "$(grep 'start held' "$T/calls" | cut -d' ' -f1)" ] && [ ! -s "$FH" ] \
  || fail "the last filing to end did not start new issues in the queue again: $(cat "$T/calls")"
# So too two filings at once of one folder, and of two folders whose names read alike (fa-b/f, fa/b/f): the first to end
# leaves the gate held for the other.
for two in "$T/fa/f $T/fa/f" "$T/fa-b/f $T/fa/b/f"; do
  read -r f1 f2 <<<"$two"; : > "$T/calls"; mkdir -p "$f1" "$f2"
  for s in "$f1 filing" "$f2 filing" "$f1 filed"; do jq -cn "$ci" | (cd "$M" && CONVEYOR_LANE=research CONVEYOR_FOREMAN_DIR=${s% *} CONVEYOR_FOREMAN_ASK=$ASKC bash "$SRC/foreman.sh" "${s#* }") > /dev/null; done
  grep -q 'start held' "$T/calls" && ! grep -q 'start queue' "$T/calls" || fail "one filing's end set new issues in the queue while another's ran on ($two): $(cat "$T/calls")"
  jq -cn "$ci" | (cd "$M" && CONVEYOR_LANE=research CONVEYOR_FOREMAN_DIR=$f2 CONVEYOR_FOREMAN_ASK=$ASKC bash "$SRC/foreman.sh" filed) > /dev/null
  grep -q 'start queue' "$T/calls" && [ ! -s "$FH" ] || fail "the last filing to end did not start new issues in the queue again ($two): $(cat "$T/calls")"
done
# A session that lost the role while its command ran still ends its filing: else its mark stays in flight and every
# project's new issues start held for ever.
: > "$T/calls"
jq -cn "{session_id: \"a2\", tool_use_id: \"x\"} + $ci" | (cd "$M" && CONVEYOR_FOREMAN_ASK=$ASKC bash "$SRC/foreman.sh" filing) > /dev/null
at "$M" bash "$SRC/foreman.sh" claim a3 > /dev/null || fail "the claim of a3 in alpha failed"
# Its next call, made after it lost the role, ran no filing; that call's end must not end the first call's filing,
# which runs on: else new issues start in the queue while the first command can still file one.
jq -cn "{session_id: \"a2\", tool_use_id: \"y\"} + $ci" | (cd "$M" && CONVEYOR_FOREMAN_ASK=$ASKC bash "$SRC/foreman.sh" filed) > /dev/null
! grep -q 'start queue' "$T/calls" && [ -s "${FH%/*}/in" ] \
  || fail "another call's end ended a filing still in flight, new issues in the queue: $(cat "$T/calls" "${FH%/*}/in")"
jq -cn "{session_id: \"a2\", tool_use_id: \"x\"} + $ci" | (cd "$M" && CONVEYOR_FOREMAN_ASK=$ASKC bash "$SRC/foreman.sh" filed) > /dev/null
grep -q 'start queue' "$T/calls" && [ ! -s "${FH%/*}/in" ] && [ ! -s "$FH" ] \
  || fail "a filing whose session lost the role was left in flight, new issues held for ever: $(cat "$T/calls" "${FH%/*}/in")"
# When the shared filing lock cannot be had, the command is refused, never run with new issues starting in the queue.
: > "$T/calls"; rm -f "${FH%/*}/lock"; mkdir "${FH%/*}/lock"
out=$(jq -cn "{session_id: \"a3\"} + $ci" | (cd "$M" && CONVEYOR_FOREMAN_ASK=$ASKC bash "$SRC/foreman.sh" filing)); rc=$?
rmdir "${FH%/*}/lock"
[ "$rc" = 0 ] && [ "$(jq -r .hookSpecificOutput.permissionDecision <<<"$out" 2>/dev/null)" = deny ] && [ ! -s "$T/calls" ] \
  || fail "a filing without the shared lock was not refused (exit $rc): $out"
# A filing whose end cannot have the shared lock (another filing holding it long) is still ended by the next to hold
# it: else its line stays in flight and every project's new issues start held for ever.
: > "$T/calls"
jq -cn "{session_id: \"a3\", tool_use_id: \"x\"} + $ci" | (cd "$M" && CONVEYOR_FOREMAN_ASK=$ASKC bash "$SRC/foreman.sh" filing) > /dev/null
rm -f "${FH%/*}/lock"; mkdir "${FH%/*}/lock"
jq -cn "{session_id: \"a3\", tool_use_id: \"x\"} + $ci" | (cd "$M" && CONVEYOR_FOREMAN_ASK=$ASKC bash "$SRC/foreman.sh" filed) > /dev/null
rmdir "${FH%/*}/lock"
! grep -q 'start queue' "$T/calls" && [ -s "$FH" ] || fail "a filing ended without the shared lock started new issues in the queue: $(cat "$T/calls")"
for s in filing filed; do jq -cn "{session_id: \"b1\", tool_use_id: \"z\"} + $ci" | (cd "$T/beta" && CONVEYOR_FOREMAN_ASK=$ASKC bash "$SRC/foreman.sh" $s) > /dev/null; done
grep -q 'start queue' "$T/calls" && [ ! -s "${FH%/*}/in" ] && [ ! -s "$FH" ] \
  || fail "a filing ended without the shared lock was left in flight, new issues held for ever: $(cat "$T/calls" "${FH%/*}/in")"
at "$M" bash "$SRC/foreman.sh" claim a2 > /dev/null || fail "the claim of a2 back in alpha failed"
at "$T/beta" bash "$SRC/foreman.sh" off > /dev/null
}

t_projects_groups() {
CASE=projects-groups
# alpha's Foreman claimed as a2, and beta's claimed and then off (as the case projects-filing leaves them).
projects_start
at "$M" bash "$SRC/foreman.sh" claim a2 > /dev/null && at "$T/beta" bash "$SRC/foreman.sh" claim b1 > /dev/null || fail "the claims failed"
at "$T/beta" bash "$SRC/foreman.sh" off > /dev/null
# A blocked card in alpha wakes only alpha's Foreman, and its watcher asks no other project.
: > "$T/asked"
at "$M" bash "$SRC/watch-conveyor.sh" --once || fail "a blocked card in alpha did not wake alpha's Foreman"
grep -qF 'alpha: #50 is blocked' "$FA"/pending/*.wake || fail "alpha's wake does not name its blocked card: $(cat "$FA"/pending/*.wake)"
[ "$(sort -u "$T/asked")" = alpha ] || fail "alpha's watcher asked another project: $(sort -u "$T/asked" | paste -sd' ')"
: > "$T/asked"
at "$T/beta" bash "$SRC/watch-conveyor.sh" --once && fail "a blocked card in alpha woke beta's Foreman: $(cat "$FB"/pending/*.wake)"
[ "$(sort -u "$T/asked")" = beta ] || fail "beta's watcher asked another project: $(sort -u "$T/asked" | paste -sd' ')"
# beta's own card wakes beta's Foreman, in beta's folder.
snap '[]' '[51]' > "$T/ask3/beta"
at "$T/beta" bash "$SRC/watch-conveyor.sh" --once && grep -qF 'beta: #51 is blocked' "$FB"/pending/*.wake || fail "beta's blocked card did not wake beta's Foreman in beta's folder"
[ "$(cat "$FA"/pending/*.wake | grep -c '#51')" = 0 ] || fail "beta's wake went to alpha's Foreman"
# A group of two (delta first, then beta) shares one Foreman: a claim in beta marks the group's folder in delta's state
# folder, both projects' cards wake it, and the ungrouped alpha's card does not.
host '[["delta", "beta"]]'
snap '[]' '[52]' > "$T/ask3/delta"
at "$T/beta" bash "$SRC/foreman.sh" claim g1 > /dev/null || fail "the claim of the group in beta failed"
[ "$(cut -d' ' -f1 "$FG/session")" = g1 ] && [ "$(cut -d' ' -f1 "$FA/session")" = a2 ] || fail "the group's claim is not in delta's folder alone"
[ "$(rlog "$T/beta")" = "$FG/rulings.jsonl" ] && [ "$(rlog "$T/delta")" = "$FG/rulings.jsonl" ] \
  || fail "the group's projects do not share its decision log: $(rlog "$T/beta") $(rlog "$T/delta")"
: > "$T/asked"
at "$T/beta" bash "$SRC/watch-conveyor.sh" --once || fail "the group's cards did not wake its Foreman"
w=$(cat "$FG"/pending/*.wake)
grep -qF 'beta: #51 is blocked' <<<"$w" && grep -qF 'delta: #52 is blocked' <<<"$w" || fail "the group's wake does not name each project's card: $w"
grep -qF 'alpha' <<<"$w" && fail "the ungrouped alpha's card woke the group's Foreman: $w"
[ "$(sort -u "$T/asked" | paste -sd' ')" = 'beta delta' ] || fail "the group's watcher asked a project outside the group: $(sort -u "$T/asked" | paste -sd' ')"
# An issue of beta awaited from beta stays beta's when the Foreman moves to delta, where delta's own #41 is not it.
echo 41 >> "$FG/await-beta.txt"
outg=$(at "$T/delta" bash "$SRC/foreman.sh" claim g2) || fail "the claim of the group in delta failed: $outg"
[ "$(cut -d' ' -f1 "$FG/session")" = g2 ] && [ "$(cut -d' ' -f1 "$FA/session")" = a2 ] || fail "a claim in delta did not move only the group's mark"
for r in beta delta; do jq -c '.pushedCards = [{issue: 41}]' "$T/ask3/$r" > "$T/a" && mv "$T/a" "$T/ask3/$r"; done
rm -f "$FG"/pending/*.wake
at "$T/delta" bash "$SRC/watch-conveyor.sh" --once || fail "beta's awaited issue landing did not wake the group's Foreman claimed in delta"
w=$(cat "$FG"/pending/*.wake)
grep -qF 'beta: #41 landed' <<<"$w" || fail "beta's awaited issue was not named after the move to delta: $w"
grep -qF 'delta: #41 landed' <<<"$w" && fail "delta's #41 was taken for beta's awaited issue: $w"
# Claimed in delta, the group's Foreman still sees beta's decisions, from beta's ledger, and its alerts name beta.
grep -qxF 'beta open decisions (1, newest first):' <<<"$outg" && grep -qF 'd-beta' <<<"$outg" || fail "the group's Foreman in delta lost beta's decisions: $outg"
rm -f "$FG"/pending/*.wake
at "$T/delta" bash "$SRC/watch-alerts.sh" --once && grep -qF 'beta: Ship the beta page' "$FG"/pending/*.wake \
  || fail "beta's overdue decision did not wake the group's Foreman claimed in delta"
# A project in two groups would have two Foremen: such groups are refused, and no watcher runs on them.
host '[["delta", "beta"], ["beta", "alpha"]]'
: > "$T/asked"
at "$T/delta" bash "$SRC/watch-conveyor.sh" --once 2>/dev/null; [ ! -s "$T/asked" ] || fail "a watcher ran on groups naming beta twice: $(cat "$T/asked")"
out=$(at "$M" bash "$SRC/foreman.sh" setup 2>&1) && fail "setup accepted groups naming beta twice: $out"
grep -qF 'not understood' <<<"$out" || fail "the refusal of groups naming beta twice does not say why: $out"
at "$T/beta" bash "$SRC/foreman.sh" claim x1 > /dev/null 2>&1 && fail "a claim was made on groups naming beta twice"
grep -rqs x1 "$FB/session" "$FG/session" && fail "a claim on groups naming beta twice wrote a mark"
host '[["delta", "beta"]]'
# A record naming its checkout by a link is still that checkout's: claimed by its real path, beta is in delta's group.
ln -s "$T/beta" "$T/beta-link"
jq --arg l "$T/beta-link" '.records[1].main = $l' "$XDG_CONFIG_HOME/conveyor/host.json" > "$T/h" && mv "$T/h" "$XDG_CONFIG_HOME/conveyor/host.json"
at "$T/beta" bash "$SRC/foreman.sh" claim g3 > /dev/null || fail "the claim in beta, its record naming a link, failed"
[ "$(cut -d' ' -f1 "$FG/session")" = g3 ] || fail "a record naming its checkout by a link split the group's Foreman: $(cat "$FG/session")"
host '[["delta", "beta"]]'
at "$M" bash "$SRC/foreman.sh" off > /dev/null; at "$T/delta" bash "$SRC/foreman.sh" off > /dev/null
}

t_remote() {
CASE=remote
# The owner runs the Foreman on their own machine and the belt runs on a host: the host file's record names the host's
# main checkout ($O, not on this machine), and the checkout here (folder named otherwise) is a clone of that repo.
# Bug: matched only by path, the checkout was taken for an unnamed project, and every question to the host named this
# machine's path, so the live summary said unavailable and the watchers never woke the Foreman.
O=$T/other-machine/gamma L=$T/here/gamma-clone
git init -q "$L" && mkdir -p "$L/.conveyor" && jq -n --arg p "$PIN" '{plugin: {commit: $p}}' > "$L/.conveyor/project.json"
git -C "$L" remote add origin "git${AT:-@}github.com:example/gamma.git"
jq -n --arg o "$O" '{records: [{repo: "alpha", main: "/nowhere/alpha"}, {repo: "gamma", main: $o}]}' > "$XDG_CONFIG_HOME/conveyor/host.json"
unset CONVEYOR_MAIN CONVEYOR_FOREMAN_DIR
mine_at() { (cd "$1" && bash -c '. "$0/lib.sh" && mine' "$SRC"); }
[ "$(mine_at "$L")" = "gamma"$'\t'"$O" ] || fail "a clone of gamma did not get gamma's record by its origin: $(mine_at "$L")"
git -C "$L" remote set-url origin https://github.com/example/gamma
[ "$(mine_at "$L")" = "gamma"$'\t'"$O" ] || fail "an https origin with no .git did not match gamma's record: $(mine_at "$L")"
# The live summary and the watcher ask the host about the record's main, and the Foreman's folder is on this machine.
export CONVEYOR_FOREMAN_ASK="echo \"\$CONVEYOR_REPO \$CONVEYOR_MAIN \$CONVEYOR_CMD\" >> $T/asked; case \$CONVEYOR_CMD in snapshot) cat $T/snap ;; esac"
snap '[]' '[7]' > "$T/snap"
out=$(cd "$L" && bash "$SRC/foreman.sh" live) || fail "the live summary failed: $out"
grep -qxF "gamma $O snapshot" "$T/asked" && grep -qF 'Conveyor gamma (' <<<"$out" && grep -qF 'gamma blocked: #7' <<<"$out" \
  || fail "the live summary did not ask the host about gamma's main: $(cat "$T/asked") $out"
# The ledger the Foreman writes and answers is the clone's, here. Bug: the live summary looked for it under the
# record's main, not on this machine, and said the decisions were unavailable.
grep -qxF 'gamma open decisions: none (no ledger)' <<<"$out" || fail "a clone with no ledger did not read as none: $out"
mkdir -p "$L/.claude/metrics" && : > "$L/.claude/metrics/decisions.jsonl"
out=$(cd "$L" && bash "$SRC/foreman.sh" live)
grep -qxF 'gamma open decisions: none' <<<"$out" || fail "the clone's empty ledger did not read as none: $out"
jq -cn '{id: "d-gamma", question: "Ship gamma", askedAt: "2026-01-01T10:00:00Z", answeredAt: null}' > "$L/.claude/metrics/decisions.jsonl"
out=$(cd "$L" && bash "$SRC/foreman.sh" live)
grep -qxF 'gamma open decisions (1, newest first):' <<<"$out" && grep -qxF -- '- d-gamma: Ship gamma' <<<"$out" \
  || fail "the live summary did not list the clone's open decisions: $out"
grep -qF 'unavailable' <<<"$out" && fail "the live summary called a decision source unavailable: $out"
out=$(cd "$L" && bash "$SRC/foreman.sh" claim r1) && [ "$(cut -d' ' -f1 "$L/conveyor/state/foreman/session")" = r1 ] \
  || fail "the claim in the clone did not mark the Foreman in its own state folder: $out"
: > "$T/asked"
(cd "$L" && bash "$SRC/watch-conveyor.sh" --once) || fail "the watcher did not wake on gamma's blocked card"
grep -qxF "gamma $O snapshot" "$T/asked" && grep -qF 'gamma: #7 is blocked' "$L"/conveyor/state/foreman/pending/*.wake \
  || fail "the watcher did not ask the host about gamma's main: $(cat "$T/asked")"
# The alerts watcher reads the same ledger: the clone's overdue decision wakes the Foreman.
rm -f "$L"/conveyor/state/foreman/pending/*.wake
(cd "$L" && bash "$SRC/watch-alerts.sh" --once) && grep -qF 'gamma: Ship gamma' "$L"/conveyor/state/foreman/pending/*.wake \
  || fail "the alerts watcher did not read the clone's ledger for gamma's decisions"
# A checkout of a repo no record names stays its own, as before.
git -C "$L" remote set-url origin https://github.com/example/zeta.git
[ "$(mine_at "$L")" = "gamma-clone"$'\t'"$L" ] || fail "a checkout of a repo with no record took another record: $(mine_at "$L")"
}

t_words() {
CASE=words
# The owner opens a session in the main checkout and says "start your role": the plugin's prompt hook claims the role,
# and the reply is the claim's first line. Bug: only /conveyor-belt:foreman claimed it, so a Foreman asked in words
# never started. The same words in a card's worktree, or in a checkout that is no Conveyor project, claim nothing.
export CONVEYOR_FOREMAN_ASK='exit 3'
unset CONVEYOR_MAIN CONVEYOR_FOREMAN_DIR CONVEYOR_FOREMAN
hook=$(jq -r '.hooks.UserPromptSubmit[].hooks[].command | select(contains("foreman.sh words"))' "$PLUGIN/hooks/hooks.json")
[ -n "$hook" ] || fail "hooks.json runs no words hook on a prompt"
say() { # <folder> <session> <prompt>: the hook as Claude Code runs it in a session in that folder
  jq -cn --arg s "$2" --arg p "$3" --arg c "$1" '{session_id: $s, prompt: $p, cwd: $c, hook_event_name: "UserPromptSubmit"}' \
    | (cd "$1" && CLAUDE_PROJECT_DIR=$1 bash -c "$hook")
}
git -C "$M" add .conveyor && git -C "$M" -c user.name=t -c user.email="t${AT:-@}example.com" commit -qm pack && git -C "$M" worktree add -q "$T/wt"
out=$(say "$T/wt" w0 'start your role'); [ -z "$out" ] && [ ! -s "$FD/session" ] || fail "the words in a worktree claimed the role: $out"
git init -q "$T/plain"
out=$(say "$T/plain" w0 'start your role'); [ -z "$out" ] && [ ! -e "$T/plain/conveyor/state/foreman/session" ] \
  || fail "the words in a checkout that is no Conveyor project claimed the role: $out"
out=$(say "$M" w0 "Please don't start your role yet"); [ -z "$out" ] && [ ! -s "$FD/session" ] || fail "a prompt only holding the words claimed the role: $out"
out=$(say "$M" w1 'Start your role.')
[ "$(cut -d' ' -f1 "$FD/session")" = w1 ] || fail "the words in the main checkout did not claim the role: $out"
jq -er '.hookSpecificOutput.additionalContext' <<<"$out" | grep -qF 'Reply with only this one line: This session is now the Foreman: ' \
  || fail "the session was not told to reply with the claim's first line: $out"
out=$(say "$M" w2 'You are the Foreman')
[ "$(cut -d' ' -f1 "$FD/session")" = w2 ] || fail "\"You are the Foreman\" did not claim the role: $out"
}

# A new session opened in the main checkout takes the role by itself: no mark, or the marked session gone, it claims
# it; a live one holding it, it claims nothing and asks the owner by the picker. Bug: only /conveyor-belt:foreman or
# the words claimed it, so for hours no Foreman watched the belts. Never in a worktree (a card's, a lane's) or a
# session the engine starts for a card or a lane: one would take the role from the owner's Foreman.
# autohost: the owner's host as the cases auto_skip and auto (side by side) open sessions on, and their helpers.
autohost() {
export CONVEYOR_FOREMAN_ASK='exit 3'
# (A card's own run of this test has CONVEYOR_CARD set: the owner's sessions have none.)
unset CONVEYOR_MAIN CONVEYOR_FOREMAN_DIR CONVEYOR_FOREMAN CLAUDE_CONFIG_DIR CONVEYOR_CARD CONVEYOR_LANE
hook=$(jq -r '.hooks.SessionStart[].hooks[].command | select(contains("foreman.sh start"))' "$PLUGIN/hooks/hooks.json")
[ -n "$hook" ] || fail "hooks.json runs no Foreman start at SessionStart"
}
open() { # <folder> <session> [<source>]: the hook as Claude Code runs it at the start of a session in that folder
  sess "$2" "${3:-startup}" | (cd "$1" && CLAUDE_PROJECT_DIR=$1 bash -c "$hook")
}
mark() { cut -d' ' -f1 "$FD/session" 2>/dev/null; }
t_auto_skip() {
CASE=auto-skip
autohost
git -C "$M" add .conveyor && git -C "$M" -c user.name=t -c user.email="t${AT:-@}example.com" commit -qm pack
git -C "$M" worktree add -q "$T/card" && git -C "$M" worktree add -q "$T/alpha-fast"
for d in "$T/card" "$T/alpha-fast"; do
  out=$(open "$d" w1); [ -z "$out" ] && [ -z "$(mark)" ] || fail "a new session in the worktree $d claimed or asked: $out"
done
out=$(CONVEYOR_CARD=c1 open "$M" w1); [ -z "$out" ] && [ -z "$(mark)" ] || fail "a session started for a card claimed or asked: $out"
out=$(CONVEYOR_LANE=research open "$M" w1); [ -z "$out" ] && [ -z "$(mark)" ] || fail "a lane's session claimed or asked: $out"
out=$(open "$M" w1 resume); [ -z "$out" ] && [ -z "$(mark)" ] || fail "a resumed session, not a new one, claimed or asked: $out"
}

t_auto() {
CASE=auto
autohost
# held <session id> <pid> [<transcript age>]: Claude Code's own record of a session, and its transcript written then.
held() {
  mkdir -p "$HOME/.claude/sessions" "$HOME/.claude/projects/p"
  jq -cn --argjson p "$2" --arg s "$1" '{pid: $p, sessionId: $s, startedAt: 1794650400000, kind: "interactive"}' > "$HOME/.claude/sessions/$2.json"
  touch -d "${3:-now}" "$HOME/.claude/projects/p/$1.jsonl"
}
# No mark: the new session claims the role and says so in one line, shown to the owner.
out=$(open "$M" a1)
[ "$(mark)" = a1 ] || fail "a new session in the main checkout with no Foreman did not claim the role: $out"
# A host file with no foreman.name: the line names no Foreman in brackets; it read "the Foreman (Foreman)" on a fresh install.
jq -e '(.systemMessage | startswith("This session is now the Foreman: ")) and (.systemMessage | contains("(Foreman)") | not) and (.hookSpecificOutput.additionalContext | contains("Foreman mode: you are Foreman"))' <<<"$out" >/dev/null \
  || fail "the claim at start did not say so in one line and give the Foreman's start: $out"
# Bug: the line still said the watchers start at the end of the first turn, though the session's start hook starts them (issue 1172).
jq -e '.systemMessage | (contains("first turn") | not) and contains("start at once")' <<<"$out" >/dev/null \
  || fail "the claim at start (input a1, no Foreman) gave the old watcher timing: $out"
# The marked session gone: its Claude process ended (the record Claude Code leaves names a pid no longer running).
dead=$(bash -c 'echo $$'); held a1 "$dead"
out=$(open "$M" a2); [ "$(mark)" = a2 ] || fail "a new session did not claim the role from a Foreman whose process ended: $out"
# Gone too: its process runs, but its transcript was last written over 24 hours ago.
sleep 600 & lp=$! # sleep: a stand-in for the Foreman's Claude process, killed at the case's end
trap 'kill "$lp" 2>/dev/null' EXIT
held a2 "$lp" '25 hours ago'
out=$(open "$M" a3); [ "$(mark)" = a3 ] || fail "a new session did not claim the role from a Foreman silent for over 24 hours: $out"
# Live: its process runs and its transcript is fresh. The new session claims nothing, and is told to ask the owner.
rm -f "$HOME/.claude/sessions/$lp.json"; held a3a3a3a3-0000 "$lp" '2 hours ago'
at "$M" bash "$SRC/foreman.sh" claim a3a3a3a3-0000 > /dev/null || fail "the claim for the live session failed"
out=$(open "$M" a4)
[ "$(mark)" = a3a3a3a3-0000 ] || fail "a new session took the role from a live Foreman: $out"
ctx=$(jq -r '.hookSpecificOutput.additionalContext' <<<"$out")
q="Session a3a3a3a3 (started $(p_date @1794650400 '+%Y-%m-%d %H:%M %Z'), last active $(p_date "@$(p_stat "$HOME/.claude/projects/p/a3a3a3a3-0000.jsonl" | cut -d' ' -f2)" '+%Y-%m-%d %H:%M %Z')) is the Foreman of alpha, beta. Make this session the Foreman instead?"
grep -qF 'As your first act' <<<"$ctx" && grep -qF 'by the picker (AskUserQuestion)' <<<"$ctx" && grep -qxF "$q" <<<"$ctx" \
  && grep -qF '"Take over" and "Leave it"' <<<"$ctx" && grep -qF 'On "Leave it": this session stays a normal session; do not ask again in it.' <<<"$ctx" \
  || fail "the new session was not told to ask the owner by the picker with the two options: $out"
jq -e 'has("systemMessage") | not' <<<"$out" >/dev/null || fail "the owner was told of a claim that was not made: $out"
# "Take over" runs the command it names, which moves the role.
cmd=$(sed -n 's/^- On "Take over": run `\(.*\)`\. Its first line.*/\1/p' <<<"$ctx")
[ -n "$cmd" ] || fail "no command for \"Take over\": $ctx"
out=$(cd "$M" && CLAUDE_PROJECT_DIR=$M CLAUDE_CODE_PROMPT_CACHE_TTL=5m bash -c "$cmd") && [ "$(mark)" = a4 ] && grep -qxF a3a3a3a3-0000 "$FD/former" \
  || fail "\"Take over\" did not move the role: $(mark) $out"
[ "$(head -n 1 <<<"$out")" = "This session is now the Foreman: its watchers start at the end of this turn." ] || fail "\"Take over\" did not say so in one line: $out"
# A session taking over with a 5-minute cache: the command prints the cache line, and the session is told to reply
# with it, or the owner never sees that this Foreman writes 5-minute caches (#714).
grep -q '^The Foreman runs with the prompt cache time 5m, not 1h: ' <<<"$out" || fail "\"Take over\" in a 5-minute session gave no cache line: $out"
grep -qF ': reply with that one line, and with the line on the prompt cache time when there is one, and from then on' <<<"$ctx" \
  || fail "\"Take over\" does not ask for the cache line in the reply: $ctx"
# "Leave it": a session is asked only at its start, so a later start in it (resumed) asks nothing.
at "$M" bash "$SRC/foreman.sh" claim a3a3a3a3-0000 > /dev/null
out=$(open "$M" a5); grep -qF 'Take over' <<<"$out" || fail "a second new session was not asked: $out"
out=$(open "$M" a5 resume); [ -z "$out" ] && [ "$(mark)" = a3a3a3a3-0000 ] || fail "a session left normal was asked again: $out"
kill "$lp"
}

# privacy_files <folder>: sets files to each file under the folder, also those in its folders (tests/), tracked or
# new, and no folder: the check ends with status 2 for a folder (issue 1681: "$SRC"/* gave it tests/, and no file in
# tests/ was checked). git's list leaves out what .gitignore names (a __pycache__ file holds this checkout's own
# path), and a file deleted from the worktree but still tracked is left out too.
privacy_files() {
local f; files=()
while IFS= read -r -d '' f; do [ -f "$1/$f" ] && files+=("$1/$f"); done \
  < <(git -C "$1" ls-files -z -c -o --exclude-standard)
[ ${#files[@]} -gt 0 ] || fail "git lists no file in $1"
}

# t_privacy [<folder> <terms file>]: the Foreman's folder and this machine's terms with none given; t_privacy_nested
# gives a folder and terms of its own.
t_privacy() {
CASE=privacy
local dir=${1:-$SRC} terms=${2:-$TERMS} files; privacy_files "$dir"
bash "$SRC/../privacy/check.sh" --terms "$terms" "${files[@]}" "$SRC/../../commands/"*.md || fail "a Foreman file names something private"
}

# Bug (issue 1681): the privacy case gave the check "$SRC"/*, so a file in a folder under the Foreman's (tests/) was
# never checked. A folder of its own stands in for the Foreman's (the real one holds no private term): the privacy
# case itself (t_privacy, in a subshell, as its fail ends it) fails on a term in a nested file and names that file.
t_privacy_nested() {
local d=$T/fm out rc
mkdir -p "$d/tests" && git init -q "$d" || fail "cannot make the folder $d"
echo 'echo top' > "$d/top.sh"; echo 'echo zyxwvprivate' > "$d/tests/helper.sh"; echo zyxwvprivate > "$T/terms"
git -C "$d" add top.sh
out=$(t_privacy "$d" "$T/terms" 2>&1); rc=$?
[ "$rc" = 1 ] && [[ $out == *"FAIL [privacy]"* ]] || fail "t_privacy $d $T/terms: status $rc, not a privacy failure: $out"
[[ $out == *"$d/tests/helper.sh:1:"* ]] || fail "t_privacy $d $T/terms: does not name $d/tests/helper.sh: $out"
}

# Every case at once, each in a subshell on its own fixture; each one's output is shown once all have ended, and the
# test passes only when each case ran to its end.
cases=(reopen projects projects_filing projects_groups remote words auto_skip auto privacy privacy_nested)
# The cases CONVEYOR_SHELL_TEST_CASE names (comma-separated), as the runner selects them; all of them with none set.
SEL=${CONVEYOR_SHELL_TEST_CASE:-${cases[*]}}; SEL=${SEL//,/ }
for one_case in $SEL; do case " ${cases[*]} " in *" $one_case "*) ;; *) echo "unknown case $one_case" >&2; exit 2 ;; esac; done
read -ra cases <<<"$SEL"
# (A case's own variables, as its loops' c, are its own: the case's name is in one none of them uses.)
for one_case in "${cases[@]}"; do
  (CASE=${one_case//_/-}; fixture "$one_case"; "t_$one_case"; : > "$B/$one_case.passed") > "$B/$one_case.out" 2>&1 &
done
wait
bad=0
for one_case in "${cases[@]}"; do
  cat "$B/$one_case.out" >&2
  # A passing case prints `ok <case>`, named as its FAIL line names it: the main-red proof reads a case's pass from that line.
  if [ -e "$B/$one_case.passed" ]; then echo "ok ${one_case//_/-}"; else bad=1; [ -s "$B/$one_case.out" ] || echo "FAIL [${one_case//_/-}]: ended with no word" >&2; fi
done
[ "$bad" = 0 ] || exit 1
echo ok
