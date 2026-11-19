#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# The Cost panel's judge replay study sends POST /control action replay (#765): the server takes a model, an effort
# if any, --last <n> if any and --estimate if asked, and runs `conveyor.sh pick replay judge ...` on the host. An
# estimate answers what the engine printed. A run checks its arguments with an estimate first and then goes on
# after the answer. Bug each case catches: a shape that reaches the host's shell unchecked, or a run that starts when
# its estimate refused it, or that holds the answer until the judge calls end.
set -uo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
export XDG_DATA_HOME=${XDG_DATA_HOME:-$HOME/.local/share}
PY=$XDG_DATA_HOME/conveyor/board-venv/bin/python3
"$PY" -c 'import pyotp, segno, cryptography' || { echo "FAIL: the Board's virtualenv $PY lacks its packages: run conveyor.sh setup" >&2; exit 1; }
D=$(mktemp -d) || exit 1; trap 'rm -rf "$D"' EXIT
# A stub main checkout: its conveyor.sh logs its arguments, refuses an estimate while $D/refuse exists, and a run
# sleeps 3 s before it logs that it ended (a run the answer waited for would come back after that line).
mkdir -p "$D/m/conveyor"
cat > "$D/m/conveyor/conveyor.sh" <<'EOF'
echo "$*" >> "$STUBD/calls"
case " $* " in *' --estimate '*) [ ! -e "$STUBD/refuse" ] || { echo "conveyor: m9 is not one of the models" >&2; exit 2; }; echo '{"estimate":true}' ;;
  *) sleep 3; echo ended >> "$STUBD/calls" ;; esac # sleep: a slow run, so an answer that waited for it comes after "ended"
EOF
# One machine's host file (dashboard-server-onemachine.test.sh) whose project is the stub checkout, for the replays
# sent through the handler.
mkdir -p "$D/config/conveyor" "$D/auth" "$D/out" && echo page > "$D/out/index.html" \
  && jq -n --arg m "$D/m" '{records: [{repo: "proj", main: $m}]}' > "$D/config/conveyor/host.json" || exit 1
STUBD=$D CONVEYOR_DASHBOARD_AUTH=$D/auth/dashboard-auth.json CONVEYOR_RULING_LOG=$D/rulings.jsonl CONVEYOR_MAIN=$D/m \
  XDG_CONFIG_HOME=$D/config HOME=$D "$PY" -I - "$HERE/.." "$D" <<'EOF'
import functools, http.client, json, os, subprocess, sys, threading, time
sys.path.insert(0, sys.argv[1])
import dashboard_server as ds
d = sys.argv[2]

passed = 0


def check(case, ok, why=''):
    global passed
    if not ok:
        print('FAIL [%s]: %s' % (case, why), file=sys.stderr)
        sys.exit(1)
    passed += 1


ok = lambda args: ds.control_ok({'action': 'replay', 'args': args, 'repo': 'project'})
for args in (['claude-haiku-5-5'], ['claude-haiku-5-5', 'low'], ['claude-haiku-5-5', '--estimate'], ['claude-haiku-5-5', 'low', '--last', '20'],
             ['opencode:prov/m-2', 'max', '--last', '5', '--estimate']):
    check('takes_%s' % '_'.join(args), ok(args), args)
for args in ([], ['--estimate'], ['claude-haiku-5-5', 'huge'], ['claude-haiku-5-5', '--last'], ['claude-haiku-5-5', '--last', '0'], ['claude-haiku-5-5', '--last', '12345'],
             ['claude-haiku-5-5', 'low', 'x'], ['m;id'], ['-m'], ['claude-haiku-5-5', '--estimate', '--last', '5']):
    check('refuses_%s' % '_'.join(args), not ok(args), args)


def run(args):
    os.makedirs(d, exist_ok=True)
    try:
        os.unlink(os.path.join(d, 'calls'))
    except OSError:
        pass
    t = time.time()
    r = subprocess.run(['bash', '-c', ds.control_script('replay', args, d + '/m', '2026-11-19', d + '/m', 'u')], capture_output=True, text=True, timeout=30)
    return r, time.time() - t


def calls():
    try:
        with open(os.path.join(d, 'calls')) as f:
            return f.read().splitlines()
    except OSError:
        return []


r, _ = run(['claude-haiku-5-5', 'low', '--estimate'])
check('estimate_answers_its_json', r.returncode == 0 and r.stdout.strip() == '{"estimate":true}' and calls() == ['pick replay judge claude-haiku-5-5 low --estimate'], (r, calls()))
open(os.path.join(d, 'refuse'), 'w').close()
r, _ = run(['m9'])
time.sleep(0.5)
check('a_refused_estimate_starts_no_run', r.returncode != 0 and 'm9 is not one of the models' in r.stderr and calls() == ['pick replay judge m9 --estimate'], (r, calls()))
os.unlink(os.path.join(d, 'refuse'))
r, sec = run(['claude-haiku-5-5', '--last', '5'])
check('a_run_answers_before_it_ends', r.returncode == 0 and 'replay started' in r.stdout and sec < 3 and 'ended' not in calls(), (r, sec, calls()))
# The run goes on in the background after the answer: only waiting for its end shows that it was started at all.
for _ in range(100):
    if 'ended' in calls():
        break
    time.sleep(0.1)
check('a_run_runs_after_its_estimate', calls() == ['pick replay judge claude-haiku-5-5 --last 5 --estimate', 'pick replay judge claude-haiku-5-5 --last 5', 'ended'], calls())
# Bug: any logged-in member could start a replay, which calls the judge with the host's model account once a review.
# Sent through the handler as a member, a run is refused before the host is asked; an estimate calls no model and is
# a member's to ask.
read_host = ds.conveyor_host
ds.conveyor_host = lambda: (lambda h: h[:2] + (d + '/m',) + h[3:])(read_host())
srv = ds.Server(('127.0.0.1', 0), functools.partial(ds.Handler, directory=d + '/out'))
threading.Thread(target=srv.serve_forever, kwargs={'poll_interval': 0.02}, daemon=True).start()


def post(args):
    c = http.client.HTTPConnection('127.0.0.1', srv.server_address[1], timeout=30)
    c.request('POST', '/control', body=json.dumps({'action': 'replay', 'args': args, 'repo': 'proj'}),
              headers={'Host': 'localhost:%d' % srv.server_address[1], 'Origin': 'https://localhost:%d' % srv.server_address[1], 'Content-Type': 'application/json'})
    r = c.getresponse()
    return r.status, r.read().decode()


os.unlink(os.path.join(d, 'calls'))
ds.role_of = lambda store, name: 'member'
said = post(['claude-haiku-5-5', '--last', '5'])
check('a_members_run_is_refused', said[0] == 403 and calls() == [], (said, calls()))
said = post(['claude-haiku-5-5', '--estimate'])
check('a_members_estimate_is_answered', said == (200, '{"estimate":true}') and calls() == ['pick replay judge claude-haiku-5-5 --estimate'], (said, calls()))
print('dashboard-server-replay: %d passed' % passed)
EOF
