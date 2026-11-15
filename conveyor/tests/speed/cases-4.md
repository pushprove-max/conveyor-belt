# Engine cases setup to watch

Measured 2026-11-14 as `README.md` says, on the loop's machine (16 cores), each file alone: main (be7a973, a
`git clone --shared` of main outside the worktree) and then this card's change, one right after the other, so each
pair ran at about the same load. Two rounds of pairs; the load is beside each pair, and was far from usual (23 to 41).
Every run passed, every case of each file. `setup`, `slots`, `testcount`, `testrec`, `views` and `visible` were
measured again after the second round of changes (rounds r1 and r2 below are those runs); `testfails`, `testlog`,
`wait` and `watch` were not changed since their two rounds, which the rows keep.

- The file's time is wall clock from its first case started to its last ended, the runner's own order and slots. On a
  machine whose test slots other cards' runs held, it counts the file's waits for a slot too, and on a machine with
  every core busy, a file split into more cases runs no faster than its cases' total work allows: in several pairs
  the load rose between the before and the after run (`views` r1: 29 to 36), and the file's time then says little of
  the file.
- The slowest case is each case's own seconds from its start to its end: from when its keeper started (`case_keep`,
  `lib.sh`), which is once the runner holds a slot for it, to when the keeper ended, the ending of what the case left
  (`case_end`) included. No slot wait is in it. It was read by running each file's cases as `conveyor.test.sh` runs
  them, with `case_keep` wrapped to write its start and end; the runner and `lib.sh` were not changed. A case run
  inside a case (`slotterm`, `slotstay` and the like) is not counted as one of the file's.
- Faster by: `1 - after / before`, rounded down to whole percent, of the file's time (as `README.md` asks) and of the
  slowest case, for each round.

