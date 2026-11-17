# Benchmarks

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
