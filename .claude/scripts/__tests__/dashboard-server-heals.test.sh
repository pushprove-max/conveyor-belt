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
print('dashboard-server-heals: %d passed' % passed)
EOF
