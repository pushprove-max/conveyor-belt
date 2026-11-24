#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 120
# The Foreman's filing hook (foreman.sh filing, cause.sh no_cause) refuses a fix issue with no `## Cause` section (#1293).
# Bug caught: the Foreman filed a fix that named a symptom ("the reader is over its size cap") and never the source of
# the problem, because nothing in the filing path asked for the cause.
set -uo pipefail
SRC=$(cd "$(dirname "$0")" && pwd -P)
B=$(mktemp -d) || exit 1
trap 'rm -rf "$B"' EXIT
cd "$B" || exit 1
unset CONVEYOR_FOREMAN CONVEYOR_FOREMAN_DIR CONVEYOR_FOREMAN_ASK CONVEYOR_LANE CONVEYOR_MAIN CONVEYOR_MACHINE_ID CLAUDE_PROJECT_DIR
# case_ <name>: a project alpha and a host file naming it; every record command is noted in calls.
case_() {
  T=$B/$1 M=$B/$1/alpha CASE=$1
  export XDG_CONFIG_HOME=$T/config HOME=$T/home CONVEYOR_FOREMAN_DIR=$T/fd CONVEYOR_MAIN=$M
  export CONVEYOR_FOREMAN_ASK="echo \"\$CONVEYOR_REPO \$CONVEYOR_CMD\" >> $T/calls; case \$CONVEYOR_CMD in control) echo '{\"start\":\"queue\"}' ;; esac"
  mkdir -p "$XDG_CONFIG_HOME/conveyor" "$HOME" "$T/fd" && git init -q "$M" \
    && jq -n --arg m "$M" '{records: [{repo: "alpha", main: $m}]}' > "$XDG_CONFIG_HOME/conveyor/host.json" || fail "the fixture was not made"
}
fail() { echo "FAIL [$CASE]: $*" >&2; exit 1; }
# hook <command>: foreman.sh filing's output for the command as the Foreman's PreToolUse hook sees it.
hook() { (cd "$M" && jq -cn --arg c "$1" '{session_id: "s1", tool_use_id: "x", hook_event_name: "PreToolUse", tool_input: {command: $c}}' | CONVEYOR_FOREMAN=1 bash "$SRC/foreman.sh" filing 2>&1); }
refused() { # <command>: the refusal says what the Cause section holds
  out=$(hook "$1")
  jq -e '.hookSpecificOutput.permissionDecision == "deny" and (.hookSpecificOutput.permissionDecisionReason | test("## Cause") and test("where the bad data or behaviour comes from and why it is there at all") and test("already solves the same problem, or that none was found") and test("stale or missing"))' <<<"$out" >/dev/null \
    || fail "a fix issue with no Cause section was not refused with what the section holds; command: $1; output: $out"
}
passes() { out=$(hook "$1"); [ -z "$out" ] || fail "the command was refused though it needed no Cause section; command: $1; output: $out"; }
body() { printf 'gh issue create --title "Fix it" %s --body "$(cat <<'"'EOF'"'\n%s\nEOF\n)"' "${2:-}" "$1"; }

