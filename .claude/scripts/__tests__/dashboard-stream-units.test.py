# SPDX-License-Identifier: Apache-2.0
"""dashboard_stream.py writes units-feed.json, the feed /units reads: stream.json with each snapshot cut to what /units
draws. Bug (issue 1287): /units read stream.json whole, so the Tests page's history (tests, testActions) in each
snapshot grew the file past the 4 MiB cap /units reads under, and the pane showed no board."""
import importlib.util
import json
import os
import tempfile
import unittest

SCRIPT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'dashboard_stream.py')
spec = importlib.util.spec_from_file_location('dashboard_stream', SCRIPT)
ds = importlib.util.module_from_spec(spec)
spec.loader.exec_module(ds)

CAP = 4 * 1024 * 1024  # hooks/units.tsx MAX_DATA
DRAWN = {'health': {'state': 'ok'}, 'needsYou': {'waiting': [], 'blocked': []}, 'belt': [{'issue': 1}], 'landed': [], 'landedCount': 0,
         'queue': {'next': [], 'held': {}}, 'cost': {'today': 1}, 'awaitingDeploy': [], 'suites': [], 'snapshotAt': 't',
         # Bug: the feed dropped recordsNow, so /units counted the kept belt's rows against the cap, not loop.json's
         # count now. Of recordsNow the feed keeps building and waitingCount alone: /units reads no more of it (SNAP's
         # lists). Bug (issue 1679): the feed dropped waitingCount, so /units gave the old snapshot's waiting count.
         'recordsNow': {'building': 1, 'waitingCount': 3},
         # Bug (#1651): the feed had no test map, so /units asked the host for it on every fetch, over ssh on a build
         # machine. Of the map the feed keeps its state (mapstate()), not the Tests page's notMapped list.
         'testMap': {'state': 'running', 'done': 3, 'of': 8, 'started': 1700000000}}
SNAP = dict(DRAWN, testMap=dict(DRAWN['testMap'], tool='c8', notMapped=[{'file': f'n{i}', 'why': 'z' * 200} for i in range(50)]), recordsNow={'building': 1, 'waitingCount': 3, 'running': 2, 'landed': 1, 'blocked': [{'card': 'c1'}], 'waiting': [], 'started': [{'card': 'c2'}]},
            tests=[{'file': f'f{i}', 'log': 'x' * 1000} for i in range(4200)], testActions=[{'a': 'y' * 1000}] * 300,
            declined=[{'id': 'a', 'by': 'judge', 'time': 't1', 'why': 'long'}, {'id': 'b', 'by': 'owner', 'time': 't2'}], declinedRest=[],
            open={'umbrellas': [{'issue': 2}], 'held': [], 'issues': list(range(500))})


def read(out, name):
    with open(os.path.join(out, name)) as f:
        return os.path.getsize(f.name), json.load(f)


class UnitsFeed(unittest.TestCase):
    def test_a_snapshot_with_a_4_mb_tests_part_gives_a_feed_under_the_cap_with_what_the_pane_draws(self):
        with tempfile.TemporaryDirectory() as out:
            feed = ds.Feed(out, '/nonexistent/dashboard.sh', out, 'h', '/h', [('r', '/m')], 'h')
            feed._write({'host': 'h', 'records': [{'repo': 'r', 'snap': SNAP, 'readAt': 'now'}], 'stream': {'live': True}})
            whole_size, whole = read(out, 'stream.json')
            size, units = read(out, 'units-feed.json')
            self.assertGreater(whole_size, CAP, 'the fixture is not over the cap, so it proves nothing')
            self.assertEqual(whole['records'][0]['snap']['tests'], SNAP['tests'], 'the Board lost its tests part')
            self.assertLess(size, CAP, 'the units feed is over the cap /units reads under')
            self.assertEqual(units['records'][0], {'repo': 'r', 'readAt': 'now', 'snap': dict(
                DRAWN, declined=[{'id': 'a', 'by': 'judge', 'time': 't1'}], declinedRest=[], open={'umbrellas': [{'issue': 2}], 'held': []})},
                'the units feed record is not the drawn parts alone')
            self.assertEqual(units['stream'], {'live': True}, 'the units feed lost the stream state')

    def test_a_feed_with_no_record_is_written_as_it_is(self):
        # changed() writes records [] and a record not read yet is null: units_doc must pass both through.
        with tempfile.TemporaryDirectory() as out:
            feed = ds.Feed(out, '/nonexistent/dashboard.sh', out, 'h', '/h', [('r', '/m')], 'h')
            for records in ([], None):
                feed._write({'host': 'h', 'records': records, 'stream': {'live': False}})
                self.assertEqual(read(out, 'units-feed.json')[1]['records'], records, f'records {records!r} changed in the units feed')


