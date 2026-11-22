#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Landed today's File on GitHub on a landed card with no GitHub issue sends POST /control action card-issue (#1346):
# the server takes one card id of issue 0 and runs it as `conveyor.sh cardissue <card id>` on the record's checkout.
# Bug each case catches: a card id of an issue (or a shape that reaches the host's shell unchecked) taken, the
# button refused, or the command run on another checkout than the record's, or cut off by the 30 s an action gets by
# default before its filing and its close are both done.
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


ok = lambda args: ds.control_ok({'action': 'card-issue', 'args': args, 'repo': 'project'})
check('takes_a_card_of_no_issue', ok(['c20261122T120000-project-0']), ['c20261122T120000-project-0'])
for args in ([], ['c20261122T120000-project-12'], ['12'], ['c20261122T120000-project-0', 'x'], ['c20261122T120000-pro;id-0'], ['-c20261122T120000-project-0']):
    check('refuses_%s' % '_'.join(args), not ok(args), args)
cmd = ds.control_script('card-issue', ['c20261122T120000-project-0'], '/m', '2026-11-22', '/r', 'u')
check('runs_cardissue_on_the_record', cmd.startswith('cd /r || exit 1; ') and cmd.endswith(' cardissue c20261122T120000-project-0'), cmd)
check('outlasts_its_two_writes', ds.CONTROL_TIMEOUT.get('card-issue', 30) >= 120, ds.CONTROL_TIMEOUT.get('card-issue'))
print('dashboard-server-cardissue: %d passed' % passed)
EOF
