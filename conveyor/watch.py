#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""watch.py <state folder> <cards folder> <main checkout> -- `conveyor.sh watch`: the Conveyor stream.

It prints one JSON object a line on stdout, each line whole, until its reader goes (ssh closed: the write fails and it
ends). Every line has `type` and `at` (when it was printed):

  snapshot  {why: start | record | control | loop | github | refresh, snap (`conveyor.sh snapshot`), took (seconds from
            when the snapshot began to this line: what it read, the control record too, is that much older than the
            line), repoUrl (the checkout's GitHub address, null for none), lastPushAt (when the last push that worked
            was recorded, null for none)}. The first line is one; a new one follows a
            new record line, a retry, a push, a new guard reading (record), a control change (control), the loop's
            process starting or ending (loop), and a new answer from GitHub (github).
            Changes that come while one is built give one more after it, not one each. With no other for REFRESH
            seconds, one is made anyway (refresh): what counts on the clock alone (a card stuck for want of output,
            today's totals at midnight, a loop that ended in a way no notification shows) never stands still.
  live      {cards: {<card>: {tokens, usd, reading, atEnd, live: {turns, lastOutputAt, action}, files}}}: the running steps'
            live records (conveyor.sh keeps <worktree>.live up to date every LIVE seconds), laid over the last
            snapshot's belt as that snapshot would have them (tokens and dollars so far, the step's own included).
            Every card with a running step is in it; one whose step ended is left out. At most one a second, and only
            when something in it changed, and one right after every snapshot (its reader drops the live fields with
            each snapshot, which holds them as they were when it began).
  beat      nothing more, every BEAT seconds: the stream is alive though nothing changed.
  error     {error}: a snapshot failed (the end of what it said); the stream goes on, and the next change tries again.