# D1: `## What happens now` with no `## Cause` is refused (gh and `ask <project> testissue`); the same body with one passes.
t_what() {
case_ what
refused "$(body $'## What happens now\nThe pane shows no board.')"
refused "foreman.sh ask alpha testissue conveyor/x.test.sh 'Slow' '## What happens now
It is slow.'"
refused "gh issue create --title 'Fix it' --body \$'## What happens now\nIt breaks.\n## Causes\nnone'"
passes "$(body $'## What happens now\nThe pane shows no board.\n## Cause\nThe file is never trimmed.')"
passes "foreman.sh ask alpha testissue conveyor/x.test.sh 'Slow' '## What happens now
It is slow.
## Cause
The file grows.'"
printf '## What happens now\nIt breaks.\n' > "$T/body.md"
refused "gh issue create --title 'Fix it' --body-file $T/body.md"
printf '## What happens now\nIt breaks.\n## Cause\nThe cache is stale.\n' > "$T/body.md"
passes "gh issue create --title 'Fix it' --body-file $T/body.md"
# Bug (#1405): a body read from stdin (`--body-file -`) was never read, so a fix with no Cause passed. The `< file`
# redirect names its file, which is read as a named body file is.
printf '## What happens now\nIt breaks.\n' > "$T/fix.md"
refused "gh issue create --title x --body-file - < $T/fix.md"
refused "gh issue create --title x -F - <$T/fix.md"
passes "gh issue create --title x --body-file - < $T/body.md"
# Bug (#1518): the redirect was the first `<` anywhere, so a `<` in the title named the wrong file ('redirection'), and a
# file name with a space was cut at the space ('fix'): both passed without the body being read.
printf '## What happens now\nIt breaks.\n' > "$T/fix notes.md"
refused "gh issue create --title 'Handle < redirection' --body-file - < $T/fix.md"
refused "gh issue create --title \"it's <b>\" --body-file - < $T/fix.md"
refused "gh issue create --title x --body-file - < '$T/fix notes.md'"
refused "gh issue create --title x --body-file - < \"$T/fix notes.md\""
# Bug: a backslash and newline (a line continuation, which bash removes) was kept in the name, so no file was read.
refused "gh issue create --title x --body-file - < $T/\\"$'\n'"'fix notes.md'"
refused "gh issue create --title x --body-file - < \"$T/\\"$'\n'"fix notes.md\""
passes "gh issue create --title 'Handle < redirection' --body-file - < $T/body.md"
# Bug (#1518): a backslash was read as a plain character: an escaped quote in a title ended the quote early, so a `<`
# after it was missed, and `fix\ notes.md` was cut at the space and kept its backslash.
refused "gh issue create --title \"Fix \\\"quote < x\" --body-file - < $T/fix.md"
refused "gh issue create --title x --body-file - < $T/fix\\ notes.md"
passes "gh issue create --title \"Fix \\\"quote < x\" --body-file - < $T/body.md"
# Bug (#1518): a file name of an unquoted part and a quoted part (`dir/'fix notes.md'`) was cut after the unquoted part
# (`dir/`), so the body was not read.
refused "gh issue create --title x --body-file - < $T/'fix notes.md'"
refused "gh issue create --title x --body-file - < $T/\"fix notes.md\""
}

