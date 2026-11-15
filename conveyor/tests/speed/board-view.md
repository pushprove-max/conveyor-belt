# Board view tests

Measured 2026-11-14 as `README.md` says, on the loop's machine (16 cores), each file alone through its runner
(`node --max-old-space-size=4096 --test <file>`, the runner `npm run test:files` uses). Before is main (d9c1ed8, a
`git clone --shared` of main), after is this card's change, run one after the other, file by file, eight rounds of
each. Every run passed, every case of each file. A file's time is its `node --test` process from start to end; a case's
time is its `duration_ms`. Each number is the median of the eight runs.

The machine was busy throughout: load average 17 to 42 on 16 cores, so a single run of one file swung by two to three
times. The medians are what to read, not one run.

The floor, measured in the same rounds: Node and the test runner with one empty case, 0.15 s; with jsdom loaded and one
page made, 1.10 s (0.67 to 1.25 s from round to round). A file can be no faster than that plus its slowest case.

## What was done

- `dashboard-view.helpers.mjs` gives a file `cases(import.meta.url)`, the `test` it registers its cases with. Each case
  runs in one of at most four worker threads, side by side, each with its own jsdom; node:test still reports every case
  by its name, in the file's order, and a case fails with the error its body threw. A worker checks the case it is given
  by its name as well as its place, so a file whose cases differ between loads fails rather than runs the wrong body.
  Every case still boots its own page and asserts what it did.
- Four workers, not eight: each worker loads jsdom and warms its own compiled code. On this machine, eight took about
  40% more CPU than four (`page`: 30 to 33 s against 20 to 24 s of user time, main 13 s) and ran slower, since the
  machine had no core to spare: medians of three rounds with eight, `rules` 4.52 s against main's 3.84 s, `overview`
  3.38 s against 3.93 s.
- jsdom is loaded at the first `boot`, not on import, so `fit`, which takes only the snapshots, never loads it. Node's
  compile cache (`module.enableCompileCache`) keeps jsdom's compiled code for the next worker: about 0.6 s less CPU over
  a file's workers.
- `fit` renders its pages side by side: case 1's nine Chromium renders (three widths by three tabs) and case 3's two
  widths, each browser with a profile of its own, and its three cases run side by side (a suite with `concurrency:
  true`). Every page is still rendered and checked the same way.

## Files

