#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Pins when a session opens the Board: only a fresh start (source startup) in a repo with a pack, with the plugin
# option on, opens it, once, on localhost. A resume, clear or compact would stack another tab each time, a
# repo with no pack has no Board of its own, and a card session must never open one: it runs headless on the loop.
# The opener (open / xdg-open) is a stub that records what it was asked to open. Each case runs the command
# hooks/hooks.json registers, so through shim.sh and the pinned install it resolves, as Claude Code runs it.
set -u
SRC=$(cd "$(dirname "$0")/../../.." && pwd)
CMD=$(jq -r '.hooks.SessionStart[].hooks[].command | select(test("board-open"))' "$SRC/hooks/hooks.json")
PIN=0123456789abcdef0123456789abcdef01234567
T=$(mktemp -d); PORTS_LSN=''
trap 'kill $PORTS_LSN $(cat "$T/server" 2>/dev/null) 2>/dev/null; rm -rf "$T"' EXIT
mkdir -p "$T/bin" "$T/repo/.conveyor" "$T/bare" "$T/config/conveyor" "$T/data/conveyor/versions/$PIN/.claude/hooks/lib"
cp "$SRC/.claude/hooks/board-open.sh" "$T/data/conveyor/versions/$PIN/.claude/hooks/"
cp "$SRC/.claude/hooks/lib/board-open.sh" "$T/data/conveyor/versions/$PIN/.claude/hooks/lib/"
jq -n --arg c "$PIN" '{plugin: {commit: $c}}' > "$T/repo/.conveyor/project.json"
# A Conveyor project is a git checkout: outside one the plugin's hooks do nothing (plugin-hooks.test.sh).
git init -q "$T/repo"
echo '{}' > "$T/config/conveyor/host.json"
for o in open xdg-open; do printf '#!/usr/bin/env bash\necho "$1" >> %q\n' "$T/opened" > "$T/bin/$o"; chmod +x "$T/bin/$o"; done
# One process gives every port the cases use: a free one for the Board, then two it holds for the cases on other
# services: RAW accepts connections and never answers, FULL has its accept queue full, so a connect to it waits on.
python3 -I -c 'import socket, time
def bound():
    s = socket.socket(); s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1); s.bind(("127.0.0.1", 0)); return s
free = socket.socket(); free.bind(("127.0.0.1", 0))
raw, full = bound(), bound()
raw.listen(8); full.listen(0)
cs = [socket.socket() for _ in range(3)]
for c in cs:
    c.setblocking(False)
    try: c.connect(full.getsockname())
    except BlockingIOError: pass
ports = [s.getsockname()[1] for s in (free, raw, full)]
free.close()
print(*ports, flush=True)
time.sleep(600)' > "$T/ports" & PORTS_LSN=$!
for _ in $(seq 50); do [ -s "$T/ports" ] && break; sleep 0.1; done
read -r PORT RAW FULL < "$T/ports"
# The Board's own page server (the first case starts it), with its login store and certificate in this test's folder.
# It runs on the Board's own virtualenv (conveyor.sh setup fills it), never the system Python.
PY=${XDG_DATA_HOME:-$HOME/.local/share}/conveyor/board-venv/bin/python3
export CONVEYOR_DASHBOARD_AUTH=$T/auth/dashboard-auth.json
mkdir -p "$T/auth" "$T/out"
# The login page is the served folder's login.html, which the Board's install copies there.
cp "$SRC/.claude/dashboard/login.html" "$T/out/"
"$PY" "$SRC/.claude/scripts/dashboard_server.py" make-cert >/dev/null \
  || { echo "FAIL: the Board's page server on $PY cannot run (does its virtualenv lack its packages? run conveyor.sh setup)" >&2; exit 1; }

