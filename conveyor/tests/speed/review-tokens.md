# The tokens of a review after a fix (#538)

A card's second or later review followed a fix of the findings of the review before it. It was asked to review the
whole staged change again, so it read again the part that had passed its earlier review. From #538, it reviews the
fix's diff, checks each finding the fix was told to fix against that diff, and looks for new defects that the fix's
lines cause, in its diff or in their callers. When the fix touches more than the pack's `review.rereviewWhole` share
(default 50%) of the change's added and removed lines, it reviews the whole change, as before.

## How it is measured

From the loop's card records (`conveyor/state/cards.jsonl`): each review line that ran a review session (no `reused`
field), in the order of the record. A card's first review line is its first review; each review line after it is a
later review. The number is the mean of `tokens.codex` on those lines.

```sh
jq -rR 'fromjson? | objects | select(.step == "review" and (.reused | not)) | "\(.card) \(.tokens.codex // 0) \(.time)"' conveyor/state/cards.jsonl \
  | awk -v since=2026-11-14 '$3 >= since { k = (n[$1]++ == 0) ? "first" : "later"; c[k]++; s[k] += $2 }
      $3 < since { n[$1]++ } END { for (k in c) printf "%s n=%d mean=%.0f\n", k, c[k], s[k] / c[k] }'
```

## Before

Measured 2026-11-14, on the records up to main 0215a22, the change not yet in force.

| Reviews | Records from | First reviews | Their mean Codex tokens | Later reviews | Their mean Codex tokens |
| --- | --- | --- | --- | --- | --- |
| The owner's count in #538 | (the issue) | 138 | about 57 k | 131 | about 63 k |
| All records | 2026-11-11 | 433 | 44.6 k | 470 | 53.5 k |
| The last day | 2026-11-14 | 163 | 56.9 k | 145 | 71.7 k |

A later review used 20% to 26% more tokens than a first review, though it had less new to read.

## After

Not measured yet: the change must first run on cards. Measure it with the command above, with `since` set to the
day this change landed, once some 50 later reviews have run on it, and add the row here.

# P2-only NO-GOs (#539)

A review is a P2-only NO-GO when its verdict is NO-GO and every finding the judge accepted is a P2 (or P3): no P0 and
no P1. Each one costs a fix session (about 56 k tokens) and another review (about 63 k). From #539, the judge accepts a
P2 only when it is inside the diff, its proof uses what the project really runs, and it would cause a wrong result
that users or the next card meet. It declines a P2 whose proof needs an unusual input, timing or setup as `rare case`,
and one about wording, naming or form with no wrong result as `style`. Declined findings stay on the Board's Declined
list.

## How it is measured

From the loop's card records (`conveyor/state/cards.jsonl`): each review line that ran a review session (no `reused`
field), by the UTC day of its time. `counts` holds the findings left after the judge.

```sh
jq -rR 'fromjson? | objects | select(.step == "review" and (.reused | not))
  | [.time[0:10], .result, (.result == "NO-GO" and .counts.P0 == 0 and .counts.P1 == 0 and .counts.P2 > 0)] | @tsv' conveyor/state/cards.jsonl \
  | awk '{ n[$1]++ } $2 == "NO-GO" { no[$1]++ } $3 == "true" { p2[$1]++ }
      END { for (d in n) printf "%s reviews=%d no-go=%d p2only=%d share=%.0f%%\n", d, n[d], no[d], p2[d], 100 * p2[d] / no[d] }' | sort
```

## Before

Measured 2026-11-14, on the records up to main 74744a4, the change not yet in force.

| Day | Reviews | NO-GO | P2-only NO-GO | Share of the NO-GOs |
| --- | --- | --- | --- | --- |
| The owner's count in #539 | 269 | 101 | 39 | 39% |
| 2026-11-12 | 296 | 188 | 93 | 49% |
| 2026-11-13 | 231 | 133 | 81 | 61% |
| 2026-11-14 | 256 | 92 | 39 | 42% |

## After

Not measured yet: the change must first run on cards. Measure it with the command above, for the days after this
change landed, once some 100 reviews have run on it, and add the rows here.
