# The cases' fixture, made once per run and copied

`lib.sh` `setup` made each case's main repo (`git init`, a commit), its bare origin (`git init --bare`, a push), its
stubs, and asked the engine for its state folder (`conveyor.sh state-dir`), from nothing, in every case:
`cases-2.md` proposed a fixture made once per run and copied (`cp -a`). Now `fixture` makes main, origin and the
stubs once, as the runner reads `lib.sh` (`$T/fixture`), and `setup` copies them into the case's folder, points main's
origin at the case's own, writes the case's pack (its ruling log is the case's stub's) and control record, and names
the state folder itself where the case has no host file (the engine's default, the checkout's `conveyor/state`;
with a host file it still asks the engine). No case made this fixture by hand.

Two more fixtures were made afresh by every case that used them: `install.test.sh`'s code repo (`coderepo`: a bare
origin, a clone holding a copy of the engine and two commits, used by the `install`, `setup`, `doctor`, `follow`,
`adopt`, `restart` and `servesame` cases) and `setup.test.sh`'s sample (`sample`: a repo on `feature` with its origin
on `trunk`, the gh, claude and codex stubs and the Board's virtualenv stub). Each is now made once per run, by the
first case that asks for it (`lib.sh` `template`, into `$FIXTURE.code` and `$FIXTURE.sample`), and copied: each case
points its copy's origin at its own and writes its own host file. Alone, a `coderepo` took 0.30 to 0.38 s before and
0.02 to 0.03 s after (its first, which makes it, 0.26 s); a `sample` past its `coderepo`, 0.34 to 0.40 s before and
0.04 s after. The repos other cases make (`machine`'s alpha and beta, `rules`'s upstream on `master`, `lane`'s
escape repo) are each a bare `git init`, different in every case, with nothing to copy.

Measured 2026-11-14 on the same machine at a load of 21 to 24, main (bbcbd0d, an archive of it in `/tmp`) and this
change, on the 44 cases that copy them (every case of `install`, `setup`, `adopt` and `followmain`, and `restart`
and `servesame`), by the same timing copy of the runner. Every run passed, every case.

| Run (order) | Before: cases' summed time | After: cases' summed time |
| --- | --- | --- |
| 1 (after, then before) | 252.4 s | 210.1 s |
| 2 (after, then before) | 240.6 s | 214.2 s |

The cases' summed time dropped by 26 to 42 s (10 to 17%) over these cases.

## The fixture `setup` copies, measured

Measured 2026-11-14 on the loop's machine (16 cores) at a load of 38 to 56, main (bbcbd0d, a Git checkout of it) and
this change, on the same 86 cases (every case of `install`, `lane`, `maintest`, `packread`, `pick`, `deps`,
`records`, `privacy`, `cardrules` and `branch`), run as the runner runs them (`slot_take`, `run_case`) by a timing
copy of the runner in `/tmp`, each case's seconds from its slot taken to its report. Every run passed, every case.

| Run (order) | Before: cases' summed time, CPU (user + sys) | After: cases' summed time, CPU (user + sys) |
| --- | --- | --- |
| 1 (before, then after) | 353.5 s | 587.2 s |
| 2 (after, then before) | 449.4 s, 331.0 s | 423.9 s, 322.1 s |
| 3 (before, then after) | 451.6 s, 340.2 s | 482.9 s, 332.0 s |
| 4 (before, then after) | 486.8 s, 341.6 s | 476.9 s, 335.0 s |

Run 4 also timed each `setup` call of those cases (77 calls): 14.83 s summed, 193 ms each, before; 2.35 s, 30 ms
each, after (84% less). Alone, on the same machine, a `setup` took 142 to 193 ms before and 17 to 28 ms after. The CPU
of every after run is below every before run's, by 7 to 9 s over these cases. The summed wall time moved by more than
that from run to run (run 1's two halves differ by 234 s with the same cases passing): at this load it measures the
machine, and the saving, about 0.15 s of the 4 to 7 s a case takes, is inside its noise. Over the whole engine suite
(about 350 `setup` calls) the saving is about 50 s of the cases' summed time.

The whole engine suite on this change (`.conveyor/test-changed.sh`, 513 cases): 511 passed. `machineleft` and
`machinekilled` failed: each runs a case of its own under another scratch folder (`T=$d/in`), where `$T/fixture` is
none. The fixture's folder is now named once, as `lib.sh` is read (`FIXTURE`), and both pass, run again by name.

## The runner ends what a case left holding a slot

`cases-2.md`: two processes an `adopt` case left held a slot of the machine's shared pool for some 20 hours. The
runner already ends every process a case leaves before it reports the case (`run_case`, `case_keep`, `case_end`); no
case pinned that down for a slot the left process holds itself. `caseslot.test.sh` `t_caseslot` runs two cases one
after the other as the runner does: the first leaves a process holding a slot of another pool that, sent TERM, starts
one more that ignores it (as `adopt`'s stub did) and exits; the second finds that slot free as it starts. With
`case_end` made to do nothing, it fails: "the slot the case before this one left held is still held as this one
starts".