# Bug (#1405): the headings were found anywhere in the text, so '### Cause' counted as a Cause section and a sentence
# that quotes '## What happens now' made a new-work issue a fix issue. A heading is a line of its own with two hashes.
t_heading() {
case_ heading
refused "$(body $'## What happens now\nIt breaks.\n### Cause\nThe file is never trimmed.')"
refused "gh issue create --title 'Fix it' --body \$'## What happens now\nIt breaks.\n### Cause\nnone'"
passes "$(body $'A fix issue has a \'## What happens now\' section, and the form should say so.')"
passes "gh issue create --title 'Form' --body 'Each fix has a \`## What happens now\` section.'"
# Bug (#1405 review): a heading with up to three spaces before it is still a Markdown heading; it was not seen, so a
# fix with an indented Cause was refused and one with an indented What happens now passed with no Cause.
refused "$(body $'  ## What happens now\nIt breaks.')"
passes "$(body $'## What happens now\nIt breaks.\n  ## Cause\nThe file grows.')"
# Bug (#1510): a `## Cause` line inside a fenced code block counted as the heading, so a fix with no Cause section
# passed. A real heading after the block still counts, and a fence of tildes or one closed by the body's quote also ends.
refused "$(body $'## What happens now\nThe form drops the heading.\n\n```md\n ## Cause\n```')"
refused "$(body $'## What happens now\nIt breaks.\n~~~\n## Cause\n~~~')"
refused "gh issue create --title 'Fix it' --body \$'## What happens now\nIt breaks.\n\`\`\`\n## Cause\n\`\`\`'"
passes "$(body $'## What happens now\nIt breaks.\n```md\n## Cause\n```\n## Cause\nThe file grows.')"
passes "$(body $'## What happens now\nIt breaks.\n````\n```\n````\n## Cause\nThe file grows.')"
# A fence that opens on the line of the command (right after the quote that opens the body) hides its heading too.
refused "gh issue create --label bug --body \$'\`\`\`md\n ## Cause\n\`\`\`'"
# In a here-document a quote ends no fence: the text after "```\"" is still inside the block (Markdown: a closing fence has no text after it).
refused "$(body $'## What happens now\nThe form drops the heading.\n```md\n```"\n ## Cause\n```')"
# In a here-document or a body file a written \n is text, not a line break: it makes no fence that hides a real heading.
passes "$(body $'## What happens now\nThe form prints \\n~~~ as text.\n## Cause\nThe cache is stale.')"
printf '## What happens now\nIt prints \\n```\\n as text.\n## Cause\nThe cache is stale.\n' > "$T/fenced.md"
passes "gh issue create --title 'Fix it' --body-file $T/fenced.md"
# A body file is read without its fences too (#1510 review): read with them, a `## Cause` inside its code block would
# count as the heading and a fix with no Cause section would pass.
printf '## What happens now\nThe form drops the heading.\n\n~~~md\n## Cause\n~~~\n' > "$T/hidden.md"
refused "gh issue create --title 'Fix it' --body-file $T/hidden.md"
# Up to three spaces may stand between the quote that opens the body and its fence.
refused "gh issue create --label bug --body \$'  ~~~\n ## Cause\n~~~'"
# A double quote inside a single-quoted body ends no fence: the heading after it is still inside the block.
refused "gh issue create --label bug --body \$'~~~\n~~~\"\n ## Cause\n~~~'"
# Bug (#1510 review): `testissue` has no --body, so either quote ended its fence and this hidden heading counted.
refused "foreman.sh ask alpha testissue conveyor/x.test.sh 'Slow tests' \$'~~~\n~~~\"\n ## Cause\n~~~'"
# Bug: a `--body "` written in a testissue body's text set the body quote, so `~~~"` closed the fence again.
refused "foreman.sh ask alpha testissue conveyor/x.test.sh 'Slow tests' \$'The runner logs --body \"missing\".\n~~~\n~~~\"\n ## Cause\n~~~'"
# Bug: a title with a backslash-escaped space split into two words, so the body quote was never found.
refused "foreman.sh ask alpha testissue conveyor/x.test.sh Slow\\ tests \$'~~~\n~~~\"\n ## Cause\n~~~'"
# Bug: a line continuation (backslash, newline) before the body or its --body broke the word match, so the body quote
# was never found and `~~~"` closed the fence; before `testissue` it hid that the command files an issue at all.
refused "foreman.sh ask alpha testissue conveyor/x.test.sh 'Slow tests' \\
\$'~~~\n~~~\"\n ## Cause\n~~~'"
refused "gh issue create --label bug --body \\
\$'~~~\n~~~\"\n ## Cause\n~~~'"
refused "foreman.sh ask alpha \\
testissue conveyor/x.test.sh 'Slow tests' 'It is slow.'"
# A `<<` inside a quoted title is no here-document: the body's written \n are still line breaks, so its fence is read.
refused "gh issue create --label bug --title 'Fix << handling' --body \$'~~~\n ## Cause\n~~~'"
# Bug: a fence after the quote of a title ('~~~ handling') opened a block that never closed, so the body's real Cause
# and What happens now were hidden and a valid fix was refused. A quoted text that closes on its line holds no block.
passes "gh issue create --label bug --title '~~~ handling' --body \$'## What happens now\nThe form fails.\n## Cause\nThe cache is stale.'"
# Bug: a written \n in that title became a line break before the scan, so its quote closed on the next line and the
# block it opened hid the body's Cause. The block ends at the title's closing quote, not at its line.
passes "gh issue create --label bug --title '~~~ followed by \\n' --body \$'## What happens now\nThe form fails.\n## Cause\nThe cache is stale.'"
# After such a title closes, the rest of its line is read again: a body fence there still hides the Cause inside it.
refused "gh issue create --label bug --title '~~~ x\\n' --body \$'~~~\n## Cause\n~~~'"
# Bug: the rest of an opener after a quote was read as a closing fence, so `~~~ ~~~` (a tilde fence whose info string
# is ~~~) closed its own block and the Cause inside it counted. Only the closing quote ends the block on that line.
refused "gh issue create --label bug --title 'Fix the form' --body \$'~~~ ~~~\n## Cause\nThe cache is stale.\n~~~'"
# A `\\n` in an inline body is a backslash and an n: it makes no fence that hides a real Cause heading.
passes "gh issue create --label bug --body \$'The form prints \\\\n~~~ as text.\n## Cause\nThe cache is stale.'"
# Bug: a `\n` in a plain single quote is a backslash and an n to bash, but it was read as a line break, so `~~~ as
# text.'` opened a fence that hid the real Cause heading of the `$'...'` part after it, and a valid fix was refused.
passes "gh issue create --label bug --body 'The form prints \\n~~~ as text.'\$'\\n## Cause\\nThe cache is stale.'"
# Bug: that mark was turned back into a line break before the headings were read, so a `\n## Cause\n` written in a
# plain or double-quoted body (one line of text to gh) counted as a Cause heading and a fix with no Cause passed.
refused "gh issue create --title 'Fix the form' --label bug --body 'The form prints \\n~~~\\n## Cause\\n~~~ as text.'"
refused "gh issue create --title 'Fix the form' --label bug --body \"The form prints \\n## Cause\\n as text.\""
# A backtick opener with a backtick in its info string is no fence, so the heading after it counts.
passes "$(body $'## What happens now\nThe form prints this line:\n``` `name`\n## Cause\nThe cache is stale.')"
}

