#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 120
# Foreman mode (foreman.sh, watch-conveyor.sh, waiter.sh, stop.sh): set up on a fresh host with two records, the
# launcher starting a session that gets the live summary, every wake naming every item, the stop hooks, one Foreman
# per project (or per group of linked projects), and no private name or path in any of its files.
set -uo pipefail
SRC=$(cd "$(dirname "$0")" && pwd -P)
. "$SRC/../tests/wait.sh"
# The private names of this machine, read before the test sets its own home: the terms file its host file names (the
# ones the engine's privacy gate checks), the name of each host project (every record but this plugin's own checkout)
# and the Foreman's name. The privacy case checks every Foreman file against them.
HOST0=${XDG_CONFIG_HOME:-$HOME/.config}/conveyor/host.json TERMS=$(mktemp)
t=$(jq -r '.terms // empty' "$HOST0" 2>/dev/null); [[ $t != "~/"* ]] || t=$HOME/${t#"~/"}
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
# unheld ends that waiter at once, where its stand-in watcher would go on putting wakes.
export CONVEYOR_FOREMAN_SESSION_PID; CONVEYOR_FOREMAN_SESSION_PID=$(sleep 600 > /dev/null 2>&1 & echo $!) # sleep: the stand-in for the session's process
trap 'kill $CONVEYOR_FOREMAN_SESSION_PID; rm -rf "$B" "$TERMS"' EXIT
unheld() { kill "$(cut -d' ' -f1 "$FD/waiter.pid")" 2>/dev/null; flock -w 10 "$FD/waiter.lock" true; }
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
# and wakes) is in alpha's state folder; the case projects below has a Foreman per project.
M=$T/alpha ST=$T/state FD=$T/state/foreman FH=$XDG_CONFIG_HOME/conveyor/filing/held
jq -n --arg s "$ST" --arg a "$M" --arg b "$T/beta" '{stateDir: $s, records: [{repo: "alpha", main: $a}, {repo: "beta", main: $b}],
  foreman: {groups: [["alpha", "beta"]]}}' > "$XDG_CONFIG_HOME/conveyor/host.json"
# The pinned install is this checkout, so the hooks setup writes run through the real shim.
mkdir -p "$XDG_DATA_HOME/conveyor/versions" && ln -s "$(cd "$SRC/../.." && pwd -P)" "$XDG_DATA_HOME/conveyor/versions/$PIN"
}
# ready: the Foreman set up, and run as its launcher runs it (as the cases after setup and launch go on from).
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

# A health record, a cards record and a snapshot holding them, with the waiting and blocked issues given.
health() { # <waiting issues> <blocked issues> [<reason>]
  jq -cn --argjson w "$1" --argjson b "$2" --arg r "${3:-it changes the sign-in page}" '{time: "2026-11-11T12:00:00Z", loop: true, gh: true,
    state: "running", reason: null, stuck: [], pushError: null, pushFailingSince: null,
    waiting: [$w[] | {card: "c\(.)", issue: ., since: "2026-11-11T11:00:00Z", reason: $r}],
    blocked: [$b[] | {card: "c\(.)", issue: ., since: "2026-11-11T10:00:00Z", reason: $r}]}'
}
snap() { jq -cn --argjson h "$(health "$@")" '{health: $h, belt: [{card: "x"}], queue: {next: []}}'; }
CARDS='{"cards":[{"issue":3,"step":"build","result":""}]}'
# The Board's data file with the 7-day limit at the share used given.
board() { # <usedPct>
  printf 'window.DASH = %s;\n' "$(jq -cn --argjson u "$1" '{updatedAt: "2026-11-11T12:00:00Z", panels: {health: {error: null, data: {limit: {usedPct: $u, goalPct: 50}}}}}')" > "$T/data.js"
}
# A hook's input for the session given: its id, how it started (startup) and its transcript.
sess() { jq -cn --arg s "$1" --arg src "${2:-startup}" --arg t "${3:-}" '{session_id: $s, source: $src, transcript_path: $t, stop_hook_active: false}'; }

# The cases setup, launch and archive run one after another: each goes on from the Foreman the one before it left.
t_setup() {
CASE=setup
CONVEYOR_MAIN=$M bash "$SRC/foreman.sh" setup > "$T/setup.out" 2>&1 || fail "setup failed: $(cat "$T/setup.out")"
[ -f "$FD/state.md" ] || fail "no state file in $FD"
S=$FD/settings.json
jq -e '.env.CONVEYOR_FOREMAN == "1" and .env.CLAUDE_CODE_PROMPT_CACHE_TTL == "1h" and .env.CONVEYOR_FOREMAN_DIR == $fd' --arg fd "$FD" "$S" >/dev/null \
  || fail "the settings do not set Foreman mode, its folder and the 1-hour cache: $(cat "$S")"
# The Foreman's hooks are the plugin's own, so a session started any way (claude --continue, an IDE) runs them; the
# launcher's settings hold none, or its session would run each twice.
P=$SRC/../../hooks/hooks.json
for h in 'SessionStart foreman.sh start' 'Stop stop.sh state' 'Stop stop.sh reply' 'Stop waiter.sh' 'PreToolUse foreman.sh filing' 'PostToolUse foreman.sh filed' 'PostToolUseFailure foreman.sh filed' \
  'UserPromptSubmit waiter.sh --check' 'PostToolUse waiter.sh --check'; do # issue 215: a dead waiter is started again by the session's next prompt or tool call
  jq -e --arg e "${h%% *}" --arg h "shim.sh conveyor/foreman/${h#* }" '[.hooks[$e][]? | select(($e | test("ToolUse") | not) or .matcher == "Bash" or .matcher == null) | .hooks[].command | endswith($h)] | any' "$P" >/dev/null \
    || fail "no plugin hook runs $h"
done
jq -e '[.hooks.Stop[].hooks[] | select(.command | endswith("waiter.sh")) | .asyncRewake] == [true]' "$P" >/dev/null || fail "the waiter does not wake the session"
jq -e 'has("hooks") | not' "$S" >/dev/null || fail "the launcher's settings repeat the plugin's hooks: $(cat "$S")"
grep -q '2 record' "$T/setup.out" || fail "setup does not say it watches both records: $(cat "$T/setup.out")"
echo '- my note' >> "$FD/state.md"; cp "$S" "$T/first.json"
CONVEYOR_MAIN=$M bash "$SRC/foreman.sh" setup > /dev/null 2>&1 || fail "a second setup failed"
cmp -s "$S" "$T/first.json" || fail "a second setup wrote other settings"
grep -qx -- '- my note' "$FD/state.md" || fail "a second setup lost the saved state"

CASE=launch
standin
export CONVEYOR_FOREMAN_ASK='case $CONVEYOR_CMD in health) jq -cn --argjson w "[$([ "$CONVEYOR_REPO" = alpha ] && echo 12 || echo 19)]" "{time: \"2026-11-11T12:00:00Z\", loop: true, state: \"running\", reason: null, blocked: [], waiting: [\$w[] | {issue: ., since: \"x\"}], before: [{issue: 21, title: \"a new page\", since: \"y\"}], pushError: null}" ;; cards) echo '"'$CARDS'"' ;; esac'
out=$(cd "$M" && PATH=$T/bin:$PATH bash "$SRC/../conveyor.sh" foreman 2>&1) || fail "conveyor foreman failed: $out"
grep -qF "cwd=$M foreman=1 ttl=1h" <<<"$out" || fail "claude did not start in the main checkout in Foreman mode with the 1-hour cache: $out"
grep -qF '# Live summary' <<<"$out" || fail "the session got no live summary: $out"
# Bug (#11): the Foreman checked status by hand in 4 to 6 shell calls, ran short commands in the background and read
# images it was not asked to, each call re-reading the whole conversation. Its rules say how to keep calls few.
grep -qF '# Check status with conveyor.sh foreman status, not your own snapshot reads.' <<<"$out" \
  && grep -qF '# Run a command that ends in under 2 minutes in the foreground; put several checks into one command; start a background command only for a long run.' <<<"$out" \
  && grep -qF '# Read an image (a screenshot, a GIF frame) only when the owner asks or a check needs to see it.' <<<"$out" \
  || fail "the Foreman's start context lacks the three lean-habit rules: $out"
# Bug (#187): the Foreman listed a git command for the owner to commit the pack. Its rules put the question by the picker.
grep -qF 'ask the owner by the picker "Commit the Conveyor pack (.conveyor/project.json) on <default branch> now?"' <<<"$out" \
  && grep -qF 'on yes run conveyor.sh setup pack-commit yes' <<<"$out" \
  || fail "the Foreman's start context does not ask the owner by the picker to commit the pack: $out"
# Bug (#220): on a wake for a waiting card the Foreman only reported it, and cards waited for hours. Its rules tell it
# to find the cause and fix it.
grep -qF '# A wake that a card has waited (or is still waiting) for main to change, or on another card: do not only report it. Find why it waits' <<<"$out" \
  && grep -qF 'Then fix the cause: a hand fix when the belt is blocked and the owner'"'"'s rules allow it, otherwise file the issue.' <<<"$out" \
  || fail "the Foreman's start context does not tell it to find and fix why a card waits: $out"
grep -qF "alpha waiting on the owner's yes: #12" <<<"$out" && grep -qF "beta waiting on the owner's yes: #19" <<<"$out" \
  || fail "the live summary does not cover both records: $out"
grep -qF "alpha waiting on the owner's yes before its build: #21" <<<"$out" || fail "the live summary leaves out an issue waiting for its yes before its build: $out"
grep -qF 'alpha in flight: #3 build' <<<"$out" || fail "the live summary does not name the card in flight: $out"
grep -qF -- '- my note' <<<"$out" || fail "the session did not get its saved state: $out"
grep -qF "you are Foreman" <<<"$out" || fail "the Foreman's default name is not Foreman: $out"
jq '.foreman.name = "Ada"' "$XDG_CONFIG_HOME/conveyor/host.json" > "$T/h" && mv "$T/h" "$XDG_CONFIG_HOME/conveyor/host.json"
out=$(cd "$M" && PATH=$T/bin:$PATH bash "$SRC/../conveyor.sh" foreman 2>&1)
grep -qF "you are Ada" <<<"$out" || fail "the Foreman's name is not the host file's: $out"
CONVEYOR_FOREMAN_ASK='exit 3' out=$(cd "$M" && PATH=$T/bin:$PATH bash "$SRC/../conveyor.sh" foreman 2>&1)
grep -qF 'Conveyor alpha: unavailable' <<<"$out" || fail "a record that does not answer is not named unavailable: $out"

CASE=archive
printf '# state\n- DONE shipped the thing\n  with its detail\n- open item\n' > "$FD/state.md"
out=$(cd "$M" && PATH=$T/bin:$PATH bash "$SRC/../conveyor.sh" foreman 2>&1)
grep -q 'DONE' "$FD/state.md" && fail "a DONE item stayed in the state: $(cat "$FD/state.md")"
grep -qx -- '- open item' "$FD/state.md" || fail "an open item left the state"
cat "$FD"/state-archive-*.md 2>/dev/null | grep -qx '  with its detail' || fail "the DONE item and its detail were not archived"
}

