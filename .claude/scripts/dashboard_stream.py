#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""dashboard_stream.py <dashboard folder> <main checkout> -- the dashboard's live Conveyor feed.

dashboard.sh --loop runs it beside the page server. For every record conveyor/host.json names it keeps one
`conveyor.sh watch` running (conveyor/watch.py says what each line holds): over ssh to the build machine (at host.json's
`ssh` target), or here on one machine (config()). After each line it writes <dashboard folder>/stream.json, the same
object dashboard.sh's conveyor() gives ({host, local, reachable, error, records}), each record with readAt (when its
snapshot began, by this machine's clock: data.js is dated when it is built, which can be after a change the snapshot
did not read yet) and retried (the blocked cards its host's last retried line names: {card, issue, at}), plus `stream`: {live (every record's stream is up and its host's last snapshot worked), heardAt (the oldest of
the times each record's host was last heard from), since (when the stream went down; null while live), error (why it
is down), writtenAt (when this file was written: every TICK seconds at least)}. After a line that changed something it
has `dashboard.sh --publish` build data.js again from that and the slower parts the last cycle read, so a card's step
reaches the page without waiting for the 60 s cycle, and the slow reads (the usage limit, GitHub, cost history) never
hold it up. A build starts at most every GAP seconds: the changes in that time go into the next one, none is lost. A
live line that changes only a running card's figures (figures_only) is built SLOW seconds after the last build (this
feed's or the cycle's) at the soonest, as such a line comes every second while a step runs; any other change in that wait builds after GAP. A
line that changes nothing (a beat) builds nothing; with no change for KEEP seconds data.js is built once more, so its
writtenAt stays within the page's window (health.js STREAM_EXPIRE_MS) and the page sees a feed that stopped. A
record's live line is laid over its last snapshot's belt.

