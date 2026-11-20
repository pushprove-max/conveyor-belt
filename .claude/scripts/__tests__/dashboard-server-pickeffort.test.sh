#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# The Rules tab's Pick settings row saves a seat's effort range through POST /control action pick-effort (#1047): the
# server takes a seat (builder, reviewer or judge) with a min and a max effort, or clear, each run as `conveyor.sh pick
# effort ...` on the host, which checks the order and saves it in the pack (t_pickeffort, conveyor/tests/pick.test.sh).
# Bug each case catches: a shape that reaches the host's shell unchecked, or a range the Board sends that the server
# refuses or runs as another command.
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


ok = lambda args: ds.control_ok({'action': 'pick-effort', 'args': args, 'repo': 'project'})
for args in (['builder', 'medium', 'high'], ['reviewer', 'minimal', 'max'], ['judge', 'low', 'low'], ['judge', 'clear']):
    check('takes_%s' % '_'.join(args), ok(args), args)
for args in ([], ['builder'], ['tests', 'low', 'high'], ['builder', 'low'], ['builder', 'low', 'huge'], ['builder', 'clear', 'low'],
             ['builder', 'low', 'high', 'max'], ['builder', 'low;id', 'high'], ['-x', 'clear']):
    check('refuses_%s' % '_'.join(args), not ok(args), args)
cmd = ds.control_script('pick-effort', ['builder', 'medium', 'high'], '/m', '2026-11-20', '/r', 'u')
check('runs_pick_effort', cmd.endswith(' pick effort builder medium high'), cmd)
cmd = ds.control_script('pick-effort', ['judge', 'clear'], '/m', '2026-11-20', '/r', 'u')
check('runs_pick_effort_clear', cmd.endswith(' pick effort judge clear'), cmd)
print('dashboard-server-pickeffort: %d passed' % passed)
EOF
