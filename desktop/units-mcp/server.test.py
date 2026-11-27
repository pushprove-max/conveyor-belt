# SPDX-License-Identifier: Apache-2.0
"""server.py, /units for Claude Desktop, over stdio as Desktop runs it: initialize, tools/list, tools/call units and
resources/read, with the project's installed fetch (hooks/units-fetch.sh) giving the fixture answer
fixtures/units-answer.txt and the Board's folder a weekly limit. The text must be the head /units prints for the same
answer and limit (hooks/sources.ts, run here by node), the tool must name the view,
and the structured content must carry each record's snapshot with its own fields."""
import datetime
import importlib.util
import json
import os
import shutil
import subprocess
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
FIXTURE = os.path.join(HERE, 'fixtures', 'units-answer.txt')
URI = 'ui://conveyor/units'
spec = importlib.util.spec_from_file_location('units_server', os.path.join(HERE, 'server.py'))
server = importlib.util.module_from_spec(spec)
spec.loader.exec_module(server)

# What /units prints for the answer: hooks/sources.ts tableText at 56 columns (/units' width where the session gives
# none), its head lines (as many as headerModel gives). Node loads sources.ts with its imports' .ts added.
HOOK = """export async function resolve(s, c, next) {
  try { return await next(s, c) } catch (e) { if (s.startsWith('.') && !/\\.[cm]?[jt]sx?$/.test(s)) return next(s + '.ts', c); throw e }
}"""
HEAD = """import { register } from 'node:module'
import { readFileSync } from 'node:fs'
register('./hook.mjs', import.meta.url)
const [root, fixture, limit] = process.argv.slice(2)
const s = await import(`${root}/hooks/sources.ts`)
const f = s.parseFetch(readFileSync(fixture, 'utf8'))
const st = { now: Date.now(), ...s.boardOf(f), limit: s.parseLimit(readFileSync(limit, 'utf8')), fast: f.fast, research: { state: 'none' }, foreman: s.foremanOf(f.foreman, '') }
process.stdout.write(s.tableText(st, 56).split('\\n').slice(0, s.headerModel(st, st.snap, 56).length).join('\\n'))
"""


def units_head(tmp, limit):
    for name, text in (('hook.mjs', HOOK), ('head.mjs', HEAD)):
        with open(os.path.join(tmp, name), 'w') as f:
            f.write(text)
    r = subprocess.run(['node', '--no-warnings', os.path.join(tmp, 'head.mjs'), ROOT, FIXTURE, limit],
                       capture_output=True, text=True, timeout=60, check=False)
    assert r.returncode == 0, f'sources.ts did not draw /units for {FIXTURE}: {r.stderr}'
    return r.stdout