| File | Before: file (slowest case) | After: file (slowest case) | Faster by | What was done |
| --- | --- | --- | --- | --- |
| `dashboard-view.account.test.mjs` | 0.86 s (0.17 s) | 0.47 s (0.11 s) | 45% | At its floor: two cases, 0.17 s; the file is under the 1.10 s floor (it loads jsdom and makes no `boot` page). Not changed. |
| `dashboard-view.belt3d-scene.test.mjs` | 0.92 s (0.11 s) | 0.88 s (0.09 s) | 4% | At its floor: 0.92 s against the 1.10 s floor; three cases of 0.11 s at most. Not changed. |
| `dashboard-view.belt3d.test.mjs` | 3.81 s (0.45 s) | 1.52 s (0.76 s) | 60% | Sped up: its 14 cases in four workers. |
| `dashboard-view.board.test.mjs` | 8.09 s (0.85 s) | 3.61 s (0.74 s) | 55% | Sped up: its 23 cases in four workers. |
| `dashboard-view.brand.test.mjs` | 0.91 s (0.30 s) | 0.61 s (0.44 s) | 32% | At its floor: 0.91 s against the 1.10 s floor and a 0.30 s case. Not changed. |
| `dashboard-view.cards.test.mjs` | 11.62 s (1.10 s) | 3.63 s (0.89 s) | 68% | Sped up: its 41 cases in four workers. |
| `dashboard-view.deps.test.mjs` | 2.46 s (0.33 s) | 1.32 s (0.57 s) | 46% | At its floor after the change: 1.32 s against the 1.10 s floor and its 0.33 s slowest case (1.43 s). Its nine cases in four workers. |
| `dashboard-view.fit.test.mjs` | 7.23 s (3.81 s) | 1.71 s (1.59 s) | 76% | Sped up: its browsers render side by side and its cases run side by side (above). Its cases are still registered by lines that start `test(`, the name `.conveyor/test-changed.sh` counts a file's cases by. |
| `dashboard-view.helpers.mjs` | shared setup | shared setup | — | `cases()`, jsdom at the first `boot`, the compile cache (above). |
| `dashboard-view.layout.test.mjs` | 7.31 s (1.34 s) | 2.92 s (0.67 s) | 60% | Sped up: its 22 cases in four workers. |
| `dashboard-view.login.test.mjs` | 0.59 s (0.10 s) | 0.40 s (0.08 s) | 33% | At its floor: two cases, 0.10 s; the file is under the 1.10 s floor. Not changed. |
| `dashboard-view.machine.test.mjs` | 4.29 s (0.70 s) | 2.13 s (1.02 s) | 50% | Sped up: its 14 cases in four workers. |
| `dashboard-view.overview.test.mjs` | 4.33 s (0.43 s) | 3.30 s (0.83 s) | 23% | Short of 50%, accepted by the owner's rule of 2026-11-14 (faster than main; what was tried and why it falls short are below). Its 23 cases in four workers. Eight more rounds of main against the card (load 17 to 47): 3.62 s against 2.46 s, 32%; eight at load 16 to 19: 4.31 s against 2.96 s, 31%; eight at load 10 to 13: 3.40 s against 2.11 s, 37%. Not at its floor: 1.10 s and its 0.43 s slowest case are 1.53 s. Not removed: no case proves what another does. What else was tried is below. |
| `dashboard-view.page.test.mjs` | 10.79 s (0.72 s) | 4.86 s (1.08 s) | 54% | Sped up: its 87 cases in four workers. |
| `dashboard-view.projects.test.mjs` | 4.49 s (0.81 s) | 2.37 s (1.35 s) | 47% | Short of 50%, accepted by the owner's rule of 2026-11-14 (faster than main; what was tried and why it falls short are below). Its 14 cases in four workers. Eight more rounds: 3.91 s against 3.02 s, 23%; at load 16 to 19: 4.72 s against 2.87 s, 39%; at load 10 to 13: 3.67 s against 2.24 s, 38%. Not at its floor: 1.10 s and its 0.81 s slowest case are 1.91 s. Not removed: no case proves what another does. |
| `dashboard-view.rules.test.mjs` | 3.83 s (0.62 s) | 2.29 s (0.78 s) | 40% | Short of 50%, accepted by the owner's rule of 2026-11-14 (faster than main; what was tried and why it falls short are below). Its 17 cases in four workers. Eight more rounds: 5.81 s against 3.42 s, 41%; at load 16 to 18: 4.51 s against 2.66 s, 40%; at load 10 to 13: 3.87 s against 2.32 s, 39%. Not at its floor: 1.10 s and its 0.62 s slowest case are 1.72 s. Not removed: no case proves what another does. |
| `dashboard-view.timeline.test.mjs` | 1.65 s (0.66 s) | 1.65 s (0.66 s) | 0% | At its floor: 1.65 s against the 1.10 s floor and its 0.66 s slowest case (1.76 s). Workers measured no faster here (1.70 s), so not changed. |

A case's "after" time is how long node:test waited for it. The first case of each worker waits for that worker to load
jsdom, so the slowest case after is often the first one.

## Why overview, projects and rules are short of 50%

The owner, 2026-11-14: a file that is neither 50% faster nor at its floor is accepted when its row shows the speed-up
it reached and this report shows what was tried and measured and why it falls short. The change is kept for these
three because each is faster than main in every set of rounds above (23 to 47%).

Each of the three runs its cases in four workers, as the files that met 50% do, but has less work to share out
(14 to 23 cases of 0.1 to 0.5 s), so a worker's own start costs a larger part of the file. A worker loads jsdom again
(0.45 to 0.55 s of CPU, `require('jsdom')` alone; the compile cache saves about a tenth of it) and warms its own
compiled code, so four workers spend about half again the CPU of main's one process (`rules`: 15 s of user time
against 10 s at load 45). On this machine, never idle while these were measured, that CPU is not free.

What was tried and did not help, measured in the same way:

- Six or eight workers instead of four: four rounds of each at load 27 to 49, no count faster than four.
- A larger young generation (`--max-semi-space-size` 32, 64, 128): the same CPU time for 40 page boots.
- Removing cases: by their names, each of the 54 cases checks a behaviour no other case of the three files
  checks, so none is removed.
- Each page script compiled once (`vm.Script`) and run in each page's context instead of `window.eval`: a boot and
  first draw of Overview took the same 60 to 66 ms; V8 already keeps the compiled scripts.
- The longest cases sent to the workers first, so no worker is left with a long case at the end: four rounds each,
  the same times within the noise (`rules` 1.91 to 2.43 s against 1.98 to 2.40 s).
- One file instead of two (`rules` with `deps`, `overview` with `page`), so a file's start-up is paid once: four
  rounds against main's two files run one after the other, 37 to 57% for `rules` with `deps`. Not kept: it does not
  reach 50% either, and `conveyor/tests/machine.test.sh` names `dashboard-view.overview.test.mjs`.