t_wake() {
CASE=wake
ready
# Three items waiting on the owner and one blocked, across two projects.
mkdir -p "$T/ask"; snap '[12,15]' '[7]' > "$T/ask/alpha"; snap '[19]' '[]' > "$T/ask/beta"
bash "$SRC/watch-conveyor.sh" --once || fail "no wake for four new items"
w=$(cat "$FD"/pending/*.wake)
[ "$(head -n 1 <<<"$w")" = "Conveyor: alpha: needs the owner's yes: #12 #15; blocked: #7 | beta: needs the owner's yes: #19" ] \
  || fail "the first line does not name every issue under its kind and project: $(head -n 1 <<<"$w")"
[ "$(wc -l <<<"$w")" = 5 ] || fail "not one line per item: $w"
for l in "alpha: #12 needs" "alpha: #15 needs" "alpha: #7 is blocked" "beta: #19 needs"; do grep -qF "$l" <<<"$w" || fail "no line for $l: $w"; done
bash "$SRC/watch-conveyor.sh" --once && fail "items already reported woke again"
# An issue waiting for the owner's yes before its build (health's before) wakes as one waiting on the owner.
rm -f "$FD"/pending/*.wake
jq -c '.health.before = [{issue: 22, title: "a new page", since: "2026-11-11T11:00:00Z"}]' "$T/ask/beta" > "$T/b" && mv "$T/b" "$T/ask/beta"
bash "$SRC/watch-conveyor.sh" --once || fail "no wake for an issue waiting for its yes before its build"
[ "$(head -n 1 "$FD"/pending/*.wake)" = "Conveyor: beta: needs the owner's yes: #22" ] || fail "the pre-build wait is not named waiting on the owner: $(cat "$FD"/pending/*.wake)"
# Bug caught (#632): one snapshot that listed a card stuck, taken between two lines of a landing that went on, woke
# the Foreman. A stuck card wakes only when two polls in a row, at least a minute apart, list it. The watcher's clock
# is the case's from here on.
CONVEYOR_FOREMAN_NOW=$(date +%s)
export CONVEYOR_FOREMAN_NOW
rm -f "$FD"/pending/*.wake
jq -c '.health.stuck = [{card: "c27", issue: 27, step: "land", since: "2026-11-11T11:00:00Z"}]' "$T/ask/beta" > "$T/b" && mv "$T/b" "$T/ask/beta"
bash "$SRC/watch-conveyor.sh" --once && fail "a card one snapshot lists stuck woke at once: $(cat "$FD"/pending/*.wake)"
jq -c '.health.stuck = []' "$T/ask/beta" > "$T/b" && mv "$T/b" "$T/ask/beta"; CONVEYOR_FOREMAN_NOW=$((CONVEYOR_FOREMAN_NOW + 60))
bash "$SRC/watch-conveyor.sh" --once && fail "a card listed stuck in the first snapshot only woke: $(cat "$FD"/pending/*.wake)"
jq -c '.health.stuck = [{card: "c27", issue: 27, step: "land", since: "2026-11-11T11:00:00Z"}]' "$T/ask/beta" > "$T/b" && mv "$T/b" "$T/ask/beta"
bash "$SRC/watch-conveyor.sh" --once && fail "a card listed stuck again after a snapshot that did not list it woke at once: $(cat "$FD"/pending/*.wake)"
CONVEYOR_FOREMAN_NOW=$((CONVEYOR_FOREMAN_NOW + 59))
bash "$SRC/watch-conveyor.sh" --once && fail "a card two snapshots under a minute apart list stuck woke: $(cat "$FD"/pending/*.wake)"
CONVEYOR_FOREMAN_NOW=$((CONVEYOR_FOREMAN_NOW + 1))
bash "$SRC/watch-conveyor.sh" --once || fail "no wake for a card two snapshots a minute apart list stuck"
[ "$(cat "$FD"/pending/*.wake | grep -c '#27 is stuck')" = 1 ] || fail "not one wake for the stuck card: $(cat "$FD"/pending/*.wake)"
CONVEYOR_FOREMAN_NOW=$((CONVEYOR_FOREMAN_NOW + 60))
bash "$SRC/watch-conveyor.sh" --once && fail "a stuck card already reported woke again: $(cat "$FD"/pending/*.wake)"
# A stuck card's line says why: the cards a long wait was behind, the test case that hangs, else the silent step.
rm -f "$FD"/pending/*.wake
jq -c '.health.stuck = [{card: "c30", issue: 30, step: "waiting", since: "2026-11-11T11:00:00Z", waitsOn: {card: "c33", issue: 33, state: "test"}, waitedMin: 41,
    waitedOn: [{card: "c31", issue: 31, state: "landed"}, {card: "c33", issue: 33, state: "test"}]},
  {card: "c34", issue: 34, step: "test", since: "2026-11-11T11:30:00Z", cases: ["serve", "views"]}, {card: "c35", issue: 35, step: "build", since: "2026-11-11T11:40:00Z"}]' "$T/ask/beta" > "$T/b" && mv "$T/b" "$T/ask/beta"
bash "$SRC/watch-conveyor.sh" --once; CONVEYOR_FOREMAN_NOW=$((CONVEYOR_FOREMAN_NOW + 60))
bash "$SRC/watch-conveyor.sh" --once || fail "no wake for three stuck cards"
w=$(cat "$FD"/pending/*.wake)
for l in "beta: #30 is stuck: it has waited on other cards for 41 minutes in all (#31, #33)" "beta: #34 is stuck: its test step has had serve, views running since 2026-11-11T11:30:00Z" \
    "beta: #35 is stuck: no new step and no output since 2026-11-11T11:40:00Z (last step: build)"; do
  grep -qF "$l" <<<"$w" || fail "a stuck card's line does not say why ($l): $w"
done
# A long reason cuts its own line only; the waiter relays the whole wake, uncut.
rm -f "$FD"/pending/*.wake
snap '[12,15,16]' '[7]' "$(printf 'word %.0s' {1..200})" > "$T/ask/alpha"
bash "$SRC/watch-conveyor.sh" --once || fail "no wake for a new item"
[ "$(head -n 1 "$FD"/pending/*.wake)" = "Conveyor: alpha: needs the owner's yes: #16" ] || fail "the wake names more than the new item: $(cat "$FD"/pending/*.wake)"
snap '[12,15,16,17,18]' '[7,8]' "$(printf 'word %.0s' {1..200})" > "$T/ask/alpha"; rm -f "$FD"/pending/*.wake
bash "$SRC/watch-conveyor.sh" --once || fail "no wake for three new items"
want=$(cat "$FD"/pending/*.wake)
[ "$(head -n 1 <<<"$want")" = "Conveyor: alpha: needs the owner's yes: #17 #18; blocked: #8" ] || fail "the first line lost an item: $(head -n 1 <<<"$want")"
got=$(echo '{}' | CONVEYOR_FOREMAN_WATCHERS='sleep 30' bash "$SRC/waiter.sh" 2>&1 >/dev/null); rc=$? # sleep: a stand-in watcher that finds nothing
[ "$rc" = 2 ] || fail "the waiter did not wake the session (exit $rc)"
[ "$got" = "$want" ] || fail "the waiter did not relay the wake whole: $got"
[ "${#got}" -gt 600 ] || fail "the test's wake is too short to show it is never cut"
compgen -G "$FD/pending/*.wake" >/dev/null && fail "a relayed wake stayed pending"
# A watcher that puts a wake while the waiter waits wakes the session with it.
got=$(echo '{}' | CONVEYOR_FOREMAN_WATCHERS="echo 'Alert: disk full' > $FD/pending/x.wake"$'\nsleep 30' bash "$SRC/waiter.sh" 2>&1 >/dev/null) # sleep: a stand-in watcher that goes on after its alert
[ "$got" = 'Alert: disk full' ] || fail "the waiter did not relay a watcher's wake: $got"
unheld
# A stuck card whose step the engine ended for no progress and runs once more says what the engine did, and wakes
# again though the card was already reported stuck.
rm -f "$FD"/pending/*.wake
jq -c '.health.stuck = [{card: "c9", issue: 9, step: "build", since: "2026-11-11T11:00:00Z"}]' "$T/ask/beta" > "$T/b" && mv "$T/b" "$T/ask/beta"
bash "$SRC/watch-conveyor.sh" --once; CONVEYOR_FOREMAN_NOW=$((CONVEYOR_FOREMAN_NOW + 60))
bash "$SRC/watch-conveyor.sh" --once || fail "no wake for a stuck card"
grep -qF 'beta: #9 is stuck: no new step and no output since 2026-11-11T11:00:00Z (last step: build)' "$FD"/pending/*.wake || fail "the stuck wake: $(cat "$FD"/pending/*.wake)"
rm -f "$FD"/pending/*.wake
jq -c '.health.stuck[0].did = "ended and retried"' "$T/ask/beta" > "$T/b" && mv "$T/b" "$T/ask/beta"
bash "$SRC/watch-conveyor.sh" --once; CONVEYOR_FOREMAN_NOW=$((CONVEYOR_FOREMAN_NOW + 60))
bash "$SRC/watch-conveyor.sh" --once || fail "no wake when the engine ended a stuck card's step and ran it again"
grep -qF 'beta: #9 is stuck: no progress since 2026-11-11T11:00:00Z at build; the engine ended and retried it' "$FD"/pending/*.wake \
  || fail "the stuck wake does not say what the engine did: $(cat "$FD"/pending/*.wake)"
rm -f "$FD"/pending/*.wake; jq -c '.health.stuck = []' "$T/ask/beta" > "$T/b" && mv "$T/b" "$T/ask/beta"
# A card's test step that refused a full run (the owner, 2026-11-14: a whole rerun no rule allows) wakes the Foreman
# once, with the reason the engine saw.
jq -c '.health.refused = [{card: "c40", issue: 40, reason: "refused full run: no list of what the last run passed", since: "2026-11-11T11:50:00Z"}]' "$T/ask/beta" > "$T/b" && mv "$T/b" "$T/ask/beta"
bash "$SRC/watch-conveyor.sh" --once || fail "no wake for a refused full test run"
grep -qF 'beta: #40: the test step refused full run: no list of what the last run passed' "$FD"/pending/*.wake || fail "the refused run's wake: $(cat "$FD"/pending/*.wake)"
rm -f "$FD"/pending/*.wake
bash "$SRC/watch-conveyor.sh" --once && fail "a refused run already reported woke again: $(cat "$FD"/pending/*.wake)"
rm -f "$FD"/pending/*.wake; jq -c '.health.refused = []' "$T/ask/beta" > "$T/b" && mv "$T/b" "$T/ask/beta"
# Issue 221: the machine hold (the loop picks no card while it stands) wakes the Foreman once, naming the failing
# control. Bug it catches: a hold the owner never heard of left the loop idle for good.
jq -c '.health.machineHold = {since: "2026-11-11T11:55:00Z", card: "c41", sha: "0123456789abcdef", controls: ["tests/control.test.sh"], cases: ["tests/a.test.sh: one"]}' "$T/ask/beta" > "$T/b" && mv "$T/b" "$T/ask/beta"
bash "$SRC/watch-conveyor.sh" --once || fail "no wake for the machine hold"
grep -qF 'beta: the machine fails tests/control.test.sh on main, with no change to main that explains it: the loop picks no card until they pass again' "$FD"/pending/*.wake \
  || fail "the machine hold's wake does not name the failing control: $(cat "$FD"/pending/*.wake)"
rm -f "$FD"/pending/*.wake
bash "$SRC/watch-conveyor.sh" --once && fail "a machine hold already reported woke again: $(cat "$FD"/pending/*.wake)"
rm -f "$FD"/pending/*.wake; jq -c '.health.machineHold = null' "$T/ask/beta" > "$T/b" && mv "$T/b" "$T/ask/beta"
}

# Bug: a push that failed its check woke the Foreman only after 10 minutes, as one git or the remote failed does,
# though it never passes on a retry. A check failure wakes at the first poll, naming the check and the issue it was
# pushed after, and again for a later commit it fails on; a transport failure only once it has failed for over 10 minutes.
t_pushwake() {
CASE=pushwake
ready
mkdir -p "$T/ask"; snap '[]' '[]' > "$T/ask/beta"
pushfail() { # <kind> <since> <sha>: alpha's health at 12:00 holds a push failing since then
  snap '[]' '[]' | jq -c --arg k "$1" --arg s "$2" --arg sha "$3" '.health += {pushFailingSince: $s, pushError: {time: $s, sha: $sha, reason: "push-checks: FAILED typecheck-web",
    kind: $k, check: (if $k == "check" then "typecheck-web" else null end), card: "c12", issue: 12}}' > "$T/ask/alpha"
}
pushfail check 2026-11-11T12:00:00Z a1
bash "$SRC/watch-conveyor.sh" --once || fail "a push that failed its check did not wake at the first poll"
w=$(cat "$FD"/pending/*.wake)
[ "$(head -n 1 <<<"$w")" = "Conveyor: alpha: push blocked: #12" ] && grep -qxF "alpha: push blocked: typecheck-web failed after #12; it will not pass on a retry" <<<"$w" \
  || fail "the wake does not name the check and the issue: $w"
rm -f "$FD"/pending/*.wake
bash "$SRC/watch-conveyor.sh" --once && fail "a check failure already reported woke again: $(cat "$FD"/pending/*.wake)"
pushfail check 2026-11-11T12:00:00Z b2
bash "$SRC/watch-conveyor.sh" --once || fail "the check failing on a later commit did not wake"
rm -f "$FD"/pending/*.wake
pushfail transport 2026-11-11T11:51:00Z c3
bash "$SRC/watch-conveyor.sh" --once && fail "a transport failure of 9 minutes woke: $(cat "$FD"/pending/*.wake)"
pushfail transport 2026-11-11T11:49:00Z c3
bash "$SRC/watch-conveyor.sh" --once || fail "a transport failure of 11 minutes did not wake"
grep -qxF 'alpha: the push has failed since 2026-11-11T11:49:00Z: push-checks: FAILED typecheck-web' "$FD"/pending/*.wake || fail "the transport wake: $(cat "$FD"/pending/*.wake)"
# Bug (#617): a push that failed twice is on the Board's Needs you at once (needsYou.blocked, push), but its transport
# failure woke the Foreman only after 10 minutes.
rm -f "$FD"/pending/*.wake
pushfail transport 2026-11-11T11:55:00Z c3
bash "$SRC/watch-conveyor.sh" --once && fail "a transport failure of 5 minutes the Board does not list woke: $(cat "$FD"/pending/*.wake)"
jq -c '.needsYou.blocked = [{card: "c12", issue: 12, title: "t", reason: "the push of main keeps failing. Not pushed: #12", push: true}]' "$T/ask/alpha" > "$T/a" && mv "$T/a" "$T/ask/alpha"
bash "$SRC/watch-conveyor.sh" --once || fail "a push the Board lists under Needs you did not wake"
[ "$(cat "$FD"/pending/*.wake)" = $'Conveyor: alpha: push failing\nalpha: the push has failed since 2026-11-11T11:55:00Z: push-checks: FAILED typecheck-web' ] \
  || fail "the push the Board lists woke as: $(cat "$FD"/pending/*.wake)"
# Bug (#544): the snapshot holds only the newest pushes and landed cards, so an awaited issue pushed before them was in
# neither list and never woke the Foreman. Its push is in the history (`conveyor.sh history`), which the watcher reads
# for an awaited issue the snapshot does not have: #2 in pushedCards, #5 landed and pushed in metrics.cards; #6 landed
# but still unpushed by the snapshot's health wakes nothing. The history is a busy day's, over the 128 KB one argument
# may hold: passed to jq as an argument it failed with "Argument list too long" and the record read as unreachable.
rm -f "$FD"/pending/*.wake
snap '[]' '[]' | jq -c '.pushedCards = [{card: "c90", issue: 90}] | .health.unpushed = [{card: "c6"}]' > "$T/ask/alpha"
jq -cn '{pushedCards: [{card: "c90", issue: 90}, {card: "c2", issue: 2}], metrics: {cards: ([{card: "c5", issue: 5, state: "landed"}, {card: "c6", issue: 6, state: "landed"}]
  + [range(3000) | {card: "c20261115T000000-busy-\(.)", issue: (1000 + .), state: "blocked"}])}}' > "$T/hist"
[ "$(wc -c < "$T/hist")" -gt 131072 ] || fail "the history fixture is not over one argument's limit"
printf '2\n5\n6\n' >> "$FD/await-alpha.txt"
CONVEYOR_FOREMAN_ASK="case \$CONVEYOR_CMD in history) [ \$CONVEYOR_REPO = alpha ] && cat $T/hist ;; *) cat $T/ask/\$CONVEYOR_REPO ;; esac" \
  bash "$SRC/watch-conveyor.sh" --once || fail "an awaited push past the snapshot's newest did not wake"
w=$(cat "$FD"/pending/*.wake)
grep -qxF 'alpha: #2 landed: your step is due' <<<"$w" && grep -qxF 'alpha: #5 landed: your step is due' <<<"$w" \
  || fail "the awaited pushes only the history holds were not named: $w"
grep -qF '#6 landed' <<<"$w" && fail "an awaited card the snapshot's health lists as unpushed woke as landed: $w"
}

# Every entry of the Board's Needs you wakes the Foreman once, read from the snapshot's needsYou (and mainTest). Bug
# (#617): two follow-ups held as pipeline changes waited on the Board for 11 minutes and the Foreman was never woken.
t_needs() {
CASE=needs
ready
mkdir -p "$T/ask"; snap '[]' '[]' > "$T/ask/beta"
snap '[]' '[]' | jq -c '.needsYou = {waiting: [], blocked: [], before: [], farDeps: null, engine: null, testRules: null,
  pipeline: [{issue: 615, title: "conveyor/lib/x.sh:9 the fix\tskips a step", cost: "not assessed", parent: 597, since: "2026-11-11T11:00:00Z"}]}' > "$T/ask/alpha"
bash "$SRC/watch-conveyor.sh" --once || fail "no wake for a held pipeline change"
w=$(cat "$FD"/pending/*.wake)
[ "$(head -n 1 <<<"$w")" = "Conveyor: alpha: pipeline change held: #615" ] \
  && grep -qxF "alpha: pipeline change held: #615 (follow-up of #597): conveyor/lib/x.sh:9 the fix skips a step" <<<"$w" && [ "$(wc -l <<<"$w")" = 2 ] \
  || fail "the wake does not name the pipeline change, its parent and its finding on one line: $w"
rm -f "$FD"/pending/*.wake
bash "$SRC/watch-conveyor.sh" --once && fail "a held pipeline change already reported woke again: $(cat "$FD"/pending/*.wake)"
# D2: a kind added to the list of Needs you kinds the Board reads (.claude/scripts/dashboard_needs.json) wakes under
# its kind, with no change to the watcher: here the watcher runs from a copy of the plugin whose list has one more kind.
mkdir -p "$T/c/conveyor/foreman" "$T/c/conveyor/lib" "$T/c/.claude/scripts"
ln -s "$SRC"/*.sh "$T/c/conveyor/foreman/"; ln -s "$SRC/../lib/portable.sh" "$T/c/conveyor/lib/"
jq '. + [{kind: "newKind", from: ["needsYou", "newKind"], title: "A new kind"}]' "$SRC/../../.claude/scripts/dashboard_needs.json" > "$T/c/.claude/scripts/dashboard_needs.json"
jq -c '.needsYou.newKind = [{issue: 40, title: "a new kind of wait"}]' "$T/ask/alpha" > "$T/a" && mv "$T/a" "$T/ask/alpha"
bash "$SRC/watch-conveyor.sh" --once && fail "a kind not in the list woke: $(cat "$FD"/pending/*.wake)"
bash "$T/c/conveyor/foreman/watch-conveyor.sh" --once || fail "no wake for a new kind of Needs you entry"
w=$(cat "$FD"/pending/*.wake)
[ "$w" = $'Conveyor: alpha: newKind: #40\nalpha: newKind: #40 a new kind of wait' ] || fail "the new kind's wake: $w"
# The other kinds the Board shows: a dependency that cannot be read, an engine update not taken, test issues held and
# the whole test failing on main.
rm -f "$FD"/pending/*.wake
jq -c '.needsYou += {farDeps: [{issue: 41, title: "t", ref: "example/other#3", reason: "not found", line: "Depends on: example/other#3"}],
    engine: {commit: "abc123", reason: "it failed its check", since: "2026-11-11T11:00:00Z"}, testRules: {time: "2026-11-11T11:00:00Z", matched: 90, cap: 20}}
  | .mainTest = {issue: 42, cases: ["serve", "views"], from: "a1", to: "b2", since: "2026-11-11T11:00:00Z"}' "$T/ask/alpha" > "$T/a" && mv "$T/a" "$T/ask/alpha"
bash "$SRC/watch-conveyor.sh" --once || fail "no wake for the other Needs you kinds"
w=$(cat "$FD"/pending/*.wake)
for l in "alpha: #41 waits on example/other#3 in another repository, which cannot be read: not found" \
  "alpha: the plugin commit abc123 was not taken: it failed its check" "alpha: the test rules matched 90 files, over the cap of 20 a day, so they filed none" \
  "alpha: the whole test fails on main (#42): serve, views"; do
  grep -qxF "$l" <<<"$w" || fail "no line '$l': $w"
done
[ "$(wc -l <<<"$w")" = 5 ] || fail "an entry already reported woke again: $w"
}

t_alerts() {
CASE=alerts
ready
# The Board's data file in the shape dashboard.sh publishes it ({updatedAt, panels}, the 7-day limit in the Health
# panel); a limit on pace to run out wakes once while it lasts, and again when it clears and comes back.
jq '.foreman.board = $b' --arg b "$T/data.js" "$XDG_CONFIG_HOME/conveyor/host.json" > "$T/h" && mv "$T/h" "$XDG_CONFIG_HOME/conveyor/host.json"
rm -f "$FD"/pending/*.wake
board 80
bash "$SRC/watch-alerts.sh" --once || fail "an alert in the Board's data file did not wake"
[[ $(cat "$FD"/pending/*.wake) == 'Alert: Claude 7-day limit is on pace to run out before the reset: 80% used'* ]] || fail "the alert wake is wrong: $(cat "$FD"/pending/*.wake)"
rm -f "$FD"/pending/*.wake
bash "$SRC/watch-alerts.sh" --once && fail "an alert still active woke again"
board 20; bash "$SRC/watch-alerts.sh" --once
board 90
bash "$SRC/watch-alerts.sh" --once || fail "an alert that cleared and came back did not wake"
rm -f "$FD"/pending/*.wake
# A question the owner has left over an hour wakes too, read from the ledger of a project of this Foreman and named
# for it; one in the Board's Needs panel does not: that is the one ledger of the Board's checkout, whichever project's
# Foreman reads it.
printf 'window.DASH = %s;\n' '{"panels":{"needs":{"data":{"decisions":[{"id":"d0","askedAt":"2026-01-01T00:00:00Z","question":"Elsewhere"}]}}}}' > "$T/data.js"
bash "$SRC/watch-alerts.sh" --once && fail "a decision in the Board's Needs panel woke the Foreman: $(cat "$FD"/pending/*.wake)"
mkdir -p "$T/beta/.claude/metrics"
jq -cn '{id: "d1", question: "Approve", askedAt: "2026-01-01T00:00:00Z", answeredAt: null}' > "$T/beta/.claude/metrics/decisions.jsonl"
bash "$SRC/watch-alerts.sh" --once || fail "an overdue owner decision in a project's ledger did not wake its Foreman"
[[ $(cat "$FD"/pending/*.wake) == 'Alert: Question waiting on the owner over 1 h: beta: Approve.'* ]] || fail "the question wake is wrong: $(cat "$FD"/pending/*.wake)"
# Bug: a ledger that did not read on one poll dropped its project's questions from the seen file, so the next poll,
# with the ledger read again, woke a second time for the decision already reported.
rm -f "$FD"/pending/*.wake; cp "$T/beta/.claude/metrics/decisions.jsonl" "$T/ledger.ok"
echo '{broken' >> "$T/beta/.claude/metrics/decisions.jsonl"
bash "$SRC/watch-alerts.sh" --once && fail "a ledger that does not read woke: $(cat "$FD"/pending/*.wake)"
mv "$T/ledger.ok" "$T/beta/.claude/metrics/decisions.jsonl"
bash "$SRC/watch-alerts.sh" --once && fail "a decision already reported woke again after its ledger failed to read once: $(cat "$FD"/pending/*.wake)"
rm -f "$FD"/pending/*.wake "$T/beta/.claude/metrics/decisions.jsonl"
# The decisions are the projects' own, so they wake with no Board at all; and a limit alert the Board raised stays
# seen while the Board does not read, so it does not wake again when the Board comes back with it still active.
board 80; bash "$SRC/watch-alerts.sh" --once; rm -f "$FD"/pending/*.wake "$T/data.js"
jq -cn '{id: "d2", question: "Merge", askedAt: "2026-01-01T00:00:00Z", answeredAt: null}' > "$T/beta/.claude/metrics/decisions.jsonl"
bash "$SRC/watch-alerts.sh" --once || fail "an overdue decision did not wake with the Board's data file unreadable"
grep -qF 'beta: Merge' "$FD"/pending/*.wake || fail "the question wake with no Board is wrong: $(cat "$FD"/pending/*.wake)"
rm -f "$FD"/pending/*.wake; board 80
bash "$SRC/watch-alerts.sh" --once && fail "a limit alert still active woke again after the Board was unreadable: $(cat "$FD"/pending/*.wake)"
jq 'del(.foreman.board)' "$XDG_CONFIG_HOME/conveyor/host.json" > "$T/h" && cp "$T/h" "$T/h0" && mv "$T/h" "$XDG_CONFIG_HOME/conveyor/host.json"
rm -f "$FD/alerts-seen.txt"
bash "$SRC/watch-alerts.sh" --once || fail "an overdue decision did not wake with no Board named"
grep -qF 'beta: Merge' "$FD"/pending/*.wake || fail "the question wake with no Board named is wrong: $(cat "$FD"/pending/*.wake)"
jq '.foreman.board = $b' --arg b "$T/data.js" "$T/h0" > "$XDG_CONFIG_HOME/conveyor/host.json"
# A Board that is not JSON, or whose panels are not the shape it reads, holds up no decision either.
for js in '{broken}' '{"panels": "x"}'; do
  rm -f "$FD"/pending/*.wake "$FD/alerts-seen.txt"; printf 'window.DASH = %s;\n' "$js" > "$T/data.js"
  bash "$SRC/watch-alerts.sh" --once || fail "an overdue decision did not wake with the Board's data $js"
  grep -qF 'beta: Merge' "$FD"/pending/*.wake || fail "the question wake with the Board's data $js is wrong: $(cat "$FD"/pending/*.wake)"
done
# A limit the rules cannot read holds up no decision; and a Health panel that does not read forgets no limit alert,
# so one still active when it reads again does not wake twice.
rm -f "$FD"/pending/*.wake "$FD/alerts-seen.txt"
printf 'window.DASH = %s;\n' '{"panels":{"health":{"data":{"limit":{"codex":"x"}}}}}' > "$T/data.js"
bash "$SRC/watch-alerts.sh" --once || fail "an overdue decision did not wake with a malformed limit on the Board"
grep -qF 'beta: Merge' "$FD"/pending/*.wake || fail "the question wake with a malformed limit is wrong: $(cat "$FD"/pending/*.wake)"
rm -f "$FD"/pending/*.wake; board 80; bash "$SRC/watch-alerts.sh" --once || fail "the limit alert did not wake"
rm -f "$FD"/pending/*.wake; printf 'window.DASH = %s;\n' '{"panels": "x"}' > "$T/data.js"
bash "$SRC/watch-alerts.sh" --once && fail "an unreadable Health panel woke: $(cat "$FD"/pending/*.wake)"
board 80; bash "$SRC/watch-alerts.sh" --once && fail "a limit alert still active woke again after an unreadable Health panel: $(cat "$FD"/pending/*.wake)"
rm -f "$FD"/pending/*.wake "$T/h0" "$T/beta/.claude/metrics/decisions.jsonl"; board 20
}

t_state_stop() {
CASE=state-stop
ready
head -c 6000 /dev/zero | tr '\0' x > "$FD/state.md"
out=$(echo '{"stop_hook_active": false}' | bash "$SRC/stop.sh" state)
jq -e '.decision == "block" and (.reason | test("6000 bytes"))' <<<"$out" >/dev/null || fail "a state over its cap did not block the stop: $out"
out=$(echo '{"stop_hook_active": true}' | bash "$SRC/stop.sh" state)
[ -z "$out" ] || fail "the second stop was blocked again: $out"
echo small > "$FD/state.md"
out=$(echo '{"stop_hook_active": false}' | bash "$SRC/stop.sh" state); [ -z "$out" ] || fail "a state under its cap blocked: $out"
out=$(echo '{"stop_hook_active": false}' | CONVEYOR_FOREMAN= bash "$SRC/stop.sh" state); [ -z "$out" ] || fail "another session was checked"
}

t_reply_stop() {
CASE=reply-stop
ready
turn() { # <uuid> <opening text> <reply>
  jq -cn --arg u "$1" --arg o "$2" --arg r "$3" '{type: "user", uuid: $u, message: {content: $o}}, {type: "assistant", message: {content: [{type: "text", text: $r}]}}' > "$T/t.jsonl"
  jq -cn --arg t "$T/t.jsonl" '{transcript_path: $t, stop_hook_active: true}' | bash "$SRC/stop.sh" reply
}
out=$(turn u1 'what now' 'Should I retry #7?'); jq -e '.decision == "block" and (.reason | test("picker"))' <<<"$out" >/dev/null || fail "a question in text passed: $out"
out=$(turn u1 'what now' 'Should I retry #7?'); [ -z "$out" ] || fail "the same turn was refused twice: $out"
out=$(turn u2 'what now' 'Filed #9 and held it.'); [ -z "$out" ] || fail "a plain report was refused: $out"
out=$(turn u3 'what now' 'Want me to file it.'); jq -e '.decision == "block"' <<<"$out" >/dev/null || fail "undone work passed: $out"
out=$(turn u3b 'what now' 'I still need to file #9.'); jq -e '.decision == "block"' <<<"$out" >/dev/null || fail "work left undone passed: $out"
out=$(turn u3d 'what now' 'You still need to approve #7 because it changes the sign-in page.'); [ -z "$out" ] || fail "the owner's own decision was refused as unfinished work: $out"
# The whole final reply is checked, not only its last text block.
jq -cn '{type: "user", uuid: "u3e", message: {content: "what now"}}, {type: "assistant", message: {content: [{type: "text", text: "Should I file #9?"}, {type: "text", text: "Idle"}]}}' > "$T/t.jsonl"
out=$(jq -cn --arg t "$T/t.jsonl" '{transcript_path: $t}' | bash "$SRC/stop.sh" reply)
jq -e '.decision == "block" and (.reason | test("picker"))' <<<"$out" >/dev/null || fail "a question in an earlier text block passed: $out"
# A long turn is still checked when its opening entry is over a thousand entries back.
{ jq -cn '{type: "user", uuid: "u3f", message: {content: "what now"}}'
  for _ in $(seq 1000); do echo '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Bash"}]}}'; done
  jq -cn '{type: "assistant", message: {content: [{type: "text", text: "I still need to file #9."}]}}'; } > "$T/t.jsonl"
out=$(jq -cn --arg t "$T/t.jsonl" '{transcript_path: $t}' | bash "$SRC/stop.sh" reply)
jq -e '.decision == "block"' <<<"$out" >/dev/null && [ "$(cat "$FD/reply-mark")" = u3f ] || fail "a long turn whose opening left the last thousand entries passed: $out"
out=$(turn u3c 'what now' $'May I retry #7?\nWaiting for your answer.'); jq -e '.decision == "block" and (.reason | test("picker"))' <<<"$out" >/dev/null || fail "a question before a closing line passed: $out"
printf 'Conveyor: alpha: blocked: #7\nalpha: #7 is blocked\n' > "$FD/last-wake.txt"
out=$(turn u4 'Stop hook feedback: Conveyor: alpha: blocked: #7' '#5 is still running, nothing needs you.'); jq -e '.decision == "block"' <<<"$out" >/dev/null || fail "play-by-play in a wake reply passed: $out"
out=$(turn u5 'Stop hook feedback: Conveyor: alpha: blocked: #7' 'Idle'); [ -z "$out" ] || fail "a one-word wake reply was refused: $out"
out=$(turn u6 'Stop hook feedback: Conveyor: alpha: blocked: #7' '#12 landed successfully.'); jq -e '.decision == "block"' <<<"$out" >/dev/null || fail "a report in a wake reply passed: $out"
out=$(turn u7 'Stop hook feedback: Conveyor: alpha: blocked: #7' '#7 needs your call: its fix changes the sign-in page.'); [ -z "$out" ] || fail "a wake reply naming what needs the owner was refused: $out"
# Bug (#139): a wake reply reporting a defect in Conveyor itself was refused as a status note, so the Foreman wrote
# Idle and the owner never saw it. A plugin-problem line passes, and is noted in plugin-bugs.md once.
bug='Plugin problem (for the conveyor-belt repo): setup never sets linkFromMain, so card c20261116T101500-alpha-7 has no packages; evidence ~/cards/c20261116T101500-alpha-7/test.log.'
out=$(turn u10 'Stop hook feedback: Conveyor: alpha: blocked: #7' "$bug"); [ -z "$out" ] || fail "a plugin-problem line in a wake reply was refused: $out"
[ "$(grep -c '^- ' "$FD/plugin-bugs.md" 2>/dev/null)" = 1 ] && grep -qE '^- [0-9T:-]+Z · card c20261116T101500-alpha-7 · setup never sets linkFromMain.* · evidence: ~/cards/c20261116T101500-alpha-7/test\.log$' "$FD/plugin-bugs.md" \
  || fail "the plugin problem was not noted with its time, card, finding and evidence: $(cat "$FD/plugin-bugs.md" 2>&1)"
# A status note beside it is still refused, the form named; the line said again is not noted twice.
out=$(turn u11 'Stop hook feedback: Conveyor: alpha: blocked: #7' "Released #926 so its review could finish."$'\n'"$bug")
jq -e '.decision == "block" and (.reason | contains("Plugin problem (for the conveyor-belt repo): <what you saw>"))' <<<"$out" >/dev/null || fail "a status note beside a plugin problem passed: $out"
[ "$(grep -c '^- ' "$FD/plugin-bugs.md")" = 1 ] || fail "a plugin problem said again was noted twice: $(cat "$FD/plugin-bugs.md")"
# A finding in other words is refused, and told the form that keeps it.
out=$(turn u12 'Stop hook feedback: Conveyor: alpha: blocked: #7' 'The tests likely failed because Conveyor does not install packages in card worktrees, another plugin problem.')
jq -e '.decision == "block" and (.reason | contains("Plugin problem (for the conveyor-belt repo): <what you saw>, card <card>, evidence <path>"))' <<<"$out" >/dev/null \
  || fail "a refused plugin finding was not told the form to use: $out"
# Only the owner can file a plugin problem, so "not filed yet" on its line is no unfinished work of the Foreman's; a
# finding that is part of one noted before is noted on its own.
out=$(turn u13 'what now' 'Plugin problem (for the conveyor-belt repo): setup never sets linkFromMain, not filed yet.'); [ -z "$out" ] || fail "a plugin problem not filed yet was refused as unfinished work: $out"
[ "$(grep -c '^- ' "$FD/plugin-bugs.md")" = 2 ] || fail "a shorter plugin problem was taken for one noted before: $(cat "$FD/plugin-bugs.md")"
# A wake delivered as a meta entry opens its own turn: its reply is checked as a wake reply, not as the owner's last message.
jq -cn '{type: "user", uuid: "u8", message: {content: "watch"}}, {type: "assistant", message: {content: [{type: "text", text: "Watching."}]}},
  {type: "user", uuid: "u8w", isMeta: true, message: {content: "Stop hook feedback: Conveyor: alpha: blocked: #7"}},
  {type: "assistant", message: {content: [{type: "text", text: "#12 landed successfully."}]}}' > "$T/t.jsonl"
out=$(jq -cn --arg t "$T/t.jsonl" '{transcript_path: $t}' | bash "$SRC/stop.sh" reply)
jq -e '.decision == "block"' <<<"$out" >/dev/null || fail "a report replying to a meta wake passed: $out"
# Bug (#243): the owner typed a request during a turn that began with a wake, and the report answering it was refused
# as a wake reply, so the Foreman wrote it twice. A message the owner types mid-turn (a queued_command entry of human
# origin) makes the reply an answer to the owner; a task notification queued mid-turn does not.
midturn() { # <uuid> <origin kind>
  jq -cn --arg u "$1" --arg k "$2" '{type: "user", uuid: $u, isMeta: true, message: {content: "Stop hook feedback: Conveyor: alpha: blocked: #7"}},
    {type: "assistant", message: {content: [{type: "tool_use", name: "Bash"}]}},
    {type: "attachment", attachment: {type: "queued_command", prompt: "file the bugs you found", origin: {kind: $k}}},
    {type: "user", message: {content: [{type: "tool_result", content: "ok"}]}},
    {type: "assistant", message: {content: [{type: "text", text: "Filed #31 and #32 in the conveyor-belt repo."}]}}' > "$T/t.jsonl"
  jq -cn --arg t "$T/t.jsonl" '{transcript_path: $t}' | bash "$SRC/stop.sh" reply
}
out=$(midturn u14 human); [ -z "$out" ] || fail "the reply to the owner's mid-turn request was judged as a wake reply: $out"
out=$(midturn u15 task-notification); jq -e '.decision == "block"' <<<"$out" >/dev/null || fail "a report replying to a wake passed after a task notification: $out"
# Other meta entries still do not open a turn.
jq -cn '{type: "user", uuid: "u9", message: {content: "what now"}}, {type: "user", uuid: "u9m", isMeta: true, message: {content: "Caveat: example"}},
  {type: "assistant", message: {content: [{type: "text", text: "Should I file #9?"}]}}' > "$T/t.jsonl"
out=$(jq -cn --arg t "$T/t.jsonl" '{transcript_path: $t}' | bash "$SRC/stop.sh" reply)
jq -e '.decision == "block"' <<<"$out" >/dev/null && [ "$(cat "$FD/reply-mark")" = u9 ] || fail "a meta entry that is not a wake opened the turn: $out"
}

t_filing() {
CASE=filing
ready
# An issue the Foreman files is held from its first sight: before the command runs, every record starts new issues
# held; after it, each issue linked is held in its own record, and the records start new issues in the queue again.
: > "$T/calls"
fileask
cmd='conveyor.sh gh-write issue create --repo example/beta --title example --body example; gh issue create -R example/beta --title example --body example; gh issue create --title example --body example'
out=$(jq -cn --arg c "$cmd" '{hook_event_name: "PreToolUse", tool_input: {command: $c}}' | bash "$SRC/foreman.sh" filing)
[ -z "$out" ] || fail "the filing command was refused: $out"
[ "$(grep -c 'control start held' "$T/calls")" = 2 ] || fail "not every record starts new issues held before the command runs: $(cat "$T/calls")"
: > "$T/calls"
# Issue 330: three issues filed in one command are all held, and each by `control adopt`, which leaves one the owner
# released before this hook ran released (deps.test.sh t_startadopt), where `control hold` held it again.
out=$(jq -cn --arg c "$cmd" '{hook_event_name: "PostToolUse", tool_input: {command: $c},
  tool_response: {stdout: "https://github.com/example/beta/issues/12\nhttps://github.com/example/beta/issues/15\nhttps://github.com/example/alpha/issues/30\n", stderr: ""}}' \
  | bash "$SRC/foreman.sh" filed)
grep -qx 'beta control adopt 12 15' "$T/calls" && grep -qx 'alpha control adopt 30' "$T/calls" || fail "each issue filed is not held in its own record: $(cat "$T/calls")"
[ "$(grep -c 'control start queue' "$T/calls")" = 2 ] || fail "the records do not start new issues in the queue again: $(cat "$T/calls")"
[ "$(sed -n '$p' "$T/calls" | cut -d' ' -f2-)" = 'control start queue' ] || fail "the queue was set back before every issue was held: $(cat "$T/calls")"
jq -e '.hookSpecificOutput.additionalContext | test("#?12") and test("15") and test("30")' <<<"$out" >/dev/null || fail "the Foreman is not told what was held: $out"
# Issue 330: the Foreman is told as held only the issues the record holds after the adopt: one released already
# (#15) is named apart, not as held with a word to release it again.
in=$(jq -cn --arg c "$cmd" '{hook_event_name: "PostToolUse", tool_input: {command: $c}, tool_response: {stdout: "https://github.com/example/beta/issues/12\nhttps://github.com/example/beta/issues/15\n"}}')
out=$(CONVEYOR_FOREMAN_ASK="[ \"\$CONVEYOR_CMD\" != 'control adopt 12 15' ] || echo '{\"held\":[3,12]}'" bash "$SRC/foreman.sh" filed <<<"$in")
jq -e '.hookSpecificOutput.additionalContext | test("Held in Conveyor \\(beta: 12\\)") and test("released already \\(beta: 15\\)")' <<<"$out" >/dev/null \
  || fail "a released issue was told to the Foreman as held: $out"
# Issue 330: a record whose engine has no `control adopt` (it pins an older one) refuses it as a usage error: the
# issues are held with `control hold` there, not reported as not held after GitHub filed them.
: > "$T/calls"
out=$(CONVEYOR_FOREMAN_ASK="echo \"\$CONVEYOR_CMD\" >> $T/calls; case \$CONVEYOR_CMD in 'control adopt'*) echo 'usage: conveyor.sh control [hold <issue>...]' >&2; exit 2 ;; 'control hold'*) echo '{\"held\":[12,15]}' ;; esac" \
  bash "$SRC/foreman.sh" filed <<<"$in")
grep -qx 'control hold 12 15' "$T/calls" && jq -e '.hookSpecificOutput.additionalContext | test("Held in Conveyor \\(beta: 12, 15\\)")' <<<"$out" >/dev/null \
  || fail "an older engine's record did not hold the issues filed: $out $(cat "$T/calls")"
# Nor does the Foreman start new issues in the queue again while the research lane's filer holds its turn: the filer,
# seeing them set held by the Foreman's filing, set nothing, and its issue is not yet held.
printf 'alpha\n' > "$FH"; : > "$T/calls"; mkdir -p "$T/state/lanes/research-filer"; mkfifo "$T/turn"
flock "$T/state/lanes/research-filer/filing.lock" sh -c "read x < '$T/turn'" & turn=$!
until flock -n "$T/state/lanes/research-filer/filing.lock" true; [ $? = 1 ]; do sleep 0.1; done
jq -cn --arg c "$cmd" '{hook_event_name: "PostToolUse", tool_input: {command: $c}, tool_response: {stdout: "", stderr: ""}}' \
  | bash "$SRC/foreman.sh" filed > "$T/filed" 2>&1 & filed=$!
wait_until 'under "$filed" flock || ! kill -0 "$filed" 2>/dev/null' # it waits at the turn's lock, or has ended
! grep -q 'start queue' "$T/calls" || { echo go > "$T/turn"; fail "the Foreman started new issues in the queue again while the lane's filer held its turn: $(cat "$T/calls")"; }
echo go > "$T/turn"; wait "$turn"; wait "$filed"
[ "$(cat "$T/calls")" = 'alpha control start queue' ] && [ ! -s "$FH" ] \
  || fail "the Foreman did not start new issues in the queue again once the filer's turn was free: $(cat "$T/calls" "$T/filed")"
# A quoted subcommand files an issue just the same: it is held before and after.
cmd="gh issue 'create' --repo example/alpha --title example --body example"
: > "$T/calls"
out=$(jq -cn --arg c "$cmd" '{hook_event_name: "PreToolUse", tool_input: {command: $c}}' | bash "$SRC/foreman.sh" filing)
grep -q 'control start held' "$T/calls" || fail "a quoted filing command was not seen before it ran: $(cat "$T/calls")"
: > "$T/calls"
out=$(jq -cn --arg c "$cmd" '{hook_event_name: "PostToolUse", tool_input: {command: $c}, tool_response: {stdout: "https://github.com/example/alpha/issues/31\n"}}' \
  | bash "$SRC/foreman.sh" filed)
grep -qx 'alpha control adopt 31' "$T/calls" || fail "a quoted filing command's issue was not held: $(cat "$T/calls")"
# A subcommand made by an expansion cannot be read, so it is held as filing; flags before the subcommand do not hide it.
# Another HTTP client (curl, wget, a script) files an issue on the issues list or GraphQL endpoint just as gh does, and
# whether it writes cannot be read: a script POSTs whenever it sends a body, a quoted `;` is no command break, and an
# escape (\u, \x, %) spells the endpoint or createIssue all the same. So naming either endpoint is held, and so is a
# request read from a file (a curl config, a wget input file) or made by an expansion.
bs='\'
for cmd in 'sub=create; gh issue "$sub" --title example --body example' 'gh issue ${sub} --title example' 'gh issue $(echo create) --title example' 'gh issue `echo new` --title example' \
  'sub=create; gh issue --repo example/alpha "$sub" --title example' 'gh issue -R example/alpha $sub' 'gh issue --repo=example/alpha $sub' \
  'gh issue --repo example/alpha create --title example' 'gh issue -R example/alpha new' \
  'noun=issue; sub=create; gh "$noun" "$sub" --title example --body example' 'gh -R example/alpha $noun $sub' 'conveyor.sh gh-write "$noun" create' \
  'repo=example/alpha; gh issue --repo "$repo" "$sub"' 'sub=create; gh issue -Rexample/alpha "$sub" --title example --body example' \
  'gh -Rexample/alpha issue $sub' 'gh -Rexample/alpha $noun create' 'gh api repos/example/alpha/issues -f title=example -f body=example' \
  "gh api graphql -f query='mutation { createIssue(input: {repositoryId: \"x\", title: \"example\"}) { issue { url } } }'" \
  'gh api graphql -F query=@reports/create.graphql' 'gh api graphql --input reports/create.json' 'gh api graphql -f query="$q"' \
  "curl --netrc -X POST https://api.github.com/repos/example/alpha/issues -H 'Content-Type: application/json' -d '{\"title\":\"example\"}'" \
  'wget --post-data=title=example "https://api.github.com/repos/$repo/issues"' 'curl -d @reports/create.json https://api.github.com/graphql' \
  "python3 -c 'import urllib.request as u; u.urlopen(u.Request(\"https://api.github.com/repos/example/alpha/issues\", b\"{}\", method=\"POST\"))'" \
  'curl --netrc --config reports/create.curl' 'curl --netrc -Kreports/create.curl' 'wget -i reports/urls.txt' 'curl -X POST "$url" -d @reports/create.json' \
  "curl --netrc https://api.github.com/repos/example/alpha/issues -H 'Content-Type: application/json; charset=utf-8' -d '{\"title\":\"example\"}'" \
  "python3 -c 'import urllib.request as u; u.urlopen(u.Request(\"https://api.github.com/repos/example/alpha/issues\", b\"{}\", headers={\"Authorization\":\"Bearer TOKEN\"}))'" \
  "curl --netrc https://api.github.com/graphql --json '{\"query\":\"mutation { create${bs}u0049ssue(input:{repositoryId:\\\"ID\\\",title:\\\"example\\\"}) { issue { id } } }\"}'" \
  "gh api graphql -f query='mutation { create${bs}u0049ssue(input: {repositoryId: \"x\", title: \"example\"}) { issue { url } } }'" \
  "python3 -c 'u.urlopen(\"https://api.github.com/repos/example/alpha/${bs}x69ssues\", b\"{}\")'" 'curl -d x https://api.github.com/repos/example/alpha/%69ssues' \
  'curl --netrc https://api.github.com/repos/example/alpha/issues' "curl --netrc https://api.github.com/graphql -d '{\"query\":\"{ viewer { login } }\"}'"; do
  : > "$T/calls"; : > "$FH"
  out=$(jq -cn --arg c "$cmd" '{hook_event_name: "PreToolUse", tool_input: {command: $c}}' | bash "$SRC/foreman.sh" filing)
  grep -q 'control start held' "$T/calls" || fail "a filing command was not seen before it ran ($cmd): $(cat "$T/calls")"
done
for cmd in 'gh issue view 7 --json "$f"' 'gh issue -R example/alpha view 7 --json "$f"' 'repo=example/alpha; gh issue --repo "$repo" view 7' \
  'gh issue -R $repo view 7' 'gh issue --repo=$repo view 7' 'gh --repo "$repo" issue view 7' 'gh issue -Rexample/alpha view 7' \
  'gh api repos/example/alpha/issues/7/comments' 'curl https://api.github.com/repos/example/alpha/issues/7' \
  'gh api graphql -f query="{ viewer { login } }"' 'cat docs/graphql.md' 'printf "%s\n" example'; do
  : > "$T/calls"; : > "$FH"
  out=$(jq -cn --arg c "$cmd" '{hook_event_name: "PreToolUse", tool_input: {command: $c}}' | bash "$SRC/foreman.sh" filing)
  [ ! -s "$T/calls" ] || fail "reading an issue was taken for filing ($cmd): $(cat "$T/calls")"
done
cmd="gh issue 'create' --repo example/alpha --title example --body example"
# Records that cannot be read hold nothing, so the filing command is refused, not run.
jq '.records = []' "$XDG_CONFIG_HOME/conveyor/host.json" > "$T/h" && cp "$XDG_CONFIG_HOME/conveyor/host.json" "$T/h0" && mv "$T/h" "$XDG_CONFIG_HOME/conveyor/host.json"
out=$(jq -cn --arg c "$cmd" '{hook_event_name: "PreToolUse", tool_input: {command: $c}}' | bash "$SRC/foreman.sh" filing)
jq -e '.hookSpecificOutput.permissionDecision == "deny"' <<<"$out" >/dev/null || fail "filing ran with no record to hold its issue in: $out"
out=$(jq -cn --arg c "$cmd" '{hook_event_name: "PostToolUse", tool_input: {command: $c}, tool_response: {stdout: "https://github.com/example/alpha/issues/32\n"}}' \
  | bash "$SRC/foreman.sh" filed)
jq -e '.decision == "block"' <<<"$out" >/dev/null || fail "an issue filed with no record to hold it in was let pass: $out"
mv "$T/h0" "$XDG_CONFIG_HOME/conveyor/host.json"
# Issue 330: a filing command run in the background has its filed hook as it starts, so the records went back to the
# queue before its issues were filed, and its output linked none: none was held. It is refused, with nothing set.
: > "$T/calls"
out=$(jq -cn --arg c "$cmd" '{hook_event_name: "PreToolUse", tool_input: {command: $c, run_in_background: true}}' | bash "$SRC/foreman.sh" filing)
jq -e '.hookSpecificOutput.permissionDecision == "deny"' <<<"$out" >/dev/null && [ ! -s "$T/calls" ] \
  || fail "a filing command run in the background was not refused, or set records: $out $(cat "$T/calls")"
}

t_ask_pin() {
CASE=ask-pin
ready
# A record command runs the pinned install only when the pin is a full commit id: a pin that is a path (../escape)
# would run a conveyor.sh outside the versions folder.
mkdir -p "$T/gamma/.conveyor" "$XDG_DATA_HOME/conveyor/escape/conveyor" "$XDG_DATA_HOME/conveyor/versions/$PIN2/conveyor"
for d in escape "versions/$PIN2"; do printf '#!/usr/bin/env bash\necho "ran %s $*"\n' "$d" > "$XDG_DATA_HOME/conveyor/$d/conveyor/conveyor.sh"; done
jq -n --arg p "$PIN2" '{plugin: {commit: $p}}' > "$T/gamma/.conveyor/project.json"
askg() { env -u CONVEYOR_FOREMAN_ASK CONVEYOR_FOREMAN_DIR="$FD" bash -c '. "$1/lib.sh" && ask gamma "$2" health' _ "$SRC" "$T/gamma"; }
out=$(askg 2>&1)
[ "$out" = "ran versions/$PIN2 health" ] || fail "a full commit pin did not run its install: $out"
for pin in ../escape "../escape/../versions/$PIN2" "${PIN2^^}" 7; do
  jq -n --arg p "$pin" '{plugin: {commit: $p}}' > "$T/gamma/.conveyor/project.json"
  out=$(askg 2>&1) \
    && fail "the pin $pin was accepted: $out"
  [[ $out != *ran* ]] || fail "the pin $pin ran a conveyor.sh: $out"
done
jq -n '{plugin: {commit: 7}}' > "$T/gamma/.conveyor/project.json"
askg > /dev/null 2>&1 && fail "a numeric pin was accepted"
}

t_ask_self() {
CASE=ask-self
ready
unset CONVEYOR_FOREMAN_ASK
# Bug caught (issue 40): a record whose pack has no plugin key (the plugin's own checkout, which runs the engine from
# itself) had no engine the Foreman could run, so it read as unreachable and its cards never woke the Foreman. alpha
# follows an install here; beta runs its own conveyor/conveyor.sh, with card 7 blocked.
mkdir -p "$XDG_DATA_HOME/conveyor/versions/$PIN2/conveyor" "$T/beta/conveyor"
jq -n '{plugin: {follow: "main"}}' > "$M/.conveyor/project.json" && jq -n --arg c "$PIN2" '{commit: $c}' > "$M/.git/conveyor-engine.json"
jq 'del(.plugin)' "$T/beta/.conveyor/project.json" > "$T/p" && mv "$T/p" "$T/beta/.conveyor/project.json"
belt() { jq -c --argjson i "$1" --arg t "$2" '.belt = [{card: "c\($i)", issue: $i, step: "build", title: $t}]'; }
snap '[]' '[]' | belt 5 "an alpha page" > "$T/snap-alpha"; snap '[]' '[7]' | belt 8 "a beta page" > "$T/snap-beta"
for e in "$XDG_DATA_HOME/conveyor/versions/$PIN2:alpha" "$T/beta:beta"; do
  printf '#!/usr/bin/env bash\n[ "$1" = snapshot ] && cat %q\n' "$T/snap-${e##*:}" > "${e%:*}/conveyor/conveyor.sh"
done
out=$(cd "$M" && bash "$SRC/../conveyor.sh" foreman status 2>&1)
grep -qxF "alpha: 1 on the belt" <<<"$out" && grep -qF "#5 build" <<<"$out" || fail "status did not read the record that follows an install: $out"
grep -qxF "beta: 1 on the belt" <<<"$out" && grep -qF "#8 build" <<<"$out" || fail "status did not read the record that runs its own engine: $out"
bash "$SRC/watch-conveyor.sh" --once || fail "no wake for the blocked card of the record that runs its own engine"
grep -qF "beta: #7 is blocked" "$FD"/pending/*.wake || fail "the wake does not name beta's blocked card: $(cat "$FD"/pending/*.wake)"
}

t_session() {
CASE=session
# The Foreman named Ada (as launch names it), the records' snapshots of the case wake, and each record command noted.
ready; fileask
jq '.foreman.name = "Ada"' "$XDG_CONFIG_HOME/conveyor/host.json" > "$T/h" && mv "$T/h" "$XDG_CONFIG_HOME/conveyor/host.json"
mkdir -p "$T/ask"; snap '[12,15,16,17,18]' '[7,8]' > "$T/ask/alpha"; snap '[19]' '[]' > "$T/ask/beta"
# The Foreman is marked by session, not by environment: a session started with no CONVEYOR_FOREMAN (claude
# --continue, an IDE) is the Foreman when /conveyor-belt:foreman marked it, and only then. Losing the mark silently
# left a Foreman running for hours with no alert.
unset CONVEYOR_FOREMAN
rm -f "$FD"/pending/*.wake
big() { head -c 6000 /dev/zero | tr '\0' x > "$FD/state.md"; }
big; out=$(sess s1 | bash "$SRC/stop.sh" state); [ -z "$out" ] || fail "an unmarked session ran the Foreman's stop hook: $out"
out=$(bash "$SRC/foreman.sh" claim s1) || fail "the claim failed: $out"
[ "$(head -n 1 <<<"$out")" = "This session is now the Foreman (Ada): its watchers start at the end of this turn." ] || fail "the claim does not say so in one line: $out"
grep -qF 'Foreman mode: you are Ada' <<<"$out" || fail "the claiming session got no Foreman rules: $out"
out=$(sess s1 | bash "$SRC/stop.sh" state); jq -e '.decision == "block"' <<<"$out" >/dev/null || fail "the marked session did not run the Foreman's stop hook: $out"
out=$(sess s2 | bash "$SRC/stop.sh" state); [ -z "$out" ] || fail "a session that is not marked ran the Foreman's stop hook: $out"
echo small > "$FD/state.md"
# Continued or resumed with the same id, it is still the Foreman: its start gives it its rules.
out=$(sess s1 resume | bash "$SRC/foreman.sh" start); grep -qF 'Foreman mode: you are Ada' <<<"$out" || fail "the resumed Foreman got no Foreman start: $out"
out=$(sess s2 startup | bash "$SRC/foreman.sh" start); [ -z "$out" ] || fail "another session got the Foreman's start: $out"
# A claim from a second session moves the mark, and the first session's waiter and its watchers exit at once.
# The waiter's output goes through cat, which ends only once nothing the waiter started holds it open.
rm -f "$FD/waiter.pid"
# The watcher is slow to stop on TERM: the claim still returns only once it is gone.
sess s1 | CONVEYOR_FOREMAN_WATCHERS="trap 'sleep 2; exit' TERM; echo \$\$ > $T/w1; while :; do sleep 1; done" bash "$SRC/waiter.sh" 2>&1 | cat > "$T/wout" & cp=$! # sleep: the 2 s the stand-in watcher takes to stop
wait_until '[ -s "$FD/waiter.pid" ] && [ -s "$T/w1" ] || ! kill -0 "$cp" 2>/dev/null'
[ -s "$T/w1" ] || fail "the Foreman's waiter did not start its watchers"
wp=$(cut -d' ' -f1 "$FD/waiter.pid")
bash "$SRC/foreman.sh" claim s2 > /dev/null || fail "the second claim failed"
[ "$(cut -d' ' -f1 "$FD/session")" = s2 ] || fail "the second claim did not move the mark: $(cat "$FD/session")"
kill -0 "$wp" 2>/dev/null && { kill "$wp"; fail "the first session's waiter still runs after the role moved"; }
kill -0 "$(cat "$T/w1")" 2>/dev/null && fail "the first session's watcher still ran when the claim returned"
wait_until '! kill -0 "$cp" 2>/dev/null'
kill -0 "$cp" 2>/dev/null && fail "something the first session's waiter started still runs after the role moved"
[ ! -s "$T/wout" ] || fail "the first session's waiter woke its session when the role moved: $(cat "$T/wout")"
kill -0 "$(cat "$T/w1")" 2>/dev/null && fail "the first session's watcher still runs after the role moved"
rm -f "$T/w1"; out=$(sess s1 | CONVEYOR_FOREMAN_WATCHERS="echo \$\$ > $T/w1" bash "$SRC/waiter.sh" 2>&1); rc=$?
[ "$rc" = 0 ] && [ ! -e "$T/w1" ] || fail "the first session's waiter started watchers at its next stop (exit $rc): $out"
out=$(sess s2 | CONVEYOR_FOREMAN_WATCHERS=". $SRC/lib.sh && echo 'Alert: moved' | pending_put" bash "$SRC/waiter.sh" 2>&1 >/dev/null); rc=$?
[ "$rc" = 2 ] && [ "$out" = 'Alert: moved' ] || fail "the new Foreman's waiter did not run its watchers (exit $rc): $out"
unheld
out=$(sess s1 resume | bash "$SRC/foreman.sh" start)
# Plain stdout at SessionStart reaches only Claude: the owner sees the line only as the systemMessage.
[ "$(wc -l <<<"$out")" = 1 ] && jq -e '.systemMessage | contains("no longer the Foreman")' <<<"$out" >/dev/null \
  || fail "the former Foreman's owner was not shown one line at its start: $out"
out=$(sess s1 resume | bash "$SRC/foreman.sh" start); [ -z "$out" ] || fail "the former Foreman was told twice: $out"
# A fork (--fork-session: source fork, a new id) keeps the role when its transcript is the Foreman's.
jq -cn '{type: "user", sessionId: "s3", forkedFrom: {sessionId: "s2", messageUuid: "u1"}, message: {content: "watch"}}' > "$T/fork.jsonl"
out=$(sess s3 fork "$T/fork.jsonl" | bash "$SRC/foreman.sh" start)
[ "$(cut -d' ' -f1 "$FD/session")" = s3 ] && grep -qF 'Foreman mode: you are Ada' <<<"$out" || fail "a fork of the Foreman lost the role: $(cat "$FD/session") $out"
jq -cn '{type: "user", sessionId: "s4", message: {content: "watch"}}' > "$T/other.jsonl"
jq -cn '{type: "user", sessionId: "s5", forkedFrom: {sessionId: "s3", messageUuid: "u2"}, message: {content: "watch"}}' > "$T/fork2.jsonl"
sess s4 resume "$T/other.jsonl" | bash "$SRC/foreman.sh" start > /dev/null
[ "$(cut -d' ' -f1 "$FD/session")" = s3 ] || fail "resuming another session took the role"
# A fork that lost the role gets it back only by a claim: resuming it, its transcript still copied from the claimant,
# tells it the role moved, or two sessions would each take the role from the other.
bash "$SRC/foreman.sh" claim s2 > /dev/null || fail "the claim back to s2 failed"
out=$(sess s3 resume "$T/fork.jsonl" | bash "$SRC/foreman.sh" start)
[ "$(cut -d' ' -f1 "$FD/session")" = s2 ] && jq -e '.systemMessage | contains("no longer the Foreman")' <<<"$out" >/dev/null \
  || fail "a displaced fork took the role back by a resume: $(cat "$FD/session") $out"
out=$(sess s3 resume "$T/fork.jsonl" | bash "$SRC/foreman.sh" start)
[ "$(cut -d' ' -f1 "$FD/session")" = s2 ] && [ -z "$out" ] || fail "a displaced fork, once told, took the role back by a resume: $(cat "$FD/session") $out"
bash "$SRC/foreman.sh" claim s3 > /dev/null || fail "the claim back to s3 failed"
# A resume that waits on the claim lock while off runs reads the mark only once it holds the lock: it never undoes off.
exec 8>>"$FD/claim.lock"; flock 8
sess s5 fork "$T/fork2.jsonl" | bash "$SRC/foreman.sh" start > /dev/null & rp=$!
wait_until 'under "$rp" flock || ! kill -0 "$rp" 2>/dev/null' # it waits at the claim lock, or has ended
: > "$FD/session"; flock -u 8; exec 8>&-
wait "$rp"
[ ! -s "$FD/session" ] || fail "a resume that waited on the lock undid off: $(cat "$FD/session")"
bash "$SRC/foreman.sh" claim s3 > /dev/null || fail "the claim back to s3 after the resume failed"
# off clears the mark, and the launcher's environment does not bring it back.
out=$(bash "$SRC/foreman.sh" off) && [ ! -s "$FD/session" ] || fail "off did not clear the mark: $out"
big
out=$(sess s3 | bash "$SRC/stop.sh" state); [ -z "$out" ] || fail "the Foreman's hooks ran after off: $out"
out=$(sess s3 | CONVEYOR_FOREMAN=1 bash "$SRC/stop.sh" state); [ -z "$out" ] || fail "the launcher's environment overrode off: $out"
# Nor does the launcher's session start again by /clear or a compaction: only a fresh launch marks it.
for src in clear compact resume; do
  sess s3 "$src" | CONVEYOR_FOREMAN=1 bash "$SRC/foreman.sh" start > /dev/null
  [ ! -s "$FD/session" ] || fail "the launcher's session took the role back on a $src start after off: $(cat "$FD/session")"
done
# The launcher marks its own session at its start.
echo small > "$FD/state.md"
out=$(sess s5 startup | CONVEYOR_FOREMAN=1 bash "$SRC/foreman.sh" start)
[ "$(cut -d' ' -f1 "$FD/session")" = s5 ] && grep -qF 'Foreman mode: you are Ada' <<<"$out" || fail "the launcher did not mark its session: $(cat "$FD/session")"
# One Foreman per group: a claim in the checkout of another project of the group (its own state folder) moves the
# group's mark, kept in the first-named project's folder.
out=$(cd "$T/beta" && env -u CONVEYOR_FOREMAN_DIR -u CONVEYOR_MAIN bash "$SRC/foreman.sh" claim s6) || fail "the claim in beta failed: $out"
[ "$(cut -d' ' -f1 "$FD/session")" = s6 ] || fail "a claim in another checkout of the group did not move the group's mark: $(cat "$FD/session")"
[ ! -e "$T/beta/conveyor/state/foreman/session" ] || fail "a claim in beta kept a mark of its own outside the group's folder"
out=$(sess s5 | CONVEYOR_FOREMAN_WATCHERS="echo \$\$ > $T/w5" bash "$SRC/waiter.sh" 2>&1); rc=$?
[ "$rc" = 0 ] && [ ! -e "$T/w5" ] || fail "a Foreman in another checkout still started its watchers (exit $rc): $out"
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
jq -c '.pushedCards = [{issue: 40}]' "$T/ask/alpha" > "$T/a" && mv "$T/a" "$T/ask/alpha"
(cd "$M" && env -u CONVEYOR_MAIN -u CONVEYOR_FOREMAN_DIR CONVEYOR_FOREMAN_ASK="cat $T/ask/\$CONVEYOR_REPO" bash "$SRC/watch-conveyor.sh" --once) || fail "no wake for an awaited issue landing without the launcher"
grep -qF 'alpha: #40 landed' "$FD"/pending/*.wake || fail "the awaited issue's landing was not named: $(cat "$FD"/pending/*.wake)"
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
out=$(sess s1 resume | bash "$SRC/foreman.sh" start)
[ "$(grep -c 'old engine' <<<"$out")" = 1 ] && grep -qxF "# WARNING: Conveyor runs an old engine here: commit ${PIN2:0:7}, and the plugin's main is at ${PIN:0:7} · last take that worked: 2026-11-16T05:10:00Z · last failure: conveyor: the plugin's main could not be read from its remote · to take it, run: cd $M && bash $(cd "$SRC/.." && pwd -P)/conveyor.sh take" <<<"$out" \
  || fail "the Foreman's start does not give one line naming the old engine and why: $out"
# Once the newest commit read is the one it runs, the line goes.
jq -n --arg c "$PIN2" '{commit: $c, taken: [$c], head: {commit: $c, name: "main"}}' > "$M/.git/conveyor-engine.json"
out=$(sess s1 resume | bash "$SRC/foreman.sh" start); [[ $out != *'old engine'* ]] || fail "the Foreman's start names an old engine on the newest commit: $out"
}

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
at() { local d=$1; shift; (cd "$d" && "$@"); }
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
grep -qx 'beta control adopt 60' "$T/calls" && grep -qx 'beta control start queue' "$T/calls" || fail "the issue filed in beta was not held, or beta's gate not set back: $(cat "$T/calls")"
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
export CONVEYOR_FOREMAN_ASK="echo \"\$CONVEYOR_REPO \$CONVEYOR_MAIN \$CONVEYOR_CMD\" >> $T/asked; case \$CONVEYOR_CMD in health) jq -c .health $T/snap ;; cards) echo '$CARDS' ;; snapshot) cat $T/snap ;; esac"
snap '[]' '[7]' > "$T/snap"
out=$(cd "$L" && bash "$SRC/foreman.sh" live) || fail "the live summary failed: $out"
grep -qxF "gamma $O health" "$T/asked" && grep -qF 'Conveyor gamma (' <<<"$out" && grep -qF 'gamma blocked: #7' <<<"$out" \
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

t_auto() {
CASE=auto
# A new session opened in the main checkout takes the role by itself: no mark, or the marked session gone, it claims
# it; a live one holding it, it claims nothing and asks the owner by the picker. Bug: only /conveyor-belt:foreman or
# the words claimed it, so for hours no Foreman watched the belts. Never in a worktree (a card's, a lane's) or a
# session the engine starts for a card or a lane: one would take the role from the owner's Foreman.
export CONVEYOR_FOREMAN_ASK='exit 3'
# (A card's own run of this test has CONVEYOR_CARD set: the owner's sessions have none.)
unset CONVEYOR_MAIN CONVEYOR_FOREMAN_DIR CONVEYOR_FOREMAN CLAUDE_CONFIG_DIR CONVEYOR_CARD CONVEYOR_LANE
hook=$(jq -r '.hooks.SessionStart[].hooks[].command | select(contains("foreman.sh start"))' "$PLUGIN/hooks/hooks.json")
[ -n "$hook" ] || fail "hooks.json runs no Foreman start at SessionStart"
open() { # <folder> <session> [<source>]: the hook as Claude Code runs it at the start of a session in that folder
  sess "$2" "${3:-startup}" | (cd "$1" && CLAUDE_PROJECT_DIR=$1 bash -c "$hook")
}
mark() { cut -d' ' -f1 "$FD/session" 2>/dev/null; }
at() { local d=$1; shift; (cd "$d" && "$@"); }
# held <session id> <pid> [<transcript age>]: Claude Code's own record of a session, and its transcript written then.
held() {
  mkdir -p "$HOME/.claude/sessions" "$HOME/.claude/projects/p"
  jq -cn --argjson p "$2" --arg s "$1" '{pid: $p, sessionId: $s, startedAt: 1794650400000, kind: "interactive"}' > "$HOME/.claude/sessions/$2.json"
  touch -d "${3:-now}" "$HOME/.claude/projects/p/$1.jsonl"
}
git -C "$M" add .conveyor && git -C "$M" -c user.name=t -c user.email="t${AT:-@}example.com" commit -qm pack
git -C "$M" worktree add -q "$T/card" && git -C "$M" worktree add -q "$T/alpha-fast"
for d in "$T/card" "$T/alpha-fast"; do
  out=$(open "$d" w1); [ -z "$out" ] && [ -z "$(mark)" ] || fail "a new session in the worktree $d claimed or asked: $out"
done
out=$(CONVEYOR_CARD=c1 open "$M" w1); [ -z "$out" ] && [ -z "$(mark)" ] || fail "a session started for a card claimed or asked: $out"
out=$(CONVEYOR_LANE=research open "$M" w1); [ -z "$out" ] && [ -z "$(mark)" ] || fail "a lane's session claimed or asked: $out"
out=$(open "$M" w1 resume); [ -z "$out" ] && [ -z "$(mark)" ] || fail "a resumed session, not a new one, claimed or asked: $out"
# No mark: the new session claims the role and says so in one line, shown to the owner.
out=$(open "$M" a1)
[ "$(mark)" = a1 ] || fail "a new session in the main checkout with no Foreman did not claim the role: $out"
# A host file with no foreman.name: the line names no Foreman in brackets; it read "the Foreman (Foreman)" on a fresh install.
jq -e '(.systemMessage | startswith("This session is now the Foreman: ")) and (.systemMessage | contains("(Foreman)") | not) and (.hookSpecificOutput.additionalContext | contains("Foreman mode: you are Foreman"))' <<<"$out" >/dev/null \
  || fail "the claim at start did not say so in one line and give the Foreman's start: $out"
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
out=$(cd "$M" && CLAUDE_PROJECT_DIR=$M bash -c "$cmd") && [ "$(mark)" = a4 ] && grep -qxF a3a3a3a3-0000 "$FD/former" \
  || fail "\"Take over\" did not move the role: $(mark) $out"
[ "$(head -n 1 <<<"$out")" = "This session is now the Foreman: its watchers start at the end of this turn." ] || fail "\"Take over\" did not say so in one line: $out"
# "Leave it": a session is asked only at its start, so a later start in it (resumed) asks nothing.
at "$M" bash "$SRC/foreman.sh" claim a3a3a3a3-0000 > /dev/null
out=$(open "$M" a5); grep -qF 'Take over' <<<"$out" || fail "a second new session was not asked: $out"
out=$(open "$M" a5 resume); [ -z "$out" ] && [ "$(mark)" = a3a3a3a3-0000 ] || fail "a session left normal was asked again: $out"
kill "$lp"
}

t_privacy() {
CASE=privacy
bash "$SRC/../privacy/check.sh" --terms "$TERMS" "$SRC"/* "$SRC/../../commands/"*.md || fail "a Foreman file names something private"
}

# Every case at once, each in a subshell on its own fixture; each one's output is shown once all have ended, and the
# test passes only when each case ran to its end.
cases=(setup wake pushwake needs alerts state_stop reply_stop filing ask_pin ask_self session stale reopen projects projects_filing projects_groups remote words auto privacy)
# (A case's own variables, as its loops' c, are its own: the case's name is in one none of them uses.)
for one_case in "${cases[@]}"; do
  (CASE=${one_case//_/-}; fixture "$one_case"; "t_$one_case"; : > "$B/$one_case.passed") > "$B/$one_case.out" 2>&1 &
done
wait
bad=0
for one_case in "${cases[@]}"; do
  cat "$B/$one_case.out" >&2
  [ -e "$B/$one_case.passed" ] || { bad=1; [ -s "$B/$one_case.out" ] || echo "FAIL [${one_case//_/-}]: ended with no word" >&2; }
done
[ "$bad" = 0 ] || exit 1
echo ok
