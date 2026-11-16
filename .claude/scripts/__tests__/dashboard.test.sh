#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 300
# The collector of the Conveyor dashboard (dashboard.sh). The page is what the owner reads instead of asking, so the
# data must never lie: every panel's part is cut from the same answers, a source that was not read is null with its
# reason (never a 0 or an empty list that reads as measured), a host that did not answer is said to be unreachable,
# and a sum with an unpriced step in it is unknown, never the sum of the priced part.
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

# The parts below run side by side ( fresh <part>; ... ) &, so the file takes its slowest part's time, not their sum.
# fresh <part> -- the part's own folder ($T, under $TOP), checkout, host file, stubs and dashboard folder, set up as
# every part begins. A part PARTSEL leaves out ends here, passed.
fresh() {
[ -z "$PARTSEL" ] || [[ " $PARTSEL " == *" $1 "* ]] || exit 0
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
# snap [<overrides>] -- one record's snapshot as conveyor.sh prints it: empty and healthy unless overridden.
snap() {
  local o=${1:-}; [ -n "$o" ] || o='{}'
  jq -cn --arg day "$(date +%F)" --arg now "$NOWISO" --argjson o "$o" '
    {time: $now, day: $day, needsYou: {waiting: [], blocked: [], before: []}, belt: [], queue: {next: []}, landed: [], landedCount: 0,
     health: {time: $now, loop: true, newest: $now, blocked: [], waiting: [], stuck: [], unpushed: [], pushError: null, pushFailingSince: null,
              gh: true, diskFreeKb: 500000000, builderCap: 3, models: {claude: "claude-x", codex: "gpt-x"}},
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

( fresh contract
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
q '.panels.belt == {error: null, data: {cards: [], cap: 6, byRepo: {sample: {cap: 3}, widgetshop: {cap: 3}}}}' "an empty belt is an empty list, with the builder slots of both records and each record's own"
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
q '.panels.landed.data.cards == [] and .panels.landed.data.day == "'"$(date +%F)"'"' "nothing landed is an empty list for today"
q '.panels.cost.data.cards | .todayUsd == 0 and .weekUsd == 0 and .perLandedUsd == null and .perCard == [] and .unpricedSteps == 0' "no spend is a measured 0, and no landed card has no average"
q '.panels.declined == {error: null, data: {lines: [], rest: []}}' "no declined finding (a snapshot from before it carried the list, too) is an empty list, not a failed part"
q '.panels.health.data | .host == {name: "devbox", local: false, reachable: true, error: null} and (.records | length) == 2 and (has("cpuCap") | not)' "the host answered: reachable, both records, and no CPU cap (dropped)"
q '.panels.health.data.records | .[0].lastPushAt == (1794000000 | todate) and .[1].lastPushAt == null and all(.[]; .loop == true and .gh == true)' "each record carries its last push; none recorded is null"
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
  jq -cn --argjson s "$(snap "{\"belt\":[{\"card\":\"$2\",\"issue\":5,\"title\":\"T5\",\"step\":\"build\",\"stepAt\":\"$NOWISO\",\"landed\":false,\"tokens\":{\"claude\":0,\"codex\":0},\"usd\":null,\"reading\":false,\"reviews\":[],\"track\":null}]}")" \
    --argjson live "$1" --arg at "$NOWISO" '{host: "devbox", reachable: true, error: null,
      records: [{repo: "sample", snap: $s, steered: true, repoUrl: "https://github.com/o/r", lastPushAt: null}],
      stream: {live: $live, heardAt: $at, since: (if $live then null else $at end), error: (if $live then null else "devbox: no line in 30 s" end)}}' > "$OUT/stream.json"
}
feed true c-fed; : > "$T/ssh-calls"
run
[ ! -s "$T/ssh-calls" ] || fail "a cycle with the live feed fresh asked the host: $(cat "$T/ssh-calls")"
q '(.panels.belt.data.cards | map(.card)) == ["c-fed"] and .panels.health.data.stream.live == true' "a cycle takes Conveyor's part from a fresh live feed"
for k in limit decisions lanes; do [ -s "$OUT/cache/part-$k.json" ] || fail "the cycle did not keep its $k part for --publish"; done
feed false c-later; stub sleep 'exit 0'  # a slow read would show here: --publish runs none
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
[ -z "$(find "$OUT" -maxdepth 1 \( -name '.run.*' -o -name '.data.js.*' -o -name '.publish.lock' \) | head -n 1)" ] || fail "--publish leaves a temporary file or its lock: $(ls -A "$OUT")"
# The first start: no cycle has kept its slow parts yet. The feed's card still reaches the page, those parts "not read yet".
mkdir -p "$T/kept" && mv "$OUT"/cache/part-*.json "$T/kept/" && feed true c-first
env -u CONVEYOR_HOOK_FIRE_LOG HOME="$T/userhome" PATH="$BIN:$PATH" CONVEYOR_HOST_OS=Linux CONVEYOR_MAIN="$MAIN" CONVEYOR_WORKSPACES="$WS" CONVEYOR_SCRATCH="$SCR" \
  CONVEYOR_DASHBOARD_DIR="$OUT" timeout 20 bash "$DASH" --publish || fail "--publish with no kept part exited non-zero"
q '(.panels.belt.data.cards | map(.card)) == ["c-first"] and (.panels.health.data.limitError | test("not read yet"))
   and (.panels.lanes.error | test("not read yet")) and (.panels.needs.data.decisionsError | test("not read yet"))' \
  "--publish before the first cycle kept its parts puts the feed's card on the page at once"
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
jq -cn --argjson s "$(snap "{\"landed\": [$NEW], \"landedCount\": 2}")" --argjson w "$(snap)" --arg at "$NOWISO" '{host: "devbox", reachable: true, error: null,
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
[ "$(hrun | jq -c '.panels.landed.data.cards | length')" = 2 ] && [ "$(wc -l < "$T/ssh-calls")" = 1 ] || fail "a second --history inside the minute asked the host again: $(cat "$T/ssh-calls")"
rm "$OUT/cache/history.json"; echo 255 > "$T/ssh-rc"
h=''; ! h=$(hrun 2>/dev/null) && [ -z "$h" ] || fail "a host that gave no history was passed off as one: $h"
) & started history

# --- cards on both records: every row names its repo and links to that repo's issue ---
# cards_fixture -- the two records' snapshots with cards on them (P, C) and each repo's issue links (PU, CU), which the
# parts from here to the host that did not answer read.
cards_fixture() {
TODAY=$(date -u +%Y%m%d) TODAY_ISO=$(date -u +%Y-%m-%d)
P=$(snap '{"needsYou": {"waiting": [{"card": "c1-12", "issue": 12, "title": "Button copy", "sentence": "Staff see a new button.", "since": "'"$(ago 600)"'"}],
                        "blocked": [{"card": "c2-13", "issue": 13, "title": "Broken", "reason": "tests failed twice", "since": "'"$(ago 900)"'",
                                     "track": {"records": [{"name": "tests failed", "state": "failed", "failures": {"files": [{"file": "a.test", "cases": [{"name": "adds up"}]}]}}]},
                                     "reviews": [{"round": 1, "verdict": "NO-GO", "sec": 40}], "metrics": {"tokens": 5000, "usd": 0.4, "timeline": [{"model": "claude-x"}, {"model": "gpt-x"}]}}],
                        "before": [{"issue": 14, "title": "Green Pay", "section": "The Pay page: a green button.", "since": "'"$(ago 1200)"'"}],
                        "engine": {"commit": "cccc", "reason": "its check of the pack failed: .tunables.x: not a field of the schema", "since": "'"$(ago 800)"'"},
                        "testRules": {"time": "'"$(ago 500)"'", "matched": 5, "cap": 3}},
  "mainTest": {"issue": 15, "cases": ["alpha", "beta"], "from": "aaaa", "to": "bbbb", "since": "'"$(ago 700)"'", "exit": 1},
  "flaky": [{"case": "b.test: flaky", "count": 3, "issue": 16}, {"case": "c.test: other", "count": 1, "issue": null}],
  "slowOff": [{"file": "s.test", "issue": 17, "cpu": 10, "budget": 8, "card": "c2-9", "last": {"cpu": 9, "card": "c2-8"}}],
  "belt": [{"card": "c3-801", "issue": 801, "title": "Rebuild the dashboard", "step": "review", "review": 2, "of": 3, "stepAt": "'"$(ago 300)"'", "model": "gpt-x", "tokens": {"claude": 10, "codex": 5}, "usd": 1.25}],
  "queue": {"next": [{"issue": 20, "title": "Next up", "priority": "P1", "followup": true, "retried": false}],
    "order": [{"issue": 20, "title": "Next up", "priority": "P1", "followup": true, "retried": false}], "holding": [{"issue": 30, "title": "Held one"}],
    "skipped": [{"issue": 31, "title": "Infra one", "rule": "area:infra"}],
    "waiting": [{"issue": 32, "title": "Second half", "priority": "P2", "followup": false, "retried": false, "created": "2026-11-01T00:00:00Z", "waitsFor": [20]}]},
  "control": {"mode": "pause", "cap": null, "guard": 90, "held": [30], "order": [], "rules": {"P0": true, "P1": true, "P2": true, "followups": true, "never": ["area:infra"]}, "model": null, "reviewer": null, "judgeOn": true},
  "modelSettings": {"builder": {"model": "claude-x", "effort": "medium", "modelFrom": "seed", "effortFrom": "seed", "choices": ["claude-x"], "efforts": ["low"]},
    "judge": {"model": "claude-j", "effort": "high", "modelFrom": "seed", "effortFrom": "seed", "choices": ["claude-j"], "efforts": ["high"], "default": "claude-j"}},
  "areaPrefix": "team/",
  "health": {"state": "paused", "reason": "the loop says why", "guard": {"at": 90, "reading": 42, "readAt": "'"$(ago 60)"'", "missing": false}, "cycles": [[40, 41]],
    "routes": {"subscription": {"state": "expired", "at": "2026-11-05T00:00:00Z"}, "proxy": {"state": "works", "at": "2026-11-05T00:00:01Z", "baseUrl": "http://127.0.0.1:4141", "route": "fallback"}},
    "unpushed": [{"card": "c5-7", "issue": 7, "sha": "abc", "since": "2026-11-05T00:00:00Z"}]},
  "forecast": {"cards": 1, "usd": 0.95, "perCard": {"usd": 0.95, "pct": 0.5}, "guard": 90, "reading": 42, "pausesAt": null},
  "fullTest": {"command": true, "why": null, "running": null, "last": {"time": "2026-11-05T01:00:00Z", "kind": "run", "push": true, "sha": "abc", "state": "failed", "exit": 1, "cases": [], "pushed": null}},
  "open": {"count": 6, "split": {"queued": 2, "you": 1, "labelOrRule": 2, "belt": 1}, "held": [{"issue": 30, "title": "Held one", "priority": "P3", "followup": false, "labels": [], "created": null, "parent": null, "reasons": [{"kind": "you"}]},
    {"issue": 33, "title": "Backlog one", "priority": "P2", "followup": false, "labels": ["backlog"], "created": null, "parent": null, "reasons": [{"kind": "label", "label": "backlog"}]}]},
  "awaitingDeploy": [{"issue": 802, "title": "Stack split", "since": "2026-11-05T00:00:00Z"}, {"issue": 803, "title": "No time", "since": null}],
  "metrics": {"cards": [{"card": "c5-1", "issue": 1, "metrics": {"buildSec": 600, "reviewSec": 300, "fixSec": null}}, {"card": "c5-2", "issue": 2, "metrics": {"buildSec": 200, "reviewSec": 100, "fixSec": 0}},
    {"card": "c5-3", "issue": 3, "metrics": {"buildSec": 400}}], "prev": {"cards": 2, "landed": 1}, "days": [{"day": "2026-11-09", "landed": 1, "blocked": 0}],
    "slots": [{"hour": 9, "slots": 1.5, "cap": 3}]},
  "declined": [{"id": "d0123456789ab", "time": "'"$TODAY_ISO"'T08:40:00Z", "card": "c3-801", "issue": 801, "finding": "[P1] b.txt:2 no mark here", "by": "judge", "why": "its proof needs a stub built to misbehave", "repo": "sample"}],
  "declinedRest": [{"id": "dba9876543210", "time": "'"$TODAY_ISO"'T07:10:00Z", "card": "c0-6", "issue": 6, "finding": "[P2] a.txt:1 wrong word", "by": "code", "why": "follow-up of a follow-up", "repo": "sample", "built": 90},
    {"id": "d0000000000dd", "time": "'"$TODAY_ISO"'T08:50:00Z", "card": "c3-801", "issue": 801, "finding": "[P3] d.txt:4 a word", "by": "judge", "why": "taste", "repo": "sample", "dismissed": {"time": "'"$TODAY_ISO"'T09:00:00Z", "by": "Board user owner"}}],
  "landedCount": 1, "landedUsd": 41.5,
  "landed": [{"card": "c'"$TODAY"'T080000-7", "issue": 7, "title": "Landed one", "step": "landed", "time": "'"$TODAY_ISO"'T08:30:00Z", "usd": 2.5, "reviews": 2, "followups": [31], "sha": "abc", "pushed": true, "start": "'"$TODAY_ISO"'T07:00:00Z", "totalSec": 2400}],
  "pushedCards": [{"card": "c0-6", "issue": 6, "time": "'"$(date -u -d yesterday +%F)"'T23:00:00Z", "day": "'"$(date +%F)"'"},
    {"card": "c0-5", "issue": 5, "time": "'"$TODAY_ISO"'T00:30:00Z", "day": "'"$(date -d yesterday +%F)"'"}],
  "cost": {"today": 3.75, "week": 10, "perLanded": 2.5, "landedAfter": {"1": 0, "2": 1, "3": 0, "more": 0}, "unpricedSteps": 0,
    "cards": [{"card": "c3-801", "issue": 801, "title": "Rebuild the dashboard", "state": "on the belt", "today": 1.25, "week": 1.25},
      {"card": "c0-6", "issue": 6, "title": "Landed days ago", "state": "landed", "today": 0, "week": 6.25},
      {"card": "c2-13", "issue": 13, "title": "Broken", "state": "blocked", "today": 2.5, "week": null}]}}')
C=$(snap '{"belt": [{"card": "c4-5", "issue": 5, "title": "Plugin thing", "step": "build", "review": null, "of": 3, "stepAt": "'"$(ago 60)"'", "model": "claude-x", "tokens": {"claude": 1, "codex": 0}, "usd": 0.25}],
  "queue": {"next": [{"issue": 9, "title": "CD next", "priority": "P3", "followup": false, "retried": true}]},
  "open": {"count": 3, "split": {"queued": 1, "you": 1, "labelOrRule": 0, "belt": 1}, "held": [{"issue": 10, "title": "CD held", "priority": "P3", "followup": false, "labels": [], "created": null, "parent": null, "reasons": [{"kind": "you"}]}]},
  "declined": [{"id": "d00000000000c", "time": "'"$TODAY_ISO"'T08:00:00Z", "card": "c4-5", "issue": 5, "finding": "[P2] c.txt:3 a nit", "by": "owner", "why": "not worth a card", "repo": "widgetshop"}],
  "landedCount": 1,
  "landed": [{"card": "c'"$TODAY"'T090000-4", "issue": 4, "title": "CD fixed already", "step": "closed", "time": "'"$TODAY_ISO"'T09:10:00Z", "usd": 0.5, "reviews": 1, "followups": [], "sha": "", "pushed": null}],
  "health": {"loop": false, "builderCap": 2, "unpushed": [{"card": "c9-2", "issue": 2, "sha": "def", "since": "'"$(ago 3600)"'"}]},
  "cost": {"today": 0.5, "week": 4, "perLanded": 0.5, "landedAfter": {"1": 3, "2": 0, "3": 0, "more": 0}, "unpricedSteps": 1,
    "cards": [{"card": "c8-4", "issue": 4, "title": "CD fixed already", "state": "retried", "today": 0.5, "week": 0.5}]},
  "release": {"tag": "v1.0.0", "count": 2, "commits": [], "next": "1.1.0", "notes": true, "head": "abc"},
  "suites": [{"kind": "release", "version": "1.1.0", "sha": "abc", "ended": null, "state": "running", "done": 3, "failed": 1, "cases": ["x: y"]}]}')
PU=https://github.com/example/sample-project/issues CU=https://github.com/example/WidgetShop/issues
}

( fresh cards; cards_fixture
answer "$P" "$P_URL" 1794000000 "$C" "$C_URL" 0
run
# Bug: the Release panel gets nothing of a record's main or its release run, or a record from an older engine breaks it;
# its changes link no issue, for want of the repository's address.
q '.panels.release == {error: null, data: {records: [{repo: "sample", url: "https://github.com/example/sample-project", release: null, suites: null},
  {repo: "widgetshop", url: "https://github.com/example/WidgetShop",
  release: {tag: "v1.0.0", count: 2, commits: [], next: "1.1.0", notes: true, head: "abc"},
  suites: [{kind: "release", version: "1.1.0", sha: "abc", ended: null, state: "running", done: 3, failed: 1, cases: ["x: y"]}]}]}}' \
  "the Release part is each record's release and suites as its snapshot gives them, null from a snapshot from before them"