- V8 flags for a faster warm-up (`--always-sparkplug`, `--no-lazy-feedback-allocation`, `--no-opt`, `--max-lazy`) and
  a worker young generation of 48 or 96 MB: no less CPU and no faster.

Measured: a worker's start costs 0.55 to 0.8 s before its warm cases (0.3 s to load the test file and jsdom, then a
first case 0.25 to 0.5 s slower than warm), and four copies of main's `rules` side by side each take about 40% longer
than one alone, so the machine itself (8 cores, 16 threads) charges for running side by side. The card's files spend
about twice main's CPU (`rules`: 11 to 12 s of user time against 5 to 6 s), and that CPU is what the three files'
cases cannot share out past 40%.

Where a case's time goes (a CPU profile of 40 `boot`s of the Rules tab, and of `rules` on main): the page's own
`start` (frames for every panel, about 130 ms a boot), jsdom building the window and parsing `index.html` (about 75 ms),
then the page's `draw` on each snapshot (half of `rules`). The test code itself is a few percent. Those costs are the
page's and jsdom's, outside this card's files: the second idea below.

## Shared helper ideas

- The runner, not a helper (`package.json` `test:files`, `dashboard-view.test.sh`): split the long files (`cards`,
  `page`, `board`) into files of about 1 s that the runner runs side by side, as `README.md` does for engine cases.
  That cuts their time alone, not their work, and it moves cases into new files: the owner's call. Done, and
  measured: "The long files split" below. It makes the whole set slower, not faster.
- Most of a case's time is the page's own drawing on each snapshot (`draw` in `index.js`, about half of `cards`'
  profile) and jsdom building elements, each with its inline style object (`CSSStyleDeclaration`, 6% of the profile on
  its own). A page that redrew only the panels a snapshot changed would make every case cheaper; that is a change to
  the page, outside this card.

## The long files split (cards, page, board)

The owner's order of 2026-11-14 (recommendation 5): split `cards`, `page` and `board` into files of about 1 s each,
no case lost, and measure the Board view tests' total time before and after.

### What was done

Each file is cut along its own sections into files that hold its cases unchanged, in the same order: every line of
the three files but their two- or three-line file heads is in exactly one new file (a sorted diff of the code lines,
and of the comment lines, of the three against the ten), and each new file imports only what it uses
(`tsc --noUnusedLocals` finds no unused or missing name). The shared setup, `dashboard-view.helpers.mjs`, is
unchanged but for the panel-state loop (below): each new file still runs its cases in at most four workers.

