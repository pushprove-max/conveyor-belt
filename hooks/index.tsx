// SPDX-License-Identifier: Apache-2.0
import type { Register } from 'claude-code'

import { register as auto } from './auto'
import { register as units } from './units'

// The plugin's one hooks module (hooks.json `modules` takes one path): the /conveyor-belt:auto band and the /units views.
export const register: Register = (on, options) => {
  auto(on, options)
  units(on, options)
}
