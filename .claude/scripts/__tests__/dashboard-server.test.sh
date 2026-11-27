#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# The dashboard's page server is the one thing on the home LAN that accepts a write. These cases hold the
# boundary: nothing in the served folder is writable, the only writes are an answer to an open decision and the
# collector restart, and every other request changes nothing.
set -uo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
# This file's own timeout is a GNU call: on macOS it runs Homebrew's, as Conveyor's does (portable.sh).
. "$HERE/../../../conveyor/lib/portable.sh"; p_tools
. "$HERE/../../../conveyor/tests/wait.sh"
SRV=$HERE/../dashboard_server.py
# The server runs on the Board's own virtualenv (conveyor.sh setup fills it), found before HOME is the test's own;
# XDG_DATA_HOME is kept for dashboard.sh, which finds it the same way.
export XDG_DATA_HOME=${XDG_DATA_HOME:-$HOME/.local/share}
PY=$XDG_DATA_HOME/conveyor/board-venv/bin/python3
"$PY" -c 'import pyotp, segno, cryptography' || { echo "FAIL: the Board's virtualenv $PY lacks its packages: run conveyor.sh setup" >&2; exit 1; }
# The parts below run side by side, each on a server of its own, so the file takes its slowest part's time, not their
# sum. Each part's folders are under $TOP/<part>; PORTS holds a port for each, taken at once so no two are the same.
TOP=$(mktemp -d)
PORTS=($(python3 -c 'import socket
ss = [socket.socket() for _ in range(11)]
for s in ss: s.bind(("127.0.0.1", 0))
print(" ".join(str(s.getsockname()[1]) for s in ss))'))
# A stand-in for the owner's real host: the host file in the home this test is run from, naming a checkout whose
# conveyor.sh records every call and whose control record must come through untouched. Every part runs under it.
RH=$(mktemp -d)
mkdir -p "$RH/.config/conveyor" "$RH/main/conveyor/state"
printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$*" >> "%s/calls"\n' "$RH" > "$RH/main/conveyor/conveyor.sh"
chmod +x "$RH/main/conveyor/conveyor.sh"
echo '{"mode":"pause","cap":20,"guard":98,"held":[7,8]}' > "$RH/main/conveyor/state/control.json"
cp "$RH/main/conveyor/state/control.json" "$RH/control.before"
jq -n --arg m "$RH/main" '{host: "realhost", ssh: "user@realhost", main: $m}' > "$RH/.config/conveyor/host.json"
export HOME=$RH; unset XDG_CONFIG_HOME
PW='correct horse battery'
# A password /login's 4096-byte body cannot carry.
TOOLONG=$(head -c 5000 /dev/zero | tr '\0' a)
trap 'chmod -R u+w "$TOP"; rm -rf "$TOP" "$RH"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }
[ -f "$SRV" ] || fail "no page server at $SRV"
# fresh <part> <port> -- the part's own folders, server port and stubs, its pass count, and its server ended when it
# ends. T is the served folder; M holds the decisions ledger and ruling log the answer address writes, outside the
# served tree; A holds the login store and the certificate, beside each other, outside the served folder, as in the
# real layout.
fresh() {
  T=$TOP/$1/t M=$TOP/$1/m A=$TOP/$1/a PORT=$2 PID='' pass=0
  trap '[ -z "$PID" ] || kill "$PID" 2>/dev/null' EXIT
  mkdir -p "$T" "$M/.claude/metrics" "$A"
  # This machine's host file (XDG_CONFIG_HOME, else HOME/.config) wins over the checkout's conveyor/host.json, so the
  # owner's real one would point every POST /control at the live loop. Bug: a run sent a real pause. Both are this
  # test's own folders, for the server and everything it runs.
  export HOME=$M/home XDG_CONFIG_HOME=$M/config
  mkdir -p "$HOME" "$XDG_CONFIG_HOME"
  export CONVEYOR_DASHBOARD_AUTH=$A/dashboard-auth.json
  # Every request below comes from this machine (127.0.0.1), which "No login on this device" lets in with no login
  # when it is on; it is off here, so these cases hold the login as every other device meets it. The setting itself
  # is dashboard-server-local.test.sh's.
  echo '{"noLoginHere": false}' > "$CONVEYOR_DASHBOARD_AUTH"
  CERT=$A/dashboard-tls/cert.pem JAR=$A/jar AU=$A/dashboard-audit.jsonl
  mkdir -p "$T/out" && echo page > "$T/out/index.html" && echo secret > "$T/outside"
  # The login page and the files it loads, as dashboard.sh copies them into the served folder.
  cp "$HERE"/../../dashboard/{login.html,login.js,app.css,icon.svg} "$T/out/"
  # An orca-ide stub on PATH records every call in sends: an answer is recorded in the ledger and the ruling log and
  # sent to no pane.
  F=$M/fake; mkdir -p "$F" "$M/bin" "$M/ws/Chief-of-Staff"
  printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$*" >> "%s/sends"\necho "{\\"ok\\":true}"\n' "$F" > "$M/bin/orca-ide"
  chmod +x "$M/bin/orca-ide"
  : > "$F/sends"
  U=https://127.0.0.1:$PORT H=127.0.0.1:$PORT L=$M/ledgers/sample/decisions.jsonl
}
# ready -- what every part but the first begins with: a certificate, the first user (max, the admin), the server, and
# max logged in on this browser ($JAR, trusted).
ready() {
  cli make-cert >/dev/null || fail "ready: could not make the certificate"
  printf '%s\n%s\n' "$PW" "$PW" | cli add-user max >/dev/null || fail "ready: could not add max"
  serve
  [ "$(login "$JAR" true main-test)" = 200 ] || fail "ready: max could not log in: $(cat "$M/login.out")"
}
# done_part -- the part ran to its end: its pass count, for the file's total.
done_part() { echo "$pass" > "$T/../pass"; }
serve() { PATH="$M/bin:$PATH" XDG_CONFIG_HOME=$M/config CONVEYOR_MAIN=$M CONVEYOR_RULING_LOG=$M/rulings.jsonl CONVEYOR_WORKSPACES=$M/ws CONVEYOR_SCRATCH=$M/scratch "$PY" "$SRV" "$PORT" "$T/out" 2>>"$M/server.err" & PID=$!
  wait_until 'command curl -s --cacert "$CERT" -o /dev/null "https://127.0.0.1:$PORT/login" || ! kill -0 "$PID" 2>/dev/null'; }
# Every request below is made by the logged-in browser: the certificate is trusted and the cookie jar holds the login.
curl() { command curl --cacert "$CERT" -b "$JAR" "$@"; }
# bare <curl args> -- the same request from a browser that has not logged in.
bare() { command curl --cacert "$CERT" "$@"; }
# login <jar> <trust true|false> <label> [password] [user] -- prints the status; the body is in $M/login.out.
login() {
  command curl -s --cacert "$CERT" -c "$1" -o "$M/login.out" -w '%{http_code}\n' -X POST -H "Origin: $U" -H 'Content-Type: application/json' \
    --data-binary "{\"user\":\"${5:-max}\",\"password\":\"${4:-$PW}\",\"trust\":$2,\"label\":\"$3\"}" "$U/login"
}
cli() { "$PY" "$SRV" "$@"; }
mode() { python3 -c 'import os, sys; print(oct(os.stat(sys.argv[1]).st_mode & 0o777)[2:])' "$1"; }
# snap -- one checksum over everything a write could reach: the served folder, the ledger, the ruling log, the unsent folder.
snap() { { find "$T" -type f | LC_ALL=C sort | xargs cat; cat "$L" "$M/rulings.jsonl" 2>/dev/null; ls "$M/dashboard-unsent" 2>/dev/null; } | cksum; }
# routes_refused <case> -- no login: every page is a redirect to /login with no body, every write is a 401, and nothing moved.
routes_refused() {
  local before p m got f
  before=$(snap)
  for p in / /index.html /data.js /panels/belt.js /nope/x; do
    for m in GET HEAD; do
      f=(); [ "$m" = HEAD ] && f=(-I)
      got=$(bare -s ${f[@]+"${f[@]}"} --path-as-is -o /dev/null -w '%{http_code} %{redirect_url} %{size_download}' "$U$p")
      [ "$got" = "302 $U/login 0" ] || fail "$1: $m $p answered '$got', want 302 to /login with no body"
      pass=$((pass + 1))
    done
  done
  got=$(bare -s -o /dev/null -w '%{http_code}' -X PUT -H "Origin: $U" -H 'Content-Type: application/json' --data-binary 'window.DASH = {};' "$U/data.js")
  [ "$got" = 501 ] || fail "$1: PUT /data.js answered $got, want 501"
  got=$(bare -s -o "$M/r.out" -w '%{http_code}' -X POST -H "Origin: $U" -H 'Content-Type: application/json' \
    --data-binary '{"id":"d-ship","answer":"yes","askedAt":"2026-10-18T12:00:00Z"}' "$U/answer")
  [ "$got" = 401 ] && grep -q 'log in to answer' "$M/r.out" || fail "$1: POST /answer answered $got '$(cat "$M/r.out")', want 401 'log in to answer'"
  [ "$(snap)" = "$before" ] || fail "$1: a refused request changed the served folder, ledger, ruling log or unsent folder"
  pass=$((pass + 3))
}
# dash <updatedAt> <cards> -- a new data.js in the served folder, written whole.
dash() { printf 'window.DASH = {"updatedAt":"%s","panels":{"belt":{"error":null,"data":{"cards":%s}},"health":{"error":null,"data":{"n":1}}}};\n' "$1" "$2" > "$T/out/.d" && mv "$T/out/.d" "$T/out/data.js"; }
nlines() { wc -l < "$1" | tr -d ' '; }
PARTS=()
started() { PARTS+=("$1:$!"); } # <part>, after its ( ... ) &

( fresh basics "${PORTS[0]}"
# No certificate, no server: it never falls back to plain HTTP.
"$PY" "$SRV" "$PORT" "$T/out" >/dev/null 2>"$M/nocert.err" & NC=$!
wait_until '! kill -0 "$NC" 2>/dev/null'
if kill -0 "$NC" 2>/dev/null; then kill "$NC"; fail "no_certificate_refuses_to_start: the server kept running with no certificate"; fi
wait "$NC" && fail "no_certificate_refuses_to_start: it exited 0"
grep -q 'no certificate: run dashboard_server.py make-cert' "$M/nocert.err" || fail "no_certificate_refuses_to_start: said '$(cat "$M/nocert.err")'"
pass=$((pass + 2))
# An openssl first on PATH that writes as LibreSSL (macOS's /usr/bin/openssl) does: a req not told
# ec_param_enc:named_curve writes the curve's explicit parameters. Bug caught (#183): macOS's curl rejects that
# certificate, so the Board never opened, and make-cert kept the bad certificate on every install.
mkdir -p "$M/libressl" && printf '#!/usr/bin/env bash\nif [ "$1" = req ] && [[ " $* " != *" ec_param_enc:named_curve "* ]]; then set -- "$@" -pkeyopt ec_param_enc:explicit; fi\nexec %q "$@"\n' \
  "$(type -P openssl)" > "$M/libressl/openssl" && chmod +x "$M/libressl/openssl" || fail "make-cert: the openssl wrapper was not made"
named() { openssl x509 -in "$CERT" -noout -text | grep -q 'ASN1 OID: prime256v1'; }
PATH=$M/libressl:$PATH cli make-cert >/dev/null || fail "make-cert: could not make the certificate"
named || fail "make_cert_names_its_curve: under a LibreSSL-like openssl the key does not name prime256v1"
[ "$(mode "$A/dashboard-tls/key.pem")" = 600 ] || fail "make-cert: the key is not mode 0600"
openssl x509 -in "$CERT" -noout -ext subjectAltName | grep -q 'DNS:localhost.*IP Address:127.0.0.1' || fail "make-cert: the certificate does not name localhost and 127.0.0.1"
# A kept certificate with explicit parameters (made before the fix) is made again with no --force.
"$M/libressl/openssl" req -x509 -newkey ec -pkeyopt ec_paramgen_curve:P-256 -nodes -days 1 -keyout "$A/dashboard-tls/key.pem" -out "$CERT" -subj /CN=localhost 2>/dev/null \
  && ! named || fail "make-cert: the explicit-parameter certificate was not made"
PATH=$M/libressl:$PATH cli make-cert >/dev/null && named || fail "explicit_certificate_made_again: make-cert kept a certificate whose key does not name prime256v1"
SUM=$(cksum < "$CERT")
cli make-cert >/dev/null && [ "$(cksum < "$CERT")" = "$SUM" ] || fail "make-cert: a second run with no --force must keep the certificate"
cli make-cert --force >/dev/null && [ "$(cksum < "$CERT")" != "$SUM" ] || fail "make-cert: --force must make a new certificate"
# A certificate that names its curve but does not load with its key: the server exits at once on it. Bug caught
# (#200): make-cert kept it, so the Board's loop restarted a server that failed on every start.
SUM=$(cksum < "$CERT"); : > "$A/dashboard-tls/key.pem"
got=$(cli make-cert) && [ "$(cksum < "$CERT")" != "$SUM" ] && "$PY" -c 'import ssl, sys; ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER).load_cert_chain(*sys.argv[1:])' "$CERT" "$A/dashboard-tls/key.pem" \
  && [[ $got == "certificate $CERT cannot be loaded with its key "* ]] || fail "unloadable_certificate_made_again: make-cert said '$got' and left a certificate that does not load"
pass=$((pass + 7))
serve
# No password set: login refuses with the way to set one, and nothing else opens.
got=$(login "$A/none" false x); [ "$got" = 503 ] && grep -q 'no dashboard user: run dashboard_server.py add-user <user> --admin' "$M/login.out" \
  || fail "no_password_set_refuses_answers: login answered $got '$(cat "$M/login.out")'"
routes_refused no_password_set_refuses_answers
printf '%s\n%s\n' short short | cli add-user max >/dev/null 2>&1 && fail "set_password: took a 5-character password"
# A password /login's 4096-byte body cannot carry would lock its user out.
printf '%s\n%s\n' "$TOOLONG" "$TOOLONG" | cli add-user max >/dev/null 2>&1 && fail "set_password: took a password too long to log in with"
# The first user is admin, though --admin was not given.
printf '%s\n%s\n' "$PW" "$PW" | cli add-user max >/dev/null || fail "set_password: refused a good password"
[ "$(mode "$CONVEYOR_DASHBOARD_AUTH")" = 600 ] || fail "set_password: the store is not mode 0600"
[ "$(jq -r .users.max.role "$CONVEYOR_DASHBOARD_AUTH")" = admin ] || fail "first_user_is_admin: $(jq -c '.users.max.role' "$CONVEYOR_DASHBOARD_AUTH")"
pass=$((pass + 5))
[ "$(login "$A/wrong" false x 'wrong password here')" = 401 ] || fail "wrong_password_refused: want 401"
[ "$(login "$JAR" true main-test)" = 200 ] || fail "login: the right password was refused: $(cat "$M/login.out")"
# The login page calls the device name optional and sends it empty when it is left blank.
[ "$(login "$A/nolabel" false '')" = 200 ] || fail "login_with_no_device_name: $(cat "$M/login.out")"
pass=$((pass + 3))
[ "$(curl -s "$U/index.html")" = page ] || fail "serves_the_page: the page is still served"; pass=$((pass + 1))
# A browser's own guess at freshness kept an old app.js running after an update; every file is revalidated.
mkdir -p "$T/out/panels" && echo belt > "$T/out/panels/belt.js" && echo 'window.DASH = {};' > "$T/out/data.js"
# grep reads every header rather than -q stopping at its match: under pipefail, curl's write of the lines after the
# match then failed the check at random on a busy machine. A curl that really fails still fails the check.
for f in index.html data.js panels/belt.js; do
  curl -s -D - -o /dev/null "$U/$f" | grep -i '^cache-control: no-cache' >/dev/null || fail "files_are_revalidated: $f is served without Cache-Control: no-cache"; pass=$((pass + 1))
done
[ "$(curl -s "$U/panels/belt.js")" = belt ] || fail "serves_the_panel_files: a panel's file is served from its folder"; pass=$((pass + 1))
# A browser refuses to run a module (Belt 3D's vendored three.js) served without a JavaScript type.
mkdir -p "$T/out/vendor/three" && echo 'export {};' > "$T/out/vendor/three/three.module.min.js"
curl -s -D - -o /dev/null "$U/vendor/three/three.module.min.js" | grep -i '^content-type: text/javascript' >/dev/null \
  || fail "serves_modules_as_javascript: $(curl -s -D - -o /dev/null "$U/vendor/three/three.module.min.js" | grep -i '^content-type')"; pass=$((pass + 1))
rm -r "$T/out/vendor"
# GET /events, the page's live feed. Without a login it is refused; with one it opens with the whole of data.js
# and then sends, as data.js changes, the one panel that changed; a page that connects again gets the whole again.
dash 2026-11-10T12:00:00Z '[]'
got=$(bare -s -o "$M/ev.out" -w '%{http_code}' --max-time 5 "$U/events")
[ "$got" = 401 ] && ! grep -q DASH "$M/ev.out" && ! grep -q 'event:' "$M/ev.out" || fail "events_refused_without_login: answered $got '$(head -c 200 "$M/ev.out")'"
pass=$((pass + 1))
# The feed's keep-alive is a day away here, so a change that reaches the page was sent as it came, at whatever pace
# the machine runs.
kill "$PID"; wait "$PID" 2>/dev/null; CONVEYOR_DASHBOARD_PING=86400 serve
curl -sN "$U/events" > "$M/ev1" 2>/dev/null & EV=$!
wait_until 'grep -q "^event: snapshot" "$M/ev1" || ! kill -0 "$EV" 2>/dev/null'
grep -A1 '^event: snapshot' "$M/ev1" | grep -q '"updatedAt":"2026-11-10T12:00:00Z"' || fail "events_open_with_a_snapshot: $(head -c 400 "$M/ev1")"
dash 2026-11-10T12:00:05Z '[{"card":"c1"}]'
wait_until 'grep -q "^event: panel" "$M/ev1" || ! kill -0 "$EV" 2>/dev/null'
grep -q '^event: panel' "$M/ev1" || fail "events_send_a_change_as_it_comes: $(cat "$M/ev1")"
[ "$(grep -A1 '^event: panel' "$M/ev1" | sed -n 's/^data: //p' | jq -sc 'map([.id, .part.data.cards[0].card, .updatedAt])')" = '[["belt","c1","2026-11-10T12:00:05Z"]]' ] \
  || fail "events_send_only_the_panel_that_changed: $(cat "$M/ev1")"
kill "$EV" 2>/dev/null; wait "$EV" 2>/dev/null
curl -sN --max-time 2 "$U/events" > "$M/ev2" 2>/dev/null || true
grep -A1 '^event: snapshot' "$M/ev2" | grep -q '"cards":\[{"card":"c1"}\]' || fail "events_reconnect_gets_the_whole_snapshot: $(head -c 400 "$M/ev2")"
curl -s -D "$M/evh" -o /dev/null --max-time 2 "$U/events" || true
grep -qi '^content-type: text/event-stream' "$M/evh" || fail "events_are_server_sent_events: $(cat "$M/evh")"
kill "$PID"; wait "$PID" 2>/dev/null; serve
kill "$EV" 2>/dev/null; wait "$EV" 2>/dev/null || true
pass=$((pass + 5))
# The page keeps its layout in the browser: the logged-in page itself can write no file, by any method or path.
BEFORE=$(snap)
for m in PUT DELETE PATCH; do
  for path in /layout /data.js /index.html /panels/belt.js '/../outside'; do
    got=$(curl -s --path-as-is -o /dev/null -w '%{http_code}' -X "$m" -H "Origin: $U" -H 'Content-Type: application/json' --data-binary '{"order":["belt"]}' "$U$path")
    case $got in 4*|5*) pass=$((pass + 1)) ;; *) fail "served_folder_is_read_only: $m $path answered $got" ;; esac
  done
done
[ "$(snap)" = "$BEFORE" ] && [ "$(cat "$T/outside")" = secret ] || fail "served_folder_is_read_only: a refused write changed a file"
[ "$(find "$T" -type f | wc -l | tr -d ' ')" = 8 ] || fail "served_folder_is_read_only: a stray file was written: $(find "$T" -type f)"
pass=$((pass + 2))
# With every file in place, still nothing opens without the login.
routes_refused every_route_needs_login
[ "$(bare -s -o /dev/null -w '%{http_code}' "$U/login")" = 200 ] || fail "login_page_is_public: GET /login with no cookie is not 200"
[ "$(bare -s -o /dev/null -w '%{http_code}' -I "$U/login")" = 200 ] || fail "login_page_is_public: HEAD /login with no cookie is not 200"
pass=$((pass + 2))
# GET /history (#524): the older entries the snapshot no longer carries, as dashboard.sh --history gives them (here its
# copy of the last minute); behind the login; a history it cannot give is a 502 that says why, never an empty one.
kill "$PID"; wait "$PID" 2>/dev/null; CONVEYOR_DASHBOARD_DIR=$T/out serve
[ "$(bare -s -o /dev/null -w '%{http_code}' "$U/history")" = 401 ] || fail "history_needs_login"
mkdir -p "$T/out/cache" && echo '{"updatedAt":"2026-11-10T12:00:00Z","panels":{"landed":{"error":null,"data":{"day":"2026-11-10","cards":[]}}}}' > "$T/out/cache/history.json"
[ "$(curl -s "$U/history" | jq -c .panels.landed.data.day)" = '"2026-11-10"' ] || fail "history_gives_dashboard_history: $(curl -s "$U/history" | head -c 300)"
rm -r "$T/out/cache"
got=$(curl -s -o "$M/hist.out" -w '%{http_code}' "$U/history")
[ "$got" = 502 ] && grep -q 'no history: this checkout has no conveyor/host.json' "$M/hist.out" || fail "history_failure_is_a_502_with_why: $got $(cat "$M/hist.out")"
kill "$PID"; wait "$PID" 2>/dev/null; serve
pass=$((pass + 3))
# The login page is the Board's: its stylesheet and icon, its title, and no host project's name. A browser with no
# login loads those files and the page's script, and nothing else.
bare -s -o "$M/login.html" "$U/login"
grep -qF '<link rel="stylesheet" href="app.css">' "$M/login.html" && grep -qF '<link rel="icon" type="image/svg+xml" href="icon.svg">' "$M/login.html" \
  && grep -qF '<title>Conveyor Board</title>' "$M/login.html" && grep -qF '<script src="login.js"></script>' "$M/login.html" \
  || fail "login_page_uses_the_boards_style: $(head -c 600 "$M/login.html")"
! grep -qi push''prove "$M/login.html" "$HERE/../../dashboard/login.js" || fail "login_page_names_no_host_project"
for f in app.css icon.svg login.js; do
  [ "$(bare -s -o "$M/pub" -w '%{http_code}' "$U/$f")" = 200 ] && cmp -s "$M/pub" "$T/out/$f" || fail "login_files_are_public: /$f"
done
[ "$(bare -s -o /dev/null -w '%{http_code}' "$U/login.html")" = 302 ] && [ "$(bare -s -o /dev/null -w '%{http_code}' "$U/account.js")" = 302 ] \
  || fail "only_the_login_files_are_public"
pass=$((pass + 6))
done_part
) & started basics