q '.panels.belt.data | .cap == 5 and (.cards | map([.repo, .issue, .step, .url])) == [["sample", 801, "review", "'"$PU"'/801"], ["widgetshop", 5, "build", "'"$CU"'/5"]]' "belt rows name their repo and link to that repo's issue (an ssh origin is the repo's https address)"
q '.panels.belt.data.cards[0] | .review == 2 and .of == 3 and .model == "gpt-x" and .usd == 1.25 and (.stepAt | fromdateiso8601) > 0' "a belt row keeps its step, review number, model, cost and the time the step began"
q '.panels.needs.data.cards | (.waiting | map([.repo, .issue, .sentence, .url])) == [["sample", 12, "Staff see a new button.", "'"$PU"'/12"]] and (.blocked | map([.issue, .reason])) == [[13, "tests failed twice"]]' "what waits on the owner: the visible change with the reviewer's sentence, and the blocked card with its reason"
q '.panels.needs.data.cards.before | map([.repo, .issue, .section, .url]) == [["sample", 14, "The Pay page: a green button.", "'"$PU"'/14"]]' "an issue waiting for the yes before its build names its repo, its section and its link"
# The whole test on main is no card's step, so its failure is no blocked card: without its own row the owner never sees it.
q '.panels.needs.data.tests | map([.repo, .issue, .cases, .from, .to, .url]) == [["sample", 15, ["alpha", "beta"], "aaaa", "bbbb", "'"$PU"'/15"]]' "a record whose whole test fails on main is in Needs you with its issue, cases and commits; a record with no failure adds none"
# A following record that refused a commit of the plugin's main stays on its old engine: without a row the owner never learns why.
q '.panels.needs.data.engines | map([.repo, .commit, .reason]) == [["sample", "cccc", "its check of the pack failed: .tunables.x: not a field of the schema"]]' "a commit of the plugin's main a record did not take is in Needs you with the commit and why; a record with none adds none"
# Issue 519: a run of the test rules that matched more files than one day's cap filed none; without a row the owner never learns the rules wait for them.
q '.panels.needs.data.testRules | map([.repo, .matched, .cap]) == [["sample", 5, 3]]' "a record whose test rules held a run is in Needs you with the files matched and the cap; a record with none adds none"
q '.panels.queue.data | (.next | map([.repo, .issue, .priority, .followup, .retried])) == [["sample", 20, "P1", true, false], ["widgetshop", 9, "P3", false, true]] and .held == 3' "the queue lists each record's next issues in its order, and counts every record's held issues (open.held: by you, a label, a rule or a wait), as the Board's Held column has them"
q '.panels.queue.data.awaitingDeploy | map([.repo, .issue, .title, .since, .url]) == [["sample", 802, "Stack split", "2026-11-05T00:00:00Z", "'"$PU"'/802"], ["sample", 803, "No time", null, "'"$PU"'/803"]]' "the issues built and waiting for a PROD deploy are listed on their own (a record without the key adds none), each with its repo, link and since when"
# An issue that waits on another is in the queue and on the Board with what it waits for; a cycle reaches health.
q '.panels.queue.data.waiting | map([.repo, .issue, .waitsFor, .url]) == [["sample", 32, [20], "'"$PU"'/32"]]' "the queue lists each record's waiting issues with what each waits for"
q '.panels.board.data.waits | map([.issue, .waitsFor]) == [[32, [20]]]' "the Board has the waiting issues with what each waits for"
q '[.panels.health.data.records[] | .cycles] == [[[40, 41]], null]' "a dependency cycle reaches the health part; a record without the key has none"
# The Claude routes' states (the health record's routes): without them Health cannot show an expired login or the proxy.
q '[.panels.health.data.records[] | .routes | if . == null then null else [.subscription.state, .proxy.state, .proxy.baseUrl] end] == [["expired", "works", "http://127.0.0.1:4141"], null]' "each record's Claude routes reach the health part; a record without the key has none"
# The flaky cases of each record (the snapshot's flaky): without them the Health panel has no Flaky tests line.
q '[.panels.health.data.records[] | .flaky] == [[{case: "b.test: flaky", count: 3, issue: 16, url: "'"$PU"'/16"}, {case: "c.test: other", count: 1, issue: null, url: null}], null]' "each record's flaky cases reach the health part, an issue filed with its link; a record without the key has none"
# Issue 457: the test files kept off card test steps (the snapshot's slowOff), with why: without them Health cannot list them.
q '[.panels.health.data.records[] | .slowOff] == [[{file: "s.test", issue: 17, cpu: 10, budget: 8, card: "c2-9", last: {cpu: 9, card: "c2-8"}, url: "'"$PU"'/17"}], null]' "each record's test files kept off card test steps reach the health part, with why and their issue's link; a record without the key has none"
q '.panels.landed.data.cards | map([.repo, .issue, .step, .tookSec, .reviews, .usd, .pushed]) == [["widgetshop", 4, "closed", 600, 1, 0.5, null], ["sample", 7, "landed", 2400, 2, 2.5, true]]' "landed cards, newest first, each with its reviews, cost and the seconds from the first pick-up of its work to its landing (the snapshot's totalSec, else its card id's time)"
# Bug: the Declined panel lists one record's lines after another's, not the newest first, or loses who declined a finding and why;
# a built or dismissed line is in the panel's lines, or lost from the rest ("Show every line"), or loses who dismissed it.
q '.panels.declined.data.lines | map([.repo, .id, .issue, .url, .finding, .by, .why, .built, .dismissed]) == [["sample", "d0123456789ab", 801, "'"$PU"'/801", "[P1] b.txt:2 no mark here", "judge", "its proof needs a stub built to misbehave", null, null],
  ["widgetshop", "d00000000000c", 5, "'"$CU"'/5", "[P2] c.txt:3 a nit", "owner", "not worth a card", null, null]]' \
  "the declined findings the panel shows, of every record, newest first, each with who declined it and why"
q '.panels.declined.data.rest | map([.repo, .id, .url, .built, .dismissed]) == [["sample", "d0000000000dd", "'"$PU"'/801", null, {time: "'"$TODAY_ISO"'T09:00:00Z", by: "Board user owner"}],
  ["sample", "dba9876543210", "'"$PU"'/6", 90, null]]' "the rest, newest first: the dismissed line with who dismissed it and when, and the built line with its issue"
# Metrics' tiles and charts: each record's 7 days before, its days and today's slots, as its snapshot gives them.
q '.panels.metrics.data.records | map([.repo, .prev, .days, .slots]) == [["sample", {cards: 2, landed: 1}, [{day: "2026-11-09", landed: 1, blocked: 0}], [{hour: 9, slots: 1.5, cap: 3}]], ["widgetshop", null, null, null]]' \
  "metrics carries each record's 7 days before, its days and its slots by hour; a record without them has null"
# Belt 3D is cut from the same answers: a lane each belt card and stuck card, a bay each of queued, waiting, held and
# landed today. Bug it catches: a held issue, an issue waiting on another, or what it waits on, missing from the floor.
q '.panels.belt3d.data | (.belt | map([.repo, .issue, .step, .landed, .url])) == [["sample", 801, "review", false, "'"$PU"'/801"], ["widgetshop", 5, "build", false, "'"$CU"'/5"]]
  and (.queue.next | map([.repo, .issue])) == [["sample", 20], ["widgetshop", 9]] and (.queue.held | map([.repo, .issue, .title])) == [["sample", 30, "Held one"]]
  and (.queue.waiting | map([.repo, .issue, .waitsFor, .url])) == [["sample", 32, [20], "'"$PU"'/32"]]
  and (.needs | map([.issue, .kind, .reason])) == [[12, "waiting", "Visible change: Staff see a new button."], [13, "blocked", "tests failed twice"]]
  and (.landed | map([.issue, .title, .usd])) == [[4, "CD fixed already", 0.5], [7, "Landed one", 2.5]]' \
  "Belt 3D has every record's belt, stuck cards, queued, held and waiting issues (with what each waits on) and landed cards"
# A stuck card's details: its review rounds with their verdicts and findings, and its cost.
q '.panels.belt3d.data.needs | map([.issue, .reviews, .usd]) == [[12, [], null], [13, [{round: 1, verdict: "NO-GO", counts: null}], 0.4]]' \
  "Belt 3D's stuck cards carry their review rounds and cost"
q '.panels.health.data.records[1] | .loop == false and (.unpushed | length) == 1 and .builderCap == 2' "a stopped loop and an unpushed landing reach the health part"
# The Board is the record on host.json's main (sample here), never another record's cards.
q '.panels.board.data | .repo == "sample" and .state == "paused" and .loop == true and .control.mode == "pause" and .cap == 3 and .guard.at == 90
  and .limit == {pct: 42, from: "loop"} and .modelSettings.builder.choices == ["claude-x"] and .issuesError == null and .reason == "the loop says why"' "the Board's bar: the loop's state and its reason, the control record, the cap, the guard with the loop's own reading, and the model settings"
q '.panels.board.data | [(.held | map([.issue, .url])), (.queue | map([.issue, .priority])), (.skipped | map([.issue, .rule]))]
  == [[[30, "'"$PU"'/30"]], [[20, "P1"]], [[31, "area:infra"]]]' "the Board's Held, Queue and skipped issues come from the record, in pick order, with their links"
q '.panels.board.data | [(.building | map(.issue)), (.review | map([.issue, .review, .of])), (.waiting | map([.issue, .sentence])), (.blocked | map([.issue, .reason])), (.landed | map([.issue, .usd, .reviews]))]
  == [[], [[801, 2, 3]], [[12, "Staff see a new button."]], [[13, "tests failed twice"]], [[7, 2.5, 2]]]' "the Board's Building, Review, Needs you and Landed today are this record's cards alone"
# Bug (#524): the snapshot's landed holds only the day's newest cards, so the Board's Today figure counted and priced
# those alone: it takes the whole day's count and cost from the snapshot (landedCount, landedUsd).
q '.panels.board.data.today == {landed: 1, usd: 41.5}' "the Board's Today figure is the snapshot's whole day, not its landed list"
# Bug: Control's blocked card had no track and no reviews, so it could not lead with the tests that failed or the
# NO-GO reviews (app.js failure()), as Needs you does from the same card.
q '.panels.board.data.blocked[0] | .track.records[0].failures.files[0].cases[0].name == "adds up" and (.reviews | map(.verdict)) == ["NO-GO"]' \
  "the Board's blocked card carries its track and reviews, to lead with why it failed"
# The Rules panel is the same record's rules and what they produce, with the snapshot's forecast as it is.
q '.panels.rules.data | .repo == "sample" and .control.rules.never == ["area:infra"] and .cap == 3 and .guard.at == 90 and .building == 1 and .issuesError == null
  and [(.held | map([.issue, .url])), (.queue | map(.issue)), (.skipped | map([.issue, .rule]))] == [[[30, "'"$PU"'/30"]], [20], [[31, "area:infra"]]]
  and .forecast == {cards: 1, usd: 0.95, perCard: {usd: 0.95, pct: 0.5}, guard: 90, reading: 42, pausesAt: null}' "the Rules part: the record's rules, its queue, held and skipped, the cards on the belt and the forecast"
# The landed cards not pushed and the full test suite (Push landed, Run full test suite: actions on the Control tab's
# Board, not rules), as the snapshot has them; none from a snapshot without them.
q '.panels.board.data | (.unpushed | map([.issue, .card, .url])) == [[7, "c5-7", "'"$PU"'/7"]] and .fullTest.command == true and .fullTest.last.state == "failed"
  and (.others.widgetshop.unpushed | map(.issue)) == [2] and .others.widgetshop.fullTest == null' "the Board part: the landed cards not pushed and the full test suite"
