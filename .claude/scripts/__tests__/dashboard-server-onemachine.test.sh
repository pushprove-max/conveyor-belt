#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# POST /control and POST /machine on one machine (issue 112): the host file is the one setup writes, its records alone,
# with no build machine (no host, main or ssh). Bug caught: the page server refused every action with "conveyor/host.json
# is missing or not understood", as it read only a host file that named a build machine. On one machine each action
# runs here, by bash, on the Board's own copy of Conveyor, for the record it names; the machine is steered as this
# checkout's. Nothing goes over ssh.
# The server runs in this process, over plain HTTP, from this device (no login: dashboard-server-local.test.sh); the
# command it would run is kept, never run.
set -uo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
export XDG_DATA_HOME=${XDG_DATA_HOME:-$HOME/.local/share}
PY=$XDG_DATA_HOME/conveyor/board-venv/bin/python3
"$PY" -c 'import pyotp, segno, cryptography' || { echo "FAIL: the Board's virtualenv $PY lacks its packages: run conveyor.sh setup" >&2; exit 1; }
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
mkdir -p "$T/out" "$T/auth" "$T/config/conveyor" "$T/my proj" && echo page > "$T/out/index.html"
# The host file as setup's hostput writes it: a record {repo, main} for the project's checkout, and nothing else. The
# checkout's path has a space, as setup records it unchanged. Bug caught: the server took only paths of letters,
# digits and ._/-, and refused setup's host file for such a checkout.
jq -n --arg m "$T/my proj" '{records: [{repo: "proj", main: $m}]}' > "$T/config/conveyor/host.json"
CONVEYOR_DASHBOARD_AUTH=$T/auth/dashboard-auth.json CONVEYOR_RULING_LOG=$T/rulings.jsonl XDG_CONFIG_HOME=$T/config \
  HOME=$T CONVEYOR_MAIN="$T/my proj" "$PY" -I - "$HERE/.." "$T/out" "$T/my proj" <<'EOF'
import functools, http.client, json, os, re, shlex, subprocess, sys, threading
sys.path.insert(0, sys.argv[1])
import dashboard_server as ds

PROJ = sys.argv[3]
ENGINE = os.path.dirname(os.path.dirname(os.path.abspath(sys.argv[1])))  # the checkout above .claude/scripts
srv = ds.Server(('127.0.0.1', 0), functools.partial(ds.Handler, directory=sys.argv[2]))
PORT = srv.server_address[1]
threading.Thread(target=srv.serve_forever, kwargs={'poll_interval': 0.02}, daemon=True).start()
RAN = []
ds.run_script = lambda args, timeout, env=None: RAN.append(args) or subprocess.CompletedProcess(args, 0, 'conveyor: done\n', '')


def fail(case, why):
    sys.exit('FAIL: %s: %s' % (case, why))


def post(path, body):
    c = http.client.HTTPConnection('127.0.0.1', PORT, timeout=60)
    c.request('POST', path, body=json.dumps(body),
              headers={'Host': 'localhost:%d' % PORT, 'Origin': 'https://localhost:%d' % PORT, 'Content-Type': 'application/json'})
    r = c.getresponse()
    out = (r.status, r.read().decode())
    c.close()
    return out


host, target, engine, records = ds.conveyor_host()
ME = re.sub(r'[^A-Za-z0-9._-]', '-', os.uname().nodename.split('.')[0]) or 'localhost'  # this machine's short name
if (host, target, engine, records) != (ME, None, ENGINE, {'proj': PROJ}):
    fail('setup_host_file_read_as_one_machine', (host, target, engine, records))
conv = 'CONVEYOR_MAIN=%s bash %s' % (shlex.quote(PROJ), shlex.quote(ENGINE + '/conveyor/conveyor.sh'))
r = post('/control', {'action': 'prices', 'args': ['clear', 'claude-new-9'], 'repo': 'proj'})
if r[0] != 200 or len(RAN) != 1 or RAN[0][:2] != ['bash', '-c'] or conv not in RAN[0][2]:
    fail('control_runs_here_on_the_record', '%s, ran %s' % (r, RAN))
r = post('/machine', {'action': 'pause'})
if r[0] != 200 or len(RAN) != 2 or RAN[1] != ['bash', '-c', '%s machine pause' % conv]:
    fail('machine_runs_here_as_this_checkout', '%s, ran %s' % (r, RAN[1:]))
srv.shutdown()
print('PASS: dashboard-server-onemachine (3 checks)')
EOF