# Both writes come from the page's own address only. A JSON content type forces another site's page to
# ask first, the Origin must be the page's own, and the Host must be a name another site cannot point at this
# machine (DNS rebinding: its page then has a matching Origin), on this server's port.
# send <want> <case> <method> <path> <body> <content-type> <origin or -> <host>
send() {
  # curl matches cookies on the Host header it is given, so the login travels as an explicit header here.
  local got h=(-H "Content-Type: $6" -H "Host: $8" -H "Cookie: $(awk '$6 ~ /^pp_/ {printf "%s%s=%s", s, $6, $7; s = "; "}' "$JAR")")
  [ "$7" = - ] || h+=(-H "Origin: $7")
  got=$(curl -s -o "$M/send.out" -w '%{http_code}' -X "$3" "${h[@]}" --data-binary "$5" "$U$4")
  [ "$got" = "$1" ] || fail "$2: $3 $4 answered $got, want $1: $(cat "$M/send.out")"
  pass=$((pass + 1))
}

# POST /answer answers one open decision, at the snapshot the page read, and logs the ruling. The decision is in the
# ledger the host file's record names (records[].ledger), never the server's own checkout's: the page names the record.
ASKED=2026-10-18T12:00:00Z
dec() { printf '{"id":"%s","askedAt":"%s","question":"%s","proposedDefault":"wait a day","source":"main","answeredAt":null,"answer":null}\n' "$@"; }
ans() { printf '{"id":"%s","answer":"%s","askedAt":"%s","repo":"%s"}' "$1" "$2" "$3" "${4:-sample}"; }
J=application/json
# ledgers -- two projects' ledgers, each with a decision d-ship open, and a project with none; no ruling yet.
ledgers() {
  L2=$M/ledgers/widgetshop/decisions.jsonl
  mkdir -p "${L%/*}" "${L2%/*}" "$M/conveyor"
  jq -n --arg l "$L" --arg l2 "$L2" '{records: [{repo: "sample", ledger: $l}, {repo: "widgetshop", ledger: $l2}, {repo: "noledger"}]}' > "$M/conveyor/host.json"
  { dec d-ship "$ASKED" 'Ship it?'; dec d-other "$ASKED" 'Other?'; } > "$L"
  dec d-ship "$ASKED" 'Ship the shop?' > "$L2"
  : > "$M/rulings.jsonl"
}

( fresh answers "${PORTS[1]}"; ready; ledgers
send 403 answer_without_origin_refused POST /answer "$(ans d-ship yes "$ASKED")" $J - "$H"
send 403 answer_from_another_origin_refused POST /answer "$(ans d-ship yes "$ASKED")" $J https://evil.example "$H"
send 403 answer_from_a_rebinding_name_refused POST /answer "$(ans d-ship yes "$ASKED")" $J "https://evil.example:$PORT" "evil.example:$PORT"
send 403 answer_as_a_form_refused POST /answer "$(ans d-ship yes "$ASKED")" text/plain "$U" "$H"
send 403 answer_on_another_path_refused POST /p/x/answer "$(ans d-ship yes "$ASKED")" $J "$U" "$H"
send 400 two_line_answer_refused POST /answer '{"id":"d-ship","answer":"yes\nrm -rf","askedAt":"'$ASKED'","repo":"sample"}' $J "$U" "$H"
send 400 answer_naming_no_project_refused POST /answer '{"id":"d-ship","answer":"yes","askedAt":"'$ASKED'"}' $J "$U" "$H"
send 400 project_like_a_path_refused POST /answer "$(ans d-ship yes "$ASKED" '../x')" $J "$U" "$H"
send 409 project_with_no_ledger_refused POST /answer "$(ans d-ship yes "$ASKED" noledger)" $J "$U" "$H"
grep -qx 'conveyor/host.json names no decision ledger for noledger; nothing recorded' "$M/send.out" || fail "project_with_no_ledger_refused: '$(cat "$M/send.out")'"
send 400 empty_answer_refused POST /answer "$(ans d-ship '' "$ASKED")" $J "$U" "$H"
send 400 id_with_a_space_refused POST /answer "$(ans 'd ship' yes "$ASKED")" $J "$U" "$H"
send 400 id_like_an_option_refused POST /answer "$(ans '--correct' yes "$ASKED")" $J "$U" "$H"
send 400 asked_at_not_a_time_refused POST /answer "$(ans d-ship yes 'yesterday')" $J "$U" "$H"
send 400 unknown_key_refused POST /answer '{"id":"d-ship","answer":"yes","askedAt":"'$ASKED'","repo":"sample","correct":true}' $J "$U" "$H"
send 413 oversized_answer_refused POST /answer "$(ans d-ship "$(head -c 5000 /dev/zero | tr '\0' a)" "$ASKED")" $J "$U" "$H"
# A decision re-asked or reopened since the page read it has a newer askedAt: decision.sh refuses, nothing is logged.
send 409 answer_to_a_reasked_decision_refused POST /answer "$(ans d-ship yes 2026-10-18T11:00:00Z)" $J "$U" "$H"
grep -q 'reopened after this answer read it' "$M/send.out" || fail "answer_to_a_reasked_decision_refused: decision.sh's reason is the body"
[ "$(wc -l < "$L" | tr -d ' ')" = 2 ] && [ "$(wc -l < "$L2" | tr -d ' ')" = 1 ] && [ ! -s "$M/rulings.jsonl" ] || fail "answer_refusals_change_nothing: $(cat "$L" "$L2" "$M/rulings.jsonl")"
pass=$((pass + 3))
# The same decision id in another project is that project's: the answer goes to the ledger its record names.
send 200 answer_goes_to_its_projects_ledger POST /answer "$(ans d-ship 'next week' "$ASKED" widgetshop)" $J "$U" "$H"
jq -e 'select(.id == "d-ship") | .answer == "next week"' <(tail -1 "$L2") >/dev/null && [ "$(wc -l < "$L" | tr -d ' ')" = 2 ] \
  && jq -e '.question == "Ship the shop?"' "$M/rulings.jsonl" >/dev/null && [ ! -e "$M/.claude/metrics/decisions.jsonl" ] \
  || fail "answer_goes_to_its_projects_ledger: $(cat "$L2"); the other ledger $(cat "$L")"
: > "$M/rulings.jsonl"
pass=$((pass + 1))
send 200 answer_is_recorded POST /answer "$(ans d-ship 'ship Monday' "$ASKED")" $J "$U" "$H"
grep -qx 'recorded, ruling r-[0-9]\{8\}-[0-9]\{6\}-1-[0-9a-f]\{6\} logged' "$M/send.out" || fail "answer_is_recorded: reply is '$(cat "$M/send.out")'"
# The row marked owner (decisions.answeredby.jsonl): needsmain() dates a release the owner asked for on the Board; a row
# with no mark is auto's or unknown.
jq -e 'select(.id == "d-ship") | .answer == "ship Monday" and .answeredAt != null' <(tail -1 "$L") >/dev/null \
  && jq -se --argjson r "$(tail -1 "$L")" 'map(select(.row == $r)) | map(.by) == ["owner"]' "${L%.jsonl}.answeredby.jsonl" >/dev/null \
  || fail "answer_is_recorded (as the owner's): POST /answer $(ans d-ship 'ship Monday' "$ASKED") left $(tail -1 "$L") marked $(cat "${L%.jsonl}.answeredby.jsonl" 2>&1)"
jq -se 'length == 1 and (.[0] | (.id | test("^r-[0-9]{8}-[0-9]{6}-1-[0-9a-f]{6}$")) and .source == "dashboard" and .pick == "dashboard" and .user == "max"
  and .question == "Ship it?" and .answer == "ship Monday" and .session == null and .cwd == null and .annotations == null
  and (.utc | test("^[0-9-]{10}T[0-9:]{8}Z$")) and (.et | test(" E[DS]T$")))' "$M/rulings.jsonl" >/dev/null \
  || fail "answer_is_logged_as_a_ruling: $(cat "$M/rulings.jsonl")"
pass=$((pass + 2))
# Bug caught: the answer was handed to send-to-pane.sh, which is archived, so every answer came back 502 "NOT sent".
[ ! -s "$F/sends" ] && [ ! -e "$M/dashboard-unsent/d-ship.json" ] || fail "answer_is_sent_nowhere: no Orca call and no unsent record: $(cat "$F/sends")"
pass=$((pass + 1))
send 409 second_answer_still_refused POST /answer "$(ans d-ship 'no' "$ASKED")" $J "$U" "$H"
grep -q 'already answered' "$M/send.out" || fail "second_answer_still_refused: body is '$(cat "$M/send.out")'"
send 409 second_answer_still_refused POST /answer "$(ans d-ship 'ship Monday' "$ASKED")" $J "$U" "$H"
[ "$(wc -l < "$M/rulings.jsonl" | tr -d ' ')" = 1 ] && [ ! -s "$F/sends" ] \
  || fail "second_answer_still_refused: a refused answer logged a ruling or sent a message"; pass=$((pass + 1))
# A ruling that could not be logged is said, never swallowed: the answer stands, the ruling does not.
chmod 0444 "$M/rulings.jsonl"
send 500 ruling_not_logged_is_loud POST /answer "$(ans d-other 'later' "$ASKED")" $J "$U" "$H"
grep -q 'answer recorded, ruling NOT logged' "$M/send.out" || fail "ruling_not_logged_is_loud: $(cat "$M/send.out")"
jq -e '.id == "d-other" and .answer == "later"' <(tail -1 "$L") >/dev/null || fail "ruling_not_logged_is_loud: the answer stands"
chmod 0644 "$M/rulings.jsonl"
pass=$((pass + 2))

# A record an earlier version kept for an answer it could not pass on. The page posts that answer again: one
# that still stands is cleared, a corrected or reopened one is retired; no ledger row, no ruling, no Orca call.
keep() { mkdir -p "$M/dashboard-unsent"; printf '{"id":"%s","askedAt":"%s","answer":"%s","ruling":"r-old"}\n' "$1" "$ASKED" "$2" > "$M/dashboard-unsent/$1.json"; }
for id in d-left d-fix d-reopen; do dec "$id" "$ASKED" "Question for $id?" >> "$L"; done
CONVEYOR_MAIN=$M CONVEYOR_LEDGER=$L bash "$HERE/../decision.sh" answer d-left go >/dev/null || fail "leftover_unsent_record_cleared: could not answer"
CONVEYOR_MAIN=$M CONVEYOR_LEDGER=$L bash "$HERE/../decision.sh" answer d-fix no >/dev/null || fail "resend_after_correct_retired: could not answer"
CONVEYOR_MAIN=$M CONVEYOR_LEDGER=$L bash "$HERE/../decision.sh" answer d-reopen yes >/dev/null && CONVEYOR_MAIN=$M CONVEYOR_LEDGER=$L bash "$HERE/../decision.sh" reopen d-reopen >/dev/null \
  || fail "resend_after_reopen_retired: could not reopen"
keep d-left go; keep d-fix yes; keep d-reopen yes
ROWS=$(nlines "$L") RULINGS=$(nlines "$M/rulings.jsonl")
send 200 leftover_unsent_record_cleared POST /answer "$(ans d-left go "$ASKED")" $J "$U" "$H"
[ "$(cat "$M/send.out")" = 'recorded, ruling r-old logged' ] && [ ! -e "$M/dashboard-unsent/d-left.json" ] \
  || fail "leftover_unsent_record_cleared: '$(cat "$M/send.out")'"
send 409 resend_after_correct_retired POST /answer "$(ans d-fix yes "$ASKED")" $J "$U" "$H"
[ "$(cat "$M/send.out")" = 'superseded: the decision now says no' ] && [ ! -e "$M/dashboard-unsent/d-fix.json" ] \
  || fail "resend_after_correct_retired: '$(cat "$M/send.out")'"
send 409 resend_after_reopen_retired POST /answer "$(ans d-reopen yes "$ASKED")" $J "$U" "$H"
[ "$(cat "$M/send.out")" = 'superseded: the decision was reopened' ] && [ ! -e "$M/dashboard-unsent/d-reopen.json" ] \
  || fail "resend_after_reopen_retired: '$(cat "$M/send.out")'"
[ "$(nlines "$L")" = "$ROWS" ] && [ "$(nlines "$M/rulings.jsonl")" = "$RULINGS" ] && [ ! -s "$F/sends" ] \
  || fail "leftover_unsent_record_cleared: a resend wrote a ledger row, a ruling or an Orca call"
pass=$((pass + 7))
# Bug caught: a kept record names no project, so another project's open decision with the same id and askedAt was
# taken for it, refused as "reopened" and left unanswered. A decision still open at that askedAt was never answered
# here: the answer is recorded as any other, and the kept record is left for its own project.
dec d-cross "$ASKED" 'Cross the streams?' >> "$L2"; keep d-cross yes
send 200 kept_record_of_another_project_does_not_block POST /answer "$(ans d-cross yes "$ASKED" widgetshop)" $J "$U" "$H"
grep -qx 'recorded, ruling r-[0-9]\{8\}-[0-9]\{6\}-[0-9]*-[0-9a-f]\{6\} logged' "$M/send.out" \
  && jq -e 'select(.id == "d-cross") | .answer == "yes" and .answeredAt != null' <(tail -1 "$L2") >/dev/null \
  && [ -e "$M/dashboard-unsent/d-cross.json" ] || fail "kept_record_of_another_project_does_not_block: '$(cat "$M/send.out")'; $(tail -1 "$L2")"
pass=$((pass + 1))
# The card's buttons are answers /answer takes: decision.sh --options uses Python's printable test, so a Unicode space
# or format character is refused at add, never offered as a button that answers 400.
for o in 'café' 'Go ahead' $'No thanks' $'a b' $'a​b' $'a　b'; do
  want=$(python3 -I -c 'import sys; print(int(sys.argv[1].isprintable()))' "$o")
  err=$(CONVEYOR_MAIN=$M bash "$HERE/../decision.sh" add "opt-$pass" "Is option $pass fine?" Yes main --options "$(jq -cn --arg o "$o" '["Yes", $o]')" 2>&1 >/dev/null)
  got=1; grep -q -- '--options takes' <<<"$err" && got=0
  [ "$got" = "$want" ] || fail "options_match_answer_validation: decision.sh took '$o' as $got, /answer as $want"
  pass=$((pass + 1))
done
done_part
) & started answers

# What the login lets in and what it keeps out. Each case that logs in uses a jar of its own.
restart() { kill "$PID"; wait "$PID" 2>/dev/null; serve; }
add_dec() { dec "$1" "$ASKED" "Question for $1?" >> "$L"; }
# status_of <jar> <path> / answer_with <jar> <decision id> -- the request made with that jar's cookies only.
status_of() { command curl -s --cacert "$CERT" -b "$1" -o /dev/null -w '%{http_code}' "$U$2"; }
answer_with() {
  command curl -s --cacert "$CERT" -b "$1" -o "$M/ans.out" -w '%{http_code}' -X POST -H "Origin: $U" -H 'Content-Type: application/json' \
    --data-binary "$(ans "$2" go "$ASKED")" "$U/answer"
}
device_id() { cli devices | awk -F'\t' -v l="$1" '$2 == l {print $1}'; }
# among_foreign <jar> -- a Cookie header with the jar's Board cookies between other apps' cookies that Python's cookie
# parser rejects (JSON with quotes, a space): a browser sends a host's cookies to every port on it.
among_foreign() { printf 'Cookie: x={"a":1}; sess=a b; %sy={"b":2}; t=c d' "$(awk '$6 ~ /^pp_/ {printf "%s=%s; ", $6, $7}' "$1")"; }
foreign_status_of() { command curl -s --cacert "$CERT" -H "$(among_foreign "$1")" -o /dev/null -w '%{http_code}' "$U$2"; }
unanswered() { jq -e --arg i "$1" 'select(.id == $i) | .answeredAt == null' "$L" >/dev/null; }