q '.panels.rules.data | has("unpushed") or has("fullTest") | not' "the Rules part carries neither: its tab has no Push landed or Run full test suite"
# The Rules tab has the loop's state (its tab's count), the models, the limit reading, the waits and every held
# issue with its labels and reasons, as the Board has them.
q '.panels.rules.data | .state == "paused" and .modelSettings.builder.choices == ["claude-x"] and .areaPrefix == "team/" and .limit == {pct: 42, from: "loop"} and (.waits | type) == "array"
  and (.open.held | map([.issue, .url, (.reasons | map(.label // .kind))])) == [[30, "'"$PU"'/30", ["you"]], [33, "'"$PU"'/33", ["backlog"]]]' "the Rules part: state, models, limit, waits and the held issues with why"
# Every open issue reaches the Board, each held one with its reasons and a link; a record without it gives null.
q '.panels.board.data.open | .count == 6 and .split == {queued: 2, you: 1, labelOrRule: 2, belt: 1} and (.held | map([.issue, .url, (.reasons | map(.label // .kind))])) == [[30, "'"$PU"'/30", ["you"]], [33, "'"$PU"'/33", ["backlog"]]]' "the Board has every open issue: the split and the held ones with why"
# Every record on the host is steered from the Board and the Rules tab: both parts name every record, and each record
# not on host.json's main has its own Board and Rules under others, its own cards and links, never main's. Bug: only
# main's record reached the page, so the second project's issues, queue and rules could not be seen or steered there.
q '.panels.board.data | .repos == ["sample", "widgetshop"] and (.others | keys) == ["widgetshop"]
  and (.others.widgetshop | .repo == "widgetshop" and (.building | map([.repo, .issue, .url])) == [["widgetshop", 5, "'"$CU"'/5"]] and (.landed | map(.issue)) == [4] and .waiting == [] and .blocked == [])' \
  "the Board names every record and carries the other record's own Board"
q '.panels.rules.data | .repos == ["sample", "widgetshop"] and .others.widgetshop.repo == "widgetshop" and .others.widgetshop.onBelt == [5]
  and .onBelt == [801] and (.blocked | map([.issue, .url])) == [[13, "'"$PU"'/13"]]' "the Rules part names every record, with each record's cards on the belt and blocked"
# The waiting list says where each issue a card waits on is: the step of each card on the belt reaches the Rules part.
# Bug: it said only "waiting on another card", never on which card nor how far that one had come.
q '.panels.rules.data | .beltSteps == [{issue: 801, step: "review", landed: false}] and .others.widgetshop.beltSteps == [{issue: 5, step: "build", landed: false}]' \
  "the Rules part has the step of each card on the belt"
q '[.panels.health.data.records[] | .state] == ["paused", null]' "each record's loop state (as its control record says) reaches the health part"
# #34 the control record holds and #35 a rule skips both depend on open #20, beside unheld #32: the snapshot's
# queue.waiting lists #32 alone, #34's held entry has its waitsFor, and open.held gives both waits (issue 383). Bug:
# a held issue with a Depends on line left the Held bay and showed under "Waiting on a card", as if queued; or, out of
# waiting, sat in Held with nothing saying what it waits on, or (the rule-skipped #35) was in no bay at all.
answer "$(jq -c '.queue.holding += [{issue: 34, title: "Held and waits", waitsFor: [20]}] | .queue.skipped += [{issue: 35, title: "Skipped and waits", rule: "area:infra"}]
  | .control.held += [34]
  | .open.held += [{issue: 34, title: "Held and waits", reasons: [{kind: "you"}, {kind: "waits", waitsFor: [20]}]}, {issue: 35, title: "Skipped and waits", reasons: [{kind: "rule", rule: "area:infra"}, {kind: "waits", waitsFor: [20]}]}]' <<<"$P")" \
  "$P_URL" 1794000000 "$C" "$C_URL" 0
run
q '.panels.queue.data.waiting | map([.issue, .waitsFor]) == [[32, [20]]]' "the Queue lists under waiting the snapshot's waiting issue alone; a held or skipped one with a Depends on line is not there"
q '.panels.belt3d.data.queue | (.waiting | map([.issue, .waitsFor])) == [[32, [20]]] and (.held | map([.issue, .waitsFor])) == [[30, []], [34, [20]], [35, [20]]]' \
  "Belt 3D keeps a held or rule-skipped issue with a Depends on line in Held with what it waits on, never under Waiting on a card"
q '.panels.rules.data.waits | map([.issue, .waitsFor]) == [[32, [20]], [34, [20]], [35, [20]]]' \
  "the Rules waiting list still has the held and the skipped issue that wait, which the snapshot's waiting leaves out"
) & started cards

# The collect of the cards above, which the machine's first checks read.
( fresh machine; cards_fixture
answer "$P" "$P_URL" 1794000000 "$C" "$C_URL" 0
run
# --- the machine's one Conveyor over both projects, each project on its own, and each Foreman ---
# Bug: two projects on one machine reached the page as two unrelated loops: nothing said the machine's cap, how many
# of its slots both hold together, or that the machine itself was paused; a project's pause could not be told from
# the machine's; and a Foreman, a group's or a project's, was nowhere in the data.
# The snapshots above are from before health named the machine: no machine cap is known, so the slots in force are
# both projects' own caps together (3 and 2), the slots in use are the cards on both belts, and the cost is both
# projects' together.
q '.panels.machine.data | .state == "running" and .cap == 5 and .used == 2 and .todayUsd == 4.25 and .repos == ["sample", "widgetshop"]' \
  "the machine: both projects' cards holding a slot, of both projects' caps, and both projects' cost today, summed"
q '.panels.machine.data.projects[0] | .repo == "sample" and .state == "paused" and .mode == "pause" and .reason == "the loop says why" and .cap == 3 and .guard == 90 and .used == 1
  and (.needs | map([.repo, .issue, .url])) == [["sample", 12, "'"$PU"'/12"], ["sample", 13, "'"$PU"'/13"], ["sample", 14, "'"$PU"'/14"]] and (.belt | map([.issue, .step])) == [[801, "review"]]
  and (.queue | map(.issue)) == [20] and (.held | map(.issue)) == [30] and (.waiting | map([.issue, .title])) == [[32, "Second half"]]
  and .order == [] and .rules.never == ["area:infra"]
  and .models == {builder: {model: "claude-x", effort: "medium"}, reviewer: null, judge: {on: true, model: "claude-j", effort: "high"}} and .landedToday == 1 and .todayUsd == 3.75' \
  "a project's section: its own state, cap, guard (the percent its paused-by-guard line names) and slots, its lists with its own links, its rules, its models and its judge"
q '.panels.machine.data.projects[1] | .repo == "widgetshop" and .state == null and .mode == null and .cap == 2 and .guard == null and .used == 1 and (.belt | map([.issue, .url])) == [[5, "'"$CU"'/5"]]
  and .queue == null and .held == null and .waiting == null and .order == null and .rules == null and .models == null and .todayUsd == 0.5' \
  "the other project is its own section: a list or record its snapshot does not give is null, never the first project's and never empty"
q '.panels.belt.data | .cap == 5 and .byRepo == {sample: {cap: 3}, widgetshop: {cap: 2}}' "the belt carries each project's own cap beside the sum, for the page filtered to one project"
q '.panels.queue.data.byRepo == {sample: {held: 2}, widgetshop: {held: 1}}' "the queue carries each project's own held count beside the sum"
# The host file here names no Foreman group and no state folder holds a mark: each project has its own Foreman line,
# and each says no session holds the role.
q '.panels.machine.data | .foremenError == null and (.foremen | map([.projects, .group, .held, .since, .lastWakeAt, .waiting]))
  == [[["sample"], false, false, null, null, []], [["widgetshop"], false, false, null, null, []]]' "a project with no Foreman has a line that says so"
# The machine's settings, as every record's health names them: the cap, and the slots both projects hold of it. A card
# that landed and waits for its push holds no slot. One project paused by its own record leaves the other, and the
# machine, running.
MC='{"cap": 10, "maxLoad": null, "minFreeMemMB": null, "paused": false}'
C3=$(jq -c '.belt += [.belt[0] + {card: "c4-6", issue: 6}, .belt[0] + {card: "c4-8", issue: 8}] | .health.state = "running" | .health.loop = true | .control = {mode: "run", order: [9]}' <<<"$C")
with_machine() { jq -c --argjson m "$1" '.health.machine = $m' <<<"$2"; } # <machine> <snapshot>
PUSHING='[{"card": "c0-98", "issue": 98, "title": "Landed, being pushed", "step": "push", "stepAt": "'"$(ago 60)"'", "landed": true, "usd": 1, "reading": true}]'
# The machine's load limit is 20 here, and its 16 cores are at a load of 31.5 (#462).
ML=$(jq -c '.maxLoad = 20' <<<"$MC")
answer "$(with_machine "$ML" "$(jq -c --argjson l "$PUSHING" '.belt += $l | .health.machineNow = {cores: 16, load: 31.5} | .tests = {files: [{file: "a.test.sh", cpu: 3, runs: [{cpu: 3, card: "c5-12"}, {cpu: 2, card: "odd"}],
    optimize: [{issue: 70, time: "2026-11-01T00:00:00Z", state: "landed", sha: "abc1234", fix: "sped up", into: [], before: 10, after: 4, since: 3.5, sinceRuns: 2},
      {issue: 71, state: "open"}, {issue: 72, state: "open"}]}]} | .open.issues = [{issue: 71}]
  | .testActions = {limit: 900, actions: [{id: "0123456789ab", action: "judge", file: "a.test.sh", state: "running", text: "first words"}], allowed: {claude: ["m1", "m2"]}}
  | .control.tests = {cli: "claude", model: "m1", effort: "high"}
  | .modelSettings = {judge: {clis: {claude: {models: ["m1"], efforts: ["high"]}}}}' <<<"$P")")" "$P_URL" 1794000000 "$(with_machine "$ML" "$C3")" "$C_URL" 0
run
# Bug (#462): the Board could not show the machine's load limit, nor its cores and load beside it. They are the
# machine's: the same in every project's Tests part (Load limit is on the Tests page, #520), read from whichever
# record's health names them. Each project's Tests part holds its own snapshot's test files, never another's; each run
# links to its card's issue (the number that ends the card id), and a card id with no number links nowhere.
q '.panels.tests.data | .machine == {maxLoad: 20, unread: false, cores: 16, load: 31.5} and .others.widgetshop.machine == .machine
  and (.tests.files | map([.file, .cpu])) == [["a.test.sh", 3]] and .others.widgetshop.tests == null
  and (.tests.files[0].runs | map([.card, .issue, .url])) == [["c5-12", 12, "'"$PU"'/12"], ["odd", null, null]]' \
  "the Tests part names the machine's load limit, cores and load, the same for every project, and each project's own test files, each run with its card's link"
# Bug (#74): a file's Optimize issues reached the Tests page with no link. Each keeps its state and the proof's before
# and after CPU s, and gets its issue's url. And one no card took, closed on GitHub (#72 is not among the open issues:
# the Board's Close its issue as done), still showed as open.
q '.panels.tests.data.tests.files[0].optimize | map([.issue, .state, .sha, .before, .after, .url])
  == [[70, "landed", "abc1234", 10, 4, "'"$PU"'/70"], [71, "open", null, null, null, "'"$PU"'/71"], [72, "closed", null, null, null, "'"$PU"'/72"]]' \
  "the Tests part names a file's landed Optimize issue, its state, commit, before and after CPU s, with its issue's link, and a closed one as closed"
# Bug (#521): the Tests page's actions had no action, text, Tests model, CLI or flaky case to show. Each project's own reach it.
# Bug (#594): nor the pack's models by CLI, so a CLI that lists none (Claude Code) offered no model.
q '.panels.tests.data | (.testActions.actions | map([.id, .text])) == [["0123456789ab", "first words"]] and .testActions.limit == 900
  and .testActions.allowed == {claude: ["m1", "m2"]}
  and .control.tests == {cli: "claude", model: "m1", effort: "high"} and .clis == {claude: {models: ["m1"], efforts: ["high"]}}
  and (.flaky | map(.case)) == ["b.test: flaky", "c.test: other"] and .others.widgetshop.testActions == null and .others.widgetshop.clis == null' \
  "the Tests part holds its project's test actions with their text, the host's CLIs and the flaky cases"
q '.panels.rules.data | has("machine") | not' "the Rules part no longer carries the load limit: the Tests page has it"
q '.panels.machine.data | .state == "running" and .cap == 5 and .used == 4 and (.projects | map([.repo, .state, .mode, .used, .cap])) == [["sample", "paused", "pause", 1, 3], ["widgetshop", "running", "run", 3, 2]]' \
  "one machine head: 4 of 5, the slots of both projects (3 and 2) under the machine's 10; sample's own pause leaves widgetshop and the machine running"
q '.panels.machine.data.projects[1].order == [9]' "a project's pinned order is its own record's"
# Issue 413: one slots figure on the page. The machine bar, the head's "On the belt" tile (the Belt part) and Belt
# 3D's deck all read 4 of 5: the cards holding a slot (the landed card being pushed holds none) of the slots in force.
# The bug: the machine bar said 4 of 10 (the machine cap, which the projects' own 3 and 2 never reach) beside 4 of 5.
q '[(.panels.belt3d.data.deck | [.used, .cap]), (.panels.machine.data | [.used, .cap]),
    (.panels.belt.data | [([.cards[] | select(.landed != true)] | length), .cap])] == [[4, 5], [4, 5], [4, 5]]' \
  "the machine bar, the On the belt tile and Belt 3D's deck give one slots figure"
# Bug: a judge turned off read as no judge setting at all (`false // null` is null), and the project list said
# "judge not read" where the owner had said off. Off is off, whatever model the judge's settings still name.
CJ=$(jq -c '.control.judgeOn = false | .modelSettings = {judge: {model: "claude-j", effort: "high"}}' <<<"$C3")
answer "$P" "$P_URL" 1794000000 "$CJ" "$C_URL" 0
run
q '.panels.machine.data.projects[1].models.judge == {on: false}' "a project whose judge is off says off, never not read"
# The whole machine paused (the host file's mode): the machine says so; no project's own state is rewritten.
# Its cap is 4 here, under the projects' 3 and 2: the slots in force are the machine's 4, everywhere on the page.
MP=$(jq -c '.paused = true | .cap = 4' <<<"$MC")
answer "$(with_machine "$MP" "$P")" "$P_URL" 1794000000 "$(with_machine "$MP" "$C3")" "$C_URL" 0
run
q '.panels.machine.data | .state == "paused" and (.projects | map(.state)) == ["paused", "running"]' "a paused machine is paused; each project's state stays its own record's"
q '[.panels.machine.data.cap, .panels.belt.data.cap, .panels.belt3d.data.deck.cap] == [4, 4, 4]' "a machine cap under the projects' own caps together is the slots in force, the same in every part"
# Belt 3D's deck reads out the machine's state as the machine part has it (its LOOP readout) (issue 393): a deck that
# said LIVE on a paused machine would lie.
q '.panels.belt3d.data.deck | {host, state} == {host: "devbox", state: "paused"}' "Belt 3D's deck: the paused machine"
answer "$(with_machine '{"unread": true}' "$P")" "$P_URL" 1794000000 "$(with_machine '{"unread": true}' "$C3")" "$C_URL" 0
run
q '.panels.machine.data | .state == "not read" and .cap == 5' "a host file the host cannot read: the machine's state is not read, never running; the projects' own caps still hold"
q '.panels.tests.data.machine == {maxLoad: null, unread: true, cores: null, load: null}' "a host file the host cannot read: its load limit is not read, never shown as Off"
q '.panels.belt3d.data.deck | {host, state} == {host: "devbox", state: "not read"}' "Belt 3D's deck: the state not read"
answer "$(jq -c '.health.loop = false' <<<"$P")" "$P_URL" 1794000000 "$C" "$C_URL" 0
run
q '.panels.machine.data.state == "stopped"' "no project's loop running: the machine is stopped"
q '.panels.belt3d.data.deck.state == "stopped"' "Belt 3D's deck: no loop running is stopped"
# Metrics side by side: each project's 7 days, then the machine's. Its time to land is the median over both
# projects' landed cards (100, 300, 500: 300), never the mean of the two medians (200, 500: 350); a blocked card
# has none.
PM=$(jq -c '.metrics.week = {landed: 2, leadSec: {p50: 200, p90: 300}} | .metrics.cards = [{card: "c5-1", issue: 1, state: "landed", metrics: {leadSec: 100}}, {card: "c5-2", issue: 2, state: "landed", metrics: {leadSec: 300}}]' <<<"$P")
CM=$(jq -c '.metrics = {week: {landed: 1, leadSec: {p50: 500, p90: 500}}, cards: [{card: "c6-1", issue: 1, state: "landed", metrics: {leadSec: 500}}, {card: "c6-2", issue: 2, state: "blocked", metrics: {leadSec: null}}]}' <<<"$C")
answer "$PM" "$P_URL" 1794000000 "$CM" "$C_URL" 0
run
q '.panels.metrics.data.compare == {projects: [{repo: "sample", landed: 2, leadSec: 200, usd: 10, usdLeftOut: 0}, {repo: "widgetshop", landed: 1, leadSec: 500, usd: 4, usdLeftOut: 0}], machine: {landed: 3, leadSec: 300, usd: 14, usdLeftOut: 0}}' \
  "metrics: each project and the machine side by side, the machine's time to land over every landed card"
answer "$PM" "$P_URL" 1794000000 "$(jq -c '.cost.week = null' <<<"$C")" "$C_URL" 0
run
q '.panels.metrics.data.compare.machine == {landed: null, leadSec: null, usd: null, usdLeftOut: 0}' "a project that measured nothing, or has an unpriced week, leaves the machine's figure unknown, never the sum of the rest"
# Bug: the machine's median left out a card whose issue was already fixed (closed), which each project's own median
# counts as landed: one project with a landed card (100) and a closed one (300) said 200 for the project and 100 for
# the machine. A card closed while it was blocked landed nothing: it has no time to land, and counts in neither.
PC=$(jq -c '.metrics.week = {landed: 2, leadSec: {p50: 200, p90: 300}} | .metrics.cards = [{card: "c5-1", issue: 1, state: "landed", metrics: {leadSec: 100}}, {card: "c5-2", issue: 2, state: "closed", metrics: {leadSec: 300}},
  {card: "c5-3", issue: 3, state: "closed", metrics: {leadSec: null}}]' <<<"$P")
answer "$PC" "$P_URL" 1794000000 "$(jq -c '.metrics = {week: {landed: 0, leadSec: null}, cards: []}' <<<"$C")" "$C_URL" 0
run
q '.panels.metrics.data.compare | .projects[0].leadSec == 200 and .machine.leadSec == 200' "the machine's time to land counts an already-fixed card, as the project's own median does"
# Bug: the side-by-side cost and a project section's cost today gave the priced steps' dollars as if they were the
# whole: the steps each leaves out for having no price were dropped, so $5.00 hid an unpriced step.
answer "$(jq -c '.cost += {todayLeftOut: 2, weekLeftOut: 3}' <<<"$P")" "$P_URL" 1794000000 "$(jq -c '.cost += {todayLeftOut: 0, weekLeftOut: 1}' <<<"$C")" "$C_URL" 0
run
q '.panels.metrics.data.compare | (.projects | map(.usdLeftOut)) == [3, 1] and .machine.usdLeftOut == 4' "the side-by-side cost of each project and of the machine names the steps it leaves out"
q '.panels.machine.data.projects | map(.todayLeftOut) == [2, 0]' "a project section's cost today names the steps it leaves out"
# Bug: Cost filtered to one project had nothing but the sums of every project to show: each project's own figures
# come beside them.
q '.panels.cost.data.cards.byRepo == {sample: {todayUsd: 3.75, weekUsd: 10, perLandedUsd: 2.5, landedAfter: {"1": 0, "2": 1, "3": 0, more: 0}, unpricedSteps: 0, todayLeftOut: 2, weekLeftOut: 3, perLandedLeftOut: 0},
  widgetshop: {todayUsd: 0.5, weekUsd: 4, perLandedUsd: 0.5, landedAfter: {"1": 3, "2": 0, "3": 0, more: 0}, unpricedSteps: 1, todayLeftOut: 0, weekLeftOut: 1, perLandedLeftOut: 0}}' \
  "cost carries each project's own figures beside the sums, for the page filtered to one project"
# Bug: a project's section counted only its blocked and waiting cards as Needs you: an issue waiting for the owner's
# yes before its build was left out, so the section said "Needs you (0)" while the Needs you panel listed it.
answer "$P" "$P_URL" 1794000000 "$(jq -c '.needsYou.before = [{issue: 40, title: "New price list", section: "Customers see new prices.", since: "2026-11-12T08:00:00Z"}]' <<<"$C")" "$C_URL" 0
run
q '.panels.machine.data.projects[1].needs | map([.repo, .card, .issue, .title, .url]) == [["widgetshop", null, 40, "New price list", "'"$CU"'/40"]]' "a project's Needs you has its issues waiting for the yes before their build"
# Bug: a follow-up filed held because it changes a pipeline file was in no list the owner reads: held, and never seen.
answer "$P" "$P_URL" 1794000000 "$(jq -c '.needsYou.pipeline = [{issue: 41, title: "[P1] conveyor/conveyor.sh:9 a slow gate", cost: "not assessed", parent: 30, since: "2026-11-12T08:00:00Z"}]' <<<"$C")" "$C_URL" 0
run
q '.panels.needs.data.cards.pipeline | map([.repo, .issue, .cost, .parent, .url]) == [["widgetshop", 41, "not assessed", 30, "'"$CU"'/41"]]' "a held pipeline follow-up is in Needs you with its repo, its cost line, its parent and its link"
q '.panels.machine.data.projects[1].needs | map([.repo, .issue]) == [["widgetshop", 41]]' "a project's Needs you counts its held pipeline follow-ups"
# Bug (#617): the page and the Foreman watcher kept two lists of the kinds of Needs you. The page is sent the one list
# (dashboard_needs.json) and each kind's entries, read from the snapshot field the list names.
q '.panels.needs.data | .kinds == '"$(jq -c . "$SOURCE/.claude/scripts/dashboard_needs.json")"' and (.entries.pipeline | map([.repo, .issue, .title, .url]))
  == [["widgetshop", 41, "[P1] conveyor/conveyor.sh:9 a slow gate", "'"$CU"'/41"]] and .entries.farDeps == []' "Needs you is sent the shared list of its kinds and each kind's entries"
# Bug (issue 605): an issue waiting on another repository's issue that gh cannot read was in no list the owner reads.
answer "$P" "$P_URL" 1794000000 "$(jq -c '.needsYou.farDeps = [{issue: 42, title: "Use the new tool", ref: "other/repo#600", line: "Depends on: other/repo#600", reason: "no access"}]' <<<"$C")" "$C_URL" 0
run
q '.panels.needs.data.cards.farDeps | map([.repo, .issue, .ref, .line, .reason, .url]) == [["widgetshop", 42, "other/repo#600", "Depends on: other/repo#600", "no access", "'"$CU"'/42"]]' "a dependency that cannot be read is in Needs you with its line and why"
q '.panels.machine.data.projects[1].needs | map([.repo, .issue]) == [["widgetshop", 42]]' "a project's Needs you counts its dependencies that cannot be read"
# The Foremen, read from this machine's state folders. A group of the host file's foreman.groups is one Foreman, in
# its first project's folder (the host file's stateDir for the host's own checkout): shown once with both projects,
# with when its session claimed the role, when it was last woken and the wakes still owed to it.
cp "$MAIN/conveyor/host.json" "$T/host.before"
FM=$T/fstate/foreman; mkdir -p "$FM/pending"
echo 'sess-1 2026-11-12T08:00:00Z' > "$FM/session"
printf 'Conveyor: sample: blocked: #13\n#13 is blocked since then\n' > "$FM/last-wake.txt"; touch -d '2026-11-12T09:30:00Z' "$FM/last-wake.txt"
printf 'Conveyor: widgetshop: needs the owner'"'"'s yes: #5\n#5 needs it\n' > "$FM/pending/20261112T100000Z-1-a.wake"
printf 'Limit: 91%% of the week used\n' > "$FM/pending/20261112T100100Z-1-b.wake"; : > "$FM/pending/.put.half"
# Issue 139: the plugin problems it noted (conveyor/foreman/stop.sh, one "- " line each under a heading) are counted,
# with the file, and Health has them. Bug it catches: a noted plugin problem the Board never showed.
printf '# Plugin problems\n\n- 2026-11-12T09:00:00Z · card #13 · a · evidence: -\n- 2026-11-12T09:10:00Z · card - · b · evidence: -\n' > "$FM/plugin-bugs.md"
jq --arg s "$T/fstate" '.stateDir = $s | .foreman = {groups: [["sample", "widgetshop", "gone"]]}' "$T/host.before" > "$MAIN/conveyor/host.json"
answer "$P" "$P_URL" 1794000000 "$C" "$C_URL" 0
run
q '.panels.machine.data.foremen == [{projects: ["sample", "widgetshop"], group: true, held: true, since: "2026-11-12T08:00:00Z", lastWakeAt: "2026-11-12T09:30:00Z",
  waiting: ["Conveyor: widgetshop: needs the owner'"'"'s yes: #5", "Limit: 91% of the week used"], pluginBugs: 2, pluginBugsFile: "'"$FM"'/plugin-bugs.md",
  pluginBugsUrl: "plugin-bugs/sample.txt"}]' "a grouped Foreman is one line with both its projects (a name no record has passed over), its claim, its last wake, what waits on it and the plugin problems it noted"