PASS=0 FAIL=0
. "$(dirname "${BASH_SOURCE[0]}")/lib/said.sh" # a FAIL line names the hook's last input (start notes each payload)
check() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); echo "ok   $1"; else FAIL=$((FAIL+1)); echo "FAIL $1 (expected $2, got $3)$(said)"; fi }
# start <source> <project> [<option value>|-] [<port>]: runs the registered command as a session start in <project>;
# prints its output and errors, then what the opener was given (one line each, after a moment for the background
# opener). How long the hook held the start, in milliseconds, is left in $T/took.
start() {
  rm -f "$T/opened"
  local t0=${EPOCHREALTIME/./}
  local opt=(); [ "${3:--}" = - ] || opt=("CLAUDE_PLUGIN_OPTION_boardAutoOpen=$3")
  # printf, not jq: the source and the mktemp path hold no character JSON escapes.
  printf '{"hook_event_name":"SessionStart","source":"%s","cwd":"%s"}' "$1" "$2" | said_tee \
    | (cd "$2" && env -u CLAUDE_PLUGIN_OPTION_boardAutoOpen "${opt[@]}" PATH="$T/bin:$PATH" CLAUDE_PROJECT_DIR="$2" \
        CLAUDE_PLUGIN_ROOT="$SRC" XDG_DATA_HOME="$T/data" XDG_CONFIG_HOME="$T/config" CONVEYOR_DASHBOARD_PORT="${4:-$PORT}" \
        bash -c "$CMD" 2>&1)
  echo "rc=$?"
  echo $(( (${EPOCHREALTIME/./} - t0) / 1000 )) > "$T/took"
  sleep 0.5
  [ ! -f "$T/opened" ] || sed 's/^/opened /' "$T/opened"
}

# A Board that is not running is started first, from the project's checkout, then opened (the owner's rule, #106).
# Bug: the start only said the Board was not running. The start is a stub that records where it ran and serves the
# Board's own page on the port, as `conveyor.sh board` would; the Board it starts serves the later cases on $PORT (the RAW and FULL cases
# pass a listener of their own).
down=$(CONVEYOR_BOARD_START_CMD="pwd -P > '$T/started'; '$PY' '$SRC/.claude/scripts/dashboard_server.py' $PORT '$T/out' >/dev/null 2>&1 & echo \$! > '$T/server'" \
  start startup "$T/repo" true | head -n 1)
