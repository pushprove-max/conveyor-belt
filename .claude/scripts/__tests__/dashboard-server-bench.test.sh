#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# The Benchmarks tab sends POST /control action bench (#236, #326): the server takes Start (n of 1 to 500, then
# --solo, or arms with --arm and --engine <main, a release or a full commit>, then --settings), Stop, List versions, an
# arm's preflight, an arm saved and Compare (two versions or results keys, as JSON or text), and nothing else; it gives
# the tab's history and a run's tasks at GET /bench. Start's and a check's script leave the work going on the host and
# answer its receipt (also when the work ended soon after it), or answer the engine's refusal when it ends at its start,
# or its result when it ends well with no receipt. Here the host's conveyor.sh is a stub that refuses the saved
# revision arm-ffffffffffff, refuses a run while $T/guard is there, answers a reused run's result with no receipt while
# $T/done is there, prints its receipt and then fails while $T/quick is there, and else prints its receipt (of the
# project's record: its id file) and waits while $T/hold is there. Bug each case catches: a shape that reaches the host's shell
# unchecked, or a Start that holds the Board's answer for the hours a run takes, or that says started when the engine
# refused it.
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
[ "$3 $4" != 'arms save' ] || { echo arm-0123456789ab; exit 0; }
[[ " $* " != *' arm-ffffffffffff '* ]] || { echo 'conveyor: no arm arm-ffffffffffff: `conveyor.sh bench swe arms` lists them' >&2; exit 1; }
[ ! -e "${0%/*}/../../guard" ] || { echo "conveyor: the usage guard is reached: no SWE-bench run starts while it stands" >&2; exit 1; }
# A run admitted, then refused at its preflight: the receipt, then the refusal, and its end. The pause keeps the
# server's first poll before the receipt, so the old answer (the whole log of a run ended by its next poll) shows.
[ ! -e "${0%/*}/../../quick" ] || { sleep 0.5; echo "conveyor: run $(cat "$CONVEYOR_MAIN/id") started"; echo 'conveyor: the arm solo cannot run: its preflight failed: no login.' >&2; exit 1; } # sleep: the receipt must come after the server's first poll, which no file can signal
# A run that reuses each task's saved result: the engine prints no receipt, only its lines and its result.
[ ! -e "${0%/*}/../../done" ] || { printf '1/1 t-1: resolved (reused)\nResolved 1 of 1 with Claude alone; not run: 0.\n'; exit 0; }
# Admitted: the receipt, of the project's own record (its id file), then the run or check goes on while $T/hold is there.
if [ "$3" = arms ]; then shift 4; [ "$1" != --settings ] || shift 2; for a; do echo "$a: checking k-$(cat "$CONVEYOR_MAIN/id")"; done
else echo "conveyor: run $(cat "$CONVEYOR_MAIN/id") started"; fi
while [ -e "${0%/*}/../../hold" ]; do sleep 0.1; done
EOF
# One machine's host file (dashboard-server-onemachine.test.sh), for Compare sent over POST /control; a second project,
# other, whose record is its own checkout.
mkdir -p "$T/config/conveyor" "$T/auth" "$T/out" "$T/other" && echo page > "$T/out/index.html" \
  && echo r20261117T090000-1 > "$T/main/id" && echo r20261117T090000-2 > "$T/other/id" \
  && jq -n --arg m "$T/main" --arg o "$T/other" '{records: [{repo: "proj", main: $m}, {repo: "other", main: $o}]}' > "$T/config/conveyor/host.json" || exit 1
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
# Bug: Compare sends each column's results key, but only versions were taken, so comparing two arms on one engine
# commit (or an arm that runs no engine) got HTTP 400.
for args in (['diff', 'codex-sol', 'conveyor-codex-claude-' + 'a' * 40], ['diff', 'solo-claude-opus-5-5', 'a' * 40]):
    check('compare_takes_results_key_%s' % args[1], ok(args), args)
for args in (['diff', 'main', '-x'], ['diff', '--json', 'main'], ['diff', 'main', 'a b'], ['diff', 'main', 'x' * 121]):
    check('compare_refuses_%s' % '_'.join(args)[:30], not ok(args), args)
for args in (['run', '0'], ['run', '501'], ['run', '05'], ['run', '5', '--solo', '--engine', 'main'], ['run', '5', '--engine', 'v1.2'],
             ['run', '5', '--engine', 'main;rm -rf ~'], ['run', '5', '--engine', 'a' * 12], ['diff', 'main'], ['diff', 'main', '$(id)'], ['stop', 'now'], []):
    check('refuses_%s' % '_'.join(args)[:30], not ok(args), args)