# Bug it catches: the notes were under the first project alone, so picking widgetshop (the project filter keeps the
# rows whose repo it names) hid its Foreman's notes. Each project of the group has them.
q '.panels.health.data.pluginBugs | map(.repo) == ["sample", "widgetshop"] and all(.projects == ["sample", "widgetshop"] and .count == 2
  and .file == "'"$FM"'/plugin-bugs.md" and .url == "plugin-bugs/sample.txt")' "Health has the plugin problems the Foreman noted, under each of its projects, with the Board's copy"
# Bug it catches: the link was file://, which a browser does not open from the https Board; the copy is served beside the page.
cmp -s "$FM/plugin-bugs.md" "$OUT/plugin-bugs/sample.txt" || fail "the Board's folder has a copy of the notes, which the page links to"
rm -f "$FM/plugin-bugs.md"
# No group: the same folder is sample's own Foreman, and widgetshop has none. A mark emptied (the role turned off)
# is no Foreman either. Groups that name a project twice are not understood: each project has its own.
jq --arg s "$T/fstate" '.stateDir = $s' "$T/host.before" > "$MAIN/conveyor/host.json"
run
q '.panels.machine.data.foremen | map([.projects, .group, .held]) == [[["sample"], false, true], [["widgetshop"], false, false]]' "each project its own Foreman: one holds the role, the other has none"
[ ! -e "$OUT/plugin-bugs" ] || fail "notes that are gone leave no copy in the Board's folder"
# Bug: the host file's own checkout was told by its main as written, while the engine follows links: a record that
# names that checkout through a link keeps its Foreman in the stateDir, and the page read the link's conveyor/state
# and said the project has no Foreman.
mkdir -p "$T/real-main"; ln -s "$T/real-main" "$T/link-main"
jq --arg s "$T/fstate" --arg m "$T/real-main" --arg l "$T/link-main" '.stateDir = $s | .main = $m | .records[0].main = $l' "$T/host.before" > "$MAIN/conveyor/host.json"
run
q '.panels.machine.data.foremen | map([.projects, .held, .since]) == [[["sample"], true, "2026-11-12T08:00:00Z"], [["widgetshop"], false, null]]' "a record that names the host file's own checkout through a link has its Foreman read from the stateDir"
: > "$FM/session"
jq --arg s "$T/fstate" '.stateDir = $s | .foreman = {groups: [["sample", "widgetshop"], ["widgetshop"]]}' "$T/host.before" > "$MAIN/conveyor/host.json"
run
q '.panels.machine.data.foremen | map([.projects, .held, .since]) == [[["sample"], false, null], [["widgetshop"], false, null]]' "a mark turned off is no Foreman; groups naming a project twice group nothing"
# Bug (issue 454): with the belt on an ssh host, a record's main is the host's path, not on this machine; the Foreman
# runs here in a checkout whose origin is that repository and marks its claim there, and the page read only under
# main and said "No Foreman". sample's checkout holds its ledger and is found by it; widgetshop's lies beside the
# Board's own checkout.
here() { git init -q -b main "$1" && git -C "$1" remote add origin "$2" && mkdir -p "$1/conveyor/state/foreman" && echo "$3" > "$1/conveyor/state/foreman/session"; }
here "$T/away/sample-here" "https://$GH/example/sample.git" 'sess-s 2026-11-12T07:00:00Z'
mkdir -p "$T/away/sample-here/.claude/metrics"; : > "$T/away/sample-here/.claude/metrics/decisions.jsonl"
here "$T/widgetshop-here" "https://$GH/example/widgetshop" 'sess-w 2026-11-12T06:00:00Z'
jq --arg s "$T/fstate" --arg l "$T/away/sample-here/.claude/metrics/decisions.jsonl" '.stateDir = $s | .records[0].ledger = $l' "$T/host.before" > "$MAIN/conveyor/host.json"
run
q '.panels.machine.data.foremen | map([.projects, .held, .since]) == [[["sample"], true, "2026-11-12T07:00:00Z"], [["widgetshop"], true, "2026-11-12T06:00:00Z"]]' "with ssh and a main not on this machine, the Foreman is read from the checkout here whose origin is that repository"
# Without ssh the folder is read under main as before, even when a checkout here has the repository as its origin.
# With no ssh target Conveyor is read on this machine, where /srv/main is no checkout, so it gives no snapshot (the
# machine panel is null) and the cycle's kept Foremen part is read.
mkdir -p "$T/wmain/conveyor/state/foreman"; echo 'sess-m 2026-11-12T04:00:00Z' > "$T/wmain/conveyor/state/foreman/session"
jq --arg l "$T/away/sample-here/.claude/metrics/decisions.jsonl" --arg w "$T/wmain" 'del(.ssh) | .records[0].ledger = $l | .records[1].main = $w' "$T/host.before" > "$MAIN/conveyor/host.json"
run
jq -e '.foremen | map([.projects, .held, .since]) == [[["sample"], false, null], [["widgetshop"], true, "2026-11-12T04:00:00Z"]]' "$OUT/cache/part-foremen.json" >/dev/null \
  || fail "without ssh the Foreman is read under the record's main, never from a checkout matched by its origin ($(cat "$OUT/cache/part-foremen.json"))"
rm -rf "$T/widgetshop-here" # beside the Board's checkout, it would be widgetshop's Foreman in every later read
cp "$T/host.before" "$MAIN/conveyor/host.json"
answer "$P" "$P_URL" 1794000000 "$C" "$C_URL" 0
run
# A card that landed on an earlier day and is still on the belt (its push fails) stays on the Board, in Building
# with its Push step and why; a card that landed today and is being pushed is in Landed today alone.
L='[{"card": "c0-99", "issue": 99, "title": "Landed yesterday", "step": "push", "stepAt": "'"$(ago 90000)"'", "landed": true, "usd": 1, "reading": true, "track": {"reason": "the pre-push hook failed"}},
  {"card": "c'"$TODAY"'T080000-7", "issue": 7, "title": "Landed one", "step": "push", "stepAt": "'"$(ago 60)"'", "landed": true, "usd": 2.5, "reading": true}]'
answer "$(jq -c --argjson l "$L" '.belt += $l' <<<"$P")" "$P_URL" 1794000000 "$C" "$C_URL" 0
run
q '.panels.board.data | (.building | map([.issue, .step, .reason])) == [[99, "push", "the pre-push hook failed"]] and (.landed | map(.issue)) == [7]' "a card landed on an earlier day whose push fails is in Building; one landed today is in Landed today alone"
q '.panels.board.data | has("checkRuns") | not' "a record whose pack names no checks.progress sends no check run"
# Bug (issue 407): a landed card whose push failed and was tried again showed on the belt and in Landed today at once,
# while Needs you said only "Nothing needs you" beside Health's red "Failing". Needs you now lists each such card with
# the fix card building for it (a belt card whose parent it is), and the belt leaves out the one Landed today shows.
PF='{"steps": [{"name": "Build", "state": "done"}, {"name": "Review", "state": "done"}, {"name": "Fix", "state": "skipped"}, {"name": "Test", "state": "done"}, {"name": "Land", "state": "done"}, {"name": "Push", "state": "failed"}], "reason": "the pre-push hook failed"}'
L='[{"card": "c0-99", "issue": 99, "title": "Landed yesterday", "step": "push", "stepAt": "'"$(ago 90000)"'", "landed": true, "usd": 1, "reading": true, "track": '"$PF"'},
  {"card": "c'"$TODAY"'T080000-7", "issue": 7, "title": "Landed one", "step": "push", "stepAt": "'"$(ago 60)"'", "landed": true, "usd": 2.5, "reading": true, "track": '"$PF"'},
  {"card": "c0-62", "issue": 62, "title": "Fix the hook", "parent": 7, "step": "build", "stepAt": "'"$(ago 60)"'", "landed": false, "usd": 1, "reading": true},
  {"card": "c'"$TODAY"'T090000-8", "issue": 8, "title": "Pushed, issue open", "step": "push", "stepAt": "'"$(ago 60)"'", "landed": true, "usd": 1, "reading": true, "track": '"$(jq -c '.reason = "GitHub did not close the issue: HTTP 502"' <<<"$PF")"'}]'
answer "$(jq -c --argjson l "$L" '.belt += $l' <<<"$P")" "$P_URL" 1794000000 "$C" "$C_URL" 0
run
q '.panels.needs.data.retrying | map([.repo, .issue, .fix]) == [["sample", 99, null], ["sample", 7, 62]]' "each landed card whose push failed is in Needs you's retrying, with the fix card building for it"
# Bug: a card whose push of main succeeded but whose issue GitHub did not close (track.jq marks its Push step failed)
# was called a push failing and being retried, and left the belt.
q '(.panels.needs.data.retrying | map(.issue) | index(8) == null) and (.panels.belt.data.cards | map(.issue) | index(8) != null)' "a card whose issue GitHub did not close is no failing push: not in retrying, still on the belt"
q '(.panels.belt.data.cards | map(.issue) | (index(7) == null and index(99) != null and index(62) != null)) and (.panels.landed.data.cards | map(.issue) | index(7) != null)' "a card that landed today and whose push failed is in Landed today and not on the belt; one landed earlier stays on the belt"
# Belt 3D's lane of a card in Test shows its test run's progress, and its details the steps' times and the turns of
# the step: the track's steps, at, since, tests and files and the live record's turns reach it.
# Issue 423: its records' names and times too (and nothing else of them), so its lane shows it went back a step.
T3='{"steps": [{"name": "Build", "state": "done", "sec": 30}], "at": 3, "since": "'"$(ago 120)"'", "label": "tests", "tests": {"done": 142, "of": 205, "failed": 0}, "files": {"run": 1, "of": 2}, "detail": [],
  "records": [{"name": "review 1 (NO-GO)", "state": "done", "sec": 60, "at": "'"$(ago 600)"'", "output": "a long review"}, {"name": "tests", "state": "now", "sec": null}]}'
answer "$(jq -c --argjson t "$T3" '.belt[0] += {track: $t, live: {turns: 7, lastOutputAt: null}}' <<<"$P")" "$P_URL" 1794000000 "$C" "$C_URL" 0
run
q '.panels.belt3d.data.belt | .[0] | .turns == 7 and .track == ('"$T3"' | del(.label, .detail) | .records |= map({name, at: (.at // null)}))' "Belt 3D's belt card carries its track's steps, step, tests, files and records' times, and its turns"
# Bug: a landed card's details showed six steps done with no times; its track (a skipped Fix, a push still to go) and
# the steps' times reach Belt 3D.
answer "$(jq -c --argjson t "$T3" '.landed[0] += {track: $t}' <<<"$P")" "$P_URL" 1794000000 "$C" "$C_URL" 0
run
q '.panels.belt3d.data.landed | map(select(.issue == 7)) | .[0].track ==('"$T3"' | del(.label, .detail, .records))' "Belt 3D's landed card carries its track"
# Cards that landed in one batch reach the Board with their batch, so its Landed today shows them as one landing.
B='["c'"$TODAY"'T080000-7", "c'"$TODAY"'T080500-8"]'
answer "$(jq -c --argjson b "$B" '.landed |= (map(. + {batch: $b}) + [.[0] + {card: $b[1], issue: 8, title: "Batch mate", batch: $b}])' <<<"$P")" "$P_URL" 1794000000 "$C" "$C_URL" 0
run
q '.panels.board.data.landed | map([.issue, .batch]) == [[7, '"$B"'], [8, '"$B"']]' "the Board's Landed today carries each card's batch, the cards it landed with"
q '.panels.board.data.others.widgetshop.landed | map(.batch) == [null]' "a card that landed alone has no batch on the Board"
# A card waiting on a same-file card is in Building with the card it waits on and where that card is, never in Review.
PICKED=$(ago 3600)
L='[{"card": "c0-56", "issue": 56, "title": "Waits", "step": "waiting", "waitsOn": {"card": "c0-55", "issue": 55, "state": "queued"}, "stepAt": "'"$(ago 60)"'", "pickedAt": "'"$PICKED"'", "landed": false, "usd": 1, "reading": true}]'
answer "$(jq -c --argjson l "$L" '.belt += $l' <<<"$P")" "$P_URL" 1794000000 "$C" "$C_URL" 0
run
q '.panels.board.data | (.building | map([.issue, .step, .waitsOn.issue, .waitsOn.state])) == [[56, "waiting", 55, "queued"]] and (.review | map(.issue)) == [801]' "a waiting card is in Building with the card it waits on and that card's state"
# Time in Building is from the card's pick-up, not the start of its step: the Board sorts that column by it.
q '.panels.board.data.building[0] | .pickedAt == "'"$PICKED"'" and .stepAt != .pickedAt' "a card in Building carries its pick-up time"
# A card that gave up its land turn is in Building with the issue it gave way to, so the Board can say so.
L='[{"card": "c0-9", "issue": 9, "title": "Fits", "step": "fix", "waitsOn": null, "gaveWay": 92, "gaveWayFixing": true, "beyond": "main is red", "stepAt": "'"$(ago 60)"'", "pickedAt": "'"$PICKED"'", "landed": false, "usd": 1, "reading": true},
  {"card": "c0-10", "issue": 10, "title": "Fitted", "step": "review", "review": 2, "of": 3, "waitsOn": null, "gaveWay": 92, "stepAt": "'"$(ago 60)"'", "pickedAt": "'"$PICKED"'", "landed": false, "usd": 1, "reading": true}]'
answer "$(jq -c --argjson l "$L" '.belt += $l' <<<"$P")" "$P_URL" 1794000000 "$C" "$C_URL" 0
run
q '.panels.board.data | (.building | map([.issue, .step, .gaveWay])) == [[9, "fix", 92]] and (.review | map(select(.issue == 10) | .gaveWay)) == [92]' "a card that gave way is in Building or Review with the issue it gave way to"
q '.panels.board.data | (.building | map(.gaveWayFixing)) == [true] and (.review | map(select(.issue == 10) | .gaveWayFixing)) == [false]' "a card that gave way for the fix of its failed tests says so, and one that gave way for another reason does not"
# Issue 612: a main-red fix in a slot beyond the cap carries why, so the Board can say so; a card in its slot has none.
q '.panels.board.data | (.building | map(.beyond)) == ["main is red"] and (.review | map(select(.issue == 10) | .beyond)) == [null]' "a card in a slot beyond the cap carries why on the Board, and one in its slot does not"
# Bug: Stop now's label counted every card in Building and Review as requeued, while the engine's stop (halt() in
# conveyor/lib/run.sh) leaves running one filing its follow-ups (its last line starts file), one landing (starts
# land) and one that has filed them; the Board dropped the fields that say so. Each card carries stays.
F='{"name": "follow-ups filed", "state": "done", "sec": 3, "n": 1}'
L='[{"card": "c0-11", "issue": 11, "title": "Filing", "step": "tests", "done": {"step": "file"}, "stepAt": "'"$(ago 60)"'", "landed": false, "usd": 1, "reading": true},
  {"card": "c0-12", "issue": 12, "title": "Landing", "step": "landing", "done": {"step": "land"}, "stepAt": "'"$(ago 60)"'", "landed": false, "usd": 1, "reading": true},
  {"card": "c0-13", "issue": 13, "title": "Filed", "step": "review", "review": 1, "of": 3, "done": {"step": "test"}, "track": {"detail": ['"$F"']}, "stepAt": "'"$(ago 60)"'", "landed": false, "usd": 1, "reading": true},
  {"card": "c0-14", "issue": 14, "title": "Testing", "step": "tests", "done": {"step": "test"}, "track": {"detail": [{"name": "follow-ups filed", "state": "todo", "sec": null}]}, "stepAt": "'"$(ago 60)"'", "landed": false, "usd": 1, "reading": true},
  {"card": "c0-99", "issue": 99, "title": "Landed yesterday", "step": "push", "stepAt": "'"$(ago 90000)"'", "landed": true, "usd": 1, "reading": true}]'
