# Conveyor

## Control

`conveyor.sh control [<action>]` changes the control record; with no action it prints the record. A new project starts
on the values in `conveyor/lib/control-defaults.json`; a record keeps each value it sets.

`conveyor.sh control cap <1-100|off>` sets the card cap: the most cards on the belt at once (Cards at once on the Rules
tab). The cap counts every card of the project on the belt, in any step: its brief, build, fix, review (with the
judge), Test step or any wait. The only cards it leaves out are those that land or push, or have landed or pushed. A
card that waits at its landing claim on another card still counts. A card whose landing fails (main moved, a conflict)
counts again at once. Before it runs its checks or a session again, it waits until the count is under the cap and
prints that it waits for room. The fix card of a red main does not wait: it goes on at once. `conveyor.sh shut`
ends a card that waits for room. `conveyor.sh control stop` ends it too, but not a card that has filed the slices of its issue: that card goes on after the stop and finishes. A card that waits on such a card at its claim can lend its room to it: when its own
wait ends, it waits for room in the same way. The loop starts no card until the count is under the cap, so for a short
time the belt can hold more cards than the cap. The machine's test slots (the host file's
`testSlots`) limit tests apart from the cap. These waits count:

- a wait at the landing claim on a card that changes the same files,
- a wait on the batch card that took the card,
- a wait in the Test step for main to change, when main is red.

A card that waits for its seat's CLI counts against the cap too. The loop picks a new card only while the count is
under the cap, so waiting cards use up its space. Two picks go past a full cap: a card that others wait on, once
`retry` has given it back, and the fix card of a red main. The machine's cap (`cap` in the host file) counts every card of
each project that builds, reviews, tests or lands, and leaves out the waiting cards. `conveyor.sh foreman status`,
`/units` and the Board give the count of cards against the cap.

`conveyor.sh control judge on|off`, `conveyor.sh control judge always [<kind>...]`,
`conveyor.sh control judge rare <level>...|none` and
`conveyor.sh control judge <cli> <model> [effort]` set the review's judge (below, The judge): each project's record holds
its own, and the Board's Rules tab sets them in its Judge row.

`conveyor.sh control tests <cli> <model> [effort]` sets the Tests seat (below, Test actions), and
`conveyor.sh control tests default` clears it.

`conveyor.sh control rules <rule>=<on|off>...` sets what the loop builds:

- `P0`, `P1`, `P2`, `P3`: issues of that priority. An issue with no priority counts as P3. `P3` also decides what
  happens to an accepted P3 review finding (below, The judge).
- `followups`: follow-up issues.
- `<areaPrefix><name>`: an area label; off means issues with that label are never built.
- `push`: whether a card that lands is pushed (Push on landing). On, the loop pushes each landing.
  Off is land only: cards still land on main one after another, each building on the last, and the loop pushes none of
  them (a `run` does not end in failure for it); what landed waits for the Board's Push landed (The full test suite,
  below), and the Board shows how many landed cards are not pushed and which.
