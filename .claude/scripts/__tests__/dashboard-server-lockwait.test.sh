#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# A control waits for the card records lock, and the loop's idle merge holds it while `gh pr merge` runs, up to
# gh_write()'s `timeout N gh` (conveyor/lib/issues.sh). Bug caught: Merge PR, Land as, a hold and a release got the 30 s
# an action gets by default, so with a merge that took 45 s the Board stopped the command and answered 504 before the
# change was saved. Each action sent through POST /control must get longer than that lock wait plus its own 30 s.
# The server runs in this process, over plain HTTP (no login, as dashboard-server-onemachine.test.sh); the command it
# would run is kept with its time limit, never run.
set -uo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
export XDG_DATA_HOME=${XDG_DATA_HOME:-$HOME/.local/share}
PY=$XDG_DATA_HOME/conveyor/board-venv/bin/python3
"$PY" -c 'import pyotp, segno, cryptography' || { echo "FAIL: the Board's virtualenv $PY lacks its packages: run conveyor.sh setup" >&2; exit 1; }
# The gh time limit of gh_write(), which the idle merge's lock is held over.
GHLIMIT=$(sed -n '/^gh_write() {/,/^}/p' "$HERE/../../../conveyor/lib/issues.sh" | grep -o 'timeout [0-9]* gh "\${args\[@\]}" {GHGATEFD}' | grep -o '[0-9]*' | head -1)
[[ $GHLIMIT =~ ^[0-9]+$ ]] || { echo "FAIL: gh_write()'s gh time limit was not found in conveyor/lib/issues.sh: '$GHLIMIT'" >&2; exit 1; }
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
mkdir -p "$T/out" "$T/auth" "$T/config/conveyor" "$T/proj" && echo page > "$T/out/index.html"
jq -n --arg m "$T/proj" '{records: [{repo: "proj", main: $m}]}' > "$T/config/conveyor/host.json" || exit 1
CONVEYOR_DASHBOARD_AUTH=$T/auth/dashboard-auth.json CONVEYOR_RULING_LOG=$T/rulings.jsonl XDG_CONFIG_HOME=$T/config \
  HOME=$T CONVEYOR_MAIN="$T/proj" "$PY" -I - "$HERE/.." "$T/out" "$GHLIMIT" <<'EOF'
import functools, http.client, json, subprocess, sys, threading
sys.path.insert(0, sys.argv[1])
import dashboard_server as ds

GHLIMIT = int(sys.argv[3])
srv = ds.Server(('127.0.0.1', 0), functools.partial(ds.Handler, directory=sys.argv[2]))
PORT = srv.server_address[1]
threading.Thread(target=srv.serve_forever, kwargs={'poll_interval': 0.02}, daemon=True).start()
RAN = []
ds.run_script = lambda args, timeout, env=None: RAN.append((args, timeout)) or subprocess.CompletedProcess(args, 0, 'conveyor: done\n', '')


def post(body):
    c = http.client.HTTPConnection('127.0.0.1', PORT, timeout=60)
    c.request('POST', '/control', body=json.dumps(body),
              headers={'Host': 'localhost:%d' % PORT, 'Origin': 'https://localhost:%d' % PORT, 'Content-Type': 'application/json'})
    r = c.getresponse()
    out = (r.status, r.read().decode())
    c.close()
    return out


passed = 0
for action, args in (('pr-merge', ['button']), ('land-as', ['pr']), ('hold', ['5']), ('release', ['5'])):
    body = {'action': action, 'args': args, 'repo': 'proj'}
    n = len(RAN)
    r = post(body)
    if r[0] != 200 or len(RAN) != n + 1:
        sys.exit('FAIL: %s_runs: POST /control %s answered %s, ran %s' % (action, json.dumps(body), r, RAN[n:]))
    if RAN[-1][1] < GHLIMIT + 30:
        sys.exit('FAIL: %s_outwaits_the_idle_merge: POST /control %s waits %ss; the idle merge can hold the lock %ss, then the action needs its own 30 s'
                 % (action, json.dumps(body), RAN[-1][1], GHLIMIT))
    passed += 1
srv.shutdown()
print('PASS: dashboard-server-lockwait (%d checks)' % passed)
EOF
