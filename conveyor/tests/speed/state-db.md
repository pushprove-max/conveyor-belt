# The engine state in SQLite (state.py): before and after

Issue 537 moved the engine's state to a SQLite database (`conveyor/state.db` in the state folder) that one Python
helper, `conveyor/state.py`, reads and writes. Every append and every rewrite of the card records, the retried lines,
the samples, the declined list and the limit readings goes through it (to its table and its file both: the
transition, issue item 4); the snapshot takes its copy of the records, the pushes, the cards waiting for the owner's
yes, the samples and the declined list from it in one call, and every other reader in `conveyor/lib/` asks it, but
`check()` (lib/views.sh), which checks the card records file's own bytes. Each call reads only what was added to a
file since the last call (and the file's first and last 4 kB), not the whole history.

Before is main at 8d2d038 (a `git clone --shared` of main); after is the card's change on the same commit. Both were
run on the machine that runs the loop, with the load average noted. CPU s is user plus system time of the whole
command and every program it started (`/usr/bin/time`).

## The snapshot

A copy of the real history (cards.jsonl 4.1 MB, 9,253 lines; retried.jsonl 1.8 MB, 3,066 lines; samples, limit and
declined files), in a test case's checkout (`setup`, GitHub stubbed), `conveyor.sh snapshot` three times: the first
(no running summary, and after the change no database: the import), the second (nothing new), the third after one
more line in the card records.

| Snapshot | Before (CPU s) | After (CPU s) |
| --- | --- | --- |
| First (the summaries made; after: the import too) | 5.25 | 5.35 |
| Second, nothing new | 3.32 | 3.18 |
| After one new line | 3.36 | 3.24 |

The snapshot's CPU is mostly its other work (the rows of the cards, rows.jq; the queue; the metrics): the reads moved
here were five `jq` runs over the records, two of them over the whole 6 MB, and are one helper call now. This table
was measured before the review's fixes (the declined list read in the same call, each call reading only what was
added); it was not measured again on the real history.

## The engine tests

Each file alone, through the runner (`bash conveyor/tests/<file>.test.sh`). Load average at the start of each run in
brackets. The after column is the change with every reader and writer moved to the helper, run one file after
another at a load of 10.5 to 12.8.

| Case file | Before (CPU s) | After (CPU s) | Change |
| --- | --- | --- | --- |
| snapsum.test.sh | 6.86 | 7.50 (12.8) | +9% |
| snapshot.test.sh | 1.79 | 1.94 (12.8) | +8% |
| views.test.sh | 44.00 | 51.70 (11.9) | +18% |
| records.test.sh (6.6, 10.5) | 28.05 | 49.75 | +77% |
| review.test.sh (10.0, 10.7) | 133.51 | 269.33 | +102% |

The tests' histories are small, where a `jq` run takes about 2 ms and the helper about 20 ms (most of it Python's
start and its imports; its own work is about 6 ms). So each read moved to the helper costs the tests more than the
`jq` run it replaced, and the files that run whole cards (records, review) pay for it on every step. On the real
history the reads it replaced cost more than the helper does: a `jq` run over the 4 MB records takes the time of
reading all of it, where the helper reads what was added since its last call.

views.test.sh's `snapshot` case fails on main as well as after (both runs). In the after run of views.test.sh,
`snaplock` failed too: its stub waited for a `cat` that `retry` no longer runs (it now waits for the helper's
rewrite), fixed after this run.
