# How a card goes

Each open issue becomes one card. The card goes through Pick, Build, Review, Test, Land and Push. A review finding
sends it to a fix session and then to review again. A card that needs a person stops on the Board's Needs you, with
its work kept, until you retry or close it.

A card that is blocked with its work kept also shows as an open decision on the Board, once. The recommended option is
"Retry keeping the work": the loop gives the card back as `conveyor.sh retry <issue>` does. "Fresh retry" gives it back
as `retry <issue> --fresh` does, and the next card builds from nothing. "Leave it held" changes nothing.
The loop looks for answers after each wait of the `tunables.idle` setting in the pack, and acts on an answer then. If you
retry or shut the card by hand first, the loop closes the decision and takes no step.
A card stopped for your yes, and a main-red fix card, are not put as decisions.

When the nightly whole test files an issue for a test that fails on main and the issue is held, the held issue also shows
as an open decision, once. The recommended option is "Release it, first in the order": the loop puts the issue first in
the `order` list and releases it. "Leave it held" changes nothing. If you release the issue by hand, or close it, the
loop closes the decision.

## Cards with no GitHub issue

The Rules tab has five switches in **Done without asking**, group **Cards with no GitHub issue**. Each is Off by
default. Off, that kind of card files a GitHub issue, and the belt builds the issue. On, the kind starts its card at
once with no GitHub issue. Its record is only in Conveyor. The five kinds:

- **Tests page actions**: an action on the Tests page. The Board shows the card as "Tests page: <file>", with the
  title of the action. It is held to the same check as the issue of that action.
- **Foreman orders**: a change that you order the Foreman to make. The Foreman runs
  `foreman.sh ask <project> card <title> <body>`. The Board shows the card as "Foreman order".
- **Review follow-ups**: a finding that the review of a card files as a follow-up. The text of the card names its
  parent. The Board shows it as "Review follow-up of #<parent>". The card waits until its parent card has landed. A
  finding that names a file of the pipeline is held as its issue would be. If its parent card does not land, the
  follow-up is taken back, and the finding goes in the brief of the next card of the parent. A follow-up inherits the
  yes that the owner gave to its parent for a visible change.