# Bug (#326): the Benchmarks tab's Start sends the arms picked (each one --arm), runs the preflight of an arm not yet
# checked, and Compare reads the comparison as JSON; none of these shapes was taken, and none other may reach the host.
for args in (['run', '20', '--arm', 'conveyor', '--arm', 'codex-sol', '--engine', 'v1.2.0'], ['run', '1', '--arm', 'solo'],
             ['arms', 'check', 'superpowers', 'conveyor-codex-claude'], ['diff', 'solo-m', 'a' * 40, '--json']):
    check('tab_takes_%s' % '_'.join(args)[:40], ok(args), args)
for args in (['run', '5', '--arm', '-x'], ['run', '5', '--arm'], ['run', '5', '--arm', 'a b'], ['run', '5', '--arm', 'Up'], ['run', '5', '--arm', 'solo', '--solo'],
             ['run', '5', '--engine', 'main', '--arm', 'solo'], ['run', '5'] + ['--arm', 'a'] * 21, ['arms', 'check'], ['arms', 'check', '../x'],
             ['arms', 'check'] + ['a'] * 21, ['arms', 'list'], ['diff', 'a', 'b', '--text'], ['diff', 'a', 'b', '--json', 'x']):
    check('tab_refuses_%s' % '_'.join(args)[:40], not ok(args), args)
# Bug (#640): Start and Check send the shared settings (--settings), a saved arm's revision ID as an arm, and the arm
# editor saves an arm (arms save <name> <spec>); none was taken. Each JSON field is checked as the engine checks its
# shape, so a field it would refuse, or one of no size limit, never reaches the host's shell.
S = json.dumps({'revision': 'b' * 40, 'seed': 's1', 'cpus': 2, 'memory': '4g', 'taskTimeout': 1800})
CONV = json.dumps({'kind': 'conveyor', 'seats': {'model': {'cli': 'codex', 'model': 'gpt-5.5', 'effort': 'high'}, 'judge': {'cli': 'claude', 'model': 'claude-opus-5-5'}},
                   'rules': 'project', 'policy': {'judgeOn': True, 'judgeAlways': ['security'], 'P3': False}})
AGENT = json.dumps({'kind': 'agent', 'recipe': 'codex-sol', 'cli': 'codex', 'model': 'gpt-5.5', 'effort': 'low'})
for i, args in enumerate((['run', '5', '--arm', 'arm-0123456789ab', '--settings', S], ['run', '5', '--solo', '--settings', '{}'],
                          ['run', '5', '--arm', 'conveyor', '--engine', 'main', '--settings', S], ['arms', 'check', '--settings', S, 'arm-0123456789ab', 'conveyor'],
                          ['arms', 'save', 'Codex builds', CONV], ['arms', 'save', 'Sol', AGENT], ['arms', 'save', 'Bare', '{"kind": "conveyor"}'])):
    check('new_form_taken_%d' % i, ok(args), args)
for i, s in enumerate(('{"gpus": 1}', '{"revision": "b"}', '{"seed": ""}', '{"seed": "a\\nb"}', '{"seed": "%s"}' % ('x' * 81), '{"cpus": 0}',
                       '{"cpus": true}', '{"cpus": 1e9}', '{"memory": "256m"}', '{"memory": "4t"}', '{"memory": 4}', '{"taskTimeout": 59}',
                       '{"taskTimeout": 60.5}', '{"taskTimeout": 1e400}', '{"taskTimeout": "60"}', '{"cpus": NaN}', '[]', '{' + ' ' * 4096 + '}', 'x')):
    check('settings_refused_%d' % i, not ok(['run', '5', '--settings', s]) and not ok(['arms', 'check', '--settings', s, 'conveyor']), s)
for i, args in enumerate((['run', '5', '--settings', S, '--arm', 'conveyor'], ['run', '5', '--settings'], ['run', '5', '--settings', S, '--settings', S],
                          ['arms', 'check', '--settings', S], ['arms', 'check', 'conveyor', '--settings', S], ['arms', 'check', '--settings'],
                          ['run', '5'] + ['--arm', 'a'] * 21 + ['--settings', S], ['arms', 'check', '--settings', S] + ['a'] * 21)):
    check('settings_place_refused_%d' % i, not ok(args), args)