- `visible`: whether a change customers or staff will see needs the owner's yes (Approve visible changes). On,
  a card whose change touches product code and that its reviewer says is visible stops for a
  `Visible change approved:` line on its issue, or on a parent issue that it inherits the yes from (follow-ups and split
  slices), and an issue whose `## What customers or staff will see` section names a change is
  not picked without one. Off, no card or issue waits for that line: the build brief and the review do not ask for it,
  the reviewer still answers the USER-VISIBLE line (kept on the card's review line), and the card lands as any other.
  A visible change landed while it is off was never approved; the Board says so beside the switch.
- `lint`: the rule Lint check, on by default. On, each card's change goes through the review gate (Lint, below)
  before each review and the landing gate before it lands. The exception is a review of the change that the landing
  gate's lint fix left: while no other session changes it, it has no review gate, because the landing gate checks it. Off, no lint command runs in a card and the brief has no `# Lint` section.
- `failfast`: the rule Stop a card's tests at the first failure, on by default. On, a card's test step ends at its
  first failed case: no other test file or case starts, the files that still run stop, and the step names the files
  that did not run. Each file's command gets `CONVEYOR_TEST_FAILFAST=1`. The run again after such a stop runs the failed
  file, so the cases after the failed one run too; its cases that passed run again too, unless the test command
  leaves out the cases that its `CONVEYOR_TEST_RERUN` list names as passed. Off, the step runs every case that it
  selects. A release's suite runs every case with either setting.
- `teststeponly`: the rule Only the Test step runs tests, off by default. On, the card rules of each session leave out
  each paragraph that starts with the line `Your own test runs, in a build or fix session:`. In their place, the rules
  say that the Test step runs the tests and that a session reads the last Test step's result. The card's command
  guard also refuses each test command of a session, a named case or test file too. Off, the card rules are the text
  of their files.
- `pushbatch`: the rule Push after a combined test run, off by default. On, the loop pushes no landing until the run
  is due (`pushbatchwhen`). Then it pushes all the landings since the last push together, after their tests pass on
  main (the run before a push, which then runs even with `push.check` off). A file that fails holds them all, and the
  push line names the landing that broke it, or says that it failed before those landings. Off, the loop pushes each
  landing as it comes.
- `pushbatchwhen`: when the run of Push after a combined test run is due: a number of landings not pushed (1 to 100),
  or a UTC time of day, `HH:MM`. The default is in `lib/control-defaults.json`.
- `pushbatchtests`: which tests that run runs: `linked` (the default), the test files linked to the landings; `all`,
  every test file of main but the pack's runners of the whole suite.
- `split`: the rule Split large issues, `off`, `shadow` or `on`. It is on by default (`conveyor.sh control rules split=<off|shadow|on>`).
  Before a card builds, code measures its issue against the pack's `split` limits; an issue that reaches
  one goes to the judge one time, which answers keep or 2 or 3 slices. Shadow records the verdict on the card's
  `split` line, and the card builds the issue whole. On files the slices as follow-ups (`Follow-up of #N`) and as
  sub-issues of the issue, and holds the issue as their umbrella; Conveyor closes it when all its slices are closed. Off checks no issue.
  A card whose change grows past `split.growFiles` files (`*.md` left out) asks the judge one time before its next
  review: keep, or keep the core change and move the rest into follow-up slices. Shadow records the answer on the
  card's `grown` line. On files the slices, drops their files from the change in one fix session, and goes on
  ([Split large issues](../docs/configuration.md#split-large-issues)).
- `pick`: the rule Pick settings, `off`, `shadow` or `on` (`conveyor.sh control rules pick=<off|shadow|on>`). After
  the split check and before the build, code puts each card in a group and records the builder that the rule
  chooses for it, as `pick` on each step line of the card from then on, up to its end. The choice is the project's builder, or the
  card's own builder when you set it (`control card`). The project's judge then chooses the builder, reviewer and
  judge of the card, from the seat's pick list in `pick.<seat>` when the pack sets one: the models that the judge can
  give the seat, each with its effort range (the Board's Pick settings row, or `conveyor.sh pick models <seat>
  <model>[=<min>-<max>]...`). Conveyor fits each choice to that list, or to `models.allowed` for a seat with no list,
  and records it in `pick` as `asked`. The judge's call has its own `seats` line, which counts in
  the cost of the card. In Shadow, the card builds on its builder as before. In On, the card uses the judge's
  seats, but a seat that you set for the issue keeps your setting. 1 small card in 5 that names no pipeline file is
  a trial on the group's challenger. The challenger is Sonnet 5.5 at first, then the one that `next` puts on trial.
  The card builds at the judge's effort, fitted to its range in the builder's pick list. When the builder has a pick
  list that does not name the group's challenger, no card of the group is a trial. After ten trial cards of a
  group, Needs you asks for your decision: `conveyor.sh control pick <group> <promote|keep|drop>`. Only your
  decision adds a medium group (`add`), tries the next challenger of a promoted group (`next`), or gives the cards a
  reviewer or judge from a replay result (`control pick <reviewer|judge> promote <model>`). When the
  promoted cards of a group cost more for each landed card than its default cards, the rule goes back to Shadow
  ([Pick settings](../docs/configuration.md#pick-settings)).
- `healsdays`: the days an entry of the self-heals list can go unfixed and unseen before it leaves the list, a whole
  number from 1 to 3650 (`conveyor.sh control rules healsdays=<days>`; [Self-heals expiry](../docs/configuration.md#self-heals-expiry)).

Every rule is on by default, except `push` and `visible`, which are off, `pick`, which is `off`, and `healsdays`, which is a number of days, 30 at first. An issue a rule excludes is left out of the pick and listed as skipped, with the rule
that skips it. A record saved before a rule existed reads that rule at its default.

`conveyor.sh control land-as main|pr` sets Land as (`landAs` in the record; null, the default, is the pack's
`push.landAs`). With `pr`, the push sends main to `conveyor/landing` and keeps one pull request open from it into the
default branch ([Land as](../docs/configuration.md#land-as)).

`conveyor.sh control pr-merge button|release|idle` sets Merge PR (`prMerge` in the record; null, the default, is the
pack's `push.prMerge`): who merges that pull request ([Merge PR](../docs/configuration.md#merge-pr)).

`conveyor.sh control dep-guard on|off` sets the dependency guard (`depGuard` in the record; a record saved before it
reads as on). On, an issue is never picked while an issue its `Depends on:` lines name is open, nor while a follow-up
filed from one is: a release, the order list and a retry do not change that. Off, `conveyor.sh control force <issue>`
adds the issue to `forced`, and it is picked despite its open dependencies; it leaves `forced` once a card of it has
landed or its issue is closed. With the guard on, `control force` is refused (exit 2) and changes nothing; a forced
issue waits again while the guard is on.

`conveyor.sh control push-check on|off|default` (the Rules tab's Test before a push; `default` clears it) sets whether the test files linked to the
landings since the last push run before a push (`pushCheck` in the record). A record that does not set it, as a new
one does not, takes the pack's `push.check` (on by default). Off, a push runs no test first, unless the rule Push
after a combined test run (`pushbatch`) is on: then the run before the push still runs.

`conveyor.sh control onboarded <rule>...` records that the owner set up the project on the Board: `onboarded` in the
record becomes `{at, rules}`, the time and the rules the owner confirmed, each by its key on the Board (`build`,
`dep-guard`, `review-account`). A new record has `onboarded` null, and the Board opens its setup
([Set up a new repository](../docs/board.md#set-up-a-new-repository)). A rule that the list does not name opens the
setup again, at that rule's step.

`conveyor.sh control depends <issue> add|remove <issue>...` (the Board's "Depends on…", on the Control and Rules tabs)
changes the issue's `Depends on:` line on GitHub, through `gh-write`; the control record is not touched. add puts the
numbers on the body's last `Depends on:` line, or writes `Depends on: #N` at the end of the body; remove takes them off,
and drops a line left with none; the rest of the body is kept byte for byte. It is refused (exit 2), with nothing
written, for an issue depending on itself, an issue that is not open in the project, a dependency that would make a
cycle, an add to an issue whose card is already running, and a remove of a number no `Depends on:` line names.

## The loop's turn

`run()` in `lib/run.sh` is the loop of `conveyor.sh run` and `conveyor.sh serve`. It takes the run lock and then
goes turn after turn. Each turn calls these functions in this order:

- `turnopen` reads the pack, the machine hold and the control record, and starts the push when one is due. It also
  finds the code that a `serve` restarts on.
- `turnended` blocks each card of the loop that ended without a result or is stuck. When the control record says
  stop, it ends the loop's cards, except a card that has begun to land, to file its follow-ups or to file the slices
  of a split. A card that waits at its land step for a release run, or at any step for the CLI of its seat, is ended,
  unless it has filed slices.
- `turnside` starts the jobs that a `serve` runs beside the cards: the whole test on main, the idle mutation checks
  and the test-speed survey.
- `turncount` counts the cards that build against the cap, the cards that wait, and the cards in their review or
  Test step, and writes `loop.json`.
- `turnrestart` runs only when the loop's code is stale and a new script is known. It restarts the loop on the new
  code, and the new loop adopts the cards in flight. A new commit of the loop's checkout, or a commit taken while the
  project follows the plugin's releases or `main`, makes the code stale unless the loop can read which files the
  commit changes and none of them is engine code. Engine code is each file that the loop or its cards run or read from
  the engine: a file under `conveyor/` (the card rules in `conveyor/rules/` too), `shim.sh`, a guard hook in
  `.claude/hooks/`, `.claude/scripts/decision.sh` or a `.claude/scripts/dashboard_limit*.py` file. The files in
  `conveyor/tests/`, `conveyor/state/` and `.claude/hooks/__tests__/`, the `*.test.sh` files, the test pack's
  `conveyor/lib/test-*.md` files and `conveyor/README.md` are not engine code. After a commit that changes no engine code, the loop goes on picking with no restart and says
  so.
- `turnask` gets what the pick reads: the open issues, the urgent and main-red cards, and the blocked cards whose
  issue is closed.
- `turnpick` picks an issue and starts its card. The turn then ends, and the next turn starts.

A pick holds the card records' lock, and while it holds the lock, no card can write its records. A pick can hold the
lock for 120 seconds at most. A pick that runs longer is stopped with all the programs it started, and the lock is
free again. The turn counts the pick as failed, and the next turn picks again. The loop's log shows
`conveyor: pick ran out of time`. A snapshot that holds new issues has the same limit, and the log shows
`conveyor: the snapshot's adopt ran out of time`.

When the turn picks nothing, it waits (`turnwait`) until a card, the push or the machine hold's check ends, or until
the turn's timer ends. `conveyor.sh control hold`, `conveyor.sh control release` and the Foreman's filing hooks also
end the wait, so the next turn starts at once. A `run` ends at the first turn where none of its cards, pushes, machine hold checks or picks
is left (`runends`).

A card with no GitHub issue (a Tests page card or a Foreman card) can be stopped before the loop picks it. `conveyor.sh
control hold <card id>` holds it, so no turn picks it, and `conveyor.sh control release <card id>` lets the next turn
pick it. `conveyor.sh shut <card id>` takes it off the record, and it is never picked. It refuses a card that is a
part of a split issue, which that issue waits for: hold it instead. `control hold` and `control
release` take issue numbers and card ids in one list and act on each. If one argument does not fit (a card id that is
not waiting to be picked, or a word that is neither an issue number nor a card id), they name it and change nothing.
A card the loop has picked is stopped with `conveyor.sh shut <card id>` as before.

## The judge

The judge is set in each project's control record, by `conveyor.sh control judge ...` or in the Judge row of the
Board's Rules tab, never in the pack: a pack (`.conveyor/project.json`) that still holds a `judge` object fails its
check, with a line naming these commands. `conveyor.sh control judge on` switches it on and
`conveyor.sh control judge off` off, from the next review; it is on in a new project (docs/configuration.md, The control record). On, a judge reads each review
that holds findings before the card acts on it, and marks each finding accepted, declined or outside with a one-line
reason. It declines a finding only when its proof cannot happen with what the project really
runs, its claim is wrong, its defect is already fixed on main, or, at a level that `control judge rare` names (below), it is a rare case. A real defect in code that the card neither changed nor broke is never
declined for that: the judge marks it outside. It becomes an `OUTSIDE:` line of the review, with no fix round for
this card, and a review with no accepted finding is a GO. When the card lands, each outside finding is filed as a
follow-up of the card, with its level and the card's issue as its parent, as a finding of a last NO-GO is; a card
at the follow-up depth cap puts it on the self-heals list instead. The card's filed line names the follow-up of each
(`outside`), and the Board shows it under the review as "Filed as a follow-up" with that issue. A line the reviewer
itself starts with `OUTSIDE:` is a finding. From the second review on (counted as for the review limit), a NO-GO
whose findings are all new and all P2 or P3 ends the fix loop: each finding of the earlier reviews is fixed, and none
is P0 or P1 (a finding with no level is P1). The card lands, and each harm finding is filed as a follow-up in the same
way; a finding of another kind goes to its list. The review's line says `new-p2` as the reason that the loop ended. A
review with a new P0 or P1, or with a finding that comes back, does not end the loop this way: the other reasons
apply to it as before, and when none of them holds, it gets a fix round. A fix round also follows for a card at the
follow-up depth cap, as it files no follow-up. One scope rule holds at every level, P0 to P3: a finding is accepted
when it is inside the diff (any file and line it names is a changed line, or one of the two lines a removal sits between), or outside it because the card's change
causes it, such as a caller the change breaks; the judge's reason names the changed line. A finding is declined only when
its claim is wrong about the code, its proof cannot happen with what the project really runs, or its defect is already fixed
on main, and the reason says which, and why. "Rare case" is no reason to decline, except at a level that `control judge rare` names (below). A finding that a test does not check what its name, its comment or the issue's Done-when says it checks is a real defect at its level: "only a test gap" and "hypothetical" are no reason to decline it. The judge starts the reason of each decline with its kind: `claim wrong`, `cannot happen`, `fixed` (already fixed on main), `rare case` (where the setting allows it), `not this change` or `other`. A finding that repeats an earlier declined one is declined as a repeat only when the earlier decline's kind is `claim wrong`, `cannot happen` or `fixed`, or the defect is fixed on main. A repeat of a finding declined with another kind, or with no kind, is judged again as a new finding. A P3 finding (a real but minor defect, such as a
misleading name or message, a small inconsistency or dead code the change left) is not declined because it causes no
wrong result. A real outside finding is filed at any level, also when its proof needs an uncommon input or timing. An accepted P3 is handled by the control record's rule `P3` (the Rules
tab): on, it is a finding as a P2 is, so it goes to its list when the judge gives it a kind that is not `harm` (below)
and otherwise makes a NO-GO, goes to the fix round and, still open after the last
review, is filed as a follow-up of the pack's P3 priority (with no priority label when the pack has fewer than four:
an issue with none counts as P3). Off, it becomes a
`MINOR:` line of the review: listed and counted on the card's review line, with no fix round and no follow-up, and a
review left with no other finding is a GO. This holds with the judge off too, where every finding is accepted. A
line the reviewer itself starts with `MINOR:` is a finding. A declined finding causes no fix round and no
follow-up, and a review with no accepted finding is a GO. Each declined finding goes to the declined list, one line
in `declined.jsonl` of the state folder: its time, card, issue, the finding, who declined it (`judge`), why and the kind of the reason (`kind`, when the reason starts with one). A finding declined again on the same card
keeps its one line, which takes the later kind and reason. A line
the reviewer itself starts with `DECLINED:` is a finding, as any other line is. The review's record line holds each finding, the judge's
reason and, for an accepted one, its "Cost to every card" (when the judge's answer decides at least one finding, a finding accepted because the answer held no line for it that could be read, or two or more lines for it, has the reason "the judge gave no line for this finding that could be read" and no cost; when it decides no finding, the review stands as the reviewer wrote it and the record line holds no reason for any finding). `conveyor.sh control judge always security data` names
the finding kinds that are always accepted, whatever the judge says: the reviewer tags a finding of one with its
kind, in square brackets right after its level. Each kind is one word; the command names them all, and with no kind
it clears them.

`conveyor.sh control judge rare <level>...` names the levels (P0 to P3) at which the judge can also decline a finding
as a rare case: a finding whose proof needs an input, timing or setup that the project runs only rarely. The reason of
such a decline starts with "rare case". At each other level, "rare case" is no reason to decline.
`conveyor.sh control judge rare none` clears the levels. The default is none: the judge declines no finding as a rare
case. A word that is not a level is refused, and the setting does not change.

The judge also gives each finding that it accepts or marks outside a kind, from what its failure does, never from
how likely it is. `harm`: data is lost or written wrong, wrong code lands or pushes, a check passes that should fail,
or the belt or a card gets stuck and only a person can free it. `self-heals`: the failure heals itself (a longer wait,
a step run again, a slot over its cap for a short time), text that the next poll or turn corrects, or extra work or cost
with no wrong result. `cleanup`: the fix changes nothing that the code does. `already guarded`: another check, which
the reason names as `file:line`, already stops the bad result. `docs drift`: a guide or README leaves out, or
describes wrongly, what the code does correctly. A finding whose Proof says that it was seen in real logs or records
is `harm`, and so is a finding with no kind, and an `already guarded` finding whose `file:line` is not a line of the
code. The record line keeps the kind of each finding as `effect`. A `harm` finding is filed as a
follow-up as before, and the follow-up's body names its kind and the judge's reason in a `Kind:` line. A finding of
another kind outside the change, and on a follow-up card such a finding in the change, goes to the self-heals list
(`selfheals.jsonl` of the state folder), or to the docs list for `docs drift` (`docsdrift.jsonl`, whose entries never
expire): it becomes a `SELFHEALS:` line of the review, with no fix round and no
follow-up, and the review's record line holds it in `judge.selfheals`. On a card that is not a follow-up, a finding
in the change that is not `harm` never blocks a review: at any review whose accepted findings in the change are each
of another kind, the findings go to their lists in the same way and the review gives GO. When a `harm` finding, or
a finding with no kind, is beside them, the review gives NO-GO and the fix round fixes all of them, with none on a
list. A finding that cannot be written to its list has no kind. One still open after the last review goes to its
list, and at that review no finding blocks the card: a `harm` one (or one with no kind) is filed as a follow-up as
the card lands, at any level. A line that
the reviewer itself starts with `SELFHEALS:` is a finding. `conveyor.sh heals batch <area>` (the Board's "File a batch
card", `-` for the entries with no area) files one card that holds an area's open entries as its scope, and marks them
with that card. The Board's batch sheet names the entries it keeps, the card's title, its priority and whether it is
held or queued (`--held` or `--queue`, `--prio P2` or `P3`, `--title <text>`, then the entry ids): only those entries go in the card. `conveyor.sh heals docs <area>` (the Board's "File a docs sweep card") does the same with the docs
list, and `release-prep` runs it for each area with entries before the suite. An entry whose card has not landed or closed waits for a later batch card. A batch card shut before
it lands gives its entries back, and `retry` of it takes them again, or is refused when another batch card holds them.
`conveyor.sh heals harm <id>...` (the Board's "Move up to harm") files each entry as its own follow-up at once, and
`conveyor.sh heals drop <id>...` (the Board's "Drop now") takes entries off the list. Either way the entry goes to
the record of dropped entries with why it left, and each entry counts its sightings.
When the judge fails, the review stays as the reviewer wrote it, and its findings keep no kind from an earlier round. `conveyor.sh heals sort` sorts the queued follow-up cards and the open finding issues by the same rule
(docs/cards.md, Harm or self-heals). The loop (`run` or `serve`) runs it by itself and picks no card until
`healssort.jsonl` of the state folder logs a sort. That file logs each run with each item, its kind and the judge's
reason. A sort that cannot read the open issues logs nothing, so the loop tries again.
An entry of the self-heals list that no batch card holds, and that nobody saw again, leaves the list after the days of the Rules setting `healsdays`
(`conveyor.sh control rules healsdays=<1-3650>`). A finding is seen again when the judge rules the same finding, its Proof aside, of a later card (`harm` for its Proof's logs too), or the sort does: the entry is then of that card.
The entry moves to `healsdropped.jsonl` of the state folder with the date it left and the reason `expired`. A finding that the sort or a review sorts to the list again later takes its entry back from there. An entry with no date is dated at the loop's next check, so it stays for the age.
An entry that a shut batch card gave back counts its days from that day, and the docs list never expires. The loop checks the list at each turn.

`conveyor.sh control judge <cli> <model> [effort]` names the judge (a CLI installed on the host, the reviewer's too,
and any model, listed by that CLI or not: docs/configuration.md, Models); a judge set to the reviewer's CLI is used, of the same
family as the reviewer. `conveyor.sh control judge default` leaves it to the first model of another CLI than the
reviewer's that the pack's `models.allowed` lists for the review (Claude Code or OpenCode for a Codex reviewer, and
so on), at medium effort. The Board's Judge row offers every installed CLI, says "same family as the reviewer" when
the judge runs on the reviewer's CLI, and shows the model the judge runs on when it is left at default. When the judge cannot run, fails
or gives an answer that cannot be read, every finding is accepted: no card is blocked by the judge. An answer with some lines that cannot be read keeps the decisions of the lines that can: a finding with no such line, or named by two lines, is accepted. The judge's line then keeps the last 2,000 characters of the answer and the number of findings decided.
An issue can have its own judge, builder and reviewer (`conveyor.sh control card`: docs/configuration.md, Settings
for one card); its card uses them in place of the project's.

## Accounts

A project's cards can run on another Claude account than the host's default login. Each account is a Claude config
folder on the Conveyor host, signed in once by you: run `CLAUDE_CONFIG_DIR=<folder> claude` there and sign in in
the browser. Then list it in the host file (`~/.config/conveyor/host.json`), by a name of your choosing:

```json
"accounts": [{"name": "second", "configDir": "~/.claude-second"}]
```

A folder that is not absolute is under your home folder. A project that names no account runs on the default login,
`~/.claude`, even when the engine was started with `CLAUDE_CONFIG_DIR` set.

`conveyor.sh control account <name>` sets the account a project's cards use, and
`conveyor.sh control review-account <name>` the one its reviews use when the reviewer is Claude; either with no name
sets none (the default login; for reviews, the cards' account). The Board's Rules tab sets both. A change reaches the
cards started after it; a card in flight finishes on the account it started with, and one whose reviewer is changed to
Claude while it runs reviews on the account it builds on. Each card session runs with `CLAUDE_CONFIG_DIR` set to the account's folder,
the card's worktree line names the accounts by name (never by email), and the usage-limit guard reads every account the
next card will use (its build account and, with a Claude reviewer, its review account; the default login is read at
its own folder), so an account at its limit holds back only the projects that use it. An issue with its own builder or
reviewer (`conveyor.sh control card`) that runs on Claude has the accounts of those seats read too: when one is at its
limit, only that issue's card waits, and the next ready issue is picked. The Board shows that issue as skipped by the
rule `the weekly limit guard` until its accounts are below the limit. It does not read the account of
a role on an API route, which has no usage limit (see `roles` in [docs/configuration.md](../docs/configuration.md)). The Board's Health panel lists
every account it can read, on its own machine and on the host, each with its own usage and what it is used for.

## OpenCode builder

The builder seat (build, fix and rebase sessions) can run any model OpenCode exposes. Choose it with
`conveyor.sh control model opencode <provider>/<model>` (the provider and model as `opencode models` names them; one
it does not list is taken as typed, and fails in the card when OpenCode cannot run it) or in the Board's Builder row on the Rules tab; the pack's `models.allowed.opencode`,
as `opencode:<provider>/<model>`, can name one as the seat's default. OpenCode 1.x
must be on PATH (`npm install -g opencode-ai`) and signed in to the provider (`opencode auth login`). OpenCode is
given no effort: name the model alone. A step it runs names its model `opencode:<provider>/<model>`.

Each session runs `opencode run --model <provider>/<model> --format json --auto` in the card's worktree, under the
build timeout, with the same prompt (the brief and the card rules) on stdin as a Claude session. `--auto` approves
every permission nothing denies, as a Claude session's bypass mode does; OpenCode's run mode denies its question
tool itself. The project's own OpenCode config is not read (`OPENCODE_DISABLE_PROJECT_CONFIG`), as a Claude session
reads no project settings; the config file the engine writes for the card (`<worktree>.opencode.json`, named by
`OPENCODE_CONFIG`) loads the guard plugin.

OpenCode's events fill the same live record as Claude's: turns (each `step_finish`, one call of the model), the
action (the tool that ran last and what it names, or writing, or thinking), the last output, and usage: input, cache
writes and reads, output (reasoning counted in it) and cost, the dollars OpenCode reports. OpenCode reports no
1-hour cache writes (0) and no effort; once a step reports no cost, cost is left out and the Board leaves the step
unpriced. The Board prices an OpenCode step at the cost OpenCode reported, never at a list price, unless the pack
prices its model or names it as an alias of a known model (`prices`, docs/configuration.md). A stall is found
as for Claude, from the output lines and the worktree.

Claude accounts (`control account`) and the weekly limit apply to Claude sessions only: an OpenCode session runs on
no Claude account, and while the builder is OpenCode the usage-limit guard does not read the builder's account (with
a Codex reviewer it reads none, and Claude's limit holds no card back).

### Guards in an OpenCode session

Every command guard of a Claude card session applies to an OpenCode one. A Claude session runs the PreToolUse hooks of
the card's settings file (`<worktree>.settings`: `card-settings.json` and the pack's `hooks.json`); an OpenCode
session loads the guard plugin, `opencode/guard.mjs`, which before each tool call (OpenCode's `tool.execute.before`)
gives the call, in the shape Claude Code gives a hook, to `opencode/guard.sh`, and that runs the same hooks of the
same file and refuses the call as Claude Code does, with the hook's message:

| Guard | Claude session | OpenCode session |
| --- | --- | --- |
| Bash hooks: `git-safety.sh`, `bash-guardrails.sh` (the 4 GB heap cap on test runs, no search over an unbounded path, no shell write into a code file and the rest), `adversarial-review-gate.sh`, `dependency-addition-guard.sh`, and the pack's Bash hooks (its privacy egress guard among them, when it has one) | PreToolUse hooks, matcher `Bash` | the plugin runs them on each `bash` call; a call a hook rewrites (an unbounded search run over the checkout instead) runs as rewritten |
| Edit and write hooks: `dependency-addition-guard.sh`, `ruling-cite-gate.sh`, the pack's `Edit\|Write\|MultiEdit` hooks | PreToolUse hooks | the plugin runs them on each `edit`, `multiedit` and `write` call, given as Claude's Edit, MultiEdit and Write, and on each file of an `apply_patch` call (the file tool OpenCode gives GPT models in place of `edit` and `write`): an added file as a Write of its contents, each chunk of an updated one as an Edit, a moved or deleted one as a Write to its path; one file refused refuses the patch |
| Denied reads (`permissions.deny`, `Read(**/package-lock.json)`) | permission rule | `guard.sh` refuses a call of that tool on a matching path |
| `worker-ask-guard.sh`: a card session asks nobody | PreToolUse hook on AskUserQuestion | `opencode run` denies its question tool, and the plugin refuses it |
| No subagent (`--disallowedTools Agent`) | flag | the plugin refuses `task` |
| No MCP server (`--strict-mcp-config`) | flag | the plugin refuses every tool it does not map to a Claude tool, each MCP tool among them |

An `apply_patch` call that does not read as a patch (no `*** Begin Patch` ... `*** End Patch`) or names no file is
refused, as are `patch` and `batch`. A hook marked `onFailure: block` that
crashes or runs past its timeout refuses the call, as for Claude; guards that cannot run at all (no settings file, a
runner that fails) refuse every call. No guard of a Claude session goes unenforced in an OpenCode one, so the card's
report names none. The seat refuses to start, and the card blocks saying why, when OpenCode is not 1.x (the plugin
API the guard plugin is written for), the guard plugin or `guard.sh` is missing, or the card's settings file is.
Plugins the host's user installed for OpenCode (`~/.config/opencode`) still load, after the guard plugin; one that
rewrites a call after the guards' turn is not seen by them.

## Codex builder

The builder seat (build, fix and rebase sessions) can run on Codex, as the reviewer and the judge already can. Choose
it with `conveyor.sh control model codex <model> [effort]` (a model Codex lists, from its models cache or `codex debug models`, or any name typed in, which fails in the card when Codex cannot run it; a family name, such
as `sol`, runs the newest of it, as for a review) or in the Board's Builder row on the Rules tab; the pack's
`models.allowed["codex-builder"]` can name one as the seat's default. It takes Codex's efforts. The Codex CLI must be on PATH and
signed in, its `exec` must have `--dangerously-bypass-hook-trust` (Codex 0.167 has it), and `node` must be on PATH for
the guard hook.

Each session runs `codex exec --json` in the card's worktree (`-C`), under the build timeout, on the model and effort
in force, with the same prompt (the brief and the card rules) on stdin as a Claude session. Its sandbox is
`workspace-write`, so it can write in the worktree, `/tmp` and `$TMPDIR` (where the brief's background runs keep
their output and status files, and a test run its scratch folder), and, given with `--add-dir`, the machine's test
slots folder (the host file's `testSlotsDir`, else `/tmp/conveyor-test-slots`), in which a test run takes a slot, and
the card's briefs folder (`CONVEYOR_BRIEFS`, where long command output is kept). A command that writes anywhere else
fails. Codex reads the user's own `~/.codex` config, as a Codex review does (its
provider and sign-in are there). Codex's web search is turned off (`web_search="disabled"`): it is a tool Codex runs
on its side, which no hook is given.

Codex's events fill the same live record as Claude's: turns (each item it completed: a message, a command, a file
change; not the notices Codex gives as error items), the action (the item it started last, a command with its text),
the last output, and usage: the running total from the session file Codex keeps under its home while the turn runs,
then the turn's own usage once it completes, as input, cache reads and output (reasoning counted in it). Codex reports
no cache writes, so write and write1h are 0. The step's line holds its tokens under `codex` and the same split, and
the Board prices it at the model's list price, as a Codex review. A session stopped or timed out before its turn
completed is read from that session file's running total. Codex's session file is removed once read, as a review's is.

Claude accounts (`control account`) and the weekly limit apply to Claude sessions only: a Codex session runs on no
Claude account, and while the builder is Codex the usage-limit guard does not read the builder's account.

### Guards in a Codex session

Every command guard of a Claude card session applies to a Codex one. The session is given one PreToolUse hook on
every tool (`-c hooks.PreToolUse=...`, hooks on with `--enable hooks`, run without Codex's trust prompt, which a
headless session cannot answer, by `--dangerously-bypass-hook-trust`): `codex/guard.mjs`, which gives each call, in the
shape Claude Code gives a hook, to `opencode/guard.sh`, and that runs the hooks of the card's settings file
(`<worktree>.settings`: `card-settings.json` and the pack's `hooks.json`), the same file and the same scripts a Claude
session runs. A refusal is exit 2 with the hook's message, which Codex gives the model; a rewrite is Codex's
`updatedInput`.

| Guard | Claude session | Codex session |
| --- | --- | --- |
| Bash hooks: `git-safety.sh`, `bash-guardrails.sh` (the 4 GB heap cap on test runs, no search over an unbounded path, no shell write into a code file and the rest), `adversarial-review-gate.sh`, `dependency-addition-guard.sh`, and the pack's Bash hooks | PreToolUse hooks, matcher `Bash` | the hook runs them on each command (Codex names its shell tool `Bash`); a command a hook rewrites runs as rewritten. Commands run without a terminal (`--disable unified_exec_tty`), so their input is closed: Codex's `write_stdin`, which types into a command already running and is given no PreToolUse hook, can then only wait for more output, and keys sent with it are refused by Codex ("stdin is closed for this session"), so no command typed into a running shell gets past the guards. A Codex that does not know the feature fails to start rather than run with it on |
| Edit and write hooks: `dependency-addition-guard.sh`, `ruling-cite-gate.sh`, the pack's `Edit\|Write\|MultiEdit` hooks | PreToolUse hooks | the hook runs them on each file of an `apply_patch` call (Codex's file tool), read as for OpenCode (`opencode/screen.mjs`): an added file as a Write of its contents, each chunk of an updated one as an Edit, a moved or deleted one as a Write to its path; one file refused refuses the patch, and a patch that does not read as one is refused |
| Denied reads (`permissions.deny`, `Read(**/package-lock.json)`) | permission rule | `guard.sh` refuses a call of that tool on a matching path; Codex has no Read tool (it reads with commands, which a Claude session's Bash may do too) |
| `worker-ask-guard.sh`: a card session asks nobody | PreToolUse hook on AskUserQuestion | `codex exec` does not run `request_user_input`, and the hook refuses it |
| No subagent (`--disallowedTools Agent`) | flag | the hook refuses `spawn_agent` and every other agent tool |
| No MCP server (`--strict-mcp-config`) | flag | the hook refuses every tool it does not map to a Claude tool, each MCP tool among them |
| No web search beyond what the hooks see | (Claude's WebSearch goes through the hooks) | Codex's web search is off: Codex runs it on its side and gives it no hook |

The hook maps `Bash`, `apply_patch`, `update_plan` (as TodoWrite) and `view_image` (as Read); any other
tool is refused. Guards that cannot run (no settings file, the runner failing) refuse every call. No guard of a
Claude session goes unenforced in a Codex one, so the card's report names none. The seat refuses to start, and the
card blocks saying why, when Codex is not on PATH, its `exec` has no `--dangerously-bypass-hook-trust` (an older Codex,
whose hooks would wait on a trust prompt and never run), `node` is not on PATH, the guard hook, `opencode/screen.mjs`
or `opencode/guard.sh` is missing, or the card's settings file is. Hooks the host's user set for Codex
(`~/.codex/hooks.json`) still run beside the guard hook.

## Research lane

`conveyor.sh lane research create`, run in the project's checkout, makes the research lane: a worktree at the host
file's `lanes.research.worktree` (default: `<main checkout>-research`), whose `.claude/settings.local.json` sets the
model and effort of the pack's `lanes.research`, the 1-hour prompt cache, the lane's shell and the lane's hooks. Run
again, it rewrites the settings and keeps the worktree. Start the lane with `claude` in that worktree.

Each `lane ... create` (`lane fast create` too) writes the lane's folder into the host file, in the record of the
project's checkout: `records[].lanes.research.worktree` or `records[].lanes.fast.worktree`. The Board reads each
project's lanes from there, on the machine it runs on. The record is the one whose `main` is the checkout; with no
such record nothing is written and the command says which entry to add by hand. A host file that cannot be written
fails the command.

The lane is read-only by its shell, `lanes/research-bash`, which Claude Code runs for every Bash call: an
operating-system sandbox (bubblewrap on Linux, `sandbox-exec` on macOS) in which only `reports/`, the lane's folder and
the temp folder can be written, whatever the command; it runs nothing while one of those folders holds the worktree
(a TMPDIR above it) or git tracks a file in `reports/`. Where the sandbox cannot run, `create` makes nothing and says
why. `create` also makes each file git tracks in the worktree, and each folder holding one, read-only on disk, so the
edit tools cannot write them either (as root, which that does not stop, it makes nothing). Beside it, a commit, a push,
another git command that changes tracked files and an interpreter's inline code are refused, and the edit tools write only
where the shell can; the worktree is never the main checkout. Reports go to the untracked
`reports/<date>/`, each with a line in `reports/INDEX.md`. The shell has no network (its own network namespace on
Linux, no outbound connection on macOS), so curl and gh cannot reach GitHub from it; the lane files work with its
filing command, `lanes/research-file <title> < <body>`, whose filer the shell runs outside the sandbox. An issue filed
that way starts held, as the Foreman's do, and is built only once the owner releases it. The lane sends a message to
the project's Foreman with `lanes/research-file --tell <message>`, through the same filer ([Lanes](../docs/lanes.md)).

## Test slots

Every test run on the machine takes its workers from one pool of test slots, so test runs never share a core with
each other, whatever number of cards and projects test at once: a card's test run holds a slot until its command and
all the command started have ended, and a test runner holds one more for each worker it runs beside the first.
The host file's `testSlots` is the size of the pool (the default, and the most, is the machine's cores); the pool is the folder
`/tmp/conveyor-test-slots`, the same for every Conveyor on the machine (`testSlotsDir` names another, for a test of
the slots themselves). A slot is a core: on Linux a test command is pinned to its slot's core, so the workers it
starts without a slot of their own share that one core, and one that cannot be pinned does not start. A project's runner that wants more cores sources the file
`CONVEYOR_TEST_SLOTS` names and, for each worker, calls `slot_pool` once, then `slot_take` before the worker,
`slot_mine` in it and `slot_free` after starting it. When Conveyor runs a card's failing tests on main next to the
controls, it sets `CONVEYOR_TEST_ONESLOT`: `slot_take` then gives each worker the run's own slot, one at a time, so
the controls and the failing tests use the same core. A test run that a card's build, fix or rebase session starts
holds at most the pack's `tunables.sessionTestSlots` slots at once (default 2), so one session cannot fill the
machine while other cards build. The loop's own test step, the check on main and a release run keep their share.

A card with no slot waits before its tests start, and the Board says "waiting for a test slot (n of N in use)". The
wait does not count against its test timeout. Builds and reviews take no slot.

Pushes go first. The push step (a landed card's push, and Push landed's) runs `git push`, and so the project's
pre-push hook, holding a test slot, on the slot's core, as a test unit runs. A push still waits while every slot is held, but it takes the next free slot before any test unit that
waits (`slot_first`): a unit that takes a slot while a push waits gives it back. The push's time limit starts when it
has its slot.

## Why the machine is busy

When the machine is slow, these commands show which card, if any, is the cause. They read the processes of the
machine, and the card worktrees and card records of every project in the host file.

- `conveyor.sh why <pid | name>` names the process, or each process of that program, and its parents. It then names
  the card, step and project that the process belongs to, or says that no card owns it. A process belongs to a card
  when it, or a process above it, works in the card's worktree or in a test worktree of the card. A card's process
  is in the step that the card is in. A process of a closed card (landed, closed, blocked, or its loop has stopped) is left over, and
  `why` gives the command that stops what the card left.
- `conveyor.sh work` lists the processes that used 5% of one core or more over one second. The processes of each
  card and step come first, as a group, the heaviest group first. Then come the busy processes that no card owns. A
  group of a closed card says "closed: left over" and gives the command that stops all of the card's processes.
  The Board's Health panel shows the same list under **Work now** (docs/board.md).

Both take `--json`.

## The test step

The engine runs the test step from `lib/testrun.sh`. These files hold its parts:

- `lib/testlist.sh`: the times a run records, the test results cache, and what the next run need not run again.
- `lib/mainred.sh`: the run on main of the tests that did not pass, the machine hold, and the fix cards of a red main.
- `lib/bugproof.sh`: the bug-card check.
- `lib/speedproof.sh`: the checks of the fix cards that the Tests page files.
- `lib/donewhen.sh`: the project's checks, the commit trailers, the Done-when check and the review findings.
- `lib/failat.sh`: where a test failed, read from the stack traces in its output.
- `lib/loadfactor.sh`: the load factor that a run's time limits grow by.
- `lib/fileeach.sh`: the run of a card's test files, each alone, side by side on the test slots.

Each run of a card's changed tests writes one `test` line to the card records, `pass` or `fail`, holding:

- `sec`: all the step took, and apart from it `wait`, the seconds it waited for a test slot, and `run`, the seconds
  its command ran (null when not known: a batch run another card made).
- `slotsFree`: the test slots of the pool free beside its own when its command started.
- `selected`: `{files, filesOf, cases, casesOf, kept}`, how many test files and cases the runner selected, out of how
  many, and how many cases that passed in the last run it kept as passed and did not run. A runner says so in its log
  (`CONVEYOR_TEST_LOG`) with the lines `TESTRUN files=<n> of=<m>`, `TESTRUN cases=<n> of=<m>` and
  `TESTRUN kept=<n>`; a count no line gives is null.
- `ended`: `passed`, `failed` (a case failed), `killed` (by a signal), `timed out`, or `nothing selected` (it passed
  having selected no test file).
- `why`: why each file ran, `{"<file>": [reasons]}`, on a first run and a run again alike, when the runner says (below).
- `wholeSuite`: `true` when the runner ran every engine case file (its log line `TESTRUN whole-suite`), so a reader
  does not count files; absent otherwise.
- `ran`: the test files the run began, from its log lines `== <file>`; absent when it names none. `why` can name a
  file that did not run, such as one the test cache kept off.
- `ranCases`: the cases the runner selected of each file it ran only part of, `{"<file>": [cases]}`, from its log
  lines `TESTRUN case<TAB><file><TAB><case>`; absent when it gives none. The search for the landing that broke a case
  on main counts a card that ran the case so.
- `refused`: `refused full run: <the reason seen>`, when the step refused to run the whole selection (below, When a
  full test run is allowed).
- `tests`: the counts a host's runner prints; a failed run also has `failures`, `reason` and `tail`.
- `timed`: each test file the card's change adds or modifies that its own run timed, `{file, sec, cpu}`: its clock
  seconds and its CPU seconds (null when its runner gave none).
- `times`: the CPU seconds of every test file the card's own run timed, `{"<file>": <CPU seconds>}`: what the test
  rules and the Tests page read (below).

A card whose tests already passed on what it holds, while it waited to land, is not run again: its `test` line is a
`pass` with `reused: true` and no run. No passing output is kept. The Board's card shows the Test step's time as
its wait and its run.

A card's test step runs each test file of its list alone through the pack's `test.fileCommand`, in its worktree. A run that ends with cases that did not pass (they
failed, or never finished because the run was killed or timed out) runs once more, straight away and on the same test
slot, for those cases alone: the cases that passed are not run again. After a run that stopped at its first
failure (`failfast`, above), it runs each failed file, and repeats the cases of that file that passed when the test
command cannot leave them out. Only when a case still does not pass does the
card go to its fix session; a card whose re-run passes goes on with no fix session. A fix session that leaves the
card's staged change as it was is followed by a run of only the cases that had not passed, not the whole selection.
A fix session (or any session) that changes the change is followed by a run of the cases that had not passed in the
last run (failed, killed or timed out) and the tests the command selects for the files the session changed: the files
whose content differs between the staged change last tested and the staged change now (the two trees are compared,
not the two patches, so a whitespace edit counts). Every other case that passed in the last run is not run again and
counts as passed. Each run has the same time limit.

A run after the card's change moved onto a newer main (merged there, or rebuilt there by a session, or a retried
card's kept change applied to a main that moved since its last run) keeps the passes of the last run too. It runs
again only:

- what had not passed in the last run (failed, killed or timed out);
- the tests of the files of the card's change whose content differs between the tree last tested and the tree now;
- the tests the command selects for the files main changed between the commit last tested on and the one now, where
  the command's selection for the card's change holds them too.

It runs the whole selection again when the merge is in doubt: the merge left a file that does not parse (the parse
check's fix session), the session that brought the change onto main edited it outside the conflicts, or a file of the
card's change that main did not change differs (the session that rebuilt or ported the change edited it beyond what
main changed). A run that passed
keeps what it passed for that, and a blocked card's list is kept with its patch: a retried card whose kept change
applies to the same main commit it was last tested on runs only what had not passed. Every test step's line, a first
run's as well as a run again's, says why each file ran in `why`, `{"<file>": [reasons]}`, each reason `main changed
<file>`, `the card changed <file>` or `did not pass`; from the command's log lines
`TESTRUN why<TAB><file><TAB><reason>`.

A test step whose run gives no result proves nothing. This is a run that a signal stopped (for example, the service
stopped or restarted), a run whose time ran out with no test file running, or a run that wrote logs in
`CONVEYOR_TEST_LOG` that name no test (no `TESTRUN`, `== ` or `-- ` line). It is also a failed run that logged no
test file and whose output names no failing case, so its only failure is the test command itself. It is also a failed
run that logged the line `TESTRUN host<TAB><file><TAB><why>`, where each file that the logs give as `-- FAIL` or
`-- timeout` has such a line: the runner did not start that file because of a problem of the host, such as no room in
the temp space, so no test failed. The reason is the first such why. When another file of the run failed, the run
has a result, but a file with such a line is not a failed file, so it does not run on main. A card's run that
passes is also a run with no result when its list names cases of a file, the file's runner writes case records (see
below), and no record is of that file: the filter ran no case. Nothing of a run with no result goes to main, to
`mainred.json`, to a wait for main or to a fix session. The step's `test` line has the reason `no result: <why>`, and
the test step runs again. This is also true for a card that a restarted loop adopted. After the third such run in a
row, the card is blocked with the reason "the changed tests gave no result 3 times in a row". A run that gives a
result starts the count again. Any other failed run is a run with a result. This is also true when a file's filter
ran no case. That file is not kept as passed, and its cases run again. The run's other failures go on to main and the
fix session as usual.

Before a failure goes to the fix session, what still did not pass after the run again runs on main (a fix session cannot repair main or the
machine): in a worktree of main's commit as it is now, on a test
slot, each failing file alone through the pack's `test.fileCommand`, its `CONVEYOR_TEST_RERUN` list naming every
other file of the card's runs as passed. Each
failure gets a verdict:

- **main**: the same case failed on main too (a timeout or a kill there says nothing of the case), an input of its
  file changed since its last recorded pass, and a control passed beside it, no control could run, or main changed
  its file, or a file the test map links to it, after the last landing whose tests ran that case (see
  **machine**). The test command
  itself is never a case and gets no verdict: it names no test. Conveyor files no
  GitHub issue: the case goes to the fix card of main's commit, a card of issue 0 that the
  loop picks ahead of the queue, one per broken main commit. The loop picks it whatever the priority switches say
  (`control rules P0=off` to `P3=off` included), by design: held, every card that meets the red main would wait for
  good. Its brief names main's commit, each case and the last
  commit that changed the case's file (the test file at main's commit that defines the case, `t_<case>()`,
  `<case>()` or the name quoted, when the failure names a runner such as the engine's `conveyor/conveyor.test.sh`),
  and asks for the cases to pass on main; it is labelled as a P0 bug and builds, is reviewed, tested, landed and
  pushed like any card. Its proof is the cases, not a new test. After its build, each case the card holds runs alone
  on a test slot, as the test step runs it, on main's code at the commit the card was built on: first without the
  change, then with it. Each case must fail without the change and pass with it. The card need not add a test, and
  the check does not run a test that it adds (its test step does). When a case still fails with the change, the
  card is blocked with "<case> still fails with the change", with no review. When every case passes without the
  change, main is no longer red for them: the card closes as already done, with no review, and its change does not
  land. Its `closed` line names the cases. When some cases pass without the change and others fail, or a run gives
  no result for a case, the card is blocked, and the reason names the case. The output of each run is kept with the
  card's kept work, as `<card>.redrun-without.out` and `<card>.redrun-with.out`. When a run gives no result, or its
  worktree cannot be made (then the file is `<card>.redrun-setup.out`), the reason names that file and quotes its
  last 40 lines. When its build session makes no change,
  its cases run again on main as it is now. When they all pass, the card closes as not needed, and its `closed`
  line says so; main is no longer red. When they do not all pass (a case fails, or a run gives no result) and newer
  main-red fix cards hold each of its cases, it closes, and its `closed` line names those cards and gives the result
  on main. A newer card on the belt counts for each case it holds. A newer card that landed counts only for a case
  that passes in each of its runs on main, and only while main is still the commit of those runs. A card that keeps
  a reviewed change from a rebuild after a landing conflict does not close this way. Otherwise it is blocked, and the reason gives the result on main. An
  `ALREADY-DONE` line in the session's reply does not change this.
  The Board shows it titled "Main is red: <cases>"; its commit names the cases and main's
  commit. In place of an issue number, the Board, `foreman status` and the Foreman's wakes name it
  "Main is red (<commit>)". A case found failing on the same commit, while its card runs too, is added to that card (its title on the
  Board, and the reviews and fix sessions after it, name the case); a case an open fix card of an earlier commit
  holds starts nothing more. `retry <card id>` gives the card back when it blocks (built again from nothing), and
  `shut <card id>` shuts it; the Board's Retry and Close in Needs you send its card id. `mainred.json` in the state folder keeps the commits,
  their cases and their cards. The brief also names the landing that broke a case, when it is known: the first
  landing on main after the last one whose card's test step ran the case's file (within the last 500 commits). The
  case's entry keeps a link from each file that landing changed to the case's test file, and the fix card stages
  those links in `.conveyor/test-links.json` (`{"<changed file>": ["<test file>", ...]}`), so they land with its fix.
  From then on, a card that changes a linked file runs its linked test files too (a whole-only file in its card
  mode), and its log says so (`TESTRUN linked<TAB><test file><TAB><changed file>`); a link to a test file that no
  longer exists is dropped. A key `main:<file>` in the same file names test files that a card's run again adds to its
  list when main changed `<file>` since the card last ran. When every failure is main's, the card neither goes to fix nor blocks: it gives way and waits in its
  Test step, its live record saying so, until main is at another commit; then it is fitted onto main as it is now
  and its test step runs again (the same change keeps its passes, so the cases that failed run again). A card that
  reaches its Test step while the main-red record holds main's commit, with its fix card not landed or closed, starts
  no test run, its own or a batch's: it waits in the same way, with the same live record, until main is at a commit
  the record holds no such entry for. It is then fitted onto main as it is now, and its tests start. A pass it holds
  for its change is kept, and so is its place in a batch. A card that waits at a file claim for another card runs no
  test of its own while its worktree is on a commit that the record holds an entry for, even when main has moved past
  that commit: it is fitted onto main first. A card with no GitHub issue (a branch's, a Tests page card) waits as any
  card does. A card that has given way as many times as it may also gives up its files for this wait, and for a wait
  after a failed run whose failures all fail on main too, so it cannot hold up the fix card. Only a card that a loop with no limit on its picks started (`conveyor.sh serve`, or
  `conveyor.sh run` with no number) waits. A card of `conveyor.sh land-branch` (it may land the repair itself), and a
  card of a run limited with a number or with `--only` (it may start no fix card), start their tests. Its other steps
  (build, review, fix, lint) do not wait, and a main-red fix card (a card that an entry of the record names) runs its
  tests at once. Those cards
  count against the cap while they wait (Control, above), so the
  loop starts a main-red fix card even with the project's cap reached: it takes one slot beyond the cap, one such card at a time, and the slot ends with it. The machine's cap
  and pause apply as to any card. The Board shows that card as "beyond the cap: main is red".
- **machine**: the same case failed on main too, but the machine is at fault, not main. This is so when the case's
  file passed before with the same inputs (the test results cache holds a pass of it with main's content), or when
  every control failed beside it and main did not change its file, or a file the test map links to it, after the
  last landing whose tests ran that case. The controls are the test files of the pack's `test.control` that have a recorded
  pass with main's content, and are not among the failing files. When the cache holds no pass with main's content
  at all, as with a runner that logs no `TESTRUN inputs` lines, the controls are all those files that are not among
  the failing files. They run in the same run on main as the failing cases, so on the same slot. With no control to
  run, nothing tells the machine from main: a case whose inputs changed is main's. A
  machine verdict opens no main-red entry, no fix card and no wait for main, and the card does not go to its fix
  session. Its test line has the result `held`, not `fail`: the Board shows the step as "tests held: the machine", not
  as failed. `machinehold.json` in the state folder holds the hold: when it began, the card and commit that found it,
  the files that must pass again (the controls that failed, and the failing files that passed before with the same
  inputs) and the cases. While it stands, the loop picks no card
  and says why once: "the machine fails <files> on main, with no change to main that explains it", with the
  failing cases. At
  most once every `tunables.poll` seconds the loop runs those files on main as it is now, on a test slot. When they
  all pass, the hold goes and the loop picks again. A card with a machine verdict and no card verdict gives way and
  waits in its Test step, its live record saying "waiting for the machine". When the hold
  goes, it is fitted onto main as it is now and its test step runs again. `health` shows the hold as `machineHold`,
  and the Foreman gets one wake for each hold that names the failing files.
  The repair lane lets a change that repairs the test step itself land while the hold stands. The lane opens for a
  card with a machine verdict and no card verdict, before it waits, and for one card at a time. The files of the
  hold run on main's code at the card's commit, first without the card's change and then with it: they must fail
  without the change and pass with it. Then the card's changed tests run with its change, and they must pass. Each
  of these runs is clean: it runs in a session of its own, with a small set of environment variables and no open
  file descriptor above 2, and `CONVEYOR_TEST_SLOTS` names the card's own `conveyor/lib/slots.sh` when the card has
  one. A card that passes lands, and its test line starts "repair lane:". Its review is the same as for any card. A
  card that does not pass gives up the lane and waits for the machine. A card that finds the lane in use waits, its
  live record saying "waiting for the repair lane", until the process of the card in the lane ends. Then its test
  step runs again.
- **card**: it passed on main, or main's run did not run it (its worktree could not be made, or the command did not
  select it). A failure in a test file that the card's change adds is always the card's: main does not have that
  file, so it does not run on main. A test file that the change edits runs on main in main's version. The card goes
  to its fix session.
- **flaky**: it failed on the first run and passed on the run again (Flaky tests, below).

When main has moved since the card's commit, a card with a failure that is not main's does not go to its fix session
yet. The card is brought onto current main first, as a card whose main moved during its tests is (its change fitted
there, or brought there by a session when it no longer applies), and the failed cases run again there: main may have
fixed them since the card was built. A pass there lands with no fix session. Only a failure on current main goes to
the fix session. This happens once before each fix session, so a card whose own change fails does not follow a busy
main for ever. When main has not moved, the card goes to its fix session. A card that waited for a red main
to change is brought onto current main in the same way before its test runs again.

The test line keeps them: `verdicts` (`[{case, verdict}]`) and, when the cases ran on main, `mainRun` (`{sha, sec,
exit}`: main's commit, the seconds that run took, its slot wait included, and its exit). A pass on re-run's line has a
flaky verdict for each case that had not passed. The Board's Metrics (All numbers, "Test failures") count the card,
main and flaky verdicts, with the seconds spent running them on main.

The card's test line records both runs: `rerun` holds the first run's exit and failing files and cases, and a pass on
re-run has the reason `passed on re-run: <file>: <case>, ...`. The Board draws such a card's Test step as "Test passed
on re-run", never as a plain pass, and a later `reused` line keeps it so.

What passed and what failed is told to the command in the file `CONVEYOR_TEST_RERUN` names (empty on a first run, but
for the `ok` and `off` lines for each case kept off as flaky: Flaky tests, below):
a line `change<TAB><id>` (the staged change it holds for), `base<TAB><commit>` and `tree<TAB><tree>` (what the next
run compares), then `pass<TAB><file>` for each file whose log says it
ended ok (`-- ok <file>`, below), `ok<TAB><file><TAB><case>` for each case of a file that did not end ok whose output
line `ok <case>` says it passed (a file killed part-way), and `fail<TAB><file><TAB><case>` for each case that failed.
A command that reads it runs no file it lists as passed; of a file it names passed cases of, the rest of its cases;
of a file it names only failed cases of, only those cases; a file it does not name (one that failed naming no case, never finished or never
began) runs whole. A file that passed, but that main changed what it tests since then, keeps its `pass` line when the
pack sets `test.changed`: the `main<TAB><file>` lines (below) make the command run the tests that both changes select. When the
pack does not set `test.changed`, the file has a `fail<TAB><file>` line and a `shared<TAB><file>` line: it runs whole,
and the log can say it passed before. After a session changed the staged change, the file also has a line `changed<TAB><file>` for each
file the session changed: the command runs the tests it selects for those files too, whether or not they passed, and
says in its log how many cases of its selection it kept as passed and did not run (`TESTRUN kept=<n>`; the test line's
`selected.kept`). When the pack sets `test.changed` and the list has a `changed` or `main` line, the step first runs
`test.command` once with `CONVEYOR_TEST_LIST` (the file it writes the selected test files to, one a line),
`CONVEYOR_TEST_RERUN`, `CONVEYOR_TEST_FILELIST` and `CONVEYOR_TEST_CASES` (the cases the card named of each file, as
a start of a file gets them) and `CONVEYOR_TEST_LOG`. A pack's script that gets `CONVEYOR_TEST_LIST` runs no test and no
check, and logs the cases it keeps of the files it leaves out as `TESTRUN kept=<n>`. The step does not start a file
that the list keeps something of (a `pass`, `ok` or `off` line) and that this selection names no case of. Of a file that ran again in that run, a case that failed is no longer listed as passed, and the
cases it did not run stay listed as they were: a file listed as passed keeps its `pass` line beside its new `fail`
lines, and of such a file the command runs those failed cases alone. A file that failed naming no case or never
finished in that run (its time ran out) loses only what it had of the cases the run selected of it, when the command's
log names them (`TESTRUN case<TAB><file><TAB><case>`, one line a case, for a file it runs only some cases of): their
`ok` lines go, and a `pass` line stays beside a `fail` line for each of them that did not print `ok`; its other cases
stay kept. A file whose log names none of its cases (one run whole) keeps nothing it had. After the change moved onto
a newer main, the file has a line `main<TAB><file>` for each file main changed since the commit in its `base` line: the
command runs the tests it selects for those files that its selection for the card's change holds too. A command that
ignores the file runs its whole selection again; one that reads `pass` lines but not `main` lines keeps passes main
may have broken. Files and cases are read from the logs the command writes to the folder `CONVEYOR_TEST_LOG` names:
`== <file>` as a file begins, `-- ok|FAIL <file>` as it ends. A runner can also write a record of each case it runs:
one JSON line `{"file": "<file>", "case": "<case>", "result": "ok"|"fail", "sec": <seconds>}`, in a file of its own
in the folder `results` of that folder, and a line `{"file": "<file>"}` there as it starts. For a file with records,
Conveyor reads which cases failed and passed from the records, not from the output. For a file with none, it reads
the output. The engine's own runner writes these records. When a pack sets no `test.fileCommand` and a Node file's
filter runs no case, Conveyor's own runner writes the line `{"file": "<file>"}` and no case record for that file.

### The list of tests a card's run is given

A card never runs the suite command (`test.command`, `test.full`) to run tests; the one run of `test.command` that only
lists the files to start is described above, with the test command. Each run of a card's tests runs each test file
of its list alone, one process a file, through `test.fileCommand`: the card's test step, the run again after a
failure, the bug-card check, the run on main, the main-red check, the checks of Fix hollow cases, Fix the waiting,
Make it run alone and the speed-up cards, the mutation check and `testaction run`. Each process has the file's own
time limit, its `# timeout: <seconds>` line, if it has one. When the file runs past it, Conveyor stops the file
and every process it started, and the file fails. A file with no such line has no limit of its own: the `testTimeout`
setting limits the whole run, shared by all its files. The `# timeout:` limit is multiplied by the run's load factor, the
1-minute load average per core, never less than 1 and never more than 3, rounded up to whole seconds. Each run gets
the factor in `CONVEYOR_LOAD_FACTOR`, and the line that says a file timed out gives the factor when it is over 1
([configuration.md](../docs/configuration.md#the-load-factor)). With no `test.fileCommand`, Conveyor runs each file with the runner
of its language, from the folder of its package (`conveyor/lib/filerun.sh`: Node, pytest, Go, Cargo, RSpec, Gradle,
Maven, dotnet, swift, PHPUnit, mix, CTest and Dart or Flutter). When
it has no runner for a file to run, the card stops at its test step under Needs you, and the reason names
`test.fileCommand` and the file. A bug card with a test file and a fix stops earlier,
at Build: its bug-card check cannot run, and the card is blocked with that reason (Bug cards: the new tests fail
without the fix). A bug card whose change is only test files, or only comments in other `.js`, `.mjs`, `.cjs`, `.ts`,
`.mts` or `.cts` files with or without test files, has no check to run, and with a test file it stops at its test
step. A comment change in any other file, such as a `.sh` or `.py` file, is a fix, and that card stops at Build. A card with no test file to run passes its
test step. [Which tests a card
runs](../docs/configuration.md#which-tests-a-card-runs) says which files are on the list.
The list is the test files the card's change adds or changes (`"by": "own"`; a shared helper is none). Conveyor also
adds a test file that had a failed case in the card's last run, though the change does not change it. It does this
only when the file is still there and the card's change links it (the test map, the links or its name)
(`conveyor/lib/testlist.sh` `failsleft()`). Thus a fix that changes only another test file still runs the failed case
again. The list's `files` count includes the added file. When cards landed on main change a test file that the
card's change also uses, Conveyor runs that file again. It adds the file to the list, runs it whole and runs it in
addition to the limit of linked files. This applies to a card's own run and to its batch's run. Of a test file
main has, it runs only the cases (`t_<case>() {` to its `}` line, with the comment lines above it) that hold a line
the change adds or changes; a file whose change touches a line outside every case (a helper or setup), a new file,
and a file with no such case run whole. The command gets those cases in `CONVEYOR_TEST_CASES`, one `<file><TAB><case>`
line each; a command that does not read it runs each file whole. The list then has `cases`, `[{"file", "case"}]`, and
a `why`, `the card ran <n> changed cases of <m> test files`, which the output and the Board's step show. A change with
none runs at most 5 of the test files the test map and the links give its files, those that failed most recently
first, and its output says so; one with none of those runs nothing and passes, its list `{"mode": "changed", "files":
0, ..., "why": "..."}`. When linked files are left out, the list has `left` (how many did not run) and a `why` that
says the run before the push runs them all. The Board shows this note with the step. The live record and the test
line hold `list`: `{"mode": "changed", "files": <count>, "by": "own", "map" or "name", "age": <commits>}` (`age`, the
commits the made test map is behind, only with one). The Board shows it with the test step (`changed: 7 files (map)
· map 12 commits old`, `changed: 7 files (by name)`); `/units` shows `changed: 7 files`. Before each push, the loop
runs the test files the test map and the links give each landing since the last push, each alone, once a commit; a
file that fails is run on the landings in turn, goes to the main-fix card of main's commit naming the landing that
broke it, and holds the push (`lib/push.sh` `pushtests`, [Push](../docs/cards.md#push)), unless the push check is off
(`push.check`, `conveyor.sh control push-check`). A run that reports more test files than it was given is stopped,
and the card is blocked with a reason that names the file that ran the rest.
The test map (`lib/testmap.sh`, [The test map](../docs/configuration.md#the-test-map)) is read before the names: the
tests it says cover a changed file are its tests, and a file more than half the mapped tests read runs the whole
suite. A card's run never adds to the map; the whole test on main and
`release-prep` make the map again when it is due (`test.mapAge`, or another test command), from the coverage that the
run collects (Node and Python), with no second run of the suite.

### When a full test run is allowed

A full run, of the whole selection, is allowed in three cases only:

1. a card's first test run: no test line of the card before it. A retried card's first run is one when main moved
   since its kept list was made; on the same main, it keeps its passes.
2. a merge in doubt: a file the merge onto main changed does not parse, or the session that brought the change onto
   main edited it outside the conflicts (or, for a rebuild or a port, beyond what main changed).
3. the full test suite: `full-test`, the Board's Run full test suite and Push landed (the pack's `test.full`), and the
   whole test on main (`test.main`).

Before it runs, the test step finds why it would run each file: what did not pass, what the card's change changed and
what main changed (above). When that cannot be found (the last run's list is missing, or names a tree or commit that
cannot be compared), it would run the whole selection. A card's run that would, and is none of the three, refuses the
full run: it runs only what its list did not keep as passed (with no list, or when the card's tree cannot be read
now, nothing was kept and every file runs), its
test line records `refused: "refused full run: <the reason seen>"`, and `health` lists it under
`refused` (`{card, issue, reason, since}`, for 24 hours), which wakes the Foreman once.

A card's build or fix session runs no whole suite by hand either. The command guard
(`.claude/hooks/bash-guardrails.sh`, one of the card hooks every project gets) refuses there, by the commands the pack
names:

- a command of `test.wholeCommands` (runners that run every case when none is named, as paths from the repository
  root) with no case named: no word after it but options and redirections, and no `CONVEYOR_SHELL_TEST_CASE=<cases>`
  before it;
- `test.changed` (the script that runs the tests a change touches) a second time in one session;
- `node --test` over a folder, a glob or nothing, rather than named files.

Each refusal says to name the cases or files instead; a run that names them is allowed.

### The session test budget

A card's build or fix session has a test-time budget: the pack's `test.sessionBudget`, in CPU seconds (default
3600). The command guard adds up, per session, the CPU time of the test commands it lets through: any `node --test`,
`*.test.sh`, `pytest`, `vitest` or `jest` run, also as `python3 -m pytest` or `npx vitest`. It runs each one behind an
EXIT trap that writes the call's CPU seconds (the user and system times of all it ran, as `times` gives them) to the
session's ledger (in `CONVEYOR_GUARD_STATE`, else `/tmp/conveyor-test-budget-<uid>`, one file per card and session id,
so a new session starts at 0). The session's own shell writes the ledger, so it is under /tmp: a Codex session's
sandbox lets it write there, and not in `~/.cache`. A call that leaves a test running in the background (`( ... ) &`) adds its CPU seconds
when that test ends, sampled each second, so the CPU of its last second is not counted. A test that waits uses no CPU
and spends none of the budget. Once the session's test CPU time is over the budget, the guard refuses its next test
command; other commands still run. The refusal tells the session to narrow to one case by reading its code and the
output it has, or to stop and report what it knows. The card's test step still runs the tests before the card lands. Not counted: a command that sets its own EXIT trap, and a test run from a
script or `bash -c` text.

### Test file times

Conveyor records the clock seconds and the CPU seconds of each test file it runs, and the Board's Tests page shows
them. No test file has a CPU budget. On a busy machine (a load of 8 to 90) a file's clock time measures the load, not
the file. Its CPU seconds (user plus system, of the file's process tree) stay the same however busy the machine is.

A runner times each test file it runs, from its start to its end, and measures its CPU seconds, and says so in its
log as the file ends: `TESTRUN sec<TAB><file><TAB><seconds><TAB><CPU seconds>` (the last line of a file counts; a
run again, and a run after a fix session that keeps what passed, keep the times the runs before them took of the
files they do not run). A line with no CPU seconds is recorded with its clock seconds only. The card's test line
holds each test file its change adds or modifies with both times (`timed`). The test
line also holds the clock seconds of each file it timed (`clocks`, `{file: sec}`). A run after a fix session lists
the files it kept as passed and did not run (`carried`): their times are from an earlier run, and the test judge
does not count them as a run of that file. A shell test file of which the run ran only some cases or parts (an
engine case file, the engine's runner, or another shell test file run with some of its parts) gets no time on the
line, as a runner does not time it: the line lists it as `partial`, and the test judge counts it as a run of that
file. A Board test file run again with the cases that passed skipped is timed as a run of the file, and is not
`partial`.

**How a split is checked.** A split does not lower the CPU seconds summed: each new file has its own start-up. It
gives files that run side by side. So the check of an Optimize card (Bug cards: the new tests
fail without the fix, below) passes a split when every case passes and the
CPU seconds summed are at most the median of the old file's recent runs plus a start-up allowance for each new file. The check
measures the allowance: it runs the first new file with no case selected. When the test command starts node --test,
pytest, go test, cargo test or rspec, Conveyor runs that runner on the file itself, with the runner's own filter set
to a case name that no file has (go test runs the file's package; cargo test needs a `tests/<name>.rs` file). Any
other test command gets a run-again line `fail<TAB><file><TAB>conveyor-no-case`. Conveyor uses that run only when the
run names no case and the run of the split named a case of that file. A command with no case filter runs the whole
file, so its CPU seconds are not start-up. When the run is not used, fails or gives no CPU seconds, the allowance is
the pack's `test.splitAllowance` (default 1). The reason of a refused split says which: the file the allowance was
measured on, or the pack's value and why. It measures only when the sum is over the old file's median.

A project whose test command prints no `TESTRUN sec` lines records no test times. The plugin ships a helper for it, `conveyor/tools/testtime.sh <file> -- <command>...`: it runs the command
once, then prints the file's `TESTRUN sec` line, with its clock seconds and its CPU seconds (the user plus system time
of all the command started); the command's output and exit code stay its own. A test script that runs the test files
one by one, writing `== <file>` and `-- ok|FAIL <file>` lines to its log in `CONVEYOR_TEST_LOG`, copies the helper
beside it and wraps each file's run, putting the helper's line in that log before the `-- ` line:

```bash
./testtime.sh "$f" -- <the file's command> > "$out" 2>&1; rc=$?
cat "$out"; grep '^TESTRUN sec' "$out" >> "$CONVEYOR_TEST_LOG/<its log>"
```

**Times from the runner's own report.** A project needs no `TESTRUN sec` lines when its test runner writes a
report Conveyor can read. The pack's `test.report` says how: `format`, and `path`, the report file or a folder of
report files, from the repository root (no `path`: the command's own output). After each test run, Conveyor reads
the report files written during that run and records each test file's clock seconds. A report gives no CPU seconds,
so these files are "Wall only" on the Board's Tests page. When the runner's log also
has a `TESTRUN sec` line for a file, that line wins.

| Runner | Report option in the test command | `format` | `path` |
| --- | --- | --- | --- |
| `node --test` | `--test-reporter=spec --test-reporter-destination=stdout --test-reporter=junit --test-reporter-destination=<file>` | `junit` | the file |
| vitest | `--reporter=default --reporter=json --outputFile.json=<file>`, or the `junit` reporter | `jest-json` or `junit` | the file |
| jest | `--json --outputFile=<file>` | `jest-json` | the file |
| pytest | `--junitxml=<file>`, or `--durations=0` | `junit`, or `pytest-durations` | the file, or none |
| go test | `-json`, or `-v` | `go-json`, or `go-text` | none |
| cargo test | none: its usual output gives the times | `cargo` | none |
| mocha | `--reporter xunit --reporter-option output=<file>` | `junit` | the file |
| rspec | `--format progress --format json --out <file>` | `rspec-json` | the file |
| any other | JUnit XML files written to a folder | `junit` | the folder |

`go test` gives a time for each test. Conveyor adds it to the `_test.go` file that declares the test. `setup` finds
the runner in the test command (or in the `package.json` script that `npm test` runs) and writes `test.report`, with
`format` and `path` when the command already writes a report. When the command writes no report, Conveyor asks for
one at each card test run and each run of the full test suite (`test.full`), and the test command stays as it is:

- `node --test`, pytest and rspec: `test.report` has `env`, the environment variable Conveyor sets for the run
  (`NODE_OPTIONS`, `PYTEST_ADDOPTS` or `SPEC_OPTS`). Conveyor adds the report option after the variable's own value.
- go test: `test.report` has `env` `GOFLAGS` set to `-v`, and Conveyor reads the times from the output (`go-text`).
  The output still shows the failures.
- mocha: `test.report` has `env` `NODE_OPTIONS` with `--require <mochatimes>`, Conveyor's helper
  `conveyor/tools/mochatimes.cjs`. It records the time of each test to the file in `CONVEYOR_MOCHA_REPORT` (`mocha-times`). Mocha's reporter
  stays as it is.
- vitest and jest, when they are the last command of the test command: `test.report` has `args`, the report option
  Conveyor adds at the end of the test command (after `--` for an npm script).

`<file>` in `env` or `args` is the report file Conveyor names, and `<mochatimes>` is the path of that helper. A command that
names a report or reporter of its own gets no second one. cargo test needs nothing: its usual output gives the time of
each test target. When Conveyor cannot ask for a report, for example for jest followed by another command,
`test.report` has `runner` and `option`, the report option to add to the test command. Set `test.report` by hand for
a runner that `setup` does not know, such as one that writes JUnit XML to a folder.

`setup` says so, with the path of the helper, when the pack's test command runs a shell script of the project that has
no `TESTRUN sec` and no `testtime.sh` in it; it never changes the script. `doctor` warns, and the Board's Health shows
a "Test times" warning, when the project's last card test runs (up to 5 that ran tests) recorded no test times
(`health`'s `untimed`: how many), each naming this section. When `test.report` names a runner with no `format`, the
warning names the runner and the report option to add to the test command.

**The test results cache.** A runner can also give, for each test file it runs whole, the files that the test file
reads: `TESTRUN inputs<TAB><file><TAB><input file>...` in its log. Paths are relative to the checkout. An input that
ends in `/` is a folder that the test file lists (`./` is the checkout's root): Conveyor compares the names of the
tracked files and folders in it, so a file added there or deleted, or a file changed to a folder of the same name,
changes the input. An input can also be a path that was not there when the test file looked for it. When the file passes (its
`-- ok` line, and no `ok`, `fail` or `off` line of the list names it, and no `TESTRUN case` line names it unless its
case lines name every `t_<case>() {` case that the file holds), Conveyor keeps a hash of the file and its inputs in
`testcache.tsv` in the state folder (the last 5000). The hash covers the contents of each file, whether the file can
run, whether a path is a file, a folder or not there, and, for a symbolic link, the path that the link names. A later test run of any card, or the whole test on
main, keeps off a file whose hash in its worktree matches a kept one: its list gets a `pass<TAB><file>` and an
`off<TAB><file>` line (unless the list names failed cases of it). The run's log says so with
`TESTRUN why<TAB><file><TAB>passed before with the same inputs`, so the test line's `why` holds it too. A file with
no `TESTRUN inputs` line is never kept off in this way.
A card's test list also gets each test file whose last kept pass read a file that the change touches, or listed a
folder that the change adds a file to or deletes a file from. Such a file runs whole, also when the card's own change
selects only some of its cases. When a fix, or a newer main, changes a file that a test file's last kept pass read,
the card's next test run does not use the pass of that file from the card's earlier run. The test map and the test
links still give the tests that have no kept pass. Each
other file on the card's list gets a `TESTRUN why` line that tells why it runs: its inputs changed since its last
pass, or no pass of it is kept with its inputs.
The full test suite does not use the cache. A path that is absolute or contains `..` is not kept.

A slow test file never sends a card to its review, a fix or another test step, and nothing is filed for it as a
follow-up. Conveyor files an issue about a test file only by a test
rule (Test rules, below), behind its switch and guards. The pack's `test.slowIssues` files nothing.

The issue that filing kept for each file is still in `slow.json` in the state folder. The Tests page reads a file's
issue from it. It keeps no file off card test steps.

### Changed lines no test reached

When a card's test command already writes a coverage report, the pack's `test.coverage` names it: `format` (`lcov`),
and `path`, the report file or a folder of report files, from the repository root. After the card's test run,
Conveyor reads the report files written during that run. The card's test step then shows the lines that the tested
patch adds and that the report counts but that no test reached, by file, and how many of the counted lines that is.
When two reports count the same line, the line counts once, and a hit in either report reaches it. When the run
runs the failed tests again, Conveyor reads the first run's reports too, so a line that the first run reached stays
reached. A file that no
report names, such as a test file or a document, is not counted. The step shows the coverage as unknown, with the
reason, when the run wrote no report, or when the report does not match the tested patch: it names no file of the
card's worktree, or it names a line past the end of a changed file. The list is a lead for the reviewer. It never
fails or holds a card, and Conveyor starts no other test run for it.

### The test files in the snapshot

The snapshot's `tests` part compares each test file with its own usual time. It is made from the card test lines (those of retried cards too), the whole-suite runs
and the test files of main's checkout, and holds:

- `settings`: the pack's `slowIssues`, `slower` (`{share, runs, minRuns}`), `files` (each file's own
  settings, as the pack holds them), `report` (the pack's `test.report`, null with none: the runner a Wall only
  file's status names) and `cpuTime` (Record CPU time: `{file, was, command, fileCommand}`, the one test file the test
  command runs and the command wrapped in `conveyor/tools/testtime.sh`, with `test.fileCommand` wrapped too when it is
  set, which `conveyor.sh test-settings cpu-time <file>` saves;
  or `{why}`, why no wrapper applies);
- `suite`: the newest whole-suite run on record, `{time, cpu}`, `cpu` the CPU seconds of its files added up (null
  when none has any); null with no whole-suite run. A `wholeOnly` file's status gives it as what a change to it costs;
- `rules`: the test rules (Test rules, below): `on`, `perDay`, `maxOpen`, `quietDays`, `burst` and `list`, as the
  pack holds them with their defaults, and `last`, the list of the last pass (`{time, on, matches, burst}`), null
  before the first;
- `files`: every test file of main's checkout (each file git lists with `.test.` in its name, and each file the pack's
  `tests.patterns` match when the pack sets them), and each other file with a run on record, the
  highest CPU seconds first and the files with none last. A run on record is a card's test
  line (`times`), a whole-suite run or a time the test-speed survey saved in `.conveyor/test-times.json` (dated by the
  commit that last wrote it, with no card; a test file of main only): the full test suite (Run full test suite and Push landed on the Board) and
  the suite of `release-prep` and `release` each keep, as they end, the result (`-- ok|FAIL <file>`) and the `TESTRUN sec` line of each file
  they ran. Each file has `file`, `cpu` (its newest run with CPU seconds; null with none), `median` (of every run on
  record with CPU seconds), `change` (`cpu` against `median`, as a share: 0.5 is 50% over; null when the median is 0
  or null), `runs` (its last 5 runs, newest first, empty for a file never run: `cpu`, `sec`, the clock seconds, null
  on a line written before the test line held `clocks`; `card`, null for a whole-suite run and a survey's time; `time`; `whole`, true for
  a whole-suite run; a whole-suite run's `result`, `ok` or `fail`; and `survey`, true for a survey's time), `lastRun` (`sec`, `cpu`, `clockPerCpu`, `time`,
  and `whole` of its newest run, and `survey: true` when it is a survey's time; null with none), `timedRuns` (its runs with CPU seconds), `runsOnRecord` (all its
  runs on record), `wholeOnly` (its
  `test.files` entry has `wholeOnly: true`), `failedSteps` (the card test steps that failed in it: it was a failed file, a runner such as
  `conveyor/conveyor.test.sh` named a failed case that the file defines (`t_<case>()` or `<case>()` in main's
  checkout) and the file names that runner, or the run timed
  out in it; a case the named file defines itself is that file's alone), `failures` (those steps, newest first, each
  `{card, issue, time, verdict, cases, tail}`: `verdict` is `main` when a case of the file failed on main too, else
  `flaky` when one failed and then passed when run again, else `card` when the card's own change made it fail, and
  null on a step from before verdicts were kept; `cases` names its failing cases; `tail` holds the last 1,500
  characters of the step's output, on the 5 newest steps only), `caught` and `changedToPass` (those of
  its failed steps whose card landed: `caught` when the landed commit did not change the file, so the fix went into
  the code; `changedToPass` when it changed the file; a landed commit that main's checkout does not have counts
  neither way), `flaky` (its entries in the flaky-test record, its cases' entries too, the
  entries a runner names as its own among them), `issue` (the issue last
  filed for it, the highest number of the old "Slow test" filings, the test rules' log and the Board's
  `conveyor.sh testissue`, else null), `slowOnPurpose`
  (the reason of its mark, else null), `cases` (the names of the cases a shell file (`.sh`, `.bash`) defines in main's checkout, its `t_<case>() {`
  lines that the runner selects, not its helpers or the lines of a heredoc, A to Z; empty with none; null for a file
  of another kind, whose cases Conveyor does not count: the Board's Tests search matches them), `usual` and `slower` (below).
  A `wholeOnly` file starts other test files whole, so its CPU seconds are the sum of theirs, each of them timed on
  its own. Its `slower` is false. Each file also has `optimize`: each issue the Board filed for it (`testactions/filed.jsonl`: the Optimize
  issues, and the older speed-up issues), newest first. Each has `issue`, `time` (when it was filed), `state` (`open`:
  no card took it; `building`; `blocked`, with `reason`; `landed`, with `sha` and `landed`, the time; `closed`: its card
  closed it with no landing), `fix`, `into`, `before` and `after` (from the `speed` of the `bugproof` line of its
  landed card, else of its newest; null and empty with none; for a delete, `into` lists the test files that the last
  review of its landed card named on its `COVERED-BY` lines), `since` (the median CPU seconds of the file's runs after
  it landed; null before it lands or with no run since) and `sinceRuns` (how many runs that median has). A file that
  only a Board filing names is listed too. `removed` is true for a file that main's checkout no longer has, when a
  landed Optimize deleted it or merged it. The totals leave such a file out. `hollow` lists the hollow cases that a
  check with no model finds in a JavaScript or TypeScript test file (a name that ends `.test.js`, `.test.ts`, `.test.mjs`,
  `.test.tsx` and the like), each `{case, kind, reason}`, and is empty with none; it is null for a file of another kind.
  A case (an `it(` or `test(` line with its name) runs to the next case, skipped case, `describe` or hook. It is
  `no-assert` with no `expect(` and no `assert` in it, and `defined-only` when each of its assertions is
  `expect(...).toBeDefined()` or `.toBeTruthy()`. An assertion in a comment counts too, so the check can miss a hollow
  case but never names a case that asserts. The Board shows a Judge's `hollow` (Test actions, below) in place of this
  one once a Judge of the file ended. `waits` holds the `waits` of the newest Judge of the file that ended done (Test
  actions, below), `[{case, kind, at, reason}]`, and is null when that Judge named none. `neverRun` says why a file of
  main's checkout with no run on record never ran, when Conveyor can tell, as `{kind, reason}`, and is null otherwise.
  The kind is `patterns` (the pack's `tests.patterns` do not match the file, or the test command names a glob, a file
  or a folder that does not match it), `load` (`bash -n`, `node --check` or Python cannot parse the file; the reason
  holds the error) or `skipped` (the file holds skip markers, named in the reason);
- `slower`: the names of the files slower than their usual;
- `edits`: each entry of the `testedits` of the landed cards (below), newest first, with the card's `card`, `issue`
  and `time` (when it landed); the newest 5 of each file;
- `totals`: `files` (those with CPU seconds on record), `slower`, and `steps`: the card
  test steps that ran in the 7 days to today, `{count, waitSec, runSec}`, with the seconds they waited for a test slot
  and the seconds their test commands ran.

When a card lands, Conveyor reads its staged change to each test file that main already has (a file with `.test.` in
its name; a new test file is not read) and writes `testedits` on the landed line, one entry a file: `file`, `read`,
`removedAsserts`, `changedExpected`, `skipsAdded`, `timeoutsRaised` and `casesDeleted`. A card that changed no such
file has no `testedits`. One table in `lib/testfiles.sh` (`TESTEDIT_TABLE`) holds the patterns, one row a language:
shell (`.sh`, `.bash`, `.bats`: `|| fail` and `assert` lines, `skip`, `t_<name>()`, `test<name>()` and `@test` cases,
`timeout <N>`, `--timeout` and `# timeout:`) and JavaScript and TypeScript (`expect(` and `assert` calls,
`it.skip`, `test.only`, `describe.todo`, `xit`, `skip: true` and the like, `it(` and `test(` cases with a literal
name, `timeout:` and `setTimeout(` numbers), Python (`.py`: `assert`, `self.assert<X>(` and `pytest.raises` lines,
`@pytest.mark.skip` and `self.skipTest(` marks, `def test<name>(` cases, `timeout=` numbers) and Go (`.go`:
`t.Errorf(` and the like and testify `assert.` and `require.` calls, `t.Skip(` marks, `func Test<Name>(` cases). A file of another kind has `read` false and its counts null: edited, not read. A test file
that the card deletes is read too: all of its assertions and cases are removed. An assertion includes the lines after
it up to its closing bracket. A line removed and added again unchanged counts for nothing. An assertion that keeps its
call and actual value but changes its expected value is a changed expected value: the value after `expect(...)`'s
matcher, the second argument of `assert.equal`, `self.assertEqual` and the like, the value of `assert(...)`,
`assert.ok`, `self.assertTrue` or a Python `assert`, the value after `t` in a testify call, or a shell test before
`|| fail`; a `t.Errorf(` and the like is its message alone. A changed message alone counts for nothing. A timeout whose number went up and nothing else is a raised timeout. Removed assertions, added
marks and deleted cases count what the file lost or gained on balance, so an assertion rewritten or a case renamed
counts for nothing.

A project with no test file and no run on record has the part with an empty `files` list and its step totals. The
part is `null` only when the pack cannot be read.

A file is slower than its usual when its CPU seconds in each of its last `test.slower.runs` runs (default 3) are over
its usual by more than `test.slower.share` (default 0.25: 25%), and at least `test.slower.minRuns` runs (default 5)
of it are on record. Its usual (`usual`) is the median of its runs before those last runs, so the slow runs do not
raise the time they are compared with; it is null with fewer runs on record. Conveyor files nothing for such a file.

A file's own settings are in the pack's `test.files`, by its path from the repository root:

- `slowOnPurpose`: why the file is slow on purpose, one line that is not blank. The CPU test rule never files it.
- `cardMode` and `wholeOnly`, of a meta-runner, a test file that starts other test files whole (read by the
  project's changed-tests script, which marks each file it starts and logs `TESTRUN nested <file> <inner file>`
  for each such start): `cardMode` is the `NAME=VALUE` that makes the file run its own checks with a stub in place of
  the files it starts, which a card's Test step runs it with; `wholeOnly: true` keeps it off a card's Test step, which says so (`TESTRUN whole-only`),
  so only a whole-suite run runs it: the full test suite (Run full test suite and Push landed on the Board) and
  the suite of `release-prep` and `release`. A meta-runner with neither fails a card's Test step, which names the file and the two marks.

```json
"test": {"command": "...", "files": {"conveyor/tests/e2e.test.sh": {"slowOnPurpose": "runs the whole loop end to end"}}}
```

The pack's `test.fileBudget`, a `budget` in `test.files` and a test rule with the measure `budget` are ignored.
`doctor` names them on one line while the pack holds them.

The Board saves these settings with `conveyor.sh test-settings`, which changes main's pack (`.conveyor/project.json`),
except `history-start`, which changes the control record, and `record-times` when its plan is a held card, which files the
card and leaves the pack as it is. Each other command checks its value and the changed pack
(lib/pack.sh) before it saves; a bad value is refused with the reason, and the pack does not change. `history-start`
checks its own value (a UTC time, or `clear`) and changes no pack. The Board saves
`history-start` too, in "Test history starts at" of the Test settings.

- `test-settings slow-issues <true | false>`: `test.slowIssues`, which files nothing now (Test rules, below);
- `test-settings slow-mark <file> <reason>`: the "slow on purpose" mark of one file that main's checkout tracks, with
  its reason (the spaces at its ends removed);
- `test-settings slow-mark-clear <file>`: that mark removed;
- `test-settings cpu-time <file>`: `test.command` wrapped in `conveyor/tools/testtime.sh` for that file, as the
  snapshot's `cpuTime` gives it, refused with its `why` when no wrapper applies. The test command finds the helper in
  `CONVEYOR_TEST_TIME`, and puts the helper's `TESTRUN sec` line in the run's log. Only an admin can save it from the
  Board.
- `test-settings record-times`: the plan the snapshot's health gives as `timesPlan` while the last card test runs
  recorded no test times. It sets the pack's `test.report` to the report that `setup` knows for the test command
  (`kind` `report`); or wraps a test command that runs one test file in `conveyor/tools/testtime.sh`, as `cpu-time`
  does (`wrap`); or, for a test command that runs a script of the project, files a held card with no GitHub issue whose
  body gives the steps to wrap each file's run (`card`). Release the card with `control release <card id>`. With no
  plan, or the same card waiting, it changes nothing and says so.
- `test-settings history-start <UTC time | clear>`: the time, such as `2026-11-21T00:00:00Z`, from which the Tests
  snapshot, the test rules and the facts the Tests judge is given count runs, failed steps and flaky entries. Older
  ones are kept and not counted. `clear` counts every run again.

A file with no setting left is removed from `test.files`. The next snapshot shows each change.

### Test rules

Rules the owner sets in the pack (`test.rules`, `lib/testrules.sh`) file one issue about a test file that meets
their limit. One switch, `test.rules.on`, turns every rule on or off; it is off by default, and a new install starts
with it off and with no rule on (no `test.rules` in the pack `setup` writes). With the switch off, no rule files
anything.

A rule has a `name`, `on`, one `measure`, one `limit`, `runs` (the card test runs in a row that each meet the limit)
and `minRuns` (the least count of the file's card test runs on record). The measures, from the card test lines and
the flaky-test record:

- `usual`: CPU seconds over `limit` times its usual, the median of its runs before its last `runs` runs ("slower than
  its usual");
- `clock`: clock seconds over `limit` times its CPU seconds, in runs of at least `minClock` clock seconds (default 0);
- `flaky`: at least `limit` entries of the flaky-test record for its cases (a case kept off as flaky) in the last
  `days` days (default 7);
- `failed`: at least `limit` card test steps that failed in it in the last `days` days (default 7).

`usual` is the CPU rule. A file two rules match is filed by the first rule in the list.

```json
"test": {"rules": {"on": true, "perDay": 3, "list": [
  {"name": "slower than usual", "on": true, "measure": "usual", "limit": 1.5, "runs": 3, "minRuns": 5}]}}
```

The guards, each a pack setting with a default, stop a match in this order:

- `off`: the switch is off;
- `slowOnPurpose`: a file marked slow on purpose is never filed by the CPU rule;
- `oneAFile`: an earlier rule matched the file in the same pass;
- `open`: the issue last filed for the file is open, whichever rule matched it; an issue whose state cannot be read
  (or that is closed with no closing time) counts as open, so nothing is filed;
- `quietDays` (default 14): no issue for a file in that many days after its last issue closed;
- `burst` (default true): when one pass matches more files than `perDay`, the pass files nothing and the snapshot puts
  one line in "Needs you" (`needsYou.testRules`: `{time, matched, cap}`) until a later pass files or stops below that;
- `perDay` (default 3): the most issues filed in one day (this machine's local day); the rest wait for the next day's
  pass;
- `maxOpen` (default 5): the most issues of the rules open at one time.

A pass runs after each card test step that ran tests. An issue it files is titled "Test rule <name>: <file>", has the
pack's type and last priority, and names the rule, the measured values and the cards of those figures. It has no
Done-when line: no run count and no time target. The list of the last pass is in `testrules.json` in the state folder
and in the snapshot (`tests.rules.last`): each match with its `result` (`filed` with its `issue`, `stopped` with its
`guard` and `why`, or `not filed` when GitHub did not take it). With the switch off, the pass keeps the list and files
and logs nothing.

The log, `testrules.jsonl` in the state folder, has one line for each issue filed and each match a guard stopped:
`time`, `event` (`filed` or `stopped`), `rule`, `measure`, `file`, `values` (the measured values), `cards`, and `issue`
or `guard` and `why`. The log is also the record of the issues filed: the guards read it. The snapshot holds its last
50 lines, newest first, in `tests.rules.log`, for the Board's Tests page.

`conveyor.sh testrules preview` lists what the rules match now, one line a match: the rule, the file, the measured
values, and "would file" or the guard that stops it. It files and writes nothing, with the switch on or off.

The commands that set the rules change main's pack and nothing else; each checks its value and the changed pack before
it saves, and a bad value is refused with the reason:

- `testrules on` and `testrules off`: the switch;
- `testrules guard <perDay | maxOpen | quietDays | burst> <value>`: a guard;
- `testrules add <name> <measure> <limit> <runs> <minRuns> [<days | minClock>]`: a rule, added off;
- `testrules set <name> <on | measure | limit | runs | minRuns | days | minClock> <value>`: one setting of a rule;
- `testrules remove <name>`: a rule.

## Lint

`lib/lint.sh` runs the pack's lint commands (the `lint` field, [Lint](../docs/configuration.md#lint)). It finds the
files of each command with git pathspecs, runs the command at the top of the worktree with `bash -o pipefail -c`
and a limit of 5 minutes, on one test slot, and reads the result: pass, findings, skipped or an execution error. It
reads a finding's path by the paths of the tree, so a path can hold spaces and colons. `conveyor.sh lint` uses it on
the worktree it is called in, and `conveyor.sh doctor` tries each command once ([Commands](../docs/commands.md)).

The ratchet (`lintratchet`, [The ratchet](../docs/configuration.md#the-ratchet)) decides which findings are the
card's. A finding on a line the card added or changed is the card's. A `complexity` finding on such a line is the
card's when the base lines its hunk replaced lack it. A finding on another line is the card's when base lacks it at
the line that the diff maps it to. Base is the commit the card's worktree is on.

One base run of the command gives base's findings, on the base paths of the files that hold findings to compare. It
runs in the base worktree
`cards/mainrun/<card>.lint`, whose trigger and policy files are first made equal to the card's tree. That worktree
links the dependency folders the card's worktree has, does not run `worktree.setup`, and is removed at the end. A
`ratchet: false` command gets no base run: every finding is the card's. A base run that does not end in pass or
findings makes the command's result an execution error.

`card()` runs a card in steps: `cardopen()` (the worktree and the brief) and `cardbuild()` (the build and its proof),
then on each pass of the review loop `cardreview()` (the review), `cardfix()` (a fix round, or on to land),
`cardready()` (the owner's yes, the trailers and the ready file), `cardlanding()` (the checks, the tests, in
`cardtest()` and `cardfailed()`, and the land step, in `cardland()`) and `landconflict()` (the one rebuild or port of a
change whose landing conflicts). The steps from `cardready()` on are in `lib/cardland.sh`.

The review gate (`lintgate`) is at the top of each pass of the review loop, in `cardreview()`: after the change is
staged, before the choice between a kept review and a review session. With the rule Lint check on, it runs the ratchet on the
staged change, from the commit the card's worktree is on, and writes the card's `lint` line. A pass or a skipped
command lets the card go on. An execution error blocks the card, with no fix session. The card's findings go to one
fix session in the same pass, its reply checked as any fix's reply is. The change is staged again and the gate runs
again: a finding left then blocks the card, and nothing lands. After that fix, the kept review, a kept patch's review
(a retry that lands it) and a kept test pass no longer stand: the review session of the same pass reads the fixed
change. The fix counts as no review. A later fix or rebuild session that adds a finding gets one new fix session at
the next pass's gate. When a card is split for its size (`growcheck`), the gate runs again after the split's fix
session, before the review of that pass.

The landing gate (`lintgate` with `land`) is in the landing loop, in `cardtest()`, each time the product checks run: after
the parse check of a merge onto main (`parses`), before the product checks and the changed tests. It uses the same
ratchet run, from the commit the worktree is on after the merge, the same read-only check, `lint` line,
execution-error block and rule Lint check. After a pass there, a card fitted onto a newer main runs no command at its
next landing gate while `lintstands` holds: the card's change and the pack's `lint` field are the same as at that
pass, and main changed none of the change's files, no command's triggers or size exempt file, and no file that a
command without `{files}` reads (`<worktree>.linted` keeps the pass). That pass stays the card's result, with no new
`lint` line. A lint run that finds the change red while the card waits (`lintwait`) or in a batch (`lintleave`) removes
that pass, so the next landing gate runs the commands again. The card's findings go to one fix session, its reply checked as any fix's
reply is, with no gate run after it. Its fix line's reason starts `lint:`, and the Board names the step
`Fix <n>: lint findings`. The card then goes round to a review, which is a last review, as after a test fix. The
review gate of that pass does not run on the change the fix left (`lfix`, its `cardpatch`): the landing gate decides
on it. At the next landing gate, a finding on that same change blocks the card with `lint: <n> findings left after its
fix session; nothing landed`. A change that a later session changed (a test fix, a check fix) gets one new fix session.

After the lint gate, `cardtest()` runs `contractgate` (`lib/contract.sh`) when main's pre-push hook names
`--contract-range`: `adversarial-review-gate.sh --contract-range` on the card's staged change, from the install of the
project's engine (the pack's pin, or the newest commit taken on this machine), as the pre-push hook loads it. A loop
run from a checkout with no such commit uses the engine's own `.claude/hooks/`. A refusal goes to a fix session with
the check's message, and the card goes round to a review. The check names one writer at a time, so a refusal that
names another writer gets its own fix session. A refusal that a fix session already had (`cfix`), or a check that
cannot run, blocks the card with a reason that starts `contract:`. With batches on, a card that waits to land runs the same check
after its lint (`contractwait`, in `settle()`): a refusal removes its `<worktree>.ready`, so no batch takes it, and its
landing gate deals with it at its turn. `landone()` (`lib/claim.sh`) runs the check again on each commit it is about to
land, from the commit before it: in a batch, that is the commit of the card before it. A refusal there, or a check that
cannot run, lands nothing and removes the card's `<worktree>.ready`.

The read-only check (`lintrun`) holds around each run of the lint commands, not around the persisted-contract check. Before the commands, the index tree is kept, and the
worktree must match the index with no file that git does not track or ignore; else no command runs and nothing is
put back. After them, also after a time-out, the index tree must be the kept one and the worktree must match it again;
else the index is read back from the kept tree, the tracked files are written from it and each file that git does not
track or ignore is deleted. Both are execution errors. The build and fix brief gets a `# Lint` section (`lintbrief`)
that names the commands and the engine's own `conveyor.sh lint`.

## Flaky tests

The flaky-test record (`flaky.json` in the state folder, `lib/flaky.sh`) keeps each time a test case failed and then
passed when run again with nothing changed. A card whose test run passed on re-run adds one entry for each case that
had not passed on its first run: the case as `<file>: <case>` (a file that failed naming no case, or ran out of time,
as the file alone), the card as its source, the card's issue and the time. Each run is recorded as it ends, so a later
run (its batch's) loses none; a batch's run counts as the card's that ran it. From outside a card,
`conveyor.sh flaky add <case> <source> <note>` adds one entry with its source and note: a nightly whole test adds a
case that failed in the full run and passed alone. `conveyor.sh flaky off <case> <source> <note>` adds the entry the
same way and files no issue for it (the Board's Keep a case off, which files none); a later entry from a card still
counts it. A call with no case name or no source adds nothing and exits 2.
A push whose pre-push hook failed naming test files that each pass alone adds one entry for each whole file, its
source `push <commit>`, and files one held issue for them, or opens again the issue of a file that is flaky again
([docs/cards.md](../docs/cards.md#push)).
Entries older than 30 days are dropped.

Before it adds its entry, `conveyor.sh flaky` drops each case that is gone from main, with all its entries. A case is
gone when its file is not in main's checkout, or when its name is not in its file or in a test file that runs through
it (a runner's case files). A file named from a subfolder of the checkout counts as that file. The command prints each
dropped case with its reason, and closes the case's open flaky issue with a comment that gives the reason. When it
cannot close the issue, or GitHub does not say whether the issue is open, it keeps the case.

When a case has entries from three different sources within seven days and no open issue filed for it, Conveyor files
one issue through its GitHub write path (the privacy check included): the title "Flaky test: <case> fails at random",
the labels of the pack's type, its last priority, `<areaPrefix>engine` when the pack's `nonProductAreas` names it, and
`flaky-test` (made when the repo lacks it), and a body that lists the entries of those seven days and asks for the
test to be made reliable or removed, with "Done when: the case passes alone and in the whole test." It is an ordinary
issue, not a review follow-up. While that issue is open, later entries file nothing; once it is closed, only the entries
made after it closed count, and the next entry that meets the rule with them files a new one that lists only them. When GitHub does not say whether it is open, nothing is filed until the next entry.

A card whose run again still failed adds an entry for each case that passed in it (its file passed, or the case
printed `ok`); a case that failed again, or did not run, adds none.

A case the record names as `<file>: <case>` is kept off card test steps until its flaky issue
closes: while no issue is filed for it yet, while the last one is open or GitHub does not say, and after it closed
only when an entry came after the closing. A card's run is told to keep the case as passed (an `ok` line in its
`CONVEYOR_TEST_RERUN` list, unless the list already names the case or its file as passed, and an
`off<TAB><file><TAB><case>` line, unless a `fail` line names the case), so the command does not run it. An `ok` line
alone is also a case that passed in a run killed part-way, which a `changed` or `main` line that selects it runs
again; an `off` case stays off even then (a test file that cannot run in part runs whole); the full test suite and the whole test on main are given no such list and run it. A whole file, or a case with no
file, is never kept off. The snapshot's `flaky` lists the cases with entries in the last seven days, each with
its count and the issue filed for it; the Board's Health panel draws them as its "Flaky tests" line.

## Bug cards: the new tests fail without the fix

A card whose issue has the pack's type label (`labels.type`, a bug) is checked after its build and before its review:
the test files its change adds or changes (paths the pack's `tests.patterns` match, [How test files are
found](../docs/configuration.md#how-test-files-are-found)) run on main's code without the fix, alone, in a worktree of
the commit the card was built on (`cards/mainrun/<card>.unfixed`), each file alone through the pack's
`test.fileCommand`. At least one must fail there. When all pass, the card goes back to its build
session once, told "the new tests pass without the fix, so they do not prove it" (its second `build` line has that
reason), and the check runs again; when it still does not hold, the card is blocked with that reason, with no review.
When the change adds or changes no test file, the reason is "no test file found in the change (patterns: <the
patterns>); set tests.patterns in .conveyor/project.json" in its place. When the pack sets no `test.fileCommand` and Conveyor has no runner of its own for one of those files, the check does not run: the card is blocked with a reason that names
`test.fileCommand`, with no second build session and no review. When the project's test files run alone as plain
scripts, setup suggests `node`, `bash` or `python3` as `test.fileCommand`. A failed run counts only when a test failed in it: when the runner writes its logs, they must name a
file that failed (a runner that stops the run with no test failing proves nothing). Each test file keeps its own time
limit there, its `# timeout: <seconds>` line among the comments it starts with; a file with no such line has no limit
of its own. The `testTimeout` setting limits the whole run, not each file, so the files before it can use most of
that time. When a file runs past its own limit, it is stopped and named as timed out. When the run's limit stops the
run, the runner's logs name the file begun and not ended, and the result says that the run's limit stopped it. Either
way the file counts as failing without the fix. A failed run whose logs give no
result for one of the test files (no pass and no fail of it) proves nothing either way, so it runs once more. When
that run gives no result for it either, the card is blocked with "the proof run on main gave no result for <file>:
<the run's last lines>", with no second build session and no review. The review is shown the check's
result. A card whose issue is not a bug, and a build that left no change, are not checked. A main-red fix card is
checked by the cases that main fails, not by its tests (the **main** verdict, above). A change to test files
alone (every path it changes is a test file, as in a fix to a test that main made wrong) is not checked either: it has
no fix to take out, so its tests would run on the same code and pass, and the card would be blocked though correct.
Its result says the change is test-only, and the review judges whether each changed test still checks what it was
written to check. A change that changes only comments in its product files, with or without test files, is
not checked either, as a comment changes no behaviour and no test of it can fail without the fix. Only
`.js`, `.mjs`, `.cjs`, `.ts`, `.mts` and `.cts` product files can be so: the `//` and `/* */` comments are found
in the whole file. Text in a string, code that a change puts between `/*` and `*/`, and a `/* */` comment that parts
two words are not comment changes. Blank lines can change too. Its result says the product change is comments only.
A change with any other product file, such as a `.css`, `.html`, `.sh` or `.py` file, or with any other change, is
checked as above.

A change that selects no test of its own is checked another way. This is a change where every changed line is a
comment, or one that touches no file linked to a test: the test map and the links give it no test file on main's
code with the whole change staged. The check then runs the test files that the issue's `## Done when` section names, alone, on
main's code with the fix and without it. At least one must fail without the fix, and they must pass with it. When
the issue names no test file, the card goes on to review with no check. Its `bugproof` line (result `skipped`) and
the result the review sees say why. The review reads that change as it reads any other.

A bug card that speeds up one test file is checked another way too. This is an issue whose title starts "Speed up the
test file", as the Board's Tests page files it (`conveyor.sh testissue`). The file is the one that filing named, else
the title's next word. Such a change keeps what the file tests, so its tests pass on main's code, and no test must fail
there. The file runs alone, with the change, on a test slot, through the pack's `test.fileCommand`. When that command
also runs other test files, a failure of one of them is named as another test file the change selects, apart from the
file's own failure. The file must pass, and its CPU
seconds must be lower than the median of its recent runs: the runs on the issue's "Last runs, newest first" line, as
the Tests page writes it. The Tests page writes `none` on that line when the file has no runs, and `— CPU s` for a
run with a clock time only. When the issue has no such line, or the line gives no CPU seconds, the check uses the
file's median on record. This is the median the Tests page shows. One run of a file can take much more or less time
than the last, so a run that is lower than the slowest of the runs on the "Last runs" line passes too. The card's `bugproof` line (result `ok` or `fail`) names the file and both numbers: `speed: {file, before,
after}`. When the file is not faster, and not lower than the slowest of those runs, the card
is blocked with "the file is not faster than <the median of its recent runs, or its median on record> (<before> CPU
s), as the verdict speed up asks: <after> CPU s now", with no review. When the file
fails, has no CPU seconds on record, or its run gives none, the card is blocked too, with the reason. The review is
shown the result.

A bug card that optimizes one test file is checked in the same way. This is an issue whose title starts "Optimize the
test file", as the Tests page files it. The card picks the fix: it speeds the file up, splits it, merges it into
another test file, or deletes it. No test must fail on main's code. The check follows the judge's verdict in the
issue: the line "The judge's verdict (...): <verdict>." that the Tests page writes, else the last `VERDICT:` line. An
issue with no verdict can take any of the changes below, each checked as the list after them says. The change must do
what the verdict asks, else the card is blocked with a reason that names the verdict:

- speed up: the change keeps the file and adds or removes no other test file, and the file must cost less than its recent runs (or less than the slowest of them).
- keep: the change keeps the file and adds or removes no other test file, and the file must cost less than its recent runs (or less than the slowest of them).
- stabilise: the change keeps the file and adds or removes no other test file. The build's reply ends with one line
  `STABILISED: <case> | <its cause> | <how the change removes it>` for each case that the issue names on a `CAUSE:`
  line, or at least one line when the issue names none. A case with no line blocks the card before the run. The file
  must cost no more than its recent runs. The review gets the lines and checks each one against the code. When a fix's
  reply gives a line for a case again, that line replaces the build's line for the case.
- split: the change changes or removes the file and adds test files.
- merge: the change removes the file and changes another test file, or changes the file and removes another test
  file. It adds no test file. When the file stays, it and the other test files that the change keeps run alone with
  the change. They must cost no more than they cost without the change, run with each test file merged into the file.
- delete: the change removes the file and adds or changes no other test file.

Then the check depends on what the change does:

- The change keeps the file and adds no test file: the check is the speed-up check above (for stabilise and merge,
  the file may cost as much as its figure).
- The change adds test files (a split): the new files run alone, with the change, on a test slot, and so does the rest
  of the old file when the change keeps it. When the command also runs other test files, a failure of one of them is
  named as another test file the change selects. They must pass. Their CPU
  seconds summed must be at most the median of the old file's recent runs plus a start-up allowance for each file the split adds (Test
  file times, above). Else the card is blocked with no review. The reason names the sum, how far it is over its limit,
  and the allowance.
- The change removes the file and adds no test file (a delete, or a merge into another file): the file runs alone on
  main's code, without the change, and the review gets the cases that its runner named. The review must
  name, for each case, the test that still covers it, one line each: `COVERED-BY: <test file>: <case>`. Such a line is
  not a finding, and it stays in the review's record. A case with no test named is a finding.
- For a merge, the test files that the change modifies also run alone on main's code, without the change and with it.
  They must pass both times. With the change, they may take their CPU seconds without it plus the figure of the removed
  file. Otherwise the check fails and names the cause.

The card's `bugproof` line names the file and both numbers, as for a speed-up: `after` is the CPU seconds summed of a
split, or of the files that a merge modifies, with the change, and null for a delete. For a merge, `before` is the
limit for those files. It also names the fix: `fix` is `sped up`, `split`, `merged` or `deleted`,
and `into` lists the test files that a split adds or that a merge changes (empty for the others). A change that
removes the file and changes another test file is a merge into that file; one that changes no other test file is a
delete.

The build of a speed-up or Optimize card is told the target. Before the build, the file runs alone on main's code to
count its cases. The brief gives the CPU seconds that the check holds the file to (the median of its recent runs, or
its median on record), its count of cases and their average CPU seconds. It also says how the check above takes a
split, and what the issue's verdict asks.

The loop retries a blocked card by itself when the check above has changed since the card was blocked. When the loop
starts, it looks at each issue whose last card is blocked by an older version of this check. It retries the card one
time, as `conveyor.sh retry <issue> --fresh` does: the next card builds from nothing, and the old card's kept work moves
to a dated folder under `kept-dropped/` in the state folder. The log and the Board's card say "retried: the speed check
that blocked it has changed". The loop does not do this for an issue that you hold, or for a card that the current
check blocked. It retries each card in this way only one time, and `speedretried.jsonl` in the state folder keeps the
cards that it retried.

## The whole test on main

A card's test step runs the tests of what the card touched, each file alone through `test.fileCommand`. The whole test on main runs
only for a project whose pack names it, as `test.main`; a pack that names none has none. The loop (`serve`) runs it on
the default branch, on the same test slots and beside the cards, so no card waits on it: at most once an hour, and
only when the branch has moved since its last run. With `test.mainAt` set in the pack (a time of day, `"HH:MM"`, in
the machine's local time), it runs once a day instead: the first time the loop looks after that time, when the branch
has moved since its last run.

When it fails, Conveyor runs each failed case again alone, 3 times, on the same commit (an engine case or a case of a
node test file runs by itself; a Python or other shell test file runs whole, and after a suite timeout the whole suite
runs). A case that passes all 3 times goes to the flaky-test record (Flaky tests, above) and files nothing. For the
cases that fail alone, Conveyor files one issue of the pack's second priority that names them, their failure lines and
the commits since the last pass, and the Board lists it under Needs you until a run passes. When that text is longer
than GitHub accepts, its end is cut, so a long list of cases can push the failure lines and the commits out of it. A
later failure of the same cases adds a comment to that issue while it is open, and files no other. A run whose failed
cases all pass alone counts as a pass.

A run that names no failing case but prints under 90% of the `ok <case>` lines of the last run that passed does not
pass: its issue says "ran N of about M cases" and shows the end of its output, and the last pass stays as it was.

## The test-speed survey

Test times taken on a busy machine swing two to three times from one run to the next, and a project's slowest lists
go stale as tests are added. So once a month the loop (`serve`) files one issue for the project, "Test-speed survey,
<month> <year>", at the pack's second priority, on the first day of the month in the machine's quietest hour. The
loop picks it only in that hour (on the 1st, or a later day when it had no room for it then), and its card measures
first, so its measurements start while the machine is quiet. Its card:

- runs each of the project's test files alone, one after another, each in one of the machine's test slots, and
  records each file's clock seconds and CPU seconds (user plus system, of the run and all it started), in its report
  and in `.conveyor/test-times.json`;
- rewrites the project's slowest lists and its survey report: every test
  file with its clock and CPU seconds.

It changes no test. It is a card, not a whole-suite run on main: the whole test on main (above) runs
only on its own schedule.

The settings, in the pack's `test`:

- `survey`: `true` (the default) files the survey; `false` turns it off, and no survey issue is filed.
- `surveyHour`: the hour, local time, 0 to 23 (default `3`: from 03:00 to 03:59), in which the issue is filed on the
  1st and the only hour in which its card is picked. The loop looks once a minute; one that is not running at any time in that hour files none that month.

The state folder's `survey.json` keeps the month of the last survey filed and its issue, so a month gets one survey
whatever the loop's restarts; one GitHub did not take is filed at the next look within the hour.
`conveyor.sh survey` makes the same look by hand.

### The first survey

Setup asks "Run a first test-speed survey now?" (yes or no) while the pack has no saved answer, and saves the answer
as the pack's `test.firstSurvey`. Yes files one issue, "Test-speed survey, first", of the same kind and picked only in
the same hour: its card measures every test file alone (clock and CPU seconds) and writes the report as above, and
names in it, for the Foreman to file as cards, each shared helper the
measurements point to (a slow library call many files repeat, a costly fixture, a runner setting). No files none.
Either way the monthly survey still runs unless `test.survey` is `false`. Setup run again does not ask again; to run a
survey later, run `/conveyor-belt:setup --survey`, or `conveyor.sh setup --survey yes` from a shell, which files
another first-survey issue.

### The test-speed rules

Every project's cards and reviews get the plugin's general test-speed rules, with no setup: the "Keep tests fast"
section of the core card rules (`conveyor/rules/card-core.md`): no wrapper that only runs other tests again and no second case of one behaviour;
one fixture, render or build per file where the cases allow it, and a case that runs several fixtures one after another
split into one case per fixture; the project's shared fast test helpers rather than the slow real thing, unless the
test is about that thing, and the function called rather than the whole program run when only the function is under
test. The helpers themselves depend on each project's stack, so the survey finds them per project.

## The full test suite

A project's full test suite is its pack's `test.full`, which `setup` sets to the test command in a new pack; a pack
that names none has none, and the Board shows both of
its buttons disabled with that reason. It runs only when asked, from the Board's Control tab (`conveyor.sh full-test`),
on main as it is at that moment, in a worktree of that commit alone and on one of the machine's test slots. Cards keep
landing while it runs. One run at a time per project: a second press while one runs is refused and says so.

- **Run full test suite** (`full-test`) runs it and shows the result, passed or failed with each failed case, and
  pushes nothing.
- **Push landed** (`full-test push`) runs it first. Green: every landed commit of the commit it tested is pushed at
  once, through the same push and checks a card's push uses, and never a commit the run did not test (one that landed
  during the run waits for the next push); the Board says so. A remote whose main holds a commit the tested one lacks
  (one made there by hand) refuses it, and it is not merged and pushed again as a card's push is: that merge is a
  commit the run did not test, so nothing is pushed and the Board shows the push failed and why. Red, when each
  failed case passes alone each time (flaky): the commit it tested is pushed as on green, and the result says
  "Flaky". Else red: nothing is pushed; press Push landed again once main is green. A press with no landed commit to push is refused.
- **Push anyway** (`full-test anyway <run id>`), beside a red result: after a confirm that names the failed cases, the
  commit that red run tested is pushed with no new run, logged (`fulltest.jsonl` in the state folder) as the owner's
  push over a red suite, with the Board user who confirmed it. The Board sends the id of the red run the confirm named;
  when a later run has ended since, nothing is pushed.

A release's suite runs its test files one by one or in parallel. `release-prep` and `release-run` take `--serial` or
`--parallel` for the run. With neither, they use the control record's `suiteMode` (`conveyor.sh control suite-mode
<serial|parallel>`, or **Release suite mode** on the Rules tab), which is `serial` in a record that sets none. The
record's `mode` keeps the mode the run used.

When main has no `docs/releases/<version>.md`, `release-prep` writes a notes draft and runs no suite. A draft that
passes the notes style check goes to main as a card with no GitHub issue, which adds the draft as it is. The run's
record then has the state `waiting` and names the card in `notes`. The Board's Release panel shows the notes step in
progress, with the card. Once the card has landed, its commit is on the branch the suite tests and no other card is
open, `serve` starts the run again with its own mode and machine: `release-run prep <version>`, or `release-run
<version>` when the release was asked for, which goes on to `release` after the suite passes. A mode not given then
is the control record's `suiteMode`. A second run of the same version while the card is open starts no second card and writes no new draft.
When the card is closed before it lands, nothing starts again, and the next run writes a new draft.
A draft that still breaks the style after its rewrite stops the run as `refused`, with the check's lines as its
reason, and starts no card.

Run full test suite, Push landed and `release-prep` keep one record of results for each commit (`suites.jsonl` in the
state folder): each test file's ok or fail, with the commit, the time and the run that made it. Each of them reads
that record before it runs:

- A run passed every file on the same commit: no test runs, and the result is green. Push landed pushes at once. The
  Board says "Reused the green run of <time> on <commit>".
- A run is on an ancestor of the commit (with more than one, the nearest ancestor): only the files that failed in it,
  the files that the commits since add or change, and the files that the changed-tests command (`test.command`)
  selects for those changes run. Each other file keeps its ok. The Board says how many files reran.
- There is no such run, or the commits since change the pack's test settings (`test.*`) or a file that their suite
  commands (`test.full` and `test.wholeCommands`, not `test.command` or `test.changed`) name (for example
  `.conveyor/test-full.sh`): the whole suite runs.

Push anyway does not read the record: it pushes over the red run with no new run.

A red run's failed cases are each run alone three times on the same commit (the command is told, in its
`CONVEYOR_TEST_RERUN` list, that every other file passed and which case of the file to run: a command that ignores the
list runs its whole selection. `.conveyor/test-full.sh` runs only the named case of an engine case file or a node test
file; it runs a Python or other shell test file whole, and the whole suite when the red run timed out) and judged as the
nightly whole test judges them:

- passed alone 3 of 3: flaky, an entry on the flaky-test record (source `full test <commit>`).
- failed alone (1 or more of 3), and each run that failed timed out, was killed or failed with words of the machine or
  the network (a refused or lost connection, a name not resolved, no disk space or quota, no memory): outside the code,
  recorded as declined with that reason.
- failed alone in the code: a fix card, an issue at the pack's second priority (P1) with the failure line, its runs
  alone, and the landed commit that plausibly caused it (the case is run alone once more at the commit origin has: when
  it passes there, the newest landed commit that changed the case's file, else the newest landed commit), or that it
  was already failing before them (it fails there too, or no landed commit is unpushed). While the issue filed for the
  same case is open it is reused, with a comment, never a second one.

The Board lists each failed case and what was done with it.

## Test actions

A test action asks a model about one test file of the project, in one headless session that needs no code review
and files no issue (or runs the file by hand, with no session: `testaction run`, below):

- `conveyor.sh testaction judge <test file>`: is the file worth its cost? The session answers keep, speed up, split,
  merge with another file (it names that file), delete, stabilise, or indirect, with its evidence, and ends with a line
  `VERDICT: <keep | speed up | split | merge | delete | stabilise | indirect>`. Indirect is for a file that checks
  what it protects through a proxy: it runs other test files or the suite runner, runs the real loop, or waits for a
  real process with a poll. The session names each proxy part on a line
  `DIRECT: <what it protects> | <the direct check> | <the cases that must keep passing>`. Stabilise is for a file whose failures with the
  verdict flaky or main have a cause in the test: shared state, timing, order, environment or a fixture. The session
  names the cause of each failing case on a line `CAUSE: <case> | <kind> | <one-line reason>`. The kind is
  `shared state`, `timing`, `order`, `environment` or `fixture`. Before that line it names each hollow case of the file, a case
  that passes but proves nothing, on a line `HOLLOW: <case> | <kind> | <one-line reason>`. The kind is `mock-echo`
  (it only checks that a mock gives back what it was told to give), `text-only` (it only checks that a file contains
  some text), `no-assert` (it has no assertion) or `defined-only` (it only checks that a value is defined or truthy).
  When the recent runs of the file took more than 2 times their CPU seconds on the clock, it names each wait on a
  line `WAIT: <case> | <kind> | <file:line> | <one-line reason>`. The kind is `sleep`, `polling`, `timeout`, `lock`,
  `network` or `other`.
- `conveyor.sh testaction explain [--time <zone> <12-hour | 24-hour>] <test file>`: which card made the file slower,
  and what in its change is the cause. The times in its facts are in the time zone and on the clock that `--time`
  names (the Board sends those of its browser and its Time setting); without it, in this machine's time zone on a
  12-hour clock.

The test file is a path of the repo as main has it. The session runs on the Tests seat of the control record: a CLI
installed on the host, a model and an effort, set by `conveyor.sh control tests <cli> <model> [effort]` as the other
seats are (any model name, listed by that CLI or not; an effort left out is medium). With no Tests seat set, the
command starts no session and says why (exit 2).

The session is given the file; its recorded times, from the test lines of the card records (`times`, `timed` and
`slow`); the cards that ran it; its entries on the flaky-test record; and its 5 newest failed test steps, each with
its verdict (card, main, flaky, or none on record), its card, its failing cases and the end of the step's output. It may read the repo: it runs in a copy of
main as it is at the ask (a worktree under the cards folder, removed when the session ends), whose files it cannot
write. It may not write to the repo, file an issue or change state: a Claude session has only Read, Grep and Glob, a
Codex one its read-only sandbox, an OpenCode one the review's read-only agent, and the `gh` first on its PATH refuses
every call. The command returns the action's id once the session has started, or once it is queued.

At most 3 test actions run at once: sessions and runs by hand (`testaction run`, below) together. The command takes
each ask. When 3 actions run, it keeps the new ask as `queued`. When an action ends, the oldest queued ask starts.
`conveyor.sh testaction stop <id>` takes a queued ask off without starting it; its record says stopped. An ask that
cannot start (its copy of main cannot be made) is failed, with the reason.

Each action keeps two files in `testactions/` of the state folder, which stay after the session ends:

- `<id>.txt`: the session's text, written as the session writes it, so the Board can show it while the session runs.
- `<id>.json`: its record: `id`, `action` (judge or explain), `file`, `project`, `commit` (the commit of main at the
  ask, which the session reads, also when it is queued), `start` (the time of the ask while it
  is queued, then the time it started), `asked` (the time of the ask, in microseconds since 1970, which orders the
  queue), `end` (null while it is queued or runs), `state` (queued, running, done, stopped, failed or timed out), `cli`, `model`, `effort`, `limit` (the time limit, in
  seconds, so the Board can show time used against it), `verdict` (judge: the verdict word, or `no verdict` when the
  text's last line names none; explain: null), `hollow` and `hollowSkipped` (judge: its `HOLLOW` lines as
  `[{case, kind, reason}]`, and how many lines that start `HOLLOW:` could not be read, with no case, no kind of the
  four or no reason; such a line is left out and fails nothing), `causes` (judge: its `CAUSE` lines as
  `[{case, kind, reason}]`; a line that cannot be read is left out), `waits` (judge: its `WAIT` lines as
  `[{case, kind, at, reason}]`, `at` the file and line; a line that cannot be read is left out), `pid` while it runs,
  and `reason` for a failed one.

`conveyor.sh testaction stop <id>` stops that one running action, and no other; its record says stopped. One time
limit applies to every action: the pack's `tunables.testActionTimeout`, 900 seconds by default. An action that runs
past it is ended, and its record says timed out.

`conveyor.sh testaction run <test file>` times one test file now, with no card: is it slow, or was the machine busy?
It is an engine command, not a session, so it needs no Tests seat. It runs the file alone through the pack's
`test.fileCommand`, on main as it is at the ask, in a worktree of that commit (removed when the run ends), on one of the
machine's test slots: it waits for a slot as a card's test step does, and holds one slot while it runs, so cards wait
on it no more than on a second card. The run's `CONVEYOR_TEST_RERUN` list names the file alone, as a `fail` line
with no case: `test.fileCommand` runs that file and no other. A path that is not a test file of main
(a file whose own name has `.test.` or `.spec.` in it, or a file the pack's own `tests.patterns` match; a helper or
fixture in a `__tests__` folder is not one) is refused (exit 2), and nothing runs. The
command returns the action's id once the run has started, or once it is queued. Its `<id>.txt` is the command's output, written as the
command writes it and kept when the run ends. Its `<id>.json` holds `id`, `action` (run), `file`, `project`, `commit` (the commit of main at the ask, which it runs, also when it is queued), `start`,
`asked`, `end`, `state` (queued, running, done, stopped, failed or timed out), `load` (the machine's 1-minute load at the ask),
`limit` (the pack's `testTimeout`, the seconds the run may run once it has its slot, as a card's test step),
`result` (pass or fail; null until it ends, or when it did not run), `sec` (the file's clock seconds, as its runner
timed it, else the command's), `cpu` (the file's CPU seconds; null when its runner gave none), `wait` (the seconds it
waited for its slot), `pid` while it runs, and `reason` for a failed one. `conveyor.sh testaction stop <id>` ends it,
and every process it started, and frees its slot; its record says stopped.

`conveyor.sh testissue <test file> <title> <body>` is the Board's File an issue about one test file: it files the
issue through the GitHub write path, with the pack's type and its last priority, prints its address, and keeps
`{time, event: "filed", file, issue}` in `testactions/filed.jsonl`, so the file's row has the issue and its Close its
issue as done. A file main does not have, a title of more than one line, or an empty body files nothing and exits 2.
The Tests page files an Optimize issue with it: its title starts "Optimize the test file <file>", and its body holds
the file's numbers, its hollow cases and the newest verdict of Judge this test, with its text (above, Bug cards: the new tests fail
without the fix, for the check of its card). It files a Fix failures issue the same way: its title starts "Fix the
failures of the test file <file>". The bug-card check does not apply to such a card. The file runs alone 10 times in
a row with the change, each run on a test slot. When one run fails, the card is blocked before its review, and the
reason names that run and its failing cases. The review is shown the result.

The Tests page files five more issues about one test file the same way. The bug-card check does not apply to their
cards either; each has a check of its own, and the review is shown its result:

- Fix hollow cases, "Fix the hollow cases of the test file <file>": its body names each hollow case on a line
  `- HOLLOW: <case> | <kind> | <reason>`. Before the review, a case whose name no case line of the file holds any
  more is deleted. It needs a line `COVERED-BY: <test file>: <its case> | <the deleted case>` in the build's reply,
  or in the reply of a later fix session, that names a test file the change keeps. Then the hollow check of Judge
  reads the file with the change, in one read-only session. It runs on the reviewer's seat or the review judge's
  seat, the first of them on another CLI than the builder's, and else on the reviewer's. Its answer ends with the line `HOLLOW-CHECK: done`. The card is blocked
  when a deleted case has no such line, when the answer names a hollow case (the reason names each one), or when the
  check cannot run or its answer is cut short.
- Fix the waiting, "Fix the waiting of the test file <file>": the file runs alone 3 times in a row with the change,
  each run on a test slot. Each run must pass, and its clock seconds must be at most 2 times its CPU seconds (the
  `TESTRUN sec` line of its runner). When a run does not, the card is blocked, and the reason names that run.
- Make it run, "Make the test file <file> run": a change that removes the file is blocked. After the card's Test step
  passed, the step must have passed the file or one of its cases; else the card is blocked.
- Delete it, "Delete the test file <file>": a change that keeps the file is blocked. A change that removes it is
  checked as an Optimize delete: the review names a `COVERED-BY` line for each of its cases.
- Make it run alone, "Make the test file <file> run alone", for a file `test.files` marks `wholeOnly`: the pack as
  the change leaves it (main's own when the project does not track `.conveyor/project.json`) must no longer mark the
  file `wholeOnly`. Then the file runs alone with the change, on a test slot, through `test.fileCommand`. It must
  pass, and the run must show that the command ran the file. The output must name a case of the file that passed,
  with the name in the file's text, or the runner must give the file's time. A `-- ok` line does not show this. A time
  from Record CPU time shows it only when the change keeps the `test.fileCommand` of main. A change that removes the file runs the test
  files it adds or changes in its place. The card is blocked when the mark stays, when the pack sets no
  `test.fileCommand`, or when the run fails or does not run the file.

The checks of Fix hollow cases, Fix the waiting, Delete it and Make it run alone run again before each later review when a fix or rebase
session changed the card. When a check no longer holds, the card is blocked with its reason.

The snapshot's `testActions` holds `seat` (the Tests seat, or null), `limit` and `actions`: the records of the 20
newest actions, running and kept, and of each file's newest older judge with a verdict, newest first; the other
records stay in the state folder. Each also has `text`, the last 16,000 characters of its `<id>.txt` as it is at the
snapshot (null when there is none), and `textCut`, true when that left the start out. So the Board's Tests page shows
the text as it comes, and each result it lists has its text after the action ends and after a reload.

## Mutation checks

A mutation check asks: does a test file fail when the code it tests is wrong? It makes small changes (mutants) to
the source files the test file covers, runs the test file on each one, and records which mutants the test file
caught. Mutation checks never run in a card's steps, and never slow a card's test step.

`conveyor.sh mutate <test file>` checks one test file of main now. A path that is not a test file of main (a file
whose own name has `.test.` or `.spec.` in it, or a file the pack's own `tests.patterns` match) is refused (exit 2), and so is a second check while one runs. One
check:

- It finds the source files the test file covers: the files it imports (JavaScript or TypeScript: `from`, `import`
  or `require` of a path that starts with `./` or `../`) or sources (shell: `. <path>` or `source <path>`). When it
  finds none, it takes the files whose name is the test file's name up to `.test.` or `.spec.`. A test file is never
  a source.
- It makes up to 20 mutants, one line each, chosen at random with a seed that it records. The kinds are `flip` (a
  comparison flipped: `<` and `>=`, `>` and `<=`, `==` and `!=`, `===` and `!==`, `-lt` and `-ge`, `-gt` and `-le`,
  `-eq` and `-ne`), `negate` (an `if` condition negated), `number` (a number constant made one more), `andor` (`&&`
  and `||` swapped) and `delete` (a call statement deleted). The rules are plain text rules for shell, JavaScript and
  TypeScript, with no parser and no added dependency. A source of another kind is recorded as not mutated.
- It runs in a copy of main's commit (a worktree under the cards folder, removed when the check stops or ends). It
  first runs the test file with no mutant. A test file that fails then says nothing about its mutants: the check
  ends failed. Then, for each mutant, it changes that one line, runs the test file alone through the pack's
  `test.fileCommand` on a test slot, and puts the line back. No other test file runs with it, so only that file can
  catch the mutant. The result is killed (the test file failed), survived (it passed) or no result (it timed out, or
  did not run).

A mutant starts only when no card of the project is in its build or test step, no test run of any project on the
machine asks for a test slot or holds one. When a card of any project goes into its test step, which asks for a
test slot, the mutant that runs is stopped at once, with every process it started, and its slot is free for the
card. The check then stops. It resumes later from its next mutant, on the same commit and with
the same mutants.

`conveyor.sh serve` keeps an idle queue of test files to check, and looks at it once a minute when no mutant is held
back. A check that stopped resumes first. Then come the files asked for with `conveyor.sh mutate ask <test file>...`
(the Board's Mutation check), the newest ask first: an ask starts no check, and a path that is not a test file of main
is refused (exit 2), with nothing asked. A file leaves that list when its check starts. Then the queue goes in this
order: the files the Tests page flags (Never
caught anything, or hollow cases), then the files checked longest ago. A file never checked comes before a checked
one. A file leaves the queue when it is checked, and comes back when the test file or one of its sources changes on
main. When the queue has nothing left, the loop does nothing more until main moves.

Each check keeps its record in `testactions/mutations/<id>.json` of the state folder: `id`, `action` (mutate),
`file`, `project`, `at` (its start), `sha` (the commit of main it checks), `seed`, `state` (running, stopped, done or
failed), `reason` (why it stopped or failed), `base` (the run with no mutant: pass or fail; null before it), `next`
(the next mutant to run), `mutants` (each `{source, line, kind, before, after}`), `tried`, `killed`, `survived` (each
mutant that survived, as `{source, line, kind, before, after}`), `noresult`, `notMutated` (the sources of a kind the
rules do not read), `blobs` (the test file's and its sources' blobs at `sha`), `pid` while it runs, and `end`. The
snapshot's tests part, and so the Board's, carries each file's newest check as `mutation`, its place in the asked
list (`testactions/mutations/asked`, 1 first) as `mutationPlace`, and, for each landed Optimize issue of the file, the
newest check that ended done before it landed and after (`mutantsBefore`, `mutantsAfter`: `{at, killed, of}`).

## Same-file cards

Cards that share a file are reviewed in parallel; they line up only to land. After its review, before it lands, a card
claims the files its change names, documentation files (`README.md` and any other `*.md`) left out: a documentation
file never makes one card wait for another, whatever their edits to it. Two cards that share a file overlap only when
their changes do not apply together: a card whose change merges three-way (`git apply --3way`), with no conflict left,
onto main with the other card's change already merged there does not wait on it, so changes to different parts of one
file land in turn without waiting, each tested on main as the one before left it. Two cards that change the same lines
of a file still wait, one behind the other. With batches on, a ready card also waits for the landing turn, on any
files (the queue, below). A card waits while a card it overlaps holds one of those files, then goes
on from main as it is then. A ready card lands first: a card whose review gave a GO and whose tests passed on main does
not wait for a card it overlaps that is still in its tests or its fix, even one picked before it. When both are
ready, the card that became ready first lands first. The card that was passed is then put on main with the landed
change, as below: it is reviewed again only when a session had to fit it, and it runs again only its test files that
the landed change touched too. A card in `order` still goes before a card that is not in it. Its change is put on main with a plain apply, or, where that fails, with a three-way
merge: when either leaves no conflict it goes on to its tests and lands with no rebuild session and no second review
(the merged change's own added and removed lines are what was reviewed and tested; only the lines around them moved).
A merge counts only when it leaves those same lines: a change main holds already merges to nothing and does not.
Test files are merged by keeping both sides: where the merge leaves a conflict in a test file the change names (a path
holding `__tests__`, `.test.` or `.spec.`), that file is merged again keeping main's lines and then the card's (git's
union merge), so two cards that both add a case at the end of one test file both land, with no session, in every
project and with no setting. It counts when no conflict is left, in a code file either, and the card's lines outside
its test files are the same. Its changed tests, those test files among them, then run once more before it lands, as
its earlier pass no longer counts: two edits to one test that do not work together fail there and send the card to its
fix.
When the merge leaves a conflict and the judge is on in the control record, the fast resolver tries first: one judge
call (the judge seat, no tools) gets only the conflicts, each with its base and a few lines around it, and answers with
the merged text of each. It counts when no conflict marker is left, only lines inside the conflicts changed and a change
is left. The merged files are checked to parse and the card's tests run on them before it lands, with no fitting
session and no second review. When the answer does not count, or the call fails, the session below fits the card, as before.
Only when the merge leaves a conflict that the fast resolver does not fit (an earlier landing changed the same lines,
of a documentation file too), or does not leave the card's change, does one session bring it onto main, and it is reviewed again; unless the clash is in
documentation files (`*.md`) alone (a README: the change outside them still merges onto main) and that session left the
change outside them as it was reviewed: then its review and, when they passed on that change, its tests stand, and only
its product checks run before it lands. Landing is one card, or one batch of cards (below), at a time.

After any merge at landing (a clean three-way merge, a union merge, the session that brings a card onto main, or the
landing's rebuild or port), every file the merge changed is checked to parse before any check or test runs: git can
call a merge clean that keeps two edits of one line, and a file no selected test loads would land broken. `*.js` and
`*.mjs` are checked with `node --check`, `*.sh` with `bash -n`, `*.json` with `jq empty` and `*.py` with
`python3 -m py_compile`, in every project. The pack's `land.parse` adds more, a glob to a command run in the worktree
with the file's path added after it (`"land": {"parse": {"*.rb": "ruby -c"}}`); a glob there
that is one of these replaces its command (`"*.js": "true"` turns the `.js` check off). A file that fails sends the
card to one fix session, given each such file and its error, and nothing lands; still failing after it, the card
blocks.

Cards ready to land land in batches. A card is ready once its review gave a GO and its own product checks and changed
tests passed: a card that waits to land runs them while it waits, holding nothing (failing tests send it to its fix and a
failing check blocks it, as at its turn; a lint finding or execution error before them runs none and leaves it not
ready, for its landing gate at its turn), and the card whose turn comes runs them first. When a ready card's turn to land comes, it takes the
landing turn, then the other ready cards waiting to land that are queued for the next batch (on any files) or share a
file with it, or with a card taken before (in turn), up to the pack's
`landBatch` (8 by default; 1 turns batches off), and holds the files of them all until the batch lands: a card that
is not ready and changes one of those files waits on it only when its change does not apply together with the whole
batch's, and a ready card waits on it whatever files it changes. The queue: one card at a time has
the landing turn, from its claim as a ready card or from when its batch forms, through its batch's run, until it
lands, gives way, waits at its claim, blocks or fails a run. A ready card that finds another card with the turn, at
its claim or when its own tests passed, is queued: it waits on that card, holding nothing, tests and lands nothing
meanwhile, and the next batch takes it. The batch is
in `order` first, then by when each card became ready, the card whose turn it is among them; a stacked card (below)
goes after the card it is stacked on. Their changes are applied
one on another in that order and tested once. That run reuses each card's passed tests: it
does not run a case that a card passed on its own change, unchanged since (the same patch-id as when it passed), when
no other card of the run selects that case, nor a case the last batch run that passed passed for cards still in this
one, on their unchanged changes (a batch formed again after a card of it left, or main moved). It runs the cases no
card has passed: the cases two or more cards select together, and every case of a card whose change changed since
its pass. A batch with no such case left runs nothing and passes. The command is told what to keep in the same list
as a run again (`CONVEYOR_TEST_RERUN`, The test step, above): `pass` and `ok` lines for the passes kept, `changed`
lines for the files of a card whose pass no longer holds; what a card's run passed is read from its logs, and a run
whose command writes none counts as one test, which every other card of the batch selects too. The test line of a
batch's run says how many cases it ran and how many passes it kept in `selected`: `cases` as the runner's log gives
it, or 0 when it ran nothing, and `kept`, the cases of the passes it kept, summed.
What this gives up: two changes that each passed alone can fail together in a case only one of them selects; the
whole test on main is the net. Green, main gets one commit per card, each with its own message and trailers, in one
move, and one push carries them; each card's landed line is its own, with `batch` naming the batch's cards. Red, the
batch is split, halves then single cards, until the card that breaks it is found: the others land, and that card goes
to its fix with that run's output, as when its own tests fail. Each run is of the pack's lint commands on the change of
the cards in it, then the product checks, then the tests; a lint finding, a lint execution error and a check that fails
are red runs. A missing lint tool lets the run go on. The card that the split finds for its lint gets no test failure
and no test fix: it leaves the batch, and it is not ready. The others land. The card is then fitted onto main as they
left it, and its landing gate gives it its fix session there, or blocks it (an execution error, or a finding still
there after that fix). The card whose turn it is, left alone after the other cards leave, lands with no second lint
run: its landing gate passed on that change and that main. A batch whose run passed lands on that run when
main moved meanwhile (a card on other files landed during it), with no second run, when no card of it has changed since
the run and its changes still apply, in its order, to main as it is now: the lint commands and the product checks run
again on the batch's combined change there before it lands, and a lint finding or execution error or a check that fails
is a red run: the batch is run again there and split, and the card that breaks it goes to its fix, or leaves the batch
for its lint, as above. When the cards that landed meanwhile touch a test file the batch touches too,
the batch is tested again on main as it is now before it lands. When the pack sets `test.changed`, that run keeps
the passes of its cards, and runs only the tests that both the batch's change and the landed change select. When it
does not, that run runs every test that the cards' changes select. A card of it whose
change no longer applies to main leaves the batch and is fitted afterwards; the others land. A batch
that does not land for another reason sends that card to its tests again, alone, before it lands alone. A card whose change does not apply on top of the
earlier ones, the card whose turn it is too, leaves the batch and is fitted afterwards, as a waiting card is. A card with follow-ups to file lands on
its own. The Board's Landed today panel shows a batch as one landing with its cards in it.

The turn goes to a card that is ready to land. A card that holds its files and has to be brought onto main, reviewed,
fixed or tested again first gives way for that time: it holds nothing, the cards behind it that are ready land
meanwhile, and it claims again once it is ready (its review and tests passed and its change applies to main), after
the cards that were waiting for its files when it gave way. The Board shows it as "fitting onto main (gave way to
#N)", N being the card that took its turn, or as "gave way to #N while fixing" when its tests failed and it gave way
for their fix; its live record names that card too (gaveWay). A card that has given way 3 times keeps its next turn,
but not while it waits for main to change when main is red.

With batches on (`landBatch` over 1), a card that would wait on a card that holds its files, and that it does not go
past once its own tests pass (a card whose tests passed first, or a card in `order`), does not sleep. It is
stacked on that card: its change is put on main plus the holder's change, with the one session it needs to fit there,
and it is reviewed and tested there while the holder goes on. When the holder's tests pass, the holder's batch takes
the stacked card after the holder, and both land in one batch. When the holder's tests fail, the stacked card waits no
more: it is fitted onto main alone, reviewed and tested there, and lands. When the holder goes to any other fix round,
such as a fix of its review findings, the stacked card does the same once its own tests have passed; until then it
waits. The holder is then fitted onto it after its fix. A stacked card whose checks or tests fail on the holder's change is not blocked or sent to a fix for that: it
waits, and runs them again where it goes next. When the holder's change changes after the stack, the card is stacked
again once; after that it waits on the holder. A card whose issue names the holder's issue in a `Depends on:` line is
never stacked: it waits.

A card's tests are not run again only because main moved. When main moved since its checks
and tests ran (while it was away, during its tests or before its landing), its change is put on main as it is then.
When it applies there unchanged, or merges there three-way with no conflict (the same added and removed lines; only the
lines around them moved), its product checks run again and it lands on the tests it already passed; a change a
session had to rework to fit is reviewed and tested again (not one it changed only in documentation files), and one whose test files were merged keeping both sides is
tested again. When the cards that landed since its tests ran select a test file that its change selects too, its
tests run again on main as it is now before it lands: two changes that each passed alone can fail together. A test
file counts for a landed card when that card's change selected it, not when it ran only because main moved. When the
pack sets `test.changed`, only the tests that both changes select run again, of the engine's runner the cases. When
it does not, each such test file runs again whole. A failure there
goes to the card's fix, and the card does not land. These tests run again once for each change. When they pass and more
cards land on the same test files before the card lands, the card lands with no second run. Its log line names the
cards that landed since. If the change no longer applies to main, it is fitted onto main as before. A failure of the
two changes together then shows on main, as main red.

A card whose issue is in the control record's `order` list does not wait for a card that is not in the list: it claims
the files and goes on to land while that card holds them. The card it went past waits for it at its own next claim
(before it lands), and is brought onto main and reviewed again if main moved under it, even
when its change still applies there. Two ordered cards never go past each other. Among waiting cards with no holder, an ordered card goes first, the earlier in
`order` first; otherwise the older pick goes first, except that a card whose change applies to main goes before an older
waiting card whose change does not and that is not earlier in `order`.

## Declined findings

A review finding that is not built is one line of `declined.jsonl` in the state folder: `id`, `time`, `card`,
`issue`, `finding`, `by` (who declined it: `code`, `judge` or `owner`), `why`, `kind` and `repo`. `kind` is the kind
of the reason: `claim wrong`, `cannot happen`, `fixed`, `rare case`, `not this change` or `other`. A line has no
`kind` when its reason has none. A finding declined again for the same card is the line it already has. With
another kind, or with no kind after one, that line takes the new `kind`, `why` and `by`, keeps its `id`, `time`,
`built` and `dismissed`, and gets two more fields: `ruled`, the time of the new ruling, and `was`, the rulings it
replaced (`time`, `by`, `why` and `kind`), oldest first. The owner
declines one by hand with `conveyor.sh declined add <card> <issue> owner <why> <finding> [<kind>]`.

The Board's Declined panel lists the lines of every project that are not dismissed, not built and at most 7 days old,
newest first, each with its reason; its count is of those. "Show every line" shows the rest too, each marked and
greyed, with a "Dismissed", "Built" or "Expired" tag beside its issue number. A review's declined count opens the panel
on that card's lines alone, dismissed ones too, tagged the same, with a "Back to the list" button. A line with 2 days
or less before it leaves the panel says when ("Expires in 1 d 4 h"). "File as issue", confirmed by a second click
(`conveyor.sh declined build <id>`), files the finding as an ordinary issue that names it, with no follow-up label, so it
is picked as any new issue is; the line keeps the issue's number (`built`), and a second ask files nothing. "Dismiss",
"Dismiss all shown (n)" and "Dismiss all (n)" (every line the panel counts, shown or not), in the panel's heading
and confirmed by a second click (`conveyor.sh declined dismiss
[--by <who>] <id>...`), take lines off the panel: each keeps who dismissed it and when (`dismissed`) and stays in the
list, so the reviewer is still told not to raise it when its kind allows that (below).

Four checks hold on every review of a change (`REVIEWT`, `lib/prompts.sh`): each test the change adds names the bug it
would catch; a test that only finds text in a source file, where the behaviour could be run, is a finding (one whose
one-line comment says no behaviour can be run, such as a stylesheet rule in a test with no layout, is not);
unrequested placeholder UI is a P1 finding; and a smaller change that fully solves the issue is a finding.

Every review of a change is told what not to raise, under "Do not raise these" after its instructions: the project's
stated limits (the section of the checkout's `README.md` headed `## Accepted limits`, its first 4000 characters) and
the last 20 declined findings the owner has not asked to be built, each as its reason and the finding. Only a line
whose `kind` is `claim wrong`, `cannot happen` or `fixed` is on this list. A line of another kind, or with no kind, is
not, and a finding raised again from it is judged again. A project with
neither is told nothing. The check of an ALREADY-DONE claim is not a review of a change and is not told.

## The snapshot

`conveyor.sh snapshot` prints one JSON record of everything the Board's live views show: what needs you, the belt,
the queue and the open issues, health, the day's and the week's totals of cost and metrics, and the newest of the
history. The Board's live feed reads it again with every change, and /units reads it too, so it is kept small: each
list that grows with every card that lands holds only its newest 20 entries (`landed`, `metrics.cards`, `cost.cards`,
`cost.unpriced` and `declinedRest`; `landedCount` is how many landed today and `landedUsd` their cost, which the
Board's Today figure shows), `branches` its newest 20 landed Fast-lane branches, and `pushedCards` its newest 100
pushes. Past those 20, `landed` also keeps a card still on the belt (its push or the close of its issue not done), and
`branches` the landing of each lane's change while the lane is left as it was, so the Board still says it landed.
However many cards land, a snapshot stays under 512 KB;
what is left grows with the cards open or blocked and the open issues, not with the cards that landed.

`conveyor.sh snapshot` prints the last snapshot at once. Its first three fields are `snapshotAt`, when that snapshot
was made, `snapshotAge`, its age in seconds, and `recordsNewer`. `recordsNewer` is true when the card records changed
after the snapshot was made, so its belt can leave out a card that started since. The Foreman does not call such a
snapshot idle. When the card records or `loop.json` changed after the snapshot was made, a fourth field, `recordsNow`,
gives what the card records and `loop.json` say now: `blocked`, each card the records hold blocked now, `waiting`,
each card that waits for your yes now, and `building` and `waitingCount`, the running loop's count at its last turn
(null when no loop runs). `conveyor.sh foreman status` takes its building count from `recordsNow` when the snapshot
has it. When `recordsNewer` is true, `conveyor.sh foreman status`, and the Board's Needs you and On the belt, say "as
of <time>, the belt has changed since" and take their blocked and waiting cards from `recordsNow`, and the Board takes
its building count from it too. When only `loop.json` changed, the Board shows the building count of the snapshot.
When no loop runs, the Board counts no card building. When a record line, the control record, a card's live record or the
list of issues changes, one process makes a new snapshot in the background and puts it in place whole. A reader does
not wait for it, and it does not get a part of a snapshot. `conveyor.sh snapshot --fresh` makes a new snapshot now,
prints it and keeps it. When a snapshot is already being made, it waits until that one is done. Then the calls that
waited make one new snapshot between them, and each prints it. A project with no snapshot yet gets its first one that way. The Board's Health panel and
/units show the age of a snapshot that is more than a minute old.

Every snapshot also writes those lists whole to `history.json` in the state folder, and `conveyor.sh history` prints
that file. The snapshot's `historySum` is a checksum of that file without the wait and run times of the Metrics cards. These times grow with the clock while a card is blocked or open. So `historySum` changes when an entry changes, but not when only the clock moves. The Board does not read it with the live feed: its Landed, Metrics, Cost and Declined panels ask the page
server for it (`GET /history`) at most once a minute while one of them is shown and not collapsed, and show the older
entries from it beside the live ones. The page server reads the history from the host again only when the ledger
changed: when a project's `historySum` or day changes. A dismiss or an issue filed from the Board makes the next ask
read it again too, with or without the live feed. Without the live feed, the page server keeps its copy for a minute. When the history did not change, the page server answers "not modified" and the panels stay as they
are. The Foreman's watcher asks for it when an issue it awaits is in neither `pushedCards` nor
`metrics.cards` of the snapshot, so a push past the cut still wakes it.
The snapshot's tests part keeps the newest 5 runs and test edits of each test file. `conveyor.sh history test <file>`
prints the older ones of one file. The Board's Tests page asks the page server for them (`GET /older`) when you open
the Timeline of that file. The Control tab's Landed today column shows the newest, and links to the Overview's Landed today for
the older ones.

## Belt 3D

The Board's 3D View tab (after Overview; `?tab=belt3d` opens it) shows a factory floor: one belt lane for each card
on the belt, with six pads (Build, Review, Fix, Test, Land, Push), each coloured by what happened at that step, and the
card's crate on the step it is in. Each lane has the card's number and title at its left and its live status at its
right: how many tests have run, with a bar, while it is in Test, else the time in its step. While a card is in Test and
runs one test file, its lane names the file by its short name: hover over the card or click it to see the full path. Stuck cards (blocked, or
waiting for your yes) are in red lanes below, with the reason. Four bays along the bottom hold the queued issues, those
waiting on another card (and on which), the held ones and the cards that just landed. The header strip counts each state
and each step. Hover a card for its full title; click it for its six steps and their times, its review rounds, why it
is stuck or what it waits on, and its cost. It reads the snapshot's cards and nothing else, and draws only while it is
in view; with motion off nothing glides and the belts stand still.

It draws with three.js 0.170.0 (MIT), vendored in `.claude/dashboard/vendor/three/` with its licence and each
file's sha256 in the README there, and fetched only when the panel is first shown: the page loads nothing from another
site.

## Foreman

The Foreman is a Claude Code session in a project's main checkout that watches that project's Conveyor and brings
the owner what needs them. Set it up once with `/conveyor-belt:setup --foreman`, then start it by typing
`/conveyor-belt:foreman` in any session in the main checkout: that session becomes the Foreman at once, and its
watchers start at the end of that turn. It stays the Foreman however it is continued or resumed (`claude --continue`,
`claude --resume`, an IDE, a session manager) and after `/clear` in it; nothing needs to be set.

The role also starts by itself. The plugin's SessionStart hook, in a new session (not a resumed or continued one)
opened in a project's main checkout, on the owner's machine or the host:

- when no session holds the role, or the session that holds it is gone, claims it for the new session at once and
  says so in one line;
- when another live session holds it, claims nothing, and the new session asks you by the picker, as its first act:
  "Session <short id> (started <time>, last active <time>) is the Foreman of <project>. Make this session the
  Foreman instead?". "Take over" claims the role, as `/conveyor-belt:foreman` does, and the other session's watchers
  stop; "Leave it" leaves it a normal session, and it is not asked again.

The holder is gone when no running Claude process holds its session id (Claude Code's `sessions/<pid>.json` under
`~/.claude`, or `CLAUDE_CONFIG_DIR`, names it and that pid runs), or when its transcript has not been written for 24
hours (a live Foreman's waiter wakes it at least every 23). A session in a worktree (a card's, a lane's, a
reviewer's) or one the engine starts for a card or a lane never claims or asks; a resumed or continued Foreman
session keeps the role.

There is one Foreman per project, never one for the machine. A Foreman holds one project's memory, rules, saved
state and decisions; one that watched several projects would mix them in one context and one memory, and would
manage both worse with every project added. So each project gets its own Foreman: run the same setup and
`/conveyor-belt:foreman` in that project's own checkout. A Foreman is woken only by its own project's Conveyor
(blocked cards, waits on your yes, stuck cards, push errors, idle, awaited issues), and keeps its session mark,
pending wakes, saved state, decision log (`rulings.jsonl`, the owner's picker answers and typed messages) and watcher positions in `foreman/` in that project's state folder (`conveyor.sh
state-dir`). The decision log is written on the machine the owner's session runs on, in the state folder of the
checkout that session is in, never in the plugin install: on the host that is the host file's `stateDir`
(`<stateDir>/foreman/rulings.jsonl`); in a checkout the host file does not name (the owner's own machine, when the
host is another) it is that checkout's own `conveyor/state/foreman/rulings.jsonl`, made on the first answer. Its open decisions are its project's own ledger (`.claude/metrics/decisions.jsonl` in that project's
main checkout): every question its picker asks becomes a row there. No picker is refused: there is no check for a
question that repeats an open decision, or one answered in the last 24 hours. It reaches you like any other; a repeat of an
open decision is that decision asked again, so your answer closes it and leaves no open row for the question. Its rules are `rules.md` in that folder, loaded at its start. Claude Code's own auto-memory is kept per checkout path, so a Foreman in a project's main checkout has
that project's memory; never point a Foreman at another project's memory or state. The Board still shows every
project on the machine: it is a view, not a Foreman.

`/conveyor-belt:foreman` in another session of the same project moves the role there, and the first session's
watchers stop; a Foreman in another project is untouched. `/conveyor-belt:foreman off` ends the role. A session that
was the Foreman and no longer is shows you one line saying so at its next start.

Linked projects, whose work drives each other (say a product whose workflow drives the development of a tool it
uses), may share one Foreman: list their record names together in the host file's `foreman.groups`, for example
`"foreman": {"groups": [["shop", "tools"]]}`. A record in no group has its own Foreman. A group's Foreman is claimed
in the main checkout of any of its projects, is woken by the cards of every project of the group and no other, names
the project of each item it is woken for, reads every project's decisions, and keeps one folder for the group, in
the first-named project's state folder, with the issues it awaits listed per project. A project is in one group at
most: groups that name a project twice are refused, as that project would have two Foremen.

Advanced: the launcher `conveyor.sh foreman` starts `claude` with `CONVEYOR_FOREMAN=1`, which makes its session the
Foreman too. When the Foreman's session is marked and its transcript is still there, the launcher reopens that
conversation (`claude --resume <id>`); with none, or with `conveyor.sh foreman --new`, it starts a fresh session,
which takes the mark.
