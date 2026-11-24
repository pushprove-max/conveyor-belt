# SPDX-License-Identifier: Apache-2.0
"""The caches of dashboard_limit.py that name transcript paths, working folders and session ids are written so that
only their owner can read them, whatever the umask.
Bug caught: requests(), codex_requests() and lane_models()' kept file were written with open(tmp, "w"), so under a
umask of 0002 or 0022 any local user could read which transcripts, folders and sessions the owner had."""
import importlib.util
import json
import os
import stat
import sys
import tempfile
import time
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, '..'))
spec = importlib.util.spec_from_file_location('dashboard_limit', os.path.join(HERE, '..', 'dashboard_limit.py'))
d = importlib.util.module_from_spec(spec)
spec.loader.exec_module(d)

NOW = time.time()
SINCE = NOW - 7 * 86400


class CacheMode(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.src = os.path.join(self.tmp.name, 'src')
        self.lane = os.path.join(self.tmp.name, 'lane')
        os.makedirs(self.src)
        # One Claude Code transcript of the lane: a model, a working folder and a session id, as the caches keep them.
        with open(os.path.join(self.src, 's.jsonl'), 'w') as f:
            f.write(json.dumps({'type': 'assistant', 'cwd': self.lane, 'sessionId': 's1', 'requestId': 'r1',
                                'timestamp': time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime(NOW - 60)),
                                'message': {'model': 'm', 'usage': {'input_tokens': 1, 'output_tokens': 1}}}) + '\n')
        self.cache = os.path.join(self.tmp.name, 'cache.json')
        # A cache an earlier version left readable by others: the new write must not keep its mode.
        with open(self.cache, 'w') as f:
            f.write('{}')
        os.chmod(self.cache, 0o664)
        # The writer cases start with no <cache>.<pid>, as a fresh Board run does: the writer must create it.
        self.left = f'{self.cache}.{os.getpid()}'
        self.umask = os.umask(0o002)  # the build host's umask: new files are 0664 unless the writer narrows them

    def tearDown(self):
        os.umask(self.umask)
        self.tmp.cleanup()

    def assertFresh(self, what):
        # Bug caught: every writer case once opened a <cache>.<pid> setUp() had made, so a private_open() that cannot
        # create the file (no O_CREAT: FileNotFoundError on a fresh run) passed them all.
        self.assertFalse(os.path.exists(self.left), f'{what}: {self.left} exists before the write')

    def assertPrivate(self, what, field=None):
        # `field`: the part of the written cache that must hold the fixture's session id as a value (not a file name
        # such as s1.jsonl), so a call that cached no session cannot pass; None for a call that returns before it writes.
        if field:
            with open(self.cache) as f:
                kept = json.dumps(json.load(f).get(field))
            self.assertIn('"s1"', kept, f'{what}: {field} of {self.cache} holds no session id s1: {kept}')
        mode = stat.S_IMODE(os.stat(self.cache).st_mode)
        self.assertEqual(mode, 0o600, f'{what} left {self.cache} with mode {oct(mode)} under umask 0002')

    def test_requests_cache(self):
        self.assertFresh('requests()')
        d.requests(self.src, self.cache, SINCE, NOW)
        self.assertPrivate('requests()', 'session')

    def leave_tmp(self):
        # A <cache>.<pid> an interrupted earlier write left at 0664.
        open(self.left, 'w').close()
        os.chmod(self.left, 0o664)

    def codex_session(self):
        # Bug caught: a Claude transcript gave codex_requests() no response, so its session map stayed empty and the
        # case passed on the file name s1.jsonl alone. A Codex session file: one response, its file name the session.
        os.unlink(os.path.join(self.src, 's.jsonl'))
        with open(os.path.join(self.src, 's1.jsonl'), 'w') as f:
            f.write(json.dumps({'type': 'session_meta', 'payload': {'cwd': self.lane}}) + '\n')
            f.write(json.dumps({'type': 'token_usage_record',
                                'timestamp': time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime(NOW - 60)),
                                'payload': {'response_id': 'r1', 'usage': {'input_tokens': 1, 'output_tokens': 1}}}) + '\n')

    def test_codex_requests_cache(self):
        self.codex_session()
        self.assertFresh('codex_requests()')
        d.codex_requests([self.src], self.cache, SINCE, NOW)
        self.assertPrivate('codex_requests()', 'session')

    def test_lane_models_kept(self):
        self.assertFresh('lane_models()')
        d.lane_models(self.src, self.lane, SINCE, self.cache)
        self.assertPrivate('lane_models()', 'files')

    # Bug caught: a <cache>.<pid> an interrupted earlier write left at 0664 keeps its mode through O_CREAT, and the
    # rename makes it the cache: each writer must narrow the file it opens, not only a file it creates. One case per
    # writer, as each opens its own temporary file and could set the mode only when it creates it.
    def test_requests_leftover_tmp(self):
        self.leave_tmp()
        d.requests(self.src, self.cache, SINCE, NOW)
        self.assertPrivate('requests() over a <cache>.<pid> left at 0664', 'session')

    def test_codex_requests_leftover_tmp(self):
        self.codex_session()
        self.leave_tmp()
        d.codex_requests([self.src], self.cache, SINCE, NOW)
        self.assertPrivate('codex_requests() over a <cache>.<pid> left at 0664', 'session')

    def test_lane_models_leftover_tmp(self):
        self.leave_tmp()
        d.lane_models(self.src, self.lane, SINCE, self.cache)
        self.assertPrivate('lane_models() over a <cache>.<pid> left at 0664', 'files')

    # Bug caught: a call that returns before it writes the cache (nothing to read, nothing new) left a cache an earlier
    # version wrote at 0664 readable by others.
    def test_requests_early_return(self):
        self.assertIsNone(d.requests(os.path.join(self.tmp.name, 'none'), self.cache, SINCE, NOW))
        self.assertPrivate('requests() with no projects folder')

    def test_codex_requests_early_return(self):
        self.assertIsNone(d.codex_requests([os.path.join(self.tmp.name, 'none')], self.cache, SINCE, NOW))
        self.assertPrivate('codex_requests() with no sessions folder')

    # Bug caught: lane_models() with nothing new writes no file, and with no research lane in the part (the host record
    # dropped it) card_costs() never calls it, so a <kept>.lanes an earlier version left at 0664 stayed readable by
    # others. card_costs() narrows it for every snapshot, research lane or not.
    def test_card_costs_no_research_lane(self):
        kept = os.path.join(self.tmp.name, 'cards.jsonl.priced')
        os.rename(self.cache, f'{kept}.lanes')
        self.cache = f'{kept}.lanes'
        lines, dest = os.path.join(self.tmp.name, 'cards.jsonl'), os.path.join(self.tmp.name, 'priced.jsonl')
        open(lines, 'w').close()
        part = {'since': time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime(SINCE)), 'cards': []}
        d.card_costs(part, lines, kept, dest)
        self.assertPrivate('card_costs() with no research in the part')


if __name__ == '__main__':
    unittest.main()
