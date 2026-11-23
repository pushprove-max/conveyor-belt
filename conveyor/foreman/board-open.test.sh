#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 60
# The Board opens when `foreman.sh claim` makes a session the Foreman (board_open, .claude/hooks/lib/board-open.sh,
# the check and opener the SessionStart hook uses too; its own cases are in .claude/hooks/__tests__/board-open.test.sh).
# Bug (#106): only a fresh session start opened the Board, so an owner who starts the Foreman by claiming it in a
# running session never saw it open. No browser: open and xdg-open are stubs that record what they were asked to open.
set -uo pipefail
SRC=$(cd "$(dirname "$0")" && pwd -P)
. "$SRC/../tests/wait.sh"
B=$(mktemp -d) || exit 1
LSN=''
trap 'kill $LSN $(cat "$B"/*/server 2>/dev/null) 2>/dev/null; rm -rf "$B"' EXIT
cd "$B" || exit 1
# A card session runs with CLAUDE_CODE_PROMPT_CACHE_TTL=5m (card-settings.json): the claim would print its cache
# warning as line 2, where t_down and t_fresh read the Board line.
unset CONVEYOR_FOREMAN CONVEYOR_FOREMAN_LAUNCH CONVEYOR_CARD CONVEYOR_LANE CLAUDE_CONFIG_DIR CLAUDE_PROJECT_DIR CLAUDE_PLUGIN_OPTION_boardAutoOpen CLAUDE_CODE_PROMPT_CACHE_TTL
# Records cannot be asked here: the live summary says so, which the claim's context prints all the same.
export CONVEYOR_FOREMAN_ASK='exit 3'
mkdir -p "$B/bin"
for o in open xdg-open; do printf '#!/usr/bin/env bash\necho "$1" >> "$OPENED"\n' > "$B/bin/$o"; chmod +x "$B/bin/$o"; done
export PATH=$B/bin:$PATH
free_port() { python3 -I -c 'import socket; s = socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1])'; }
# One Board for every case: the Board's own page server, on its own virtualenv, with its login store and certificate
# here (the cases' CONVEYOR_DASHBOARD_AUTH), so board_open's check passes only for it.
PY=${XDG_DATA_HOME:-$HOME/.local/share}/conveyor/board-venv/bin/python3
"$PY" -c 'import pyotp, segno, cryptography' || { echo "FAIL: the Board's virtualenv $PY lacks its packages: run conveyor.sh setup" >&2; exit 1; }
export CONVEYOR_DASHBOARD_AUTH=$B/auth/dashboard-auth.json
mkdir -p "$B/auth" "$B/out" && cp "$SRC/../../.claude/dashboard/login.html" "$B/out/" || exit 1
"$PY" "$SRC/../../.claude/scripts/dashboard_server.py" make-cert >/dev/null || exit 1
PORT=$(free_port)
"$PY" "$SRC/../../.claude/scripts/dashboard_server.py" "$PORT" "$B/out" 2>/dev/null & LSN=$!
WAIT_CEILING=20 wait_until 'curl -sk -o /dev/null "https://127.0.0.1:$PORT/login"' || exit 1
export CONVEYOR_DASHBOARD_PORT=$PORT

# fixture <case>: a project alpha and its Foreman's folder; what the stub opener is asked to open goes to $OPENED.
fixture() {
  T=$B/$1 CASE=$1
  export HOME=$T/home XDG_CONFIG_HOME=$T/config XDG_DATA_HOME=$T/data XDG_STATE_HOME=$T/xstate OPENED=$T/opened
  M=$T/alpha FD=$T/foreman
  export CONVEYOR_FOREMAN_DIR=$FD CONVEYOR_MAIN=$M
  mkdir -p "$HOME" "$XDG_CONFIG_HOME/conveyor" "$FD" && git init -q "$M" && mkdir -p "$M/.conveyor" \
    && jq -n '{plugin: {follow: "main"}}' > "$M/.conveyor/project.json" \
    && jq -n --arg m "$M" '{records: [{repo: "alpha", main: $m}]}' > "$XDG_CONFIG_HOME/conveyor/host.json" \
    || fail "the fixture was not made"
}
fail() { echo "FAIL [board-open-$CASE]: $*" >&2; exit 1; }
opened() { cat "$OPENED" 2>/dev/null; }
# settle: time for an opener that a claim wrongly started to record its tab, before a case checks that none did.
settle() { sleep 0.5; } # sleep: nothing is expected to happen; this lets a wrong open show

