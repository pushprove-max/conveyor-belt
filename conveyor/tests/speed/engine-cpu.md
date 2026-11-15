# Engine CPU per card run (#379)

#372 measured about 2.5 s of the engine's CPU and about 400 `jq` calls per card run, most of them reading one value of
the pack (`.conveyor/project.json`) or the control record. This card reads each once per process where it can.

## What changed

- The pack: when its text (or the schema's) is checked, one more `jq` run reads every field the schema names
  (`packall`, lib/prompts.sh) into `PACK_V`. `packget` takes a field from there and starts no program; a subshell or
  card started after the read finds it too. A field the schema does not name, one whose read fails, or one holding a
  NUL is read by its own run, as before. The pack's names (`names()`: remote, branch, labels, owner, tunables) are
  kept while the pack's text is the one they were read from (`NAMED`).
- The control record: read at every use, as before, but checked only when its text is not the one last checked
  (`ctlread`, `CTL_K`, lib/control.sh). The loop reads it once per turn in its own shell, so the turn's subshells and the
  cards it starts find it kept.
- A seat's model, effort and agent are read in one `jq` run (`jqget`, lib/control.sh), not three (`session1`, `review`,
  `judgecall`, `codexready`, `routes`).
- The machine's room check (`roomed`, lib/pick.sh) reads a slot file split on `\037`, not tabs. Found on the way:
  `t_machinekill` failed about one run in three on main under load, and three in three with this card's faster loop. A
  loop killed while it wrote its slot file leaves `"started": ""`, `read` joined the tabs around that empty field, and
  the run lock its cards still hold read as none, so another project started a card past the machine cap.
  `t_machinegone` makes that slot file and fails without the fix.

## One stub card run

One issue, built, reviewed GO, tested, landed and pushed: `loop run 1` after the shared `setup` (tests/lib.sh), with
the harness's own setup outside the measure. CPU is user plus system time of the loop and every process it waited for
(bash `times`, before and after). `jq` calls are counted by a `jq` wrapper first on PATH, in a run of their own (the
wrapper's own CPU is not in the CPU rows). Before is main at cda9d5b, from a clone outside the worktree
(`git clone --shared`); after is this card's worktree. Alternating, five runs each, on the loop's machine.

| | Before | After | Change |
|---|---|---|---|
| `jq` calls | 308 | 223 | 28% fewer |
| CPU, load 12 to 14 (median of five) | 1.57 s | 1.30 s | 17% less |
| CPU, load 37 to 45 (median of five) | 3.49 s | 2.97 s | 15% less |

Where the 85 went, by program, before and after: pack fields read one run each, 39 to 0, with 1 `packall` run added;
the control record's check, 33 to 3; a seat's model, effort or agent read alone, 17 to 2, with 6 `jqget` runs added;
the pack's names and tunables, read again at every turn, 10 to 2. #372's figures (about 2.5 s and 400 calls) were taken another way, inside its
cases; the before and after here are one method's, on one fixture.

## The files #372 recorded at their floor

Each file alone (`bash conveyor/tests/<file>.test.sh`), wall clock, every case passing on both sides. Two rounds: the
first before then after (load 24 to 42), the second after then before (load 14 to 29). The files #372 grouped are
listed apart (`rules` with `checkrun`, `serve` with `adopt`).

| File | Before, round 1 | After, round 1 | Before, round 2 | After, round 2 |
|---|---|---|---|---|
| `port.test.sh` | 31.4 s | 40.1 s | 16.7 s | 14.0 s |
| `records.test.sh` | 20.8 s | 17.6 s | 9.0 s | 10.5 s |
| `rerun.test.sh` | 7.2 s | 6.8 s | 7.5 s | 6.3 s |
| `reuse.test.sh` | 4.1 s | 3.4 s | 2.5 s | 2.3 s |
| `rules.test.sh` | 18.0 s | 15.4 s | 15.1 s | 13.2 s |
| `checkrun.test.sh` | 7.9 s | 7.7 s | 7.8 s | 7.7 s |
| `samefile.test.sh` | 18.6 s | 16.5 s | 18.6 s | 17.4 s |
| `serve.test.sh` | 21.8 s | 20.5 s | 18.6 s | 20.1 s |
| `adopt.test.sh` | 34.7 s | 20.0 s | 21.3 s | 17.8 s |

Most are a little faster, within this machine's noise at these loads. What holds these files is mostly not the
engine's CPU: their waits (a loop's turns, test clocks, the cases' own pauses) and the harness's own setup and
snapshots (#372) do. 17% less engine CPU per card shows only where the cases' CPU fills the cores.

## Tests changed

- `t_packread` (packread.test.sh) counted the pack's reads as `jq` runs of the per-field read program and required at
  least 20 of them. A read of a checked text now starts no program, so that count is the number of `packall` runs
  (8), and the case could not pass unchanged without keeping the `jq` run at every read that this card removes. It
  still checks what it was written for, with the counts main gives: on main the run made 39 reads and 8 checks; it
  now requires at most 9 checks (39 if checked at every read) and one `packall` run per check.
- `t_packnames` now counts `names()`'s own run and requires no field read by a run of its own; it fails (33 such runs)
  without `packall`.
- New: `t_controlread` (control.test.sh), `t_packnames` (packread.test.sh), `t_machinegone` (machine.test.sh).

# The seats and the host's CLIs once per step (#401)

After #379 the pack was read once per process (one `packall` run in a card's run) and the control record checked once
per text, but what is made of them was not: each ask for a seat (`seat`, `judgeseat`), for the host's CLIs
(`hostclis`, three `jq` runs) and for whether a seat can start (`seatready`) worked it out again, and the loop asks for
all of them at every turn (`clis`, `codexready`) and the card again at each session and review.

## What changed

- `seat` works out the builder's, the reviewer's and the judge's seats in one `jq` run and keeps them, keyed on the
  control record's and `models.allowed`'s text (`SEAT_K`, lib/control.sh); `judgeseat` asks it.
- `hostclis` reads CLIS in one `jq` run, not three, and keeps the report, keyed on CLIS's text and the CLIs installed
  (`HOST_K`); whether it is due is bash's clock (`EPOCHSECONDS`), not a `jq` run.
- `seatready` keeps why each seat cannot start while the host's report is the same (`READY_H`).
- `clis` asks for them in its own shell, and the loop's turn runs it once in its own shell (lib/run.sh) before the
  check it makes in a subshell, so that check, the pick and the cards the turn starts find them kept.

## One stub card run

Measured as above (`loop run 1` after `setup`, one issue built, reviewed GO, tested, landed and pushed). Before is main
at bbcbd0d (`git clone --shared`), after is this card's worktree. `jq` calls in three runs each; CPU alternating, five
runs each, at load 38 to 47.

| | Before | After | Change |
|---|---|---|---|
| `jq` calls (three runs) | 275, 276, 283 | 222, 222, 224 | 20% fewer (median 276 to 222) |
| CPU (median of five) | 1.92 s | 1.65 s | 14% less |

Where the 54 went: seats worked out, 15 to 1; the host's report, 27 `jq` runs (10 reads) to 2; seats' start checks, 10
to 2.

## Tests

- New: `t_seatread` (control.test.sh) counts the seats worked out, the host's reports read and the start checks in one
  card's run whose build sets the reviewer: 3, 3 and 4 with this change, 19, 12 and 12 on main (5 turns); it requires
  at most 5 each, and the review to run on the reviewer the build set.
