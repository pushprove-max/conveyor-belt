# How a card goes

Each open issue becomes one card. The card goes through Pick, Build, Review, Test, Land and Push. A review finding
sends it to a fix session and then to review again. A card that needs a person stops on the Board's Needs you, with
its work kept, until you retry or close it.

## Build

The card builds in a fresh git worktree. Claude build, fix and review sessions start without your account's connectors
(its MCP servers), so a card never sees your mail, drives or notes.

When the issue has a `## Done when` section, Conveyor checks the build or fix session's reply before the review. The
reply needs a `D<n> met:` or `D<n> not met:` line for each item. It must also name each TODO or [VERIFY] marker that
the change adds, on a line with its file. On the Board, open a card's `Done when` line to see each item: its text,
the builder's line for it, and the reviewer's answer when the review gave one.

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

- A finding goes to one fix session before any test runs. Its step is `Fix <n>: lint findings`. Then the card goes to
  a review, and that review is its last review: a `NO-GO` lands with follow-ups. The gate before that review does not
  run again on the fixed change.
- At the next landing gate, a finding that is still there blocks the card with the reason
  `lint: <n> findings left after its fix session; nothing landed`. If a different session (a test fix, for example)
  changed the code after the lint fix, a finding gets one new fix session.

The lint commands must not change the card's work. Before they run, the worktree must have no change that is not
staged, and no file that git does not track or ignore. If it has one, that is an execution error, and Conveyor changes
nothing. After they run, the staged change, the worktree and the untracked files must be as before. This is also true
after a command that ran past its time limit. If they are not as before, that is an execution error. Conveyor then puts
back the staged change and the tracked files, and deletes each new file that git does not ignore. Conveyor does not
check the files that git ignores.

Each gate run writes a `lint` line to the card's records, with each command's result and seconds. When the change
changed a trigger of a command that ran, the line says `tools ran as installed`: the tools ran as installed on this
host, not as the change would install them.

The rule Lint check is on by default. `conveyor.sh control rules lint=off` turns it off. Then no lint command runs in a
card, and the brief has no `# Lint` section.

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

The judge, when it is on (`conveyor.sh control judge on`), reads each review and declines a finding that does not earn
its place. A declined finding causes no fix and no follow-up (`conveyor/README.md`, The judge).

A change can need a step when you deploy it: a migration before the deploy, a new environment value or a flag. The
reviewer writes this step as a `ROLLOUT:` line: the action, what fails without it, and its file and line. The builder
writes one as a `Rollout:` line of the card's commit trailers. A rollout action is not a finding. It does not stop the
card, and the judge does not read it. The card's commit message has each one as a `Rollout:` line, so the push carries
it, and the Landed today panel shows it under the card. The reviewer's steps come first, then the builder's, each in
the order it was written.

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

Cards that share a file land in turn, or together in one batch that is tested once. A card whose change still applies
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

A push that fails is one of two kinds:

- `check`: the pre-push hook failed (typecheck, tests, lint), or a test file failed in the run before the push. A retry fails the same way, so the loop wakes the
  Foreman and shows the hook's last lines on Needs you. It does not run the checks again until main's commit changes.
- `transport`: git, the network or the remote failed. The loop tries again every `tunables.pushRetry` seconds. Needs
  you shows it once a retry fails too.
