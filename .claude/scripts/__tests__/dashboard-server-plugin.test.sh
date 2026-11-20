#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# POST /plugin-dismiss (issue 1042): the Plugin problems pane's Dismiss removes one note from a Foreman's
# plugin-bugs.md and files nothing. Bugs each case catches: a Dismiss that removed more than that one line, or none;
# one that ran gh; a write to a file the Board did not read its notes from (any path a page could name); a write taken
# without a login or from another site's page.
# The server runs in this process, over plain HTTP: what is checked is the handler, not TLS. Its requests come from
# this device, which "No login on this device" (on with no value stored) lets in with no login.
set -uo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
export XDG_DATA_HOME=${XDG_DATA_HOME:-$HOME/.local/share}
PY=$XDG_DATA_HOME/conveyor/board-venv/bin/python3
"$PY" -c 'import pyotp, segno, cryptography' || { echo "FAIL: the Board's virtualenv $PY lacks its packages: run conveyor.sh setup" >&2; exit 1; }
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
mkdir -p "$T/out" "$T/auth" "$T/bin" "$T/fm"
# stub: a gh that leaves a mark when run, so the case can show Dismiss never runs it.
printf '#!/usr/bin/env bash\ntouch "%s/gh-ran"\n' "$T" > "$T/bin/gh"; chmod +x "$T/bin/gh"
PATH=$T/bin:$PATH CONVEYOR_DASHBOARD_AUTH=$T/auth/dashboard-auth.json CONVEYOR_RULING_LOG=$T/rulings.jsonl XDG_CONFIG_HOME=$T/config \
  HOME=$T CONVEYOR_MAIN=$T "$PY" -I - "$HERE/.." "$T" <<'EOF'
import functools, http.client, io, json, os, sys, threading
sys.path.insert(0, sys.argv[1])
import dashboard_server as ds

T = sys.argv[2]
OUT, NOTES, OTHER = os.path.join(T, 'out'), os.path.join(T, 'fm', 'plugin-bugs.md'), os.path.join(T, 'fm', 'other.md')
HEAD = '# Plugin problems the Foreman noted (for the conveyor-belt repo)\n\n'
A = '- 2026-11-20T09:00:00Z · card c20261120T080000-sample-7 · setup never sets linkFromMain · evidence: -'
B = '- 2026-11-20T09:10:00Z · card - · npm ci runs twice · evidence: -'
with open(NOTES, 'w') as f:
    f.write(HEAD + A + '\n' + B + '\n')
os.chmod(NOTES, 0o600)
with open(OTHER, 'w') as f:
    f.write(B + '\n')
# data.js as dashboard.sh writes it: the Health part names the one file the Board read notes from.
with open(os.path.join(OUT, 'data.js'), 'w') as f:
    f.write('window.DASH = %s;\n' % json.dumps({'panels': {'health': {'error': None, 'data': {'pluginBugs': [
        {'repo': 'sample', 'projects': ['sample'], 'count': 2, 'file': NOTES, 'url': 'plugin-bugs/sample.txt', 'notes': []}]}}}}))
srv = ds.Server(('127.0.0.1', 0), functools.partial(ds.Handler, directory=OUT))
PORT = srv.server_address[1]
threading.Thread(target=srv.serve_forever, kwargs={'poll_interval': 0.02}, daemon=True).start()
passed = [0]


def check(case, ok, why=''):
    if not ok:
        sys.exit('FAIL: %s: %s' % (case, why))
    passed[0] += 1


def post(body, host='localhost:%d' % PORT, origin=None):
    c = http.client.HTTPConnection('127.0.0.1', PORT, timeout=10)
    c.request('POST', '/plugin-dismiss', body=json.dumps(body).encode(),
              headers={'Host': host, 'Origin': origin or 'https://' + host, 'Content-Type': 'application/json'})
    r = c.getresponse()
    r.read()
    c.close()
    return r.status


def text(p):
    with open(p) as f:
        return f.read()


# Refused, and the file stays: no login, another site's page, a file the Board did not read, another key, a line
# that is not a note, a note no longer in the file.
WHOLE = HEAD + A + '\n' + B + '\n'
check('not_logged_in', post({'file': NOTES, 'line': B}, host='192.0.2.1:%d' % PORT) == 401 and text(NOTES) == WHOLE, text(NOTES))
check('other_site', post({'file': NOTES, 'line': B}, origin='https://example.com') == 403 and text(NOTES) == WHOLE, text(NOTES))
check('unread_file', post({'file': OTHER, 'line': B}) == 409 and text(OTHER) == B + '\n', text(OTHER))
check('other_key', post({'file': NOTES, 'line': B, 'all': True}) == 400 and text(NOTES) == WHOLE, text(NOTES))
check('not_a_note', post({'file': NOTES, 'line': '# Plugin problems the Foreman noted (for the conveyor-belt repo)'}) == 400 and text(NOTES) == WHOLE, text(NOTES))
check('gone_note', post({'file': NOTES, 'line': B + ' and more'}) == 409 and text(NOTES) == WHOLE, text(NOTES))
err, sys.stderr = sys.stderr, io.StringIO()
got = post({'file': NOTES, 'line': B})
log, sys.stderr = sys.stderr.getvalue(), err
check('dismisses_that_note_alone', got == 200 and text(NOTES) == HEAD + A + '\n', (got, text(NOTES)))
check('names_its_user', 'dashboard: plugin problem dismissed by %s from 127.0.0.1' % ds.LOCAL in log, log)
check('keeps_the_mode', os.stat(NOTES).st_mode & 0o777 == 0o600, oct(os.stat(NOTES).st_mode))
check('no_temp_left', sorted(os.listdir(os.path.dirname(NOTES))) == ['other.md', 'plugin-bugs.md'], os.listdir(os.path.dirname(NOTES)))
check('runs_no_gh', not os.path.exists(os.path.join(T, 'gh-ran')), 'gh was run')
srv.shutdown()
print('PASS: dashboard-server-plugin (%d checks)' % passed[0])
EOF
