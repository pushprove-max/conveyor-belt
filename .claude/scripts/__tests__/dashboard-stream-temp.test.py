# SPDX-License-Identifier: Apache-2.0
"""dashboard_stream.py leaves no .stream.json.<n> temp file: each process names its own by thread id, so the ones a
failed write or an ended feed left added up in the dashboard folder (22 MB of them in two days)."""
import glob
import importlib.util
import os
import subprocess
import sys
import tempfile
import time
import unittest

SCRIPT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'dashboard_stream.py')
spec = importlib.util.spec_from_file_location('dashboard_stream', SCRIPT)
ds = importlib.util.module_from_spec(spec)
spec.loader.exec_module(ds)


def temps(out):
    return glob.glob(os.path.join(out, '.stream.json.*'))


class StreamTemps(unittest.TestCase):
    def test_a_failed_write_leaves_no_temp_file(self):
        # stream.json is a folder, so the rename fails after the temp file is written in full.
        with tempfile.TemporaryDirectory() as out:
            os.mkdir(os.path.join(out, 'stream.json'))
            feed = ds.Feed(out, '/nonexistent/dashboard.sh', out, 'h', '/h', [('r', '/m')], 'h')
            sys.stderr, err = open(os.devnull, 'w'), sys.stderr
            try:
                feed._write({'records': []})
            finally:
                sys.stderr.close()
                sys.stderr = err
            self.assertEqual(temps(out), [], 'a failed write left its temp file')

    def test_the_feed_removes_old_temp_files_at_start(self):
        with tempfile.TemporaryDirectory() as t:
            out, cfg = os.path.join(t, 'out'), os.path.join(t, 'cfg')
            os.mkdir(out)
            os.mkdir(cfg)
            for n in ('123', '456'):
                with open(os.path.join(out, '.stream.json.' + n), 'w') as f:
                    f.write('{"partial":')
            with open(os.path.join(out, 'stream.json'), 'w') as f:
                f.write('{}')
            # No host file anywhere: the feed starts and waits for one, so it writes nothing of its own.
            p = subprocess.Popen([sys.executable, SCRIPT, out, t], env=dict(os.environ, XDG_CONFIG_HOME=cfg),
                                 stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            try:
                end = time.monotonic() + 10
                while temps(out) and time.monotonic() < end:
                    time.sleep(0.05)
                self.assertEqual(temps(out), [], 'the feed kept the temp files an earlier one left')
                self.assertTrue(os.path.exists(os.path.join(out, 'stream.json')), 'the feed removed stream.json itself')
            finally:
                p.kill()
                p.wait()


if __name__ == '__main__':
    unittest.main()
