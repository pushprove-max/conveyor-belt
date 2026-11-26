#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# The Self-heals tab sends POST /control action heals for "File a batch card" (#1559), and its Docs list for "File a
# docs sweep card" (#1563): the server takes batch or docs and one area label, or - for the entries
# with no area, and runs `conveyor.sh heals batch <area>` or `conveyor.sh heals docs <area>` on the record. Bug each case catches: a shape that reaches the host's shell unchecked, the button refused, or the command
# run on another checkout than the record's.
set -uo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
export XDG_DATA_HOME=${XDG_DATA_HOME:-$HOME/.local/share}
PY=$XDG_DATA_HOME/conveyor/board-venv/bin/python3
"$PY" -c 'import pyotp, segno, cryptography' || { echo "FAIL: the Board's virtualenv $PY lacks its packages: run conveyor.sh setup" >&2; exit 1; }
"$PY" -I - "$HERE/.." <<'EOF'
import sys
sys.path.insert(0, sys.argv[1])
import dashboard_server as ds

passed = 0


def check(case, ok, why=''):
    global passed
    if not ok:
        print('FAIL [%s]: %s' % (case, why), file=sys.stderr)
        sys.exit(1)
    passed += 1


ok = lambda args: ds.control_ok({'action': 'heals', 'args': args, 'repo': 'project'})
for args in (['batch', 'area:engine'], ['batch', '-'], ['docs', 'area:engine'], ['docs', '-']):
    check('takes_%s' % '_'.join(args), ok(args), args)
for args in ([], ['batch'], ['sort'], ['sort', 'area:engine'], ['batch', 'area:engine', 'x'], ['batch', 'area;id'], ['batch', '-x'], ['batch', ''],
             ['docs'], ['docs', 'area;id'], ['docs', '']):
    check('refuses_%s' % '_'.join(args), not ok(args), args)
cmd = ds.control_script('heals', ['batch', 'area:engine'], '/m', '2026-11-23', '/r', 'u')
check('runs_heals_batch_on_the_record', cmd.startswith('CONVEYOR_MAIN=/r ') and cmd.endswith(' heals batch area:engine'), cmd)
# The Docs list's "File a docs sweep card" (#1563): bug it catches, the docs sweep filed as a self-heals batch card.
cmd = ds.control_script('heals', ['docs', 'area:engine'], '/m', '2026-11-23', '/r', 'u')
check('runs_heals_docs_on_the_record', cmd.startswith('CONVEYOR_MAIN=/r ') and cmd.endswith(' heals docs area:engine'), cmd)
# The Self-heals page's "Move up to harm" and "Drop now": entry ids of the list, at most 10 for harm (one card each,
# within the call's time limit). Bug each catches: the buttons refused, an id that is shell text or another list's let
# through, a harm of more entries than the call can file in its time, or the action run as a batch.
H1, H2 = 'h0123456789ab', 'hba9876543210'
for args in (['harm', H1], ['harm', H1, H2], ['harm'] + ['h%012x' % i for i in range(10)], ['drop', H1], ['drop'] + ['h%012x' % i for i in range(400)]):
    check('takes_heals_%s_%d' % (args[0], len(args) - 1), ok(args), args[:3])
for args in (['harm'], ['drop'], ['harm', 'd0123456789ab'], ['harm', 'h0123;id'], ['drop', H1 + 'x'], ['drop', '-'], ['harm', 'area:engine'],
             ['harm'] + ['h%012x' % i for i in range(11)], ['drop'] + ['h%012x' % i for i in range(401)]):
    check('refuses_heals_%s_%s' % (args[0], len(args) - 1), not ok(args), args[:3])