answer "$(jq -c --argjson l "$L" '.belt += $l' <<<"$P")" "$P_URL" 1794000000 "$C" "$C_URL" 0
run
q '.panels.board.data | ([.building[], .review[]] | map(select(.issue | IN(11, 12, 13, 14, 99)) | [.issue, .stays]) | sort) == [[11, true], [12, true], [13, true], [14, false], [99, true]]
  and ([.building[], .review[]] | map(select(.issue | IN(11, 12, 13, 14, 99) | not) | .stays) | all(. == false))' "a card Stop now leaves running (filing, landing, filed its follow-ups, landed) is marked stays; one it ends is not"
# A long check run (the pack's checks.progress) shows on the Board as the snapshot gives it, or the Board looks idle
# while the run holds the loop paused.
CR='{"name":"nightly","sha":"0123456789ab","started":"'"$(ago 600)"'","ended":null,"result":null,"counts":{"passed":3,"failed":1,"running":2,"queued":4,"reused":0},"done":4,"all":10,"leftSec":225,
  "lanes":[{"name":"broken-0","state":"failed","started":null,"sec":120},{"name":"busy-0","state":"running","started":"'"$(ago 30)"'","sec":null},{"name":"busy-1","state":"running","started":"'"$(ago 30)"'","sec":null}]}'
answer "$(jq -c --argjson c "$CR" '.checkRun = $c' <<<"$P")" "$P_URL" 1794000000 "$C" "$C_URL" 0
run
q '.panels.board.data.checkRuns | length == 1 and (.[0] | .repo == "sample" and .name == "nightly" and .counts == {passed: 3, failed: 1, running: 2, queued: 4, reused: 0} and .done == 4 and .all == 10 and .leftSec == 225
  and ([.lanes[] | select(.state == "failed") | .name] == ["broken-0"]) and ([.lanes[] | select(.state == "running")] | length) == 2)' "the Board has the check run: its counts, its failed lane and its running lanes"
# A record the Board does not steer runs checks too: its run is on the Board, named by its repo.
answer "$P" "$P_URL" 1794000000 "$(jq -c --argjson c "$CR" '.checkRun = $c' <<<"$C")" "$C_URL" 0
run
q '.panels.board.data | .repo == "sample" and (.checkRuns | map([.repo, .name, .done])) == [["widgetshop", "nightly", 4]]' "the check run of a record the Board does not steer reaches the Board"
# No record is on host.json's main: the Board steers nothing, and the run still reaches it.
cp "$MAIN/conveyor/host.json" "$T/host.steered"
jq -c '.main = "/srv/elsewhere"' "$T/host.steered" > "$MAIN/conveyor/host.json"
run
q '.panels.board.data | .repo == null and (.checkRuns | map([.repo, .name, .done])) == [["widgetshop", "nightly", 4]]' "the check run reaches the Board when no record is steered"
mv "$T/host.steered" "$MAIN/conveyor/host.json"
answer "$(jq -c '.checkRun = {error: "check run: progress unreadable: jq: parse error"}' <<<"$P")" "$P_URL" 1794000000 "$C" "$C_URL" 0
run
q '.panels.board.data | .checkRuns == [{error: "check run: progress unreadable: jq: parse error", repo: "sample"}] and .repo == "sample" and (.review | length) == 1' "an unreadable check run is said, and the rest of the Board is still there"
q '.panels.cost.data.cards | .todayUsd == 4.25 and .weekUsd == 14 and .perLandedUsd == 1 and .landedAfter == {"1": 3, "2": 1, "3": 0, more: 0} and .unpricedSteps == 1' "cost sums both records; the average per landed card weighs each record by the cards it landed"
q '.panels.cost.data.cards.perCard | map([.repo, .issue, .state, .todayUsd, .weekUsd]) == [["sample", 801, "on the belt", 1.25, 1.25], ["sample", 6, "landed", 0, 6.25], ["sample", 13, "blocked", 2.5, null], ["widgetshop", 4, "retried", 0.5, 0.5]]' "per card, the 7 days: a card landed on an earlier day and a blocked one are rows too, and an unpriced sum stays null"
q '.panels.cost.data.cards.perCard | (.[1] | .url == "'"$PU"'/6" and .title == "Landed days ago") and (.[3].url == "'"$CU"'/4") and (.[0] | keys) == ["card", "issue", "repo", "runs", "state", "title", "todayUsd", "url", "weekUsd"]' "a per-card cost row names its repo and links to that repo's issue"
# The figures are the priced steps'; how many each leaves out is summed over the records, and the steps are
# listed with why. A record from before it named them leaves the list unknown, never empty.
q '.panels.cost.data.cards | .todayLeftOut == 0 and .weekLeftOut == 0 and .perLandedLeftOut == 0 and .unpriced == null' "no record gives the steps left out"
U='{"todayLeftOut": 1, "weekLeftOut": 2, "perLandedLeftOut": 1, "unpriced": [{"card": "c8-4", "issue": 4, "step": "build", "time": "2026-11-09T01:00:00Z", "why": "no model recorded"}]}'
answer "$(jq -c '.cost += {todayLeftOut: 0, weekLeftOut: 0, perLandedLeftOut: 0, unpriced: []}' <<<"$P")" "$P_URL" 1794000000 "$(jq -c --argjson u "$U" '.cost += $u' <<<"$C")" "$C_URL" 0
run
q '.panels.cost.data.cards | .todayLeftOut == 1 and .weekLeftOut == 2 and .perLandedLeftOut == 1
  and .unpriced == [{repo: "widgetshop", card: "c8-4", issue: 4, url: "'"$CU"'/4", step: "build", time: "2026-11-09T01:00:00Z", why: "no model recorded"}]' "the steps the figures leave out are counted and named, each with why and its link"
) & started machine

( fresh figures; cards_fixture
# --- a figure that was not read is null, never a smaller number ---
answer "$P" "$P_URL" 1794000000 "$(jq -c '.cost.today = null | .cost.perLanded = null' <<<"$C")" "$C_URL" 0
run
q '.panels.cost.data.cards | .todayUsd == null and .perLandedUsd == null and .weekUsd == 14' "a record with an unpriced total leaves the sum unknown, never the priced part"
# A host whose snapshot is from before it carried the per-card rows: they are unknown, never an empty list.
answer "$P" "$P_URL" 1794000000 "$(jq -c 'del(.cost.cards)' <<<"$C")" "$C_URL" 0
run
q '.panels.cost.data.cards | .perCard == null and .weekUsd == 14' "a record with no per-card cost rows leaves them unknown; the totals are still given"
answer "$P" "$P_URL" 1794000000 "$(jq -c '.queue = {next: null, held: null}' <<<"$C")" "$C_URL" 0
run
q '.panels.queue | .error == null and .data.next == null and .data.held == null and .data.awaitingDeploy == null and (.data.issuesError | test("devbox"))' "a record whose issues GitHub did not list leaves the queue unknown, never short"
# Bug: filtered to the project whose issues were listed, the page still had no queue: the part held only the unknown
# queue of all. Each record's own queue is beside it, the read one whole and the unread one unknown with its reason.
q '.panels.queue.data.byRepo | (.sample | (.next | map([.repo, .issue])) == [["sample", 20]] and .held == 2 and (.awaitingDeploy | type) == "array" and (.waiting | type) == "array" and .issuesError == null)
  and (.widgetshop | .next == null and .held == null and .awaitingDeploy == null and .waiting == null and (.issuesError | test("widgetshop on devbox")))' "one record's failed read leaves the other record's own queue readable, for the page filtered to it"
q '.panels.belt3d.data | .queue == null and (.byRepo.sample.queue | (.next | map([.repo, .issue])) == [["sample", 20]] and (.held | map(.issue)) == [30] and (.waiting | map(.issue)) == [32])
  and .byRepo.widgetshop.queue == null' "Belt 3D carries the read record's own queue too, and the unread one's as unknown"
q '.panels.belt.data.cards | length == 2' "the queue's failed read leaves the rest of the snapshot in place"
answer "$P" "" 1794000000 "$C" "https://gitlab.example/example/cd.git" 0
run
q '.panels.belt.data.cards | map(.url) == [null, null]' "a record whose origin is not a GitHub address gives no issue link"

# --- the host did not answer, or answered with something else: no card is shown, and the reason is ---
quiet; echo 255 > "$T/ssh-rc"; echo 'ssh: connect to host devbox port 22: Connection timed out' > "$T/ssh-err"; : > "$T/ssh-out"
run
q '.panels.health.data.host | .name == "devbox" and .reachable == false and (.error | test("devbox did not answer: ssh: connect to host devbox"))' "ssh that does not get through is an unreachable host, with ssh's own reason"
q '[.panels.belt, .panels.queue, .panels.landed] | all(.[]; .data == null and (.error | test("devbox did not answer")))' "with no answer the belt, the queue and the landed cards are not read, never empty"
q '.panels.needs | .error == null and .data.cards == null and (.data.cardsError | test("did not answer"))' "the cards that need the owner are unknown while the host is away"
q '.panels.health.data.records == null' "no record is read from a host that did not answer"
q '.panels.cost | .error == null and .data.cards == null and (.data.cardsError | test("did not answer")) and .data.sessions != null' "card costs are unknown; this machine's own session costs are still given"
quiet; echo 124 > "$T/ssh-rc"; : > "$T/ssh-out"
run
q '.panels.health.data.host | .reachable == false and (.error | test("no answer in [0-9]+ s"))' "an ssh that hits its time limit is an unreachable host"
quiet; echo 1 > "$T/ssh-rc"; echo 'conveyor: /srv/state/cards.jsonl line 3 is not a whole record of a known step; stopping' > "$T/ssh-err"; : > "$T/ssh-out"
run
q '.panels.health.data.host | .reachable == true and (.error | test("answered, but its Conveyor gave no snapshot: conveyor: .* line 3 is not a whole record"))' "a host that answers with Conveyor's refusal is reachable, and the refusal is shown"
q '.panels.belt.data == null' "a refused snapshot shows no card"
printf '%s\n%s\n%s\n@@end\n' "$(snap)" "$P_URL" 0 > "$T/ssh-out"; echo 0 > "$T/ssh-rc"; : > "$T/ssh-err"
run
q '.panels.belt | .data == null and (.error | test("not with the snapshot of every record"))' "an answer one record short is no answer: never a part of the records"
answer 'not json' "$P_URL" 0 "$(snap)" "$C_URL" 0
run
q '.panels.belt | .data == null and (.error | test("not with the snapshot of every record"))' "a record whose answer is not a snapshot leaves every record unread"
answer "$(snap | jq -c 'del(.belt)')" "$P_URL" 0 "$(snap)" "$C_URL" 0
run
q '.panels.belt.data == null and .panels.health.data.host.reachable == true' "a snapshot with a part missing is not understood, and is not shown in part"

# --- a checkout that names no host, or one it cannot find ---
mv "$MAIN/conveyor/host.json" "$T/host.json"; : > "$T/ssh-calls"
run
q '.panels.health.data.host == {name: null, local: true, reachable: null, error: "this checkout has no conveyor/host.json"} and (.panels.belt.error | test("no conveyor/host.json"))' "a checkout with no host file says so, and names no build machine"
[ ! -s "$T/ssh-calls" ] || fail "with no host file nothing is asked over ssh: $(cat "$T/ssh-calls")"
# Each error names the field that is wrong (#112), and a host file that names a build machine is said to.
echo '{"host":"dev box","ssh":"user@devbox","main":"/srv/main"}' > "$MAIN/conveyor/host.json"
run
q '.panels.belt.error == "conveyor/host.json names an ssh target, but its host is not a machine name" and .panels.health.data.host.local == false' "a host name that is not a plain name is refused, never passed to ssh"
echo '{"host":"elsewhere","ssh":"","main":"/srv/main"}' > "$MAIN/conveyor/host.json"
run
q '.panels.belt.error == "conveyor/host.json names no ssh target for elsewhere that ssh can use"' "an ssh target ssh cannot use is not guessed from test-hosts.json"
echo '{"host":"devbox","ssh":"user@devbox","records":[{"repo":"sample","main":"/srv/main"}]}' > "$MAIN/conveyor/host.json"
run
q '.panels.belt.error == "conveyor/host.json names no main: the path of the main checkout on devbox"' "a build machine with no main is refused, naming the field"
echo '{"host":"devbox","ssh":"user@devbox","main":"/srv/main","records":[{"repo":"sample","main":"relative/path"}]}' > "$MAIN/conveyor/host.json"
run
q '.panels.belt.error == "conveyor/host.json records are not understood: each needs a repo name and the path of its main checkout"' "a record whose checkout is not an absolute path is refused"
[ ! -s "$T/ssh-calls" ] || fail "a host file that is not understood asks nothing over ssh: $(cat "$T/ssh-calls")"
mv "$T/host.json" "$MAIN/conveyor/host.json"
) & started figures

( fresh decisions
# --- the open decisions: each project's ledger, where the host file's record names it on this machine ---
# Bug caught: the Board read the ledger of its own checkout, a plugin clone that holds none, and Needs you said
# "Decisions were not read: no ledger at <the clone>" while the project's decisions waited in the project's checkout.
dec() { local l=$1; shift; env HOME="$T/userhome" CONVEYOR_MAIN="$MAIN" CONVEYOR_LEDGER="$l" CONVEYOR_RULING_LOG="$T/userhome/.claude/rulings/conveyor.jsonl" CONVEYOR_WORKSPACES="$WS" CONVEYOR_SCRATCH="$SCR" bash "$DECIDE" "$@"; }
dec "$MAIN/.claude/metrics/decisions.jsonl" add q-own "The Board's own checkout?" 'no' main >/dev/null 2>&1 || fail "decision add to the Board's own ledger failed"
quiet
run
q '.panels.needs.data | .decisions == [] and .decisionsError == null' "a named ledger with no open decision is a measured empty list; a record that names no ledger has none and no warning; the Board's own ledger is not read"
mv "$PPL" "$T/ppl.kept"
run
q '.panels.needs.data | .decisions == null and (.decisionsError | test("^no ledger for sample at .*/ledgers/sample/decisions.jsonl$")) and .cards != null' "a named ledger that does not exist is a warning naming its project, and the cards still show"
mv "$T/ppl.kept" "$PPL"
dec "$PPL" add q-ship 'Ship "it" <b>now</b>?' 'Yes' main --options '["Yes","No"]' >/dev/null 2>&1 || fail "decision add failed"
dec "$PPL" add q-old 'Already settled?' 'no' main >/dev/null 2>&1 && dec "$PPL" answer q-old 'no' >/dev/null 2>&1 || fail "decision answer failed"
dec "$WSL" add w-pay 'Take card payments from Monday?' 'No' main >/dev/null 2>&1 || fail "decision add to the second ledger failed"
cp "$MAIN/conveyor/host.json" "$T/host.one-ledger"
jq -c --arg l "$WSL" '.records[1].ledger = $l' "$T/host.one-ledger" > "$MAIN/conveyor/host.json"
run
q '.panels.needs.data | .decisionsError == null and (.decisions | map([.repo, .id])) == [["sample", "q-ship"], ["widgetshop", "w-pay"]]
   and (.decisions[0] | .question == "Ship \"it\" <b>now</b>?" and .options == ["Yes", "No"] and .proposedDefault == "Yes" and .source == "main" and (.askedAt | test("Z$")))' \
  "two records with ledgers show both projects' open decisions, each named, with what the owner needs to answer it"
# Bug: a project's section left its open decisions out of its Needs you, so it counted fewer than wait on the owner.
q '[.panels.machine.data.projects[] | [.needs[] | select(.decision != null) | [.repo, .decision, .title]]] == [[["sample", "q-ship", "Ship \"it\" <b>now</b>?"]], [["widgetshop", "w-pay", "Take card payments from Monday?"]]]' \
  "each project's section has its own open decisions in its Needs you, never another project's"
grep -qx '# sample' "$OUT/digest.txt" && grep -qx '# widgetshop' "$OUT/digest.txt" \
  || fail "a collect that read the ledgers writes the owner's daily page beside data.js, a page a project: $(cat "$OUT/digest.txt" 2>/dev/null)"
# Bug caught: the decisions read so far went to the next ledger's jq as one argument, so a long question passed the
# argument limit and every project after it was dropped. And the whole ruling log's picker answers, which name no
# project, were printed under every project's heading.
cp "$PPL" "$T/ppl.short"
jq -cn '{id: "q-long", askedAt: "2026-11-12T10:00:00Z", question: ("x" * 140000), proposedDefault: "no", source: "main", answeredAt: null, answer: null}' >> "$PPL"
RL=$T/userhome/.claude/rulings/conveyor.jsonl; mkdir -p "${RL%/*}"; [ ! -e "$RL" ] || fail "no ruling log is expected here yet"
jq -cn --arg t "$(ago 0)" '{id: "r-pick", source: "ask", utc: $t, question: "Ship project A?", answer: "yes"}' > "$RL"
run
q '.panels.needs.data | .decisionsError == null and (.decisions | map([.repo, .id])) == [["sample", "q-ship"], ["sample", "q-long"], ["widgetshop", "w-pay"]]' \
  "a question past the argument limit drops no project's decisions"
[ "$(grep -c 'Ship project A?' "$OUT/digest.txt")" = 1 ] \
  && [ "$(awk '/^# /{h=$0} /Ship project A\?/{print h}' "$OUT/digest.txt")" = '# Picker answers no project ledger holds' ] \
  || fail "a picker answer is on the daily page once, under no project's heading: $(cat "$OUT/digest.txt")"
mv "$T/ppl.short" "$PPL"; rm -f "$RL"
jq -c '.records[1].ledger = "/nowhere/decisions.jsonl"' "$T/host.one-ledger" > "$MAIN/conveyor/host.json"
run
q '.panels.needs.data | (.decisions | map(.id)) == ["q-ship"] and .decisionsError == "no ledger for widgetshop at /nowhere/decisions.jsonl"' \
  "a ledger that does not exist is a warning naming that project, beside the decisions of the ledgers that read"
grep -qx '# widgetshop' "$OUT/digest.txt" \
  || fail "a collect in which a named ledger did not read keeps the last good daily page: $(cat "$OUT/digest.txt" 2>/dev/null)"
# Bug caught: a run that read no ledger kept the last page, so removing the last named ledger left its decisions on
# the owner's daily page for good.
jq -c '.records |= map(del(.ledger))' "$T/host.one-ledger" > "$MAIN/conveyor/host.json"
grep -q 'q-ship\|Ship "it"' "$OUT/digest.txt" || fail "the daily page holds the open decision before its ledger is removed: $(cat "$OUT/digest.txt")"
run
q '.panels.needs.data | .decisions == [] and .decisionsError == null' "with no ledger named there are no decisions and no warning"
[ -e "$OUT/digest.txt" ] && ! grep -q 'q-ship\|Ship "it"\|^# ' "$OUT/digest.txt" \
  || fail "with no ledger named the daily page holds no project's decisions: $(cat "$OUT/digest.txt" 2>/dev/null)"
mv "$T/host.one-ledger" "$MAIN/conveyor/host.json"
# There is no main session any more; an answer that is recorded is done, and nothing is listed as unsent.
UD=$T/userhome/.claude/rulings/dashboard-unsent; mkdir -p "$UD"
printf '{"id":"u1","askedAt":"2026-10-18T12:00:00Z","answer":"go","ruling":"ruling-1"}' > "$UD/u1.json"
run
q '.panels.needs.data | has("unsent") or has("unsentError") | not' "an answer kept from before is not listed as waiting on main"
rm -rf "$UD"
cp "$PPL" "$T/ledger.ok"; printf '{"id":"broken"\n' >> "$PPL"
run
q '.panels.needs | .error == null and .data.decisions == null and (.data.decisionsError | startswith("sample: ")) and .data.cards != null' "a corrupt ledger is not read, never an empty list; the cards still show"
echo 255 > "$T/ssh-rc"; : > "$T/ssh-out"
run
q '.panels.needs | .data == null and (.error | test("Cards: .*did not answer.* Decisions: "))' "with neither the cards nor the decisions read, the part itself failed to load"
cp "$T/ledger.ok" "$PPL"

# The host file's `main` is the Conveyor host's checkout, on another machine when the Board runs on the Mac. A
# Board in a git checkout, with CONVEYOR_MAIN unset, reads its own checkout and sends only the host's path over ssh.
# Bug caught: the host file's main was taken as this machine's checkout: the collect ran `cd /srv/linux-only` here
# and failed, and `decision.sh list` found no ledger there.
HF=$T/hostfile; mkdir -p "$HF/conveyor" "$MAIN/.claude/scripts"
jq -cn --arg l "$PPL" '{host: "devbox", ssh: "user@devbox", main: "/srv/linux-only",
  records: [{repo: "sample", main: "/srv/linux-only", ledger: $l}, {repo: "widgetshop", main: "/srv/cd"}]}' > "$HF/conveyor/host.json"