class StdioSession(unittest.TestCase):
    """One server, one session: every case reads its answers."""

    @classmethod
    def setUpClass(cls):
        cls.tmp = tempfile.mkdtemp()
        plugin, cls.checkout = os.path.join(cls.tmp, 'plugin'), os.path.join(cls.tmp, 'project')
        os.makedirs(os.path.join(plugin, 'desktop', 'units-mcp'))
        os.makedirs(os.path.join(plugin, 'hooks'))
        for f in ('server.py', 'view.html'):
            shutil.copy(os.path.join(HERE, f), os.path.join(plugin, 'desktop', 'units-mcp', f))
        # units.tsx, whose FEED_DIR script names the Board's folder for the server as for /units.
        shutil.copy(os.path.join(ROOT, 'hooks', 'units.tsx'), os.path.join(plugin, 'hooks', 'units.tsx'))
        home, data, board = (os.path.join(cls.tmp, d) for d in ('home', 'data', 'board'))
        # The project follows the plugin's main and this machine took COMMIT, installed under the data folder: /units
        # runs that install's fetch (units.tsx fetchPath). It gives the fixture answer, only when run as /units runs it
        # (in the checkout given, with no mode); the plugin's own fetch beside the server gives nothing.
        commit = '0123456789abcdef0123456789abcdef01234567'
        installed = os.path.join(data, 'conveyor', 'versions', commit, 'hooks')
        for d in (installed, os.path.join(cls.checkout, '.conveyor'), os.path.join(cls.checkout, '.git'), board,
                  os.path.join(home, '.config', 'systemd', 'user'), os.path.join(home, 'Library', 'LaunchAgents')):
            os.makedirs(d)
        for path, obj in (('.conveyor/project.json', {'plugin': {'follow': 'main'}}), ('.git/conveyor-engine.json', {'commit': commit})):
            with open(os.path.join(cls.checkout, path), 'w') as f:
                json.dump(obj, f)
        with open(os.path.join(installed, 'units-fetch.sh'), 'w') as f:
            f.write(f'[ "$PWD" = {json.dumps(cls.checkout)} ] && [ $# = 0 ] && cat {json.dumps(FIXTURE)}\n')
        with open(os.path.join(plugin, 'hooks', 'units-fetch.sh'), 'w') as f:
            f.write('exit 0\n')
        # The Board's job names its folder, which holds the weekly limit: 42.6% used, reset 3d 5h 30m from now (the
        # server reads the limit at the time it runs, so the reset is put well inside its hour).
        resets = datetime.datetime.now(datetime.UTC) + datetime.timedelta(days=3, hours=5, minutes=30)
        cls.limit = os.path.join(board, 'limit.json')
        with open(cls.limit, 'w') as f:
            json.dump({'limit': {'usedPct': 42.6, 'resetsAt': resets.strftime('%Y-%m-%dT%H:%M:%SZ')}}, f)
        with open(os.path.join(home, '.config', 'systemd', 'user', 'dashboard.service'), 'w') as f:
            f.write(f'Environment="CONVEYOR_DASHBOARD_DIR={board}"\n')
        with open(os.path.join(home, 'Library', 'LaunchAgents', 'com.conveyor.dashboard.plist'), 'w') as f:
            f.write('<?xml version="1.0" encoding="UTF-8"?>\n<plist version="1.0"><dict><key>ProgramArguments</key>'
                    '<array><string>/bin/bash</string><string>/x/scripts/dashboard.sh</string></array>'
                    f'<key>EnvironmentVariables</key><dict><key>CONVEYOR_DASHBOARD_DIR</key><string>{board}</string></dict></dict></plist>\n')
        env = {**os.environ, 'HOME': home, 'XDG_DATA_HOME': data}
        msgs = [{'id': 1, 'method': 'initialize', 'params': {'protocolVersion': '2025-06-18', 'capabilities': {}, 'clientInfo': {'name': 't', 'version': '0'}}},
                {'method': 'notifications/initialized'},
                {'id': 2, 'method': 'tools/list'},
                {'id': 3, 'method': 'tools/call', 'params': {'name': 'units', 'arguments': {}}},
                {'id': 4, 'method': 'resources/read', 'params': {'uri': URI}}]
        cls.sent = ''.join(json.dumps({'jsonrpc': '2.0', **m}) + '\n' for m in msgs)
        r = subprocess.run(['python3', os.path.join(plugin, 'desktop', 'units-mcp', 'server.py'), cls.checkout],
                           input=cls.sent, capture_output=True, text=True, timeout=60, check=False, env=env)
        cls.out = {m['id']: m for m in map(json.loads, r.stdout.splitlines())}
        cls.want_head = units_head(cls.tmp, cls.limit)

    @classmethod
    def tearDownClass(cls):
        shutil.rmtree(cls.tmp, ignore_errors=True)

    def result(self, i):
        self.assertIn('result', self.out.get(i, {}), f'no result for request {i} of {self.sent!r}: {self.out!r}')
        return self.out[i]['result']

    def test_initialize_answers_the_version(self):
        # Bug it catches: a server that does not answer initialize, or gives no tools or resources, is never asked for them.
        r = self.result(1)
        self.assertEqual((r['protocolVersion'], sorted(r['capabilities'])), ('2025-06-18', ['resources', 'tools']), f'initialize of {self.sent!r}')

    def test_tool_names_the_view(self):
        # Bug it catches: a tool that names no ui:// resource is shown as text, and Desktop draws no view.
        tools = self.result(2)['tools']
        self.assertEqual([(t['name'], t['_meta']['ui']['resourceUri']) for t in tools], [('units', URI)], f'tools/list of {self.sent!r}')

    def test_text_is_the_units_head(self):
        # Bug it catches: the Chat tab's text differs from what /units prints for the same fetch answer (the port of
        # sources.ts reads a field, adds the dollars or fits the line differently), says "weekly limit not read" where
        # the Board keeps a limit, or comes from the plugin's own fetch where the project has its engine installed.
        text = self.result(3)['content'][0]['text']
        self.assertEqual(text, self.want_head, f'tools/call units on {FIXTURE}, limit {self.limit}')
        self.assertIn('weekly limit 43% · resets 3d 5h', text, f'tools/call units on {FIXTURE}, limit {self.limit}')
        self.assertEqual(self.result(3)['structuredContent']['limitLine'], 'weekly limit 43% · resets 3d 5h', f'tools/call units, limit {self.limit}')

    def test_structured_content_carries_each_snapshot(self):
        # Bug it catches: the view gets fields renamed or dropped by the port, not the snapshot's own.
        c = self.result(3)['structuredContent']
        with open(FIXTURE) as f:
            lines = [ln.split('\t', 1) for ln in f.read().splitlines()]
        want = [{'repo': repo, 'snapshot': json.loads(j)} for repo, j in lines[lines.index(['host', 'buildbox\tlocal\t0']) + 1:]]
        self.assertEqual(c['records'], want, f'tools/call units on {FIXTURE}')
        self.assertEqual((c['host']['name'], c['own'], c['foreman'][-1], c['note']), ('buildbox', 'bakery', 'listening', ''), f'tools/call units on {FIXTURE}')

    def test_resource_is_the_view(self):
        # Bug it catches: the ui:// resource is not view.html, or not marked as an MCP App, so Desktop draws nothing.
        c = self.result(4)['contents']
        with open(os.path.join(HERE, 'view.html')) as f:
            view = f.read()
        self.assertEqual([(x['uri'], x['mimeType'], x['text']) for x in c], [(URI, 'text/html;profile=mcp-app', view)], f'resources/read of {self.sent!r}')


