# The hooks' time per call

Each `.claude/hooks/*.sh` runs once per tool call it is registered for: in a card's session
(`conveyor/card-settings.json`) `git-safety.sh`, `bash-guardrails.sh`, `adversarial-review-gate.sh` and
`dependency-addition-guard.sh` before every Bash call, `dependency-addition-guard.sh` and `ruling-cite-gate.sh` before
every Edit or Write, `worker-ask-guard.sh` before every question. The others are measured too, on the same inputs.

## How it was measured

Measured 2026-11-14 on the loop's machine (16 cores, load average 4 to 8 during the runs), from this card's worktree,
with the session's own environment (`CONVEYOR_CARD` set, as in every card session). Before is main (2d6d8df, from a
Git checkout of main outside the worktree, `git clone --shared --branch main`); after is this card's change. Every hook
ran 20 times on each input, main and the change one after the other, each call fed its input on stdin with its output
thrown away, timed by bash's `time` (wall clock, and CPU as user plus system time of the hook and every program it
started). The numbers are the mean per call, in milliseconds.

The inputs: plain `ls -la conveyor`, test `timeout 240 bash conveyor/conveyor.test.sh metrics`, git `git status
--short` (each a Bash call), and edit, an Edit of `conveyor/lib/x.sh` (a code file outside memory and the rules
folder, the usual edit). Programs started were counted with `strace -f -e trace=execve`.

## Per call, before and after (ms: wall / CPU)

| Hook | plain | test | git | edit |
| --- | --- | --- | --- | --- |
| `adversarial-review-gate.sh` | 10/11, 10/11 | 10/11, 10/10 | 10/10, 10/11 | 8/9, 8/9 |
| `ask-records-decision.sh` | 9/9, 9/9 | 9/9, 9/9 | 9/9, 9/9 | 9/9, 9/9 |
| `bash-guardrails.sh` | **54/58, 31/33** | **53/58, 33/35** | **54/58, 31/33** | 6/6, 6/6 |
| `bash-write-rules.sh` | 6/6, 6/6 | 6/6, 6/6 | 6/6, 6/7 | 6/6, 6/6 |
| `board-open.sh` | 4/4, 4/4 | 4/4, 4/4 | 4/4, 4/4 | 4/4, 4/4 |
| `bugfix-test-lock.sh` | 6/6, 6/6 | 6/6, 6/6 | 6/6, 6/6 | 6/6, 6/6 |
| `codex-dispatch.sh` | 6/7, 6/6 | 6/6, 6/7 | 6/6, 6/7 | 6/7, 6/6 |
| `dependency-addition-guard.sh` | 31/37, 31/37 | 32/38, 32/38 | 32/35, 33/35 | 10/11, 10/11 |
| `file-size-cop.sh` | 8/9, 8/9 | 8/8, 8/8 | 8/8, 8/8 | 9/10, 9/10 |
| `git-safety.sh` | 6/6, 6/6 | 6/6, 6/6 | 6/6, 6/6 | 6/6, 6/7 |
| `literal-secret-warning.sh` | 7/7, 7/7 | 7/7, 7/7 | 7/7, 7/7 | 10/12, 10/12 |
| `new-test-file-guard.sh` | 9/9, 9/9 | 9/9, 9/9 | 9/9, 9/9 | 9/9, 9/9 |
| `ruling-cite-gate.sh` | 68/71, 7/7 | 68/71, 7/7 | 68/71, 7/7 | **74/78, 13/14** |
| `ruling-log.sh` | 7/7, 6/7 | 7/7, 7/7 | 6/7, 6/7 | 6/7, 7/7 |
| `suite-rerun-guard.sh` | 11/12, 11/12 | 32/34, 32/34 | 10/11, 10/11 | 6/6, 6/6 |
| `worker-ask-guard.sh` | 12/13, 12/13 | 12/13, 12/13 | 12/13, 12/12 | 12/12, 12/12 |

Each cell is before, after. A hook on an input it is not registered for mostly exits at once; those cells are the
cost of starting it.

## The two that cost the most, and what changed

- `bash-guardrails.sh`, on every Bash call: 54 ms, five times `git-safety.sh` and `adversarial-review-gate.sh` and
  more than half of the four Bash hooks' 102 ms together. It started 28 programs on a plain command; it now starts 7 (`cat`, and `jq` for the
  command, the pack's two settings and the call's folder). Same decisions: each skipped program's result could not
  change one.
  - The heap check's segment loop (`sed`, `sed`, `awk`, `grep`) runs only when the command holds `--test`: without
    one it read a single empty segment, which never holds a node call.
  - The redirect check starts `perl` only for a segment holding `>`: a word with no `>` is no redirect.
  - The command's search text is built once, not once for each of the search, aws and card rules; its arithmetic
    `sed` runs only when the command holds `$((`.
  - `wr_real` finds a path's folder and name by parameter expansion, as `dirname` and `basename` give them, not by
    starting both (four programs a segment).
  - The session id (`jq`) is read only when a caller hunt needs it.
- `ruling-cite-gate.sh`, on every Edit and Write: 74 ms, the most of any hook. Naming the decision log's path started
  some twenty programs (git, jq and the engine's `state-dir`) on every call; it is now named only once an added line
  in memory or the rules folder cites a ruling, the only time the log is read. `--id` names it as before.

`dependency-addition-guard.sh` (31 ms) and `suite-rerun-guard.sh` on a test command (32 ms) are left as they are: about
the same as `bash-guardrails.sh` now, and not by a wide margin above the others.
