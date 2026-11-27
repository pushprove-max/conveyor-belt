// SPDX-License-Identifier: Apache-2.0
// view.html, the /units view in Claude Desktop, drawn in jsdom with a stand-in host (MCP Apps: JSON-RPC over
// postMessage) from the units tool's structured content for fixtures/units-answer.txt, as server.py gives it.
import { test } from 'node:test'
import assert from 'node:assert/strict'
import { execFileSync } from 'node:child_process'
import { readFileSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'
import { JSDOM } from 'jsdom'

process.env.TZ = 'UTC'
const HERE = dirname(fileURLToPath(import.meta.url))
const HTML = readFileSync(join(HERE, 'view.html'), 'utf8')
// server.py's units() for the fixture answer read at 19:12 UTC with a weekly limit of 42.6% that resets 3d 5h 30m on,
// for a fetch that did not run, and for the answer with gadgetlab's snapshot not read (the fetch's null): the function,
// not the server, as the stdio session is server.test.py's.
const RESULTS = JSON.parse(execFileSync('python3', ['-c', `
import datetime, importlib.util, json, re, sys
spec = importlib.util.spec_from_file_location('s', sys.argv[1]); s = importlib.util.module_from_spec(spec); spec.loader.exec_module(s)
now = datetime.datetime(2026, 11, 26, 19, 12, tzinfo=datetime.timezone.utc)
text = open(sys.argv[2]).read()
limit = {'pct': 42.6, 'resetsAt': now + datetime.timedelta(days=3, hours=5, minutes=30)}
partial = re.sub(r'^gadgetlab\\t.*$', 'gadgetlab\\tnull', text, flags=re.M)
print(json.dumps([s.units(text, now, limit), s.units(None, now), s.units(partial, now, limit)]))`, join(HERE, 'server.py'), join(HERE, 'fixtures', 'units-answer.txt')], { encoding: 'utf8' }))
const [GOOD, FAILED, PARTIAL] = RESULTS

// The view with a host that answers each request with answer(method, params); sent: every message the view posted;
// tick: the view's 30 s refresh, run now.
function open(answer) {
  const sent = [], timers = []
  const dom = new JSDOM(HTML, {
    runScripts: 'dangerously',
    beforeParse(win) {
      win.setInterval = (fn, ms) => timers.push({ fn, ms })
      const reply = (m) => setTimeout(() => win.dispatchEvent(new win.MessageEvent('message', { data: { jsonrpc: '2.0', id: m.id, result: answer(m.method, m.params) } })))
      Object.defineProperty(win, 'parent', { value: { postMessage: (m) => { sent.push(m); if (m.id !== undefined) reply(m) } } })
    },
  })
  const win = dom.window, doc = win.document
  const push = (result) => win.dispatchEvent(new win.MessageEvent('message', { data: { jsonrpc: '2.0', method: 'ui/notifications/tool-result', params: result } }))
  const tick = () => timers.filter(t => t.ms === 30000).forEach(t => t.fn())
  return { win, doc, sent, push, tick }
}
const settle = () => new Promise(r => setTimeout(r, 5))
const host = (tool) => (method) => (method === 'ui/initialize' ? { hostContext: { displayMode: 'inline' } }
  : method === 'tools/call' ? tool : method === 'ui/request-display-mode' ? { mode: 'fullscreen' } : {})
const figures = (doc) => [...doc.querySelectorAll('.stats .stat')].map(s => `${s.querySelector('.stat-label').textContent} ${s.querySelector('.stat-fig').textContent}`)
const rows = (doc) => [...doc.querySelectorAll('#needs > li .issue')].map(x => x.textContent)

test('the inline card shows 5 figures, the first 5 needs-you rows, and N more, and the two buttons', async () => {
  // Bug it catches: the inline card grows with every card that needs you (an inner scroll, or a card taller than the
  // chat), or loses a figure or a button the approved mockup has.
  const v = open(host(GOOD))
  await settle()
  v.push(GOOD)
  await settle()
  assert.deepEqual(figures(v.doc), ['On belt 3 of 7', 'Ready 5', 'Waiting 2', 'Needs you 7', 'Day spend $63.10+'], 'figures for units-answer.txt')
  assert.deepEqual(rows(v.doc), ['#415', '#412', 'gadgetlab#80', 'gadgetlab#81', '#399'], 'the needs-you rows for units-answer.txt: your yes first, then the longest blocked')
  assert.equal(v.doc.getElementById('more')?.textContent, 'and 2 more', 'the rows left out of units-answer.txt')
  assert.deepEqual([...v.doc.querySelectorAll('.ucard-actions button')].map(b => b.textContent), ['Open the board', 'Read again'])
  // The weekly limit, as /units prints it: the view once said "weekly limit not read" whatever the Board kept.
  assert.equal(v.doc.getElementById('foot').textContent, 'Foreman has 1 · 1 landing, not counted · 19 landed today · weekly limit 43% · resets 3d 5h · read 7:12 PM', 'the foot line for units-answer.txt')
})

test('a project whose snapshot was not read leaves the day partial and says so', async () => {
  // Bug it catches: with gadgetlab's read failed and bakery's good, the card showed bakery's $61.34+ as the whole
  // day's spend, with a fresh read time and no word of the missing project.
  const v = open(host(PARTIAL))
  await settle()
  v.push(PARTIAL)
  await settle()
  assert.equal(figures(v.doc).at(-1), 'Day spend partial', 'Day spend for units-answer.txt with gadgetlab null')
  assert.match(v.doc.getElementById('foot').textContent, / · units: the gadgetlab snapshot cannot be read · read 7:12 PM$/, 'the foot line for units-answer.txt with gadgetlab null')
})

test('a blocked reason sets its code spans apart, without their backticks', async () => {
  // Bug it catches: the row escaped the whole reason as plain text, so `make pay` showed with its backticks.
  const data = structuredClone(GOOD)
  const blocked = data.structuredContent.records[0].snapshot.needsYou.blocked[0]
  blocked.reason = 'build: `make pay` failed at `web/pay.ts:12`. Nothing landed.'
  const v = open(host(data))
  await settle()
  v.doc.getElementById('board').click()
  await settle()
  v.push(data)
  await settle()
  const row = [...v.doc.querySelectorAll('#needs > li')].find(li => li.querySelector('.finding-at').textContent.endsWith(blocked.card))
  assert.deepEqual([...row.querySelectorAll('code.why-code')].map(c => c.textContent), ['make pay', 'web/pay.ts:12'], `the code spans of reason ${JSON.stringify(blocked.reason)}`)
  assert.equal(row.querySelector('.finding-claim').textContent, 'build: make pay failed at web/pay.ts:12. Nothing landed.', `reason ${JSON.stringify(blocked.reason)} as written, without its backticks`)
})

test('the view answers the host teardown and reads no more after it', async () => {
  // Bug it catches: the host closes the view and waits on ui/resource-teardown for an answer that never comes, and
  // the 30 s refresh keeps calling the units tool from a closed view.
  const v = open(host(GOOD))
  await settle()
  v.win.dispatchEvent(new v.win.MessageEvent('message', { data: { jsonrpc: '2.0', id: 'td-1', method: 'ui/resource-teardown', params: {} } }))
  await settle()
  // Through JSON: the message is an object of the page's realm, which deepEqual never finds equal to one of this one.
  assert.deepEqual(JSON.parse(JSON.stringify(v.sent.find(m => m.id === 'td-1') ?? null)), { jsonrpc: '2.0', id: 'td-1', result: {} }, 'the answer to ui/resource-teardown id td-1')
  v.tick()
  await settle()
  assert.equal(v.sent.filter(m => m.method === 'tools/call').length, 0, 'a refresh called the units tool after ui/resource-teardown')
})

test('a failed refresh keeps the last data and gives the time of the last good read', async () => {
  // Bug it catches: a read that fails (the host down, ssh unreachable) blanks the card, or shows the old data as if it
  // were just read.
  const v = open(host(FAILED))
  await settle()
  v.push(GOOD)
  await settle()
  v.tick()
  await settle()
  assert.ok(v.sent.some(m => m.method === 'tools/call' && m.params.name === 'units'), 'the 30 s refresh did not call the units tool')
  assert.deepEqual(figures(v.doc), ['On belt 3 of 7', 'Ready 5', 'Waiting 2', 'Needs you 7', 'Day spend $63.10+'], 'figures after a failed read of units-answer.txt')
  assert.equal(rows(v.doc).length, 5, 'needs-you rows after a failed read')
  assert.match(v.doc.getElementById('foot').textContent, /last good read 7:12 PM · this read failed: units: the Conveyor snapshot cannot be read \(the fetch did not run\)$/)
})

test('Read again calls the units tool, and Open the board asks for full screen and lists every row', async () => {
  // Bug it catches: a button that does nothing, or a full-screen board cut to the inline card's five rows.
  const v = open(host(GOOD))
  await settle()
  v.push(GOOD)
  await settle()
  const calls = () => v.sent.filter(m => m.method === 'tools/call').length
  v.doc.getElementById('again').click()
  await settle()
  assert.equal(calls(), 1, 'Read again did not call the units tool')
  v.doc.getElementById('board').click()
  await settle()
  assert.ok(v.sent.some(m => m.method === 'ui/request-display-mode' && m.params.mode === 'fullscreen'), 'Open the board did not ask for full screen')
  assert.equal(rows(v.doc).length, 7, 'needs-you rows in full screen for units-answer.txt')
  assert.equal(v.doc.getElementById('more'), null)
})
