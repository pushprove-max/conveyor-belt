# Engine test speed

The owner asked that every case file of the engine's full suite (`conveyor/tests/*.test.sh`) run at least 50% faster,
or be removed with a reason. Each card of that work writes its own report here, one row per case file it covered:
`lib-and-first.md` for the shared setup (`lib.sh`) and the first four files, and `<group>.md` for each group card, so no
two cards edit one report.

## How a file is measured

- Alone: the file's cases and nothing else of the suite, through the runner (`bash conveyor/tests/<file>.test.sh`,
  which runs its own cases through `conveyor/conveyor.test.sh`). Its cases run side by side, as many as the machine's
  test slots allow, so the file's time is close to its slowest case's.
- A card's Test step runs each case file the same way, as a test file of its own: its own process and test slot,
  with only the cases the change selects of it, side by side with the other case files it selects. Each one pays
  the runner's start-up once (about 0.4 CPU s on the build machine). Its result and its time name the case file, and
  the time counts toward that file's own CPU budget only when the step ran all of the file's cases.
- On the machine that runs the loop, with whatever else it runs at the time: the same machine and about the same load
  for the before and the after. Note the load average next to the times when it is far from usual.
- Two numbers, before and after: the file's time (wall clock, from the first case started to the last ended) and its
  slowest case with that case's time, as the file ran (each case's own seconds from its start to its end).
- Before is main, from a Git checkout of main outside the card's worktree (`git clone --shared --branch main <repo>
  <folder>`), so the worktree is never switched; after is the card's worktree. Not a copy of main's tree without its
  Git repository (`git archive`): some cases run Git on the checkout itself and fail there (`fail.test.sh`'s
  `corrupt`). Both runs pass, every case of the file, or the time means nothing.
- Faster by: `1 - after / before`, of the file's time, rounded down to whole percent.

## Rules (every card of this work)

- Each case file is measured on main first. Then it is either sped up by at least 50% while it still proves the same
  thing, or removed when another case already proves the same behaviour (the row names it), it tests code that no
  longer exists, or it asserts nothing that could fail when the behaviour breaks.
- No test limit or timeout is raised and no case is skipped.
- `.conveyor/engine-areas.json` stays true: every remaining case file is named by an area; a removed file leaves it.
- A case renamed or split leaves `conveyor/conveyor.slowest` and `conveyor/tools/closure.slowest` naming only cases that
  exist.

## Rules for every test (its author and its reviewer)

The same three rules are in the card rules (`.conveyor/card-rules.md`), so every card and review sees them;
`.conveyor/card-rules.test.sh` checks both places hold them.

- No wrapper that only runs other tests again. Why: the test run already runs those tests, so the wrapper proves
  nothing they do not and doubles their time. #357 removed two: `dashboard-view.test.sh` (26.38 s) and
  `dashboard-collector-incremental.test.sh` (4.98 s), 31 s of every run cut (`board-server.md`).
- A case that runs several fixtures one after another is split into one case per fixture. Why: the runner runs cases
  side by side, so the file takes about its slowest fixture, not their sum: `metrics` 35.7 s to 7.2 s (79% cut) and
  `stall` 40.9 s to 11.6 s (71% cut) (`lib-and-first.md`).
- A case that proves one engine function calls that function; a whole card run is kept for what only a whole card
  proves. Why: a card run pays for the loop, its sessions and its waits around the one function: `testfails` 13.62 s to
  3.14 s (76% cut, #362) and `testrec` 19.26 s to 1.99 s (89% cut, #371) (`cases-4.md`).

## How a split is checked, and a budget of its own

An Optimize card that splits a test file passes its check when every case passes, each new file is at or under its
budget (the pack's `test.fileBudget`, or the file's own in `test.files`), and the new files' CPU seconds summed are at
most the old file's on record plus a start-up allowance for each new file. The allowance is the CPU seconds of a run of
a new file with no case selected, when that run names no case. An engine case file run so runs the runner with no
case. A runner with no case filter runs the whole file, so
then the allowance is the pack's `test.splitAllowance`, as it is when that run gives no CPU seconds. A split never makes the
sum lower, so a split into too few files fails: the card's brief says how many files a split alone needs. Make the
heavy cases faster, or make the split finer.

A file whose cases cannot fit the budget without losing what they test gets a budget of its own: the build ends its
reply with `OWN-BUDGET: <CPU s> CPU s: <why>`, the card stops for the owner's yes, and the yes puts that budget in
`test.files` for the file. `conveyor/README.md` (The CPU budget of a test file) has the details.

## Ways that worked

- Split a case that runs several fixtures one after another into one case per fixture: the runner runs them side by
  side (metrics, stall).
- Shorten a loop's wait between turns where the case waits for its turns, not their seconds (`tunables.poll`, the
  machine loop's poll in `watchturns`).
- Make a fixture as large as the bug needs in as few lines as that takes: an issue body of 6500 short lines cost a
  case about 95 s more than the same bytes in 100 long lines.