cp "$SOURCE"/.claude/scripts/{dashboard.sh,dashboard_limit.py,dashboard_alerts.jq,dashboard_needs.json,decision.sh} "$MAIN/.claude/scripts/"
quiet; : > "$T/ssh-calls"
new_cycle
env -u CONVEYOR_MAIN -u CONVEYOR_HOOK_FIRE_LOG -u CODEX_HOME HOME="$T/userhome" XDG_CONFIG_HOME="$HF" PATH="$BIN:$PATH" CONVEYOR_HOST_OS=Linux \
  CONVEYOR_WORKSPACES="$WS" CONVEYOR_SCRATCH="$SCR" CONVEYOR_DASHBOARD_DIR="$OUT" timeout 120 bash "$MAIN/.claude/scripts/dashboard.sh" 2>"$T/hf.err" \
  || fail "a Board whose host file names a checkout on another machine must still collect: $(cat "$T/hf.err")"
q '.panels.needs.data | .decisionsError == null and (.decisions | map(.id)) == ["q-ship"]' "the decisions come from the ledger the host file names, not the host file's main nor the Board's own checkout"
grep -qF "bash '/srv/linux-only/conveyor/conveyor.sh' snapshot" "$T/ssh-calls" || fail "the host file's main is the host's checkout, sent over ssh: $(cat "$T/ssh-calls")"
env -u CONVEYOR_MAIN HOME="$T/userhome" XDG_CONFIG_HOME="$HF" bash "$MAIN/.claude/scripts/decision.sh" list > "$T/hf.list" 2>&1 \
  && jq -e 'map(.id) | index("q-own") != null' "$T/hf.list" >/dev/null \
  || fail "decision.sh must read this machine's ledger, not the host file's main: $(cat "$T/hf.list")"
rm -rf "$MAIN/.claude/scripts"

# With CONVEYOR_DASHBOARD_DIR unset, the Board's folder is dashboard/ in the state folder: the host file's stateDir,
# else the checkout's conveyor/state, as `conveyor.sh state-dir` names it. Bug caught: the Board wrote to a fixed
# folder in the owner's home, outside the state folder, whatever the host file said.
SDH=$T/sd-host SD=$T/sd-state; mkdir -p "$SDH/conveyor"
jq -c --arg s "$SD" --arg m "$MAIN" '. + {main: $m, stateDir: $s}' "$MAIN/conveyor/host.json" > "$SDH/conveyor/host.json"
quiet; run CONVEYOR_DASHBOARD_DIR= XDG_CONFIG_HOME="$SDH"
[ -s "$SD/dashboard/data.js" ] || fail "the Board writes data.js to dashboard/ in the host file's stateDir"
quiet; run CONVEYOR_DASHBOARD_DIR= XDG_CONFIG_HOME="$T/sd-none"
[ -s "$MAIN/conveyor/state/dashboard/data.js" ] || fail "with no host file the Board writes data.js to the checkout's conveyor/state/dashboard"
echo '{' > "$SDH/conveyor/host.json"
env HOME="$T/userhome" PATH="$BIN:$PATH" CONVEYOR_HOST_OS=Linux CONVEYOR_MAIN="$MAIN" CONVEYOR_WORKSPACES="$WS" CONVEYOR_SCRATCH="$SCR" \
  XDG_CONFIG_HOME="$SDH" timeout 120 bash "$DASH" 2>/dev/null && fail "a host file that cannot be read must stop the Board, never fall back to the checkout's folder"
rm -rf "$SDH" "$SD" "$MAIN/conveyor/state"
) & started decisions

( fresh lanes
# --- the lanes: each record's Fast lane and Research worktrees on this machine, at the folders the host file names ---
quiet
run
q '.panels.lanes == {error: null, data: {records: [{repo: "sample", fast: {present: false}, research: {present: false}},
  {repo: "widgetshop", fast: null, research: null}], cardsError: null}}' "a named lane folder that is not there is said, not guessed; a record that names no lane has none, and that is no error"
g worktree add -q -b fix-123-fast "$FL" main
gw() { git -C "$FL" -c user.email=t@t -c user.name=t "$@"; }
run
q '.panels.lanes.data.records[0].fast | .present and .branch == "fix-123-fast" and .ahead == 0 and .dirty == 0 and .subject == null and .landing == {state: "none"}' "a lane level with main has no open change"
# A saved new file is work not committed: the tile counts it, never Idle.
echo x > "$FL/new.txt"
run
q '.panels.lanes.data.records[0].fast | .ahead == 0 and .dirty == 1' "a new file not yet added is an uncommitted change"
rm "$FL/new.txt"
# New files in a new folder are each a file changed, not the folder once.
mkdir "$FL/new"; echo a > "$FL/new/a.txt"; echo b > "$FL/new/b.txt"
run
q '.panels.lanes.data.records[0].fast | .ahead == 0 and .dirty == 2' "each new file in a new folder is counted, not the folder once"
rm -r "$FL/new"
gw commit -q --allow-empty -m "First lane commit"; gw commit -q --allow-empty -m "Second lane commit"
echo x > "$FL/f.txt"; gw add f.txt
run
q '.panels.lanes.data.records[0].fast | .ahead == 2 and .subject == "Second lane commit" and .first == "First lane commit" and .dirty == 1 and .landing == {state: "none"}' "the open change: commits ahead of main, the newest and the oldest, and uncommitted files; no card lands it yet"
lane_card() { jq -c --argjson c "$1" "$2" <<<"$(snap)"; }
BELT_CARD='{"card": "c5-123", "issue": 123, "title": "Fast thing", "step": "tests", "review": null, "of": 3, "stepAt": "'"$(ago 30)"'", "model": null, "tokens": {"claude": 0, "codex": 0}, "usd": 0}'
answer "$(lane_card "$BELT_CARD" '.belt = [$c]')" "$P_URL" 0 "$(snap)" "$C_URL" 0
run
q '.panels.lanes.data.records[0].fast.landing | .state == "belt" and .card == "c5-123" and .step == "tests"' "the card of the issue the branch names is the lane's landing, with its step"
answer "$(lane_card '{"card": "c5-123", "issue": 123, "title": "Fast thing", "reason": "worktree: branch does not merge", "since": "'"$(ago 30)"'"}' '.needsYou.blocked = [$c]')" "$P_URL" 0 "$(snap)" "$C_URL" 0
run
q '.panels.lanes.data.records[0].fast.landing | .state == "blocked" and .reason == "worktree: branch does not merge"' "a blocked landing carries its reason"
answer "$(lane_card '{"card": "c5-123", "issue": 123, "title": "Fast thing", "sentence": "Customers see a new page.", "since": "'"$(ago 30)"'"}' '.needsYou.waiting = [$c]')" "$P_URL" 0 "$(snap)" "$C_URL" 0
run
q '.panels.lanes.data.records[0].fast.landing | .state == "waiting" and .reason == "Customers see a new page."' "a landing that waits for the owner's yes says what they would be approving"
answer "$(lane_card '{"card": "c5-123", "issue": 123, "title": "Fast thing", "step": "landed", "time": "'"$(ago 30)"'", "usd": 1, "reviews": 1, "followups": [], "sha": "abc", "pushed": true}' '.landed = [$c]')" "$P_URL" 0 "$(snap)" "$C_URL" 0
run
q '.panels.lanes.data.records[0].fast.landing | .state == "landed" and .reviews == 1' "a landed lane change says so until the lane is reset"
# The landed list is today's alone; after midnight the card is in branches, however long ago it landed.
answer "$(lane_card '{"card": "c5-123", "issue": 123, "title": "Fast thing", "step": "landed", "time": "2026-01-01T00:00:00Z"}' '.branches = [$c]')" "$P_URL" 0 "$(snap)" "$C_URL" 0
run
q '.panels.lanes.data.records[0].fast.landing == {state: "landed", card: "c5-123", since: null, reviews: null}' "a lane change landed long ago still says landed, with no time"
# A snapshot from before it carried branches: the card is among the 7 days' cost rows.
answer "$(lane_card '{"card": "c5-123", "issue": 123, "title": "Fast thing", "state": "landed", "today": 0, "week": 1}' '.cost.cards = [$c]')" "$P_URL" 0 "$(snap)" "$C_URL" 0
run
q '.panels.lanes.data.records[0].fast.landing == {state: "landed", card: "c5-123", since: null, reviews: null}' "a lane change landed on an earlier day still says landed, with no time"
answer "$(lane_card '{"card": "c5-123", "issue": 123, "title": "Fast thing", "state": "retried", "today": 0, "week": 1}' '.cost.cards = [$c]')" "$P_URL" 0 "$(snap)" "$C_URL" 0
run
q '.panels.lanes.data.records[0].fast.landing == {state: "none"}' "a retried card of an earlier day is not a landing"
answer "$(snap)" "$P_URL" 0 "$(lane_card "$BELT_CARD" '.belt = [$c]')" "$C_URL" 0
run
q '.panels.lanes.data.records[0].fast.landing == {state: "none"}' "another record's card of the same issue number is not this record's lane's landing"
# A branch that names no issue lands as a card of issue 0, titled with the first commit of the branch.
gw branch -q -m lane-work
NO_ISSUE='{"card": "c6-0", "issue": 0, "title": "First lane commit", "step": "review", "review": 1, "of": 3, "stepAt": "'"$(ago 30)"'", "model": "gpt-x", "tokens": {"claude": 0, "codex": 0}, "usd": 0}'
answer "$(lane_card "$NO_ISSUE" '.belt = [$c]')" "$P_URL" 0 "$(snap)" "$C_URL" 0
run
q '.panels.lanes.data.records[0].fast | .branch == "lane-work" and .landing.state == "belt" and .landing.review == 1' "a branch that names no issue is matched by the title Conveyor gave its card"
q '.panels.belt.data.cards[0].url == null' "a card of no issue has no issue link"
answer "$(lane_card "$(jq -c '.title = "Some other branch"' <<<"$NO_ISSUE")" '.belt = [$c]')" "$P_URL" 0 "$(snap)" "$C_URL" 0
run
q '.panels.lanes.data.records[0].fast.landing == {state: "none"}' "another branch's card of no issue is not this lane's landing"
echo 255 > "$T/ssh-rc"; : > "$T/ssh-out"
run
q '.panels.lanes | .error == null and .data.records[0].fast.ahead == 2 and .data.records[0].fast.landing == null and (.data.cardsError | test("did not answer"))' "with the cards unread the lane still shows its change, and its landing is unknown, never \"not landing\""
quiet
g worktree add -q -b research-notes "$RSL" main
# The owner's Board said "no worktrees folder is set (CONVEYOR_WORKSPACES)": its lanes were in no folder it could
# find. The host file names each record's lanes, so both show with no environment variable naming a folder.
run CONVEYOR_WORKSPACES=
q '.panels.lanes | .error == null and (.data.records | map([.repo, .fast.present, .fast.branch, .research.present, .research.branch]))
  == [["sample", true, "lane-work", true, "research-notes"], ["widgetshop", null, null, null, null]]' \
  "with the host file naming a record's fast and research lane folders and no environment variable, both lanes show; the record that names none has none"
# A lanes entry that is no folder name is said, never read as no lanes.
cp "$MAIN/conveyor/host.json" "$T/host.lanes"
jq -c '.records[1].lanes = {fast: {worktree: 7}}' "$T/host.lanes" > "$MAIN/conveyor/host.json"
run
q '.panels.lanes == {error: "conveyor/host.json records are not understood", data: null}' "a lane folder that is not a path is not understood, and the panel says so"
mv "$T/host.lanes" "$MAIN/conveyor/host.json"
run
q '.panels.lanes.data.records[0].research == {present: true, branch: "research-notes", ahead: 0, subject: null, first: null, dirty: 0, run: null}' "a Research worktree with no session has no run"
RLOG=$T/userhome/.claude/projects/$(sed 's/[^a-zA-Z0-9]/-/g' <<<"$RSL"); mkdir -p "$RLOG"
{ echo '{"type":"summary","summary":"x"}'
  echo '{"type":"user","timestamp":"2026-11-09T10:00:00Z","message":{"role":"user","content":"Compare   OCR vendors\nfor passports"}}'
  echo '{"type":"assistant","timestamp":"2026-11-09T10:00:05Z","message":{"content":[{"type":"text","text":"On it."}]}}'; } > "$RLOG/s1.jsonl"
run
q '.panels.lanes.data.records[0].research.run | .startedAt == "2026-11-09T10:00:00Z" and .active == true and .topic == "Compare OCR vendors for passports" and (.lastAt | fromdateiso8601) > 0' "the Research lane's run: when it began, that its record just moved, and how its first prompt opens"
touch -d '-7 minutes' "$RLOG/s1.jsonl"
run
q '.panels.lanes.data.records[0].research.run.active == true' "a session quiet for a few minutes (a long test run) is still working"
touch -d '-11 minutes' "$RLOG/s1.jsonl"
run
q '.panels.lanes.data.records[0].research.run.active == false' "a session whose record has not moved for over 10 minutes is not working"
# A session begun in the main checkout (or a folder of the lane) is filed under that folder; its records' cwd says
# it works in the lane now. The Board read the lane's own folder alone, and showed such a lane as idle.
MLOG=$T/userhome/.claude/projects/$(sed 's/[^a-zA-Z0-9]/-/g' <<<"$MAIN"); mkdir -p "$MLOG"
{ echo '{"type":"user","timestamp":"2026-11-11T09:00:00Z","cwd":"'"$MAIN"'","message":{"role":"user","content":"Fix the login copy"}}'
  echo '{"type":"assistant","timestamp":"2026-11-11T09:00:05Z","cwd":"'"$FL/web"'","message":{"content":[{"type":"text","text":"Editing."}]}}'
  echo '{"type":"last-prompt","sessionId":"m1"}'; } > "$MLOG/m1.jsonl"
run
q '.panels.lanes.data.records[0].fast.run | .active == true and .topic == "Fix the login copy" and .startedAt == "2026-11-11T09:00:00Z"' "a session working in the Fast lane is its run, wherever it was begun"
q '.panels.lanes.data.records[0].research.run.topic == "Compare OCR vendors for passports"' "a session working in another lane is not this lane's run"
# A session whose latest cwd left the lane, or is a folder whose name only begins like it, is not the lane's run.
{ echo '{"type":"user","timestamp":"2026-11-11T09:00:00Z","cwd":"'"$FL"'","message":{"role":"user","content":"Fix the login copy"}}'
  echo '{"type":"assistant","timestamp":"2026-11-11T09:00:05Z","cwd":"'"$FL-old"'","message":{"content":[{"type":"text","text":"Elsewhere."}]}}'; } > "$MLOG/m1.jsonl"