# A fence in a list item hides the `## Cause` in its block; a line outside the list is read as no item.
t_list() {
case_ list
# Bug (#1510 review): a fence after a list marker was no fence, so the indented `## Cause` in the item's code block
# counted as the heading and a fix with no Cause section passed. A heading after the item still counts.
refused "$(body $'## What happens now\nThe form prints an example.\n\n- ~~~\n  ## Cause\n  ~~~')"
refused "gh issue create --label bug --body \$'1. \`\`\`\n   ## Cause\n   \`\`\`'"
passes "$(body $'## What happens now\nIt breaks.\n- ~~~\n  x\n## Cause\nThe cache is stale.')"
# Bug (E1): a tab-indented line in the item's block ended it, so the `## Cause` after it counted.
refused "$(body $'## What happens now\nThe form prints an example.\n\n- ~~~\n\tExample output\n  ## Cause\n  ~~~')"
# Bug (#1510 review): a tab after the item indent was kept before the closing fence, so `  \t~~~` (two columns past the
# indent) did not close the block, the real `## Cause` after it was hidden and a valid fix was refused.
passes "$(body $'## What happens now\n- ~~~\n  Example output\n  \t~~~\n  ## Cause\n  The cache is stale.')"
# Bug (E2): an ordered list that starts at 2 cannot interrupt a paragraph, so `2. ~~~` there is text, not a fence,
# and the heading after it counts; one that starts at 1 can, and hides it; so can a later item of a list.
passes "$(body $'## What happens now\nThe form prints this line:\n2. ~~~\n   ## Cause\nThe cache is stale.')"
refused "$(body $'## What happens now\nThe form prints this line:\n1. ~~~\n   ## Cause\n   ~~~')"
refused "$(body $'## What happens now\n1. It breaks.\n2. ~~~\n   ## Cause\n   ~~~')"
# Bug (#1510 follow-up): a fence on the line after a list marker, indented past the item's text, was read with only
# three spaces cut, so it was no fence and the `## Cause` in the item's code block counted.
refused "$(body $'## What happens now\nThe form prints an example.\n\n- Example:\n    ~~~\n  ## Cause\n    ~~~')"
# Bug (E1 of the follow-up): a fence indented less than a nested item ended it but also lost the outer item, so the
# fence, in the outer item, was no fence and the `## Cause` in its block counted.
refused "$(body $'## What happens now\nThe form prints an example.\n\n- Outer:\n  1. Inner:\n    ~~~\n  ## Cause\n    ~~~')"
# Bug (E2 of the follow-up): a thematic break did not end the list, so an indented code line after it was read as a
# fence in the item and hid the real `## Cause` heading.
passes "$(body $'## What happens now\nThe form fails.\n\n- Example\n***\n\n    ~~~\n  ## Cause\nThe cache is stale.')"
# Bug (E2, follow-up): only a paragraph at column 0 ended the list, so after a paragraph indented 1 (left of the item
# text at 2, so outside the list) `2. ~~~` was still a fence and hid the heading. A paragraph at the item text stays in it.
passes "$(body $'## What happens now\n- One example.\n\n A separate paragraph.\n2. ~~~\n   ## Cause\nThe cache is stale.')"
refused "$(body $'## What happens now\n- One example.\n\n  More of the item.\n2. ~~~\n   ## Cause\n   ~~~')"
# Bug (E1): the list kept the text indent of its first item (2), not of its last (3), so a paragraph at 2 after the
# second item stayed in the list and `2. ~~~` hid the heading after it.
passes "$(body $'## What happens now\n- First example.\n-  Second example.\n\n  A separate paragraph.\n2. ~~~\n   ## Cause\nThe cache is stale.')"
# Bug (E2): the spaces that start an indented code block after `1.` counted as item indent (6, not 3), so the
# paragraph at 3 left the list and `2. ~~~` was read as text: the heading inside its fence counted.
refused "$(body $'## What happens now\n1.     Example output\n\n   More of the item.\n2. ~~~\n   ## Cause\n   ~~~')"
}