| Was | Cases | Now | Cases |
| --- | --- | --- | --- |
| `dashboard-view.cards.test.mjs` | 41 | `cards-track` (a card along its steps), `cards-lines` (fix, review, cost, gave way, batches), `cards-blocked` (a blocked card, its output; numbers that count), `cards-answers` (the page's writes from Needs you), `cards-needs` (the rest of Needs you, Declined, the judge line, re-run) | 7 + 9 + 8 + 8 + 9 = 41 |
| `dashboard-view.page.test.mjs` | 87 | `page-panels` (the panel list; the first half of the panels' three states and own part), `page-states` (the second half), `page-live` (markup, refresh, one look, the top bar, the live feed), `page-tabs` (the tabs, the head tiles) | 28 + 28 + 18 + 13 = 87, and a check that `page-panels` and `page-states` name every panel's four cases (below) |
| `dashboard-view.board.test.mjs` | 23 | `board-control` (the loop steered from the Board), `board-held` (answers against snapshots, every open issue, a long column) | 11 + 12 = 23 |
| three files | 151 | eleven files (`dashboard-view.<name>.test.mjs`) | 151, every one passing |

### Measured

The same day, on the loop's machine (16 threads), main (a `git clone --shared` of main at 6da8c8a, whose Board view
files are the card's base) against the card, through `node --max-old-space-size=4096 --test`. Other
cards ran their tests the whole time: load average 16 to 90, swinging within a minute, so each "before" ran next to
its "after", the order swapped every round.

Each file alone, six rounds: the round at the lowest load (16 to 21), and the median of the six (load 17 to 66).

| File | Lowest-load round | Median |
| --- | --- | --- |
| `cards` (main) | 2.60 s | 4.69 s |
| `cards-track`, `-lines`, `-blocked`, `-answers`, `-needs` | 1.24, 1.23, 1.16, 1.61, 1.27 s | 2.73, 1.66, 1.84, 2.25, 2.21 s |
| `page` (main) | 3.76 s | 5.03 s |
| `page-panels`, `-live`, `-tabs` | 2.10, 1.60, 1.35 s | 2.78, 2.35, 2.31 s |
| `board` (main) | 2.99 s | 4.11 s |
| `board-control`, `-held` | 1.28, 1.41 s | 2.33, 2.55 s |

Nine of the ten are about 1 s at that load (1.1 to 1.6 s, against the 1.10 s floor above); `page-panels` was 2.1 s,
and is split again below ("page-panels in two"). The split files of one old file run
together, side by side, are about as fast as the old file: `cards` 3.62 s against 2.60 s, `page` 4.32 against 3.76,
`board` 3.00 against 2.99 at the lowest load; medians 5.15 against 4.69, 4.83 against 5.03, 3.71 against 4.11.

The Board view tests' total: every `dashboard-view.*.test.mjs` in one `node --test`, as `npm run test:files` runs
them, 301 cases without `fit` (its Chromium renders swing by tens of seconds), main and the card in turn, eight pairs.
Wall time, and CPU time (user and system, `/usr/bin/time`):

| Pair | Load | Before: wall (CPU) | After: wall (CPU) |
| --- | --- | --- | --- |
| 1 | 21 to 30 | 14.37 s (179 s) | 17.74 s (232 s) |
| 2 | 38 to 40 | 14.47 s (194 s) | 18.20 s (231 s) |
| 3 | 44 to 53 | 17.14 s (196 s) | 20.63 s (236 s) |
| 4 | 55 to 57 | 17.04 s (194 s) | 21.82 s (235 s) |
| 5 | 55 to 71 | 17.89 s (195 s) | 39.34 s (240 s) |
| 6 | 77 to 82 | 38.29 s (202 s) | 47.22 s (241 s) |
| 7 | 78 to 81 | 36.34 s (200 s) | 34.60 s (239 s) |
| 8 | 79 | 34.90 s (200 s) | 36.16 s (241 s) |

With `fit`, one pair at load 60 to 90: 57.7 s (208 s of CPU) against 102.0 s (247 s); every case passed in each run.

### Why the total is slower

The whole set already keeps 12 to 13 of the 16 threads busy (179 s of CPU in 14.4 s at its least loaded), so its
floor is the machine's CPU, not its longest file: running more files side by side frees no time. And each file starts
its own workers, each loading jsdom and warming its code (about 1 s of CPU a worker, above): the three long files
started 12 workers, the ten started 40 (the eleven, 44). The CPU time rose 21% (medians 196 s against 237 s), in every pair, and the
wall time with it in seven pairs of eight (by 3.4 to 4.8 s, 20 to 28%, in the four pairs at load 21 to 57). The split lowers a file's time
alone, as the idea said, but not the time of the Board view tests run together.

Not tried, outside this card: fewer workers for a small file (the helper's four at most, `cases()`), which would
take back most of the 28 extra worker starts but make each split file slower alone.

### page-panels in two

At 56 cases, `page-panels` was the one split file not about 1 s (2.10 s at the lowest load, 2.78 s median, above). Its
52 panel-state cases (data, empty, failed to load, drawn from its own part; four a panel) were one loop over the panel
list; their bodies are now `panelState` in `dashboard-view.helpers.mjs`, and two files name each case on its own
`test(` line: `page-panels` keeps the panel list's own four cases and the first 6 panels (28 cases), `page-states` the
other 7 (28 cases). One `test(` line a case because `.conveyor/test-changed.sh` counts a file's cases by those lines
(a loop's four lines counted 4 of its 52, and a helper's none), so the Board's test progress and failure counts see
every case; a fifth case of `page-panels` checks the two files name all four for every panel of the list. No case
lost: 56 before, 28 + 28 after (29 with that check), every one passing, and each file's counted cases equal node's.

Measured the same day as the card's change, the ten files (before) against the eleven (after), three rounds, the
order swapped every round; other cards' tests kept the load at 52 to 93 throughout, so no round is near the 1.10 s
floor, and the ratio is the figure to read:

| Round | Load | `page-panels` before (56) | `page-panels` after (28) | `page-states` (28) |
| --- | --- | --- | --- | --- |
| 1 | 52 to 55 | 16.24 s | 9.98 s | 10.34 s |
| 2 | 82 to 93 | 12.13 s | 7.12 s | 9.64 s |
| 3 | 73 to 81 | 10.89 s | 5.63 s | 5.86 s |

Each half takes 0.52 to 0.79 of the whole (median 0.60); at the 2.10 s lowest-load figure above that is about 1.3 s
a file, as the other nine are.

The Board view tests' total, 301 cases without `fit`, the ten files against the eleven in turn: wall 40.34 s against
47.07 s (load 54 to 72), 35.55 against 38.36 (73 to 81), 37.80 against 37.86 (71 to 81); CPU (user and system)
243.2 s against 245.1 s, 240.0 against 245.5, 240.6 against 244.5. The four more workers cost 1 to 2% more CPU, and
the total is as the section above says: no faster for the split.
