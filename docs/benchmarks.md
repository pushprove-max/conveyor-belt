# Benchmarks

`conveyor.sh bench swe` runs tasks of [SWE-bench Verified](https://www.swebench.com/) through Conveyor, and the
official SWE-bench harness grades each result. Use it to see how well a version of Conveyor fixes real issues, and to
compare two versions.

A task of SWE-bench Verified is a public Python repository at a fixed commit, the text of a real issue from it, and
hidden tests from the real fix. The dataset has 500 tasks.

## Before you run

You need Docker and the SWE-bench harness. Install the harness in its own virtualenv, in the place Conveyor looks for
it:

```
python3 -m venv ~/.local/share/conveyor/swebench-venv
~/.local/share/conveyor/swebench-venv/bin/pip install swebench
```

The first run reads the task list from the dataset. Each task then fetches its Docker image, which can be several
gigabytes.

## Run

```
conveyor.sh bench swe 5
```

runs the first 5 tasks. Give any number from 1 to 500. The quick choices are `swe 1` and `swe 5`, which take minutes,
and `swe 20` and `swe 50`.

The order of the tasks is fixed: `conveyor/bench/swe.json` pins the dataset revision and a seed, and they put the
tasks in one order. So `swe 5` is always the first 5 tasks of `swe 20`. A task that the same engine commit already ran
is not run again: its result is used again, at no cost.

Before it starts, a run prints the sessions it usually takes and the worst case, and the minutes it is expected to
take. A run does not start while the usage guard (`conveyor.sh control guard`, in [the control
record](configuration.md#the-control-record)) is reached, and it stops before the next task when the guard is reached
during the run. `conveyor.sh bench swe stop` ends a run.

Each task is built in a sandbox of its own: a local clone of the task's repository at its base commit, with a pack
made for it (the test command of the task's own Docker image) and the issue text as the card's issue. Conveyor builds,
reviews, fixes and tests the card as it does any card, on the machine's test slots and under the builder cap. A card
that lands is pushed only to the sandbox's own bare origin, never to the task's repository, and no issue is filed on
GitHub. What lands on the sandbox's main is the final patch; a blocked card has none. The harness then grades the patch with the task's hidden tests.

### Another version

`--engine <version>` builds the tasks with an earlier release (`v1.0.0` and up) or with any full commit id. The
default is main. Only the building of the cards uses that version: the task setup, the grading and the results are
always those of the version you run the command from, so a release made before this benchmark existed can still be
run. The version is installed in the versions folder, as `conveyor.sh install <commit>` does.

### Claude alone

`--solo` runs the same tasks with one Claude session given the issue, with no review, fix or test step. Use it as the
baseline to compare Conveyor with. The session can read, search and edit the files of the task's checkout, and nothing
else: it has no shell and no web tools, so it cannot run the tests.

## Results

For each task the result shows whether it is resolved, and its sessions, tokens and minutes. A run ends with its
resolved count of n and the engine commit. A task whose Docker image cannot be fetched or built, that the harness
could not grade, or whose Claude alone session failed (for example, a sign-in error), is reported as not run, never as
failed, and the next run tries it again.

`conveyor.sh bench swe results` shows the results of every version run so far, side by side, with a line that says how
big a difference the number of tasks can show.

`conveyor.sh bench swe diff <version A> <version B>` compares two versions on the tasks both ran. It shows:

- the tasks that flipped (resolved by one version and not by the other), and the tasks that stayed the same;
- for each flipped task, the first step where the two runs went apart (build, review, a fix round, the test step, or
  blocked), with each run's review findings, fix rounds, test result, block reason, tokens and minutes;
- the commits between the two versions that changed the engine files of that step, with their titles;
- a short explanation of each flipped task from one model call, given only the facts above, and labelled as the
  model's reading;
- the totals of each version, and the run-to-run noise for that number of tasks.

On the Board, the Tests page has a Benchmarks part with the same run, results and Compare ([Tests
page](board.md#tests-page)).

## What the numbers mean

The resolved count is the number of tasks whose final patch passes the task's hidden tests, as the official harness
grades it.

A small run tells you little. Two runs of the same version can differ by chance, because the models do not give the
same answer each time. With n tasks, a difference under about the square root of 2n tasks is within that noise: with 5
tasks only a difference of 4 tasks shows, with 20 tasks 7, and with 50 tasks 10. With 1 task, only a total break
shows. Use `swe 1` and `swe 5` to see that a version works at all, and `swe 50` or more to compare two versions.

## Limits

- All tasks are in Python. A result says nothing about other languages.
- The tasks come from public repositories and their fixes are public. The models may have seen them during training,
  so a score can be higher than on new work.
- A task's tests run in the task's Docker image, which holds the repository's own environment. A project whose build
  makes compiled parts can fail there for reasons other than the change.
- The minutes are those of this machine and depend on the other work on it.
- Conveyor's sessions run on a task as on any card, with a shell on this machine. While a card builds, no file on
  this machine holds the reference fixes and hidden tests from Conveyor: it reads them only to make the task list and
  to grade a patch, and then removes them. A copy of the dataset that you keep, for example in the Hugging Face cache,
  stays, and a session that looks for it can find it.

## Drift watch

The drift watch compares the cards that ran on one engine commit with the cards that ran on the engine commit before
it. It uses the cards your belt runs anyway, so it costs no sessions.

Run it on the build machine:

```
conveyor.sh bench drift [<engine commit>]
```

With no commit, it compares the latest engine commit with the one before it. Give a commit, or the start of one, to
compare that commit with the one before it. Each card's worktree line in the card records names the engine commit the
card ran on. The engine commits are in the order that their first card started. A commit whose cards are all still
on the belt is a commit too: the command compares it, with no cards in its group, and does not skip it.

Only a card that ended counts in a group: a card that landed, that was closed, or that was blocked. A card still on the
belt does not count. A card ends at the first of these: a blocked card whose issue is closed later stays blocked, and
its time ends at the block.

The command shows the two groups side by side, before and after:

| Figure | What it is |
| --- | --- |
| Cards | The cards of the group that ended. |
| Landed | The cards that landed. |
| Blocked | The cards that were blocked. |
| Tokens a card | The mean of the Claude and Codex tokens of each card, every step added up. |
| Minutes a card | The mean time from the pick-up of a card to its end. |
| Reviews to land | The mean number of reviews of a card that landed. |
| Fix rounds a card | The mean number of fix rounds of a card. |
| Minutes waited a card | The mean time that a card waited on other cards that change the same files, and for main to change when main failed the same tests, to its end. A card that landed or was blocked before the engine recorded this time has no figure and is not in this mean. A dash shows when no card has the figure. |

A group of fewer than 5 cards is too small to mean anything, and the command says so under the table. A difference
between the groups does not tell you its cause: the issues of the two groups are not the same issues.

The Board shows the latest drift watch of a project in the Benchmarks part of the
[Tests page](board.md#tests-page).
