#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# POST /time (issue 506): the Board's Time setting, sent from Customize, kept in time.json in the served folder, where
# the /units pane reads it (hooks/units.tsx readTime). Bugs each case catches: the Time never leaving the browser (the
# pane wrote AM and PM with 24-hour set); a value the pane cannot read, or any other key, written to the file; and a
# write taken without a login or from another site's page.
# The server runs in this process, over plain HTTP: what is checked is the handler, not TLS. Its requests come from
# this device, which "No login on this device" (on with no value stored) lets in with no login.
set -uo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
export XDG_DATA_HOME=${XDG_DATA_HOME:-$HOME/.local/share}
PY=$XDG_DATA_HOME/conveyor/board-venv/bin/python3
"$PY" -c 'import pyotp, segno, cryptography' || { echo "FAIL: the Board's virtualenv $PY lacks its packages: run conveyor.sh setup" >&2; exit 1; }
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
mkdir -p "$T/out" "$T/auth"
CONVEYOR_DASHBOARD_AUTH=$T/auth/dashboard-auth.json CONVEYOR_RULING_LOG=$T/rulings.jsonl XDG_CONFIG_HOME=$T/config \
  HOME=$T CONVEYOR_MAIN=$T "$PY" -I - "$HERE/.." "$T/out" <<'EOF'
import functools, http.client, io, json, os, stat, sys, threading
sys.path.insert(0, sys.argv[1])
import dashboard_server as ds

OUT = sys.argv[2]
KEPT = os.path.join(OUT, 'time.json')
srv = ds.Server(('127.0.0.1', 0), functools.partial(ds.Handler, directory=OUT))
PORT = srv.server_address[1]
threading.Thread(target=srv.serve_forever, kwargs={'poll_interval': 0.02}, daemon=True).start()
passed = [0]


def check(case, ok, why=''):
    if not ok:
        sys.exit('FAIL: %s: %s' % (case, why))
    passed[0] += 1


def post(body, host='localhost:%d' % PORT, origin=None):
    c = http.client.HTTPConnection('127.0.0.1', PORT, timeout=10)
    c.request('POST', '/time', body=json.dumps(body).encode(),
              headers={'Host': host, 'Origin': origin or 'https://' + host, 'Content-Type': 'application/json'})
    r = c.getresponse()
    r.read()
    c.close()
    return r.status


def kept():
    with open(KEPT) as f:
        return json.load(f)


err, sys.stderr = sys.stderr, io.StringIO()
check('sets_24', post({'time': '24-hour'}) == 200 and kept() == {'time': '24-hour'}, os.path.exists(KEPT) and kept())
log, sys.stderr = sys.stderr.getvalue(), err
# Bug it catches: a Time write that named no user, where every other write of the server names one in its log.
check('names_its_user', 'dashboard: Time set to 24-hour by %s from 127.0.0.1' % ds.LOCAL in log, log)
check('readable_by_the_pane', stat.S_IMODE(os.stat(KEPT).st_mode) == 0o644, oct(os.stat(KEPT).st_mode))
check('sets_12', post({'time': '12-hour'}) == 200 and kept() == {'time': '12-hour'}, kept())
check('no_temp_left', sorted(os.listdir(OUT)) == ['time.json'], os.listdir(OUT))
# Refused, and the kept Time stays: a value the pane cannot read, another key, no login, another site's page.
check('bad_value', post({'time': '25-hour'}) == 400 and kept() == {'time': '12-hour'}, kept())
check('other_key', post({'time': '24-hour', 'date': 'dd/mm/yyyy'}) == 400 and kept() == {'time': '12-hour'}, kept())
check('not_logged_in', post({'time': '24-hour'}, host='192.0.2.1:%d' % PORT) == 401 and kept() == {'time': '12-hour'}, kept())
check('other_site', post({'time': '24-hour'}, origin='https://example.com') == 403 and kept() == {'time': '12-hour'}, kept())
# Bug it catches (#1461 B-R138): a browser's first send of the Time it kept from before (first: true) overwrote the
# Time set since in another browser. It is kept only when no Time is here; the server checks as it writes, so a Time
# sent between a page's read and its send is not overwritten either.
check('first_refused_when_kept', post({'time': '24-hour', 'first': True}) == 409 and kept() == {'time': '12-hour'}
      and sorted(os.listdir(OUT)) == ['time.json'], 'POST /time {time: 24-hour, first: true} over a kept 12-hour: %s, %s' % (kept(), os.listdir(OUT)))
check('first_not_true', post({'time': '24-hour', 'first': False}) == 400 and kept() == {'time': '12-hour'}, 'POST /time {time: 24-hour, first: false}: %s' % kept())
os.remove(KEPT)
check('first_kept_when_none', post({'time': '24-hour', 'first': True}) == 200 and kept() == {'time': '24-hour'}
      and sorted(os.listdir(OUT)) == ['time.json'], 'POST /time {time: 24-hour, first: true} with no time.json: %s' % os.listdir(OUT))
srv.shutdown()
print('PASS: dashboard-server-time (%d checks)' % passed[0])
EOF
