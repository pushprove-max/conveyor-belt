// SPDX-License-Identifier: Apache-2.0
// The usage-limit reader (dashboard_limit.py) reads what changed since the last 60 s cycle, and every value the page
// reads equals a cold read. Each case is labelled `red-first` (it failed before the reader kept state) or
// `pin` (it held already and must keep holding; its guard condition was deleted once to see it go red).
// Each case has folders of its own, so the cases run side by side (one describe, concurrency on): the file takes its
// slowest case's time, not their sum.
import { describe, test } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { execFile, spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const SCRIPTS = fileURLToPath(new URL('../', import.meta.url));
const DAY = 86400;
const NOW = 1791633600; // 2026-10-10T12:00:00Z, a Saturday
const REAL_GIT =spawnSync('which', ['git'], { encoding: 'utf8' }).stdout.trim();

const iso = (s) => new Date(s * 1000).toISOString();

function makeCtx(t) {
  const d = fs.mkdtempSync(path.join(os.tmpdir(), 'dash-incr-'));
  t.after(() => fs.rmSync(d, { recursive: true, force: true }));
  return { d, home: path.join(d, 'home'), cache: path.join(d, 'cache'), now: NOW, seq: 0, cold: 0, runs: 0 };
}

function putFile(c, p, text, mode, mtimeBase) {
  fs.mkdirSync(path.dirname(p), { recursive: true });
  (mode === 'a' ? fs.appendFileSync : fs.writeFileSync)(p, text);
  const m = mtimeBase + ++c.seq;
  fs.utimesSync(p, m, m);
}

function coldDir(c) {
  const d = path.join(c.d, `cold-${++c.cold}`);
  fs.mkdirSync(d, { recursive: true });
  return d;
}

// The python module under `python3 -c` with open() wrapped to count, per .jsonl path, the opens and the bytes
// ingested line by line. A tail read() (the Codex rate-limit reading) is not ingestion and is left out.
const PRELUDE = `
import builtins, collections, json, os, sys
sys.path.insert(0, ${JSON.stringify(SCRIPTS)})
_open = builtins.open
opens, nbytes = collections.Counter(), collections.Counter()
class Counted:
    def __init__(self, f, p):
        self._f, self._p = f, p
    def __enter__(self):
        self._f.__enter__()
        return self
    def __exit__(self, *a):
        return self._f.__exit__(*a)
    def __iter__(self):
        for line in self._f:
            nbytes[self._p] += len(line)
            yield line
    def __getattr__(self, n):
        return getattr(self._f, n)
def counting(p, mode="r", *a, **k):
    f = _open(p, mode, *a, **k)
    if isinstance(p, str) and p.endswith(".jsonl") and "r" in mode and "+" not in mode:
        opens[p] += 1
        return Counted(f, p)
    return f
builtins.open = counting
import dashboard_limit as m
`;
const EPILOGUE = `
with _open(os.environ["COUNTS"], "w") as _f:
    json.dump({"opens": dict(opens), "bytes": dict(nbytes)}, _f)
`;

// py: the python run, awaited, so another case runs while this one waits for it. -S: dashboard_limit.py needs only the
// standard library, so no run spends its start on the site packages.
async function py(c, body, env = {}) {
  const counts = path.join(c.d, `counts-${++c.runs}.json`);
  const r = await new Promise((resolve) => execFile('python3', ['-S', '-c', PRELUDE + body + EPILOGUE], {
    encoding: 'utf8',
    env: {
      ...process.env, TZ: 'UTC', HOME: c.home, COUNTS: counts,
      CONVEYOR_CODEX_REVIEW_HOME: path.join(c.d, 'no-review'),
      CONVEYOR_CLAUDE_PROFILES: path.join(c.d, 'no-profiles'), ...env,
    },
  }, (err, stdout, stderr) => resolve({ status: err ? err.code : 0, stdout, stderr })));
  assert.equal(r.status, 0, r.stderr);
  return { out: r.stdout, ...JSON.parse(fs.readFileSync(counts, 'utf8')) };
}

const stateText = (dir) => {
  let s = '';
  const walk = (d) => {
    if (!fs.existsSync(d)) return;
    for (const e of fs.readdirSync(d, { withFileTypes: true })) {
      if (e.isDirectory()) walk(path.join(d, e.name));
      else s += fs.readFileSync(path.join(d, e.name), 'utf8');
    }
  };
  walk(dir);
  return s;
};

// ---- the two readers, one adapter each --------------------------------------------------------------------------
// line(id, out): one full record, newline included, whose visible effect is the id. ids(c, cold): the sorted ids a
// read shows; a warm read is a new cycle, a cold one reads the same files with no state.

const claudeReq = (c, cache, since = c.now - 7 * DAY, now = c.now) => `m.requests(${JSON.stringify(path.join(c.d, 'proj'))}, ${JSON.stringify(cache)}, ${since}, ${now})`;
const codexReq = (c, cache, since = c.now - 7 * DAY, now = c.now) => `m.codex_requests([${JSON.stringify(path.join(c.d, 'cx'))}], ${JSON.stringify(cache)}, ${since}, ${now})`;

function requestsAdapter(name, dir, cacheName, call, line) {
  return {
    name, keepsRows: true,
    setup(t) { const c = makeCtx(t); fs.mkdirSync(path.join(c.d, dir), { recursive: true }); return c; },
    path: (c, n) => path.join(c.d, dir, `${n}.jsonl`),
    put(c, n, text, mode = 'w') { putFile(c, this.path(c, n), text, mode, NOW - 3600); },
    rm(c, n) { fs.rmSync(this.path(c, n)); },
    line,
    stateDir: (c) => c.cache,
    async ids(c, cold = false) {
      if (!cold) c.now += 60;
      const cache = path.join(cold ? coldDir(c) : c.cache, cacheName);
      fs.mkdirSync(path.dirname(cache), { recursive: true });
      const r = await py(c, `rows = ${call(c, cache)}\nprint(json.dumps(sorted(x[6] for x in rows)))`);
      if (!cold) c.last = r;
      return JSON.parse(r.out);
    },
    bytesOf: (c, n) => c.last.bytes[path.join(c.d, dir, `${n}.jsonl`)] ?? 0,
  };
}

const claude = requestsAdapter('claude', 'proj/p', 'limit-requests.json', claudeReq, (id, out = id) => JSON.stringify({
  type: 'assistant', requestId: `req_${id}`, timestamp: iso(NOW - 7200), cwd: '/w', sessionId: 's', isSidechain: false,
  message: { model: 'claude-opus-5-5', usage: { input_tokens: 1, output_tokens: out, cache_read_input_tokens: 0, cache_creation_input_tokens: 0 } },
}) + '\n');

const codex = requestsAdapter('codex', 'cx/2026/10/10', 'codex-requests.json', codexReq, (id, out = id) => JSON.stringify({
  type: 'token_usage_record', timestamp: iso(NOW - 7200),
  payload: { response_id: `resp_${id}`, usage: { input_tokens: 1, cached_input_tokens: 0, output_tokens: out } },
}) + '\n');

const ADAPTERS = [claude, codex];
const want = (A, ids) => (A.norm ? A.norm(ids) : ids);

describe('the incremental limit read', { concurrency: true }, () => {
// ---- the four cases every reader owes ----------------------------------------------------------------------------
for (const A of ADAPTERS) {
  test(`${A.name}: partial_line_waits`, async (t) => {
    const c = A.setup(t);
    const full = A.line(2);
    const cut = full.slice(0, full.length - 12);
    A.put(c, 'f1', A.line(1) + cut);
    assert.deepEqual(await A.ids(c), want(A, [1]));
    assert.deepEqual(await A.ids(c, true), want(A, [1]));
    A.put(c, 'f1', full.slice(cut.length), 'a');
    assert.deepEqual(await A.ids(c), want(A, [1, 2]));
    if (A.bytesOf) assert.equal(A.bytesOf(c, 'f1'), full.length, 'only the once-partial line is read again');
    assert.deepEqual(await A.ids(c, true), want(A, [1, 2]));
  });

  test(`${A.name}: rotation_and_retention`, async (t) => {
    const c = A.setup(t);
    A.put(c, 'f1', A.line(1));
    await A.ids(c);
    A.put(c, 'f2', A.line(2));
    await A.ids(c);
    assert.ok(stateText(A.stateDir(c)).includes(A.path(c, 'f2')), 'the state is keyed by the file path');
    A.rm(c, 'f1');
    A.put(c, 'f3', A.line(3));
    const expected = [1, 2, 3];
    assert.deepEqual(await A.ids(c), want(A, expected));
    if (!A.keepsRows) assert.deepEqual(await A.ids(c, true), want(A, expected));
    assert.ok(!stateText(A.stateDir(c)).includes(A.path(c, 'f1')), 'a file that is gone leaves no state');
  });

  test(`${A.name}: truncation_rereads_from_zero`, async (t) => {
    const c = A.setup(t);
    A.put(c, 'f1', A.line(1) + A.line(2) + A.line(3));
    assert.deepEqual(await A.ids(c), want(A, [1, 2, 3]));
    A.put(c, 'f1', A.line(4));
    assert.deepEqual(await A.ids(c), want(A, A.keepsRows ? [1, 2, 3, 4] : [4]));
    if (A.bytesOf) assert.equal(A.bytesOf(c, 'f1'), A.line(4).length, 'the rewritten file is read from its start');
    assert.deepEqual(await A.ids(c, true), want(A, [4]));
  });

  test(`${A.name}: corrupt_state_is_cold_start`, async (t) => {
    // Each corrupt state on a folder of its own, side by side.
    await Promise.all(['{not json', '', '{"version":999}', 'FIRSTHALF'].map(async (bad) => {
      const c = A.setup(t);
      A.put(c, 'f1', A.line(1) + A.line(2));
      await A.ids(c);
      assert.ok(stateText(A.stateDir(c)).length > 0, 'the reader keeps state between cycles');
      for (const f of fs.readdirSync(A.stateDir(c))) {
        const p = path.join(A.stateDir(c), f);
        const text = fs.readFileSync(p, 'utf8');
        fs.writeFileSync(p, bad === 'FIRSTHALF' ? text.slice(0, Math.floor(text.length / 2)) : bad);
      }
      A.put(c, 'f1', A.line(3), 'a');
      assert.deepEqual(await A.ids(c), want(A, [1, 2, 3]), `state ${JSON.stringify(bad)} is a cold start`);
    }));
  });
}

for (const A of [claude, codex]) {
  // pin: the cached `seen` and the request key dedupe a streamed request today
  test(`${A.name}: duplicate_streamed_request_counted_once`, async (t) => {
    const c = A.setup(t);
    A.put(c, 'f1', A.line(7, 5) + A.line(7, 6));
    assert.deepEqual(await A.ids(c), [6]);
    A.put(c, 'f1', A.line(7, 9), 'a');
    assert.deepEqual(await A.ids(c), [9], 'the last streamed line carries the final usage, and the request is one row');
    assert.deepEqual(await A.ids(c, true), [9]);
  });
}

// ---- the 50 MB state files: json.dump to a file takes the pure-Python encoder ------------------------------
// A wall-clock assertion is banned, so these patch json.dump to raise on any file but stdout. Same seam as the stated bug:
// the limit read spent most of each cycle's Python time in that encoder.
const REFUSE_DUMP = `import json, sys
_dump = json.dump
def _refuse(o, f, *a, **k):
    if f is not sys.stdout:
        raise AssertionError("a state file went through json.dump")
    return _dump(o, f, *a, **k)
json.dump = _refuse
`;
for (const [A, call] of [[claude, claudeReq], [codex, codexReq]]) {
  // red-first: the state write used json.dump
  test(`${A.name}: requests_state_skips_python_encoder`, async (t) => {
    const c = A.setup(t);
    A.put(c, 'f1', A.line(1));
    fs.mkdirSync(c.cache, { recursive: true });
    const cache = path.join(c.cache, 'state.json');
    await py(c, `${REFUSE_DUMP}${call(c, cache)}\njson.dump = _dump\n`);
    assert.ok(JSON.parse(fs.readFileSync(cache, 'utf8')).version, 'the state is written, and reads back');
  });
}

// ---- Claude and Codex: old files keep their offsets, one ingestion per cycle -------------------------------------
function cliCtx(t) {
  const c = makeCtx(t);
  const claudeFile = (n, ts) => ({ p: path.join(c.d, 'proj/p', `${n}.jsonl`), ts });
  c.files = [claudeFile('old', NOW - 2 * DAY), claudeFile('today', NOW - 3600)];
  c.cxFiles = [
    { p: path.join(c.d, 'cx/2026/10/08/rollout-old.jsonl'), ts: NOW - 2 * DAY },
    { p: path.join(c.d, 'cx/2026/10/10/rollout-today.jsonl'), ts: NOW - 3600 },
  ];
  c.files.forEach((f, i) => putFile(c, f.p, [1, 2, 3].map((k) => claude.line(10 * i + k)).join('').replaceAll(iso(NOW - 7200), iso(f.ts - 60)), 'w', f.ts - 10));
  c.cxFiles.forEach((f, i) => putFile(c, f.p, [1, 2, 3].map((k) => codex.line(10 * i + k)).join('').replaceAll(iso(NOW - 7200), iso(f.ts - 60)), 'w', f.ts - 10));
  for (const f of [...c.files, ...c.cxFiles]) fs.utimesSync(f.p, f.ts, f.ts);
  fs.mkdirSync(c.cache, { recursive: true });
  fs.writeFileSync(path.join(c.d, 'usage.json'), JSON.stringify({ seven_day: { utilization: 10, resets_at: '2026-10-13T12:00:00+00:00' } }));
  fs.writeFileSync(path.join(c.d, 'billing.json'), JSON.stringify({ billing: 'api', weeklyLimitUsd: 1000 }));
  return c;
}

async function cycle(c, now, cache = c.cache) {
  const j = JSON.stringify;
  fs.mkdirSync(cache, { recursive: true });
  const build = await py(c, `m.main(["x", "build", "fresh", ${j(path.join(c.d, 'usage.json'))}, "${now}", ${j(cache)}, ${j(path.join(c.d, 'proj'))}, ${j(path.join(c.d, 'cx'))}])`);
  const b = JSON.parse(build.out);
  return { opens: build.opens, bytes: build.bytes, view: { requests: b.requests, cost: b.cost, today: b.today, api: b.api, cw: b.cacheWritePct24h } };
}

// red-first: a file older than midnight lost its offset in the `today` call
test('claude_and_codex_old_files_keep_offsets', async (t) => {
  const c = cliCtx(t);
  await cycle(c, NOW);
  const second = await cycle(c, NOW + 60);
  for (const f of [...c.files, ...c.cxFiles]) assert.equal(second.bytes[f.p] ?? 0, 0, `${path.basename(f.p)} is not read again`);
  assert.deepEqual(second.view, (await cycle(c, NOW + 60, path.join(c.d, 'cold-cache'))).view, 'the warm cycle equals a cold read');
});

// red-first: limit, api week and today each walked and opened the file
test('one_ingestion_per_cycle', async (t) => {
  const c = cliCtx(t);
  await cycle(c, NOW);
  fs.appendFileSync(c.files[1].p, claude.line(99).replace(iso(NOW - 7200), iso(NOW - 600)));
  fs.appendFileSync(c.cxFiles[1].p, codex.line(99).replace(iso(NOW - 7200), iso(NOW - 600)));
  const second = await cycle(c, NOW + 60);
  for (const f of c.files) assert.ok((second.opens[f.p] ?? 0) <= 1, `${path.basename(f.p)} opened ${second.opens[f.p]} times across limit and today`);
  assert.deepEqual(second.view, (await cycle(c, NOW + 60, path.join(c.d, 'cold-cache'))).view);
  const monday = NOW - 5 * DAY, midnight = NOW - 12 * 3600;
  const cxCache = JSON.stringify(path.join(c.cache, 'codex-requests.json'));
  const cx = await py(c, `a = m.codex_requests([${JSON.stringify(path.join(c.d, 'cx'))}], ${cxCache}, ${monday}, ${NOW + 120})
b = m.codex_requests([${JSON.stringify(path.join(c.d, 'cx'))}], ${cxCache}, ${midnight}, ${NOW + 120})
print(json.dumps([len(a), len(b)]))`);
  assert.ok((cx.opens[c.cxFiles[1].p] ?? 0) <= 1, `the Codex file is opened ${cx.opens[c.cxFiles[1].p]} times across two calls of one cycle`);
});

// red-first for the hit (no cycle key today); the misses below are pins
test('cycle_snapshot_hit', async (t) => {
  await Promise.all([[claude, 'limit-requests.json'], [codex, 'codex-requests.json']].map(async ([A, cacheName]) => {
    const c = A.setup(t);
    A.put(c, 'f1', A.line(1) + A.line(2));
    await A.ids(c);
    const cache = path.join(c.cache, cacheName);
    assert.equal(JSON.parse(fs.readFileSync(cache, 'utf8')).cycle, c.now, `${A.name}: the cache names its cycle`);
    const call = A === claude ? claudeReq : codexReq;
    const again = await py(c, `rows = ${call(c, cache)}\nprint(json.dumps(sorted(x[6] for x in rows)))`);
    assert.deepEqual(JSON.parse(again.out), [1, 2]);
    assert.deepEqual(again.opens, {}, `${A.name}: a second call in the same cycle opens no file`);
  }));
});

// pin: every guard of the hit
test('cycle_snapshot_misses_unless_whole', async (t) => {
  await Promise.all([[claude, 'limit-requests.json', claudeReq], [codex, 'codex-requests.json', codexReq]].map(async ([A, cacheName, call]) => {
    const c = A.setup(t);
    A.put(c, 'f1', A.line(1));
    await A.ids(c);
    const cache = path.join(c.cache, cacheName);
    const saved = fs.readFileSync(cache, 'utf8');
    const opened = async (since, now) => Object.keys((await py(c, `rows = ${call(c, cache, since, now)}\nprint(json.dumps(len(rows)))`)).opens).length;
    fs.writeFileSync(cache, JSON.stringify({ ...JSON.parse(saved), complete: false }));
    assert.ok(await opened(c.now - 7 * DAY, c.now) > 0, `${A.name}: an incomplete cache is walked`);
    fs.writeFileSync(cache, saved);
    assert.ok(await opened(c.now - 8 * DAY, c.now) > 0, `${A.name}: a call starting before the cache's coverage is walked`);
    fs.writeFileSync(cache, saved);
    assert.ok(await opened(c.now - 7 * DAY, c.now + 60) > 0, `${A.name}: another cycle is walked`);
  }));
});
});