- **Release fix cards**: the fix card for a red test file of a release suite. Its text has the line
  `Release fix: <version>`, which Conveyor reads as it reads the line of an issue. Once each fix card has landed
  and its change is in the commit the suite tests, the release suite starts again ([Fix cards of a failed suite](releases.md#fix-cards-of-a-failed-suite)). The Board
  shows the card as "Release fix".
- **Split parts**: the parts of an issue that Split large issues cuts into 2 or 3. Each part is a card with no GitHub
  issue, under the umbrella issue, which stays open and held. A part that depends on an earlier part has the line
  `Depends on: <card id>`. The Board shows each as "Split part of #<umbrella>". Conveyor closes the umbrella when each
  part card has landed or is already done on main. A part inherits the yes that the owner gave to the umbrella for a
  visible change. The parts of a change that grew past `split.growFiles` are still issues.

A review follow-up and a split part are follow-ups, so the Follow-ups rule in the Rules tab holds them back when it is
Off. `conveyor.sh run --only <issue>` also runs the review follow-ups and the split parts of that issue, and the review follow-ups of those parts. A follow-up of a split part names the umbrella as its parent, so it inherits the same yes.

Each card builds, reviews, tests and lands as any card does. No size check splits it.

- **Held**: a card that a Foreman session starts (a Foreman order, a release fix card) is held until you say yes. So are the parts of a held umbrella. `conveyor.sh control release <card id>`
  releases it, and the loop picks it in its turn.
- **Depends on**: a line `Depends on: <card id>` in the text of the card holds it until the card of that id lands or is
  already done on main. A line `Depends on: #<issue>` holds it as it holds an issue: until that issue is closed or its
  card has landed.
- **Never build**: a card with a label that the Rules tab sets to Never build (an area) is not started, as an issue with that
  label is not.
- **On a block**: Conveyor tries the card again one time, with its work kept. If it blocks again, it stays in Needs
  you with its reason. Retry and Close in Needs you use its card id, as `conveyor.sh retry <card id>` and
  `conveyor.sh shut <card id>` do. Retry starts the card again from its kept work. Close ends the card, and the action
  starts no card again.
- **On landing**: its commit message has its title, the text it came from and its card id. It has no `Closes` line,
  and a "Fixes #12" in the text goes in as "Fixes issue 12", so the push closes no issue. When the pack's
  `privacy.mode` is public, each part of the message that the privacy check flags (a home path in test output, for
  example) goes in as a mark of what it is, such as `<home path>`. A whole private key, from its BEGIN line to its END
  line, goes in as one `<token>` mark. **Landed today** keeps the
  record of the card, and its **File on GitHub** files an issue from it
  ([Board: Done without asking](board.md#rules)).

## Build

The card builds in a fresh git worktree. Claude build, fix and review sessions start without your account's connectors
(its MCP servers), so a card never sees your mail, drives or notes.

A Claude build or fix session cannot use the tools that schedule work, send messages or start other agents:
`ScheduleWakeup`, `CronCreate`, `CronDelete`, `CronList`, `Monitor`, `RemoteTrigger`, `PushNotification`,
`SendMessage`, `ListAgents`, `Agent` and the tool that runs a script of steps. It can still use `WebFetch` and
`WebSearch`. There is no limit on turns or on cost. The session ends at its time limit, or sooner when it makes no
progress for the pack's `tunables.stuck`.

A Claude build session that makes no progress, or that the model API refuses, continues once in the same session
(`claude --resume`). It does not start again with the whole brief. The card's line then shows `resumed: 1`. This needs
the session id in the session's output: a session that stops before it names its id starts again with the whole
brief. A build step resumes once at most. When the
build still fails, the blocked line names the cause in its `class`: `stall`, `api error` or `timeout`.

The card's guard hooks check each Bash, Edit, Write and AskUserQuestion call of a build or fix session. Each guard
hook that `onFailure: block` marks (all the guards of Conveyor, and each guard of `.conveyor/hooks.json` with that
field) runs behind Conveyor's guard runner. When such a guard fails to run, the runner refuses the call. The text that
the session sees names the guard and the cause:

- it crashed: the exit code and the last error line, for example `the guard git-safety.sh failed to run: it crashed with exit 1: <error>`;
- it ran past its time-out (the hook's `timeout` setting);
- its file is missing.

When the same guard fails a second time in one session, the session stops at once and the card blocks. The reason
names the guard and the cause, for example `build: guard git-safety.sh is failing: it crashed with exit 1: <error>`. The card
shows on the Board's Needs you with that reason, so you see `guard <name> is failing`. Repair the guard, then retry the
card.

No Claude session of a card uses Claude Code's auto memory. A card does not read notes that an earlier card kept, and
it keeps no notes for a later card.

When the issue has a `## Done when` section, Conveyor checks the build or fix session's reply before the review. The
reply needs a `D<n> met:` or `D<n> not met:` line for each item. It must also name each TODO or [VERIFY] marker that
the change adds, on a line with its file. On the Board, open a card's `Done when` line to see each item: its text,
the builder's line for it, and the reviewer's answer when the review gave one.

A main-red fix card runs its cases on main before its build session. A case that fails in any of three runs keeps the
card going. When every case passes in all three runs, the card ends as `closed` with no session.

A main-red fix card whose session changes no file runs its cases again on main. When they pass, the card ends as
`closed`, and when they fail, the card is blocked. Any other build session that changes no file blocks the card with "the session made no change", unless
its reply ends with one of two lines:

- `ALREADY-DONE: <where it is fixed>`: main already does what the issue asks. A reviewer checks this against main.
- `DONE-OUTSIDE: <what it did and where the evidence is>`: the issue asks for no change to a tracked file, and the
  session did the work outside the repository, for example records in the state folder or issues it filed. A
  reviewer checks each `Done when` item against the evidence that the line names.

When the reviewer answers GO, Conveyor closes the issue and the card ends as `closed`, not landed. For
`DONE-OUTSIDE`, the issue's closing comment is the session's report, and the card's reason starts "Done outside
the repository". When the reviewer answers NO-GO, or gives no clear verdict, the card is blocked, and the reason
gives what the reviewer found.

Before a build, fix or review session starts, Conveyor checks that the CLI of its seat is on PATH. An update or a
reinstall can remove a CLI for a short time. So when the CLI is missing, Conveyor reads the host's CLIs again for
about two minutes. When the CLI is still missing, the card waits in its step and takes no build slot. The Board and
`/units` show the wait as `waiting for <cli>`. When the host's CLIs list that CLI again, the loop starts the step on
the card's kept work in its next turn with a free build slot. You do not retry the card. A seat set to a CLI that this
host never had blocks the card at once, and the reason names the seat and the CLI. A review that `conveyor.sh lane`
starts does not wait: after the two minutes, it fails with that reason.

A build, fix or review session can end with no turn and no token. Its CLI then stopped before any work. The card's
reason names the cause from the CLI's own error output: not logged in, a model the account does not have, a settings
error, or a CLI that is not installed. The reason also says what to do. Under it are the last lines of that output,
each cut short. Conveyor writes your home folder as `~`. It leaves out text that looks like a credential, and each
line that the privacy check's patterns find.

When the cause is the sign-in (it expired, it is missing or it was refused), the reason says so and what to run, for
example `build: Claude Code's own sign-in expired`, then `run claude /login (or set up the proxy route), then conveyor.sh
control resume`. A session through a proxy or the API names that route and its base URL instead, for example
`build: the proxy at http://localhost:4141 refused the call`, with the proxy's answer below. The loop pauses at that first card, so the next cards do not fail in the same way. Cards that already
started go on. The Board, `/units` and `conveyor.sh foreman status` show the pause with that reason. When you resume
(`conveyor.sh control resume`, or Resume on the Board), each card that the sign-in stopped goes back to the queue,
once for each issue. When the role has a working fallback route through a proxy (`claudeProxy` or `codexProxy`), the
step runs again on that route and the loop does not pause.

For any other cause, the loop runs a short check session on the same account, with the
CLI and model the builder or reviewer is set to at that time, at most once every `tunables.apiPause` seconds (the
pack, `.conveyor/project.json`). When the check session starts, for example after you set another model,
the card goes back to the queue. This happens once for each issue. A card that
stops again in the same way stays on Needs you until you retry it.

## Lint

When the pack has a `lint` field ([Lint](configuration.md#lint)) and the rule Lint check is on, the card's change goes
through a lint gate before each review, and through the landing gate (below) before it lands. The gate runs the pack's lint commands on the staged change. The brief of the build and fix sessions has a
`# Lint` section. It names the commands and tells the session to run `conveyor.sh lint` before it finishes.

- A pass lets the card go on. So does a command whose tool is missing: the card's lint line says
  `skipped: missing <tool>` for it.
- A command that main added with its script after the card's worktree was made, and that has files to check, is
  skipped while the card's tree does not have the script. It runs at the landing gate, on the card's change on main as it is now
  ([Lint](configuration.md#lint)).
- A finding on the card's change goes to one fix session. The session gets the first 50 findings and their count.
  Then the gate runs again. A finding that is still there blocks the card with the reason
  `lint: <n> findings left after its fix session; nothing landed`. The fix uses no review: the review of the same pass
  reads the fixed change. When the card is split for its size, the gate runs again after the split's fix session.
  A review that stood for the change, and a kept patch that you approved, do not stand after
  the fix: a new review session reads the change.
- Any other end of a command is an execution error. The card blocks with `lint: an execution error, so nothing
  landed:`, the command and the first line of its output. There is no fix session.

The landing gate runs the same commands each time the card is about to land: after the check that the files of a
merge onto main still parse, and before the product checks and tests. A merge onto main can bring a finding that the
gate before the review did not see. A pass, a missing tool and an execution error act as above.
When the gate passed and the card is then fitted onto a newer main, the gate does not run the commands again if main
changed none of the card's files, no file that a lint command reads for all changes, and not the pack's `lint` field.
The pass stays the card's lint result, and the card gets no new `lint` line.

- A finding goes to one fix session before any test runs. Its step is `Fix <n>: lint findings`. Then the card goes to
  a review, and that review is its last review: a `NO-GO` lands with follow-ups, or blocks if it holds a P0. The gate before that review does not
  run again on the fixed change.
- At the next landing gate, a finding that is still there blocks the card with the reason
  `lint: <n> findings left after its fix session; nothing landed`. If a different session (a test fix, for example)
  changed the code after the lint fix, a finding gets one new fix session.

With batches on, a card that waits to land after its `GO` runs its own product checks and tests while it waits. The
same lint commands run first, once in the wait. A pass and a missing tool let its checks and tests run. A finding or an
execution error stops them, with no fix session. The card is then not ready: no batch takes it, and the lint does not
run again while it waits. At its turn, its landing gate gives it its fix session, or blocks it on an execution error.

A batch runs the same lint commands on the combined change of its cards, before its product checks and tests. This is
true each time the batch is split, and when the batch runs again on main after main moved. A pass and a missing tool
let the batch go on. A finding or an execution error is a red run, and the batch is split to find the card that
causes it. That card gets no test failure and no test fix. It leaves the batch, and the other cards land. The card is
then fitted onto main, and its landing gate gives it its fix session there, or blocks it. If each of the other
cards fails or leaves, the card whose turn it is lands alone, with no second lint run, on the main where its landing
gate passed. On a main that moved, its lint runs again, and a finding sends it back to its landing gate.

The lint commands must not change the card's work. Before they run, the worktree must have no change that is not
staged, and no file that git does not track or ignore. If it has one, that is an execution error, and Conveyor changes
nothing. After they run, the staged change, the worktree and the untracked files must be as before. This is also true
after a command that ran past its time limit. If they are not as before, that is an execution error. Conveyor then puts
back the staged change and the tracked files, and deletes each new file that git does not ignore. Conveyor does not
check the files that git ignores.

Each gate run writes a `lint` line to the card's records, with each command's result and seconds. When the change
changed a trigger of a command that ran, the line says `tools ran as installed`: the tools ran as installed on this
host, not as the change would install them.

A change of lint policy needs your yes. Lint policy is each file that the pack's `lint.policy` matches, and the pack's
`lint` field ([Lint](configuration.md#lint)). When a review lets such a card land, the card stops with the reason
`lint policy: needs <owner>'s yes: it changes lint policy: <files>`, and the reason goes on the issue. If the card
also stops for a visible change, it stops only once. That reason then names the policy files too, and one yes
covers both. A change that only removes lines from a policy file that the `files` of a `ratchet: false` command
match makes a rule stricter, so it does not stop.

To approve, add a `Visible change approved:` line to the issue, as for a visible change. The next turn of the loop
then gives the card back. Its next card lands the kept patch with no build and no review. A retry with no new
approval line stops again, with no build. Your yes covers that one policy change. If a later session of the card
changes a policy file, the card stops again for a new yes. This stop is not controlled by the rule "visible changes
need the owner's yes". It waits for your yes when that rule is off too. To say no, hold the issue.

The rule Lint check is on by default. `conveyor.sh control rules lint=off` turns it off. Then no lint command runs in a
card, the brief has no `# Lint` section, and a change of lint policy does not stop for your yes.

## Review and the judge

A second model reviews each card, at most three times. Each finding has a level:

- P0: it breaks main, loses data or opens a security hole.
- P1: the change does not do what the issue asks, or breaks behaviour the project uses today.
- P2: a real defect with a limited effect.
- P3: a real but minor defect with no wrong result that users or the next card meet. While the rule `P3` is on, an
  accepted P3 is fixed and filed as a P2 is. Off, the card only lists it.

The `review.proof` of the pack (the project's settings, `.conveyor/project.json`) sets the proof that a finding
needs. `any`, the default, takes any proof that can be reproduced. `real` asks for a proof with what the project really
runs: its real config, commands and inputs. A finding with no such proof becomes an `UNPROVEN:` line, which never
holds the verdict. A security finding needs only a proof that can be reproduced.

A review after a fix gets the findings that the fix was told to fix and the findings declined so far. It says for each
earlier finding whether the fix holds. It raises a declined finding again only with a new, concrete reason.

### When the fix loop ends

After a `NO-GO`, a fix session fixes the findings, and the card goes to its next review. The first fix session of a
card runs at the effort of its seat. The second fix session of the same card, whether it fixes review findings or
failed tests, runs one effort level above the effort of its seat, and a fix session after it runs at that level too.
The level never goes above the highest effort that the pack's `pick.builder` list allows for the model, or above the
highest effort its program takes when the list names no range. A model with no effort, such as an OpenCode builder,
has no step. The loop ends at the first of these:

- `go`: a review says `GO`.
- `max-reviews`: the card has had three reviews. A card that starts from the kept patch of a blocked card also counts
  the reviews of that card and of the cards whose kept patch it took. It does not count the reviews of other cards of
  the same issue. After an automatic port of one of those cards, it counts only the reviews after the review of the
  port.
- `rebased`: the one review after a conflict with main at landing.
- `test-fix`: the one review after the fix of failed tests.
- `lint-fix`: the one review after the fix of lint findings at the landing gate.
- `land`: the card lands from a kept patch on its kept review, with no new review.
- `repeat`: a finding comes back after its fix, and each finding of the review is P2 or P3. A P0 or P1 that comes
  back blocks the card.

If a finding of the last review is a privacy hit in the card's own change, the card gets one more fix session. If a
last review after that session still holds such a hit, the card blocks and files no follow-up. If the
last review is a `NO-GO` that holds a P1 finding, the card also gets one fix session, once, and one more review of that
fix alone. If that review still holds a P1, the card blocks and files no follow-up, as it does for a P1 that comes back
after its fix. The findings that are still open when the loop ends become follow-ups. If the last review is a `NO-GO`
that holds a P0 finding, the card does not land and files no follow-ups. It blocks, and the reason names the P0. The
card's work and reviews are kept, so you can retry it. The review that ends the loop and the `filed` step
record the reason as `stop`, with `pass` (the reviews of this card) and `rounds` (the reviews of earlier cards). On the
Board, that review shows "Fix loop ended:" and the reason.

The judge, when it is on (`conveyor.sh control judge on`), reads each review and declines a finding that does not earn
its place. A declined finding causes no fix and no follow-up (`conveyor/README.md`, The judge).

A real defect that the card's change did not cause is never declined for that. The judge marks it `OUTSIDE`. The card
gets no fix round for it and lands as its other findings let it. When the card lands, the finding is filed as a
follow-up of the card, with its level and the card's issue as its parent, as a finding of a last `NO-GO` is. The
Board shows such a finding as "Filed as a follow-up" with its issue, and as "To be filed as a follow-up" until the card
lands.

A change can need a step when you deploy it: a migration before the deploy, a new environment value or a flag. The
reviewer writes this step as a `ROLLOUT:` line: the action, what fails without it, and its file and line. The builder
writes one as a `Rollout:` line of the card's commit trailers. A rollout action is not a finding. It does not stop the
card, and the judge does not read it. The card's commit message has each one as a `Rollout:` line, so the push carries
it, and the Landed today panel shows it under the card. The reviewer's steps come first, then the builder's, each in
the order it was written. When the pack's `privacy.mode` is public, each part of these lines that the privacy check
flags goes in as a mark of what it is, such as `<home path>`.

A test that a card adds or changes must check its behaviour directly. Some tests run other test files or the suite
runner, run the real loop, or poll a real process until a condition holds. Such a test needs a comment beside it that
says what a direct check cannot show. The reviewer raises a test with no such comment as a P3 finding.

A project lists what it knowingly lives with under the heading `## Accepted limits` in its own `README.md`. Every
card's reviewer reads that section and does not raise what it lists.

## Declined findings and follow-ups

Every finding that is not built is a line of the Declined list, with who declined it and why. The Board's Declined
panel lists them, and "File as issue" files one as an issue (`conveyor/README.md`, Declined findings). A line's reason
is in its own block under the finding, led by "Why the judge declined it" or "Why the code declined it". Each sentence
starts a new line, code shows in a code font, and a file and line in it opens that line on GitHub.

Findings still open after the last review become follow-up issues, which become cards of their own. Each follow-up's
body says how deep it is, as the line `Follow-up depth: N`: 1 for a follow-up of a first card, 2 for a follow-up of
a follow-up. Follow-ups go two levels deep. A card whose issue is at depth 2 files no follow-ups: its leftover findings
go to the Declined list, and the reason names the cap. A follow-up that changes one of the pack's `pipelineFiles` is filed held.
It builds only once you release it.

A finding whose fix changes no behaviour, such as a comment, dead code or a redundant check, has the mark `[cleanup]`
after its level, as `[P3][cleanup] file:line what`. Its follow-up is a cleanup, not a bug: it does not get the pack's
type label (`labels.type`), and its body has a `Cleanup:` line. Its card skips the build check of a bug card, so no
test must fail on main for it, and its review checks that the change keeps what the code does. A finding with no
such mark is filed as a bug.

The build check of a bug card does not block a change that changes only comments in its `.js`, `.mjs`, `.cjs`, `.ts`,
`.mts` or `.cts` product files, with or without a test file. Its result says the change is comments only, and the
review judges each changed comment.

When the pack's `privacy.mode` is public, a follow-up's finding is filed with each part the privacy check flags
replaced by a mark such as `<home path>`, and the issue says the text was masked. A last finding that the privacy check
flags in a line the card itself adds gets one more fix round instead of a follow-up.

## Tests

A card's tests run before it lands. When some cases fail, they run once more before any fix session. A card whose
re-run passes goes on with no fix, and the Board shows its Test step as "passed on re-run" (`conveyor/README.md`, The
test step).

Each failing case shows where it failed when the output has a stack trace after its failure line. Its line ends with
`(at <file>:<line>: <that line's text>)`. For a JavaScript stack, this is the first frame of the stack that is in a
file of the checkout. For a Python traceback, it is the last such frame. So an assertion with no message of its own,
such as `assert.ok(false)`, still shows the line that failed. A failed file whose output names no case, such as a
Python `unittest` file, shows the place of the first stack trace in its output. The push check and a release's suite
show the same, and a failed push check gives the place in its reason. The text of a line is not shown when the path
to its file goes through a symbolic link. The tests need no change for this.

The test fix session gets the failing cases first, each with its file and the place where it failed, and then the last
200 lines of the raw output.

A case that fails again runs on main. When it fails there too, Conveyor checks whether main or the machine is at
fault. Main is at fault only when an input of the case's test file changed since its last recorded pass, and a
control passed in the same run or no control could run. The controls are the test files that the pack's
`test.control` names. Otherwise the
machine is at fault: no "Main is red" card opens, and the loop picks no new card. The Foreman gets one wake that names
the files that fail. The cards with that failure wait in their Test step, "waiting for the machine". The Board shows
that step as "tests held: the machine", not as failed. When those files
pass on main again, the loop picks again and the waiting cards run their tests again (`conveyor/README.md`, The test
step).

A case that failed and then passed goes on the flaky-test record. `conveyor.sh flaky add <case> <source> <note>` adds
an entry from outside a card. A case with entries from three sources within seven days gets one issue, "Flaky test:
<case> fails at random". Until that issue closes, card test steps keep the case off. The full test suite still runs
it. The Board's Health panel has a "Flaky tests" line (`conveyor/README.md`, Flaky tests).

The full test suite of this repository, `.conveyor/test-full.sh`, runs each area file under `conveyor/tests/`. It
does not run the whole engine test, so each engine case runs once ([releases.md](releases.md)).

The whole test on main runs only for a project whose pack names `test.main` (`conveyor/README.md`, The whole test on
main).

## Landing

Cards that share a file land in turn, or together in one batch that is tested once. With batches on, ready cards on
other files land in one batch too ([How a batch lands](#how-a-batch-lands)). A card whose change still applies
to a main that moved lands on the tests it already passed, with no second run and no second review. Its product checks
run again on main. A change that had to be reworked to fit is reviewed and tested again (`conveyor/README.md`,
Same-file cards).

A ready card lands first. A card is ready when its review gave a GO and its tests passed. It does not wait for a card
that changes the same files and is still in its tests or its fix, even when that card was picked first. When two cards
are ready, the card that became ready first lands first. The other card is then put on main with the change that
landed. When its change applies there, it is not reviewed again, and it runs again only its test files that the
landed change touched too. When its change clashes, one session fits it onto main, and it is reviewed again before it
lands. A card in the `order` list still goes before the cards that are not in it. So the Board shows a ready card as
"waiting on card" only when the other card became ready first or is in the `order` list.

With batches on (the pack's `landBatch` over 1), a card whose change does not apply with the change of the card that
holds its files, and that will not go past that card, does not wait for that card to land. It is stacked: its change is put on main plus the other card's
change, then reviewed and tested there. When the other card passes its tests, the two land in one batch, the other
card first. When the other card fails its tests, the stacked card is put on main alone and lands first. When the other
card's change changes, the card is stacked again once; after that it waits. A card whose issue has a `Depends on:`
line that names the other card's issue waits.

### How a batch lands

With batches on, ready cards land through a queue, on any files. One card at a time has the landing turn. A ready card
takes the turn when no other card has it. While another card has the turn, a ready card does not test or land again.
It waits on that card, and the log says it is queued for the next batch. When the turn is free, the next ready card
takes it, with every ready card in the queue, up to the pack's `landBatch` cards. That is the batch. Their changes go
onto main one after another, and the batch is tested once on the result. When that run passes, all the cards of the
batch land in one move of main, each with its own commit.

When the run fails, the batch is split into two halves. Each half is tested on main with the cards that passed before
it. The split goes on until it finds the card that breaks the run. That card goes back to its fix with the output of
that run, and the other cards land. A run that fails ends the turn, so the queue does not wait for the fix.

## Push

By default, Conveyor lands each card and pushes when you press
[Push landed](board.md#push-landed-and-run-full-test-suite). Turn on the Rules tab's **Push on landing** rule,
and the loop pushes main on its own after each landing. Each push goes through the project's own pre-push hook.

The push closes the issue of each card that it carries. With **Push on landing** off, the issue of a landed card stays
open until you push. The Board and `/units` show it as "landed, not pushed", and the queue does not list it. A parent issue, such
as an issue that **Split large issues** split, does not wait for the push. The loop closes it when each of its parts
is closed or landed on main, and it removes the hold on it.

Before the loop pushes main, and before Push now, Conveyor runs the test files that the test map and
`.conveyor/test-links.json` link to the landings since the last push. Each file runs alone, once for each commit of
main. This run never runs a test runner or the whole suite. If a file fails, Conveyor runs that file on each landing
in turn to find the landing that broke it. Then it files a main-fix card that names that landing, and it holds the
push until main changes. Push landed pushes the commit that its full test run tested, so it skips this run. The run
needs `test.fileCommand`, or a `test.list` form that can give the test command one file. Without them, the push goes
on without the run. With `push.check` off, or the Rules tab's **Test before a push** Off, the push goes on without
the run too ([Which tests a card runs](configuration.md#which-tests-a-card-runs)).

Each push writes the pre-push hook's output, as it comes, to a log of its own: `pushlogs/<time>-<process>.log` in the
state folder (`conveyor.sh state-dir` prints it). Conveyor keeps the newest 20 logs. Push now also writes the path of
its push's log to `pushnow.log` in the state folder. While a push runs, the Board (under Push now) and `/units`
(under the belt) show the commit and what runs: the tests before the push, the wait for the push's worktree,
dependencies and test slot, the pre-push hook, the end of `git push`, or, after the remote has the commit, the wait
for GitHub. They also show the push's process, when that part started, the time it has run and the newest line of
the pre-push hook's output. When that output has a runner's `N/M passed` line, they show that line. When the
push's process is gone and the push did not end, they show the push as stale, with the path of its log. When the
push ends, they show if it passed or failed. A failed push shows the failed test (from a `FAILED <name>` line of the
output, else the pre-push hook) and the path of its log, on the card too. When the remote still does not have all of
main as it was at the end of the push, or Push now started no push, they say so. A push by hand that puts main on
the remote removes the "ahead" text.

A push that fails is one of two kinds:

- `check`: the pre-push hook failed (typecheck, tests, lint), or a test file failed in the run before the push. A retry fails the same way, so the loop wakes the
  Foreman and shows the hook's last lines on Needs you. It does not run the checks again until main's commit changes.
- `transport`: git, the network or the remote failed. The loop tries again every `tunables.pushRetry` seconds. Needs
  you shows it once a retry fails too.

When the pre-push hook fails and its output names test files as failed, Conveyor first runs each of those files
alone, once, on the same commit, with `test.fileCommand`, as a card's Test step runs a file. When each file passes
alone, Conveyor pushes the same commit again without the hook. The files go on the flaky-test record, and one
`flaky-test` issue for all of them is filed held. The Foreman's wake and the card's Push step on the Board say
"flaky: passed alone". When a file fails alone too, the push stays blocked as a `check` failure. The push also stays
blocked when the hook prints `FAILED <name>` for a check that is not one of those files, or names no test file.

A file whose flaky issue is still open gets a comment on that issue, not a new issue. A file recorded flaky twice
within seven days, after an issue was filed for it, is flaky again. When that issue is closed, Conveyor opens it
again, holds it and adds the comment "Flaky again since its fix #N". It does not file a new issue. The Tests page
shows "Flaky again since its fix #N" on the file's row.
