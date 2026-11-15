// SPDX-License-Identifier: Apache-2.0
import { expect, mock, test } from 'claude-code/testing'

// The plugin has one session.start hook, in units.tsx: Claude Code refuses a module with two that have no matcher, so
// the /conveyor-belt:auto band's start (auto.tsx's refresh) runs from it. Catches a session start that no longer
// refreshes the band, which then stays empty until the next `conveyor.sh auto` run.
const ROOT = '/r/project'
const NOW = Date.UTC(2026, 10, 10, 4, 40, 0)

test('the session start reads the auto band from the engine and the band draws it', async ($, on) => {
  mock.clock(on, { now: NOW })
  const runs: string[][] = []
  on('session.start', (_, e) => ({ cwd: e.cwd }))
  on('session.root', () => ({ value: ROOT }))
  on('session.cwd', () => ({ value: ROOT }))
  // No Conveyor pack here (no .conveyor/project.json): the /units part of the start registers nothing.
  on('fs.stat', (_, e) => { throw new Error(`ENOENT ${e.path}`) })
  on('fs.read', (_, e) => { throw new Error(`ENOENT ${e.path}`) })
  on('process.run', (_, e) => {
    runs.push([...e.argv])
    const band = e.argv.includes('auto') && e.argv.includes('band')
    return { value: { exitCode: band ? 0 : 1, stdout: band ? JSON.stringify({ scope: 'full', since: '04:30', count: 2 }) : '', stderr: '', isStdoutTruncated: false, isStderrTruncated: false } }
  })

  await $.session.start({ cwd: ROOT, surface: 'terminal', isInteractive: true })
  expect(runs.some(a => a.includes('auto') && a.includes('band'))).toBe(true)
  const ui = await $.ui.mount({ plugin: 'conveyor-belt', surface: 'terminal', component: 'AbovePrompt', requestId: 'band', props: { hasSurvey: false } })
  const text = ((await ui.findAll({ type: 'Text' })) as { text: string }[]).map(t => t.text).join('')
  await ui.unmount()
  expect(text).toContain('AUTO ON since 04:30')
})