A stream that ends, or says nothing for DEAD seconds (the host beats every 10 s), is closed and opened again after
1 s, then 2, 4 ... up to 30 s between tries; each new stream begins with a whole snapshot. While a record's stream is
down its last snapshot stays, marked stale (live false, with heardAt), and records is null only until every record
has sent one. stream.json is written at least every TICK seconds while this runs, so its age says whether it does.
/units reads units-feed.json, written with it: the same, each snapshot cut to what /units draws.
Test seams: CONVEYOR_STREAM_DEAD, CONVEYOR_STREAM_TICK and CONVEYOR_STREAM_BACKOFF (the first wait, s).
"""
import copy
import datetime
import glob
import json
import os
import select
import shlex
import signal
import subprocess
import sys
import threading
import time

HERE = os.path.dirname(os.path.abspath(__file__))
DEAD = float(os.environ.get('CONVEYOR_STREAM_DEAD') or 30)
TICK = float(os.environ.get('CONVEYOR_STREAM_TICK') or 10)
BACKOFF = float(os.environ.get('CONVEYOR_STREAM_BACKOFF') or 1)
BACKOFF_MAX = 30.0
GAP = 2.0    # s from the start of one build of data.js to the start of the next, at least
SLOW = 15.0  # the same, when the only changes since the last build are a running card's figures (figures_only)
KEEP = 45.0  # s with no change after which data.js is built again for its writtenAt: under health.js STREAM_EXPIRE_MS
OPEN = set()  # the ssh of every stream open now: each in a group of its own, so each is ended with this process


def end(*_):
    for p in list(OPEN):
        try:
            os.killpg(p.pid, signal.SIGKILL)
        except OSError:
            pass
    os._exit(0)


def iso(t):
    return None if t is None else datetime.datetime.fromtimestamp(t, datetime.timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')


def config(main):
    """(host, the steered record's main, [(repo, main)], ssh target or None, the checkout whose conveyor.sh runs), or
    (host or None, reason naming the field that is wrong) when it cannot be read: as hostfile.sh, the one reader of
    the host file, gives it for the checkout main. On one machine there is no target, and the Board's own copy of
    Conveyor runs here."""
    try:
        run = subprocess.run(['bash', os.path.join(HERE, 'hostfile.sh'), main], capture_output=True, text=True, timeout=30)
        got = json.loads(run.stdout)
    except (OSError, subprocess.SubprocessError, ValueError) as e:
        return None, 'conveyor/host.json could not be read: %s' % e
    if not isinstance(got, dict):
        return None, 'conveyor/host.json could not be read'
    if run.returncode != 0 or got.get('error') is not None:
        return got.get('host'), got.get('error') or 'conveyor/host.json could not be read'
    return (got['host'], got['main'], [(r['repo'], r['main']) for r in got['records']], got['target'], got['engine']), None


FIGURES = ('tokens', 'usd', 'reading')   # a live card's figures: its counts, and whether its usage is read yet
LIVE_FIGURES = ('turns', 'lastOutputAt')  # the same, in its `live`: its reply count and the time of its last output


def figures_only(old, new):
    """True when the live cards new differ from old, the overlay they replace, only in their figures (FIGURES and
    LIVE_FIGURES): the same cards, each with the same step, action, files and atEnd. With no overlay before, the
    snapshot's belt is replaced: not figures only."""
    def rest(c):
        if not isinstance(c, dict):
            return c
        c = {k: v for k, v in c.items() if k not in FIGURES}
        if isinstance(c.get('live'), dict):
            c['live'] = {k: v for k, v in c['live'].items() if k not in LIVE_FIGURES}
        return c
    return isinstance(old, dict) and old.keys() == new.keys() and all(rest(old[k]) == rest(new[k]) for k in new)


# The parts of a record's snapshot that /units draws (hooks/sources.ts parseRecord). The rest (tests, testActions ...)
# is the Board's alone and grows with the Tests page's history. `declined` and `declinedRest` are cut to the judge's
# lines, by id, who and time; `open` to the two lists /units reads.
UNITS_PARTS = ('health', 'needsYou', 'belt', 'landed', 'landedCount', 'queue', 'cost', 'awaitingDeploy', 'suites', 'snapshotAt')


def units_snap(snap):
    if not isinstance(snap, dict):
        return snap
    out = {k: snap[k] for k in UNITS_PARTS if k in snap}
    if isinstance(snap.get('open'), dict):
        out['open'] = {k: snap['open'][k] for k in ('umbrellas', 'held') if k in snap['open']}
    for k in ('declined', 'declinedRest'):
        if isinstance(snap.get(k), list):
            out[k] = [{f: x.get(f) for f in ('id', 'by', 'time')} for x in snap[k] if isinstance(x, dict) and x.get('by') == 'judge']
    return out


def units_doc(d):
    """d with each record's snapshot cut to the parts /units draws."""
    if not isinstance(d.get('records'), list):
        return d
    return dict(d, records=[dict(r, snap=units_snap(r.get('snap'))) if isinstance(r, dict) else r for r in d['records']])


def put(out, d):
    """<out>/stream.json replaced by d, whole: a reader never sees half of it. Then <out>/units-feed.json: the same, each
    snapshot cut to what /units draws (units_doc), so it stays under the cap /units reads under as the history grows."""
    tmp = os.path.join(out, '.stream.json.%d' % threading.get_ident())
    try:
        for name, doc in (('stream.json', d), ('units-feed.json', units_doc(d))):
            with open(tmp, 'w') as f:
                json.dump(doc, f, separators=(',', ':'))
            os.chmod(tmp, 0o644)
            os.replace(tmp, os.path.join(out, name))
    except OSError as e:
        sys.stderr.write(f'dashboard_stream: could not write the feed: {e}\n')
        try:
            os.remove(tmp)  # not left: each process names its own, so leftovers add up
        except OSError:
            pass


class Feed:
    def __init__(self, out, dash, main, host, hmain, recs, target, engine=None):
        self.out, self.dash, self.main, self.host, self.hmain, self.target = out, dash, main, host, hmain, target
        self.engine = engine or hmain
        self.cfg = (host, hmain, recs, target, engine)
        self.lock = threading.Lock()
        self.recs = [{'repo': repo, 'main': m, 'snap': None, 'overlay': None, 'retried': [], 'repoUrl': None, 'lastPushAt': None, 'up': False,
                      'heardAt': None, 'downAt': time.time(), 'error': 'the stream has not opened yet', 'unreachable': False,
                      'snapAt': None, 'readAt': None, 'failed': None, 'failedAt': None}
                     for repo, m in recs]
        self.wlock = threading.Lock()
        self.dirty = threading.Event()  # data.js is to be built again
        self.urgent = threading.Event()  # and a change since the last build is more than figures: after GAP, not SLOW
        self.built = time.monotonic() - GAP  # when the last build of data.js started (none yet: the first is not held)
        self.shown = None               # what of the stream the last publish showed: (live, error)
        self.gone = False               # the host file changed: stream.json is no longer this feed's

    # ---- one record's stream ----
    def follow(self, rec):
        wait = BACKOFF
        while True:
            cmd = 'CONVEYOR_MAIN=%s exec bash %s watch' % (shlex.quote(rec['main']), shlex.quote(self.engine + '/conveyor/conveyor.sh'))
            # Over ssh to the build machine, or here on one machine (no target).
            argv = ['bash', '-c', cmd] if self.target is None else [
                'ssh', '-o', 'BatchMode=yes', '-o', 'ConnectTimeout=5', '-o', 'ServerAliveInterval=15', '-o', 'ServerAliveCountMax=4', self.target, cmd]
            try:
                # A group of its own: closing a stream ends everything it started, so nothing holds its pipes open.
                p = subprocess.Popen(argv, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=subprocess.PIPE, bufsize=0,
                                     start_new_session=True)
            except OSError as e:
                self.down(rec, '%s could not start: %s' % (argv[0], e), False)
                time.sleep(wait)
                wait = min(BACKOFF_MAX, wait * 2)
                continue
            OPEN.add(p)
            tail = []
            reader = threading.Thread(target=lambda: tail.extend(p.stderr.read().splitlines()[-5:]), daemon=True)
            reader.start()
            got, quiet = self.read(rec, p)
            try:
                os.killpg(p.pid, signal.SIGKILL)
            except OSError:
                pass
            rc = p.wait()
            OPEN.discard(p)
            reader.join(2)
            p.stdout.close()
            err = [x.decode('utf-8', 'replace').strip() for x in tail if x.strip()]
            why = 'no line in %g s' % DEAD if quiet else err[-1][:200] if err else 'the stream ended (exit %s)' % rc
            self.down(rec, '%s: %s' % (self.host, why), rc == 255 and self.target is not None)
            if got:
                wait = BACKOFF  # it worked: the next try is soon
            time.sleep(wait)
            wait = BACKOFF if got else min(BACKOFF_MAX, wait * 2)

    def read(self, rec, p):
        """Reads lines until the stream ends or goes quiet for DEAD seconds: (a snapshot came, it went quiet)."""
        got, buf, fd = False, b'', p.stdout.fileno()
        last = time.monotonic()
        while True:
            ready, _, _ = select.select([fd], [], [], max(0.0, last + DEAD - time.monotonic()))
            if not ready:
                return got, True
            chunk = os.read(fd, 1 << 16)
            if not chunk:
                return got, False
            last = time.monotonic()
            buf += chunk
            while b'\n' in buf:
                line, buf = buf.split(b'\n', 1)
                try:
                    ev = json.loads(line)
                except ValueError:
                    continue
                if isinstance(ev, dict) and self.take(rec, ev):
                    got = True

    def take(self, rec, ev):
        kind, now, changed, slow = ev.get('type'), time.time(), False, False
        with self.lock:
            rec['heardAt'] = now
            if kind == 'snapshot' and isinstance(ev.get('snap'), dict):
                # When the snapshot began, by this machine's clock: what it read is that old, however late the line
                # came. A line that does not say how long it took is dated when it came.
                took = ev.get('took')
                took = took if isinstance(took, (int, float)) and not isinstance(took, bool) and 0 <= took < 86400 else 0
                rec.update(snap=ev['snap'], overlay=None, repoUrl=ev.get('repoUrl'), lastPushAt=ev.get('lastPushAt'),
                           up=True, downAt=None, error=None, unreachable=False, snapAt=now, readAt=now - took, failed=None, failedAt=None)
                changed = True
            elif kind == 'live' and isinstance(ev.get('cards'), dict) and rec['snap'] is not None:
                slow = figures_only(rec['overlay'], ev['cards'])
                rec['overlay'] = ev['cards']
                changed = True
            elif kind == 'retried' and isinstance(ev.get('cards'), list):
                # The cards given back, read at once by the host: a snapshot can take long after a retry, and until
                # it comes Needs you shows such a blocked card as retried (docs/board.md).
                rec['retried'] = [c for c in ev['cards'] if isinstance(c, dict) and isinstance(c.get('card'), str)]
                changed = True
            elif kind == 'error':
                # The host's snapshot failed: the board is its last good one, so it is not live (its beats say only
                # that the stream is open) until a snapshot works again.
                if rec['failed'] is None:
                    rec['failedAt'] = now
                rec['failed'] = '%s: %s' % (self.host, str(ev.get('error') or 'the snapshot failed')[:200])
                changed = True
        # stream.json is replaced before the publisher is told, so a publish that starts at once reads this change.
        self.write()
        if changed:
            if not slow:
                self.urgent.set()
            self.dirty.set()
        return kind == 'snapshot'

    def down(self, rec, why, unreachable):
        with self.lock:
            if rec['up']:
                rec['downAt'] = time.time()
            rec.update(up=False, error=why, unreachable=unreachable)
        self.write()
        self.urgent.set()
        self.dirty.set()

    # ---- stream.json ----
    @staticmethod
    def merged(rec):
        snap = rec['snap']
        if rec['overlay'] is None:
            return snap
        snap = copy.deepcopy(snap)
        for b in snap.get('belt') or []:
            if not isinstance(b, dict) or b.get('landed'):
                continue
            o = rec['overlay'].get(b.get('card'))
            if o is None:
                b['live'] = None  # its step ended after the snapshot; the next snapshot has the step's line
                continue
            b.update(tokens=o.get('tokens'), usd=o.get('usd'), reading=o.get('reading'), atEnd=o.get('atEnd') is True, live=o.get('live'))
            if isinstance(o.get('files'), dict) and isinstance(b.get('track'), dict):
                b['track']['files'] = o['files']
        return snap

    def doc(self):
        with self.lock:
            recs = list(self.recs)
            # A record whose stream is open but whose last snapshot failed is stale like one whose stream is down: its
            # age is that of its last good snapshot, and its error is the failure.
            stale = lambda r: not r['up'] or r['failed'] is not None  # noqa: E731
            live = not any(stale(r) for r in recs)
            heard = [r['snapAt'] if r['up'] and r['failed'] is not None else r['heardAt'] for r in recs]
            down = [dict(r, error=r['failed'], downAt=r['failedAt']) if r['up'] else r for r in recs if stale(r)]
            records = None if any(r['snap'] is None for r in recs) else [
                {'repo': r['repo'], 'snap': self.merged(r), 'steered': r['main'] == self.hmain, 'repoUrl': r['repoUrl'], 'lastPushAt': r['lastPushAt'],
                 'readAt': iso(r['readAt']), 'retried': r['retried']}
                for r in recs]
            error = None
            if records is None:
                error = down[0]['error'] if down else 'waiting for the first snapshot of every record'
            return {'host': self.host, 'local': self.target is None, 'reachable': not any(r['unreachable'] for r in recs), 'error': error, 'records': records,
                    'stream': {'live': live, 'heardAt': None if None in heard else iso(min(heard)),
                               'since': None if live else iso(min(r['downAt'] or time.time() for r in down)),
                               'error': None if live else '; '.join(sorted({r['error'] for r in down if r['error']})) or None,
                               'writtenAt': iso(time.time())}}

    def write(self):
        # One write at a time: a document built earlier never replaces one built later; none once the host file changed.
        with self.wlock:
            if not self.gone:
                self._write()

    def changed(self, host):
        """The host file changed: /control reads it per request, so the page stops showing this feed's cards
        before the feed ends. stream.json becomes the new host's, with no card, data.js is built from it at once, and
        the feed ends; dashboard.sh --loop starts it again on the new file."""
        why = 'conveyor/host.json changed; the stream restarts on it'
        sys.stderr.write('dashboard_stream: %s\n' % why)
        t = iso(time.time())
        with self.wlock:
            self.gone = True
            self._write({'host': host, 'reachable': None, 'error': why, 'records': [],
                         'stream': {'live': False, 'heardAt': None, 'since': t, 'error': why, 'writtenAt': t}})
        try:
            run = subprocess.run(['bash', self.dash, '--publish'], capture_output=True, text=True, timeout=120)
            if run.returncode != 0:
                sys.stderr.write('dashboard_stream: publish failed: %s\n' % run.stderr.strip()[-300:])
        except (OSError, subprocess.TimeoutExpired) as e:
            sys.stderr.write('dashboard_stream: publish failed: %s\n' % e)
        end()

    def _write(self, d=None):
        put(self.out, d or self.doc())

    # ---- data.js, built again after a change: one build at a time, at most every GAP s (SLOW s while only figures
    # changed), and the changes during the wait or a build give one more ----
    def publisher(self):
        while True:
            self.publish_next()

    def publish_next(self):
        self.dirty.wait()
        # Figures only: held until SLOW s after the last build, this feed's or the cycle's, or until a change that is
        # more comes in that time.
        while not self.urgent.is_set():
            left = self.last_build() + SLOW - time.monotonic()
            if left <= 0:
                break
            self.urgent.wait(left)
        time.sleep(max(0.0, self.built + GAP - time.monotonic()))
        # Cleared after the wait: a change in it is in stream.json already, so this build takes it.
        self.urgent.clear()
        self.dirty.clear()
        self.built = time.monotonic()
        try:
            run = subprocess.run(['bash', self.dash, '--publish'], capture_output=True, text=True, timeout=120)
            if run.returncode != 0:
                sys.stderr.write('dashboard_stream: publish failed: %s\n' % run.stderr.strip()[-300:])
        except (OSError, subprocess.TimeoutExpired) as e:
            sys.stderr.write('dashboard_stream: publish failed: %s\n' % e)

    def last_build(self):
        """When data.js was last built, on the monotonic clock: by this feed (built) or by the Board's own cycle, which
        this feed does not start (the time data.js was written). A data.js dated in the future is not counted."""
        try:
            age = time.time() - os.stat(os.path.join(self.out, 'data.js')).st_mtime
        except OSError:
            return self.built
        return self.built if age < 0 else max(self.built, time.monotonic() - age)

    def ticker(self):
        while True:
            time.sleep(TICK)
            now = config(self.main)
            if now != (self.cfg, None):
                self.changed(now[0][0] if now[1] is None else now[0])
            self.write()
            # A tick builds nothing while lines change nothing, but data.js carries writtenAt too: built again after
            # KEEP s, so the page sees this feed stop (its Live expires) without the 60 s cycle, and not before.
            if time.monotonic() - self.built >= KEEP:
                self.dirty.set()

    def run(self):
        os.makedirs(self.out, exist_ok=True)
        self.write()
        for target in [self.publisher, self.ticker] + [lambda r=r: self.follow(r) for r in self.recs]:
            threading.Thread(target=target, daemon=True).start()
        while True:
            time.sleep(3600)


def main(argv):
    if len(argv) != 3:
        sys.exit('usage: dashboard_stream.py <dashboard folder> <main checkout>')
    out, main = argv[1], argv[2]
    # The temp files of an earlier feed (it ended mid-write): nothing else removes them, and this one names its own.
    for name in glob.glob(os.path.join(glob.escape(out), '.stream.json.*')):
        try:
            os.remove(name)
        except OSError:
            pass
    for sig in (signal.SIGTERM, signal.SIGHUP, signal.SIGINT):
        signal.signal(sig, end)
    cfg, why = config(main)
    if cfg is None or why:
        # Nothing to follow: logged, and stream.json says why, with no record, so neither the page nor /units takes it
        # for a feed (each reads Conveyor itself, and the cycle's read says why on the page), and no earlier feed's
        # "the stream restarts on it" is left standing. Waiting here keeps the loop from restarting it.
        sys.stderr.write('dashboard_stream: no stream: %s\n' % why)
        t = iso(time.time())
        os.makedirs(out, exist_ok=True)
        put(out, {'host': cfg, 'reachable': None, 'error': why, 'records': None,
                  'stream': {'live': False, 'heardAt': None, 'since': t, 'error': 'the live stream cannot start: %s' % why, 'writtenAt': t}})
        while config(main) == (cfg, why):
            time.sleep(TICK)
        end()  # the host file changed: dashboard.sh --loop starts the stream again on it
    Feed(out, os.path.join(HERE, 'dashboard.sh'), main, *cfg).run()


if __name__ == '__main__':
    main(sys.argv)
