#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# The Tests page's Benchmarks part sends POST /control action bench (#236): the server takes Start (n of 1 to 500, then
# --solo or --engine <main, a release or a full commit>), Stop, List versions and Compare (two versions), and nothing
# else; Start's script leaves the run going on the host and answers at once, or answers the engine's refusal when the
# run ends at its start, or its summary when the run ends well at its start. Here the host's conveyor.sh is a stub that
# refuses a run while $T/guard is there, answers a summary at once while $T/saved is there, and else waits while
# $T/hold is there. Bug each case catches: a shape that reaches the host's shell unchecked, or a Start
# that holds the Board's answer for the hours a run takes, or that says started when the engine refused it.
set -uo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
export XDG_DATA_HOME=${XDG_DATA_HOME:-$HOME/.local/share}
PY=$XDG_DATA_HOME/conveyor/board-venv/bin/python3
"$PY" -c 'import pyotp, segno, cryptography' || { echo "FAIL: the Board's virtualenv $PY lacks its packages: run conveyor.sh setup" >&2; exit 1; }
T=$(mktemp -d)
trap 'rm -f "$T/hold"; rm -rf "$T"' EXIT
mkdir -p "$T/main/conveyor"
cat > "$T/main/conveyor/conveyor.sh" <<'EOF'
#!/usr/bin/env bash
echo "$*" >> "${0%/*}/../asked"
[ ! -e "${0%/*}/../../guard" ] || { echo "conveyor: the usage guard is reached: no SWE-bench run starts while it stands" >&2; exit 1; }
[ ! -e "${0%/*}/../../saved" ] || { echo "SWE-bench run: 1 of 1 tasks resolved (results saved before)"; exit 0; }
while [ -e "${0%/*}/../../hold" ]; do sleep 0.1; done
EOF
# One machine's host file (dashboard-server-onemachine.test.sh), for Compare sent over POST /control.
mkdir -p "$T/config/conveyor" "$T/auth" "$T/out" && echo page > "$T/out/index.html" \
  && jq -n --arg m "$T/main" '{records: [{repo: "proj", main: $m}]}' > "$T/config/conveyor/host.json" || exit 1
CONVEYOR_DASHBOARD_AUTH=$T/auth/dashboard-auth.json CONVEYOR_RULING_LOG=$T/rulings.jsonl CONVEYOR_MAIN=$T/main \
  XDG_CONFIG_HOME=$T/config HOME=$T "$PY" -I - "$HERE/.." "$T" <<'EOF'
import functools, http.client, json, os, subprocess, sys, threading, time
sys.path.insert(0, sys.argv[1])
import dashboard_server as ds

T = sys.argv[2]
MAIN = T + '/main'
passed = [0]


def check(case, ok, why=''):
    if not ok:
        print('FAIL [%s]: %s' % (case, why), file=sys.stderr)
        sys.exit(1)
    passed[0] += 1


ok = lambda args: ds.control_ok({'action': 'bench', 'args': args, 'repo': 'project'})
for args in (['run', '1'], ['run', '500', '--solo'], ['run', '5', '--engine', 'v1.2.0'], ['run', '20', '--engine', 'main'],
             ['run', '50', '--engine', 'a' * 40], ['stop'], ['versions'], ['diff', 'v1.0.0', 'main']):
    check('takes_%s' % '_'.join(args)[:30], ok(args), args)
for args in (['run', '0'], ['run', '501'], ['run', '05'], ['run', '5', '--solo', '--engine', 'main'], ['run', '5', '--engine', 'v1.2'],
             ['run', '5', '--engine', 'main;rm -rf ~'], ['run', '5', '--engine', 'a' * 12], ['diff', 'main'], ['diff', 'main', '$(id)'], ['stop', 'now'], []):
    check('refuses_%s' % '_'.join(args)[:30], not ok(args), args)


def host(args):
    """The script for <args>, run here as the host runs it: (exit code, answer, seconds)."""
    t0 = time.time()
    r = subprocess.run(['bash', '-c', ds.control_script('bench', args, MAIN, '2026-11-17', MAIN, 'max')], capture_output=True, text=True, timeout=60)
    return r.returncode, r.stdout + r.stderr, time.time() - t0


# On one machine the handler runs the Board's own engine; here it runs the stub conveyor.sh in its place.
read_host = ds.conveyor_host
ds.conveyor_host = lambda: (lambda h: h[:2] + (MAIN,) + h[3:])(read_host())
srv = ds.Server(('127.0.0.1', 0), functools.partial(ds.Handler, directory=T + '/out'))
threading.Thread(target=srv.serve_forever, kwargs={'poll_interval': 0.02}, daemon=True).start()


def post(args):
    """The Board's POST /control of action bench <args>: (HTTP status, answer)."""
    c = http.client.HTTPConnection('127.0.0.1', srv.server_address[1], timeout=60)
    c.request('POST', '/control', body=json.dumps({'action': 'bench', 'args': args, 'repo': 'proj'}),
              headers={'Host': 'localhost:%d' % srv.server_address[1], 'Origin': 'https://localhost:%d' % srv.server_address[1], 'Content-Type': 'application/json'})
    r = c.getresponse()
    return r.status, r.read().decode()


open(T + '/hold', 'w').close()
rc, out, sec = host(['run', '5', '--engine', 'v1.2.0'])
check('start_answers_while_the_run_goes', rc == 0 and 'the SWE-bench run started' in out and sec < 30, (rc, out, sec))
check('start_runs_bench_swe', open(MAIN + '/asked').read().split('\n')[0] == 'bench swe 5 --engine v1.2.0', open(MAIN + '/asked').read())
# Bug: Start's script copied the engine's refusal to stdout, but the handler answers a failed script with its stderr
# alone, so the Board showed "refused it (exit 1)" and not why. Sent through the handler, the answer is the reason.
open(T + '/guard', 'w').close()
said = post(['run', '1', '--solo'])
check('start_answers_the_refusal', said == (409, 'conveyor: the usage guard is reached: no SWE-bench run starts while it stands'), said)
os.remove(T + '/guard')
# Bug: a run that ended well at once (each task's result saved before) also sent its summary to stderr, which the
# handler drops when a script succeeds, so the Board said "done" and not the result.
open(T + '/saved', 'w').close()
said = post(['run', '1', '--solo'])
check('start_answers_a_run_that_ended_at_once', said == (200, 'SWE-bench run: 1 of 1 tasks resolved (results saved before)'), said)
os.remove(T + '/saved')
os.remove(T + '/hold')
rc, out, sec = host(['diff', 'v1.0.0', 'main'])
check('compare_runs_bench_swe_diff', rc == 0 and open(MAIN + '/asked').read().split('\n')[-2] == 'bench swe diff v1.0.0 main', open(MAIN + '/asked').read())
# Bug: Compare's answer was the last line of `bench swe diff` alone, so the Board showed no totals, no task list and
# no facts of the flipped tasks. The host's answer here is a comparison of several lines; the reply is all of it.
DIFF = ('v1.0.0 against main on the 2 tasks both ran:\n  v1.0.0: 2 resolved\n  main: 1 resolved\n'
        '  The same in both: 1 task(s): p__b-2. Flipped: 1.\n\np__a-1: resolved by v1.0.0 only; the runs went apart at: review\n')
ds.run_script = lambda args, timeout, env=None: subprocess.CompletedProcess(args, 0, DIFF, '')
said = post(['diff', 'v1.0.0', 'main'])
srv.shutdown()
check('compare_answers_the_whole_comparison', said == (200, DIFF.strip()), said)
print('PASS: dashboard-server-bench (%d checks)' % passed[0])
EOF
