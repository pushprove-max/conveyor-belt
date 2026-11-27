# How a card goes

Each open issue becomes one card. The card goes through Pick, Build, Review, Test, Land and Push. A review finding
sends it to a fix session and then to review again. A card that needs a person stops on the Board's Needs you, with
its work kept, until you retry or close it.

A card that is blocked with its work kept also shows as an open decision on the Board, once. The recommended option is
"Retry keeping the work": the loop gives the card back as `conveyor.sh retry <issue>` does. Only your own answer releases a held issue:
your answer on the Board, or one given with `decision.sh answer <id> <answer> --by owner`. When auto or the Foreman gives the answer, a held issue stays held until you release it. "Fresh retry" gives it back
as `retry <issue> --fresh` does, and the next card builds from nothing. "Leave it held" changes nothing.
The loop looks for answers after each wait of the `tunables.idle` setting in the pack, and acts on an answer then. If you
retry or shut the card by hand first, the loop closes the decision and takes no step.
A card stopped for your yes, and a main-red fix card, are not put as decisions.

When the nightly whole test files an issue for a test that fails on main and the issue is held, the held issue also shows
as an open decision. The recommended option is "Release it, first in the order": the loop puts the issue first in
the `order` list and releases it. "Leave it held" changes nothing. If you release the issue by hand, or close it, the
loop closes the decision. If the issue is then held and open again, the decision opens again.
After an engine upgrade, the engine may not know if an older engine already acted on your answer. Then the issue stays
held, and the decision opens again with no recommended option. Auto mode does not answer it.

## Cards with no GitHub issue

The Rules tab has five switches in **Done without asking**, group **Cards with no GitHub issue**. Each is Off by
default. Off, that kind of card files a GitHub issue, and the belt builds the issue. On, the kind starts its card at
once with no GitHub issue. Its record is only in Conveyor. The five kinds:

- **Tests page actions**: an action on the Tests page. The Board shows the card as "Tests page: <file>", with the
  title of the action. It is held to the same check as the issue of that action.
- **Foreman orders**: a change that you order the Foreman to make. The Foreman runs
  `foreman.sh ask <project> card <title> <body>`. The Board shows the card as "Foreman order".
- **Review follow-ups**: a finding that the review of a card files as a follow-up. The text of the card names its
  parent. The Board shows it as "Review follow-up of #<parent>". If the parent card has no GitHub issue, the Board
  shows the branch of the parent card or its card ID in place of "#<parent>". A split part with no GitHub issue
  is the exception: its follow-up shows the number of the umbrella issue, as "Review follow-up of #7". The card waits until its parent card
  has landed. A finding that names a file of the pipeline is held as its issue would be. If its parent card does not land, the
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
  The hold on the umbrella is the split's, not yours: `conveyor.sh foreman status` and the Board show it as "held as
  the umbrella of a split: waits for <part card ids>". The list has the parts that are not landed, and a shut part
  has "(shut)" after its id. A part counts as landed only while main has its commit. To land a part by hand, put its
  change on a branch named as the part's card id and run `conveyor.sh land-branch <card id>` ([Commands](commands.md)).
  That card lands as the part, and its review holds it to the part's Done-when items.

A review follow-up and a split part are follow-ups, so the Follow-ups rule in the Rules tab holds them back when it is
Off. `conveyor.sh run --only <issue>` also runs the review follow-ups and the split parts of that issue, and the review follow-ups of those parts. A follow-up of a split part names the umbrella as its parent, so it inherits the same yes.

