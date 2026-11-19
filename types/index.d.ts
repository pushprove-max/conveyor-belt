// SPDX-License-Identifier: Apache-2.0
// The band /conveyor-belt:auto draws (hooks/auto.tsx), as `conveyor.sh auto band` prints it.
export type AutoBand = { scope: 'full' | 'narrow' | 'off'; since: string | null; count: number }

declare module 'claude-code' {
  interface PluginState {
    // autoBand: hooks/auto.tsx. The others are the /units views' atoms (hooks/units.tsx); `state` is sources.ts's
    // State, which the contract file cannot import.
    'conveyor-belt': {
      autoBand: AutoBand | null
      state: Record<string, unknown> | null
      view: { band: boolean; pane: boolean; status: boolean }
      frame: number
      details: boolean
      now: number
    }
  }
}
