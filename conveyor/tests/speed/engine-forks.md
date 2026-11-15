# The programs the engine starts in its tests (#532)

#473's trace found that most of the engine suite's CPU is the engine starting programs (`batchfails` alone started
6,475, 1,820 of them `jq`). This card counted, for the whole engine suite, the programs each engine function starts,
and cut the top ones.

## How it was counted

- Every bash the suite starts traced its commands (`BASH_ENV` naming a file that runs `set -x`, with
  `BASH_XTRACEFD` on a file of its own and `PS4='+@${BASH_SOURCE[0]##*/}|${FUNCNAME[0]:-main}|${FUNCNAME[1]:-}|${BASH_SOURCE[1]:-}@ '`).
- A traced simple command whose first word is not an assignment, a builtin, a keyword or a shell function is one
  program started, counted to the function and file that ran it. `command <program>` counts as `<program>`. The
  engine's `git()` (conveyor.sh) only runs `command git`: its programs count to the function that called it.
- Checked against `strace -f -e trace=execve` on `batchfails`: 5,283 programs started (each `execve` that worked), and
  5,193 counted from the trace of that case, within 2%.
- The whole suite (`conveyor/conveyor.test.sh`, its 585 cases), in four runs of chosen cases, each under
  `timeout 600`. Before: main at 66d94fb. After: this card's change. In both runs every case passed but `pack` and
  `snapshot`, which also fail on main at 66d94fb without the trace.
- A count that depends on waits (a card's claim, asked each turn while it waits; a loop's turns) changes a little from
  run to run with the machine's load: a change of 1% or less is that, not a cut.
- Engine functions only: a function of `conveyor/conveyor.sh` or `conveyor/lib/*.sh`. The tests' own harness and stubs
  are left out. `new` is a function inside `check` (views.sh); together they went from 39,187 to 34,088.

## Top 20 engine functions by programs started

| # | Function (file) | Before | After | Change | Programs before (top) |
|---|---|---:|---:|---:|---|
| 1 | `check` (views.sh) | 25,735 | 24,014 | -7% | wc 7739, head 7657, cksum 4286, flock 2699 |
| 2 | `claim` (claim.sh) | 22,007 | 13,777 | -37% | jq 17450, mv 1934, git 1920, basename 703 |
| 3 | `card` (card.sh) | 20,216 | 20,188 | +0% | jq 8513, git 6214, rm 1819, sed 1236 |
| 4 | `installed` (install.sh) | 19,523 | 905 | -95% | git 19272, grep 114, readlink 108, find 29 |
| 5 | `run` (run.sh) | 15,778 | 15,613 | -1% | jq 7888, grep 2905, sort 2493, rm 919 |
| 6 | `slot_used` (slots.sh) | 15,133 | 14,209 | -6% | flock 14224, seq 909 |
| 7 | `cardpatch` (claim.sh) | 14,181 | 7,412 | -48% | git 9454, cut 4727 |
| 8 | `new` (views.sh) | 13,452 | 10,074 | -25% | tail 6726, head 6726 |
| 9 | `locked` (records.sh) | 12,019 | 12,003 | +0% | flock 12019 |
| 10 | `owed` (push.sh) | 11,745 | 8,378 | -29% | jq 6632, tail 3306, git 1807 |
| 11 | `rerunlist` (testrun.sh) | 10,017 | 10,016 | +0% | sed 4059, jq 2531, sort 1266, grep 633 |
| 12 | `testlogs` (session.sh) | 8,998 | 8,948 | -1% | find 4499, sort 4499 |
| 13 | `deps` (push.sh) | 8,940 | 3,405 | -62% | grep 4418, dirname 1141, mkdir 1139, git 1101 |
| 14 | `watch` (session.sh) | 8,721 | 6,977 | -20% | jq 3990, rm 3866, awk 318, mv 146 |
| 15 | `verdict` (followups.sh) | 8,718 | 8,705 | +0% | grep 3151, sort 2063, wc 2063, tail 1441 |
| 16 | `slot_try` (slots.sh) | 8,605 | 7,936 | -8% | flock 7852, seq 753 |
| 17 | `line` (records.sh) | 8,525 | 8,506 | +0% | jq 8525 |
| 18 | `donewhen` (testrun.sh) | 8,232 | 8,220 | +0% | git 3689, jq 2273, awk 1544, rm 726 |
| 19 | `tests` (testrun.sh) | 8,166 | 8,168 | +0% | git 2292, rm 2069, cat 1419, grep 823 |
| 20 | `land` (claim.sh) | 7,933 | 7,925 | +0% | git 6482, jq 1427, mv 24 |

All programs the suite started: 628,125 before, 562,064 after (10% fewer). Those of engine functions: 549,770 before,
486,281 after (11% fewer).

## What changed

- `installed`: the files of the tree are hashed in one `git hash-object` run (`xargs -0`: a few, for a tree too long for
  one command line), not one run each.
- `claim`: the card's name from its claim file's name by bash, not `basename`; a claim's pid read in the same `jq` run
  as the claim; no `jq` run for the cards a card gave way to when it is not away, for the cards it went past when there
  are none, or for the cards whose change applies together when there are none; with no other card's live claim, none
  of the steps whose answer matters only when there is one (`together`, `ready` of the card, the filters of the
  claims).
- `cardpatch` and `fits`: the patch id is cut from `git patch-id`'s line by bash, not `cut`.
- `check` (views.sh): the new lines are counted once, not twice (`new` runs three times, not four).
- `owed`: the last landed line taken by bash, not `tail`.
- `deps`: the exclude file read once, not one `grep` per linked path; its folder by bash, not `dirname`.
- `watch`: `rm` of the card's stalled mark only when there is one.
- `slot_used`, `slot_try`, `slot_pool`, `slot_cpus`: the slots and cores counted by bash loops, not `seq`, `tr` and `wc`.

## Left as they are

- `locked`, `slot_used`, `slot_try`: one `flock` per lock or slot is the lock itself; bash has none.
- `card`, `run`, `land`, `tests`, `donewhen`: their programs are spread over many steps, no one of them large.
- `rerunlist`: its `sort -u` sorts as the locale does; one `jq` run in its place would sort by code point.
- `line`: one `jq` run per record line, which it writes.
