// SPDX-License-Identifier: Apache-2.0
import { atom, read, update } from 'claude-code'
import type { EngineInterface, Register } from 'claude-code'

import type { AutoBand } from '../types'

// /conveyor-belt:auto (commands/auto.md, conveyor/commands/auto.sh), by Max Goldfarb: its band above the prompt, its
// rules in the system prompt while it is on, and, while it is on in full, the picker refused. Everything is read
// from the engine of the session's project, `conveyor.sh auto band` and `auto rules`; a session with no Conveyor
// project (the shim fails there) draws no band.
const band = atom({ plugin: 'conveyor-belt', key: 'autoBand' } as const, null)

// Function declarations, engine and refresh: units.tsx's session.start hook reaches them past an import, where Claude
// Code follows $ only into a declaration.
async function engine($: EngineInterface, what: 'band' | 'rules') {
  const root = await $.session.root()
  const r = await $.process
    .run([`${$.plugin.root}/shim.sh`, 'conveyor/conveyor.sh', 'auto', what], { cwd: root, env: { CLAUDE_PROJECT_DIR: root } })
    .catch(() => undefined)
  return r && r.exitCode === 0 ? r.stdout : undefined
}

// The band's part of the session's start: the plugin has one session.start hook, in units.tsx (Claude Code refuses a
// second one with no matcher, and session.start takes none).
export async function refresh($: EngineInterface) {
  const out = await engine($, 'band')
  let b: AutoBand | null = null
  try {
    b = out ? (JSON.parse(out) as AutoBand) : null
  } catch {
    b = null
  }
  await update($, band, () => b)
  return b
}

export const register: Register = on => {
  // The command and the decide step run the engine through Bash: the band follows each run.
  on('tool.call', { tool: 'Bash' }, async ($, e, next) => {
    const ran = await next(e)
    if (e.command.includes('conveyor.sh auto')) await refresh($)
    return ran
  }).catch(($, e, next) => next(e)) // the band not redrawn never stops the command

  on('prompt.compose', async ($, e, next) => {
    const r = await next(e)
    const b = await read($, band)
    if (!b || b.scope === 'off') return r
    const text = await engine($, 'rules')
    return text ? { sections: [...r.sections, { id: 'conveyor-belt:auto', text, scope: 'session' }] } : r
  })

  // On in full, the owner is away: a picker would wait for nobody. Narrow leaves it open.
  on('tool.call', { tool: 'AskUserQuestion' }, async ($, e, next) =>
    (await read($, band))?.scope === 'full'
      ? { deny: 'auto is on: the owner is away. Decide this yourself by the auto rules, log it with its why, and do not ask.' }
      : next(e),
  ).catch(($, e, next) => next(e)) // a failed guard lets the picker through: asking the owner is the safe side

  on('ui.render', { component: 'AbovePrompt' }, async ($, e, next) => {
    const b = await read($, band)
    if (e.props.hasSurvey || !b) return next(e)
    // The place above the prompt is shared with other plugins: the next view stays below this one, not in place of it.
    const below = await next(e)
    const { Box, Text } = $.ui.resolve(e)
    const n = b.count
    const line = b.scope === 'narrow' ? (
      <Text color="warning">◐ auto narrow since {b.since} · {n} formalit{n === 1 ? 'y' : 'ies'} decided · /conveyor-belt:auto off</Text>
    ) : b.scope === 'full' ? (
      <Text color="error" weight="bold">● AUTO ON since {b.since} · {n} decision{n === 1 ? '' : 's'} made · /conveyor-belt:auto off</Text>
    ) : (
      <Text dimColor>○ auto off · last run: {n} decision{n === 1 ? '' : 's'} · /conveyor-belt:auto on</Text>
    )
    return (
      <Box flexDirection="column">
        {line}
        {below}
      </Box>
    )
  })
}