run
q '.panels.lanes.data.records[0].fast.run == null' "a session that moved out of the lane is not its run"
# A record with one message longer than any tail read still shows the folder it works in.
{ printf '{"type":"user","timestamp":"2026-11-11T09:00:00Z","cwd":"%s","message":{"role":"user","content":"Fix the login copy %s"}}\n' \
    "$FL" "$(head -c 500000 /dev/zero | tr '\0' x)"; } > "$MLOG/m1.jsonl"
run
q '.panels.lanes.data.records[0].fast.run | .active == true and (.topic | startswith("Fix the login copy x")) and .startedAt == "2026-11-11T09:00:00Z"' "a session working in the lane is its run with its prompt, however long that message"
rm -rf "$MLOG"
# A session filed under the lane whose latest cwd has left it is not the lane's run, however fresh.
FLOG=$T/userhome/.claude/projects/$(sed 's/[^a-zA-Z0-9]/-/g' <<<"$FL"); mkdir -p "$FLOG"
{ echo '{"type":"user","timestamp":"2026-11-11T09:00:00Z","cwd":"'"$FL"'","message":{"role":"user","content":"Fix the login copy"}}'
  echo '{"type":"assistant","timestamp":"2026-11-11T09:00:05Z","cwd":"/elsewhere","message":{"content":[{"type":"text","text":"Elsewhere."}]}}'; } > "$FLOG/s1.jsonl"
run
q '.panels.lanes.data.records[0].fast.run == null' "a session begun in the lane that has left it is not its run"
rm -rf "$FLOG"

# --- what the Foreman's watchers read from the same file ---
q '(.panels.needs.data.decisions | type) == "array" and (.panels.health.data | has("limit") and has("limitError"))' "the decision and limit watchers find their fields"
) & started lanes

