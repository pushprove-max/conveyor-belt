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
         'queue': {'next': [], 'held': {}}, 'cost': {'today': 1}, 'awaitingDeploy': [], 'suites': [], 'snapshotAt': 't'}
SNAP = dict(DRAWN,
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


if __name__ == '__main__':
    unittest.main()
