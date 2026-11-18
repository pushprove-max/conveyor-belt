#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 60
# The page server's work for each open page (issue 566), by function: GET /events, GET /history, GET /work, GET /older and GET /donewhen called on a
# stand-in request, with no server, socket or login. Every open page did again work one could do for all: each /events
# connection serialised every panel of data.js (about 1.1 MB) on each update, and each GET /history started bash,
# every 60 s a page, though dashboard.sh kept the answer for 60 s.
set -euo pipefail
SOURCE=$(git rev-parse --show-toplevel)
# The server imports the Board's own packages: its virtualenv, as dashboard-server.test.sh runs it.
PY=${XDG_DATA_HOME:-$HOME/.local/share}/conveyor/board-venv/bin/python3
"$PY" -c 'import pyotp, segno, cryptography' || { echo "FAIL: the Board's virtualenv $PY lacks its packages: run conveyor.sh setup" >&2; exit 1; }
T=$(cd "$(mktemp -d /tmp/dashboard-server-feed-test.XXXXXX)" && pwd -P)
trap 'rm -rf "$T"' EXIT
CONVEYOR_DASHBOARD_AUTH=$T/auth/dashboard-auth.json CONVEYOR_RULING_LOG=$T/rulings.jsonl \
  "$PY" - "$SOURCE/.claude/scripts" "$T" <<'EOF'
import io, json, os, subprocess, sys, threading, time
sys.path.insert(0, sys.argv[1])
import dashboard_server as ds
T = sys.argv[2]
fail = []
def check(ok, why):
    if not ok:
        fail.append(why)

class Page:
    """A stand-in request: logged in, its replies kept; `gone` makes its next write fail, as a closed page's does."""
    def __init__(self, directory=T):
        self.directory, self.out, self.code, self.gone, self.close_connection = directory, io.BytesIO(), None, False, False
        self.wfile = self
    def authed(self, store=None):
        return True
    def send_response(self, code):
        self.code = code
    def send_header(self, *a):
        pass
    def end_headers(self):
        pass
    def reply(self, code, text, headers=None):
        self.code, self.text = code, text
    def write(self, b):
        if self.gone:
            raise OSError('the page went away')
        self.out.write(b)
    def flush(self):
        pass
    def events(self):
        return [e.split('\n', 1)[0] for e in self.out.getvalue().decode().split('\n\n') if e.startswith('event: ')]

def until(cond, why):
    end = time.monotonic() + 5
    while not cond():
        if time.monotonic() > end:
            fail.append(why)
            return
        time.sleep(0.01)

# D1. Bug: each /events connection serialised every panel again on each update, so two open pages paid twice. Two
# connections, two versions of data.js with two panels: one serialisation of each panel a version, four in all.
def data_js(n, a):
    with open(os.path.join(T, 'data.js'), 'w') as f:
        f.write('window.DASH = %s;\n' % json.dumps({'updatedAt': 't%d' % n, 'panels': {'a': {'n': a}, 'b': {'n': 'same' * n}}}))
data_js(1, 1)
serialised, real_dumps = [], json.dumps
def dumps(obj, *a, **k):
    if k.get('sort_keys'):
        serialised.append(obj)
    return real_dumps(obj, *a, **k)
ds.json.dumps = dumps
ds.PING = 0.1  # a closed page is found at its next ping
feed = ds.FEED[0] = ds.Feed(T)
feed.look()  # the feed's thread has read it: each page's own look finds it unchanged
pages = [Page(), Page()]
threads = [threading.Thread(target=ds.Handler.events, args=(p,), daemon=True) for p in pages]
for t in threads:
    t.start()
until(lambda: all(p.events() == ['event: snapshot'] for p in pages), 'events: each page opens with its snapshot')
data_js(2, 2)
feed.look()
until(lambda: all(len(p.events()) == 3 for p in pages), 'events: each page gets both changed panels')
for p in pages:
    p.gone = True
for t in threads:
    t.join(5)
ds.json.dumps = real_dumps
check(not any(t.is_alive() for t in threads), 'events: a closed page ends its connection')
check(all(p.events() == ['event: snapshot', 'event: panel', 'event: panel'] for p in pages),
      'events: each page gets its snapshot, then a panel event for each changed panel: %r' % [p.events() for p in pages])
check(len(serialised) == 4, 'events_serialise_each_panel_once_a_version: two pages, two versions, two panels must be '
      '4 serialisations, not one set a page: %d' % len(serialised))

# D2. Bug: each GET /history started bash, every 60 s for each open page, though dashboard.sh --history only printed
# its copy of the last minute. A fresh copy is served from the file and starts no process; an old one runs the script.
started = []
def no_process(*a, **k):
    started.append(a[0] if a else k.get('args'))
    return subprocess.CompletedProcess(a[0] if a else None, 0, '{"updatedAt":"built","panels":{}}\n', '')
