#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 120
# Foreman mode (foreman.sh, watch-conveyor.sh, watch-alerts.sh, waiter.sh): set up on a fresh host with two records,
# the launcher starting a session that gets the live summary, and every wake naming every item. The other Foreman
# cases are in foreman-session.test.sh and foreman-projects.test.sh.
set -uo pipefail
SRC=$(cd "$(dirname "$0")" && pwd -P)
. "$SRC/../tests/wait.sh"
. "$SRC/../lib/portable.sh"; p_tools
# Each case (t_<case>) runs side by side with the others, on a host of its own made by fixture in $B/<case> (T); a
# case that goes on from what another left (the Foreman set up, a name, a mark) makes that itself first.
B=$(mktemp -d)
# A waiter that delivers a wake leaves a waiter listening (waiter.sh handoff), which ends with the session's process:
# here a stand-in, ended with the test, and no child of it, so the wait for the cases below does not wait for it.
# unheld ends that waiter at once, where its stand-in watcher would go on putting wakes.
export CONVEYOR_FOREMAN_SESSION_PID; CONVEYOR_FOREMAN_SESSION_PID=$(sleep 600 > /dev/null 2>&1 & echo $!) # sleep: the stand-in for the session's process
trap 'kill $CONVEYOR_FOREMAN_SESSION_PID; rm -rf "$B"' EXIT
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
# and wakes) is in alpha's state folder; the case projects (foreman-projects.test.sh) has a Foreman per project.
M=$T/alpha ST=$T/state FD=$T/state/foreman
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
# standin: a stand-in for claude on PATH ($T/bin) that runs the plugin's SessionStart hook, as a session would.
standin() {
mkdir -p "$T/bin"
# stub: a claude that runs only the plugin's SessionStart hook and prints its text, which no real claude run can show cheaply
cat > "$T/bin/claude" <<'EOF'
#!/usr/bin/env bash
# A stand-in for claude: runs the plugin's SessionStart hook, as a session would.
echo "cwd=$PWD foreman=${CONVEYOR_FOREMAN:-} ttl=${CLAUDE_CODE_PROMPT_CACHE_TTL:-}"
echo "args=$*"
echo "launch=${CONVEYOR_FOREMAN_LAUNCH:-}"
src=startup; case " $* " in *' --resume '* | *' --continue '*) src=resume ;; esac
jq -cn --arg s "${STANDIN_SID:-}" --arg src "$src" 'if $s == "" then {} else {session_id: $s, source: $src} end' | CLAUDE_PROJECT_DIR=$PWD bash -c "$(jq -r '.hooks.SessionStart[0].hooks[0].command' "$PLUGIN/hooks/hooks.json")" | jq -r '.hookSpecificOutput.additionalContext // empty'
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
# filing and filed go through filing-hook.sh, which runs the shim only for a command that files an issue (issue 610).
for h in 'SessionStart foreman.sh start --rules-apart' 'SessionStart foreman.sh rules || true' 'Stop stop.sh state' 'Stop stop.sh reply' 'Stop waiter.sh' 'PreToolUse filing-hook.sh filing' 'PostToolUse filing-hook.sh filed' 'PostToolUseFailure filing-hook.sh filed' \
  'UserPromptSubmit waiter.sh --check' 'PostToolUse waiter.sh --check'; do # issue 215: a dead waiter is started again by the session's next prompt or tool call
  s="shim.sh conveyor/foreman/${h#* }"; [[ ${h#* } != filing-hook.sh* ]] || s="}\"/conveyor/foreman/${h#* }"
  jq -e --arg e "${h%% *}" --arg h "$s" '[.hooks[$e][]? | select(($e | test("ToolUse") | not) or .matcher == "Bash" or .matcher == null) | .hooks[].command | endswith($h)] | any' "$P" >/dev/null \
    || fail "no plugin hook runs $h"
done
jq -e '[.hooks.Stop[].hooks[] | select(.command | endswith("waiter.sh")) | .asyncRewake] == [true]' "$P" >/dev/null || fail "the waiter does not wake the session"
# Issue 1172: a session started or resumed with no one typing runs no turn, so only SessionStart can start its waiter.
# Its mode is in CONVEYOR_WAITER_START, with no argument, as an older engine the shim selects refuses --start with a
# usage error on stderr, which asyncRewake sends to the session as a wake.
jq -e '[.hooks.SessionStart[] | select(.matcher == null) | .hooks[] | select(.command | test("CONVEYOR_WAITER_START=1 .*shim\\.sh conveyor/foreman/waiter\\.sh$")) | .asyncRewake] == [true]' "$P" >/dev/null \
  || fail "no SessionStart hook of every source starts the waiter that can wake the session: $(jq -c '.hooks.SessionStart' "$P")"
jq -e 'has("hooks") | not' "$S" >/dev/null || fail "the launcher's settings repeat the plugin's hooks: $(cat "$S")"
grep -q '2 record' "$T/setup.out" || fail "setup does not say it watches both records: $(cat "$T/setup.out")"
echo '- my note' >> "$FD/state.md"; cp "$S" "$T/first.json"
CONVEYOR_MAIN=$M bash "$SRC/foreman.sh" setup > /dev/null 2>&1 || fail "a second setup failed"
cmp -s "$S" "$T/first.json" || fail "a second setup wrote other settings"
grep -qx -- '- my note' "$FD/state.md" || fail "a second setup lost the saved state"

CASE=launch
standin
export CONVEYOR_FOREMAN_ASK='case $CONVEYOR_CMD in snapshot) jq -cn --argjson w "[$([ "$CONVEYOR_REPO" = alpha ] && echo 12 || echo 19)]" "{snapshotAt: \"2026-11-11T12:00:00Z\", belt: [{card: \"c3\", issue: 3, step: \"build\"}], health: {time: \"2026-11-11T12:00:00Z\", loop: true, state: \"running\", reason: null, blocked: [], waiting: [\$w[] | {issue: ., since: \"x\"}], before: [{issue: 21, title: \"a new page\", since: \"y\"}], pushError: null}}" ;; esac'
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
# Bug (#791): the Foreman started a release's suite with no mode, so it ran one by one whatever the owner wanted. Its
# rules tell it to ask the owner by the picker for the mode before release-run prep or release-run, and to pass it.
grep -qF '# A release'"'"'s suite: before you run conveyor.sh release-run prep <version> or release-run <version>, ask the owner by the picker "Run the test files one by one or in parallel?"' <<<"$out" \
  && grep -qF 'pass the answer last in the command: --serial for one by one, --parallel for in parallel.' <<<"$out" \
  || fail "the Foreman's start context does not tell it to ask the owner for the suite's mode and pass it: $out"
# Bug (#1174): the parallel option did not say how many files run at once, so the owner chose it blind; then it named
# the number of this machine's own record, wrong for a release on the build host or of another project. It names the
# number release-run atonce prints where the release's project runs (t_relatonce checks that command). The rules are
# text the Foreman's model reads, so their text is the behaviour here.
grep -qF '"In parallel (<n> at once)" (faster' <<<"$out" \
  && grep -qF "<n> is the number $XDG_DATA_HOME/conveyor/foreman.sh ask <project> release-run atonce prints for the release's project" <<<"$out" \
  || fail "the Foreman's release question does not name, in its parallel option, the number release-run atonce prints for the release's project: $out"
# Bug (#1271): the release question did not offer the rule's machine, so a suite set for a Devbox could not be run here
# for one release, or the owner did not know where it ran. The rules are text the Foreman's model reads, so their text is
# the behaviour here.
grep -qF 'Ask a second question in the same picker call, "Run the suite on which machine?"' <<<"$out" \
  && grep -qF 'first the rule'"'"'s machine by that name (marked Recommended, as the rule'"'"'s choice), then "This machine (the belt is slower meanwhile)"' <<<"$out" \
  && grep -qF 'When the owner answers This machine, add --machine local as the very last words of the command' <<<"$out" \
  || fail "the Foreman's release question does not ask which machine the suite runs on, with the rule's machine first and --machine local for This machine: $out"
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
# Bug (issue 1218): a session read the start text as "end the line with - DONE", and items so marked were never archived.
printf '# state\n- DONE shipped the thing\n  with its detail\n- shipped the other thing - DONE\n  with its own detail\n- open item\n' > "$FD/state.md"
out=$(cd "$M" && PATH=$T/bin:$PATH bash "$SRC/../conveyor.sh" foreman 2>&1)
grep -q 'DONE' "$FD/state.md" && fail "a DONE item stayed in the state: $(cat "$FD/state.md")"
grep -qx -- '- open item' "$FD/state.md" || fail "an open item left the state"
cat "$FD"/state-archive-*.md 2>/dev/null | grep -qx '  with its detail' || fail "the DONE item and its detail were not archived"
cat "$FD"/state-archive-*.md 2>/dev/null | grep -qx '  with its own detail' || fail "an item ending ' - DONE' and its detail were not archived: $(cat "$FD/state.md")"
grep -qF 'with its own detail' "$FD/state.md" && fail "the detail of an item ending ' - DONE' stayed in the state: $(cat "$FD/state.md")"
grep -qF 'begin the line of a finished item with "- DONE"' <<<"$out" || fail "the start text does not say the line must begin with - DONE: $out"
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
}

# The cases wake, wake_relay and wake_engine run side by side, each on its own Foreman, so the file takes about the
# slowest of them.
t_wake_relay() {
CASE=wake-relay
ready
# The items of the case wake already reported, so a later poll names only the new ones.
mkdir -p "$T/ask"; snap '[12,15]' '[7]' > "$T/ask/alpha"; snap '[19]' '[]' > "$T/ask/beta"
bash "$SRC/watch-conveyor.sh" --once || fail "no wake for four new items"
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
}

t_wake_engine() {
CASE=wake-engine
ready
# Nothing waits or is blocked; the watcher's clock is the case's, as in the case wake.
mkdir -p "$T/ask"; snap '[]' '[]' > "$T/ask/alpha"; snap '[]' '[]' > "$T/ask/beta"
CONVEYOR_FOREMAN_NOW=$(date +%s)
export CONVEYOR_FOREMAN_NOW
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
# #1079 ask 2. Bug it catches: a push that went on over a pre-push hook that failed naming a test file that passed
# alone (health pushFlaky) said nothing, or that the check "will not pass on a retry". It wakes once, "flaky: passed
# alone", naming the file and the held issue.
rm -f "$FD"/pending/*.wake
snap '[]' '[]' | jq -c '.health.pushFlaky = {time: "2026-11-11T11:58:00Z", card: "c12", issue: 12, files: ["lib/a.test.sh"], issues: [101]}' > "$T/ask/alpha"
bash "$SRC/watch-conveyor.sh" --once || fail "a push over a flaky hook did not wake"
[ "$(cat "$FD"/pending/*.wake)" = $'Conveyor: alpha: push flaky: #101\nalpha: push went on: the pre-push hook failed naming lib/a.test.sh, flaky: passed alone; held for the owner: #101' ] \
  || fail "the push over a flaky hook woke as: $(cat "$FD"/pending/*.wake)"
rm -f "$FD"/pending/*.wake
bash "$SRC/watch-conveyor.sh" --once && fail "a flaky push already reported woke again: $(cat "$FD"/pending/*.wake)"
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
# The other kinds the Board shows: a dependency that cannot be read, an engine update not taken, test issues held,
# models with no price (#1074: no issue is filed for them now, so this wake is what tells the owner) and the whole
# test failing on main.
rm -f "$FD"/pending/*.wake
jq -c '.needsYou += {farDeps: [{issue: 41, title: "t", ref: "example/other#3", reason: "not found", line: "Depends on: example/other#3"}],
    engine: {commit: "abc123", reason: "it failed its check", since: "2026-11-11T11:00:00Z"}, testRules: {time: "2026-11-11T11:00:00Z", matched: 90, cap: 20},
    prices: {models: ["claude-new-9", "m"]}}
  | .mainTest = {issue: 42, cases: ["serve", "views"], from: "a1", to: "b2", since: "2026-11-11T11:00:00Z"}' "$T/ask/alpha" > "$T/a" && mv "$T/a" "$T/ask/alpha"
bash "$SRC/watch-conveyor.sh" --once || fail "no wake for the other Needs you kinds"
w=$(cat "$FD"/pending/*.wake)
for l in "alpha: #41 waits on example/other#3 in another repository, which cannot be read: not found" \
  "alpha: the plugin commit abc123 was not taken: it failed its check" "alpha: the test rules matched 90 files, over the cap of 20 a day, so they filed none" \
  "alpha: the whole test fails on main (#42): serve, views" \
  "alpha: 2 models the belt runs or offers have no price: claude-new-9, m; add them on the Board, Rules, Model prices"; do
  grep -qxF "$l" <<<"$w" || fail "no line '$l': $w"
done
[ "$(wc -l <<<"$w")" = 6 ] || fail "an entry already reported woke again: $w"
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
# The cache-write alert names the card step of each session by the Board's Metrics steps. Bug caught: a watcher that
# passed the rules the limit alone, so the wake named no card step.
printf 'window.DASH = %s;\n' "$(jq -cn '((now | floor) - 60) as $t | {panels: {health: {data: {limit: {usedPct: 20, goalPct: 50, cacheWritePct24h: 8,
    cacheWrites24h: {write: 3000, write1h: 1000, cards: [{card: "c7", model: "claude-opus-5-5", first: ($t - 300), last: ($t - 10), write: 3000, write1h: 1000}]}}}},
  metrics: {data: {steps: [{repo: "alpha", card: "c7", issue: 7, steps: [{step: "build", time: ($t | todate)}]}]}}}}')" > "$T/data.js"
bash "$SRC/watch-alerts.sh" --once || fail "the cache-write alert did not wake"
grep -qF 'alpha#7 build claude-opus-5-5 3000+1000' "$FD"/pending/*.wake || fail "the cache-write wake names no card step: $(cat "$FD"/pending/*.wake)"
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

# Every case at once, each in a subshell on its own fixture; each one's output is shown once all have ended, and the
# test passes only when each case ran to its end.
cases=(setup wake wake_relay wake_engine pushwake needs alerts)
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
  [ -e "$B/$one_case.passed" ] || { bad=1; [ -s "$B/$one_case.out" ] || echo "FAIL [${one_case//_/-}]: ended with no word" >&2; }
done
[ "$bad" = 0 ] || exit 1
echo ok
