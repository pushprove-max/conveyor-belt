#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# A card's Settings and Pick for me on the Board send POST /control action card (#387): the server takes one seat set
# (an issue, builder, reviewer or judge, a model and an effort or none), a seat or every seat cleared, and Pick for
# me, each run as `conveyor.sh control card ...` on the host, and Pick for me given the time the judge's call takes.
# Bug each case catches: a shape that reaches the host's shell unchecked, a Settings change the server refuses, or a
# Pick for me cut off by the 30 s an action gets by default before the judge answers.
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


ok = lambda args: ds.control_ok({'action': 'card', 'args': args, 'repo': 'project'})
for args in (['12', 'builder', 'claude-opus-5-5'], ['12', 'reviewer', 'gpt-6.1-sol', 'low'], ['12', 'judge', 'opencode:prov/m-2', 'max'],
             ['12', 'judge', 'clear'], ['12', 'clear'], ['12', 'pick']):
    check('takes_%s' % '_'.join(args), ok(args), args)
for args in (['12'], ['0', 'clear'], ['x', 'pick'], ['12', 'tests', 'm'], ['12', 'builder'], ['12', 'builder', '-m'], ['12', 'builder', 'm', 'huge'],
             ['12', 'builder', 'm', 'low', 'x'], ['12', 'pick', 'now'], ['12', 'builder', 'clear', 'low'], ['12', 'builder', 'm;id']):
    check('refuses_%s' % '_'.join(args), not ok(args), args)
cmd = ds.control_script('card', ['12', 'reviewer', 'gpt-6.1-sol', 'low'], '/m', '2026-11-18', '/r', 'u')
check('runs_control_card', cmd.endswith(' control card 12 reviewer gpt-6.1-sol low'), cmd)
check('pick_outlasts_the_judge', ds.CONTROL_TIMEOUT.get('card', 30) > 300, ds.CONTROL_TIMEOUT.get('card'))
print('dashboard-server-card: %d passed' % passed)
EOF