bad = lambda **k: json.dumps({**json.loads(CONV), **k})
seat = lambda **k: bad(seats={'model': {'cli': 'codex', 'model': 'gpt-5.5', **k}})
for i, (name, spec) in enumerate((('', CONV), (' x', CONV), ('x' * 81, CONV), ('a\nb', CONV), ('x', bad(kind='other')), ('x', bad(command='rm -rf ~')),
                                  ('x', bad(seats={'tester': {'cli': 'codex', 'model': 'm'}})), ('x', seat(cli='aider')), ('x', seat(effort='huge')),
                                  ('x', seat(effort=[])), ('x', seat(model='-x')), ('x', seat(extra=1)), ('x', bad(seats=[])), ('x', bad(rules='none')),
                                  ('x', bad(policy={'P0': 'yes'})), ('x', bad(policy={'judgeAlways': ['k'] * 21})), ('x', bad(policy={'judgeAlways': ['a b']})),
                                  ('x', bad(policy={'merge': True})), ('x', json.dumps({**json.loads(AGENT), 'recipe': 'arm-0123456789ab'})),
                                  ('x', json.dumps({**json.loads(AGENT), 'cli': 'opencode'})), ('x', json.dumps({**json.loads(AGENT), 'cmd': 'x'})),
                                  ('x', json.dumps({k: v for k, v in json.loads(AGENT).items() if k != 'model'})), ('x', CONV + ' ' * 4096), ('x', '[]'))):
    check('save_refused_%d' % i, not ok(['arms', 'save', name, spec]), (name, spec))
check('save_refuses_another_argument', not ok(['arms', 'save', 'x', CONV, 'y']) and not ok(['arms', 'save', 'x']))


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


def post(args, repo='proj'):
    """The Board's POST /control of action bench <args>: (HTTP status, answer)."""
    c = http.client.HTTPConnection('127.0.0.1', srv.server_address[1], timeout=60)
    c.request('POST', '/control', body=json.dumps({'action': 'bench', 'args': args, 'repo': repo}),
              headers={'Host': 'localhost:%d' % srv.server_address[1], 'Origin': 'https://localhost:%d' % srv.server_address[1], 'Content-Type': 'application/json'})
    r = c.getresponse()
    return r.status, r.read().decode()