# The Self-heals page's batch sheet: --held, --prio P<n> and --title, then the entries it keeps (self-heals ids for a
# batch, docs ids for a docs sweep). Bug each catches: the sheet's filing refused, or a title, level or id that is shell
# text, too long or of the other list let through.
D1 = 'd0123456789ab'
for args in (['batch', 'area:engine', H1], ['batch', '-', '--held', '--prio', 'P3', '--title', 'Self-heals batch: engine (2 entries)', H1, H2],
             ['batch', 'area:engine', '--queue', '--prio', 'P2', H1], ['docs', 'area:docs', '--title', 'Docs sweep: docs (1 entry)', D1]):
    check('takes_sheet_%s' % '_'.join(args[:4]), ok(args), args)
# The sheet offers P3 and P2 alone: bug P0 and P1 caught, a level the sheet never sends let through; and --held with
# --queue, which ask for opposite things.
for args in (['batch', 'area:engine', D1], ['docs', 'area:docs', H1], ['batch', 'area:engine', '--prio', 'P4', H1], ['batch', 'area:engine', '--prio'],
             ['batch', 'area:engine', '--prio', 'P0', H1], ['batch', 'area:engine', '--prio', 'P1', H1], ['batch', 'area:engine', '--held', '--queue', H1],
             ['batch', 'area:engine', '--title', 'a\nb', H1], ['batch', 'area:engine', '--title', 'x' * 201, H1], ['batch', 'area:engine', '--title'],
             ['batch', 'area:engine', '--title', 't', '--held', H1], ['batch', 'area:engine'] + ['h%012x' % i for i in range(401)]):
    check('refuses_sheet_%s' % '_'.join(a[:12] for a in args[2:4]), not ok(args), args[:6])
cmd = ds.control_script('heals', ['batch', 'area:engine', '--held', '--title', 'A b', H1], '/m', '2026-11-23', '/r', 'u')
check('runs_heals_batch_sheet_on_the_record', cmd.startswith('CONVEYOR_MAIN=/r ') and cmd.endswith(" heals batch area:engine --held --title 'A b' %s" % H1), cmd)
cmd = ds.control_script('heals', ['harm', H1, H2], '/m', '2026-11-23', '/r', 'u')
check('runs_heals_harm_on_the_record', cmd.startswith('CONVEYOR_MAIN=/r ') and cmd.endswith(' heals harm %s %s' % (H1, H2)), cmd)
cmd = ds.control_script('heals', ['drop', H1], '/m', '2026-11-23', '/r', 'u')
check('runs_heals_drop_on_the_record', cmd.startswith('CONVEYOR_MAIN=/r ') and cmd.endswith(' heals drop %s' % H1), cmd)
# The Rules tab's "Self-heals expiry" (#1561): bug it catches, `rules healsdays=10` refused as no rule, or a value that is no whole number
# (shell text, a sign, a leading zero, a fraction) let through to the host's shell, days past 3650 (3651) passed to the
# host as if good, or the days sent with another rule (#1615: it goes alone).
rules = lambda args: ds.control_ok({'action': 'rules', 'args': args, 'repo': 'project'})
for args in (['healsdays=10'], ['healsdays=3650'], ['healsdays=1']):
    check('takes_rules_%s' % args[0], rules(args), args)
for args in (['healsdays='], ['healsdays=0'], ['healsdays=3651'], ['healsdays=010'], ['healsdays=-1'], ['healsdays=1.5'], ['healsdays=1;id'],
             ['healsdays=10000'], ['healsdays=10\n'], ['healsdays=on'], ['healsdays=10', 'P0=on'], ['P0=on', 'healsdays=10'], ['healsdays=10', 'healsdays=20']):
    check('refuses_rules_%s' % '_'.join(args), not rules(args), args)
# The Rules tab's dollar limits: bug it catches, `cardusd=20` refused as no rule, a value the engine does not take
# (on, which the on or off rules' pattern lets through; abc; 0; past 100000) passed to the host, or a limit sent with
# another rule.
for args in (['cardusd=1'], ['cardusd=100000'], ['issueusd=20'], ['cardusd=off'], ['issueusd=off']):
    check('takes_rules_%s' % args[0], rules(args), args)