( fresh sessions "${PORTS[2]}"; ready; ledgers
# The live feed below follows a data.js that is there from the start, as the collector keeps one.
dash 2026-11-10T12:00:05Z '[{"card":"c1"}]'

add_dec d-login1; RULINGS=$(nlines "$M/rulings.jsonl")
[ "$(login "$A/j1" false plain)" = 200 ] || fail "login_then_answer_records: login refused: $(cat "$M/login.out")"
[ "$(answer_with "$A/j1" d-login1)" = 200 ] && jq -e 'select(.id == "d-login1") | .answer == "go"' "$L" >/dev/null \
  && [ "$(nlines "$M/rulings.jsonl")" = $((RULINGS + 1)) ] || fail "login_then_answer_records: a logged-in answer is recorded and logged ($(cat "$M/ans.out"))"
pass=$((pass + 1))
# A trusted device is let back in after the server restarts; a session that was not trusted is not (sessions live in memory).
add_dec d-login2
[ "$(login "$A/j2" true phone-2)" = 200 ] || fail "trusted_device_answers_after_restart: login refused"
restart
[ "$(status_of "$A/j1" /index.html)" = 302 ] || fail "restart_logs_untrusted_sessions_out: the plain session survived a restart"
[ "$(answer_with "$A/j2" d-login2)" = 200 ] || fail "trusted_device_answers_after_restart: answered $(cat "$M/ans.out")"
pass=$((pass + 2))
# Bug: a trusted device whose session had ended met the login form: GET /login served it to a browser the device
# cookie lets in, and each "Trust this device" from that browser added one more device to the user's list.
grep pp_device "$A/j2" > "$A/j2-device-only"
[ "$(status_of "$A/j2-device-only" /)" = 200 ] || fail "trusted_device_cookie_alone_lets_in: GET / refused"
got=$(command curl -s --cacert "$CERT" -b "$A/j2-device-only" -o /dev/null -w '%{http_code} %{redirect_url}' "$U/login")
[ "$got" = "302 $U/" ] || fail "login_page_sends_a_trusted_device_to_the_board: GET /login answered $got"
DEVICES=$(cli devices | wc -l | tr -d ' ')
[ "$(command curl -s --cacert "$CERT" -b "$A/j2-device-only" -c "$A/j2-again" -o "$M/login.out" -w '%{http_code}' -X POST -H "Origin: $U" \
  -H 'Content-Type: application/json' --data-binary "{\"user\":\"max\",\"password\":\"$PW\",\"trust\":true,\"label\":\"phone-2b\"}" "$U/login")" = 200 ] \
  && [ "$(cli devices | wc -l | tr -d ' ')" = "$DEVICES" ] && [ -z "$(device_id phone-2b)" ] \
  && [ "$(awk '$6 == "pp_device" {print $7}' "$A/j2-again")" = "$(awk '$6 == "pp_device" {print $7}' "$A/j2-device-only")" ] \
  || fail "trusted_login_keeps_the_browsers_device: a new device was made: $(cli devices)"
pass=$((pass + 3))
# Bug: another local app's cookie with JSON or a space in it, sent to the Board too, made the cookie parser drop every
# cookie, so after a restart each visit asked for a login and each "Trust this device" made a new device.
DEVICES=$(cli devices | wc -l | tr -d ' ')
restart
[ "$(foreign_status_of "$A/j2" /index.html)" = 200 ] && [ "$(cli devices | wc -l | tr -d ' ')" = "$DEVICES" ] \
  || fail "trusted_device_among_foreign_cookies_signs_in_after_restart: refused, or the device list changed"
[ "$(login "$A/j7" false plain-7)" = 200 ] && [ "$(foreign_status_of "$A/j7" /index.html)" = 200 ] \
  || fail "session_among_foreign_cookies_is_used: refused"
pass=$((pass + 2))
# F02: a revoke takes effect on the next request, for the device and the session made with it, with no restart.
add_dec d-rev
[ "$(login "$A/j3" true phone-3)" = 200 ] && [ "$(status_of "$A/j3" /index.html)" = 200 ] || fail "revoked_device_ends_its_session: could not log in"
cli revoke "$(device_id phone-3)" >/dev/null || fail "revoked_device_ends_its_session: revoke failed"
BEFORE=$(snap)
[ "$(status_of "$A/j3" /data.js)" = 302 ] && [ "$(answer_with "$A/j3" d-rev)" = 401 ] && unanswered d-rev && [ "$(snap)" = "$BEFORE" ] \
  || fail "revoked_device_ends_its_session: the revoked device still gets in, or the ledger moved"
[ "$(status_of "$A/j2" /index.html)" = 200 ] || fail "revoked_device_ends_its_session: another device lost access"
pass=$((pass + 3))
# A revoke also ends a live feed that never goes quiet: data.js changing faster than PING (1 s here) does not
# keep the revoked page following.
kill "$PID"; wait "$PID" 2>/dev/null; CONVEYOR_DASHBOARD_PING=1 serve
[ "$(login "$A/j5" true phone-5)" = 200 ] || fail "revoked_device_ends_a_busy_feed: could not log in"
command curl -sN --cacert "$CERT" -b "$A/j5" "$U/events" > "$M/ev5" 2>/dev/null & EV=$!
wait_until 'grep -q "^event: snapshot" "$M/ev5" || ! kill -0 "$EV" 2>/dev/null'
( i=0; while [ -d "$T" ]; do i=$((i + 1)); dash "2026-11-10T13:00:$(printf %02d $((i % 60)))Z" "[{\"card\":\"c$i\"}]"; sleep 0.25; done ) & BUSY=$! # sleep: the pace of the changes that keep the feed busy
# The feed is busy once a change has reached the page: then the revoke.
wait_until 'grep -q "^event: panel" "$M/ev5" || ! kill -0 "$EV" 2>/dev/null'; cli revoke "$(device_id phone-5)" >/dev/null || fail "revoked_device_ends_a_busy_feed: revoke failed"
# The changes go on for as long as the feed does: it ends only if the revoke ends it, however long that takes here.
wait_until '! kill -0 "$EV" 2>/dev/null' || { kill "$EV" "$BUSY" 2>/dev/null; fail "revoked_device_ends_a_busy_feed: the feed went on after the revoke"; }
kill "$BUSY" 2>/dev/null; wait "$BUSY" "$EV" 2>/dev/null
pass=$((pass + 1))
restart
# `revoke all` also ends a session made without a trusted device (the epoch moves) and every device.
[ "$(login "$A/j4" false plain-4)" = 200 ] && [ "$(status_of "$A/j4" /index.html)" = 200 ] || fail "revoke_all_ends_untrusted_session: could not log in"
cli revoke all >/dev/null || fail "revoke_all_ends_untrusted_session: revoke all failed"
[ "$(status_of "$A/j4" /index.html)" = 302 ] && [ "$(status_of "$A/j2" /index.html)" = 302 ] || fail "revoke_all_ends_untrusted_session: a session or device survived"
[ -z "$(cli devices)" ] || fail "revoke_all_ends_untrusted_session: devices are still listed"
pass=$((pass + 2))
# A new password ends every session (the epoch moves) but keeps the trusted devices (the owner's ruling):
# the device cookie logs straight back in, and `revoke all` is how every device ends.
[ "$(login "$A/j6" true phone-6)" = 200 ] && [ "$(status_of "$A/j6" /index.html)" = 200 ] || fail "password_change_keeps_devices: could not log in"
printf '%s\n%s\n' "$PW" "$PW" | cli set-password max >/dev/null || fail "password_change_keeps_devices: set-password failed"
grep pp_session "$A/j6" > "$A/j6-session-only"
grep pp_device "$A/j6" > "$A/j6-device-only"
[ "$(status_of "$A/j6-session-only" /index.html)" = 302 ] || fail "password_change_keeps_devices: the old session cookie still gets in"
[ "$(status_of "$A/j6-device-only" /index.html)" = 200 ] || fail "password_change_keeps_devices: the device cookie was refused"
[ -n "$(device_id phone-6)" ] || fail "password_change_keeps_devices: the device is no longer listed"
# A login that checked the old password and finishes after the change must still be refused, and add no new device
# and no live session. In process, so the change lands between the check and the device write.
got=$(PW=$PW "$PY" - "$SRV" <<'EOF'
import io, json, os, sys
sys.path.insert(0, os.path.dirname(sys.argv[1])); import dashboard_server as s
check = s.password_ok
def racing(store, user, pw):
    good = check(store, user, pw)
    s.change_store(lambda st: st['users']['max'].update(epoch=st['users']['max']['epoch'] + 1))  # set-password's store change, mid-login
    return good
s.password_ok = racing
before = len(s.read_store()['users']['max']['devices'])
body =json.dumps({'user': 'max', 'password': os.environ['PW'], 'trust': True, 'label': 'race'}).encode()
codes = []
h = type('H', (), {})()
h.own_page, h.headers, h.rfile, h.wfile = (lambda: True), {'Content-Length': str(len(body))}, io.BytesIO(body), io.BytesIO()
h.reply = lambda code, text: codes.append(code)
h.send_error = h.send_response = codes.append
h.send_header = h.end_headers = lambda *a: None
s.Handler.login(h)
store = s.read_store()
u = store['users']['max']
print(codes[0], len(u['devices']) - before, sum(v['epoch'] == u['epoch'] for v in s.SESSIONS.values()))
EOF
)
[ "$got" = '401 0 0' ] || fail "login_across_password_change_is_refused: status, new devices, live sessions = $got"
# MFA turned on between a password-only login's check and its session (mfa_on leaves the epoch alone) must not let
# that login in without a code: refused, with no new device and no session.
got=$(PW=$PW "$PY" - "$SRV" <<'EOF'
import io, json, os, sys
sys.path.insert(0, os.path.dirname(sys.argv[1])); import dashboard_server as s
check = s.password_ok
def racing(store, user, pw):
    good = check(store, user, pw)
    s.change_store(lambda st: st['users']['max'].update(mfa=True))  # mfa_on's store change, mid-login
    return good
s.password_ok = racing
before = len(s.read_store()['users']['max']['devices'])
body = json.dumps({'user': 'max', 'password': os.environ['PW'], 'trust': True, 'label': 'race'}).encode()
codes = []
h = type('H', (), {})()
h.own_page, h.headers, h.rfile, h.wfile = (lambda: True), {'Content-Length': str(len(body))}, io.BytesIO(body), io.BytesIO()
h.reply = lambda code, text: codes.append(code)
h.send_error = h.send_response = codes.append
h.send_header = h.end_headers = lambda *a: None
s.Handler.login(h)
s.change_store(lambda st: st['users']['max'].pop('mfa'))
print(codes[0], len(s.read_store()['users']['max']['devices']) - before, len(s.SESSIONS))
EOF
)
[ "$got" = '401 0 0' ] || fail "login_across_mfa_on_is_refused: status, new devices, sessions = $got"
pass=$((pass + 5))
# R04: a device older than its cookie's year is refused by the server, whatever cookie a client keeps sending.
[ "$(login "$A/j5" true old-5)" = 200 ] && [ "$(status_of "$A/j5" /index.html)" = 200 ] || fail "expired_device_is_refused: could not log in"
OLD=$(device_id old-5)
jq --arg i "$OLD" '.users.max.devices[$i].created = "2025-01-01T00:00:00Z"' "$CONVEYOR_DASHBOARD_AUTH" > "$A/store.tmp" && cat "$A/store.tmp" > "$CONVEYOR_DASHBOARD_AUTH"
grep pp_device "$A/j5" > "$A/j5-device-only"
[ "$(status_of "$A/j5-device-only" /index.html)" = 302 ] && [ "$(status_of "$A/j5" /index.html)" = 302 ] \
  || fail "expired_device_is_refused: a device cookie past its year still gets in"
pass=$((pass + 2))
# A trusted device keeps when it was last used, which the account page lists for each device: set at its login, then
# moved by a use through its cookie or through a session it made, once the last one recorded is DEVICE_USED_EVERY
# (600 s) old, and left alone by a use within that (no store write on every request). Bug it catches: devices that can
# be told apart only by when they were trusted, never by whether they are still in use.
[ "$(login "$A/j7" true used-7)" = 200 ] || fail "device_keeps_its_last_use: could not log in"
D7=$(device_id used-7)
used7() { jq -r --arg i "$D7" '.users.max.devices[$i].used' "$CONVEYOR_DASHBOARD_AUTH"; }
set_used7() { jq --arg i "$D7" ".users.max.devices[\$i].used = ($1)" "$CONVEYOR_DASHBOARD_AUTH" > "$A/store.tmp" && cat "$A/store.tmp" > "$CONVEYOR_DASHBOARD_AUTH"; }
[ "$(used7)" = "$(jq -r --arg i "$D7" '.users.max.devices[$i].created' "$CONVEYOR_DASHBOARD_AUTH")" ] || fail "device_keeps_its_last_use: not set at login: $(used7)"
grep pp_device "$A/j7" > "$A/j7-device-only"; grep pp_session "$A/j7" > "$A/j7-session-only"
for jar in j7-device-only j7-session-only; do
  set_used7 '"2025-01-01T00:00:00Z"'
  [ "$(status_of "$A/$jar" /index.html)" = 200 ] && [ "$(used7)" != 2025-01-01T00:00:00Z ] || fail "device_keeps_its_last_use: a use through $jar left $(used7)"
  set_used7 'now - 60 | strftime("%Y-%m-%dT%H:%M:%SZ")'; RECENT=$(used7)
  [ "$(status_of "$A/$jar" /index.html)" = 200 ] && [ "$(used7)" = "$RECENT" ] || fail "device_keeps_its_last_use: a use through $jar a minute after the last wrote $(used7)"
done
pass=$((pass + 5))
# Both cookies are HttpOnly and Secure. The session is SameSite=Strict; the device is SameSite=Lax, so a link from
# another app or site, which a browser sends with no Strict cookie, still lets a trusted device in (bug: it met the login).
command curl -s --cacert "$CERT" -D "$M/hdr" -o /dev/null -X POST -H "Origin: $U" -H 'Content-Type: application/json' \
  --data-binary "{\"user\":\"max\",\"password\":\"$PW\",\"trust\":true,\"label\":\"phone-6\"}" "$U/login"
for c in pp_session:SameSite=Strict pp_device:SameSite=Lax; do
  site=${c#*:} c=${c%%:*}
  for attr in HttpOnly Secure "$site"; do
    grep -i "^set-cookie: $c=" "$M/hdr" | grep -q "; $attr" || fail "cookies_are_secure: $c lacks $attr: $(grep -i "^set-cookie: $c=" "$M/hdr")"
    pass=$((pass + 1))
  done
done
[ "$(command curl -s -m 5 -o /dev/null -w '%{http_code}' "http://127.0.0.1:$PORT/index.html")" = 000 ] || fail "plain_http_gets_no_page: plain HTTP got an answer"
pass=$((pass + 1))
# 5 trusted logins at once each keep their device (the store is read, changed and written under one lock).
restart; N=$(cli devices | wc -l | tr -d ' ')
pids=; for i in 1 2 3 4 5; do login "$A/pt$i" true "par-$i" >/dev/null & pids="$pids $!"; done; wait $pids
[ "$(cli devices | wc -l | tr -d ' ')" = $((N + 5)) ] || fail "parallel_trusted_logins_keep_every_device: $(cli devices)"
pass=$((pass + 1))
done_part
) & started sessions

( fresh lockout "${PORTS[3]}"; ready
# Lockout: five wrong logins in a row, then even the right password is refused.
restart
for i in 1 2 3 4 5; do [ "$(login "$A/lk" false x "wrong password $i")" = 401 ] || fail "login_lockout_after_five_failures: miss $i was not a 401"; done
[ "$(login "$A/lk" false x "wrong password 6")" = 429 ] && [ "$(login "$A/lk" false x)" = 429 ] || fail "login_lockout_after_five_failures: the sixth try, or the right password, was not refused with 429"
pass=$((pass + 2))
# Parallel attempts cannot slip past the count: 20 wrong logins at once give exactly five 401 and fifteen 429.
restart
codes=$(pids=; for i in $(seq 20); do login "$A/pw$i" false x "wrong password $i" & pids="$pids $!"; done; wait $pids)
[ "$(grep -c '^401$' <<<"$codes")" = 5 ] && [ "$(grep -c '^429$' <<<"$codes")" = 15 ] || fail "lockout_holds_under_parallel_logins: $(sort <<<"$codes" | uniq -c | tr '\n' ' ')"
pass=$((pass + 1))
done_part
) & started lockout

# POST /restart kicks the collector job through dashboard.sh --restart. launchctl and systemctl stubs record argv;
# every part that runs dashboard.sh's service commands has them (service_stubs), so none reaches this machine's own.
service_stubs() {
  local c
  for c in launchctl systemctl; do
    cat > "$M/bin/$c" <<STUB
#!/usr/bin/env bash
printf '%s %s\n' "$c" "\$*" >> "$F/restarts"
[ ! -e "$F/restart-fail" ] || { echo 'restart refused' >&2; exit 1; }
STUB
    chmod +x "$M/bin/$c"
  done
}

( fresh restart "${PORTS[4]}"; ready; service_stubs
export CONVEYOR_HOST_OS=Darwin
STAMP=$A/dashboard-restart-at
# rst <jar> [path] [origin] -- a POST /restart as the page sends it; the status, the body in $M/rst.out.
rst() {
  command curl -s --cacert "$CERT" -b "$1" -o "$M/rst.out" -w '%{http_code}' -X POST -H "Origin: ${3:-$U}" \
    -H 'Connection: close' --ignore-content-length -H 'Content-Type: application/json' --data-binary '{}' "$U${2:-/restart}"
}
# restarts_are <n> <case> -- the command runs after the reply, in the request's own handler, and rst reads to the
# connection's end, which the server closes when that handler is done: every command the request ran has been run.
restarts_are() {
  [ "$(nlines "$F/restarts")" = "$1" ] || fail "$2: want $1 restart command(s), got $(nlines "$F/restarts"): $(cat "$F/restarts")"
  pass=$((pass + 1))
}
fresh_restart() { : > "$F/restarts"; rm -f "$STAMP" "$F/restart-fail"; }
restart; [ "$(login "$A/rs" true restart-test)" = 200 ] || fail "restart route: login refused"
fresh_restart
[ "$(rst "$A/rs")" = 202 ] && [ "$(cat "$M/rst.out")" = restarting ] || fail "restart_runs_one_kickstart: answered $(cat "$M/rst.out")"
restarts_are 1 restart_runs_one_kickstart
grep -qx "launchctl kickstart -k gui/$(id -u)/com.conveyor.dashboard" "$F/restarts" || fail "restart_runs_one_kickstart: ran '$(cat "$F/restarts")'"
grep -q 'dashboard: restart requested by max from 127.0.0.1 at ' "$M/server.err" || fail "restart_runs_one_kickstart: no 'restart requested' line in the log"
[ "$(rst "$A/rs")" = 429 ] && grep -q 'restarted under a minute ago' "$M/rst.out" || fail "restart_twice_in_a_minute_refused: answered $(cat "$M/rst.out")"
restarts_are 1 restart_twice_in_a_minute_refused
# The server is a child of the job the restart kills, so the cooldown is a file and outlives the server.
restart
[ "$(rst "$A/rs")" = 429 ] || fail "restart_cooldown_survives_server_restart: want 429"
restarts_are 1 restart_cooldown_survives_server_restart
fresh_restart
[ "$(rst "$A/none")" = 401 ] && grep -q 'log in to restart' "$M/rst.out" || fail "restart_logged_out_refused: answered $(cat "$M/rst.out")"
[ "$(rst "$A/rs" /restart https://evil.example)" = 403 ] || fail "restart_from_another_origin_refused: want 403"
[ "$(rst "$A/rs" /p/x/restart)" = 403 ] || fail "restart_on_another_path_refused: want 403"
restarts_are 0 restart_refusals_run_nothing
[ ! -e "$STAMP" ] || fail "restart_refusals_run_nothing: a refused request wrote the cooldown stamp"
# A failing command leaves its reason in the log, since the 202 has gone out by then.
echo x > "$F/restart-fail"
[ "$(rst "$A/rs")" = 202 ] || fail "restart_command_failure_logged: want 202"
wait_until 'grep -q "restart refused" "$M/server.err"'
grep -q 'dashboard: restart FAILED (exit 1): .*restart refused' "$M/server.err" || fail "restart_command_failure_logged: log has no failure line"
pass=$((pass + 1))
fresh_restart; unset CONVEYOR_HOST_OS
done_part
) & started restart

# POST /control steers the loop from the Board. The host is the one conveyor/host.json names, at its ssh
# target; the ssh stub records the command it is given and runs it here, where the host's conveyor.sh and gh
# are stubs that record their arguments. So each case checks the command the host would run, quoting included.
# control_setup -- that host (HM), its stubs, and the host file naming it.
control_setup() {
HM=$M/host-main; mkdir -p "$HM/conveyor" "$M/conveyor" "${L%/*}"
# The approval and decline lines name the pack's owner, read by the real pack reader on the host; Quinn, not the checkout's own owner.
cp -R "$HERE/../../../conveyor/lib" "$HERE/../../../conveyor/schema" "$HM/conveyor/"
mkdir -p "$HM/.conveyor"; jq '.owner.name = "Quinn"' "$HERE/../../../conveyor/lib/test-pack.json" > "$HM/.conveyor/project.json"
cat > "$HM/conveyor/conveyor.sh" <<STUB
#!/usr/bin/env bash
# The Board's GitHub writes go through the host's gh-write (plan section 8, P5): recorded, then handed to gh.
[ "\$1" != gh-write ] || { shift; printf '%s\n' "\$*" >> "$F/gh-writes"; exec gh "\$@"; }
printf '%s %s\n' "CONVEYOR_MAIN=\$CONVEYOR_MAIN" "\$*" >> "$F/conveyor-calls"
# A call with the Board's mark of a release after the label came off (unlabel), which control release reads.
[ -z "\${CONVEYOR_UNLABELED:-}" ] || printf '%s\n' "\$*" >> "$F/unlabeled-calls"
[ ! -e "$F/conveyor-refuse" ] || { echo "conveyor: \$(cat "$F/conveyor-refuse")" >&2; exit 2; }
case \$1 in
  health) printf '{"waiting":[{"card":"c1","issue":%s}],"before":[{"issue":%s}]}\n' "\$(cat "$F/waiting" 2>/dev/null || echo 0)" "\$(cat "$F/before" 2>/dev/null || echo 0)" ;;
  control) echo '{"mode":"run"}' ;;
  retry) echo "conveyor: issue #\$2 can be picked again" ;;
  shut) [ ! -e "$F/shut-none" ] || { echo "conveyor: issue #\$2 has no card; nothing changed" >&2; exit 4; }
    [ ! -e "$F/shut-fails" ] || { echo "conveyor: the card records do not check" >&2; exit 3; }
    # shut's check could not lock the records (flock on an unwritable \$STATE.checked.lock): exit 1, as shut.sh fails.
    [ ! -e "$F/shut-unlocked" ] || exit 1
    echo "conveyor: issue #\$2 was closed while card c1 was blocked; the card is closed" ;;
  machine) echo "conveyor: the machine's Conveyor: \$2" ;;
  # suite-machine check --json: the lines of the check; exit 1 with them when a need is missing, as the engine does.
  suite-machine) printf '{"kind":"ssh","name":"box.example.com","ok":false,"needs":[{"need":"jq","ok":false,"detail":"not installed"}],"cpus":4,"slots":3}\n'; exit 1 ;;
  # A test action's id (of its file, the last argument), or an issue's address; a file named gone is not main's.
  testaction|testissue) [[ "\$*" != *gone* ]] || { echo "conveyor: the file is not a file of main" >&2; exit 2; }
    [ "\$1" != testissue ] || echo "\${CONVEYOR_FOREMAN-unset}:\${CLAUDE_CODE_SESSION_ID-unset}" >> "$F/testissue-mark"
    if [ "\$1" = testaction ]; then l=\${*: -1}; echo "id-\${l##*/}"; else echo "https://github.com/o/r/issues/\$(grep -c . "$F/conveyor-calls")"; fi ;;
esac
STUB
printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$*" >> "%s/gh-calls"\npwd >> "%s/gh-pwd"\ncase "$1 $2" in "issue view") echo "Old body" ;; "issue edit") cat > "%s/gh-body" ;; esac\n' "$F" "$F" "$F" > "$M/bin/gh"
cat > "$M/bin/ssh" <<STUB
#!/usr/bin/env bash
[ ! -e "$F/ssh-down" ] || { echo 'ssh: connect to host: No route to host' >&2; exit 255; }
printf '%s\n' "\$*" >> "$F/ssh-calls"
sh -c "\${@: -1}"
STUB
chmod +x "$HM/conveyor/conveyor.sh" "$M/bin/gh" "$M/bin/ssh"
jq -n --arg m "$HM" --arg l "$L" '{host: "buildhost", ssh: "user@buildhost", main: $m, records: [{repo: "sample", main: $m, ledger: $l}]}' > "$M/conveyor/host.json"
}
# The host main the running server reports (GET /me, as the logged-in $GJ); any other than $HM is a real loop, so
# the test stops before a POST reaches it (kill: ctl runs inside $(...), where exit would end only that subshell).
host_guard() {
  local hm; hm=$(command curl -s --cacert "$CERT" -b "$GJ" -D - -o /dev/null "$U/me" | tr -d '\r' \
    | awk -F': ' 'tolower($1) == "x-conveyor-main" { print $2 }')
  [ "$hm" = "$HM" ] || { echo "FAIL: control_reaches_only_the_tests_host: the server's host main is '$hm', not $HM; nothing sent" >&2; kill "$$"; exit 1; }
}
ctl() {
  host_guard
  command curl -s --cacert "$CERT" -b "${2:-$A/ct}" -o "$M/ctl.out" -w '%{http_code}' -X POST -H "Origin: ${3:-$U}" \
    -H "Content-Type: ${4:-application/json}" --data-binary "$1" "$U/control"
}
# Every action names the record it is for: here the host file's one record, sample, on its main.
act() { jq -cn --arg a "$1" '{action: $a, args: $ARGS.positional, repo: "sample"}' --args -- "${@:2}"; }
yes_act() { act "$@"; }
fresh_control() { rm -f "$F/testissue-mark" "$F/conveyor-calls" "$F/unlabeled-calls" "$F/gh-calls" "$F/gh-writes" "$F/gh-pwd" "$F/gh-body" "$F/ssh-calls" "$F/conveyor-refuse" "$F/waiting" "$F/before" "$F/ssh-down" "$F/shut-none" "$F/shut-fails" "$F/shut-unlocked"; }
calls() { cat "$F/conveyor-calls" 2>/dev/null; }

# control_part <part> <port> -- a part on the control host, max logged in on control-test ($A/ct).
control_part() {
  fresh "$1" "$2"; ready; control_setup
  restart; [ "$(login "$A/ct" true control-test)" = 200 ] || fail "control route: login refused"
  GJ=$A/ct
}
# control_actions <action>... -- each action of `conveyor.sh control` reaches that command, on host.json's main, over
# ssh to the host's target. Two parts run half of them each.
control_actions() {
  local a got
  for a; do
    fresh_control
    # shellcheck disable=SC2086
    got=$(ctl "$(act $a)")
    [ "$got" = 200 ] && [ "$(calls)" = "CONVEYOR_MAIN=$HM control $a" ] && grep -q '^-o BatchMode=yes -o ConnectTimeout=5 user@buildhost bash -c ' "$F/ssh-calls" \
      || fail "control_action_reaches_its_command: '$a' answered $got '$(cat "$M/ctl.out")', ran '$(calls)' over '$(cat "$F/ssh-calls" 2>/dev/null)'"
    pass=$((pass + 1))
  done
}

