# Procedures for the Foreman (the plugin's rules; `foreman.sh procedures` prints them)
Each `ask <project> ...` below is run as the start gives it: after the same path as the start's `ask <project> testissue` command.

## A release's suite
A release's suite: before you run conveyor.sh release-run prep <version> or release-run <version>, ask the owner by the picker "Run the test files one by one or in parallel?" with the options "One by one" (slower, the least load) and "In parallel (<n> at once)" (faster, more load, the belt slower meanwhile), and pass the answer last in the command: --serial for one by one, --parallel for in parallel. <n> is the number ask <project> release-run atonce prints for the release's project (none: "In parallel"). Mark the option of the rule's mode Recommended: the suiteMode in the JSON ask <project> control prints (serial or none: "One by one"). Unless the rule's machine is this one (its name is in the JSON ask <project> suite-machine check --json prints; "this machine" when the suite runs here), ask a second question in the same picker call, "Run the suite on which machine?", with the rule's machine by that name (Recommended), then "This machine (the belt is slower meanwhile)"; name each machine beside its number: "In parallel (<n> at once on <the rule's machine>, <m> on this machine)", <m> being the number ask <project> release-run atonce --machine local prints (leave out a machine that prints none). On This machine, add --machine local as the very last words of the command, after the mode.

## A card that waits
A wake that a card has waited (or is still waiting) for main to change, or on another card: do not only report it. Find why it waits: read the waited-on card's logs (<card>.out, .err, .test, .testlog beside its worktree) and mainred.json (in the folder conveyor.sh state-dir prints). Then fix the cause: a hand fix when the belt is blocked and the owner's rules allow it, otherwise file the issue.

## A blocked push
A wake "push blocked: <check> failed after <card>; it will not pass on a retry": the engine makes the fix card for it and picks it ahead of the queue, so do not file a second fix card. 1. Read the fix card the wake names (ask <project> health: pushError.fix). 2. Do the step the wake gives the owner (start or resume the loop, push main with Push now, retry the fix card when it is blocked) when the owner's rules let you, else say it to the owner. 3. While the push is blocked, a wake reply may carry one line "Push blocked: <check> failed after <card>; cleared by <fix card>." 4. A wake that says "a repeat of that block, not a new one" is the same block: take no new step for it. 5. At the wake "the push went through", reply with the one line "Push went through: <check> passes."

## The pack not committed
In a project's main checkout, run conveyor.sh setup pack-commit (with no answer: it reads the size entries' exempt paths from the pack, so do not gate it on a git status of fixed paths); on ok: there is nothing to do; on an ask: line, ask the owner by the picker "Commit the Conveyor pack (.conveyor/project.json) on <default branch> now?" (yes / no), with the change it printed; on yes run conveyor.sh setup pack-commit yes, on no the same with no; say what it printed. Never list a git command for the owner to run.

## A blocked card you take
When you take a blocked card (a hand run, a fix card, a picker to the owner), run `note <card> <what you do about it>` after the same path as the `ask <project>` commands, one short line, so /units and the Board show the card as yours and not as one that needs the owner. When the card waits on the owner's answer to your picker, run `note <card> --ask <the question>`: it stays with the cards that need the owner and says it waits for their answer. Write it again when what you do changes; a retry, a landing or a shut ends it.

## Filing an issue
Each issue you file has a line `Benefit: <the live case it fixes, or the gain as measured>`, or `Guards: <the risk>` (security, compliance, data loss, a silent fallback, fail-loud).

## An issue held for its benefit
An issue skipped by the rule `no live benefit` waits for the owner's yes. Ask the owner by the picker. The question says plainly that no live case is known or the gain was never measured, and "Recommended" goes on closing the issue or measuring first. On yes, add a line `Benefit approved: <date>` to the issue.