check "a Board that is not running is named in one line, with the start's output file" yes \
  "$([[ $down == "conveyor: the Board is not running (nothing serves https://localhost:$PORT/), so conveyor.sh board starts it; it opens when it answers (the start's output: "*")" ]] && echo yes || echo "no, $down")"
for _ in $(seq 100); do [ -s "$T/opened" ] && break; sleep 0.1; done
check "it is started from the project's checkout" "$(cd "$T/repo" && pwd -P)" "$(cat "$T/started" 2>/dev/null)"
check "and opened once it answers, on localhost" "https://localhost:$PORT/" "$(cat "$T/opened" 2>/dev/null)"
check "option on, a pack and a fresh start open the Board once, on localhost" \
  "rc=0|opened https://localhost:$PORT/" "$(start startup "$T/repo" true | paste -sd'|')"
check "the option unset (its default) opens it too" \
  "rc=0|opened https://localhost:$PORT/" "$(start startup "$T/repo" | paste -sd'|')"
echo '{"board": {"lan": true}}' > "$T/config/conveyor/host.json"
# Bug caught (#108): with LAN on, a new Board (no password yet) opened at the LAN name, where "No login on this device"
# does not let this machine in, so the tab showed a login no one could pass. While that setting is on, localhost opens.
check "a host file that says LAN, with No login on this device on (its default), opens the Board on localhost" \
  "rc=0|opened https://localhost:$PORT/" "$(start startup "$T/repo" true | paste -sd'|')"
# The owner's rule (#106): the open always uses localhost, never the LAN name, whatever the login settings are.
echo '{"noLoginHere": false}' > "$CONVEYOR_DASHBOARD_AUTH"
check "a host file that says LAN, with No login on this device off, still opens the Board on localhost" \
  "rc=0|opened https://localhost:$PORT/" "$(start startup "$T/repo" true | paste -sd'|')"
rm -f "$CONVEYOR_DASHBOARD_AUTH"
echo '{}' > "$T/config/conveyor/host.json"
check "option off opens nothing" "rc=0" "$(start startup "$T/repo" false | paste -sd'|')"
for s in resume clear compact; do
  check "a $s start opens nothing (no stacked tabs)" "rc=0" "$(start "$s" "$T/repo" true | paste -sd'|')"
done
# No pack, so no pin: the shim would fail the start with "pins no Conveyor Belt commit" if the command reached it.
check "a repo with no pack opens nothing and reports no error" "rc=0" "$(start startup "$T/bare" true | paste -sd'|')"
# Another service on the Board's port is not the Board: a listener that accepts connections and never answers must
# not open a tab, even once the background check gives up (its two-second limit).
check "another service listening on the port is not the Board: the start is not held for it" \
  "rc=0" "$(start startup "$T/repo" true "$RAW" | paste -sd'|')"
took=$(<"$T/took")
check "and the hook returns within a second, not after the check's two-second limit" yes \
  "$([ "$took" -lt 1000 ] && echo yes || echo "no, $took ms")"
sleep 2.5
check "and nothing opens once its check gives up" no "$([ -f "$T/opened" ] && echo yes || echo no)"
# Another HTTPS service serving the very same login page, under a certificate of its own, is not the Board either:
# the page alone can be copied, the Board's certificate cannot. The Board's page server on $PORT plays that service:
# the hook is given a login store whose certificate is another one, made as make-cert makes it, so the page answers
# under a certificate that is not the one the hook trusts (the first cases show that server serves the page).
mkdir -p "$T/forge/dashboard-tls"
openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:P-256 -pkeyopt ec_param_enc:named_curve -nodes -days 1 \
  -keyout "$T/forge/dashboard-tls/key.pem" -out "$T/forge/dashboard-tls/cert.pem" -subj /CN=localhost \
  -addext subjectAltName=DNS:localhost,IP:127.0.0.1 2>/dev/null
FORGED=$T/forge/dashboard-auth.json
# Bug caught (#183): a listener that failed the certificate check was named "nothing serves", untrue for a running
# Board whose certificate curl cannot check; the line says what failed, with curl's exit (60: an unknown issuer).
CERTFAIL="conveyor: something answers on https://localhost:$PORT/ but fails the check of the Board's certificate (curl exit 60), so it was not opened; fix: run conveyor.sh board in the project's checkout, which replaces a certificate that does not name its curve and restarts the Board|rc=0"
check "another HTTPS service serving the Board's login page under its own certificate: named in one line, nothing opens" \
  "$CERTFAIL" "$(CONVEYOR_DASHBOARD_AUTH=$FORGED start startup "$T/repo" true | paste -sd'|')"
# A curl configuration that turns certificate checks off must not let the forged service through either.
mkdir -p "$T/curlhome"; echo insecure > "$T/curlhome/.curlrc"
check "the forged service, with the user's curl configuration saying insecure, still opens nothing" \
  "$CERTFAIL" \
  "$(CURL_HOME=$T/curlhome CONVEYOR_DASHBOARD_AUTH=$FORGED start startup "$T/repo" true | paste -sd'|')"
# A listener whose accept queue is full: a connect to it waits on, so the hook must not wait for it to hold the start.
check "a Board whose accept queue is full does not hold the start" "rc=0" \
  "$(start startup "$T/repo" true "$FULL" | paste -sd'|')"
took=$(<"$T/took")
check "and the hook returns within a second, not after the check's two-second limit" yes \
  "$([ "$took" -lt 1000 ] && echo yes || echo "no, $took ms")"
sleep 2.5
check "and nothing opens once its check gives up" no "$([ -f "$T/opened" ] && echo yes || echo no)"

# A card session opens no Board: it is launched with no setting sources (so no plugin and its SessionStart hook;
# conveyor/tests codex.test.sh t_codexclaude and opencode.test.sh t_opencodeclaude check the launch args), and the
# settings it is given carry no such hook (conveyor/tests/rules.test.sh t_packrules).

echo; echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