What it watches, by looking every POLL seconds (one way on every system; each look is a stat of a few files): the state folder (cards.jsonl, retried.jsonl, control.json, pushed, maintest.json,
limit.jsonl, and loop.json: what the running loop makes of the control record), the cards folder (each *.live) and its own GitHub folder. GitHub is asked by `conveyor.sh github <folder>`
every GITHUB_EVERY seconds, in a thread of its own, and every snapshot runs with CONVEYOR_GITHUB naming that folder:
the snapshot reads GitHub's last answers and never waits on GitHub. The first snapshot waits for the first answer, at
most GITHUB_FIRST seconds, and not at all once a record, control or live record change comes: that change is on its way at once,
and GitHub's answer follows as a snapshot of its own. A snapshot also never asks for a new weekly limit reading (the loop takes those): it reads
the last one.
Whether the loop runs is whether the process loop.json names (its pid and start time, as `ps -o lstart=` gives it:
lib/portable.sh's p_started) is alive: looked at with each poll, and its start time asked of ps with each beat and
whenever loop.json changes, so a pid used again by another process is not taken for the loop.
Test seams: CONVEYOR_WATCH_BEAT, CONVEYOR_WATCH_GITHUB (GITHUB_EVERY), CONVEYOR_WATCH_GITHUB_FIRST,
CONVEYOR_WATCH_REFRESH (REFRESH).
"""
import datetime
import json
import os
import re
import shutil
import signal
import subprocess
import sys
import tempfile
import threading
import time

HERE = os.path.dirname(os.path.abspath(__file__))
SH = os.path.join(HERE, 'conveyor.sh')
sys.path.insert(0, os.path.join(HERE, '..', '.claude', 'scripts'))
try:
    from dashboard_limit import card_costs  # the one price table: the snapshot prices with it too
except Exception:  # noqa: BLE001 -- no table: the live dollars are unknown, never guessed
    card_costs = None

BEAT = float(os.environ.get('CONVEYOR_WATCH_BEAT') or 10)
GITHUB_EVERY = float(os.environ.get('CONVEYOR_WATCH_GITHUB') or 60)
GITHUB_FIRST = float(os.environ.get('CONVEYOR_WATCH_GITHUB_FIRST') or 10)
REFRESH = float(os.environ.get('CONVEYOR_WATCH_REFRESH') or 30)
LIVE_EVERY = 1.0
PROOF_LIVE = '.unfixed.live'  # mainrun/<card>.unfixed.live: the live record of a bug card's proof run (testrun.sh)
POLL = 0.5
SNAPSHOT_LIMIT = 120  # a snapshot that hangs is killed, and the next change tries again
STATE_FILES = {'cards.jsonl': 'record', 'retried.jsonl': 'record', 'pushed': 'record', 'limit.jsonl': 'record', 'maintest.json': 'record', 'control.json': 'control',
               'loop.json': 'loop'}
# Asked for while another waits, the one that says more is kept: a refresh is the least, then GitHub's.
RANK = {None: 0, 'refresh': 1, 'github': 2}
GITHUB_URL = re.compile(r'github\.com[:/]([A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+?)(\.git)?$')


def iso(t=None):
    return datetime.datetime.fromtimestamp(time.time() if t is None else t, datetime.timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')


class Out:
    """One line at a time on stdout. A write that fails means the reader has gone: the stream ends."""
    lock = threading.Lock()
    tmp = None  # the GitHub folder, removed however the stream ends

    @classmethod
    def end(cls, *_):
        if cls.tmp:
            shutil.rmtree(cls.tmp, ignore_errors=True)
        os._exit(0)

    @classmethod
    def send(cls, kind, **fields):
        line = json.dumps(dict(type=kind, at=iso(), **fields), separators=(',', ':')) + '\n'
        with cls.lock:
            try:
                sys.stdout.write(line)
                sys.stdout.flush()
            except (BrokenPipeError, OSError, ValueError):
                cls.end()


class Poll:
    """The watched files of each folder, looked at on demand: what changed since the last look."""
    def __init__(self):
        self.dirs = []  # (folder, kind, which of its file names count)
        self.seen = {}

    def add(self, path, kind, names):
        self.dirs.append((path, kind, names))

    def look(self):
        now = {}
        for path, kind, names in self.dirs:
            try:
                listed = os.listdir(path)
            except OSError:
                listed = []
            for name in listed:
                if names(name):
                    try:
                        st = os.stat(os.path.join(path, name))
                    except OSError:
                        continue
                    now[(kind, name)] = (st.st_ino, st.st_size, st.st_mtime_ns)
        return now

    def read(self):
        """[(kind of folder, file name)] of every watched file made, changed or removed since the last read."""
        now = self.look()
        out = [k for k in set(now) | set(self.seen) if now.get(k) != self.seen.get(k)]
        self.seen = now
        return out


def started(pid):
    """When <pid> started, as ps says it, the way lib/portable.sh's p_started asks: the two must match."""
    try:
        return subprocess.run(['ps', '-o', 'lstart=', '-p', str(pid)], capture_output=True, text=True, timeout=5,
                              env=dict(os.environ, LC_ALL='C')).stdout.strip() or None
    except (OSError, subprocess.TimeoutExpired):
        return None


class Stream:
    def __init__(self, state, cards, main):
        self.state, self.cards, self.main = state, cards, main
        self.github = tempfile.mkdtemp(prefix='conveyor-watch-')
        self.env = dict(os.environ, CONVEYOR_MAIN=main, CONVEYOR_CARDS=cards, CONVEYOR_GITHUB=self.github)
        self.cond = threading.Condition()
        self.emit = threading.RLock()  # a snapshot line and the live line after it go out together
        self.pending = None   # the reason of the snapshot asked for and not yet begun
        self.belt = {}        # the last snapshot's belt, by card: what a live line is laid over
        self.models = None  # None until the first snapshot
        self.sent_live = None
        self.repo_url = self.origin()
        self.started = False  # the first snapshot is asked for
        self.first_github = threading.Event()  # GitHub's first answer is in (or failed)
        self.loop_pid = None  # the pid of loop.json whose start time ps last confirmed
        self.loop = self.loop_runs(True)  # whether the loop's process ran when last looked
        self.snapped = time.monotonic()  # when the last snapshot began: REFRESH counts from it

    # ---- the pieces of a snapshot line that conveyor.sh snapshot does not give ----
    def origin(self):
        try:
            url = subprocess.run(['git', '-C', self.main, 'remote', 'get-url', 'origin'], capture_output=True, text=True, timeout=10).stdout.strip()
        except (OSError, subprocess.TimeoutExpired):
            return None
        m = GITHUB_URL.search(url)
        return 'https://github.com/%s' % m.group(1) if m else None

    def last_push(self):
        try:
            return iso(os.stat(os.path.join(self.state, 'pushed')).st_mtime)
        except OSError:
            return None

    # ---- snapshots: one at a time, in a thread of their own, so live lines keep coming while one is built ----
    def ask(self, why):
        with self.cond:
            if RANK.get(self.pending, 3) < RANK.get(why, 3):
                self.pending = why
            self.cond.notify()

    # ---- the loop's process: the one loop.json names ----
    def loop_runs(self, ask_ps):
        """True while it runs, False when no loop.json names a running one, None when loop.json cannot be read.
        A pid whose start time ps confirmed is taken as the loop while it lives, until ask_ps."""
        try:
            with open(os.path.join(self.state, 'loop.json')) as f:
                said = json.load(f)
        except FileNotFoundError:
            return False
        except (OSError, ValueError):
            return None
        pid = said.get('pid') if isinstance(said, dict) else None
        if not isinstance(pid, int) or isinstance(pid, bool) or pid <= 0:
            return False
        try:
            os.kill(pid, 0)
        except ProcessLookupError:
            self.loop_pid = None
            return False
        except PermissionError:
            pass
        if ask_ps or self.loop_pid != pid:
            self.loop_pid = pid if started(pid) == said.get('started') else None
        return self.loop_pid == pid

    def check_loop(self, ask_ps):
        runs = self.loop_runs(ask_ps)
        if runs is not None and runs != self.loop:
            self.loop = runs
            if self.started:
                self.ask('loop')

    def snapshots(self):
        while True:
            with self.cond:
                while self.pending is None:
                    self.cond.wait()
                why, self.pending = self.pending, None
                self.snapped = began = time.monotonic()
            try:
                run = subprocess.run(['bash', SH, 'snapshot'], capture_output=True, text=True, env=self.env, timeout=SNAPSHOT_LIMIT,
                                     stdin=subprocess.DEVNULL)
                snap = json.loads(run.stdout) if run.returncode == 0 else None
            except (OSError, subprocess.TimeoutExpired, ValueError) as e:
                run, snap = None, None
                err = str(e)
            if not isinstance(snap, dict):
                if run is not None:
                    err = (run.stderr.strip().splitlines() or ['exit %d' % run.returncode])[-1]
                Out.send('error', error=('the snapshot failed: %s' % err)[:300])
                continue
            extra = dict(repoUrl=self.repo_url, lastPushAt=self.last_push())
            # The snapshot holds the live records as they were when it began; a live line sent while it was built is
            # newer, and the reader drops its live fields with each snapshot. So the live fields as they are now
            # follow it at once, and no live line comes between the two.
            with self.emit:
                with self.cond:
                    self.belt = {b.get('card'): b for b in snap.get('belt') or [] if isinstance(b, dict)}
                    self.models = (snap.get('health') or {}).get('models') or {}
                    self.sent_live = None
                Out.send('snapshot', why=why, took=round(time.monotonic() - began, 3), snap=snap, **extra)
                self.send_live()

    # ---- GitHub, on its own timer ----
    def read_github(self):
        before = self.github_files()
        try:
            subprocess.run(['bash', SH, 'github', self.github], capture_output=True, env=dict(self.env, CONVEYOR_GITHUB=''),
                           timeout=max(60, GITHUB_EVERY), stdin=subprocess.DEVNULL)
        except (OSError, subprocess.TimeoutExpired):
            pass
        return self.github_files() != before

    def github_files(self):
        out = {}
        for name in ('issues', 'labelled', 'gh', 'ghreach'):
            try:
                with open(os.path.join(self.github, name), 'rb') as f:
                    out[name] = f.read()
            except OSError:
                out[name] = None
        return out

    def githubs(self):
        changed = self.read_github()
        self.first_github.set()
        if changed and self.started:
            self.ask('github')  # the first snapshot went without it
        while True:
            time.sleep(GITHUB_EVERY)
            if self.read_github():
                self.ask('github')

    def start(self):
        if not self.started:
            self.started = True
            self.ask('start')

    # ---- live records ----
    def live_cards(self):
        """{card: the belt fields its live record changes}, for every card of the last snapshot with a running step."""
        out = {}
        with self.cond:
            belt, models = dict(self.belt), dict(self.models or {})
        try:
            names = [n for n in os.listdir(self.cards) if n.endswith('.live')]
        except OSError:
            names = []
        for name in names:
            card = name[:-5]
            entry = belt.get(card)
            if not entry or entry.get('landed'):
                continue
            try:
                with open(os.path.join(self.cards, name)) as f:
                    live = json.load(f)
            except (OSError, ValueError):
                continue
            done = entry.get('done') or {}
            if not isinstance(live, dict) or live.get('step') != done.get('step'):
                continue  # a live record counts only while the card's last line is the start of that step
            out[card] = self.lay(live, done, models)
        # A bug card's proof run (testrun.sh bugproof()) has a live record of its own, in mainrun/<card>.unfixed.live;
        # it counts while the last snapshot shows that card's proof (snapshot.sh: no step started, the record there).
        try:
            names = [n for n in os.listdir(os.path.join(self.cards, 'mainrun')) if n.endswith(PROOF_LIVE)]
        except OSError:
            names = []
        for name in names:
            card = name[:-len(PROOF_LIVE)]
            entry = belt.get(card)
            if not entry or entry.get('step') != 'proof' or card in out:
                continue
            try:
                with open(os.path.join(self.cards, 'mainrun', name)) as f:
                    live = json.load(f)
            except (OSError, ValueError):
                continue
            if isinstance(live, dict):
                out[card] = self.lay(dict(live, usage=None), entry.get('done') or {}, models)  # it runs no model
        return out

    @staticmethod
    def lay(live, done, models):
        u = live.get('usage') if isinstance(live.get('usage'), dict) else None
        tokens = dict(done.get('tokens') or {'claude': 0, 'codex': 0})
        if u:
            n = lambda k: u.get(k) if isinstance(u.get(k), (int, float)) else 0  # noqa: E731
            if live.get('step') == 'review':
                tokens['codex'] = tokens.get('codex', 0) + n('input') + n('output')
            else:
                tokens['claude'] = tokens.get('claude', 0) + n('input') + n('write') + n('write1h') + n('output')
        reading = bool(done.get('reading')) or bool(u and sum(v for v in u.values() if isinstance(v, (int, float))) > 0)
        live_usd = None
        if u and card_costs is not None:
            try:
                live_usd = card_costs({'cards': [{'steps': [], 'models': models, 'live': dict(live)}]})['cards'][0]['live']['usd']
            except Exception:  # noqa: BLE001
                live_usd = None
        base = done.get('usd')
        usd = None if not reading or base is None or (u is not None and live_usd is None) else round(base + (live_usd or 0), 4)
        # atEnd: no reading, and the running Claude session's answers all report usage 0 (session.sh's zero): its
        # route gives the cost only when the step ends (#391).
        return {'tokens': tokens, 'usd': usd, 'reading': reading, 'atEnd': not reading and live.get('zero') is True,
                'live': {'turns': live.get('turns'), 'lastOutputAt': live.get('last'), 'action': live.get('action')},
                'files': live.get('files') if isinstance(live.get('files'), dict) else None}

    def send_live(self):
        with self.emit:  # read and sent as one, so a line laid over an older snapshot never follows a newer one
            cards = self.live_cards()
            with self.cond:
                if self.models is None or cards == self.sent_live:  # nothing before the first snapshot: it holds them
                    return
                self.sent_live = cards
            Out.send('live', cards=cards)

    # ---- the stream ----
    def run(self):
        files = Poll()
        os.makedirs(self.cards, exist_ok=True)
        files.add(self.state, 'state', lambda n: n in STATE_FILES)
        files.add(self.cards, 'cards', lambda n: n.endswith('.live'))
        files.add(os.path.join(self.cards, 'mainrun'), 'proof', lambda n: n.endswith(PROOF_LIVE))
        files.read()  # what is there now is no change
        proofs = {n for k, n in files.seen if k == 'proof'}  # the proof runs' live records there now
        threading.Thread(target=self.snapshots, daemon=True).start()
        threading.Thread(target=self.githubs, daemon=True).start()
        # The first snapshot waits for GitHub's first answer (a snapshot without it has no queue) for at most
        # GITHUB_FIRST seconds, and never holds up a change: the notifications are read meanwhile, and the first one
        # starts it.
        first_by = time.monotonic() + GITHUB_FIRST
        live_due, live_last, beat = False, 0.0, time.monotonic() + BEAT
        while True:
            now = time.monotonic()
            if not self.started and (self.first_github.is_set() or now >= first_by):
                self.start()
            wait = min(beat, self.snapped + REFRESH, now + POLL) - now
            if live_due:
                wait = min(wait, live_last + LIVE_EVERY - now)
            if not self.started:
                wait = min(wait, 0.05)
            time.sleep(max(0.0, wait))
            for kind, name in files.read():
                if kind == 'state':
                    if name == 'loop.json':
                        self.loop = self.loop_runs(True)  # its snapshot follows, as for any state file
                    if self.started:
                        self.ask(STATE_FILES[name])
                    else:
                        self.start()  # the change goes now, in the first snapshot
                else:
                    if not self.started:
                        self.start()  # a running step's fields go now, in the live line right after the first snapshot
                    elif kind == 'proof' and ((kind, name) in files.seen) != (name in proofs):
                        self.ask('record')  # a proof run began or ended: the belt's step changes, which only a snapshot says
                    if kind == 'proof':
                        proofs = {n for k, n in files.seen if k == 'proof'}
                    live_due = True
            self.check_loop(False)  # a loop whose process ended changes no file
            now = time.monotonic()
            if live_due and now >= live_last + LIVE_EVERY:
                live_due, live_last = False, now
                self.send_live()
            if self.started and now >= self.snapped + REFRESH:
                self.snapped = now  # asked once: the snapshot thread sets it again when it begins
                self.ask('refresh')
            if now >= beat:
                beat = now + BEAT
                self.check_loop(True)  # a pid that ended and was used again since the last poll is found here
                Out.send('beat')


def main(argv):
    if len(argv) != 4:
        sys.exit('usage: watch.py <state folder> <cards folder> <main checkout>')
    state, cards, main = argv[1:]
    if not os.path.isdir(state):
        sys.exit('conveyor: no state folder at %s' % state)
    s = Stream(state, cards, main)
    Out.tmp = s.github
    for sig in (signal.SIGTERM, signal.SIGHUP, signal.SIGINT):
        signal.signal(sig, Out.end)
    try:
        s.run()
    except Exception as e:  # noqa: BLE001 -- said, never a silent end of the stream
        sys.stderr.write('conveyor: watch stopped: %s\n' % e)
        shutil.rmtree(s.github, ignore_errors=True)
        os._exit(1)


if __name__ == '__main__':
    main(sys.argv)
