# Engine cases accounts to giveway

Measured 2026-11-14 as `README.md` says, on the loop's machine (16 cores): main (8c900a6, the card's base, from a Git
checkout of it) and this card's change, each file alone through its runner (`bash conveyor/tests/<file>.test.sh`),
three pairs, main and then the change one right after the other, so each pair ran at about the same load. Every run
passed, every case of each file.

- A file's time is the middle of its three runs: wall clock from the runner's start to its end.
- A case's time is its own seconds from its start to its end: the runner run with `CONVEYOR_TEST_LOG` set marks each
  case as running when it starts and as ok when it ends (`run_case`, `tests/lib.sh`), and those marks were looked at
  every 0.05 s. The slowest case of a run is the case with the most such seconds; the column gives the middle of the
  three runs' slowest cases.
- The load average (one minute) was 18 to 42 during the runs, other loops' tests running beside them; it is given per
  file. A case is pinned to one core (`lib/slots.sh`) and its time is the engine's work on that core, so at that load
  each case ran at about half speed, and one run of a file could take twice another's: `batchreuse.test.sh`, which
  this card does not change, took 11.2 to 25.4 s on main alone. `accounts.test.sh` and `deps.test.sh` were changed
  last and measured again then; the other eight are from one set of runs.
- The change was then brought onto main at 31eeba1. Main had changed `batchreuse.test.sh` since 8c900a6
  (`batchreuseagain` checks more of a reformed batch's passes), which this card still leaves as it is; the other nine
  files' changes applied unchanged. All ten files passed there, each alone. One more pair of the five files below 50%
  was run then, main (31eeba1) and the change, at a load of 30 to 76: the times (main, then the change: `batch` 43.6
  and 41.3 s, `batchreuse` 51.1 and 42.1 s, `flaky` 23.0 and 46.5 s, `followmain` 65.4 and 84.1 s, `giveway` 81.1 and
  62.3 s) moved with the load, not the change, and are not used in the table.

| File | Before: file (slowest case) | After: file (slowest case) | Faster by | Load | How |
| --- | --- | --- | --- | --- | --- |
| `accounts.test.sh` | 15.0 s (`accounts` 14.8 s) | 6.7 s (`accountsflight` 6.4 s) | 55% | 23 to 36 | `accounts` is in two (`accounts`, `accountsother`), `reviewacct` in four (`reviewacct`, `reviewacctown`, `reviewacctbuilder`, `reviewacctcodex`) and `acctpaths` in two (`acctpaths`, `acctpathsrel`), each one card at most, and they run side by side. The cases that read only which folder a build ran on (`accountsother`, `accountsnext`, `acctpaths`, `acctpathsrel`) build nothing, so their card ends after its build (blocked: no change to review), with no review, tests or landing. What is left is `accountsflight`, one card with a NO-GO and a fix, whose fix is the session that must start after the account changed. An earlier set of three pairs, at load 21 to 30, gave 9.6 s and 6.5 s: 32%. |
| `batch.test.sh` | 29.3 s (`batchfails` 28.8 s) | 25.2 s (`batchleftout` 24.8 s) | 13% (#359); at its floor (#389) | 29 to 40 | At its floor (#389, numbers below the table): its three slowest cases, `batchleftout`, `batchfails` and `batchtogether`, cost 41 to 43, 40 to 41 and 37 G instructions alone; half of the slowest is 20 to 21 G, about 2.4 one-card runs, and each of the three lands three or four cards with a fix or fit session and one to four batch runs, so none comes near it. On main (b73ca2f), alone: 24.0 s (`batchfails` 23.2 s), load 27 to 55. #359: `batchfails` slept 3 s in each of the five runs that had `eight` in them; it now sleeps only in the one run its check needs slow (#9 and #8, the run after #7's red one). `batchorder` is removed: `batchfails` sets an order list too ([9, 7]) and now checks what `batchorder` did, the ordered cards first in the batch though #8 was ready before them, and main's commits in the batch's order. `batchmoved` is removed: `batchmovedagain` proves the same (main gets a commit on another file during the batch's run, and the batch lands on that one run, each card its own commit on top), and now checks each card's steps and main's changes as `batchmoved` did. `batchapart` is a batch of two and one other card, not three and one: the bug, a card that applies with the batch waiting on it, needs one batch. What is left is `batchleftout`: four cards (#7, left out of the batch of #8 and #9 that wait on it, and #10 beside them), each landing; no case proves it, and it needs all four. |
| `batchreuse.test.sh` | 17.0 s (`batchreuseagain` 15.0 s) | 12.0 s (`batchreuseagain` 11.8 s) | 29% (the load's, #359); at its floor (#389) | 33 to 38 | At its floor (#389, numbers below the table): `batchreuseagain` costs 27.5 to 27.9 G instructions alone (three cards, a batch refused, #7 tested alone again, a second batch); half of it is 14 G, and every case of the file lands a batch of two or three cards, about two one-card runs (17 to 18 G) at the least: the next case, `batchreusemoved`, a batch of two that is run again, costs 18.5 G. On main (b73ca2f), alone: 12.4 s (`batchreuseagain` 12.0 s), load 26 to 52. #359: not changed: each of its five cases is one batch run of two or three cards that must land (what a batch's run reuses is the point), and its time is the engine's work for them. None is proved by another case. |
| `branch.test.sh` | 13.7 s (`branch` 13.0 s) | 4.0 s (`branchtests` 3.6 s) | 70% | 28 to 36 | `branch` ran six land-branch checks one after another on one main; each is a case of its own (`branch`, `branchfix`, `branchtests`, `branchvisible`, `branchrefused`, `branchnolink`) on a main of its own (`branchsetup`), its reviews numbered from 1 and its session, review and test counts its own. `branchrefused` moves main's a.txt itself, so the branch from the first commit still conflicts with main, as it did after the earlier landings. |
| `cardrules.test.sh` | 5.5 s (`longwait` 5.2 s) | 2.0 s (`longwait` 1.8 s) | 63% | 26 to 35 | `longwait`'s card builds nothing, so it ends after the build session that read the header (no review, tests or landing); the check that the wait does not end on an earlier run's status gives it half a second, not 3 s: the wait looks at once and then sleeps `$s` seconds, which the case now checks is at least one. |
| `control.test.sh` | 37.8 s (`control` 37.7 s) | 11.3 s (`controlpick` 11.0 s) | 70% | 18 to 25 | `control` ran five parts one after another on one record; each is a case of its own from the seeded record (`controlsetup`): `control` (the actions, health, the model settings), `controlpick` (pause, hold, order, rules, the guard), `controlcap`, `controlmodel`, `controlstop`, each with only the issues it picks. |
| `deps.test.sh` | 31.1 s (`only` 30.3 s) | 14.2 s (`only` 12.4 s) | 54% | 24 to 42 | `start` is in three (`start`, `startheld`, `startqueue`, from `startsetup`), each starting from landed lines of the issues the part before it built instead of building them again; `depends` is in three (`depends`, `dependsside`, `dependscycle`), `followdeps` in two (`followdeps`, `followdepscycle`), `only` in two (`only`, `onlyheld`). A card these cases need only picked, not landed, builds nothing and ends after its build (blocked: no change to review): every card of the start cases, `followdeps` and `onlyheld`, #12 in `dependsside`, and in `only` all but #21, which #26 waits on. `only` builds four cards with a limit of two, not six with a limit of four: three are free to build, so a loop that builds past the limit builds three at once. |
| `flaky.test.sh` | 7.3 s (`flakybatch` 7.0 s) | 6.9 s (`flakybatch` 6.7 s) | 5% (#359); at its floor (#389) | 18 to 24 | At its floor (#389, numbers below the table): `flakybatch` costs 16.0 to 16.8 G instructions alone, about two one-card runs (8.4 to 9.0 G each, 1.9 to 2.1 G of which is the runner's start), as it lands two cards on four test runs; half of it, 8 G, is less than one card's run, and `flakyrerunfail` (one card, a fix, three test runs) costs 13 G. On main (b73ca2f), alone: 7.4 s (`flakybatch` 6.9 s), load 25 to 50. #359: sped up, not enough. `flakybatch` lands a batch of two cards (#8 and #7), not three: the bug, an entry lost when the batch's run passed first time after #7's own run passed on re-run, needs one card beside #7. Four test runs, not five. Its two cards must each pass their own tests and land in one batch, so it cannot be halved again, and no other case proves it. |
| `followmain.test.sh` | 17.3 s (`followtake` 16.6 s) | 14.2 s (`followtake` 13.5 s) | 17% (#359); at its floor (#389) | 19 to 27 | At its floor (#389, numbers below the table): `followtake` costs 29 to 30 G instructions alone and `followrefuse` 23.5 to 24.4 G, both above half of it (15 G). `followtake` is one `serve` that starts on an install (`followpin`, serve on an install for two turns and nothing else, costs 7.9 G), takes a second commit while a card is in flight, restarts on it, builds two cards and is asked for its health; a quarter of its CPU is `ps` and `pgrep`, the restarted loop watching the processes of the card it adopted, at each turn (lib/run.sh), the engine's work and not the case's. Its checks all need that one loop across the take, so it does not split into halves that cost less. On main (b73ca2f), alone: 13.5 s (`followtake` 13.1 s), load 25 to 45. #359: sped up, not enough. `followprune` is in four (`followprune`, `followprunelane`, `followpruneother`, `followprunelist`, from `prunesetup`, each with only the takes it needs and a host file of its own, as two of them write one); `followpin` waits for one whole turn after serve's first look at main, not three; `followtake` waits for the loop's `loop.json` to name the new commit, then asks health once, instead of asking health until it does, and its two cards build nothing, so they end after their builds (its checks read their worktree lines and that #7's build ran to its end). What is left is `followtake`: serve installs and takes a commit of main, takes the next while a card is in flight and restarts on it, a turn of one second at least each time, all on the case's one core. |
| `giveway.test.sh` | 16.0 s (`givewayback` 15.6 s) | 14.7 s (`givewaykeep` 14.3 s) | 8% (#359); at its floor (#389) | 21 to 35 | At its floor (#389, numbers below the table): four cases cost 20 to 25 G instructions alone each (`givewaykeep` 25.0 to 25.4, `givewayback` 21.7 to 21.9, `giveway` 20.4 to 21.3, `givewayfix` 20.3 to 20.9), and half of the slowest is 12.5 G, under one and a half one-card runs; each lands two cards, one of them through a rebase session, a second review and a second test step. On main (b73ca2f), alone: 13.6 s (`givewaykeep` 12.8 s), load 26 to 45. #359: sped up, not enough. The rebase session took a snapshot of the Board in every `gwsetup` case; only `giveway` and `givewaykeep` read it, so only they take one (`$STUB/snapit`). Each case is one run of two cards that both land (the land turn is the point), one through a rebase, and its time is the engine's work for them; none is proved by another case. |

Not met: five of the ten files are not 50% faster (`batch`, `batchreuse`, `flaky`, `followmain`, `giveway`). Their
slowest cases are runs of two to four cards that must each be reviewed, tested and land, as the behaviour they
prove is a landing (a batch, a land turn, a pass reused); on its one core a card costs about 3 s of the engine's work
(a one-card run started 286 `jq`, 81 `git` and 92 `flock`), so such a case cannot be halved while it proves the same
thing. `followmain`'s is serve installing and taking two commits of main and restarting on the second, the engine's
work on the case's one core too. The shared change each needs, under "Shared helper ideas": `batch`, `batchreuse`,
`flaky` and `giveway` the engine reading its control record and pack once per step; `followmain` that too and a test
pack's turn under one second (`tunables.poll`, `tunables.idle`). No case was found that another case already proves, other than `batchorder` and `batchmoved`, nor one that tests
code that no longer exists or asserts nothing.

No case was skipped and no limit or timeout raised. No file was removed, so `.conveyor/engine-areas.json` needs no
change. The cases that were split are still cases under their old names; `batchorder` and `batchmoved` are named in
neither `conveyor/conveyor.slowest` nor `conveyor/tools/closure.slowest`, so both name only cases that exist.

## The five files short of 50%, measured again (#389)

Measured 2026-11-14 on the loop's machine (16 cores), main at b73ca2f (after #379, which reads the pack once per
process), from a Git checkout of it. No case file is changed: none of the five could be halved, so each is at its floor
(its row above). Every run passed, every case of each file.

- A file's time alone: `bash conveyor/tests/<file>.test.sh`, three runs, the middle one given, its slowest case from
  the runner's marks as above. The load average was 25 to 55, and one file's time moved by up to twice between runs at
  about the same load (`flaky` 3.5 and 7.4 s, `batchreuse` 7.0 and 14.0 s), its CPU seconds with it.
- So the floor is shown by what the load does not move: the instructions a case runs, all its processes counted
  (`perf stat -e instructions` on the runner given that one case), two runs each, within 5% of each other.
- The runner's start-up: a case that does nothing, 0.63 to 0.68 s and 1.9 to 2.1 G instructions. The engine's
  start-up: one `conveyor.sh check` in a set-up project, 0.10 to 0.11 s and 0.44 G. One card's run (one issue built,
  reviewed GO, tested, landed and pushed: `loop run 1` after `setup`): 3.1 to 3.5 s and 8.4 to 9.0 G, the runner's
  start-up among them.

| File | Alone: file (slowest case) | Its slowest cases, instructions alone | Half of the slowest |
| --- | --- | --- | --- |
| `batch.test.sh` | 24.0 s (`batchfails` 23.2 s) | `batchleftout` 40.7 to 42.6 G, `batchfails` 40.1 to 41.3 G, `batchtogether` 36.7 to 36.8 G | 20 to 21 G |
| `batchreuse.test.sh` | 12.4 s (`batchreuseagain` 12.0 s) | `batchreuseagain` 27.5 to 27.9 G, `batchreusemoved` 18.5 G | 14 G |
| `flaky.test.sh` | 7.4 s (`flakybatch` 6.9 s) | `flakybatch` 16.0 to 16.8 G, `flakyrerunfail` 13.0 to 13.2 G | 8 G |
| `followmain.test.sh` | 13.5 s (`followtake` 13.1 s) | `followtake` 29.1 to 30.3 G, `followrefuse` 23.5 to 24.4 G | 15 G |
| `giveway.test.sh` | 13.6 s (`givewaykeep` 12.8 s) | `givewaykeep` 25.0 to 25.4 G, `givewayback` 21.7 to 21.9 G, `giveway` 20.4 to 21.3 G, `givewayfix` 20.3 to 20.9 G | 12.5 G |

The runner's start-up is 5 to 13% of these cases; with none at all, no file would be halved. What a case costs is
the engine's work for its cards: of the 5,675 programs `batchfails` starts, the cases' own waits (a `jq` look every
0.1 s) are 142, and of `flakybatch`'s CPU, `bash` is 38%, `jq` 34% and `git` 8%, spread over the engine's steps with
no one of them most. Halving these files needs the engine to do less per card (in `followtake`, `ps` and `pgrep` are
a quarter of the CPU: the restarted loop looking at the processes of the card it adopted, at each turn, lib/run.sh).

## Shared helper ideas

- `conveyor/tests/lib.sh`: none from this group.
- The engine (not a test helper, and not this card's): a card in these cases costs about 3 s of one core, and a case's
  cards share its slot's one core, so a case of two to four cards is as slow as the engine's work for them. One run of
  `batchland` (three cards) started 1,236 `jq` and 533 `git`; one run of `giveway` (two cards) 858 `jq` and 311 `git`:
  the control record merged with its seed (`($d * .) | .rules = ...`) 57 times, and the pack read (`packget`) about 55
  times. Reading each once per step would make every case of cards faster, and is what the files left above need.
- `conveyor/schema/pack.schema.json`: `tunables.poll` and `tunables.idle` are whole seconds, at least 1, so a case that
  waits for the loop's turns (`followtake`, `followpin`, `controlstop`) waits a second a turn. A test pack allowed
  less would cut them.
- `conveyor/tests/speed/README.md`: at a load average of 20 to 40 one run of a file can take twice another's (above:
  `batchreuse`, unchanged, 11 to 25 s on main). Measuring at a quiet hour, or each case's CPU seconds (user and system,
  which the load moves far less), would show what a change to a case file did.