( control_part actions "${PORTS[9]}"
# #1621: the Board's settings of Push after a combined test run (pushbatchwhen, pushbatchtests) were refused as no rule.
# #1823: the Board's checkboxes of the rule Serena (serena=<roles>|off) were refused as no rule; a role it does not know
# is refused below.
# Bug: the Board's Save of antigravity as the builder (model antigravity ...) was refused; its other seats stay refused
# below (control_bad_value_refused), as the engine runs agy for the builder alone.
control_actions 'rules P1=off followups=on area:infra=on' 'rules P3=off' 'rules P3=on' 'rules team/billing=off' 'rules visible=off' 'rules visible=on' 'rules lint=off' 'rules lint=on' 'rules split=shadow' 'rules split=on' 'rules pick=shadow' 'rules pushbatchwhen=3' 'rules pushbatchwhen=02:30' 'rules pushbatchtests=all' 'model claude claude-opus-5-5 high' 'model claude claude-opus-5-5' 'model default' 'reviewer codex gpt-6.1-sol low' 'reviewer default' 'start held' 'start queue' \
  'reviewer opencode openrouter/vendor/model-1:free high' 'judge opencode openrouter/vendor/model-1' 'model claude opus[1m]' 'model codex gpt-6.1-sol' 'model antigravity gem-1 high' \
  'judge on' 'judge off' 'judge claude claude-opus-5-5 high' 'judge default' 'judge always security data' 'judge always' 'judge rare P2 P3' 'judge rare none' \
  'rules serena=build,fix,testfix' 'rules serena=review' 'rules serena=off' \
  'account second' 'account default' 'account' 'review-account first' 'review-account' 'dep-guard off' 'dep-guard on' 'push-check off' 'push-check on' 'push-check default' 'force 12' 'land-as pr' 'land-as main' 'pr-merge idle' 'pr-merge release' 'pr-merge button' 'onboarded build review-account dep-guard'
grep -q "dashboard: control model default by max from 127.0.0.1" "$M/server.err" || fail "control_is_logged: no line for the control in the log"
done_part
) & started actions