ds.run_script = no_process
real_popen = subprocess.Popen
def popen(*a, **k):
    started.append(a[0] if a else k.get('args'))
    return real_popen(*a, **k)
ds.subprocess.Popen = popen
os.makedirs(os.path.join(T, 'cache'))
cached = os.path.join(T, 'cache', 'history.json')
with open(cached, 'w') as f:
    f.write('{"updatedAt":"cached","panels":{}}\n')
fresh = Page()
ds.Handler.history(fresh)
check(started == [], 'history_with_a_fresh_cache_starts_no_process: started %r' % started)
check(fresh.code == 200 and json.loads(fresh.out.getvalue())['updatedAt'] == 'cached',
      'history: a fresh cache is the answer: %s %r' % (fresh.code, fresh.out.getvalue()[:200]))
old = time.time() - 120  # two minutes: past dashboard.sh's HISTORY_TTL of 60 s
os.utime(cached, (old, old))
stale = Page()
ds.Handler.history(stale)
check(len(started) == 1 and stale.code == 200 and json.loads(stale.out.getvalue())['updatedAt'] == 'built',
      'history: a cache older than HISTORY_TTL runs dashboard.sh --history and gives its answer: %r %s' % (started, stale.code))
subprocess.Popen = real_popen

# D3 (#197). Bugs: GET /work served no reading, or a kept one, of what keeps the host busy; a failed reading reached
# the page as an empty machine. Each ask runs dashboard.sh --work and gives its JSON; a failure is a 502 with its reason.
started.clear()
ds.run_script = lambda *a, **k: (started.append(a[0]), subprocess.CompletedProcess(a[0], 0, '{"host":"devbox","groups":[],"other":[]}\n', ''))[1]
for _ in range(2):
    work = Page()
    ds.Handler.work(work)
check(len(started) == 2 and started[-1][-1] == '--work' and work.code == 200 and json.loads(work.out.getvalue())['host'] == 'devbox',
      'work: each ask runs dashboard.sh --work and gives its answer: %r %s' % (started, work.code))
ds.run_script = lambda *a, **k: subprocess.CompletedProcess(a[0], 1, '', 'dashboard: devbox gave no work reading: refused\n')
bad = Page()
ds.Handler.work(bad)
check(bad.code == 502 and 'gave no work reading' in bad.text and bad.out.getvalue() == b'',
      'work: a failed reading is a 502 with its reason: %s %r' % (bad.code, getattr(bad, 'text', None)))

# D4 (#251). Bugs: data.js carried every older run of every test file, so the Tests page's Timeline must read one
# file's from the server; GET /older ran dashboard.sh --older for another repo or file than the page asked for, or for
# one of a shape the Board never names; a failed read reached the page as a file with no older run.
started.clear()
ds.run_script = lambda *a, **k: (started.append(a[0]), subprocess.CompletedProcess(a[0], 0, '{"file":"t/a.test.sh","olderRuns":[],"olderEdits":[]}\n', ''))[1]
older = Page()
older.path = '/older?repo=sample&file=t%2Fa.test.sh'
ds.Handler.older(older)
check(started == [started[0]] and started[0][-3:] == ['--older', 'sample', 't/a.test.sh'] and older.code == 200
      and json.loads(older.out.getvalue())['olderRuns'] == [],
      'older: an ask runs dashboard.sh --older for its repo and file and gives its answer: %r %s' % (started, older.code))
started.clear()
for q in ('repo=sample&file=-x.test.sh', 'repo=a%20b&file=a.test.sh', 'repo=sample'):
    bad = Page()
    bad.path = '/older?' + q
    ds.Handler.older(bad)
    check(bad.code == 400, 'older: %s is refused: %s' % (q, bad.code))
check(started == [], 'older: a refused ask starts no process: %r' % started)
ds.run_script = lambda *a, **k: subprocess.CompletedProcess(a[0], 1, '', 'dashboard: devbox gave no older runs: refused\n')
bad = Page()
bad.path = '/older?repo=sample&file=a.test.sh'
ds.Handler.older(bad)
check(bad.code == 502 and 'gave no older runs' in bad.text and bad.out.getvalue() == b'',
      'older: a failed read is a 502 with its reason: %s %r' % (bad.code, getattr(bad, 'text', None)))

# #305. Bugs: data.js would carry every card's Done-when detail, so the Board reads one card's from the server; GET
# /donewhen ran dashboard.sh --donewhen for another repo or card than the page asked for, or for one of a shape no card
# has; a failed read reached the page as a check with no item.
started.clear()
ds.run_script = lambda *a, **k: (started.append(a[0]), subprocess.CompletedProcess(a[0], 0, '{"card":"c20260101T000000-sample-7","items":[]}\n', ''))[1]
dw = Page()
dw.path = '/donewhen?repo=sample&card=c20260101T000000-sample-7'
ds.Handler.donewhen(dw)
check(started == [started[0]] and started[0][-3:] == ['--donewhen', 'sample', 'c20260101T000000-sample-7'] and dw.code == 200
      and json.loads(dw.out.getvalue())['items'] == [],
      'donewhen: an ask runs dashboard.sh --donewhen for its repo and card and gives its answer: %r %s' % (started, dw.code))