for args in (['cardusd=abc'], ['cardusd=on'], ['issueusd=on'], ['cardusd='], ['cardusd=0'], ['issueusd=100001'], ['cardusd=010'],
             ['issueusd=1.5'], ['cardusd=5;id'], ['cardusd=5\n'], ['cardusd=5', 'P0=on'], ['P0=on', 'issueusd=on']):
    check('refuses_rules_%s' % '_'.join(args), not rules(args), args)
print('dashboard-server-heals: %d passed' % passed)
EOF
[ $? = 0 ] || exit 1
# The batch sheet's answer, through the server's POST /control: the host's run is a stub (run_script) that prints what
# `heals batch --held` prints: the filed line, which says how many entries wait, then the hold. Bug it catches: the
# Board answered the hold's line alone, so the owner never read that entries still wait.
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
mkdir -p "$T/config/conveyor" "$T/out" "$T/main" && echo page > "$T/out/index.html" \
  && jq -n --arg m "$T/main" '{records: [{repo: "proj", main: $m}]}' > "$T/config/conveyor/host.json" || exit 1
CONVEYOR_DASHBOARD_AUTH=$T/auth.json CONVEYOR_RULING_LOG=$T/rulings.jsonl CONVEYOR_MAIN=$T/main \
  XDG_CONFIG_HOME=$T/config HOME=$T "$PY" -I - "$HERE/.." "$T" <<'EOF'
import functools, http.client, json, subprocess, sys, threading
sys.path.insert(0, sys.argv[1])
import dashboard_server as ds

T = sys.argv[2]
SAID = ('conveyor: filed 100101 with 1 finding of area:engine; 1 wait for their card to land or close and stay on the list\n'
        'conveyor: #100101 is held, as it was filed held: release it (conveyor.sh control release 100101) once the owner says yes\n')
ds.run_script = lambda args, timeout, env=None: subprocess.CompletedProcess(args, 0, SAID, '')
read_host = ds.conveyor_host
ds.conveyor_host = lambda: (lambda h: h[:2] + (T + '/main',) + h[3:])(read_host())
srv = ds.Server(('127.0.0.1', 0), functools.partial(ds.Handler, directory=T + '/out'))
threading.Thread(target=srv.serve_forever, kwargs={'poll_interval': 0.02}, daemon=True).start()
args = ['batch', 'area:engine', '--held', '--prio', 'P3', 'h0123456789ab', 'hba9876543210']
c = http.client.HTTPConnection('127.0.0.1', srv.server_address[1], timeout=60)
c.request('POST', '/control', body=json.dumps({'action': 'heals', 'args': args, 'repo': 'proj'}),
          headers={'Host': 'localhost:%d' % srv.server_address[1], 'Origin': 'https://localhost:%d' % srv.server_address[1], 'Content-Type': 'application/json'})
r = c.getresponse()
said = (r.status, r.read().decode())
if said != (200, SAID.strip()):
    print('FAIL [heals_batch_answers_every_line]: POST /control heals %s answered %r, not the whole receipt %r' % (' '.join(args), said, SAID.strip()), file=sys.stderr)
    sys.exit(1)
print('dashboard-server-heals: the batch sheet gets the whole receipt')
# Bug it catches: a dollar limit that is no number answered as taken, or sent on to the host's command.
ran = []
ds.run_script = lambda args, timeout, env=None: ran.append(args) or subprocess.CompletedProcess(args, 0, '', '')
body = json.dumps({'action': 'rules', 'args': ['cardusd=abc'], 'repo': 'proj'})
c = http.client.HTTPConnection('127.0.0.1', srv.server_address[1], timeout=60)
c.request('POST', '/control', body=body,
          headers={'Host': 'localhost:%d' % srv.server_address[1], 'Origin': 'https://localhost:%d' % srv.server_address[1], 'Content-Type': 'application/json'})
status = c.getresponse().status; srv.shutdown()
if status != 400 or ran:
    print('FAIL [rules_cardusd_abc_runs_nothing]: POST /control %s answered %r and ran %r' % (body, status, ran), file=sys.stderr)
    sys.exit(1)
print('dashboard-server-heals: a dollar limit that is no number runs no command')
EOF
