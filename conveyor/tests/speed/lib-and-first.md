# The shared setup and the first four files

Measured 2026-11-14 as `README.md` says, on the loop's machine (16 cores, load average 10 to 19 during the runs),
each file alone, main first (8c035f2, from a Git checkout of main) and then this card's change. Every run passed,
every case of each file. A case's time is when the runner printed its `ok`, counted from the run's start: the cases
these rows name start first, so that is their own time to within a few tenths of a second.

| File | Before: file (slowest case) | After: file (slowest case) | Faster by | How |
| --- | --- | --- | --- | --- |
| `fail.test.sh` | 109.1 s (`apicodexrefused` 108.8 s) | 27.8 s (`apierror` 27.5 s) | 74% | `apicodexrefused` (22.5 s after) takes a turn every second (`tunables.poll = 1`): while its API error is fresh the loop starts no card and waited out whole 30 s turns. It still proves the same: up to 5 tries, each refusal marked fresh. |
| `metrics.test.sh` | 35.7 s (`metrics` 35.5 s) | 7.2 s (`metrics` 6.8 s) | 79% | `t_metrics` ran 15 fixtures one after another, each on a main of its own; each is now a case of its own (`metrics`, `metricstotals`, `metricsfail`, `metricstwo`, `metricscut`, `metricsearly`, `metricsunread`, `metricspartial`, `metricsbymodel`, `metricsretried`, `metricsshut`, `metricsstopreview`, `metricsstopretry`, `metricsstoppause`, `metricstests`), with the same fixtures and checks, and they run side by side. |
| `review.test.sh` | 82.3 s (`fuknown` 81.9 s) | 24.9 s (`repeatkept` 24.6 s) | 69% | `fuknown` (15.0 s after) keeps a body past a pipe's 64 KiB (84 KB, and the case checks it is still over 64 KiB) in 100 long lines, not 6500 short ones. |
| `stall.test.sh` | 40.9 s (`stallprogress` 40.7 s) | 11.6 s (`stallwait` 11.4 s) | 71% | `t_stallprogress` ran six kinds of progress one after another in one session; each is now a case of its own (`stallprogress`, `stallprogressrare`, `stallprogressfile`, `stallprogressignored`, `stallprogressmtime`, `stallprogresscommit`) whose session does only that kind for twice `stuck`, the others still the whole time, and they run side by side. |

## `lib.sh`

- `watchturns`: the machine loop's wait between turns is 1 s in a case, not its 5 s (`MACHINE_POLL`). A case that
  watches turns waits for a number of them, never for their seconds. The cases it changes are `machine.test.sh`'s
  (`machinecap`, `machinecards`, `machineempty`, `machinekill`, `machineroom`, all passing with it). That file's
  before and after belong to its group card's report.
- No other shared helper changed: `setup` is a small part of a case (all of `metricsshut`, its setup included, took
  1.8 s), so a fixture repository built once and copied would not save the 50% any file here needs.

The case `metrics` left `conveyor/conveyor.slowest` and `conveyor/tools/closure.slowest`: its parts take 6 s or less,
under both lists' thresholds.