# A claim opens the Board once, on localhost, and its first line is still the claim's.
t_once() {
  fixture once
  out=$(bash "$SRC/foreman.sh" claim s1) || fail "the claim failed: $out"
  [ "$(head -n 1 <<<"$out")" = "This session is now the Foreman: its watchers start at the end of this turn." ] \
    || fail "the claim's first line is not the claim: $out"
  wait_until '[ -s "$OPENED" ]' || fail "the claim did not open the Board"
  settle
  [ "$(opened)" = "https://localhost:$PORT/" ] || fail "the claim did not open the Board once, on localhost: $(opened)"
}
# A second claim by the session that already holds the role opens no second tab.
t_again() {
  fixture again
  bash "$SRC/foreman.sh" claim s1 > /dev/null || fail "the claim failed"
  wait_until '[ -s "$OPENED" ]' || fail "the first claim did not open the Board"
  bash "$SRC/foreman.sh" claim s1 > /dev/null || fail "the repeated claim failed"
  settle
  [ "$(opened)" = "https://localhost:$PORT/" ] || fail "the repeated claim opened another tab: $(opened)"
}
# The plugin option boardAutoOpen false: the claim opens nothing.
t_off() {
  fixture off
  out=$(CLAUDE_PLUGIN_OPTION_boardAutoOpen=false bash "$SRC/foreman.sh" claim s1) || fail "the claim failed: $out"
  settle
  [ -z "$(opened)" ] || fail "the option off still opened the Board: $(opened)"
  ! grep -qF 'the Board is not running' <<<"$out" || fail "the option off still checked the Board: $out"
}
# No Board on the port: the claim says so in one line, starts the Board from the project's checkout (the owner's rule
# for #106: started first, then opened), opens it once it answers, and the session is the Foreman all the same.
# Bug: the claim only said the Board was not running, so the owner still saw no Board. The start is a stub that
# records where it ran and serves the Board's own page on the port, as `conveyor.sh board` would.
t_down() {
  fixture down
  local dead; dead=$(free_port)
  export CONVEYOR_BOARD_START_CMD="pwd -P > '$T/started'; '$PY' '$SRC/../../.claude/scripts/dashboard_server.py' $dead '$B/out' >/dev/null 2>&1 & echo \$! > '$T/server'"
  out=$(CONVEYOR_DASHBOARD_PORT=$dead bash "$SRC/foreman.sh" claim s1) || fail "the claim with no Board failed: $out"
  [[ $(sed -n 2p <<<"$out") == "conveyor: the Board is not running (nothing serves https://localhost:$dead/), so conveyor.sh board starts it; it opens when it answers (the start's output: "*")" ]] \
    || fail "the claim does not say in one line that the Board is not running and is started: $out"
  [ "$(cut -d' ' -f1 "$FD/session")" = s1 ] || fail "the claim with no Board did not mark the session: $(cat "$FD/session")"
  WAIT_CEILING=30 wait_until '[ -s "$OPENED" ]' || fail "the started Board was not opened"
  kill "$(cat "$T/server")" 2>/dev/null
  [ "$(cat "$T/started")" = "$(cd "$M" && pwd -P)" ] || fail "the Board was not started from the project's checkout: $(cat "$T/started")"
  [ "$(opened)" = "https://localhost:$dead/" ] || fail "the started Board did not open once, on localhost: $(opened)"
}