# The quote that opens a gh body comes from the real `--body`: an `ask ... testissue` or a `--body "` in the title is text.
t_quote() {
case_ quote
# Bug (#1510 review): `ask ... testissue` in a gh title was read as the command, so `--body` was skipped: no body quote
# was set and `~~~"` closed the fence; in the second, the title's `'c'` set it to `'`, so the `"~~~` fence was none.
refused "gh issue create --label bug --title 'Fix ask conveyor-belt testissue' --body \$'~~~\n~~~\"\n ## Cause\n~~~'"
refused "gh issue create --label bug --title \"Fix ask p testissue a b 'c'\" --body \"~~~
 ## Cause
~~~\""
# Bug (review E1): a `--body "` inside the title set the body quote to `"`, so the `$'...'` body's fence was not read.
refused "gh issue create --label bug --title 'Document ask conveyor-belt testissue and the --body \"flag\"' --body \$'~~~\n ## Cause\n~~~'"
# Bug (review E2): in a command that files two issues, the last body's quote (`"`) was used for both, so the first
# body's `$'~~~` fence was none and its ` ## Cause` counted; the same with an `ask ... testissue` body's quote, and
# line continuations before the second issue's words.
refused "gh issue create --label bug --title Fix --body \$'~~~\n ## Cause\n~~~'; gh issue create --title Docs --body \"Summary\""
refused "gh issue create --label bug --title Fix \\
--body \$'~~~\n ## Cause\n~~~'; \\
foreman.sh ask alpha testissue conveyor/x.test.sh Slow \"Summary\""
}

