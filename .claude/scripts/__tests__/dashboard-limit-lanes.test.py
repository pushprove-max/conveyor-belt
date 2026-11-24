# SPDX-License-Identifier: Apache-2.0
"""lane_models() of dashboard_limit_pricing.py (loaded through dashboard_limit.py) with its kept file: a snapshot build
reads again only the research lane's transcripts that are new or changed, and its result is the one a full read gives.
Bugs caught: every build read every transcript of 30 days; a cache that kept a changed transcript's old count, missed
a new one, kept counting one older than 30 days, a kept line the window moved past, or one that can no longer be
read."""
import builtins
import importlib.util
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

NOW = time.time()
SINCE = NOW - 30 * 86400


def line(model, cwd, session, age=60):
    stamp = time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime(NOW - age))
    return json.dumps({'type': 'assistant', 'message': {'model': model}, 'cwd': cwd, 'sessionId': session,
                       'timestamp': stamp}) + '\n'


class LaneModelsKept(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.projects = os.path.join(self.tmp.name, 'projects')
        self.lane = os.path.join(self.tmp.name, 'lane')
        self.kept = os.path.join(self.tmp.name, 'priced.lanes')
        os.makedirs(os.path.join(self.projects, 'p'))
        self.a = self.write('a.jsonl', line('m-a', self.lane, 's1'))
        self.b = self.write('b.jsonl', line('m-b', self.lane, 's2'))

    def tearDown(self):
        self.tmp.cleanup()

    def write(self, name, text, mode='w'):
        path = os.path.join(self.projects, 'p', name)
        with open(path, mode) as f:
            f.write(text)
        return path

    def run_kept(self, since=SINCE):
        """lane_models() with the kept file: (its result, the transcripts it opened)."""
        opened, real = [], builtins.open

        def spy(path, *a, **k):
            if str(path).endswith('.jsonl'):
                opened.append(path)
            return real(path, *a, **k)
        d.open = spy  # the parts run in this module's namespace, so this open is the one lane_models() calls
        try:
            return d.lane_models(self.projects, self.lane, since, self.kept), sorted(opened)
        finally:
            del d.open

    def full(self, since=SINCE):
        return d.lane_models(self.projects, self.lane, since)

    def test_unchanged_transcripts_are_not_read_again(self):
        _, opened = self.run_kept()
        self.assertEqual(opened, sorted([self.a, self.b]), 'the first call, with no kept file, reads every transcript')
        again, opened = self.run_kept()
        self.assertEqual(opened, [], 'no transcript changed, yet the second call read them again')
        self.assertEqual(again, self.full())
        self.assertEqual(again, {'m-a': 1, 'm-b': 1})
        # A kept file that cannot be read is a miss: every transcript is read, and the result is a full read's.
        with open(self.kept, 'w') as f:
            f.write('not json')
        got, opened = self.run_kept()
        self.assertEqual((got, opened), (self.full(), sorted([self.a, self.b])), 'an unreadable kept file')

    def test_new_changed_and_old_transcripts(self):
        self.run_kept()
        self.write('a.jsonl', line('m-a2', self.lane, 's3'), 'a')
        c = self.write('c.jsonl', line('m-c', self.lane, 's4'))
        old = NOW - 31 * 86400
        os.utime(self.b, (old, old))
        got, opened = self.run_kept()
        self.assertEqual(opened, sorted([self.a, c]), 'only the changed and the new transcript are read')
        self.assertEqual(got, {'m-a': 1, 'm-a2': 1, 'm-c': 1}, 'a changed or new transcript is missed, or one older '
                         'than 30 days is still counted')
        self.assertEqual(got, self.full())

    def test_kept_line_ages_out_of_a_recent_transcript(self):
        # Bug caught: the cutoff applied once when the transcript was read, so a kept line stayed counted after the
        # 30-day window moved past it while its file (written to since) stayed recent.
        self.write('a.jsonl', line('m-old', self.lane, 's5', age=10 * 86400), 'a')
        got, _ = self.run_kept()
        self.assertEqual(got, {'m-a': 1, 'm-b': 1, 'm-old': 1}, 'a line inside the window is not counted')
        later = NOW - 5 * 86400  # the window has moved past the m-old line, not past the files
        got, opened = self.run_kept(later)
        self.assertEqual(opened, [], 'no transcript changed, yet the call read them again')
        self.assertEqual(got, {'m-a': 1, 'm-b': 1}, 'a kept line older than the window is still counted')
        self.assertEqual(got, self.full(later))

    @unittest.skipIf(os.geteuid() == 0, 'root reads a file of mode 000, so the file stays readable')
    def test_unreadable_transcript_counts_nothing(self):
        # Bug caught: chmod keeps a file's time and size, so a kept entry still counted a transcript a full read
        # can no longer open.
        self.run_kept()
        os.chmod(self.b, 0)
        try:
            got, _ = self.run_kept()
            self.assertEqual(got, {'m-a': 1}, 'a transcript that cannot be read is still counted from the kept file')
            self.assertEqual(got, self.full())
        finally:
            os.chmod(self.b, 0o644)


if __name__ == '__main__':
    unittest.main()