# A fresh install: no certificate yet (its own login store's folder has no dashboard-tls) and no Board. Bug caught
# (#183): curl 8.18 takes a --cacert file that does not exist for a usage error (exit 2, not 7), so the claim gave
# "nothing serves ... not opened" and never started the Board. The start makes the certificate there, then serves.
t_fresh() {
  fixture fresh
  local dead; dead=$(free_port)
  export CONVEYOR_DASHBOARD_AUTH=$T/auth/dashboard-auth.json; mkdir -p "$T/auth"
  export CONVEYOR_BOARD_START_CMD="'$PY' '$SRC/../../.claude/scripts/dashboard_server.py' make-cert >/dev/null && { '$PY' '$SRC/../../.claude/scripts/dashboard_server.py' $dead '$B/out' >/dev/null 2>&1 & echo \$! > '$T/server'; }"
  out=$(CONVEYOR_DASHBOARD_PORT=$dead bash "$SRC/foreman.sh" claim s1) || fail "the claim on a fresh install failed: $out"
  [[ $(sed -n 2p <<<"$out") == "conveyor: the Board is not running (nothing serves https://localhost:$dead/), so conveyor.sh board starts it; it opens when it answers (the start's output: "*")" ]] \
    || fail "the claim on a fresh install did not start the Board: $out"
  WAIT_CEILING=30 wait_until '[ -s "$OPENED" ]' || fail "the Board started on a fresh install was not opened"
  settle
  kill "$(cat "$T/server")" 2>/dev/null
  [ "$(opened)" = "https://localhost:$dead/" ] || fail "the Board started on a fresh install did not open once, on localhost: $(opened)"
}

# The live summary a claim prints while the Board is being started in the background ends, and says "wait: pid N is
# not a child of this shell" at most once. Bug (#1239): the claim's context runs the live summary in a subshell that
# inherits the claim's background start, and its bare `wait` then looped on that line for ever and wrote gigabytes.
# The limit is a timeout, so a loop ends the case; the stderr is cut to 100 lines, so a loop cannot fill the disk.
t_live() {
  fixture live
  local dead rc n; dead=$(free_port)
  export CONVEYOR_BOARD_START_CMD=true
  CONVEYOR_DASHBOARD_PORT=$dead timeout 20 bash "$SRC/foreman.sh" claim s1 2>&1 >"$T/live.out" | head -n 100 > "$T/live.err"; rc=${PIPESTATUS[0]}
  [ "$rc" = 0 ] || fail "the claim with its live summary did not end within its 20 s limit (status $rc): $(head -c 400 "$T/live.err")"
  n=$(grep -c 'is not a child of this shell' "$T/live.err")
  [ "$n" -le 1 ] || fail "the live summary printed the wait line $n times: $(head -c 400 "$T/live.err")"
  grep -q '^# Live summary' "$T/live.out" || fail "the claim did not print the live summary: $(head -c 400 "$T/live.out")"
}

cases=(once again off down fresh live)
# The cases CONVEYOR_SHELL_TEST_CASE names (comma-separated), as the runner selects them; all of them with none set.
SEL=${CONVEYOR_SHELL_TEST_CASE:-${cases[*]}}; SEL=${SEL//,/ }
for c in $SEL; do case " ${cases[*]} " in *" $c "*) ;; *) echo "unknown case $c" >&2; exit 2 ;; esac; done
read -ra cases <<<"$SEL"
pids=()
for c in "${cases[@]}"; do (t_"$c" && : > "$B/$c.passed") > "$B/$c.out" 2>&1 & pids+=($!); done
[ ${#pids[@]} = 0 ] || wait "${pids[@]}" # with no pid, wait waits for the Board's server too
. "$SRC/casesreport.sh"
casesreport "$B" board-open- "${cases[@]}" || exit 1
echo "ok [board-open]"