# unfenced <inline> <quote> <text> keeps what is outside the fences and reads on after each block ends.
t_fence() {
CASE=fence
. "$SRC/cause.sh"
local o
o=$(unfenced 0 "" $'a\n~~~\nx\n~~~\nb\nc') || fail "unfenced failed"
[ "$o" = $'a\nb\nc' ] || fail "text after a closing tilde fence was not read on; got: $o"
o=$(unfenced 1 "" $'a\n```\nx\n```\nb') || fail "unfenced failed"
[ "$o" = $'a\nb' ] || fail "text after a closing backtick fence was not read on; got: $o"
o=$(unfenced 1 "'" $'x $\'```md\ny\n```\'\nafter') || fail "unfenced failed"
[ "$o" = $'\'\nafter' ] || fail "an inline body's closing quote did not end the block, or its opener was not found; got: $o"
o=$(unfenced 0 "" $'a\n```\nx\n```"\ny\n```\nz') || fail "unfenced failed"
[ "$o" = $'a\nz' ] || fail "a here-document fence was closed by a quote, or not by the real fence; got: $o"
o=$(unfenced 1 "'" $'x $\'~~~\n~~~"\nz\n~~~\'\nafter') || fail "unfenced failed"
[ "$o" = $'\'\nafter' ] || fail "a double quote ended a block of a single-quoted body; got: $o"
o=$(unfenced 0 "" $'a\n``` `x`\nb') || fail "unfenced failed"
[ "$o" = $'a\n``` `x`\nb' ] || fail "a backtick opener with a backtick in its info string hid text; got: $o"
# A fence in a (nested) list item closes at its fence read after the item's indent, and a blank line stays inside it.
# The line `    z` after the closing fence is still in the item: it is read only if that fence closed the block.
o=$(unfenced 0 "" $'a\n- * ~~~\n    x\n\n    y\n    ~~~\n    z\nb') || fail "unfenced failed"
[ "$o" = $'a\n    z\nb' ] || fail "a fence in a nested list item was not hidden, or not closed after the item's indent; got: $o"
# Bug (E1): a tab counted as no indent, so a tab-indented line in the item ended its block early.
o=$(unfenced 0 "" $'- ~~~\n\tx\n  y\n  ~~~\nb') || fail "unfenced failed"
[ "$o" = $'b' ] || fail "a tab-indented line ended the block of its list item; got: $o"
# A fence four columns past the item indent (`  \t` then two spaces) is code in the block, not its closing fence.
o=$(unfenced 0 "" $'- ~~~\n  \t  ~~~\n  x\n  ~~~\nb') || fail "unfenced failed"
[ "$o" = $'b' ] || fail "a fence four columns past the item indent closed its block; got: $o"
# A line indented less than the item ends the item and its block: the text from it on is read.
o=$(unfenced 0 "" $'- ```\n  x\nb\n- c') || fail "unfenced failed"
[ "$o" = $'b\n- c' ] || fail "a line indented less than the list item did not end its block; got: $o"
# Bug (#1510 follow-up): a fence on a later line of a list item is read after the item's indent, so it hides its block.
o=$(unfenced 0 "" $'- Example:\n    ~~~\n  x\n    ~~~\nb') || fail "unfenced failed"
[ "$o" = $'- Example:\nb' ] || fail "a fence on the line after a list marker was not read after the item's indent; got: $o"
# A paragraph after a blank line, indented less than the item, ends it: a fence 4 columns in after that is no fence.
o=$(unfenced 0 "" $'- a\n\nb\n    ~~~\nx') || fail "unfenced failed"
[ "$o" = $'- a\n\nb\n    ~~~\nx' ] || fail "a list item went on past a paragraph that ended it; got: $o"
}

# D2: a `bug` label makes it a fix issue, whatever its body. `testissue` files with the pack's type label (`bug` here),
# so a testissue with no Cause section is refused though its body has no `## What happens now` either.
t_bug() {
case_ bug
refused "foreman.sh ask alpha testissue conveyor/x.test.sh 'Speed up tests' 'Measured: 12 CPU s.'"
passes "foreman.sh ask alpha testissue conveyor/x.test.sh 'Speed up tests' 'Measured: 12 CPU s.
## Cause
The suite runs twice.'"
refused "$(body $'Something is wrong.' '--label bug')"
refused "$(body $'Something is wrong.' '-l priority,bug')"
refused "$(body $'Something is wrong.' '--label=Bug')"
passes "$(body $'Something is wrong.\n## Cause\nA stale file.' '--label bug')"
passes "$(body $'Something is wrong.' '--label debugging')"
}

# D3: ordered new work with neither passes, and so does a fix issue of a session that is not the Foreman's: the engine
# files its follow-ups, release fixes and main fixes itself, through no Foreman hook, and a hook of another session
# does nothing.
t_new() {
case_ new
passes "$(body $'## Done when\nThe page shows the new row.' '--label enhancement')"
passes "gh issue view 7 --label bug"
# Bug caught (#1347): `ask <project> card` (a Foreman's order, or with --release a release fix card) was checked for a Cause section
# as a fix issue is, so the Foreman could not order a card with no GitHub issue, whatever its Rules switch; the engine itself asks an order that files an issue for its Cause section (cardnew(), testcards.test.sh nioff).
passes "foreman.sh ask alpha card 'Add a row' 'Make it so.'"
passes "foreman.sh ask alpha card --release 1.1.0 'Fix a.test.sh' 'It fails.'"
out=$(cd "$M" && jq -cn --arg c "$(body $'## What happens now\nIt breaks.')" '{session_id: "s2", tool_use_id: "x", tool_input: {command: $c}}' | bash "$SRC/foreman.sh" filing 2>&1)
[ -z "$out" ] || fail "a fix issue filed in a session that is not the Foreman's was checked; command: $(body $'## What happens now\nIt breaks.'); output: $out"
}

