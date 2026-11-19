#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# "No login on this device" (dashboard_server.py, Handler.this_device): the Board opened on the machine it runs on
# needs no login, and acts as an admin named "this device"; every other device logs in. These cases hold that
# boundary: only a connection whose own peer is loopback, to a Host of localhost or a loopback address on the Board's
# port, is let in; no header makes another peer pass for one; the setting is on with no value stored, and an admin
# alone turns it off, at once. Bug each case catches: the Board open to the LAN, or to another site through the
# owner's browser (DNS rebinding), with no login.
# The server runs in this process (its own handler and checks, over plain HTTP), so a case can give a request any
# peer address it needs: Server.get_request hands the handler the peer the case names, as the socket would.
set -uo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
export XDG_DATA_HOME=${XDG_DATA_HOME:-$HOME/.local/share}
PY=$XDG_DATA_HOME/conveyor/board-venv/bin/python3
"$PY" -c 'import pyotp, segno, cryptography' || { echo "FAIL: the Board's virtualenv $PY lacks its packages: run conveyor.sh setup" >&2; exit 1; }
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
mkdir -p "$T/out" "$T/auth"
echo page > "$T/out/index.html"
CONVEYOR_DASHBOARD_AUTH=$T/auth/dashboard-auth.json CONVEYOR_RULING_LOG=$T/rulings.jsonl XDG_CONFIG_HOME=$T/config \
  HOME=$T CONVEYOR_MAIN=$T "$PY" -I - "$HERE/.." "$T/out" <<'EOF'
import functools, http.client, io, json, os, subprocess, sys, threading
sys.path.insert(0, sys.argv[1])
import dashboard_server as ds

# The passwords here only log the two users in from another device; how they are hashed is dashboard-server.test.sh's.
# The cheapest scrypt the server takes, so its four hashes (two set, two checked) cost no time.
ds.SCRYPT = {'n': 2, 'r': 1, 'p': 1}

PEER = ['127.0.0.1']


class Server(ds.Server):
    def get_request(self):
        sock, addr = super().get_request()
        return sock, (PEER[0], addr[1])


srv = Server(('127.0.0.1', 0), functools.partial(ds.Handler, directory=sys.argv[2]))
PORT = srv.server_address[1]
# A short poll: shutdown() at the end waits for the serving loop's next poll, 0.5 s at its default.
threading.Thread(target=srv.serve_forever, kwargs={'poll_interval': 0.02}, daemon=True).start()
LOCAL_HOST = 'localhost:%d' % PORT
# The host the control route steers, and its ssh: the command it would run is kept, never run.
RAN = []
ds.conveyor_host = lambda: ('buildhost', 'user@buildhost', '/srv/main', {'project': '/srv/main'})
ds.run_script = lambda args, timeout, env=None: RAN.append(args) or subprocess.CompletedProcess(args, 0, 'conveyor: paused\n', '')
passed = [0]


def fail(case, why):
    sys.exit('FAIL: %s: %s' % (case, why))


def req(method, path, peer='127.0.0.1', host=LOCAL_HOST, headers=None, body=None, cookie=None):
    """(status, headers, body) of one request from peer, with this Host."""
    PEER[0] = peer
    h = {'Host': host, **(headers or {})}
    if cookie:
        h['Cookie'] = cookie
    if body is not None:
        body = json.dumps(body).encode()
        h.setdefault('Content-Type', 'application/json')
        h.setdefault('Origin', 'https://' + host)
    c = http.client.HTTPConnection('127.0.0.1', PORT, timeout=10)
    c.request(method, path, body=body, headers=h)
    r = c.getresponse()
    out = (r.status, {k.lower(): v for k, v in r.getheaders()}, r.read())
    c.close()
    return out


def to_login(case, r):
    if not (r[0] == 302 and r[1].get('location') == '/login'):
        fail(case, 'answered %d %s, want 302 to /login' % (r[0], r[2][:80]))
    passed[0] += 1


def check(case, ok, why=''):
    if not ok:
        fail(case, why)
    passed[0] += 1


# The first admin, as setup adds it, and a member: each logs in from another device.
def add(store):
    for name, role in (('max', 'admin'), ('ana', 'member')):
        ds.user_action(store, 'add', name, role)
        ds.set_hash(store, store['users'][name], 'correct horse battery ' + name)
