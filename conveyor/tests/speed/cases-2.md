# Engine cases health to pick

Measured 2026-11-14 as `README.md` says, on the loop's machine (16 cores), each file alone through its runner, main
first (4858816, from a Git checkout of main) and then this card's change, before and after one right after the other
so each pair ran at about the same load. Every run counted below passed, every case of its file.

The machine was far from quiet: the load average was 15 to 66 during the runs, and up to 15 of the 16 shared test
slots were held by other cards' test runs. A file then waits for slots, and its time measures the queue as much as its
cases; so from the third round on, both before and after ran on a slot pool of their own (a host file naming
`testSlotsDir`, under `XDG_CONFIG_HOME` for the runner alone), which lets a file's cases run side by side as the
README means, on the same cores and load as everything else. Two runs of the same unchanged file in a row still
differed by a quarter to a half (`health.test.sh` 23.0 s then 17.4 s, `machine.test.sh` 103.5 s then 157.1 s, as the
load rose from 37 to 66). A file's time below is the middle of its paired runs (each run's before and after are in
the last column), and faster by is `1 - after / before` of those middles. Its slowest case is the one of the middle
run, with that case's time from the start of the run to its end.

`health`, `judge`, `machine` and `merge` are at their floor, as the owner's floor rule (#356) allows and #372 records
for seven other engine files: their time is the engine's own work for the cards each case runs, not anything in the
test file. Their one final pair ran on 2026-11-14 from 05:24 at a load of 30 to 47, main (1f4e4fc, a Git checkout of
it) then the card's code, one file at a time, on the machine's shared slot pool, with the CPU of the whole run
(`/usr/bin/time`, user + sys of the runner and every case under it). Not on a slot pool of its own: a case's engine
runs its test step in a slot of the shared pool (`lib.sh` gives the case a host file of its own, naming none), so on a
private pool `health`'s waits found the shared pool full (16 of 16), waited their 120 s and failed, on main as on the
card. The per-case harness and setup, measured on the same machine: `machinecards`, a case that runs no card (a dozen
`conveyor.sh check`), used 2.4 and 3.3 s of CPU, its harness, setup and checks together, in two runs that took 50 and
74 s from start to end as the case waited for a free shared slot. #372 measured the harness at about 0.45 s a case and
`setup` at about 0.08 s.

