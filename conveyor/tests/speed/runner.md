# The runner, end-to-end, foreman, lanes and map tests

Measured 2026-11-14 as `README.md` says, on the loop's machine (16 cores), main first (22952b4, from a Git checkout of
main) and then this card's change, three runs each, before and after one after the other, so each pair ran at about
the same load. The load average was far from usual: 13 to 35 during the runs (the load beside each pair below). Every
run passed. A file's time is the middle of its three runs. A case's time before is its own seconds as the file ran it
(its cases one after another); after, the cases run side by side, and a case's time is from its start to its end.

| File | Before: file (slowest case) | After: file (slowest case) | Faster by | How |
| --- | --- | --- | --- | --- |
| `.conveyor/test-changed.test.sh` | 2.51 s (no cases by name; its checks ran one after another) | 0.64 s (its parts side by side) | 74% | Load 33 to 35. Its checks are in 28 parts (`p_<name>`) that run side by side, each on its own copy of the scratch repo (or of this checkout's map copy) as committed; a part that went on from the state an earlier check left (a changed `x.sh`, a committed map test, the change run again) makes that state itself first. The same 49 checks, the lines numbered once every part has ended; a part that does not run to its end is a `not ok`. |
| `.conveyor/test-lint.test.sh` | 0.76 s (the lint of this whole checkout, 0.64 s alone) | 0.20 s | 73% | Load 31. Removed the check that this checkout's own tests pass the lint: `test-changed.sh` lints the same files on every run (the Test step's and every session's), and this file's last case proves it does and fails on a sleep-then-check. Its 60 lint cases run side by side, reported in the order they were called. |
| `conveyor/conveyor.test.sh` (the runner) | 0.85 s of its own (whole run 1.73 s) | 0.20 s of its own (whole run 1.03 s) | 76% | The runner has no cases: its time is its own in a whole-suite run, with every case a no-op and no whole-suite turn waited for, before its first case starts and after its last ends (five runs each; the whole run, slot taking included, beside it). It split the slowest-first list from the rest with a `grep` per case and read each case's exit status with a `cat` per case, 300 of each; both are now done in the shell. |
| `conveyor/foreman/foreman.test.sh` | 16.42 s (`projects` 6.07 s) | 5.06 s (`session` 4.29 s) | 69% | Load 16 to 26. Each case is a function (`t_<case>`) that runs side by side with the others on a host of its own (`fixture`); `setup`, `launch` and `archive` stay one after another in `t_setup`. A case that went on from what an earlier one left makes it itself first, and says so: the Foreman set up (`ready`), the name Ada, the wake case's snapshots, a mark (`claim c7`), the Board's data file. `projects` is in three (`projects`, `projects-filing`, `projects-groups`), each from `projects_start` and the marks the part before it left. |
| `conveyor/lanes/research.test.sh` | 14.51 s (`refused` 4.45 s) | 4.88 s (`allowed` 3.22 s) | 66% | Load 13 to 14. Each case runs side by side with the others on a host and project of its own (`fixture`), each after `create` making the lane first (`lane`). `refused` is in four parts and `sandboxed` in four (`sandbox_start`: what it made before its checks, and the link the case refused leaves in `reports/`). |

No case was skipped and no limit or timeout raised. No file was removed, so `.conveyor/engine-areas.json` needs no change
(the foreman and lanes files are under its `outside` folders; the two `.conveyor` files are not engine files), and no
engine case was renamed, so `conveyor/conveyor.slowest` and `conveyor/tools/closure.slowest` are as they were.

## Shared helper ideas

- `conveyor/lib/slots.sh` `slot_take` (engine code, not a test helper): with no home slot, each case's slot is asked
  for by an outside `flock`, about 3 ms a case, 0.9 s of a 300-case run with no-op cases. A whole-suite run could take
  its slots with fewer outside programs.
- `conveyor/tests/lib.sh`: none from this group.