ds.change_store(add)
check('no_value_stored', ds.NO_LOGIN_HERE not in ds.read_store(), ds.read_store())


def login(name):
    r = req('POST', '/login', peer='192.0.2.7', host='192.0.2.1:%d' % PORT,
            body={'user': name, 'password': 'correct horse battery ' + name, 'trust': False, 'label': ''})
    check('login_' + name, r[0] == 200, r)
    return r[1]['set-cookie'].split(';')[0]


# D1: no value stored, a loopback peer, Host localhost:<port>, no cookie: the Board's page, and /me is "this device", an admin.
r = req('GET', '/')
check('this_device_gets_the_board', r[0] == 200 and r[2] == b'page\n', r)
for host in ('127.0.0.1:%d' % PORT, '127.8.9.10:%d' % PORT, '[::1]:%d' % PORT):
    check('this_device_by_loopback_address', req('GET', '/', host=host)[0] == 200, host)
r = req('GET', '/me')
check('this_device_is_an_admin', r[0] == 200 and json.loads(r[2]) == {'user': 'this device', 'role': 'admin', 'local': True}, r)
r = req('GET', '/users')
check('this_device_reads_the_users_and_the_setting', r[0] == 200 and json.loads(r[2])['noLoginHere'] is True
      and [u['user'] for u in json.loads(r[2])['users']] == ['ana', 'max'], r)
r = req('POST', '/me', body={'action': 'mfa-setup'})
check('this_device_has_no_account_to_change', r[0] == 409 and b'no password' in r[2], r)
# D2: the same request from a peer that is not loopback.
to_login('another_device_logs_in', req('GET', '/', peer='192.0.2.7'))
check('another_device_gets_no_me', req('GET', '/me', peer='192.0.2.7')[0] == 401)
# D3: a loopback peer whose Host is any other name (a name another site points at this machine), or another port.
for host in ('example.com:%d' % PORT, 'localhost.example.com:%d' % PORT, 'board.local:%d' % PORT, '192.0.2.1:%d' % PORT,
             'localhost:%d' % (PORT + 1), 'localhost', ''):
    to_login('rebinding_host_logs_in: ' + host, req('GET', '/', host=host))
# D4: a peer that is not loopback naming loopback in a header.
to_login('forwarded_header_ignored', req('GET', '/', peer='192.0.2.7', headers={
    'X-Forwarded-For': '127.0.0.1', 'Forwarded': 'for=127.0.0.1', 'X-Real-IP': '127.0.0.1'}))
# D6: a control write from this device with no cookie is done, and its log line names "this device"; the same write
# with a wrong Origin is refused as before, and nothing runs.
err = io.StringIO()
real, sys.stderr = sys.stderr, err
try:
    r = req('POST', '/control', body={'action': 'pause', 'args': [], 'repo': 'project'})
finally:
    sys.stderr = real
check('this_device_steers_the_loop', r[0] == 200 and r[2] == b'conveyor: paused' and len(RAN) == 1, r)
check('this_device_named_in_the_log', 'dashboard: control pause by this device from 127.0.0.1' in err.getvalue(), err.getvalue())
r = req('POST', '/control', headers={'Origin': 'https://example.com'}, body={'action': 'pause', 'args': [], 'repo': 'project'})
check('this_device_wrong_origin_refused', r[0] == 403 and len(RAN) == 1, r)
# D5: a member cannot change the setting; an admin's change is stored and read back, and takes effect on the next request.
ana, mx = login('ana'), login('max')
other = {'peer': '192.0.2.7', 'host': '192.0.2.1:%d' % PORT}
r = req('POST', '/users', cookie=ana, body={'action': 'no-login-here', 'on': False}, **other)
check('member_cannot_change_the_setting', r[0] == 403 and ds.NO_LOGIN_HERE not in ds.read_store(), r)
check('setting_takes_a_bool', req('POST', '/users', cookie=mx, body={'action': 'no-login-here', 'on': 'no'}, **other)[0] == 400)
r = req('POST', '/users', cookie=mx, body={'action': 'no-login-here', 'on': False}, **other)
check('admin_turns_it_off', r[0] == 200 and ds.read_store()[ds.NO_LOGIN_HERE] is False, r)
check('setting_read_back', json.loads(req('GET', '/users', cookie=mx, **other)[2])['noLoginHere'] is False)
to_login('off_this_device_logs_in', req('GET', '/'))
check('off_this_device_gets_no_me', req('GET', '/me')[0] == 401)
check('off_this_device_cannot_write', req('POST', '/control', body={'action': 'pause', 'args': [], 'repo': 'project'})[0] == 401 and len(RAN) == 1)
r = req('POST', '/users', cookie=mx, body={'action': 'no-login-here', 'on': True}, **other)
check('admin_turns_it_on', r[0] == 200 and ds.read_store()[ds.NO_LOGIN_HERE] is True and req('GET', '/')[0] == 200, r)
# This device, an admin, turns it off itself: its next request is sent to the login.
r = req('POST', '/users', body={'action': 'no-login-here', 'on': False})
check('this_device_turns_it_off', r[0] == 200 and ds.read_store()[ds.NO_LOGIN_HERE] is False, r)
to_login('this_device_sent_to_login_after', req('GET', '/'))
audit = [json.loads(l) for l in open(ds.AUDIT)]
check('setting_change_audited', [(a['by'], a['action'], a['on']) for a in audit if a['action'] == 'no-login-here']
      == [('max', 'no-login-here', False), ('max', 'no-login-here', True), ('this device', 'no-login-here', False)], audit)
