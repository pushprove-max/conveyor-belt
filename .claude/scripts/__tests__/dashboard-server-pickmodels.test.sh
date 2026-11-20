#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# The Rules tab's Pick settings row saves the models the pick may give a seat through POST /control action pick-models
# (#1067): the server takes a seat (builder, reviewer or judge) with one or more models, each <model> or
# <model>=<min>-<max> (either bound empty), or clear, each run as `conveyor.sh pick models ...` on the host, which
# checks that the seat allows each model and its program takes the efforts, and saves the list in the pack
# (t_pickmodels, conveyor/tests/pick.test.sh).
# Bug each case catches: a shape that reaches the host's shell unchecked, or a list the Board sends that the server
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


ok = lambda args: ds.control_ok({'action': 'pick-models', 'args': args, 'repo': 'project'})
for args in (['builder', 'claude-opus-5-5=medium-high'], ['builder', 'claude-opus-5-5=medium-high', 'claude-sonnet-5-5'],
             ['reviewer', 'gpt-6-sol=-low', 'opencode:prov/m=minimal-'], ['judge', 'claude-opus-5-5=-'], ['judge', 'clear']):
    check('takes_%s' % '_'.join(args), ok(args), args)
for args in ([], ['builder'], ['tests', 'm'], ['builder', 'm=low'], ['builder', 'm=low-huge'], ['builder', 'clear', 'm'],
             ['builder', 'm;id'], ['builder', 'm=low-high;id'], ['builder', '-x'], ['builder', 'm=low-high-max'], ['builder', 7]):
    check('refuses_%s' % '_'.join(map(str, args)), not ok(args), args)
cmd = ds.control_script('pick-models', ['builder', 'claude-opus-5-5=medium-high', 'claude-sonnet-5-5'], '/m', '2026-11-20', '/r', 'u')
check('runs_pick_models', cmd.endswith(' pick models builder claude-opus-5-5=medium-high claude-sonnet-5-5'), cmd)
cmd = ds.control_script('pick-models', ['judge', 'clear'], '/m', '2026-11-20', '/r', 'u')
check('runs_pick_models_clear', cmd.endswith(' pick models judge clear'), cmd)
print('dashboard-server-pickmodels: %d passed' % passed)
EOF
