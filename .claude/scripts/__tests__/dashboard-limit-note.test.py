# SPDX-License-Identifier: Apache-2.0
"""note() and fetch() of dashboard_limit_usage.py (loaded through dashboard_limit.py) on one account's shared cache:
a 429 one reader saved stays in force, with its own deadline, when another reader's success, started a second later,
lands after it. note() and fetch() are called with a fixed clock and no request: two real requests cannot be made to
land in that order."""
import contextlib
import importlib.util
import io
import json
import os
import sys
import tempfile
import time
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, '..'))
spec = importlib.util.spec_from_file_location('dashboard_limit', os.path.join(HERE, '..', 'dashboard_limit.py'))
d = importlib.util.module_from_spec(spec)
spec.loader.exec_module(d)

T = 1000.0
BODY = {'seven_day': {'utilization': 45.0}}


class NoteKeeps429(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.folder = os.path.join(self.tmp.name, '.claude')
        self.cache = d.account_cache(self.tmp.name, self.folder)[0]

    def tearDown(self):
        self.tmp.cleanup()

    def kept(self):
        with open(self.cache) as f:
            return json.load(f)

    def fetch_at(self, now):
        """fetch() on the cache at the clock `now`, with usage() stubbed: (exit code, the folders asked, stderr)."""
        asked = []
        d.usage = lambda f: asked.append(f) or ({'seven_day': {'utilization': 50.0}}, None)
        d.metadata, d.account_email = (lambda f: {}), (lambda m: None)
        real = time.time
        time.time = lambda: now
        try:
            with contextlib.redirect_stderr(io.StringIO()) as err, contextlib.redirect_stdout(io.StringIO()):
                rc = d.fetch(self.folder, self.tmp.name)
        finally:
            time.time = real
        return rc, asked, err.getvalue()

    # Bug it guards: the Board's 429 with no Retry-After kept next T+300; the guard's success from T+1 had next T+301,
    # later than the 429's, so the 429 was cleared and fetch(), which waits only on a 429, asked inside its window.
    def test_a_later_success_keeps_an_earlier_429(self):
        d.note(self.cache, {}, T, None, d.RATE_LIMITED)
        d.note(self.cache, {}, T + 1, BODY, None)
        k = self.kept()
        self.assertEqual((k['error'], k['next']), (d.RATE_LIMITED, T + d.ACCOUNT_TTL), k)
        self.assertEqual(k['body'], BODY, 'the success\'s figures are still kept')
        rc, asked, err = self.fetch_at(T + d.ACCOUNT_TTL - 1)
        self.assertEqual((rc, asked), (1, []), f"fetch() refuses inside the 429's window: {err}")
        self.assertTrue(err.startswith(d.RATE_LIMITED), err)

    # Bug it guards: a kept 429 took the later of its deadline and the success's (max), so a success from T+1 stretched
    # a 429 that named a 120 s wait to T+301, and fetch() still refused at T+120, when the endpoint takes reads again.
    def test_a_later_success_does_not_lengthen_a_named_429_wait(self):
        d.note(self.cache, {}, T, None, f'{d.RATE_LIMITED}; retry after 120 s')
        d.note(self.cache, {}, T + 1, BODY, None)
        self.assertEqual(self.kept()['next'], T + 120, self.kept())
        rc, asked, err = self.fetch_at(T + 120)
        self.assertEqual((rc, len(asked)), (0, 1), f'fetch() asks once the named wait is over: {err}')


if __name__ == '__main__':
    unittest.main()