# Bug: a card that changed only no_cause did not run this file. The Foreman folder is outside the engine's area map and
# no test is named after foreman.sh, so only its test links chose this file, one of six, and a card's Test step runs
# five (CARDLINKED): the cap left it out. The case stages a change to no_cause in a copy of this checkout and asks the
# engine for the card's list as its Test step does (testsel narrow, then testcap with CARDLINKED; neither runs a
# test): the list comes from the links, the name lookup and the cap together, which the link text alone does not show.
t_linked() {
CASE=linked
local root W=$B/linked R=$B/linked/r f
root=$(cd "$SRC/../.." && pwd -P)
f=$(cd "$root" && grep -l '^no_cause()' conveyor/foreman/*.sh)
[ -n "$f" ] || fail "no file under conveyor/foreman/ defines no_cause()"
mkdir -p "$R" "$W/home" && git -C "$root" ls-files -z | while IFS= read -r -d '' p; do [ ! -e "$root/$p" ] || printf '%s\0' "$p"; done \
  | tar -C "$root" --null -T - -cf - | tar -C "$R" -xf - || fail "the checkout was not copied"
git -C "$R" init -q && git -C "$R" add -A && git -C "$R" -c user.name=t -c user.email=t@example.com commit -qm base \
  || fail "the copy was not committed"
sed 's/^no_cause() {/no_cause() { :;/' "$R/$f" > "$W/f.tmp" && mv "$W/f.tmp" "$R/$f" && git -C "$R" add -A || fail "no_cause was not changed"
# The engine of the copy, on the copy as its main, with no host file, so its state folder is the copy's own.
( unset "${!CONVEYOR_TEST_@}" SHAREDRUN CAPMAX
  export HOME=$W/home XDG_CONFIG_HOME=$W/config CONVEYOR_MAIN=$R CONVEYOR_CARDS=$W/cards
  . "$R/conveyor/conveyor.sh" state-dir > /dev/null && eval "$(grep '^\. "\$HERE/lib/' "$R/conveyor/commands/run.sh")" || exit 1
  s=$(testsel "$R" narrow) || exit 1; mapfile -t a < <(tail -n +2 <<<"$s")
  CAPMAX=$CARDLINKED testcap "${a[@]}"; echo "$CAPLEFT"; printf '%s\n' "${CAPFILES[@]}" ) > "$W/list" 2> "$W/err" \
  || fail "the card's list of tests was not made for a change to no_cause in $f: $(tail -5 "$W/err")"
grep -qxF conveyor/foreman/filing-cause.test.sh <(tail -n +2 "$W/list") \
  || fail "a card that changes only no_cause in $f does not run conveyor/foreman/filing-cause.test.sh; its list: $(tr '\n' ' ' < "$W/list")"
# The copy has no test records, so the cap keeps the given order; a card's records put the files that failed last first
# (testcap), and any of them can push this file out. Only a list the cap leaves whole runs it whatever the records say.
[ "$(head -1 "$W/list")" = 0 ] \
  || fail "the cap leaves files out of the list of a card that changes only no_cause in $f, so its records can drop conveyor/foreman/filing-cause.test.sh; left out: $(head -1 "$W/list"), list: $(tail -n +2 "$W/list" | tr '\n' ' ')"
}

cases=(what heading list fence bug new linked)
cases=(what heading quote fence bug new linked)
SEL=${CONVEYOR_SHELL_TEST_CASE:-${cases[*]}}; SEL=${SEL//,/ }
for c in $SEL; do case " ${cases[*]} " in *" $c "*) ;; *) echo "unknown case $c" >&2; exit 2 ;; esac; done
read -ra cases <<<"$SEL"
for c in "${cases[@]}"; do (t_"$c" && : > "$B/$c.passed") > "$B/$c.out" 2>&1 & done
wait
. "$SRC/tests/casesreport-helper.sh"
casesreport "$B" '' "${cases[@]}" || exit 1
echo "ok [filing-cause]"