A queued card with no GitHub issue starts before the issues. `conveyor.sh control order` takes issue numbers and card IDs. A card's place in that list is the first place that holds its card ID, its parent issue, or the umbrella of that parent. So an umbrella issue in the list puts its split parts and their follow-ups there too. Ready issues and cards with a place start first, lowest place first. Then the cards with no place start, oldest first, and then the issues. A held issue stays held.

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
  line, goes in as one `<token>` mark. If the host file names a terms file that cannot be read, the check cannot be
  made, and the card is blocked. **Landed today** keeps the
  record of the card, and its **File on GitHub** files an issue from it
  ([Board: Done without asking](board.md#rules)).

## Build

An issue that says no live case is known, or that the gain was not measured, does not start a card unless it names a
risk it guards against: security, compliance, data loss, a silent fallback or fail-loud. The Board shows it as
skipped by the rule `no live benefit`, a rule of Conveyor's own: you cannot queue it from the Board or change it in
Rules. To release it, add a `Benefit approved:` line to the issue. Add it as the repository's owner, or with the
GitHub account that Conveyor uses (the account gh is signed in as). Conveyor reads the edit history of the issue: the
line releases the issue only when one of these two accounts added it. A line that another person added does not
release the issue, also when the owner saves the text later. If another person edits the text after the line is
added, the issue is held again until one of these two accounts edits the text. If the edit history is not complete, for example when
someone deleted a version, the issue stays held. A `Visible change approved:` line does not release it, and a
condition in that line does not count as a risk. A risk named in a sentence that denies it, such as `This change does
not affect security.`, does not count either. An issue that does not use those words is not held.

The card builds in a fresh git worktree. Claude build, fix and review sessions start without your account's connectors
(its MCP servers), so a card never sees your mail, drives or notes. Codex sessions start with each MCP server in your
Codex `config.toml` turned off.

A Claude build or fix session cannot use the tools that schedule work, send messages or start other agents:
`ScheduleWakeup`, `CronCreate`, `CronDelete`, `CronList`, `Monitor`, `RemoteTrigger`, `PushNotification`,
`SendMessage`, `ListAgents`, `Agent` and the tool that runs a script of steps. It can still use `WebFetch` and
`WebSearch`. There is no limit on turns. The session ends at its time limit, or sooner when it makes no
progress for the pack's `tunables.stuck`. A card and its issue each have a limit on cost
([Dollar limits](configuration.md#dollar-limits)).

When ast-grep is installed ([Setup](setup.md)), a build or fix session can run `ast-grep` by its name, with Claude
Code, Codex or OpenCode. The card rules tell it to use `ast-grep run` to find definitions, callers and code patterns,
and text search for strings, comments and docs. The brief of a build session lists the files that define and call each
function that the issue names. With ast-grep, ast-grep finds them in each file of a language that has functions and
that ast-grep reads, such as shell (Bats too), Java, JavaScript and Python. It finds a call in `$(name)`, a Java method
and a JavaScript arrow function, which a text search misses. It does not list a file that names the function only in
a comment or a string. Other files, and every file without ast-grep, come from a text search.

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

After the build, the card runs each case on main with its change. A case passes when the run prints a pass line for
it: `ok <case>`, or the `ok <n> - <case>` line of a TAP report, as a Node test file prints. A case that is a whole file
also passes when the file passes, and so does any case when the test runner keeps no log of its own. A case of an
engine case file also passes when its case record says so, with no pass line. A case fails when the run prints a fail
line for it: `FAIL [<case>]`, or `not ok <n> - <case>` of a TAP report. It also fails when its case record says so,
and when the run of its file goes past its time limit. A run that gives a named case none of these gives no result,
and the card is blocked. So a test file with named cases must print a pass line for each case that passes.

A main-red fix card whose session changes no file runs its cases again on main. When they pass, the card ends as
`closed`. When they do not all pass (a case fails, or a run gives no result) and newer main-red fix cards hold
each of its cases, the card ends as `closed`, and its `closed` line names those cards. A newer card on the belt counts
for each case it holds. A newer card that landed counts only for a case that passes in each of its runs on main,
and only while main is still the commit of those runs. A card that keeps a
reviewed change from a rebuild after a landing conflict does not close this way. Otherwise the card is blocked.

A "Push blocked" fix card (see Push, below) is not a main-red fix card here, also when main is red at its commit.
Its cases passing on main do not close it, as its push check can still fail. Before its build session it runs no
case. Its change is checked as a bug card's change. When its session changes no file, it goes the way below.

Any other build session that changes no file blocks the card with "the session made no change", unless
its reply ends with one of two lines:

- `ALREADY-DONE: <where it is fixed>`: main already does what the issue asks. A reviewer checks this against main.
- `DONE-OUTSIDE: <what it did and where the evidence is>`: the issue asks for no change to a tracked file, and the
  session did the work outside the repository, for example records in the state folder or issues it filed. A
  reviewer checks each `Done when` item against the evidence that the line names. The reviewer sees each state file that
  the line names cut at 4000 bytes, and at most 40000 characters in all. The files that the line names come first,
  then its folders; in a folder, the files that the session changed come first, the smallest first. A file that the
  limit leaves out is counted in the evidence, not shown.

When the reviewer answers GO, Conveyor closes the issue and the card ends as `closed`, not landed. For
`DONE-OUTSIDE`, the issue's closing comment is the session's report, and the card's reason starts "Done outside
the repository". When the reviewer answers NO-GO, or gives no clear verdict, the card is blocked, and the reason
gives what the reviewer found.

Before a build, fix or review session starts, Conveyor checks that the CLI of its seat is on PATH. An update or a
reinstall can remove a CLI for a short time. So when the CLI is missing, Conveyor reads the host's CLIs again for
about two minutes. When the CLI is still missing, the card waits in its step and still counts against the card cap. The Board and
`/units` show the wait as `waiting for <cli>`. When the host's CLIs list that CLI again, the loop starts the step on
the card's kept work in its next turn. You do not retry the card. A seat set to a CLI that this
host never had blocks the card at once, and the reason names the seat and the CLI. A review that `conveyor.sh lane`
starts does not wait: after the two minutes, it fails with that reason.

A build, fix or review session can end with no turn and no token. Its CLI then stopped before any work. The card's
reason names the cause from the CLI's own error output: not logged in, a model the account does not have, a settings
error, or a CLI that is not installed. The reason also says what to do. Under it are the last lines of that output,
each cut short. Conveyor writes your home folder as `~`. It leaves out text that looks like a credential, and each
line that the privacy check's patterns find.

A failed Codex review has no line of the CLI's output under its reason. The reason names the file that keeps that
output, such as `<card>.review.events`, in the card's kept folder: `kept/<card>` in the state folder (`conveyor.sh
state-dir` prints it). The CLI's error output is beside it, as `<card>.review.err`. A later review of the same card
adds a number, as `<card>.review-2.events`. When Conveyor could not keep the files, the reason names a folder to make
writable. Other review reasons can name a kept events file in the same way, for example a review that **Stop** stopped
before its cost could be read: look for it in the same folder.

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
through a lint gate before each review, and through the landing gate (below) before it lands. There is one exception:
after a fix of lint findings at the landing gate, the review of the change that fix left has no lint gate before it,
because the landing gate checks that change. When another session changes it again, the next review has its lint gate.
The gate runs the pack's lint commands on the staged change. The brief of the build and fix sessions has a
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
When the gate passed and the card is then fitted onto a newer main, the gate does not run the commands again if all
of these are true:

- The card's change is the same change that passed.
- Main changed none of the card's files.
- Main changed no trigger of a lint command.
- Main changed no file that a lint command reads for all changes.
- Main did not change the pack's `lint` field.
- When the card changes a command's triggers or the pack's `lint` field, main changed none of the files that the
  command reads.

The pass stays the card's lint result, and the card gets no new `lint` line.

- A finding goes to one fix session before any test runs. Its step is `Fix <n>: lint findings`. Then the card goes to
  a review, and that review is its last review: a `NO-GO` lands with follow-ups, or gets one fix round if it holds a
  `harm` P1 and no P0, and lands after that round ([When the fix loop ends](#when-the-fix-loop-ends)). The gate before that review does not
  run again on the fixed change.
- At the next landing gate, a finding that is still there blocks the card with the reason
  `lint: <n> findings left after its fix session; nothing landed`. If a different session (a test fix, for example)
  changed the code after the lint fix, a finding gets one new fix session.

After the lint commands, the landing gate runs the persisted-contract check when the project's pre-push hook runs it
(the hook names `--contract-range`). The check is the copy in the Conveyor install that the project uses: the
commit the pack pins, or the newest commit taken on this machine. So a change that the pre-push hook would refuse does
not land. A refusal goes to a fix session with the check's message. Then the card goes to a review again. The check
names one writer at a time, so a refusal that names a different writer gets its own fix session. A refusal that a fix
session already had blocks the card with the reason `contract: the persisted-contract check still refuses the change
after its fix session; nothing landed: <the check's BLOCKED line>`. With batches on, a card that waits to land runs the same
check after its lint. A refusal stops its checks and tests, no batch takes it, and its landing gate deals with it.
The check also runs on each commit just before it lands, so a card in a batch is checked on top of the cards before
it. A refusal there lands nothing, and the card goes back to its own landing gate. If the landing gate then
passes the change and the same refusal comes again when the card lands, the card is blocked.
Each check reads all the commits that a push can check. With **Push on landing** off, a landed card that is not pushed and
has a finding that got no follow-up issue is checked again with the cards after it. Each card after it must also pass
without it, because a push can start after it. A check does not start at a commit inside a batch where no push can start.
In a batch, a card before it that has no leftover finding, or a follow-up issue for each one, is not checked again
with it, because a push does not check that card.

Then the landing gate runs the push checks on the card's change, when the project's pre-push hook names the push-gate
variable. For the push checks to run before a card lands, add that variable to the project's pre-push hook: its name is
in the engine reference ([Lint](../conveyor/README.md#lint)). The hook runs in the card's worktree, as for a
push of the card's change alone: its input line gives the card's change as the local commit and the commit before it as
the remote's. So the checks that the hook selects by changed files are those of the card. The hook gets the push-gate
variable set to the card's name, and it has the time limit of a push (`pushTimeout`, in the `tunables` of `.conveyor/project.json`). It runs on a test slot, and
waits for one while all are in use. The Test step shows the card as waiting for a slot, then as running the hook. If a
check fails, the card blocks with the reason `push check: <check> failed on the card's change (exit <n>); nothing landed.` and the hook's
output. The check is the word after the last `FAILED` that the hook prints. If the hook runs past its time limit, the
card blocks with the reason `push check: its checks not finished: ...`. A hook that does not name
the push-gate variable runs only at the push.
When a session brought a card onto main by a change to documentation files alone, and its change outside them is the
one that passed its tests, the push checks also run on its new change before the landing gate. When they fail, no
batch takes the card, and the landing gate blocks it at its turn.

With batches on, a card that waits to land runs the push checks too, after the persisted-contract check. If they fail
or do not finish, it runs no checks or tests, no batch takes it, and at its turn its landing gate runs them again and
blocks it if they fail again.

With batches on, a card that waits to land after its `GO` runs its own product checks and tests while it waits. The
same lint commands run first, once in the wait. A pass and a missing tool let its checks and tests run. A finding or an
execution error stops them, with no fix session. The card is then not ready: no batch takes it, and the lint does not
run again while it waits. At its turn, its landing gate gives it its fix session, or blocks it on an execution error.

With batches off, a card that waits on another card runs no lint, checks or tests while it waits. This is true when it
waits for the files of the other card, and when it waits for the landing turn. When its turn comes, it runs its Test
step once, on main after the other card landed. With batches on or off, when a card starts its Test step, the order of
the cards that wait on its files is fixed. The claim of each of those cards names the card that it lands after.

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

A yes gives a condition in one form only: `condition:`, in any case, with the condition after it, as in
`Visible change approved: <owner>, <date>; condition: <text>`. **Approve with this condition** on the Board writes
this form. All other words in the line are notes, and they change nothing. When the rule "visible changes need the
owner's yes" is on, a yes with a condition has the kept patch reviewed against the condition, with no build, before
it lands. A yes with no condition lands the kept patch with no build and no review.

When a kept patch that you approved no longer applies to main, one session brings it onto main. Then one review reads
that port alone, the tests run, and the card lands. The card goes through the full review loop instead when the issue
text has changed since the review of the kept patch, or when your yes gives a condition. It also does so when the card
is held to the change you approved before the build and that review did not say the change matches it. The same is
true when a follow-up's review did not say `INHERITED: part` for the yes it inherits.

The rule Lint check is on by default. `conveyor.sh control rules lint=off` turns it off. Then no lint command runs in a
card, the brief has no `# Lint` section, and a change of lint policy does not stop for your yes.

## Review and the judge

A second model reviews each card, at most three times, once more after each fix of a privacy hit on the last review and once more after the fix of a P1 on a last review. Each finding has a level:

- P0: it breaks main, loses data or opens a security hole.
- P1: the change does not do what the issue asks, or breaks behaviour the project uses today.
- P2: a real defect with a limited effect.
- P3: a real but minor defect with no wrong result that users or the next card meet. While the rule `P3` is on, an
  accepted P3 is handled as a P2 is: fixed and filed, or put on its list when its kind is not `harm` (below). Off, the card only lists it.

The `review.proof` of the pack (the project's settings, `.conveyor/project.json`) sets the proof that a finding
needs. `any`, the default, takes any proof that can be reproduced. `real` asks for a proof with what the project really
runs: its real config, commands and inputs. A finding with no such proof becomes an `UNPROVEN:` line, which never
holds the verdict. A security finding needs only a proof that can be reproduced.

The proof of a finding ends with `At <file:line>: ` and the text of that line in backticks: the one line of the code that
makes the proof true. The engine reads that line in the staged change, with each run of spaces taken as one space, and
marks the finding `proof line: match` when the text is the same. It marks it `differs` when the text is other or the line
does not exist, and `none` when the finding has no such part. The engine drops no finding for this mark. The judge sees
it, and reads the code before it accepts a finding marked `differs` or `none`. The review's line in the card's steps
keeps the number of findings of each mark as `proofLines`.

A Claude review or judge can read and search the files, but it cannot edit them. When ast-grep is installed
([Setup](setup.md)), it can also run `cb-ast run -p '<pattern>' -l <language>`, an ast-grep search that cannot
write. Its shell refuses every other command that writes: `rm`, `touch`, `bash -c`, an ast-grep option that writes, a
command chained to `cb-ast`, a redirection of its output, a command substitution and an environment prefix. Claude
Code's own read-only commands, such as `git status` and `ls`, can run. A finding's `Class search:` line can then be a
`cb-ast run` search when the mistake is in code that ast-grep reads, and is an `rg` search otherwise. Without
ast-grep, the review has no shell, and its `Class search:` lines are `rg` searches.

A review after a fix gets the findings that the fix was told to fix and the findings declined so far as `claim wrong`,
`cannot happen` or `fixed`. It says for each earlier finding whether the fix holds. It raises one of those declined
findings again only with a new, concrete reason.

### When the fix loop ends

After a `NO-GO`, a fix session fixes the findings, and the card goes to its next review. The first fix session of a
card runs at the effort of its seat. The second fix session of the same card, whether it fixes review findings or
failed tests, runs one effort level above the effort of its seat, and a fix session after it runs at that level too.
The level never goes above the highest effort that the pack's `pick.builder` list allows for the model, or above the
highest effort its program takes when the list names no range. A model with no effort, such as an OpenCode builder,
has no step. The loop ends at the first of these:

- `go`: a review says `GO`.
- `max-reviews`: the card has had three reviews. One more review follows each fix of a privacy hit on the last review, and one more the fix of a P1 on a last review (below). A card that starts from the kept patch of a blocked card also counts
  the reviews of that card and of the cards whose kept patch it took. It does not count the reviews of other cards of
  the same issue. After an automatic port of one of those cards, it counts only the reviews after the review of the
  port.
- `rebased`: the one review after a conflict with main at landing.
- `test-fix`: the one review after each fix of failed tests.
- `lint-fix`: the one review after the fix of lint findings at the landing gate.
- `land`: the card lands from a kept patch on its kept review, with no new review.
- `repeat`: a finding comes back after its fix, and each P0 or P1 finding of the review comes back too. A `harm` P0
  or P1 that comes back also ends the loop this way, whatever else the review holds. The card gets no more fix
  sessions for it.
- `new-p2`: from the first review on, a `NO-GO` whose findings are all new and all P2 or P3. None of them is P0 or P1,
  and none comes back after its fix. The card gets no fix session for them: it goes to its tests and lands, and each
  `harm` finding becomes a follow-up card. A finding of another kind goes to its list (Harm or self-heals, below). A
  review with a P0 or P1, or with a finding that comes back, does not end the loop this way: the reasons above apply to
  it as before, and when none of them holds, it gets a fix round. A fix round also follows for a card whose issue is a
  follow-up at the follow-up depth cap, as it files no follow-up.

A `NO-GO` with no finding to fix, such as one that holds only an `UNPROVEN` line, blocks the card when none of the
reasons above ends the loop at that review. The reason is
`review <n> is NO-GO with no finding to fix:` and the reviewer's first `UNPROVEN` line, else its `VERDICT` line.

A review finding never blocks a card. When the loop ends, the card goes on to its tests and its landing gate, and
lands. Each `harm` finding that is still open, at any level from P0 to P3, becomes a follow-up card. A finding of
another kind goes to its list (Harm or self-heals, below). A finding that the judge declined is not filed.

If the last review is a `NO-GO` that holds a `harm` P1 finding and no P0, the card first gets one fix session, once,
and one more review of that fix alone. If that review still holds a P1, the card lands and the P1 becomes a follow-up.
A P0 on the last review gets no extra fix session: the card lands, and the P0 becomes a follow-up. A finding with no
kind counts as `harm`, and a finding with no level counts as P1.

With `privacy.mode` public, a privacy hit in the card's own change never lands. With it private, a hit that the
review does not quote can land. If a finding of the last review is such a hit, the card gets
another fix session and one more review. This repeats until a last review holds no such hit, and then the card lands
as above. If the hit is still there after 3 of these fix sessions, the card does not land and does not go to Needs
you: the engine shuts it with its work kept, and the hit goes on the self-heals list as a possible false hit of the privacy
check. `conveyor.sh retry <issue>` takes the card again. The review that ends the loop and the `filed` step
record the reason as `stop`, with `pass` (the reviews of this card) and `rounds` (the reviews of earlier cards). On the
Board, that review shows "Fix loop ended:" and the reason.

When a card of an issue is blocked, Conveyor posts a comment on the issue. It starts with **Blocked:** and why, in
words. Next come the findings of the last review that the reason names, under "The review still finds:", or else the
reason, and then **Other findings of the last review**. Two folded parts follow, which you open on GitHub: **Declined
by the judge (N)**, the findings that the judge declined, and **Last output**, the end of the card's output. The
comment ends with **Next:**, what `conveyor.sh retry <issue>` does for this card, and a small line with the card ID
and, when the work is kept, the path of the kept patch and the commit it was built on.

The judge, when it is on (`conveyor.sh control judge on`), reads each review and declines a finding that does not earn
its place. A declined finding causes no fix and no follow-up (`conveyor/README.md`, The judge). After a fix round,
the judge also gets the findings that the round was told to fix. Each one comes with the reason that the judge gave
when it accepted it, when the judge gave a reason that can be read for that finding; else it comes with no reason.

The judge's cost is a step of its own. Each review that the judge reads leaves a `judge` step in the card's steps, right
before the review, with the judge's model, effort, seconds and usage. A judge that fails leaves it with the result
`failed` and the reason. A review with no finding, and a review that reuses the last one, leave none.

A fix session gets each finding with its `E<n>` ID. When the review finds a finding again after a fix round for it, its
earlier fix did not hold. The session is then told one more rule: do not make the same guess narrower. It must record the fact where it is
written, so that the reader does not have to infer it. When the code cannot tell, it takes the safe path: ask again,
refuse, or keep both. The session says in its reply which of the two it did. A fix session whose findings are all new
does not get this rule.

A finding that a test does not check what its name, its comment or the issue's Done-when says it checks is a real
defect, not "only a test gap".

Each decline has a kind: `claim wrong`, `cannot happen`, `fixed` (already fixed on main), `rare case`,
`not this change` or `other`. The declined list keeps it beside the reason. A finding that repeats a declined one is
declined as a repeat, with the earlier kind, when that kind is `claim wrong`, `cannot happen` or `fixed`, or when the
defect is fixed on main now. A repeat is the same claim about the same code, with only a value in its proof different (a width,
a count, a name, a time). The judge also sees the findings ruled `OUTSIDE` on the cards of the issue. A repeat of one of
those, or of a decline of the kind `not this change`, gets its earlier ruling again: its reason starts with the earlier
kind and names the earlier finding by `file:line`. A repeat of a finding declined with another kind, or with no kind,
is judged again as a new finding, and so is a finding on lines that a fix round of the card changed after that ruling. The
reviewer's list of findings not to raise holds only lines of those three kinds.

A real defect that the card's change did not cause is never declined for that. The judge marks it `OUTSIDE`. The card
gets no fix round for it and lands as its other findings let it. When the card lands, the finding is filed as a
follow-up of the card, with its level and the card's issue as its parent, as a finding of a last `NO-GO` is. The
Board shows such a finding as "Filed as a follow-up" with its issue, and as "To be filed as a follow-up" until the card
lands. An `OUTSIDE` finding that the judge sorts as another kind than `harm` is not filed. It goes to the self-heals
list or the docs list (Harm or self-heals, below).

### Harm or self-heals

The judge gives each finding that it accepts or marks `OUTSIDE` a kind. The kind is about what the failure does, not
about how likely the failure is:

- `harm`: data is lost or written wrong (card records, issues, kept work). Wrong code lands or pushes, or a check
  passes that should fail. The belt or a card gets stuck, and only a person can free it. A step stops and nobody is
  told. Private text is published, or a security hole opens.
- `self-heals`: the failure heals itself. A card waits longer, a step runs again, or a slot is over its cap for a short
  time. Wrong or missing text is corrected at the next poll or turn. Extra work or cost gives no wrong result.
- `cleanup`: the fix changes nothing that the code does. Examples are an unused variable, a check that another check
  repeats, a name that misleads, or a comment that is out of date.
- `already guarded`: the finding is real, but another check in the code already stops the bad result. The finding
  asks for a second guard, not for a fix of an open hole. The judge's reason names that check as `file:line`.
- `docs drift`: a guide or README leaves out, or describes wrongly, what the code does correctly.

A finding whose Proof says that it was seen in real logs or records is `harm`, also when it heals itself. A finding
with no kind is `harm`, so nothing is lost. An `already guarded` finding is `harm` when its reason names no
`file:line`, or when that line is not in the code. A finding of a kind that the project always accepts is `harm`,
whatever kind the judge gives it.

- A `harm` finding gets its follow-up at once. On a follow-up card, a `harm` P2 or P3 goes to the self-heals list
  instead (Declined findings and follow-ups, below).
- A `self-heals`, `cleanup` or `already guarded` finding goes to the self-heals list with its kind. A `docs drift`
  finding goes to the docs list. No follow-up is filed for them. On a follow-up card, they also get no fix round. The
  review shows each one as a `SELFHEALS:` line, with its kind and the judge's reason.
- On a card that is not a follow-up, a finding in the card's own change that is not `harm` never stops a review. At
  any review, when each accepted finding in the change is `self-heals`, `cleanup`, `already guarded` or `docs drift`,
  the review gives GO and each finding goes to its list. When a `harm` finding, or a finding with no kind, is beside
  them, the review gives NO-GO and the fix round fixes all of them; none goes to a list. A finding that cannot be
  written to its list is a finding with no kind. If such a finding is still open after the last review, it goes to
  its list.
- At the last review, no finding stops the card. A `harm` P0 or P1 in the card's own change becomes a follow-up as the
  card lands. A P0 or P1 of another kind goes to its list with that card. A finding with no kind is `harm`.

A follow-up's body has a `Kind:` line, with the kind and the judge's reason. In a card's steps on the Board, each
review finding that the judge gave a kind shows it, and an accepted one also shows the judge's reason. When a later
review of the card rules on a finding again, the later ruling counts. A finding that it sends to the list is not also
filed as a follow-up. A finding on the list that it rules `harm`, or gives no kind, leaves the list. When the judge
fails, the review stays as the reviewer wrote it: each of its findings has no kind, so it is `harm`.

Each entry of the self-heals list and the docs list has an area, or, as below, none. It is the area of the file that the finding names,
from the pack's `labels.areaPaths` ([The pack](configuration.md#the-pack)). A file that no path of the map names gets
the map's `other` area. When the finding names no file, or the pack has no map, the entry gets the area label of its
issue. When that issue has no area label, the entry has no area, and the Board shows it under "No area".

The list is fixed in batches, one card for each area. The Board's Self-heals tab shows each area with all of its
entries and their count. "Review batch" on an area opens the batch sheet, which files one card that has the area's
entries as its scope. An entry whose card has not landed or closed waits for the next batch card: the code it names is only in that
card's change. If you shut a batch card before it lands (`conveyor.sh shut`), its entries go back to the list for the
next batch card. `conveyor.sh retry` of that card takes them again, and is refused when another batch card holds
them. A later review that rules an entry of a batch card `harm` files no second card for it.
When the sort moves findings of an audit issue to the self-heals list or the docs list, the issue's body still names them. The card of that issue
is told that they are out of its scope, also after they expire (below).
An entry that no batch card holds and that nobody fixes or sees again leaves the self-heals list after the days of the rule
`healsdays` (`conveyor.sh control rules healsdays=<days>`; [Self-heals expiry](configuration.md#self-heals-expiry)). A finding is seen again when the judge rules the same
finding on a later card (its Proof aside), or rules it `harm` because its Proof names the logs: that starts the days over, and
the entry is then of that card, so the next batch card waits for it. An entry that leaves is kept, with the date and the reason
`expired`. The Self-heals tab shows these entries under "Dropped entries", and the Rules tab sets the days. A finding that the judge sorts to the list again takes its entry back. An entry
that a shut batch card gave back counts its days from that day, like any other. The docs list has no expiry.
Nothing on the list needs you until you file the card. The Foreman's status gives the count and does not report the
list as something to do.
A batch card tells its builder to check each `already guarded` entry first. When the check that its reason names no
longer stops the bad result, the entry is `harm`, and the batch card fixes it with a test.
A batch card that holds only `cleanup` and `already guarded` entries has no bug label, as a `cleanup` follow-up has
none: no test can fail on main for them. Only a batch card that holds only `cleanup` entries has a `Cleanup:` line,
so its review reports a change to what the code does.

The docs list is fixed in the same way, one docs sweep card for each area, so that the docs match what users see. An
entry of the docs list never expires. On the Board's Self-heals tab, the Docs list shows each area with its entries,
and "File docs sweep card" opens the batch sheet, which files one card that has the area's entries as its scope. `conveyor.sh release-prep`
also files one docs sweep card for each area that has entries, before it runs the suite. A docs sweep card has no bug
label. If you shut a docs sweep card before it lands, its entries go back to the docs list, as a batch card's do.

`conveyor.sh heals sort` sorts the work that was filed before this rule, with the same judge. The loop runs it by
itself, with `run` and `serve` alike, and picks no card until a sort has run. When the open issues cannot be read,
the sort changes nothing and the loop tries again at a later turn. The sort reads each queued follow-up card that no
card has picked, also a held one, and each open issue that is one review finding (a `[P0]` to `[P3]` title with a
Proof). To file a review finding by hand so that the sort reads it, start the title with `[P0]` to `[P3]` and
include a `Proof:` line. The sort also reads each finding of an open audit issue that holds many findings. The sort uses the same kinds as
the review's judge. A `harm` item stays. An item of another kind goes to its list: the docs list for `docs drift`,
else the self-heals list. Such a card leaves the queue. Such an issue is closed with a comment that names its list
entry. In an audit issue, such findings go to their lists, and the sort posts one comment on the issue that names
them and their entries. The issue closes, with that comment, when all of its findings
are on the list. The sort never changes the body of an issue. If the comment or the close fails, the findings stay
in the issue and leave the list. The sort reads each issue again just before it comments on it or closes it. A
finding whose text changed while the judge read it stays as it is. An issue that changes as it is closed is opened
again, and its finding leaves the list. A card or issue that the judge cannot read stays, as `harm`. The sort does not
read an issue that is held, that is not a finding (a feature, a Board change, a bug you reported), or that has a card
that did not land or close, such as a card on the belt or a blocked card. It does not read a follow-up that has a
`Kind:` line: the judge already gave it its kind. An issue that is held while the judge reads stays as it is. The
Board and the Foreman's status say when the sort ran.

A change can need a step when you deploy it: a migration before the deploy, a new environment value or a flag. The
reviewer writes this step as a `ROLLOUT:` line: the action, what fails without it, and its file and line. The builder
writes one as a `Rollout:` line of the card's commit trailers. A rollout action is not a finding. It does not stop the
card, and the judge does not read it. A later review that gives GO decides the reviewer's actions: it gets the actions
in force, and drops each one that it does not write again, for example one that a fix made obsolete. The card's commit
message has each action in force as a `Rollout:` line, so the push carries it, and the Landed today panel shows it
under the card. The reviewer's steps come first, then the builder's, each in
the order it was written. When the pack's `privacy.mode` is public, each part of these lines that the privacy check
flags goes in as a mark of what it is, such as `<home path>`. If the host file names a terms file that cannot be read,
the check cannot be made. That blocks the card, not the action.

A test that a card adds or changes must check its behaviour directly. Some tests run other test files or the suite
runner, run the real loop, or poll a real process until a condition holds. Such a test needs a comment beside it that
says what a direct check cannot show. The reviewer raises a test with no such comment as a P3 finding.

A project lists what it knowingly lives with under the heading `## Accepted limits` in its own `README.md`. Every
card's reviewer reads that section and does not raise what it lists.

## Declined findings and follow-ups

Every finding that is declined is a line of the Declined list, with who declined it and why. A finding that the judge
sorts as another kind than `harm` is not declined: it is on the self-heals list or the docs list (Harm or self-heals,
above). The Board's Declined
panel lists them, and "File as issue" files one as an issue (`conveyor/README.md`, Declined findings). A line's reason
is in its own block under the finding, led by "Why the judge declined it" or "Why the code declined it". Each sentence
starts a new line, code shows in a code font, and a file and line in it opens that line on GitHub.

Findings still open after the last review become follow-up issues, which become cards of their own. This includes
the first review: when it is a `NO-GO` whose findings are all P2 or P3, the loop ends there (`new-p2`, above), and the
card gets no fix session for them. A finding that the
judge sorted as another kind than `harm` goes to its list instead (Harm or self-heals, above). Each follow-up's
body says how deep it is, as the line `Follow-up depth: N`: 1 for a follow-up of a first card, 2 for a follow-up of
a follow-up. Follow-ups go two levels deep. A card whose issue is a follow-up (depth 1 or more) files a follow-up only
for a `harm` P0 or P1. Its `harm` P2 and P3 findings go on the self-heals list, under the area of its issue, and the
reason says that its issue is a follow-up. A P2 or P3 that names one of the pack's `pipelineFiles` is the exception: it
gets a follow-up, filed held. If a finding cannot be written to the list, the card does not land. If the depth of the
issue cannot be read, the card counts as at the cap. A card whose issue is at depth 2 files no
follow-ups: its leftover findings go on the self-heals list, and the reason names the cap. A follow-up that changes one of the pack's `pipelineFiles` is filed held.
It builds only once you release it. A follow-up whose finding names only files of its parent card's change, and no
word of `auto.reserved`, is not held ([Standing yes](foreman.md#standing-yes), `review-followup`).

A finding whose fix changes no behaviour, such as a comment, dead code or a redundant check, has the mark `[cleanup]`
after its level, as `[P3][cleanup] file:line what`. Its follow-up is a cleanup, not a bug: it does not get the pack's
type label (`labels.type`), and its body has a `Cleanup:` line. Its card skips the build check of a bug card, so no
test must fail on main for it, and its review checks that the change keeps what the code does. A finding with no
such mark is filed as a bug.

The build check of a bug card does not block a change that changes only comments in its `.js`, `.mjs`, `.cjs`, `.ts`,
`.mts` or `.cts` product files, with or without a test file. Its result says the change is comments only, and the
review judges each changed comment.

A bug issue names its error in a line of its body that starts with `Bug error:`, followed by the error text. The text
needs 8 characters or more, and only the first such line counts. The build check of a bug card runs the card's new
tests on main's code without the fix, and a failing run proves the fix only when the test command could run and, when
the issue has such a line, the run's output holds that text, exact in case. A run whose test command could not run
(exit 126 or 127), or whose output lacks that text, is no proof: the card goes back to its build session, told "the
new tests fail without the fix, but not with the bug's own error", and the result says which of the two it was. An
issue with no such line is checked as before.

When the pack's `privacy.mode` is public, a follow-up's finding is filed with each part the privacy check flags
replaced by a mark such as `<home path>`, and the issue says the text was masked. A last finding that the privacy check
flags in a line the card itself adds gets one more fix round instead of a follow-up.

## Tests

A card's tests run before it lands. When some cases fail, they run once more before any fix session. A card whose
re-run passes goes on with no fix, and the Board shows its Test step as "passed on re-run" (`conveyor/README.md`, The
test step).

A card's changed tests also run one time before its first review, when the pack has a `test.fileCommand`, main is
not red and the project's checks (`test.checkCommand`) pass. A failure there goes the same way as a failure in the Test step. When each failed case also fails on main,
the card waits for main. When a failed case is a fault of the machine and the card's change repairs that fault (the
repair lane, `conveyor/README.md`, The test step), the review starts. If not, the card waits until the machine passes
its checks again. Otherwise the card goes to a test fix session before any review, with the same fix rounds.
After the fix, the tests run again. The review starts when they pass, or when main is red after a wait, a wait for a
test slot included. The card's history on
the Board shows that run before the first review. A card that starts from a kept review has no such run. Nor has the
one review of a blocked card's kept work that a card brings onto main after the review loop of that work ended, or a
review that is reused. A card that keeps only the findings of an earlier review has the run.

Each failing case shows where it failed when the output has a stack trace after its failure line. Its line ends with
`(at <file>:<line>: <that line's text>)`. For a JavaScript stack, this is the first frame of the stack that is in a
file of the checkout. For a Python traceback, it is the last such frame. So an assertion with no message of its own,
such as `assert.ok(false)`, still shows the line that failed. A failed file whose output names no case, such as a
Python `unittest` file, shows the place of the first stack trace in its output. The push check and a release's suite
show the same, and a failed push check gives the place in its reason. The text of a line is not shown when the path
to its file goes through a symbolic link. The tests need no change for this.

The test fix session gets the failing cases first, each with its file and the place where it failed, and then the last
200 lines of the raw output.

A card gets 3 fix rounds for the failed tests of its change. Each round gets the failures of the test run before it.
When the tests still fail after the third round, the card is blocked with the reason `the changed tests failed again
after their 3 fix rounds`.

A retry of a card blocked in its test step (with that reason, or with `the changed tests gave no result 3 times in a
row`) starts at the tests, from the kept patch. It runs no build session and no review before its first test run. A
test that fails again gets a test fix session and a review, as in any card. The retry starts so only when the card's last
review gave a verdict and the issue text is the text that review read. When the issue text has changed, the card runs one
session and a review. A card blocked in a fix session also runs one session and a review. When the kept patch no longer
applies to main, one session brings it onto main, and a review follows. When the issue's section `## What customers or
staff will see` has changed since that review, the card is built from nothing. When the rule "visible changes need the
owner's yes" is on, and a `Visible change approved:` line with a condition has come or been edited since that review,
the card first runs one review of the kept patch, with no build session.

A case that fails again runs on main. When it fails there too, Conveyor checks whether main or the machine is at
fault. Main is at fault only when an input of the case's test file changed since its last recorded pass, and a
control passed in the same run, no control could run, or a change on main explains the case (below). The controls are the test files that the pack's
`test.control` names. When all the controls fail, Conveyor checks each case alone. Main is at fault for a case when a
change on main changed its test file, or a file that the test map links to it, after the last landing whose tests ran that
case. Otherwise the
machine is at fault: no "Main is red" card opens, and the loop picks no new card. The Foreman gets one wake that names
the files and the cases that fail. The cards with that failure wait in their Test step, "waiting for the machine". The Board shows
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
landed. When its change applies there, it is not reviewed again, and its tests do not run again: its pass stands, even
when the landed change uses the same test files. The same is true for a batch when a card lands on main during the
batch's tests, and for the cards of a batch that passed their tests on different commits of main. Two changes that
each passed alone can fail together. That failure shows on main, as main red, and the main-red fix card fixes it.
When its change clashes, one session fits it onto main, and it is reviewed and tested again before it
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
main. When more than one file must run, the pack sets `test.fileCommand` and more than one test slot is free, the
files run side by side, each in its own process on its own test slot. A file does not run again when it passed before, for example in a card's Test step, and none of the files that it
reads changed since that pass. When the rule Push after a combined test run has `pushbatchtests` set to `all`,
every file runs. This run never runs a test runner or the whole suite. If a file fails, Conveyor runs that file on each landing
in turn to find the landing that broke it. Then it files a main-fix card that names that landing, and it holds the
push until main changes. Push landed pushes the commit that its full test run tested, so it skips this run. The run
needs `test.fileCommand`, or a `test.list` form that can give the test command one file. Without them, the push goes
on without the run. With `push.check` off, or the Rules tab's **Test before a push** Off, the push goes on without
the run too ([Which tests a card runs](configuration.md#which-tests-a-card-runs)). These two do not apply while the
Rules tab's **Push after a combined test run** is On. Then the run always runs before the push, and when it cannot run
one file, the push is held.

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

- `check`: the pre-push hook failed (typecheck, tests, lint), or a test file failed in the run before the push. A retry fails the same way,
  so the loop does not run the checks again until main's commit changes. When the pre-push hook failed, Conveyor makes
  a fix card with no issue, titled "Push blocked: <check> fails on main". The loop starts it before the queued cards,
  and also when the cap is reached, as it starts a "Main is red" card. When that card lands, the loop pushes at once,
  also while the rule Push after a combined test run holds other landings. If origin has the blocked commit before
  the loop starts the card (you pushed it yourself), the loop does not start the card. Needs you and the Foreman's
  wake show the block only when you must act: when it has no fix card, when no loop is running, when the loop is
  paused and has not started the fix card, when its fix card is blocked, closed or gone, or when it landed and the rule Push when a card lands is off. Then they name the fix card, and Needs you shows the
  hook's last lines. While the fix card is on the belt, the Board's Health tab names it in the Last push row.
- `transport`: git, the network or the remote failed. The loop tries again every `tunables.pushRetry` seconds. Needs
  you shows it once a retry fails too.

When the pre-push hook fails and its output names test files as failed, Conveyor first runs each of those files
alone, once, on the same commit, with `test.fileCommand`, as a card's Test step runs a file. When each file passes
alone, Conveyor pushes the same commit again without the hook. The files go on the flaky-test record, and one
`flaky-test` issue for all of them is filed held. The Foreman's wake and the card's Push step on the Board say
"flaky: passed alone". When a file fails alone too, the push stays blocked as a `check` failure. The push also stays
blocked when the hook prints `FAILED <name>` for a check that is not one of those files, or names no test file.

A file whose flaky issue is still open gets a comment on that issue, not a new issue. A file recorded flaky from two
different sources within seven days, after an issue was filed for it, is flaky again. A card, a push and a full test run
of one commit are each one source, however many cases of the file failed in it. When that issue is closed, Conveyor opens it
again, holds it and adds the comment "Flaky again since its fix #N". It does not file a new issue. The Tests page
shows "Flaky again since its fix #N" on the file's row.
