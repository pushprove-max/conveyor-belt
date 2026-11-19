# SPDX-License-Identifier: Apache-2.0
"""How often dashboard_stream.py builds data.js. While a step runs the host sends a live line every second, most of
them changing only the card's figures (tokens, dollars, reading, replies, last output); each build is a bash and
three jq over up to a megabyte, so such lines are built at most every SLOW s. A change the owner acts on (a step, an
action, a snapshot, a retry, a failed snapshot, a stream that goes down) is still built within GAP s. The feed runs on
a fake clock, so its minutes take no time."""
import importlib.util
import os
import sys
import tempfile
import threading
import unittest

SCRIPT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'dashboard_stream.py')
spec = importlib.util.spec_from_file_location('dashboard_stream', SCRIPT)
ds = importlib.util.module_from_spec(spec)
spec.loader.exec_module(ds)

START = 1000.0


class Stop(Exception):
    pass


class Clock:
    """The feed's time module. Each wait moves it on a second at a time; at each whole second `second(n)` sends the
    host's line for that second. Past `until` the publisher is stopped."""
    def __init__(self, until):
        self.t, self.until, self.second = START, until, lambda n: None

    def monotonic(self):
        return self.t

    def time(self):
        return self.t

    def sleep(self, s, done=lambda: False):
        end = self.t + s
        while self.t < end and not done():
            self.t = min(end, float(int(self.t) + 1))
            if self.t == int(self.t):
                self.second(int(self.t - START))
            if self.t > self.until:
                raise Stop


class Event(threading.Event):
    """An Event whose wait runs on the fake clock: the publisher's waits are where the clock moves."""
    def __init__(self, clock):
        super().__init__()
        self.clock = clock

    def wait(self, timeout=None):
        self.clock.sleep(float('inf') if timeout is None else timeout, self.is_set)
        return self.is_set()


def live(n, action='Bash: npm test', cards=('c1',), files=None, at_end=False):
    """A live line in which only the tokens and usd differ for each n."""
    return {'type': 'live', 'cards': {c: {'tokens': 1000 * n, 'usd': n / 100, 'reading': True, 'atEnd': at_end, 'files': files or {},
                                          'live': {'turns': 3, 'lastOutputAt': '2026-01-01T00:00:00Z', 'action': action}}
                                      for c in cards}}


