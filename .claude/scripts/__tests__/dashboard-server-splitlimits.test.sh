#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# The Rules tab's four limit rows under Split large issues save a limit through POST /control action split-limits: the
# server takes one to four limits, each <limit>=<n> (a whole number of 1 or more) or <limit>=default, run as
# `conveyor.sh split-limits ...` on the host, which saves them in the pack (t_splitlimitsset,
# conveyor/tests/splitlimits.test.sh).
# Bug each case catches: a shape that reaches the host's shell unchecked, or a limit the Board sends that the server
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


ok = lambda args: ds.control_ok({'action': 'split-limits', 'args': args, 'repo': 'project'})
for args in (['files=5'], ['doneWhen=default'], ['chars=3000', 'areas=2'], ['doneWhen=1', 'files=2', 'areas=3', 'chars=4']):
    check('takes_%s' % '_'.join(args), ok(args), args)
for args in ([], ['files=0'], ['files=05'], ['files='], ['files'], ['growFiles=5'], ['files=5;id'], ['files=-1'],
             ['files=1234567890'], ['doneWhen=1', 'files=2', 'areas=3', 'chars=4', 'files=5']):
    check('refuses_%s' % '_'.join(args), not ok(args), args)
cmd = ds.control_script('split-limits', ['files=5', 'chars=default'], '/m', '2026-11-20', '/r', 'u')
check('runs_split_limits', cmd.endswith(' split-limits files=5 chars=default'), cmd)
print('dashboard-server-splitlimits: %d passed' % passed)
EOF