| File | Before: file (slowest case) | After: file (slowest case) | Faster by | How |
| --- | --- | --- | --- | --- |
| `health.test.sh` | 24.4 s (`keepalive` 24.3 s) | 29.9 s, unchanged (`keepalive` 29.8 s) | at its floor | Not changed. Final pair 24.4/29.9 s at load 30 to 38, main's code both times, so the 22% between them is the load. Its 6 cases used 66.2 s of CPU (32.1 user + 34.1 sys) to run 11 cards: about 6 s of engine CPU a card run, of which the harness and setup are under 0.6 s a case. `waitsum` and `waitkept` each run three cards that wait on one another's claims, about 18 s of CPU on their slot's one core: half the file's time, 12 s, is below what their cards' engine work takes even on a quiet machine. Their waits are on the cards' own steps, not on a set time, and the three cards of one scenario do not split; `waitlong`'s and `casehung`'s second halves could be cases of their own, but neither is the slowest case. Lower only with a faster engine, outside this card. |
| `install.test.sh` | 6.5 s (`service` 6.5 s) | 2.8 s (`servicesecond` 2.7 s) | 56%, meets 50% | Pairs 4.9/2.8, 4.8/2.8, 6.6/4.5, 6.5/3.5, 8.3/2.7. `t_install` and `t_service` each ran their parts one after another on one code repo; each part is now a case of its own on a code repo of its own (`install`, `installok`, `installkept`, `installhidden`, `installlink`; `service`, `serviceunits`, `servicesecond`, `servicemac`, each from `service_start`), with the same checks. `servicesecond` counts the two records its own run made (2), where the whole case counted 4 with the two earlier parts'. |
| `judge.test.sh` | 55.0 s (`judgesnapshot` 54.8 s) | unchanged: main's file (split: 99.9 s, `judgesnapfail` 99.7 s) | at its floor | Not changed. Splitting each case into one card a case (25 cases from 14) was built and measured, then taken back: it was slower in 4 of 5 pairs (main/split 18.7/40.3, 48.4/75.4, 43.3/35.4, 44.4/48.5, and the final 55.0/99.9 at load 41 to 43). The split used more CPU (134.5 s against 125.5 s: 11 more cases' harness and setup), and its 25 cases queue for slots on a busy machine. On main its 14 cases run 24 cards, each through review and judge and most through a fix round: 125.5 s of CPU (63.7 user + 61.9 sys), about 5.2 s a card run. Its slowest cases (`judgesnapshot`, `judgeunread`, `judgeswitch`) each run 2 or 3 such cards in turn, 10 to 16 s of CPU on one core, about 2.5 times that at a load of 40 on 16 cores; the file's time is its slowest case's. Lower only with a faster engine. |
| `lane.test.sh` | 12.7 s (`lane` 12.7 s) | 4.7 s (`lanepreview` 4.7 s) | 62%, meets 50% | Pairs 15.2/13.9, 18.8/16.9 (shared slots, mostly held), 10.3/3.4, 12.4/4.7, 12.7/3.1. `t_lane` ran every lane command one after another on one lane; each part is now a case of its own (`lane`, `lanecreate`, `lanelock`, `lanepush`, `laneowner`, `laneownerbranch`, `lanepreview`, `lanesingle`), each on a lane of its own (`lane_start`), and a part that went on from a change in the lane, with main moved and the lane rebased, makes that first (`lane_change`). |
| `machine.test.sh` | 62.5 s (`machinecap` 62.3 s) | unchanged: main's file (split: 66.9 s, `machinehost` 66.8 s) | at its floor | Not changed. Splitting `machinecap` (into `machinecap`, `machineown`, `machineone`), `machineempty` (`machinecut`) and `machineroom` (`machineroomnone`, `machineroomcut`, `machineroomlink`), 19 cases from 13, was built and measured, then taken back: the final pair was 62.5/66.9 s at load 41 to 47, no gain, and the CPU rose (216.5 s against 196.1 s). An earlier pair (165/135 s) had `machinekill` fail on both sides, so it counts for nothing. On main its 13 cases used 196.1 s of CPU (93.4 user + 102.7 sys), 15 s a case: the machine's Conveyor and each project's loop taking their turns 1 s apart (`watchturns`; the machine loop's 1 s turn came from an earlier card), and the cards they build. `machinecap` runs 6 cards of two projects through a machine cap of 3, and its waits are on the loops' own turns (a slot freed, the next pick); the file's time is its time. Lower only with a faster engine or loop turn. |
| `maintest.test.sh` | 14.6 s (`maintest` 14.6 s) | 4.6 s (`maintestserve` 4.6 s) | 68%, meets 50% | Pairs 14.6/4.4, 26.7/4.9, 8.9/4.6. `t_maintest` ran every stage of the whole test on main one after another; each stage is now a case of its own (`maintest`, `maintestneeds`, `maintestagain`, `maintestother`, `maintestclear`, `maintestretry`, `maintestgh`, `maintestslots`, `maintestfile`, `maintestserve`), and a stage that went on from a record an earlier one left makes it with the same runs first (`maintest_pass`, `maintest_failed`); the run counts and issue numbers each checks are its own case's. |
| `merge.test.sh` | 19.5 s (`mergedocs` 19.5 s) | 19.9 s, unchanged (`mergedocs` 19.7 s) | at its floor | Not changed. Final pair 19.5/19.9 s at load 38 to 41, main's code both times. Its 5 cases used 28.5 s of CPU (13.8 user + 14.7 sys) for about 8 card runs, about 3.5 s a card. Each case is one scenario of two cards whose steps wait on each other's claims (`mergedocs`: #8 waits in review for #7's claim, then meets #7's change at landing and is rebuilt), so none splits; `mergedocs` is about 3 card runs, some 10 s of CPU on one core, about 20 s at this load. Lower only with a faster engine. |
| `models.test.sh` | 54.4 s (`proxy` 54.4 s) | 18.1 s (`opencodereview` 18.0 s) | 66%, meets 50% | Pairs 35.6/18.1, 54.4/11.7, 98.8/44.5. `t_proxy` ran a dozen kinds of request one after another through one stub proxy, and `t_claudereview` several review runs; each is now a case of its own on its own proxy or main (`proxy`, `proxytool`, `proxyv`, `proxye`, `proxyenv0`, `proxykeys`, `proxyfetch`, `proxytoml`, `proxytables`, `proxyinline`, `proxynomatch`, `proxydirect`, from `proxy_start`; `claudereview`, `claudefail`, `claudeexit`, `claudebare`, `claudepart`, from `claude_reviewer`). |
| `packread.test.sh` | 13.3 s (`packread` 13.3 s) | 2.8 s (`packread` 2.8 s) | 78%, meets 50% | Pairs 13.3/2.8, 5.4/2.7, 24.2/12.0. `t_packread` ran four cards one after another, each changing the pack or schema; each is now a case of its own on an engine copy of its own (`packread`, `packbroken`, `packschema`, `packnul`, from `packread_start`). |
| `pick.test.sh` | 43.6 s (`p3rule` 43.6 s) | 16.1 s (`pushable` 16.0 s) | 63%, meets 50% | Pairs 21.9/16.1, 69.3/18.1, 43.6/12.0 (this change; an earlier one, without `emptyrelease` and `pushablenext`, ran 8.1/4.8, 7.2/4.7, 10.9/5.9, 11.8/10.8). `t_empty`, `t_pushable` and `t_p3rule` each ran cards in two or three runs one after another; each later run is now a case of its own (`emptyfar`, the issue past the first 1,000, made in one jq and not 1,000; `emptyrelease`; `pushablenext`, from #50's picked and blocked lines written as a card's; `p3on`). `p3rule` and `p3on` check what is picked, so their cards' builds fail and end there. |

The cases `proxy`, `claudereview` and `empty` are still in `conveyor/conveyor.slowest` and
`conveyor/tools/closure.slowest` with their times of before: each still exists, and both lists are outside this card's
files; they should be measured again for the lists.

## Shared helper ideas

- `conveyor.test.sh` / `lib.sh`: a case pinned to its slot's core shares that core with whatever else the machine runs
  there; under a load of 30 on 16 cores a case that took 1.5 s alone (`lanecreate`) took 7.5 s in its file. Pinning the runner's
  cases to the least busy cores, or not pinning them while the machine is that loaded, would cut the files whose cases
  are short and many.
- `lib.sh` `setup`: each case makes a main repo, a bare origin and its stubs from nothing; a fixture made once per run
  and copied (`cp -a`) would save each split case its share. Measured at about 0.2 s a case, so worth doing only for
  files of many short cases.
- The runner's start of a case (its slot, the subreaper, the dump of the shell's functions and variables) took about
  2 s before the case's first line under load: a cost every split case pays once.
- `lib.sh` `setup`: the host file it gives a case names no `testSlotsDir`, so a case's engine takes its test step's
  slot from the machine's shared pool unless the case's own slot is of that pool. With the shared pool full (16 of 16
  held on 2026-11-14), a case that runs no card (`machinecards`, 2.4 s of CPU) took 50 to 74 s waiting for a slot, and
  a runner on a slot pool of its own left `health`'s cases waiting 120 s for a test step's slot until they failed.
  Two processes a test left behind (an `adopt` case's stub `deaf.sh` and its parent) held one shared slot for some
  20 hours. A case's engine always using the case's own slot, and the runner ending what a case leaves holding a slot,
  would keep a file's time its cases' own.