# This part's Board runs with the Foreman's mark, as one the Foreman's claim started does (test_issue_and_close_reach_conveyor).
( export CONVEYOR_FOREMAN=1 CLAUDE_CODE_SESSION_ID=foreman-1; control_part control "${PORTS[5]}"
control_actions 'pause' 'resume' 'stop' 'cap 3' 'cap 9' 'cap 100' 'cap off' 'guard 90' 'guard off' 'atonce 3' 'atonce 999' 'hold 12 13' 'release 12' 'order 13 12' 'order' 'unpin 13'
# Bug: a card id in the pinned order (`control order` takes them) was refused, so the Board could not move or unpin it.
control_actions 'order 13 c20261101T000001-x-0' 'unpin c20261101T000001-x-0'
# The release suite machine's rule: each form of `control suite-machine` reaches it as sent. Check the box answers the
# check's JSON line, with 200, though the check exits 1 for a missing tool; a check with no output answers its error.
# Bug: a form the Rules row sends was refused with a Bad Request; a missing tool's check answered as a failed action,
# so the row had no lines to show.
control_actions 'suite-mode serial' 'suite-mode parallel'
control_actions 'suite-machine local' 'suite-machine devbox' 'suite-machine devbox --size 8x16' 'suite-machine devbox --box hand-made' 'suite-machine devbox --size 4x8 --box hand-made --setup-at 2026-11-20T15:04:00Z' 'suite-machine devbox --size 4x8 --setup-at 2026-11-20T15:04:00Z' 'suite-machine ssh me@box.example.com' 'suite-machine ssh box.example.com --dir ~/suite' 'suite-machine ssh box --dir /srv/suite'
fresh_control
got=$(ctl "$(act suite-machine-check)")
[ "$got" = 200 ] && [ "$(calls)" = "CONVEYOR_MAIN=$HM suite-machine check --json" ] && jq -e '.ok == false and .needs[0].need == "jq" and .slots == 3' "$M/ctl.out" >/dev/null \
  || fail "suite_machine_check_answers_its_lines: answered $got '$(cat "$M/ctl.out")', ran '$(calls)'"
pass=$((pass + 1))
fresh_control; echo "the control record cannot be read" > "$F/conveyor-refuse"
got=$(ctl "$(act suite-machine-check)")
[ "$got" = 409 ] && grep -q 'cannot be read' "$M/ctl.out" || fail "suite_machine_check_without_lines_answers_its_error: answered $got '$(cat "$M/ctl.out")'"
pass=$((pass + 1))
fresh_control
# POST /machine pauses or resumes the whole machine: `conveyor.sh machine pause|resume` on the host's main, over the
# same ssh. It is its own control: it names no project, and a project's action is never taken without its project.
# Bug: the machine's pause could only be set by hand in the host file; and a pause sent with no project must never be
# read as the machine's, nor as main's.
mctl() {
  host_guard
  command curl -s --cacert "$CERT" -b "${2:-$A/ct}" -o "$M/ctl.out" -w '%{http_code}' -X POST -H "Origin: ${3:-$U}" \
    -H "Content-Type: application/json" --data-binary "$1" "$U/machine"
}
for a in pause resume; do
  fresh_control
  got=$(mctl "{\"action\":\"$a\"}")
  [ "$got" = 200 ] && [ "$(calls)" = "CONVEYOR_MAIN=$HM machine $a" ] && grep -q '^-o BatchMode=yes -o ConnectTimeout=5 user@buildhost bash -c ' "$F/ssh-calls" \
    && grep -q "the machine's Conveyor: $a" "$M/ctl.out" || fail "machine_action_reaches_its_command: '$a' answered $got '$(cat "$M/ctl.out")', ran '$(calls)'"
  pass=$((pass + 1))
done
grep -q "dashboard: control machine resume by max from 127.0.0.1" "$M/server.err" || fail "machine_control_is_logged: no line for the machine control in the log"
tail -n 1 "$M/rulings.jsonl" | jq -e '.question == "Board control: machine resume" and .user == "max"' >/dev/null || fail "machine_control_names_its_user: the ruling row is $(tail -n 1 "$M/rulings.jsonl")"
# Anything but the one action alone is refused and runs nothing: a project named with it, arguments, another action,
# or a pause with a value. A load limit (issue 346: the machine room, and `conveyor.sh machine load`, are removed) is
# refused too, a valid one included.
for body in '{"action":"pause","repo":"sample"}' '{"action":"pause","args":[]}' '{"action":"stop"}' '{"action":"cap"}' '{}' '["pause"]' \
  '{"action":"load","value":"20"}' '{"action":"load","value":"off"}' '{"action":"pause","value":"20"}'; do
  fresh_control
  [ "$(mctl "$body")" = 400 ] && [ -z "$(calls)" ] && [ ! -e "$F/ssh-calls" ] || fail "machine_takes_pause_or_resume_alone: '$body' answered '$(cat "$M/ctl.out")', ran '$(calls)'"
done
# A project's action with no project is refused, never taken as the machine's or as main's; nor is the machine's
# action taken through a project's route.
for body in '{"action":"pause","args":[]}' '{"action":"hold","args":["12"]}' '{"action":"cap","args":["3"]}' '{"action":"machine","args":["pause"],"repo":"sample"}'; do
  fresh_control
  [ "$(ctl "$body")" = 400 ] && [ -z "$(calls)" ] && [ ! -e "$F/ssh-calls" ] || fail "project_action_needs_its_project: '$body' answered '$(cat "$M/ctl.out")', ran '$(calls)'"
done
# The same door as every write: a caller with no login, or another site's page, changes nothing.
fresh_control
[ "$(mctl '{"action":"pause"}' "$M/no-such-jar")" = 401 ] && [ "$(mctl '{"action":"pause"}' "$A/ct" https://evil.example)" = 403 ] && [ -z "$(calls)" ] \
  || fail "machine_control_needs_the_login_and_the_page: answered '$(cat "$M/ctl.out")', ran '$(calls)'"
pass=$((pass + 3))
# Control start may wait on conveyor.sh's own `timeout N gh issue list`, so POST /control must wait longer than
# N for start, or a slow GitHub turns a change that was made into a 504.
lookup=$(sed -n '/^    start) /,/;;$/p' "$HERE/../../../conveyor/lib/control.sh" | grep -o 'timeout [0-9]* gh issue list' | grep -o '[0-9]*')
waits=$("$PY" - "$SRV" <<'EOF'
import os, sys
sys.path.insert(0, os.path.dirname(sys.argv[1])); import dashboard_server as s
print(s.CONTROL_TIMEOUT.get('start', 30))
EOF
)
[[ $lookup =~ ^[0-9]+$ ]] && [ "$waits" -gt "$lookup" ] \
  || fail "control_start_outwaits_its_lookup: POST /control waits ${waits}s for start, conveyor.sh's lookup up to '${lookup}'s"
pass=$((pass + 1))
# The answer says when it was in (this machine's clock, whole seconds rounded up), so the Board can tell a
# snapshot read before the change from one read after it.
fresh_control; t0=$(date +%s); host_guard
answered=$(command curl -s --cacert "$CERT" -b "$A/ct" -D - -o /dev/null -X POST -H "Origin: $U" -H "Content-Type: application/json" \
  --data-binary "$(act cap 4)" "$U/control" | tr -d '\r' | awk -F': ' 'tolower($1) == "x-answered-at" { print $2 }')
[[ $answered =~ ^[0-9]+$ ]] && [ "$answered" -ge "$t0" ] && [ "$answered" -le $(($(date +%s) + 1)) ] \
  || fail "control_answer_says_when: X-Answered-At '$answered' is not a time at or after $t0"
pass=$((pass + 1))
fresh_control
[ "$(ctl "$(act retry 13)")" = 200 ] && [ "$(calls)" = "CONVEYOR_MAIN=$HM retry 13" ] && grep -q 'can be picked again' "$M/ctl.out" \
  || fail "retry_reaches_conveyor_retry: $(cat "$M/ctl.out") ran '$(calls)'"
pass=$((pass + 1))
# A blocked card's Hold and its Fix that drops the kept work. Bug: either is refused, or reaches another command.
fresh_control
[ "$(ctl "$(act unblock 13)")" = 200 ] && [ "$(calls)" = "CONVEYOR_MAIN=$HM unblock 13 --hold" ] || fail "unblock_reaches_conveyor_unblock_hold: answered '$(cat "$M/ctl.out")', ran '$(calls)'"
fresh_control
[ "$(ctl "$(act retry 13 --fresh)")" = 200 ] && [ "$(calls)" = "CONVEYOR_MAIN=$HM retry 13 --fresh" ] || fail "retry_fresh_reaches_conveyor_retry: answered '$(cat "$M/ctl.out")', ran '$(calls)'"
pass=$((pass + 2))
# The Board's "Depends on…": control_ok() takes depends <issue> add|remove with 1 to 20 issues, and the host's
# `control depends` gets them as sent (its refusals are the host's). Bug: the action refused, so the Board could not
# set a dependency; or a shape the host does not take sent to it (the refusals are in control_bad_value_refused).
for a in 'depends 12 add 7' 'depends 12 remove 7' "depends 12 add $(seq -s ' ' 1 20)"; do
  fresh_control
  # shellcheck disable=SC2086
  [ "$(ctl "$(act $a)")" = 200 ] && [ "$(calls)" = "CONVEYOR_MAIN=$HM control $a" ] || fail "depends_reaches_conveyor_control: '$a' answered '$(cat "$M/ctl.out")', ran '$(calls)'"
  pass=$((pass + 1))
done
# Close on a blocked card of Needs you: its issue is closed through the host's gh-write (the privacy gate), with the
# comment that says where, in the record's repository, then its card shut at once (conveyor.sh shut), so it leaves
# Needs you though the loop is stopped. Bug: the button reaches no command, or gh without the gate; it leaves the
# card blocked until a loop turn that a stopped loop never takes; or it also retries the card, which gives it back, so the loop can pick the closed issue from an open list asked before it closed.
# Bug (#1635): shut is not told the issue was closed (--closed), so it shuts the card as the owner's, and no turn
# gives it back once the issue is opened again.
fresh_control
[ "$(ctl "$(act close 13)")" = 200 ] && [ "$(cat "$F/gh-writes")" = "issue close 13 --comment Closed from the Board's Needs you list." ] \
  && [ "$(cat "$F/gh-calls")" = "$(cat "$F/gh-writes")" ] && [ "$(cat "$F/gh-pwd")" = "$HM" ] && [ "$(calls)" = "CONVEYOR_MAIN=$HM shut 13 --closed" ] \
  && grep -q 'issue #13 was closed' "$M/ctl.out" \
  || fail "close_reaches_gh_write_issue_close: answered '$(cat "$M/ctl.out")', wrote '$(cat "$F/gh-writes" 2>&1)', ran '$(calls)'"
# Close on a pipeline change held there: its issue has no card, so shut shuts nothing and exits 4 (#1030). Bugs: the
# Board answers that as a failed Close, though GitHub closed the issue; or it hides a shut that failed, with exit 1
# too (R115: shut's records could not be locked, which the Board took as "shut nothing").
fresh_control; touch "$F/shut-none"
[ "$(ctl "$(act close 41)")" = 200 ] && [ "$(calls)" = "CONVEYOR_MAIN=$HM shut 41 --closed" ] \
  || fail "close_of_an_issue_with_no_card_is_no_failure: answered '$(cat "$M/ctl.out")', ran '$(calls)'"
fresh_control; touch "$F/shut-fails"
[ "$(ctl "$(act close 41)")" != 200 ] || fail "close_shows_a_shut_that_failed: answered '$(cat "$M/ctl.out")', ran '$(calls)'"
fresh_control; touch "$F/shut-unlocked"
[ "$(ctl "$(act close 13)")" != 200 ] || fail "close_shows_a_shut_that_could_not_lock: close 13 with shut exiting 1 answered '$(cat "$M/ctl.out")', ran '$(calls)'"
pass=$((pass + 3))
# A blocked main-red fix card has no issue (issue 0): Retry and Close take its card id, and Close closes no issue on
# GitHub, only shuts the card. Bug: control_ok() took only issue numbers, so both buttons of such a card were refused.
fresh_control
[ "$(ctl "$(act retry c20261115T120000-sample-0)")" = 200 ] && [ "$(calls)" = "CONVEYOR_MAIN=$HM retry c20261115T120000-sample-0" ] \
  || fail "retry_takes_a_main_red_card_id: answered '$(cat "$M/ctl.out")', ran '$(calls)'"
fresh_control
[ "$(ctl "$(act close c20261115T120000-sample-0)")" = 200 ] && [ "$(calls)" = "CONVEYOR_MAIN=$HM shut c20261115T120000-sample-0" ] && [ ! -e "$F/gh-calls" ] \
  || fail "close_shuts_a_main_red_card_by_its_id: answered '$(cat "$M/ctl.out")', wrote '$(cat "$F/gh-writes" 2>&1)', ran '$(calls)'"
fresh_control
[ "$(ctl "$(act retry c20261115T120000-sample-12)")" = 400 ] && [ -z "$(calls)" ] || fail "retry_refuses_a_card_id_of_an_issue: answered '$(cat "$M/ctl.out")', ran '$(calls)'"
pass=$((pass + 3))
# Retry and Close take the login, as every control does: logged out, nothing runs.
fresh_control
[ "$(ctl "$(act retry 13)" "$A/none")" = 401 ] && [ "$(ctl "$(act close 13)" "$A/none")" = 401 ] && [ -z "$(calls)" ] && [ ! -e "$F/gh-calls" ] \
  || fail "retry_and_close_need_the_login: answered '$(cat "$M/ctl.out")', ran '$(calls)'"
pass=$((pass + 2))
# "File as issue" on a declined finding: the host files it from its record's declined list, by the line's id.
# Bug: the Declined panel's button reaches no command, or one of another record.
fresh_control
[ "$(ctl "$(act build d0123456789ab)")" = 200 ] && [ "$(calls)" = "CONVEYOR_MAIN=$HM declined build d0123456789ab" ] \
  || fail "build_reaches_conveyor_declined_build: $(cat "$M/ctl.out") ran '$(calls)'"
pass=$((pass + 1))
# "Dismiss" and "Dismiss all shown": the host marks the lines dismissed by the Board user. Bug: the ids reach no
# command, the line keeps no record of who dismissed it, or a list with one id that is no line's is sent on.
fresh_control
[ "$(ctl "$(act dismiss d0123456789ab d00000000000c)")" = 200 ] && [ "$(calls)" = "CONVEYOR_MAIN=$HM declined dismiss --by Board user max d0123456789ab d00000000000c" ] \
  || fail "dismiss_reaches_conveyor_declined_dismiss: $(cat "$M/ctl.out") ran '$(calls)'"
fresh_control
[ "$(ctl "$(act dismiss d0123456789ab 'x; id')")" = 400 ] && [ -z "$(calls)" ] || fail "dismiss_checks_every_id: answered '$(cat "$M/ctl.out")', ran '$(calls)'"
pass=$((pass + 2))
# The Rules tab's Run full test suite, Push landed and Push anyway reach `conveyor.sh full-test` on the record; a push
# over a red suite names the red run the confirm showed (its id) and the Board user who confirmed it (the one user this
# part has logged in). Bug: a button reaches no command, the push anyway is logged as no one's or does not say which red
# run it is over, or another argument reaches the host.
for a in '' push; do
  fresh_control
  [ "$(ctl "$(act full-test $a)")" = 200 ] && [ "$(calls)" = "CONVEYOR_MAIN=$HM full-test${a:+ $a}" ] || fail "full_test_${a:-run}_reaches_conveyor: $(cat "$M/ctl.out") ran '$(calls)'"
done
fresh_control
[ "$(ctl "$(act full-test anyway 0123456789ab)")" = 200 ] && [ "$(calls)" = "CONVEYOR_MAIN=$HM full-test anyway 0123456789ab --by Board user $(jq -r '.users | keys[0]' "$CONVEYOR_DASHBOARD_AUTH")" ] \
  || fail "full_test_anyway_names_the_run_and_the_user: $(cat "$M/ctl.out") ran '$(calls)'"
fresh_control
for a in now anyway 'anyway 0123456789AB' 'anyway 0123456789a' 'anyway 0123456789ab --by'; do
  # shellcheck disable=SC2086 # each word an argument
  [ "$(ctl "$(act full-test $a)")" = 400 ] || fail "full_test_takes_no_other_argument: '$a' answered '$(cat "$M/ctl.out")'"
done
[ -z "$(calls)" ] || fail "full_test_takes_no_other_argument: ran '$(calls)'"
# The Control tab's Push now reaches `conveyor.sh push-now` on the record, with no argument. Bug: the button reaches no
# command, or an argument reaches the host.
fresh_control
[ "$(ctl "$(act push-now)")" = 200 ] && [ "$(calls)" = "CONVEYOR_MAIN=$HM push-now" ] || fail "push_now_reaches_conveyor: $(cat "$M/ctl.out") ran '$(calls)'"
fresh_control
[ "$(ctl "$(act push-now push)")" = 400 ] && [ -z "$(calls)" ] || fail "push_now_takes_no_argument: answered '$(cat "$M/ctl.out")', ran '$(calls)'"
# The Control tab's Merge (#248) reaches `conveyor.sh pr merge` on the record, with no argument. Bug: the button
# reaches no command, or an argument reaches the host.
fresh_control
[ "$(ctl "$(act merge-pr)")" = 200 ] && [ "$(calls)" = "CONVEYOR_MAIN=$HM pr merge" ] || fail "merge_pr_reaches_conveyor: $(cat "$M/ctl.out") ran '$(calls)'"
fresh_control
[ "$(ctl "$(act merge-pr 7)")" = 400 ] && [ -z "$(calls)" ] || fail "merge_pr_takes_no_argument: answered '$(cat "$M/ctl.out")', ran '$(calls)'"
pass=$((pass + 8))
# The Release panel's Release (the version typed) and Stop reach `conveyor.sh release-run` on the record. Bug: a press
# reaches no command, or a version the engine does not take (or a word the shell reads) reaches the host. Run suite's
# `prep <version>` (release-prep alone) reaches it as two words. The suite's mode the owner chose (#791) reaches it after the version, then `--machine local`
# (this machine chosen over the rule's) last. Bug: a press with the mode or the machine is refused, so no suite starts from the panel.
# Stop reaches it with the version of the run the panel shows, so the engine stops no run of another version.
# Stop of a wait names the waiting run's start (follow-up of #1461). Bug: it is refused, so the Board cannot end the wait.
for a in 1.2.0 'stop 1.2.0' 'stop 2026-11-14T08:00:00Z' 'prep 1.2.0' 'prep 1.2.0 --parallel' 'prep 1.2.0 --serial' '1.2.0 --parallel' 'prep 1.2.0 --machine local' 'prep 1.2.0 --serial --machine local' '1.2.0 --parallel --machine local'; do
  fresh_control
  # shellcheck disable=SC2086 # each word an argument
  [ "$(ctl "$(act release-run $a)")" = 200 ] && [ "$(calls)" = "CONVEYOR_MAIN=$HM release-run $a" ] || fail "release_run_${a// /_}_reaches_conveyor: $(cat "$M/ctl.out") ran '$(calls)'"
done
# Release anyway over a red suite is logged under the Board user who confirmed it. Bug: the release over a red suite
# is logged as no one's, or the press reaches no command.
fresh_control
[ "$(ctl "$(act release-run anyway 1.2.0)")" = 200 ] && [ "$(calls)" = "CONVEYOR_MAIN=$HM release-run anyway 1.2.0 --by Board user $(jq -r '.users | keys[0]' "$CONVEYOR_DASHBOARD_AUTH")" ] \
  || fail "release_run_anyway_names_the_user: $(cat "$M/ctl.out") ran '$(calls)'"
fresh_control
# Bug: a Stop with no version (stop) reached the engine, which stopped whatever run was under way when it came.
for a in '' stop 'stop 1.2' 'stop 1.2.0 1.3.0' 1.2 01.2.0 'v1.2.0' '1.2.0 stop' '1.2.0;id' prep 'prep stop' 'prep 1.2' '1.2.0 prep' anyway 'anyway 1.2' 'anyway 1.2.0 --by' \
  --parallel 'prep --parallel' 'stop --serial' 'anyway 1.2.0 --parallel' '1.2.0 --fast' '1.2.0 --serial --parallel' '--machine local' 'stop --machine local' 'stop 2026-11-14' 'stop 2026-11-14T08:00:00Z;id' 'anyway 1.2.0 --machine local' 'prep 1.2.0 --machine ssh' 'prep 1.2.0 --machine local --serial' 'prep 1.2.0 --machine'; do
  # shellcheck disable=SC2086 # each word an argument
  [ "$(ctl "$(act release-run $a)")" = 400 ] || fail "release_run_takes_a_version_or_stop: '$a' answered '$(cat "$M/ctl.out")'"
done
[ -z "$(calls)" ] || fail "release_run_takes_a_version_or_stop: ran '$(calls)'"
pass=$((pass + 4))
# The Tests page's limits and a file's mark reach `conveyor.sh test-settings` on the record, each argument one quoted
# word (a reason with spaces too). Bug: a Save reaches no command, or a shape the engine does not take (no value, a
# path that reads as an option, a reason of two lines, a budget, which no test file has now: #349) is sent on.
fresh_control
[ "$(ctl "$(act test-settings slow-issues true)")" = 200 ] && [ "$(ctl "$(act test-settings slow-mark conveyor/tests/e2e.test.sh 'runs the whole loop')")" = 200 ] \
  && [ "$(ctl "$(act test-settings history-start 2026-11-21T00:00:00Z)")" = 200 ] && [ "$(ctl "$(act test-settings history-start clear)")" = 200 ] \
  && [ "$(calls)" = "CONVEYOR_MAIN=$HM test-settings slow-issues true
CONVEYOR_MAIN=$HM test-settings slow-mark conveyor/tests/e2e.test.sh runs the whole loop
CONVEYOR_MAIN=$HM test-settings history-start 2026-11-21T00:00:00Z
CONVEYOR_MAIN=$HM test-settings history-start clear" ] || fail "test_settings_reach_conveyor: $(cat "$M/ctl.out") ran '$(calls)'"
fresh_control
for a in 'history-start yesterday' 'history-start 2026-11-21' 'history-start' 'file-budget a.test.sh 30' 'budget 8' 'file-budget-clear a.test.sh' 'slow-mark a.test.sh' 'slow-mark-clear -x.test.sh' 'slow-issues yes' 'slow-mark-clear /etc/x'; do
  # shellcheck disable=SC2086 # each word an argument
  [ "$(ctl "$(act test-settings $a)")" = 400 ] || fail "test_settings_take_only_their_shapes: '$a' answered '$(cat "$M/ctl.out")'"
done
[ "$(ctl "$(act test-settings slow-mark a.test.sh "$(printf 'two\nlines')")")" = 400 ] || fail "test_settings_take_only_their_shapes: a reason of two lines answered '$(cat "$M/ctl.out")'"
[ -z "$(calls)" ] || fail "test_settings_take_only_their_shapes: ran '$(calls)'"
pass=$((pass + 2))
# The Rules tab's standing kinds reach `conveyor.sh auto standing <kind> on|off` on the record. Bug: a switch reaches no
# command, or a kind the engine does not know, or a value other than on and off, is sent on.
fresh_control
[ "$(ctl "$(act standing review-followup on)")" = 200 ] && [ "$(calls)" = "CONVEYOR_MAIN=$HM auto standing review-followup on" ] \
  || fail "standing_reaches_conveyor: $(cat "$M/ctl.out") ran '$(calls)'"
fresh_control # #715: the kind the watcher acts on is taken too
[ "$(ctl "$(act standing review-retry off)")" = 200 ] && [ "$(calls)" = "CONVEYOR_MAIN=$HM auto standing review-retry off" ] \
  || fail "standing_reaches_conveyor: review-retry: $(cat "$M/ctl.out") ran '$(calls)'"
fresh_control
for a in 'review-followup' 'review-followup maybe' 'any-fix on' 'asked-fix on off' '-x on'; do
  # shellcheck disable=SC2086 # each word an argument
  [ "$(ctl "$(act standing $a)")" = 400 ] || fail "standing_takes_a_kind_and_on_or_off: '$a' answered '$(cat "$M/ctl.out")'"
done
[ -z "$(calls)" ] || fail "standing_takes_a_kind_and_on_or_off: ran '$(calls)'"
pass=$((pass + 2))
# The Tests page's actions (#521) reach the engine's commands on the record, each argument one quoted word; an issue
# filed has the pack's type and last priority. Bug: an action that reaches no command, or a shape the engine does not
# take (a stop with no id, a path that reads as an option, a rule value of two words, the measure budget, which no test
# file has now (#349), a title of two lines) sent on; Keep a
# case off run as `flaky add`, which files an issue when its entry is the case's third source, though the action is "now".
fresh_control
[ "$(ctl "$(act testaction judge conveyor/tests/merge.test.sh)")" = 200 ] && [ "$(ctl "$(act testaction stop 0123456789ab)")" = 200 ] \
  && [ "$(ctl "$(act tests codex gpt-6.1-sol high)")" = 200 ] && [ "$(ctl "$(act testrules set 'over budget' limit 1.5)")" = 200 ] \
  && [ "$(ctl "$(act flaky-off 'conveyor/tests/merge.test.sh: two cards' 'fails one run in ten')")" = 200 ] \
  && [ "$(calls)" = "CONVEYOR_MAIN=$HM testaction judge conveyor/tests/merge.test.sh
CONVEYOR_MAIN=$HM testaction stop 0123456789ab
CONVEYOR_MAIN=$HM control tests codex gpt-6.1-sol high
CONVEYOR_MAIN=$HM testrules set over budget limit 1.5
CONVEYOR_MAIN=$HM flaky off conveyor/tests/merge.test.sh: two cards Board user max fails one run in ten" ] || fail "test_actions_reach_conveyor: $(cat "$M/ctl.out") ran '$(calls)'"
# File an issue reaches the engine's testissue with its file (bug: filed with no file, so its row never had the issue
# for Close its issue as done); the close goes through gh-write.
fresh_control
[ "$(ctl "$(act test-issue conveyor/tests/merge.test.sh 'Speed up conveyor/tests/merge.test.sh' "$(printf 'Measured: 12 CPU s.\n\nVerdict: split')")")" = 200 ] \
  && [ "$(ctl "$(act test-close 480 'Done: before 12 CPU s, after 6 CPU s.')")" = 200 ] \
  && [ "$(calls)" = "CONVEYOR_MAIN=$HM testissue conveyor/tests/merge.test.sh Speed up conveyor/tests/merge.test.sh Measured: 12 CPU s.

Verdict: split" ] && [ "$(cat "$F/gh-writes")" = "issue close 480 --comment Done: before 12 CPU s, after 6 CPU s." ] \
  && [ "$(cat "$F/testissue-mark")" = : ] \
  || fail "test_issue_and_close_reach_conveyor: $(cat "$M/ctl.out") ran '$(calls)' wrote '$(cat "$F/gh-writes" 2>&1)' with the mark '$(cat "$F/testissue-mark" 2>&1)'"
fresh_control
for a in 'testaction judge' 'testaction stop 12' 'testaction judge -x.test.sh' 'testaction delete a.test.sh' 'testaction explain --time ../zone 12-hour a.test.sh' 'testaction explain --time :/etc/zone 12-hour a.test.sh' 'testaction explain --time UTC 13-hour a.test.sh' 'testaction judge --time UTC 12-hour a.test.sh' 'testrules guard perDay off' 'testrules set r limit' 'testrules add r budget 1 3 3' 'testrules set r measure budget' 'tests codex' 'test-close x done' 'flaky-off a.test.sh why'; do
  # shellcheck disable=SC2086 # each word an argument
  [ "$(ctl "$(act $a)")" = 400 ] || fail "test_actions_take_only_their_shapes: '$a' answered '$(cat "$M/ctl.out")'"
done
[ "$(ctl "$(act test-issue "$(printf 'two\nlines')" body)")" = 400 ] && [ "$(ctl "$(act test-issue a.test.sh "$(printf 'two\nlines')" body)")" = 400 ] \
  && [ "$(ctl "$(act test-issue -x.test.sh title body)")" = 400 ] || fail "test_actions_take_only_their_shapes: a title of two lines answered '$(cat "$M/ctl.out")'"
[ -z "$(calls)" ] && [ ! -e "$F/gh-writes" ] || fail "test_actions_take_only_their_shapes: ran '$(calls)' wrote '$(cat "$F/gh-writes" 2>&1)'"
pass=$((pass + 3))
# The Tests page's actions on many files (#72): a list of files in one POST is one action or issue a file, each
# answered on its own, in the list's order. Bug: a list ran one command for all, ran only its first file, or answered
# one text for all, so the Board could not tell which file was taken and which refused.
fresh_control
[ "$(ctl "$(act testaction judge t/a.test.sh t/b.test.sh t/c.test.sh)")" = 200 ] \
  && [ "$(jq -c '.results' "$M/ctl.out")" = '[{"file":"t/a.test.sh","id":"id-a.test.sh"},{"file":"t/b.test.sh","id":"id-b.test.sh"},{"file":"t/c.test.sh","id":"id-c.test.sh"}]' ] \
  && [ "$(calls)" = "CONVEYOR_MAIN=$HM testaction judge t/a.test.sh
CONVEYOR_MAIN=$HM testaction judge t/b.test.sh
CONVEYOR_MAIN=$HM testaction judge t/c.test.sh" ] || fail "testaction_list_one_a_file: $(cat "$M/ctl.out") ran '$(calls)'"
# An explain carries the browser's zone and Time setting (#770), which go with each file of a list; bug: the facts'
# times then fell back to the build machine's zone, or the --time words were read as files.
fresh_control
[ "$(ctl "$(act testaction explain --time America/New_York 24-hour t/a.test.sh t/b.test.sh)")" = 200 ] \
  && [ "$(jq -c '.results' "$M/ctl.out")" = '[{"file":"t/a.test.sh","id":"id-a.test.sh"},{"file":"t/b.test.sh","id":"id-b.test.sh"}]' ] \
  && [ "$(calls)" = "CONVEYOR_MAIN=$HM testaction explain --time America/New_York 24-hour t/a.test.sh
CONVEYOR_MAIN=$HM testaction explain --time America/New_York 24-hour t/b.test.sh" ] || fail "testaction_explain_time_each_file: $(cat "$M/ctl.out") ran '$(calls)'"
fresh_control
[ "$(ctl "$(act test-issue t/a.test.sh 'Optimize the test file t/a.test.sh' 'Median 12 CPU s. VERDICT: split' t/b.test.sh 'Optimize the test file t/b.test.sh' 'Median 9 CPU s. VERDICT: delete')")" = 200 ] \
  && [ "$(jq -c '.results' "$M/ctl.out")" = '[{"file":"t/a.test.sh","id":"https://github.com/o/r/issues/1"},{"file":"t/b.test.sh","id":"https://github.com/o/r/issues/2"}]' ] \
  && [ "$(calls)" = "CONVEYOR_MAIN=$HM testissue t/a.test.sh Optimize the test file t/a.test.sh Median 12 CPU s. VERDICT: split
CONVEYOR_MAIN=$HM testissue t/b.test.sh Optimize the test file t/b.test.sh Median 9 CPU s. VERDICT: delete" ] || fail "test_issue_list_one_a_file: $(cat "$M/ctl.out") ran '$(calls)'"
# One file refused leaves the others taken, and says why for that file alone.
fresh_control
[ "$(ctl "$(act testaction run t/a.test.sh t/gone.test.sh)")" = 200 ] \
  && [ "$(jq -c '.results' "$M/ctl.out")" = '[{"file":"t/a.test.sh","id":"id-a.test.sh"},{"file":"t/gone.test.sh","refused":"conveyor: the file is not a file of main"}]' ] \
  || fail "test_list_refuses_one_file_alone: $(cat "$M/ctl.out") ran '$(calls)'"
# A list with a file of a bad shape, a test-issue list with a part missing, or a list over TEST_FILES_MAX runs nothing.
fresh_control
# shellcheck disable=SC2046 # each file an argument
for body in "$(act testaction judge t/a.test.sh -x.test.sh)" "$(act test-issue t/a.test.sh title body t/b.test.sh title)" \
  "$(act testaction judge $(seq -f 't/%g.test.sh' 21))"; do
  [ "$(ctl "$body")" = 400 ] || fail "test_list_takes_only_its_shapes: '$body' answered '$(cat "$M/ctl.out")'"
done
[ -z "$(calls)" ] || fail "test_list_takes_only_its_shapes: ran '$(calls)'"
pass=$((pass + 5))
# The Tests page's Mutation check (#79): the files selected are one ask, `mutate ask` with them all, which puts them at
# the front of the idle queue. Bug: one call a file (each would go before the last, so the order turned round), a
# command that ran a check now, or a file of a bad shape or a list over TEST_FILES_MAX that ran anything.
fresh_control
[ "$(ctl "$(act mutate t/a.test.sh t/b.test.sh t/c.test.sh)")" = 200 ] && [ "$(calls)" = "CONVEYOR_MAIN=$HM mutate ask t/a.test.sh t/b.test.sh t/c.test.sh" ] \
  || fail "mutate_one_ask: $(cat "$M/ctl.out") ran '$(calls)'"
fresh_control
# shellcheck disable=SC2046 # each file an argument
for body in "$(act mutate)" "$(act mutate t/a.test.sh -x.test.sh)" "$(act mutate $(seq -f 't/%g.test.sh' 21))"; do
  [ "$(ctl "$body")" = 400 ] || fail "mutate_takes_only_its_shapes: '$body' answered '$(cat "$M/ctl.out")'"
done
[ -z "$(calls)" ] || fail "mutate_takes_only_its_shapes: ran '$(calls)'"
pass=$((pass + 2))
# Yes on a visible change: the approval line, naming the Board user who said yes, is added to the issue's body,
# then the card is retried.
fresh_control; echo 12 > "$F/waiting"
[ "$(ctl "$(yes_act approve 12)")" = 200 ] && [ "$(calls | tr '\n' ,)" = "CONVEYOR_MAIN=$HM health,CONVEYOR_MAIN=$HM retry 12," ] \
  && [ "$(cat "$F/gh-body")" = "$(printf 'Old body\n\nVisible change approved: Quinn, %s (Board user max)' "$(TZ=America/New_York date +%F)")" ] \
  && grep -qx 'issue edit 12 --body-file -' "$F/gh-calls" && [ "$(cat "$F/gh-writes")" = 'issue edit 12 --body-file -' ] || fail "approve_writes_the_line_and_retries: ran '$(calls)', body '$(cat "$F/gh-body" 2>&1)'"
# No: the card is retried, then the issue is held, so it waits under Held. Bug (issue 1430): the hold came first, and
# the real retry releases an issue it finds held (retry.sh again()), so the declined card was built again; the stub
# here releases nothing, so the order of the calls is what shows it.
fresh_control; echo 12 > "$F/waiting"
[ "$(ctl "$(yes_act decline 12)")" = 200 ] && [ "$(calls | tr '\n' ,)" = "CONVEYOR_MAIN=$HM health,CONVEYOR_MAIN=$HM retry 12,CONVEYOR_MAIN=$HM control hold 12," ] \
  && [ ! -e "$F/gh-calls" ] || fail "decline_retries_then_holds: ran '$(calls)'"
# Yes with a condition (from "Needs you"): the condition is on the approval line, quoting kept.
fresh_control; echo 12 > "$F/waiting"
[ "$(ctl "$(yes_act approve 12 "only for admins; don't show 'beta'")")" = 200 ] && [ "$(calls | tr '\n' ,)" = "CONVEYOR_MAIN=$HM health,CONVEYOR_MAIN=$HM retry 12," ] \
  && [ "$(cat "$F/gh-body")" = "$(printf "Old body\n\nVisible change approved: Quinn, %s (Board user max); condition: only for admins; don't show 'beta'" "$(TZ=America/New_York date +%F)")" ] \
  || fail "approve_with_a_condition_writes_it_on_the_line: ran '$(calls)', body '$(cat "$F/gh-body" 2>&1)'"
# No with why: the reason is posted on the issue, then the card is retried and the issue held.
fresh_control; echo 12 > "$F/waiting"
[ "$(ctl "$(yes_act decline 12 'not for staff yet $(id)')")" = 200 ] && [ "$(calls | tr '\n' ,)" = "CONVEYOR_MAIN=$HM health,CONVEYOR_MAIN=$HM retry 12,CONVEYOR_MAIN=$HM control hold 12," ] \
  && [ "$(cat "$F/gh-calls")" = "issue comment 12 --body Visible change declined: Quinn, $(TZ=America/New_York date +%F) (Board user max): not for staff yet \$(id)" ] \
  && [ "$(cat "$F/gh-writes")" = "$(cat "$F/gh-calls")" ] \
  || fail "decline_with_why_posts_it_then_holds: ran '$(calls)', gh '$(cat "$F/gh-calls" 2>&1)', through gh-write '$(cat "$F/gh-writes" 2>&1)'"
pass=$((pass + 2))
# An issue waiting for the yes before its build (health's before) has no card: approve writes the line and
# retries nothing (the issue is picked in its turn); decline posts why and holds the issue, and retries nothing.
fresh_control; echo 14 > "$F/before"
[ "$(ctl "$(yes_act approve 14 'staff only')")" = 200 ] && [ "$(calls | tr '\n' ,)" = "CONVEYOR_MAIN=$HM health," ] \
  && [ "$(cat "$F/gh-body")" = "$(printf 'Old body\n\nVisible change approved: Quinn, %s (Board user max); condition: staff only' "$(TZ=America/New_York date +%F)")" ] \
  && grep -q 'issue #14 is approved before its build; it is picked in its turn' "$M/ctl.out" \
  || fail "approve_before_build_writes_the_line_and_retries_nothing: ran '$(calls)', body '$(cat "$F/gh-body" 2>&1)', answered '$(cat "$M/ctl.out")'"
fresh_control; echo 14 > "$F/before"
[ "$(ctl "$(yes_act decline 14 'not this')")" = 200 ] && [ "$(calls | tr '\n' ,)" = "CONVEYOR_MAIN=$HM health,CONVEYOR_MAIN=$HM control hold 14," ] \
  && [ "$(cat "$F/gh-calls")" = "issue comment 14 --body Visible change declined: Quinn, $(TZ=America/New_York date +%F) (Board user max): not this" ] \
  && grep -q 'issue #14 is held; it is not built until it is released' "$M/ctl.out" \
  || fail "decline_before_build_holds_and_retries_nothing: ran '$(calls)', gh '$(cat "$F/gh-calls" 2>&1)', answered '$(cat "$M/ctl.out")'"
pass=$((pass + 2))
# Needs you lists the cards of every record, so approve and decline name the card's repo, and the host acts on
# that record's checkout (its conveyor record, and gh in its folder). Bug: only the number was sent, so another
# repository's #12 approved and resumed main's #12. A repo host.json does not list is refused, and nothing runs; so is
# an approve or decline with no repo at all (a page open from before repo was sent), never taken as main's.
OM=$M/other-main; mkdir -p "$OM/.conveyor"
jq '.owner.name = "Sam"' "$HERE/../../../conveyor/lib/test-pack.json" > "$OM/.conveyor/project.json"
jq -n --arg m "$HM" --arg o "$OM" '{host: "buildhost", ssh: "user@buildhost", main: $m, records: [{repo: "sample", main: $m}, {repo: "widgetshop", main: $o}]}' > "$M/conveyor/host.json"
fresh_control; echo 12 > "$F/waiting"
[ "$(ctl '{"action":"approve","args":["12"],"repo":"widgetshop"}')" = 200 ] && [ "$(calls | tr '\n' ,)" = "CONVEYOR_MAIN=$OM health,CONVEYOR_MAIN=$OM retry 12," ] \
  && [ "$(sort -u "$F/gh-pwd")" = "$OM" ] && grep -q '^Visible change approved: Sam, ' "$F/gh-body" \
  || fail "approve_acts_on_the_cards_repo: ran '$(calls)' in '$(cat "$F/gh-pwd" 2>&1)', body '$(cat "$F/gh-body" 2>&1)'"
fresh_control; echo 12 > "$F/waiting"
[ "$(ctl '{"action":"decline","args":["12","no"],"repo":"widgetshop"}')" = 200 ] \
  && [ "$(calls | tr '\n' ,)" = "CONVEYOR_MAIN=$OM health,CONVEYOR_MAIN=$OM retry 12,CONVEYOR_MAIN=$OM control hold 12," ] \
  && [ "$(sort -u "$F/gh-pwd")" = "$OM" ] || fail "decline_acts_on_the_cards_repo: ran '$(calls)' in '$(cat "$F/gh-pwd" 2>&1)'"
fresh_control; echo 12 > "$F/waiting"
[ "$(ctl '{"action":"approve","args":["12"],"repo":"sample"}')" = 200 ] && [ "$(calls | tr '\n' ,)" = "CONVEYOR_MAIN=$HM health,CONVEYOR_MAIN=$HM retry 12," ] \
  && [ "$(sort -u "$F/gh-pwd")" = "$HM" ] || fail "approve_acts_on_mains_repo_when_named: ran '$(calls)' in '$(cat "$F/gh-pwd" 2>&1)'"
fresh_control; echo 12 > "$F/waiting"
[ "$(ctl '{"action":"approve","args":["12"],"repo":"elsewhere"}')" = 409 ] && grep -q 'no record elsewhere; nothing changed' "$M/ctl.out" \
  && [ ! -e "$F/ssh-calls" ] && [ -z "$(calls)" ] || fail "approve_of_an_unknown_repo_refused: '$(cat "$M/ctl.out")', ran '$(calls)'"
# The Board and the Rules tab steer every record on the host: a hold (or any action) sent for the second record runs
# on that record's checkout alone. Bug: every action but approve and decline ran on main's record, so the second
# project could be seen but not steered, and a hold for its #12 held main's #12.
fresh_control
[ "$(ctl '{"action":"hold","args":["12","13"],"repo":"widgetshop"}')" = 200 ] && [ "$(calls)" = "CONVEYOR_MAIN=$OM control hold 12 13" ] \
  || fail "control_acts_on_the_named_record: answered '$(cat "$M/ctl.out")', ran '$(calls)'"
# A pause or a resume of one project is that project's alone: the one command the host runs is on the named record's
# checkout, and none on the other's. Bug: a server that paused every record on a pause of one would stop the other
# project too; the page's own test delivers its readings by hand, so only this case can catch it.
for a in pause resume; do
  fresh_control
  [ "$(ctl "{\"action\":\"$a\",\"args\":[],\"repo\":\"widgetshop\"}")" = 200 ] && [ "$(calls)" = "CONVEYOR_MAIN=$OM control $a" ] \
    && [ "$(grep -c . "$F/ssh-calls")" = 1 ] || fail "${a}_of_one_project_leaves_the_other: answered '$(cat "$M/ctl.out")', ran '$(calls)' over '$(cat "$F/ssh-calls" 2>/dev/null)'"
  pass=$((pass + 1))
done
fresh_control
[ "$(ctl '{"action":"retry","args":["12"],"repo":"widgetshop"}')" = 200 ] && [ "$(calls)" = "CONVEYOR_MAIN=$OM retry 12" ] \
  || fail "retry_acts_on_the_named_record: ran '$(calls)'"
fresh_control
[ "$(ctl '{"action":"unlabel","args":["12","backlog"],"repo":"widgetshop"}')" = 200 ] && [ "$(calls)" = "CONVEYOR_MAIN=$OM control release 12" ] \
  && [ "$(sort -u "$F/gh-pwd")" = "$OM" ] || fail "unlabel_acts_in_the_named_records_repo: ran '$(calls)' in '$(cat "$F/gh-pwd" 2>&1)'"
# A steering request naming a record the host file does not list is refused, and nothing runs.
fresh_control
[ "$(ctl '{"action":"hold","args":["12"],"repo":"elsewhere"}')" = 409 ] && grep -q 'no record elsewhere; nothing changed' "$M/ctl.out" \
  && [ ! -e "$F/ssh-calls" ] && [ -z "$(calls)" ] || fail "control_of_an_unknown_record_refused: '$(cat "$M/ctl.out")', ran '$(calls)'"
pass=$((pass + 4))
for b in '{"action":"approve","args":["12"],"repo":"a b"}' '{"action":"decline","args":["12"],"repo":7}' '{"action":"approve","args":["12"],"repo":""}' \
  '{"action":"pause","args":[]}' '{"action":"hold","args":["12"]}' '{"action":"pause","args":[],"repo":null}' \
  '{"action":"approve","args":["12"]}' '{"action":"decline","args":["12","no"]}'; do
  got=$(ctl "$b")
  [ "$got" = 400 ] || fail "control_bad_repo_refused: '$b' answered $got '$(cat "$M/ctl.out")'"
done
[ ! -e "$F/ssh-calls" ] && [ -z "$(calls)" ] || fail "control_bad_repo_runs_nothing: $(cat "$F/ssh-calls" 2>/dev/null)"
jq -n --arg m "$HM" --arg l "$L" '{host: "buildhost", ssh: "user@buildhost", main: $m, records: [{repo: "sample", main: $m, ledger: $l}]}' > "$M/conveyor/host.json"
pass=$((pass + 6))
# "Remove the label and queue it": the label comes off the issue on GitHub, then the issue is released. The release
# carries CONVEYOR_UNLABELED (bug #1627: without it, control release dated no owner's release of an issue only the
# label held, so foreman status showed none and the Foreman held the issue again).
fresh_control
[ "$(ctl "$(act unlabel 12 ux-change)")" = 200 ] && [ "$(calls)" = "CONVEYOR_MAIN=$HM control release 12" ] \
  && [ "$(cat "$F/unlabeled-calls" 2>/dev/null)" = 'control release 12' ] \
  && [ "$(cat "$F/gh-calls")" = 'issue edit 12 --remove-label ux-change' ] && [ "$(cat "$F/gh-writes")" = "$(cat "$F/gh-calls")" ] && grep -q '"mode":"run"' "$M/ctl.out" \
  || fail "unlabel_removes_the_label_and_releases: ran '$(calls)', marked unlabeled '$(cat "$F/unlabeled-calls" 2>&1)', gh '$(cat "$F/gh-calls" 2>&1)', answered '$(cat "$M/ctl.out")'"
fresh_control
[ "$(ctl "$(act unlabel 13 backlog dormant)")" = 200 ] && [ "$(cat "$F/gh-calls")" = 'issue edit 13 --remove-label backlog --remove-label dormant' ] \
  || fail "unlabel_removes_every_label_named: gh '$(cat "$F/gh-calls" 2>&1)'"
pass=$((pass + 2))
# Yes or No on a card that is not waiting for a yes changes nothing: no line on the issue, no hold, no retry.
for a in approve decline; do
  fresh_control; echo 99 > "$F/waiting"
  [ "$(ctl "$(yes_act $a 12)")" = 409 ] && grep -q 'not waiting for your yes' "$M/ctl.out" && [ "$(calls)" = "CONVEYOR_MAIN=$HM health" ] && [ ! -e "$F/gh-calls" ] \
    || fail "${a}_of_a_card_not_waiting_refused: '$(cat "$M/ctl.out")', ran '$(calls)'"
done
pass=$((pass + 4))
# The host's own refusal is the reply; a host that does not answer is said.
fresh_control; echo "codex on this host does not list the model nosuch; nothing changed" > "$F/conveyor-refuse"
[ "$(ctl "$(act model codex nosuch)")" = 409 ] && grep -q "codex on this host does not list the model nosuch" "$M/ctl.out" || fail "host_refusal_is_the_reply: $(cat "$M/ctl.out")"
fresh_control; : > "$F/ssh-down"
[ "$(ctl "$(act pause)")" = 502 ] && grep -q 'buildhost did not answer' "$M/ctl.out" || fail "host_down_is_said: $(cat "$M/ctl.out")"
pass=$((pass + 2))
# Logged out, cross-site, or not the page's JSON: refused, and nothing reaches the host.
fresh_control
[ "$(ctl "$(act stop)" "$A/none")" = 401 ] && grep -q 'log in to steer the loop' "$M/ctl.out" || fail "control_logged_out_refused: $(cat "$M/ctl.out")"
[ "$(ctl "$(act stop)" "$A/ct" https://evil.example)" = 403 ] || fail "control_from_another_origin_refused"
[ "$(ctl "$(act stop)" "$A/ct" "$U" text/plain)" = 403 ] || fail "control_as_a_form_refused"
[ "$(ctl "$(act stop)" "$A/ct" -)" = 403 ] || fail "control_with_a_wrong_origin_refused"
pass=$((pass + 4))
# An unknown action, a bad value, or a body of another shape: 400, and nothing reaches the host.
for b in "$(act frob)" "$(act 'pause;rm')" "$(act pause now)" "$(act cap 101)" "$(act cap 0)" "$(act cap 08)" "$(act cap)" "$(act guard 0)" "$(act guard 101)" \
  "$(act hold)" "$(act hold x)" "$(act hold '12; rm -rf /')" "$(act hold 012)" "$(act release -1)" "$(act order 12 '$(id)')" \
  "$(act rules serena=deploy)" "$(act rules 'serena=build,')" "$(act rules 'serena=build;id')" \
  "$(act start)" "$(act start maybe)" "$(act start held queue)" "$(act start 'held;id')" \
  "$(act rules)" "$(act rules P4=off)" "$(act rules P1=maybe)" "$(act rules 'area:a b=off')" "$(act rules split=maybe)" "$(act rules pick=maybe)" "$(act rules 'split=on;id')" \
  "$(act model)" "$(act model --help)" "$(act model claude m bogus)" "$(act model default high)" "$(act model claude m high x)" "$(act reviewer codex 'm;id')" \
  "$(act model claude-opus-5-5)" "$(act model claude-opus-5-5 high)" "$(act model nosuch m)" "$(act model claude --help)" "$(act model claude '')" \
  "$(act reviewer antigravity gem-1)" "$(act judge antigravity gem-1 high)" "$(act tests antigravity gem-1)" "$(act reviewer opencode 'openrouter/m;id')" "$(act reviewer opencode '/m')" "$(act judge opencode 'p/m $(id)')" "$(act judge opencode 'p/m x')" \
  "$(act judge)" "$(act judge on off)" "$(act judge always 'a b')" "$(act judge always 'x;id')" "$(act judge always -x)" "$(act judge always $(seq 21))" "$(act judge rare)" "$(act judge rare P4)" "$(act judge rare p3)" "$(act judge rare none P3)" "$(act judge rare 'P3;id')" "$(act judge claude m bogus)" \
  "$(act account a b)" "$(act account 'a;id')" "$(act account -x)" "$(act review-account '')" \
  "$(act dep-guard)" "$(act dep-guard maybe)" "$(act dep-guard on off)" "$(act push-check)" "$(act push-check maybe)" "$(act push-check on off)" "$(act force)" "$(act force x)" "$(act force 12 13)" "$(act force '12;id')" \
  "$(act land-as)" "$(act land-as branch)" "$(act land-as main pr)" "$(act pr-merge)" "$(act pr-merge never)" "$(act pr-merge idle button)" \
  "$(act onboarded)" "$(act onboarded Build)" "$(act onboarded 'build;id')" "$(act onboarded -x)" "$(act onboarded $(seq -f r%g 41))" \
  "$(act approve)" "$(act approve 12 a b)" "$(act retry x)" "$(act retry 12 13)" "$(act retry x --fresh)" "$(act retry 12 --hold)" "$(act retry c20261115T120000-sample-0 --fresh)" "$(act unblock)" "$(act unblock x)" "$(act unblock 12 --hold)" "$(act close)" "$(act close x)" "$(act close 012)" "$(act close '12;id')" "$(act close 12 13)" "$(act decline '')" "$(act approve x why)" \
  "$(act build)" "$(act build 12)" "$(act build 'd0123456789ab;id')" "$(act build d0123456789ab d0123456789ab)" \
  "$(act approve 12 '')" "$(act approve 12 ' padded')" "$(act decline 12 $'two\nlines')" "$(act decline 12 "$(printf 'x%.0s' $(seq 301))")" \
  "$(act unlabel 12)" "$(act unlabel x backlog)" "$(act unlabel 12 '.x')" "$(act unlabel 12 'a b')" "$(act unlabel 12 'backlog;id')" "$(act unlabel 12 a b c d e f)" \
  "$(act depends)" "$(act depends 12)" "$(act depends 12 add)" "$(act depends 12 drop 7)" "$(act depends 12 ADD 7)" "$(act depends x add 7)" "$(act depends 012 add 7)" \
  "$(act depends 12 add 07)" "$(act depends 12 remove '7;id')" "$(act depends 12 add 7 -x)" "$(act depends add 12 7)" "$(act depends 12 add $(seq 21))" \
  "$(act suite-machine)" "$(act suite-machine frob)" "$(act suite-machine local now)" "$(act suite-machine devbox 4x8)" "$(act suite-machine devbox --size)" "$(act suite-machine devbox --size '4x8;id')" \
  "$(act suite-machine devbox --box)" "$(act suite-machine devbox --box 'a;id')" "$(act suite-machine devbox --box -x)" "$(act suite-machine devbox --box a --box b)" "$(act suite-machine devbox --box a --setup-at 2026-11-20T15:04:00Z)" \
  "$(act suite-machine devbox --size 4x8 x)" "$(act suite-machine devbox --size 4x8 --setup-at)" "$(act suite-machine devbox --size 4x8 --setup-at yesterday)" "$(act suite-machine devbox --size 4x8 --setup-at '2026-11-20T15:04:00Z;id')" "$(act suite-machine devbox --size 4x8 --since 2026-11-20T15:04:00Z)" "$(act suite-machine ssh)" "$(act suite-machine ssh -oProxyCommand=id)" "$(act suite-machine ssh 'a b')" "$(act suite-machine ssh box --dir)" \
  "$(act suite-machine ssh box dir /x)" "$(act suite-machine ssh box --dir rel/x)" "$(act suite-machine ssh box --dir '~other')" "$(act suite-machine ssh box --dir '/x;id')" "$(act suite-machine ssh box --dir "$(printf '/a\nb')")" \
  "$(act suite-machine-check now)" "$(act suite-mode)" "$(act suite-mode frob)" "$(act suite-mode Parallel)" "$(act suite-mode serial parallel)" \
  '{"action":"hold","args":[12]}' '{"action":"pause"}' '{"action":"pause","args":[],"extra":1}' '{"action":["pause"],"args":[]}' '[]' 'not json'; do
  got=$(ctl "$b")
  [ "$got" = 400 ] || fail "control_bad_value_refused: '$b' answered $got '$(cat "$M/ctl.out")'"
  pass=$((pass + 1))
done
# Bug: an invalid Test files at once value was refused with a bare Bad Request, so the Rules tab could not say why.
for b in "$(act atonce 0)" "$(act atonce -1)" "$(act atonce 1.5)" "$(act atonce 1000)" "$(act atonce)" "$(act atonce 2 3)"; do
  got=$(ctl "$b")
  [ "$got" = 400 ] && grep -q 'must be a whole number from 1 to 999' "$M/ctl.out" || fail "control_atonce_refused_with_reason: '$b' answered $got '$(cat "$M/ctl.out")'"
  pass=$((pass + 1))
done
[ ! -e "$F/ssh-calls" ] && [ -z "$(calls)" ] || fail "control_refusals_run_nothing: $(cat "$F/ssh-calls" 2>/dev/null)"
[ "$(ctl "$(act hold "$(seq -s ' ' 1 51)")")" = 400 ] || fail "control_too_many_issues_refused"
pass=$((pass + 2))
fresh_control
done_part
) & started control

# Users. An admin manages every user from the Board; a member uses the Board and manages only their own password,
# MFA and devices. The server refuses a member every user-management route (403), so the page's Users panel, drawn
# from GET /users, has nothing to show a member. Each user-management action is audited ($AU), with no secret in the line.
PW2='ana horse battery' PW3='bo horse battery'
# um <jar> <method> <path> [body] -- a request as the page sends it; the status, the body in $M/um.out.
um() {
  local d=(); [ -z "${4:-}" ] || d=(--data-binary "$4")
  command curl -s --cacert "$CERT" -b "$1" -o "$M/um.out" -w '%{http_code}' -X "$2" -H "Origin: $U" -H 'Content-Type: application/json' ${d[@]+"${d[@]}"} "$U$3"
}
# ua <jar> <action> <user> [key value] -- POST /users {action, user[, key: value]}.
ua() { um "$1" POST /users "$(jq -cn --arg a "$2" --arg u "$3" --arg k "${4:-}" --arg v "${5:-}" '{action: $a, user: $u} + (if $k == "" then {} else {($k): $v} end)')"; }
setup_with() {
  command curl -s --cacert "$CERT" -o "$M/setup.out" -w '%{http_code}' -X POST -H "Origin: $U" -H 'Content-Type: application/json' \
    --data-binary "$(jq -cn --arg t "${1#/setup#}" --arg p "$2" '{token: $t, password: $p}')" "$U/setup"
}
store() { jq -c "$@" "$CONVEYOR_DASHBOARD_AUTH"; }

# A Board action below goes through POST /control, so this part has the control host too, and max a trusted device
# named control-test.
( fresh users "${PORTS[6]}"; ready; control_setup
[ "$(login "$A/ct" true control-test)" = 200 ] || fail "users: max could not log in on control-test"
GJ=$A/ct
AU0=$(nlines "$AU")
restart; [ "$(login "$A/adm" false admin-test)" = 200 ] || fail "users: the admin could not log in"
# Add from the Board: a one-time setup link (no password shown or sent); the new user sets their own, then logs in.
[ "$(ua "$A/adm" add ana role member)" = 200 ] && LINK=$(jq -r .link "$M/um.out") && [[ $LINK == /setup#?????????????????????????????????????????* ]] \
  || fail "admin_adds_a_user_with_a_setup_link: $(cat "$M/um.out")"
[ "$(store '.users.ana | [.role, has("hash"), .mfa, .lastLogin]')" = '["member",false,false,null]' ] || fail "admin_adds_a_user_with_a_setup_link: $(store .users.ana)"
[ "$(login "$A/ana" false x "$PW2" ana)" = 401 ] || fail "added_user_has_no_password_until_setup"
[ "$(bare -s -o /dev/null -w '%{http_code}' "$U/setup")" = 200 ] || fail "setup_page_is_public"
[ "$(setup_with "$LINK" short)" = 400 ] || fail "setup_refuses_a_short_password"
[ "$(setup_with "$LINK" "$PW2")" = 200 ] || fail "setup_link_sets_the_password: $(cat "$M/setup.out")"
[ "$(setup_with "$LINK" 'another password')" = 410 ] || fail "setup_link_works_once: the second use answered $(cat "$M/setup.out")"
[ "$(login "$A/ana" true ana-phone "$PW2" ana)" = 200 ] && [ "$(status_of "$A/ana" /index.html)" = 200 ] || fail "added_user_logs_in_after_setup: $(cat "$M/login.out")"
[ "$(store '.users.ana.lastLogin | test("^[0-9-]{10}T[0-9:]{8}Z$")')" = true ] || fail "login_records_last_login: $(store .users.ana)"
# A setup link lasts 24 h: one past that is refused.
[ "$(ua "$A/adm" add bo role member)" = 200 ] && LINK_BO=$(jq -r .link "$M/um.out") || fail "admin_adds_a_user: $(cat "$M/um.out")"
left=$(store '[.setups[] | select(.user == "bo") | .exp - now] | .[0] | floor')
[ "$left" -gt 86000 ] && [ "$left" -le 86400 ] || fail "setup_link_lasts_24_hours: $left s left"
jq '.setups |= map_values(.exp = 1)' "$CONVEYOR_DASHBOARD_AUTH" > "$A/store.tmp" && cat "$A/store.tmp" > "$CONVEYOR_DASHBOARD_AUTH"
[ "$(setup_with "$LINK_BO" "$PW3")" = 410 ] && [ "$(store '.users.bo | has("hash")')" = false ] || fail "setup_link_expires: answered $(cat "$M/setup.out")"
pass=$((pass + 12))
# A member: GET /me is their own record; every user-management route is 403, and nothing in the store moves.
[ "$(um "$A/ana" GET /me)" = 200 ] && jq -e '.user == "ana" and .role == "member" and (.devices | map(.label)) == ["ana-phone"] and (.devices[0].used | test("^[0-9-]{10}T[0-9:]{8}Z$")) and (tostring | test("sha|hash|salt") | not)' "$M/um.out" >/dev/null \
  || fail "member_sees_their_own_record: $(cat "$M/um.out")"
BEFORE=$(cksum < "$CONVEYOR_DASHBOARD_AUTH")
[ "$(um "$A/ana" GET /users)" = 403 ] || fail "member_refused_the_users_list: $(um "$A/ana" GET /users) $(cat "$M/um.out")"
for b in 'add zed role admin' 'role ana role admin' 'role max role member' 'reset max' 'mfa-off max' 'revoke max device all' 'remove max' 'remove bo'; do
  # shellcheck disable=SC2086
  got=$(ua "$A/ana" $b); [ "$got" = 403 ] || fail "member_refused_every_user_action: '$b' answered $got '$(cat "$M/um.out")'"
  pass=$((pass + 1))
done
[ "$(cksum < "$CONVEYOR_DASHBOARD_AUTH")" = "$BEFORE" ] || fail "member_refused_every_user_action: the store changed"
# Where a release's suite runs sends the release commit to that machine: a member's change of it is refused and reaches
# no host; Check the box, which only reads, still answers a member. Bug: a member could send the commit to an ssh host.
fresh_control
for b in 'suite-machine ssh box.example.com' 'suite-machine devbox' 'suite-machine local'; do
  # shellcheck disable=SC2086
  got=$(ctl "$(act $b)" "$A/ana"); { [ "$got" = 403 ] && [ -z "$(calls)" ]; } || fail "member_refused_the_suite_machine: '$b' answered $got '$(cat "$M/ctl.out")', ran '$(calls)'"
  pass=$((pass + 1))
done
# Bug: a member's check asked the account for a devbox, which can create one: the member's check runs with --no-create.
got=$(ctl "$(act suite-machine-check)" "$A/ana"); [ "$got" = 200 ] && [ "$(calls)" = "CONVEYOR_MAIN=$HM suite-machine check --json --no-create" ] || fail "member_may_check_the_suite_machine: answered $got '$(cat "$M/ctl.out")', ran '$(calls)'"
pass=$((pass + 1))
fresh_control
# An action that is not a string is a bad request, not a crash (a list cannot be looked up in the action table).
[ "$(um "$A/ana" POST /me '{"action":[]}')" = 400 ] || fail "malformed_own_action_is_400: answered $(um "$A/ana" POST /me '{"action":[]}')"
[ "$(um "$A/adm" POST /users '{"action":[],"user":"example"}')" = 400 ] || fail "malformed_user_action_is_400: answered $(um "$A/adm" POST /users '{"action":[],"user":"example"}')"
[ "$(cksum < "$CONVEYOR_DASHBOARD_AUTH")" = "$BEFORE" ] || fail "malformed_user_action_is_400: the store changed"
pass=$((pass + 2))
# The page: account.js, run on a stub page whose /me says member, removes the Users panel and never asks for the
# users; for an admin it keeps the panel and draws it from GET /users.
page_as() {
  node - "$HERE/../../dashboard/account.js" "$1" <<'EOF'
const src = require('fs').readFileSync(process.argv[2], 'utf8'), role = process.argv[3];
const el = () => ({ style: {}, children: [], dataset: {}, setAttribute() {}, addEventListener() {}, append(...c) { this.children.push(...c); }, replaceChildren(...c) { this.children = c; }, remove() { this.removed = true; } });
const els = {}, asked = [];
const document = { getElementById: (id) => (els[id] = els[id] || el()), createElement: el };
const json = (d) => Promise.resolve({ ok: true, status: 200, json: () => Promise.resolve(d) });
const window = { location: { assign() {}, origin: '' }, fetch(url) {
  asked.push(url);
  return url === 'me' ? json({ user: 'ana', role, created: null, lastLogin: null, mfa: false, password: true, devices: [] }) : json({ me: 'ana', users: [] });
} };
document.getElementById('panel-users').hidden = true; // as account.html serves it
require('vm').runInNewContext(src, { window, document });
const p = els['panel-users'];
setTimeout(() => console.log(`${asked.join(',')} ${p.removed ? 'removed' : p.hidden ? 'hidden' : 'shown'}`), 100);
EOF
}
# That the panel is hidden as served is in dashboard-view.account.test.mjs (the Users panel stays hidden until /me answers).
[ "$(page_as member)" = 'me removed' ] || fail "member_does_not_see_the_users_panel: $(page_as member)"
[ "$(page_as admin)" = 'me,users shown' ] || fail "admin_sees_the_users_panel: $(page_as admin)"
# An admin resetting their own password keeps the page and its setup link: a reload would answer 401, go to /login and
# lose the only copy of the link. Another user's reset reloads as before. Either way the link is drawn on the page (in
# its box under the user).
reset_as() {
  node - "$HERE/../../dashboard/account.js" "$1" <<'EOF'
const src = require('fs').readFileSync(process.argv[2], 'utf8'), whom = process.argv[3];
const el = () => ({ style: {}, children: [], on: {}, attrs: {}, dataset: {}, classList: { add() {} }, setAttribute(k, v) { this.attrs[k] = v; }, addEventListener(k, f) { this.on[k] = f; }, append(...c) { this.children.push(...c); }, replaceChildren(...c) { this.children = c; }, remove() { this.removed = true; } });
const els = {}, asked = [], made = [];
const document = { getElementById: (id) => (els[id] = els[id] || el()), createElement: () => { const e = el(); made.push(e); return e; } };
const json = (d) => Promise.resolve({ ok: true, status: 200, headers: { get: () => 'application/json' }, json: () => Promise.resolve(d) });
const u = (n) => ({ user: n, role: 'admin', created: null, lastLogin: null, mfa: false, password: true, devices: [] });
let reset = false, went = '';
const window = { location: { assign(to) { went = to; }, origin: 'https://example.com' }, setTimeout: () => 1, clearTimeout() {}, fetch(url, o) {
  asked.push(url + (o ? ':post' : ''));
  if (o) { reset = reset || whom === 'max'; return json({ link: '/setup#tok' }); }
  if (reset) return Promise.resolve({ ok: false, status: 401, text: () => Promise.resolve('') });
  return url === 'me' ? json(u('max')) : json({ me: 'max', users: [u('ana'), u('max')] });
} };
require('vm').runInNewContext(src, { window, document });
setTimeout(() => {
  // A reset acts on the second click: the first only arms the button (no browser dialog).
  const b = made.find((x) => x.attrs['aria-label'] === `Reset the password of ${whom}`);
  b.on.click(); b.on.click();
  setTimeout(() => console.log(`${asked.slice(2).join(',')} ${went || 'stayed'} ${made.some((e) => e.textContent === 'https://example.com/setup#tok')}`), 100);
}, 100);
EOF
}
[ "$(reset_as max)" = 'users:post stayed true' ] || fail "own_reset_keeps_its_setup_link: $(reset_as max)"
[ "$(reset_as ana)" = 'users:post,me,users stayed true' ] || fail "anothers_reset_reloads_the_page: $(reset_as ana)"
# Turning MFA on: while the recovery codes are on screen, the user's facts say the codes are on, not off as they were
# drawn with.
mfa_turned_on() {
  node - "$HERE/../../dashboard/account.js" "$1" <<'EOF'
const src = require('fs').readFileSync(process.argv[2], 'utf8'), role = process.argv[3];
const el = () => ({ style: {}, children: [], on: {}, attrs: {}, dataset: {}, classList: { add() {} }, value: '123456', setAttribute(k, v) { this.attrs[k] = v; }, addEventListener(k, f) { this.on[k] = f; }, append(...c) { this.children.push(...c); }, replaceChildren(...c) { this.children = c; }, replaceWith(n) { this.replacedBy = n; }, focus() {}, remove() { this.removed = true; } });
const els = {}, made = [];
const document = { getElementById: (id) => (els[id] = els[id] || el()), createElement: () => { const e = el(); made.push(e); return e; } };
const json = (d) => Promise.resolve({ ok: true, status: 200, headers: { get: () => 'application/json' }, json: () => Promise.resolve(d) });
let on = false;
const u = () => ({ user: 'ana', role, created: null, lastLogin: null, mfa: on, password: true, devices: [] });
const window = { location: { assign() {}, origin: 'https://example.com' }, fetch(url, o) {
  if (!o) return json(url === 'me' ? u() : { me: 'ana', users: [u()] });
  if (JSON.parse(o.body).action === 'mfa-setup') return json({ secret: 'JBSWY3DPEHPK3PXP', uri: '' });
  on = true;
  return json({ recovery: ['1111-2222-3333-4444'] });
} };
const chips = (meta) => meta.children.filter((c) => /chip/.test(c.className)).map((c) => c.textContent).join('+');
const row = () => (role === 'admin' ? ` users:${chips(els['users-body'].children[0].children[0].children[1])}` : '');
require('vm').runInNewContext(src, { window, document });
setTimeout(() => {
  const info = els['me-body'].children[1], before = chips(info);
  made.find((b) => b.attrs['aria-label'] === 'Turn on authenticator codes for your account').on.click();
  setTimeout(() => {
    made.filter((f) => f.on.submit).pop().on.submit({ preventDefault() {} });
    setTimeout(() => console.log(`${before} ${info.replacedBy ? chips(info.replacedBy) : 'unchanged'}${row()} ${els.note.textContent}`), 100);
  }, 100);
}, 100);
EOF
}
[ "$(mfa_turned_on member)" = 'Member+Authenticator codes off Member+Authenticator codes on Authenticator codes are on.' ] || fail "mfa_on_redraws_the_users_facts: $(mfa_turned_on member)"
[ "$(mfa_turned_on admin)" = 'Admin+Authenticator codes off Admin+Authenticator codes on users:Admin+Authenticator codes on Authenticator codes are on.' ] || fail "mfa_on_redraws_the_admins_own_row: $(mfa_turned_on admin)"
pass=$((pass + 9))
# A member manages their own devices, MFA and password only.
MAXDEV=$(device_id control-test); [ -n "$MAXDEV" ] || fail "member_cannot_revoke_anothers_device: max has no device control-test"
[ "$(um "$A/ana" POST /me "$(jq -cn --arg d "$MAXDEV" '{action: "revoke", device: $d}')")" = 409 ] && [ "$(device_id control-test)" = "$MAXDEV" ] \
  || fail "member_cannot_revoke_anothers_device: $(cat "$M/um.out")"
jq '.users.ana.mfa = true' "$CONVEYOR_DASHBOARD_AUTH" > "$A/store.tmp" && cat "$A/store.tmp" > "$CONVEYOR_DASHBOARD_AUTH"
[ "$(um "$A/ana" POST /me '{"action":"mfa-off"}')" = 200 ] && [ "$(store .users.ana.mfa)" = false ] || fail "member_turns_off_own_mfa: $(cat "$M/um.out")"
[ "$(um "$A/ana" POST /me "$(jq -cn --arg p "$PW3" '{action: "password", old: "wrong password", new: $p}')")" = 403 ] || fail "own_password_needs_the_current_one: a wrong one must not be 401, which sends the page to /login"
[ "$(um "$A/ana" POST /me "$(jq -cn --arg o "$PW2" --arg p "$PW3" '{action: "password", old: $o, new: $p}')")" = 200 ] \
  && [ "$(login "$A/ana2" false x "$PW3" ana)" = 200 ] && [ "$(login "$A/ana-old" false x "$PW2" ana)" = 401 ] || fail "member_sets_own_password: $(cat "$M/um.out")"
# {"user":"ana","password":"","trust":false,"label":""} is 53 bytes, so 4043 characters is the longest password that
# logs in. It can be set, and changed both to and from (old and new travel in one body).
LONGPW=$(head -c 4043 /dev/zero | tr '\0' a)
[ "$(um "$A/ana2" POST /me "$(jq -cn --arg o "$PW3" --arg p "$LONGPW" '{action: "password", old: $o, new: $p}')")" = 200 ] \
  && [ "$(login "$A/ana2" false '' "$LONGPW" ana)" = 200 ] \
  && [ "$(um "$A/ana2" POST /me "$(jq -cn --arg o "$LONGPW" --arg p "$PW3" '{action: "password", old: $o, new: $p}')")" = 200 ] \
  && [ "$(login "$A/ana2" false x "$PW3" ana)" = 200 ] || fail "long_password_can_be_changed: $(cat "$M/um.out")"
# One /me's 8192-byte body carries but /login's 4096 does not is refused, and the sessions and password stay.
[ "$(um "$A/ana2" POST /me "$(jq -cn --arg o "$PW3" --arg p "$TOOLONG" '{action: "password", old: $o, new: $p}')")" = 400 ] \
  && [ "$(status_of "$A/ana2" /index.html)" = 200 ] && [ "$(login "$A/ana3" false x "$PW3" ana)" = 200 ] \
  || fail "own_password_too_long_to_log_in_with_refused: $(cat "$M/um.out")"
ANA_PW=$PW2 PW2=$PW3
pass=$((pass + 6))
# One browser: the admin logs in trusting it, then ana logs in without trust. The admin's device cookie must go, or
# once ana's session ends that browser is the admin again with no password asked.
same() { command curl -s --cacert "$CERT" -b "$1" -c "$1" -o /dev/null -w '%{http_code}' -X POST -H "Origin: $U" -H 'Content-Type: application/json' \
  --data-binary "$(jq -cn --arg u "$2" --arg p "$3" --argjson t "$4" '{user: $u, password: $p, trust: $t, label: "shared"}')" "$U/login"; }
: > "$A/shared"
[ "$(same "$A/shared" max "$PW" true)" = 200 ] && grep -q pp_device "$A/shared" && [ "$(same "$A/shared" ana "$PW2" false)" = 200 ] \
  || fail "switch_user_clears_device_cookie: a login was refused"
grep -v pp_session "$A/shared" > "$A/shared-left"
! grep -q pp_device "$A/shared" && [ "$(status_of "$A/shared-left" /index.html)" = 302 ] \
  || fail "switch_user_clears_device_cookie: the admin's device cookie outlived ana's untrusted login"
pass=$((pass + 1))
# A Board action records the acting user: the approval line and the ruling row name ana, the log line too.
fresh_control; echo 12 > "$F/waiting"
[ "$(ctl "$(yes_act approve 12)" "$A/ana")" = 200 ] && grep -q '^Visible change approved: Quinn, .* (Board user ana)$' "$F/gh-body" \
  || fail "board_action_records_the_user: approve answered '$(cat "$M/ctl.out")', body '$(cat "$F/gh-body" 2>&1)'"
grep -q 'dashboard: control approve 12 by ana from ' "$M/server.err" || fail "board_action_records_the_user: no log line names ana"
tail -1 "$M/rulings.jsonl" | jq -e '.question == "Board control: approve 12" and .user == "ana" and .source == "dashboard"' >/dev/null \
  || fail "board_action_logs_a_ruling_naming_the_user: $(tail -1 "$M/rulings.jsonl")"
add_dec d-ana
[ "$(answer_with "$A/ana" d-ana)" = 200 ] && [ "$(tail -1 "$M/rulings.jsonl" | jq -r .user)" = ana ] || fail "answer_records_the_user: $(tail -1 "$M/rulings.jsonl")"
fresh_control
pass=$((pass + 4))
# The audit log of this part's actions: who, what, whom, when for each, and never a password (ana's first, her own
# changes, the long one), a hash, a salt or a link's token. This part's log is its own; the admins part checks its own.
jq -se 'all(keys - ["action", "by", "device", "role", "time", "user"] == [] and (.time | test("^[0-9-]{10}T[0-9:]{8}Z$")))' "$AU" >/dev/null \
  && [ "$(head -1 "$AU" | jq -r '"\(.by) \(.action) \(.user) \(.role)"')" = 'cli add max admin' ] \
  && [ "$(tail -n +$((AU0 + 1)) "$AU" | jq -rs 'map("\(.by) \(.action) \(.user)") | join(",")')" = 'max add ana,ana setup ana,max add bo,ana mfa-off ana,ana set-password ana,ana set-password ana,ana set-password ana' ] \
  || fail "audit_log_says_who_what_whom_when: $(cat "$AU")"
[ "$(mode "$AU")" = 600 ] || fail "audit_log_is_private"
for secret in "$PW" "$ANA_PW" "$PW3" "$LONGPW" "${LINK#/setup#}" "${LINK_BO#/setup#}" $(store -r '.users[] | .hash, .salt'); do
  grep -qF -- "$secret" "$AU" "$M/server.err" && fail "audit_line_holds_no_secret: a password, hash or link token is in the audit log or the server log"
  pass=$((pass + 1))
done
pass=$((pass + 2))
done_part
) & started users

( fresh admins "${PORTS[10]}"; ready
restart; [ "$(login "$A/adm" false admin-test)" = 200 ] || fail "admins: the admin could not log in"
# ana and bo as the part above leaves them: ana a member whose password is $PW3, logged in trusting this browser
# ($A/ana, ana-phone) and in a session of her own ($A/ana2); bo added and never set up.
[ "$(ua "$A/adm" add ana role member)" = 200 ] && [ "$(setup_with "$(jq -r .link "$M/um.out")" "$PW3")" = 200 ] \
  && [ "$(login "$A/ana" true ana-phone "$PW3" ana)" = 200 ] && [ "$(login "$A/ana2" false x "$PW3" ana)" = 200 ] \
  && [ "$(ua "$A/adm" add bo role member)" = 200 ] && LINK_BO=$(jq -r .link "$M/um.out") \
  || fail "admins: ana and bo could not be set up: $(cat "$M/um.out")"
PW2=$PW3
AU0=$(nlines "$AU")
# An admin's actions. A role change ends that user's sessions (a session-only cookie is refused); reset ends theirs only.
grep pp_session "$A/ana2" > "$A/ana-session"
[ "$(status_of "$A/ana-session" /index.html)" = 200 ] || fail "role_change_ends_sessions: no session to end"
[ "$(ua "$A/adm" role ana role admin)" = 200 ] && [ "$(store .users.ana.role)" = '"admin"' ] || fail "admin_makes_a_user_admin: $(cat "$M/um.out")"
[ "$(status_of "$A/ana-session" /index.html)" = 302 ] && [ "$(status_of "$A/adm" /index.html)" = 200 ] || fail "role_change_ends_that_users_sessions"
[ "$(um "$A/ana" GET /users)" = 200 ] && [ "$(jq -c '[.users[].user]' "$M/um.out")" = '["ana","bo","max"]' ] || fail "an_admin_lists_users: $(cat "$M/um.out")"
[ "$(ua "$A/adm" role ana role member)" = 200 ] || fail "admin_makes_a_user_member: $(cat "$M/um.out")"
[ "$(login "$A/ana3" false x "$PW2" ana)" = 200 ] && grep pp_session "$A/ana3" > "$A/ana-session" || fail "reset: ana could not log in"
[ "$(ua "$A/adm" reset ana)" = 200 ] && LINK=$(jq -r .link "$M/um.out") && [[ $LINK == /setup#* ]] || fail "admin_resets_a_password: $(cat "$M/um.out")"
[ "$(status_of "$A/ana-session" /index.html)" = 302 ] && [ "$(status_of "$A/adm" /index.html)" = 200 ] || fail "reset_ends_that_users_sessions_only"
[ "$(login "$A/ana3" false x "$PW2" ana)" = 401 ] && [ "$(setup_with "$LINK" "$PW3")" = 200 ] && [ "$(login "$A/ana3" false x "$PW3" ana)" = 200 ] \
  || fail "reset_password_is_set_through_its_link"
jq '.users.ana.mfa = true' "$CONVEYOR_DASHBOARD_AUTH" > "$A/store.tmp" && cat "$A/store.tmp" > "$CONVEYOR_DASHBOARD_AUTH"
[ "$(ua "$A/adm" mfa-off ana)" = 200 ] && [ "$(store .users.ana.mfa)" = false ] || fail "admin_turns_off_a_users_mfa: $(cat "$M/um.out")"
grep pp_device "$A/ana" > "$A/ana-device"
[ "$(status_of "$A/ana-device" /index.html)" = 200 ] && [ "$(ua "$A/adm" revoke ana device all)" = 200 ] && [ "$(status_of "$A/ana-device" /index.html)" = 302 ] \
  && [ -z "$(cli devices ana)" ] || fail "admin_revokes_a_users_devices: $(cat "$M/um.out")"
pass=$((pass + 10))
# The last admin cannot be removed or made a member; a removed user's sessions and devices end at once.
[ "$(ua "$A/adm" role max role member)" = 409 ] && grep -q 'last admin' "$M/um.out" || fail "last_admin_cannot_be_demoted: $(cat "$M/um.out")"
[ "$(ua "$A/adm" remove max)" = 409 ] && grep -q 'last admin' "$M/um.out" || fail "last_admin_cannot_be_removed: $(cat "$M/um.out")"
[ "$(login "$A/ana4" true ana-phone-4 "$PW3" ana)" = 200 ] && [ "$(status_of "$A/ana4" /index.html)" = 200 ] || fail "remove: ana could not log in"
grep pp_device "$A/ana4" > "$A/ana-device"
[ "$(ua "$A/adm" remove ana)" = 200 ] && [ "$(store '.users | has("ana")')" = false ] || fail "admin_removes_a_user: $(cat "$M/um.out")"
[ "$(status_of "$A/ana4" /index.html)" = 302 ] && [ "$(status_of "$A/ana-device" /index.html)" = 302 ] && [ "$(status_of "$A/ana3" /index.html)" = 302 ] \
  || fail "removed_users_sessions_and_devices_end_at_once"
pass=$((pass + 4))
# A request whose login ends while its body is on its way changes nothing: an admin made a member mid-request adds no
# one, and a password reset mid-request is not overwritten with a password checked against the old one. In process,
# so the change lands between the first checks and the store write.
got=$("$PY" - "$SRV" <<'EOF'
import io, json, os, sys, time
sys.path.insert(0, os.path.dirname(sys.argv[1])); import dashboard_server as s
s.change_store(lambda st: s.set_hash(st, st['users']['bo'], 'bo old password'))
def run(user, path, body, meanwhile):
    tok = 'race-' + user
    s.SESSIONS[s.sha(tok)] = {'exp': time.time() + 60, 'epoch': s.read_store()['users'][user]['epoch'], 'device': None, 'user': user}
    codes = []
    h = type('H', (), {})()
    h.headers, h.client_address = {'Cookie': 'pp_session=' + tok}, ('192.0.2.1', 0)
    h.own_page = lambda: True
    h.authed = lambda store=None: s.Handler.authed(h, store)
    h.this_device = lambda store: s.Handler.this_device(h, store)
    h.json_body = lambda limit: (s.change_store(meanwhile), body)[1]
    h.reply = lambda code, text, headers=None: codes.append(code)
    h.json_reply = lambda code, data: codes.append(code)
    s.Handler.users_post(h, path)
    return codes[0]
demote = lambda st: (s.user_action(st, 'role', 'bo', 'admin'), s.user_action(st, 'role', 'max', 'member'))
a = run('max', '/users', {'action': 'add', 'user': 'intruder', 'role': 'admin'}, demote)
st = s.read_store()
print(a, 'intruder' in st['users'], end=' ')
s.change_store(lambda st: (s.user_action(st, 'role', 'max', 'admin'), s.user_action(st, 'role', 'bo', 'member')))
b = run('bo', '/me', {'action': 'password', 'old': 'bo old password', 'new': 'bo new password'}, lambda st: s.user_action(st, 'reset', 'bo'))
st = s.read_store()
print(b, 'hash' in st['users']['bo'])
EOF
)
[ "$got" = '401 False 401 False' ] || fail "user_action_rechecks_its_login_under_the_lock: status, intruder added, status, bo has a password = $got"
pass=$((pass + 2))
# A Board action whose user is removed while its body is on its way runs nothing: no control reaches the host, no
# answer reaches decision.sh. Bug: the login was checked only before the body was read.
got=$("$PY" - "$SRV" <<'EOF'
import io, os, sys, time
sys.path.insert(0, os.path.dirname(sys.argv[1])); import dashboard_server as s
ran = []
s.run_script = lambda args, timeout: ran.append(args[0]) or (_ for _ in ()).throw(OSError('must not run'))
def run(path, body):
    s.change_store(lambda st: s.user_action(st, 'add', 'gone', 'member'))
    tok = 'race-gone'
    s.SESSIONS[s.sha(tok)] = {'exp': time.time() + 60, 'epoch': s.read_store()['users']['gone']['epoch'], 'device': None, 'user': 'gone'}
    codes = []
    class Body:
        def read(self, n):
            s.change_store(lambda st: s.user_action(st, 'remove', 'gone'))
            return body
    h = type('H', (), {})()
    h.path, h.command, h.rfile, h.client_address = path, 'POST', Body(), ('192.0.2.1', 0)
    h.headers = {'Cookie': 'pp_session=' + tok, 'Content-Length': str(len(body))}
    h.own_page = lambda: True
    h.authed = lambda store=None: s.Handler.authed(h, store)
    h.this_device = lambda store: s.Handler.this_device(h, store)
    h.reply = lambda code, text, headers=None: codes.append(code)
    h.send_error = lambda code: codes.append(code)
    h.control = lambda: s.Handler.control(h)
    s.Handler.do_POST(h)
    return codes[0]
print(run('/control', b'{"action":"pause","args":[],"repo":"sample"}'), run('/answer', b'{"id":"d-race","answer":"yes","askedAt":"2026-10-18T12:00:00Z","repo":"sample"}'), ran)
EOF
)
[ "$got" = '401 401 []' ] || fail "board_action_rechecks_its_login_after_the_body: control status, answer status, ran = $got"
pass=$((pass + 2))
# The command line, for the first user and recovery: add, set-role, mfa-off, devices, remove; the last user stays.
printf '%s\n%s\n' "$PW3" "$PW3" | cli add-user cy --admin >/dev/null && [ "$(store .users.cy.role)" = '"admin"' ] || fail "cli_add_user_admin"
cli set-role cy member >/dev/null && [ "$(store .users.cy.role)" = '"member"' ] || fail "cli_set_role"
cli set-role max member >/dev/null 2>&1 && fail "cli_last_admin_cannot_be_demoted"
jq '.users.cy.mfa = true' "$CONVEYOR_DASHBOARD_AUTH" > "$A/store.tmp" && cat "$A/store.tmp" > "$CONVEYOR_DASHBOARD_AUTH"
cli mfa-off cy >/dev/null && [ "$(store .users.cy.mfa)" = false ] || fail "cli_mfa_off: $(store .users.cy)"
# A removed user's name given again is a new user: the removed one's session does not come back with it.
printf '%s\n%s\n' "$PW3" "$PW3" | cli add-user dee >/dev/null && [ "$(login "$A/dee" false x "$PW3" dee)" = 200 ] || fail "reused_name: dee could not log in"
cli remove-user dee >/dev/null && printf '%s\n%s\n' "$PW3" "$PW3" | cli add-user dee >/dev/null && [ "$(status_of "$A/dee" /index.html)" = 302 ] \
  || fail "reused_name_does_not_revive_the_removed_users_sessions"
cli remove-user dee >/dev/null || fail "reused_name: dee could not be removed"
cli remove-user cy >/dev/null && cli remove-user bo >/dev/null || fail "cli_remove_user"
cli remove-user max >/dev/null 2>"$M/rm.err" && fail "last_user_cannot_be_removed"
grep -q 'last user' "$M/rm.err" && [ "$(store '.users | keys')" = '["max"]' ] || fail "last_user_cannot_be_removed: $(cat "$M/rm.err")"
pass=$((pass + 6))
# The audit log: who, what, whom, when for each action, and never a password, a hash, a salt or a link's token.
jq -se 'all(keys - ["action", "by", "device", "role", "time", "user"] == [] and (.time | test("^[0-9-]{10}T[0-9:]{8}Z$")))' "$AU" >/dev/null \
  && [ "$(head -1 "$AU" | jq -r '"\(.by) \(.action) \(.user) \(.role)"')" = 'cli add max admin' ] \
  && [ "$(tail -n +$((AU0 + 1)) "$AU" | jq -rs 'map("\(.by) \(.action) \(.user)") | join(",")')" = 'max role ana,max role ana,max reset ana,ana setup ana,max mfa-off ana,max revoke ana,max remove ana,cli add cy,cli role cy,cli mfa-off cy,cli add dee,cli remove dee,cli add dee,cli remove dee,cli remove cy,cli remove bo' ] \
  || fail "audit_log_says_who_what_whom_when: $(cat "$AU")"
[ "$(mode "$AU")" = 600 ] || fail "audit_log_is_private"
for secret in "$PW" "$PW2" "$PW3" "${LINK#/setup#}" "${LINK_BO#/setup#}" $(store -r '.users[] | .hash, .salt'); do
  grep -qF -- "$secret" "$AU" "$M/server.err" && fail "audit_line_holds_no_secret: a password, hash or link token is in the audit log or the server log"
  pass=$((pass + 1))
done
pass=$((pass + 2))
done_part
) & started admins

( fresh mfa "${PORTS[7]}"; ready
# MFA, each user's choice: TOTP per RFC 6238 as authenticator apps read it (SHA-1, 6 digits, 30 s), through pyotp.
# Bugs it holds against: a code accepted outside the step either side of now, or twice (a replay); MFA on before
# one valid code; a user with MFA off asked for a code; a recovery code that works twice; code failures that do not
# count toward the lockout, or a password alone that clears the count; the secret kept or shown in the clear.
got=$("$PY" - "$SRV" <<'EOF'
import base64, hashlib, os, sys
import pyotp
sys.path.insert(0, os.path.dirname(sys.argv[1])); import dashboard_server as s
# RFC 6238 Appendix B, SHA-1: the seed "12345678901234567890", 8 digits; the server's 6-digit codes are their last 6.
seed = base64.b32encode(b'12345678901234567890').decode()
vec = {59: '94287082', 1111111109: '07081804', 1111111111: '14050471', 1234567890: '89005924', 2000000000: '69279037', 20000000000: '65353130'}
ok8 = all(pyotp.TOTP(seed, digits=8, digest=hashlib.sha1, interval=30).at(t) == c for t, c in vec.items())
ok6 = all(s.totp(seed).at(t) == c[-6:] for t, c in vec.items())
now, t = 1234567890, s.totp(seed)
st = now // 30
window = [s.totp_step(seed, t.generate_otp(st + d), now, -1) for d in (-2, -1, 0, 1, 2)] == [None, st - 1, st, st + 1, None]
replay = s.totp_step(seed, t.generate_otp(st), now, st) is None and s.totp_step(seed, t.generate_otp(st + 1), now, st) == st + 1
print(ok8, ok6, window, replay)
EOF
)
[ "$got" = 'True True True True' ] || fail "totp_rfc6238_vectors_window_and_replay: vectors 8-digit, 6-digit, the window, no replay: $got"
pass=$((pass + 4))
restart
printf '%s\n%s\n' "$PW2" "$PW2" | cli add-user mia >/dev/null || fail "mfa: mia could not be added"
# code_with <jar> <code> -- the code step of the login in <jar>; the status, the body in $M/login.out.
code_with() {
  command curl -s --cacert "$CERT" -b "$1" -c "$1" -o "$M/login.out" -w '%{http_code}' -X POST -H "Origin: $U" -H 'Content-Type: application/json' \
    --data-binary "$(jq -cn --arg c "$2" '{code: $c}')" "$U/login"
}
# step_code <secret> <step> -- the app's code for that step.
step_code() { "$PY" -c 'import sys, pyotp; print(pyotp.TOTP(sys.argv[1]).generate_otp(int(sys.argv[2])))' "$1" "$2"; }
now_step() { echo $(( $(date +%s) / 30 )); }
[ "$(login "$A/mia" false x "$PW2" mia)" = 200 ] && [ "$(status_of "$A/mia" /index.html)" = 200 ] || fail "mfa_off_logs_in_with_the_password_alone: $(cat "$M/login.out")"
[ "$(um "$A/mia" POST /me '{"action":"mfa-on","code":"123456"}')" = 409 ] || fail "mfa_on_needs_a_setup_first: $(cat "$M/um.out")"
[ "$(um "$A/mia" POST /me '{"action":"mfa-setup"}')" = 200 ] && SECRET=$(jq -r .secret "$M/um.out") && [[ $SECRET =~ ^[A-Z2-7]{32}$ ]] \
  && [ "$(jq -r .uri "$M/um.out")" = "otpauth://totp/Conveyor:mia?secret=$SECRET&issuer=Conveyor" ] || fail "mfa_setup_gives_the_secret_and_uri: $(cat "$M/um.out")"
[ "$(store '.users.mia | [.mfa, has("totpPending"), has("totp")]')" = '[false,true,false]' ] && ! grep -qF "$SECRET" "$CONVEYOR_DASHBOARD_AUTH" \
  && [ "$(mode "$A/dashboard-mfa.key")" = 600 ] || fail "mfa_secret_is_kept_encrypted_with_a_0600_key: $(store .users.mia) key $(mode "$A/dashboard-mfa.key")"
[ "$(bare -s -b "$A/mia" -D "$M/qr.head" -o "$M/qr.svg" -w '%{http_code}' "$U/me/qr")" = 200 ] && grep -qi '^content-type: image/svg+xml' "$M/qr.head" && grep -q '<svg' "$M/qr.svg" \
  || fail "mfa_setup_shows_a_qr: $(cat "$M/qr.head")"
[ "$(bare -s -o /dev/null -w '%{http_code}' "$U/me/qr")" = 401 ] || fail "mfa_qr_needs_the_login"
pass=$((pass + 6))
S0=$(now_step); BAD=$(printf '%06d' $(( (10#$(step_code "$SECRET" "$S0") + 1) % 1000000 )))
[ "$(um "$A/mia" POST /me "$(jq -cn --arg c "$BAD" '{action: "mfa-on", code: $c}')")" = 403 ] && [ "$(store .users.mia.mfa)" = false ] \
  || fail "mfa_on_needs_one_valid_code: a wrong code answered $(cat "$M/um.out")"
# A code that is not ASCII is a wrong code too (compare_digest raised on it: the request died with no answer).
[ "$(um "$A/mia" POST /me '{"action":"mfa-on","code":"é"}')" = 403 ] && [ "$(store .users.mia.mfa)" = false ] \
  || fail "mfa_on_refuses_a_non_ascii_code: $(cat "$M/um.out")"
# A lone surrogate is valid JSON but no str.encode() takes it: refused as a wrong code, not a crash of the request.
[ "$(um "$A/mia" POST /me '{"action":"mfa-on","code":"\ud800"}')" = 403 ] && [ "$(store .users.mia.mfa)" = false ] \
  || fail "mfa_on_refuses_a_lone_surrogate_code: $(cat "$M/um.out")"
[ "$(um "$A/mia" POST /me "$(jq -cn --arg c "$(step_code "$SECRET" "$S0")" '{action: "mfa-on", code: $c}')")" = 200 ] && jq -r '.recovery[]' "$M/um.out" > "$M/recovery" \
  && [ "$(wc -l < "$M/recovery" | tr -d ' ')" = 10 ] && [ "$(sort -u "$M/recovery" | wc -l | tr -d ' ')" = 10 ] || fail "mfa_on_with_a_valid_code_gives_10_recovery_codes: $(cat "$M/um.out")"
[ "$(store '.users.mia | [.mfa, has("totp"), has("totpPending"), (.recovery | length)]')" = '[true,true,false,10]' ] \
  && ! grep -qF -f <(cat "$M/recovery"; tr -d -- '- ' < "$M/recovery") "$CONVEYOR_DASHBOARD_AUTH" && ! grep -qF "$SECRET" "$CONVEYOR_DASHBOARD_AUTH" \
  || fail "mfa_on_keeps_only_hashes_and_the_encrypted_secret: $(store .users.mia)"
[ "$(status_of "$A/mia" /me/qr)" = 404 ] && [ "$(um "$A/mia" POST /me '{"action":"mfa-setup"}')" = 409 ] \
  || fail "mfa_secret_is_not_shown_again_once_on"
pass=$((pass + 5))
# Login with MFA on: the password gives no session, only the code step; the next step's code logs in, once.
TAKEN=$(store .users.mia.totpStep)
[ "$(login "$A/mia2" false x "$PW2" mia)" = 202 ] && grep -q pp_mfa "$A/mia2" && ! grep -q pp_session "$A/mia2" && [ "$(status_of "$A/mia2" /index.html)" = 302 ] \
  || fail "mfa_password_alone_opens_nothing: $(cat "$M/login.out")"
CODE=$(step_code "$SECRET" $((TAKEN + 1)))
[ "$(code_with "$A/mia2" "$CODE")" = 200 ] && [ "$(status_of "$A/mia2" /index.html)" = 200 ] || fail "mfa_valid_code_logs_in: $(cat "$M/login.out")"
[ "$(login "$A/mia3" false x "$PW2" mia)" = 202 ] && [ "$(code_with "$A/mia3" "$CODE")" = 401 ] && [ "$(status_of "$A/mia3" /index.html)" = 302 ] \
  || fail "mfa_reused_code_refused: $(cat "$M/login.out")"
[ "$(code_with "$A/nobody" "$CODE")" = 401 ] || fail "mfa_code_without_a_password_step_refused"
pass=$((pass + 4))
# A recovery code works once in place of a code, typed with or without its dashes; a trusted device then skips both steps.
R1=$(sed -n 1p "$M/recovery")
[ "$(login "$A/mia4" true mia-phone "$PW2" mia)" = 202 ] && [ "$(code_with "$A/mia4" "${R1//-/}")" = 200 ] && [ "$(store '.users.mia.recovery | length')" = 9 ] \
  || fail "mfa_recovery_code_works: $(cat "$M/login.out")"
[ "$(login "$A/mia5" false x "$PW2" mia)" = 202 ] && [ "$(code_with "$A/mia5" "$R1")" = 401 ] || fail "mfa_recovery_code_works_once"
grep pp_device "$A/mia4" > "$A/mia-device"
[ "$(status_of "$A/mia-device" /index.html)" = 200 ] || fail "mfa_trusted_device_skips_the_code"
pass=$((pass + 3))
# The code step finds its pp_mfa cookie among other apps' cookies that Python's cookie parser rejects.
[ "$(login "$A/mia-f" false x "$PW2" mia)" = 202 ] && [ "$(command curl -s --cacert "$CERT" -c "$A/mia-f" -o "$M/login.out" -w '%{http_code}' -X POST \
  -H "Origin: $U" -H 'Content-Type: application/json' -H "$(among_foreign "$A/mia-f")" \
  --data-binary "$(jq -cn --arg c "$(sed -n 2p "$M/recovery")" '{code: $c}')" "$U/login")" = 200 ] \
  || fail "mfa_code_step_among_foreign_cookies: $(cat "$M/login.out")"
pass=$((pass + 1))
# Lockout: two wrong passwords, a right one (which does not clear the count while the code is owed), then three wrong
# codes make LOCK_AFTER: every login, even the right password, is refused until it lifts. A restart starts the count at 0.
# One wrong code is not ASCII: it is refused and counted like any other, not a request that dies uncounted.
restart
for i in 1 2; do [ "$(login "$A/mia6" false x 'wrong password here' mia)" = 401 ] || fail "lockout: a wrong password was not 401"; done
[ "$(login "$A/mia6" false x "$PW2" mia)" = 202 ] || fail "lockout: the password step: $(cat "$M/login.out")"
for c in "$BAD" é "$BAD"; do [ "$(code_with "$A/mia6" "$c")" = 401 ] || fail "lockout: the wrong code $c was not 401: $(cat "$M/login.out")"; done
[ "$(login "$A/mia7" false x "$PW2" mia)" = 429 ] && [ "$(login "$A/mia7" false x)" = 429 ] || fail "mfa_code_failures_count_toward_lockout: $(cat "$M/login.out")"
pass=$((pass + 1))
# MFA off (from the account): the secret and recovery codes go, and the password alone logs in again.
restart
[ "$(um "$A/mia-device" POST /me '{"action":"mfa-off"}')" = 200 ] && [ "$(store '.users.mia | [.mfa, has("totp"), has("recovery"), has("totpStep")]')" = '[false,false,false,false]' ] \
  && [ "$(login "$A/mia8" false x "$PW2" mia)" = 200 ] || fail "mfa_off_drops_the_secret: $(store .users.mia)"
grep -rqF -- "$SECRET" "$M/server.err" "$AU" "$CONVEYOR_DASHBOARD_AUTH" && fail "mfa_secret_never_logged"
pass=$((pass + 2))
[ "$(cli remove-user mia >/dev/null && store '.users | has("mia")')" = false ] || fail "mfa: mia could not be removed"
# Nothing secret is written down: not the password, not either cookie, in the served folder, the logs, the unsent folder or the store.
restart
[ "$(login "$A/sec" true secret-7)" = 200 ] || fail "no_secret_in_files: login refused"
SES=$(awk '$6 == "pp_session" {print $7}' "$A/sec"); DEV=$(awk '$6 == "pp_device" {print $7}' "$A/sec")
[ -n "$SES" ] && [ -n "$DEV" ] || fail "no_secret_in_files: no cookie to look for"
for secret in "$PW" "$SES" "$DEV"; do
  grep -rqF -- "$secret" "$T/out" "$M/rulings.jsonl" "$M/dashboard-unsent" "$M/server.err" "$CONVEYOR_DASHBOARD_AUTH" "$L" 2>/dev/null \
    && fail "no_secret_in_files: a secret is written in plain text"
  pass=$((pass + 1))
done
done_part
) & started mfa

( fresh standalone "${PORTS[8]}"; ready; control_setup; service_stubs
# Plan A9: the Board runs from its own files alone. Its release folder is no git checkout and holds only the
# Board's scripts, decision.sh and the page (no paths.sh, host-services.sh, peer-runtime.sh, .githooks/lib-workspaces.sh
# or test-hosts.json). The checkout is CONVEYOR_MAIN and has no conveyor/host.json: the host, its checkout and its
# ssh target are the ones this machine's host file (under XDG_CONFIG_HOME) names. It collects an open decision
# onto the page, reaches the host at that target, installs its own copy as the job (keeping CONVEYOR_MAIN and
# XDG_CONFIG_HOME), runs that job's loop (page copied from the release folder, no sync-install.sh), serves the page,
# records an answer and steers the loop.
# Bug caught: dashboard.sh died at its first line (`. paths.sh`), then found the host only through test-hosts.json
# and the checkout's conveyor/host.json, and the page and the job's script only in the checkout; the job it installed
# lost XDG_CONFIG_HOME. It must keep XDG_CACHE_HOME too: the job's account reads and their 429 deadline go in the
# folder the engine's guard and the Foreman's watcher use (issue 1087), and a job without it read another folder's.
SA=$M/standalone R=$M/standalone/release C=$HM
mkdir -p "$R/.claude/scripts" "$C/.claude/metrics" "$SA/config/conveyor" "$SA/userhome" "$SA/ws"
cp "$HERE"/../{dashboard*.sh,dashboard_server*.py,dashboard_stream.py,dashboard_limit*.py,dashboard_alerts.jq,dashboard_needs.json,decision.sh,hostfile.sh} "$R/.claude/scripts/"
cp -R "$HERE/../../dashboard" "$R/.claude/"
jq -n --arg m "$C" --arg l "$C/.claude/metrics/decisions.jsonl" '{host: "buildhost", ssh: "user@standalone", main: $m, records: [{repo: "sample", main: $m, ledger: $l}]}' > "$SA/config/conveyor/host.json"
[ ! -e "$C/conveyor/host.json" ] || fail "standalone setup: the checkout must have no conveyor/host.json"
dec d-alone "$ASKED" 'Standalone?' > "$C/.claude/metrics/decisions.jsonl"
: > "$M/rulings.jsonl"; fresh_control
# An array, not a function: `"${board[@]}" ... & PID=$!` is the command itself, so kill "$PID" stops the loop (a
# backgrounded function is a subshell, and the loop outlived the test).
board=(env -u CODEX_HOME CONVEYOR_MAIN="$C" HOME="$SA/userhome" XDG_CONFIG_HOME="$SA/config" XDG_CACHE_HOME="$SA/cache" PATH="$M/bin:$PATH" CONVEYOR_HOST_OS=Linux
  CONVEYOR_WORKSPACES="$SA/ws" CONVEYOR_SCRATCH="$SA/scratch" CONVEYOR_DASHBOARD_DIR="$SA/out" CONVEYOR_RULING_LOG="$M/rulings.jsonl"
  CONVEYOR_DASHBOARD_PORT="$PORT")
board() { "${board[@]}" "$@"; }
board timeout 120 bash "$R/.claude/scripts/dashboard.sh" 2>"$SA/collect.err" || fail "standalone_board_collects: exited non-zero: $(cat "$SA/collect.err")"
sed -e '1s/^window\.DASH = //' -e '$s/;$//' "$SA/out/data.js" \
  | jq -e '.panels.needs.data.decisions | map(.id) == ["d-alone"]' >/dev/null \
  || fail "standalone_board_collects: the open decision is not on the page: $(head -c 600 "$SA/out/data.js")"
grep -q ' user@standalone ' "$F/ssh-calls" 2>/dev/null \
  || fail "standalone_board_reaches_the_host: no ssh to host.json's target: '$(cat "$F/ssh-calls" 2>/dev/null)'"
pass=$((pass + 2))
board bash "$R/.claude/scripts/dashboard.sh" --install >"$SA/install.out" 2>&1 \
  && grep -qF "ExecStart=\"$BASH\" \"$R/.claude/scripts/dashboard.sh\" --loop" "$SA/userhome/.config/systemd/user/dashboard.service" \
  && grep -qxF "Environment=\"XDG_CONFIG_HOME=$SA/config\"" "$SA/userhome/.config/systemd/user/dashboard.service" \
  && grep -qxF "Environment=\"XDG_CACHE_HOME=$SA/cache\"" "$SA/userhome/.config/systemd/user/dashboard.service" \
  && grep -qxF "Environment=\"CONVEYOR_MAIN=$C\"" "$SA/userhome/.config/systemd/user/dashboard.service" \
  || fail "standalone_board_installs: $(cat "$SA/install.out") $(cat "$SA/userhome/.config/systemd/user/dashboard.service" 2>/dev/null)"
pass=$((pass + 1))
# The job's loop, with the page server on this test's port. index.html goes first, so the one served is the loop's copy.
kill "$PID"; wait "$PID" 2>/dev/null; rm -f "$SA/out/index.html"
"${board[@]}" bash "$R/.claude/scripts/dashboard.sh" --loop >"$SA/loop.log" 2>&1 & PID=$!
wait_until 'command curl -s --cacert "$CERT" -o /dev/null "$U/login" || ! kill -0 "$PID" 2>/dev/null'
[ "$(login "$JAR" true standalone)" = 200 ] || fail "standalone_board_serves: login refused: $(cat "$M/login.out") $(cat "$SA/loop.log")"
GJ=$JAR
[ "$(curl -s -o /dev/null -w '%{http_code}' "$U/data.js")" = 200 ] || fail "standalone_board_serves: data.js is not served"
[ "$(curl -s -o "$SA/served.html" -w '%{http_code}' "$U/index.html")" = 200 ] && cmp -s "$SA/served.html" "$R/.claude/dashboard/index.html" \
  || fail "standalone_board_serves: /index.html is not the release folder's page: $(head -c 300 "$SA/served.html") $(cat "$SA/loop.log")"
# The cycle's end is written before the sync-install step, which a release folder has none of: the loop goes on quietly.
wait_until 'grep -q "\"lastCycleSec\":[0-9]" "$SA/out/.cycle" 2>/dev/null || ! kill -0 "$PID" 2>/dev/null'
# The loop's wait for its next cycle (its own sleep 60) begins once the step after the cycle's end is over.
wait_until 'pgrep -P "$PID" -f "^sleep 60\$" >/dev/null || ! kill -0 "$PID" 2>/dev/null' # sleep: the loop's own, named here to find it
grep -q '"lastCycleSec":[0-9]' "$SA/out/.cycle" && kill -0 "$PID" && ! grep -qE 'sync-install|unbound|No such file' "$SA/loop.log" \
  || fail "standalone_board_loops: $(cat "$SA/out/.cycle" 2>/dev/null) $(cat "$SA/loop.log")"
pass=$((pass + 4))
send 200 standalone_board_records_an_answer POST /answer "$(ans d-alone 'yes' "$ASKED")" $J "$U" "$H"
jq -e 'select(.id == "d-alone") | .answer == "yes" and .answeredAt != null' <(tail -1 "$C/.claude/metrics/decisions.jsonl") >/dev/null \
  && jq -e '.question == "Standalone?" and .answer == "yes"' "$M/rulings.jsonl" >/dev/null \
  || fail "standalone_board_records_an_answer: ledger $(tail -1 "$C/.claude/metrics/decisions.jsonl"); rulings $(cat "$M/rulings.jsonl")"
pass=$((pass + 1))
fresh_control
got=$(ctl "$(act pause)" "$JAR")
# The loop's live feed calls the host's conveyor.sh too, so the control call is found among its calls.
[ "$got" = 200 ] && calls | grep -qxF "CONVEYOR_MAIN=$HM control pause" && grep -q ' user@standalone bash -c ' "$F/ssh-calls" \
  || fail "standalone_board_steers_the_loop: answered $got '$(cat "$M/ctl.out")', ran '$(calls)' over '$(cat "$F/ssh-calls" 2>/dev/null)'"
pass=$((pass + 1))
done_part
) & started standalone

# Every part ended, and ran to its end (its pass count written last); the file's checks are theirs added up.
pass=0 bad=()
for p in "${PARTS[@]}"; do
  if wait "${p#*:}" && [ -s "$TOP/${p%%:*}/pass" ]; then pass=$((pass + $(cat "$TOP/${p%%:*}/pass"))); else bad+=("${p%%:*}"); fi
done
[ ${#bad[@]} -eq 0 ] || fail "these parts failed (their FAIL lines are above): ${bad[*]}"
# Nothing in the run reached the stand-in real host: its conveyor.sh was never called and its control record is unchanged.
[ ! -e "$RH/calls" ] && cmp -s "$RH/control.before" "$RH/main/conveyor/state/control.json" \
  || fail "real_host_untouched: calls '$(cat "$RH/calls" 2>/dev/null)', control record $(cat "$RH/main/conveyor/state/control.json")"
pass=$((pass + 1))
echo "PASS: dashboard-server ($pass checks)"
