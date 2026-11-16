#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# The Rules tab's Model prices save through POST /control (action prices), which runs `conveyor.sh prices` on the
# record's main: here the host is this machine and its main a fixture checkout with a pack of its own, so the case
# reads the override back from the pack the engine wrote. A bad value (negative, a word) is refused with the engine's
# message and leaves the pack as it was; a shape the engine does not take is refused by the server and runs nothing.
# Bug each case catches: an override, added model, display name or alias that never reaches the pack, or a bad price
# saved, or refused with no reason.
# The server runs in this process, over plain HTTP, from this device (no login: dashboard-server-local.test.sh).
set -uo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
export XDG_DATA_HOME=${XDG_DATA_HOME:-$HOME/.local/share}
PY=$XDG_DATA_HOME/conveyor/board-venv/bin/python3
"$PY" -c 'import pyotp, segno, cryptography' || { echo "FAIL: the Board's virtualenv $PY lacks its packages: run conveyor.sh setup" >&2; exit 1; }
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
mkdir -p "$T/out" "$T/auth" "$T/main/.conveyor" "$T/main/conveyor/state" && echo page > "$T/out/index.html"
# The record's main: its pack (the engine's test pack) and a conveyor.sh that runs this checkout's engine on it.
git -C "$T/main" init -q -b main || exit 1
cp "$HERE/../../../conveyor/lib/test-pack.json" "$T/main/.conveyor/project.json"
printf '#!/usr/bin/env bash\nexec bash %q "$@"\n' "$(cd "$HERE/../../../conveyor" && pwd -P)/conveyor.sh" > "$T/main/conveyor/conveyor.sh"
CONVEYOR_DASHBOARD_AUTH=$T/auth/dashboard-auth.json CONVEYOR_RULING_LOG=$T/rulings.jsonl XDG_CONFIG_HOME=$T/config \
  HOME=$T CONVEYOR_MAIN=$T "$PY" -I - "$HERE/.." "$T/out" "$T/main" <<'EOF'
import functools, http.client, json, sys, threading
sys.path.insert(0, sys.argv[1])
import dashboard_server as ds

MAIN = sys.argv[3]
PACK = MAIN + '/.conveyor/project.json'
srv = ds.Server(('127.0.0.1', 0), functools.partial(ds.Handler, directory=sys.argv[2]))
PORT = srv.server_address[1]
threading.Thread(target=srv.serve_forever, kwargs={'poll_interval': 0.02}, daemon=True).start()
# The host is this machine: the ssh command's script runs here, by bash, as the host would run it.
ds.conveyor_host = lambda: ('buildhost', 'user@buildhost', MAIN, {'project': MAIN})
RAN = []
real = ds.run_script
ds.run_script = lambda args, timeout, env=None: RAN.append(args) or real(['bash', '-c', args[-1]], timeout, env)


def fail(case, why):
    sys.exit('FAIL: %s: %s' % (case, why))


def control(*args):
    c = http.client.HTTPConnection('127.0.0.1', PORT, timeout=60)
    c.request('POST', '/control', body=json.dumps({'action': 'prices', 'args': list(args), 'repo': 'project'}),
              headers={'Host': 'localhost:%d' % PORT, 'Origin': 'https://localhost:%d' % PORT, 'Content-Type': 'application/json'})
    r = c.getresponse()
    out = (r.status, r.read().decode())
    c.close()
    return out


def prices():
    with open(PACK) as f:
        return json.load(f).get('prices')


r = control('set', 'claude-new-9', '3', '15', '0.3')
if r[0] != 200 or prices() != {'claude-new-9': {'input': 3, 'output': 15, 'cacheRead': 0.3}}:
    fail('override_saved_in_the_pack', '%s, the pack holds %s' % (r, prices()))
with open(PACK) as f:
    before = f.read()
for bad, said in ((('-1', '15', '0.3'), 'the input price is dollars per million tokens'), (('3', 'fifteen', '0.3'), 'the output price is dollars per million tokens')):
    r = control('set', 'claude-new-9', *bad)
    if r[0] != 409 or said not in r[1] or 'nothing changed' not in r[1]:
        fail('bad_price_refused_with_why', '%s answered %s' % (bad, r))
with open(PACK) as f:
    if f.read() != before:
        fail('bad_price_refused_with_why', 'a refused price changed the pack: %s' % prices())
n = len(RAN)
for bad in (('set', 'claude-new-9', '3', '15'), ('set', '-x', '1', '2', '3'), ('clear', 'claude-new-9', 'x'),
            ('add', 'm', 'gemini', 'M', '1', '2', '3'), ('add', 'm', 'other', 'a\nb', '1', '2', '3'), ('name', 'm', 'x' * 61),
            ('alias', 'm', 'rename', 'x'), ('alias', 'm', 'add', '-x'), ('remove', 'm', 'x')):
    r = control(*bad)
    if r[0] != 400 or len(RAN) != n:
        fail('shape_refused_by_the_server', '%s answered %s, ran %s' % (bad, r, RAN[n:]))
r = control('clear', 'claude-new-9')
if r[0] != 200 or prices() is not None:
    fail('override_cleared', '%s, the pack holds %s' % (r, prices()))
# The Model prices panel's other changes reach the pack: Add model, a display name, an alias (This is…), Remove.
for args in (('add', 'my-model', 'other', 'My model', '1', '2', '0.1', '1.5'), ('name', 'claude-opus-5-5', 'Opus (proxy)'),
             ('alias', 'claude-opus-5-5', 'add', 'proxy/opus'), ('remove', 'my-model')):
    r = control(*args)
    if r[0] != 200:
        fail('model_changes_saved_in_the_pack', '%s answered %s' % (args, r))
if prices() != {'claude-opus-5-5': {'name': 'Opus (proxy)', 'aliases': ['proxy/opus']}}:
    fail('model_changes_saved_in_the_pack', 'the pack holds %s' % prices())
srv.shutdown()
print('PASS: dashboard-server-prices (5 checks)')
EOF
