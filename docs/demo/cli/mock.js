// SPDX-License-Identifier: Apache-2.0
// The belt that the Claude Code beats (record-cli.sh) show: the timeline of the Board beats (timeline.js), on a story
// clock, answered as a real Conveyor answers the plugin, so /units and the Foreman run unchanged.
// node mock.js serve <feed folder> <start delay s>: the story clock stands at 0 until `ask go`, and for the delay
//   after it, then runs one story second a second. Every 250 ms it writes <feed folder>/stream.json (the Board's live feed, which /units reads) and
//   data.js (the Board's data) and limit.json (the usage limit alone, as the Board writes it beside data.js, which
//   /units reads); it answers `ask` on 127.0.0.1:PORT.
// node mock.js ask <command> [<argument>...]: one engine command, answered from the timeline and printed as the
//   engine prints it: snapshot, health, cards, history and retry <issue>; go starts the story clock. Exit 1 for
//   another command or issue.
import fs from 'node:fs';
import http from 'node:http';
import path from 'node:path';
import { pathToFileURL } from 'node:url';
import { REPO, createTimeline } from '../timeline.js';

const PORT = 47417;
const HOST = 'acme';

// The record `conveyor.sh snapshot` prints for the project, from the Board's snapshot of the same story second.
export function record(board) {
  const p = board.panels;
  const blocked = p.needs.data.cards.blocked;
  return {
    health: { time: board.updatedAt, loop: true, gh: true, state: 'running', reason: null, blocked: blocked.map((c) => ({ card: c.card, issue: c.issue, since: c.since, reason: c.reason })),
      waiting: [], before: [], stuck: [], unpushed: [], pushError: null, pushFailingSince: null },
    needsYou: { waiting: [], blocked },
    belt: p.belt.data.cards,
    queue: { next: p.queue.data.next, held: {}, waiting: [] },
    landed: p.landed.data.cards,
    awaitingDeploy: [],
    cost: { today: p.cost.data.cards.todayUsd, todayLeftOut: 0 },
  };
}

// One engine command: [exit code, what it prints].
export function answer(tl, t, cmd, args) {
  const snap = record(tl.snapshot(t));
  if (cmd === 'snapshot') return [0, JSON.stringify(snap)];
  if (cmd === 'health') return [0, JSON.stringify(snap.health)];
  if (cmd === 'cards') return [0, JSON.stringify({ cards: snap.belt.map((c) => ({ card: c.card, issue: c.issue, step: c.step, result: '' })) })];
  if (cmd === 'history') return [0, 'null'];
  if (cmd === 'retry' && snap.needsYou.blocked.some((c) => String(c.issue) === args[0])) {
    tl.act('retry', [args[0]], t);
    return [0, `conveyor: #${args[0]} can be picked again`];
  }
  if (cmd === 'retry') return [1, `conveyor: #${args[0] || ''} has no blocked card; nothing to retry`];
  return [1, `conveyor: ${cmd} is not answered here`];
}

// limit.json as dashboard.sh writes it: the health panel's usedPct and resetsAt, or null with no limit.
function limitFile(board) {
  const l = board?.panels?.health?.data?.limit;
  return { limit: l && typeof l === 'object' ? { usedPct: l.usedPct, resetsAt: l.resetsAt } : null };
}

// One write of the feed folder: stream.json, data.js and limit.json, each by write-then-rename.
export function writeFeed(feed, board) {
  const put = (name, text) => { fs.writeFileSync(path.join(feed, `${name}.new`), text); fs.renameSync(path.join(feed, `${name}.new`), path.join(feed, name)); };
  const at = new Date().toISOString().replace(/\.\d{3}Z$/, 'Z');
  put('stream.json', JSON.stringify({ host: HOST, reachable: true, error: null, records: [{ repo: REPO, snap: record(board) }],
    stream: { live: true, heardAt: at, since: null, error: null, writtenAt: at } }));
  put('data.js', `window.DASH = ${JSON.stringify(board)};`);
  put('limit.json', JSON.stringify(limitFile(board)));
}

function serve(feed, delay) {
  const tl = createTimeline();
  let start = null;
  const now = () => (start === null ? 0 : Math.max(0, (Date.now() - start) / 1000));
  fs.mkdirSync(feed, { recursive: true });
  const write = () => writeFeed(feed, tl.snapshot(now()));
  write();
  setInterval(write, 250);
  http.createServer((req, res) => {
    let body = '';
    req.on('data', (c) => { body += c; });
    req.on('end', () => {
      let a = [];
      try { a = JSON.parse(body); } catch { a = []; }
      if (a[0] === 'go' && start === null) start = Date.now() + delay * 1000;
      const [rc, out] = a[0] === 'go' ? [0, 'conveyor: the belt runs'] : answer(tl, now(), String(a[0] || ''), a.slice(1).map(String));
      write();
      res.writeHead(rc === 0 ? 200 : 409, { 'Content-Type': 'text/plain' });
      res.end(out);
    });
  }).listen(PORT, '127.0.0.1');
}

function ask(args) {
  const req = http.request({ host: '127.0.0.1', port: PORT, method: 'POST', path: '/' }, (res) => {
    let out = '';
    res.on('data', (c) => { out += c; });
    res.on('end', () => {
      if (res.statusCode === 200) { process.stdout.write(`${out}\n`); return; }
      process.stderr.write(`${out}\n`);
      process.exitCode = 1;
    });
  });
  req.on('error', (e) => { process.stderr.write(`conveyor: the belt does not answer (${e.message})\n`); process.exitCode = 1; });
  req.end(JSON.stringify(args));
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const [mode, ...rest] = process.argv.slice(2);
  if (mode === 'serve' && rest[0]) serve(rest[0], Number(rest[1]) || 0);
  else if (mode === 'ask' && rest[0]) ask(rest);
  else { process.stderr.write('usage: mock.js serve <feed folder> <start delay s> | ask <command> [<argument>...]\n'); process.exit(2); }
}