( fresh update
# --- --update brings a checkout behind origin/main forward, a fast-forward only, and restarts on new code ---
ORIG=$T/origin.git UP=$T/up PUSHER=$T/pusher
git init -q --bare -b main "$ORIG"
git clone -q "$ORIG" "$PUSHER" 2>/dev/null
pg() { git -C "$PUSHER" -c user.email=t@t -c user.name=t "$@"; }
pg symbolic-ref HEAD refs/heads/main
mkdir -p "$PUSHER/.claude/scripts"
echo v1 > "$PUSHER/.claude/scripts/dashboard_server.py"; echo v1 > "$PUSHER/README"
pg add -A; pg commit -q -m base; pg push -q origin main
git clone -q "$ORIG" "$UP"
stub systemctl 'echo "$*" >> "'"$T"'/systemctl-calls"'
upd() {
  : > "$T/systemctl-calls"
  env -u CONVEYOR_HOOK_FIRE_LOG HOME="$T/userhome" PATH="$BIN:$PATH" CONVEYOR_HOST_OS=Linux CONVEYOR_MAIN="$UP" CONVEYOR_WORKSPACES="$WS" \
    CONVEYOR_SCRATCH="$SCR" CONVEYOR_DASHBOARD_DIR="$OUT" timeout 60 bash "$DASH" --update 2>> "$T/update.log"
}
uq() { jq -e "$1" "$OUT/update.json" >/dev/null || fail "$2 (jq: $1; update.json: $(cat "$OUT/update.json"))"; }
# Behind by one commit that changes the page server; an untracked file and a changed file the commit does not touch
# do not hold it.
echo v2 > "$PUSHER/.claude/scripts/dashboard_server.py"; pg commit -q -am "server change"; pg push -q origin main
echo local > "$UP/README"; echo scratch > "$UP/notes.txt"
upd || fail "--update exited non-zero on a checkout it can bring forward: $(cat "$T/update.log")"
[ "$(git -C "$UP" rev-parse HEAD)" = "$(pg rev-parse HEAD)" ] || fail "one --update must fast-forward a checkout behind origin/main"
[ "$(cat "$UP/README")" = local ] && [ -e "$UP/notes.txt" ] || fail "the fast-forward must keep the changed and untracked files it does not touch"
grep -qxF -- '--user --no-block restart dashboard.service' "$T/systemctl-calls" || fail "a move that changes a file the loop runs must restart the service: $(cat "$T/systemctl-calls")"
uq '.error == null and .moved.restart == true and .moved.to == .head and (.moved.at | fromdateiso8601) > 0' "update.json says the checkout moved and the dashboard restarted on it"
run
q '.panels.health.data.update | .error == null and .moved.restart == true' "the Health part carries the update's last word"
# A move that changes no file the loop runs: brought forward, no restart.
echo doc > "$PUSHER/doc.txt"; pg add doc.txt; pg commit -q -m "doc only"; pg push -q origin main
upd || fail "--update exited non-zero: $(cat "$T/update.log")"
[ "$(git -C "$UP" rev-parse HEAD)" = "$(pg rev-parse HEAD)" ] && [ ! -s "$T/systemctl-calls" ] || fail "a move that changes no file the loop runs must not restart: $(cat "$T/systemctl-calls")"
uq '.error == null and .moved.restart == false' "update.json says the checkout moved with no restart"
# A move that changes only what the live feed reads once, at its start (its records' host): a restart.
mkdir -p "$PUSHER/conveyor"; echo '{}' > "$PUSHER/conveyor/host.json"; pg add conveyor; pg commit -q -m "host"; pg push -q origin main
upd || fail "--update exited non-zero: $(cat "$T/update.log")"
grep -qxF -- '--user --no-block restart dashboard.service' "$T/systemctl-calls" || fail "a move that changes conveyor/host.json must restart the service: $(cat "$T/systemctl-calls")"
uq '.error == null and .moved.restart == true' "update.json says the move to a new host.json restarted"
# A restart that fails is reported and retried by the next run, and stays owed through a later move that alone would
# need none.
echo v3 > "$PUSHER/.claude/scripts/dashboard_server.py"; pg commit -q -am "server change 2"; pg push -q origin main
stub systemctl 'echo "$*" >> "'"$T"'/systemctl-calls"; exit 1'
upd && fail "--update must exit non-zero when the restart fails"
uq '(.error | test("restart failed")) and .moved.restartFailed == true' "a failed restart is reported and kept"
stub systemctl 'echo "$*" >> "'"$T"'/systemctl-calls"'
echo doc2 > "$PUSHER/doc.txt"; pg commit -q -am "doc only 2"; pg push -q origin main
upd || fail "--update exited non-zero on the restart retry: $(cat "$T/update.log")"
[ "$(git -C "$UP" rev-parse HEAD)" = "$(pg rev-parse HEAD)" ] || fail "the retry run must still bring a later move forward"
grep -qxF -- '--user --no-block restart dashboard.service' "$T/systemctl-calls" || fail "the next run must retry a failed restart: $(cat "$T/systemctl-calls")"
uq '.error == null and .moved.restart == true and (.moved | has("restartFailed") | not)' "a retried restart clears the failure"
# A fast-forward that would overwrite a changed file: git refuses, and the reason is reported, autostash set or not.
git -C "$UP" config merge.autoStash true
echo v3 > "$PUSHER/README"; pg commit -q -am "readme"; pg push -q origin main
here=$(git -C "$UP" rev-parse HEAD)
upd || fail "a refused fast-forward is reported, not a failed run: $(cat "$T/update.log")"
[ "$(git -C "$UP" rev-parse HEAD)" = "$here" ] && [ "$(cat "$UP/README")" = local ] && [ ! -s "$T/systemctl-calls" ] || fail "a fast-forward that would overwrite a changed file must leave the checkout as it is"
uq '(.error | test("refused the fast-forward")) and .moved.to == .head' "the refusal is reported, and the last move is kept"
# A local commit: the checkout is left alone and the reason reported.
git -C "$UP" -c user.email=t@t -c user.name=t commit -q -am "local work"
here=$(git -C "$UP" rev-parse HEAD)
upd || fail "--update exited non-zero: $(cat "$T/update.log")"
[ "$(git -C "$UP" rev-parse HEAD)" = "$here" ] && [ ! -s "$T/systemctl-calls" ] || fail "a checkout with a local commit must be left alone"
uq '.error == "main has 1 commit(s) that origin/main does not; it is left as it is"' "a local commit is reported with its reason"
run
q '.panels.health.data.update.error | test("main has 1 commit")' "the page reads why the checkout was not brought forward"
# Another branch: left alone.
git -C "$UP" switch -q -c side
upd || fail "--update exited non-zero: $(cat "$T/update.log")"
[ "$(git -C "$UP" rev-parse HEAD)" = "$here" ] || fail "a checkout on another branch must be left alone"
uq '.error == "the checkout is on side, not main; it is left as it is"' "another branch is reported with its reason"
# A fetch that fails says git's fatal line, not its last: that is "and the repository exists.", the end of a hint,
# which Health showed as the reason (issue 415).
git -C "$UP" switch -q main
git -C "$UP" remote set-url origin "$T/no-such.git"
upd || fail "--update exited non-zero on a failed fetch: $(cat "$T/update.log")"
uq '(.error | startswith("origin/main could not be fetched: fatal:")) and (.error | test("repository exists") | not)' "a failed fetch is reported by git's fatal line"
git -C "$UP" remote set-url origin "$ORIG"
rm -f "$BIN/systemctl" "$OUT/update.json"

# --- only what the script was asked for ---
rc=0; env HOME="$T/userhome" CONVEYOR_MAIN="$MAIN" CONVEYOR_DASHBOARD_DIR="$OUT" bash "$DASH" --follow > "$T/usage.out" 2>&1 || rc=$?
[ "$rc" = 2 ] && grep -qF 'usage: dashboard.sh [--install|--uninstall|--restart|--loop|--publish|--update|--history|--check]' "$T/usage.out" || fail "an argument the collector does not have is refused with its usage: rc=$rc $(cat "$T/usage.out")"

# --- the strip-down holds: the retired workflow is named nowhere in the collector, the page or their tests ---
RETIRED='\b([u]nits?|[s]eats?|[p]ass(es)?|[m]erge queue|[c]hain)\b'
found=$(grep -n -i -E "$RETIRED" "$DASH" "$VIEW"/*.* "$VIEW"/panels/*.js "$SOURCE"/.claude/scripts/__tests__/dashboard.test.sh \
  "$SOURCE"/.claude/scripts/__tests__/dashboard-view.*.mjs | grep -v -E ':[0-9]+:\[[U]nit\]$' || true)
# Exempt: the service file's section header, a line that is only that header. Any other line still fails: the
# header's text anywhere in a line used to exempt it, so this check's own line could hide a retired word beside it.
[ -z "$found" ] || fail "the retired workflow is still named (the service file's own section header aside): $found"
) & started update

( fresh install
# The page's folder as a collect leaves it, data.js and all, which an install copies the page beside.
quiet; run
# --- install refuses missing files and copies the page beside data.js ---
# bootout returns before launchd has removed the job, and a bootstrap in that window fails with "Input/output
# error"; the stub keeps the old job listed for two prints after bootout, so install must wait for it to go.
stub launchctl 'echo "$*" >> "'"$T"'/launchctl-calls"; L="'"$T"'/launchctl-left"
case "$1" in
  bootout) echo 2 > "$L" ;;
  print) n=$(cat "$L" 2>/dev/null || echo 0); [ "$n" -gt 0 ] || exit 1; echo $((n-1)) > "$L"; exit 0 ;;
  bootstrap) [ "$(cat "$L" 2>/dev/null || echo 0)" -eq 0 ] || exit 5 ;;
esac
[ -z "${LAUNCHCTL_FAIL:-}" ] || [ "$1" != bootstrap ] || exit 1'
inst() {
  env HOME="$T/userhome" PATH="$BIN:$PATH" CONVEYOR_HOST_OS=Darwin CONVEYOR_MAIN="$MAIN" \
    CONVEYOR_DASHBOARD_DIR="$OUT" "$@" bash "$DASH" --install
}
PL=$T/userhome
PL=$PL/Library/LaunchAgents/com.conveyor.dashboard.plist
mkdir -p "${PL%/*}" "$MAIN/.claude/scripts"
echo 'previous job' > "$PL"
cp -R "$VIEW" "$MAIN/.claude/dashboard"
cp "$SOURCE/.claude/scripts/dashboard.sh" "$SOURCE/.claude/scripts/dashboard_server.py" "$MAIN/.claude/scripts/"
view_list() { (cd "$MAIN/.claude/dashboard" && find . -type f \( -name '*.html' -o -name '*.css' -o -name '*.js' -o -name '*.svg' \) | sed 's|^\./||' | LC_ALL=C sort); }
for f in scripts/dashboard.sh dashboard/index.html dashboard/app.css dashboard/app.js; do
  mv "$MAIN/.claude/$f" "$T/held"
  rm -f "$T/launchctl-calls"
  ! inst > "$T/inst.log" 2>&1 || fail "--install must fail without $f"
  grep -qF "$MAIN/.claude/$f" "$T/inst.log" || fail "--install must name the missing $f"
  grep -qx 'previous job' "$PL" || fail "a refused install must not replace the existing job"
  [ ! -e "$T/launchctl-calls" ] || fail "a refused install must not touch launchd"
  mv "$T/held" "$MAIN/.claude/$f"
done
chmod a-w "$OUT"
! inst > "$T/inst.log" 2>&1 || fail "--install must fail when the page cannot be copied"
grep -qx 'previous job' "$PL" || fail "a failed copy must not replace the existing job"
chmod u+w "$OUT"
# A restart that would serve a login nobody can get through (No login on this device off, and no admin with a
# password) refuses before launchd is touched, so the old server keeps serving. The store checked is the one the
# restarted job serves: an override set at install time is forwarded to it.
AUTHD=$T/userhome/.claude/rulings/dashboard-auth.json VALID=$T/valid-auth.json OFF=$T/off-auth.json NONE=$T/none-auth.json
mkdir -p "${AUTHD%/*}"; echo '{"noLoginHere": false}' | tee "$OFF" > "$AUTHD"; echo '{}' > "$NONE"; rm -f "$T/launchctl-calls"
python3 -c 'import hashlib, json; s = b"0" * 16; print(json.dumps(dict(epoch=1, noLoginHere=False, users=dict(max=dict(role="admin", salt=s.hex(), n=2, r=1, p=1, epoch=1,
  hash=hashlib.scrypt(b"password1", salt=s, n=2, r=1, p=1, dklen=32).hex())))))' > "$VALID"
! inst > "$T/inst.log" 2>&1 || fail "--install must refuse when No login on this device is off and the auth store holds no password"
grep -qF "$AUTHD" "$T/inst.log" || fail "the refusal must name the store it read: $(cat "$T/inst.log")"
[ ! -e "$T/launchctl-calls" ] || fail "a refused install must not boot the running job out: $(cat "$T/launchctl-calls")"
grep -qx 'previous job' "$PL" || fail "a refused install must not replace the existing job"
# A hash with no salt, user or scrypt parameters fails every login, so it is no password either.
echo '{"hash":"h","noLoginHere":false}' > "$AUTHD"
! inst > "$T/inst.log" 2>&1 || fail "--install accepted a store with a hash but no salt, user or scrypt parameters"
[ ! -e "$T/launchctl-calls" ] && grep -qx 'previous job' "$PL" || fail "a store no login can use still touched the running job"
rm -f "$AUTHD"
inst CONVEYOR_DASHBOARD_AUTH="$VALID" > "$T/inst.log" 2>&1 || fail "an override store that holds a hash was refused: $(cat "$T/inst.log")"
grep -qF "<key>CONVEYOR_DASHBOARD_AUTH</key><string>$VALID</string>" "$PL" \
  || fail "the job does not carry the auth store the preflight read, so it would serve the empty default: $(cat "$PL")"
cp "$VALID" "$AUTHD"; echo 'previous job' > "$PL"; rm -f "$T/launchctl-calls"
! inst CONVEYOR_DASHBOARD_AUTH="$OFF" > "$T/inst.log" 2>&1 || fail "an override store with no password was accepted because the default store has a hash"
[ ! -e "$T/launchctl-calls" ] && grep -qx 'previous job' "$PL" || fail "an override store with no password still touched the running job"
# Bug caught (#108): the first install needed a typed admin password, so an agent could not start the Board. With no
# user at all and No login on this device at its default (on), this machine gets in, so the install goes ahead.
inst CONVEYOR_DASHBOARD_AUTH="$NONE" < /dev/null > "$T/inst.log" 2>&1 || fail "a store with no user, with No login on this device on, was refused: $(cat "$T/inst.log")"
grep -q 'bootstrap' "$T/launchctl-calls" || fail "the install with no user did not start the job: $(cat "$T/launchctl-calls" 2>&1)"
! inst LAUNCHCTL_FAIL=1 >/dev/null 2>&1 || fail "--install must fail when launchd refuses the job"
inst > /dev/null || fail "--install failed"
[ "$(view_list | wc -l)" -ge 11 ] || fail "the page is its core files and one file for each panel: $(view_list | tr '\n' ' ')"
while IFS= read -r f; do cmp -s "$MAIN/.claude/dashboard/$f" "$OUT/$f" || fail "install must copy $f beside data.js"; done < <(view_list)
grep -qF "<string>--loop</string>" "$PL" || fail "the job must run the collect loop"
grep -qF "$MAIN/.claude/scripts/dashboard.sh" "$PL" || fail "the job must run the primary checkout's script"
grep -q 'bootstrap' "$T/launchctl-calls" || fail "install must bootstrap the job"
# The page is served over HTTPS only, so an install makes the self-signed certificate once and a second install keeps it.
CERT_DIR=$T/userhome/.claude/rulings/dashboard-tls
[ -s "$CERT_DIR/cert.pem" ] && [ -s "$CERT_DIR/key.pem" ] || fail "install_makes_the_certificate: no certificate in $CERT_DIR"
CERT_SUM=$(cksum < "$CERT_DIR/cert.pem")
inst > /dev/null || fail "--install failed the second time"
[ "$(cksum < "$CERT_DIR/cert.pem")" = "$CERT_SUM" ] || fail "install_keeps_the_certificate: a second install replaced the certificate"
env HOME="$T/userhome" PATH="$BIN:$PATH" CONVEYOR_HOST_OS=Darwin CONVEYOR_MAIN="$MAIN" \
  bash "$DASH" --uninstall >/dev/null || fail "--uninstall failed"
[ ! -e "$PL" ] || fail "uninstall must remove the plist"
grep -q 'bootout' "$T/launchctl-calls" || fail "uninstall must boot the job out"
# The Linux service: each word of the command is quoted, so a path with a space is one word, and a
# service that is already running is restarted.
stub systemctl 'echo "$*" >> "'"$T"'/systemctl-calls"'
linst() { env HOME="$T/userhome" PATH="$BIN:$PATH" CONVEYOR_HOST_OS=Linux CONVEYOR_MAIN="$MAIN" CONVEYOR_DASHBOARD_DIR="$OUT" "$@" bash "$DASH" --install; }
SVCF=$T/userhome/.config/systemd/user/dashboard.service
cp "$OFF" "$AUTHD"; rm -f "$T/systemctl-calls"
! linst > "$T/inst.log" 2>&1 || fail "a Linux --install must refuse when No login on this device is off and the auth store holds no password"
[ ! -e "$T/systemctl-calls" ] || fail "a refused Linux install restarted the service: $(cat "$T/systemctl-calls")"
linst CONVEYOR_DASHBOARD_AUTH="$VALID" > "$T/inst.log" 2>&1 || fail "a Linux override store that holds a hash was refused: $(cat "$T/inst.log")"
grep -qxF "Environment=\"CONVEYOR_DASHBOARD_AUTH=$VALID\"" "$SVCF" || fail "the service does not carry the auth store the preflight read: $(cat "$SVCF")"
cp "$VALID" "$AUTHD"; rm -f "$T/systemctl-calls"
! linst CONVEYOR_DASHBOARD_AUTH="$OFF" > "$T/inst.log" 2>&1 || fail "a Linux override store with no password was accepted because the default store has a hash"
[ ! -e "$T/systemctl-calls" ] || fail "a Linux override store with no password still restarted the service"
linst >/dev/null || fail "--install failed on Linux"
grep -qE '^ExecStart="[^"]+" "[^"]+/dashboard\.sh" --loop$' "$SVCF" || fail "the service's command is not quoted: $(grep ExecStart "$SVCF")"
grep -q -- '--user restart dashboard.service' "$T/systemctl-calls" || fail "a Linux install did not restart the running service: $(cat "$T/systemctl-calls")"
# A release installed as a git clone (plan section 7), for a project that carries no Board of its own, installs
# its own files, not the project's.
# Bug caught: a Board in any git checkout took CONVEYOR_MAIN's files and refused the project's missing dashboard.sh.
REL=$T/release PROJ=$T/project
mkdir -p "$REL/.claude/scripts" "$PROJ"
cp -R "$VIEW" "$REL/.claude/dashboard"
cp "$SOURCE/.claude/scripts/dashboard.sh" "$SOURCE/.claude/scripts/dashboard_server.py" "$REL/.claude/scripts/"
git -C "$REL" init -q -b main
env HOME="$T/userhome" PATH="$BIN:$PATH" CONVEYOR_HOST_OS=Linux CONVEYOR_MAIN="$PROJ" CONVEYOR_DASHBOARD_DIR="$OUT" \
  bash "$REL/.claude/scripts/dashboard.sh" --install > "$T/inst.log" 2>&1 \
  && grep -qxF "ExecStart=\"$BASH\" \"$REL/.claude/scripts/dashboard.sh\" --loop" "$SVCF" \
  || fail "a git-clone release must install its own Board: $(cat "$T/inst.log") $(grep ExecStart "$SVCF")"
rm -f "$BIN/systemctl"

# --- the loop serves the page to other machines on the LAN, and its server ends with it (a leftover would hold
# the port against the next job) ---
port=$(python3 -c 'import socket; s = socket.socket(); s.bind(("", 0)); print(s.getsockname()[1])')
lan=$(ipconfig getifaddr en0 2>/dev/null || hostname -I 2>/dev/null | awk '{print $1}')
[ -n "$lan" ] || fail "no LAN address to test the page from"
rm -f "$OUT/data.js"  # a fresh install: the page is up before the first collect lands
# A page fix landed in the primary checkout reaches the running loop on its next cycle, with no reinstall;
# a page file that did not change is not rewritten.
printf '/* landed page fix */\n' >> "$MAIN/.claude/dashboard/app.css"
printf '// landed panel fix\n' >> "$MAIN/.claude/dashboard/panels/belt.js"
touch -d '-1 hour' "$OUT/index.html"
idx_stat=$(stat -c '%i %Y' "$OUT/index.html")
# The loop's server is HTTPS behind a login. The certificate names localhost, so the LAN address is reached
# with --resolve; the password is set through the server's own command, in a store of this test's.
AUTHL=$T/auth; SRVPY=${DASH%/*}/dashboard_server.py; DPW='a long enough password'
CONVEYOR_DASHBOARD_AUTH=$AUTHL/dashboard-auth.json "$PY" "$SRVPY" make-cert >/dev/null || fail "the loop's HTTPS certificate could not be made"
printf '%s\n%s\n' "$DPW" "$DPW" | CONVEYOR_DASHBOARD_AUTH=$AUTHL/dashboard-auth.json "$PY" "$SRVPY" set-password max >/dev/null || fail "the loop's password could not be set"
DU=https://localhost:$port
dcurl() { curl --cacert "$AUTHL/dashboard-tls/cert.pem" --resolve "localhost:$port:$lan" -b "$AUTHL/jar" "$@"; }
# The loop itself brings the checkout forward each cycle, with no --update typed. Its origin is one commit
# ahead with a file the loop runs, so the cycle must fast-forward and restart the service.
MORIG=$T/main-origin.git MPUSH=$T/main-pusher
git init -q --bare -b main "$MORIG"; g remote add origin "$MORIG"; g push -q origin main
git clone -q "$MORIG" "$MPUSH" 2>/dev/null
mkdir -p "$MPUSH/.claude/scripts"; echo v2 > "$MPUSH/.claude/scripts/dashboard_stream.py"
git -C "$MPUSH" add -A; git -C "$MPUSH" -c user.email=t@t -c user.name=t commit -q -m "stream change"; git -C "$MPUSH" push -q origin main
stub systemctl 'echo "$*" >> "'"$T"'/systemctl-calls"'; : > "$T/systemctl-calls"
quiet
# A feed that ended mid-write left its temp files; each new feed names its own, so the loop must remove these.
echo '{"partial":' > "$OUT/.stream.json.123"; echo '{"partial":' > "$OUT/.stream.json.456"
env HOME="$T/userhome" PATH="$BIN:$PATH" CONVEYOR_HOST_OS=Linux CONVEYOR_MAIN="$MAIN" CONVEYOR_DASHBOARD_AUTH="$AUTHL/dashboard-auth.json" \
  CONVEYOR_WORKSPACES="$WS" CONVEYOR_SCRATCH="$SCR" CONVEYOR_DASHBOARD_DIR="$OUT" \
  CONVEYOR_DASHBOARD_PORT="$port" bash "$DASH" --loop > "$T/loop.log" 2>&1 &
loop=$!
stop() { kill "$loop" 2>/dev/null || true; fail "$1"; }
wait_until 'dcurl -sf -m 1 -o /dev/null "$DU/login" || ! kill -0 "$loop" 2>/dev/null' || :
dcurl -sf -m 1 -o /dev/null "$DU/login" || stop "the page is not served over https on $lan:$port: $(cat "$T/loop.log")"
[ "$(dcurl -s -m 2 -o /dev/null -w '%{http_code}' "$DU/index.html")" = 302 ] || stop "loop_serves_https_behind_login: the page opened without a login"
[ "$(curl -s -m 2 -o /dev/null -w '%{http_code}' "http://$lan:$port/index.html")" = 000 ] || stop "loop_serves_https_behind_login: plain http got an answer"
dcurl -sf -m 5 -c "$AUTHL/jar" -o /dev/null -X POST -H "Origin: $DU" -H 'Content-Type: application/json' \
  --data-binary "{\"user\":\"max\",\"password\":\"$DPW\",\"trust\":false,\"label\":\"\"}" "$DU/login" || stop "the loop's login was refused"
dcurl -sf -m 5 "$DU/index.html" > "$T/served.html" || stop "the page is not served after the login"
cmp -s "$OUT/index.html" "$T/served.html" || stop "the served page must be the installed one"
dcurl -sf -m 5 "$DU/panels/belt.js" > "$T/served-belt.js" || stop "a panel's file is not served from its folder"
# The header's mark is the Conveyor logo (the C path and the card rectangle), and the tab icon is served as SVG.
grep -qF '<svg class="brand-mark" aria-hidden="true"' "$T/served.html" \
  && grep -qF '<path d="M42.5 20.5A16 16 0 1 0 42.5 43.5"' "$T/served.html" \
  && grep -qF '<rect x="35" y="26.5" width="16" height="11" rx="3"' "$T/served.html" \
  || stop "page_shows_the_logo: the header must hold the Conveyor mark's SVG"
grep -qF '<link rel="icon" type="image/svg+xml" href="icon.svg">' "$T/served.html" || stop "page_names_its_tab_icon: no SVG icon link"
dcurl -sf -m 5 -D "$T/icon.head" -o "$T/served-icon.svg" "$DU/icon.svg" || stop "page_names_its_tab_icon: icon.svg is not served"
grep -qi '^content-type: image/svg+xml' "$T/icon.head" && cmp -s "$MAIN/.claude/dashboard/icon.svg" "$T/served-icon.svg" \
  || stop "page_names_its_tab_icon: icon.svg must be served as image/svg+xml: $(cat "$T/icon.head")"
# The server starts before the first collect publishes data.js, so wait for that too, while the loop lives.
wait_until '[ -s "$OUT/data.js" ] || ! kill -0 "$loop" 2>/dev/null' || :
[ -s "$OUT/data.js" ] || stop "data.js must be served beside the page: the loop ended, or hung, before its first collect: $(cat "$T/loop.log")"
[ -z "$(find "$OUT" -maxdepth 1 -name '.stream.json.*' | head -n 1)" ] || stop "loop_clears_stream_temps: the temp files an ended feed left are kept: $(ls -A "$OUT")"
dcurl -sf -m 5 "$DU/data.js" > "$T/served.js" || stop "data.js must be served beside the page"
head -c 14 "$T/served.js" | grep -qF 'window.DASH = ' || stop "the served data.js must assign window.DASH"
# alive.js is the loop's heartbeat: the page tells a slow cycle (heartbeat fresh, data.js old) from a stopped
# collector (no heartbeat) by it. The first cycle's end stamps its length.
wait_until 'grep -qE "\"lastCycleSec\":[0-9]+" "$OUT/alive.js" 2>/dev/null || ! kill -0 "$loop" 2>/dev/null' || :
grep -qE '"lastCycleSec":[0-9]+' "$OUT/alive.js" 2>/dev/null || stop "the loop must write alive.js with the cycle it timed: $(cat "$OUT/alive.js" 2>&1)"
sed -e '1s/^window\.DASH_ALIVE = //' -e '$s/;$//' "$OUT/alive.js" \
  | jq -e '(.at | fromdateiso8601) > 0 and (.cycleStartedAt | fromdateiso8601) > 0 and (.lastCycleSec | type) == "number"' >/dev/null \
  || stop "alive.js must assign window.DASH_ALIVE = {at, cycleStartedAt, lastCycleSec}: $(cat "$OUT/alive.js")"
wait_until 'grep -qxF -- "--user --no-block restart dashboard.service" "$T/systemctl-calls" || ! kill -0 "$loop" 2>/dev/null' || :
grep -qxF -- '--user --no-block restart dashboard.service' "$T/systemctl-calls" \
  || stop "loop_runs_the_update: the cycle must restart the service on new code: $(cat "$OUT/update.json" "$T/loop.log" 2>&1)"
[ "$(git -C "$MAIN" rev-parse HEAD)" = "$(git -C "$MPUSH" rev-parse HEAD)" ] && jq -e '.error == null and .moved.restart == true' "$OUT/update.json" >/dev/null \
  || stop "loop_runs_the_update: the cycle must fast-forward the checkout and say so in update.json: $(cat "$OUT/update.json" 2>&1)"
cmp -s "$MAIN/.claude/dashboard/app.css" "$OUT/app.css" && cmp -s "$MAIN/.claude/dashboard/panels/belt.js" "$OUT/panels/belt.js" \
  || stop "loop_refreshes_the_page: a changed page file, a panel's included, must be served after the next cycle"
[ "$(stat -c '%i %Y' "$OUT/index.html")" = "$idx_stat" ] || stop "loop_refreshes_the_page: an unchanged page file must not be rewritten"
# The heartbeat carries a stamp of the installed page files, so a page left open sees an update and reloads.
[ "$(sed -e '1s/^window\.DASH_ALIVE = //' -e '$s/;$//' "$OUT/alive.js" | jq -r .view)" = "$(view_list | (cd "$OUT" && xargs -d '\n' cat) | cksum | cut -d' ' -f1)" ] \
  || stop "heartbeat_stamps_the_page: alive.js must carry the checksum of every installed page file: $(cat "$OUT/alive.js")"
# The page keeps its layout in the browser: the loop's server takes no layout and writes none.
[ "$(dcurl -s -m 2 -o /dev/null -w '%{http_code}' -X PUT -H 'Content-Type: application/json' -H "Origin: $DU" --data-binary '{"order":["belt"]}' "$DU/layout")" = 501 ] \
  && [ ! -e "$OUT/layout.js" ] || stop "loop_keeps_no_layout: the server took a layout, or a layout file was written: $(ls "$OUT")"
# On the main checkout the live dashboard service is another `dashboard.sh --loop` of this very script, hours old.
# A stand-in plays it: only the loop this test started, and its children, must be gone.
( exec -a "bash $DASH --loop" sleep 30 ) & standin=$! # sleep: the stand-in, alive under the live service's name
kids=$(pgrep -P "$loop" -f -- "$DASH --loop" | tr '\n' ' ')  # the heartbeat subshell, not the cycle's own sleep
[ -n "$kids" ] || { kill "$loop" "$standin"; fail "the loop has a heartbeat child to watch"; }
kill "$loop"; wait "$loop" 2>/dev/null || true
wait_until '! curl -s -m 1 -o /dev/null --cacert "$AUTHL/dashboard-tls/cert.pem" "https://127.0.0.1:$port/login"' \
  || { kill "$standin"; fail "the page server must stop with the loop"; }
# A heartbeat that outlives its loop reads alive forever. A deadline, not a poll count: a slow process list must
# not wait out the heartbeat's own 15 s sleep.
alive_kids() { local p; for p in $kids; do ! kill -0 "$p" 2>/dev/null || ps -o pid=,command= -p "$p"; done; }
end=$((SECONDS + 3)); while [ -n "$(alive_kids)" ]; do
  [ $SECONDS -lt $end ] || { kill "$standin"; fail "loop_check_ignores_another_loop: the heartbeat must stop with the loop: $(alive_kids)"; }; sleep 0.1
done
kill -0 "$standin" 2>/dev/null || fail "loop_check_ignores_another_loop: the stand-in for the live service must still be running"
kill "$standin"; wait "$standin" 2>/dev/null || true
) & started install

( fresh queuewait
# Bug (issue 19): an issue waiting on another (sample's #16 on #7) with nothing else queued must still reach the Queue
# part, on the whole Board and, when the other record's issues were not listed, in byRepo for its own project.
W16='{"queue": {"next": [], "waiting": [{"issue": 16, "title": "Second half", "waitsFor": [7], "forced": false}]}}'
answer "$(snap "$W16")" "$P_URL" 0 "$(snap)" "$C_URL" 0
run
q '.panels.queue.data | .next == [] and (.waiting | map([.repo, .issue, .waitsFor])) == [["sample", 16, [7]]]' \
  "every project: the Queue part's waiting has the issue that waits on another, with next empty"
answer "$(snap "$W16")" "$P_URL" 0 "$(snap '{"queue": {"next": null}}')" "$C_URL" 0
run
q '.panels.queue.data | .waiting == null and (.byRepo.sample.waiting | map([.repo, .issue, .waitsFor])) == [["sample", 16, [7]]]
  and .byRepo.sample.next == [] and .byRepo.widgetshop.waiting == null' \
  "byRepo: its own project's part has the waiting issue when another project's issues were not listed"
) & started queuewait

# Every part ended and passed; a part that failed stopped at its FAIL line, above.
bad=()
for p in "${PARTS[@]}"; do wait "${p#*:}" || bad+=("${p%%:*}"); done
[ ${#bad[@]} -eq 0 ] || fail "these parts failed (their FAIL lines are above): ${bad[*]}"
echo "ok: dashboard"
