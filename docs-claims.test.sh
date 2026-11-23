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
# - the /units guide's short IDs: hooks/sources.test.tsx ('a card with no issue has a short ID in every table' draws `red <commit>`
#   and `card <N>`, the one for a card id ending in -0 draws `card`, and the Issue 1582 case draws `fu #N`, `split #N`, `red <commit>`
#   and `test <file>`), but a test of the mod has no file access
#   in its types, so it cannot read the guide, and the guide's text is read here.
# - a page or release note line that states a condition of behaviour that other cases run (issue 1447): a release note
#   is the fixed text of a past version, so only its text can be read; each line below names the code or case that runs it.
# Bugs it catches: a page or release note that says more than the code does (issue 1447, each line below); a /units guide that names only the issue as a row's ID; a tab row the guide does not tell to swipe; a comment that again says a card waits only for its own
# issue's approval line, a last NO-GO that lands or blocks with no P1 round, or a seat's model only from the pack's list.
set -uo pipefail
SRC=$(cd "$(dirname "$0")" && pwd -P)
fails=0
say() { echo "FAIL [docs-claims]: $*" >&2; fails=$((fails + 1)); }
# <file> : its text with the lines joined and the spaces folded.
flat() { tr '\n' ' ' < "$SRC/$1" | tr -s ' '; }
# has <file> <text> <what is wrong without it>
has() { flat "$1" | grep -qF -- "$2" || say "$1 does not have \"$2\": $3"; }
# line <file> <text> <what is wrong without it>: a line of the file is the text whole, and the Markdown block ends
# there (the next line is blank, a new "- " item or a heading, or there is none), so words added before or after it,
# on its line or on a line that continues the bullet, fail.
line() {
  want=$2 awk 'hit { ok = /^[[:space:]]*$/ || /^- / || /^#/; exit } $0 == ENVIRON["want"] { hit = 1; ok = 1 }
    END { exit !(hit && ok) }' "$SRC/$1" ||
    say "$1 has no line that is exactly \"$2\" and ends its bullet: $3"
}

