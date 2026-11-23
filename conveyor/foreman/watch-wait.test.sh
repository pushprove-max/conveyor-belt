#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 60
# The Foreman's Conveyor watcher, watch-conveyor.sh, on a card that waits: one poll (--once) at a time of a snapshot
# given by CONVEYOR_FOREMAN_ASK, the clock set by CONVEYOR_FOREMAN_NOW.
# Bug (#220): a card waiting for main to change (mainred.sh mainwait()) or on another card woke the Foreman only once
# it was stuck, 30 minutes on, and the wake only stated it; cards waited for hours. Now a wait of the pack's
# foreman.waitWake minutes (default 10) wakes it once, naming what the card waits on, and again, "still waiting",
# after each further waitWake minutes.
set -uo pipefail
SRC=$(cd "$(dirname "$0")" && pwd -P)
T=$(mktemp -d) || exit 1
trap 'rm -rf "$T"' EXIT
fails=0
AT=2026-11-17T08:00:00Z START=1794902400 # $AT in epoch seconds
mkdir -p "$T/home" "$T/config/conveyor"
check() { if "${@:2}"; then echo "ok [watch-wait]: $1"; else echo "FAIL [watch-wait]: $1" >&2; fails=$((fails + 1)); fi; }
nope() { ! "$@"; }
# The snapshot of record <repo>, its main $T/<repo>: <repo>.json.
fixture() { # <repo> <snapshot> <pack>
  git init -q "$T/$1" && mkdir -p "$T/$1/.conveyor" && echo "$3" > "$T/$1/.conveyor/project.json" && printf '%s\n' "$2" > "$T/$1.json" \
    && jq -n --arg m "$T/$1" --arg r "$1" '{records: [{repo: $r, main: $m}]}' > "$T/config/conveyor/host-$1.json"
}
poll() { # <repo> <minutes after $AT>: one poll then; 0 with a wake put in pending, which goes to $T/<repo>.wake
  rm -f "$T/$1.fd"/pending/*.wake "$T/$1.wake"; cp "$T/config/conveyor/host-$1.json" "$T/config/conveyor/host.json"
  HOME=$T/home XDG_CONFIG_HOME=$T/config CONVEYOR_MAIN=$T/$1 CONVEYOR_FOREMAN_DIR=$T/$1.fd CONVEYOR_FOREMAN_NOW=$((START + $2 * 60)) \
    CONVEYOR_FOREMAN_ASK="cat $T/$1.json" bash "$SRC/watch-conveyor.sh" --once 2>> "$T/$1.err" && cat "$T/$1.fd"/pending/*.wake > "$T/$1.wake"
}
has() { grep -qF -- "$2" "$T/$1.wake"; } # <repo> <text>
HEALTH='{time: $at, loop: true, gh: true, blocked: [], waiting: [], stuck: [], pushFailingSince: null, waitingOnCard: []}'

# A card in mainred.sh mainwait() since $AT, its main-red fix card open in its fix step.
fixture main "$(jq -cn --arg at "$AT" '{queue: {next: []}, health: '"$HEALTH"', belt: [
  {card: "c44", issue: 44, step: "tests", live: {action: "waiting for main to change: serve fail on main at 0123456789ab too", at: $at}},
  {card: "cred", issue: 0, name: "Main is red (0123456789ab)", step: "fix", landed: false, live: {action: "Bash: npm test", at: $at}}]}')" '{}'
check 'a wait under 10 minutes gives no wake' nope poll main 9
check 'a wait of 10 minutes gives a wake' poll main 10
check 'the wake names the card, what it waits on and the main-red card with its step and last action' \
  has main 'main: #44 has waited 10 minutes on main to change (serve fail on main at 0123456789ab too); main-red fix card Main is red (0123456789ab) (at fix, last action: Bash: npm test)'
check 'the wake is one line for the one card' test "$(grep -c '#44' "$T/main.wake")" = 2
check 'the same wait a poll later gives no second wake' nope poll main 11
check 'the same wait 20 minutes on gives "still waiting"' poll main 20
check 'its line says still waiting' has main 'main: #44 is still waiting, 20 minutes now, on main to change'
check 'the still-waiting wake is not repeated' nope poll main 25

# A card waiting at its claim on a same-file card (health waitingOnCard) since $AT, that card in review; the belt's
# pack sets foreman.waitWake to 5 minutes, which the snapshot gives (the belt may be on another host, its pack not
# on this machine: the pack here sets none).
fixture card "$(jq -cn --arg at "$AT" '{waitWake: 5, queue: {next: []}, health: ('"$HEALTH"' | .waitingOnCard = [{card: "c50", issue: 50, since: $at, waitsOn: {card: "c51", issue: 51, state: "review"}}]),
  belt: [{card: "c50", issue: 50, step: "waiting", live: null}, {card: "c51", issue: 51, step: "review", live: {action: "codex review round 2", at: $at}}]}')" '{}'
check 'a wait under the pack'"'"'s waitWake gives no wake' nope poll card 4
check 'a card waiting the pack'"'"'s waitWake on another card wakes' poll card 5
check 'its line names that card, its step and its last action' has card 'card: #50 has waited 5 minutes on #51 (at review, last action: codex review round 2)'

[ "$fails" = 0 ] || { cat "$T"/*.err >&2; exit 1; }
echo "ok watch-wait" # the pass of the case its FAIL lines name, as the main-red proof reads it