class Pace(unittest.TestCase):
    def feed(self, seconds, line):
        """Runs the publisher for `seconds` on the fake clock, the host sending line(n, feed, rec) at second n (None:
        nothing). Gives the build times as seconds from the start, and how many lines came and stream.json writes."""
        out = tempfile.TemporaryDirectory()
        self.addCleanup(out.cleanup)
        clock = Clock(START + seconds)
        builds, puts, lines = [], [], []
        self.builds = builds  # for a line that is sent after a build
        ds.time = clock
        ds.subprocess.run = lambda *a, **k: builds.append(clock.t - START) or type('R', (), {'returncode': 0})()
        put = ds.put
        ds.put = lambda o, d: puts.append(d) or put(o, d)
        self.addCleanup(setattr, ds, 'put', put)
        f = ds.Feed(out.name, '/nowhere/dashboard.sh', out.name, 'h', '/h', [('r', '/h')], None)
        f.dirty, f.urgent = Event(clock), Event(clock)
        rec = f.recs[0]

        def second(n):
            ev = line(n, f, rec)
            if ev is not None:
                lines.append(ev)
                f.take(rec, ev)
        clock.second = second
        f.take(rec, {'type': 'snapshot', 'snap': {'belt': [{'card': 'c1'}]}})
        lines.append('snapshot')
        try:
            while True:
                f.publish_next()
        except Stop:
            pass
        return builds, len(lines), len(puts)

    def test_figures_only_build_at_most_every_15_s(self):
        # Bug caught: a running card's figures change every second, and each change built data.js again 2 s after
        # the last build: 30 builds a minute of a megabyte feed for a cost figure.
        builds, lines, puts = self.feed(62, lambda n, f, rec: live(n) if n <= 60 else {'type': 'beat'})
        # 0: the snapshot; 2: the first live line, which replaces the snapshot's figures (no overlay to compare).
        self.assertEqual(builds[:2], [0, 2], builds)
        # Then every 15 s exactly: closer is the bug, further leaves the figures behind for longer than docs/board.md says.
        apart = [b - a for a, b in zip(builds[1:], builds[2:])]
        self.assertEqual(apart, [15.0] * 4, 'figures-only lines were not built 15 s apart: %s' % builds)
        # Each line, beats too, is in stream.json at once: /units reads it, not data.js.
        self.assertEqual(puts, lines, 'stream.json was not written for each line')

    def test_other_changes_build_2_s_after_the_last_build(self):
        # Bug caught: a change the owner acts on waiting behind figures-only lines for up to 15 s, or built sooner than
        # GAP after the last build. Each change comes 1 s after a build, between figures-only lines, so it is built at
        # that build + 2 s: + 15 s if it is taken for figures only, + 1 s if GAP is not kept.
        state = {'action': 'Bash: npm test', 'cards': ('c1',), 'files': {}, 'at_end': False}
        todo = [('a new action', {'action': 'Edit: hooks/units.tsx'}),
                ('a snapshot', {'type': 'snapshot', 'snap': {'belt': [{'card': 'c1'}]}}),
                ('a new card', {'cards': ('c1', 'c2')}),
                ('a changed files list', {'files': {'hooks/units.tsx': {'added': 3}}}),
                ('a card at its end', {'at_end': True}),
                ('a retry', {'type': 'retried', 'cards': [{'card': 'c3', 'issue': 3, 'at': None}]}),
                ('a failed snapshot', {'type': 'error', 'error': 'the snapshot failed'}),
                ('a stream that went down', None)]
        sent = []

        def line(n, f, rec):
            # Only a beat in the second after a change, when it is due to be built: a live line then could build it
            # instead (the first one after a snapshot has no overlay to compare, so it is never figures only).
            if sent and sent[-1][1] == n - 1:
                return {'type': 'beat'}
            if todo and self.builds[-1] == n - 1 and (not sent or sent[-1][1] < n - 1):
                what, ch = todo.pop(0)
                sent.append((what, n))
                if ch is None:
                    return f.down(rec, 'h: the stream ended (exit 1)', False)
                if 'type' in ch:
                    return ch
                state.update(ch)
            return live(n, **state)
        builds, _, _ = self.feed(60, line)
        self.assertEqual(todo, [], 'not every change was sent: %s' % builds)
        for what, n in sent:
            self.assertIn(n - 1 + ds.GAP, builds, '%s was not built 2 s after the last build: %s' % (what, builds))
            self.assertNotIn(n, builds, '%s was built sooner than 2 s after the last build: %s' % (what, builds))

    def test_a_change_ends_a_figures_only_wait(self):
        # Bug caught: a change that comes while the publisher already holds figures-only lines for SLOW s waits out
        # the rest of those 15 s (a sleep in place of the wait on urgent). Figures-only lines from 3 s start that
        # wait after the build at 2; an action comes at 7 and a snapshot at 12, each well past GAP, so each is built
        # in its own second, not at 17.
        def line(n, f, rec):
            if n == 12:
                return {'type': 'snapshot', 'snap': {'belt': [{'card': 'c1'}]}}
            return live(n, action='Edit: hooks/units.tsx' if n >= 7 else 'Bash: npm test')
        builds, _, _ = self.feed(13, line)
        self.assertEqual(builds, [0, 2, 7, 12], 'a change did not end the figures-only wait: %s' % builds)

    def test_the_cycle_build_starts_the_wait(self):
        # Bug caught: the Board's own cycle builds data.js at 10 s, and a figures-only line was built again at 17 s,
        # 15 s after this feed's last build but 7 s after the cycle's.
        def line(n, f, rec):
            if n == 10:
                path = os.path.join(f.out, 'data.js')
                open(path, 'w').close()
                os.utime(path, (START + 10, START + 10))
            return live(n)
        builds, _, _ = self.feed(30, line)
        self.assertEqual(builds, [0, 2, 25], 'a figures-only line was built sooner than 15 s after the cycle: %s' % builds)

    def test_figures_only(self):
        # Bug caught: a change to the files or atEnd of a card taken for figures only waits up to 15 s; a change to
        # reading, turns or lastOutputAt taken for more builds every 2 s while a step runs.
        old = live(1)['cards']
        for key, value, figures in [('reading', False, True), ('files', {'a.py': {}}, False), ('atEnd', True, False),
                                    ('turns', 4, True), ('lastOutputAt', '2026-01-01T00:00:09Z', True), ('action', 'Read', False)]:
            new = live(2)['cards']
            (new['c1'] if key in new['c1'] else new['c1']['live'])[key] = value
            self.assertEqual(ds.figures_only(old, new), figures, 'a change to %s' % key)


if __name__ == '__main__':
    unittest.main()
