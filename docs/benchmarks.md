# Benchmarks

`conveyor.sh bench swe` runs tasks of [SWE-bench Verified](https://www.swebench.com/) through Conveyor, and the
official SWE-bench harness grades each result. Use it to see how well a version of Conveyor fixes real issues, to
compare two versions, and to compare Conveyor with other ways to build a change ([arms](#arms)).

A task of SWE-bench Verified is a public Python repository at a fixed commit, the text of a real issue from it, and
hidden tests from the real fix. The dataset has 500 tasks.

## Before you run

You need Docker and the SWE-bench harness. Install the harness in its own virtualenv, in the place Conveyor looks for
it:

```
python3 -m venv ~/.local/share/conveyor/swebench-venv
~/.local/share/conveyor/swebench-venv/bin/pip install swebench==4.1.0
```

Conveyor needs this release of swebench, which `conveyor/bench/swe.json` names as `swebench`. Before a run or an
arm's check starts, Conveyor checks that Docker answers and that the harness has this release. When one of them fails,
the run or check stops and says what to repair:

- No harness: install it with the commands above, then check again.
- Another release: the message names the release the harness has. Install this release with the `pip install` command
  above, then check again.
- Docker does not answer: install or start Docker, check that `docker info` works, then check again.

The first run reads the task list from the dataset. Each task then fetches its Docker image, which can be several
gigabytes.

## Run

```
conveyor.sh bench swe 5
```

runs the first 5 tasks. Give any number from 1 to 500. The quick choices are `swe 1` and `swe 5`, which take minutes,
and `swe 20` and `swe 50`.

The order of the tasks is fixed: `conveyor/bench/swe.json` pins the dataset revision and a seed, and they put the
tasks in one order. So `swe 5` is always the first 5 tasks of `swe 20`, while the seed stays the same.

A task that an arm already ran with the same inputs is not run again: its result is used again, at no cost. The
inputs are the arm and its models and efforts, the engine commit, the control record and pack settings of a Conveyor
arm, the contents of its card and area rules, the dataset revision, the harness version and the limits. A change to
one of them gives a new result, and the earlier result stays in the results. A result with no recorded inputs is
shown, but never used again. A run reads these inputs once, when it starts. A change to the control record or the
rules while it runs applies to the next run only.

### Run settings

`--settings <json>` changes the task set and the limits for every arm of one run:

```
conveyor.sh bench swe 5 --settings '{"seed": "my-seed", "cpus": 2, "memory": "4g", "taskTimeout": 7200}'
```

Each key is optional. A key that you leave out keeps its value in `conveyor/bench/swe.json`.

| Key | What it sets |
| --- | --- |
| `revision` | The dataset revision, as a full commit id. The grade reads the tasks from this revision. |
| `seed` | The seed of the task order, 1 to 80 characters. |
| `cpus` | The CPUs of each task's container. It cannot be more than this machine has. |
| `memory` | The memory of each task's container, such as `600m` or `4g`. It cannot be more than this machine holds. |
| `taskTimeout` | The seconds that the install of an arm and its run on one task can each take. The preflight command has a fixed limit of its own. |

The run records its settings in its line in the run history. `conveyor.sh bench swe arms check --settings <json>
<arm>...` runs the preflights with the same settings.

When a run has recorded its start, it prints `conveyor: run <run ID> started`. A run that reuses the kept result of
each of its tasks does not print this line. It prints `conveyor: run <run ID> ended` as its last line, when it has
recorded its end. Before its first task, it prints the
sessions it usually takes and the worst case, and the minutes it is expected to take. A run does not start while the usage guard (`conveyor.sh control guard`, in [the control
record](configuration.md#the-control-record)) is reached, and it stops before the next task when the guard is reached
during the run. The guard reads the Claude account, so it does not stop an arm that does not use the Claude login.
`conveyor.sh bench swe stop <run ID>` ends that run, in its setup or in a task. Without a run ID, it ends the run that
goes now. The run records when it started to stop, ends the work of its arm on the task, and records its end. Stop
removes the run's own containers, the grading container too, and keeps its finished tasks. It does not touch the container of an arms check. A
second Stop of the same run changes nothing. A Stop for a run that already ended says how it ended, and a newer run
goes on. When the process of a run has stopped with no end recorded, Stop records the end and removes the run's
containers. A new run does this too before it starts. `bench swe show <run>` and `bench swe history` give such a run
as `stopped` with `gone` true, before and after its end is recorded.

Each task is built in a sandbox of its own: a local clone of the task's repository at its base commit, with the issue
text as the card's issue. Conveyor builds the task in a Docker container made from the task's own image, with a pack
made for it. The pack holds the task's test command, run in the container, and a command that runs one test file in
the task's own Python environment: `python3 -m pytest` on the file when that Python has pytest, else `python3` on the
file. The change leaves
out the files Python makes (`__pycache__/`, `*.pyc`). The container can see the sandbox and, read-only, the
folder of the installed Conveyor version, and no other folder of this machine. Conveyor builds, reviews, fixes and
tests the card as it does any card. A card that lands is pushed only to the sandbox's own bare origin, never to the
task's repository, and no issue is filed on GitHub. What lands on the sandbox's main is the final patch. A blocked
card has none. The harness then grades the patch with the task's hidden tests.

### Another version

`--engine <version>` builds the tasks with an earlier release (`v1.0.0` and up) or with any full commit id. The
default is main. Only the building of the cards uses that version: the task setup, the grading and the results are
always those of the version you run the command from, so a release made before this benchmark existed can still be
run. The version is installed in the versions folder, as `conveyor.sh install <commit>` does.

### Claude alone

`--solo` runs the same tasks with one Claude session given the issue, with no review, fix or test step. Use it as the
baseline to compare Conveyor with. The session can read, search and edit the files of the task's checkout, and nothing
else: it has no shell and no web tools, so it cannot run the tests. `--solo` is the same as `--arm solo`.

## Arms

An arm is one way to build a task: Conveyor, Claude alone, Codex alone, or Claude Code with a plugin or a method.
Each arm is one JSON file in `conveyor/bench/arms/`. The file names the arm's kind, the logins it uses, how it is
installed in a task's container, the command that builds one task with no one at the keyboard, and a preflight
check.

```
conveyor.sh bench swe 20 --arm conveyor --arm codex-sol --arm caveman
```

runs the first 20 tasks with the three arms. Give `--arm` once for each arm. Every arm builds the same pinned tasks.
The run builds each task with every arm before it goes to the next task, so a run that stops early has compared the
arms on the same tasks. With no `--arm`, the run uses the `conveyor` arm.

| Arm | What builds a task | Install in the container | Login |
| --- | --- | --- | --- |
| `conveyor` | Conveyor, on the seats of the control record | Node.js, the Claude Code and Codex CLIs, jq 1.8.1 and the engine version. The preflight fails when jq is older than 1.8 | Claude, and Codex when a seat uses Codex |
| `conveyor-codex-claude` | Conveyor, with Codex as the builder and Claude as the reviewer | The same as `conveyor` | Claude and Codex |
| `solo` | One Claude session, with no shell (the same as `--solo`) | The Claude Code CLI | Claude |
| `solo-review` | One Claude session, then one more Claude session that reviews the change and fixes it | The Claude Code CLI | Claude |
| `codex-sol` | One Codex session on gpt-6.2-sol, with no review | Node.js and the Codex CLI | Codex |
| `codex-astra` | One Codex session on gpt-6.2-astra, with no review | Node.js and the Codex CLI | Codex |
| `ponytail` | Two Claude sessions with the Ponytail plugin: `/ponytail full`, then the issue in the same conversation | Node.js, the Claude Code CLI and the plugin from `DietrichGebert/ponytail` | Claude |
| `caveman` | Two Claude sessions with the Caveman plugin: `/caveman` (Caveman is off in `claude -p` until it is turned on), then the issue in the same conversation | Node.js, the Claude Code CLI and the plugin from `JuliusBrussee/caveman` | Claude |
| `chisle` | One Claude session with the Chisle plugin | Node.js, the Claude Code CLI and the plugin from `JayPokale/Chisle` | Claude |
| `superpowers` | One Claude session with the Superpowers plugin | Node.js, the Claude Code CLI and the plugin from `obra/superpowers-marketplace` | Claude |
| `feature-dev` | One Claude session that runs `/feature-dev` on the issue | The Claude Code CLI and the plugin from `anthropics/claude-plugins-official` | Claude |
| `everything-claude-code` | One Claude session with the everything-claude-code plugin, told to use its skills and agents | Node.js, the Claude Code CLI and the plugin from `affaan-m/everything-claude-code` | Claude |
| `spec-kit` | Four Claude sessions: `/speckit.specify` with the issue, then `/speckit.plan`, `/speckit.tasks` and `/speckit.implement` | The Claude Code CLI, uv and the `specify` CLI | Claude |
| `bmad` | One Claude session told to use the BMAD Method's quick flow | Node.js and the Claude Code CLI. The run installs the BMAD Method in the checkout | Claude |
| `gsd` | One Claude session that runs `/gsd:quick` on the issue | Node.js and the Claude Code CLI. The run installs GSD in the checkout | Claude |
| `openhands` | Not offered | | |
| `aider` | Not offered | | |

The Claude arms other than `conveyor` use the model of the builder seat when it is a Claude model. A method that
asks questions by design gets a fixed script of steps. Its prompt tells it that no one will answer, and to take the
recommended choice at each point. The files that a method writes for itself (for example `specs/` or `.claude/`) are
not part of the patch.

OpenHands and Aider are not offered. They run on a model provider's API key, and they cannot run on a subscription
login. The benchmark uses no API keys.

### Saved arms

A saved arm is a name and a set of choices. It holds no command. It runs on one of the arms above: a Conveyor arm on
the `conveyor` arm with its own seats, and an agent arm on an agent arm that takes a model, such as `solo`.

```
conveyor.sh bench swe arms save "Claude builds, Codex reviews" '{"kind":"conveyor","seats":{"model":{"cli":"claude","model":"claude-opus-5-5","effort":"high"},"reviewer":{"cli":"codex","model":"gpt-6.2-sol"}}}'
conveyor.sh bench swe arms save "Claude alone on Sonnet" '{"kind":"agent","recipe":"solo","cli":"claude","model":"claude-sonnet-5-5","effort":"high"}'
conveyor.sh bench swe arms show arm-0123456789ab
```

`save` prints the ID of the saved arm, for example `arm-0123456789ab`. Give that ID to `--arm` or to
`bench swe arms check`, as you give the name of an arm. A Conveyor arm takes the seats `model` (the builder),
`reviewer`, `judge`, `fix` and `testFix`. `fix` is the session that fixes the findings of a review. `testFix` is the
session that fixes the card's tests when they fail. When you leave `fix` or `testFix` out, that session uses the
project's own setting for it, and the builder when the project has none. Each seat takes `cli`, `model` and, if you want, `effort`. The test command and the official grade use no
model. An engine version that has no `fix` or `testFix` seat cannot run an arm that sets one: the check and the
start refuse the arm and tell you why. Choose a newer engine version. A Conveyor arm can also take
`rules` and `policy`. An agent arm takes `recipe`, `cli` (`claude` or `codex`, the CLI that the recipe signs in to),
`model` and, if you want, `effort`. The recipe's CLI runs on that model and effort. Without `effort`, the CLI uses
its own default effort. The save refuses a recipe that does not run on the CLI you chose, or that cannot pass an
effort to its CLI when you choose one. Each agent arm in the table above that is offered takes an effort.

The `rules` choice sets the rules that the task's card gets:

- `engine`: the core card rules of the engine version only. This is the default.
- `project`: the core card rules, then your project's `.conveyor/card-rules.md`, then the area rule files that the
  `areas` setting in `.conveyor/project.json` gives for the paths that the task's issue names. Conveyor copies these
  files into the sandbox when it sets up the task. If one of them is missing, the arm does not run, and the run tells
  you which file is missing.

The `policy` choice sets the judge and the priority switches of the task's card. It takes any of these keys:

- `judgeOn`: `true` or `false`. Turns the judge on or off, as `conveyor.sh control judge on` and `off` do.
- `judgeAlways`: a list of finding kinds that the judge always accepts, as `conveyor.sh control judge always` takes
  them. An empty list means none.
- `P0`, `P1`, `P2` and `P3`: `true` or `false`, as `conveyor.sh control rules P3=off` and the other priorities do.
  These switches set which issues the loop builds. The task's issue has no priority, so it counts as P3: `P0`, `P1`
  and `P2` do not change the task's card while `P3` is on. A priority that is off also keeps issues of that priority
  off the queue. When `P3` is off, the task's issue gets the least urgent priority label of your project that is
  still on. When the arm turns off every priority, the check and the start refuse the arm and tell you that its card
  would never be picked.

A key that you leave out keeps the value of your control record.

The task's card uses the seats of the arm over the seats of your control record. It does not use the seats that your control record keeps for one issue (`conveyor.sh control card`).

When you save the same name again with other choices, you get a new ID. The earlier arm does not change, and
`bench swe arms show` still shows it. A run keeps the ID of the arm that it used.

You can choose only the models that the project allows. The builder, `fix` and `testFix` take the builder models of the `models.allowed`
setting in `.conveyor/project.json`: `claude`, `codex-builder` and `opencode`. The reviewer and the judge take the
review models: `codex`, `claude-reviewer` and `opencode`. An agent arm takes the models of both lists for its CLI.
When the project has no `models.allowed` setting, Conveyor uses its own default models. The effort must be one that
the CLI takes. Conveyor does not save an arm with a choice that is not permitted, and it tells you why. A saved arm
does not add a model to the project's models. `bench swe history` shows the permitted choices under `choices`, and
`source` tells you if they come from the project or from the defaults. It shows each saved arm under `arms`, with its
`revision` and its `spec`. Under `defaults` it shows the seats that a task's card uses for a seat that an arm does
not set.

### Containers and logins

Each arm builds each task in a Docker container of its own, made from the task's image. Every arm gets the same CPU
and memory limits (the `limits` setting in `conveyor/bench/swe.json`) and the same time limit for a task (the
`taskTimeout` setting in the same file). The [run settings](#run-settings) of a run change these limits for all of its
arms. The container can see the task's sandbox and no other folder of this
machine, except for a Conveyor arm: its container can also see the folder of the installed Conveyor version,
read-only. The official harness grades the patch of every arm in the same way.

An arm uses the subscription logins that the cards use. The Claude login is the one of the builder's account
(`conveyor.sh control account`). The Codex login is the one in `~/.codex`. Conveyor copies the login files into the
container when it starts the container, and removes the container when the task ends. A login is never put into an
image, the repository, a log or a result.

### Preflight

An arm runs only after its preflight passes. The preflight checks that each login of the arm is on this machine. It then installs the arm in a container and runs the arm on one small task: a file that prints a
word with a spelling mistake. The arm must fire and change the file. A preflight that fails says what is missing. A
run does not start when the preflight of one of its arms fails. A preflight that passed stays good for one day, while
the arm's file and the logins it needs do not change. A run uses it only when it ran on the same image, limits and task
set as the run's. If not, the run does the preflight again.

```
conveyor.sh bench swe arms
conveyor.sh bench swe arms check codex-sol caveman
```

The first command lists each arm with the state of its last preflight. The second runs the preflight of the arms that
you name. It does not start while the usage guard is reached, unless no arm that you name uses the Claude login. It
does not start when an arm or saved arm that you name is not on this machine.

The check prints `<arm>: checking <check ID>` for each arm when it starts, then `<arm>: ready` or
`<arm>: failed: <why>` when it ends. A Conveyor arm is checked on main's engine. While a check runs, the list, the
Board and Start show the arm as checking, with the step that the check is at. A check that fails before the preflight
starts, for example when Docker does not answer or the test image cannot be fetched, records that failure for each
arm. When you ask for a check of an arm while a check of that arm runs, your request waits for that check and gives
its result, if the arm, its logins, the limits and the task set are the same. If not, your check prints its own check
ID and starts when the other one ends.

An arm shows one of these states:

- `checking`: its check runs now.
- `ready`: its last preflight passed, and a run on main's engine with the default settings can use that pass.
- `failed`: its last preflight failed, or its check stopped before it ended.
- `expired`: its last preflight passed more than one day ago.
- `changed`: its last preflight passed, but the arm's file, its logins, the engine commit, the image, the limits or the
  task set changed after it.
- `not checked` or `not offered`.

### An arm that does not fire

An arm fires when its method runs. Each arm's file says what shows that in the arm's output. For example, `caveman` and
`ponytail` fire when the session ran the plugin's command, `superpowers` and `everything-claude-code` fire when the
session used one of the plugin's skills or agents, `chisle` (on in every session) fires when the session loaded it,
and Codex fires when its session completed a turn. When an arm does not
fire in a task, that task is a failure of the arm. This is also true when its install or its command failed. The task
is not skipped, and the run does not grade the change.

## Results

For each task the result shows whether it is resolved, whether the arm fired, and its sessions, tokens and minutes.
The results are kept for each arm and each version. A run ends with the resolved count of n for each arm. A task
whose Docker image cannot be fetched or built, whose container cannot be made, or that the harness could not grade, is
reported as not run, never as failed, and the next run tries it again.

`conveyor.sh bench swe results` shows the results of every arm and version run so far, side by side, with a line that
says how big a difference the number of tasks can show.

`conveyor.sh bench swe diff <A> <B>` compares two arms or two versions on the tasks both ran. Each of A and B is a
version (of the `conveyor` arm), an arm such as `codex-sol`, a Conveyor arm at a version, such as
`conveyor-codex-claude@v1.5.0`, or a results key, as `conveyor.sh bench swe results --json` lists it (`key`). A
name that is also a results key reads the results of that key. An arm or a version reads its newest results, whatever
settings that run used, from these results only:

- a Conveyor arm with no version: the results on the commit that `main` of the engine source points to now;
- a version, or a Conveyor arm at a version: the results on the commit of that version;
- an arm that uses the model of the builder seat, such as `solo`: the results on the builder's model as it is set now, when
  that is a Claude model, else all its results;
- an arm with a model of its own, such as `codex-sol`: the results on the model the arm has now;
- any other arm: all its results.

To read older results, give their results key. It shows:

- the tasks that flipped (resolved by one version and not by the other), and the tasks that stayed the same;
- for each flipped task, the first step where the two runs went apart (build, review, a fix round, the test step, or
  blocked), with each run's review findings, fix rounds, test result, block reason, tokens and minutes;
- when both sides are versions of Conveyor, the commits between them that changed the engine files of that step, with
  their titles;
- a short explanation of each flipped task from one model call, given only the facts above, and labelled as the
  model's reading;
- the totals of each version, and the run-to-run noise for that number of tasks.

On the Board, the [Benchmarks tab](board.md#benchmarks-tab) shows the same runs, results and Compare. It has an
overview with the history of every run, a page for each run, Compare, Start a run with the expected sessions, minutes
and cost of each arm, and an infographic of up to 6 runs. `conveyor.sh bench swe history` and `conveyor.sh bench swe show <run>`
print what the tab reads, as JSON.

While a run goes, `bench swe show <run>` gives the arm, the task and the step it is at, before the task has a result.
The step is one of Checking, Preparing image, Setting up, Running agent, Reading patch, Grading, or for a Conveyor arm
the step its card is at: Building, Reviewing, Judging, Fixing, Rebasing, Testing, Landing or Filing follow-ups. An engine
version that does not record when a step starts shows "Running Conveyor. Step unavailable." The read revision, `seq`,
goes up each time the run changes, including when only the step changes. Every task the run plans is listed, with
each arm's state: waiting, active, finished, interrupted (the task that Stop ended) or not reached. Each arm also has
`wall`: the minutes of its work in this run, a task not run and the task that Stop ended included. A reused result
adds none. The active task gives `start`, the time its work began, so its minutes so far are the time since then.

Each run also keeps a short event log, the last lines of which `bench swe show <run>` gives as `tail`. Each line has
a time, an arm, a task and an event: a step, a result (Resolved, Unresolved, Not run or reused), or the start and end
of the run. The log stays after the run ends. It holds no output of the arms and no text from their containers.

A run also gives its cost at list prices: the same prices as the Board's Cost panel, with your `prices` in the pack
over them. `bench swe show <run>` and `bench swe history` give `cost` for the run and for each arm, and `bench swe
diff <A> <B> --json` gives it in the totals of each side, for the tasks that both ran. While a run goes,
the cost includes the active task's work so far. Each task's result keeps its `cost` and the prices used for it. A
Conveyor arm's sessions are priced from the token usage that its card records for each session, including the judge's
and that of a session that failed.
When a session's final record comes, it replaces the figure for that session so far. An agent arm reports no usage by
model, so its cost is unknown. A reused result adds nothing. The work of a task that Stop interrupted is counted.

Each `cost` has `usd` and `state`:

- `known`: every session is priced.
- `partial`: some sessions have no usage that can be priced, for example a session that has not reported usage yet.
  `usd` is the cost of the priced sessions only.
- `unknown`: no session can be priced, and `usd` is null. Runs and results from before costs were recorded show
  unknown, not $0.

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
- The sessions of an arm run in its container and see only the task's sandbox (a Conveyor arm also sees the folder of
  the installed Conveyor version, read-only). In a Conveyor arm, Codex sessions run without Codex's own sandbox,
  because it cannot start a command in the container. The container is their sandbox. Conveyor also reads the reference
  fixes and hidden tests only to make the task list and to grade a patch, and then removes them.
- The task images are for x86-64. Each arm installs its tools in each task's container, with the network, so each
  task takes more minutes than the build alone, and an install that the network stops makes the arm fail that task.
- An arm installs the latest version of its plugin or method. Two runs some weeks apart can use different versions.
- A Claude login must be a file on this machine. On macOS, Claude Code can keep its login in the Keychain. Then the
  Claude arms cannot run, and their preflight says that the login file is missing.
- A session in a container can renew the login that it was given. When that happens, the login on this machine can
  stop working, and you must sign in again.
- An arm's preflight and its fired check read the arm's own output. A new version of a plugin that changes that
  output can make an arm fail its preflight, or not fire.

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

With `--json`, each group also has `spread`: the standard deviation of each mean figure a card.

The Board shows the latest drift watch of a project on the [Benchmarks tab](board.md#benchmarks-tab), folded under
**Drift watch**. Each figure there shows one of these:

- **Moved**: the two means are more than two standard errors apart.
- **In its usual range**: the two means are closer than that.
- **Too few cards**: a group has fewer than 5 cards, so no figure is judged.
- **Not read**: a group has no figure or no spread for it.