# O347: the tab row scrolls sideways with no bar, so on a narrow screen the tabs past the edge are reached by a swipe.
has .claude/dashboard/app.css '.tabs-list { overflow-x: auto; scrollbar-width: none; }' 'the tab row no longer scrolls sideways, or shows a bar'
has docs/board.md 'swipe it sideways to reach the other tabs' 'the guide left out the sideways swipe'
# O369, #1582: a card with no issue has `fu #N`, `split #N`, `red <commit>`, `test <file>`, `card <N>` or `card` for its ID, and its work in Title.
has docs/units.md 'A card with no issue shows its kind and its parent' 'the guide names only the issue as the matrix ID'
has docs/units.md '`fu #1571` for a review follow-up' 'the guide leaves out the review follow-up ID'
has docs/units.md '`split #1453` for a split part' 'the guide leaves out the split part ID'
has docs/units.md '`red <commit>` (the' 'the guide leaves out the main-red fix card ID'
has docs/units.md '`test <file>` for a card of the Tests page' 'the guide leaves out the Tests page card ID'
has docs/units.md '`card <N>`, with the number its card id ends in, or `card` when it ends in no number or in `-0`' 'the guide leaves out the plain ID, or the card id that ends in -0'
has docs/units.md 'a review follow-up shows its finding there' 'the guide leaves out what the Title shows'
# O337: the comment on the Approve visible changes row.
has .claude/dashboard/parts/rules-rows.js 'or a parent issue it inherits the yes from (follow-ups and split slices)' 'the comment names only the issue'"'"'s own line'
# O352: the loop comment of a last NO-GO.
has conveyor/lib/card.sh 'or gets one fix round and a review on a P1' 'the loop comment leaves out the P1 round'
# O357: the comment of cardok().
has conveyor/lib/control.sh 'the review'"'"'s list has the Codex models that Codex reports too, when the pack sets no models.allowed or its codex' 'the comment names only the pack'"'"'s list, or Codex'"'"'s models as an addition for every seat or with no condition'
# Issue 1447 (R-ids are the audit's). Each line is a claim that was wider than the code; the behaviour is run in the case named.
# R400: a release pushes the default branch (commands/release-prep.sh `git push --atomic`), so Land as pr cannot say never.
has docs/configuration.md 'Conveyor never pushes the default branch, except that a release pushes its commits and tag.' 'Land as pr says no push of the default branch happens, though a release does it'
# R401: with no test.fileCommand or test.list form that gives one file, pushtests() runs nothing and idle merges. The merge
# runs in tests/landas.test.sh t_pridlenofile; the words are read here and in t_pridledocs.
has docs/configuration.md 'This run needs a pack that can run one test file at a time' 'Idle promises tests before a merge to a pack that cannot run one file'
has docs/configuration.md 'or the pack cannot run one test file, Conveyor merges with no test run first' 'Idle leaves out the merge with no test run for such a pack'
has docs/board.md 'must pass first, when the pack can run one test file at a time' 'the Board guide promises the idle test run to a pack that cannot run one file'
# R397: the Feed stopped mark follows the heartbeat alone (app-feed.js), so new data can still arrive.
has docs/board.md "**Feed stopped**: the feed's heartbeat stopped." 'the guide says Feed stopped means no data arrives'
# R208: a "filed as" line outside the plugin's own repository is a second row (foreman/stop.sh, plugin_home).
has docs/foreman.md 'In another project, it is a second line.' 'the guide says one line each, though a filed line outside the plugin repository is a second one'
# R408 (lib/claim.sh): the batch is on any files, off at landBatch 1, and runs a shared test file again once for each change.
has docs/releases/1.11.0.md "The cards can change different files. A batch holds up to the pack's \`landBatch\` cards, and \`landBatch\` 1 turns batches off." 'the 1.11.0 batch line leaves out the files and the off value'
has docs/releases/1.11.0.md 'the batch runs that file again on main before it lands, once for each change of that card.' 'the 1.11.0 batch line promises a second run whenever a landing shares a file'
# R409 (lib/mainred.sh mainprobe() and mainkeep(): a run is kept only when its controls pass, a file that timed out is
# not kept, and a card takes a kept file only at the same dependencies and with each control it needs run beside it;
# tests/mainredproof.test.sh t_mainreddepsnew, t_mainredmachinefixed, t_mainredcontrol); a file that main deleted
# does not run (mainprobe() leaves it out before the kept results are read; t_mainwaitgone). The bullet's line must be the
# text whole, from its dash to its end, and the bullet must end there, so a word put in, such as a "no", or a sentence
# added that says the opposite, on the bullet's line or on a line below that continues it, fails.
line docs/releases/1.11.0.md "- At a red commit, cards that wait on the same test file can share one run of it. A card uses an earlier run of a test file at that commit only when the file ended in time in that run, the installed dependencies are the same, and each control test (the pack's \`test.control\`) that the card needs ran and passed in that run. Else the card runs that test file at that commit itself. A test file that main deleted does not run. A waiting card wakes only when main's state changes." 'the 1.11.0 notes share a run of a file that timed out, ran at other dependencies, or did not run and pass each control the card needs, or promise a run of a test file that main deleted'
# R124 (lib/session.sh): no session ID in the output, no resume.
has docs/releases/1.11.0.md 'when its output names one, and else started again from nothing' 'the 1.11.0 notes resume with no session ID'
# R411 (tests/narrow.test.sh t_narrowownwhole).
has docs/releases/1.6.0.md 'A changed helper outside any case runs the whole file.' 'the 1.6.0 notes leave out the whole-file run for a helper'
# R414 (lib/lint.sh lintratchet; tests/lint.test.sh t_lintnoratchet: two findings on unchanged lines fail it).
has docs/releases/1.7.0.md 'A lint command with `ratchet` set to false judges every finding, on any line, so a finding on a line you did not change fails it.' 'the 1.7.0 lint note leaves out that ratchet false fails on every finding'
# R418 (docs/cards.md): a seat CLI that the host never had blocks at once.
has docs/releases/1.7.0.md 'A seat set to a CLI that the host never had still blocks the card at once.' 'the 1.7.0 notes say any missing tool waits'
# R126 (foreman/watch-idle.sh): only a turn that wrote the cache and read none stops the pings.
has docs/releases/1.7.0.md "after a ping that visibly did not keep the model's cache warm" 'the 1.7.0 notes say the pings stop when the cache use cannot be read'
# R416 (commands/release-prep.sh; tests/releaseminver.test.sh t_relminver: a commands/setup.md change runs no check): the check reads the diff of hooks, types and .claude-plugin/plugin.json only.
has docs/releases/1.7.0.md 'when `hooks/`, `types/` or `.claude-plugin/plugin.json` has changed' 'the 1.7.0 notes say any plugin file starts the oldest-version check'
# R421, R424 (lib/card.sh loopstop and privfix; tests/reviewback.test.sh).
has docs/releases/1.8.0.md 'comes back after its fix and that review has no P0 or P1 finding.' 'the 1.8.0 notes end the loop on a repeated P2 or P3 beside a new P0 or P1'
has docs/releases/1.8.0.md "A privacy finding in the card's own change gets one more fix round and one more review." 'the 1.8.0 notes leave out the privacy fix round'
# R422 (bench/swe.sh swe_versionsnow): a file:// source is a folder read each time.
has docs/releases/1.8.0.md 'A source given as a `file://` folder is read from its git folder each time.' 'the 1.8.0 notes give the hourly read to a file:// source'
# R423 (lib/fulltest.sh suitereuse; docs/configuration.md).
has docs/releases/1.8.0.md "a file that its suite commands name, the whole suite runs." 'the 1.8.0 notes leave out the settings and suite file exception'
# R425 (docs/cards.md; lib/lint.sh lintstands): the lint reuse conditions. The 1.9.0 notes give v1.9.0's: main changed
# no trigger (v1.9.0:conveyor/lib/lint.sh:501). The rule for a card that changes a trigger came after 1.11.0, so only
# the guide gives it (lintgate's t_lintgatetriggerfile). Both versions keep the pass only for the same card change
# (the cardpatch check at the top of lintstands, v1.9.0's too): a test fix that changes the card runs lint again.
has docs/releases/1.9.0.md "At the landing gate, a card skips lint when all of these are true:" 'the 1.9.0 notes leave out that lint is skipped only at the landing gate'
has docs/releases/1.9.0.md "- Its change is the same change that passed lint. - Main changed none of its files." 'the 1.9.0 notes leave out that the pass stands only for the same change'
has docs/cards.md "- The card's change is the same change that passed. - Main changed none of the card's files." 'the guide leaves out that the pass stands only for the same change'
has docs/releases/1.9.0.md "- Main changed none of a lint command's triggers. - Main changed none of the files a lint command reads for all changes. - Main did not change the pack's \`lint\` field." 'the 1.9.0 notes leave out the trigger reuse condition'
has docs/cards.md "- Main changed no trigger of a lint command. - Main changed no file that a lint command reads for all changes." 'the guide leaves out the trigger reuse condition'
has docs/cards.md "- When the card changes a command's triggers or the pack's \`lint\` field, main changed none of the files that the command reads." 'the guide leaves out the files a command reads when the card changes its triggers'
# R426 (commands/release-prep.sh relnotes): the first release's draft has no source check.
has docs/releases/1.9.0.md 'For releases after the first, release notes check each line' 'the 1.9.0 notes promise the source check for the first release'
[ "$fails" = 0 ] || exit 1
echo "ok docs-claims"
