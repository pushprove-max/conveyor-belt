// SPDX-License-Identifier: Apache-2.0
import { describe, test } from 'node:test';
import assert from 'node:assert/strict';
import { execFile } from 'node:child_process';
import { chmodSync, mkdirSync, mkdtempSync, rmSync, utimesSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = fileURLToPath(new URL('../../../', import.meta.url));
// python <args>: the run's stdout, awaited, so the cases below run side by side (one describe, concurrency on), each
// on folders of its own; a run that fails rejects, as a synchronous call would throw. -S: dashboard_limit.py needs
// only the standard library, so no run spends its start on the site packages.
const python = (args) => new Promise((resolve, reject) => execFile('python3', ['-S', ...args], { cwd: root, encoding: 'utf8' },
  (err, stdout) => (err ? reject(err) : resolve(stdout))));
async function cost(rows) {
  const code = [
    'import json, sys',
    'sys.path.insert(0, ".claude/scripts")',
    'import dashboard_limit as d',
    'print(json.dumps(d.cost(json.loads(sys.argv[1]), 44, 0, 94.5 * 3600)))',
  ].join('\n');
  return JSON.parse(await python(['-B', '-c', code, JSON.stringify(rows)]));
}

describe('the limit cost', { concurrency: true }, () => {
test('projected hourly cost matches the supplied design', async () => {
  const result = await cost([
    [0, 'claude-opus-5-5', 0, 0, 0, 0, 25304500],
  ]);
  assert.equal(result.week, 506.09);
  assert.equal(result.perHour.toFixed(2), '6.85');
  assert.equal(result.perHour, result.projected / 168);
});

test('requests without any known price leave every dollar field unmeasured', async () => {
  const result = await cost([[0, 'unsupported-model', 0, 0, 0, 0, 1000]]);
  assert.equal(result.unpricedRequests, 1);
  for (const field of ['week', 'projected', 'perPoint', 'perHour']) {
    assert.equal(result[field], null, `${field} has no price source`);
  }
});

// One logged call as Claude Code writes it; an advisor call sits only in usage.iterations.
async function callPrice(iterations) {
  const usage = { input_tokens: 4, cache_read_input_tokens: 253751, output_tokens: 1744,
    cache_creation: { ephemeral_5m_input_tokens: 0, ephemeral_1h_input_tokens: 3877 }, iterations };
  const record = { requestId: 'req_1', timestamp: '2026-10-12T00:00:00Z', type: 'assistant',
    message: { model: 'claude-opus-5-5', usage } };
  const code = [
    'import json, sys',
    'sys.path.insert(0, ".claude/scripts")',
    'import dashboard_limit as d',
    'print(json.dumps(d.price(d.request_row(json.loads(sys.argv[1])))))',
  ].join('\n');
  return JSON.parse(await python(['-B', '-c', code, JSON.stringify(record)]));
}
const turn = { type: 'message', input_tokens: 2, output_tokens: 1196, cache_read_input_tokens: 124937 };
const advisor = (model) => ({ type: 'advisor_message', model, input_tokens: 129139, output_tokens: 10893,
  cache_read_input_tokens: 0, cache_creation_input_tokens: 0 });

test('an advisor iteration adds exactly its own tokens at its own model price', async () => {
  const [without, withAdvisor] = await Promise.all([callPrice([turn]), callPrice([turn, advisor('claude-fable-5-1'), turn])]);
  // Fable list price: 129139 input at $10/M plus 10893 output at $50/M.
  assert.equal((withAdvisor - without).toFixed(9), '1.836040000');
});

test('an advisor model with no list price leaves the whole call unpriced', async () => {
  assert.equal(await callPrice([turn, advisor('unsupported-model')]), null);
});

// Behind an API proxy (ANTHROPIC_BASE_URL) the log has no requestId; skipping those lines read as $0.00.
test('a request logged without a requestId is counted once, keyed on its message id', async () => {
  const dir = mkdtempSync(join(tmpdir(), 'dash-proxy-'));
  mkdirSync(join(dir, 'proj', 'p'), { recursive: true });
  const line = (extra, id, out) => JSON.stringify({ ...extra, type: 'assistant', timestamp: '2026-10-12T00:00:00Z',
    message: { id, model: 'claude-opus-5-5', usage: { input_tokens: 0, output_tokens: out } } });
  writeFileSync(join(dir, 'proj', 'p', 's.jsonl'), [
    line({}, 'msg_proxy', 10), line({}, 'msg_proxy', 1000000), // one streamed request: its last line wins
    line({ requestId: 'req_1' }, 'msg_direct', 2000000), line({ requestId: 'req_1' }, 'msg_direct', 3000000),
  ].join('\n') + '\n');
  const code = [
    'import json, sys',
    'sys.path.insert(0, ".claude/scripts")',
    'import dashboard_limit as d',
    'print(json.dumps(sorted(r[6] for r in d.requests(sys.argv[1] + "/proj", sys.argv[1] + "/cache.json", 0, 1791766800))))',
  ].join('\n');
  try {
    const outputs = JSON.parse(await python(['-B', '-c', code, dir]));
    assert.deepEqual(outputs, [1000000, 3000000]);
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

// Every cost is read from the request caches the two readers write. A collection that could not read a transcript
// folder still writes its cache; a cost read from it as whole would show the missing spend as a measured $0.
// `whole` below is both caches marked complete.
test('a collection that missed a folder leaves its cache incomplete, never whole', async () => {
  const dir = mkdtempSync(join(tmpdir(), 'limit-cost-lost-'));
  const locked = join(dir, 'proj', 'locked');
  mkdirSync(locked, { recursive: true });
  mkdirSync(join(dir, 'sessions'));
  const code = [
    'import json, os, sys',
    'sys.path.insert(0, ".claude/scripts")',
    'import dashboard_limit as d',
    'b, now = sys.argv[1], 1791766800.0',
    'd.requests(b + "/proj", b + "/limit-requests.json", 0, now)',
    'd.codex_requests([b + "/sessions"],b + "/codex-requests.json", 0, now)',
    'caches = [b + "/limit-requests.json", b + "/codex-requests.json"]',
    'print(json.dumps(all(os.path.exists(p) and json.load(open(p)).get("complete") is True for p in caches)))',
  ].join('\n');
  const whole = async () => JSON.parse(await python(['-B', '-c', code, dir]));
  try {
    chmodSync(locked, 0o000);
    assert.equal(await whole(), false, 'a folder that could not be read leaves the caches incomplete');
    chmodSync(locked, 0o755);
    assert.equal(await whole(), true, 'once every folder is read, the caches are whole');
  } finally {
    chmodSync(locked, 0o755);
    rmSync(dir, { recursive: true, force: true });
  }
});

// A folder under a parent that cannot be searched is unread, not gone: lexists() says False for both, which
// would drop it from the unread list and save a complete cache.
test('a folder under an unsearchable parent leaves the Codex cache incomplete', async () => {
  // requests() returns None before any cache for such a folder (isdir), so only codex_requests reaches the save.
  for (const [fn, dirArg, cacheName] of [['codex_requests', '[b + "/parent/sessions"]', 'codex-requests.json']]) {
    const dir = mkdtempSync(join(tmpdir(), 'limit-cost-parent-'));
    const parent = join(dir, 'parent');
    mkdirSync(join(parent, 'sessions'), { recursive: true });
    const code = [
      'import json, os, sys',
      'sys.path.insert(0, ".claude/scripts")',
      'import dashboard_limit as d',
      'b, now = sys.argv[1], 1791766800.0',
      `d.${fn}(${dirArg}, b + "/${cacheName}", 0, now)`,
      `print(json.load(open(b + "/${cacheName}"))["complete"])`,
    ].join('\n');
    const complete = async () => (await python(['-B', '-c', code, dir])).trim();
    try {
      chmodSync(parent, 0o000);
      assert.equal(await complete(), 'False', `${fn}: an unsearchable parent leaves the cache incomplete`);
      chmodSync(parent, 0o755);
      assert.equal(await complete(), 'True', `${fn}: once readable, the cache is complete`);
    } finally {
      chmodSync(parent, 0o755);
      rmSync(dir, { recursive: true, force: true });
    }
  }
});

// The day's figures refresh the same caches from midnight on, skipping yesterday's files unread. A file that
// could not be read yesterday is still missing from a two-day cost, so that refresh must not call the cache whole.
test('a narrower refresh keeps an earlier unread file unknown, for both readers', async () => {
  const now = 1791766800;
  const code = [
    'import json, os, sys',
    'sys.path.insert(0, ".claude/scripts")',
    'import dashboard_limit as d',
    'b, now = sys.argv[1], 1791766800.0',
    'for since in json.loads(sys.argv[2]):',
    '    d.requests(b + "/proj", b + "/limit-requests.json", since, now)',
    '    d.codex_requests([b + "/sessions"],b + "/codex-requests.json", since, now)',
    'caches = [b + "/limit-requests.json", b + "/codex-requests.json"]',
    'print(json.dumps(all(os.path.exists(p) and json.load(open(p)).get("complete") is True for p in caches)))',
  ].join('\n');
  // Each reader's folder on a folder of its own, side by side.
  await Promise.all(['proj/p', 'sessions'].map(async (where) => {
    const dir = mkdtempSync(join(tmpdir(), 'limit-cost-narrow-'));
    mkdirSync(join(dir, 'proj', 'p'), { recursive: true });
    mkdirSync(join(dir, 'sessions'));
    const old = join(dir, where, 'yesterday.jsonl');
    writeFileSync(old, '{}\n');
    utimesSync(old, now - 86400, now - 86400);
    const whole = async (sinces) => JSON.parse(await python(['-B', '-c', code, dir, JSON.stringify(sinces)]));
    try {
      chmodSync(old, 0o000);
      assert.equal(await whole([0, now - 3600]), false, `${where}: the midnight refresh leaves yesterday's unread file unknown`);
      chmodSync(old, 0o644);
      assert.equal(await whole([0]), true, `${where}: once that file is read, the caches are whole`);
    } finally {
      chmodSync(old, 0o644);
      rmSync(dir, { recursive: true, force: true });
    }
  }));
});

// The same for a folder: listing it again from midnight on reads none of its older files, so it is still unknown.
test('a folder listed again by a narrower refresh stays unknown until its older files are read', async () => {
  const now = 1791766800;
  const code = [
    'import json, os, sys',
    'sys.path.insert(0, ".claude/scripts")',
    'import dashboard_limit as d',
    'b, now, since = sys.argv[1], 1791766800.0, float(sys.argv[2])',
    'd.requests(b + "/proj", b + "/limit-requests.json", since, now)',
    'd.codex_requests([b + "/sessions"],b + "/codex-requests.json", since, now)',
    'caches = [b + "/limit-requests.json", b + "/codex-requests.json"]',
    'print(json.dumps(all(os.path.exists(p) and json.load(open(p)).get("complete") is True for p in caches)))',
  ].join('\n');
  // Each reader's folder on a folder of its own, side by side.
  await Promise.all(['proj/p', 'sessions/p'].map(async (where) => {
    const dir = mkdtempSync(join(tmpdir(), 'limit-cost-folder-'));
    mkdirSync(join(dir, 'proj', 'p'), { recursive: true });
    mkdirSync(join(dir, 'sessions', 'p'), { recursive: true });
    const folder = join(dir, where);
    const old = join(folder, 'yesterday.jsonl');
    writeFileSync(old, '{}\n');
    utimesSync(old, now - 86400, now - 86400);
    const whole = async (since) => JSON.parse(await python(['-B', '-c', code, dir, String(since)]));
    try {
      chmodSync(folder, 0o000);
      assert.equal(await whole(0), false, `${where}: a folder that cannot be listed is unknown`);
      chmodSync(folder, 0o755);
      assert.equal(await whole(now - 3600), false, `${where}: listed again from midnight, its older file is still unread`);
      assert.equal(await whole(0), true, `${where}: once that file is read, the caches are whole`);
    } finally {
      chmodSync(folder, 0o755);
      rmSync(dir, { recursive: true, force: true });
    }
  }));
});
});