| File | r1 before: file (slowest case), load | r1 after | r2 before | r2 after | Faster by, file: r1, r2 | Faster by, slowest case: r1, r2 | Met | What was done |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `setup.test.sh` | 14.46 s (`doctor` 14.36 s), 24 | 8.22 s (`doctordamaged` 4.94 s), 26 | 15.94 s (`doctor` 15.84 s), 23 | 6.00 s (`doctordamaged` 4.91 s), 25 | 43%, 62% | 65%, 69% | In r2, and by the slowest case in both; r1's file time is under 50% | Sped up: `t_setup` is four cases (`setup`, `setuppin`, `setuplabels`, `setupbad`) and `t_doctor` eleven, one for each doctor run it made: `doctor`, `doctormissing`, `doctordamaged`, `doctorlink`, `doctorfolder`, `doctorclimb`, `doctorsnap`, `doctorprivate`, `doctorhostbad`, `doctornopack`, `doctortools`. Each starts from the sample set up (`setupdone`, `doctordone`) and makes what the part before it left that it needs itself: the install removed (`uninstalled`), gh signed out, the pack private or gone. `without` links PATH's programs with one `ln`, not one a program. |
| `slots.test.sh` | 15.73 s (`slotcaseterm` 13.32 s), 25 | 17.12 s (`slots` 12.04 s), 24 | 83.99 s (`slotcaseterm` 21.21 s), 38 | 38.10 s (`slotcaseterm` 18.35 s), 38 | -8%, 54% | 9%, 13% | At its floor after #371 (below): `slotclock` 5.1 s and `slotwholeclock` 7.0 s at a load of 2, each a 5 s hold past its 3 s test timeout and 1.3 to 1.7 s of CPU; `slots` 53% to 78% faster in four pairs | Here, #362: not changed (r2 is the first measure's second round). `slotcaseterm` is the file's time, and nearly all of it is the shared `case_end` (`lib.sh`): the process the case leaves ignores TERM, as it must for the case to prove it is killed, so `case_end` makes all its 30 tries, each a `ps` of the whole machine and a `pgrep` for each process (about 0.3 s a try at a load of 21, 606 processes), before its KILL. No change to this file alone takes that case below half, and no other case proves it (`machine.test.sh`'s `deaf` is the machine loop's TERM, not a case's). See "Shared helper ideas". The r2 file time is the before run's slot waits. |
| `testcount.test.sh` | 4.48 s (`testcountcases` 4.40 s), 24 | 2.56 s (`testcountcases` 2.43 s), 24 | 5.57 s (`testcountcases` 5.40 s), 23 | 3.48 s (`testcountrunner` 3.06 s), 24 | 42%, 37% | 44%, 43% | Meets 50% after #371 (below): file 62%, 64%; slowest case 52%, 66% | Here, #362: under 50%. `testcountcases` and `testcountnone` ran a whole card to its test step to read the live record. They now run the test command as the card's test step runs it (`testonce()`): the engine's own `watch()` (`lib/session.sh`) on its output and logs where a card's worktree has them, with the card's records at its test step, as `views.test.sh`'s `track` writes them, for the snapshot; `views.test.sh`'s `live` still reads a real run's test step. The file's time is now `testcountrunner`, not changed (1.9 to 3.1 s): the engine's runner run on two probe cases, which sources every case file of the suite before it starts one, about half of what the file took before. No case proves what it does. |
| `testfails.test.sh` | 13.62 s (`testfailsown` 13.39 s), 33 | 3.14 s (`testforged` 0.54 s), 34 | 11.86 s (`testfailsown` 11.66 s), 35 | 0.25 s (`testforged` 0.17 s), 35 | 76%, 97% | 95%, 98% | Yes | Sped up: its cases ran a whole card to read a failed run's logs. They now run the same test command where a card's worktree has its output and logs and read them with the engine's own `testfails()` (`logfails`, with the exit and the timeout the card had: 1, and 124 at 2 s), and check the same fields its test line keeps (`.failures`). `testfailsown`'s hanging file and its 2 s timeout are now the exit 124 it ended with. `rules.test.sh` `t_testfails` still proves a card's test line holds what `testfails()` reads. |
| `testlog.test.sh` | 4.37 s (`testlognonewline` 4.01 s), 33 | 0.36 s (`testlognonewline` 0.24 s), 33 | 2.53 s (`testlognonewline` 2.45 s), 35 | 0.38 s (`testlognonewline` 0.25 s), 35 | 91%, 84% | 94%, 89% | Yes | Sped up as `testfails.test.sh`: the logs are read by `testfails()` (`logfails`, in `testfails.test.sh`), not through a card's whole run. |
| `testrec.test.sh` | 8.52 s (`testrecwait` 8.34 s), 24 | 6.49 s (`testrecended` 6.29 s), 26 | 8.97 s (`testrecended` 8.80 s), 26 | 7.64 s (`testrecwait` 7.26 s), 27 | 23%, 14% | 24%, 17% | Meets 50% after #371 (below): file 89%, 84%; slowest case 93%, 94% | Here, #362: under 50%. `testrecwait` holds the slot 1 s past the card's wait being seen, not 3 s, and checks a wait of 1 s at least: the record counts whole seconds, so a wait left out of it reads 0 and still fails. Its three cases are now about as long as each other, each one or two cards' whole runs: `testrecreused` is two cards whose batch, claims and reused pass are what it proves, so it cannot be done without the loop, and no case proves what it does (`merge.test.sh` and `giveway.test.sh` check a reused line's `.reused`, not its `.ended`, `.run` or the record check). |
| `views.test.sh` | 26.81 s (`live` 26.71 s), 29 | 21.69 s (`livebuild` 13.46 s), 36 | 21.34 s (`live` 21.18 s), 23 | 10.37 s (`live` 10.20 s), 24 | 19%, 51% | 49%, 51% | In r2; r1's after run was at a load of 36, its before at 29 | Sped up. `t_snapshot`'s 20 snapshots, one after another, are eight cases (`snapshot`, `snapshotdeploy`, `snapshotpushed`, `snapshotsteps`, `snapshotcards`, `snapshotprice`, `snapshotlate`, `snapshotpush`), each from the same records (`snapshotstart`; `latestart` makes what `snapshotlate` left for `snapshotpush`); `snapshotsteps` reads one snapshot where it read two of the same records. `t_live`'s one run, held at the build, the first review and the test run, is three runs (`livebuild`, `livereview`, `live`), each held at one with the holds before it open from the start. A live case asked for a whole snapshot every 0.2 s while its card ran, each about half a second of a core: it now asks again only once the card's records, its live record or the review's session file changed, and its checks read the snapshot that showed what it waited for (`seen`), not a new one each. `track` wrote its 300 record lines with a `jq` each and took five snapshots, one after each group of cards: it writes them with a `jq` a card, the same lines byte for byte, and takes one snapshot of them all (its checks of the landed and blocked cards name them, not their place among all). |
| `visible.test.sh` | 37.85 s (`before` 37.46 s), 27 | 15.07 s (`visibleyes` 8.62 s), 27 | 73.14 s (`before` 72.97 s), 41 | 34.98 s (`visibleyes` 13.52 s), 39 | 60%, 52% | 76%, 81% | Yes | Sped up: `t_visible`'s cards are fourteen cases, one card each on a main of its own (`visiblestart`): `visible`, `visibleyes`, `visibleinline`, six for a review with no clear answer (`unclearnone`, `uncleartwo`, `unclearboth`, `unclearmaybe`, `unclearempty`, `unclearnogo`; `unclear`), `visiblecap`, `visiblecapyes`, `visibletooling`, `visibleweb`, `visiblemixed`. `t_before`'s are fifteen (`before`, `beforelong`, `beforehold`, `beforeyes`, `beforediffers`, `beforetwo`, `beforeyesno`, `beforeboard`, `beforeboardcond`, `beforedevice`, `beforenothing`, `beforenothingno`, `beforenothingyes`, `beforenone`, `beforetooling`; `beforestart`). Each review stub a case reads is numbered from 1 in it, and a count of reviews or comments is the case's own. `t_inherit` is three: `inheritpart` (#100101), `inherit` (#100104, which goes beyond #7's yes, and its retry) and `inheritno` (#100103, of #8 with no yes, and its retry); `inherit` and `inheritno` need only #100101's landed line, not each other: the "beyond" of each is checked in its own case, and #100104's retry lands its own kept patch (it was made a file of its own only because #100103 had landed on the same files first). |
| `wait.test.sh` | 12.01 s (`waituntil` 11.88 s), 35 | 21.76 s (`waitceiling` 3.36 s), 36 | 10.78 s (`waituntil` 10.66 s), 29 | 2.81 s (`waitceiling` 2.73 s), 29 | -82%, 73% | 71%, 74% | Yes in r2; r1's file time is the after run's slot waits | Sped up: `t_waituntil` waited out seven ceilings one after another (3 s, then six of 1 s); each is a case of its own: `waituntil` (the waits that are met), `waitceiling`, `waitprinted`, `waitexit`, `waitblocked`, `waitstateblocked`, `waitnul`, `waitnulblocked`, `waittick`. |
| `watch.test.sh` | 23.05 s (`watch` 22.85 s), 37 | 10.63 s (`watch` 7.84 s), 37 | 15.72 s (`watch` 15.60 s), 24 | 6.18 s (`watch` 6.06 s), 23 | 53%, 60% | 65%, 61% | Yes | Sped up: `t_watch`'s four streams are five cases, each a stream of its own on a main of its own (`watchstart`): `watch` (the first snapshot, a record and a control change while GitHub is slow), `watchlive` (the live record, in a stream that starts with the loop paused, as `watch` leaves it), `watchslow`, `watchslowlive` and `watchloop`. `watchlive` waits for its beat line where the one stream had long had one. |

In #362, three files were not 50% faster in either round and none was removed: `slots` (the shared `case_end`'s ending of a
process that ignores TERM), `testrec` (each case one or two cards' whole runs through the engine) and `testcount` (the
engine's runner run inside a case, which sources every case file of the suite). Nothing in #362's files made
those cases faster. `setup` and `views` are 50% faster in one round of two, by the file's time. The follow-up below
(#371) changed the shared `case_end` and moved or removed cases of all three files: `testcount` and `testrec` now meet
50% and `slots` is at its floor, as their rows and the follow-up say.

In #362, no case was skipped and no limit or timeout raised. No file was removed, so `.conveyor/engine-areas.json`
needed no change then (`bash .conveyor/test-changed.sh --check` exits 0); #371's area changes are in its follow-up below. The cases `conveyor/conveyor.slowest` and
`conveyor/tools/closure.slowest` name all still exist (`visible`, `before`, `inherit`, `snapshot`, `live`, `doctor`,
`watch`, `track`). The lists are not changed here: see below.

## Follow-up: `slots`, `testcount` and `testrec` (#371)

What was done:

- `lib.sh` `case_end` waits 3 s by the clock before its KILL, not 30 looks. `slotcaseterm` now makes each look half a
  second slower (as on a busy machine) and fails if the case takes 10 s or more to end: on main's `lib.sh` it took
  18 s and more.
- `slots.test.sh`: `t_slots`, `t_slotclock` and `t_slotwholeclock` run each card's test step (`teststep`: the engine's
  own `tests()` and `testrec()`, its libraries sourced as `conveyor.sh` sources them) where they ran whole cards through
  `loop run`. `t_slots` no longer takes a snapshot while its workers hold all three cards: that check (the Board says a
  card waits for a test slot) is now `t_slotclock`'s, taken during the wait its card already has. `t_slotclock` and
  `t_slotwholeclock` are near the file's top, so the runner starts them among its first.
- `testrec.test.sh`:
  - `testrecwait` is removed. Its checks of the test line (wait and run apart, selected, ended, slots free, the record
    check) are now `t_slotclock`'s, whose card already waits 4 s at least for the pool's one slot.
  - `testrecreused` is removed. `batch.test.sh` `t_batchmask` already checked the reused pass's line and now also
    checks its `.run` is null and that the record check takes it.
  - `testrecended` is two cases, `testrecended` (killed) and `testrecnothing` (nothing selected), each the test
    command run as a card's test step runs it, its line made by the engine's own `testrec()` (`recline`), not a card's
    whole run.
  - `.conveyor/engine-areas.json`: `testrec.test.sh` is in the `records` and `session` areas (`recline` reads their
    functions), `slots.test.sh` in `session`, `card` and `record`, and `batch.test.sh` in `record`.
- `testcount.test.sh`: the check that a case run inside a case is not named in the run's records is
  `testcountinner`, which runs it as `run_case` does with a loop's test log folder. It is no longer a probe that
  `testcountrunner`'s inner runner ran, where its keeper made that case the file's longest.

How it was measured: as above (main in a `git clone --shared`, then this change, one right after the other, each
case's own seconds read by wrapping `case_keep`). The file's time here is the runner's whole run, so it also counts the
waits for the machine's test slots. `testcount` was measured on the change before its last round; `testrec` and
`slots` on this change as it is, in the pairs below. A further pair could not be run when the card was brought onto
main: all 16 of the machine's test slots were held by other cards' suites for over 20 minutes, and both runners timed
out waiting for one.

| File | Round, load before/after | Before: file (slowest case) | After: file (slowest case) | Faster by: file, slowest case |
| --- | --- | --- | --- | --- |
| `testcount.test.sh` | r1, 44/43 | 13.06 s (`testcountrunner` 8.54 s) | 4.92 s (`testcountrunner` 4.03 s) | 62%, 52% |
| `testcount.test.sh` | r2, 31/31 | 4.23 s (`testcountcases` 3.77 s) | 1.51 s (`testcountcases` 1.28 s) | 64%, 66% |
| `testrec.test.sh` | r1, 21/29 | 19.26 s (`testrecwait` 14.14 s) | 1.99 s (`testrecnothing` 0.85 s) | 89%, 93% |
| `testrec.test.sh` | r2, 27/30 | 11.06 s (`testrecended` 9.30 s) | 1.69 s (`testrecended` 0.54 s) | 84%, 94% |
| `slots.test.sh` | r1, 16/16 | 20.09 s (`slots` 19.69 s) | 18.55 s (`slotwholeclock` 11.97 s) | 7%, 39% |
| `slots.test.sh` | r2, 30/28 | 18.24 s (`slots` 12.18 s) | 14.21 s (`slotclock` 8.15 s) | 22%, 33% |

The cases of `slots.test.sh` this change touched, each case's own seconds in those two rounds and in two more pairs
(r3 at a load of 28/27, r4 at 37/60):

| Case | Before: r1, r2, r3, r4 | After: r1, r2, r3, r4 |
| --- | --- | --- |
| `slots` | 19.69, 12.18, 19.04, 25.48 s | 6.46, 4.29, 8.92, 5.46 s |
| `slotcaseterm` | 17.05, 9.74, 17.27, 49.82 s | 5.60, 5.96, 11.55, 6.57 s |
| `slotclock` | 9.67, 10.58, 9.62, 18.02 s | 8.47, 8.15, 15.23, 12.38 s |
| `slotwholeclock` | 8.20, 9.63, 9.30, 14.38 s | 11.97, 7.68, 10.71, 9.42 s |

Met:

- `testcount`: meets 50%, in both rounds, by both measures.
- `testrec`: meets 50%, in both rounds, by both measures (84% and 89% by the file's time).
- `slots`: at its floor. `slots` is half or less of what it was in all four rounds (53% to 78% faster), and
  `slotcaseterm` in two of four (33% to 86%); the file's time is now `slotclock` and `slotwholeclock`, 7.7 to 15.2 s,
  about what they were (8.2 to 18.0 s). Each is a card's test step that must wait past its 3 s test timeout for the bug it proves (a
  wait counted against the timeout timed the run out), so each holds the slot or the whole-suite turns 5 s, by the
  clock, before the step can start its run; the rest, 3 to 10 s with the load, is the engine's own test step for that
  card (`teststep`: sourcing the engine's libraries, `tests()`, the slot and the turn, `testrec()`), no `loop run`
  around it now. A shorter hold needs a test timeout under 3 s, which a case on a loaded machine cannot rely on: the
  run would time out for the load, not for the bug. Each run alone through the runner on a quiet machine (load 2, this
  change, no slot wait): `slotclock` 5.1 s wall, 1.3 s of CPU (0.7 user + 0.5 sys); `slotwholeclock` 7.0 s wall,
  1.7 s of CPU (0.8 user + 0.9 sys; its two whole-suite runs get their turns before the card's step waits); `slots`
  3.1 s; the runner on an empty case (`testcountok`) 0.3 s. So each is its 5 s hold and about 1.5 s of the engine's
  own work for that card's test step; on a loaded machine that work is what grows.

## Shared helper ideas

- `conveyor/tests/lib.sh` `case_end`: done in #371 (above): it waits 3 s by the clock, not 30 tries of `case_left`
  (11 to 24 s on a busy machine for a process that ignores TERM).
- The engine's run of one card (`loop run`: start, worktree, brief, the build and review stubs, the test step) is 3 s
  at a usual load and 5 to 7 s at a load of 35: the floor of every `visible` case and `views`' live cases. That time is the engine's own (its `jq` and `gh` stub calls), and cutting it is engine work, not a test
  file's.
- `conveyor/conveyor.test.sh` sources every case file before it runs a case, so a runner run inside a case
  (`testcountrunner`, the slot cases that run one) pays for the whole suite's files to run two probe cases. Measured
  in #371, that sourcing takes about 0.3 s. Most of a runner run inside a case is each case's keeper (`run_case`:
  python3, the dump of the shell's state, `case_end`'s look).
- The measure in `conveyor/tests/speed/README.md`: the file's wall time counts its waits for the machine's test slots,
  which other cards' runs hold, and on a machine with every core busy it is the file's total work over the cores
  left, so the same file measured twice an hour apart differed by half (`visible` before: 38 s and 73 s). Each case's
  own seconds, as read here by wrapping `case_keep`, or the file's CPU seconds, would be measures that other cards'
  runs move less; the runner could print the first on its `ok` line.
- `conveyor/conveyor.slowest` and `conveyor/tools/closure.slowest` (the core area: a change to them runs the whole
  suite): re-measure them. `visible`, `before`, `snapshot`, `doctor`, `watch` and `inherit` are now short and still
  start first; the longest cases of their files are now `live`, `livebuild`, `visibleyes`, `before*`, `doctor*` and
  `watchloop`, of which only `live` is named.
