# How a card goes

Each open issue becomes one card. The card goes through Pick, Build, Review, Test, Land and Push. A review finding
sends it to a fix session and then to review again. A card that needs a person stops on the Board's Needs you, with
its work kept, until you retry or close it.

## Build

The card builds in a fresh git worktree. Claude build, fix and review sessions start without your account's connectors
(its MCP servers), so a card never sees your mail, drives or notes.

When the issue has a `## Done when` section, Conveyor checks the build or fix session's reply before the review. The
reply needs a `D<n> met:` or `D<n> not met:` line for each item. It must also name each TODO or [VERIFY] marker that
the change adds, on a line with its file.

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

A project lists what it knowingly lives with under the heading `## Accepted limits` in its own `README.md`. Every
card's reviewer reads that section and does not raise what it lists.

## Declined findings and follow-ups

Every finding that is not built is a line of the Declined list, with who declined it and why. The Board's Declined
panel lists them, and "File as issue" files one as an issue (`conveyor/README.md`, Declined findings).

Findings still open after the last review become follow-up issues, which become cards of their own. A follow-up's own
leftover findings go to the Declined list. A follow-up that changes one of the pack's `pipelineFiles` is filed held.
It builds only once you release it.

## Tests

A card's tests run before it lands. When some cases fail, they run once more before any fix session. A card whose
re-run passes goes on with no fix, and the Board shows its Test step as "passed on re-run" (`conveyor/README.md`, The
test step).

A case that failed and then passed goes on the flaky-test record. `conveyor.sh flaky add <case> <source> <note>` adds
an entry from outside a card. A case with entries from three sources within seven days gets one issue, "Flaky test:
<case> fails at random". Until that issue closes, card test steps keep the case off. The full test suite still runs
it. The Board's Health panel has a "Flaky tests" line (`conveyor/README.md`, Flaky tests).

The whole test on main runs only for a project whose pack names `test.main` (`conveyor/README.md`, The whole test on
main).

## Landing

Cards that share a file land in turn, or together in one batch that is tested once. A card whose change still applies
to a main that moved lands on the tests it already passed, with no second run and no second review. Its product checks
run again on main. A change that had to be reworked to fit is reviewed and tested again (`conveyor/README.md`,
Same-file cards).

## Push

By default, Conveyor lands each card and pushes when you press
[Push landed](board.md#push-landed-and-run-full-test-suite). Turn on the Rules tab's **Push when a card lands** rule,
and the loop pushes main on its own after each landing. Each push goes through the project's own pre-push hook. A push
that fails is one of two kinds:

- `check`: the pre-push hook failed (typecheck, tests, lint). A retry fails the same way, so the loop wakes the
  Foreman and shows the hook's last lines on Needs you. It does not run the checks again until main's commit changes.
- `transport`: git, the network or the remote failed. The loop tries again every `tunables.pushRetry` seconds. Needs
  you shows it once a retry fails too.
