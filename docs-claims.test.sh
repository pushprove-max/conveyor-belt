#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 60
# What the pages and comments say where no behaviour can be run (issue 1436). The pages' claims about behaviour are
# checked where that behaviour runs, in the case that shows it, with the value the run gave (`pagesays_<file>` in each engine case
# file that calls it, `guide` in each Board test file: not in the shared helper files, as the bug check runs only
# the card's test files on main's code). Three things have no run:
# - a stylesheet rule with no layout to show it (the tab row's sideways scroll), so its text is read once and the page's line checked;
# - the comment of a function that a case calls but whose comment no case reads (rules-rows.js, card.sh, control.sh): a
#   comment that still told the old rule beside a changed behaviour is the bug, so each comment is read for the new words.
# - the /units guide's short IDs: hooks/sources.test.tsx ('a card with no issue has a short ID in every table', and the
#   one for a card id ending in -0) draws `red <commit>`, `card <N>` and `card`, but a test of the mod has no file access
#   in its types, so it cannot read the guide, and the guide's text is read here.
# Bugs it catches: a /units guide that names only the issue as a row's ID; a tab row the guide does not tell to swipe; a comment that again says a card waits only for its own
# issue's approval line, a last NO-GO that lands or blocks with no P1 round, or a seat's model only from the pack's list.
set -uo pipefail
SRC=$(cd "$(dirname "$0")" && pwd -P)
fails=0
say() { echo "FAIL [docs-claims]: $*" >&2; fails=$((fails + 1)); }
# <file> : its text with the lines joined and the spaces folded.
flat() { tr '\n' ' ' < "$SRC/$1" | tr -s ' '; }
# has <file> <text> <what is wrong without it>
has() { flat "$1" | grep -qF -- "$2" || say "$1 does not have \"$2\": $3"; }

# O347: the tab row scrolls sideways with no bar, so on a narrow screen the tabs past the edge are reached by a swipe.
has .claude/dashboard/app.css '.tabs-list { overflow-x: auto; scrollbar-width: none; }' 'the tab row no longer scrolls sideways, or shows a bar'
has docs/board.md 'swipe it sideways to reach the other tabs' 'the guide left out the sideways swipe'
# O369: a card with no issue has `red <commit>`, `card <N>` or `card` for its ID, and its whole name in Title.
has docs/units.md 'a card with no issue shows `red <commit>`' 'the guide names only the issue as the matrix ID'
has docs/units.md '`card <N>` for any other, with the number its card id ends in, or `card` when it ends in no number or in `-0`' 'the guide leaves out the plain ID, or the card id that ends in -0'
has docs/units.md 'a card with no issue shows its whole name there' 'the guide leaves out where the whole name is'
# O337: the comment on the Approve visible changes row.
has .claude/dashboard/parts/rules-rows.js 'or a parent issue it inherits the yes from (follow-ups and split slices)' 'the comment names only the issue'"'"'s own line'
# O352: the loop comment of a last NO-GO.
has conveyor/lib/card.sh 'or gets one fix round and a review on a P1' 'the loop comment leaves out the P1 round'
# O357: the comment of cardok().
has conveyor/lib/control.sh 'the review'"'"'s list has the Codex models that Codex reports too, when the pack sets no models.allowed or its codex' 'the comment names only the pack'"'"'s list, or Codex'"'"'s models as an addition for every seat or with no condition'
[ "$fails" = 0 ] || exit 1
echo "ok docs-claims"