# Build the test map (#178) is an admin's: a member's ask is refused (403) and nothing runs on the host; an admin's runs
# conveyor.sh testmap build there. Bug it catches: a member started a whole-suite run on the build machine.
n = len(RAN)
r = req('POST', '/control', cookie=ana, body={'action': 'testmap', 'args': ['build'], 'repo': 'project'}, **other)
check('member_cannot_build_the_test_map', r[0] == 403 and b'only an admin' in r[2] and len(RAN) == n, r)
r = req('POST', '/control', cookie=mx, body={'action': 'testmap', 'args': ['build'], 'repo': 'project'}, **other)
check('admin_builds_the_test_map', r[0] == 200 and len(RAN) == n + 1 and RAN[-1][-1].endswith("conveyor.sh testmap build'"), (r, RAN[-1:]))
r = req('POST', '/control', cookie=mx, body={'action': 'testmap', 'args': ['delete'], 'repo': 'project'}, **other)
check('test_map_takes_build_or_stop', r[0] == 400 and len(RAN) == n + 1, r)
# Record CPU time (#190) changes the pack's test command, which every card runs: a member's ask is refused (403) and
# nothing runs; an admin's runs conveyor.sh test-settings cpu-time <file>. Bug it catches: a member changed it.
n = len(RAN)
r = req('POST', '/control', cookie=ana, body={'action': 'test-settings', 'args': ['cpu-time', 'a.test.js'], 'repo': 'project'}, **other)
check('member_cannot_change_the_test_command', r[0] == 403 and b'only an admin' in r[2] and len(RAN) == n, r)
r = req('POST', '/control', cookie=mx, body={'action': 'test-settings', 'args': ['cpu-time', 'a.test.js'], 'repo': 'project'}, **other)
check('admin_records_cpu_time', r[0] == 200 and len(RAN) == n + 1 and RAN[-1][-1].endswith("conveyor.sh test-settings cpu-time a.test.js'"), (r, RAN[-1:]))
# Benchmarks (#326) start model sessions on the build machine for hours: a member's Start, preflight or Compare is
# refused (403) and nothing runs; an admin's runs bench swe there. The tab's history is read behind the login. Bugs
# it catches: a member started a run; the runs and their figures were read with no login.
n = len(RAN)
for args in (['run', '1'], ['arms', 'check', 'solo'], ['diff', 'a', 'b']):
    r = req('POST', '/control', cookie=ana, body={'action': 'bench', 'args': args, 'repo': 'project'}, **other)
    check('member_cannot_run_bench_%s' % args[0], r[0] == 403 and b'only an admin' in r[2] and len(RAN) == n, r)
r = req('POST', '/control', cookie=mx, body={'action': 'bench', 'args': ['stop'], 'repo': 'project'}, **other)
check('admin_runs_bench', r[0] == 200 and len(RAN) == n + 1 and RAN[-1][-1].endswith("conveyor.sh bench swe stop'"), (r, RAN[-1:]))
check('bench_needs_a_login', req('GET', '/bench?repo=project', **other)[0] == 401)
srv.shutdown()
print('PASS: dashboard-server-local (%d checks)' % passed[0])
EOF
