#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# The Declined panel's Self-heals list sends POST /control action heals for "File a batch card" (#1559), and its Docs
# list for "File a docs sweep card" (#1563): the server takes batch or docs and one area label, or - for the entries
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
cmd = ds.control_script('heals', ['harm', H1, H2], '/m', '2026-11-23', '/r', 'u')
check('runs_heals_harm_on_the_record', cmd.startswith('CONVEYOR_MAIN=/r ') and cmd.endswith(' heals harm %s %s' % (H1, H2)), cmd)
cmd = ds.control_script('heals', ['drop', H1], '/m', '2026-11-23', '/r', 'u')
check('runs_heals_drop_on_the_record', cmd.startswith('CONVEYOR_MAIN=/r ') and cmd.endswith(' heals drop %s' % H1), cmd)
# The Rules tab's "Self-heals expiry" (#1561): bug it catches, `rules healsdays=10` refused as no rule, or a value that is no whole number
# (shell text, a sign, a leading zero, a fraction) let through to the host's shell.
rules = lambda args: ds.control_ok({'action': 'rules', 'args': args, 'repo': 'project'})
for args in (['healsdays=10'], ['healsdays=3650'], ['healsdays=1']):
    check('takes_rules_%s' % args[0], rules(args), args)
for args in (['healsdays='], ['healsdays=0'], ['healsdays=010'], ['healsdays=-1'], ['healsdays=1.5'], ['healsdays=1;id'], ['healsdays=10000']):
    check('refuses_rules_%s' % args[0], not rules(args), args)
print('dashboard-server-heals: %d passed' % passed)
EOF
