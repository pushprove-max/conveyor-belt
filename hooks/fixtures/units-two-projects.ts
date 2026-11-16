// SPDX-License-Identifier: Apache-2.0
// What hooks/units-fetch.sh prints for a host file with two projects, bakery and gadgetlab, neither of them the
// plugin's own, run in bakery's main checkout with the home folder at /r/HOME. hooks/units-fetch.test.sh checks that
// the fetch prints exactly this for that host file (each record's stub engine prints its line below); units.test.tsx
// draws /units from it. One line a record, its fields split by tabs (\t).
export const TWO_PROJECTS = `paths\t\t/r/HOME\tbakery
fast\tnone
host\tlab\tlocal\t0
bakery\t{"time":"2026-11-10T04:40:00Z","day":"2026-11-10","needsYou":{"waiting":[],"blocked":[]},"belt":[{"card":"c1-12","issue":12,"title":"Bread oven timer","step":"build","review":null,"of":3,"tokens":{},"usd":null,"reading":false}],"queue":{"next":[],"held":{}},"landed":[],"health":{"loop":true,"state":"paused"},"cost":{"today":1.5}}
gadgetlab\t{"time":"2026-11-10T04:40:00Z","day":"2026-11-10","needsYou":{"waiting":[],"blocked":[]},"belt":[{"card":"c2-7","issue":7,"title":"Gear ratio chart","step":"review","review":1,"of":3,"tokens":{},"usd":null,"reading":false}],"queue":{"next":[],"held":{}},"landed":[],"health":{"loop":true,"state":"running"},"cost":{"today":2}}
`