started.clear()
for q in ('repo=sample&card=-x', 'repo=a%20b&card=c20260101T000000-sample-7', 'repo=sample'):
    bad = Page()
    bad.path = '/donewhen?' + q
    ds.Handler.donewhen(bad)
    check(bad.code == 400, 'donewhen: %s is refused: %s' % (q, bad.code))
check(started == [], 'donewhen: a refused ask starts no process: %r' % started)
ds.run_script = lambda *a, **k: subprocess.CompletedProcess(a[0], 1, '', 'dashboard: devbox gave no Done-when detail: refused\n')
bad = Page()
bad.path = '/donewhen?repo=sample&card=c20260101T000000-sample-7'
ds.Handler.donewhen(bad)
check(bad.code == 502 and 'gave no Done-when detail' in bad.text and bad.out.getvalue() == b'',
      'donewhen: a failed read is a 502 with its reason: %s %r' % (bad.code, getattr(bad, 'text', None)))

# D5 (#308). Bugs: GET /shot ran dashboard.sh --shot for a card or file of a shape the snapshot never names (a path out
# of the card's kept folder); the image did not reach the page as the bytes the host gave; a failed read reached the
# page as an empty image.
PNG = '%s.png' % ('c' * 40)
started.clear()
ds.run_script = lambda *a, **k: (started.append(a[0]), subprocess.CompletedProcess(a[0], 0, 'iVBORw==\n', ''))[1]
shot = Page()
shot.path = '/shot?repo=sample&card=c20260101T000000-sample-12&file=' + PNG
ds.Handler.shot(shot)
check(started == [started[0]] and started[0][-4:] == ['--shot', 'sample', 'c20260101T000000-sample-12', PNG] and shot.code == 200
      and shot.out.getvalue() == b'\x89PNG', 'shot: an ask runs dashboard.sh --shot for its card and file and gives the image: %r %s' % (started, shot.code))
started.clear()
for q in ('repo=sample&card=..&file=' + PNG, 'repo=sample&card=c20260101T000000-sample-12&file=../x.png', 'repo=sample&card=c20260101T000000-sample-12&file=%s.svg' % ('c' * 40), 'repo=sample&card=c20260101T000000-sample-12'):
    bad = Page()
    bad.path = '/shot?' + q
    ds.Handler.shot(bad)
    check(bad.code == 400, 'shot: %s is refused: %s' % (q, bad.code))
check(started == [], 'shot: a refused ask starts no process: %r' % started)
ds.run_script = lambda *a, **k: subprocess.CompletedProcess(a[0], 1, '', 'dashboard: devbox gave no screenshot\n')
bad = Page()
bad.path = '/shot?repo=sample&card=c20260101T000000-sample-12&file=' + PNG
ds.Handler.shot(bad)
check(bad.code == 502 and 'gave no screenshot' in bad.text and bad.out.getvalue() == b'',
      'shot: a failed read is a 502 with its reason: %s %r' % (bad.code, getattr(bad, 'text', None)))

# #307. Bugs: data.js would carry every review's cited lines, so the Board reads one card's from the server; GET
# /excerpts ran dashboard.sh --excerpts for another repo or card than the page asked for, or for one of a shape no card
# has.
started.clear()
ds.run_script = lambda *a, **k: (started.append(a[0]), subprocess.CompletedProcess(a[0], 0, '{"card":"c20260101T000000-sample-7","excerpts":[]}\n', ''))[1]
ex = Page()
ex.path = '/excerpts?repo=sample&card=c20260101T000000-sample-7'
ds.Handler.excerpts(ex)
check(started == [started[0]] and started[0][-3:] == ['--excerpts', 'sample', 'c20260101T000000-sample-7'] and ex.code == 200
      and json.loads(ex.out.getvalue())['excerpts'] == [],
      'excerpts: an ask runs dashboard.sh --excerpts for its repo and card and gives its answer: %r %s' % (started, ex.code))
started.clear()
bad = Page()
bad.path = '/excerpts?repo=sample&card=../x'
ds.Handler.excerpts(bad)
check(bad.code == 400 and started == [], 'excerpts: a card of another shape is refused and starts no process: %s %r' % (bad.code, started))

for f in fail:
    print('FAIL: ' + f, file=sys.stderr)
sys.exit(1 if fail else 0)
EOF
echo "PASS: dashboard-server-feed"