asked = lambda: open(MAIN + '/asked').read().split('\n')[:-1]
# Bug (#640): Start answered "started" when its process still ran after a three-second guess, whatever the engine had
# recorded; the answer is now the receipt the engine prints once it recorded the run (its id), while the run goes on.
# The hold keeps each run going, so an answer that waited for its end would not come.
open(T + '/hold', 'w').close()
rc, out, sec = host(['run', '5', '--engine', 'v1.2.0'])
check('start_answers_while_the_run_goes', (rc, out) == (0, 'conveyor: run r20261117T090000-1 started\n'), (rc, out, sec))
check('start_runs_bench_swe', open(MAIN + '/asked').read().split('\n')[0] == 'bench swe 5 --engine v1.2.0', open(MAIN + '/asked').read())
# Bug: Start's script copied the engine's refusal to stdout, but the handler answers a failed script with its stderr
# alone, so the Board showed "refused it (exit 1)" and not why. Sent through the handler, the answer is the reason.
open(T + '/guard', 'w').close()
said = post(['run', '1', '--solo'])
check('start_answers_the_refusal', said == (409, 'conveyor: the usage guard is reached: no SWE-bench run starts while it stands'), said)
os.remove(T + '/guard')
# Bug: a run that ended well with no receipt (each task's result saved before) also sent its result to stderr, which
# the handler drops when a script succeeds, so the Board said "done" and not the result.
open(T + '/done', 'w').close()
said = post(['run', '1', '--solo'])
check('start_answers_a_run_that_ended_at_once', said == (200, '1/1 t-1: resolved (reused)\nResolved 1 of 1 with Claude alone; not run: 0.'), said)
os.remove(T + '/done')
# Bug (#640): a run that printed its receipt and then ended soon was answered with the receipt or with its whole log,
# as the server's poll came before or after its end. Its answer is the receipt: its end is in its record.
open(T + '/quick', 'w').close()
said = post(['run', '1', '--solo'])
check('start_answers_the_receipt_of_a_run_that_ended_soon', said == (200, 'conveyor: run r20261117T090000-1 started'), said)
os.remove(T + '/quick')
# Bug (#640): the receipt must be the project's own: each record's command runs on its checkout, and the answer is
# what that run printed (another project's run id would open the wrong run).
said = post(['run', '5', '--arm', 'conveyor', '--settings', S], 'other')
check('start_answers_its_projects_receipt', said == (200, 'conveyor: run r20261117T090000-2 started') and asked()[-1] == 'bench swe 5 --arm conveyor --settings ' + S, (said, asked()))
# A run or check naming a saved revision the build machine does not have is refused, with the engine's reason.
said = post(['run', '1', '--arm', 'arm-ffffffffffff'])
check('start_refuses_an_unknown_revision', said == (409, 'conveyor: no arm arm-ffffffffffff: `conveyor.sh bench swe arms` lists them'), said)
said = post(['arms', 'check', 'conveyor', 'arm-ffffffffffff'])
check('check_refuses_an_unknown_revision', said == (409, 'conveyor: no arm arm-ffffffffffff: `conveyor.sh bench swe arms` lists them'), said)
os.remove(T + '/hold')
# An arm's preflight takes minutes: like a run, it starts on the host and the Board is answered at once, with each
# arm's check ID (Bug #640: the answer said only that the preflights started, after a three-second guess).
open(T + '/hold', 'w').close()
rc, out, sec = host(['arms', 'check', 'superpowers'])
check('preflight_answers_while_it_goes', (rc, out) == (0, 'superpowers: checking k-r20261117T090000-1\n'), (rc, out, sec))
check('preflight_runs_bench_swe_arms_check', asked()[-1] == 'bench swe arms check superpowers', asked())
said = post(['arms', 'check', '--settings', S, 'conveyor', 'arm-0123456789ab'], 'other')
check('check_answers_every_arms_receipt', said == (200, 'conveyor: checking k-r20261117T090000-2\narm-0123456789ab: checking k-r20261117T090000-2'), said)
os.remove(T + '/hold')
said = post(['arms', 'save', 'Codex builds', CONV])
check('save_answers_the_revision', said == (200, 'arm-0123456789ab') and asked()[-1] == 'bench swe arms save Codex builds ' + CONV, (said, asked()))
# Saving an arm, a Start and a check are an admin's: a member's is refused before the host is asked.
role, n = ds.role_of, len(asked())
ds.role_of = lambda store, name: 'member'
said = [post(['arms', 'save', 'x', CONV]), post(['run', '1']), post(['arms', 'check', 'conveyor'])]
ds.role_of = role
check('a_members_bench_write_is_refused', [s[0] for s in said] == [403] * 3 and len(asked()) == n, (said, asked()[n:]))
# A field control_ok refuses, or a spec over its size limit, is HTTP 400 before the host is asked.
said = [post(['run', '5', '--settings', '{"cpus": 0}']), post(['arms', 'save', 'x', bad(command='id')]), post(['arms', 'save', 'x', CONV + ' ' * 5000])]
check('bad_bench_fields_are_refused', [s[0] for s in said] == [400] * 3 and len(asked()) == n, ([s[0] for s in said], asked()[n:]))
rc, out, sec = host(['diff', 'v1.0.0', 'main'])
check('compare_runs_bench_swe_diff', rc == 0 and open(MAIN + '/asked').read().split('\n')[-2] == 'bench swe diff v1.0.0 main', open(MAIN + '/asked').read())
# Bug: Compare's answer was the last line of `bench swe diff` alone, so the Board showed no totals, no task list and
# no facts of the flipped tasks. The host's answer here is a comparison of several lines; the reply is all of it.
DIFF = ('v1.0.0 against main on the 2 tasks both ran:\n  v1.0.0: 2 resolved\n  main: 1 resolved\n'
        '  The same in both: 1 task(s): p__b-2. Flipped: 1.\n\np__a-1: resolved by v1.0.0 only; the runs went apart at: review\n')
ds.run_script = lambda args, timeout, env=None: subprocess.CompletedProcess(args, 0, DIFF, '')
said = post(['diff', 'v1.0.0', 'main'])
# Bug (#326): the tab's history and a run's tasks are not in data.js (its size): GET /bench runs dashboard.sh --bench
# for the repo, and the run when one is asked, and gives its JSON; a run id of another shape never reaches it.
started = []
ds.run_script = lambda args, timeout, env=None: (started.append(args), subprocess.CompletedProcess(args, 0, '{"runs":[]}\n', ''))[1]


def get(path):
    c = http.client.HTTPConnection('127.0.0.1', srv.server_address[1], timeout=60)
    c.request('GET', path, headers={'Host': 'localhost:%d' % srv.server_address[1]})
    r = c.getresponse()
    return r.status, r.read().decode()


got = (get('/bench?repo=proj'), get('/bench?repo=proj&run=r20261117T090000-12'))
check('bench_gives_the_history_and_a_run', got == ((200, '{"runs":[]}\n'),) * 2 and [a[2:] for a in started] == [['--bench', 'proj'], ['--bench', 'proj', 'r20261117T090000-12']]
      and all(a[1].endswith('/dashboard.sh') for a in started), (got, started))
for path in ('/bench?repo=proj&run=../x', '/bench?repo=proj&run=-x', '/bench?repo=a%20b', '/bench'):
    check('bench_refuses_%s' % path, get(path)[0] == 400 and len(started) == 2, path)
srv.shutdown()
check('compare_answers_the_whole_comparison', said == (200, DIFF.strip()), said)
print('PASS: dashboard-server-bench (%d checks)' % passed[0])
EOF
