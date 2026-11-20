#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 300
# The collector of the Conveyor dashboard (dashboard.sh). The page is what the owner reads instead of asking, so the
# data must never lie: every panel's part is cut from the same answers, a source that was not read is null with its
# reason (never a 0 or an empty list that reads as measured), a host that did not answer is said to be unreachable,
# and a sum with an unpriced step in it is unknown, never the sum of the priced part.
# This file has the data contract and the host's one-off reads (contract, history, historyserver, work, older,
# donewhen, shot, excerpts, bench); dashboard-cards.test.sh and dashboard-local.test.sh have the others.
set -euo pipefail
# CONVEYOR_SHELL_TEST_CASE=<part>[,<part>] runs only those parts (each part's `) & started <part>` line below), as the
# coverage map selects them (.conveyor/test-changed.sh, issue 527); an unknown name exits 2. Unset, every part runs.
PARTSEL=${CONVEYOR_SHELL_TEST_CASE:-}; PARTSEL=${PARTSEL//,/ }; unset CONVEYOR_SHELL_TEST_CASE
for p in $PARTSEL; do grep -qxF ") & started $p" "$0" || { echo "unknown part $p" >&2; exit 2; }; done
# This file's own touch -d and stat -c are GNU calls: on macOS they run Homebrew's, as Conveyor's do (portable.sh).
. "$(dirname "$0")/../../../conveyor/lib/portable.sh"; p_tools
. "$(dirname "$0")/../../../conveyor/tests/wait.sh"

SOURCE=$(git rev-parse --show-toplevel)
DASH=$SOURCE/.claude/scripts/dashboard.sh
DECIDE=$SOURCE/.claude/scripts/decision.sh
VIEW=$SOURCE/.claude/dashboard
TOP=$(cd "$(mktemp -d /tmp/dashboard-test.XXXXXX)" && pwd -P) # physical spelling: on the Mac /tmp is /private/tmp
trap 'chmod -R u+w "$TOP" 2>/dev/null; rm -rf "$TOP"' EXIT
# The host file is XDG_CONFIG_HOME's when it is set, ahead of the test's HOME: an inherited one is the owner's real host.
unset XDG_CONFIG_HOME
fail() { echo "FAIL: $*" >&2; exit 1; }
# The page server runs on the Board's own virtualenv (conveyor.sh setup fills it). Every run below has the test's
# HOME, so XDG_DATA_HOME names where the real one is, for dashboard.sh and for this file's own calls.
export XDG_DATA_HOME=${XDG_DATA_HOME:-$HOME/.local/share}
PY=$XDG_DATA_HOME/conveyor/board-venv/bin/python3
"$PY" -c 'import pyotp, segno, cryptography' || fail "the Board's virtualenv $PY lacks its packages: run conveyor.sh setup"
REALPY=$(command -v python3) # the python3 a collect runs, for the stub setup writes

# The parts below run side by side ( fresh <part>; ... ) &, so the file takes its slowest part's time, not their sum.
# fresh <part> -- the part's own folder ($T, under $TOP), checkout, host file, stubs and dashboard folder, set up as
# every part begins. A part PARTSEL leaves out ends here, passed.
fresh() {
[ -z "$PARTSEL" ] || [[ " $PARTSEL " == *" $1 "* ]] || exit 0
setup "$1"
}
# A long part runs its stretches that need no state of one another side by side too: each `( setup <part>-<n>; ... ) &
# PIECES+=($!)` has a folder of its own, set up as fresh's, and the part ends with `pieces`, failed when one failed.
PIECES=()
pieces() {
  local p bad=0
  for p in "${PIECES[@]}"; do wait "$p" || bad=1; done
  [ "$bad" -eq 0 ] || fail "a piece of this part failed (its FAIL line is above)"
}
# setup <folder> -- the folder $TOP/<folder> and all in it, as above.
setup() {
T=$TOP/$1; mkdir -p "$T"
# The limit read also walks the review sessions' Codex folder; without this a collect reads the owner's real spend.
export CONVEYOR_CODEX_REVIEW_HOME=$T/codex-review
MAIN=$T/main WS=$T/ws SCR=$T/scratch OUT=$T/out BIN=$T/bin
mkdir -p "$MAIN/.claude/metrics" "$MAIN/conveyor" "$WS" "$SCR" "$BIN" "$T/userhome"
git -C "$MAIN" init -q -b main
g() { git -C "$MAIN" -c user.email=t@t -c user.name=t "$@"; }
g commit -q --allow-empty -m "feat: base commit"
# Each project's decision ledger is where the host file's record names it on this machine; sample's has no decision
# yet. The Board's own checkout holds a ledger too, whose decision must never reach the page. widgetshop's path holds a
# backslash: the Board opens the path the host file names, character for character (it once doubled it).
PPL=$T/ledgers/sample/decisions.jsonl WSL=$T/ledgers/widget\\shop/decisions.jsonl
mkdir -p "${PPL%/*}" "${WSL%/*}"; : > "$PPL"
stub() { printf '#!/usr/bin/env bash\n%s\n' "$2" > "$BIN/$1"; chmod +x "$BIN/$1"; }
# The usage limit and accounts read (dashboard_limit.py, three Python starts a collect, some 40% of its CPU) fails
# at once here, so the limit part is "could not be built" and every other python3 call runs the real one. A part that
# checks the limit, the accounts or the session cost calls limit_read first, and its collects read them for real.
stub python3 'case "${1-}" in */dashboard_limit.py) exit 1 ;; esac; exec '"$(printf %q "$REALPY")"' "$@"'
limit_read() { rm -f "$BIN/python3"; }

# Conveyor's host: two records on one machine, reached over ssh. The ssh stub records its arguments and answers
# with $T/ssh-out, $T/ssh-err and the exit code in $T/ssh-rc, so no test opens a connection. The host's accounts
# read is answered with $T/ssh-accounts (nothing when there is none).
# The first record names its two lanes' folders on this machine, neither in the worktrees folder ($WS) nor named as
# that folder's lanes were (the research lane's under the home folder, written ~/); the second names no lane.
FL=$T/lanes/main-fast-lane RSL=$T/userhome/lanes/main-research
jq -cn --arg l "$PPL" --arg f "$FL" '{host: "devbox", ssh: "user@devbox", main: "/srv/main",
  records: [{repo: "sample", main: "/srv/main", ledger: $l, lanes: {fast: {worktree: $f}, research: {worktree: "~/lanes/main-research"}}},
    {repo: "widgetshop", main: "/srv/cd"}]}' > "$MAIN/conveyor/host.json"
stub ssh 'case "$*" in *"dashboard_limit.py accounts"*) printf "%s\n" "$*" >> "'"$T"'/ssh-accounts-calls"; cat "'"$T"'/ssh-accounts" 2>/dev/null; exit 0 ;; esac
printf "%s\n" "$*" >> "'"$T"'/ssh-calls"
cat "'"$T"'/ssh-out" 2>/dev/null
[ ! -s "'"$T"'/ssh-err" ] || cat "'"$T"'/ssh-err" >&2
exit "$(cat "'"$T"'/ssh-rc" 2>/dev/null || echo 0)"'

ago() { date -u -d "-$1 seconds" +%Y-%m-%dT%H:%M:%SZ; }
NOWISO=$(ago 0)
# The snapshots' day, taken once like NOWISO. Bug caught (issue 363): each snapshot and the check of the day it gave
# read the clock on their own, so a run that went past midnight failed "nothing landed is an empty list for today".
DAY=$(date +%F)
# snap [<overrides>] -- one record's snapshot as conveyor.sh prints it: empty and healthy unless overridden.
snap() {
  local o=${1:-}; [ -n "$o" ] || o='{}'
  jq -cn --arg day "$DAY" --arg now "$NOWISO" --argjson o "$o" '
    {time: $now, day: $day, needsYou: {waiting: [], blocked: [], before: []}, belt: [], queue: {next: []}, landed: [], landedCount: 0,
     health: {time: $now, loop: true, newest: $now, blocked: [], waiting: [], stuck: [], unpushed: [], pushError: null, pushFailingSince: null,
              gh: true, ghReached: false, diskFreeKb: 500000000, builderCap: 3, models: {claude: "claude-x", codex: "gpt-x"}},
     cost: {today: 0, week: 0, perLanded: null, landedAfter: {"1": 0, "2": 0, "3": 0, more: 0}, unpricedSteps: 0, cards: []}} * $o'
}
# answer <snapshot 1> <origin 1> <pushed epoch 1> <snapshot 2> <origin 2> <pushed epoch 2> -- what the
# host prints for the collector's one command: three lines a record, then the end marker.
answer() {
  printf '%s\n%s\n%s\n%s\n%s\n%s\n@@end\n' "$1" "$2" "$3" "$4" "$5" "$6" > "$T/ssh-out"
  echo 0 > "$T/ssh-rc"; : > "$T/ssh-err"
}
# An ssh remote, its host apart: written out, git@<host> is an email hit of conveyor/privacy/check.sh.
GH=github.com
P_URL=git@$GH:example/sample-project.git C_URL=https://github.com/example/WidgetShop
quiet() { answer "$(snap)" "$P_URL" 1794000000 "$(snap)" "$C_URL" 0; }

# A collect in the same second as the last one would be answered from that cycle's own request cache: a cache is
# reused only by a collect stamped with its `cycle`. So wait out that second, and only when a cache has one: waiting out
# every collect's end second cost some 25 s a run, most of it before the test has written any transcript.
new_cycle() {
  local c; c=$({ cat "$OUT"/cache/*-requests.json 2>/dev/null || :; } | jq -s 'map(.cycle? | numbers) | max // empty | floor')
  while [ -n "$c" ] && [ "$(date +%s)" = "$c" ]; do sleep 0.1; done
}
# One collect, bounded: a hang fails here, naming the line, instead of running into the file's budget.
run() {
  local rc=0
  new_cycle
  env -u CONVEYOR_HOOK_FIRE_LOG -u CODEX_HOME HOME="$T/userhome" PATH="$BIN:$PATH" CONVEYOR_HOST_OS=Linux CONVEYOR_MAIN="$MAIN" \
    CONVEYOR_WORKSPACES="$WS" CONVEYOR_SCRATCH="$SCR" CONVEYOR_DASHBOARD_DIR="$OUT" \
    "$@" timeout 120 bash "$DASH" || rc=$?
  [ "$rc" -ne 124 ] || fail "HUNG: a collect ran past 120 s (line ${BASH_LINENO[0]})"
  [ "$rc" -eq 0 ] || fail "dashboard.sh exited $rc (line ${BASH_LINENO[0]})"
}
D=$OUT/data.js
}
json() { sed -e '1s/^window\.DASH = //' -e '$s/;$//' "$D"; }
q() { json | jq -e "$1" >/dev/null || fail "$2 (jq: $1; data: $(json | jq -c '.panels' | cut -c1-1500))"; }
PARTS=()
started() { PARTS+=("$1:$!"); } # <part>, after its ( ... ) &

( fresh contract; limit_read
# --- the data contract: one part per panel of the page, under the panel's id ---
quiet
run
head -c 14 "$D" | grep -qF 'window.DASH = ' || fail "data.js must assign window.DASH"
q '(.updatedAt | fromdateiso8601) > 0' "the snapshot carries when it was collected"
PAGE_PANELS=$(node -e 'const window = {}; eval(require("fs").readFileSync(process.argv[1], "utf8")); console.log(JSON.stringify(window.DASH_PANELS.slice().sort()))' "$VIEW/panels/index.js")
[ "$(json | jq -c '.panels | keys')" = "$PAGE_PANELS" ] || fail "the collector writes one part for each panel on the page's list and no other: $(json | jq -c '.panels | keys') against $PAGE_PANELS"
q '.panels | all(.[]; has("error") and has("data"))' "every part is {error, data}"
[ -z "$(find "$OUT" -maxdepth 1 \( -name '.run.*' -o -name '.data.js.*' \) | head -n 1)" ] || fail "a collect leaves no temporary file beside data.js: $(ls -A "$OUT")"

# --- a host with nothing on it: every list is a measured empty list, never null ---
q '.panels.belt == {error: null, data: {cards: [], cap: 6, waiting: 0, building: null, behind: [], byRepo: {sample: {cap: 3, waiting: 0, building: null}, widgetshop: {cap: 3, waiting: 0, building: null}}}}' "an empty belt is an empty list, with the builder slots of both records and each record's own"
# Its deck's slots are the head's "On the belt" figure, the Belt part's cards of its cap (issue 413: the deck read the
# host's test-slot pool, "2/16 FREE" with 5 cards running, beside the tile's "5 of 13").
q '.panels.belt3d == {error: null, data: {repos: ["sample", "widgetshop"], byRepo: {}, belt: [], queue: {next: [], held: [], waiting: []}, needs: [], landed: [],
  deck: {host: "devbox", state: "running", used: 0, cap: 6}}}' \
  "Belt 3D on an empty host: measured empty lists (a snapshot with no held or waiting issues has none of them), and no slot in use of both records' 6"
q '.panels.needs.data.cards == {waiting: [], blocked: [], before: [], pipeline: [], farDeps: []} and .panels.needs.data.cardsError == null' "no blocked card is a measured empty list"
q '.panels.queue.data == {next: [], held: null, awaitingDeploy: [], waiting: [], issuesError: null, byRepo: {sample: {held: null}, widgetshop: {held: null}}}' \
  "an empty queue is an empty list, and so is what waits for a PROD deploy or on another issue; a snapshot that lists no open issues has no held count, never 0"
q '.panels.machine.data | .host == "devbox" and .state == "running" and .cap == 6 and .used == 0 and .todayUsd == 0 and .repos == ["sample", "widgetshop"]
  and (.projects | map([.repo, .cap, .used, .needs, .belt, .landedToday])) == [["sample", 3, 0, [], [], 0], ["widgetshop", 3, 0, [], [], 0]]' \
  "a machine with nothing on it: no card holds a slot (a measured 0), with no machine cap the slots in force are both projects' 6, and each project is there on its own"
q '.panels.landed.data.cards == [] and .panels.landed.data.day == "'"$DAY"'"' "nothing landed is an empty list for today"
q '.panels.cost.data.cards | .todayUsd == 0 and .weekUsd == 0 and .perLandedUsd == null and .perCard == [] and .unpricedSteps == 0' "no spend is a measured 0, and no landed card has no average"
q '.panels.declined == {error: null, data: {lines: [], rest: []}}' "no declined finding (a snapshot from before it carried the list, too) is an empty list, not a failed part"
q '.panels.health.data | .host == {name: "devbox", local: false, reachable: true, error: null} and (.records | length) == 2 and (has("cpuCap") | not)' "the host answered: reachable, both records, and no CPU cap (dropped)"
q '.panels.health.data.records | .[0].lastPushAt == (1794000000 | todate) and .[1].lastPushAt == null and all(.[]; .loop == true and .gh == true)' "each record carries its last push; none recorded is null"
# Issue 410. Bug it catches: the collector dropped ghReached, so the Board showed no warning when gh was signed in and
# GitHub was not reached.
q '.panels.health.data.records | all(.[]; .ghReached == false)' "a record's GitHub not reached (ghReached false) reaches the Board"
# Issue 151: Health gives today's cost (the Board's own project's sessions alone) on the row of the record on the
# host's main only; without steered on each record it could not tell that record from the others.
q '[.panels.health.data.records[] | .steered] == [true, false]' "each record says whether it is the one on the host's main"
q '.panels.board.data | .repo == "sample" and .control == null and .modelSettings == null and .held == null and .queue == null and (.issuesError | test("did not list"))
  and ([.building, .review, .waiting, .blocked, .landed] | all(. == []))' "a snapshot from before the control record: the Board says the queue was not listed, and its cards are measured empty lists"
q '.panels.rules.data | .repo == "sample" and .control == null and .queue == null and (.issuesError | test("did not list")) and .building == 0 and .forecast == null' "a snapshot from before the control record: the Rules part has no record, no queue and no forecast"

# --- the one ssh command: every record's snapshot, origin and last push, then the end marker ---
[ "$(wc -l < "$T/ssh-calls")" -eq 1 ] || fail "a collect asks the host once: $(cat "$T/ssh-calls")"
# Each path is quoted, as a checkout's path may hold a space.
for want in 'user@devbox' 'BatchMode=yes' "CONVEYOR_MAIN='/srv/main' bash '/srv/main/conveyor/conveyor.sh' snapshot" "CONVEYOR_MAIN='/srv/cd' bash '/srv/main/conveyor/conveyor.sh' snapshot" \
    "git -C '/srv/cd' remote get-url origin" "stat -c %Y \"\$(CONVEYOR_MAIN='/srv/cd' bash '/srv/main/conveyor/conveyor.sh' state-dir)\"/pushed" 'echo @@end'; do
  grep -qF -- "$want" "$T/ssh-calls" || fail "the host command lacks '$want': $(cat "$T/ssh-calls")"
done
! grep -qE 'cpu-cap|scaling_max_freq' "$T/ssh-calls" || fail "the host command still asks for the CPU cap: $(cat "$T/ssh-calls")"
q '.panels.health.data.stream | .live == false and (.heardAt | fromdateiso8601) > 0 and (.error | test("live feed is not running"))' \
  "with no live feed, the cycle's own read is marked as no live one, with when it was read"

# --- every Claude account: the host's two, each with its own figures and what it is used for (widgetshop's control
# record names the second; sample names none, so it runs on the default login), beside this machine's. Reviews
# are an account's only with a Claude reviewer: sample names the second for reviews but reviews with Codex, and
# widgetshop's Claude reviewer, naming no review account, reviews on its builder's ---
jq -cn '[{name: "default", listedAs: [], folder: "/srv/acct1", email: "noreply-a@example.com", inUse: true, default: true, usedPct: 12, fiveHourPct: 3, resetsAt: null, readAt: null, error: null},
  {name: "second", listedAs: ["second"], folder: "/srv/acct2", email: "noreply-b@example.com", inUse: false, default: false, usedPct: 95, fiveHourPct: 40, resetsAt: null, readAt: null, error: null}]' > "$T/ssh-accounts"
answer "$(snap '{"control":{"account":null,"reviewAccount":"second"},"modelSettings":{"reviewer":{"agent":"codex"}}}')" "$P_URL" 0 \
  "$(snap '{"control":{"account":"second","reviewAccount":null},"modelSettings":{"reviewer":{"agent":"claude"}}}')" "$C_URL" 0
rm -f "$OUT/cache/host-accounts" "$OUT/cache/host-accounts.retry"; : > "$T/ssh-accounts-calls"
run
q '.panels.health.data.accounts | .error == null and ([.list[] | select(.machine == "devbox") | [.name, .usedPct, .fiveHourPct, .email, .usedFor]]
    == [["default", 12, 3, "noreply-a@example.com", ["cards of sample: build and fix"]], ["second", 95, 40, "noreply-b@example.com", ["cards of widgetshop: build and fix", "cards of widgetshop: reviews"]]])' \
  "the panel lists each of the host's accounts with its own figures and the project whose cards use it, reviews only where a Claude reviewer runs on it"
q '.panels.health.data.accounts.list | map(select(.machine == null)) | length > 0 and all(.[]; .usedFor | type == "array")' "this machine's accounts are listed beside the host's"
# Issue 629: Health told to move a 92% account's work on the Rules tab when the host file listed no other account.
# The default login, with no host file name beside its own, has no other account to move to; the second has the default.
q '[.panels.health.data.accounts.list[] | select(.machine == "devbox") | [.cards, .others]] == [[true, false], [true, true]]' \
  "the default login with no other account listed has none to move its work to; a listed account has the default"
# Issue 151. Bug: a role on an API route (no subscription, billed per token) still marked the account its record names
# as used, so Health warned for ever that the account was not read. A record's routes name the roles on the
# subscription now: sample's on none (both on the API), widgetshop's on its reviewer alone (mixed). Only that
# reviewer's account is used; the default login is used by no card, so Health gives it no warning.
answer "$(snap '{"control":{"account":null,"reviewAccount":"second"},"modelSettings":{"reviewer":{"agent":"claude"}},"health":{"routes":{"subscription":{"roles":[]}}}}')" "$P_URL" 0 \
  "$(snap '{"control":{"account":null,"reviewAccount":"second"},"modelSettings":{"reviewer":{"agent":"claude"}},"health":{"routes":{"subscription":{"roles":["reviewer"]}}}}')" "$C_URL" 0
run
q '[.panels.health.data.accounts.list[] | select(.machine == "devbox") | [.usedFor, .cards]]
    == [[["not used by the Conveyor"], false], [["cards of widgetshop: reviews"], true]]' \
  "a role on an API route uses no account: only a subscription role's account is used"
# A card in flight keeps the account it started on: widgetshop's record now names none, but a card of it still
# runs on the second (the snapshot's inFlight), so the second is not shown as unused.
answer "$(snap '{"control":{"account":null,"reviewAccount":null},"modelSettings":{"reviewer":{"agent":"codex"}}}')" "$P_URL" 0 \
  "$(snap '{"control":{"account":null,"reviewAccount":null},"modelSettings":{"reviewer":{"agent":"claude"}},"inFlight":[{"account":"second","reviewAccount":null}],"accounts":["second"]}')" "$C_URL" 0
run
q '[.panels.health.data.accounts.list[] | select(.machine == "devbox") | .usedFor]
    == [["cards of sample: build and fix", "cards of widgetshop: build and fix", "cards of widgetshop: reviews"], ["cards in flight of widgetshop: build and fix", "cards in flight of widgetshop: reviews"]]' \
  "an account a card in flight still uses, after its project's record named another, is listed as used by that card"
q '[.panels.health.data.accounts.list[] | select(.machine == "devbox") | [.cards, .others]] == [[true, true], [true, true]]' \
  "with the second listed in the host file (the snapshot's accounts), the default login has it to move its work to"
# A card that started with a Claude reviewer on the second keeps reviewing on it after the reviewer is changed to
# Codex: its worktree line names a review account only for a Claude reviewer, so the second is not shown as unused.
answer "$(snap '{"control":{"account":null,"reviewAccount":null},"modelSettings":{"reviewer":{"agent":"codex"}}}')" "$P_URL" 0 \
  "$(snap '{"control":{"account":null,"reviewAccount":"second"},"modelSettings":{"reviewer":{"agent":"codex"}},"inFlight":[{"account":null,"reviewAccount":"second"}]}')" "$C_URL" 0
run
q '[.panels.health.data.accounts.list[] | select(.machine == "devbox") | .usedFor]
    == [["cards of sample: build and fix", "cards of widgetshop: build and fix"], ["cards in flight of widgetshop: reviews"]]' \
  "an account a Claude review in flight runs on, after its project's reviewer was changed to Codex, is listed as used by that card"
# A listed account may be named default: the host's own default login, not listed, is shown under that name too, and
# a record naming the listed one does not run on it, so only the listed one is labelled as used by that record.
cp "$T/ssh-accounts" "$T/ssh-accounts.kept"
jq -cn '[{name: "default", listedAs: [], folder: "/srv/acct1", email: "noreply-a@example.com", inUse: true, default: true, usedPct: 12, fiveHourPct: 3, resetsAt: null, readAt: null, error: null},
  {name: "default", listedAs: ["default"], folder: "/srv/second", email: "noreply-b@example.com", inUse: false, default: false, usedPct: 95, fiveHourPct: 40, resetsAt: null, readAt: null, error: null}]' > "$T/ssh-accounts"
answer "$(snap '{"control":{"account":null,"reviewAccount":null},"modelSettings":{"reviewer":{"agent":"codex"}}}')" "$P_URL" 0 \
  "$(snap '{"control":{"account":"default","reviewAccount":null},"modelSettings":{"reviewer":{"agent":"claude"}}}')" "$C_URL" 0
rm -f "$OUT/cache/host-accounts" "$OUT/cache/host-accounts.retry"
run
q '[.panels.health.data.accounts.list[] | select(.machine == "devbox") | [.email, .usedFor]]
    == [["noreply-a@example.com", ["cards of sample: build and fix"]], ["noreply-b@example.com", ["cards of widgetshop: build and fix", "cards of widgetshop: reviews"]]]' \
  "a record naming a listed account called default uses that account, not the host's separate default login"
# The other way round: the listed account called default is the default login itself, and an unlisted folder (the
# one CLAUDE_CONFIG_DIR names) is shown under the same name. The record runs on the listed one, never the unlisted.
jq -cn '[{name: "default", listedAs: [], folder: "/srv/default", email: "noreply-a@example.com", inUse: true, default: false, usedPct: 12, fiveHourPct: 3, resetsAt: null, readAt: null, error: null},
  {name: "default", listedAs: ["default"], folder: "/srv/acct1", email: "noreply-b@example.com", inUse: false, default: true, usedPct: 95, fiveHourPct: 40, resetsAt: null, readAt: null, error: null}]' > "$T/ssh-accounts"
rm -f "$OUT/cache/host-accounts" "$OUT/cache/host-accounts.retry"
run
q '[.panels.health.data.accounts.list[] | select(.machine == "devbox") | [.email, .usedFor]]
    == [["noreply-a@example.com", ["not used by the Conveyor"]], ["noreply-b@example.com", ["cards of sample: build and fix", "cards of widgetshop: build and fix", "cards of widgetshop: reviews"]]]' \
  "a record naming the listed default login uses it, not an unlisted folder shown under the same name"
q '.panels.health.data.accounts.list | ([.[] | select(.machine == "devbox") | .cards] == [false, true]) and all(.[] | select(.machine == null); .cards == false)' \
  "an account no card runs on, here or on the host, is marked so: Health gives it no next step about its work"
mv "$T/ssh-accounts.kept" "$T/ssh-accounts"
grep -qF "user@devbox python3 '/srv/main'/.claude/scripts/dashboard_limit.py accounts" "$T/ssh-accounts-calls" || fail "the host's accounts are not read over ssh to its target: $(cat "$T/ssh-accounts-calls")"
: > "$T/ssh-accounts-calls"; quiet; run
[ ! -s "$T/ssh-accounts-calls" ] || fail "the host's accounts were read again inside the TTL: $(cat "$T/ssh-accounts-calls")"
# #623: the limit panel shows the account the cards run on, as the build machine's guard read it, never this machine's
# own login. Bug it catches: this machine's ~/.claude.json still named the old account B (92%) after the build machine
# moved to account A (3%), and the panel showed B. Here this machine's login is B; sample's cards run on the build
# machine's default login, A, its builder and its reviewer; widgetshop's builder runs on the second account and its
# Claude reviewer on the third, not read yet. (dashboard-view.health.test.mjs draws the rows.)
printf '{"oauthAccount":{"emailAddress":"noreply-b@example.com"}}' > "$T/userhome/.claude.json"
# This machine's own reading of B, 92%, fresh: the usage file limit() reads for the login in use.
jq -cn --arg d "$T/userhome/.claude" '{seven_day: {utilization: 92, resets_at: null}, five_hour: {utilization: 10, resets_at: null},
  account: {folder: $d, email: "noreply-b@example.com"}}' > "$OUT/cache/claude-usage"
rm -f "$OUT/cache/claude-usage.retry"
answer "$(snap '{"limits":[{"account":null,"uses":["build","review"],"pct":3,"readAt":"'"$NOWISO"'","email":"noreply-a@example.com"}]}')" "$P_URL" 0 \
  "$(snap '{"limits":[{"account":"second","uses":["build"],"pct":40,"readAt":"'"$NOWISO"'","email":"noreply-c@example.com"},{"account":"third","uses":["review"],"pct":null,"readAt":null,"email":null}]}')" "$C_URL" 0
run CLAUDE_CONFIG_DIR="$T/userhome/.claude"
q '.panels.health.data.accounts.list | any(.machine == null and .email == "noreply-b@example.com" and .usedPct == 92)' "this machine's own login names account B, read at 92%"
q '.panels.health.data | .limits == [{repo: "sample", account: null, uses: ["build", "review"], pct: 3, readAt: "'"$NOWISO"'", email: "noreply-a@example.com"},
    {repo: "widgetshop", account: "second", uses: ["build"], pct: 40, readAt: "'"$NOWISO"'", email: "noreply-c@example.com"}, {repo: "widgetshop", account: "third", uses: ["review"], pct: null, readAt: null, email: null}]' \
  "the limit panel has each account the cards run on, with the build machine's reading and login, not this machine's 92% of account B"
q '.panels.board.data.limit == {pct: 3, from: "loop"} and .panels.board.data.others.widgetshop.limit == {pct: 40, from: "loop"}' \
  "a record with no guard reading shows its accounts' highest reading, never this machine's own login's"
rm -f "$T/userhome/.claude.json" "$OUT/cache/claude-usage"; quiet

# --- the live feed: a fresh stream.json is Conveyor's part, and no host is asked; --publish builds data.js
# again from it and the parts the last cycle kept, with no slow read at all ---
feed() { # <live true|false> <belt card> -- stream.json as dashboard_stream.py writes it
  jq -cn --argjson s "$(snap "{\"belt\":[{\"card\":\"$2\",\"issue\":5,\"title\":\"T5\",\"step\":\"build\",\"stepAt\":\"$NOWISO\",\"landed\":false,\"tokens\":{\"claude\":0,\"codex\":0},\"usd\":null,\"reading\":false,\"atEnd\":true,\"reviews\":[],\"track\":null}]}")" \
    --argjson live "$1" --arg at "$NOWISO" '{host: "devbox", reachable: true, error: null,
      records: [{repo: "sample", snap: $s, steered: true, repoUrl: "https://github.com/o/r", lastPushAt: null}],
      stream: {live: $live, heardAt: $at, since: (if $live then null else $at end), error: (if $live then null else "devbox: no line in 30 s" end)}}' > "$OUT/stream.json"
}
feed true c-fed; : > "$T/ssh-calls"
run
[ ! -s "$T/ssh-calls" ] || fail "a cycle with the live feed fresh asked the host: $(cat "$T/ssh-calls")"
q '(.panels.belt.data.cards | map(.card)) == ["c-fed"] and .panels.health.data.stream.live == true' "a cycle takes Conveyor's part from a fresh live feed"
# The Board's building column keeps a card's atEnd (its cost shown when the step ends, #391): a bug dropped it there.
q '.panels.board.data.building | map([.card, .atEnd]) == [["c-fed", true]]' "the Board's building column dropped atEnd"
for k in limit decisions lanes; do [ -s "$OUT/cache/part-$k.json" ] || fail "the cycle did not keep its $k part for --publish"; done
feed false c-later; stub sleep 'exit 0'  # a slow read would show here: --publish runs none
# A kept limit part with a reading, for limit.json below.
jq -cn --arg r "$NOWISO" '{limit: {usedPct: 41.5, resetsAt: $r, goalPct: 50, usd: 12}, error: "the usage read failed (test); showing the last reading"}' > "$OUT/cache/part-limit.json"
# Each jq run of --publish is counted. The feed runs one --publish per change, up to one each 2 s, so its cost is the
# Board's CPU. Bug caught: one --publish ran jq about ten times: stream.json read twice, every part checked again and
# its own data.js parsed again.
stub jq "echo jq >> '$T/jq-runs'; exec '$(command -v jq)' \"\$@\""; rm -f "$T/jq-runs"
env -u CONVEYOR_HOOK_FIRE_LOG HOME="$T/userhome" PATH="$BIN:$PATH" CONVEYOR_HOST_OS=Linux CONVEYOR_MAIN="$MAIN" CONVEYOR_WORKSPACES="$WS" CONVEYOR_SCRATCH="$SCR" \
  CONVEYOR_DASHBOARD_DIR="$OUT" timeout 20 bash "$DASH" --publish || fail "--publish exited non-zero"
rm "$BIN/jq" "$BIN/sleep"
[ "$(( $(wc -l < "$T/jq-runs") ))" -le 3 ] || fail "one --publish ran jq $(( $(wc -l < "$T/jq-runs") )) times, not at most 3"
[ ! -s "$T/ssh-calls" ] || fail "--publish asked the host: $(cat "$T/ssh-calls")"
q '(.panels.belt.data.cards | map(.card)) == ["c-later"] and (.panels.health.data.stream | .live == false and .error == "devbox: no line in 30 s")' \
  "--publish puts the feed's newest part on the page, stale marker and all"
q '.panels.needs.data.decisions == [] and .panels.health.data.limitError != null' "--publish keeps the slower parts the cycle read"
# #858: the plugin's pane reads the limit from limit.json alone, as data.js outgrows any reader's cap; a publish that left it out
# or stale lost the pane's weekly limit and pause warning.
jq -e --argjson d "$(json)" '. == {limit: ($d.panels.health.data.limit | {usedPct, resetsAt})} and .limit.usedPct == 41.5' "$OUT/limit.json" >/dev/null \
  || fail "limit.json beside data.js holds the health panel's usedPct and resetsAt: $(cat "$OUT/limit.json" 2>&1)"
[ -z "$(find "$OUT" -maxdepth 1 \( -name '.run.*' -o -name '.data.js.*' -o -name '.publish.lock' \) | head -n 1)" ] || fail "--publish leaves a temporary file or its lock: $(ls -A "$OUT")"
# The first start: no cycle has kept its slow parts yet. The feed's card still reaches the page, those parts "not read yet".
mkdir -p "$T/kept" && mv "$OUT"/cache/part-*.json "$T/kept/" && feed true c-first
env -u CONVEYOR_HOOK_FIRE_LOG HOME="$T/userhome" PATH="$BIN:$PATH" CONVEYOR_HOST_OS=Linux CONVEYOR_MAIN="$MAIN" CONVEYOR_WORKSPACES="$WS" CONVEYOR_SCRATCH="$SCR" \
  CONVEYOR_DASHBOARD_DIR="$OUT" timeout 20 bash "$DASH" --publish || fail "--publish with no kept part exited non-zero"
q '(.panels.belt.data.cards | map(.card)) == ["c-first"] and (.panels.health.data.limitError | test("not read yet"))
   and (.panels.lanes.error | test("not read yet")) and (.panels.needs.data.decisionsError | test("not read yet"))' \
  "--publish before the first cycle kept its parts puts the feed's card on the page at once"
[ "$(jq -c . "$OUT/limit.json")" = '{"limit":null}' ] || fail "with no limit in the health panel limit.json says null, never the last limit: $(cat "$OUT/limit.json")"
mv "$T/kept"/part-*.json "$OUT/cache/"
touch -d '2 minutes ago' "$OUT/stream.json"; quiet; : > "$T/ssh-calls"
run
[ -s "$T/ssh-calls" ] || fail "a stream.json the feed no longer writes was taken for a live one"
q '.panels.health.data.stream.live == false and (.panels.health.data.stream.error | test("live feed has stopped"))' "a stopped feed is said to be stopped"
rm "$OUT/stream.json"
) & started contract

# --- --history (#524): the snapshot holds only the newest of each list that grows with landed cards; GET /history
# gives the Landed, Metrics, Cost and Declined parts built from every record's `conveyor.sh history`, once a minute at
# most. Bugs: the older cards never reach the page; each ask is a host read; a host that gives no history is passed off
# as one with nothing in it ---
( fresh history
quiet; run  # a cycle, which keeps the slower parts
card() { jq -cn --arg c "$1" --arg t "$2" '{card: $c, issue: 7, title: $c, step: "landed", time: $t, usd: 1, reviews: 1, followups: [], sha: "abc", pushed: true}'; }
NEW=$(card c-new "$(ago 60)") OLD=$(card c-old "$(ago 7200)")
jq -cn --argjson s "$(snap "{\"landed\": [$NEW], \"landedCount\": 2, \"historySum\": \"1-1\"}")" --argjson w "$(snap '{"historySum": "2-2"}')" --arg at "$NOWISO" '{host: "devbox", reachable: true, error: null,
  records: [{repo: "sample", snap: $s, steered: true, repoUrl: "https://github.com/o/r", lastPushAt: null}, {repo: "widgetshop", snap: $w, steered: false, repoUrl: null, lastPushAt: null}],
  stream: {live: true, heardAt: $at, since: null, error: null}}' > "$OUT/stream.json"
hist() { jq -cn --argjson l "$1" '{landed: $l, metrics: {cards: []}, cost: {cards: [], unpriced: []}, declinedRest: []}'; }
printf '%s\n%s\n@@end\n' "$(hist "[$NEW, $OLD]")" "$(hist '[]')" > "$T/ssh-out"; : > "$T/ssh-calls"
hrun() { env -u CONVEYOR_HOOK_FIRE_LOG HOME="$T/userhome" PATH="$BIN:$PATH" CONVEYOR_HOST_OS=Linux CONVEYOR_MAIN="$MAIN" CONVEYOR_WORKSPACES="$WS" CONVEYOR_SCRATCH="$SCR" \
  CONVEYOR_DASHBOARD_DIR="$OUT" timeout 20 bash "$DASH" --history; }
h=$(hrun) || fail "--history exited non-zero"
[ "$(jq -c '[(.panels | keys), (.panels.landed.data.cards | map(.card))]' <<<"$h")" = '[["cost","declined","landed","metrics"],["c-new","c-old"]]' ] \
  || fail "--history does not give the four parts with the older card of the day: $(jq -c '.panels.landed' <<<"$h" | cut -c1-600)"
[ "$(grep -c "conveyor.sh' history" "$T/ssh-calls")" = 1 ] && [ "$(wc -l < "$T/ssh-calls")" = 1 ] || fail "--history asks the host for every record's history in one command: $(cat "$T/ssh-calls")"
[ "$(hrun | jq -c '.panels.landed.data.cards | length')" = 2 ] && [ "$(wc -l < "$T/ssh-calls")" = 1 ] || fail "a second --history with no ledger change asked the host again: $(cat "$T/ssh-calls")"
rm "$OUT/cache/history.json"; echo 255 > "$T/ssh-rc"
h=''; ! h=$(hrun 2>/dev/null) && [ -z "$h" ] || fail "a host that gave no history was passed off as one: $h"
) & started history

# --- GET /history (#551): the page server's handler, run on stand-in requests, on the real dashboard.sh --history and
# the ssh stub. Bugs: the history was read from the host each minute for each page though the ledger had not changed;
# two asks at once both read it; the whole history went again to a page that had it; a dismiss from the Board was not
# shown until the copy aged out ---
( fresh historyserver
quiet; run  # a cycle, which keeps the slower parts
CARD=$(jq -cn --arg t "$(ago 60)" '{card: "c-new", issue: 7, title: "c-new", step: "landed", time: $t, usd: 1, reviews: 1, followups: [], sha: "abc", pushed: true}')
feed() {  # stream.json, as the live feed writes it, sample's snapshot with landedCount $1 and historySum $2
  jq -cn --argjson s "$(snap "{\"landed\": [$CARD], \"landedCount\": $1, \"historySum\": \"$2\"}")" --argjson w "$(snap '{"historySum": "2-2"}')" --arg at "$NOWISO" '{host: "devbox", reachable: true, error: null,
    records: [{repo: "sample", snap: $s, steered: true, repoUrl: null, lastPushAt: null}, {repo: "widgetshop", snap: $w, steered: false, repoUrl: null, lastPushAt: null}],
    stream: {live: true, heardAt: $at, since: null, error: null}}' > "$OUT/stream.json"
}
feed 1 1-1
hist=$(jq -cn --argjson c "$CARD" '{landed: [$c], metrics: {cards: []}, cost: {cards: [], unpriced: []}, declinedRest: []}')
printf '%s\n%s\n@@end\n' "$hist" "$hist" > "$T/ssh-out"; : > "$T/ssh-calls"
env -u CONVEYOR_HOOK_FIRE_LOG HOME="$T/userhome" PATH="$BIN:$PATH" CONVEYOR_HOST_OS=Linux CONVEYOR_MAIN="$MAIN" CONVEYOR_WORKSPACES="$WS" \
  CONVEYOR_SCRATCH="$SCR" CONVEYOR_DASHBOARD_DIR="$OUT" CONVEYOR_DASHBOARD_AUTH="$T/auth/dashboard-auth.json" CONVEYOR_RULING_LOG="$T/rulings.jsonl" \
  timeout 120 "$PY" - "$SOURCE/.claude/scripts" "$OUT" "$T/ssh-calls" <<'EOF' || fail "GET /history: exit $? (see the lines above)"
import io, json, os, subprocess, sys, threading, time
sys.path.insert(0, sys.argv[1])
import dashboard_server as ds
OUT, CALLS = sys.argv[2], sys.argv[3]
SSH_OUT = os.path.join(os.path.dirname(CALLS), 'ssh-out')
bad = []
def reads():  # the host's history reads so far
    return sum("conveyor.sh' history" in l for l in open(CALLS))
started = []  # the --history processes started: an ask the kept copy answers starts none (#566 D2)
real_run = ds.run_script
def counted(cmd, *a, **k):
    if '--history' in cmd:
        started.append(cmd)
    return real_run(cmd, *a, **k)
ds.run_script = counted
class Page:
    """A stand-in request: logged in, from the page's own address, its reply kept."""
    def __init__(self, inm=None, body=None):
        self.directory, self.out, self.code, self.tag, self.close_connection = OUT, io.BytesIO(), None, None, False
        self.headers = {'If-None-Match': inm} if inm else {}
        if body is not None:
            raw = json.dumps(body).encode()
            self.headers['Content-Length'], self.rfile = str(len(raw)), io.BytesIO(raw)
        self.wfile, self.client_address = self.out, ('192.0.2.1', 0)
    def authed(self, store=None): return 'ann'
    def own_page(self): return True
    def send_response(self, code): self.code = code
    def send_header(self, *a): return None
    def end_headers(self): return None
    def reply(self, code, text, headers=None): self.code, self.text = code, text
    def send_error(self, code): self.code = code
def get(inm=None):
    p = Page(inm)
    ds.Handler.history(p)
    return p
def dismiss(did):
    """POST /control dismiss of did, then the host's history after it: the line in sample's declinedRest."""
    d = Page(body={'action': 'dismiss', 'args': [did], 'repo': 'sample'})
    ds.Handler.control(d)
    lines = open(SSH_OUT).read().split('\n')
    h = json.loads(lines[0])
    h['declinedRest'] = h['declinedRest'] + [{'id': did, 'repo': 'sample', 'finding': '[P2] a.txt:1 a line', 'dismissed': {'by': 'ann'}}]
    lines[0] = json.dumps(h)
    open(SSH_OUT, 'w').write('\n'.join(lines))
    return d.code
ds.conveyor_host = lambda: ('devbox', 'user@devbox', '/srv/main', {'sample': '/srv/main', 'widgetshop': '/srv/cd'})
a = get()
if not (a.code == 200 and a.tag and reads() == 1):
    bad.append('a first ask reads the host and sends an ETag: %s %r, %d reads' % (a.code, a.tag, reads()))
b = get(a.tag)
if not (b.code == 304 and b.out.getvalue() == b'' and reads() == 1 and len(started) == 1):
    bad.append('a second ask with the first ETag and no ledger change is a 304 with no host read and no process: %s, %d reads, %d started'
               % (b.code, reads(), len(started)))
STREAM = os.path.join(OUT, 'stream.json')
def snap(**kw):  # sets fields of sample's snapshot in the live feed
    s = json.load(open(STREAM))
    s['records'][0]['snap'].update(kw)
    json.dump(s, open(STREAM, 'w'))
snap(landedCount=2, historySum='3-3')  # a new landed card: the snapshot's history, and so its sum, changes
c = get(a.tag)
if not (c.code == 200 and reads() == 2 and c.tag != a.tag):
    bad.append('a new landedCount reads the host again, under a new ETag: %s, %d reads' % (c.code, reads()))
snap(day='2000-01-02')  # midnight: Cost's rows past the live cut are of another day, with the same history
if not (get(c.tag).code == 200 and reads() == 3):
    bad.append('a new day reads the host again: %d reads' % reads())
# The dismissed line goes to declinedRest; the live feed's snapshot, taken before the dismiss, has the same key.
dcode = dismiss('d0123456789ab')
e = get(c.tag)
if not (dcode == 200 and e.code == 200 and reads() == 4 and b'd0123456789ab' in e.out.getvalue()):
    bad.append('a POST /control dismiss makes the next ask read the host again: %s %s, %d reads' % (dcode, e.code, reads()))
for name in ('history.json', 'history.key'):
    if os.path.exists(os.path.join(OUT, 'cache', name)):
        os.remove(os.path.join(OUT, 'cache', name))
two = [Page(), Page()]
runs = [threading.Thread(target=ds.Handler.history, args=(p,)) for p in two]
for t in runs: t.start()
for t in runs: t.join()
if not ([p.code for p in two] == [200, 200] and two[0].out.getvalue() == two[1].out.getvalue() and reads() == 5):
    bad.append('two asks at once on a cold copy read the host once: %s, %d reads' % ([p.code for p in two], reads()))
old = time.time() - 120  # the live feed stopped: no ledger key, the copy kept while it is young
os.utime(STREAM, (old, old))
n = len(started)
f = get()
if not (f.code == 200 and json.loads(f.out.getvalue()).get('panels') and reads() == 5 and len(started) == n):
    bad.append('with no live feed a young copy is given with no host read and no process: %s, %d reads' % (f.code, reads()))
dcode = dismiss('d0123456789ac')  # with no live feed, a dismiss drops the young copy too
g = get()  # not the young copy: the host is read again (then its records too, which the stub does not answer: a 502)
if not (dcode == 200 and g.code != 200 and reads() == 6):
    bad.append('with no live feed a POST /control dismiss makes the next ask read the host again: %s %s, %d reads' % (dcode, g.code, reads()))
for why in bad:
    print('FAIL: GET /history: ' + why, file=sys.stderr)
sys.exit(1 if bad else 0)
EOF
) & started historyserver

# --- --work (#197): the Health panel's Work now, the first record's `conveyor.sh work --json`, which reads every
# record's cards, in one host command. Bugs: each record was asked for its work and the answers merged, so one card
# showed once a record; the groups are not the heaviest first; a long command line reaches the page whole; a host
# that gives no reading is passed off as an idle machine ---
( fresh work
long=$(printf 'x%.0s' $(seq 300))
jq -cn --arg l "node $long" '{groups: [{card: "c20261117T000001-sample-5", project: "sample", step: "test", closed: false, cpu: 40,
    stop: null, processes: [{pid: 10, cpu: 40, command: $l}]}, {card: "c20261117T000002-widgetshop-6", project: "widgetshop", step: null,
    closed: true, cpu: 60, stop: "kill 30", processes: [{pid: 30, cpu: 50, command: "node b.js"}]}],
    other: [{pid: 20, cpu: 90, command: "firefox", test: false}]}' > "$T/ssh-out"
: > "$T/ssh-calls"
wrun() { env -u CONVEYOR_HOOK_FIRE_LOG HOME="$T/userhome" PATH="$BIN:$PATH" CONVEYOR_HOST_OS=Linux CONVEYOR_MAIN="$MAIN" CONVEYOR_WORKSPACES="$WS" CONVEYOR_SCRATCH="$SCR" \
  CONVEYOR_DASHBOARD_DIR="$OUT" timeout 20 bash "$DASH" --work; }
w=$(wrun) || fail "--work exited non-zero"
[ "$(jq -c '[.host, [.groups[].card[-1:]], [.other[].pid], (.groups[1].processes[0].command | length)]' <<<"$w")" = '["devbox",["6","5"],[20],200]' ] \
  || fail "--work does not give every record's cards, the heaviest first, and the work no card owns: $(cut -c1-600 <<<"$w")"
[ "$(grep -o "work --json" "$T/ssh-calls" | wc -l)" = 1 ] && grep -q "CONVEYOR_MAIN='/srv/main' bash .*conveyor.sh' work --json" "$T/ssh-calls" \
  || fail "--work does not ask the host once, for the first record: $(cat "$T/ssh-calls")"
: > "$T/ssh-out"
w=''; ! w=$(wrun 2>/dev/null) && [ -z "$w" ] || fail "a host that gave no work reading was passed off as an idle machine: $w"
) & started work

# --- --older (#251): the older runs and test edits of one test file, which data.js no longer carries: the named
# record's `conveyor.sh history test <file>` in one host command, each run with its card's issue link as the Tests
# part's runs have (#217: an older run with no link had no issue on the Timeline). Bugs: another record was asked; the
# file reached the host unquoted; a host that gives no answer is passed off as a file with no older run ---
( fresh older
jq -cn '{file: "a b.test.sh", olderRuns: [{cpu: 1, card: "c4-11"}, {cpu: 2, card: null, whole: true}], olderEdits: [{card: "c3-9", file: "a b.test.sh"}]}' > "$T/ssh-out"
echo 'git@github.com:o/w.git' >> "$T/ssh-out"
: > "$T/ssh-calls"
orun() { env -u CONVEYOR_HOOK_FIRE_LOG HOME="$T/userhome" PATH="$BIN:$PATH" CONVEYOR_HOST_OS=Linux CONVEYOR_MAIN="$MAIN" CONVEYOR_WORKSPACES="$WS" CONVEYOR_SCRATCH="$SCR" \
  CONVEYOR_DASHBOARD_DIR="$OUT" timeout 20 bash "$DASH" --older "$@"; }
o=$(orun widgetshop 'a b.test.sh') || fail "--older exited non-zero"
[ "$(jq -c '[.file, (.olderRuns | map([.card, .issue, .url, .repo])), (.olderEdits | map(.card))]' <<<"$o")" = '["a b.test.sh",[["c4-11",11,"https://github.com/o/w/issues/11","widgetshop"],[null,null,null,"widgetshop"]],["c3-9"]]' ] \
  || fail "--older does not give the file's older runs, each with its card's link: $o"
[ "$(wc -l < "$T/ssh-calls")" = 1 ] && grep -q "CONVEYOR_MAIN='/srv/cd' bash .*conveyor.sh' history test 'a b.test.sh'" "$T/ssh-calls" \
  || fail "--older does not ask the host once, for the named record and the file quoted: $(cat "$T/ssh-calls")"
o=''; ! o=$(orun nosuch a.test.sh 2>/dev/null) && [ -z "$o" ] || fail "a record the host file does not name gave older runs: $o"
: > "$T/ssh-out"
o=''; ! o=$(orun widgetshop a.test.sh 2>/dev/null) && [ -z "$o" ] || fail "a host that gave no older runs was passed off as a file with none: $o"
) & started older

# --- --donewhen (#305): a card's Done-when items, which data.js does not carry: the named record's `conveyor.sh
# history donewhen <card>` in one host command. Bugs: another record was asked; the card reached the host unquoted; a
# host that gives no answer is passed off as a check with no item ---
( fresh donewhen
jq -cn '{card: "c1 x", items: [{n: 1, text: "the thing", builder: "D1 met: a.test.sh", reviewer: "holds"}]}' > "$T/ssh-out"
: > "$T/ssh-calls"
drun() { env -u CONVEYOR_HOOK_FIRE_LOG HOME="$T/userhome" PATH="$BIN:$PATH" CONVEYOR_HOST_OS=Linux CONVEYOR_MAIN="$MAIN" CONVEYOR_WORKSPACES="$WS" CONVEYOR_SCRATCH="$SCR" \
  CONVEYOR_DASHBOARD_DIR="$OUT" timeout 20 bash "$DASH" --donewhen "$@"; }
d=$(drun widgetshop 'c1 x') || fail "--donewhen exited non-zero"
[ "$(jq -c '.items | map([.n, .builder, .reviewer])' <<<"$d")" = '[[1,"D1 met: a.test.sh","holds"]]' ] || fail "--donewhen does not give the card's items: $d"
[ "$(wc -l < "$T/ssh-calls")" = 1 ] && grep -q "CONVEYOR_MAIN='/srv/cd' bash .*conveyor.sh' history donewhen 'c1 x'" "$T/ssh-calls" \
  || fail "--donewhen does not ask the host once, for the named record and the card quoted: $(cat "$T/ssh-calls")"
d=''; ! d=$(drun nosuch c1 2>/dev/null) && [ -z "$d" ] || fail "a record the host file does not name gave Done-when items: $d"
: > "$T/ssh-out"
d=''; ! d=$(drun widgetshop c1 2>/dev/null) && [ -z "$d" ] || fail "a host that gave no answer was passed off as a check with no item: $d"
) & started donewhen

# --- --shot (#308): one screenshot a card waiting for the owner's yes kept, from the named record's kept folder on the
# host, in one host command. Bugs: another record was asked; the card or file reached the host unquoted; a host that
# gives no image is passed off as one ---
( fresh shot
echo 'iVBORw==' > "$T/ssh-out"; : > "$T/ssh-calls"
srun() { env -u CONVEYOR_HOOK_FIRE_LOG HOME="$T/userhome" PATH="$BIN:$PATH" CONVEYOR_HOST_OS=Linux CONVEYOR_MAIN="$MAIN" CONVEYOR_WORKSPACES="$WS" CONVEYOR_SCRATCH="$SCR" \
  CONVEYOR_DASHBOARD_DIR="$OUT" timeout 20 bash "$DASH" --shot "$@"; }
o=$(srun widgetshop c1-12 a.png) || fail "--shot exited non-zero"
[ "$o" = 'iVBORw==' ] || fail "--shot does not give the host's image: $o"
[ "$(wc -l < "$T/ssh-calls")" = 1 ] && grep -q "CONVEYOR_MAIN='/srv/cd' bash .*conveyor.sh' state-dir)\"/kept/'c1-12'/shots/'a.png'" "$T/ssh-calls" \
  || fail "--shot does not ask the host once, for the named record's kept folder with the card and file quoted: $(cat "$T/ssh-calls")"
o=''; ! o=$(srun nosuch c1-12 a.png 2>/dev/null) && [ -z "$o" ] || fail "a record the host file does not name gave a screenshot: $o"
echo 1 > "$T/ssh-rc"; : > "$T/ssh-out"
o=''; ! o=$(srun widgetshop c1-12 a.png 2>/dev/null) && [ -z "$o" ] || fail "a host that gave no screenshot was passed off as one: $o"
) & started shot

# --- --excerpts (#307): the lines a card's review findings cite, which data.js does not carry: the named record's
# `conveyor.sh history excerpts <card>` in one host command. Bugs: another record was asked; the card reached the host
# unquoted; a host that gives no answer is passed off as a card with no reviewed lines ---
( fresh excerpts
jq -cn '{card: "c1 x", excerpts: [{review: "2026-01-01T00:01:00Z", at: "a.sh:2", side: "new", from: 2, lines: ["two"]}]}' > "$T/ssh-out"
: > "$T/ssh-calls"
xrun() { env -u CONVEYOR_HOOK_FIRE_LOG HOME="$T/userhome" PATH="$BIN:$PATH" CONVEYOR_HOST_OS=Linux CONVEYOR_MAIN="$MAIN" CONVEYOR_WORKSPACES="$WS" CONVEYOR_SCRATCH="$SCR" \
  CONVEYOR_DASHBOARD_DIR="$OUT" timeout 20 bash "$DASH" --excerpts "$@"; }
d=$(xrun widgetshop 'c1 x') || fail "--excerpts exited non-zero"
[ "$(jq -c '.excerpts | map([.at, .lines])' <<<"$d")" = '[["a.sh:2",["two"]]]' ] || fail "--excerpts does not give the card's reviewed lines: $d"
[ "$(wc -l < "$T/ssh-calls")" = 1 ] && grep -q "CONVEYOR_MAIN='/srv/cd' bash .*conveyor.sh' history excerpts 'c1 x'" "$T/ssh-calls" \
  || fail "--excerpts does not ask the host once, for the named record and the card quoted: $(cat "$T/ssh-calls")"
d=''; ! d=$(xrun nosuch c1 2>/dev/null) && [ -z "$d" ] || fail "a record the host file does not name gave reviewed lines: $d"
: > "$T/ssh-out"
d=''; ! d=$(xrun widgetshop c1 2>/dev/null) && [ -z "$d" ] || fail "a host that gave no answer was passed off as a card with no reviewed lines: $d"
) & started excerpts

# --- --bench (#326): the Benchmarks tab's history, or one run's tasks, which data.js does not carry: the named record's
# `conveyor.sh bench swe history` or `bench swe show <run>` in one host command. Bugs: another record was asked; the
# run reached the host unquoted; a host that gave no answer was passed off as no benchmarks ---
( fresh bench
brun() { env -u CONVEYOR_HOOK_FIRE_LOG HOME="$T/userhome" PATH="$BIN:$PATH" CONVEYOR_HOST_OS=Linux CONVEYOR_MAIN="$MAIN" CONVEYOR_WORKSPACES="$WS" CONVEYOR_SCRATCH="$SCR" \
  CONVEYOR_DASHBOARD_DIR="$OUT" timeout 20 bash "$DASH" --bench "$@"; }
echo '{"runs":[],"arms":[]}' > "$T/ssh-out"; : > "$T/ssh-calls"
o=$(brun widgetshop) && [ "$o" = '{"runs":[],"arms":[]}' ] || fail "--bench does not give the record's history: $o"
o=$(brun widgetshop 'r20261117T090000-1') || fail "--bench <run> exited non-zero"
[ "$(wc -l < "$T/ssh-calls")" = 2 ] && grep -q "CONVEYOR_MAIN='/srv/cd' bash .*conveyor.sh' bench swe history$" "$T/ssh-calls" \
  && grep -q "CONVEYOR_MAIN='/srv/cd' bash .*conveyor.sh' bench swe show 'r20261117T090000-1'$" "$T/ssh-calls" \
  || fail "--bench does not ask the host once a read, for the named record and the run quoted: $(cat "$T/ssh-calls")"
o=''; ! o=$(brun nosuch 2>/dev/null) && [ -z "$o" ] || fail "a record the host file does not name gave benchmarks: $o"
: > "$T/ssh-out"
o=''; ! o=$(brun widgetshop 2>/dev/null) && [ -z "$o" ] || fail "a host that gave no benchmarks was passed off as none: $o"
) & started bench

# Every part ended and passed; a part that failed stopped at its FAIL line, above.
bad=()
for p in "${PARTS[@]}"; do wait "${p#*:}" || bad+=("${p%%:*}"); done
[ ${#bad[@]} -eq 0 ] || fail "these parts failed (their FAIL lines are above): ${bad[*]}"
echo "ok: dashboard"