class FetchPath(unittest.TestCase):
    def test_a_commit_that_is_no_full_id_runs_the_plugins_own_fetch(self):
        # Bug it catches: a pinned commit that is not a full id ('../..') names a path outside versions/, and the
        # server runs a script from there.
        with tempfile.TemporaryDirectory() as tmp:
            for d in ('.conveyor', 'hooks', 'conveyor/versions'):
                os.makedirs(os.path.join(tmp, d))
            # The script the commit '../..' names: tmp/conveyor/versions/../../hooks/units-fetch.sh.
            open(os.path.join(tmp, 'hooks', 'units-fetch.sh'), 'w').close()
            with open(os.path.join(tmp, '.conveyor', 'project.json'), 'w') as f:
                json.dump({'plugin': {'commit': '../..'}}, f)
            got = server.fetch_path(tmp, {'XDG_DATA_HOME': tmp})
        self.assertEqual(got, server.HERE.parents[1] / 'hooks' / 'units-fetch.sh', 'fetch_path with plugin.commit "../.."')


class NoAnswer(unittest.TestCase):
    def test_a_fetch_that_did_not_run_gives_the_reason_and_no_record(self):
        # Bug it catches: a failed fetch reads as an empty board, so the view would drop its last good data for it.
        r = server.units(None, datetime.datetime(2026, 11, 26, 19, 12, tzinfo=datetime.UTC))
        self.assertEqual((r['content'][0]['text'], r['structuredContent']['records']),
                         ('units: the Conveyor snapshot cannot be read (the fetch did not run)', []), 'units(None)')


if __name__ == '__main__':
    unittest.main()