class FeedMachine(unittest.TestCase):
    """Bug (issue 1667): the feed named its host alone, so /units could not tell a build machine reached at another ssh
    target under the same host name, and took that machine's test map for the session's project at the same path."""

    def test_the_feed_names_the_ssh_target_its_snapshots_come_from_and_none_on_one_machine(self):
        with tempfile.TemporaryDirectory() as out:
            for target in ('owner@oven', None):
                d = ds.Feed(out, '/nonexistent/dashboard.sh', out, 'lab', '/h', [('r', '/m')], target).doc()
                self.assertEqual([d['host'], d['ssh'], d['local']], ['lab', target, target is None], f'a feed with ssh target {target!r} gave {d!r}')


class LiveGap(unittest.TestCase):
    """Bug (#1585 review): a live line laid a running step's dollars over a belt card but not its known dollars and its
    gap, so /units showed the snapshot's "$0.00 + 1 step not priced" for the whole of a priced fix after such a step."""

    def test_a_live_line_gives_the_card_its_known_dollars_and_gap(self):
        snap = {'belt': [{'card': 'c1', 'usd': None, 'usdKnown': 0, 'notPriced': 1, 'estimate': False}]}
        over = {'c1': {'tokens': {'claude': 1000000, 'codex': 0}, 'usd': None, 'usdKnown': 2, 'notPriced': 1, 'reading': True, 'atEnd': False, 'live': {}}}
        b = ds.Feed.merged({'snap': snap, 'overlay': over})['belt'][0]
        self.assertEqual([b['usd'], b['usdKnown'], b['notPriced']], [None, 2, 1], f'the live line {over!r} over the belt {snap!r} gave {b!r}')


class ReadAt(unittest.TestCase):
    """Bug (R14): a snapshot's readAt was the line's arrival less its took, so a line that came late over ssh was dated
    after the start of the snapshot it holds, and a release reply between the two read as older than that snapshot."""
    T = 1700000000  # a whole second: snapshotAt has no fraction

    def take(self, snap, took, arrives):
        with tempfile.TemporaryDirectory() as out:
            feed = ds.Feed(out, '/nonexistent/dashboard.sh', out, 'h', '/h', [('r', '/m')], 'h')
            real = ds.time.time
            ds.time.time = lambda: arrives
            try:
                feed.take(feed.recs[0], {'type': 'snapshot', 'snap': snap, 'took': took})
            finally:
                ds.time.time = real
            return feed.recs[0]['readAt']

    def test_a_snapshot_is_dated_by_its_own_snapshotAt_whatever_the_line_s_delay(self):
        at = ds.iso(self.T)
        self.assertEqual(self.take({'snapshotAt': at}, 0.15, self.T + 0.25), self.T, 'a line 250 ms late was dated after its snapshotAt')

    def test_a_snapshot_with_no_usable_snapshotAt_is_dated_by_arrival_less_took(self):
        for snap in ({}, {'snapshotAt': 'x'}, {'snapshotAt': ds.iso(self.T + 60)}):
            self.assertAlmostEqual(self.take(snap, 0.15, self.T + 0.25), self.T + 0.10, msg=f'snap {snap!r} was not dated by took')


if __name__ == '__main__':
    unittest.main()
